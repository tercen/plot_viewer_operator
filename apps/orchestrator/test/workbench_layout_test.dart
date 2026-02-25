import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:orchestrator/presentation/providers/layout_provider.dart';
import 'package:orchestrator/core/theme/app_spacing.dart';

/// Workbench layout integration tests.
///
/// These tests build the exact same widget structure as workbench.dart
/// but replace PanelHost/iframes with labeled colored containers.
/// After pumping, they measure every element's Rect and generate
/// an HTML file showing the layout.

// Named keys for every measurable element.
const _kToolbar = Key('toolbar');
const _kIconStrip = Key('icon-strip');
const _kContentHeader = Key('content-header');
const _kContentArea = Key('content-area');
const _kBottomIconStrip = Key('bottom-icon-strip');
const _kBottomPanel = Key('bottom-panel');

Key _stripKey(String id) => Key('strip-$id');
Key _splitterKey(String id) => Key('splitter-$id');
Key _contentCellKey(int i) => Key('content-cell-$i');

void main() {
  group('Workbench layout geometry', () {
    late LayoutProvider layout;

    setUp(() {
      layout = LayoutProvider();
    });

    Widget buildWorkbench({
      required LayoutProvider layout,
      int contentAppCount = 1,
      bool showBottomPanel = false,
      String? activeBottomApp,
      double width = 1280,
      double height = 720,
    }) {
      if (showBottomPanel && activeBottomApp != null) {
        layout.toggleBottomPanel(activeBottomApp);
      }

      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: height,
            child: ChangeNotifierProvider.value(
              value: layout,
              child: _TestWorkbench(
                openToolStrips: layout.openToolStrips,
                contentAppCount: contentAppCount,
                showBottomStrip: true,
                showBottomPanel: layout.isBottomPanelVisible,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('no strips open — full content area', (tester) async {
      await tester.pumpWidget(buildWorkbench(layout: layout));

      final report = _measureAll(tester, layout, 1);


      // Icon strip at x=0
      final iconRect = tester.getRect(find.byKey(_kIconStrip));
      expect(iconRect.left, 0.0);
      expect(iconRect.width, AppSpacing.iconStripWidth);

      // Content area fills remaining width
      final contentRect = tester.getRect(find.byKey(_kContentArea));
      expect(contentRect.left, AppSpacing.iconStripWidth,
          reason: 'Content starts after icon strip');

      // Content fills all space right of icon strip
      final totalWidth = tester.getRect(find.byKey(_kToolbar)).width;
      expect(contentRect.right, totalWidth,
          reason: 'Content extends to right edge');

      // No strip elements
      expect(find.byKey(_stripKey('project-nav')), findsNothing);
      expect(find.byKey(_stripKey('factor-nav')), findsNothing);

      _printReport('NO STRIPS OPEN', report);
    });

    testWidgets('one strip open — strip + content', (tester) async {
      layout.toggleToolStrip('project-nav', availableWidth: 1240);

      await tester.pumpWidget(buildWorkbench(layout: layout));

      final report = _measureAll(tester, layout, 1);


      final iconRect = tester.getRect(find.byKey(_kIconStrip));
      final stripRect = tester.getRect(find.byKey(_stripKey('project-nav')));
      final splitterRect =
          tester.getRect(find.byKey(_splitterKey('project-nav')));
      final contentRect = tester.getRect(find.byKey(_kContentArea));

      // Icon strip | project-nav strip | splitter | content
      expect(stripRect.left, iconRect.right,
          reason: 'Strip starts after icon strip');
      expect(stripRect.width, AppSpacing.defaultToolStripWidth,
          reason: 'Strip is 280px wide');
      expect(splitterRect.left, stripRect.right,
          reason: 'Splitter abuts strip');
      expect(splitterRect.width, AppSpacing.splitterThickness);
      expect(contentRect.left, splitterRect.right,
          reason: 'Content starts after splitter');

      // No overlap between strip and content
      expect(stripRect.right, lessThanOrEqualTo(contentRect.left),
          reason: 'NO OVERLAP: strip ends before content starts');

      _printReport('ONE STRIP (project-nav)', report);
    });

    testWidgets('two strips open — strips side-by-side + content',
        (tester) async {
      layout.toggleToolStrip('project-nav', availableWidth: 1240);
      layout.toggleToolStrip('factor-nav', availableWidth: 1240);

      await tester.pumpWidget(buildWorkbench(layout: layout));

      final report = _measureAll(tester, layout, 1);


      final iconRect = tester.getRect(find.byKey(_kIconStrip));
      final strip1Rect =
          tester.getRect(find.byKey(_stripKey('project-nav')));
      final splitter1Rect =
          tester.getRect(find.byKey(_splitterKey('project-nav')));
      final strip2Rect =
          tester.getRect(find.byKey(_stripKey('factor-nav')));
      final splitter2Rect =
          tester.getRect(find.byKey(_splitterKey('factor-nav')));
      final contentRect = tester.getRect(find.byKey(_kContentArea));

      // Sequence: icon | strip1 | splitter1 | strip2 | splitter2 | content
      expect(strip1Rect.left, iconRect.right);
      expect(splitter1Rect.left, strip1Rect.right);
      expect(strip2Rect.left, splitter1Rect.right,
          reason: 'Strip 2 starts after splitter 1');
      expect(splitter2Rect.left, strip2Rect.right);
      expect(contentRect.left, splitter2Rect.right);

      // No overlap between ANY adjacent elements
      expect(strip1Rect.right, lessThanOrEqualTo(strip2Rect.left),
          reason: 'NO OVERLAP: strip1 ends before strip2 starts');
      expect(strip2Rect.right, lessThanOrEqualTo(contentRect.left),
          reason: 'NO OVERLAP: strip2 ends before content starts');

      // Strips don't overlap each other
      expect(strip1Rect.overlaps(strip2Rect), false,
          reason: 'Strips must not overlap');
      expect(strip1Rect.overlaps(contentRect), false,
          reason: 'Strip 1 must not overlap content');
      expect(strip2Rect.overlaps(contentRect), false,
          reason: 'Strip 2 must not overlap content');

      _printReport('TWO STRIPS (project-nav + factor-nav)', report);
    });

    testWidgets('bottom panel visible', (tester) async {
      await tester.pumpWidget(buildWorkbench(
        layout: layout,
        showBottomPanel: true,
        activeBottomApp: 'ai-chat',
      ));

      final report = _measureAll(tester, layout, 1);


      final bottomStripRect =
          tester.getRect(find.byKey(_kBottomIconStrip));
      final bottomPanelRect =
          tester.getRect(find.byKey(_kBottomPanel));

      expect(bottomPanelRect.top, greaterThanOrEqualTo(bottomStripRect.bottom),
          reason: 'Bottom panel below bottom icon strip');

      _printReport('BOTTOM PANEL OPEN', report);
    });

    testWidgets('content grid 2 columns with 2 apps', (tester) async {
      layout.setContentColumns(2);

      await tester.pumpWidget(buildWorkbench(
        layout: layout,
        contentAppCount: 2,
      ));

      final report = _measureAll(tester, layout, 2);


      final cell0 = tester.getRect(find.byKey(_contentCellKey(0)));
      final cell1 = tester.getRect(find.byKey(_contentCellKey(1)));

      expect(cell0.top, cell1.top, reason: 'Same row');
      expect(cell0.right, lessThanOrEqualTo(cell1.left),
          reason: 'Cell 0 left of cell 1');
      expect(cell0.overlaps(cell1), false,
          reason: 'Content cells must not overlap');

      _printReport('CONTENT GRID 2 COLUMNS', report);
    });

    testWidgets('full layout: 1 strip + bottom panel + 2-col content',
        (tester) async {
      layout.toggleToolStrip('project-nav', availableWidth: 1240);
      layout.setContentColumns(2);

      await tester.pumpWidget(buildWorkbench(
        layout: layout,
        contentAppCount: 2,
        showBottomPanel: true,
        activeBottomApp: 'ai-chat',
      ));

      final report = _measureAll(tester, layout, 2);


      // Verify no overlaps between major regions
      final toolbarRect = tester.getRect(find.byKey(_kToolbar));
      final iconRect = tester.getRect(find.byKey(_kIconStrip));
      final stripRect =
          tester.getRect(find.byKey(_stripKey('project-nav')));
      final contentRect = tester.getRect(find.byKey(_kContentArea));

      expect(toolbarRect.bottom, lessThanOrEqualTo(iconRect.top),
          reason: 'Toolbar above body');
      expect(iconRect.right, lessThanOrEqualTo(stripRect.left),
          reason: 'Icon strip left of strip');
      expect(stripRect.right, lessThanOrEqualTo(contentRect.left),
          reason: 'Strip left of content');

      _printReport('FULL LAYOUT', report);
    });
  });
}

// ─── Test workbench (mirrors real workbench structure) ──────────────

class _TestWorkbench extends StatelessWidget {
  final List<String> openToolStrips;
  final int contentAppCount;
  final bool showBottomStrip;
  final bool showBottomPanel;

  const _TestWorkbench({
    required this.openToolStrips,
    required this.contentAppCount,
    required this.showBottomStrip,
    required this.showBottomPanel,
  });

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LayoutProvider>();

    return Column(
      children: [
        // Toolbar
        Container(
          key: _kToolbar,
          height: AppSpacing.toolbarHeight,
          color: Colors.blue[100],
          child: const Center(child: Text('TOOLBAR')),
        ),
        // Body
        Expanded(
          child: Column(
            children: [
              // Main row
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Row(
                      children: [
                        // Left icon strip
                        Container(
                          key: _kIconStrip,
                          width: AppSpacing.iconStripWidth,
                          color: Colors.grey[300],
                          child: const Center(
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: Text('ICONS'),
                            ),
                          ),
                        ),
                        // Tool strips + splitters
                        for (final appId in openToolStrips) ...[
                          SizedBox(
                            key: _stripKey(appId),
                            width: layout.toolStripWidth(appId),
                            child: Container(
                              color: _stripColor(appId),
                              child: Center(child: Text(appId)),
                            ),
                          ),
                          Container(
                            key: _splitterKey(appId),
                            width: AppSpacing.splitterThickness,
                            color: Colors.grey[600],
                          ),
                        ],
                        // Content area
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                key: _kContentHeader,
                                height: AppSpacing.contentHeaderHeight,
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Text('CONTENT HEADER [1][2][3]'),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  key: _kContentArea,
                                  child: _buildContentGrid(
                                    layout.contentColumns,
                                    contentAppCount,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // Bottom icon strip
              if (showBottomStrip)
                Container(
                  key: _kBottomIconStrip,
                  height: AppSpacing.bottomIconStripHeight,
                  color: Colors.grey[300],
                  child: const Center(child: Text('BOTTOM ICONS')),
                ),
              // Bottom panel
              if (showBottomPanel) ...[
                Container(
                  height: AppSpacing.splitterThickness,
                  color: Colors.grey[600],
                ),
                Container(
                  key: _kBottomPanel,
                  height: layout.bottomPanelHeight,
                  color: Colors.orange[100],
                  child: const Center(child: Text('BOTTOM PANEL')),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContentGrid(int columns, int childCount) {
    if (childCount == 0) {
      return const Center(child: Text('No open editors'));
    }

    final children = List.generate(
      childCount,
      (i) => Container(
        key: _contentCellKey(i),
        color: _contentColor(i),
        child: Center(child: Text('content-$i')),
      ),
    );

    if (children.length == 1 || columns <= 1) {
      return children.first;
    }

    final rows = <List<Widget>>[];
    for (var i = 0; i < children.length; i += columns) {
      rows.add(
          children.sublist(i, min(i + columns, children.length)));
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

  static Color _stripColor(String id) {
    switch (id) {
      case 'project-nav':
        return Colors.green[100]!;
      case 'factor-nav':
        return Colors.purple[100]!;
      case 'team-nav':
        return Colors.teal[100]!;
      default:
        return Colors.amber[100]!;
    }
  }

  static Color _contentColor(int i) {
    const colors = [
      Color(0xFFBBDEFB), // blue 100
      Color(0xFFF8BBD0), // pink 100
      Color(0xFFC8E6C9), // green 100
      Color(0xFFFFF9C4), // yellow 100
    ];
    return colors[i % colors.length];
  }
}

// ─── Measurement & reporting ────────────────────────────────────────

class _ElementRect {
  final String label;
  final Rect rect;
  final String color;
  _ElementRect(this.label, this.rect, this.color);
}

List<_ElementRect> _measureAll(
    WidgetTester tester, LayoutProvider layout, int contentAppCount) {
  final rects = <_ElementRect>[];

  void tryMeasure(Key key, String label, String color) {
    final finder = find.byKey(key);
    if (finder.evaluate().isNotEmpty) {
      rects.add(_ElementRect(label, tester.getRect(finder), color));
    }
  }

  tryMeasure(_kToolbar, 'Toolbar', '#BBDEFB');
  tryMeasure(_kIconStrip, 'Icon Strip', '#E0E0E0');

  for (final appId in layout.openToolStrips) {
    final color = appId == 'project-nav'
        ? '#C8E6C9'
        : appId == 'factor-nav'
            ? '#E1BEE7'
            : '#B2DFDB';
    tryMeasure(_stripKey(appId), 'Strip: $appId', color);
    tryMeasure(_splitterKey(appId), 'Splitter: $appId', '#757575');
  }

  tryMeasure(_kContentHeader, 'Content Header', '#EEEEEE');
  tryMeasure(_kContentArea, 'Content Area', '#E3F2FD');

  for (var i = 0; i < contentAppCount; i++) {
    final colors = ['#BBDEFB', '#F8BBD0', '#C8E6C9', '#FFF9C4'];
    tryMeasure(_contentCellKey(i), 'Content Cell $i', colors[i % 4]);
  }

  tryMeasure(_kBottomIconStrip, 'Bottom Icons', '#E0E0E0');
  tryMeasure(_kBottomPanel, 'Bottom Panel', '#FFE0B2');

  return rects;
}

void _printReport(String title, List<_ElementRect> rects) {
  final buf = StringBuffer();
  buf.writeln('\n=== $title ===');
  buf.writeln('${'Element'.padRight(25)} ${'Left'.padRight(8)} '
      '${'Top'.padRight(8)} ${'Width'.padRight(8)} ${'Height'.padRight(8)} '
      '${'Right'.padRight(8)} Bottom');
  buf.writeln('-' * 85);
  for (final r in rects) {
    buf.writeln('${r.label.padRight(25)} '
        '${r.rect.left.toStringAsFixed(0).padRight(8)} '
        '${r.rect.top.toStringAsFixed(0).padRight(8)} '
        '${r.rect.width.toStringAsFixed(0).padRight(8)} '
        '${r.rect.height.toStringAsFixed(0).padRight(8)} '
        '${r.rect.right.toStringAsFixed(0).padRight(8)} '
        '${r.rect.bottom.toStringAsFixed(0)}');
  }

  // Check for overlaps
  buf.writeln('\nOverlap check:');
  var hasOverlap = false;
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      if (rects[i].rect.overlaps(rects[j].rect)) {
        // Skip expected overlaps (content cells are children of content area)
        if (rects[i].label == 'Content Area' &&
            rects[j].label.startsWith('Content Cell')) continue;
        if (rects[i].label == 'Content Header' &&
            rects[j].label == 'Content Area') continue;
        buf.writeln(
            '  OVERLAP: "${rects[i].label}" overlaps "${rects[j].label}"');
        hasOverlap = true;
      }
    }
  }
  if (!hasOverlap) buf.writeln('  No unexpected overlaps found.');

  // ignore: avoid_print
  print(buf.toString());
}

