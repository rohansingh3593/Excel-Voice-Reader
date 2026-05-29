import 'package:flutter_tts/flutter_tts.dart';

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
    _tts.awaitSpeakCompletion(false);
  }

  static const List<AccentOption> accents = [
    AccentOption(label: 'English India', languageCode: 'en-IN'),
    AccentOption(label: 'English US', languageCode: 'en-US'),
    AccentOption(label: 'English UK', languageCode: 'en-GB'),
    AccentOption(label: 'English Australia', languageCode: 'en-AU'),
  ];

  final FlutterTts _tts = FlutterTts();

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

    await _tts.stop();
    await _tts.setLanguage(accent.languageCode);
    await _tts.setSpeechRate(speed.rate);
    await _tts.setPitch(pitch);
    await _tts.setVolume(1.0);
    await _tts.speak(trimmedText);
  }

  Future<void> pause() async {
    await _tts.pause();
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
