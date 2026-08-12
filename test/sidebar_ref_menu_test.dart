import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// 로컬 브랜치와 태그 이름도 더블클릭하면 원격 행처럼 메뉴가 열린다. 메뉴는 그
/// ref가 할 수 있는 일만 눌리게 두고, 못 하는 일은 자리에 남긴 채 흐리게 둔다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  const refs = RepoRefs(
    local: ['main', 'lane'],
    tags: ['v1.0'],
    current: 'main',
    tips: {'main': '1', 'lane': '1', 'v1.0': '1'},
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

  testWidgets('a local branch opens the menu on double-click', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('sidebar-menu-header-lane')), findsNothing);

    await doubleTap(tester, 'lane');

    expect(find.byKey(const Key('sidebar-menu-header-lane')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('sidebar-menu-header-lane')),
        matching: find.text('lane'),
      ),
      findsOneWidget,
    );
    expect(actionOf(tester, 'sidebar-menu-checkout-lane'), isNotNull);
    expect(actionOf(tester, 'sidebar-menu-base-lane'), isNotNull);
    expect(actionOf(tester, 'sidebar-menu-compare-lane'), isNotNull);
    expect(actionOf(tester, 'sidebar-menu-hide-lane'), isNotNull);
    expect(actionOf(tester, 'sidebar-menu-delete-lane'), isNotNull);
  });

  testWidgets('the checked-out branch keeps its impossible actions in place', (
    tester,
  ) async {
    await pump(tester);
    await doubleTap(tester, 'main');

    expect(find.text('체크아웃된 브랜치 · 기준 브랜치'), findsOneWidget);
    // git은 체크아웃된 브랜치를 지우지 못하고, 서 있는 자리로 다시 전환할 것도
    // 없다. 항목은 자리에 남지만 눌리지 않는다.
    expect(actionOf(tester, 'sidebar-menu-checkout-main'), isNull);
    expect(actionOf(tester, 'sidebar-menu-delete-main'), isNull);
    // 체크아웃된 브랜치는 숨겨도 HEAD로 그래프에 남으므로 숨기기도 막힌다.
    expect(actionOf(tester, 'sidebar-menu-hide-main'), isNull);
  });

  testWidgets('a tag offers the comparison and no branch action', (
    tester,
  ) async {
    await pump(tester);
    await doubleTap(tester, 'v1.0');

    expect(find.byKey(const Key('sidebar-menu-header-v1.0')), findsOneWidget);
    expect(actionOf(tester, 'sidebar-menu-compare-v1.0'), isNotNull);
    // 태그는 체크아웃·기준·삭제의 대상이 아니라 항목 자체가 없다.
    expect(find.byKey(const Key('sidebar-menu-checkout-v1.0')), findsNothing);
    expect(find.byKey(const Key('sidebar-menu-base-v1.0')), findsNothing);
    expect(find.byKey(const Key('sidebar-menu-delete-v1.0')), findsNothing);
  });
}
