import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// 사이드바에서 ⌘클릭·⇧클릭으로 여러 ref를 골라 한 번에 지운다. 한 선택은 한
/// 섹션 안에서만 모이고, 체크아웃된 브랜치는 묶음에 들지 않으며, 대화상자는
/// 무엇이 몇 개 사라지는지 먼저 말한다.
class _RecordingRepository extends FakeGitRepository {
  _RecordingRepository(super.loader, {required super.refs});

  /// 시킨 순서대로. 하나가 거절당해도 나머지가 갔는지 이 목록이 말해 준다.
  final deleted = <String>[];

  /// 이 브랜치는 git이 거절한다 — 묶음의 나머지가 그대로 가는지 보려고 둔다.
  String? refuses;

  @override
  Future<void> deleteLocalBranch(String branch) async {
    if (branch == refuses) {
      throw ProcessException('git', ['branch', '-D', branch], 'refused');
    }
    deleted.add(branch);
  }

  @override
  Future<void> deleteTag(String tag) async => deleted.add('tag $tag');

  @override
  Future<void> deleteRemoteRef(String remote, String qualifiedRef) async =>
      deleted.add('$remote $qualifiedRef');
}

void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  const refs = RepoRefs(
    local: ['main', 'lane', 'spike', 'draft'],
    tags: ['v1.0', 'v0.9'],
    current: 'main',
    tips: {'main': '1', 'lane': '1', 'spike': '1', 'draft': '1', 'v1.0': '1'},
  );

  /// 기본 150pt 사이드바에서는 동작 줄이 버튼만 담을 만큼 좁아 이름 칸이 빠진다.
  /// 몇 개를 골랐는지 적는 칸까지 보려면 판을 넓게 두고 시작한다.
  Future<_RecordingRepository> pump(
    WidgetTester tester, {
    double sidebar = 280,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final repository = _RecordingRepository(
      (_, _) async => [commit('1', 'c')],
      refs: refs,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository,
          controller: controller,
          columnWidths: TimelineColumnWidths(sidebar: sidebar),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Finder row(String name) => find.byKey(Key('sidebar-ref-$name'));

  Future<void> tapRow(WidgetTester tester, String name) async {
    await tester.tap(row(name));
    await tester.pumpAndSettle();
  }

  /// ⌘를 누른 채로 한 행을 집는다.
  Future<void> commandTapRow(WidgetTester tester, String name) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(row(name));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  Future<void> shiftTapRow(WidgetTester tester, String name) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(row(name));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  String deleteTooltip(WidgetTester tester) => tester
      .widget<IconButton>(find.byKey(const Key('sidebar-action-delete')))
      .tooltip!;

  testWidgets('⌘클릭이 두 번째 행을 선택에 더한다', (tester) async {
    await pump(tester);
    await tapRow(tester, 'lane');
    await commandTapRow(tester, 'spike');

    // 처음 클릭한 행도 선택에 남는다 — 두 개가 모여야 묶음이다.
    expect(find.text('2개 선택'), findsOneWidget);
    expect(deleteTooltip(tester), '브랜치 2개 삭제');
  });

  testWidgets('⇧클릭이 커서와 그 행 사이를 한 번에 담는다', (tester) async {
    await pump(tester);
    await tapRow(tester, 'lane');
    await shiftTapRow(tester, 'draft');

    // LOCAL은 체크아웃된 브랜치가 앞장서므로 lane·spike·draft가 잇달아 선다.
    expect(find.text('3개 선택'), findsOneWidget);
  });

  testWidgets('묶음 삭제는 지우기 전에 이름을 다 말한다', (tester) async {
    final repository = await pump(tester);
    await tapRow(tester, 'lane');
    await commandTapRow(tester, 'spike');

    await tapKey(tester, 'sidebar-action-delete');

    expect(find.text('브랜치 2개를 삭제할까요?'), findsOneWidget);
    expect(find.text('lane'), findsWidgets);
    expect(find.text('spike'), findsWidgets);
    expect(repository.deleted, isEmpty, reason: '묻는 동안에는 아무것도 지우지 않는다');

    await tapKey(tester, 'delete-refs-confirm');

    expect(repository.deleted, ['lane', 'spike']);
    expect(find.textContaining('브랜치 2개 삭제됨'), findsOneWidget);
  });

  testWidgets('하나가 거절당해도 나머지는 간다', (tester) async {
    final repository = await pump(tester);
    repository.refuses = 'lane';
    await tapRow(tester, 'lane');
    await commandTapRow(tester, 'spike');

    await tapKey(tester, 'sidebar-action-delete');
    await tapKey(tester, 'delete-refs-confirm');

    expect(repository.deleted, ['spike']);
    expect(find.textContaining('1개 실패: lane'), findsOneWidget);
  });

  testWidgets('체크아웃된 브랜치는 묶음에 들지 않는다', (tester) async {
    final repository = await pump(tester);
    await tapRow(tester, 'lane');
    await commandTapRow(tester, 'main');

    // 두 행이 선택되어 있어도 지울 수 있는 것은 하나뿐이니, 하나짜리 대화상자다.
    expect(find.text('2개 선택'), findsOneWidget);
    expect(deleteTooltip(tester), '브랜치 삭제', reason: '수를 붙이지 않는다');

    await tapKey(tester, 'sidebar-action-delete');
    await tapKey(tester, 'delete-branch-confirm');

    expect(repository.deleted, ['lane']);
  });

  testWidgets('섹션이 다른 행을 집으면 선택이 다시 시작된다', (tester) async {
    await pump(tester);
    await tapRow(tester, 'lane');
    await commandTapRow(tester, 'spike');
    await commandTapRow(tester, 'v1.0');

    // 브랜치와 태그는 같은 손실이 아니라 한 대화상자에 함께 서지 않는다.
    expect(find.text('2개 선택'), findsNothing);
    expect(deleteTooltip(tester), '태그 삭제');
  });

  testWidgets('⇧↓도 걸어온 행들을 담는다', (tester) async {
    await pump(tester);
    await tapRow(tester, 'lane');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(deleteTooltip(tester), '브랜치 2개 삭제');

    // ⇧ 없이 한 칸 더 걸으면 묶음은 풀리고 커서 하나만 남는다.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(deleteTooltip(tester), '브랜치 삭제');
  });

  testWidgets('태그도 묶음으로 지운다', (tester) async {
    final repository = await pump(tester);
    await tapRow(tester, 'v1.0');
    await commandTapRow(tester, 'v0.9');

    expect(deleteTooltip(tester), '태그 2개 삭제');

    await tapKey(tester, 'sidebar-action-delete');
    expect(find.text('태그 2개를 삭제할까요?'), findsOneWidget);
    await tapKey(tester, 'delete-refs-confirm');

    expect(repository.deleted, ['tag v1.0', 'tag v0.9']);
  });

  testWidgets('한 행만 남으면 그 행의 원래 대화상자로 돌아간다', (tester) async {
    final repository = await pump(tester);
    await tapRow(tester, 'lane');
    await commandTapRow(tester, 'spike');
    // 집었던 것을 다시 집어 빼면 하나만 남는다.
    await commandTapRow(tester, 'spike');

    await tapKey(tester, 'sidebar-action-delete');

    expect(find.text('브랜치를 삭제할까요?'), findsOneWidget);
    await tapKey(tester, 'delete-branch-confirm');
    expect(repository.deleted, ['lane']);
  });
}
