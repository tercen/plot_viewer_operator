import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sci_tercen_client/sci_service_factory_web.dart';

import 'core/theme/app_theme.dart';
import 'di/service_locator.dart';
import 'presentation/providers/app_state_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/screens/home_screen.dart';
import 'utils/message_helper.dart';

/// Global references so messages can reach providers after the app is running.
ThemeProvider? _themeProvider;
AppStateProvider? _appStateProvider;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Show waiting UI, then listen for init-context from orchestrator
  runApp(const _WaitingApp());

  MessageHelper.listen((type, payload) async {
    if (type == 'init-context') {
      try {
        final token = payload['token'] as String;
        final serviceUri = payload['serviceUri'] as String?;
        final themeMode = payload['themeMode'] as String? ?? 'light';

        final factory = await createServiceFactoryForWebApp(
          tercenToken: token,
          serviceUri: serviceUri,
        );

        setupServiceLocator(
          tercenFactory: factory,
        );

        runApp(FactorNavApp(initialThemeMode: themeMode));

        MessageHelper.postMessage('app-ready', {});
      } catch (e) {
        debugPrint('Tercen init failed: $e');
        MessageHelper.postMessage('app-error', {'message': '$e'});
        runApp(_ErrorApp(message: 'Initialization failed: $e'));
      }
    } else if (type == 'step-selected') {
      final workflowId = payload['workflowId'] as String?;
      final stepId = payload['stepId'] as String?;
      if (workflowId != null &&
          workflowId.isNotEmpty &&
          stepId != null &&
          stepId.isNotEmpty) {
        _appStateProvider?.onStepSelected(workflowId, stepId);
      }
    } else if (type == 'theme-changed') {
      final mode = payload['mode'] as String? ?? 'light';
      _themeProvider?.setFromModeName(mode);
    }
  });

  // Request credentials from orchestrator
  MessageHelper.postMessage('request-context', {});
}

class FactorNavApp extends StatelessWidget {
  final String initialThemeMode;

  const FactorNavApp({super.key, required this.initialThemeMode});

  @override
  Widget build(BuildContext context) {
    final themeProvider = ThemeProvider(
      initialMode:
          initialThemeMode == 'dark' ? ThemeMode.dark : ThemeMode.light,
    );
    _themeProvider = themeProvider;

    final appStateProvider = AppStateProvider();
    _appStateProvider = appStateProvider;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: appStateProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Factor Navigator',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeProvider.themeMode,
            debugShowCheckedModeBanner: false,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

/// Blank placeholder while waiting for init-context from orchestrator.
/// The orchestrator shows its own loading overlay over this iframe.
class _WaitingApp extends StatelessWidget {
  const _WaitingApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SizedBox.shrink(),
    );
  }
}

/// Displayed when initialization fails.
class _ErrorApp extends StatelessWidget {
  final String message;

  const _ErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Initialization Error',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
