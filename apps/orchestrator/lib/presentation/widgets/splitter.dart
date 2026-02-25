import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_dark.dart';
import '../../core/theme/app_spacing.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

/// Draggable divider between two adjacent panels.
///
/// Horizontal splitter: 4px tall, full width, vertical drag.
/// Vertical splitter: 4px wide, full height, horizontal drag.
class Splitter extends StatefulWidget {
  final Axis axis;
  final ValueChanged<double> onDrag;

  const Splitter({
    super.key,
    required this.axis,
    required this.onDrag,
  });

  @override
  State<Splitter> createState() => _SplitterState();
}

class _SplitterState extends State<Splitter> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final isActive = _isHovered || _isDragging;
    final color = isActive
        ? (isDark ? AppColorsDark.neutral400 : AppColors.neutral400)
        : (isDark ? AppColorsDark.borderLight : AppColors.borderLight);

    final isHorizontal = widget.axis == Axis.horizontal;

    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (details) {
          widget.onDrag(
            isHorizontal ? details.delta.dy : details.delta.dx,
          );
        },
        onPanEnd: (_) => setState(() => _isDragging = false),
        child: Container(
          width: isHorizontal ? double.infinity : AppSpacing.splitterThickness,
          height: isHorizontal ? AppSpacing.splitterThickness : double.infinity,
          color: color,
        ),
      ),
    );
  }
}
