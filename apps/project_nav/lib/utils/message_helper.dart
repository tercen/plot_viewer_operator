import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

/// PostMessage utilities for inter-app communication.
///
/// Source format follows the orchestrator's MessageEnvelope spec:
///   { type, source: { appId, instanceId }, target, payload }
class MessageHelper {
  MessageHelper._();

  static const String _appId = 'project-nav';

  /// Listen for incoming postMessage events.
  ///
  /// Calls [onMessage] with the message type and payload map
  /// for every valid envelope received.
  static void listen(
    void Function(String type, Map<String, dynamic> payload) onMessage,
  ) {
    web.window.addEventListener(
      'message',
      (web.Event event) {
        final msgEvent = event as web.MessageEvent;
        final data = msgEvent.data;
        if (data == null) return;

        final jsonObj = web.window['JSON'] as JSObject;
        final stringifyFn = jsonObj['stringify'] as JSFunction;
        final jsonStr = stringifyFn.callAsFunction(jsonObj, data) as JSString;
        final map = json.decode(jsonStr.toDart) as Map<String, dynamic>;

        final type = map['type'] as String?;
        final payload = map['payload'] as Map<String, dynamic>? ?? {};
        if (type != null) {
          onMessage(type, payload);
        }
      }.toJS,
    );
  }

  /// Send a message to the parent window (orchestrator).
  ///
  /// [type] is the message type (e.g., 'app-ready', 'step-selected').
  /// [payload] is the message data.
  /// [target] defaults to 'orchestrator'. Use '*' for broadcast.
  static void postMessage(
    String type,
    Map<String, dynamic> payload, {
    String target = 'orchestrator',
  }) {
    final message = {
      'type': type,
      'source': {'appId': _appId, 'instanceId': ''},
      'target': target,
      'payload': payload,
    };
    web.window.parent?.postMessage(message.jsify(), '*'.toJS);
  }
}
