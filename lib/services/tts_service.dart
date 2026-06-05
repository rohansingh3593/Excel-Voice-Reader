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

class _TtsQueueItem {
  _TtsQueueItem({
    required this.text,
    required this.accent,
    required this.speed,
    required this.pitch,
  });

  final String text;
  AccentOption accent;
  SpeechSpeed speed;
  double pitch;
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
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      debugPrint('TtsService.speak() called with empty text');
      return;
    }

    debugPrint('TtsService.speak() queueing text (length=${trimmed.length})');
    _queue.add(_TtsQueueItem(
      text: trimmed,
      accent: accent,
      speed: speed,
      pitch: pitch,
    ));
    queueLength.value = _queue.length;
    debugPrint('TtsService.speak() queue length now ${_queue.length}');
    unawaited(_processQueue());
  }

  bool get isPlaying => _isProcessingQueue;

  void applyPlaybackSettings({
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
  }) {
    _applySettingsToItem(
      _currentItem,
      accent: accent,
      speed: speed,
      pitch: pitch,
    );
    _applySettingsToItem(
      _pausedItem,
      accent: accent,
      speed: speed,
      pitch: pitch,
    );
    for (final item in _queue) {
      _applySettingsToItem(
        item,
        accent: accent,
        speed: speed,
        pitch: pitch,
      );
    }
  }

  void _applySettingsToItem(
    _TtsQueueItem? item, {
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
  }) {
    if (item == null) {
      return;
    }

    item.accent = accent;
    item.speed = speed;
    item.pitch = pitch;
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
    await _setLanguageWithFallback(item.accent.languageCode);
    await _tts.setVolume(1.0);

    final chunks = _splitTextForSpeech(item.text);
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
        '(length=${chunk.length})',
      );
      // ignore: avoid_print
      print('Speech Rate: $speechRate');
      // ignore: avoid_print
      print('Speech Pitch: $speechPitch');
      await _tts.setSpeechRate(speechRate);
      await _tts.setPitch(speechPitch);
      final result = await _tts.speak(chunk);
      if (result == 0 || result == false) {
        throw StateError(
          'The text-to-speech engine rejected the speech request.',
        );
      }
    }
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

  Future<void> _setLanguageWithFallback(String languageCode) async {
    try {
      await _tts.setLanguage(languageCode);
      return;
    } catch (error) {
      debugPrint('TtsService: failed to set language $languageCode: $error');
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

  Future<void> _speakWithWindowsSapi({
    required String text,
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
  }) async {
    debugPrint(
        '_speakWithWindowsSapi starting (text length=${text.length}, accent=${accent.label})');
    // write text to temp file and call PowerShell to Speak it
    final tempDir = Directory.systemTemp;
    final textFile = File(
        '${tempDir.path}${Platform.pathSeparator}flutter_tts_text_${DateTime.now().millisecondsSinceEpoch}.txt');
    final scriptFile = File(
        '${tempDir.path}${Platform.pathSeparator}flutter_tts_${DateTime.now().millisecondsSinceEpoch}.ps1');

    await textFile.writeAsString(text);
    debugPrint('_speakWithWindowsSapi wrote text file: ${textFile.path}');
    final script = _buildWindowsSpeechScript(
      textFilePath: textFile.path,
      accent: accent,
      speed: speed,
      pitch: pitch,
    );
    await scriptFile.writeAsString(script);
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
            scriptFile.path
          ],
          runInShell: false,
        );
      } catch (e) {
        // fallback to pwsh
        process = await Process.start(
          'pwsh.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            scriptFile.path
          ],
          runInShell: false,
        );
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
      _windowsProcess = null;

      if (exitCode != 0) {
        debugPrint('Windows TTS exited with code $exitCode: $stderrStr');
      } else {
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
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
  }) {
    final escapedTextFilePath =
        _escapePowerShellSingleQuotedString(textFilePath);
    final escapedLanguage =
        _escapePowerShellSingleQuotedString(accent.languageCode);
    final windowsRate = _windowsRateFor(speed);
    final windowsPitch = _windowsPitchPercentFor(pitch);

    return '''
Add-Type -AssemblyName System.Speech;
\$rawText = Get-Content -Raw -LiteralPath '$escapedTextFilePath';
\$escapedText = [System.Security.SecurityElement]::Escape(\$rawText);
\$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer;
\$speaker.Volume = 100;
\$speaker.Rate = $windowsRate;
\$voice = \$speaker.GetInstalledVoices() | Where-Object { \$_.VoiceInfo.Culture.Name -eq '$escapedLanguage' } | Select-Object -First 1;
if (\$voice -ne \$null) { \$speaker.SelectVoice(\$voice.VoiceInfo.Name); }
\$ssml = "<speak version='1.0' xml:lang='$escapedLanguage' xmlns='http://www.w3.org/2001/10/synthesis'><prosody pitch='$windowsPitch%'>\$escapedText</prosody></speak>";
\$speaker.SpeakSsml(\$ssml);
\$speaker.Dispose();
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

  String _escapePowerShellSingleQuotedString(String value) {
    return value.replaceAll("'", "''");
  }
}
