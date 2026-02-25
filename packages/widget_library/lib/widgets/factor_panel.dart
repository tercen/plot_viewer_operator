import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/factor.dart';
import '../theme/app_colors.dart';
import '../theme/app_colors_dark.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Self-contained factor list panel with search, namespace grouping,
/// and draggable factor chips.
///
/// Manages its own search and expand/collapse state.
/// Each factor row is a `Draggable<Factor>`.
class FactorPanel extends StatefulWidget {
  final List<Factor> factors;
  final bool isLoading;
  final String? error;
  final VoidCallback? onClose;

  const FactorPanel({
    super.key,
    required this.factors,
    this.isLoading = false,
    this.error,
    this.onClose,
  });

  @override
  State<FactorPanel> createState() => _FactorPanelState();
}

class _FactorPanelState extends State<FactorPanel> {
  String _searchQuery = '';
  final Set<String> _expandedNamespaces = {};
  final _searchController = TextEditingController();

  @override
  void didUpdateWidget(FactorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factors != widget.factors) {
      // Auto-expand all namespaces when factors change
      _expandedNamespaces
        ..clear()
        ..addAll(_allNamespaces);
    }
  }

  @override
  void initState() {
    super.initState();
    _expandedNamespaces.addAll(_allNamespaces);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _allNamespaces {
    final ns = widget.factors.map((f) => f.namespace).toSet().toList();
    ns.sort((a, b) {
      if (a.isEmpty) return -1;
      if (b.isEmpty) return 1;
      return a.compareTo(b);
    });
    return ns;
  }

  Map<String, List<Factor>> get _filteredGroupedFactors {
    final query = _searchQuery.toLowerCase();
    final grouped = <String, List<Factor>>{};

    for (final factor in widget.factors) {
      if (query.isNotEmpty && !factor.name.toLowerCase().contains(query)) {
        continue;
      }
      grouped.putIfAbsent(factor.namespace, () => []).add(factor);
    }

    // Sort namespaces: empty first, then alphabetical
    final sorted = Map.fromEntries(
      grouped.entries.toList()
        ..sort((a, b) {
          if (a.key.isEmpty) return -1;
          if (b.key.isEmpty) return 1;
          return a.key.compareTo(b.key);
        }),
    );
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColorsDark.border : AppColors.border;
    final bgColor = isDark ? AppColorsDark.surface : AppColors.surface;

    return Container(
      width: AppSpacing.panelWidth,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(isDark),
          _buildSearch(isDark),
          Expanded(child: _buildFactorList(isDark)),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final headerBg = isDark ? AppColorsDark.surfaceElevated : AppColors.surfaceElevated;
    final headerTextColor = isDark ? AppColorsDark.neutral300 : AppColors.textMuted;
    final borderColor = isDark ? AppColorsDark.border : AppColors.border;

    return Column(
      children: [
        Container(
          color: headerBg,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              FaIcon(FontAwesomeIcons.layerGroup, size: 12, color: headerTextColor),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'FACTORS',
                style: AppTextStyles.sectionHeader.copyWith(color: headerTextColor),
              ),
              const Spacer(),
              if (widget.onClose != null)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    onPressed: widget.onClose,
                    icon: Icon(Icons.close, size: 14, color: headerTextColor),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Close',
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: borderColor),
      ],
    );
  }

  Widget _buildSearch(bool isDark) {
    final mutedColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Filter factors...',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, size: 16, color: mutedColor),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _expandedNamespaces
                        ..clear()
                        ..addAll(_allNamespaces);
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.xl,
                    minHeight: AppSpacing.xl,
                  ),
                )
              : null,
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
            if (value.isNotEmpty) {
              // Auto-expand matching namespaces
              _expandedNamespaces
                ..clear()
                ..addAll(_filteredGroupedFactors.keys);
            }
          });
        },
      ),
    );
  }

  Widget _buildFactorList(bool isDark) {
    final mutedColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;

    if (widget.isLoading) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (widget.error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          widget.error!,
          style: AppTextStyles.bodySmall.copyWith(
            color: isDark ? AppColorsDark.error : AppColors.error,
          ),
        ),
      );
    }

    if (widget.factors.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'No factors available',
          style: AppTextStyles.bodySmall.copyWith(
            color: mutedColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final filtered = _filteredGroupedFactors;

    if (filtered.isEmpty && _searchQuery.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'No matching factors',
          style: AppTextStyles.bodySmall.copyWith(
            color: mutedColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final ns in filtered.keys) ...[
          _NamespaceRow(
            namespace: ns,
            isExpanded: _expandedNamespaces.contains(ns),
            onToggle: () => setState(() {
              if (_expandedNamespaces.contains(ns)) {
                _expandedNamespaces.remove(ns);
              } else {
                _expandedNamespaces.add(ns);
              }
            }),
          ),
          if (_expandedNamespaces.contains(ns))
            for (final factor in filtered[ns]!)
              _FactorRow(factor: factor),
        ],
      ],
    );
  }
}

class _NamespaceRow extends StatelessWidget {
  final String namespace;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _NamespaceRow({
    required this.namespace,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColorsDark.textPrimary : AppColors.textPrimary;
    final mutedColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;

    return InkWell(
      onTap: onToggle,
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

class _FactorRow extends StatelessWidget {
  final Factor factor;
  const _FactorRow({required this.factor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColorsDark.textPrimary : AppColors.textPrimary;
    final mutedColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;
    final iconColor = isDark ? AppColorsDark.textSecondary : AppColors.textSecondary;

    return Draggable<Factor>(
      data: factor,
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
        left: AppSpacing.sm + AppSpacing.md,
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
