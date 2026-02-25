import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_dark.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/models/webapp_registration.dart';
import '../providers/layout_provider.dart';
import '../providers/theme_provider.dart';
import 'icon_strip_button.dart';

/// Vertical icon strip for the left edge of the workbench.
///
/// Multiple icons can be active simultaneously (checkbox behavior).
class LeftIconStrip extends StatelessWidget {
  final List<WebappRegistration> webapps;
  final void Function(String appId) onToggle;

  const LeftIconStrip({
    super.key,
    required this.webapps,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LayoutProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    return Container(
      width: AppSpacing.iconStripWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColorsDark.neutral100 : AppColors.neutral100,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColorsDark.borderLight : AppColors.borderLight,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xs),
          for (final webapp in webapps)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.xs / 2,
                horizontal: AppSpacing.xs,
              ),
              child: IconStripButton(
                icon: webapp.icon,
                tooltip: webapp.name,
                isActive: layout.isToolStripOpen(webapp.id),
                onTap: () => onToggle(webapp.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal icon strip for the bottom edge of the workbench.
class BottomIconStrip extends StatelessWidget {
  final List<WebappRegistration> webapps;

  const BottomIconStrip({super.key, required this.webapps});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LayoutProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    return Container(
      height: AppSpacing.bottomIconStripHeight,
      decoration: BoxDecoration(
        color: isDark ? AppColorsDark.neutral100 : AppColors.neutral100,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColorsDark.borderLight : AppColors.borderLight,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.xs),
          for (final webapp in webapps)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs / 2,
                vertical: 2,
              ),
              child: IconStripButton(
                icon: webapp.icon,
                tooltip: webapp.name,
                isActive: layout.isBottomPanelVisible &&
                    layout.activeBottomAppId == webapp.id,
                onTap: () => layout.toggleBottomPanel(webapp.id),
              ),
            ),
        ],
      ),
    );
  }
}
