import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_minimap.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/git.dart';

import 'support/full_diff_fixtures.dart';

void main() {
  test('maps additions and deletions to source line ratios', () {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,0 +11 @@ add'),
      DiffLine(kind: DiffLineKind.add, text: 'added', newNumber: 11),
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -81 +82,0 @@ delete'),
      DiffLine(kind: DiffLineKind.delete, text: 'deleted', oldNumber: 81),
    ]);

    final geometry = MinimapGeometry.fromDocument(
      document: document,
      activeAnchor: document.hunks[1].anchor,
      sourceLineCount: 100,
      height: 500,
      deletedFile: false,
    );

    expect(geometry.markers, hasLength(2));
    expect(geometry.markers[0].top, closeTo(50.202, 0.001));
    expect(geometry.markers[0].height, 3);
    expect(geometry.markers[0].color, fullDiffAccent);
    expect(geometry.markers[0].active, isFalse);
    expect(geometry.markers[1].color, fullDiffDeletedMark);
    expect(geometry.markers[1].active, isTrue);
  });

  test('uses old coordinates for deleted files', () {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -20 +80 @@ replace'),
      DiffLine(kind: DiffLineKind.delete, text: 'before', oldNumber: 20),
      DiffLine(kind: DiffLineKind.add, text: 'after', newNumber: 80),
    ]);

    final regular = MinimapGeometry.fromDocument(
      document: document,
      activeAnchor: null,
      sourceLineCount: 100,
      height: 102,
      deletedFile: false,
    );
    final deleted = MinimapGeometry.fromDocument(
      document: document,
      activeAnchor: null,
      sourceLineCount: 100,
      height: 102,
      deletedFile: true,
    );

    expect(regular.markers.single.top, 79);
    expect(deleted.markers.single.top, 19);
  });

  test('handles empty, short, and large source documents', () {
    expect(
      MinimapGeometry.fromDocument(
        document: DiffDocument.empty,
        activeAnchor: null,
        sourceLineCount: 0,
        height: 2,
        deletedFile: false,
      ).markers,
      isEmpty,
    );
    expect(lineToTop(1, 1, 2), 0);
    expect(lineToTop(200000, 200000, 100), 97);
    expect(lineToTop(300000, 200000, 100), 97);
    expect(nearestAnchorForY(10, 100, const []), isNull);
  });

  test('maps and clamps a scrollable viewport', () {
    final viewport = scrollViewport(
      pixels: 200,
      maxScrollExtent: 800,
      viewportDimension: 200,
      height: 500,
    );
    expect(viewport.top, 100);
    expect(viewport.height, 100);

    final beforeStart = scrollViewport(
      pixels: -50,
      maxScrollExtent: 800,
      viewportDimension: 200,
      height: 20,
    );
    final afterEnd = scrollViewport(
      pixels: 1000,
      maxScrollExtent: 800,
      viewportDimension: 200,
      height: 20,
    );
    final shortDocument = scrollViewport(
      pixels: 0,
      maxScrollExtent: 0,
      viewportDimension: 200,
      height: 12,
    );

    expect(beforeStart.top, 0);
    expect(beforeStart.height, 18);
    expect(afterEnd.top, 2);
    expect(afterEnd.height, 18);
    expect(shortDocument.top, 0);
    expect(shortDocument.height, 12);
  });

  test('chooses the nearest marker and clamps pointer coordinates', () {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -10 +10 @@ one'),
      DiffLine(kind: DiffLineKind.add, text: 'one', newNumber: 10),
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -90 +90 @@ two'),
      DiffLine(kind: DiffLineKind.add, text: 'two', newNumber: 90),
    ]);
    final geometry = MinimapGeometry.fromDocument(
      document: document,
      activeAnchor: document.hunks.first.anchor,
      sourceLineCount: 100,
      height: 500,
      deletedFile: false,
    );

    expect(
      nearestAnchorForY(-50, 500, geometry.markers),
      same(document.hunks.first.anchor),
    );
    expect(
      nearestAnchorForY(460, 500, geometry.markers),
      same(document.hunks.last.anchor),
    );
    expect(
      nearestAnchorForY(600, 500, geometry.markers),
      same(document.hunks.last.anchor),
    );
  });

  testWidgets('history hides the minimap', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      qaApp(
        SizedBox(
          height: 300,
          child: FullDiffMinimap(
            document: twoHunkDocument,
            activeAnchor: twoHunkDocument.hunks.first.anchor,
            sourceLineCount: 100,
            deletedFile: false,
            view: FullDiffView.history,
            scrollController: scrollController,
            onAnchorSelected: (_) {},
            onScrollFractionChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('full-diff-minimap')), findsNothing);
  });

  testWidgets(
    'external scroll updates state without echoing a scroll request',
    (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      var scrollCallbacks = 0;

      await tester.pumpWidget(
        qaApp(
          SizedBox(
            height: 300,
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: const [SizedBox(height: 1200)],
                  ),
                ),
                FullDiffMinimap(
                  document: twoHunkDocument,
                  activeAnchor: twoHunkDocument.hunks.first.anchor,
                  sourceLineCount: 100,
                  deletedFile: false,
                  view: FullDiffView.diff,
                  scrollController: scrollController,
                  onAnchorSelected: (_) {},
                  onScrollFractionChanged: (_) => scrollCallbacks++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      scrollController.jumpTo(120);
      await tester.pump();

      expect(scrollCallbacks, 0);
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const Key('full-diff-minimap')),
          matching: find.byType(CustomPaint),
        ),
      );
      final painter = paint.painter! as FullDiffMinimapPainter;
      expect(painter.viewport.top, 30);
      expect(painter.viewport.height, 75);
      expect(
        tester.getSize(find.byKey(const Key('full-diff-minimap'))).width,
        fullDiffMinimapWidth,
      );
    },
  );

  testWidgets('track clicks select one nearest anchor at both boundaries', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final selected = <DiffAnchor>[];

    await tester.pumpWidget(
      qaApp(
        Center(
          child: SizedBox(
            height: 300,
            child: FullDiffMinimap(
              document: twoHunkDocument,
              activeAnchor: twoHunkDocument.hunks.first.anchor,
              sourceLineCount: 30,
              deletedFile: false,
              view: FullDiffView.diff,
              scrollController: scrollController,
              onAnchorSelected: selected.add,
              onScrollFractionChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final minimap = find.byKey(const Key('full-diff-minimap'));
    final topLeft = tester.getTopLeft(minimap);
    await tester.tapAt(topLeft + const Offset(9, 0));
    await tester.pump();
    await tester.tapAt(topLeft + const Offset(9, 299.9));
    await tester.pump();

    expect(selected, [
      same(twoHunkDocument.hunks.first.anchor),
      same(twoHunkDocument.hunks.last.anchor),
    ]);
  });

  testWidgets('empty documents ignore track clicks and drags', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    var anchorCallbacks = 0;
    var scrollCallbacks = 0;

    await tester.pumpWidget(
      qaApp(
        SizedBox(
          height: 100,
          child: FullDiffMinimap(
            document: DiffDocument.empty,
            activeAnchor: null,
            sourceLineCount: 0,
            deletedFile: false,
            view: FullDiffView.diff,
            scrollController: scrollController,
            onAnchorSelected: (_) => anchorCallbacks++,
            onScrollFractionChanged: (_) => scrollCallbacks++,
          ),
        ),
      ),
    );

    final minimap = find.byKey(const Key('full-diff-minimap'));
    await tester.tap(minimap);
    await tester.drag(minimap, const Offset(0, 80));
    await tester.pump();

    expect(anchorCallbacks, 0);
    expect(scrollCallbacks, 0);
  });

  testWidgets('viewport drag clamps scroll requests to track boundaries', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final fractions = <double>[];
    var anchorCallbacks = 0;

    await tester.pumpWidget(
      qaApp(
        SizedBox(
          height: 300,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: const [SizedBox(height: 1200)],
                ),
              ),
              FullDiffMinimap(
                document: twoHunkDocument,
                activeAnchor: twoHunkDocument.hunks.first.anchor,
                sourceLineCount: 100,
                deletedFile: false,
                view: FullDiffView.diff,
                scrollController: scrollController,
                onAnchorSelected: (_) => anchorCallbacks++,
                onScrollFractionChanged: fractions.add,
              ),
            ],
          ),
        ),
      ),
    );
    scrollController.jumpTo(300);
    await tester.pump();

    final minimap = find.byKey(const Key('full-diff-minimap'));
    final topLeft = tester.getTopLeft(minimap);
    final gesture = await tester.startGesture(topLeft + const Offset(9, 80));
    await gesture.moveTo(topLeft + const Offset(9, -100));
    await tester.pump();
    await gesture.moveTo(topLeft + const Offset(9, 400));
    await tester.pump();
    await gesture.up();

    expect(fractions.first, 0);
    expect(fractions.last, 1);
    expect(anchorCallbacks, 0);
  });
}
