import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:logger/logger.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../models/flashcard.dart';
import '../models/user.dart';
import '../models/conversation.dart';

class DatabaseService {
  static Database? _database;
  // Add database caching for common queries
  static final Map<String, dynamic> _cache = {};
  static const int _cacheExpiryMinutes = 5;
  static final Map<String, DateTime> _cacheTimestamps = {};

  // Add logger instance
  final _logger = Logger();

  // Initialize the database
  Future<void> init() async {
    if (_database != null) return;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'arabic_learning.db');

    // Open database with incremented version number (3) to trigger migration
    _database = await openDatabase(
      path,
      version: 3, // Incremented from 2 to 3 to trigger migration
      onCreate: _createDatabase,
      onUpgrade: _onUpgrade,
    );

    _logger.i('Database initialized at $path');

    // Clear caches on startup
    _clearCache();
  }

  void _clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    _logger.d('Cache cleared');
  }

  // Create database tables
  Future<void> _createDatabase(Database db, int version) async {
    _logger.i('Creating database schema version $version');

    // User table - now includes knownWords column
    await db.execute('''
      CREATE TABLE users(
        id TEXT PRIMARY KEY,
        username TEXT,
        email TEXT,
        nativeLanguage TEXT,
        arabicLevel TEXT,
        learningGoal TEXT,
        dailyGoal INTEGER,
        streak INTEGER,
        lastActive TEXT,
        knownWords TEXT
      )
    ''');

    // Flashcards table
    await db.execute('''
      CREATE TABLE flashcards(
        id TEXT PRIMARY KEY,
        arabic TEXT,
        transliteration TEXT,
        translation TEXT,
        exampleArabic TEXT,
        exampleTransliteration TEXT,
        exampleTranslation TEXT,
        category TEXT,
        difficulty TEXT,
        audioUrl TEXT,
        imageUrl TEXT,
        interval INTEGER,
        repetition INTEGER,
        efactor REAL,
        dueDate TEXT,
        isKnown INTEGER
      )
    ''');

    // Add indexes for performance
    await db
        .execute('CREATE INDEX idx_flashcards_duedate ON flashcards(dueDate)');

    await db
        .execute('CREATE INDEX idx_flashcards_isknown ON flashcards(isKnown)');

    // Conversation history table
    await db.execute('''
      CREATE TABLE conversations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        messageId TEXT,
        text TEXT,
        isUser INTEGER,
        timestamp TEXT
      )
    ''');

    _logger.i('Database schema created successfully');
  }

  // Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _logger.i('Upgrading database from v$oldVersion to v$newVersion');

    if (oldVersion < 2) {
      // Add any new indexes or tables for version 2
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_flashcards_duedate ON flashcards(dueDate)');

        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_flashcards_isknown ON flashcards(isKnown)');

        _logger.i('Added performance indexes to flashcards table');
      } catch (e) {
        _logger.e('Error creating indexes: $e');
        // Continue even if index creation fails
      }
    }

    if (oldVersion < 3) {
      // Migration from version 2 to 3: Add knownWords column to users table
      try {
        // Check if the column already exists to prevent errors
        var tableInfo = await db.rawQuery("PRAGMA table_info(users)");
        bool columnExists =
            tableInfo.any((column) => column['name'] == 'knownWords');

        if (!columnExists) {
          // Add the knownWords column if it doesn't exist
          await db.execute(
              'ALTER TABLE users ADD COLUMN knownWords TEXT DEFAULT "[]"');
          _logger.i('Added knownWords column to users table');

          // Update existing rows with an empty array
          await db.update('users', {'knownWords': '[]'});
          _logger.i('Updated existing users with empty knownWords array');
        } else {
          _logger.d('knownWords column already exists in users table');
        }
      } catch (e) {
        _logger.e('Error during database migration to version 3: $e');
      }
    }
  }

  // User methods
  Future<void> saveUser(User user) async {
    _logger.d('Saving user ${user.id}');

    try {
      final Map<String, dynamic> userData = user.toJson();

      // Convert knownWords list to JSON string for storage
      if (userData.containsKey('knownWords')) {
        // Make sure we have a list that can be encoded
        final knownWordsValue = userData['knownWords'];
        if (knownWordsValue is List) {
          userData['knownWords'] = json.encode(knownWordsValue);
        } else {
          userData['knownWords'] = '[]';
        }
      } else {
        userData['knownWords'] = '[]';
      }

      await _database?.insert(
        'users',
        userData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Clear user cache
      _invalidateCache('user_${user.id}');

      _logger.d('User saved successfully');
    } catch (e) {
      _logger.e('Error saving user: $e');
      throw e; // Re-throw to allow handling upstream
    }
  }

  Future<User?> getUser(String id, {bool bypassCache = false}) async {
    _logger.d('Getting user $id, bypassCache=$bypassCache');

    // Check if user is in cache and bypass flag is not set
    final cacheKey = 'user_$id';
    if (!bypassCache && _isCacheValid(cacheKey)) {
      _logger.d('User $id found in cache');
      return _cache[cacheKey] as User?;
    }

    // If bypass flag is set, invalidate the cache for this user
    if (bypassCache) {
      _invalidateCache(cacheKey);
      _logger.d('Cache bypassed for user $id');
    }

    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        'users',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (maps.isEmpty) {
        _logger.d('User $id not found in database');
        return null;
      }

      final userData = Map<String, dynamic>.from(maps.first);

      // Parse the knownWords string back to a List
      if (userData.containsKey('knownWords') &&
          userData['knownWords'] != null) {
        try {
          final knownWordsStr = userData['knownWords'] as String;
          userData['knownWords'] = json.decode(knownWordsStr);
        } catch (e) {
          _logger.e('Error parsing knownWords: $e');
          userData['knownWords'] = <String>[];
        }
      } else {
        userData['knownWords'] = <String>[];
      }

      final user = User.fromJson(userData);

      // Cache user
      _cache[cacheKey] = user;
      _cacheTimestamps[cacheKey] = DateTime.now();
      _logger.d('User $id loaded and cached');

      return user;
    } catch (e) {
      _logger.e('Error getting user: $e');
      return null;
    }
  }

  // Clears all user-related data from the cache
  Future<void> clearUserCache() async {
    _logger.d('Clearing user cache');

    // Remove user data from cache
    for (final key in _cache.keys.toList()) {
      if (key.startsWith('user_')) {
        _invalidateCache(key);
      }
    }

    // Additionally clear related caches that might contain user-specific data
    _invalidateCache('flashcards_due');
    _invalidateCache('flashcards_known');
    _invalidateCache('conversations');

    _logger.d('User cache cleared');
  }

  // NEW METHOD: Reset learning progress
  Future<void> resetLearningProgress() async {
    _logger.d('Resetting user learning progress in local database');

    try {
      // Update user streak and progress
      final currentUser = await getUser(
          firebase_auth.FirebaseAuth.instance.currentUser?.uid ?? '');

      if (currentUser != null) {
        // Create updated user with reset progress
        final updatedUser = currentUser.copyWith(
          streak: 0,
          knownWords: [], // Clear known words
        );

        // Save the updated user
        await saveUser(updatedUser);

        // Reset all flashcards progress
        await _database?.update(
          'flashcards',
          {
            'interval': 0,
            'repetition': 0,
            'efactor': 2.5,
            'dueDate': DateTime.now().toIso8601String(),
            'isKnown': 0, // Mark all as unknown
          },
        );

        // Clear all related caches
        _invalidateCache('flashcards_due');
        _invalidateCache('flashcards_known');
        _invalidateCache('user_${currentUser.id}');

        _logger.i('Learning progress reset successfully in local database');
      } else {
        _logger.w('Cannot reset progress: User not found in local database');
      }
    } catch (e) {
      _logger.e('Error resetting learning progress in local database: $e');
      throw e;
    }
  }

  // Flashcard methods with pagination support
  Future<void> saveFlashcards(List<Flashcard> flashcards) async {
    _logger.d('Saving ${flashcards.length} flashcards');

    final batch = _database!.batch();

    for (var card in flashcards) {
      batch.insert(
        'flashcards',
        {
          'id': card.id,
          'arabic': card.arabic,
          'transliteration': card.transliteration,
          'translation': card.translation,
          'exampleArabic': card.example.arabic,
          'exampleTransliteration': card.example.transliteration,
          'exampleTranslation': card.example.translation,
          'category': card.category,
          'difficulty': card.difficulty,
          'audioUrl': card.audioUrl,
          'imageUrl': card.imageUrl,
          'interval': card.interval,
          'repetition': card.repetition,
          'efactor': card.efactor,
          'dueDate': card.dueDate.toIso8601String(),
          'isKnown': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    _logger.d('Batch save of ${flashcards.length} flashcards completed');

    // Invalidate flashcard cache
    _invalidateCache('flashcards_due');
    _invalidateCache('flashcards_known');
  }

  Future<List<Flashcard>> getFlashcards({
    String? category,
    String? difficulty,
    bool dueOnly = false,
    int? limit,
    int? offset,
  }) async {
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (category != null) {
      whereClause = 'category = ?';
      whereArgs.add(category);
    }

    if (difficulty != null) {
      whereClause = whereClause.isEmpty
          ? 'difficulty = ?'
          : '$whereClause AND difficulty = ?';
      whereArgs.add(difficulty);
    }

    if (dueOnly) {
      final now = DateTime.now().toIso8601String();
      whereClause = whereClause.isEmpty
          ? 'dueDate <= ?'
          : '$whereClause AND dueDate <= ?';
      whereArgs.add(now);
    }

    _logger.d(
        'Getting flashcards with params: dueOnly=$dueOnly, limit=$limit, offset=$offset');

    // Generate a unique cache key based on query parameters
    final cacheKey =
        'flashcards_${whereClause}_${whereArgs.join("_")}_${limit ?? 0}_${offset ?? 0}';

    // Check if we can use cached results for this specific query
    if (_isCacheValid(cacheKey)) {
      _logger.d('Using cached results for key: $cacheKey');
      return _cache[cacheKey] as List<Flashcard>;
    }

    // Build query with pagination support
    final query = _database!.query(
      'flashcards',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      limit: limit,
      offset: offset,
      orderBy: dueOnly ? 'dueDate ASC' : null,
    );

    // Execute query
    final List<Map<String, dynamic>> maps = await query;
    _logger.d('Retrieved ${maps.length} flashcards from database');

    final flashcards = List.generate(maps.length, (i) {
      return Flashcard(
        id: maps[i]['id'],
        arabic: maps[i]['arabic'],
        transliteration: maps[i]['transliteration'],
        translation: maps[i]['translation'],
        example: Example(
          arabic: maps[i]['exampleArabic'],
          transliteration: maps[i]['exampleTransliteration'],
          translation: maps[i]['exampleTranslation'],
        ),
        category: maps[i]['category'],
        difficulty: maps[i]['difficulty'],
        audioUrl: maps[i]['audioUrl'],
        imageUrl: maps[i]['imageUrl'],
        interval: maps[i]['interval'],
        repetition: maps[i]['repetition'],
        efactor: maps[i]['efactor'],
        dueDate: DateTime.parse(maps[i]['dueDate']),
      );
    });

    // Cache results with the unique key
    _cache[cacheKey] = flashcards;
    _cacheTimestamps[cacheKey] = DateTime.now();
    _logger.d('Cached ${flashcards.length} flashcards with key: $cacheKey');

    // Additionally, store due cards in a separate cache for quick access
    // This maintains backward compatibility with existing code
    if (dueOnly && limit == null && offset == null) {
      _cache['flashcards_due'] = flashcards;
      _cacheTimestamps['flashcards_due'] = DateTime.now();
    }

    return flashcards;
  }

  Future<void> updateFlashcard(Flashcard card) async {
    _logger.d(
        'Updating flashcard ${card.id}, interval=${card.interval}, repetition=${card.repetition}');

    await _database!.update(
      'flashcards',
      {
        'interval': card.interval,
        'repetition': card.repetition,
        'efactor': card.efactor,
        'dueDate': card.dueDate.toIso8601String(),
        'isKnown': card.repetition > 1
            ? 1
            : 0, // Consider known after successful repetition
      },
      where: 'id = ?',
      whereArgs: [card.id],
    );

    // Invalidate relevant caches
    _invalidateCache('flashcards_due');

    // Update known cache if card is now known
    if (card.repetition > 1) {
      _invalidateCache('flashcards_known');
    }
  }

  Future<void> markFlashcardAsKnown(String id) async {
    _logger.d('Marking flashcard $id as known');

    await _database!.update(
      'flashcards',
      {'isKnown': 1},
      where: 'id = ?',
      whereArgs: [id],
    );

    // Invalidate cache
    _invalidateCache('flashcards_known');
  }

  Future<List<Flashcard>> getKnownFlashcards() async {
    _logger.d('Getting known flashcards');

    // Check if cache is valid
    if (_isCacheValid('flashcards_known')) {
      _logger.d('Using cached known flashcards');
      return _cache['flashcards_known'] as List<Flashcard>;
    }

    final List<Map<String, dynamic>> maps = await _database!.query(
      'flashcards',
      where: 'isKnown = ?',
      whereArgs: [1],
    );

    _logger.d('Retrieved ${maps.length} known flashcards from database');

    final knownCards = List.generate(maps.length, (i) {
      return Flashcard(
        id: maps[i]['id'],
        arabic: maps[i]['arabic'],
        transliteration: maps[i]['transliteration'],
        translation: maps[i]['translation'],
        example: Example(
          arabic: maps[i]['exampleArabic'],
          transliteration: maps[i]['exampleTransliteration'],
          translation: maps[i]['exampleTranslation'],
        ),
        category: maps[i]['category'],
        difficulty: maps[i]['difficulty'],
        audioUrl: maps[i]['audioUrl'],
        imageUrl: maps[i]['imageUrl'],
        interval: maps[i]['interval'],
        repetition: maps[i]['repetition'],
        efactor: maps[i]['efactor'],
        dueDate: DateTime.parse(maps[i]['dueDate']),
      );
    });

    // Cache results
    _cache['flashcards_known'] = knownCards;
    _cacheTimestamps['flashcards_known'] = DateTime.now();

    return knownCards;
  }

  // Conversation methods
  Future<void> saveConversation(List<Message> messages) async {
    _logger.d('Saving ${messages.length} conversation messages');

    final batch = _database!.batch();

    for (var message in messages) {
      batch.insert(
        'conversations',
        {
          'messageId': message.id,
          'text': message.text,
          'isUser': message.isUser ? 1 : 0,
          'timestamp': message.timestamp.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    _logger.d('Conversation messages saved successfully');

    // Invalidate conversation cache
    _invalidateCache('conversations');
  }

  Future<List<Message>> getConversationHistory() async {
    _logger.d('Getting conversation history');

    // Check cache
    if (_isCacheValid('conversations')) {
      _logger.d('Using cached conversation history');
      return _cache['conversations'] as List<Message>;
    }

    final List<Map<String, dynamic>> maps = await _database!.query(
      'conversations',
      orderBy: 'timestamp ASC',
    );

    _logger.d('Retrieved ${maps.length} conversation messages from database');

    final messages = List.generate(maps.length, (i) {
      return Message(
        id: maps[i]['messageId'],
        text: maps[i]['text'],
        isUser: maps[i]['isUser'] == 1,
        timestamp: DateTime.parse(maps[i]['timestamp']),
      );
    });

    // Cache results
    _cache['conversations'] = messages;
    _cacheTimestamps['conversations'] = DateTime.now();

    return messages;
  }

  Future<void> clearConversationHistory() async {
    _logger.d('Clearing conversation history');

    await _database!.delete('conversations');

    // Clear cache
    _invalidateCache('conversations');
    _logger.d('Conversation history cleared');
  }

  // Debug method to check database schema
  Future<void> checkDatabaseSchema() async {
    try {
      _logger.d('Checking database schema...');

      // Check users table structure
      final userTableInfo =
          await _database!.rawQuery("PRAGMA table_info(users)");
      _logger.d(
          'Users table columns: ${userTableInfo.map((c) => "${c['name']}:${c['type']}").join(', ')}');

      // Check flashcards table structure
      final flashcardsTableInfo =
          await _database!.rawQuery("PRAGMA table_info(flashcards)");
      _logger.d(
          'Flashcards table columns: ${flashcardsTableInfo.map((c) => "${c['name']}:${c['type']}").join(', ')}');

      // Check conversations table structure
      final conversationsTableInfo =
          await _database!.rawQuery("PRAGMA table_info(conversations)");
      _logger.d(
          'Conversations table columns: ${conversationsTableInfo.map((c) => "${c['name']}:${c['type']}").join(', ')}');
    } catch (e) {
      _logger.e('Error checking database schema: $e');
    }
  }

  // Cache management
  bool _isCacheValid(String key) {
    if (!_cache.containsKey(key) || !_cacheTimestamps.containsKey(key)) {
      return false;
    }

    final timestamp = _cacheTimestamps[key]!;
    final now = DateTime.now();
    final difference = now.difference(timestamp).inMinutes;

    return difference < _cacheExpiryMinutes;
  }

  void _invalidateCache(String key) {
    if (_cache.containsKey(key)) {
      _logger.d('Invalidating cache for key: $key');
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  // Call this method when app is sent to background to optimize memory usage
  void trimCache() {
    _logger.d('Trimming cache to conserve memory');

    // Keep only the most essential caches
    final keysToKeep = ['flashcards_due', 'flashcards_known'];

    final keysToRemove =
        _cache.keys.where((key) => !keysToKeep.contains(key)).toList();

    for (var key in keysToRemove) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }

    _logger.d(
        'Removed ${keysToRemove.length} cache entries, keeping ${keysToKeep.length}');
  }

  // Reset the database (for development/testing only)
  Future<void> resetDatabase() async {
    _logger.w('RESETTING DATABASE - ALL DATA WILL BE LOST');

    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'arabic_learning.db');

    await deleteDatabase(path);
    _logger.w('Database deleted at $path');

    // Reinitialize the database
    await init();
    _logger.i('Database reinitialized');
  }
}
