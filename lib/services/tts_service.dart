import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts_no_windows/flutter_tts.dart';

class AccentOption {
  const AccentOption({required this.label, required this.languageCode});
  final String label;
  final String languageCode;
}

enum SpeechSpeed {
  slow('Slow', 0.75),
  normal('Normal', 1.0),
  fast('Fast', 1.25);

  const SpeechSpeed(this.label, this.rate);
  final String label;
  final double rate;
}

enum VoiceStyle {
  femaleSmooth('Female'),
  male('Male'),
  defaultVoice('Default');

  const VoiceStyle(this.label);
  final String label;
}

class _TtsQueueItem {
  _TtsQueueItem({
    required this.text,
    required this.accent,
    required this.speed,
    required this.pitch,
    required this.voiceStyle,
  }) : completion = Completer<void>();

  final String text;
  AccentOption accent;
  SpeechSpeed speed;
  double pitch;
  VoiceStyle voiceStyle;
  final Completer<void> completion;
}

class _SpeechTextChunk {
  const _SpeechTextChunk({
    required this.text,
    required this.languageCode,
    required this.isHindi,
  });

  final String text;
  final String languageCode;
  final bool isHindi;
}

class TtsService {
  TtsService() {
    _configuration = _configurePlatformTts();
  }

  static const List<AccentOption> accents = [
    AccentOption(label: 'English US', languageCode: 'en-US'),
    AccentOption(label: 'English India', languageCode: 'en-IN'),
    AccentOption(label: 'English UK', languageCode: 'en-GB'),
    AccentOption(label: 'English Australia', languageCode: 'en-AU'),
  ];

  static const int _speechChunkSize = 3500;
  static const String _hindiLanguageCode = 'hi-IN';
  static final RegExp _hindiRegex = RegExp(r'[\u0900-\u097F]');
  static const String _hindiVoiceInstallMessage =
      'No Hindi voice is installed on this device. Please install Speech '
      'Services by Google and download Hindi (India) voice data from '
      'Text-to-speech output settings.';

  final FlutterTts _tts = FlutterTts();
  final List<_TtsQueueItem> _queue = [];
  _TtsQueueItem? _currentItem;
  _TtsQueueItem? _pausedItem;
  bool _isProcessingQueue = false;
  int _speechGeneration = 0;
  late final Future<void> _configuration;
  Process? _windowsProcess;

  // Expose queue length for UI
  final ValueNotifier<int> queueLength = ValueNotifier<int>(0);
  final ValueNotifier<String?> playbackError = ValueNotifier<String?>(null);

  Future<void> speak({
    required String text,
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
    required VoiceStyle voiceStyle,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      debugPrint('TtsService.speak() called with empty text');
      return;
    }

    debugPrint('TtsService.speak() queueing text (length=${trimmed.length})');
    final queueItem = _TtsQueueItem(
      text: trimmed,
      accent: accent,
      speed: speed,
      pitch: pitch,
      voiceStyle: voiceStyle,
    );
    _queue.add(queueItem);
    queueLength.value = _queue.length;
    debugPrint('TtsService.speak() queue length now ${_queue.length}');
    unawaited(_processQueue());
    return queueItem.completion.future;
  }

  bool get isPlaying => _isProcessingQueue;

  void applyPlaybackSettings({
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
    required VoiceStyle voiceStyle,
  }) {
    _applySettingsToItem(
      _currentItem,
      accent: accent,
      speed: speed,
      pitch: pitch,
      voiceStyle: voiceStyle,
    );
    _applySettingsToItem(
      _pausedItem,
      accent: accent,
      speed: speed,
      pitch: pitch,
      voiceStyle: voiceStyle,
    );
    for (final item in _queue) {
      _applySettingsToItem(
        item,
        accent: accent,
        speed: speed,
        pitch: pitch,
        voiceStyle: voiceStyle,
      );
    }
  }

  void _applySettingsToItem(
    _TtsQueueItem? item, {
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
    required VoiceStyle voiceStyle,
  }) {
    if (item == null) {
      return;
    }

    item.accent = accent;
    item.speed = speed;
    item.pitch = pitch;
    item.voiceStyle = voiceStyle;
  }

