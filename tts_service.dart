import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TTSService {
  final _logger = Logger();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;

  // Initialize TTS service
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _logger.d('Initializing Google Cloud TTS service');

      // Initialize audio player
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);

      _isInitialized = true;
      _logger.i('TTS service initialized successfully');
    } catch (e) {
      _logger.e('Error initializing TTS service: $e');
    }
  }

  // Speak Arabic text using Google Cloud TTS
  Future<void> speak(String text) async {
    if (text.isEmpty) {
      _logger.w('Attempted to speak empty text');
      return;
    }

    try {
      await init(); // Ensure initialized

      // Stop any existing audio playback first
      await stop();

      _logger.d('Speaking text with Google Cloud TTS: $text');

      // Get API key from environment variables
      final apiKey = dotenv.env['GOOGLE_TTS_API_KEY'];

      if (apiKey == null || apiKey.isEmpty) {
        _logger.e('Google Cloud API key not found in environment variables');
        return;
      }

      // Prepare the request body
      final requestBody = {
        'input': {'text': text},
        'voice': {
          'languageCode': 'ar-XA', // Arabic (all regions)
          'ssmlGender': 'FEMALE' // You can change to MALE if preferred
        },
        'audioConfig': {
          'audioEncoding': 'MP3',
          'speakingRate': 0.85, // Slightly slower for learning
          'pitch': 0.0 // Default pitch
        }
      };

      // Make the API request
      final response = await http.post(
        Uri.parse(
            'https://texttospeech.googleapis.com/v1/text:synthesize?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        // Extract the audio content from the response
        final responseData = jsonDecode(response.body);
        final audioContent = responseData['audioContent'];

        // Decode the base64 audio content
        final bytes = base64Decode(audioContent);

        // Save to a temporary file with a unique name based on the text
        final dir = await getTemporaryDirectory();
        final fileHash = text.hashCode.toString();
        final file = File('${dir.path}/arabic_speech_$fileHash.mp3');
        await file.writeAsBytes(bytes);

        // Play the audio
        await _audioPlayer.play(DeviceFileSource(file.path));
        _logger.d('Playing Google Cloud TTS audio for: $text');
      } else {
        _logger.e(
            'Google Cloud TTS API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _logger.e('Error speaking text: $e');
    }
  }

  // Stop speaking
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      _logger.e('Error stopping audio: $e');
    }
  }

  // Dispose of TTS resources
  Future<void> dispose() async {
    try {
      await _audioPlayer.dispose();
    } catch (e) {
      _logger.e('Error disposing TTS service: $e');
    }
  }
}
