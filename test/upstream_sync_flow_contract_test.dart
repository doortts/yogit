import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart'
    show
        FakeGitRepository,
        FakeRebasePreviewSession,
        app,
        branchComparison,
        commit;

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
    final pushes =
        <({String remote, String branch, String? to, String? from})>[];
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: refs(ahead: 2),
      movedCommitsCallback: (before, after) async => const [
        (incoming: true, shortSha: 'aaa1111', subject: 'local work'),
        (incoming: true, shortSha: 'ccc3333', subject: 'more local work'),
      ],
      pushBranchCallback:
          (remote, branch, {toBranch, fromTip, setUpstream = false}) async {
            pushes.add((
              remote: remote,
              branch: branch,
              to: toBranch,
              from: fromTip,
            ));
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
    expect(pushes.single, (
      remote: 'origin',
      branch: 'main',
      to: 'main',
      from: 'aaa1111',
    ), reason: '영수증이 보인 그 끝만 올라간다');
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
          (remote, branch, {toBranch, fromTip, setUpstream = false}) async {
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
    expect(find.byKey(const Key('remote-pull-confirm')), findsNothing);
    expect(find.text('Pull'), findsNothing, reason: '빨리감기는 묻지 않는다');
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
          (remote, branch, {toBranch, fromTip, setUpstream = false}) async {
            walked.add('push $remote $branch from $fromTip');
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
      'push origin main from ddd4444',
    ], reason: '확인 한 번, 걸음 둘, 순서대로 — 올라가는 것은 잰 그 끝이다');
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
          (remote, branch, {toBranch, fromTip, setUpstream = false}) async {
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

  testWidgets('an amber pull asks first — it rewrites local hashes', (
    tester,
  ) async {
    final walked = <String>[];
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: refs(ahead: 1, behind: 2),
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
        (incoming: false, shortSha: 'ccc3333', subject: 'more remote work'),
        (incoming: true, shortSha: 'aaa1111', subject: 'local work'),
      ],
      applyUpstreamRebaseCallback:
          ({required branch, required expectedTip, required virtualTip}) async {
            walked.add('rebase $expectedTip -> $virtualTip');
            return false;
          },
      pushBranchCallback:
          (remote, branch, {toBranch, fromTip, setUpstream = false}) async {
            walked.add('push');
          },
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('upstream-sync-pull')));
    await tester.pumpAndSettle();

    expect(find.text('받아 얹을까요? (Pull --rebase)'), findsOneWidget);
    expect(find.byKey(const Key('push-receipt-pull-block')), findsOneWidget);
    expect(
      find.textContaining('해시가 달라집니다'),
      findsOneWidget,
      reason: '다시 쓰이는 역사임을 읽은 뒤에 답한다',
    );
    expect(walked, isEmpty);

    await tester.tap(find.byKey(const Key('upstream-rebase-pull-confirm')));
    await tester.pumpAndSettle();

    expect(walked, ['rebase aaa1111 -> ddd4444'], reason: 'Push는 없다 — Pull이다');
  });

  testWidgets('a first push is asked like every other push', (tester) async {
    final pushes = <({String? to, bool up})>[];
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: const RepoRefs(
        local: ['main'],
        remoteNames: ['origin'],
        current: 'main',
        localTips: {'main': 'aaa1111'},
        tips: {'main': 'aaa1111'},
      ),
      pushBranchCallback:
          (remote, branch, {toBranch, fromTip, setUpstream = false}) async {
            pushes.add((to: toBranch, up: setUpstream));
          },
    );
    await pumpApp(tester, repository);

    await tester.tap(find.byKey(const Key('upstream-sync-push')));
    await tester.pumpAndSettle();
    expect(
      find.text('main 브랜치를 origin에 처음 Push할까요?'),
      findsOneWidget,
      reason: 'Push는 항상 확인을 거친다',
    );
    expect(pushes, isEmpty);

    await tester.tap(find.byKey(const Key('upstream-first-push-confirm')));
    await tester.pumpAndSettle();
    expect(pushes.single, (to: null, up: true));
  });

  testWidgets('the receipt never claims fewer commits than will travel', (
    tester,
  ) async {
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: refs(ahead: 12),
      movedCommitsCallback: (before, after) async => [
        for (var index = 0; index < 9; index++)
          (incoming: true, shortSha: 'c$index', subject: 'work $index'),
      ],
      pushBranchCallback:
          (remote, branch, {toBranch, fromTip, setUpstream = false}) async {},
    );
    await pumpApp(tester, repository);

    await tester.tap(find.byKey(const Key('upstream-sync-push')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('커밋 12개 올라감'),
      findsOneWidget,
      reason: '요약은 목록이 아니라 실제 개수를 센다',
    );
    expect(find.text('외 3개'), findsOneWidget);
  });

  testWidgets('a fetch that finds news re-arms the judgement', (tester) async {
    var loads = 0;
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refsLoader: () async => ++loads == 1 ? refs() : refs(behind: 2),
      fetchRemoteCallback: (_) async => FetchOriginResult.updated,
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('upstream-sync-pull')),
      findsOneWidget,
      reason: 'fetch가 실어 온 어긋남이 판정으로 선다',
    );
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('upstream-sync-pull')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, contains('확인'), reason: '확인 시각은 fetch의 것');
  });

  testWidgets('a failed measure names itself in the status bar', (
    tester,
  ) async {
    final repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: refs(ahead: 1, behind: 1),
      // measure 콜백 없음 — 기본이 '실패'다.
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('upstream-sync-measuring')), findsOneWidget);
    expect(
      find.byKey(const Key('upstream-measure-error')),
      findsOneWidget,
      reason: '판정이 보류된 이유는 상태바가 말한다',
    );
  });

  testWidgets('the red door opens the conflict flow, aimed the right way', (
    tester,
  ) async {
    // 어긋남 + 충돌 판정. 빨강을 누르면 기준 upstream, 비교 로컬 브랜치의
    // 브랜치 diff가 rebase 모드로 열린다 — 기존 충돌 해결 화면 그대로.
    final previews = <({String base, String compare})>[];
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: RepoRefs(
        local: const ['main'],
        remote: const ['origin/main'],
        remoteNames: const ['origin'],
        current: 'main',
        tips: const {'main': 'aaa1111', 'origin/main': 'bbb2222'},
        localTips: const {'main': 'aaa1111'},
        aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)},
        upstreams: const {'main': 'origin/main'},
        upstreamRemotes: const {'main': 'origin'},
      ),
      measureUpstreamRebaseCallback:
          ({required remoteTip, required localTip}) async =>
              RebasePreviewResult(
                status: RebasePreviewStatus.conflict,
                baseTip: remoteTip,
                compareTip: localTip,
                conflictFiles: const ['lib/a.dart'],
              ),
      compareBranchesCallback: (base, compare) async {
        previews.add((base: base, compare: compare));
        return branchComparison(compareRef: compare, compareTip: 'aaa1111');
      },
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(
                repository,
                const RebasePreviewResult(
                  status: RebasePreviewStatus.conflict,
                  baseTip: 'bbb2222',
                  compareTip: 'aaa1111',
                  conflictFiles: ['lib/a.dart'],
                ),
              ),
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upstream-sync-conflict')), findsOneWidget);

    await tester.tap(find.byKey(const Key('upstream-sync-conflict')));
    await tester.pumpAndSettle();

    expect(previews.single, (
      base: 'origin/main',
      compare: 'main',
    ), reason: '잰 그 방향 그대로 — upstream 위에 로컬을 얹는다');
    expect(find.byKey(const Key('branch-preview-summary')), findsOneWidget);
    expect(
      find.byKey(const Key('upstream-sync-capsule')),
      findsNothing,
      reason: '흐름이 도는 동안 기준은 원격 ref라 캡슐은 물러난다',
    );
  });

  testWidgets('leaving the conflict flow restores the base branch', (
    tester,
  ) async {
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: RepoRefs(
        // zeta가 목록 앞에 선다 — 복원이 '첫 번째 로컬'이 아니라 빌려 갈 때
        // 적어 둔 그 브랜치를 고른다는 것을 이 순서가 증명한다.
        local: const ['zeta', 'main'],
        remote: const ['origin/main'],
        remoteNames: const ['origin'],
        current: 'main',
        tips: const {
          'zeta': 'eee5555',
          'main': 'aaa1111',
          'origin/main': 'bbb2222',
        },
        localTips: const {'zeta': 'eee5555', 'main': 'aaa1111'},
        aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)},
        upstreams: const {'main': 'origin/main'},
        upstreamRemotes: const {'main': 'origin'},
      ),
      measureUpstreamRebaseCallback:
          ({required remoteTip, required localTip}) async =>
              RebasePreviewResult(
                status: RebasePreviewStatus.conflict,
                baseTip: remoteTip,
                compareTip: localTip,
                conflictFiles: const ['lib/a.dart'],
              ),
      compareBranchesCallback: (base, compare) async =>
          branchComparison(compareRef: compare, compareTip: 'aaa1111'),
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(
                repository,
                const RebasePreviewResult(
                  status: RebasePreviewStatus.conflict,
                  baseTip: 'bbb2222',
                  compareTip: 'aaa1111',
                  conflictFiles: ['lib/a.dart'],
                ),
              ),
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('upstream-sync-conflict')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upstream-sync-capsule')), findsNothing);

    // 그만두기 — 브랜치 diff를 닫는다. (해제 버튼은 선택 메뉴 안에 산다.)
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-clear')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('upstream-sync-capsule')),
      findsOneWidget,
      reason: '기준 브랜치가 돌아오고 캡슐도 돌아온다',
    );
    expect(
      find.byKey(const Key('upstream-sync-conflict')),
      findsOneWidget,
      reason: '로컬은 무변 — 판정도 그대로 충돌이다',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('base-branch-selector')),
        matching: find.text('main'),
      ),
      findsOneWidget,
      reason: '돌아가는 곳은 빌려 갈 때의 그 브랜치다 — 목록의 첫째가 아니라',
    );
  });

  testWidgets('coming back from the flow reads the world anew', (tester) async {
    // 흐름 안에서 해결과 적용이 끝났다고 치자 — 되돌아오는 길은 낡은 refs로
    // 판정하지 않고 새로 읽는다. 끝난 어긋남은 끝났다고 새 refs가 말한다.
    var resolved = false;
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refsLoader: () async => resolved
          ? RepoRefs(
              local: const ['main'],
              remote: const ['origin/main'],
              remoteNames: const ['origin'],
              current: 'main',
              tips: const {'main': 'eee5555', 'origin/main': 'bbb2222'},
              localTips: const {'main': 'eee5555'},
              aheadBehind: const {
                'main': BranchAheadBehind(ahead: 1, behind: 0),
              },
              upstreams: const {'main': 'origin/main'},
              upstreamRemotes: const {'main': 'origin'},
            )
          : refs(ahead: 1, behind: 1),
      measureUpstreamRebaseCallback:
          ({required remoteTip, required localTip}) async =>
              RebasePreviewResult(
                status: RebasePreviewStatus.conflict,
                baseTip: remoteTip,
                compareTip: localTip,
                conflictFiles: const ['lib/a.dart'],
              ),
      compareBranchesCallback: (base, compare) async =>
          branchComparison(compareRef: compare, compareTip: 'aaa1111'),
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(
                repository,
                const RebasePreviewResult(
                  status: RebasePreviewStatus.conflict,
                  baseTip: 'bbb2222',
                  compareTip: 'aaa1111',
                  conflictFiles: ['lib/a.dart'],
                ),
              ),
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('upstream-sync-conflict')));
    await tester.pumpAndSettle();

    // 흐름 안에서 재배치가 실현되어 어긋남이 끝났다.
    resolved = true;
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-clear')));
    await tester.pumpAndSettle();

    final push = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('upstream-sync-push')),
        matching: find.byType(Text),
      ),
    );
    expect(
      push.textSpan!.toPlainText(),
      '↑ 1 Push',
      reason: '남은 걸음은 Push뿐 — 계약 그대로',
    );
  });

  testWidgets('a base the user chose mid-flow is not stomped by the return', (
    tester,
  ) async {
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('aaa1111', 'local work')],
      refs: RepoRefs(
        local: const ['main', 'develop'],
        remote: const ['origin/main'],
        remoteNames: const ['origin'],
        current: 'main',
        tips: const {
          'main': 'aaa1111',
          'develop': 'fff6666',
          'origin/main': 'bbb2222',
        },
        localTips: const {'main': 'aaa1111', 'develop': 'fff6666'},
        aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)},
        upstreams: const {'main': 'origin/main'},
        upstreamRemotes: const {'main': 'origin'},
      ),
      measureUpstreamRebaseCallback:
          ({required remoteTip, required localTip}) async =>
              RebasePreviewResult(
                status: RebasePreviewStatus.conflict,
                baseTip: remoteTip,
                compareTip: localTip,
                conflictFiles: const ['lib/a.dart'],
              ),
      compareBranchesCallback: (base, compare) async =>
          branchComparison(compareRef: compare, compareTip: 'aaa1111'),
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(
                repository,
                const RebasePreviewResult(
                  status: RebasePreviewStatus.conflict,
                  baseTip: 'bbb2222',
                  compareTip: 'aaa1111',
                  conflictFiles: ['lib/a.dart'],
                ),
              ),
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('upstream-sync-conflict')));
    await tester.pumpAndSettle();

    // 흐름 도중 사용자가 기준을 손수 develop으로 바꾼다 — 빌림은 끝났다.
    await tester.tap(find.byKey(const Key('base-branch-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('base-branch-menu-develop')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-clear')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('base-branch-selector')),
        matching: find.text('develop'),
      ),
      findsOneWidget,
      reason: '사용자의 선택을 복원이 덮지 않는다',
    );
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
          (remote, branch, {toBranch, fromTip, setUpstream = false}) async {
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
