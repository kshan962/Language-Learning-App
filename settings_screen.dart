import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '../utils/database_util.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../config/theme_provider.dart'; // Import ThemeProvider
import '../models/user.dart' as app_models;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Settings variables
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  String _selectedLanguageDialect = 'Modern Standard Arabic';
  double _dailyGoal = 15; // Default daily learning goal
  String _learningMode = 'Conversation';

  app_models.User? _user;

  bool _isLoading = false;

  // List of Arabic dialects
  final List<String> _arabicDialects = [
    'Modern Standard Arabic',
    'Egyptian Arabic',
    'Levantine Arabic',
    'Gulf Arabic',
    'Moroccan Arabic',
  ];

  // Add logger
  final _logger = Logger();

  @override
  void initState() {
    super.initState();

    // Get dark mode setting from ThemeProvider
    _darkModeEnabled =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;

    // Load user data
    _loadUserData();

    // Load other settings
    _loadSettings();
  }

// Use the aliased type in your class variable

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _notificationsEnabled = prefs.getBool('notifications') ?? true;
          // Don't set _darkModeEnabled here, we got it from ThemeProvider
          _selectedLanguageDialect =
              prefs.getString('dialect') ?? 'Modern Standard Arabic';
          _dailyGoal = prefs.getDouble('dailyGoal') ?? 15;
          _learningMode = prefs.getString('learningMode') ?? 'Conversation';
        });
      }
    } catch (e) {
      _logger.e('Error loading settings: $e');
    }
  }

// And update the method to use the aliased type
  Future<void> _loadUserData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentFirebaseUser = authService.currentUser;

      if (currentFirebaseUser != null) {
        final databaseService = DatabaseUtil.getDatabaseService(context);
        _user = await databaseService.getUser(currentFirebaseUser.uid);
      }
    } catch (e) {
      _logger.e('Error loading user data: $e');
    }
  }

