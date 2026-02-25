import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../domain/models/message_envelope.dart';

/// Routes postMessage events between webapp iframes.
///
/// Listens to window.onMessage, parses the standard envelope, and forwards
/// to the appropriate target iframe(s). Does not interpret payloads.
class MessageRouter {
  final _controller = StreamController<MessageEnvelope>.broadcast();
  final Map<String, html.IFrameElement> _iframes = {};
  StreamSubscription<html.MessageEvent>? _subscription;

  /// Stream of all incoming messages (for providers to subscribe).
  Stream<MessageEnvelope> get messages => _controller.stream;

  /// Start listening for postMessage events on the window.
  void start() {
    _subscription = html.window.onMessage.listen(_handleMessage);
  }

  /// Stop listening.
  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }

  /// Register an iframe for a webapp instance.
  void registerIframe(String instanceId, html.IFrameElement iframe) {
    _iframes[instanceId] = iframe;
  }

  /// Unregister an iframe.
  void unregisterIframe(String instanceId) {
    _iframes.remove(instanceId);
  }

  /// Send a message to a specific webapp instance's iframe.
  void sendToInstance(String instanceId, MessageEnvelope envelope) {
    final iframe = _iframes[instanceId];
    if (iframe?.contentWindow == null) return;
    iframe!.contentWindow!.postMessage(
      envelope.toJson(),
      '*',
    );
  }

  /// Broadcast a message to all registered iframes.
  void broadcast(MessageEnvelope envelope) {
    for (final iframe in _iframes.values) {
      if (iframe.contentWindow == null) continue;
      iframe.contentWindow!.postMessage(
        envelope.toJson(),
        '*',
      );
    }
  }

  void _handleMessage(html.MessageEvent event) {
    // Ignore messages that aren't our envelope format
    if (event.data is! Map) return;

    try {
      // JSON round-trip: converts all nested LinkedMap<dynamic, dynamic>
      // (from JS interop) into clean Map<String, dynamic> for Dart.
      final data = json.decode(json.encode(event.data)) as Map<String, dynamic>;
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
