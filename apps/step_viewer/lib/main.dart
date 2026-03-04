import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sci_tercen_client/sci_service_factory_web.dart';
import 'package:widget_library/widget_library.dart';

import 'di/service_locator.dart';
import 'presentation/providers/plot_state_provider.dart';
import 'presentation/widgets/plot_area.dart';
import 'presentation/widgets/top_toolbar.dart';
import 'services/ggrs_service_v2.dart';
import 'services/ggrs_service_v3.dart';
import 'utils/message_helper.dart';

/// Global reference so messages can reach the provider after the app is running.
PlotStateProvider? _plotStateProvider;
GgrsServiceV3? _ggrsService;

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

        setupServiceLocator(tercenFactory: factory);

        // Pass credentials to GGRS (no-op in mock mode, kept for future Phase 2)
        serviceLocator<GgrsServiceV3>().setTercenCredentials(
          serviceUri ?? '',
          token,
        );

        runApp(StepViewerApp(initialThemeMode: themeMode));

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
        _plotStateProvider?.onStepSelected(workflowId, stepId);
      }
    } else if (type == 'theme-changed') {
      // Theme changes handled by orchestrator's ThemeMode — no-op for now
    } else if (type == 'load-facets') {
      // Background facet loading triggered by viewport scroll/zoom
      debugPrint('[main] ========== RECEIVED load-facets MESSAGE ==========');
      final containerId = payload['containerId'] as String?;
      final newRectangles = payload['newRectangles'] as List<dynamic>?;
      final neededRange = payload['neededRange'] as Map<String, dynamic>?;
      final loadId = payload['loadId'] as int?;

      debugPrint('[main] containerId: $containerId');
      debugPrint('[main] newRectangles: $newRectangles');
      debugPrint('[main] neededRange: $neededRange');
      debugPrint('[main] loadId: $loadId');
      debugPrint('[main] _ggrsService: ${_ggrsService != null ? "available" : "NULL"}');

      if (containerId != null && newRectangles != null && neededRange != null && loadId != null && _ggrsService != null) {
        debugPrint('[main] → Calling loadFacetsInBackground with ${newRectangles.length} rectangle(s)');
        await _ggrsService!.loadFacetsInBackground(containerId, newRectangles, neededRange, loadId);
        debugPrint('[main] → loadFacetsInBackground completed');
      } else {
        debugPrint('[main] ⚠️ Missing required fields or service, skipping');
      }
    }
  });

  // Request credentials from orchestrator
  MessageHelper.postMessage('request-context', {});
}

class StepViewerApp extends StatelessWidget {
  final String initialThemeMode;

  const StepViewerApp({super.key, required this.initialThemeMode});

  @override
  Widget build(BuildContext context) {
    final plotState = PlotStateProvider();
    _plotStateProvider = plotState;

    final ggrsService = serviceLocator<GgrsServiceV3>();
    _ggrsService = ggrsService;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: plotState),
        ChangeNotifierProvider.value(value: ggrsService),
      ],
      child: MaterialApp(
        title: 'Step Viewer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: initialThemeMode == 'dark' ? ThemeMode.dark : ThemeMode.light,
        home: const _StepViewerScreen(),
      ),
    );
  }
}

class _StepViewerScreen extends StatelessWidget {
  const _StepViewerScreen();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlotStateProvider>();

    return Scaffold(
      body: Column(
        children: [
          const TopToolbar(),
          Expanded(
            child: Row(
              children: [
                // Collapsible factor panel sidebar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  width: state.isFactorPanelOpen ? AppSpacing.panelWidth : 0,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(),
                  child: state.isFactorPanelOpen
                      ? FactorPanel(
                          factors: state.factors,
                          isLoading: state.isFactorsLoading,
                          error: state.factorsError,
                          onClose: () => state.toggleFactorPanel(),
                        )
                      : const SizedBox.shrink(),
                ),
                // Plot area (takes remaining width)
                const Expanded(child: PlotArea()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Blank placeholder while waiting for init-context from orchestrator.
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
