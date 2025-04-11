import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/flashcard.dart';
import '../models/user.dart';
import '../models/conversation.dart';
import '../services/auth_service.dart';

class ApiService {
  // Add logger instance
  final _logger = Logger();

  // Base URL for API
  final String baseUrl;

  // Auth service reference
  final AuthService _authService;

  // Constructor with authService parameter
  ApiService({required AuthService authService})
      : _authService = authService,
        baseUrl = _getBaseUrl() {
    _logger.i('Initializing ApiService with baseUrl: $baseUrl');
    // Initialize token when service is created
    _initializeToken();
  }

  // Initialize token asynchronously
  Future<void> _initializeToken() async {
    try {
      final token = await _authService.getToken();
      _logger.d('Token initialized: ${token != null ? 'Yes' : 'No'}');
    } catch (e) {
      _logger.e('Error initializing token', error: e);
    }
  }

  // Static method to safely get base URL
  static String _getBaseUrl() {
    final logger = Logger();

    try {
      // Try specific API_BASE_URL key first
      final apiBaseUrl = dotenv.env['API_BASE_URL'];
      if (apiBaseUrl != null && apiBaseUrl.isNotEmpty) {
        logger.i('Using API_BASE_URL from environment: $apiBaseUrl');
        return apiBaseUrl;
      }

      // No environment variable found, use appropriate default for physical device
      const physicalDeviceUrl = 'http://192.168.1.149:5000/api';
      logger.i(
          'No API_BASE_URL found in environment. Using physical device URL: $physicalDeviceUrl');
      return physicalDeviceUrl;
    } catch (e) {
      logger.e('Error getting base URL', error: e);
      // Always have a fallback for robustness
      const fallbackUrl = 'http://192.168.1.149:5000/api';
      logger.i('Falling back to physical device URL: $fallbackUrl');
      return fallbackUrl;
    }
  }

  // Get authentication headers with token
  Future<Map<String, String>> get _authHeaders async {
    // Get the actual token from the auth service
    final token = await _authService.getToken();

    // Get Firebase UID from shared preferences
    final prefs = await SharedPreferences.getInstance();
    final firebaseUid = prefs.getString('firebase_uid');

    if (token == null) {
      _logger.w('No authentication token available');
    } else {
      _logger.d('Using authentication token for API request');
    }

    if (firebaseUid != null) {
      _logger.d('Including Firebase UID in request headers: $firebaseUid');
    }

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': token != null ? 'Bearer $token' : '',
    };

    // Add Firebase UID header if available
    if (firebaseUid != null) {
      headers['X-Firebase-UID'] = firebaseUid;
    }

