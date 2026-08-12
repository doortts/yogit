import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// docs/ref-name-hover-mockup.html — B안. 칸이 이름을 앞에서 잘라 놓으면 앞이
/// 통째로 사라져 어느 브랜치인지 못 읽는다. 마우스가 올라간 동안 칩이 제자리에서
/// 전체 이름만큼 자라 GRAPH 칸 위로 넘어간다. 색과 테두리는 그대로 들고 간다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  const long = 'main-before-a-very-long-palette-merge';

  Future<void> pump(
    WidgetTester tester, {
    required String name,
    double refsWidth = 120,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit(
                'a',
                'tip',
                parents: ['b'],
                refs: [GitRef(name: name)],
              ),
              commit('b', 'root'),
            ],
          ),
          controller: controller,
          columnWidths: TimelineColumnWidths(refs: refsWidth),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
    return mouse;
  }

  Finder chip(String name) => find.byKey(Key('ref-chip-a-$name'));
  Finder whole(String name) => find.byKey(Key('ref-chip-whole-a-$name'));
  Finder reveal(String name) => find.byKey(Key('ref-chip-reveal-a-$name'));

  testWidgets('a cut name opens whole under the mouse', (tester) async {
    await pump(tester, name: long);
    // 칸이 좁아 앞이 잘려 있다.
    expect(
      tester
          .widget<Text>(
            find.descendant(of: chip(long), matching: find.byType(Text)),
          )
          .data,
      isNot(long),
    );
    expect(whole(long), findsNothing, reason: '마우스가 오기 전에는 없다');

    await hover(tester, chip(long));

    expect(whole(long), findsOneWidget);
    expect(
      find.descendant(of: whole(long), matching: find.text(long)),
      findsOneWidget,
      reason: '전체 이름이 통째로 보인다',
    );
  });

  testWidgets(
    'it hides the cut name it grew out of, rather than lying over it',
    (tester) async {
      await pump(tester, name: long);
      await hover(tester, chip(long));

      final cut = tester.getRect(chip(long));
      final grown = tester.getRect(whole(long));
      final decoration =
          tester.widget<Container>(whole(long)).decoration! as BoxDecoration;

      // 판이 비치면 밑에 깔린 잘린 이름이 겹쳐 읽힌다.
      expect(decoration.color!.a, 1.0, reason: '자란 칩의 판은 불투명하다');
      // 그리고 원래 칩을 남김없이 덮는다 — 위아래로 한 줄도 새어 나오면 안 된다.
      expect(grown.top, cut.top);
      expect(grown.bottom, cut.bottom);
      expect(grown.left, cut.left);
      expect(grown.right, greaterThanOrEqualTo(cut.right));
    },
  );

  testWidgets('it keeps the chip it grew out of', (tester) async {
    await pump(tester, name: long);
    final cut =
        tester.widget<Container>(chip(long)).decoration! as BoxDecoration;

    await hover(tester, chip(long));
    final grown =
        tester.widget<Container>(whole(long)).decoration! as BoxDecoration;

    // 판은 불투명해졌지만 눈에는 같은 색이다 — 원래 색을 행 위에 얹은 값이다.
    expect(
      grown.color,
      Color.alphaBlend(cut.color!, const Color(0xFF1C1C1E)),
      reason: '같은 색으로 보이되 비치지 않는다',
    );
    expect(
      (grown.border! as Border).top.color,
      (cut.border! as Border).top.color,
    );
    expect(grown.borderRadius, cut.borderRadius);
  });

  testWidgets('it starts where the cut chip stood and reaches further', (
    tester,
  ) async {
    await pump(tester, name: long);
    final before = tester.getRect(chip(long));

    await hover(tester, chip(long));
    final after = tester.getRect(whole(long));

    expect(after.left, before.left, reason: '자리는 그대로다 — 길어질 뿐이다');
    expect(after.width, greaterThan(before.width));
    expect(
      after.right,
      greaterThan(tester.getRect(find.byKey(const Key('refs-cell-0'))).right),
      reason: '칸 밖으로 넘어가도 된다',
    );
  });

  testWidgets('a name that already fits stays quiet', (tester) async {
    await pump(tester, name: 'main', refsWidth: 200);

    await hover(tester, chip('main'));

    expect(whole('main'), findsNothing, reason: '이미 읽히는 것을 덮는 건 방해다');
  });

  testWidgets('a row full of chips reads one name at a time', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    const first = 'v2-monaco-slash-commands';
    const second = 'v2-monaco-image-attach';
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit(
                'a',
                'tip',
                parents: ['b'],
                refs: const [
                  GitRef(name: first),
                  GitRef(name: second),
                ],
              ),
              commit('b', 'root'),
            ],
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(refs: 180),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final neighbour = tester.getRect(chip(second));
    await hover(tester, chip(first));

    // 옆 칩 위로 지나가지만 판이 불투명해서 두 이름이 겹쳐 읽히지 않는다.
    final grown = tester.getRect(whole(first));
    expect(grown.right, greaterThan(neighbour.left));
    expect(
      (tester.widget<Container>(whole(first)).decoration! as BoxDecoration)
          .color!
          .a,
      1.0,
    );
    // 그리고 마우스가 올라간 그 칩만 열린다.
    expect(whole(second), findsNothing);
  });

  testWidgets('it opens over time instead of appearing at full width', (
    tester,
  ) async {
    await pump(tester, name: long);
    final cut = tester.getRect(chip(long));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(chip(long)));
    await tester.pump();

    // 첫 프레임에는 잘린 칩 폭 그대로다 — 튀어나오지 않는다.
    expect(tester.getRect(reveal(long)).width, closeTo(cut.width, 1));

    // 중간 프레임은 그 사이 어딘가에 있다.
    await tester.pump(GrowingChip.openDuration ~/ 2);
    final midway = tester.getRect(reveal(long)).width;
    expect(midway, greaterThan(cut.width));

    await tester.pumpAndSettle();
    expect(tester.getRect(whole(long)).width, greaterThan(midway));

    // 그리고 닫히는 길도 한 번에 사라지지 않는다.
    await mouse.moveTo(const Offset(1200, 700));
    await tester.pump();
    final closing = tester.getRect(reveal(long)).width;
    await tester.pump(GrowingChip.closeDuration ~/ 2);
    expect(whole(long), findsOneWidget, reason: '물러나는 동안에도 붙어 있다');
    expect(tester.getRect(reveal(long)).width, lessThan(closing));
  });

  testWidgets('the tail stays put and the cut head arrives from the left', (
    tester,
  ) async {
    await pump(tester, name: long);
    final cut = tester.getRect(chip(long));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(chip(long)));
    await tester.pump();

    // 이름은 앞에서 잘린다. 읽고 있던 것은 꼬리이므로 첫 프레임에서 꼬리가 있던
    // 자리를 그대로 지켜야 한다 — 여기가 어긋나면 아무리 천천히 열려도 글자가
    // 통째로 바뀐 것으로 보인다.
    expect(tester.getRect(whole(long)).right, closeTo(cut.right, 1));
    // 머리는 아직 창 왼쪽 밖에 있다.
    expect(tester.getRect(whole(long)).left, lessThan(cut.left));

    await tester.pumpAndSettle();

    // 다 열리면 잘린 칩이 서 있던 그 자리에서 시작한다.
    expect(tester.getRect(whole(long)).left, closeTo(cut.left, 1));
  });

  testWidgets('a name one point too wide for its chip still opens', (
    tester,
  ) async {
    // 잘림을 판정하는 계산이 칩의 여백을 실제보다 좁게 알고 있으면, 딱 그 차이만큼
    // 넘치는 이름들만 열리지 않는다. 눈에는 잘려 있는데 마우스를 올려도 아무 일이
    // 없고, 어느 폭에서 그러는지 알기 전에는 재현도 안 된다. 그래서 폭을 훑는 대신
    // 경계를 직접 만든다.
    const name = 'fix/v2-core-window-bugs';
    const inset = 14.0 * 2;

    // 먼저 이 이름이 통째로 서려면 몇 점이 필요한지 앱에게 물어본다.
    await pump(tester, name: name, refsWidth: 100);
    var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(chip(name)));
    await tester.pumpAndSettle();
    final natural = tester.getSize(whole(name)).width;
    await mouse.removePointer();
    await tester.pumpAndSettle();

    // 그 언저리를 한 점씩 오가며, 잘렸으면 예외 없이 열리는지 본다. 어긋남은
    // 몇 점 폭의 창으로만 나타나므로 경계를 비껴가면 아무것도 못 잡는다.
    for (var slack = -2.0; slack <= 3; slack += 1) {
      await pump(tester, name: name, refsWidth: natural + slack + inset);
      final shown = tester
          .widgetList<Text>(
            find.descendant(of: chip(name), matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .join();
      if (shown == name) continue;

      mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(chip(name)));
      await tester.pumpAndSettle();
      expect(
        whole(name),
        findsOneWidget,
        reason: '여유 $slack점: "$shown"으로 잘렸는데 열리지 않는다',
      );
      await mouse.removePointer();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('it closes when the mouse leaves', (tester) async {
    await pump(tester, name: long);
    final mouse = await hover(tester, chip(long));
    expect(whole(long), findsOneWidget);

    await mouse.moveTo(const Offset(1200, 700));
    await tester.pumpAndSettle();

    expect(whole(long), findsNothing);
  });

  testWidgets('the rows underneath stay reachable', (tester) async {
    await pump(tester, name: long);
    await hover(tester, chip(long));

    expect(
      find.ancestor(
        of: whole(long),
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsOneWidget,
      reason: '읽는 중이지 겨냥하는 중이 아니다',
    );
  });
}
