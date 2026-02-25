import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:widget_library/widget_library.dart';
import '../providers/plot_state_provider.dart';
import 'drop_zone.dart';
import 'ggrs_plot_view.dart';

/// The main plot area with spatial drop zones around a mock grid.
///
/// Layout:
/// ```
///     [+ col drop]  (narrow, only when col facets exist)
///     [col strip N] (outermost col facet)
///     [col strip 1] (innermost col facet, closest to grid)
///                   — or [col facet drop] when empty —
/// [+row][row N][row 1] [y axis] [     grid     ]
///                                [    x axis    ]
/// ```
///
/// Facets grow outward: col facets upward, row facets leftward.
class PlotArea extends StatelessWidget {
  const PlotArea({super.key});

  static const double _axisDropWidth = 36.0;
  static const double _axisDropHeight = 32.0;
  static const double _facetStripSize = 28.0; // assigned facet strip thickness
  static const double _facetDropSize = 36.0; // empty "drop here" zone thickness
  static const double _facetAddSize = 24.0; // narrow "+" zone for adding more

  @override
  Widget build(BuildContext context) {
    return Consumer<PlotStateProvider>(
      builder: (context, state, _) {
        // Calculate left spacer width (row facets + y axis + gaps)
        final leftWidth = _rowFacetsWidth(state) + _axisDropWidth + AppSpacing.xs;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Col facet area (horizontal strips at top, growing upward)
              ..._buildColFacetArea(state, leftWidth),
              // X axis (immediately below col facets, aligned to grid)
              SizedBox(
                height: _axisDropHeight,
                child: Row(
                  children: [
                    SizedBox(width: leftWidth),
                    Expanded(
                      child: DropZone(
                        label: 'X axis',
                        role: 'x',
                        axis: DropZoneAxis.horizontal,
                        binding: state.xBinding,
                        onAccept: (f) => state.setBinding('x', f),
                        onClear: () => state.clearBinding('x'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Main row: row facets + y axis + grid
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Row facet area (vertical strips, growing leftward)
                    ..._buildRowFacetArea(state),
                    // Y axis
                    SizedBox(
                      width: _axisDropWidth,
                      child: DropZone(
                        label: 'Y axis',
                        role: 'y',
                        axis: DropZoneAxis.vertical,
                        binding: state.yBinding,
                        onAccept: (f) => state.setBinding('y', f),
                        onClear: () => state.clearBinding('y'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // Grid — GGRS WASM plot
                    const Expanded(child: GgrsPlotView()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Total width of the row facet area (strips + add zone + gaps).
  double _rowFacetsWidth(PlotStateProvider state) {
    if (state.rowFacetBindings.isEmpty) {
      return _facetDropSize + AppSpacing.xs; // one empty drop zone + gap
    }
    // Narrow "+" zone + each assigned strip + gaps
    return _facetAddSize +
        AppSpacing.xs +
        state.rowFacetBindings.length * (_facetStripSize + AppSpacing.xs);
  }

  /// Build the column facet area: horizontal strips stacking at the top.
  List<Widget> _buildColFacetArea(PlotStateProvider state, double leftWidth) {
    final colFacets = state.colFacetBindings;
    final widgets = <Widget>[];

    if (colFacets.isEmpty) {
      // Single empty drop zone spanning the grid width
      widgets.add(
        SizedBox(
          height: _facetDropSize,
          child: Row(
            children: [
              SizedBox(width: leftWidth),
              Expanded(
                child: _FacetDropZone(
                  label: 'Col facet',
                  role: 'col_facet',
                  axis: DropZoneAxis.horizontal,
                  onAccept: (f) => state.addFacet('col_facet', f),
                ),
              ),
            ],
          ),
        ),
      );
      widgets.add(const SizedBox(height: AppSpacing.xs));
    } else {
      // Narrow "+" zone at the top (outermost)
      widgets.add(
        SizedBox(
          height: _facetAddSize,
          child: Row(
            children: [
              SizedBox(width: leftWidth),
              Expanded(
                child: _FacetDropZone(
                  label: '+',
                  role: 'col_facet',
                  axis: DropZoneAxis.horizontal,
                  narrow: true,
                  onAccept: (f) => state.addFacet('col_facet', f),
                ),
              ),
            ],
          ),
        ),
      );
      widgets.add(const SizedBox(height: AppSpacing.xs));
      // Assigned strips (outermost first = last added, innermost last = first added)
      for (int i = colFacets.length - 1; i >= 0; i--) {
        widgets.add(
          SizedBox(
            height: _facetStripSize,
            child: Row(
              children: [
                SizedBox(width: leftWidth),
                Expanded(
                  child: _AssignedFacetStrip(
                    binding: colFacets[i],
                    axis: DropZoneAxis.horizontal,
                    onClear: () => state.removeFacet('col_facet', i),
                  ),
                ),
              ],
            ),
          ),
        );
        widgets.add(const SizedBox(height: AppSpacing.xs));
      }
    }
    return widgets;
  }

  /// Build the row facet area: vertical strips growing leftward.
  List<Widget> _buildRowFacetArea(PlotStateProvider state) {
    final rowFacets = state.rowFacetBindings;
    final widgets = <Widget>[];

    if (rowFacets.isEmpty) {
      // Single empty drop zone
      widgets.add(
        SizedBox(
          width: _facetDropSize,
          child: _FacetDropZone(
            label: 'Row facet',
            role: 'row_facet',
            axis: DropZoneAxis.vertical,
            onAccept: (f) => state.addFacet('row_facet', f),
          ),
        ),
      );
      widgets.add(const SizedBox(width: AppSpacing.xs));
    } else {
      // Narrow "+" zone on the far left (outermost)
      widgets.add(
        SizedBox(
          width: _facetAddSize,
          child: _FacetDropZone(
            label: '+',
            role: 'row_facet',
            axis: DropZoneAxis.vertical,
            narrow: true,
            onAccept: (f) => state.addFacet('row_facet', f),
          ),
        ),
      );
      widgets.add(const SizedBox(width: AppSpacing.xs));
      // Assigned strips (outermost first = last added, innermost last = first added)
      for (int i = rowFacets.length - 1; i >= 0; i--) {
        widgets.add(
          SizedBox(
            width: _facetStripSize,
            child: _AssignedFacetStrip(
              binding: rowFacets[i],
              axis: DropZoneAxis.vertical,
              onClear: () => state.removeFacet('row_facet', i),
            ),
          ),
        );
        widgets.add(const SizedBox(width: AppSpacing.xs));
      }
    }
    return widgets;
  }
}

/// Empty drop zone for adding a facet factor.
class _FacetDropZone extends StatelessWidget {
  final String label;
  final String role;
  final DropZoneAxis axis;
  final bool narrow;
  final ValueChanged<Factor> onAccept;

  const _FacetDropZone({
    required this.label,
    required this.role,
    required this.axis,
    this.narrow = false,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Factor>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, _) {
        final isDragOver = candidateData.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: isDragOver ? AppColors.primaryBg : AppColors.neutral50,
            border: Border.all(
              color: isDragOver ? AppColors.primary : AppColors.neutral300,
              width: isDragOver ? 2.0 : 1.0,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          alignment: Alignment.center,
          child: axis == DropZoneAxis.vertical
              ? RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    isDragOver ? 'Drop here' : label,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: isDragOver ? AppColors.primary : AppColors.textMuted,
                    ),
                  ),
                )
              : Text(
                  isDragOver ? 'Drop here' : label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isDragOver ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
        );
      },
    );
  }
}

/// An assigned facet strip showing the factor name and a clear button.
class _AssignedFacetStrip extends StatelessWidget {
  final Factor binding;
  final DropZoneAxis axis;
  final VoidCallback onClear;

  const _AssignedFacetStrip({
    required this.binding,
    required this.axis,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: binding.name,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.neutral200,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: AppColors.neutral300),
        ),
        child: axis == DropZoneAxis.horizontal
            ? _horizontalContent()
            : _verticalContent(),
      ),
    );
  }

  Widget _horizontalContent() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          binding.shortName,
          style: AppTextStyles.label.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _clearButton(),
      ],
    );
  }

  Widget _verticalContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _clearButton(),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: Center(
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                binding.shortName,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _clearButton() {
    return SizedBox(
      width: 18,
      height: 18,
      child: IconButton(
        onPressed: onClear,
        icon: const Icon(Icons.close, size: 12),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        color: AppColors.textMuted,
        tooltip: 'Clear',
      ),
    );
  }
}
