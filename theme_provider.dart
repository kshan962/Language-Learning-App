import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _loadThemePreference();
  }

  // Load theme preference from SharedPreferences
  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool('darkMode');

      // If darkMode preference exists, use it
      if (isDark != null) {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      } else {
        // Otherwise use system default
        _themeMode = ThemeMode.system;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading theme preference: $e');
    }
  }

  // Set theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;

    // Save to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();

      // Only save explicit light/dark preference, not system
      if (mode != ThemeMode.system) {
        await prefs.setBool('darkMode', mode == ThemeMode.dark);
      } else {
        // If system, remove the preference
        await prefs.remove('darkMode');
      }
    } catch (e) {
      debugPrint('Error saving theme preference: $e');
    }

    notifyListeners();
  }

  // Set dark mode specifically
  Future<void> setDarkMode(bool isDark) async {
    await setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
  }

  // Toggle between light and dark (ignores system)
  Future<void> toggleTheme() async {
    await setThemeMode(
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
  }
}
