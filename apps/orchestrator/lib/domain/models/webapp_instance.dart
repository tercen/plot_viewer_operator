import 'webapp_registration.dart';

/// A running instance of a webapp within the orchestrator.
class WebappInstance {
  final String instanceId;
  final String appId;
  final WebappRegistration registration;
  bool isReady;

  WebappInstance({
    required this.instanceId,
    required this.appId,
    required this.registration,
    this.isReady = false,
  });
}
