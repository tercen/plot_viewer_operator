import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'domain/models/message_envelope.dart';
import 'domain/models/webapp_registration.dart';
import 'presentation/providers/layout_provider.dart';
import 'presentation/providers/splash_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/webapp_provider.dart';
import 'presentation/screens/orchestrator_screen.dart';
import 'services/message_router.dart';
import 'services/webapp_registry.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  final registry = WebappRegistry();
  final messageRouter = MessageRouter()..start();
  final splashProvider = SplashProvider();
  final themeProvider = ThemeProvider()..attachMessageRouter(messageRouter);

  final layoutProvider = LayoutProvider();

  // Create initial webapp instances
  final webappProvider = WebappProvider(
    registry: registry,
    messageRouter: messageRouter,
    splashProvider: splashProvider,
    themeProvider: themeProvider,
  );

  _createInitialInstances(registry, webappProvider, splashProvider,
      layoutProvider);

  // Cache last step-selected so we can forward it to step-viewer after it
  // reports app-ready (its iframe doesn't exist when the broadcast fires).
  Map<String, dynamic>? lastStepSelectedPayload;

  // Create step-viewer when a data step is selected.
  messageRouter.messages.where((e) => e.type == 'step-selected').listen((msg) {
    lastStepSelectedPayload = msg.payload;

    // Create step-viewer instance on first step selection
    if (webappProvider.getInstanceIdForApp('step-viewer') == null) {
      final instance = webappProvider.createInstance('step-viewer');
      layoutProvider.addContentInstance(instance.instanceId);
    } else {
      // Forward to existing step-viewer instance
      final instanceId = webappProvider.getInstanceIdForApp('step-viewer')!;
      messageRouter.sendToInstance(
        instanceId,
        MessageEnvelope(
          type: 'step-selected',
          source:
              const MessageSource(appId: 'orchestrator', instanceId: ''),
          target: 'step-viewer',
          payload: msg.payload,
        ),
      );
    }
  });

  // Forward the cached step-selected to step-viewer once it is ready.
  messageRouter.messages
      .where((e) => e.type == 'app-ready' && e.source.appId == 'step-viewer')
      .listen((_) {
    if (lastStepSelectedPayload != null) {
      final instanceId = webappProvider.getInstanceIdForApp('step-viewer');
      if (instanceId != null) {
        messageRouter.sendToInstance(
          instanceId,
          MessageEnvelope(
            type: 'step-selected',
            source:
                const MessageSource(appId: 'orchestrator', instanceId: ''),
            target: 'step-viewer',
            payload: lastStepSelectedPayload!,
          ),
        );
      }
    }
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: splashProvider),
        ChangeNotifierProvider.value(value: layoutProvider),
        ChangeNotifierProvider.value(value: webappProvider),
      ],
      child: OrchestratorApp(registry: registry),
    ),
  );
}

/// Create one instance per registered webapp and set up the default layout.
void _createInitialInstances(
  WebappRegistry registry,
  WebappProvider webappProvider,
  SplashProvider splashProvider,
  LayoutProvider layoutProvider,
) {
  final requiredInstanceIds = <String>{};

  for (final reg in registry.all) {
    // Center-panel apps are created on demand (e.g., on step-selected)
    if (reg.preferredPosition == PanelPosition.center) continue;

    final instance = webappProvider.createInstance(reg.id);
    requiredInstanceIds.add(instance.instanceId);
  }

  // Tell splash provider which instances must be ready
  splashProvider.setRequiredInstances(requiredInstanceIds);

  // Fallback: dismiss splash after 3 seconds even if not all ready
  Future.delayed(const Duration(seconds: 3), () {
    splashProvider.dismiss();
  });
}

class OrchestratorApp extends StatelessWidget {
  final WebappRegistry registry;

  const OrchestratorApp({super.key, required this.registry});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    return MaterialApp(
      title: 'Tercen',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        body: OrchestratorScreen(registry: registry),
      ),
    );
  }
}
