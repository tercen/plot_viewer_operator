import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_dark.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/models/webapp_registration.dart';
import '../../services/webapp_registry.dart';
import '../providers/layout_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/webapp_provider.dart';
import 'icon_strip.dart';
import 'panel_host.dart';
import 'splitter.dart';

/// The full workbench layout (v3.0 multi-tool-strip model).
///
/// Structure:
/// ```
/// ┌──────────────────────────────────────────────────────┐
/// │  Toolbar (fixed height)                               │
/// ├──┬──────────┬┬──────────┬┬───────────────────────────┤
/// │  │          ││          ││ Content header [1][2][3]   │
/// │I │ Tool A   ││ Tool B   ││───────────────────────────│
/// │C │          ││          ││                            │
/// │O │          ││          ││  Content grid              │
/// │N │          ││          ││                            │
/// ├──┼──────────┴┴──────────┴┴───────────────────────────┤
/// │  Bottom icon strip                                    │
/// │  Bottom panel (collapsible)                           │
/// └──────────────────────────────────────────────────────┘
/// ```
class Workbench extends StatelessWidget {
  final WebappRegistry registry;

  const Workbench({super.key, required this.registry});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LayoutProvider>();
    final webappProvider = context.watch<WebappProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    final leftWebapps = registry
        .getByPosition(PanelPosition.left)
        .where((w) => w.showInIconStrip)
        .toList();
    final bottomWebapps = registry.getByPosition(PanelPosition.bottom);

    final toolbarInstanceId = webappProvider.getInstanceIdForApp('toolbar');

    // Build instance ID map for all bottom webapps (radio-toggle, kept alive)
    final bottomInstanceIds = <String, String?>{
      for (final w in bottomWebapps)
        w.id: webappProvider.getInstanceIdForApp(w.id),
    };

