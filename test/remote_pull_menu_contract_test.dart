import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// 원격 브랜치 행을 더블클릭하면, fast-forward로 받을 게 있는 한 줄기 말고는
/// 상태를 말해 주는 메뉴가 열린다. 갈라진 브랜치와 로컬이 없는 브랜치는 더블
/// 클릭으로 아무것도 바꾸지 않는다 — 메뉴가 무엇을 할 수 있는지 먼저 보인다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  const refs = RepoRefs(
    local: ['main', 'lane', 'split'],
    remote: ['origin/lane', 'origin/new-lane', 'origin/split'],
    remoteNames: ['origin'],
    current: 'main',
    tips: {'main': '1', 'lane': '1', 'split': '1'},
    remoteAheadBehind: {
      'origin/lane': BranchAheadBehind(ahead: 3, behind: 0),
      'origin/split': BranchAheadBehind(ahead: 2, behind: 3),
    },
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository((_, _) async => [commit('1', 'c')], refs: refs),
        controller,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> doubleTap(WidgetTester tester, String name) async {
    final row = find.byKey(Key('sidebar-ref-$name'));
    await tester.tap(row);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  VoidCallback? actionOf(WidgetTester tester, String key) =>
      tester.widget<MenuItemButton>(find.byKey(Key(key))).onPressed;

  testWidgets('a diverged remote opens the menu instead of pulling', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const Key('remote-pull-header')), findsNothing);

    await doubleTap(tester, 'origin/split');

    expect(find.byKey(const Key('remote-pull-header')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('remote-pull-header')),
        matching: find.text('origin/split'),
      ),
      findsOneWidget,
    );
    // 갈라진 상태에서 pull은 자리만 지키고 눌리지 않는다. 비교는 열려 있다.
    expect(actionOf(tester, 'remote-pull-pull'), isNull);
    expect(actionOf(tester, 'remote-pull-compare'), isNotNull);
    expect(actionOf(tester, 'remote-pull-checkout'), isNotNull);
  });

  testWidgets('a remote with no local branch offers the checkout', (
    tester,
  ) async {
    await pump(tester);
    await doubleTap(tester, 'origin/new-lane');

    expect(find.text('로컬 브랜치 없음'), findsOneWidget);
    // pull 항목은 아예 없다 — 받아올 로컬이 없다.
    expect(find.byKey(const Key('remote-pull-pull')), findsNothing);
    expect(actionOf(tester, 'remote-pull-checkout'), isNotNull);
  });
}
