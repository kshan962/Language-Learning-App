import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logger/logger.dart';
import 'firebase_options.dart';

import 'screens/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/flashcard_screen.dart';
import 'screens/conversation_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/accounts_screen.dart';

import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/database_service.dart';
import 'services/tts_service.dart';
import 'services/stt_service.dart';
import 'services/account_token_service.dart';

import 'config/theme.dart';
import 'config/theme_provider.dart';

// Create a global logger instance
final Logger _logger = Logger();

// Use a Completer to track initialization
final Completer<bool> _initCompleter = Completer<bool>();

void main() {
  // Wrap the app initialization in a zone to catch all errors
  runZonedGuarded(() async {
    // Set error handlers before anything else
    FlutterError.onError = (FlutterErrorDetails details) {
      _logger.e('Flutter error: ${details.exception}',
          error: details.exception, stackTrace: details.stack);
    };

    // Initialize Flutter binding
    WidgetsFlutterBinding.ensureInitialized();
    _logger.i("Flutter initialized");

    // Start app immediately while initialization continues in background
    runApp(LoadingApp());

    // Perform async initialization in parallel
    await _initializeApp();

    // Once initialization is complete, update app
    _initCompleter.complete(true);
    _logger.i("App ready");
  }, (error, stackTrace) {
    // Catch any errors not caught by Flutter
    _logger.e('Uncaught error in app', error: error, stackTrace: stackTrace);
  });
}

// Function to initialize services in parallel
Future<void> _initializeApp() async {
  _logger.i("Starting app initialization");

  // Create database service first
  final databaseService = DatabaseService();

  try {
    // Load environment variables
    final envFuture = _loadEnvVars();

    // Initialize Firebase
    final firebaseFuture = Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).then((_) {
      _logger.i("Firebase initialized successfully");
    }).catchError((e) {
      _logger.e("Firebase initialization error", error: e);
      // Continue anyway, as we can fall back to local storage
    });

    // Initialize database
    final dbFuture = databaseService.init().then((_) {
      _logger.i("Database initialized successfully");
    }).catchError((e) {
      _logger.e("Database initialization error", error: e);
      // Continue anyway, some features will still work
    });

    // We'll defer asset preloading since we don't have a BuildContext yet

    // Wait for all critical initialization to complete
    await Future.wait([
      envFuture,
      firebaseFuture,
      dbFuture,
    ]);

    _logger.i("App initialization completed");
  } catch (e) {
    _logger.e("Error during app initialization", error: e);
    // App will continue with limited functionality
  }
}

// Load environment variables with fallback
// Inside the _loadEnvVars() function in main.dart
Future<void> _loadEnvVars() async {
  try {
    // Try multiple possible .env file locations
    bool loaded = false;

    // Check for files in this specific order
    final envFiles = [
      "flutter.env", // Try Flutter-specific env file first
      ".env", // Try project root .env
      "backend/.env", // Try backend folder
      "assets/flutter.env", // Try assets folder
      "assets/.env" // Try assets folder alternative
    ];

    for (final fileName in envFiles) {
      try {
        await dotenv.load(fileName: fileName);
        _logger.i("Loaded environment from: $fileName");

        // Add this debug log to check for the TTS API key
        final ttsKey = dotenv.env['GOOGLE_TTS_API_KEY'];
        _logger.d(
            "TTS API Key found: ${ttsKey != null ? 'Yes (length: ${ttsKey.length})' : 'No'}");

        // Log loaded variables for debugging (exclude sensitive ones)
        final variables = dotenv.env.keys.where((key) =>
            !key.contains('SECRET') &&
            !key.contains('KEY') &&
            !key.contains('PASSWORD'));
        _logger.d("Loaded variables: ${variables.join(", ")}");

        loaded = true;
        break; // Stop after first successful load
      } catch (e) {
        _logger.d("Could not load $fileName: ${e.toString().split('\n')[0]}");
      }
    }

    if (!loaded) {
      _logger.w("No environment files could be loaded. Using default values.");
    }
  } catch (e) {
    _logger.w("Error during environment loading process", error: e);
    // Continue without env vars, will use defaults
  }
}

