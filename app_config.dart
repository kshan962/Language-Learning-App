import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // API Configuration
  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:5000/api';

  // App Settings
  static const String appName = 'Arabic Learning';
  static const String appVersion = '1.0.0';

  // Learning Configuration
  static const int defaultDailyGoal = 10; // Number of flashcards per day
  static const int maxDailyGoal = 100;
  static const int minDailyGoal = 5;

  // Flashcard Configuration
  static const double defaultEFactor = 2.5; // Initial ease factor
  static const List<String> arabicLevels = [
    'Beginner',
    'Intermediate',
    'Advanced'
  ];
  static const List<String> learningGoals = [
    'Travel',
    'Business',
    'Academic',
    'Cultural',
    'Religious'
  ];

  // Flashcard Categories
  static const List<String> flashcardCategories = [
    'Greeting',
    'Food',
    'Travel',
    'Shopping',
    'Family',
    'Numbers',
    'Time',
    'Weather',
    'Common Phrases',
    'Question Words',
    'Verbs',
    'Adjectives',
    'Other',
  ];

  // Spaced Repetition Configuration
  static const List<String> qualityDescriptions = [
    'Complete blackout, didn\'t remember at all',
    'Incorrect, but recognized the answer',
    'Incorrect, but the answer was easy to recall once seen',
    'Correct, but with significant difficulty',
    'Correct, with some hesitation',
    'Perfect response, no hesitation',
  ];

  // Conversation Practice Configuration
  static const int maxConversationHistory =
      10; // Maximum messages to keep in history
  static const int maxConversationResponseTokens =
      150; // Maximum tokens for AI response

  // File paths
  static const String initialVocabularyPath =
      'assets/data/initial_vocabulary.json';
}
