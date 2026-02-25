import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import 'package:widget_library/widget_library.dart';

import '../../services/ggrs_service_v2.dart';
import '../providers/plot_state_provider.dart';

/// Embeds the GGRS 6-layer DOM container via HtmlElementView and triggers
/// rendering whenever bindings, geom type, theme, or size change.
class GgrsPlotView extends StatefulWidget {
  const GgrsPlotView({super.key});

  @override
  State<GgrsPlotView> createState() => _GgrsPlotViewState();
}

class _GgrsPlotViewState extends State<GgrsPlotView> {
  static int _nextViewId = 0;

  late final String _viewType;
  late final String _containerId;
  late final PlotStateProvider _plotState;
  double _lastWidth = 0;
  double _lastHeight = 0;
  bool _mounted = false;

  @override
  void initState() {
    super.initState();
    final viewId = _nextViewId++;
    _containerId = 'ggrs-container-$viewId';
    _viewType = 'ggrs-plot-view-$viewId';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int id) {
        final container = web.document.createElement('div') as web.HTMLDivElement
          ..id = _containerId
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.position = 'relative'
          ..style.overflow = 'hidden';
        return container;
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Attach listener once — didChangeDependencies can fire multiple times
    // but the provider reference is stable, so we only add on first call.
    if (!_mounted) {
      _plotState = context.read<PlotStateProvider>();
      _plotState.addListener(_onStateChanged);
    }
  }

  @override
  void dispose() {
    _plotState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (_mounted && _lastWidth > 0 && _lastHeight > 0) {
      _scheduleRender();
    }
  }

  void _scheduleRender() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ggrs = context.read<GgrsServiceV2>();
      final state = context.read<PlotStateProvider>();
      ggrs.render(_containerId, state, _lastWidth, _lastHeight);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        if (w > 0 && h > 0 && (w != _lastWidth || h != _lastHeight || !_mounted)) {
          _lastWidth = w;
          _lastHeight = h;
          _mounted = true;
          _scheduleRender();
        }

        return Stack(
          children: [
            SizedBox.expand(
              child: HtmlElementView(viewType: _viewType),
            ),
            // Progress / error overlay
            Consumer<GgrsServiceV2>(
              builder: (context, ggrs, _) {
                if (ggrs.error != null) {
                  return Positioned(
                    bottom: AppSpacing.sm,
                    left: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                        border: Border.all(color: AppColors.error),
                      ),
                      child: Text(
                        ggrs.error!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }
                if (ggrs.isRendering) {
                  return Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: _PhaseIndicator(phase: ggrs.phase),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        );
      },
    );
  }
}

/// Compact phase-aware progress indicator shown top-right during rendering.
class _PhaseIndicator extends StatelessWidget {
  final RenderPhase phase;

  const _PhaseIndicator({required this.phase});

  @override
  Widget build(BuildContext context) {
    final label = switch (phase) {
      RenderPhase.chrome => 'Chrome',
      RenderPhase.cubeQuery => 'Query',
      RenderPhase.streaming => 'Streaming',
      _ => '',
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.neutral800.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.white),
          ),
        ],
      ),
    );
  }
}
