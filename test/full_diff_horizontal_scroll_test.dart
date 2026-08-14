import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_side_by_side_view.dart';
import 'package:yogit/git.dart';

import 'support/full_diff_fixtures.dart';

/// One long line per side, plus a Korean one that a per-character estimate
/// would measure short.
DiffDocument _longLineDocument({String suffix = ''}) => DiffDocument.fromLines([
  const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,2 +1,2 @@ wide'),
  DiffLine(
    kind: DiffLineKind.delete,
    text: 'old ${'segment ' * 60}$suffix',
    oldNumber: 1,
  ),
  DiffLine(
    kind: DiffLineKind.add,
    text: 'new ${'조각 ' * 60}$suffix',
    newNumber: 1,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'tail',
    oldNumber: 2,
    newNumber: 2,
  ),
]);

Widget _sideBySide(DiffDocument document, {bool wrapLines = false}) => qaApp(
  SizedBox(
    width: 600,
    height: 200,
    child: SideBySidePresentationView(
      document: document,
      activeAnchor: document.hunks.single.anchor,
      oldPath: 'old.dart',
      newPath: 'new.dart',
      wrapLines: wrapLines,
      showOldSide: true,
      highlighter: fakeHighlighter,
      anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
    ),
  ),
);

final _horizontal = find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.right,
);

Future<void> _wheel(WidgetTester tester, double dx) async {
  final pointer = TestPointer(1, ui.PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(tester.getCenter(_horizontal)));
  await tester.sendEventToBinding(pointer.scroll(Offset(dx, 0)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('side-by-side moves both sides by one shared offset', (
    tester,
  ) async {
    await tester.pumpWidget(_sideBySide(_longLineDocument()));
    await tester.pumpAndSettle();

    expect(_horizontal, findsOneWidget);
    final position = tester.state<ScrollableState>(_horizontal).position;
    expect(position.maxScrollExtent, greaterThan(0));

    final oldSource = find
        .descendant(
          of: find.byKey(const Key('side-by-side-row-0-0')),
          matching: find.byKey(const Key('code-row-source-text')),
        )
        .first;
    final newSource = find
        .descendant(
          of: find.byKey(const Key('side-by-side-row-0-0')),
          matching: find.byKey(const Key('code-row-source-text')),
        )
        .last;
    final oldLeft = tester.getRect(oldSource).left;
    final newLeft = tester.getRect(newSource).left;
    final dividerLeft = tester
        .getRect(find.byKey(const Key('side-by-side-divider')))
        .left;
    final numberLeft = tester.getRect(find.text('1').first).left;

    await _wheel(tester, 120);

    expect(position.pixels, greaterThan(0));
    expect(
      oldLeft - tester.getRect(oldSource).left,
      moreOrLessEquals(position.pixels, epsilon: 0.5),
    );
    expect(
      newLeft - tester.getRect(newSource).left,
      moreOrLessEquals(position.pixels, epsilon: 0.5),
      reason: '반대쪽도 같은 거리를 간다',
    );
    expect(
      tester.getRect(find.byKey(const Key('side-by-side-divider'))).left,
      moreOrLessEquals(dividerLeft, epsilon: 0.5),
      reason: '분할 구분선은 제자리다',
    );
    expect(
      tester.getRect(find.text('1').first).left,
      moreOrLessEquals(numberLeft, epsilon: 0.5),
      reason: '줄 번호는 따라가지 않는다',
    );
  });

  testWidgets('the range reaches the end of the widest line, Hangul included', (
    tester,
  ) async {
    await tester.pumpWidget(_sideBySide(_longLineDocument()));
    await tester.pumpAndSettle();

    final position = tester.state<ScrollableState>(_horizontal).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    final hangulSource = find
        .descendant(
          of: find.byKey(const Key('side-by-side-row-0-0')),
          matching: find.byKey(const Key('code-row-source-text')),
        )
        .last;
    expect(
      tester.getRect(hangulSource).right,
      lessThanOrEqualTo(tester.getRect(_horizontal).right),
    );
  });

  testWidgets('a line narrower than its column still stops at the divider', (
    tester,
  ) async {
    await tester.pumpWidget(_sideBySide(_longLineDocument()));
    await tester.pumpAndSettle();
    await _wheel(tester, 120);

    // 'tail' fits its column, so the column has no overflow of its own to
    // clip -- but the shared offset slides it left all the same, out over the
    // divider and onto the other side, unless the column always clips.
    final pan = find
        .descendant(
          of: find.byKey(const Key('side-by-side-row-0-1')),
          matching: find.byKey(const Key('code-row-horizontal-pan')),
        )
        .last;
    expect(pan, findsOneWidget);
    expect(tester.renderObject(pan), paints..clipRect());
  });

  testWidgets('wrapped lines leave nothing to scroll', (tester) async {
    await tester.pumpWidget(_sideBySide(_longLineDocument(), wrapLines: true));
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(_horizontal).position.maxScrollExtent,
      0,
    );
  });

  testWidgets('a new document sends the pane back to column 0', (tester) async {
    await tester.pumpWidget(_sideBySide(_longLineDocument()));
    await tester.pumpAndSettle();
    await _wheel(tester, 120);
    expect(
      tester.state<ScrollableState>(_horizontal).position.pixels,
      greaterThan(0),
    );

    await tester.pumpWidget(_sideBySide(_longLineDocument(suffix: ' more')));
    await tester.pumpAndSettle();

    expect(tester.state<ScrollableState>(_horizontal).position.pixels, 0);
  });
}
