import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// docs/graph-squeeze-design.md — 그래프 컬럼의 폭과 압축은 **화면에 그려진
/// 레인**만 보고 정한다. 화면 밖 한 행이나, 아까 지나온 깊은 구간이 지금 밀리는
/// 시점을 정하면 안 된다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  /// 30줄짜리 외줄 머리 뒤에 갈래가 벌어지는 꼬리.
  List<GitCommit> shallowThenDeep() => [
    for (var index = 0; index < 30; index++)
      commit('$index', 'shallow $index', parents: ['${index + 1}']),
    for (var index = 30; index < 60; index++)
      commit(
        '$index',
        'deep $index',
        parents: ['${index + 1}', '${index + 2}', '${index + 3}'],
      ),
    commit('60', 'root'),
    commit('61', 'root b'),
    commit('62', 'root c'),
  ];

  Future<ScrollPosition> pumpTimeline(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 420);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(FakeGitRepository((_, _) async => shallowThenDeep()), controller),
    );
    await tester.pumpAndSettle();
    return tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('timeline-list')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
  }

  double graphWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('graph-header'))).width;

  Finder graphPainters() => find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is CommitGraphPainter,
  );

  /// 지금 화면에 실제로 그려진 행들의 가장 깊은 레인. 리스트는 화면 밖 행도
  /// 미리 만들어 두므로 뷰포트와 겹치는 것만 센다.
  int visibleDepth(WidgetTester tester) {
    final viewport = tester.getRect(find.byKey(const Key('timeline-list')));
    var deepest = 0;
    for (final element in graphPainters().evaluate()) {
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.bottom <= viewport.top || rect.top >= viewport.bottom) continue;
      final row =
          ((element.widget as CustomPaint).painter as CommitGraphPainter).row;
      for (final lane in [row.lane, ...row.activeLanes, ...row.nextLanes]) {
        deepest = math.max(deepest, lane);
      }
    }
    return deepest;
  }

  double laneSpacing(WidgetTester tester) =>
      (tester.widget<CustomPaint>(graphPainters().first).painter
              as CommitGraphPainter)
          .laneSpacing;

  double autoFit(int depth) => CommitGraphPainter.contentWidth(
    depth,
    laneSpacing: CommitGraphPainter.defaultLaneSpacing,
  ).clamp(CommitGraphPainter.minAutoFitWidth, timelineColumns['graph']!.max);

  Future<void> setGraphWidth(WidgetTester tester, double target) async {
    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      Offset(target - graphWidth(tester), 0),
      touchSlopX: 0,
    );
    await tester.pumpAndSettle();
    expect(graphWidth(tester), closeTo(target, 0.5));
  }

  testWidgets('a one-lane history opens at one lane’s worth of column', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 420);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            for (var index = 0; index < 8; index++)
              commit('$index', 'straight $index', parents: ['${index + 1}']),
            commit('8', 'root'),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(visibleDepth(tester), 0);
    expect(
      graphWidth(tester),
      CommitGraphPainter.minAutoFitWidth,
      reason: '한 줄짜리 그래프가 빈 컬럼을 끌고 다니면 안 된다',
    );
  });

  testWidgets('the column never counts a row past the fold', (tester) async {
    final position = await pumpTimeline(tester);

    // 한 행씩 내려가며 매 화면에서 폭이 보이는 깊이와 정확히 맞는지 본다.
    // 화면 밖 한 행을 세면 갈래가 벌어지기 직전 화면에서 어긋난다.
    for (var step = 0; step < 34; step++) {
      position.jumpTo(step * TimelineScreen.rowHeight);
      await tester.pumpAndSettle();
      expect(
        graphWidth(tester),
        autoFit(visibleDepth(tester)),
        reason: '$step번째 행까지 내려온 화면: 보이는 레인에만 맞아야 한다',
      );
    }
  });

  testWidgets('lanes hold still until the deepest visible node reaches the '
      'divider', (tester) async {
    final position = await pumpTimeline(tester);
    position.jumpTo(45 * TimelineScreen.rowHeight);
    await tester.pumpAndSettle();

    final depth = visibleDepth(tester);
    expect(depth, greaterThan(0), reason: '갈래가 보이는 화면이어야 한다');
    final boundary = CommitGraphPainter.contentWidth(depth);

    await setGraphWidth(tester, boundary + 40);
    expect(laneSpacing(tester), CommitGraphPainter.defaultLaneSpacing);

    await setGraphWidth(tester, boundary);
    expect(
      laneSpacing(tester),
      CommitGraphPainter.defaultLaneSpacing,
      reason: '노드가 경계에 닿는 폭까지는 제자리다',
    );

    await setGraphWidth(tester, boundary - 12);
    expect(
      laneSpacing(tester),
      lessThan(CommitGraphPainter.defaultLaneSpacing),
      reason: '닿은 뒤부터 함께 밀린다',
    );
  });

  testWidgets('a depth left behind up the list does not squeeze this screen', (
    tester,
  ) async {
    final position = await pumpTimeline(tester);

    position.jumpTo(45 * TimelineScreen.rowHeight);
    await tester.pumpAndSettle();
    final deepDepth = visibleDepth(tester);

    position.jumpTo(0);
    await tester.pumpAndSettle();
    final shallowDepth = visibleDepth(tester);
    expect(shallowDepth, lessThan(deepDepth));

    // 래칫이 잡아 둔 폭은 그대로 넓다 — 컬럼 경계가 스크롤마다 흔들리지 않는다.
    expect(graphWidth(tester), autoFit(deepDepth));

    // 그 폭에서 보이는 깊이에 딱 맞게 좁혀도 레인은 기본 간격이다.
    await setGraphWidth(tester, autoFit(shallowDepth));
    expect(
      laneSpacing(tester),
      CommitGraphPainter.defaultLaneSpacing,
      reason: '보이지 않는 깊이로 압축하면 안 된다',
    );
  });

  testWidgets('squeezing bottoms out at the minimum lane spacing', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await setGraphWidth(tester, CommitGraphPainter.compactWidth + 1);

    expect(
      laneSpacing(tester),
      greaterThanOrEqualTo(CommitGraphPainter.minLaneSpacing),
    );
  });
}
