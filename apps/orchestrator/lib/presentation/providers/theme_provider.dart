import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../../domain/models/message_envelope.dart';
import '../../services/message_router.dart';

/// Manages light/dark theme state with localStorage persistence.
///
/// When a [MessageRouter] is attached, theme changes are broadcast
/// to all child app iframes via `theme-changed` messages.
class ThemeProvider extends ChangeNotifier {
  static const _storageKey = 'tercen_theme_dark';

  bool _isDarkMode;
  MessageRouter? _messageRouter;

  ThemeProvider() : _isDarkMode = _loadFromStorage();

  bool get isDarkMode => _isDarkMode;
  String get themeModeName => _isDarkMode ? 'dark' : 'light';

  /// Attach a message router for broadcasting theme changes to iframes.
  void attachMessageRouter(MessageRouter router) {
    _messageRouter = router;
  }

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _saveToStorage(_isDarkMode);
    _broadcastThemeChanged();
    notifyListeners();
  }

  void setDarkMode(bool value) {
    if (_isDarkMode == value) return;
    _isDarkMode = value;
    _saveToStorage(_isDarkMode);
    _broadcastThemeChanged();
    notifyListeners();
  }

  void _broadcastThemeChanged() {
    _messageRouter?.broadcast(MessageEnvelope(
      type: 'theme-changed',
      source: const MessageSource(appId: 'orchestrator', instanceId: ''),
      target: '*',
      payload: {'mode': themeModeName},
    ));
  }

  static bool _loadFromStorage() {
    return web.window.localStorage.getItem(_storageKey) == 'true';
  }

  static void _saveToStorage(bool value) {
    web.window.localStorage.setItem(_storageKey, value.toString());
  }
}
