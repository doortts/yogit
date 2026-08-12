import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, branchComparison, commit;

/// 캡슐이 툴바의 기준 브랜치 곁에 서고, refs가 실릴 때마다 판정이 다시 서며,
/// Push는 오갈 커밋의 영수증을 보인 뒤에만 원격을 움직인다. 주황 확인 한 번에
/// 받아 얹기와 Push 두 걸음이 이어진다. docs/upstream-sync-mockup.html 계약.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  RepoRefs refs({int ahead = 0, int behind = 0}) => RepoRefs(
    local: const ['main'],
    remote: const ['origin/main'],
    remoteNames: const ['origin'],
    current: 'main',
    tips: const {'main': 'aaa1111', 'origin/main': 'bbb2222'},
    localTips: const {'main': 'aaa1111'},
    aheadBehind: {'main': BranchAheadBehind(ahead: ahead, behind: behind)},
    upstreams: const {'main': 'origin/main'},
    upstreamRemotes: const {'main': 'origin'},
  );

  Future<void> pumpApp(
    WidgetTester tester,
    FakeGitRepository repository,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
  }

  testWidgets('the capsule stands beside the base branch selector', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('aaa1111', 'first')],
        refs: refs(),
      ),
    );

    final capsule = tester.getRect(
      find.byKey(const Key('upstream-sync-capsule')),
    );
    final base = tester.getRect(find.byKey(const Key('base-branch-selector')));
    expect(capsule.left, greaterThan(base.right - 1));
    expect(find.byKey(const Key('upstream-sync-dot')), findsOneWidget);
  });

  testWidgets('a push shows its receipt and only then moves the remote', (
    tester,
  ) async {
    final pushes = <({String remote, String branch, String? to})>[];
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: refs(ahead: 2),
      movedCommitsCallback: (before, after) async => const [
        (incoming: true, shortSha: 'aaa1111', subject: 'local work'),
        (incoming: true, shortSha: 'ccc3333', subject: 'more local work'),
      ],
      pushBranchCallback:
          (remote, branch, {toBranch, setUpstream = false}) async {
            pushes.add((remote: remote, branch: branch, to: toBranch));
          },
    );
    await pumpApp(tester, repository);

    await tester.tap(find.byKey(const Key('upstream-sync-push')));
    await tester.pumpAndSettle();

    // 영수증: 올라갈 커밋과 원격 ref의 이동이 해시로 선다. 아직 아무 일도
    // 하지 않았다.
    expect(find.byKey(const Key('push-receipt-push-block')), findsOneWidget);
    expect(find.textContaining('local work'), findsWidgets);
    final footnote = tester
        .widget<Text>(find.byKey(const Key('push-receipt-footnote')))
        .data!;
    expect(footnote, contains('bbb2222'));
    expect(footnote, contains('aaa1111'));
    expect(pushes, isEmpty, reason: '읽기 전에 움직이지 않는다');

    await tester.tap(find.byKey(const Key('upstream-push-confirm')));
    await tester.pumpAndSettle();
    expect(pushes.single, (remote: 'origin', branch: 'main', to: 'main'));
  });

  testWidgets('declining the receipt moves nothing', (tester) async {
    var pushed = 0;
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: refs(ahead: 1),
      movedCommitsCallback: (before, after) async => const [
        (incoming: true, shortSha: 'aaa1111', subject: 'local work'),
      ],
      pushBranchCallback:
          (remote, branch, {toBranch, setUpstream = false}) async {
            pushed++;
          },
    );
    await pumpApp(tester, repository);

    await tester.tap(find.byKey(const Key('upstream-sync-push')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(pushed, 0);
  });

  testWidgets('a fast-forward pull runs without being asked twice', (
    tester,
  ) async {
    final pulls = <({String remote, String branch, bool checkedOut})>[];
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'first')],
      refs: refs(behind: 2),
      pullRemoteBranchCallback: (remote, branch, {checkedOut = false}) async {
        pulls.add((remote: remote, branch: branch, checkedOut: checkedOut));
      },
    );
    await pumpApp(tester, repository);

    await tester.tap(find.byKey(const Key('upstream-sync-pull')));
    await tester.pumpAndSettle();

    expect(pulls.single, (remote: 'origin', branch: 'main', checkedOut: true));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('one amber confirmation walks both steps in order', (
    tester,
  ) async {
    final walked = <String>[];
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: refs(ahead: 1, behind: 1),
      measureUpstreamRebaseCallback:
          ({required remoteTip, required localTip}) async =>
              RebasePreviewResult(
                status: RebasePreviewStatus.clean,
                baseTip: remoteTip,
                compareTip: localTip,
                virtualTip: 'ddd4444',
              ),
      movedCommitsCallback: (before, after) async => const [
        (incoming: false, shortSha: 'bbb2222', subject: 'remote work'),
        (incoming: true, shortSha: 'aaa1111', subject: 'local work'),
      ],
      applyUpstreamRebaseCallback:
          ({required branch, required expectedTip, required virtualTip}) async {
            walked.add('rebase $branch $expectedTip -> $virtualTip');
            return false;
          },
      pushBranchCallback:
          (remote, branch, {toBranch, setUpstream = false}) async {
            walked.add('push $remote $branch');
          },
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();

    // 판정: 주황. Push를 누르면 두 블록 영수증.
    await tester.tap(find.byKey(const Key('upstream-sync-push')));
    await tester.pumpAndSettle();
    expect(
      find.text('받아 얹은 뒤 Push할까요? (Pull Rebase and Push)'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('push-receipt-pull-block')), findsOneWidget);
    expect(find.byKey(const Key('push-receipt-push-block')), findsOneWidget);
    expect(walked, isEmpty);

    await tester.tap(find.byKey(const Key('upstream-rebase-push-confirm')));
    await tester.pumpAndSettle();

    expect(walked, [
      'rebase main aaa1111 -> ddd4444',
      'push origin main',
    ], reason: '확인 한 번, 걸음 둘, 순서대로');
  });

  testWidgets('a conflicted divergence stands red and runs nothing', (
    tester,
  ) async {
    var acted = 0;
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: refs(ahead: 1, behind: 1),
      measureUpstreamRebaseCallback:
          ({required remoteTip, required localTip}) async =>
              RebasePreviewResult(
                status: RebasePreviewStatus.conflict,
                baseTip: remoteTip,
                compareTip: localTip,
                conflictFiles: const ['lib/a.dart'],
              ),
      pushBranchCallback:
          (remote, branch, {toBranch, setUpstream = false}) async {
            acted++;
          },
      applyUpstreamRebaseCallback:
          ({required branch, required expectedTip, required virtualTip}) async {
            acted++;
            return false;
          },
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('upstream-sync-conflict')), findsOneWidget);
    await tester.tap(find.byKey(const Key('upstream-sync-conflict')));
    await tester.pumpAndSettle();
    expect(acted, 0, reason: '빨강은 실행이 아니다');
  });

  testWidgets('a branch diff underway shows the verdict but locks the verbs', (
    tester,
  ) async {
    var pushed = 0;
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('aaa1111', 'local work'),
        commit('eee5555', 'other'),
      ],
      refs: RepoRefs(
        local: const ['main', 'feature'],
        remote: const ['origin/main'],
        remoteNames: const ['origin'],
        current: 'main',
        tips: const {
          'main': 'aaa1111',
          'feature': 'eee5555',
          'origin/main': 'bbb2222',
        },
        localTips: const {'main': 'aaa1111', 'feature': 'eee5555'},
        aheadBehind: const {'main': BranchAheadBehind(ahead: 2, behind: 0)},
        upstreams: const {'main': 'origin/main'},
        upstreamRemotes: const {'main': 'origin'},
      ),
      pushBranchCallback:
          (remote, branch, {toBranch, setUpstream = false}) async {
            pushed++;
          },
      compareBranchesCallback: (base, compare) async =>
          branchComparison(compareRef: compare, compareTip: 'eee5555'),
    );
    await pumpApp(tester, repository);

    // 브랜치 diff에 들어간다.
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('upstream-sync-push')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('upstream-sync-push')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(pushed, 0, reason: '두 worktree 흐름을 겹치지 않는다');
  });
}
