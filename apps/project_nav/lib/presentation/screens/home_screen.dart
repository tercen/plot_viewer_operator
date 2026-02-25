import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_dark.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/left_panel/left_panel.dart';
import '../widgets/left_panel/search_section.dart';
import '../widgets/left_panel/projects_section.dart';
import '../widgets/left_panel/info_section.dart';

/// Home screen: assembles AppShell with search, projects tree, and info sections.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<AppStateProvider>().loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      appTitle: 'Project Navigator',
      appIcon: FontAwesomeIcons.folder,
      sections: const [
        PanelSection(
          icon: Icons.search,
          label: 'SEARCH',
          content: SearchSection(),
        ),
        PanelSection(
          icon: Icons.folder,
          label: 'PROJECTS',
          content: ProjectsSection(),
        ),
        PanelSection(
          icon: Icons.info_outline,
          label: 'INFO',
          content: InfoSection(),
        ),
      ],
      content: const _MainContent(),
    );
  }
}

/// Main content area. Since the project navigator is a tool window app,
/// the main content shows the currently selected step or an empty state.
class _MainContent extends StatelessWidget {
  const _MainContent();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final bgColor = isDark ? AppColorsDark.background : AppColors.background;
    final textColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;
    final iconColor = (isDark ? AppColorsDark.textMuted : AppColors.textMuted).withValues(alpha: 0.5);

    if (provider.selectedStepId != null) {
      final stepName = _findStepName(provider);
      return Container(
        color: bgColor,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selected Step',
              style: AppTextStyles.label.copyWith(color: textColor),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              stepName ?? provider.selectedStepId!,
              style: AppTextStyles.h3.copyWith(
                color: isDark ? AppColorsDark.textPrimary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'ID: ${provider.selectedStepId}',
              style: AppTextStyles.bodySmall.copyWith(color: textColor),
            ),
          ],
        ),
      );
    }

    return Container(
      color: bgColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.folder, size: 48, color: iconColor),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Select a data step',
              style: AppTextStyles.body.copyWith(color: textColor),
            ),
          ],
        ),
      ),
    );
  }

  String? _findStepName(AppStateProvider provider) {
    for (final project in provider.projects) {
      for (final wf in provider.childrenOf(project.id)) {
        for (final step in provider.childrenOf(wf.id)) {
          if (step.id == provider.selectedStepId) return step.name;
        }
      }
    }
    return null;
  }
}
