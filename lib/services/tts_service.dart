import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AccentOption {
  const AccentOption({required this.label, required this.languageCode});
  final String label;
  final String languageCode;
}

enum SpeechSpeed {
  slow('Slow', 0.35),
  normal('Normal', 0.50),
  fast('Fast', 0.70);

  const SpeechSpeed(this.label, this.rate);
  final String label;
  final double rate;
}

class _TtsQueueItem {
  const _TtsQueueItem({
    required this.text,
    required this.accent,
    required this.speed,
    required this.pitch,
  });

  final String text;
  final AccentOption accent;
  final SpeechSpeed speed;
  final double pitch;
}

class TtsService {
  TtsService() {
    // Ensure platform TTS awaits completion so we can sequence items
    if (!Platform.isWindows) {
      try {
        _tts.awaitSpeakCompletion(true);
      } catch (_) {}
    }
  }

  static const List<AccentOption> accents = [
    AccentOption(label: 'English US', languageCode: 'en-US'),
    AccentOption(label: 'English India', languageCode: 'en-IN'),
    AccentOption(label: 'English UK', languageCode: 'en-GB'),
    AccentOption(label: 'English Australia', languageCode: 'en-AU'),
  ];

  final FlutterTts _tts = FlutterTts();
  final List<_TtsQueueItem> _queue = [];
  _TtsQueueItem? _currentItem;
  _TtsQueueItem? _pausedItem;
  bool _isProcessingQueue = false;
  Process? _windowsProcess;

  // Expose queue length for UI
  final ValueNotifier<int> queueLength = ValueNotifier<int>(0);

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
      await _tts.awaitSpeakCompletion(true);
      // FlutterTTS does not guarantee a resume API across platforms.
      // If the plugin supports resume, call it here. Otherwise re-speak.
      await _tts.setVolume(1.0);
    } catch (_) {}
  }

  /// Skip current item and move to next.
  Future<void> skip() async {
    if (Platform.isWindows) {
      try {
        _windowsProcess?.kill();
      } catch (_) {}
      _windowsProcess = null;
      return;
    }

    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Stop and clear the queue.
  Future<void> stop() async {
    _queue.clear();
    queueLength.value = 0;
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
          await _setLanguageWithFallback(item.accent.languageCode);
          await _tts.setSpeechRate(item.speed.rate);
          await _tts.setPitch(item.pitch);
          await _tts.setVolume(1.0);
          debugPrint('TtsService._processQueue() calling _tts.speak()');
          await _tts.speak(item.text);
        }
      } catch (e, s) {
        debugPrint('TTS queue item failed: $e');
        debugPrintStack(stackTrace: s);
      }
      _currentItem = null;
    }
    _isProcessingQueue = false;
    debugPrint('TtsService._processQueue() completed');
  }

  Future<void> dispose() async {
    await stop();
    queueLength.dispose();
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
  }) {
    final escapedTextFilePath =
        _escapePowerShellSingleQuotedString(textFilePath);
    final escapedLanguage =
        _escapePowerShellSingleQuotedString(accent.languageCode);
    final windowsRate = _windowsRateFor(speed);

    return '''
Add-Type -AssemblyName System.Speech;
\$rawText = Get-Content -Raw -LiteralPath '$escapedTextFilePath';
\$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer;
\$speaker.Volume = 100;
\$speaker.Rate = $windowsRate;
\$voice = \$speaker.GetInstalledVoices() | Where-Object { \$_.VoiceInfo.Culture.Name -eq '$escapedLanguage' } | Select-Object -First 1;
if (\$voice -ne \$null) { \$speaker.SelectVoice(\$voice.VoiceInfo.Name); }
\$speaker.Speak(\$rawText);
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

  String _escapePowerShellSingleQuotedString(String value) {
    return value.replaceAll("'", "''");
  }
}
