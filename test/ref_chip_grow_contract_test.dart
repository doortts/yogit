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
              commit('a', 'tip', parents: ['b'], refs: [GitRef(name: name)]),
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

  testWidgets('a cut name opens whole under the mouse', (tester) async {
    await pump(tester, name: long);
    // 칸이 좁아 앞이 잘려 있다.
    expect(
      tester.widget<Text>(
        find.descendant(of: chip(long), matching: find.byType(Text)),
      ).data,
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

  testWidgets('it keeps the chip it grew out of', (tester) async {
    await pump(tester, name: long);
    final cut = tester.widget<Container>(chip(long)).decoration! as BoxDecoration;

    await hover(tester, chip(long));
    final grown =
        tester.widget<Container>(whole(long)).decoration! as BoxDecoration;

    expect(grown.color, cut.color, reason: '같은 색 판');
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

    expect(
      whole('main'),
      findsNothing,
      reason: '이미 읽히는 것을 덮는 건 방해다',
    );
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
