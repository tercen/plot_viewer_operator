import 'package:flutter_test/flutter_test.dart';
import 'package:orchestrator/presentation/providers/layout_provider.dart';
import 'package:orchestrator/core/theme/app_spacing.dart';

void main() {
  group('LayoutProvider - Tool Strips', () {
    late LayoutProvider layout;

    setUp(() {
      layout = LayoutProvider();
    });

    test('starts with no open tool strips', () {
      expect(layout.openToolStrips, isEmpty);
      expect(layout.hasOpenToolStrips, false);
      expect(layout.isToolStripOpen('project-nav'), false);
    });

    test('openToolStripDefault opens a strip without notifying', () {
      var notified = false;
      layout.addListener(() => notified = true);

      layout.openToolStripDefault('project-nav');

      expect(layout.isToolStripOpen('project-nav'), true);
      expect(layout.openToolStrips, ['project-nav']);
      expect(notified, false, reason: 'Should not notify during init');
    });

    test('toggleToolStrip opens a closed strip', () {
      final result = layout.toggleToolStrip('project-nav',
          availableWidth: 1200);

      expect(result, true);
      expect(layout.isToolStripOpen('project-nav'), true);
      expect(layout.openToolStrips, ['project-nav']);
    });

    test('toggleToolStrip closes an open strip', () {
      layout.toggleToolStrip('project-nav', availableWidth: 1200);
      final result = layout.toggleToolStrip('project-nav',
          availableWidth: 1200);

      expect(result, true);
      expect(layout.isToolStripOpen('project-nav'), false);
      expect(layout.openToolStrips, isEmpty);
    });

    test('multiple strips can be open simultaneously', () {
      layout.toggleToolStrip('project-nav', availableWidth: 1200);
      layout.toggleToolStrip('factor-nav', availableWidth: 1200);

      expect(layout.openToolStrips, ['project-nav', 'factor-nav']);
      expect(layout.isToolStripOpen('project-nav'), true);
      expect(layout.isToolStripOpen('factor-nav'), true);
    });

    test('open order is preserved (first opened = leftmost)', () {
      layout.toggleToolStrip('factor-nav', availableWidth: 1200);
      layout.toggleToolStrip('project-nav', availableWidth: 1200);

      expect(layout.openToolStrips, ['factor-nav', 'project-nav']);
    });

    test('closing a strip preserves other strips order', () {
      // Need enough width for 3 strips: 3*(280+4) = 852 + 400 min content = 1252
      layout.toggleToolStrip('project-nav', availableWidth: 2000);
      layout.toggleToolStrip('factor-nav', availableWidth: 2000);
      layout.toggleToolStrip('team-nav', availableWidth: 2000);

      layout.toggleToolStrip('factor-nav', availableWidth: 2000);

      expect(layout.openToolStrips, ['project-nav', 'team-nav']);
    });

    test('guard prevents opening when content would be too narrow', () {
      // Available = 700. First strip: 700 - (280+4) = 416 > 400, OK.
      layout.toggleToolStrip('project-nav', availableWidth: 700);
      expect(layout.isToolStripOpen('project-nav'), true);

      // Second strip: 700 - 2*(280+4) = 132 < 400, BLOCKED.
      final result = layout.toggleToolStrip('factor-nav',
          availableWidth: 700);

      expect(result, false);
      expect(layout.isToolStripOpen('factor-nav'), false);
      expect(layout.openToolStrips, ['project-nav']);
    });

    test('guard allows opening when enough space', () {
      // Available = 1200. One strip = 280+4 = 284. Remaining = 916. OK.
      layout.toggleToolStrip('project-nav', availableWidth: 1200);
      // Two strips = 284*2 = 568. Remaining = 632. Still > 400. OK.
      final result = layout.toggleToolStrip('factor-nav',
          availableWidth: 1200);

      expect(result, true);
    });

    test('toolStripWidth returns default for new strips', () {
      layout.toggleToolStrip('project-nav', availableWidth: 1200);
      expect(layout.toolStripWidth('project-nav'),
          AppSpacing.defaultToolStripWidth);
    });

    test('setToolStripWidth updates and clamps', () {
      layout.toggleToolStrip('project-nav', availableWidth: 1200);

      layout.setToolStripWidth('project-nav', 350);
      expect(layout.toolStripWidth('project-nav'), 350);

      // Clamp to min
      layout.setToolStripWidth('project-nav', 10);
      expect(layout.toolStripWidth('project-nav'), AppSpacing.minPanelSize);

      // Clamp to maxWidth
      layout.setToolStripWidth('project-nav', 500, maxWidth: 400);
      expect(layout.toolStripWidth('project-nav'), 400);
    });

    test('totalToolStripWidth sums widths and splitters', () {
      layout.toggleToolStrip('project-nav', availableWidth: 1200);
      layout.toggleToolStrip('factor-nav', availableWidth: 1200);

      // 2 strips * (280 + 4 splitter) = 568
      expect(layout.totalToolStripWidth,
          2 * (AppSpacing.defaultToolStripWidth + AppSpacing.splitterThickness));
    });

    test('width is remembered after close/reopen', () {
      layout.toggleToolStrip('project-nav', availableWidth: 1200);
      layout.setToolStripWidth('project-nav', 350);
      layout.toggleToolStrip('project-nav', availableWidth: 1200); // close

      expect(layout.isToolStripOpen('project-nav'), false);

      layout.toggleToolStrip('project-nav', availableWidth: 1200); // reopen
      expect(layout.toolStripWidth('project-nav'), 350,
          reason: 'Width should be remembered');
    });

    test('ensureToolStripOpen opens and notifies', () {
      var notified = false;
      layout.addListener(() => notified = true);

      layout.ensureToolStripOpen('factor-nav');

      expect(layout.isToolStripOpen('factor-nav'), true);
      expect(notified, true);
    });

    test('ensureToolStripOpen is no-op if already open', () {
      layout.toggleToolStrip('factor-nav', availableWidth: 1200);
      var notifyCount = 0;
      layout.addListener(() => notifyCount++);

      layout.ensureToolStripOpen('factor-nav');

      expect(notifyCount, 0, reason: 'Should not notify if already open');
    });
  });

  group('LayoutProvider - Content Grid', () {
    late LayoutProvider layout;

    setUp(() {
      layout = LayoutProvider();
    });

    test('starts with 1 column and no content', () {
      expect(layout.contentColumns, 1);
      expect(layout.contentInstanceIds, isEmpty);
    });

    test('addContentInstance adds an instance', () {
      layout.addContentInstance('step-viewer-1');
      expect(layout.contentInstanceIds, ['step-viewer-1']);
    });

    test('addContentInstance ignores duplicates', () {
      layout.addContentInstance('step-viewer-1');
      layout.addContentInstance('step-viewer-1');
      expect(layout.contentInstanceIds, ['step-viewer-1']);
    });

    test('removeContentInstance removes an instance', () {
      layout.addContentInstance('step-viewer-1');
      layout.addContentInstance('report-1');
      layout.removeContentInstance('step-viewer-1');
      expect(layout.contentInstanceIds, ['report-1']);
    });

    test('setContentColumns clamps 1..4', () {
      layout.setContentColumns(2);
      expect(layout.contentColumns, 2);

      layout.setContentColumns(0);
      expect(layout.contentColumns, 1);

      layout.setContentColumns(5);
      expect(layout.contentColumns, 4);
    });
  });

  group('LayoutProvider - Bottom Panel', () {
    late LayoutProvider layout;

    setUp(() {
      layout = LayoutProvider();
    });

    test('starts collapsed', () {
      expect(layout.isBottomPanelVisible, false);
      expect(layout.activeBottomAppId, null);
    });

    test('toggleBottomPanel opens', () {
      layout.toggleBottomPanel('ai-chat');
      expect(layout.isBottomPanelVisible, true);
      expect(layout.activeBottomAppId, 'ai-chat');
    });

    test('toggleBottomPanel same app closes', () {
      layout.toggleBottomPanel('ai-chat');
      layout.toggleBottomPanel('ai-chat');
      expect(layout.isBottomPanelVisible, false);
    });

    test('toggleBottomPanel different app switches (radio)', () {
      layout.toggleBottomPanel('ai-chat');
      layout.toggleBottomPanel('task-manager');
      expect(layout.isBottomPanelVisible, true);
      expect(layout.activeBottomAppId, 'task-manager');
    });

    test('setBottomPanelHeight clamps', () {
      layout.setBottomPanelHeight(300);
      expect(layout.bottomPanelHeight, 300);

      layout.setBottomPanelHeight(10);
      expect(layout.bottomPanelHeight, AppSpacing.minPanelSize);

      layout.setBottomPanelHeight(1000);
      expect(layout.bottomPanelHeight, 600);
    });
  });
}
