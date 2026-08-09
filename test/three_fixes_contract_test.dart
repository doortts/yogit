import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/git.dart';
import 'package:yogit/github_api.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// docs/three-fixes-design.md — 아바타가 두 번 그려지지 않게, 그래프 아바타를
/// 2pt 키우고, 그래프 컬럼 폭은 화면에 보이는 구조만으로 정한다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  // ── 1. 아바타 깜박임 ───────────────────────────────────────────────
  AvatarService serviceWithPhotos() => AvatarService(
    remote: const RemoteRepository(
      host: 'github.com',
      owner: 'team',
      repository: 'yogit',
    ),
    api: GitHubApi(
      apiBaseUrl: 'https://api.github.com',
      token: 'token',
      send: (uri, {required method, required headers, body}) async => (
        status: 200,
        body: jsonEncode({
          'author': {'login': 'ada', 'avatar_url': 'https://x/ada.png'},
          'committer': {'login': 'ada', 'avatar_url': 'https://x/ada.png'},
        }),
      ),
    ),
  );

  final photographed = commit('1', 'first commit');

  testWidgets('a known avatar is a photo on the very first frame', (
    tester,
  ) async {
    final service = serviceWithPhotos();
    await service.resolve(photographed.sha);
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CommitAvatarStack(
            commit: photographed,
            avatarService: service,
            size: 42,
          ),
        ),
      ),
    );

    // 한 프레임도 이니셜을 거치지 않는다 — 커서를 옮길 때 깜박이던 원인.
    expect(find.byType(Image), findsWidgets);
    expect(find.text('AL'), findsNothing);
  });

  testWidgets('an unknown avatar still starts with its initials', (
    tester,
  ) async {
    final service = serviceWithPhotos();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CommitAvatarStack(
            commit: commit('2', 'second commit'),
            avatarService: service,
            size: 42,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
  });

  // ── 2. 그래프 아바타 지름 ──────────────────────────────────────────
  test('the graph avatar is two points wider', () {
    expect(CommitGraphPainter.avatarDiameter, 20.0);
    expect(CommitGraphPainter.avatarRadius, 10.0);
    expect(
      CommitGraphPainter.avatarDiameter,
      lessThanOrEqualTo(TimelineScreen.rowHeight),
      reason: '행 안에 들어가야 한다',
    );
  });

  // ── 3. 그래프 컬럼 폭 ─────────────────────────────────────────────
  /// 얕은 머리(한 줄) 뒤에 깊은 꼬리(다섯 줄)가 오는 히스토리.
  List<GitCommit> shallowThenDeep() {
    final commits = <GitCommit>[];
    for (var index = 0; index < 40; index++) {
      commits.add(
        commit('$index', 'shallow $index', parents: ['${index + 1}']),
      );
    }
    // 40번째부터 다섯 갈래로 갈라진다: 머지 커밋이 레인을 넓힌다.
    for (var index = 40; index < 60; index++) {
      commits.add(
        commit(
          '$index',
          'deep $index',
          parents: ['${index + 1}', '${index + 2}', '${index + 3}'],
        ),
      );
    }
    commits.add(commit('60', 'root'));
    commits.add(commit('61', 'root b'));
    commits.add(commit('62', 'root c'));
    return commits;
  }

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

  testWidgets('the first screen fits the lanes it can see', (tester) async {
    await pumpTimeline(tester);

    // 화면에는 한 줄짜리 머리만 보인다 — 아래의 다섯 갈래는 폭에 끼지 않는다.
    expect(
      graphWidth(tester),
      lessThan(
        CommitGraphPainter.contentWidth(
          3,
          laneSpacing: CommitGraphPainter.defaultLaneSpacing,
        ),
      ),
      reason: '보이지 않는 갈래가 폭을 넓히면 안 된다',
    );
  });

  testWidgets('scrolling into the branches widens the column', (tester) async {
    final position = await pumpTimeline(tester);
    final before = graphWidth(tester);

    position.jumpTo(45 * TimelineScreen.rowHeight);
    await tester.pumpAndSettle();

    expect(graphWidth(tester), greaterThan(before));
  });

  testWidgets('another repository opens at its own width', (tester) async {
    // 저장소마다 화면을 새로 세운다(main.dart가 root로 key를 준다), 그래서 앞
    // 저장소가 넓혀 둔 폭을 물려받지 않는다.
    final position = await pumpTimeline(tester);
    position.jumpTo(45 * TimelineScreen.rowHeight);
    await tester.pumpAndSettle();
    final widened = graphWidth(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          key: const Key('timeline-screen-other'),
          repository: FakeGitRepository(
            (_, _) async => [
              for (var index = 0; index < 6; index++)
                commit('s$index', 'shallow $index', parents: ['s${index + 1}']),
              commit('s6', 'root'),
            ],
          ),
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      graphWidth(tester),
      lessThan(widened),
      reason: '앞 저장소의 깊이가 다음 저장소의 폭을 정하면 안 된다',
    );
  });

  testWidgets('a width the user chose survives every scroll', (tester) async {
    final position = await pumpTimeline(tester);

    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    final chosen = graphWidth(tester);

    position.jumpTo(45 * TimelineScreen.rowHeight);
    await tester.pumpAndSettle();
    expect(graphWidth(tester), chosen);
  });
}
