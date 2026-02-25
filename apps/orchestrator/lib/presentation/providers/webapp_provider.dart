import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/models/message_envelope.dart';
import '../../domain/models/webapp_instance.dart';
import '../../services/message_router.dart';
import '../../services/webapp_registry.dart';
import 'splash_provider.dart';
import 'theme_provider.dart';

/// Error info for the error overlay.
class WebappError {
  final String webappName;
  final String message;
  const WebappError({required this.webappName, required this.message});
}

/// Manages webapp instances and their lifecycle.
class WebappProvider extends ChangeNotifier {
  final WebappRegistry registry;
  final MessageRouter messageRouter;
  final SplashProvider splashProvider;
  final ThemeProvider themeProvider;

  final Map<String, WebappInstance> _instances = {};
  int _nextInstanceNum = 1;
  WebappError? _currentError;
  StreamSubscription<MessageEnvelope>? _messageSubscription;

  WebappProvider({
    required this.registry,
    required this.messageRouter,
    required this.splashProvider,
    required this.themeProvider,
  }) {
    _messageSubscription = messageRouter.messages.listen(_handleMessage);
  }

  Map<String, WebappInstance> get instances => Map.unmodifiable(_instances);
  WebappError? get currentError => _currentError;

  /// Create a new instance of a registered webapp.
  WebappInstance createInstance(String appId) {
    final reg = registry.get(appId);
    if (reg == null) {
      throw StateError('Unknown webapp: $appId');
    }

    final instanceId = '$appId-${_nextInstanceNum++}';
    final instance = WebappInstance(
      instanceId: instanceId,
      appId: appId,
      registration: reg,
    );
    _instances[instanceId] = instance;
    notifyListeners();
    return instance;
  }

  /// Get instance by instanceId.
  WebappInstance? getInstance(String instanceId) => _instances[instanceId];

  /// Get all instances for a given appId.
  List<WebappInstance> getInstancesForApp(String appId) {
    return _instances.values.where((i) => i.appId == appId).toList();
  }

  /// Find the instanceId for a given appId (first match).
  String? getInstanceIdForApp(String appId) {
    final instances = getInstancesForApp(appId);
    return instances.isEmpty ? null : instances.first.instanceId;
  }

  /// Reset a webapp instance's ready state when its iframe is destroyed
  /// (e.g., tool strip closed). Ensures the loading overlay shows on reopen.
  void resetInstanceReady(String instanceId) {
    final instance = _instances[instanceId];
    if (instance != null && instance.isReady) {
      instance.isReady = false;
      notifyListeners();
    }
  }

  /// Dismiss the current error overlay.
  void dismissError() {
    _currentError = null;
    notifyListeners();
  }

  static const _token = String.fromEnvironment('TERCEN_TOKEN');
  static const _teamId = String.fromEnvironment('TEAM_ID');
  static const _serviceUri = String.fromEnvironment('SERVICE_URI');

  void _handleMessage(MessageEnvelope envelope) {
    switch (envelope.type) {
      case 'request-context':
        _sendInitContext(envelope.source);
      case 'app-ready':
        final instanceId = _findInstanceBySource(envelope.source);
        if (instanceId != null) {
          _instances[instanceId]?.isReady = true;
          splashProvider.markReady(instanceId);
          notifyListeners();
        }
      case 'app-error':
        final instanceId = _findInstanceBySource(envelope.source);
        final instance = instanceId != null ? _instances[instanceId] : null;
        _currentError = WebappError(
          webappName: instance?.registration.name ?? envelope.source.appId,
          message: envelope.payload['message'] as String? ?? 'Unknown error',
        );
        notifyListeners();
      case 'theme-changed':
        // Broadcast to all iframes (already handled by message router)
        break;
      default:
        // Other messages are routed by MessageRouter, not handled here
        break;
    }
  }

  void _sendInitContext(MessageSource requester) {
    if (_token.isEmpty) return;

    final instanceId = _findInstanceBySource(requester);
    if (instanceId == null) return;

    final envelope = MessageEnvelope(
      type: 'init-context',
      source: const MessageSource(appId: 'orchestrator', instanceId: ''),
      target: requester.appId,
      payload: {
        'token': _token,
        'teamId': _teamId,
        if (_serviceUri.isNotEmpty) 'serviceUri': _serviceUri,
        'themeMode': themeProvider.themeModeName,
      },
    );

    messageRouter.sendToInstance(instanceId, envelope);
  }

  String? _findInstanceBySource(MessageSource source) {
    // Try exact instanceId match first
    if (source.instanceId.isNotEmpty &&
        _instances.containsKey(source.instanceId)) {
      return source.instanceId;
    }
    // Fall back to first instance of the appId
    return getInstanceIdForApp(source.appId);
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}
