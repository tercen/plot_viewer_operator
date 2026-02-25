import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_colors_dark.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../domain/models/factor.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/theme_provider.dart';

/// FACTORS section: the collapsible factor tree grouped by namespace.
class FactorsSection extends StatelessWidget {
  const FactorsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final mutedColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;

    if (provider.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
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

    // Empty state: no step selected
    if (!provider.hasStep) {
      return Text(
        'Select a data step in the project navigator',
        style: AppTextStyles.bodySmall.copyWith(
          color: mutedColor,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Empty state: step selected but no factors
    if (provider.factorCount == 0) {
      return Text(
        'No factors available for this step',
        style: AppTextStyles.bodySmall.copyWith(
          color: mutedColor,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final filtered = provider.filteredGroupedFactors;

    // Empty state: search matches nothing
    if (filtered.isEmpty && provider.searchQuery.isNotEmpty) {
      return Text(
        'No matching factors',
        style: AppTextStyles.bodySmall.copyWith(
          color: mutedColor,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Factor tree
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final ns in filtered.keys) ...[
          _NamespaceRow(namespace: ns),
          if (provider.isNamespaceExpanded(ns))
            for (final factor in filtered[ns]!)
              _FactorRow(factor: factor),
        ],
      ],
    );
  }
}

/// Namespace group header row with expand/collapse chevron.
class _NamespaceRow extends StatelessWidget {
  final String namespace;
  const _NamespaceRow({required this.namespace});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final textColor = isDark ? AppColorsDark.textPrimary : AppColors.textPrimary;
    final mutedColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;
    final isExpanded = provider.isNamespaceExpanded(namespace);

    return InkWell(
      onTap: () => provider.toggleNamespace(namespace),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: Icon(
                isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: mutedColor,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            FaIcon(FontAwesomeIcons.layerGroup, size: 12, color: mutedColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                namespace.isEmpty ? 'Factors' : namespace,
                style: AppTextStyles.body.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draggable factor leaf row with type icon and muted type label.
class _FactorRow extends StatelessWidget {
  final Factor factor;
  const _FactorRow({required this.factor});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final textColor = isDark ? AppColorsDark.textPrimary : AppColors.textPrimary;
    final mutedColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;
    final iconColor =
        isDark ? AppColorsDark.textSecondary : AppColors.textSecondary;

    final dragData = json.encode({'name': factor.name, 'type': factor.type});

    // Phase 2: Flutter Draggable for visual demonstration.
    // Phase 3: Replace with HTML5 native drag-and-drop for cross-iframe support.
    return Draggable<String>(
      data: dragData,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppColorsDark.surfaceElevated : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: isDark ? AppColorsDark.border : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _typeIcon(factor, iconColor),
              const SizedBox(width: AppSpacing.xs),
              Text(
                factor.shortName,
                style: AppTextStyles.bodySmall.copyWith(color: textColor),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _buildRow(textColor, mutedColor, iconColor),
      ),
      child: _buildRow(textColor, mutedColor, iconColor),
    );
  }

  Widget _buildRow(Color textColor, Color mutedColor, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.sm + AppSpacing.md, // Indent past namespace row
        right: AppSpacing.sm,
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          _typeIcon(factor, iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              factor.shortName,
              style: AppTextStyles.body.copyWith(color: textColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            factor.type,
            style: AppTextStyles.bodySmall.copyWith(color: mutedColor),
          ),
        ],
      ),
    );
  }

  static Widget _typeIcon(Factor factor, Color color) {
    return FaIcon(
      factor.isNumeric ? FontAwesomeIcons.hashtag : FontAwesomeIcons.font,
      size: 12,
      color: color,
    );
  }
}
