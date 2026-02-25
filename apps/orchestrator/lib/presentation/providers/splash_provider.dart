import 'package:flutter/material.dart';

/// Manages splash screen visibility.
///
/// In mock build: splash dismisses after a short delay simulating webapp readiness.
/// In production: splash dismisses when auth is complete and required webapps
/// send app-ready.
class SplashProvider extends ChangeNotifier {
  bool _isVisible = true;
  final Set<String> _readyInstances = {};
  Set<String> _requiredInstances = {};

  bool get isVisible => _isVisible;

  /// Set the instances that must report ready before splash dismisses.
  void setRequiredInstances(Set<String> instanceIds) {
    _requiredInstances = instanceIds;
    _checkReady();
  }

  /// Mark an instance as ready (called when app-ready message received).
  void markReady(String instanceId) {
    _readyInstances.add(instanceId);
    _checkReady();
  }

  /// Force dismiss (for mock build timer fallback).
  void dismiss() {
    if (!_isVisible) return;
    _isVisible = false;
    notifyListeners();
  }

  void _checkReady() {
    if (!_isVisible) return;
    if (_requiredInstances.isEmpty) return;
    if (_requiredInstances.every(_readyInstances.contains)) {
      _isVisible = false;
      notifyListeners();
    }
  }
}