  /// Pause current speech. On Windows this kills the process and stores
  /// the current item so resume() can re-enqueue it. On other platforms
  /// it calls the platform pause if available.
  Future<void> pause() async {
    if (Platform.isWindows) {
      if (_currentItem != null) {
        _pausedItem = _currentItem;
      }
      try {
        _windowsProcess?.kill();
      } catch (_) {}
      _windowsProcess = null;
      _isProcessingQueue = false;
      return;
    }

    try {
      await _configuration;
      await _tts.pause();
    } catch (_) {}
  }

  /// Resume playback. On Windows this re-enqueues the paused item (best-effort).
  Future<void> resume() async {
    if (Platform.isWindows) {
      if (_pausedItem != null) {
        _queue.insert(0, _pausedItem!);
        _pausedItem = null;
        queueLength.value = _queue.length;
        unawaited(_processQueue());
      }
      return;
    }

    try {
      await _configuration;
      // FlutterTTS does not guarantee a resume API across platforms.
      // If the plugin supports resume, call it here. Otherwise re-speak.
      await _tts.setVolume(1.0);
    } catch (_) {}
  }

  /// Skip current item and move to next.
  Future<void> skip() async {
    _speechGeneration++;
    if (Platform.isWindows) {
      try {
        _windowsProcess?.kill();
      } catch (_) {}
      _windowsProcess = null;
      return;
    }

    try {
      await _configuration;
      await _tts.stop();
    } catch (_) {}
  }

  /// Stop and clear the queue.
  Future<void> stop() async {
    _speechGeneration++;
    for (final item in _queue) {
      if (!item.completion.isCompleted) {
        item.completion.complete();
      }
    }
    _queue.clear();
    queueLength.value = 0;
    _currentItem = null;
    _pausedItem = null;
    if (Platform.isWindows) {
      try {
        _windowsProcess?.kill();
      } catch (_) {}
      _windowsProcess = null;
      _isProcessingQueue = false;
      return;
    }

    try {
      await _configuration;
      await _tts.stop();
    } catch (_) {}
  }

