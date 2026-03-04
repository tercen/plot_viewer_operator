import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import '../domain/models/message_envelope.dart';

/// Routes postMessage events between webapp iframes.
///
/// Listens to window.onMessage, parses the standard envelope, and forwards
/// to the appropriate target iframe(s). Does not interpret payloads.
class MessageRouter {
  final _controller = StreamController<MessageEnvelope>.broadcast();
  final Map<String, web.HTMLIFrameElement> _iframes = {};

  /// Stream of all incoming messages (for providers to subscribe).
  Stream<MessageEnvelope> get messages => _controller.stream;

  /// Start listening for postMessage events on the window.
  void start() {
    web.window.addEventListener(
      'message',
      (web.Event event) {
        final msgEvent = event as web.MessageEvent;
        _handleMessage(msgEvent);
      }.toJS,
    );
  }

  /// Stop listening.
  void dispose() {
    // Note: addEventListener cleanup would go here if needed
    _controller.close();
  }

  /// Register an iframe for a webapp instance.
  void registerIframe(String instanceId, web.HTMLIFrameElement iframe) {
    _iframes[instanceId] = iframe;
  }

  /// Unregister an iframe.
  void unregisterIframe(String instanceId) {
    _iframes.remove(instanceId);
  }

  /// Send a message to a specific webapp instance's iframe.
  void sendToInstance(String instanceId, MessageEnvelope envelope) {
    final iframe = _iframes[instanceId];
    if (iframe == null || iframe.contentWindow == null) return;
    iframe.contentWindow!.postMessage(
      envelope.toJson().jsify(),
      '*'.toJS,
    );
  }

  /// Broadcast a message to all registered iframes.
  void broadcast(MessageEnvelope envelope) {
    for (final iframe in _iframes.values) {
      if (iframe.contentWindow == null) continue;
      iframe.contentWindow!.postMessage(
        envelope.toJson().jsify(),
        '*'.toJS,
      );
    }
  }

  void _handleMessage(web.MessageEvent event) {
    try {
      // Convert JS data to Dart via JSON (ensures proper Map<String, dynamic>)
      final jsData = event.data;
      if (jsData == null) return;

      // Use JSON.stringify → json.decode pattern (same as project_nav MessageHelper)
      final jsonObj = web.window['JSON'] as JSObject;
      final stringifyFn = jsonObj['stringify'] as JSFunction;
      final jsonStr = stringifyFn.callAsFunction(jsonObj, jsData) as JSString;
      final data = json.decode(jsonStr.toDart) as Map<String, dynamic>;

      if (!data.containsKey('type') || !data.containsKey('source')) return;

      final envelope = MessageEnvelope.fromJson(data);

      // Emit to the stream for providers to handle
      _controller.add(envelope);

      // Route the message
      if (envelope.isForOrchestrator) {
        // Handled by providers listening on the stream
        return;
      }

      if (envelope.isBroadcast) {
        broadcast(envelope);
        return;
      }

      // Targeted message — find instances matching the target appId
      for (final entry in _iframes.entries) {
        // instanceId format is "{appId}-{n}", so check prefix
        if (entry.key.startsWith(envelope.target)) {
          sendToInstance(entry.key, envelope);
        }
      }
    } catch (e) {
      print('MessageRouter: failed to parse message: $e');
    }
  }
}