// In _performReset, also update to use the aliased type
  final app_models.User resetUser = app_models.User(
    id: user.uid,
    username: _user?.username ?? 'User', // Preserve username
    email: _user?.email ?? user.email ?? '',
    streak: 0,
    knownWords: [],
    arabicLevel: 'Beginner',
  );
  Future<void> _saveSettings() async {
    try {
      // Store Firebase and Firestore references before await
      final currentUser = FirebaseAuth.instance.currentUser;
      final userDocRef = currentUser != null
          ? FirebaseFirestore.instance.collection('users').doc(currentUser.uid)
          : null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications', _notificationsEnabled);
      // Don't save dark mode here, it's handled by ThemeProvider
      await prefs.setString('dialect', _selectedLanguageDialect);
      await prefs.setDouble('dailyGoal', _dailyGoal);
      await prefs.setString('learningMode', _learningMode);

      // Update user settings in Firestore
      if (userDocRef != null) {
        // Use set with merge option instead of update to handle case where document doesn't exist
        await userDocRef.set({
          'settings': {
            'notifications': _notificationsEnabled,
            // Don't include darkMode here as it's handled by ThemeProvider
            'dialect': _selectedLanguageDialect,
            'dailyGoal': _dailyGoal,
            'learningMode': _learningMode,
          }
        }, SetOptions(merge: true));
        _logger.i('Settings saved to Firestore');
      }
    } catch (e) {
      _logger.e('Error saving settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: $e')),
        );
      }
    }
  }

  void _resetProgress() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Learning Progress'),
        content: const Text(
            'Are you sure you want to reset all your learning progress? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _performReset(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  Future<void> _performReset(BuildContext dialogContext) async {
    try {
      // Store the current context's scaffold messenger
      final scaffoldMessenger = ScaffoldMessenger.of(context);

      // Get current user reference before await
      final user = FirebaseAuth.instance.currentUser;

      // Close the dialog first
      Navigator.of(dialogContext).pop();

      // Show loading indicator
      setState(() {
        _isLoading = true;
      });

      if (user != null) {
        // 1. Update Firestore (cloud data) with correct field names
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'streak': 0, 'knownWords': [], 'arabicLevel': 'Beginner'},
          SetOptions(merge: true),
        );

        _logger.i('User progress reset in Firestore for user: ${user.uid}');

        // 2. Reset progress on backend API
        try {
          final apiService = Provider.of<ApiService>(context, listen: false);
          await apiService.resetLearningProgress();
          _logger.i('Backend API progress reset');
        } catch (apiError) {
          _logger.e('Error resetting progress on backend API: $apiError');
          // Continue anyway, as we've at least updated Firestore
        }

        // 3. Reset local database progress via DatabaseService
        try {
          final databaseService = DatabaseUtil.getDatabaseService(context);

          // Clear user cache first to ensure fresh data
          await databaseService.clearUserCache();

          // Then perform the reset operation
          await databaseService.resetLearningProgress();

          // Create a minimal user object with reset values to save to database
          final app_models.User resetUser = app_models.User(
            id: user.uid,
            username: _user?.username ?? 'User', // Preserve username
            email: _user?.email ?? user.email ?? '',
            streak: 0,
            knownWords: [],
            arabicLevel: 'Beginner',
          );

          // Save this reset user to the database to ensure local data is consistent
          await databaseService.saveUser(resetUser);

          _logger.i('Local database progress reset and reset user saved');
        } catch (dbError) {
          _logger.e('Error resetting local database progress: $dbError');
          // Continue anyway, as we've at least updated Firestore and API
        }

        // 4. Set force refresh flag
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('force_refresh_home', true);
          _logger.i('Set flag to force refresh home screen');
        } catch (e) {
          _logger.e('Error setting refresh flag: $e');
        }

        // Show success message
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Learning progress reset successfully')),
        );

        // 5. Return to home screen with a complete refresh
        if (mounted) {
          // Pop back to the first route (typically home)
          Navigator.of(context).popUntil((route) => route.isFirst);

          // Then push the home route again with replacement to force recreation
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    } catch (e) {
      _logger.e('Error resetting progress: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting progress: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Show delete account confirmation dialog
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete your account?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'This action will:',
            ),
            SizedBox(height: 8),
            Text('• Permanently delete your account'),
            Text('• Remove all your learning progress'),
            Text('• Delete all your data from our servers'),
            SizedBox(height: 16),
            Text(
              'This action cannot be undone.',
              style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _performAccountDeletion(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
            ),
            child: const Text('Delete My Account'),
          ),
        ],
      ),
    );
  }

  // Perform account deletion
  // Method to handle account deletion with proper loading indicator management
  Future<void> _performAccountDeletion(BuildContext dialogContext) async {
    try {
      // Store the current context's scaffold messenger and navigator
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      // Close the dialog first
      Navigator.of(dialogContext).pop();

      // Show loading indicator dialog
      BuildContext? loadingDialogContext;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          loadingDialogContext = context;
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      );

      // Create auth service
      final authService = AuthService();

      // Delete account
      final success = await authService.deleteAccount();

      // Close loading indicator dialog if it's still showing
      if (loadingDialogContext != null &&
          Navigator.canPop(loadingDialogContext!)) {
        Navigator.of(loadingDialogContext!).pop();
      }

      if (success) {
        _logger.i('Account cleanup completed successfully');

        // Show success message
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Your account has been removed successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to login screen with a slight delay to ensure all dialogs are closed
        Future.delayed(const Duration(milliseconds: 100), () {
          navigator.pushNamedAndRemoveUntil('/login', (route) => false);
        });
      } else {
        _logger.e('Account deletion failed');

        // Show error message that's more informative
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not fully delete your account. You have been signed out, but you may need to contact support to complete the deletion.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );

        // Still navigate to login screen since the user is likely signed out now
        Future.delayed(const Duration(milliseconds: 100), () {
          navigator.pushNamedAndRemoveUntil('/login', (route) => false);
        });
      }
    } catch (e) {
      _logger.e('Error deleting account: $e');

      // Ensure any loading dialog is closed
      if (mounted && ModalRoute.of(context)?.isCurrent != true) {
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during account deletion: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Notifications Setting
          SwitchListTile(
            title: const Text('Enable Notifications'),
            value: _notificationsEnabled,
            onChanged: (bool value) {
              setState(() {
                _notificationsEnabled = value;
              });
              _saveSettings();
            },
          ),

          // Dark Mode Setting
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: _darkModeEnabled,
            onChanged: (bool value) {
              setState(() {
                _darkModeEnabled = value;
              });

              // Update ThemeProvider
              Provider.of<ThemeProvider>(context, listen: false)
                  .setDarkMode(value);

              // Save other settings
              _saveSettings();
            },
          ),

          // Language Dialect Dropdown
          ListTile(
            title: const Text('Arabic Dialect'),
            trailing: DropdownButton<String>(
              value: _selectedLanguageDialect,
              items: _arabicDialects.map((String dialect) {
                return DropdownMenuItem<String>(
                  value: dialect,
                  child: Text(dialect),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedLanguageDialect = newValue;
                  });
                  _saveSettings();
                }
              },
            ),
          ),

          // Daily Learning Goal Slider
          ListTile(
            title: Text('Daily Learning Goal: ${_dailyGoal.round()} words'),
            subtitle: Slider(
              value: _dailyGoal,
              min: 5,
              max: 50,
              divisions: 9,
              label: _dailyGoal.round().toString(),
              onChanged: (double value) {
                setState(() {
                  _dailyGoal = value;
                });
                _saveSettings();
              },
            ),
          ),

          // Learning Mode Dropdown
          ListTile(
            title: const Text('Learning Mode'),
            trailing: DropdownButton<String>(
              value: _learningMode,
              items:
                  ['Conversation', 'Vocabulary', 'Grammar'].map((String mode) {
                return DropdownMenuItem<String>(
                  value: mode,
                  child: Text(mode),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _learningMode = newValue;
                  });
                  _saveSettings();
                }
              },
            ),
          ),

          // Reset Progress Button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: ElevatedButton(
              onPressed: _resetProgress,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reset Learning Progress'),
            ),
          ),

          // Account Management Section
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Management',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                // Manage Accounts Button
                ListTile(
                  title: const Text('Manage Accounts'),
                  subtitle: const Text('View and delete stored accounts'),
                  leading: const Icon(Icons.account_circle),
                  onTap: () {
                    Navigator.of(context).pushNamed('/accounts');
                  },
                ),
                const SizedBox(height: 16),
                // Delete Account Button
                ElevatedButton.icon(
                  onPressed: _showDeleteAccountDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12.0,
                      horizontal: 16.0,
                    ),
                  ),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete My Account'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Warning: This will permanently delete your account and all associated data.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade800,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ),
          ),

          // App Information
          Padding(
            padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App Information',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Version'),
                  subtitle: const Text('1.0.0'),
                  leading: const Icon(Icons.info_outline),
                ),
                ListTile(
                  title: const Text('About'),
                  subtitle: const Text(
                      'Arabic Learning App with Flashcards and Conversation Practice'),
                  leading: const Icon(Icons.help_outline),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'Arabic Learning App',
                      applicationVersion: '1.0.0',
                      applicationIcon: const Icon(
                        Icons.language,
                        size: 48,
                        color: Colors.green,
                      ),
                      children: const [
                        Text(
                          'A comprehensive Arabic learning app featuring flashcards with spaced repetition and AI-powered conversation practice.',
                        ),
                        SizedBox(height: 16),
                        Text(
                          '© 2024 Arabic Learning App',
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
