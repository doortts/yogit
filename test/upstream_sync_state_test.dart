import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/upstream_sync.dart';

/// 판정은 공짜 사실(ahead/behind)로 먼저 서고, 어긋났을 때만 재연 한 번을
/// 기다린다. 같은 두 끝(tip)을 두 번 재지 않고, 재는 사이 끝이 움직이면 낡은
/// 답을 버리며, 재연이 실패하면 판정을 보류할지언정 틀린 판정을 내리지 않는다.
void main() {
  RepoRefs refs({
    String? current = 'main',
    List<String> local = const ['main'],
    Map<String, String> upstreams = const {'main': 'origin/main'},
    Map<String, String> tips = const {'main': 'aaa', 'origin/main': 'bbb'},
    Map<String, String>? localTips,
    Map<String, BranchAheadBehind> aheadBehind = const {
      'main': BranchAheadBehind(ahead: 0, behind: 0),
    },
  }) => RepoRefs(
    local: local,
    remote: const ['origin/main'],
    remoteNames: const ['origin'],
    current: current,
    tips: tips,
    localTips: localTips ?? {'main': tips['main'] ?? 'aaa'},
    aheadBehind: aheadBehind,
    upstreams: upstreams,
    upstreamRemotes: const {'main': 'origin'},
  );

  RebasePreviewResult clean(String virtualTip) => RebasePreviewResult(
    status: RebasePreviewStatus.clean,
    baseTip: 'bbb',
    compareTip: 'aaa',
    virtualTip: virtualTip,
  );

  const conflicted = RebasePreviewResult(
    status: RebasePreviewStatus.conflict,
    baseTip: 'bbb',
    compareTip: 'aaa',
    conflictFiles: ['lib/a.dart', 'lib/b.dart'],
  );

  const failed = RebasePreviewResult(
    status: RebasePreviewStatus.failed,
    baseTip: 'bbb',
    compareTip: 'aaa',
    error: 'worktree add failed',
  );

  test(
    'the free facts settle every un-diverged kind without measuring',
    () async {
      var measured = 0;
      final controller = UpstreamSyncController(
        measure: ({required remoteTip, required localTip}) async {
          measured++;
          return clean('ccc');
        },
      );
      addTearDown(controller.dispose);

      controller.updateRefs(refs(), null);
      expect(controller.state.kind, UpstreamSyncKind.hidden, reason: '기준이 없다');

      controller.updateRefs(refs(), 'origin/main');
      expect(
        controller.state.kind,
        UpstreamSyncKind.hidden,
        reason: '원격 ref가 기준이면 올릴 로컬이 없다',
      );

      controller.updateRefs(refs(upstreams: const {}), 'main');
      expect(controller.state.kind, UpstreamSyncKind.firstPush);

      controller.updateRefs(refs(tips: const {'main': 'aaa'}), 'main');
      expect(
        controller.state.kind,
        UpstreamSyncKind.firstPush,
        reason: 'upstream 이름만 남고 원격 ref가 사라졌다',
      );

      controller.updateRefs(refs(), 'main');
      expect(controller.state.kind, UpstreamSyncKind.synced);

      controller.updateRefs(
        refs(
          aheadBehind: const {'main': BranchAheadBehind(ahead: 3, behind: 0)},
        ),
        'main',
      );
      expect(controller.state.kind, UpstreamSyncKind.pushOnly);
      expect(controller.state.ahead, 3);

      controller.updateRefs(
        refs(
          aheadBehind: const {'main': BranchAheadBehind(ahead: 0, behind: 2)},
        ),
        'main',
      );
      expect(controller.state.kind, UpstreamSyncKind.pullOnly);
      expect(controller.state.behind, 2);

      expect(measured, 0, reason: '어긋나지 않으면 재연은 없다');
    },
  );

  test(
    'divergence measures once and wears the verdict on both sides',
    () async {
      final measures = <({String remoteTip, String localTip})>[];
      final kinds = <UpstreamSyncKind>[];
      final controller = UpstreamSyncController(
        measure: ({required remoteTip, required localTip}) async {
          measures.add((remoteTip: remoteTip, localTip: localTip));
          return clean('ccc');
        },
      );
      addTearDown(controller.dispose);
      controller.addListener(() => kinds.add(controller.state.kind));

      final diverged = refs(
        aheadBehind: const {'main': BranchAheadBehind(ahead: 3, behind: 2)},
      );
      controller.updateRefs(diverged, 'main');
      expect(controller.state.kind, UpstreamSyncKind.measuring);
      expect(controller.state.ahead, 3);
      expect(controller.state.behind, 2);

      await pumpEventQueue();
      expect(controller.state.kind, UpstreamSyncKind.divergedClean);
      expect(controller.state.virtualTip, 'ccc');
      expect(controller.state.measuredAt, isNotNull);
      expect(measures.single, (remoteTip: 'bbb', localTip: 'aaa'));
      expect(kinds, [
        UpstreamSyncKind.measuring,
        UpstreamSyncKind.divergedClean,
      ]);

      // 같은 두 끝은 다시 재지 않는다.
      controller.updateRefs(diverged, 'main');
      await pumpEventQueue();
      expect(measures, hasLength(1));
      expect(controller.state.kind, UpstreamSyncKind.divergedClean);
    },
  );

  test('a conflicted replay names its files', () async {
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) async => conflicted,
    );
    addTearDown(controller.dispose);

    controller.updateRefs(
      refs(aheadBehind: const {'main': BranchAheadBehind(ahead: 3, behind: 2)}),
      'main',
    );
    await pumpEventQueue();

    expect(controller.state.kind, UpstreamSyncKind.divergedConflict);
    expect(controller.state.conflictFiles, ['lib/a.dart', 'lib/b.dart']);
  });

  test('a measure in flight is not fired twice for the same tips', () async {
    var measured = 0;
    final gate = Completer<RebasePreviewResult>();
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) {
        measured++;
        return gate.future;
      },
    );
    addTearDown(controller.dispose);

    final diverged = refs(
      aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)},
    );
    controller.updateRefs(diverged, 'main');
    controller.updateRefs(diverged, 'main');
    expect(measured, 1);

    gate.complete(clean('ccc'));
    await pumpEventQueue();
    expect(controller.state.kind, UpstreamSyncKind.divergedClean);
  });

  test('a tip that moves mid-measure throws the stale answer away', () async {
    final gates = <String, Completer<RebasePreviewResult>>{};
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) =>
          (gates[localTip] = Completer<RebasePreviewResult>()).future,
    );
    addTearDown(controller.dispose);

    controller.updateRefs(
      refs(aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)}),
      'main',
    );
    // 재는 사이 로컬에 커밋이 하나 더 붙었다.
    controller.updateRefs(
      refs(
        tips: const {'main': 'aa2', 'origin/main': 'bbb'},
        aheadBehind: const {'main': BranchAheadBehind(ahead: 2, behind: 1)},
      ),
      'main',
    );
    expect(gates.keys, ['aaa', 'aa2']);

    // 낡은 답이 나중에 도착해도 버려진다.
    gates['aaa']!.complete(clean('stale'));
    await pumpEventQueue();
    expect(controller.state.kind, UpstreamSyncKind.measuring);

    gates['aa2']!.complete(clean('fresh'));
    await pumpEventQueue();
    expect(controller.state.kind, UpstreamSyncKind.divergedClean);
    expect(controller.state.virtualTip, 'fresh');
    expect(controller.state.localTip, 'aa2');
  });

  test('a measure landing after the divergence ended is thrown away', () async {
    final gate = Completer<RebasePreviewResult>();
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) => gate.future,
    );
    addTearDown(controller.dispose);

    controller.updateRefs(
      refs(aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)}),
      'main',
    );
    expect(controller.state.kind, UpstreamSyncKind.measuring);

    // 재는 사이 어긋남 자체가 끝났다 — 원격이 우리 커밋만 받아들였다.
    controller.updateRefs(
      refs(aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 0)}),
      'main',
    );
    expect(controller.state.kind, UpstreamSyncKind.pushOnly);

    gate.complete(clean('stale'));
    await pumpEventQueue();
    expect(
      controller.state.kind,
      UpstreamSyncKind.pushOnly,
      reason: '끝난 어긋남의 답이 산 판정을 덮지 않는다',
    );
  });

  test('a failed measure withholds judgement and stays retryable', () async {
    var attempt = 0;
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) async =>
          attempt++ == 0 ? failed : clean('ccc'),
    );
    addTearDown(controller.dispose);

    final diverged = refs(
      aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)},
    );
    controller.updateRefs(diverged, 'main');
    await pumpEventQueue();
    expect(
      controller.state.kind,
      UpstreamSyncKind.measuring,
      reason: '틀린 판정보다 판정 보류가 낫다',
    );

    // 실패는 답이 아니라서 같은 두 끝을 다시 잴 수 있다.
    controller.updateRefs(diverged, 'main');
    await pumpEventQueue();
    expect(attempt, 2);
    expect(controller.state.kind, UpstreamSyncKind.divergedClean);
  });

  test('a failed measure after a verdict keeps the last verdict', () async {
    var fail = false;
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) async =>
          fail ? failed : clean('ccc'),
    );
    addTearDown(controller.dispose);

    controller.updateRefs(
      refs(aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)}),
      'main',
    );
    await pumpEventQueue();
    expect(controller.state.kind, UpstreamSyncKind.divergedClean);
    final measuredAt = controller.state.measuredAt;

    fail = true;
    controller.updateRefs(
      refs(
        tips: const {'main': 'aa2', 'origin/main': 'bbb'},
        aheadBehind: const {'main': BranchAheadBehind(ahead: 2, behind: 1)},
      ),
      'main',
    );
    await pumpEventQueue();

    expect(
      controller.state.kind,
      UpstreamSyncKind.divergedClean,
      reason: '마지막으로 성립한 판정이 남는다',
    );
    expect(
      controller.state.measuredAt,
      measuredAt,
      reason: '낡은 판정임은 잰 시각이 말한다',
    );
  });

  test(
    "another branch's failure never revives this branch's verdict",
    () async {
      // main의 판정이 성립한 뒤 기준을 feature로 바꾸고, feature의 재연이
      // 실패한다. main의 판정이 feature의 얼굴로 부활하면 사용자는 feature를
      // 보며 main을 Push하게 된다.
      var fail = false;
      final controller = UpstreamSyncController(
        measure: ({required remoteTip, required localTip}) async =>
            fail ? failed : clean('ccc'),
      );
      addTearDown(controller.dispose);

      controller.updateRefs(
        refs(
          aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)},
        ),
        'main',
      );
      await pumpEventQueue();
      expect(controller.state.kind, UpstreamSyncKind.divergedClean);

      fail = true;
      controller.updateRefs(
        refs(
          local: const ['main', 'feature'],
          upstreams: const {'feature': 'origin/feature'},
          tips: const {'feature': 'fff', 'origin/feature': 'ggg'},
          localTips: const {'feature': 'fff'},
          aheadBehind: const {
            'feature': BranchAheadBehind(ahead: 1, behind: 1),
          },
        ),
        'feature',
      );
      await pumpEventQueue();

      expect(
        controller.state.kind,
        UpstreamSyncKind.measuring,
        reason: '다른 브랜치의 판정은 이 브랜치의 답이 아니다',
      );
      expect(controller.state.branch, 'feature');
    },
  );

  test('a verdict names the branch it was measured for', () async {
    // 두 브랜치가 우연히 같은 두 끝을 가져도, 판정은 잰 브랜치의 것이다.
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) async => clean('ccc'),
    );
    addTearDown(controller.dispose);

    final shared = refs(
      local: const ['main', 'twin'],
      upstreams: const {'main': 'origin/main', 'twin': 'origin/main'},
      localTips: const {'main': 'aaa', 'twin': 'aaa'},
      aheadBehind: const {
        'main': BranchAheadBehind(ahead: 1, behind: 1),
        'twin': BranchAheadBehind(ahead: 1, behind: 1),
      },
    );
    controller.updateRefs(shared, 'main');
    await pumpEventQueue();
    expect(controller.state.branch, 'main');

    controller.updateRefs(shared, 'twin');
    await pumpEventQueue();
    expect(
      controller.state.branch,
      'twin',
      reason: '같은 두 끝이라도 남의 이름표를 달고 나오지 않는다',
    );
  });

  test('a settled verdict keeps the whole story, not just the kind', () async {
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) async => clean('ccc'),
    );
    addTearDown(controller.dispose);

    controller.updateRefs(
      refs(aheadBehind: const {'main': BranchAheadBehind(ahead: 3, behind: 2)}),
      'main',
    );
    await pumpEventQueue();

    final state = controller.state;
    expect(state.kind, UpstreamSyncKind.divergedClean);
    expect(state.branch, 'main');
    expect(state.remote, 'origin');
    expect(state.upstreamRef, 'origin/main');
    expect(state.ahead, 3);
    expect(state.behind, 2);
    expect(state.checkedOut, isTrue);
  });

  test('a failed measure says so, for the status bar to repeat', () async {
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) async => failed,
    );
    addTearDown(controller.dispose);

    controller.updateRefs(
      refs(aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)}),
      'main',
    );
    await pumpEventQueue();

    expect(controller.state.measureError, 'worktree add failed');

    // 어긋남이 끝나면 오류도 끝이다.
    controller.updateRefs(refs(), 'main');
    expect(controller.state.measureError, isNull);
  });

  test('dispose kills the answer in flight', () async {
    final gate = Completer<RebasePreviewResult>();
    var notified = 0;
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) => gate.future,
    );
    controller.addListener(() => notified++);

    controller.updateRefs(
      refs(aheadBehind: const {'main': BranchAheadBehind(ahead: 1, behind: 1)}),
      'main',
    );
    final before = notified;
    controller.dispose();

    gate.complete(clean('ccc'));
    await pumpEventQueue();
    expect(notified, before, reason: '무덤 너머에서 알리지 않는다');
  });

  test('the sole remote of the repository names the first push', () async {
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) async => clean('ccc'),
    );
    addTearDown(controller.dispose);

    controller.updateRefs(
      const RepoRefs(
        local: ['main'],
        remoteNames: ['company'],
        current: 'main',
        localTips: {'main': 'aaa'},
      ),
      'main',
    );

    expect(controller.state.kind, UpstreamSyncKind.firstPush);
    expect(
      controller.state.remote,
      'company',
      reason: "유일한 원격이 있는데 'origin'을 짐작하지 않는다",
    );
  });

  test(
    'the freshness the tooltip speaks is the fetch, not the judge',
    () async {
      final controller = UpstreamSyncController(
        measure: ({required remoteTip, required localTip}) async =>
            clean('ccc'),
      );
      addTearDown(controller.dispose);

      final fetchedAt = DateTime(2026, 8, 12, 10, 0);
      controller.updateRefs(refs(), 'main', refreshedAt: fetchedAt);
      expect(controller.state.kind, UpstreamSyncKind.synced);
      expect(controller.state.checkedAt, fetchedAt);

      // refs가 로컬 작업으로 다시 로드돼도 fetch 시각은 남는다.
      controller.updateRefs(refs(), 'main');
      expect(controller.state.checkedAt, fetchedAt);
    },
  );

  test('a cached verdict still reads the checkout of today', () async {
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) async => clean('ccc'),
    );
    addTearDown(controller.dispose);

    final diverged = {'main': const BranchAheadBehind(ahead: 1, behind: 1)};
    controller.updateRefs(refs(aheadBehind: diverged), 'main');
    await pumpEventQueue();
    expect(controller.state.checkedOut, isTrue);

    // 판정은 그대로 쓰되, 체크아웃이 옮겨 간 사실은 오늘 것을 말한다.
    controller.updateRefs(
      refs(current: 'elsewhere', aheadBehind: diverged),
      'main',
    );
    expect(controller.state.kind, UpstreamSyncKind.divergedClean);
    expect(controller.state.checkedOut, isFalse);
  });

  test('the state carries what the actions will need', () async {
    final controller = UpstreamSyncController(
      measure: ({required remoteTip, required localTip}) async => clean('ccc'),
    );
    addTearDown(controller.dispose);

    controller.updateRefs(
      refs(aheadBehind: const {'main': BranchAheadBehind(ahead: 3, behind: 0)}),
      'main',
    );

    expect(controller.state.branch, 'main');
    expect(controller.state.remote, 'origin');
    expect(controller.state.upstreamRef, 'origin/main');
    expect(controller.state.localTip, 'aaa');
    expect(controller.state.remoteTip, 'bbb');
    expect(
      controller.state.checkedOut,
      isTrue,
      reason: 'Pull의 두 경로는 체크아웃 여부가 가른다',
    );

    controller.updateRefs(
      refs(
        current: 'other',
        aheadBehind: const {'main': BranchAheadBehind(ahead: 3, behind: 0)},
      ),
      'main',
    );
    expect(controller.state.checkedOut, isFalse);
  });
}
