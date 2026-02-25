import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/webapp_registry.dart';
import '../providers/webapp_provider.dart';
import '../widgets/error_overlay.dart';
import '../widgets/splash_screen.dart';
import '../widgets/workbench.dart';

/// Top-level screen that composes the workbench, splash, and error overlays.
class OrchestratorScreen extends StatelessWidget {
  final WebappRegistry registry;

  const OrchestratorScreen({super.key, required this.registry});

  @override
  Widget build(BuildContext context) {
    final hasError = context.watch<WebappProvider>().currentError != null;

    return Stack(
      children: [
        // Workbench is always rendered (iframes stay alive)
        Workbench(registry: registry),
        // Error overlay (above workbench)
        if (hasError) const ErrorOverlay(),
        // Splash screen (above everything)
        const SplashScreen(),
      ],
    );
  }
}
