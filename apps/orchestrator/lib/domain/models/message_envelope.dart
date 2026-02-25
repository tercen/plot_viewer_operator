/// Source identifier for a postMessage.
class MessageSource {
  final String appId;
  final String instanceId;

  const MessageSource({required this.appId, required this.instanceId});

  Map<String, dynamic> toJson() => {
        'appId': appId,
        'instanceId': instanceId,
      };

  factory MessageSource.fromJson(Map<String, dynamic> json) {
    return MessageSource(
      appId: json['appId'] as String? ?? '',
      instanceId: json['instanceId'] as String? ?? '',
    );
  }
}

/// Standard postMessage envelope for inter-app communication.
class MessageEnvelope {
  final String type;
  final MessageSource source;

  /// Either a specific appId string, or "*" for broadcast.
  final String target;
  final Map<String, dynamic> payload;

  const MessageEnvelope({
    required this.type,
    required this.source,
    required this.target,
    this.payload = const {},
  });

  bool get isBroadcast => target == '*';
  bool get isForOrchestrator => target == 'orchestrator';

  Map<String, dynamic> toJson() => {
        'type': type,
        'source': source.toJson(),
        'target': target,
        'payload': payload,
      };

  factory MessageEnvelope.fromJson(Map<String, dynamic> json) {
    final targetRaw = json['target'];
    String targetStr;
    if (targetRaw is String) {
      targetStr = targetRaw;
    } else if (targetRaw is Map) {
      targetStr = (targetRaw['appId'] as String?) ?? '';
    } else {
      targetStr = '';
    }

    return MessageEnvelope(
      type: json['type'] as String? ?? '',
      source: MessageSource.fromJson(
        (json['source'] as Map<String, dynamic>?) ?? {},
      ),
      target: targetStr,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }
}
