import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
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
      sourceSide: FileDocumentSide.result,
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
      sourceSide: FileDocumentSide.result,
    );
    final deleted = MinimapGeometry.fromDocument(
      document: document,
      activeAnchor: null,
      sourceLineCount: 100,
      height: 102,
      sourceSide: FileDocumentSide.old,
    );

    expect(regular.markers.single.top, 79);
    expect(deleted.markers.single.top, 19);
  });

  test('uses the result hunk start for deletion-only changes', () {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -81 +82,0 @@ delete'),
      DiffLine(kind: DiffLineKind.delete, text: 'deleted', oldNumber: 81),
    ]);

    final regular = MinimapGeometry.fromDocument(
      document: document,
      activeAnchor: null,
      sourceLineCount: 100,
      height: 102,
      sourceSide: FileDocumentSide.result,
    );
    final deleted = MinimapGeometry.fromDocument(
      document: document,
      activeAnchor: null,
      sourceLineCount: 100,
      height: 102,
      sourceSide: FileDocumentSide.old,
    );

    expect(regular.markers.single.top, 81);
    expect(deleted.markers.single.top, 80);
  });

  test('handles empty, short, and large source documents', () {
    expect(
      MinimapGeometry.fromDocument(
        document: DiffDocument.empty,
        activeAnchor: null,
        sourceLineCount: 0,
        height: 2,
        sourceSide: FileDocumentSide.result,
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

  test('maps active hunk ranges on the selected source side', () {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,40 +80,5 @@ uneven'),
      DiffLine(
        kind: DiffLineKind.context,
        text: 'line',
        oldNumber: 10,
        newNumber: 80,
      ),
    ]);
    final hunk = document.hunks.single;

    final oldViewport = hunkViewport(
      hunk: hunk,
      sourceSide: FileDocumentSide.old,
      sourceLineCount: 100,
      height: 200,
    );
    final resultViewport = hunkViewport(
      hunk: hunk,
      sourceSide: FileDocumentSide.result,
      sourceLineCount: 100,
      height: 200,
    );

    expect(oldViewport?.top, 18);
    expect(oldViewport?.height, 80);
    expect(resultViewport?.top, 154);
    expect(resultViewport?.height, 18);
    expect(sourceLineCountForSide(document, FileDocumentSide.old), 49);
    expect(sourceLineCountForSide(document, FileDocumentSide.result), 84);
  });

  test('normalizes deletion boundaries, EOF, and empty source ranges', () {
    final deletion = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -81 +82,0 @@ delete'),
      DiffLine(kind: DiffLineKind.delete, text: 'deleted', oldNumber: 81),
    ]).hunks.single;
    final eofAddition = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -100,0 +101 @@ add'),
      DiffLine(kind: DiffLineKind.add, text: 'added', newNumber: 101),
    ]).hunks.single;

    final deletionBoundary = hunkViewport(
      hunk: deletion,
      sourceSide: FileDocumentSide.result,
      sourceLineCount: 81,
      height: 200,
    )!;
    expect(deletionBoundary.top, 182);
    expect(deletionBoundary.height, 18);

    final eofBoundary = hunkViewport(
      hunk: eofAddition,
      sourceSide: FileDocumentSide.old,
      sourceLineCount: 100,
      height: 200,
    )!;
    expect(eofBoundary.top, 182);
    expect(eofBoundary.height, 18);

    expect(
      hunkViewport(
        hunk: deletion,
        sourceSide: FileDocumentSide.result,
        sourceLineCount: 0,
        height: 10,
      ),
      isA<MinimapViewport>()
          .having((viewport) => viewport.top, 'top', 0)
          .having((viewport) => viewport.height, 'height', 10),
    );
    expect(
      hunkViewport(
        hunk: deletion,
        sourceSide: FileDocumentSide.old,
        sourceLineCount: 0,
        height: 200,
      ),
      isNull,
    );
    expect(
      hunkViewport(
        hunk: null,
        sourceSide: FileDocumentSide.result,
        sourceLineCount: 100,
        height: 200,
      ),
      isNull,
    );
  });

  test('nullable viewport changes invalidate minimap painting', () {
    final geometry = MinimapGeometry.fromDocument(
      document: DiffDocument.empty,
      activeAnchor: null,
      sourceLineCount: 0,
      height: 100,
      sourceSide: FileDocumentSide.result,
    );
    final withoutViewport = FullDiffMinimapPainter(
      geometry: geometry,
      viewport: null,
    );
    final same = FullDiffMinimapPainter(geometry: geometry, viewport: null);
    final withViewport = FullDiffMinimapPainter(
      geometry: geometry,
      viewport: const MinimapViewport(top: 0, height: 18),
    );

    expect(withoutViewport.shouldRepaint(same), isFalse);
    expect(withViewport.shouldRepaint(withoutViewport), isTrue);
    expect(withoutViewport.shouldRepaint(withViewport), isTrue);
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
      sourceSide: FileDocumentSide.result,
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
            sourceSide: FileDocumentSide.result,
            view: FullDiffView.history,
            presentation: DiffPresentation.hunk,
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
                  sourceSide: FileDocumentSide.result,
                  view: FullDiffView.diff,
                  presentation: DiffPresentation.inline,
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
      expect(painter.viewport!.top, 30);
      expect(painter.viewport!.height, 75);
      expect(
        tester.getSize(find.byKey(const Key('full-diff-minimap'))).width,
        fullDiffMinimapWidth,
      );
    },
  );

  testWidgets('scrolling a large document reuses marker geometry', (
    tester,
  ) async {
    final lines = <DiffLine>[];
    for (var line = 1; line <= 2000; line++) {
      lines
        ..add(
          DiffLine(kind: DiffLineKind.hunk, text: '@@ -$line +$line @@ change'),
        )
        ..add(
          DiffLine(kind: DiffLineKind.add, text: 'line $line', newNumber: line),
        );
    }
    final document = DiffDocument.fromLines(lines);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      qaApp(
        SizedBox(
          height: 300,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: const [SizedBox(height: 4000)],
                ),
              ),
              FullDiffMinimap(
                document: document,
                activeAnchor: document.hunks.first.anchor,
                sourceLineCount: 2000,
                sourceSide: FileDocumentSide.result,
                view: FullDiffView.diff,
                presentation: DiffPresentation.inline,
                scrollController: scrollController,
                onAnchorSelected: (_) {},
                onScrollFractionChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final before = _minimapPainter(tester).geometry;

    scrollController
      ..jumpTo(300)
      ..jumpTo(900);
    await tester.pump();

    expect(_minimapPainter(tester).geometry, same(before));
  });

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
              sourceSide: FileDocumentSide.result,
              view: FullDiffView.diff,
              presentation: DiffPresentation.inline,
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

  testWidgets('semantics names the current hunk and moves both directions', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    var activeAnchor = twoHunkDocument.hunks.first.anchor;
    final selected = <DiffAnchor>[];

    await tester.pumpWidget(
      qaApp(
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            height: 300,
            child: FullDiffMinimap(
              document: twoHunkDocument,
              activeAnchor: activeAnchor,
              sourceLineCount: 30,
              sourceSide: FileDocumentSide.result,
              view: FullDiffView.diff,
              presentation: DiffPresentation.inline,
              scrollController: scrollController,
              onAnchorSelected: (anchor) {
                selected.add(anchor);
                setState(() => activeAnchor = anchor);
              },
              onScrollFractionChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final minimap = find.semantics.byLabel('Diff minimap');
    var data = minimap.evaluate().single.getSemanticsData();
    expect(data.value, 'Change 1 of 2');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isFalse);

    tester.semantics.increase(minimap);
    await tester.pump();
    expect(selected.last, same(twoHunkDocument.hunks.last.anchor));
    data = minimap.evaluate().single.getSemanticsData();
    expect(data.value, 'Change 2 of 2');
    expect(data.hasAction(SemanticsAction.increase), isFalse);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);

    tester.semantics.decrease(minimap);
    await tester.pump();
    expect(selected.last, same(twoHunkDocument.hunks.first.anchor));
    semanticsHandle.dispose();
  });

  testWidgets('focused minimap uses arrow keys for previous and next hunks', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    var activeAnchor = twoHunkDocument.hunks.first.anchor;
    final selected = <DiffAnchor>[];

    await tester.pumpWidget(
      qaApp(
        StatefulBuilder(
          builder: (context, setState) => Center(
            child: SizedBox(
              height: 300,
              child: FullDiffMinimap(
                document: twoHunkDocument,
                activeAnchor: activeAnchor,
                sourceLineCount: 30,
                sourceSide: FileDocumentSide.result,
                view: FullDiffView.diff,
                presentation: DiffPresentation.inline,
                scrollController: scrollController,
                onAnchorSelected: (anchor) {
                  selected.add(anchor);
                  setState(() => activeAnchor = anchor);
                },
                onScrollFractionChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final minimap = find.byKey(const Key('full-diff-minimap'));
    final topLeft = tester.getTopLeft(minimap);
    await tester.tapAt(topLeft + const Offset(9, 1));
    await tester.pump();
    selected.clear();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(selected.last, same(twoHunkDocument.hunks.last.anchor));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(selected.last, same(twoHunkDocument.hunks.first.anchor));
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
            sourceSide: FileDocumentSide.result,
            view: FullDiffView.diff,
            presentation: DiffPresentation.hunk,
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

  testWidgets('empty hunk minimap paints no viewport or ring', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      qaApp(
        SizedBox(
          height: 100,
          child: FullDiffMinimap(
            document: DiffDocument.empty,
            activeAnchor: null,
            sourceLineCount: 0,
            sourceSide: FileDocumentSide.result,
            view: FullDiffView.diff,
            presentation: DiffPresentation.hunk,
            scrollController: scrollController,
            onAnchorSelected: (_) {},
            onScrollFractionChanged: (_) {},
          ),
        ),
      ),
    );

    final painter = _minimapPainter(tester);
    void paint(Canvas canvas) {
      painter.paint(canvas, const Size(fullDiffMinimapWidth, 100));
    }

    expect(painter.viewport, isNull);
    expect(
      paint,
      paints
        ..rect(color: fullDiffMinimapTrack)
        ..line(color: fullDiffDivider, strokeWidth: 1),
    );
    expect(paint, isNot(paints..rect(color: fullDiffMinimapViewport)));
    expect(
      paint,
      isNot(
        paints..rect(
          color: fullDiffMinimapRing,
          strokeWidth: 1,
          style: PaintingStyle.stroke,
        ),
      ),
    );
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
                sourceSide: FileDocumentSide.result,
                view: FullDiffView.diff,
                presentation: DiffPresentation.inline,
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

  for (final scenario in [
    (
      label: 'hunk',
      view: FullDiffView.diff,
      presentation: DiffPresentation.hunk,
      scrolls: false,
    ),
    (
      label: 'inline',
      view: FullDiffView.diff,
      presentation: DiffPresentation.inline,
      scrolls: true,
    ),
    (
      label: 'split',
      view: FullDiffView.diff,
      presentation: DiffPresentation.split,
      scrolls: true,
    ),
    (
      label: 'file',
      view: FullDiffView.file,
      presentation: DiffPresentation.hunk,
      scrolls: true,
    ),
    (
      label: 'blame',
      view: FullDiffView.blame,
      presentation: DiffPresentation.hunk,
      scrolls: true,
    ),
  ]) {
    testWidgets('${scenario.label} viewport drag uses the correct callback', (
      tester,
    ) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final selected = <DiffAnchor>[];
      final fractions = <double>[];

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
                  sourceSide: FileDocumentSide.result,
                  view: scenario.view,
                  presentation: scenario.presentation,
                  scrollController: scrollController,
                  onAnchorSelected: selected.add,
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
      await gesture.moveTo(topLeft + const Offset(9, 180));
      await tester.pump();
      await gesture.up();

      expect(fractions, scenario.scrolls ? isNotEmpty : isEmpty);
      expect(selected, scenario.scrolls ? isEmpty : isNotEmpty);
    });
  }
}

FullDiffMinimapPainter _minimapPainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byKey(const Key('full-diff-minimap')),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter! as FullDiffMinimapPainter;
}
