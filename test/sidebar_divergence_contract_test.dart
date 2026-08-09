import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/timeline_palette.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// docs/sidebar-divergence-design.md — LOCAL 트리의 브랜치 행마다 추적하는 원격과
/// 몇 커밋 벌어졌는지를 `+N`(초록) `−N`(빨강)으로 단다. 기준 브랜치만이 아니라
/// 모든 로컬 행에, 뒤처진 수만이 아니라 앞선 수도.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  /// main은 갈라졌고, release는 앞서기만, hotfix는 뒤처지기만, synced는 같고,
  /// local-only는 추적하는 원격이 없다. release의 업스트림은 이름이 다르다.
  const refs = RepoRefs(
    local: ['main', 'release', 'hotfix', 'synced', 'local-only'],
    remote: ['origin/main', 'company/topic-release', 'origin/hotfix'],
    remoteNames: ['origin', 'company'],
    current: 'main',
    upstreams: {
      'main': 'origin/main',
      'release': 'company/topic-release',
      'hotfix': 'origin/hotfix',
      'synced': 'origin/synced',
    },
    upstreamRemotes: {
      'main': 'origin',
      'release': 'company',
      'hotfix': 'origin',
      'synced': 'origin',
    },
    aheadBehind: {
      'main': BranchAheadBehind(ahead: 2, behind: 12),
      'release': BranchAheadBehind(ahead: 3, behind: 0),
      'hotfix': BranchAheadBehind(ahead: 0, behind: 7),
      'synced': BranchAheadBehind(ahead: 0, behind: 0),
    },
    // 원격 쪽은 관점이 뒤집힌 채로 적재된다. 이름이 같은 로컬이 있는 원격만 채워지므로
    // company/topic-release는 여기 없다 — 실제 적재부와 같다.
    remoteAheadBehind: {
      'origin/main': BranchAheadBehind(ahead: 12, behind: 2),
      'origin/hotfix': BranchAheadBehind(ahead: 7, behind: 0),
    },
  );

  Future<void> pumpSidebar(
    WidgetTester tester, {
    GitRepository? repository,
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
          repository:
              repository ??
              FakeGitRepository(
                (_, _) async => [commit('1', 'first commit')],
                refs: refs,
              ),
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder badge(String branch) =>
      find.byKey(Key('sidebar-local-divergence-$branch'));

  /// 배지는 한 덩이 `Text.rich`다 — 조각마다 색이 다르므로 span을 직접 읽는다.
  List<TextSpan> spans(WidgetTester tester, Finder badgeFinder) =>
      ((tester.widget<Text>(badgeFinder).textSpan! as TextSpan).children ??
              const <InlineSpan>[])
          .cast<TextSpan>()
          .toList();

  Color? colorOf(WidgetTester tester, Finder badgeFinder, String text) => spans(
    tester,
    badgeFinder,
  ).firstWhere((span) => span.text == text).style?.color;

  String label(WidgetTester tester, Finder badgeFinder) =>
      tester.widget<Text>(badgeFinder).textSpan!.toPlainText();

  testWidgets(
    'every local branch carries its own divergence, not just the base',
    (tester) async {
      await pumpSidebar(tester);

      // release는 기준 브랜치도 아니고 체크아웃되어 있지도 않다.
      expect(badge('release'), findsOneWidget);
      expect(badge('hotfix'), findsOneWidget);
      expect(badge('main'), findsOneWidget);
    },
  );

  testWidgets('the pair reads ahead in green and behind in red', (
    tester,
  ) async {
    await pumpSidebar(tester);

    expect(label(tester, badge('main')), '+2 −12');
    expect(colorOf(tester, badge('main'), '+2'), successGreen);
    expect(colorOf(tester, badge('main'), '−12'), remoteBehindRed);
  });

  testWidgets('one direction shows one number', (tester) async {
    await pumpSidebar(tester);

    expect(label(tester, badge('release')), '+3');
    expect(label(tester, badge('hotfix')), '−7');
  });

  testWidgets('the numbers sit against the name, not a stop away', (
    tester,
  ) async {
    await pumpSidebar(tester);

    // 로컬 행에는 자리를 예약할 hover 버튼이 없다 — 숫자가 이름에 붙어야 한다.
    final label = find.descendant(
      of: find.byKey(const Key('sidebar-ref-hotfix')),
      matching: find.text('hotfix'),
    );
    expect(
      tester.getRect(badge('hotfix')).left - tester.getRect(label).right,
      lessThanOrEqualTo(4),
    );
  });

  testWidgets('nothing to say means no badge', (tester) async {
    await pumpSidebar(tester);

    expect(badge('synced'), findsNothing, reason: '차이가 0이면 배지가 없다');
    expect(badge('local-only'), findsNothing, reason: '추적하는 원격이 없으면 잴 것이 없다');
  });

  testWidgets('a local row says 원격보다, never 로컬보다', (tester) async {
    await pumpSidebar(tester);

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: badge('main'), matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, '원격보다 2개 커밋 앞서 있습니다 · 원격보다 12개 커밋 뒤처져 있습니다');
  });

  testWidgets('the remote rows keep the badge they already had', (
    tester,
  ) async {
    await pumpSidebar(tester);

    // 원격 쪽은 관점이 뒤집혀 저장된다: 로컬이 2 앞서면 원격은 2 뒤처진다.
    final remote = find.byKey(
      const Key('sidebar-remote-divergence-origin/main'),
    );
    expect(remote, findsOneWidget);
    expect(colorOf(tester, remote, '+12'), successGreen);
    expect(colorOf(tester, remote, '−2'), remoteBehindRed);
  });

  testWidgets('the periodic fetch reaches a differently named upstream', (
    tester,
  ) async {
    final fetched = <String>[];
    await pumpSidebar(
      tester,
      repository: FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        refs: refs,
        fetchRemoteCallback: (remote) async {
          fetched.add(remote);
          return FetchOriginResult.unchanged;
        },
      ),
    );

    await tester.pump(const Duration(minutes: 3));
    await tester.pumpAndSettle();

    expect(
      fetched,
      contains('company'),
      reason: 'release가 company/topic-release를 추적하는데 이름이 달라 빠져 있었다',
    );
  });
}
