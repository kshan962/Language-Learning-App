import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import '../models/user.dart' as app_models;
import '../models/account_token.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../services/account_token_service.dart';

class AuthService {
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final Logger _logger = Logger();
  final AccountTokenService _accountTokenService = AccountTokenService();

  // Stream of authentication state changes
  Stream<firebase_auth.User?> authStateChanges() {
    return _firebaseAuth.authStateChanges();
  }

  // Get current user
  firebase_auth.User? get currentUser => _firebaseAuth.currentUser;

  // Check if user is authenticated
  bool get isAuthenticated => currentUser != null;

  // Sign in with email and password
  Future<firebase_auth.UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save auth token to shared preferences for API calls
      if (credential.user != null) {
        final token = await credential.user!.getIdToken();
        // Use the non-nullable version with the null assertion operator (!)
        await _saveToken(token!);

        // Store the Firebase UID in shared preferences for future reference
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('firebase_uid', credential.user!.uid);
        _logger.d('Stored Firebase UID from sign-in: ${credential.user!.uid}');

        // Also store in account tokens list for future reference
        await _storeAccountToken(
            credential.user!.email ?? '', credential.user!.uid, token);
      }

      return credential;
    } catch (e) {
      _logger.e('Sign in error', error: e);
      rethrow;
    }
  }

  // Create account with email and password
  Future<firebase_auth.UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save auth token to shared preferences for API calls
      if (credential.user != null) {
        final token = await credential.user!.getIdToken();
        await _saveToken(token!);

        // Store the Firebase UID in shared preferences for future reference
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('firebase_uid', credential.user!.uid);
        _logger.d('Stored Firebase UID: ${credential.user!.uid}');

        // Also store in account tokens list for future reference
        await _storeAccountToken(
            credential.user!.email ?? '', credential.user!.uid, token);
      }

      return credential;
    } catch (e) {
      _logger.e('Sign up error', error: e);
      rethrow;
    }
  }

  // Sign in with Google
  Future<firebase_auth.UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        throw Exception('Google sign in aborted');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
          await _firebaseAuth.signInWithCredential(credential);

      // Save auth token to shared preferences for API calls
      if (userCredential.user != null) {
        final token = await userCredential.user!.getIdToken();
        await _saveToken(token!);

        // Store the Firebase UID in shared preferences for future reference
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('firebase_uid', userCredential.user!.uid);
        _logger.d(
            'Stored Firebase UID from Google sign-in: ${userCredential.user!.uid}');

        // Also store in account tokens list for future reference
        await _storeAccountToken(
            userCredential.user!.email ?? '', userCredential.user!.uid, token);

        // Try to register the Google user with the backend
        try {
          await registerGoogleUserInBackend();
        } catch (e) {
          _logger.w('Error registering Google user with backend: $e');
          // Continue anyway - the registration will be retried when profile is fetched
        }
      }

      return userCredential;
    } catch (e) {
      _logger.e('Google sign in error', error: e);
      rethrow;
    }
  }

  // Register Google user with backend
  // Add this method to auth_service.dart
  Future<bool> registerGoogleUserInBackend() async {
    try {
      if (currentUser == null) {
        _logger.w('No current user to register');
        return false;
      }

      _logger.i('Registering Google user with backend: ${currentUser!.email}');

      // Create user data for backend registration
      // IMPORTANT: Include a password field to satisfy validation requirements
      final userData = {
        'email': currentUser!.email,
        'username': currentUser!.displayName ?? 'Google User',
        'firebaseUid': currentUser!.uid,
        'nativeLanguage': 'English',
        'arabicLevel': 'Beginner',
        'learningGoal': 'Travel', // Use a known valid enum value
        'dailyGoal': 10,
        'password':
            'Google${DateTime.now().millisecondsSinceEpoch}', // Generate a random password
      };

      _logger.d('Registering with data: ${userData.toString()}');

      // Create API service instance
      final apiService = ApiService(authService: this);

      // Call register endpoint
      await apiService.register(userData);

      _logger.i('Successfully registered Google user with backend');
      return true;
    } catch (e) {
      _logger.e('Failed to register Google user with backend: $e');
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // We'll use a simpler approach to get the database service
      // since the context-based approach may not work reliably
      DatabaseService? databaseService;

      // Clear user cache if possible
      try {
        // Instead of trying to get the database service from context,
        // we'll create a new instance or you can inject it in a different way
        databaseService = DatabaseService();
        await databaseService.clearUserCache();
        _logger.i('User cache cleared during sign out');
      } catch (e) {
        _logger.d('Could not clear user cache: $e');
        // Continue with signout even if we can't clear the cache
      }

      // Standard sign out procedure
      await _googleSignIn.signOut();
      await _firebaseAuth.signOut();
      await _clearToken();

      _logger.i('User signed out successfully');
    } catch (e) {
      _logger.e('Sign out error', error: e);
      rethrow;
    }
  }

  // Delete account
  Future<bool> deleteAccount() async {
    try {
      _logger.i('Deleting user account');

      // Store current user UID before we start the deletion process
      final currentUserUid = currentUser?.uid;

      if (currentUserUid == null) {
        _logger.e('Cannot delete account: No current user');
        return false;
      }

      // Create API service to call backend
      final apiService = ApiService(authService: this);
      bool backendDeletionSuccess = false;

      try {
        // Try to delete account on backend
        backendDeletionSuccess = await apiService.deleteAccount();
        _logger.i('Account deleted on backend: $backendDeletionSuccess');
      } catch (apiError) {
        // Check if the error is "User not found" - this is actually okay
        // as we still want to clean up the Firebase user and local data
        if (apiError.toString().contains('User not found')) {
          _logger.w('Backend user not found, continuing with local cleanup');
          // We'll consider this a non-fatal error and continue
          backendDeletionSuccess = true;
        } else {
          _logger.e('Backend account deletion failed: $apiError');
          // For other API errors, we'll still try to clean up local data
        }
      }

      // Regardless of backend success, clean up local data
      _logger.i('Cleaning up local data');

      // Clear local database
      final databaseService = DatabaseService();
      await databaseService.clearUserCache();

      // Remove token from AccountTokenService
      try {
        await _accountTokenService.deleteToken(currentUserUid);
        _logger.i('Removed token for UID: $currentUserUid');
      } catch (e) {
        _logger.w('Error removing token: $e');
        // Continue anyway
      }

      // Delete Firebase user
      bool firebaseUserDeleted = false;
      try {
        if (_firebaseAuth.currentUser != null) {
          await _firebaseAuth.currentUser?.delete();
          _logger.i('Firebase user deleted');
          firebaseUserDeleted = true;
        }
      } catch (e) {
        _logger.w('Could not delete Firebase user: $e');
        // Continue with sign out even if we can't delete the Firebase user
      }

      // If we couldn't delete the Firebase user, at least sign out
      if (!firebaseUserDeleted) {
        await _googleSignIn.signOut();
        await _firebaseAuth.signOut();
        _logger.i('User signed out');
      }

      // Clear auth token
      await _clearToken();

      _logger.i('Account cleanup completed');

      // Consider the operation successful if either backend deletion worked
      // or we successfully deleted the Firebase user
      return backendDeletionSuccess || firebaseUserDeleted;
    } catch (e) {
      _logger.e('Account deletion error', error: e);
      // Don't rethrow - return false instead so the UI can handle it gracefully
      return false;
    }
  }

  // Add a new method to refresh user data
  Future<void> refreshUserData() async {
    try {
      if (currentUser == null) {
        _logger.w('Cannot refresh user data: No current user');
        return;
      }

      _logger.i('Refreshing user data for ${currentUser!.uid}');

      // Create a new database service instance
      final databaseService = DatabaseService();

      // Clear user data cache
      await databaseService.clearUserCache();
      _logger.d('User cache cleared during refresh');

      try {
        // Try to fetch fresh data from API
        // We need to create an ApiService instance
        // This is a bit of a hack since we don't have dependency injection
        final apiService = ApiService(authService: this);
        final user = await apiService.getUserProfile();

        // Save the fresh data to the database
        await databaseService.saveUser(user);
        _logger.d('Fresh user data from API saved to database');
      } catch (apiError) {
        _logger.w('Could not fetch user data from API: $apiError');

        // If API fetch fails, at least force a refresh from the database
        await databaseService.getUser(currentUser!.uid, bypassCache: true);
        _logger.d('User data refreshed from database as fallback');
      }

      _logger.i('User data refresh complete');
    } catch (e) {
      _logger.e('Error refreshing user data', error: e);
    }
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
    } catch (e) {
      _logger.e('Password reset error', error: e);
      rethrow;
    }
  }

  // Update user profile
  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    try {
      await _firebaseAuth.currentUser?.updateDisplayName(displayName);
      await _firebaseAuth.currentUser?.updatePhotoURL(photoURL);
    } catch (e) {
      _logger.e('Update profile error', error: e);
      rethrow;
    }
  }

  // Get auth token for API calls
  Future<String?> getToken() async {
    try {
      if (currentUser == null) {
        _logger.w('No current user, cannot get token');
        return null;
      }

      // First, try to get a fresh token from AccountTokenService for the current user
      try {
        final accountToken =
            await _accountTokenService.getTokenByUid(currentUser!.uid);
        if (accountToken != null) {
          _logger.d('Using token from AccountTokenService for current user');

          // Check if the token is recent (less than 1 hour old)
          final tokenAge =
              DateTime.now().difference(accountToken.createdAt).inMinutes;
          if (tokenAge < 55) {
            // Firebase tokens typically expire after 1 hour
            return accountToken.token;
          } else {
            _logger.d('Token is older than 55 minutes, getting a fresh one');
          }
        }
      } catch (e) {
        _logger.d('Error getting token from AccountTokenService: $e');
        // Continue to try other methods
      }

      // If we couldn't get a valid token from AccountTokenService, get a fresh one from Firebase
      if (currentUser != null) {
        _logger.d('Getting fresh token from Firebase');
        final token = await currentUser!.getIdToken(true); // Force refresh
        if (token != null) {
          // Save the fresh token
          await _saveToken(token);

          // Also update the token in AccountTokenService
          await _storeAccountToken(
              currentUser!.email ?? '', currentUser!.uid, token);

          return token;
        }
      }

      // Try to get from shared preferences as a last resort
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('auth_token');

      if (savedToken != null) {
        _logger.d('Using token from SharedPreferences');
        return savedToken;
      }

      _logger.w('Could not get a valid token');
      return null;
    } catch (e) {
      _logger.e('Get token error', error: e);
      return null;
    }
  }

  // Save token to shared preferences
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  // Clear token and Firebase UID from shared preferences
  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('firebase_uid');
    _logger.d('Cleared auth token and Firebase UID from shared preferences');
  }

  // Map Firebase user to our app User model
  app_models.User? mapFirebaseUser(firebase_auth.User? firebaseUser) {
    if (firebaseUser == null) return null;

    return app_models.User(
      id: firebaseUser.uid,
      username: firebaseUser.displayName ?? '',
      email: firebaseUser.email ?? '',
    );
  }

  // Store account token for future reference
  Future<void> _storeAccountToken(
      String email, String uid, String token) async {
    try {
      final accountToken = AccountToken(
        email: email,
        uid: uid,
        token: token,
        createdAt: DateTime.now(),
      );

      await _accountTokenService.saveToken(accountToken);
      _logger.d('Stored account token for future reference: $email');
    } catch (e) {
      _logger.e('Error storing account token', error: e);
      // Don't throw - this is a non-critical operation
    }
  }

  // Get all stored account tokens
  Future<List<AccountToken>> getAllAccountTokens() async {
    try {
      return await _accountTokenService.getAllTokens();
    } catch (e) {
      _logger.e('Error getting all account tokens', error: e);
      return [];
    }
  }

  // Delete an account by UID
  Future<bool> deleteAccountByUid(String uid) async {
    try {
      _logger.i('Deleting account with UID: $uid');

      // Get the token for this account
      final accountToken = await _accountTokenService.getTokenByUid(uid);

      if (accountToken == null) {
        _logger.w('No token found for UID: $uid');
        return false;
      }

      // Check if this is the current user
      final isCurrentUser = currentUser?.uid == uid;

      if (isCurrentUser) {
        // If this is the current user, we can delete it directly
        _logger.d('Deleting current user account');
        final success = await deleteAccount();

        if (success) {
          // Remove the token from our stored tokens
          await _accountTokenService.deleteToken(uid);
        }

        return success;
      } else {
        // For other accounts, we can't directly delete them without authentication
        // But we can remove them from our stored tokens
        _logger.d('Removing token for account with UID: $uid');
        await _accountTokenService.deleteToken(uid);

        // Show a message that the token was removed but the account may still exist
        _logger.w('Token removed, but Firebase account may still exist');
        return true; // Return true to indicate the token was successfully removed
      }
    } catch (e) {
      _logger.e('Error deleting account by UID', error: e);
      return false;
    }
  }
}
