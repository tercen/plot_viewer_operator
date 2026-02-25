import 'package:flutter/material.dart';
import 'package:widget_library/widget_library.dart';

/// Orientation for a drop zone.
enum DropZoneAxis { horizontal, vertical }

/// A spatial drop zone that accepts factor drags.
///
/// Positioned around the plot grid: X (below), Y (left), row facet (left strip),
/// column facet (top strip). Shows empty/drag-over/assigned states.
class DropZone extends StatelessWidget {
  final String label;
  final String role;
  final DropZoneAxis axis;
  final Factor? binding;
  final ValueChanged<Factor> onAccept;
  final VoidCallback onClear;

  const DropZone({
    super.key,
    required this.label,
    required this.role,
    required this.axis,
    required this.binding,
    required this.onAccept,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Factor>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;
        final isAssigned = binding != null;

        return Container(
          decoration: BoxDecoration(
            color: isDragOver
                ? AppColors.primaryBg
                : isAssigned
                    ? AppColors.white
                    : AppColors.neutral50,
            border: Border.all(
              color: isDragOver
                  ? AppColors.primary
                  : AppColors.neutral300,
              width: isDragOver ? 2.0 : 1.0,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: axis == DropZoneAxis.horizontal
              ? _buildHorizontalContent(isDragOver, isAssigned)
              : _buildVerticalContent(isDragOver, isAssigned),
        );
      },
    );
  }

  Widget _buildHorizontalContent(bool isDragOver, bool isAssigned) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAssigned) ...[
            Flexible(
              child: Tooltip(
                message: binding!.name,
                child: Text(
                  binding!.shortName,
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _ClearButton(onClear: onClear),
          ] else
            Text(
              isDragOver ? 'Drop here' : label,
              style: AppTextStyles.labelSmall.copyWith(
                color: isDragOver ? AppColors.primary : AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVerticalContent(bool isDragOver, bool isAssigned) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAssigned) ...[
            _ClearButton(onClear: onClear),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: Tooltip(
                message: binding!.name,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    binding!.shortName,
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ] else
            Flexible(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  isDragOver ? 'Drop here' : label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isDragOver ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  final VoidCallback onClear;
  const _ClearButton({required this.onClear});

  @override
  Widget build(BuildContext context) {
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
