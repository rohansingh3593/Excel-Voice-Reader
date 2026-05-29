import 'dart:io';

import 'package:flutter_tts_no_windows/flutter_tts.dart';

class AccentOption {
  const AccentOption({
    required this.label,
    required this.languageCode,
  });

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

class TtsService {
  TtsService() {
    if (!Platform.isWindows) {
      _tts.awaitSpeakCompletion(false);
    }
  }

  static const List<AccentOption> accents = [
    AccentOption(label: 'English India', languageCode: 'en-IN'),
    AccentOption(label: 'English US', languageCode: 'en-US'),
    AccentOption(label: 'English UK', languageCode: 'en-GB'),
    AccentOption(label: 'English Australia', languageCode: 'en-AU'),
  ];

  final FlutterTts _tts = FlutterTts();
  Process? _windowsSpeechProcess;

  Future<void> speak({
    required String text,
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      return;
    }

    if (Platform.isWindows) {
      await _speakWithWindowsSapi(
        text: trimmedText,
        accent: accent,
        speed: speed,
        pitch: pitch,
      );
      return;
    }

    await _tts.stop();
    await _tts.setLanguage(accent.languageCode);
    await _tts.setSpeechRate(speed.rate);
    await _tts.setPitch(pitch);
    await _tts.setVolume(1.0);
    await _tts.speak(trimmedText);
  }

  Future<void> pause() async {
    if (Platform.isWindows) {
      await stop();
      return;
    }

    await _tts.pause();
  }

  Future<void> stop() async {
    if (Platform.isWindows) {
      _windowsSpeechProcess?.kill();
      _windowsSpeechProcess = null;
      return;
    }

    await _tts.stop();
  }

  Future<void> dispose() async {
    await stop();
  }

  Future<void> _speakWithWindowsSapi({
    required String text,
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
  }) async {
    await stop();

    final script = _buildWindowsSpeechScript(
      text: text,
      accent: accent,
      speed: speed,
      pitch: pitch,
    );

    _windowsSpeechProcess = await Process.start(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      mode: ProcessStartMode.detachedWithStdio,
    );
  }

  String _buildWindowsSpeechScript({
    required String text,
    required AccentOption accent,
    required SpeechSpeed speed,
    required double pitch,
  }) {
    final escapedText = _escapePowerShellSingleQuotedString(text);
    final escapedLanguage = _escapePowerShellSingleQuotedString(accent.languageCode);
    final windowsRate = _windowsRateFor(speed);
    final windowsPitch = _windowsPitchFor(pitch);

    return '''
Add-Type -AssemblyName System.Speech;
\$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer;
\$speaker.Volume = 100;
\$speaker.Rate = $windowsRate;
\$voice = \$speaker.GetInstalledVoices() | Where-Object { \$_.VoiceInfo.Culture.Name -eq '$escapedLanguage' } | Select-Object -First 1;
if (\$voice -ne \$null) { \$speaker.SelectVoice(\$voice.VoiceInfo.Name); }
\$speaker.Speak('<pitch absmiddle="$windowsPitch">$escapedText</pitch>');
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

  int _windowsPitchFor(double pitch) {
    return ((pitch - 1.0) * 5).round().clamp(-5, 5);
  }

  String _escapePowerShellSingleQuotedString(String value) {
    return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll("'", "''");
  }
}
