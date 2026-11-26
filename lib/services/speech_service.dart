import 'package:flutter_tts/flutter_tts.dart';

class SpeechService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    await _tts.setLanguage('nl-NL');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  Future<void> announce(String message) async {
    await initialize();
    await _tts.stop();
    await _tts.speak(message);
  }

  Future<void> stop() => _tts.stop();

  Future<void> dispose() => _tts.stop();
}
