import 'package:flutter/material.dart';

/// Manages light/dark theme state.
///
/// Theme is controlled by the orchestrator via postMessage.
/// No local persistence — the orchestrator is the source of truth.
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode;

  ThemeProvider({ThemeMode initialMode = ThemeMode.light})
      : _themeMode = initialMode;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  /// Parse a mode name string ('light'/'dark') from postMessage payload.
  void setFromModeName(String modeName) {
    setThemeMode(modeName == 'dark' ? ThemeMode.dark : ThemeMode.light);
  }
}
