import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import '../models/account_token.dart';

class AccountTokenService {
  static const String _tokensKey = 'account_tokens';
  final Logger _logger = Logger();

  // Get all stored account tokens
  Future<List<AccountToken>> getAllTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tokensJson = prefs.getString(_tokensKey);

      if (tokensJson == null) {
        return [];
      }

      final List<dynamic> tokensList = json.decode(tokensJson);
      return tokensList.map((json) => AccountToken.fromJson(json)).toList();
    } catch (e) {
      _logger.e('Error getting account tokens', error: e);
      return [];
    }
  }

  // Save a new account token
  Future<void> saveToken(AccountToken token) async {
    try {
      final tokens = await getAllTokens();

      // Check if token for this UID already exists
      final existingIndex = tokens.indexWhere((t) => t.uid == token.uid);

      if (existingIndex >= 0) {
        // Replace existing token
        tokens[existingIndex] = token;
      } else {
        // Add new token
        tokens.add(token);
      }

      await _saveTokens(tokens);
      _logger.i('Saved token for account: ${token.email}');
    } catch (e) {
      _logger.e('Error saving account token', error: e);
      rethrow;
    }
  }

  // Delete an account token by UID
  Future<bool> deleteToken(String uid) async {
    try {
      final tokens = await getAllTokens();
      final initialLength = tokens.length;

      tokens.removeWhere((token) => token.uid == uid);

      if (tokens.length < initialLength) {
        await _saveTokens(tokens);
        _logger.i('Deleted token for UID: $uid');
        return true;
      }

      _logger.w('No token found for UID: $uid');
      return false;
    } catch (e) {
      _logger.e('Error deleting account token', error: e);
      return false;
    }
  }

  // Get a specific token by UID
  Future<AccountToken?> getTokenByUid(String uid) async {
    try {
      final tokens = await getAllTokens();
      return tokens.firstWhere(
        (token) => token.uid == uid,
        orElse: () => throw Exception('Token not found for UID: $uid'),
      );
    } catch (e) {
      _logger.e('Error getting token by UID', error: e);
      return null;
    }
  }

  // Get a specific token by email
  Future<AccountToken?> getTokenByEmail(String email) async {
    try {
      final tokens = await getAllTokens();
      return tokens.firstWhere(
        (token) => token.email.toLowerCase() == email.toLowerCase(),
        orElse: () => throw Exception('Token not found for email: $email'),
      );
    } catch (e) {
      _logger.e('Error getting token by email', error: e);
      return null;
    }
  }

  // Private method to save tokens list to SharedPreferences
  Future<void> _saveTokens(List<AccountToken> tokens) async {
    final prefs = await SharedPreferences.getInstance();
    final tokensJson = json.encode(tokens.map((t) => t.toJson()).toList());
    await prefs.setString(_tokensKey, tokensJson);
  }

  // Clear all tokens (use with caution)
  Future<void> clearAllTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokensKey);
      _logger.w('All account tokens have been cleared');
    } catch (e) {
      _logger.e('Error clearing account tokens', error: e);
      rethrow;
    }
  }
}