    return Column(
      children: [
        // Toolbar (fixed height)
        Container(
          height: AppSpacing.toolbarHeight,
          decoration: BoxDecoration(
            color: isDark ? AppColorsDark.surface : AppColors.white,
            border: Border(
              bottom: BorderSide(
                color:
                    isDark ? AppColorsDark.borderLight : AppColors.borderLight,
              ),
            ),
          ),
          child: PanelHost(instanceId: toolbarInstanceId),
        ),
        // Body
        Expanded(
          child: Column(
            children: [
              // Main row (icon strip + tool strips + content area)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bodyWidth = constraints.maxWidth;
                    return Row(
                      children: [
                        // Left icon strip
                        LeftIconStrip(
                          webapps: leftWebapps,
                          onToggle: (appId) {
                            final availableWidth =
                                bodyWidth - AppSpacing.iconStripWidth;
                            layout.toggleToolStrip(appId,
                                availableWidth: availableWidth);
                          },
                        ),
                        // Dynamic tool strips — one per open tool, in open-order
                        for (final appId in layout.openToolStrips) ...[
                          SizedBox(
                            width: layout.toolStripWidth(appId),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColorsDark.surface
                                    : AppColors.white,
                                border: Border(
                                  right: BorderSide(
                                    color: isDark
                                        ? AppColorsDark.borderLight
                                        : AppColors.borderLight,
                                  ),
                                ),
                              ),
                              child: PanelHost(
                                instanceId: webappProvider
                                    .getInstanceIdForApp(appId),
                              ),
                            ),
                          ),
                          Splitter(
                            axis: Axis.vertical,
                            onDrag: (delta) {
                              final currentWidth =
                                  layout.toolStripWidth(appId);
                              // Dynamic max: prevent content from shrinking
                              // below minimum
                              final maxWidth = bodyWidth -
                                  AppSpacing.iconStripWidth -
                                  layout.totalToolStripWidth +
                                  currentWidth -
                                  AppSpacing.minContentWidth;
                              layout.setToolStripWidth(
                                appId,
                                currentWidth + delta,
                                maxWidth: maxWidth,
                              );
                            },
                          ),
                        ],
                        // Center content area
                        Expanded(
                          child: _ContentArea(
                            isDark: isDark,
                            layout: layout,
                            webappProvider: webappProvider,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // Bottom region (unchanged from v2.0)
              if (bottomWebapps.isNotEmpty) ...[
                BottomIconStrip(webapps: bottomWebapps),
                if (layout.isBottomPanelVisible) ...[
                  Splitter(
                    axis: Axis.horizontal,
                    onDrag: (delta) {
                      layout.setBottomPanelHeight(
                          layout.bottomPanelHeight - delta);
                    },
                  ),
                  SizedBox(
                    height: layout.bottomPanelHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            isDark ? AppColorsDark.surface : AppColors.white,
                        border: Border(
                          top: BorderSide(
                            color: isDark
                                ? AppColorsDark.borderLight
                                : AppColors.borderLight,
                          ),
                        ),
                      ),
                      child: Stack(
                        children: [
                          for (final entry in bottomInstanceIds.entries)
                            Visibility(
                              visible:
                                  entry.key == layout.activeBottomAppId,
                              maintainState: true,
                              maintainAnimation: true,
                              maintainSize: true,
                              child:
                                  PanelHost(instanceId: entry.value),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Content area: header with layout toggle + grid of content apps.
class _ContentArea extends StatelessWidget {
  final bool isDark;
  final LayoutProvider layout;
  final WebappProvider webappProvider;

  const _ContentArea({
    required this.isDark,
    required this.layout,
    required this.webappProvider,
  });

  @override
  Widget build(BuildContext context) {
    final contentIds = layout.contentInstanceIds;

    return Container(
      color: isDark ? AppColorsDark.background : AppColors.white,
      child: Column(
        children: [
          // Content header with layout toggle
          _ContentHeader(
            isDark: isDark,
            columns: layout.contentColumns,
            onColumnsChanged: layout.setContentColumns,
            contentCount: contentIds.length,
          ),
          // Content grid
          Expanded(
            child: _ContentGrid(
              columns: layout.contentColumns,
              children: [
                for (final instanceId in contentIds)
                  PanelHost(instanceId: instanceId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin header bar above the content area with layout toggle buttons.
class _ContentHeader extends StatelessWidget {
  final bool isDark;
  final int columns;
  final ValueChanged<int> onColumnsChanged;
  final int contentCount;

  const _ContentHeader({
    required this.isDark,
    required this.columns,
    required this.onColumnsChanged,
    required this.contentCount,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isDark ? AppColorsDark.borderLight : AppColors.borderLight;
    final bgColor = isDark ? AppColorsDark.surface : AppColors.neutral50;

    return Container(
      height: AppSpacing.contentHeaderHeight,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          // Layout toggle buttons
          for (final n in [1, 2, 3])
            _LayoutButton(
              columns: n,
              isActive: columns == n,
              isDark: isDark,
              onTap: () => onColumnsChanged(n),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// A single layout toggle button (shows a grid icon for the column count).
class _LayoutButton extends StatelessWidget {
  final int columns;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _LayoutButton({
    required this.columns,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  IconData get _icon {
    switch (columns) {
      case 1:
        return Icons.crop_square;
      case 2:
        return Icons.view_column_outlined;
      default:
        return Icons.grid_view;
    }
  }

  String get _tooltip {
    switch (columns) {
      case 1:
        return 'Single';
      case 2:
        return 'Side by side';
      default:
        return '$columns columns';
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark ? AppColorsDark.primary : AppColors.primary;
    final inactiveColor =
        isDark ? AppColorsDark.neutral500 : AppColors.neutral500;
    final activeBg =
        isDark ? AppColorsDark.primarySurface : AppColors.primarySurface;

    return Tooltip(
      message: _tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          width: 28,
          height: 24,
          decoration: BoxDecoration(
            color: isActive ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(
            _icon,
            size: 16,
            color: isActive ? activeColor : inactiveColor,
          ),
        ),
      ),
    );
  }
}

/// Renders content app instances in a grid with the specified column count.
class _ContentGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;

  const _ContentGrid({
    required this.columns,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const _EmptyContentState();
    }

    // Single view or only one content app
    if (children.length == 1 || columns <= 1) {
      return children.first;
    }

    // Arrange in rows of `columns` items
    final rows = <List<Widget>>[];
    for (var i = 0; i < children.length; i += columns) {
      rows.add(children.sublist(i, min(i + columns, children.length)));
    }

    return Column(
      children: [
        for (final row in rows)
          Expanded(
            child: Row(
              children: [
                for (final child in row) Expanded(child: child),
              ],
            ),
          ),
      ],
    );
  }
}

/// Empty state shown when no content apps are open.
class _EmptyContentState extends StatelessWidget {
  const _EmptyContentState();

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final textColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;
    final iconColor = isDark ? AppColorsDark.neutral400 : AppColors.neutral400;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dashboard_outlined, size: 64, color: iconColor),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No open editors',
            style: TextStyle(fontSize: 16, color: textColor),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Select a step from the navigator to begin.',
            style: TextStyle(fontSize: 14, color: iconColor),
          ),
        ],
      ),
    );
  }
}
