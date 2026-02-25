import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_dark.dart';
import '../../core/theme/app_spacing.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

/// A single toggle button within an icon strip.
///
/// Active state: primary-surface background, primary icon color.
/// Inactive state: transparent background, neutral-600 icon color.
class IconStripButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const IconStripButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    final bgColor = isActive
        ? (isDark ? AppColorsDark.primarySurface : AppColors.primarySurface)
        : Colors.transparent;
    final iconColor = isActive
        ? (isDark ? AppColorsDark.primary : AppColors.primary)
        : (isDark ? AppColorsDark.neutral500 : AppColors.neutral600);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          width: AppSpacing.iconStripWidth - 8,
          height: AppSpacing.iconStripWidth - 8,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );
  }
}
