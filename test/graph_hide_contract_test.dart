import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// docs/sidebar-and-row-branch-design.md §2 — 사이드바의 눈 아이콘이 ref를
/// 그래프에서 숨긴다. 숨긴다는 것은 **로그의 출발점에서 뺀다**는 뜻이다: 다른
/// 보이는 ref에서도 닿는 커밋은 그대로 남는다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  const refs = RepoRefs(
    local: ['main', 'feature/one', 'feature/two'],
    current: 'main',
    tips: {
      'main': 'main-tip',
      'feature/one': 'one-tip',
      'feature/two': 'two-tip',
    },
    localTips: {
      'main': 'main-tip',
      'feature/one': 'one-tip',
      'feature/two': 'two-tip',
    },
  );

  late List<Set<String>> asked;
  late Set<String>? reported;
  late TestGesture mouse;

  FakeGitRepository repository() => FakeGitRepository(
    (_, _) async => [
      commit('main-tip', 'main tip', parents: ['shared']),
      commit('one-tip', 'one tip', parents: ['shared']),
      commit('two-tip', 'two tip', parents: ['shared']),
      commit('shared', 'shared root'),
    ],
    refs: refs,
    onLoadHistory: (hidden) => asked.add(hidden),
  );

  Future<void> pump(
    WidgetTester tester, {
    Set<String> hiddenRefs = const {},
  }) async {
    asked = [];
    reported = null;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository(),
          controller: controller,
          hiddenRefs: hiddenRefs,
          onHiddenRefsChanged: (value) => reported = value,
          columnWidths: const TimelineColumnWidths(sidebar: 320),
        ),
      ),
    );
    await tester.pumpAndSettle();

    mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
  }

  Future<void> hover(WidgetTester tester, Finder row) async {
    await mouse.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();
  }

  /// 눈은 hover에만 나온다 — 마우스를 행에 올리고 나서 누른다.
  Future<void> tapEye(WidgetTester tester, String key, Finder row) async {
    await hover(tester, row);
    await tester.tap(find.byKey(Key(key)), warnIfMissed: false);
    await tester.pumpAndSettle();
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
  }

  Finder branchRow(String name) => find.byKey(Key('sidebar-row-$name'));

  testWidgets('the eye drops a branch from the log\'s starting points', (
    tester,
  ) async {
    await pump(tester);
    expect(asked.last, isEmpty);

    await tapEye(tester, 'sidebar-hide-feature/one', branchRow('feature/one'));

    expect(asked.last, {'one-tip'}, reason: '숨긴 브랜치의 tip이 출발점에서 빠져야 한다');
    expect(reported, {'feature/one'});
  });

  testWidgets('a second press brings it back', (tester) async {
    await pump(tester);
    await tapEye(tester, 'sidebar-hide-feature/one', branchRow('feature/one'));
    await tapEye(tester, 'sidebar-hide-feature/one', branchRow('feature/one'));

    expect(asked.last, isEmpty);
    expect(reported, isEmpty);
  });

  testWidgets('a folder\'s eye hides everything under it', (tester) async {
    await pump(tester);

    await tapEye(
      tester,
      'sidebar-hide-folder-local-feature',
      find.text('feature'),
    );

    expect(asked.last, {'one-tip', 'two-tip'});
    expect(reported, {'feature/one', 'feature/two'});

    await tapEye(
      tester,
      'sidebar-hide-folder-local-feature',
      find.text('feature'),
    );
    expect(asked.last, isEmpty);
  });

  testWidgets('the checked-out branch is offered no eye at all', (
    tester,
  ) async {
    await pump(tester);

    await hover(tester, branchRow('main'));

    expect(
      find.byKey(const Key('sidebar-hide-main')),
      findsNothing,
      reason: 'HEAD도 출발점이라 숨겨도 남는다 — 듣지 않는 스위치는 내지 않는다',
    );
  });

  testWidgets('a hidden row keeps a closed eye showing', (tester) async {
    await pump(tester, hiddenRefs: const {'feature/one'});

    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('sidebar-hide-feature/one')),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.visibility_off_outlined,
    );
  });

  testWidgets('a set kept from last session applies once refs resolve', (
    tester,
  ) async {
    // 첫 페이지는 refs와 나란히 나가므로 그때는 아직 tip을 풀 수 없다. refs가
    // 도착하면 출발점이 달라졌음을 알아채고 로그를 다시 읽는다.
    await pump(tester, hiddenRefs: const {'feature/two'});

    expect(asked.last, {'two-tip'});
  });
}