  /// Clear queued items without stopping the current one.
  void clearQueue() {
    for (final item in _queue) {
      if (!item.completion.isCompleted) {
        item.completion.complete();
      }
    }
    _queue.clear();
    queueLength.value = 0;
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) {
      debugPrint('TtsService._processQueue() already processing, skipping');
      return;
    }
    debugPrint(
        'TtsService._processQueue() starting, queue length=${_queue.length}');
    _isProcessingQueue = true;
    while (_queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      queueLength.value = _queue.length;
      _currentItem = item;
      debugPrint(
          'TtsService._processQueue() processing item (text length=${item.text.length})');
      try {
        if (Platform.isWindows) {
          debugPrint('TtsService._processQueue() using Windows SAPI');
          await _speakWithWindowsSapi(
            text: item.text,
            accent: item.accent,
            speed: item.speed,
            pitch: item.pitch,
            voiceStyle: item.voiceStyle,
            generation: _speechGeneration,
          );
        } else {
          await _speakWithPlatformTts(
            item: item,
            generation: _speechGeneration,
          );
        }
      } catch (e, s) {
        debugPrint('TTS queue item failed: $e');
        debugPrintStack(stackTrace: s);
        _reportPlaybackError(
          'Unable to play audio. Check your phone media volume and Text-to-Speech voice data.',
        );
      } finally {
        if (!item.completion.isCompleted) {
          item.completion.complete();
        }
      }
      _currentItem = null;
    }
    _isProcessingQueue = false;
    debugPrint('TtsService._processQueue() completed');
  }

  void clearPlaybackError() {
    playbackError.value = null;
  }

  Future<void> dispose() async {
    await stop();
    queueLength.dispose();
    playbackError.dispose();
  }

  void _reportPlaybackError(String message) {
    playbackError.value = null;
    playbackError.value = message;
  }

  Future<void> _configurePlatformTts() async {
    if (Platform.isWindows) {
      return;
    }

    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (error) {
      debugPrint('TtsService: failed to enable speak completion: $error');
    }

    if (Platform.isAndroid) {
      try {
        // Keep chunks in the native Android TTS queue instead of letting a
        // later chunk flush an earlier one on engines that return early.
        await (_tts as dynamic).setQueueMode(1);
      } catch (error) {
        debugPrint('TtsService: failed to set Android queue mode: $error');
      }
    }
  }

  Future<void> _speakWithPlatformTts({
    required _TtsQueueItem item,
    required int generation,
  }) async {
    await _configuration;
    await _tts.setVolume(1.0);

    final chunks = _speechChunksForText(
      text: item.text,
      englishLanguageCode: item.accent.languageCode,
    );
    debugPrint(
      'TtsService._speakWithPlatformTts() speaking ${chunks.length} chunk(s)',
    );

    for (var index = 0; index < chunks.length; index++) {
      if (generation != _speechGeneration) {
        debugPrint('TtsService._speakWithPlatformTts() cancelled');
        break;
      }

      final chunk = chunks[index];
      final speechRate = item.speed.rate;
      final speechPitch = item.pitch;
      debugPrint(
        'TtsService._speakWithPlatformTts() chunk ${index + 1}/${chunks.length} '
        '(length=${chunk.text.length}, language=${chunk.languageCode})',
      );
      _logSpeechChunk(
        originalText: chunk.text,
        isHindi: chunk.isHindi,
        languageCode: chunk.languageCode,
      );
      // ignore: avoid_print
      print('Speech Rate: $speechRate');
      // ignore: avoid_print
      print('Speech Pitch: $speechPitch');
      final result = chunk.isHindi
          ? await _speakHindi(
              text: chunk.text,
              speechRate: speechRate,
              speechPitch: speechPitch,
            )
          : await _speakNonHindi(
              text: chunk.text,
              languageCode: chunk.languageCode,
              voiceStyle: item.voiceStyle,
              speechRate: speechRate,
              speechPitch: speechPitch,
            );
      if (result == 0 || result == false) {
        throw StateError(
          'The text-to-speech engine rejected the speech request.',
        );
      }
    }
  }

  List<_SpeechTextChunk> _speechChunksForText({
    required String text,
    required String englishLanguageCode,
  }) {
    final units = _languageDetectionUnits(text);
    final chunks = <_SpeechTextChunk>[];

    for (final unit in units) {
      final isHindi = _isHindiText(unit);
      final languageCode = isHindi ? _hindiLanguageCode : englishLanguageCode;
      final splitUnits = _splitTextForSpeech(unit);
      for (final splitUnit in splitUnits) {
        chunks.add(_SpeechTextChunk(
          text: splitUnit,
          languageCode: languageCode,
          isHindi: isHindi,
        ));
      }
    }

    return chunks;
  }

  List<String> _languageDetectionUnits(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }

    final matches = RegExp(r'[^.!?।\n]+[.!?।]*|\n+')
        .allMatches(trimmed)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (matches.isEmpty) {
      return <String>[trimmed];
    }

    final units = <String>[];
    final languages = <bool>[];
    for (final match in matches) {
      final isHindi = _isHindiText(match);
      if (units.isNotEmpty && languages.last == isHindi) {
        units[units.length - 1] = '${units.last}\n$match';
      } else {
        units.add(match);
        languages.add(isHindi);
      }
    }
    return units;
  }

  bool _isHindiText(String text) {
    return _hindiRegex.hasMatch(text);
  }

  List<String> _splitTextForSpeech(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final chunks = <String>[];
    var remaining = trimmed;
    while (remaining.length > _speechChunkSize) {
      final splitIndex = _bestSpeechSplitIndex(remaining, _speechChunkSize);
      final chunk = remaining.substring(0, splitIndex).trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }
      remaining = remaining.substring(splitIndex).trimLeft();
    }

    if (remaining.trim().isNotEmpty) {
      chunks.add(remaining.trim());
    }
    return chunks;
  }

  int _bestSpeechSplitIndex(String text, int maxLength) {
    final preferredBoundaries = [
      '\n\n',
      '. ',
      '! ',
      '? ',
      '\n',
      '; ',
      ', ',
      ' ',
    ];
    final minimumUsefulSplit = (maxLength * 0.55).round();

    for (final boundary in preferredBoundaries) {
      final boundaryIndex = text.lastIndexOf(boundary, maxLength);
      if (boundaryIndex >= minimumUsefulSplit) {
        return boundaryIndex + boundary.length;
      }
    }

    return maxLength;
  }

  void _logSpeechChunk({
    required String originalText,
    required bool isHindi,
    required String languageCode,
  }) {
    final cleanText = originalText.trim();
    // ignore: avoid_print
    print('Original Text: $originalText');
    // ignore: avoid_print
    print('Contains Hindi: $isHindi');
    // ignore: avoid_print
    print('Detected Hindi: $isHindi');
    // ignore: avoid_print
    print('Selected Language: $languageCode');
    // ignore: avoid_print
    print('Selected TTS Language: $languageCode');
    // ignore: avoid_print
    print(
      isHindi ? 'Speaking Hindi Text: $cleanText' : 'Speaking Text: $cleanText',
    );
  }

  Future<void> _configureHindiTtsEngine() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await (_tts as dynamic).setEngine('com.google.android.tts');
      debugPrint('TtsService: requested Google TTS engine for Hindi');
    } catch (error) {
      debugPrint('TtsService: unable to force Google TTS engine: $error');
    }

    try {
      final available = await (_tts as dynamic).isLanguageAvailable(
        _hindiLanguageCode,
      );
      debugPrint('TtsService: hi-IN language available: $available');
      if (available == false || available == 0) {
        _reportPlaybackError(_hindiVoiceInstallMessage);
      }
    } catch (error) {
      debugPrint('TtsService: unable to check hi-IN availability: $error');
    }
  }

  Future<dynamic> _speakHindi({
    required String text,
    required double speechRate,
    required double speechPitch,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return false;
    }

    await _configureHindiTtsEngine();
    await _tts.setLanguage(_hindiLanguageCode);
    final voiceApplied = await _setHindiVoice();
    if (!voiceApplied) {
      await _tts.setLanguage(_hindiLanguageCode);
    }
    await _tts.setSpeechRate(speechRate);
    await _tts.setPitch(speechPitch);
    return _tts.speak(cleanText);
  }

  Future<dynamic> _speakNonHindi({
    required String text,
    required String languageCode,
    required VoiceStyle voiceStyle,
    required double speechRate,
    required double speechPitch,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return false;
    }

    await _setLanguageWithFallback(languageCode);
    await _applyVoiceForStyle(
      languageCode: languageCode,
      voiceStyle: voiceStyle,
    );
    await _tts.setSpeechRate(speechRate);
    await _tts.setPitch(speechPitch);
    return _tts.speak(cleanText);
  }

  Future<bool> _setHindiVoice() async {
    final voices = await _loadVoiceMaps();
    // ignore: avoid_print
    print('Available Voices: $voices');
    final hindiVoices = voices.where(_isHindiVoice).toList(growable: false);
    if (hindiVoices.isEmpty) {
      debugPrint(
        'TtsService: no Hindi voice found; using hi-IN language setting',
      );
      _reportPlaybackError(_hindiVoiceInstallMessage);
      await _tts.setLanguage(_hindiLanguageCode);
      return false;
    }

    final selectedVoice = _preferredHindiVoice(hindiVoices);
    final ttsVoice = _voiceMapForTts(selectedVoice);
    if (ttsVoice == null) {
      debugPrint(
        'TtsService: Hindi voice is missing name/locale: $selectedVoice',
      );
      _reportPlaybackError(_hindiVoiceInstallMessage);
      await _tts.setLanguage(_hindiLanguageCode);
      return false;
    }

    try {
      await _tts.setVoice(ttsVoice);
      debugPrint('TtsService: selected Hindi voice ${ttsVoice['name']}');
      return true;
    } catch (error) {
      debugPrint('TtsService: failed to set Hindi voice $ttsVoice: $error');
      _reportPlaybackError(_hindiVoiceInstallMessage);
      await _tts.setLanguage(_hindiLanguageCode);
      return false;
    }
  }

  Map<String, String>? _voiceMapForTts(Map<String, String> voice) {
    final name = _voiceName(voice);
    final locale = _voiceLocale(voice);
    if (name == null || name.isEmpty || locale == null || locale.isEmpty) {
      return null;
    }

    return <String, String>{
      'name': name,
      'locale': locale,
    };
  }

  bool _isHindiVoice(Map<String, String> voice) {
    final locale = (_voiceLocale(voice) ?? '')
        .replaceAll('_', '-')
        .toLowerCase();
    final name = (_voiceName(voice) ?? '').toLowerCase();
    return locale.contains('hi-in') ||
        locale == 'hi' ||
        locale.startsWith('hi-') ||
        name.contains('hindi') ||
        name.contains('hi-in') ||
        name.contains('swara') ||
        name.contains('madhur') ||
        name.contains('हिन्दी') ||
        name.contains('हिंदी') ||
        (name.contains('google') &&
            (locale == 'hi' || locale.startsWith('hi-')));
  }

  Future<void> _setLanguageWithFallback(String languageCode) async {
    try {
      await _tts.setLanguage(languageCode);
      return;
    } catch (error) {
      debugPrint('TtsService: failed to set language $languageCode: $error');
    }

    if (languageCode == _hindiLanguageCode) {
      debugPrint(
        'TtsService: Hindi language unavailable; not falling back to an English voice',
      );
      _reportPlaybackError(_hindiVoiceInstallMessage);
      return;
    }

    if (languageCode != 'en-US') {
      try {
        debugPrint('TtsService: falling back to en-US');
        await _tts.setLanguage('en-US');
        return;
      } catch (error) {
        debugPrint('TtsService: fallback en-US failed: $error');
      }
    }

    debugPrint('TtsService: using default system voice');
  }

  Future<void> _applyVoiceForStyle({
    required String languageCode,
    required VoiceStyle voiceStyle,
  }) async {
    final selectedVoice = await _selectVoiceForStyle(
      languageCode: languageCode,
      voiceStyle: voiceStyle,
    );
    if (selectedVoice == null) {
      debugPrint(
        'TtsService: no ${voiceStyle.label} voice found for $languageCode; using default voice',
      );
      return;
    }

    try {
      final ttsVoice = _voiceMapForTts(selectedVoice);
      if (ttsVoice == null) {
        debugPrint(
          'TtsService: selected voice is missing name/locale: $selectedVoice',
        );
        return;
      }
      await _tts.setVoice(ttsVoice);
      debugPrint('TtsService: selected voice ${ttsVoice['name']}');
    } catch (error) {
      debugPrint('TtsService: failed to set voice $selectedVoice: $error');
    }
  }

  Future<List<Map<String, String>>> _loadVoiceMaps() async {
    final dynamic voices;
    try {
      voices = await _tts.getVoices;
    } catch (error) {
      debugPrint('TtsService: failed to load voices: $error');
      return const <Map<String, String>>[];
    }

    if (voices is! Iterable) {
      return const <Map<String, String>>[];
    }

    return voices
        .whereType<Map>()
        .map(_stringVoiceMap)
        .toList(growable: false);
  }

  Future<Map<String, String>?> _selectVoiceForStyle({
    required String languageCode,
    required VoiceStyle voiceStyle,
  }) async {
    final voices = await _loadVoiceMaps();
    final languageVoices = voices
        .where((voice) => _voiceMatchesLanguage(voice, languageCode))
        .toList(growable: false);
    if (languageVoices.isEmpty) {
      return null;
    }

    if (languageCode == _hindiLanguageCode) {
      return _preferredHindiVoice(languageVoices);
    }

    return switch (voiceStyle) {
      VoiceStyle.femaleSmooth => _preferredFemaleVoice(languageVoices),
      VoiceStyle.male => _preferredMaleVoice(languageVoices),
      VoiceStyle.defaultVoice => languageVoices.first,
    };
  }

  Map<String, String> _stringVoiceMap(Map voice) {
    return voice.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }

  bool _voiceMatchesLanguage(Map<String, String> voice, String languageCode) {
    final locale = (_voiceLocale(voice) ?? '')
        .replaceAll('_', '-')
        .toLowerCase();
    final language = languageCode.toLowerCase();
    final primaryLanguage = language.split('-').first;
    return locale == language ||
        locale.startsWith('$language-') ||
        locale == primaryLanguage ||
        locale.startsWith('$primaryLanguage-');
  }

  Map<String, String> _preferredHindiVoice(List<Map<String, String>> voices) {
    const preferredTerms = [
      'hi-in',
      'hindi',
      'swara',
      'madhur',
      'google हिन्दी',
      'हिन्दी',
      'हिंदी',
      'google',
    ];
    return _voiceWithPreferredTerms(voices, preferredTerms) ?? voices.first;
  }

  Map<String, String> _preferredFemaleVoice(List<Map<String, String>> voices) {
    const preferredTerms = [
      'female',
      'woman',
      'samantha',
      'zira',
      'google',
      'natural',
    ];
    return _voiceWithPreferredTerms(voices, preferredTerms) ?? voices.first;
  }

  Map<String, String> _preferredMaleVoice(List<Map<String, String>> voices) {
    const preferredTerms = ['male', 'man', 'david', 'mark', 'google', 'natural'];
    final maleVoices = voices.where((voice) {
      final name = (_voiceName(voice) ?? '').toLowerCase();
      return !name.contains('female') && !name.contains('woman');
    }).toList(growable: false);
    if (maleVoices.isEmpty) {
      return voices.first;
    }

    return _voiceWithPreferredTerms(maleVoices, preferredTerms) ??
        maleVoices.first;
  }

  Map<String, String>? _voiceWithPreferredTerms(
    List<Map<String, String>> voices,
    List<String> preferredTerms,
  ) {
    for (final term in preferredTerms) {
      for (final voice in voices) {
        final haystack = [
          _voiceName(voice),
          _voiceLocale(voice),
        ].whereType<String>().join(' ').toLowerCase();
        if (haystack.contains(term.toLowerCase())) {
          return voice;
        }
      }
    }
    return null;
  }

  String? _voiceName(Map<String, String> voice) {
    return voice['name'] ?? voice['voiceName'];
  }

  String? _voiceLocale(Map<String, String> voice) {
    return voice['locale'] ?? voice['language'] ?? voice['languageCode'];
  }

  Future<void> _speakWithWindowsSapi({
    required String text,
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
    required VoiceStyle voiceStyle,
    required int generation,
  }) async {
    final chunks = _speechChunksForText(
      text: text,
      englishLanguageCode: accent.languageCode,
    );
    debugPrint(
      '_speakWithWindowsSapi starting (${chunks.length} chunk(s), accent=${accent.label})',
    );

    for (var index = 0; index < chunks.length; index++) {
      if (generation != _speechGeneration) {
        debugPrint('_speakWithWindowsSapi cancelled');
        return;
      }

      final chunk = chunks[index];
      _logSpeechChunk(
        originalText: chunk.text,
        isHindi: chunk.isHindi,
        languageCode: chunk.languageCode,
      );
      await _speakWindowsChunk(
        text: chunk.text,
        languageCode: chunk.languageCode,
        speed: speed,
        pitch: pitch,
        voiceStyle: voiceStyle,
        generation: generation,
      );
    }
  }

  Future<void> _speakWindowsChunk({
    required String text,
    required String languageCode,
    required SpeechSpeed speed,
    required double pitch,
    required VoiceStyle voiceStyle,
    required int generation,
  }) async {
    final tempDir = Directory.systemTemp;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final textFile = File(
      '${tempDir.path}${Platform.pathSeparator}flutter_tts_text_$timestamp.txt',
    );
    final scriptFile = File(
      '${tempDir.path}${Platform.pathSeparator}flutter_tts_$timestamp.ps1',
    );

    await textFile.writeAsString(text, encoding: utf8);
    debugPrint('_speakWithWindowsSapi wrote text file: ${textFile.path}');
    final script = _buildWindowsSpeechScript(
      textFilePath: textFile.path,
      languageCode: languageCode,
      speed: speed,
      pitch: pitch,
      voiceStyle: voiceStyle,
    );
    await scriptFile.writeAsString(script, encoding: utf8);
    debugPrint('_speakWithWindowsSapi wrote script file: ${scriptFile.path}');

    try {
      Process process;
      try {
        debugPrint('_speakWithWindowsSapi starting powershell.exe');
        process = await Process.start(
          'powershell.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            scriptFile.path,
          ],
          runInShell: false,
        );
      } catch (e) {
        process = await Process.start(
          'pwsh.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            scriptFile.path,
          ],
          runInShell: false,
        );
      }

      if (generation != _speechGeneration) {
        process.kill();
        debugPrint('_speakWithWindowsSapi cancelled before playback');
        return;
      }

      // ignore: avoid_print
      print('Speech Rate: ${speed.rate}');
      // ignore: avoid_print
      print('Speech Pitch: $pitch');
      _windowsProcess = process;
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      final stdoutStr = await stdoutFuture;
      final stderrStr = await stderrFuture;
      if (identical(_windowsProcess, process)) {
        _windowsProcess = null;
      }

      if (exitCode != 0) {
        if (generation != _speechGeneration || exitCode == -1) {
          debugPrint('Windows TTS playback was stopped.');
        } else {
          debugPrint('Windows TTS exited with code $exitCode: $stderrStr');
        }
      } else {
        if (stdoutStr.trim().isNotEmpty) {
          debugPrint('Windows TTS output: $stdoutStr');
        }
        debugPrint('Windows TTS completed successfully');
      }
    } catch (e, stack) {
      debugPrint('Windows TTS Error: $e');
      debugPrintStack(stackTrace: stack);
    } finally {
      await scriptFile.delete().catchError((_) {});
      await textFile.delete().catchError((_) {});
    }
  }

  String _buildWindowsSpeechScript({
    required String textFilePath,
    required String languageCode,
    required SpeechSpeed speed,
    required double pitch,
    required VoiceStyle voiceStyle,
  }) {
    final escapedTextFilePath =
        _escapePowerShellSingleQuotedString(textFilePath);
    final escapedLanguage =
        _escapePowerShellSingleQuotedString(languageCode);
    final windowsRate = _windowsRateFor(speed);
    final windowsPitch = _windowsPitchPercentFor(pitch);
    final preferredGender = _windowsGenderFilterFor(voiceStyle);

    return '''
\$ErrorActionPreference = 'Stop';
\$speaker = \$null;
try {
  Add-Type -AssemblyName System.Speech;
  \$rawText = Get-Content -Raw -Encoding UTF8 -LiteralPath '$escapedTextFilePath';
  \$escapedText = [System.Security.SecurityElement]::Escape(\$rawText);
  \$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer;
  \$speaker.Volume = 100;
  \$speaker.Rate = $windowsRate;
  \$requestedCulture = '$escapedLanguage';
  \$neutralCulture = (\$requestedCulture -split '-')[0];
  \$voices = \$speaker.GetInstalledVoices() | Where-Object { \$_.Enabled -and \$_.VoiceInfo.Culture.Name -eq \$requestedCulture };
  if (-not \$voices) { \$voices = \$speaker.GetInstalledVoices() | Where-Object { \$_.Enabled -and \$_.VoiceInfo.Culture.TwoLetterISOLanguageName -eq \$neutralCulture }; }
  \$voice = \$null;
  if ('$preferredGender' -ne '') { \$voice = \$voices | Where-Object { \$_.VoiceInfo.Gender.ToString() -eq '$preferredGender' } | Select-Object -First 1; }
  if (\$voice -eq \$null) { \$voice = \$voices | Select-Object -First 1; }
  if (\$voice -ne \$null) { \$speaker.SelectVoice(\$voice.VoiceInfo.Name); }
  \$spokenCulture = \$speaker.Voice.Culture.Name;
  \$pitch = $windowsPitch;
  \$pitchValue = if (\$pitch -gt 0) { "+\$pitch%" } elseif (\$pitch -lt 0) { "\$pitch%" } else { 'default' };
  \$ssml = "<speak version='1.0' xml:lang='\$spokenCulture' xmlns='http://www.w3.org/2001/10/synthesis'><prosody pitch='\$pitchValue'>\$escapedText</prosody></speak>";
  try {
    \$speaker.SpeakSsml(\$ssml);
  } catch {
    Write-Output "SSML playback failed; falling back to plain SAPI speech. \$(\$_.Exception.Message)";
    \$speaker.Speak(\$rawText);
  }
} catch {
  Write-Error \$_.Exception.Message;
  exit 1;
} finally {
  if (\$speaker -ne \$null) { \$speaker.Dispose(); }
}
''';
  }

  int _windowsRateFor(SpeechSpeed speed) {
    return switch (speed) {
      SpeechSpeed.slow => -3,
      SpeechSpeed.normal => 0,
      SpeechSpeed.fast => 3,
    };
  }

  int _windowsPitchPercentFor(double pitch) {
    return ((pitch - 1.0) * 50).round().clamp(-25, 50).toInt();
  }

  String _windowsGenderFilterFor(VoiceStyle voiceStyle) {
    return switch (voiceStyle) {
      VoiceStyle.femaleSmooth => 'Female',
      VoiceStyle.male => 'Male',
      VoiceStyle.defaultVoice => '',
    };
  }

  String _escapePowerShellSingleQuotedString(String value) {
    return value.replaceAll("'", "''");
  }
}
