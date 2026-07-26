import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_hunk_view.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/git.dart';

void main() {
  testWidgets('shows readable hunk cards without raw patch headers', (
    tester,
  ) async {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.header, text: 'diff --git a/a.pas b/a.pas'),
      DiffLine(
        kind: DiffLineKind.hunk,
        text: '@@ -10,2 +10,2 @@ procedure ConfigureWindow',
      ),
      DiffLine(kind: DiffLineKind.delete, text: 'Scale := 1;', oldNumber: 10),
      DiffLine(
        kind: DiffLineKind.add,
        text: 'Scale := PixelRatio;',
        newNumber: 10,
      ),
    ]);

    await _pumpHunkList(tester, document: document);

    expect(find.text('−10,2  +10,2'), findsOneWidget);
    expect(find.text('procedure ConfigureWindow'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.textContaining('diff --git'), findsNothing);
    expect(find.text('−'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
  });

  testWidgets('shows surrounding context and exact add and delete fills', (
    tester,
  ) async {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,7 +10,7 @@ build'),
      DiffLine(
        kind: DiffLineKind.context,
        text: 'context before 1',
        oldNumber: 10,
        newNumber: 10,
      ),
      DiffLine(
        kind: DiffLineKind.context,
        text: 'context before 2',
        oldNumber: 11,
        newNumber: 11,
      ),
      DiffLine(
        kind: DiffLineKind.context,
        text: 'context before 3',
        oldNumber: 12,
        newNumber: 12,
      ),
      DiffLine(kind: DiffLineKind.delete, text: 'old value', oldNumber: 13),
      DiffLine(kind: DiffLineKind.add, text: 'new value', newNumber: 13),
      DiffLine(
        kind: DiffLineKind.context,
        text: 'context after 1',
        oldNumber: 14,
        newNumber: 14,
      ),
      DiffLine(
        kind: DiffLineKind.context,
        text: 'context after 2',
        oldNumber: 15,
        newNumber: 15,
      ),
      DiffLine(
        kind: DiffLineKind.context,
        text: 'context after 3',
        oldNumber: 16,
        newNumber: 16,
      ),
    ]);
    final anchor = document.hunks.single.anchor.id;

    await _pumpHunkList(tester, document: document, height: 420);

    for (final text in const [
      'context before 1',
      'context before 2',
      'context before 3',
      'old value',
      'new value',
      'context after 1',
      'context after 2',
      'context after 3',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(
      tester.widget<ColoredBox>(find.byKey(Key('hunk-line-$anchor-3'))).color,
      const Color(0xFFF29AB2).withValues(alpha: 0.15),
    );
    expect(
      tester.widget<ColoredBox>(find.byKey(Key('hunk-line-$anchor-4'))).color,
      const Color(0xFF8AD6A1).withValues(alpha: 0.15),
    );
  });

  testWidgets('marks the active hunk and selects a tapped card', (
    tester,
  ) async {
    final document = _twoHunkDocument();
    final firstAnchor = document.hunks.first.anchor.id;
    final secondAnchor = document.hunks.last.anchor.id;
    int? selectedIndex;

    await _pumpHunkList(
      tester,
      document: document,
      activeHunkIndex: 1,
      onHunkSelected: (index) => selectedIndex = index,
      height: 360,
    );

    BoxDecoration decorationOf(String anchor) =>
        tester
                .widget<DecoratedBox>(
                  find.byKey(Key('hunk-card-surface-$anchor')),
                )
                .decoration
            as BoxDecoration;
    expect(
      (decorationOf(secondAnchor).border! as Border).top.color,
      const Color(0xFF3A4657),
    );
    expect(
      (decorationOf(firstAnchor).border! as Border).top.color,
      isNot(const Color(0xFF3A4657)),
    );
    final selectedSemantics = tester.widget<Semantics>(
      find.descendant(
        of: find.byKey(ValueKey(secondAnchor)),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      ),
    );
    expect(selectedSemantics.properties.button, isTrue);
    expect(selectedSemantics.properties.onTap, isNotNull);

    await tester.tap(find.byKey(ValueKey(firstAnchor)));

    expect(selectedIndex, 0);
  });

  testWidgets('keeps one selection area inside each mounted hunk card', (
    tester,
  ) async {
    final document = _twoHunkDocument();

    await _pumpHunkList(tester, document: document, height: 360);

    for (final hunk in document.hunks) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(hunk.anchor.id)),
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.ancestor(
        of: find.byKey(const Key('hunk-list')),
        matching: find.byType(SelectionArea),
      ),
      findsNothing,
    );
  });

  testWidgets('shows a deliberate empty state without a list', (tester) async {
    await _pumpHunkList(tester, document: DiffDocument.empty);

    expect(find.text('No changes'), findsOneWidget);
    expect(find.byType(HunkCard), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('builds distant hunks only when they scroll into view', (
    tester,
  ) async {
    final document = _manyHunkDocument(100);
    final firstAnchor = document.hunks.first.anchor.id;
    final lastAnchor = document.hunks.last.anchor.id;

    await _pumpHunkList(tester, document: document, height: 160);

    expect(find.byKey(ValueKey(firstAnchor)), findsOneWidget);
    expect(find.byKey(ValueKey(lastAnchor)), findsNothing);
    final list = tester.widget<ListView>(find.byKey(const Key('hunk-list')));
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());

    await tester.scrollUntilVisible(
      find.byKey(ValueKey(lastAnchor)),
      600,
      scrollable: find.descendant(
        of: find.byKey(const Key('hunk-list')),
        matching: find.byType(Scrollable),
      ),
    );

    expect(find.byKey(ValueKey(lastAnchor)), findsOneWidget);
  });

  testWidgets('scrolls long source rows horizontally when wrapping is off', (
    tester,
  ) async {
    const longLine =
        'final configuration = application.window.pixelRatio * '
        'application.window.displayScale * application.window.zoom;';
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@ configure'),
      DiffLine(
        kind: DiffLineKind.context,
        text: longLine,
        oldNumber: 1,
        newNumber: 1,
      ),
    ]);
    final anchor = document.hunks.single.anchor.id;

    await _pumpHunkList(
      tester,
      document: document,
      wrapLines: false,
      width: 320,
      height: 220,
    );

    final horizontal = find.descendant(
      of: find.byKey(ValueKey(anchor)),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
    );
    expect(horizontal, findsOneWidget);
    final scrollView = tester.widget<SingleChildScrollView>(horizontal);
    expect(
      tester.getSize(find.byWidget(scrollView.child!)).width,
      greaterThan(tester.getSize(horizontal).width),
    );
    final scrollable = find.descendant(
      of: horizontal,
      matching: find.byType(Scrollable),
    );

    await tester.drag(horizontal, const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('wraps source text without a horizontal scroll view', (
    tester,
  ) async {
    const longLine =
        'final configuration = application.window.pixelRatio * '
        'application.window.displayScale * application.window.zoom;';
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@ configure'),
      DiffLine(
        kind: DiffLineKind.context,
        text: longLine,
        oldNumber: 1,
        newNumber: 1,
      ),
    ]);
    final anchor = document.hunks.single.anchor.id;

    await _pumpHunkList(tester, document: document, width: 320, height: 260);

    expect(
      find.descendant(
        of: find.byKey(ValueKey(anchor)),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
    expect(tester.widget<Text>(find.text(longLine)).softWrap, isTrue);
  });
}

Future<void> _pumpHunkList(
  WidgetTester tester, {
  required DiffDocument document,
  int activeHunkIndex = 0,
  bool wrapLines = true,
  ValueChanged<int>? onHunkSelected,
  double width = 640,
  double height = 300,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: HunkListView(
            document: document,
            activeHunkIndex: activeHunkIndex,
            wrapLines: wrapLines,
            onHunkSelected: onHunkSelected ?? (_) {},
          ),
        ),
      ),
    ),
  ),
);

DiffDocument _twoHunkDocument() => DiffDocument.fromLines(const [
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@ first'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'first line',
    oldNumber: 1,
    newNumber: 1,
  ),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -20 +20 @@ second'),
  DiffLine(kind: DiffLineKind.add, text: 'second line', newNumber: 20),
]);

DiffDocument _manyHunkDocument(int count) {
  final lines = <DiffLine>[];
  for (var index = 0; index < count; index++) {
    final number = index + 1;
    lines
      ..add(
        DiffLine(
          kind: DiffLineKind.hunk,
          text: '@@ -$number +$number @@ hunk $number',
        ),
      )
      ..add(
        DiffLine(
          kind: DiffLineKind.add,
          text: 'line $number',
          newNumber: number,
        ),
      );
  }
  return DiffDocument.fromLines(lines);
}
