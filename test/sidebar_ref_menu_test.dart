import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// 로컬 브랜치와 태그 이름도 더블클릭하면 원격 행처럼 메뉴가 열린다. 메뉴는 그
/// ref가 할 수 있는 일만 눌리게 두고, 못 하는 일은 자리에 남긴 채 흐리게 둔다.
/// 삭제는 세 섹션이 각각 다른 것을 지운다 — 로컬 브랜치, 원격의 브랜치, 태그.
class _RecordingRepository extends FakeGitRepository {
  _RecordingRepository(super.loader, {required super.refs});

  /// 지운 것들을 시킨 순서대로. 원격이 먼저인지도 이 목록이 말해 준다.
  final deleted = <String>[];

  @override
  Future<void> deleteRemoteRef(String remote, String qualifiedRef) async =>
      deleted.add('$remote $qualifiedRef');

  @override
  Future<void> deleteTag(String tag) async => deleted.add('tag $tag');
}

void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  const refs = RepoRefs(
    local: ['main', 'lane'],
    remote: ['origin/lane'],
    remoteNames: ['origin'],
    tags: ['v1.0'],
    current: 'main',
    tips: {'main': '1', 'lane': '1', 'origin/lane': '1', 'v1.0': '1'},
  );

  Future<_RecordingRepository> pump(WidgetTester tester) async {
    final repository = _RecordingRepository(
      (_, _) async => [commit('1', 'c')],
      refs: refs,
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> doubleTap(WidgetTester tester, String name) async {
    final row = find.byKey(Key('sidebar-ref-$name'));
    await tester.tap(row);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
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

  testWidgets('a tag offers the comparison and its own deletion', (
    tester,
  ) async {
    await pump(tester);
    await doubleTap(tester, 'v1.0');

    expect(find.byKey(const Key('sidebar-menu-header-v1.0')), findsOneWidget);
    expect(actionOf(tester, 'sidebar-menu-compare-v1.0'), isNotNull);
    expect(actionOf(tester, 'sidebar-menu-delete-v1.0'), isNotNull);
    // 태그는 체크아웃 대상도 기준도 아니라 항목 자체가 없다.
    expect(find.byKey(const Key('sidebar-menu-checkout-v1.0')), findsNothing);
    expect(find.byKey(const Key('sidebar-menu-base-v1.0')), findsNothing);
  });

  testWidgets('the remote branch deletion goes up to the remote', (
    tester,
  ) async {
    final repository = await pump(tester);
    await doubleTap(tester, 'origin/lane');
    expect(actionOf(tester, 'remote-pull-delete'), isNotNull);

    await tapKey(tester, 'remote-pull-delete');
    // 원격을 건드리는 유일한 삭제다 — 무엇이 사라지는지 먼저 말한다.
    expect(find.text('원격 브랜치를 삭제할까요?'), findsOneWidget);
    expect(repository.deleted, isEmpty, reason: '묻는 동안에는 아무것도 지우지 않는다');

    await tapKey(tester, 'delete-remote-branch-confirm');

    expect(repository.deleted, ['origin refs/heads/lane']);
    expect(find.textContaining('origin/lane 삭제됨'), findsOneWidget);
  });

  testWidgets('a tag can die locally alone or on the remote too', (
    tester,
  ) async {
    final repository = await pump(tester);
    await doubleTap(tester, 'v1.0');
    await tapKey(tester, 'sidebar-menu-delete-v1.0');

    // 원격이 있으면 두 반경을 함께 내민다: 로컬만, 아니면 원격까지.
    expect(find.byKey(const Key('delete-tag-confirm')), findsOneWidget);
    expect(find.byKey(const Key('delete-tag-remote-confirm')), findsOneWidget);

    await tapKey(tester, 'delete-tag-confirm');
    expect(repository.deleted, ['tag v1.0']);

    repository.deleted.clear();
    await doubleTap(tester, 'v1.0');
    await tapKey(tester, 'sidebar-menu-delete-v1.0');
    await tapKey(tester, 'delete-tag-remote-confirm');

    // 원격이 먼저다: 거절당하면 태그는 양쪽에 그대로 남는다.
    expect(repository.deleted, ['origin refs/tags/v1.0', 'tag v1.0']);
  });

  testWidgets('menu lines stand apart, each behind its own icon', (
    tester,
  ) async {
    await pump(tester);
    await doubleTap(tester, 'lane');

    // 아이콘은 행 위에 뜨는 버튼들과 같은 그림이다: 같은 일에 같은 표시.
    const icons = {
      'sidebar-menu-checkout-lane': Icons.logout,
      'sidebar-menu-base-lane': Icons.anchor,
      'sidebar-menu-compare-lane': Icons.compare_arrows,
      'sidebar-menu-delete-lane': Icons.delete_outline,
    };
    for (final entry in icons.entries) {
      expect(
        find.descendant(
          of: find.byKey(Key(entry.key)),
          matching: find.byIcon(entry.value),
        ),
        findsOneWidget,
        reason: entry.key,
      );
    }

    // 그리고 알약끼리 붙어 있지 않다 — 붙으면 제목이 윗 항목의 세 번째 줄로
    // 읽힌다.
    final checkout = tester.getRect(
      find.byKey(const Key('sidebar-menu-checkout-lane')),
    );
    final base = tester.getRect(
      find.byKey(const Key('sidebar-menu-base-lane')),
    );
    expect(base.top - checkout.bottom, greaterThanOrEqualTo(4));
  });

  testWidgets('the strip deletes whatever kind of ref the cursor holds', (
    tester,
  ) async {
    final repository = await pump(tester);
    await tester.tap(find.byKey(const Key('sidebar-ref-origin/lane')));
    await tester.pumpAndSettle();

    await tapKey(tester, 'sidebar-action-delete');
    await tapKey(tester, 'delete-remote-branch-confirm');

    expect(repository.deleted, ['origin refs/heads/lane']);
  });
}
