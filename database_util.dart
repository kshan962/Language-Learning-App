import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import '../services/database_service.dart';

class DatabaseUtil {
  static final _logger = Logger();

  // Helper method to get database service
  static DatabaseService getDatabaseService(BuildContext context) {
    try {
      return Provider.of<DatabaseService>(context, listen: false);
    } catch (e) {
      // If Provider is not available, create a new instance
      return DatabaseService();
    }
  }

  // Show dialog with database information for debugging
  static void showDatabaseDebugInfo(BuildContext context) async {
    final databaseService = getDatabaseService(context);

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking database...'),
            ],
          ),
        );
      },
    );

    // Check database schema
    await databaseService.checkDatabaseSchema();

    // Dismiss loading dialog
    Navigator.of(context, rootNavigator: true).pop();

    // Show debug options
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Database Management'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What would you like to do?'),
              SizedBox(height: 16),
              Text('Warning: These operations can affect your data.',
                  style: TextStyle(
                      color: Colors.red, fontStyle: FontStyle.italic)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _clearCache(context);
              },
              child: Text('Clear Cache'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _resetProgress(context);
              },
              child: Text('Reset Progress'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                _confirmResetDatabase(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Reset Database'),
            ),
          ],
        );
      },
    );
  }

  // Clear database cache
  static Future<void> _clearCache(BuildContext context) async {
    final databaseService = getDatabaseService(context);

    try {
      databaseService.trimCache();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Database cache cleared')),
      );
    } catch (e) {
      _logger.e('Error clearing cache: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error clearing cache: $e')),
      );
    }
  }

  // Reset user progress
  static Future<void> _resetProgress(BuildContext context) async {
    final databaseService = getDatabaseService(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Resetting progress...'),
            ],
          ),
        );
      },
    );

    try {
      await databaseService.resetLearningProgress();

      // Dismiss loading dialog
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Learning progress reset successfully')),
      );
    } catch (e) {
      // Dismiss loading dialog
      Navigator.of(context, rootNavigator: true).pop();

      _logger.e('Error resetting progress: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resetting progress: $e')),
      );
    }
  }

  // Confirm reset database
  static void _confirmResetDatabase(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Reset Database'),
          content: Text(
            'WARNING: This will delete ALL your data and cannot be undone. '
            'Are you absolutely sure?',
            style: TextStyle(color: Colors.red),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _resetDatabase(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Reset Everything'),
            ),
          ],
        );
      },
    );
  }

  // Reset entire database
  static Future<void> _resetDatabase(BuildContext context) async {
    final databaseService = getDatabaseService(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Resetting database...'),
            ],
          ),
        );
      },
    );

    try {
      await databaseService.resetDatabase();

      // Dismiss loading dialog
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Database reset successfully')),
      );
    } catch (e) {
      // Dismiss loading dialog
      Navigator.of(context, rootNavigator: true).pop();

      _logger.e('Error resetting database: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resetting database: $e')),
      );
    }
  }
}
