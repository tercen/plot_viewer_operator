import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the content grid layout logic.
///
/// These tests verify that children are arranged correctly
/// in rows of N columns. We test the layout algorithm directly
/// using simple Container widgets (no iframes needed).
void main() {
  group('Content grid layout', () {
    Widget buildGrid({required int columns, required int childCount}) {
      final children = List.generate(
        childCount,
        (i) => Container(
          key: ValueKey('child-$i'),
          color: Colors.primaries[i % Colors.primaries.length],
        ),
      );

      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: _ContentGrid(columns: columns, children: children),
          ),
        ),
      );
    }

    testWidgets('single column shows first child only', (tester) async {
      await tester.pumpWidget(buildGrid(columns: 1, childCount: 3));

      // Only the first child should be rendered
      expect(find.byKey(const ValueKey('child-0')), findsOneWidget);
      // With columns=1, grid just returns children.first
      expect(find.byKey(const ValueKey('child-1')), findsNothing);
    });

    testWidgets('2 columns with 2 children: side-by-side', (tester) async {
      await tester.pumpWidget(buildGrid(columns: 2, childCount: 2));

      expect(find.byKey(const ValueKey('child-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('child-1')), findsOneWidget);

      // Both should be in a single Row (side-by-side)
      final child0 = tester.getTopLeft(find.byKey(const ValueKey('child-0')));
      final child1 = tester.getTopLeft(find.byKey(const ValueKey('child-1')));
      expect(child0.dy, child1.dy, reason: 'Same row (same Y)');
      expect(child0.dx, lessThan(child1.dx), reason: 'Child 0 left of child 1');
    });

    testWidgets('2 columns with 4 children: 2x2 grid', (tester) async {
      await tester.pumpWidget(buildGrid(columns: 2, childCount: 4));

      for (var i = 0; i < 4; i++) {
        expect(find.byKey(ValueKey('child-$i')), findsOneWidget);
      }

      // Row 1: child-0, child-1 (same Y)
      final c0 = tester.getTopLeft(find.byKey(const ValueKey('child-0')));
      final c1 = tester.getTopLeft(find.byKey(const ValueKey('child-1')));
      expect(c0.dy, c1.dy, reason: 'Row 1: same Y');

      // Row 2: child-2, child-3 (same Y, below row 1)
      final c2 = tester.getTopLeft(find.byKey(const ValueKey('child-2')));
      final c3 = tester.getTopLeft(find.byKey(const ValueKey('child-3')));
      expect(c2.dy, c3.dy, reason: 'Row 2: same Y');
      expect(c2.dy, greaterThan(c0.dy), reason: 'Row 2 below row 1');
    });

    testWidgets('3 columns with 5 children: 2 rows, last row has 2',
        (tester) async {
      await tester.pumpWidget(buildGrid(columns: 3, childCount: 5));

      for (var i = 0; i < 5; i++) {
        expect(find.byKey(ValueKey('child-$i')), findsOneWidget);
      }

      // Row 1: 3 children
      final c0 = tester.getTopLeft(find.byKey(const ValueKey('child-0')));
      final c1 = tester.getTopLeft(find.byKey(const ValueKey('child-1')));
      final c2 = tester.getTopLeft(find.byKey(const ValueKey('child-2')));
      expect(c0.dy, c1.dy);
      expect(c1.dy, c2.dy);

      // Row 2: 2 children
      final c3 = tester.getTopLeft(find.byKey(const ValueKey('child-3')));
      final c4 = tester.getTopLeft(find.byKey(const ValueKey('child-4')));
      expect(c3.dy, c4.dy);
      expect(c3.dy, greaterThan(c0.dy));
    });

    testWidgets('empty grid shows empty state', (tester) async {
      await tester.pumpWidget(buildGrid(columns: 2, childCount: 0));

      expect(find.text('No open editors'), findsOneWidget);
    });

    testWidgets('1 child with 3 columns shows just the child',
        (tester) async {
      await tester.pumpWidget(buildGrid(columns: 3, childCount: 1));

      expect(find.byKey(const ValueKey('child-0')), findsOneWidget);
    });

    testWidgets('children get equal width in a row', (tester) async {
      await tester.pumpWidget(buildGrid(columns: 2, childCount: 2));

      final c0Size = tester.getSize(find.byKey(const ValueKey('child-0')));
      final c1Size = tester.getSize(find.byKey(const ValueKey('child-1')));

      expect(c0Size.width, c1Size.width, reason: 'Equal width');
      expect(c0Size.width, 400, reason: '800 / 2 columns = 400');
    });
  });
}

// ─── Extracted grid widget for testing ──────────────────────────────────────

/// Renders children in a grid with the specified column count.
/// This is a copy of the private _ContentGrid from workbench.dart,
/// extracted here so it can be tested in isolation.
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
      return const Center(
        child: Text('No open editors'),
      );
    }

    if (children.length == 1 || columns <= 1) {
      return children.first;
    }

    // Arrange in rows of `columns` items
    final rows = <List<Widget>>[];
    for (var i = 0; i < children.length; i += columns) {
      final end = i + columns;
      rows.add(children.sublist(i, end > children.length ? children.length : end));
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
