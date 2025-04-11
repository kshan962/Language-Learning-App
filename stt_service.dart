import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:logger/logger.dart';

class STTService {
  final _logger = Logger();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  // Initialize speech recognition
  Future<bool> init() async {
    if (_isInitialized) return true;

    _isInitialized = await _speech.initialize(
      onStatus: (status) {
        _logger.i('STT Status: $status');
      },
      onError: (error) {
        _logger.e('STT Error: $error');
      },
    );

    return _isInitialized;
  }

  // Check if speech recognition is available
  Future<bool> isAvailable() async {
    if (!_isInitialized) {
      await init();
    }
    return _isInitialized;
  }

  // Check if speech recognition is active
  bool isListening() {
    return _speech.isListening;
  }

  // Start listening for Arabic speech
  Future<void> startListening({
    required Function(String text) onResult,
    Function()? onListeningComplete,
  }) async {
    if (!_isInitialized) {
      final available = await init();
      if (!available) {
        throw Exception('Speech recognition not available');
      }
    }

    // Define SpeechListenOptions
    final listenOptions = stt.SpeechListenOptions(
      partialResults: true,
      cancelOnError: true,
      listenMode: stt.ListenMode.confirmation,
    );

    await _speech.listen(
      localeId: 'ar-SA', // Arabic (Saudi Arabia)
      listenFor: Duration(seconds: 30), // Maximum listen duration
      pauseFor: Duration(seconds: 3), // Pause detection
      listenOptions: listenOptions,
      onResult: (SpeechRecognitionResult result) {
        onResult(result.recognizedWords);
      },
      onSoundLevelChange: (level) {
        // Could be used to show a visual indicator of sound level
      },
    );

    _speech.statusListener = (status) {
      if (status == 'done' && onListeningComplete != null) {
        onListeningComplete();
      }
    };
  }

  // Stop listening
  Future<void> stopListening() async {
    await _speech.stop();
  }

  // Cancel listening
  Future<void> cancelListening() async {
    await _speech.cancel();
  }

  // Get list of available locales
  Future<List<String>> getAvailableLocales() async {
    if (!_isInitialized) {
      await init();
    }

    final locales = await _speech.locales();
    return locales
        .where((locale) => locale.localeId.startsWith('ar'))
        .map((locale) => locale.localeId)
        .toList();
  }
}
