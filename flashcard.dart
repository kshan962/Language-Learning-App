class Flashcard {
  final String id;
  final String arabic;
  final String transliteration;
  final String translation;
  final Example example;
  final String category;
  final String difficulty;
  final String audioUrl;
  final String imageUrl;

  // Spaced repetition algorithm fields
  int interval; // Days between repetitions
  int repetition; // Number of times reviewed
  double efactor; // Ease factor
  DateTime dueDate; // Next review date

  Flashcard({
    required this.id,
    required this.arabic,
    required this.transliteration,
    required this.translation,
    required this.example,
    required this.category,
    required this.difficulty,
    this.audioUrl = '',
    this.imageUrl = '',
    this.interval = 0,
    this.repetition = 0,
    this.efactor = 2.5,
    DateTime? dueDate,
  }) : dueDate = dueDate ?? DateTime.now();

  // Factory constructor to create a Flashcard from JSON
  factory Flashcard.fromJson(Map<String, dynamic> json) {
    return Flashcard(
      id: json['_id'] ?? json['id'] ?? '',
      arabic: json['arabic'] ?? '',
      transliteration: json['transliteration'] ?? '',
      translation: json['translation'] ?? '',
      example: Example.fromJson(json['example'] ?? {}),
      category: json['category'] ?? 'Common Phrases',
      difficulty: json['difficulty'] ?? 'Beginner',
      audioUrl: json['audioUrl'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      interval: json['interval'] ?? 0,
      repetition: json['repetition'] ?? 0,
      efactor: json['efactor']?.toDouble() ?? 2.5,
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'])
          : DateTime.now(),
    );
  }

  // Convert Flashcard to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'arabic': arabic,
      'transliteration': transliteration,
      'translation': translation,
      'example': example.toJson(),
      'category': category,
      'difficulty': difficulty,
      'audioUrl': audioUrl,
      'imageUrl': imageUrl,
      'interval': interval,
      'repetition': repetition,
      'efactor': efactor,
      'dueDate': dueDate.toIso8601String(),
    };
  }

  // Create a copy of this Flashcard with updated fields
  Flashcard copyWith({
    String? id,
    String? arabic,
    String? transliteration,
    String? translation,
    Example? example,
    String? category,
    String? difficulty,
    String? audioUrl,
    String? imageUrl,
    int? interval,
    int? repetition,
    double? efactor,
    DateTime? dueDate,
  }) {
    return Flashcard(
      id: id ?? this.id,
      arabic: arabic ?? this.arabic,
      transliteration: transliteration ?? this.transliteration,
      translation: translation ?? this.translation,
      example: example ?? this.example,
      category: category ?? this.category,
      difficulty: difficulty ?? this.difficulty,
      audioUrl: audioUrl ?? this.audioUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      interval: interval ?? this.interval,
      repetition: repetition ?? this.repetition,
      efactor: efactor ?? this.efactor,
      dueDate: dueDate ?? this.dueDate,
    );
  }
}

class Example {
  final String arabic;
  final String transliteration;
  final String translation;

  Example({
    required this.arabic,
    required this.transliteration,
    required this.translation,
  });

  factory Example.fromJson(Map<String, dynamic> json) {
    return Example(
      arabic: json['arabic'] ?? '',
      transliteration: json['transliteration'] ?? '',
      translation: json['translation'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'arabic': arabic,
      'transliteration': transliteration,
      'translation': translation,
    };
  }
}