    return headers;
  }

  // Handle API response
  dynamic _handleResponse(http.Response response) {
    _logger.d('API Response - Status Code: ${response.statusCode}');

    // Only log the first 500 characters of the response body to avoid cluttering logs
    final truncatedBody = response.body.length > 500
        ? '${response.body.substring(0, 500)}...(truncated)'
        : response.body;
    _logger.d('API Response Body: $truncatedBody');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      _logger.e('API Error: ${response.statusCode} - ${response.body}');
      throw Exception('API Error: ${response.statusCode} - ${response.body}');
    }
  }

  // Authentication
  Future<Map<String, dynamic>> login(String email, String password) async {
    _logger.i('Logging in user: $email');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final data = _handleResponse(response);
      _logger.i('Login successful');
      return data;
    } catch (e) {
      _logger.e('Login failed: $e');
      rethrow;
    }
  }

  // Updated register method to handle Google users
  Future<Map<String, dynamic>> register(Map<String, dynamic> userData) async {
    _logger.i('Registering user: ${userData['email']}');

    try {
      // Validate required fields
      if (userData['email'] == null || userData['email'].isEmpty) {
        throw Exception('Email is required');
      }

      // For registration, we don't need an auth token
      final headers = {
        'Content-Type': 'application/json',
      };

      // Add Firebase UID header if available
      if (userData['firebaseUid'] != null) {
        _logger.d(
            'Including Firebase UID in registration: ${userData['firebaseUid']}');
      }

      _logger.d(
          'Sending registration request to backend with data: ${jsonEncode(userData)}');

      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: headers,
        body: jsonEncode(userData),
      );

      // Handle HTTP errors
      if (response.statusCode >= 400) {
        _logger.e('Registration API error: ${response.statusCode}');
        _logger.e('Response body: ${response.body}');

        // Try to parse error message from response
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(
              errorData['message'] ?? 'Server error: ${response.statusCode}');
        } catch (e) {
          throw Exception(
              'Registration failed: Server error ${response.statusCode}');
        }
      }

      final data = jsonDecode(response.body);

      // Verify success flag in response
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Registration failed');
      }

      _logger.i('Registration successful');
      return data;
    } catch (e) {
      _logger.e('Registration failed', error: e);
      rethrow;
    }
  }

  // User profile - updated to use async headers
  Future<User> getUserProfile() async {
    _logger.d('Fetching user profile');

    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$baseUrl/users/profile'),
        headers: headers,
      );

      final data = _handleResponse(response);
      _logger.d('User profile data received: ${jsonEncode(data)}');
      return User.fromJson(data);
    } catch (e) {
      _logger.e('Failed to get user profile: $e');
      rethrow;
    }
  }

  Future<User> updateUserProfile(User user) async {
    _logger.d('Updating user profile: ${user.id}');

    try {
      final headers = await _authHeaders;
      final response = await http.put(
        Uri.parse('$baseUrl/users/profile'),
        headers: headers,
        body: jsonEncode(user.toJson()),
      );

      final data = _handleResponse(response);
      _logger.d('User profile updated successfully');
      return User.fromJson(data);
    } catch (e) {
      _logger.e('Failed to update user profile: $e');
      rethrow;
    }
  }

  // Flashcards - updated to use async headers
  Future<List<Flashcard>> getFlashcards({
    String? category,
    String? difficulty,
    bool dueOnly = false,
  }) async {
    _logger.d(
        'Getting flashcards: category=$category, difficulty=$difficulty, dueOnly=$dueOnly');

    try {
      var queryParams = <String, String>{};
      if (category != null) queryParams['category'] = category;
      if (difficulty != null) queryParams['difficulty'] = difficulty;
      if (dueOnly) queryParams['dueOnly'] = 'true';

      final uri = Uri.parse('$baseUrl/flashcards')
          .replace(queryParameters: queryParams);

      final headers = await _authHeaders;
      final response = await http.get(uri, headers: headers);

      final List<dynamic> data = _handleResponse(response);
      final flashcards = data.map((json) => Flashcard.fromJson(json)).toList();

      // Log IDs to verify they are correct MongoDB ObjectIds
      for (var card in flashcards) {
        _logger.d('Received flashcard with ID: ${card.id}');
      }

      _logger.d('Retrieved ${flashcards.length} flashcards');
      return flashcards;
    } catch (e) {
      _logger.e('Failed to get flashcards: $e');
      rethrow;
    }
  }

  Future<void> updateFlashcardProgress(String id, int quality) async {
    _logger.d('Updating flashcard progress: id=$id, quality=$quality');

    try {
      // Check if ID is in the correct format for MongoDB
      if (id.length != 24 && !id.startsWith('ObjectId')) {
        _logger.w('Invalid MongoDB ObjectId format: $id - skipping API call');
        return; // Skip API call for invalid IDs
      }

      // For ObjectId, we need to extract the actual ID value
      final String cleanId = id.startsWith('ObjectId')
          ? id.substring(id.indexOf('"') + 1, id.lastIndexOf('"'))
          : id;

      _logger.d('Using cleaned ID for API call: $cleanId');

      final headers = await _authHeaders;
      final response = await http.post(
        Uri.parse('$baseUrl/flashcards/$cleanId/progress'),
        headers: headers,
        body: jsonEncode({
          'quality': quality,
        }),
      );

      _handleResponse(response);
      _logger.d('Flashcard progress updated successfully');
    } catch (e) {
      _logger.w('Failed to update flashcard progress: $e');
      // Make this non-fatal so the app can continue working
    }
  }

  // AI Conversation - updated to use async headers
  Future<String> getAIResponse(String message, List<Message> history) async {
    _logger.d(
        'Getting AI response for message: "${message.substring(0, message.length > 50 ? 50 : message.length)}${message.length > 50 ? "..." : ""}"');
    _logger.d('Conversation history length: ${history.length}');

    try {
      final historyJson = history.map((m) => m.toJson()).toList();

      final headers = await _authHeaders;
      final response = await http.post(
        Uri.parse('$baseUrl/conversations/response'),
        headers: headers,
        body: jsonEncode({
          'message': message,
          'history': historyJson,
        }),
      );

      final data = _handleResponse(response);
      final aiResponse = data['response'] as String;
      _logger.d(
          'Received AI response: "${aiResponse.substring(0, aiResponse.length > 50 ? 50 : aiResponse.length)}${aiResponse.length > 50 ? "..." : ""}"');
      return aiResponse;
    } catch (e) {
      _logger.e('Failed to get AI response: $e');
      rethrow;
    }
  }

  Future<List<Flashcard>> getWordSuggestions(int count) async {
    _logger.d('Getting word suggestions, count=$count');

    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$baseUrl/users/word-suggestions?count=$count'),
        headers: headers,
      );

      final List<dynamic> data = _handleResponse(response);
      final suggestions = data.map((json) => Flashcard.fromJson(json)).toList();
      _logger.d('Retrieved ${suggestions.length} word suggestions');
      return suggestions;
    } catch (e) {
      _logger.e('Failed to get word suggestions: $e');
      rethrow;
    }
  }

  // Reset user learning progress
  Future<bool> resetLearningProgress() async {
    _logger.d('Resetting user learning progress via API');

    try {
      final headers = await _authHeaders;
      final response = await http.post(
        Uri.parse('$baseUrl/users/reset-progress'),
        headers: headers,
      );

      final data = _handleResponse(response);
      _logger.i(
          'Learning progress reset successfully via API: ${data['message']}');
      return true;
    } catch (e) {
      _logger.e('Failed to reset learning progress via API: $e');
      // Don't rethrow, just return false to allow the app to continue
      return false;
    }
  }

  // Delete user account and all associated data
  Future<bool> deleteAccount() async {
    _logger.d('Deleting user account');

    try {
      final headers = await _authHeaders;
      final response = await http.delete(
        Uri.parse('$baseUrl/users/account'),
        headers: headers,
      );

      final data = _handleResponse(response);
      _logger.i('Account deleted successfully: ${data['message']}');

      return true;
    } catch (e) {
      // Check for specific error messages
      final errorMessage = e.toString();

      // If the error is "User not found", this is actually expected in some cases
      // where the user exists in Firebase but not in our backend
      if (errorMessage.contains('User not found')) {
        _logger.w(
            'Backend user not found, but this is okay for Firebase-only users');
        // Return true to indicate that we should proceed with Firebase deletion
        return true;
      }

      _logger.e('Failed to delete account: $e');
      rethrow;
    }
  }
}
