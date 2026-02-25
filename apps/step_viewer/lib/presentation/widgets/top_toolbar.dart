import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:widget_library/widget_library.dart';
import '../providers/plot_state_provider.dart';

/// Compact toolbar above the plot with factor panel toggle and geom/theme selectors.
class TopToolbar extends StatelessWidget {
  const TopToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlotStateProvider>();

    return Container(
      height: AppSpacing.headerHeight,
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          // Factor panel toggle
          Tooltip(
            message: state.isFactorPanelOpen ? 'Hide factors' : 'Show factors',
            child: InkWell(
              onTap: () => state.toggleFactorPanel(),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: Container(
                width: AppSpacing.controlHeightSm,
                height: AppSpacing.controlHeightSm,
                decoration: BoxDecoration(
                  color: state.isFactorPanelOpen
                      ? AppColors.primaryBg
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Center(
                  child: FaIcon(
                    FontAwesomeIcons.layerGroup,
                    size: 14,
                    color: state.isFactorPanelOpen
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Separator
          Container(width: 1, height: 24, color: AppColors.borderSubtle),
          const SizedBox(width: AppSpacing.sm),
          // Geom type selector
          _GeomSelector(),
          const SizedBox(width: AppSpacing.sm),
          // Theme selector
          _ThemeSelector(),
        ],
      ),
    );
  }
}

class _GeomSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlotStateProvider>();
    return _CompactDropdown<String>(
      value: state.geomType,
      items: const {
        'point': 'Point',
        'line': 'Line',
        'bar': 'Bar',
        'heatmap': 'Heatmap',
      },
      onChanged: (v) => state.setGeomType(v),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlotStateProvider>();
    return _CompactDropdown<String>(
      value: state.plotTheme,
      items: const {
        'gray': 'Gray',
        'bw': 'B&W',
        'minimal': 'Minimal',
      },
      onChanged: (v) => state.setPlotTheme(v),
    );
  }
}

class _CompactDropdown<T> extends StatelessWidget {
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  const _CompactDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.controlHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.neutral50,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        isDense: true,
        style: AppTextStyles.label.copyWith(color: AppColors.textPrimary),
        items: items.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
