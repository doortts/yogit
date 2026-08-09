import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// docs/sidebar-and-row-branch-design.md §4 — 사이드바 행 정리: 숨기기 눈은 맨
/// 왼쪽에, 숨긴 행은 제자리에, 원격 행도 커밋 차이와 마지막 갱신 시각을 잃지
/// 않는다. 행에 붙어 있던 ↓ 버튼은 없앤다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  const remoteTip = 1700000000;
  const tagTime = 1699000000;

  const refs = RepoRefs(
    local: ['main', 'alpha', 'deep/nested/leaf'],
    remote: ['origin/main', 'origin/alpha'],
    remoteNames: ['origin'],
    tags: ['v1.0'],
    current: 'main',
    tips: {
      'main': 'main-tip',
      'alpha': 'alpha-tip',
      'deep/nested/leaf': 'leaf-tip',
      'origin/main': 'main-tip',
      'origin/alpha': 'origin-alpha-tip',
      'v1.0': 'main-tip',
    },
    localTips: {
      'main': 'main-tip',
      'alpha': 'alpha-tip',
      'deep/nested/leaf': 'leaf-tip',
    },
    branchActivityTimes: {'origin/alpha': remoteTip, 'origin/main': remoteTip},
    tagCreatorTimes: {'v1.0': tagTime},
    aheadBehind: {'alpha': BranchAheadBehind(ahead: 4, behind: 0)},
    remoteAheadBehind: {'origin/alpha': BranchAheadBehind(ahead: 0, behind: 4)},
    upstreams: {'alpha': 'origin/alpha'},
    upstreamRemotes: {'alpha': 'origin'},
  );

  late TestGesture mouse;

  Future<void> pump(WidgetTester tester) async {
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
            (_, _) async => [commit('main-tip', 'only commit')],
            refs: refs,
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(sidebar: 320),
        ),
      ),
    );
    await tester.pumpAndSettle();
    mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
  }

  Future<void> hover(WidgetTester tester, Finder target) async {
    await mouse.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
  }

  Finder row(String name) => find.byKey(Key('sidebar-row-$name'));
  Finder eye(String name) => find.byKey(Key('sidebar-hide-$name'));

  testWidgets('the eye hugs the left edge whatever the depth', (tester) async {
    await pump(tester);

    await hover(tester, row('alpha'));
    final shallow = tester.getRect(eye('alpha'));

    await hover(tester, row('deep/nested/leaf'));
    final deep = tester.getRect(eye('deep/nested/leaf'));

    expect(deep.left, shallow.left, reason: '트리 들여쓰기가 눈을 밀면 안 된다');
    expect(
      shallow.left,
      lessThan(tester.getRect(row('alpha')).left + 22),
      reason: '행 맨 왼쪽 칸 안에 있다',
    );
  });

  testWidgets('hiding a ref leaves its row where it was', (tester) async {
    await pump(tester);
    final before = [
      for (final name in ['main', 'alpha', 'deep/nested/leaf'])
        tester.getRect(row(name)).top,
    ];

    await hover(tester, row('alpha'));
    await tester.tap(eye('alpha'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    expect(
      [
        for (final name in ['main', 'alpha', 'deep/nested/leaf'])
          tester.getRect(row(name)).top,
      ],
      before,
      reason: '숨겼다고 목록 아래로 내려보내지 않는다',
    );
  });

  testWidgets('a remote row keeps its counts under the cursor', (tester) async {
    await pump(tester);
    final badge = find.byKey(
      const Key('sidebar-remote-divergence-origin/alpha'),
    );
    expect(badge, findsOneWidget);

    await hover(tester, row('origin/alpha'));
    expect(badge, findsOneWidget, reason: 'hover에 숫자가 사라지면 안 된다');

    await tester.tap(row('origin/alpha'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(badge, findsOneWidget, reason: '선택해도 숫자는 남는다');
  });

  testWidgets('the row-level pull button is gone', (tester) async {
    await pump(tester);
    await hover(tester, row('origin/alpha'));

    // 행 위에는 ↓가 없다 — pull은 액션 스트립과 더블클릭이 맡는다.
    expect(
      find.descendant(
        of: row('origin/alpha'),
        matching: find.byIcon(Icons.arrow_downward),
      ),
      findsNothing,
    );
  });

  testWidgets('a remote branch and a tag say when they last moved', (
    tester,
  ) async {
    await pump(tester);

    String label(int seconds) => socialTimeLabel(
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
      DateTime.now(),
    );

    expect(
      find.descendant(
        of: row('origin/alpha'),
        matching: find.text(label(remoteTip)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('v1.0'), matching: find.text(label(tagTime))),
      findsOneWidget,
    );
  });
}
