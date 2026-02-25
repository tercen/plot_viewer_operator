import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_colors_dark.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../domain/models/tree_node.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/theme_provider.dart';

/// PROJECTS section: the interactive tree view.
class ProjectsSection extends StatelessWidget {
  const ProjectsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final mutedColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;

    if (provider.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (provider.error != null) {
      return Text(
        provider.error!,
        style: AppTextStyles.bodySmall.copyWith(
          color: isDark ? AppColorsDark.error : AppColors.error,
        ),
      );
    }

    final projects = provider.filteredProjects;

    if (projects.isEmpty) {
      return Text(
        provider.searchQuery.isNotEmpty ? 'No results' : 'No projects',
        style: AppTextStyles.bodySmall.copyWith(color: mutedColor),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final project in projects) _TreeNodeTile(node: project, depth: 0),
      ],
    );
  }
}

/// A single tree node row with icon, name, expand/collapse, and indentation.
class _TreeNodeTile extends StatelessWidget {
  final TreeNode node;
  final int depth;

  const _TreeNodeTile({required this.node, required this.depth});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final textColor = isDark ? AppColorsDark.textPrimary : AppColors.textPrimary;
    final mutedColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;
    final selectedBg = isDark ? AppColorsDark.primarySurface : AppColors.primarySurface;
    final selectedBorder = isDark ? AppColorsDark.primary : AppColors.primary;
    final isExpanded = provider.isExpanded(node.id);
    final isSelected = node.type == TreeNodeType.dataStep && provider.selectedStepId == node.id;
    final isLoading = provider.isNodeLoading(node.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The node row
        InkWell(
          onTap: () {
            if (node.isLeaf) {
              provider.selectStep(node);
            } else {
              provider.toggleExpand(node.id, node.type);
            }
          },
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    color: selectedBg,
                    border: Border(left: BorderSide(width: 3, color: selectedBorder)),
                  )
                : null,
            padding: EdgeInsets.only(
              left: AppSpacing.sm + (depth * AppSpacing.md),
              right: AppSpacing.sm,
              top: AppSpacing.xs,
              bottom: AppSpacing.xs,
            ),
            child: Row(
              children: [
                // Expand/collapse chevron or spacer for leaf nodes
                if (node.isExpandable)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: isLoading
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : Icon(
                            isExpanded ? Icons.expand_more : Icons.chevron_right,
                            size: 16,
                            color: mutedColor,
                          ),
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: AppSpacing.xs),
                // Node type icon
                _nodeIcon(node.type, isDark),
                const SizedBox(width: AppSpacing.sm),
                // Node name
                Expanded(
                  child: Text(
                    node.name,
                    style: AppTextStyles.body.copyWith(
                      color: isSelected ? selectedBorder : textColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Children (when expanded)
        if (isExpanded && !isLoading) ...[
          if (provider.filteredChildrenOf(node.id).isEmpty)
            Padding(
              padding: EdgeInsets.only(left: AppSpacing.sm + ((depth + 1) * AppSpacing.md) + 16 + AppSpacing.xs),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(
                  node.type == TreeNodeType.project ? 'No workflows' : 'No data steps',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: mutedColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else
            for (final child in provider.filteredChildrenOf(node.id))
              _TreeNodeTile(node: child, depth: depth + 1),
        ],
      ],
    );
  }

  Widget _nodeIcon(TreeNodeType type, bool isDark) {
    final iconColor = isDark ? AppColorsDark.textSecondary : AppColors.textSecondary;
    switch (type) {
      case TreeNodeType.project:
        return FaIcon(FontAwesomeIcons.folder, size: 12, color: iconColor);
      case TreeNodeType.workflow:
        // tercen-Workflow custom icon — using a workflow-like icon from FontAwesome
        // In production, this would use the Tercen custom icon font.
        // For Phase 2 mock, we use a diagram-project icon as a recognizable placeholder.
        return FaIcon(FontAwesomeIcons.diagramProject, size: 12, color: iconColor);
      case TreeNodeType.dataStep:
        // tercen-Data-Step custom icon — using a cube icon as placeholder
        return FaIcon(FontAwesomeIcons.cube, size: 12, color: iconColor);
    }
  }
}