// Initial loading screen shown while initializing
class LoadingApp extends StatelessWidget {
  const LoadingApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arabic Learning App',
      theme: AppTheme.lightTheme,
      home: FutureBuilder<bool>(
        future: _initCompleter.future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // when initialization is complete, rebuild with MyApp
            _logger.d("Loading complete, transitioning to main app");
            // Create a database service here since we can't access the provider yet
            return MyApp(databaseService: DatabaseService());
          } else {
            // Show loading screen
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.language,
                      size: 80,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Arabic Learning',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ],
                ),
              ),
            );
          }
        },
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  final DatabaseService databaseService;

  const MyApp({super.key, required this.databaseService});

  // In MyApp class in main.dart
  @override
  Widget build(BuildContext context) {
    _logger.d("Building MyApp");

    // Now we have a context, preload assets
    _preloadAssets(context);

    // In the MultiProvider section of your MyApp class
    return MultiProvider(
      providers: [
        // Theme provider
        ChangeNotifierProvider(create: (_) => ThemeProvider()),

        // Services - Reordered providers to fix dependency issue
        Provider<DatabaseService>.value(value: databaseService),

        // Initialize AuthService first
        Provider<AuthService>(create: (_) {
          _logger.d("Creating AuthService");
          return AuthService();
        }),

        // Initialize AccountTokenService
        Provider<AccountTokenService>(create: (_) {
          _logger.d("Creating AccountTokenService");
          return AccountTokenService();
        }),

        // Then create ApiService that depends on AuthService
        Provider<ApiService>(
          create: (context) {
            _logger.d("Creating ApiService");
            final authService = context.read<AuthService>();
            return ApiService(authService: authService);
          },
        ),

        // Create TTS and STT services lazily only when needed
        Provider<TTSService>(
            create: (_) {
              _logger.d("Creating TTSService (lazy)");
              return TTSService();
            },
            lazy: true),
        Provider<STTService>(
            create: (_) {
              _logger.d("Creating STTService (lazy)");
              return STTService();
            },
            lazy: true),

        // Stream providers and other state management
        StreamProvider<firebase_auth.User?>(
          create: (context) {
            _logger.d("Setting up auth state stream");
            return context.read<AuthService>().authStateChanges();
          },
          initialData: null,
        ),
      ],
      child: Consumer<ThemeProvider>(builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Arabic Learning App',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          debugShowCheckedModeBanner: false,
          // Use routes with builders to enable lazy loading of screens
          routes: {
            '/': (context) => const AuthWrapper(),
            '/login': (context) => const LoginScreen(),
            '/signup': (context) => const SignupScreen(),
            '/home': (context) => const HomeScreen(),
            '/flashcards': (context) => const FlashcardScreen(),
            '/conversation': (context) => const ConversationScreen(),
            '/profile': (context) => const ProfileScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/accounts': (context) => const AccountsScreen(),
          },
        );
      }),
    );
  }

  // Preload assets with a valid BuildContext
  void _preloadAssets(BuildContext context) {
    _logger.d("Preloading assets");
    try {
      // Now we have a valid context we can use
      precacheImage(const AssetImage('assets/images/google_logo.png'), context);
      // Add other common images here
      _logger.i("Assets preloading started");
    } catch (e) {
      _logger.w("Error preloading assets: $e");
      // Continue anyway
    }
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isRefreshing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = Provider.of<firebase_auth.User?>(context);

    if (user != null && !_isRefreshing) {
      _refreshUserData(user.uid);
    }
  }

  Future<void> _refreshUserData(String userId) async {
    setState(() {
      _isRefreshing = true;
    });

    try {
      // First, ensure we have a valid token by forcing a refresh
      final authService = Provider.of<AuthService>(context, listen: false);

      // Force token refresh by calling getToken() which will refresh if needed
      final token = await authService.getToken();

      if (token == null) {
        _logger.w("Could not get a valid token, skipping user data refresh");
        return;
      }

      _logger.d("Got valid token, proceeding with user data refresh");

      // Clear cached user data first
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);
      await databaseService.clearUserCache();

      try {
        // Fetch fresh data from API
        final apiService = Provider.of<ApiService>(context, listen: false);
        final userData = await apiService.getUserProfile();

        // Save updated user data to local database
        await databaseService.saveUser(userData);

        _logger.i("User data refreshed for user: ${userData.username}");
      } catch (apiError) {
        _logger.e("Error fetching user data from API: $apiError");

        // Try to load from local database as fallback
        try {
          final localUser =
              await databaseService.getUser(userId, bypassCache: true);
          if (localUser != null) {
            _logger
                .i("Using local user data as fallback: ${localUser.username}");
          } else {
            _logger.w("No local user data available");
          }
        } catch (dbError) {
          _logger.e("Error loading local user data: $dbError");
        }
      }
    } catch (e) {
      _logger.e("Error during user data refresh process: $e");
      // Continue anyway, as the app will try to use whatever data is available
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<firebase_auth.User?>(context);

    if (user == null) {
      _logger.i("User not authenticated, showing LoginScreen");
      return const LoginScreen();
    }

    // If we're refreshing user data, show a loading indicator
    if (_isRefreshing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading your profile...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    // Only show HomeScreen after user data is refreshed
    _logger.i("User authenticated and data refreshed, showing HomeScreen");
    return const HomeScreen();
  }
}
