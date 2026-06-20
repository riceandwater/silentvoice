import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService extends ChangeNotifier {
  final FlutterTts _flutterTts = FlutterTts();
  String _lastSpokenText = '';
  
  TtsService() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5); // Slightly slower for clarity
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      debugPrint("Failed to initialize TTS: $e");
    }
  }

  /// Speaks the text aloud if it differs from the last spoken text
  /// (prevents spamming TTS during continuous detection)
  Future<void> speak(String text, {bool force = false}) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    if (!force && cleanText == _lastSpokenText) {
      // Skip duplicate spoken word
      return;
    }

    try {
      _lastSpokenText = cleanText;
      await _flutterTts.stop(); // Stop any current speech
      await _flutterTts.speak(cleanText);
      notifyListeners();
    } catch (e) {
      debugPrint("Error in TTS speak: $e");
    }
  }

  /// Explicitly speak any text (e.g. for complete phrase readouts)
  Future<void> speakPhrase(String phrase) async {
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(phrase);
    } catch (e) {
      debugPrint("Error in TTS speakPhrase: $e");
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
