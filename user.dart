class User {
  final String id;
  final String username;
  final String email;
  final String nativeLanguage;
  final String arabicLevel;
  final String learningGoal;
  final int dailyGoal;
  final int streak;
  final DateTime lastActive;
  final List<String> knownWords;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.nativeLanguage = 'English',
    this.arabicLevel = 'Beginner',
    this.learningGoal = 'Travel',
    this.dailyGoal = 10,
    this.streak = 0,
    DateTime? lastActive,
    this.knownWords = const [],
  }) : lastActive = lastActive ?? DateTime.now();

  factory User.fromJson(Map<String, dynamic> json) {
    // Handle knownWords which might be in various formats
    List<String> parsedKnownWords = [];

    if (json['knownWords'] != null) {
      if (json['knownWords'] is List) {
        // Direct list from API or memory
        parsedKnownWords = List<String>.from(json['knownWords']
            .map((word) => word is String ? word : word.toString()));
      } else if (json['knownWords'] is String) {
        // JSON string from SQLite - already handled in DatabaseService
        try {
          final parsed = json['knownWords'] as List;
          parsedKnownWords = List<String>.from(
              parsed.map((word) => word is String ? word : word.toString()));
        } catch (e) {
          // If parsing fails, use empty list
          parsedKnownWords = [];
        }
      }
    }

    return User(
      id: json['_id'] ?? json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      nativeLanguage: json['nativeLanguage'] ?? 'English',
      arabicLevel: json['arabicLevel'] ?? 'Beginner',
      learningGoal: json['learningGoal'] ?? 'Travel',
      dailyGoal: json['dailyGoal'] ?? 10,
      streak: json['streak'] ?? 0,
      lastActive: json['lastActive'] != null
          ? DateTime.parse(json['lastActive'])
          : DateTime.now(),
      knownWords: parsedKnownWords,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'nativeLanguage': nativeLanguage,
      'arabicLevel': arabicLevel,
      'learningGoal': learningGoal,
      'dailyGoal': dailyGoal,
      'streak': streak,
      'lastActive': lastActive.toIso8601String(),
      'knownWords': knownWords,
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? email,
    String? nativeLanguage,
    String? arabicLevel,
    String? learningGoal,
    int? dailyGoal,
    int? streak,
    DateTime? lastActive,
    List<String>? knownWords,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      nativeLanguage: nativeLanguage ?? this.nativeLanguage,
      arabicLevel: arabicLevel ?? this.arabicLevel,
      learningGoal: learningGoal ?? this.learningGoal,
      dailyGoal: dailyGoal ?? this.dailyGoal,
      streak: streak ?? this.streak,
      lastActive: lastActive ?? this.lastActive,
      knownWords: knownWords ?? this.knownWords,
    );
  }
}
