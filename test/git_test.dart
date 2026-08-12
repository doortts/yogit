import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/git.dart';
import 'package:yogit/timeline.dart';

void main() {
  test('loads the complete commit message body', () async {
    late List<String> arguments;
    final repository = GitRepository(
      '/repo',
      runner: (executable, args, {workingDirectory, environment}) async {
        arguments = args;
        return ProcessResult(1, 0, 'Subject\n\nBody line\n', '');
      },
    );

    expect(
      await repository.loadCommitMessage('40aff6d'),
      'Subject\n\nBody line\n',
    );
    expect(arguments, ['show', '-s', '--format=%B', '40aff6d']);
  });

  test('parses a merge log record with identities and refs', () {
    const log =
        'b561300abcde0000000000000000000000000000\x1f'
        'b561300abcde\x1f'
        '1111111111111111111111111111111111111111 '
        '2222222222222222222222222222222222222222\x1f'
        'Ada Author\x1fada@example.com\x1f1700000000\x1f'
        'Cam Committer\x1fcam@example.com\x1f1700000100\x1f'
        'HEAD -> main, tag: v1.0, origin/main\x1f'
        'Merge feature\x1e';

    final commits = parseGitLog(log);

    expect(commits.single.shortSha, 'b561300');
    expect(commits.single.parents, hasLength(2));
    expect(commits.single.author.name, 'Ada Author');
    expect(commits.single.committer.email, 'cam@example.com');
    expect(commits.single.refs.map((ref) => ref.name), [
      'main',
      'v1.0',
      'origin/main',
    ]);
  });

  test('drops origin/HEAD, an alias for a branch already listed', () {
    const log =
        'b561300abcde0000000000000000000000000000\x1f'
        'b561300abcde\x1f'
        '1111111111111111111111111111111111111111\x1f'
        'Ada Author\x1fada@example.com\x1f1700000000\x1f'
        'Cam Committer\x1fcam@example.com\x1f1700000100\x1f'
        'origin/HEAD, origin/main, upstream/HEAD, upstream/main\x1f'
        'A commit\x1e';

    // `origin/HEAD` is a symbolic alias; whatever it points at is decorated on
    // the same commit, so showing it only doubles the chip.
    expect(parseGitLog(log).single.refs.map((ref) => ref.name), [
      'origin/main',
      'upstream/main',
    ]);
  });

  test('keeps a branch merely named HEAD-something', () {
    const log =
        'b561300abcde0000000000000000000000000000\x1f'
        'b561300abcde\x1f'
        '1111111111111111111111111111111111111111\x1f'
        'Ada Author\x1fada@example.com\x1f1700000000\x1f'
        'Cam Committer\x1fcam@example.com\x1f1700000100\x1f'
        'origin/HEADroom, HEAD -> HEADless\x1f'
        'A commit\x1e';

    expect(parseGitLog(log).single.refs.map((ref) => ref.name), [
      'origin/HEADroom',
      'HEADless',
    ]);
  });

  test('finds a deleted branch from recognized merge subjects', () {
    for (final entry in {
      "Merge branch 'feature/local'": 'feature/local',
      "Merge remote-tracking branch 'origin/fix/remote'": 'fix/remote',
      'Merge pull request #42 from octo/topic/pr': 'topic/pr',
    }.entries) {
      final commits = [
        _commit('merge', ['main', 'tip'], subject: entry.key),
        _commit('tip', ['base']),
      ];

      expect(deletedBranchNameFromMerge(commits, 'tip'), entry.value);
    }
  });

  test(
    'deleted branch merge lookup ignores arbitrary and first-parent text',
    () {
      expect(
        deletedBranchNameFromMerge([
          _commit('merge', ['tip', 'side'], subject: "Merge branch 'feature'"),
          _commit('other', ['main', 'tip'], subject: 'Merge feature'),
        ], 'tip'),
        isNull,
      );
    },
  );

  test('one pass over the commits names every merged-in line at once', () {
    // 줄 하나를 물을 때마다 커밋 전체를 훑는 대신 한 번에 색인을 만든다.
    final names = mergedBranchNamesByTip([
      _commit('merge', ['main', 'tip'], subject: "Merge branch 'feature/one'"),
      _commit('octopus', [
        'main',
        'left',
        'right',
      ], subject: "Merge branch 'feature/many'"),
      _commit('plain', ['main'], subject: "Merge branch 'not/a/merge'"),
      _commit('noisy', ['main', 'other'], subject: 'Merge feature'),
    ]);

    // 두 부모짜리 머지만, 그리고 알아보는 제목만 색인에 들어간다. 제목 하나는
    // 브랜치 하나를 말하므로, 부모 셋을 그 이름으로 함께 부르면 지어내는 것이다.
    expect(names, {'tip': 'feature/one'});
  });

  test('the merge index keeps the newest name for a reused tip', () {
    // 같은 커밋이 두 번 머지됐으면 위에 있는(더 최근) 제목이 이긴다.
    final names = mergedBranchNamesByTip([
      _commit('newer', ['main', 'tip'], subject: "Merge branch 'renamed'"),
      _commit('older', ['main', 'tip'], subject: "Merge branch 'original'"),
    ]);

    expect(names['tip'], 'renamed');
  });

  test(
    'deleted branch reflog finds the checkout source before the matching tip',
    () {
      const output =
          'main-tip\x00checkout: moving from feature/gone to main\n'
          'gone-tip\x00commit: finish feature\n';

      expect(deletedBranchNameFromReflog(output, 'gone-tip'), 'feature/gone');
    },
  );

  test('one reflog read names every branch it was ever checked out from', () {
    const output =
        'main-tip\x00checkout: moving from feature/newest to main\n'
        'newest-tip\x00commit: finish the newest\n'
        'other-tip\x00checkout: moving from feature/older to main\n'
        'older-tip\x00commit: finish the older\n'
        'older-tip\x00checkout: moving from HEAD to main\n'
        'detached-tip\x00commit: on a detached head\n';

    // 접어 두면 그 뒤로는 tip 하나를 물을 때마다 reflog를 다시 읽지 않는다.
    expect(deletedBranchNamesFromReflog(output), {
      'newest-tip': 'feature/newest',
      'older-tip': 'feature/older',
    });
  });

  test('the folded reflog keeps the newest name for a reused tip', () {
    const output =
        'a\x00checkout: moving from renamed to main\n'
        'tip\x00commit: work\n'
        'b\x00checkout: moving from original to main\n'
        'tip\x00commit: work\n';

    expect(deletedBranchNamesFromReflog(output)['tip'], 'renamed');
  });

  test('deleted branch reflog lookup rejects detached checkout sources', () {
    for (final source in ['HEAD', '-', '307fc8b']) {
      final output =
          'main-tip\x00checkout: moving from $source to main\n'
          'gone-tip\x00commit: finish feature\n';

      expect(deletedBranchNameFromReflog(output, 'gone-tip'), isNull);
    }
  });

  test(
    'local deleted branch lookup falls back from merge to HEAD reflog',
    () async {
      late List<String> arguments;
      final repository = GitRepository(
        '/repo',
        runner: (executable, args, {workingDirectory, environment}) async {
          arguments = args;
          return ProcessResult(
            1,
            0,
            'main-tip\x00checkout: moving from feature/gone to main\n'
                'gone-tip\x00commit: finish feature\n',
            '',
          );
        },
      );

      expect(
        await repository.loadLocalDeletedBranchName('gone-tip', const []),
        'feature/gone',
      );
      expect(arguments, ['reflog', 'show', '--format=%H%x00%gs', 'HEAD']);
    },
  );

  test('the reflog is read once, with a ceiling on how far back', () async {
    late List<String> arguments;
    final repository = GitRepository(
      '/repo',
      runner: (executable, args, {workingDirectory, environment}) async {
        arguments = args;
        return ProcessResult(
          1,
          0,
          'main-tip\x00checkout: moving from feature/gone to main\n'
              'gone-tip\x00commit: finish feature\n',
          '',
        );
      },
    );

    expect(await repository.loadReflogBranchNames(limit: 500), {
      'gone-tip': 'feature/gone',
    });
    expect(arguments, [
      'reflog',
      'show',
      '--format=%H%x00%gs',
      '-n',
      '500',
      'HEAD',
    ]);

    // 기본 상한은 그리는 isolate에서 5ms쯤 쓰는 지점이다. 숫자를 올리면 그 예산을
    // 올리는 것이니, 바꿀 때 함께 읽히도록 여기에 묶어 둔다.
    await repository.loadReflogBranchNames();
    expect(arguments[4], '7000');
  });

  test('a repository with no reflog folds to nothing, not an error', () async {
    final repository = GitRepository(
      '/repo',
      runner: (executable, args, {workingDirectory, environment}) async =>
          throw const ProcessException('git', ['reflog']),
    );

    expect(await repository.loadReflogBranchNames(), isEmpty);
  });

  test('a moved branch says what moved it and what came of it', () async {
    final commands = <List<String>>[];
    final repository = GitRepository(
      '/repo',
      runner: (executable, args, {workingDirectory, environment}) async {
        commands.add(args);
        return ProcessResult(1, 0, switch (args.first) {
          'reflog' => 'pull: Fast-forward\n',
          'rev-list' => '0\t3\n',
          _ =>
            '> 89a61cb feat: let a remote branch stand as the base\n'
                '> 06fdbd1 test: pin the origin/HEAD drop against real output\n'
                '> 954e6e8 fix: stop drawing origin/HEAD as if it were a branch\n',
        }, '');
      },
    );

    expect(await repository.loadBranchOperation('main'), 'pull');
    expect(await repository.countMovedCommits('old', 'new'), (
      outgoing: 0,
      incoming: 3,
    ));
    final commits = await repository.loadMovedCommits('old', 'new', limit: 9);
    expect(commits, hasLength(3));
    expect(commits.first.incoming, isTrue);
    expect(commits.first.shortSha, '89a61cb');

    expect(commands[0], ['reflog', 'show', '--format=%gs', '-n', '1', 'main']);
    expect(commands[1], ['rev-list', '--left-right', '--count', 'old...new']);
    expect(commands[2], [
      'log',
      '--left-right',
      '--oneline',
      '-n',
      '9',
      'old...new',
    ]);
  });

  test(
    'a repository that cannot answer says nothing, and does not throw',
    () async {
      final repository = GitRepository(
        '/repo',
        runner: (executable, args, {workingDirectory, environment}) async =>
            throw const ProcessException('git', ['reflog']),
      );

      expect(await repository.loadBranchOperation('main'), isNull);
      expect(await repository.countMovedCommits('old', 'new'), isNull);
      expect(await repository.loadMovedCommits('old', 'new'), isEmpty);
    },
  );

  test('resolves a saved local branch before current and first local', () {
    const refs = RepoRefs(local: ['main', 'release'], current: 'main');
    expect(resolveBaseBranch(refs, 'release'), 'release');
    expect(resolveBaseBranch(refs, 'deleted'), 'main');
    expect(
      resolveBaseBranch(
        const RepoRefs(local: ['release'], current: null),
        null,
      ),
      'release',
    );
    expect(resolveBaseBranch(const RepoRefs(), null), isNull);
    // 기준을 원격 브랜치로 골라 뒀으면 그대로 되살린다.
    const withRemote = RepoRefs(
      local: ['main'],
      remote: ['origin/main'],
      current: 'main',
    );
    expect(resolveBaseBranch(withRemote, 'origin/main'), 'origin/main');
    expect(resolveBaseBranch(withRemote, 'origin/gone'), 'main');
  });

  test('a remote base rebases the local branch onto it', () {
    // 기준이 origin/main, 비교가 로컬 main. pull --rebase와 같은 방향이라 재배치
    // 결과를 받을 브랜치는 로컬 main 자신이고, 그 tip이 곧 비교 tip이다.
    const comparison = BranchComparisonResult(
      baseRef: 'origin/main',
      compareRef: 'main',
      baseTip: 'remote-tip',
      compareTip: 'local-tip',
      baseParent: null,
      compareParent: null,
      mergeBases: [],
      commits: [],
      files: [],
      merge: MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: 'merge-tree',
      ),
    );
    const refs = RepoRefs(
      local: ['main'],
      remote: ['origin/main'],
      tips: {'main': 'local-tip', 'origin/main': 'remote-tip'},
      localTips: {'main': 'local-tip'},
    );

    final rebase = resolveBranchApplyTarget(
      mode: BranchApplyMode.rebase,
      comparison: comparison,
      refs: refs,
    );
    expect(rebase?.localBranch, 'main');
    expect(rebase?.createsBranch, isFalse);
    expect(rebase?.needsRecalculation, isFalse);

    // 원격 기준을 옮길 수는 없으니 Merge 쪽은 받을 브랜치가 없다.
    expect(
      resolveBranchApplyTarget(
        mode: BranchApplyMode.merge,
        comparison: comparison,
        refs: refs,
      ),
      isNull,
    );
  });

  const remoteComparison = BranchComparisonResult(
    baseRef: 'main',
    compareRef: 'origin/feature',
    baseTip: 'main-tip',
    compareTip: 'remote-tip',
    baseParent: null,
    compareParent: null,
    mergeBases: [],
    commits: [],
    files: [],
    merge: MergeConflictCheck(
      status: MergeConflictStatus.clean,
      treeSha: 'merge-tree',
    ),
  );

  test('remote rebase target maps to a missing local branch', () {
    const refs = RepoRefs(
      local: ['main'],
      remote: ['origin/feature'],
      tips: {'main': 'main-tip', 'origin/feature': 'remote-tip'},
      localTips: {'main': 'main-tip'},
    );

    final target = resolveBranchApplyTarget(
      mode: BranchApplyMode.rebase,
      comparison: remoteComparison,
      refs: refs,
    );

    expect(target?.selectedRef, 'origin/feature');
    expect(target?.selectedTip, 'remote-tip');
    expect(target?.localBranch, 'feature');
    expect(target?.localTip, isNull);
    expect(target?.createsBranch, isTrue);
    expect(target?.needsRecalculation, isFalse);
  });

  test('different same-named local rebase target requires recalculation', () {
    const refs = RepoRefs(
      local: ['main', 'feature'],
      remote: ['origin/feature'],
      tips: {
        'main': 'main-tip',
        'feature': 'local-tip',
        'origin/feature': 'remote-tip',
      },
      localTips: {'main': 'main-tip', 'feature': 'local-tip'},
    );

    final target = resolveBranchApplyTarget(
      mode: BranchApplyMode.rebase,
      comparison: remoteComparison,
      refs: refs,
    );

    expect(target?.localBranch, 'feature');
    expect(target?.localTip, 'local-tip');
    expect(target?.createsBranch, isFalse);
    expect(target?.needsRecalculation, isTrue);
  });

  test('matching same-named local rebase target is reused', () {
    const refs = RepoRefs(
      local: ['main', 'feature'],
      remote: ['origin/feature'],
      tips: {
        'main': 'main-tip',
        'feature': 'remote-tip',
        'origin/feature': 'remote-tip',
      },
      localTips: {'main': 'main-tip', 'feature': 'remote-tip'},
    );

    final target = resolveBranchApplyTarget(
      mode: BranchApplyMode.rebase,
      comparison: remoteComparison,
      refs: refs,
    );

    expect(target?.localBranch, 'feature');
    expect(target?.localTip, 'remote-tip');
    expect(target?.createsBranch, isFalse);
    expect(target?.needsRecalculation, isFalse);
  });

  test('preferred tip reserves lane zero across newer branch commits', () {
    final commits = [
      _commit('feature-tip', ['base']),
      _commit('main-tip', ['main-parent']),
      _commit('main-parent', ['base']),
      _commit('base', const []),
    ];

    final rows = layoutGraph(commits, preferredTip: 'main-tip');

    expect([for (final row in rows) row.lane], [1, 0, 0, 0]);
    expect([for (final row in layoutGraph(commits)) row.lane], [0, 1, 1, 0]);
  });

  test('preferred lane zero stays reserved after its root', () {
    final commits = [
      _commit('P', ['R']),
      _commit('R', const []),
      _commit('O', const []),
    ];

    final preferred = layoutGraph(commits, preferredTip: 'P');
    final legacy = layoutGraph(commits);

    expect([for (final row in preferred) row.lane], [0, 0, 1]);
    expect([for (final row in legacy) row.lane], [0, 0, 0]);
  });

  test('working tree uses lane zero only when its parent is preferred', () {
    final current = layoutGraph([
      _commit('', ['main-tip']),
      _commit('main-tip', ['root']),
      _commit('root', const []),
    ], preferredTip: 'main-tip');
    expect([for (final row in current) row.lane], [0, 0, 0]);

    final other = layoutGraph([
      _commit('', ['feature-tip']),
      _commit('feature-tip', ['root']),
      _commit('main-tip', ['root']),
      _commit('root', const []),
    ], preferredTip: 'main-tip');
    expect(other.first.lane, greaterThan(0));
    expect(other[2].lane, 0);
  });

  test('working tree preserves an unloaded preferred first-parent edge', () {
    final commits = [
      _commit('', ['preferred']),
      _commit('child', ['preferred']),
      _commit('side', ['side-root']),
      _commit('preferred', const []),
      _commit('side-root', const []),
    ];
    final page = layoutGraph(
      commits.take(3).toList(),
      preferredTip: 'preferred',
    );
    final full = layoutGraph(commits, preferredTip: 'preferred');
    final prefix = full.take(3);

    expect([for (final row in page) row.lane], [0, 1, 1]);
    expect([for (final row in page) row.branch], [0, 1, 2]);
    expect(
      [for (final row in page) row.parentLanes],
      [
        [0],
        [0],
        [1],
      ],
    );
    expect(
      [for (final row in page) row.transitions],
      [
        const <LaneTransition>[],
        [(from: 1, to: 0, sha: 'preferred')],
        const <LaneTransition>[],
      ],
    );
    expect([for (final row in page) row.nextLaneBranches[0]], [0, 0, 0]);
    expect(
      [for (final row in page) row.lane],
      [for (final row in prefix) row.lane],
    );
    expect(
      [for (final row in page) row.branch],
      [for (final row in prefix) row.branch],
    );
    expect(
      [for (final row in page) row.parentLanes],
      [for (final row in prefix) row.parentLanes],
    );
    expect(
      [for (final row in page) row.transitions],
      [for (final row in prefix) row.transitions],
    );
    expect(
      [for (final row in page) row.nextLaneBranches[0]],
      [for (final row in prefix) row.nextLaneBranches[0]],
    );
  });

  test('working tree preserves an unloaded preferred merge-parent edge', () {
    final commits = [
      _commit('', ['preferred']),
      _commit('merge', ['main', 'preferred']),
      _commit('main', const []),
      _commit('preferred', const []),
    ];
    final page = layoutGraph(
      commits.take(3).toList(),
      preferredTip: 'preferred',
    );
    final full = layoutGraph(commits, preferredTip: 'preferred');
    final prefix = full.take(3);

    expect([for (final row in page) row.lane], [0, 1, 1]);
    expect([for (final row in page) row.branch], [0, 1, 1]);
    expect(
      [for (final row in page) row.parentLanes],
      [
        [0],
        [1, 0],
        const <int>[],
      ],
    );
    expect(
      [for (final row in page) row.transitions],
      [
        const <LaneTransition>[],
        [(from: 1, to: 0, sha: 'preferred')],
        const <LaneTransition>[],
      ],
    );
    expect([for (final row in page) row.nextLaneBranches[0]], [0, 0, 0]);
    expect(
      [for (final row in page) row.lane],
      [for (final row in prefix) row.lane],
    );
    expect(
      [for (final row in page) row.branch],
      [for (final row in prefix) row.branch],
    );
    expect(
      [for (final row in page) row.parentLanes],
      [for (final row in prefix) row.parentLanes],
    );
    expect(
      [for (final row in page) row.transitions],
      [for (final row in prefix) row.transitions],
    );
    expect(
      [for (final row in page) row.nextLaneBranches[0]],
      [for (final row in prefix) row.nextLaneBranches[0]],
    );
  });

  test('merge-parent edge to unloaded preferred tip uses lane zero', () {
    final row = layoutGraph([
      _commit('merge', ['main', 'preferred']),
    ], preferredTip: 'preferred').single;

    expect(row.lane, 1);
    expect(row.parentLanes, [1, 0]);
    expect(row.nextLaneShas, {0: 'preferred', 1: 'main'});
    expect(row.transitions, [(from: 1, to: 0, sha: 'preferred')]);
  });

  test('first-parent edge to unloaded preferred tip uses lane zero', () {
    final page = layoutGraph([
      _commit('child', ['preferred']),
    ], preferredTip: 'preferred');
    final full = layoutGraph([
      _commit('child', ['preferred']),
      _commit('preferred', ['root']),
      _commit('root', const []),
    ], preferredTip: 'preferred');

    expect(page.single.lane, 1);
    expect(page.single.parentLanes, [0]);
    expect(page.single.nextLaneShas, {0: 'preferred'});
    expect(page.single.transitions, [(from: 1, to: 0, sha: 'preferred')]);
    expect(page.single.lane, full.first.lane);
    expect(page.single.branch, full.first.branch);
    expect(page.single.transitions, full.first.transitions);
  });

  test('a first-parent chain keeps a single column', () {
    // Main is the first parent all the way down, so it never leaves column 0 —
    // not even across the merge that pulls in the side branch.
    final rows = layoutGraph([
      _commit('M', ['A', 'S']),
      _commit('A', ['R']),
      _commit('S', ['R']),
      _commit('R', const []),
    ]);

    expect([for (final row in rows) row.lane], [0, 0, 1, 0]);
    expect(rows[0].parentLanes.first, 0);
    expect(rows[1].parentLanes, [0]);
    _expectStableColumns(rows);
  });

  test('a merge edge drops in the parent column without moving anyone', () {
    // N is new and columns 0 and 1 are busy, so N opens column 2. The tip in
    // column 1 keeps its index — columns never slide under it.
    final rows = layoutGraph([
      _commit('T', ['M']),
      _commit('S', ['X']),
      _commit('M', ['P', 'N']),
      _commit('N', const []),
    ]);

    expect(rows[2].lane, 0);
    expect(rows[2].parentLanes, [0, 2]);
    expect(rows[2].transitions, [(from: 0, to: 2, sha: 'N')]);
    expect(rows[2].nextLaneShas, {0: 'P', 1: 'X', 2: 'N'});
    expect(rows[3].lane, 2);
    expect(rows[3].activeLaneShas, {0: 'P', 1: 'X', 2: 'N'});
    expect(rows[3].nextLaneShas, {0: 'P', 1: 'X'});
    _expectStableColumns(rows);
  });

  test('a merge edge passes through the rows between child and parent', () {
    // M waits for N two rows down, so N's column carries the edge on every row
    // in between, and the horizontal sweep stays on M's own row.
    final rows = layoutGraph([
      _commit('M', ['A', 'N']),
      _commit('A', ['R']),
      _commit('N', ['R']),
      _commit('R', const []),
    ]);

    expect(rows[2].lane, 1);
    expect(rows[0].transitions, [(from: 0, to: 1, sha: 'N')]);
    expect(rows[1].activeLaneShas, {0: 'A', 1: 'N'});
    expect(rows[1].nextLaneShas, {0: 'R', 1: 'N'});
    expect(rows[1].transitions, isEmpty);
    _expectStableColumns(rows);
  });

  test('reuses the leftmost freed column instead of a new one', () {
    final rows = layoutGraph([
      _commit('A', ['C']),
      _commit('B', ['C']),
      _commit('C', ['D']),
      _commit('E', ['D']),
      _commit('D', const []),
    ]);

    // B's column 1 is released when C absorbs it, so the later tip E reuses it.
    expect(rows[1].lane, 1);
    expect(rows[2].nextLanes, [0]);
    expect(rows[3].lane, 1);
    // C's row no longer touches column 1: the convergence into C is drawn on the
    // row above, so column 1 is already free by C's own row.
    expect([for (final row in rows) row.maxLane], [0, 1, 0, 1, 0]);
    _expectStableColumns(rows);
  });

  test('a column busy across a merge span is forbidden to the parent', () {
    // M waits for P from row 0. P's branch child D sits in column 0, but column
    // 0 carried main's line until row 3 — inside the span P's merge edge has to
    // drop through — so P is pushed to a fresh column and D converges into it.
    final rows = layoutGraph([
      _commit('M', ['A', 'P']),
      _commit('S', ['Q']),
      _commit('A', ['Q']),
      _commit('Q', const []),
      _commit('D', ['P']),
      _commit('P', const []),
    ]);

    expect(rows[4].lane, 0);
    expect(rows[5].lane, 2);
    expect(rows[0].transitions, [(from: 0, to: 2, sha: 'P')]);
    expect(rows[4].transitions, [(from: 0, to: 2, sha: 'P')]);
    // The merge edge occupies its column on every row it crosses.
    expect(rows[2].activeLaneShas[2], 'P');
    expect(rows[3].nextLaneShas[2], 'P');
    _expectStableColumns(rows);
  });

  test('a merge parent will not take a column that holds a node above it', () {
    // M waits for P from row 0, and P's branch child D holds column 1 from row 1
    // — below the start of that span. Dropping P's merge edge down column 1
    // would run it straight through D's node, so P opens a column of its own.
    final rows = layoutGraph([
      _commit('M', ['A', 'P']),
      _commit('D', ['P']),
      _commit('A', const []),
      _commit('P', const []),
    ]);

    expect(rows[1].lane, 1);
    expect(rows[3].lane, 2);
    expect(rows[2].transitions, [(from: 1, to: 2, sha: 'P')]);
    _expectStableColumns(rows);
  });

  test('two columns may await one commit and converge above its row', () {
    final rows = layoutGraph([
      _commit('C', ['A', 'B']),
      _commit('A', ['R']),
      _commit('B', ['R']),
      _commit('R', const []),
    ]);

    // Both A's and B's lines wait for R; nothing dedupes them before R's row.
    expect(rows[2].nextLaneShas, {0: 'R', 1: 'R'});
    // B waits for R in its own column 1, but R lands in column 0, so B's first
    // parent entry is 0 — the tail is B's own line converging, not a merge edge.
    expect(rows[2].parentLanes, [0]);
    // The convergence sits on the row above R, which is where the painter
    // starts the sweep that lands on R.
    expect(rows[3].lane, 0);
    expect(rows[2].transitions, [(from: 1, to: 0, sha: 'R')]);
    expect(rows[3].transitions, isEmpty);
    _expectStableColumns(rows);
  });

  test('a converging first parent reports the column it lands in', () {
    // The shape of fixture2's 8122009: a branch tip whose first parent joins the
    // line to its left. Reporting its own lane here made the painter read the
    // tail as a merge edge and color it after the destination line.
    final rows = layoutGraph([
      _commit('main', ['base']),
      _commit('alpha', ['base']),
      _commit('base', const []),
    ]);

    expect(rows[1].lane, 1);
    expect(rows[2].lane, 0);
    expect(rows[1].parentLanes, [0]);
    expect(rows[1].transitions, [(from: 1, to: 0, sha: 'base')]);
    // The first parent of the row that keeps its column still reads as its own.
    expect(rows[0].parentLanes, [0]);
    _expectStableColumns(rows);
  });

  test('a first-parent chain shares one branch line id', () {
    final rows = layoutGraph([
      _commit('M', ['A', 'S']),
      _commit('A', ['R']),
      _commit('S', ['R']),
      _commit('R', const []),
    ]);

    // Main is born at row 0 and still line 0 at the root, across the merge; the
    // side branch is its own line.
    expect([for (final row in rows) row.branch], [0, 0, 1, 0]);
    expect(rows[1].nextLaneBranches, {0: 0, 1: 1});
    _expectStableColumns(rows);
  });

  test('a reused column carries a new branch line id', () {
    final rows = layoutGraph([
      _commit('A', ['C']),
      _commit('B', ['C']),
      _commit('C', ['D']),
      _commit('E', ['D']),
      _commit('D', const []),
    ]);

    // B's line 1 ends at C. E reuses B's column but is a different branch, so it
    // is line 2 — column index alone would have colored them the same.
    expect([for (final row in rows) row.branch], [0, 1, 0, 2, 0]);
    expect(rows[1].activeLaneBranches, {0: 0, 1: 1});
    expect(rows[3].activeLaneBranches, {0: 0, 1: 2});
    expect(rows[3].nextLaneBranches, {0: 0, 1: 2});
    _expectStableColumns(rows);
  });

  test('branch line ids do not renumber when a page is appended', () {
    final commits = [
      _commit('M', ['A', 'P']),
      _commit('S', ['Q']),
      _commit('A', ['Q']),
      _commit('Q', const []),
      _commit('D', ['P']),
      _commit('P', const []),
    ];

    final page = layoutGraph(commits.take(4).toList());
    final full = layoutGraph(commits);

    expect([for (final row in page) row.branch], [0, 1, 0, 0]);
    expect(
      [for (final row in page) row.branch],
      [for (final row in full.take(page.length)) row.branch],
    );
    expect([for (final row in full) row.branch], [0, 1, 0, 0, 2, 3]);

    final preferredPage = layoutGraph(
      commits.take(4).toList(),
      preferredTip: 'P',
    );
    final preferredFull = layoutGraph(commits, preferredTip: 'P');
    final preferredPrefix = preferredFull.take(preferredPage.length);
    expect(
      [for (final row in preferredPage) row.lane],
      [for (final row in preferredPrefix) row.lane],
    );
    expect(
      [for (final row in preferredPage) row.branch],
      [for (final row in preferredPrefix) row.branch],
    );
    expect(
      [for (final row in preferredPage) row.transitions],
      [for (final row in preferredPrefix) row.transitions],
    );
  });

  test('lays out a real repository by the straight-branch rules', () async {
    final root = await Directory.systemTemp.createTemp('yogit_graph_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    Future<void> tick(String name) async {
      await File('${root.path}/$name.txt').writeAsString(name);
      await _git(root, ['add', '-A']);
      await _git(root, ['commit', '-m', name]);
    }

    await tick('base');
    await _git(root, ['switch', '-c', 'one']);
    await tick('one1');
    await _git(root, ['switch', 'main']);
    await tick('main1');
    await _git(root, ['merge', '--no-ff', 'one', '-m', 'merge one']);
    await tick('main2');
    // A second branch, cut only after the first one has merged away.
    await _git(root, ['switch', '-c', 'two']);
    await tick('two1');
    await _git(root, ['switch', 'main']);
    await tick('main3');
    await _git(root, ['merge', '--no-ff', 'two', '-m', 'merge two']);

    final rows = layoutGraph(await GitRepository(root.path).loadHistory());

    // Hand-computed from the pvigier rules over the topo order below:
    //   0 merge two  new column 0 (nothing above), waits for main3
    //   1 main3      branch child of main2 in column 0 -> stays in 0
    //   2 two1       merge child of row 0; columns 0 busy -> opens column 1
    //   3 main2      branch children in 0 and 1 -> leftmost 0, column 1 frees
    //   4 merge one  branch child in column 0 -> 0
    //   5 main1      branch child in column 0 -> 0
    //   6 one1       merge child of row 4; column 1 free since row 2 -> reuse 1
    //   7 base       branch children in 0 and 1 -> leftmost 0
    expect(
      {for (final row in rows) row.commit.subject: row.lane},
      {
        'merge two': 0,
        'main3': 0,
        'two1': 1,
        'main2': 0,
        'merge one': 0,
        'main1': 0,
        'one1': 1,
        'base': 0,
      },
    );
    // Never a third column: column 1 is freed and reused, not abandoned.
    expect([for (final row in rows) row.maxLane], everyElement(lessThan(2)));
    // Main is one line the whole way; `two` and `one` share column 1 but are
    // separate lines, so they never share a color.
    expect([for (final row in rows) row.branch], [0, 0, 1, 0, 0, 0, 2, 0]);
    expect(rows[5].nextLaneBranches, {0: 0, 1: 2});
    _expectStableColumns(rows);
  });

  test(
    'compares branch tips with unique commits, common boundary, and diff direction',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yogit_branch_compare_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/shared.txt').writeAsString('base\n');
      await _git(root, ['add', 'shared.txt']);
      await _git(root, ['commit', '-m', 'base']);
      final baseSha = (await _git(root, ['rev-parse', 'HEAD'])).trim();

      await _git(root, ['switch', '-c', 'feature']);
      await File('${root.path}/shared.txt').writeAsString('feature\n');
      await _git(root, ['commit', '-am', 'feature one']);
      await File('${root.path}/feature.txt').writeAsString('feature only\n');
      await _git(root, ['add', 'feature.txt']);
      await _git(root, ['commit', '-m', 'feature two']);

      await _git(root, ['switch', 'main']);
      await File('${root.path}/shared.txt').writeAsString('main\n');
      await _git(root, ['commit', '-am', 'main one']);

      final repository = GitRepository(root.path);
      final result = await repository.compareBranches('main', 'feature');

      expect(result.sameFirstParent, isFalse);
      expect(result.mergeBases, [baseSha]);
      expect(
        result.commits.map((entry) => entry.side),
        containsAll([
          BranchCommitSide.baseOnly,
          BranchCommitSide.compareOnly,
          BranchCommitSide.commonBoundary,
        ]),
      );
      expect(result.files.map((file) => file.path), contains('shared.txt'));
      expect(result.merge.status, MergeConflictStatus.conflicts);
      expect(result.merge.files, contains('shared.txt'));
      expect(
        layoutBranchComparison(result.commits).map((row) => row.maxLane),
        everyElement(lessThanOrEqualTo(1)),
      );

      final shared = result.files.singleWhere(
        (file) => file.path == 'shared.txt',
      );
      final lines = await repository.loadDiffBetween(
        result.baseTip,
        result.compareTip,
        shared,
      );
      expect(
        lines.where((line) => line.kind == DiffLineKind.delete).single.text,
        'main',
      );
      expect(
        lines.where((line) => line.kind == DiffLineKind.add).single.text,
        'feature',
      );
    },
  );

  test('branch comparison recognizes sibling tips with one parent', () async {
    final root = await Directory.systemTemp.createTemp('yogit_siblings_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/base.txt').writeAsString('base\n');
    await _git(root, ['add', 'base.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['branch', 'sibling']);

    await File('${root.path}/main.txt').writeAsString('main\n');
    await _git(root, ['add', 'main.txt']);
    await _git(root, ['commit', '-m', 'main']);
    await _git(root, ['switch', 'sibling']);
    await File('${root.path}/sibling.txt').writeAsString('sibling\n');
    await _git(root, ['add', 'sibling.txt']);
    await _git(root, ['commit', '-m', 'sibling']);

    final result = await GitRepository(
      root.path,
    ).compareBranches('main', 'sibling');

    expect(result.sameFirstParent, isTrue);
  });

  test('branch comparison returns a clean virtual merge tree', () async {
    final root = await Directory.systemTemp.createTemp('yogit_merge_preview_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/base.txt').writeAsString('base\n');
    await _git(root, ['add', 'base.txt']);
    await _git(root, ['commit', '-m', 'base']);

    await _git(root, ['switch', '-c', 'feature']);
    await File('${root.path}/feature.txt').writeAsString('feature\n');
    await _git(root, ['add', 'feature.txt']);
    await _git(root, ['commit', '-m', 'feature']);

    await _git(root, ['switch', 'main']);
    await File('${root.path}/main.txt').writeAsString('main\n');
    await _git(root, ['add', 'main.txt']);
    await _git(root, ['commit', '-m', 'main']);
    final originalMain = (await _git(root, ['rev-parse', 'main'])).trim();
    final originalFeature = (await _git(root, ['rev-parse', 'feature'])).trim();

    final result = await GitRepository(
      root.path,
    ).compareBranches('main', 'feature');

    expect(result.merge.status, MergeConflictStatus.clean);
    expect(result.merge.treeSha, isNotEmpty);
    expect(
      result.merge.resultFiles.map((file) => file.path),
      contains('feature.txt'),
    );
    expect((await _git(root, ['rev-parse', 'main'])).trim(), originalMain);
    expect(
      (await _git(root, ['rev-parse', 'feature'])).trim(),
      originalFeature,
    );
    expect((await _git(root, ['status', '--porcelain'])).trim(), isEmpty);
  });

  test(
    'does not activate a base lane when only the compare branch is unique',
    () {
      final rows = layoutBranchComparison([
        BranchComparisonCommit(
          commit: _commit('feature-tip', ['shared']),
          side: BranchCommitSide.compareOnly,
        ),
        BranchComparisonCommit(
          commit: _commit('shared', const []),
          side: BranchCommitSide.commonBoundary,
        ),
      ]);

      expect(rows.first.activeLanes, [1]);
      expect(rows.first.activeLaneBranches, {1: 1});
      expect(rows.first.nextLanes, [0]);
      expect(rows.first.transitions, [(from: 1, to: 0, sha: 'shared')]);
    },
  );

  test(
    'does not draw a compare transition when only the base branch is unique',
    () {
      final rows = layoutBranchComparison([
        BranchComparisonCommit(
          commit: _commit('main-tip', ['shared']),
          side: BranchCommitSide.baseOnly,
        ),
        BranchComparisonCommit(
          commit: _commit('shared', const []),
          side: BranchCommitSide.commonBoundary,
        ),
      ]);

      expect(rows.first.activeLanes, [0]);
      expect(rows.first.nextLanes, [0]);
      expect(rows.first.transitions, isEmpty);
    },
  );

  test(
    'merge preview resolves conflicts without moving either branch',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yogit_merge_preview_fixture_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/shared.txt').writeAsString('base\n');
      await _git(root, ['add', 'shared.txt']);
      await _git(root, ['commit', '-m', 'base']);

      await _git(root, ['switch', '-c', 'feature']);
      await File('${root.path}/shared.txt').writeAsString('feature\n');
      await _git(root, ['commit', '-am', 'feature']);
      final featureBefore = (await _git(root, ['rev-parse', 'feature'])).trim();

      await _git(root, ['switch', 'main']);
      await File('${root.path}/shared.txt').writeAsString('main\n');
      await _git(root, ['commit', '-am', 'main']);
      final mainBefore = (await _git(root, ['rev-parse', 'main'])).trim();

      final session = await GitRepository(
        root.path,
      ).openMergePreview(baseRef: 'main', compareRef: 'feature');
      addTearDown(session.dispose);
      final conflict = await session.start();

      expect(conflict.status, MergePreviewStatus.conflict);
      expect(conflict.conflictFiles, ['shared.txt']);
      expect(Directory(session.worktreePath!).existsSync(), isTrue);
      final conflictDiff = await session.loadConflictDiff('shared.txt');
      expect(
        conflictDiff
            .where((line) => line.kind == DiffLineKind.delete)
            .map((line) => line.text),
        contains('main'),
      );
      expect(
        conflictDiff
            .where((line) => line.kind == DiffLineKind.add)
            .map((line) => line.text),
        contains('feature'),
      );

      await session.resolveFile('shared.txt', MergeConflictChoice.compare);
      final resolvedDiff = await session.loadConflictDiff('shared.txt');
      expect(
        resolvedDiff
            .where((line) => line.kind == DiffLineKind.add)
            .map((line) => line.text),
        contains('feature'),
      );
      final completed = await session.finish();

      expect(completed.status, MergePreviewStatus.clean);
      expect(completed.treeSha, isNotEmpty);
      expect(
        (await _git(root, ['show', '${completed.treeSha}:shared.txt'])).trim(),
        'feature',
      );
      expect((await _git(root, ['rev-parse', 'main'])).trim(), mainBefore);
      expect(
        (await _git(root, ['rev-parse', 'feature'])).trim(),
        featureBefore,
      );
    },
  );

  test(
    'rebase simulation reports first conflicting commit and cleans worktree',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yogit_rebasefixture_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/shared.txt').writeAsString('base\n');
      await _git(root, ['add', 'shared.txt']);
      await _git(root, ['commit', '-m', 'base']);

      await _git(root, ['switch', '-c', 'feature']);
      await File('${root.path}/feature.txt').writeAsString('one\n');
      await _git(root, ['add', 'feature.txt']);
      await _git(root, ['commit', '-m', 'feature one']);
      await File('${root.path}/shared.txt').writeAsString('feature\n');
      await _git(root, ['commit', '-am', 'feature two']);
      final conflictingSha = (await _git(root, ['rev-parse', 'HEAD'])).trim();

      await _git(root, ['switch', 'main']);
      await File('${root.path}/shared.txt').writeAsString('main\n');
      await _git(root, ['commit', '-am', 'main']);
      final originalHead = (await _git(root, ['rev-parse', 'HEAD'])).trim();

      final repository = GitRepository(root.path);
      final result = await repository.simulateRebase(
        baseRef: 'main',
        compareRef: 'feature',
      );

      expect(result.status, RebaseCheckStatus.conflicts);
      expect(result.stoppedCommit, conflictingSha);
      expect(result.files, ['shared.txt']);
      expect((await _git(root, ['rev-parse', 'HEAD'])).trim(), originalHead);
      expect((await _git(root, ['branch', '--show-current'])).trim(), 'main');
      expect((await _git(root, ['status', '--porcelain'])).trim(), isEmpty);
      // 미리보기가 쓰던 worktree는 이 저장소의 장부에서 사라져야 한다. 임시
      // 디렉터리 전체를 세지 않는 이유는 그 이름 공간을 이 기계의 다른 yogit도
      // 함께 쓰기 때문이다 — 앱이 떠 있으면 재는 사이에 하나가 생겼다 사라져서
      // 이 시험이 제 잘못 없이 빨개진다.
      expect(
        (await _git(root, [
          'worktree',
          'list',
          '--porcelain',
        ])).split('\n').where((line) => line.startsWith('worktree ')).length,
        1,
        reason: '저장소 자신 말고는 남지 않는다',
      );
    },
  );

  test(
    'rebase simulation reports a clean replay without moving HEAD',
    () async {
      final root = await Directory.systemTemp.createTemp('yogit_cleanrebase_');
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/base.txt').writeAsString('base\n');
      await _git(root, ['add', 'base.txt']);
      await _git(root, ['commit', '-m', 'base']);
      await _git(root, ['switch', '-c', 'feature']);
      await File('${root.path}/feature.txt').writeAsString('feature\n');
      await _git(root, ['add', 'feature.txt']);
      await _git(root, ['commit', '-m', 'feature']);
      await _git(root, ['switch', 'main']);
      await File('${root.path}/main.txt').writeAsString('main\n');
      await _git(root, ['add', 'main.txt']);
      await _git(root, ['commit', '-m', 'main']);
      final originalHead = (await _git(root, ['rev-parse', 'HEAD'])).trim();

      final result = await GitRepository(
        root.path,
      ).simulateRebase(baseRef: 'main', compareRef: 'feature');

      expect(result.status, RebaseCheckStatus.clean);
      expect((await _git(root, ['rev-parse', 'HEAD'])).trim(), originalHead);
      expect((await _git(root, ['status', '--porcelain'])).trim(), isEmpty);
    },
  );

  test('rebase preview reports rewritten commits and a virtual tip', () async {
    final root = await Directory.systemTemp.createTemp(
      'yogit_rebase_preview_fixture_',
    );
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/base.txt').writeAsString('base\n');
    await _git(root, ['add', 'base.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'feature']);
    await File('${root.path}/one.txt').writeAsString('one\n');
    await _git(root, ['add', 'one.txt']);
    await _git(root, ['commit', '-m', 'feature one']);
    await File('${root.path}/two.txt').writeAsString('two\n');
    await _git(root, ['add', 'two.txt']);
    await _git(root, ['commit', '-m', 'feature two']);
    final originalFeature = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    await _git(root, ['switch', 'main']);
    await File('${root.path}/main.txt').writeAsString('main\n');
    await _git(root, ['add', 'main.txt']);
    await _git(root, ['commit', '-m', 'main']);
    final originalMain = (await _git(root, ['rev-parse', 'HEAD'])).trim();

    final session = await GitRepository(
      root.path,
    ).openRebasePreview(baseRef: 'main', compareRef: 'feature');
    addTearDown(session.dispose);
    final result = await session.start();

    expect(result.status, RebasePreviewStatus.clean);
    expect(result.rewritten, hasLength(2));
    expect(result.rewritten.map((entry) => entry.original.subject), [
      'feature one',
      'feature two',
    ]);
    expect(
      result.rewritten.every(
        (entry) => entry.original.sha != entry.rewrittenSha,
      ),
      isTrue,
    );
    expect(result.virtualTip, result.rewritten.last.rewrittenSha);
    expect(
      (await GitRepository(root.path).loadFilesBetween(
        originalMain,
        result.virtualTip!,
      )).map((file) => file.path),
      containsAll(['one.txt', 'two.txt']),
    );
    expect((await _git(root, ['rev-parse', 'main'])).trim(), originalMain);
    expect(
      (await _git(root, ['rev-parse', 'feature'])).trim(),
      originalFeature,
    );
  });

  test(
    'rebase preview does not pair a dropped commit with another rewrite',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yogit_rebase_preview_dropped_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/base.txt').writeAsString('base\n');
      await _git(root, ['add', 'base.txt']);
      await _git(root, ['commit', '-m', 'base']);
      await _git(root, ['switch', '-c', 'feature']);
      await File('${root.path}/shared.txt').writeAsString('shared\n');
      await _git(root, ['add', 'shared.txt']);
      await _git(root, ['commit', '-m', 'already upstream']);
      final sharedCommit = (await _git(root, ['rev-parse', 'HEAD'])).trim();
      await File('${root.path}/feature.txt').writeAsString('feature\n');
      await _git(root, ['add', 'feature.txt']);
      await _git(root, ['commit', '-m', 'feature only']);
      await _git(root, ['switch', 'main']);
      await File('${root.path}/main.txt').writeAsString('main\n');
      await _git(root, ['add', 'main.txt']);
      await _git(root, ['commit', '-m', 'main first']);
      await _git(root, ['cherry-pick', sharedCommit]);

      final session = await GitRepository(
        root.path,
      ).openRebasePreview(baseRef: 'main', compareRef: 'feature');
      addTearDown(session.dispose);
      final result = await session.start();

      expect(result.status, RebasePreviewStatus.clean);
      expect(result.rewritten.map((entry) => entry.original.subject), [
        'feature only',
      ]);
    },
  );

  test(
    'rebase preview continues after resolving its current conflict',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yogit_rebase_preview_conflict_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/shared.txt').writeAsString('base\n');
      await _git(root, ['add', 'shared.txt']);
      await _git(root, ['commit', '-m', 'base']);
      await _git(root, ['switch', '-c', 'feature']);
      await File('${root.path}/one.txt').writeAsString('one\n');
      await _git(root, ['add', 'one.txt']);
      await _git(root, ['commit', '-m', 'feature one']);
      await File('${root.path}/shared.txt').writeAsString('feature\n');
      await _git(root, ['commit', '-am', 'feature conflict']);
      final conflictingSha = (await _git(root, ['rev-parse', 'HEAD'])).trim();
      await _git(root, ['switch', 'main']);
      await File('${root.path}/shared.txt').writeAsString('main\n');
      await _git(root, ['commit', '-am', 'main']);

      final session = await GitRepository(
        root.path,
      ).openRebasePreview(baseRef: 'main', compareRef: 'feature');
      final conflict = await session.start();

      expect(conflict.status, RebasePreviewStatus.conflict);
      expect(conflict.currentCommit?.sha, conflictingSha);
      expect(conflict.completed, 1);
      expect(conflict.total, 2);
      expect(conflict.conflictFiles, ['shared.txt']);
      final worktree = session.worktreePath!;
      expect(Directory(worktree).existsSync(), isTrue);
      final conflictDiff = await session.loadConflictDiff('shared.txt');
      expect(
        conflictDiff
            .where((line) => line.kind == DiffLineKind.delete)
            .map((line) => line.text),
        contains('main'),
      );
      expect(
        conflictDiff
            .where((line) => line.kind == DiffLineKind.add)
            .map((line) => line.text),
        contains('feature'),
      );

      await session.resolveFile('shared.txt', RebaseConflictChoice.commit);
      expect(
        await File(session.filePath('shared.txt')).readAsString(),
        'feature\n',
      );
      final completed = await session.continueAfterResolving();

      expect(completed.status, RebasePreviewStatus.clean);
      expect(completed.virtualTip, isNotEmpty);
      await session.dispose();
      expect(Directory(worktree).existsSync(), isFalse);
    },
  );

  test('first rebase conflict has no rewritten commits', () async {
    final root = await Directory.systemTemp.createTemp(
      'yogit_first_rebase_conflict_',
    );
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/shared.txt').writeAsString('base\n');
    await _git(root, ['add', 'shared.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'feature']);
    await File('${root.path}/shared.txt').writeAsString('feature\n');
    await _git(root, ['commit', '-am', 'feature conflict']);
    await _git(root, ['switch', 'main']);
    await File('${root.path}/shared.txt').writeAsString('main\n');
    await _git(root, ['commit', '-am', 'main']);

    final repository = GitRepository(root.path);
    final comparison = await repository.compareBranches('main', 'feature');
    final session = await repository.openRebasePreview(
      baseRef: 'main',
      compareRef: 'feature',
    );
    addTearDown(session.dispose);
    final conflict = await session.start();

    expect(conflict.status, RebasePreviewStatus.conflict);
    expect(conflict.rewritten, isEmpty);
    expect(
      layoutRebasePreviewGraph(comparison, conflict).kinds.values,
      contains(PreviewGraphNodeKind.conflictTarget),
    );
  });

  test(
    'a leftover conflict marker blocks the rebase resolution it names',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yogit_marker_rebase_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/shared.txt').writeAsString('base\n');
      await _git(root, ['add', 'shared.txt']);
      await _git(root, ['commit', '-m', 'base']);
      await _git(root, ['switch', '-c', 'feature']);
      await File('${root.path}/shared.txt').writeAsString('feature\n');
      await _git(root, ['commit', '-am', 'feature conflict']);
      await _git(root, ['switch', 'main']);
      await File('${root.path}/shared.txt').writeAsString('main\n');
      await _git(root, ['commit', '-am', 'main']);

      final session = await GitRepository(
        root.path,
      ).openRebasePreview(baseRef: 'main', compareRef: 'feature');
      addTearDown(session.dispose);
      expect((await session.start()).status, RebasePreviewStatus.conflict);

      // git이 써 넣은 마커가 그대로 남아 있다 — 파일과 첫 마커 행을 지목하며 거부한다.
      await expectLater(
        session.markResolved('shared.txt'),
        throwsA(
          isA<ConflictMarkerResidueException>().having(
            (error) => error.toString(),
            'message',
            '충돌 마커가 남아 있어 해결로 표시할 수 없습니다: shared.txt 1행',
          ),
        ),
      );
      // 거부는 스테이징 전에 일어나니 파일은 여전히 충돌 상태다.
      expect(
        (await _git(Directory(session.worktreePath!), const [
          'ls-files',
          '-u',
          '--',
          'shared.txt',
        ])).trim(),
        isNotEmpty,
      );

      // 마커를 걷어내면 같은 호출이 통과한다.
      await File(session.filePath('shared.txt')).writeAsString('둘 다\n');
      await session.markResolved('shared.txt');
      expect(
        (await _git(Directory(session.worktreePath!), const [
          'ls-files',
          '-u',
          '--',
          'shared.txt',
        ])).trim(),
        isEmpty,
      );
    },
  );

  test(
    'a merge resolution keeps marker-looking lines the stage blobs already had',
    () async {
      const example =
          '# 충돌 마커 예시\n'
          '<<<<<<< HEAD\n'
          '왼쪽\n'
          '=======\n'
          '오른쪽\n'
          '>>>>>>> topic\n';
      final root = await Directory.systemTemp.createTemp('yogit_marker_merge_');
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/docs.md').writeAsString('$example끝\n');
      await File('${root.path}/shared.txt').writeAsString('base\n');
      await _git(root, ['add', 'docs.md', 'shared.txt']);
      await _git(root, ['commit', '-m', 'base']);
      await _git(root, ['switch', '-c', 'feature']);
      await File('${root.path}/docs.md').writeAsString('${example}feature 끝\n');
      await File('${root.path}/shared.txt').writeAsString('feature\n');
      await _git(root, ['commit', '-am', 'feature']);
      await _git(root, ['switch', 'main']);
      await File('${root.path}/docs.md').writeAsString('${example}main 끝\n');
      await File('${root.path}/shared.txt').writeAsString('main\n');
      await _git(root, ['commit', '-am', 'main']);

      final session = await GitRepository(
        root.path,
      ).openMergePreview(baseRef: 'main', compareRef: 'feature');
      addTearDown(session.dispose);
      final conflict = await session.start();
      expect(conflict.status, MergePreviewStatus.conflict);
      expect(conflict.conflictFiles, ['docs.md', 'shared.txt']);

      // 원래부터 마커 모양 행이 있던 파일은 세 stage 블롭과 대조해 통과시킨다.
      await File(
        session.filePath('docs.md'),
      ).writeAsString('${example}main 끝\nfeature 끝\n');
      await session.markResolved('docs.md');

      // 같은 세션에서 마커가 남은 파일은 여전히 막힌다.
      await expectLater(
        session.markResolved('shared.txt'),
        throwsA(
          isA<ConflictMarkerResidueException>().having(
            (error) => error.toString(),
            'message',
            '충돌 마커가 남아 있어 해결로 표시할 수 없습니다: shared.txt 1행',
          ),
        ),
      );
    },
  );

  test(
    'the conflict forecast lands only on the commits that conflict',
    () async {
      final fixture = await _conflictForecastFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final repository = GitRepository(fixture.root.path);

      final forecast = await repository.probeRebaseConflicts(
        baseTip: fixture.baseTip,
        compareTip: fixture.compareTip,
        commits: fixture.commits,
      );

      expect(forecast.keys, unorderedEquals([fixture.first, fixture.second]));
      expect(forecast[fixture.first], ['shared.txt']);
      expect(forecast[fixture.second]!.toList()..sort(), [
        'second.txt',
        'shared.txt',
      ]);
      // 예고는 저장소를 건드리지 않고 자기 worktree도 남기지 않는다.
      expect(await _probeWorktrees(fixture.root), isEmpty);
      expect(
        (await _git(fixture.root, ['status', '--porcelain'])).trim(),
        isEmpty,
      );
    },
  );

  test('the forecast never warns about a commit rebase would drop', () async {
    // 옛 브랜치 tip 모양: feature의 첫 커밋이 이미 main에 들어갔고 main이 그 뒤로
    // 같은 파일을 또 고쳤다. 그 커밋만 단독으로 다시 얹으면 충돌하지만 — 변경이 이미
    // 적용돼 있으니 충돌한다 — 순차 재배치는 그 커밋을 아예 재생하지 않는다.
    final root = await Directory.systemTemp.createTemp('yogit_forecast_drop_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/file.txt').writeAsString('base\n');
    await File('${root.path}/other.txt').writeAsString('base\n');
    await _git(root, ['add', 'file.txt', 'other.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'feature']);
    await File('${root.path}/file.txt').writeAsString('feature\n');
    await _git(root, ['commit', '-am', 'feature edits file']);
    final duplicate = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    await File('${root.path}/other.txt').writeAsString('feature\n');
    await _git(root, ['commit', '-am', 'feature edits other']);
    final conflicting = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    await _git(root, ['switch', 'main']);
    // main이 먼저 움직여야 빼온 커밋이 원본과 다른 커밋이 된다.
    await File('${root.path}/main.txt').writeAsString('main\n');
    await _git(root, ['add', 'main.txt']);
    await _git(root, ['commit', '-m', 'main only']);
    await _git(root, ['cherry-pick', duplicate]);
    await File('${root.path}/file.txt').writeAsString('main again\n');
    await File('${root.path}/other.txt').writeAsString('main\n');
    await _git(root, ['commit', '-am', 'main moves both on']);
    final repository = GitRepository(root.path);
    final baseTip = (await _git(root, ['rev-parse', 'main'])).trim();

    // patch-id 중복이라는 사실과 단독 재생이 충돌한다는 사실이 둘 다 참이다.
    expect(
      await repository.duplicateCompareCommits(
        baseTip: baseTip,
        compareTip: conflicting,
      ),
      {duplicate},
    );

    final forecast = await repository.probeRebaseConflicts(
      baseTip: baseTip,
      compareTip: conflicting,
      commits: [duplicate, conflicting],
    );

    // 예고는 재배치가 실제로 재생할 커밋에만 붙는다.
    expect(forecast.keys, [conflicting]);
    expect(forecast[conflicting], ['other.txt']);
    expect(await _probeWorktrees(root), isEmpty);
  });

  test('a cancelled forecast stops early and leaves no worktree', () async {
    final fixture = await _conflictForecastFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    var replays = 0;

    final forecast = await GitRepository(fixture.root.path)
        .probeRebaseConflicts(
          baseTip: fixture.baseTip,
          compareTip: fixture.compareTip,
          commits: fixture.commits,
          cancelled: () => replays++ > 0,
        );

    expect(replays, 2);
    expect(forecast.length, lessThan(2));
    expect(await _probeWorktrees(fixture.root), isEmpty);
  });

  test('a branch past the forecast ceiling is never probed', () async {
    final commands = <List<String>>[];
    final repository = GitRepository(
      '/repo',
      runner: (executable, args, {workingDirectory, environment}) async {
        commands.add(args);
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(
      await repository.probeRebaseConflicts(
        baseTip: 'main-tip',
        compareTip: 'feature-tip',
        commits: [
          for (var at = 0; at <= conflictForecastCommitCeiling; at++) 'sha$at',
        ],
      ),
      isEmpty,
    );
    expect(commands, isEmpty);
  });

  test('patch-id duplicates come back as the compared commits', () async {
    final root = await Directory.systemTemp.createTemp('yogit_duplicates_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/base.txt').writeAsString('base\n');
    await _git(root, ['add', 'base.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'feature']);
    await File('${root.path}/picked.txt').writeAsString('picked\n');
    await _git(root, ['add', 'picked.txt']);
    await _git(root, ['commit', '-m', 'already in main']);
    final picked = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    await File('${root.path}/own.txt').writeAsString('own\n');
    await _git(root, ['add', 'own.txt']);
    await _git(root, ['commit', '-m', 'feature only']);
    await _git(root, ['switch', 'main']);
    // main이 먼저 움직여야 빼온 커밋이 원본과 다른 커밋이 된다 — 부모까지 같으면
    // git이 같은 객체를 그대로 만들어 낸다.
    await File('${root.path}/main.txt').writeAsString('main\n');
    await _git(root, ['add', 'main.txt']);
    await _git(root, ['commit', '-m', 'main only']);
    await _git(root, ['cherry-pick', picked]);

    expect(
      await GitRepository(root.path).duplicateCompareCommits(
        baseTip: (await _git(root, ['rev-parse', 'main'])).trim(),
        compareTip: (await _git(root, ['rev-parse', 'feature'])).trim(),
      ),
      {picked},
    );
  });

  test(
    'a two-sided addition offers both orders and stages the one picked',
    () async {
      final root = await Directory.systemTemp.createTemp('yogit_keep_both_');
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/list.txt').writeAsString('a\nb\nc\n');
      await _git(root, ['add', 'list.txt']);
      await _git(root, ['commit', '-m', 'base']);
      await _git(root, ['switch', '-c', 'feature']);
      await File(
        '${root.path}/list.txt',
      ).writeAsString('a\nFEATURE1\nFEATURE2\nb\nc\n');
      await _git(root, ['commit', '-am', 'feature adds']);
      await _git(root, ['switch', 'main']);
      await File('${root.path}/list.txt').writeAsString('a\nMAIN1\nb\nc\n');
      await _git(root, ['commit', '-am', 'main adds']);

      final session = await GitRepository(
        root.path,
      ).openMergePreview(baseRef: 'main', compareRef: 'feature');
      addTearDown(session.dispose);
      expect((await session.start()).status, MergePreviewStatus.conflict);

      final candidate = (await session.keepBothCandidate('list.txt'))!;

      expect(candidate.hunks, hasLength(1));
      expect(candidate.hunks.single.ours, ['MAIN1']);
      expect(candidate.hunks.single.theirs, ['FEATURE1', 'FEATURE2']);
      expect(candidate.baseFirst, 'a\nMAIN1\nFEATURE1\nFEATURE2\nb\nc\n');
      expect(candidate.branchFirst, 'a\nFEATURE1\nFEATURE2\nMAIN1\nb\nc\n');

      await session.applyKeepBoth('list.txt', candidate.branchFirst);

      expect(
        await File(session.filePath('list.txt')).readAsString(),
        candidate.branchFirst,
      );
      final worktree = Directory(session.worktreePath!);
      expect(
        (await _git(worktree, const [
          'ls-files',
          '-u',
          '--',
          'list.txt',
        ])).trim(),
        isEmpty,
      );
      expect(
        await _git(worktree, const ['show', ':list.txt']),
        candidate.branchFirst,
      );
    },
  );

  test('a modification conflict is offered no keep-both suggestion', () async {
    final root = await Directory.systemTemp.createTemp('yogit_keep_both_none_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/list.txt').writeAsString('a\nOLD\nc\n');
    await _git(root, ['add', 'list.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'feature']);
    await File('${root.path}/list.txt').writeAsString('a\nFEATURE\nc\n');
    await _git(root, ['commit', '-am', 'feature edits']);
    await _git(root, ['switch', 'main']);
    await File('${root.path}/list.txt').writeAsString('a\nMAIN\nc\n');
    await _git(root, ['commit', '-am', 'main edits']);

    final session = await GitRepository(
      root.path,
    ).openMergePreview(baseRef: 'main', compareRef: 'feature');
    addTearDown(session.dispose);
    expect((await session.start()).status, MergePreviewStatus.conflict);

    expect(await session.keepBothCandidate('list.txt'), isNull);
  });

  test(
    'every hunk of a qualifying file combines in the chosen order',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yogit_keep_both_many_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/list.txt').writeAsString('a\nb\nc\nd\ne\n');
      await _git(root, ['add', 'list.txt']);
      await _git(root, ['commit', '-m', 'base']);
      await _git(root, ['switch', '-c', 'feature']);
      await File(
        '${root.path}/list.txt',
      ).writeAsString('a\nFEATURE1\nb\nc\nd\nFEATURE2\ne\n');
      await _git(root, ['commit', '-am', 'feature adds twice']);
      await _git(root, ['switch', 'main']);
      await File(
        '${root.path}/list.txt',
      ).writeAsString('a\nMAIN1\nb\nc\nd\nMAIN2\ne\n');
      await _git(root, ['commit', '-am', 'main adds twice']);

      final session = await GitRepository(
        root.path,
      ).openMergePreview(baseRef: 'main', compareRef: 'feature');
      addTearDown(session.dispose);
      expect((await session.start()).status, MergePreviewStatus.conflict);

      final candidate = (await session.keepBothCandidate('list.txt'))!;

      expect(candidate.hunks, hasLength(2));
      expect(
        candidate.baseFirst,
        'a\nMAIN1\nFEATURE1\nb\nc\nd\nMAIN2\nFEATURE2\ne\n',
      );
      expect(
        candidate.branchFirst,
        'a\nFEATURE1\nMAIN1\nb\nc\nd\nFEATURE2\nMAIN2\ne\n',
      );
    },
  );

  test('a file that carries marker-shaped lines gets no suggestion', () async {
    // 빈 섹션 마커 예시 블록 — merge-file 출력에서 진짜 마커와 구분할 수 없다.
    const example =
        '<<<<<<< a\n'
        '||||||| b\n'
        '=======\n'
        '>>>>>>> c\n';
    final root = await Directory.systemTemp.createTemp(
      'yogit_keep_both_markers_',
    );
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/list.txt').writeAsString('${example}a\nb\n');
    await _git(root, ['add', 'list.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'feature']);
    await File(
      '${root.path}/list.txt',
    ).writeAsString('${example}a\nFEATURE\nb\n');
    await _git(root, ['commit', '-am', 'feature adds']);
    await _git(root, ['switch', 'main']);
    await File('${root.path}/list.txt').writeAsString('${example}a\nMAIN\nb\n');
    await _git(root, ['commit', '-am', 'main adds']);

    final session = await GitRepository(
      root.path,
    ).openMergePreview(baseRef: 'main', compareRef: 'feature');
    addTearDown(session.dispose);
    expect((await session.start()).status, MergePreviewStatus.conflict);

    // 양쪽 추가 충돌이지만 버튼은 뜨지 않는다 — 예시 블록을 삼킨 제안보다 없는 게 낫다.
    expect(await session.keepBothCandidate('list.txt'), isNull);
  });

  test('a file whose bytes are not UTF-8 gets no suggestion', () async {
    // CP949로 쓰인 '한' — UTF-8로 왕복되지 않는 바이트다.
    const cp949 = [0xC7, 0xD1, 0x0A];
    final root = await Directory.systemTemp.createTemp(
      'yogit_keep_both_cp949_',
    );
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    final file = File('${root.path}/list.txt');
    await file.writeAsBytes(utf8.encode('a\nb\n'));
    await _git(root, ['add', 'list.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'feature']);
    await file.writeAsBytes([
      ...utf8.encode('a\n'),
      ...cp949,
      ...utf8.encode('b\n'),
    ]);
    await _git(root, ['commit', '-am', 'feature adds']);
    await _git(root, ['switch', 'main']);
    await file.writeAsBytes(utf8.encode('a\nMAIN\nb\n'));
    await _git(root, ['commit', '-am', 'main adds']);

    final session = await GitRepository(
      root.path,
    ).openMergePreview(baseRef: 'main', compareRef: 'feature');
    addTearDown(session.dispose);
    expect((await session.start()).status, MergePreviewStatus.conflict);

    // 바이트를 그대로 보존할 수 없으니 결합을 제안하지 않는다.
    expect(await session.keepBothCandidate('list.txt'), isNull);
  });

  test('a diff3 base-label marker blocks the resolution too', () async {
    final root = await Directory.systemTemp.createTemp('yogit_marker_diff3_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    // 미리보기 worktree는 저장소 설정을 그대로 물려받는다 — git이 ||||||| 행을 쓴다.
    await _git(root, ['config', 'merge.conflictstyle', 'diff3']);
    await File('${root.path}/shared.txt').writeAsString('base\n');
    await _git(root, ['add', 'shared.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'feature']);
    await File('${root.path}/shared.txt').writeAsString('feature\n');
    await _git(root, ['commit', '-am', 'feature']);
    await _git(root, ['switch', 'main']);
    await File('${root.path}/shared.txt').writeAsString('main\n');
    await _git(root, ['commit', '-am', 'main']);

    final session = await GitRepository(
      root.path,
    ).openMergePreview(baseRef: 'main', compareRef: 'feature');
    addTearDown(session.dispose);
    expect((await session.start()).status, MergePreviewStatus.conflict);

    final conflicted = File(session.filePath('shared.txt'));
    final lines = const LineSplitter().convert(await conflicted.readAsString());
    expect(lines.where((line) => line.startsWith('|||||||')), hasLength(1));

    // 세 마커만 걷어내고 ||||||| 행을 남긴다 — git이 쓴 마커가 아직 남아 있다.
    final kept = lines
        .where(
          (line) =>
              !line.startsWith('<<<<<<<') &&
              !line.startsWith('=======') &&
              !line.startsWith('>>>>>>>'),
        )
        .toList();
    await conflicted.writeAsString('${kept.join('\n')}\n');
    final residue = kept.indexWhere((line) => line.startsWith('|||||||')) + 1;

    await expectLater(
      session.markResolved('shared.txt'),
      throwsA(
        isA<ConflictMarkerResidueException>().having(
          (error) => error.toString(),
          'message',
          '충돌 마커가 남아 있어 해결로 표시할 수 없습니다: shared.txt $residue행',
        ),
      ),
    );
    expect(
      (await _git(Directory(session.worktreePath!), const [
        'ls-files',
        '-u',
        '--',
        'shared.txt',
      ])).trim(),
      isNotEmpty,
    );
  });

  test('a stale forecast probe worktree is cleaned once it ages out', () async {
    final root = await Directory.systemTemp.createTemp('yogit_probe_stale_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/base.txt').writeAsString('base\n');
    await _git(root, ['add', 'base.txt']);
    await _git(root, ['commit', '-m', 'base']);
    // 강제 종료가 남긴 프로브 worktree를 그대로 만들어 둔다.
    final probe = await Directory.systemTemp.createTemp(
      'yogit_conflict_probe_',
    );
    await probe.delete();
    await _git(root, ['worktree', 'add', '--detach', probe.path, 'HEAD']);
    addTearDown(() async {
      if (probe.existsSync()) await probe.delete(recursive: true);
    });
    final repository = GitRepository(root.path);

    // 방금 만든 프로브는 지금 돌고 있을 수 있으니 그대로 둔다.
    await repository.cleanupStalePreviewWorktrees();
    expect(await _probeWorktrees(root), hasLength(1));

    expect(
      (await Process.run('touch', ['-t', '202001010000', probe.path])).exitCode,
      0,
    );
    await repository.cleanupStalePreviewWorktrees();

    expect(await _probeWorktrees(root), isEmpty);
    expect(probe.existsSync(), isFalse);
  });

  test(
    'a preview directory git never registered is swept once it ages',
    () async {
      final root = await Directory.systemTemp.createTemp('yogit_orphan_sweep_');
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/base.txt').writeAsString('base\n');
      await _git(root, ['add', 'base.txt']);
      await _git(root, ['commit', '-m', 'base']);

      // 앱이 미리보기 도중 죽으면 장부에 없는 빈 디렉터리만 남는다. 장부를 훑는
      // 청소는 이런 것을 영영 못 본다.
      final orphan = await Directory.systemTemp.createTemp(
        'yogit_rebase_preview_',
      );
      final fresh = await Directory.systemTemp.createTemp(
        'yogit_merge_preview_',
      );
      final stranger = await Directory.systemTemp.createTemp(
        'yogit_unrelated_',
      );
      addTearDown(() async {
        for (final directory in [orphan, fresh, stranger]) {
          if (directory.existsSync()) await directory.delete(recursive: true);
        }
      });
      expect(
        (await Process.run('touch', [
          '-t',
          '202001010000',
          orphan.path,
        ])).exitCode,
        0,
      );

      await GitRepository(root.path).cleanupStalePreviewWorktrees();

      expect(orphan.existsSync(), isFalse, reason: '오래된 고아는 쓸어낸다');
      expect(
        fresh.existsSync(),
        isTrue,
        reason: '방금 생긴 것은 지금 돌고 있는 미리보기일 수 있다',
      );
      expect(stranger.existsSync(), isTrue, reason: '우리 이름이 아닌 것은 남긴다');
    },
  );

  test('merge preview applies locally and restores both exact tips', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);

    final applied = await repository.applyMergePreview(
      comparison: fixture.comparison,
      treeSha: fixture.comparison.merge.treeSha!,
    );

    expect(applied.mode, BranchApplyMode.merge);
    // main is the checked-out branch, so the result lands on disk as well.
    expect(applied.workingTreeUpdated, isTrue);
    expect(applied.baseBefore, fixture.comparison.baseTip);
    expect(applied.baseAfter, isNot(fixture.comparison.baseTip));
    expect(
      (await _git(fixture.root, [
        'rev-list',
        '--parents',
        '-n',
        '1',
        'main',
      ])).trim().split(' '),
      [
        applied.baseAfter,
        fixture.comparison.baseTip,
        fixture.comparison.compareTip,
      ],
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
      fixture.comparison.compareTip,
    );

    await repository.restoreBranchApply(applied);

    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
      fixture.comparison.compareTip,
    );
  });

  test('merge apply writes the message it was handed, body and all', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    const message =
        "Merge branch 'feature' into main\n"
        '\n'
        'Reviewed-by: 채수원';

    final applied = await repository.applyMergePreview(
      comparison: fixture.comparison,
      treeSha: fixture.comparison.merge.treeSha!,
      message: message,
    );

    expect(
      (await _git(fixture.root, ['log', '-1', '--format=%B', 'main'])).trim(),
      message,
    );

    // 메시지를 주지 않으면 git이 쓰던 문구 그대로다.
    await repository.restoreBranchApply(applied);
    await repository.applyMergePreview(
      comparison: fixture.comparison,
      treeSha: fixture.comparison.merge.treeSha!,
    );

    expect(
      (await _git(fixture.root, ['log', '-1', '--format=%B', 'main'])).trim(),
      "Merge branch 'feature' into main",
    );
  });

  test('merge apply moves a base branch that is checked out nowhere', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    await _git(fixture.root, ['switch', 'feature']);
    final head = (await _git(fixture.root, ['rev-parse', 'HEAD'])).trim();
    final commands = <List<String>>[];
    final repository = GitRepository(
      fixture.root.path,
      runner: (executable, arguments, {workingDirectory, environment}) async {
        commands.add(List<String>.of(arguments));
        return runProcess(
          executable,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
        );
      },
    );

    final applied = await repository.applyMergePreview(
      comparison: fixture.comparison,
      treeSha: fixture.comparison.merge.treeSha!,
    );

    expect(applied.workingTreeUpdated, isFalse);
    // The user's working directory is never yanked: nothing checks main out.
    expect(
      commands.map((command) => command.first),
      isNot(contains('checkout')),
    );
    expect(commands.map((command) => command.first), isNot(contains('reset')));
    expect(
      (await _git(fixture.root, ['branch', '--show-current'])).trim(),
      'feature',
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      applied.baseAfter,
    );
    expect((await _git(fixture.root, ['rev-parse', 'HEAD'])).trim(), head);
    // The merge result stays off disk until main is checked out.
    expect(File('${fixture.root.path}/main.txt').existsSync(), isFalse);
    expect(
      (await _git(fixture.root, ['status', '--porcelain'])).trim(),
      isEmpty,
    );

    await repository.restoreBranchApply(applied);

    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
    expect(
      (await _git(fixture.root, ['branch', '--show-current'])).trim(),
      'feature',
    );
    expect((await _git(fixture.root, ['rev-parse', 'HEAD'])).trim(), head);
    expect(File('${fixture.root.path}/main.txt').existsSync(), isFalse);
    expect(
      (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
      fixture.comparison.compareTip,
    );
  });

  test('a dirty tree does not block moving another branch', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    await _git(fixture.root, ['switch', 'feature']);
    await File('${fixture.root.path}/feature.txt').writeAsString('dirty\n');
    final head = (await _git(fixture.root, ['rev-parse', 'HEAD'])).trim();
    final repository = GitRepository(fixture.root.path);

    final applied = await repository.applyMergePreview(
      comparison: fixture.comparison,
      treeSha: fixture.comparison.merge.treeSha!,
    );

    expect(applied.workingTreeUpdated, isFalse);
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      applied.baseAfter,
    );
    expect(
      (await _git(fixture.root, ['branch', '--show-current'])).trim(),
      'feature',
    );
    expect((await _git(fixture.root, ['rev-parse', 'HEAD'])).trim(), head);
    expect(
      await File('${fixture.root.path}/feature.txt').readAsString(),
      'dirty\n',
    );
  });

  test('merge apply refuses a dirty tree on the base branch itself', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    // main is the checked-out branch here, so applying resets the disk.
    await File('${fixture.root.path}/main.txt').writeAsString('dirty\n');
    final repository = GitRepository(fixture.root.path);

    await expectLater(
      repository.applyMergePreview(
        comparison: fixture.comparison,
        treeSha: fixture.comparison.merge.treeSha!,
      ),
      throwsA(
        isA<GitRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('작업 트리와 인덱스가 깨끗해야'),
        ),
      ),
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
    expect(
      await File('${fixture.root.path}/main.txt').readAsString(),
      'dirty\n',
    );
  });

  test('merge apply rejects a base branch held by another worktree', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    await _git(fixture.root, ['switch', 'feature']);
    final temporary = await Directory.systemTemp.createTemp(
      'yogit_merge_apply_worktree_',
    );
    final worktreePath = temporary.path;
    await temporary.delete();
    await _git(fixture.root, ['worktree', 'add', worktreePath, 'main']);
    addTearDown(() async {
      await Process.run('git', [
        'worktree',
        'remove',
        '--force',
        worktreePath,
      ], workingDirectory: fixture.root.path);
      final directory = Directory(worktreePath);
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final repository = GitRepository(fixture.root.path);

    await expectLater(
      repository.applyMergePreview(
        comparison: fixture.comparison,
        treeSha: fixture.comparison.merge.treeSha!,
      ),
      throwsA(
        isA<GitRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('다른 worktree에서 체크아웃한 브랜치'),
        ),
      ),
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
  });

  test('remote merge preview updates only the local base', () async {
    final fixture = await _remoteBranchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final commands = <List<String>>[];
    final repository = GitRepository(
      fixture.root.path,
      runner: (executable, arguments, {workingDirectory, environment}) async {
        commands.add(List<String>.of(arguments));
        return runProcess(
          executable,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
        );
      },
    );

    final applied = await repository.applyMergePreview(
      comparison: fixture.comparison,
      treeSha: fixture.comparison.merge.treeSha!,
    );

    expect(applied.mode, BranchApplyMode.merge);
    expect(applied.baseBranch, 'main');
    expect(applied.compareBranch, 'origin/feature');
    expect(
      (await _git(fixture.root, ['rev-parse', 'origin/feature'])).trim(),
      fixture.remoteTip,
    );
    final localFeature = await Process.run('git', [
      'show-ref',
      '--verify',
      'refs/heads/feature',
    ], workingDirectory: fixture.root.path);
    expect(localFeature.exitCode, isNot(0));

    await repository.restoreBranchApply(applied);

    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'origin/feature'])).trim(),
      fixture.remoteTip,
    );
    expect(
      commands.where(
        (arguments) =>
            arguments.isNotEmpty &&
            (arguments.first == 'push' || arguments.first == 'fetch'),
      ),
      isEmpty,
    );
  });

  test('remote merge apply rejects a changed remote tip', () async {
    final fixture = await _remoteBranchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    await _git(fixture.root, [
      'update-ref',
      'refs/remotes/origin/feature',
      fixture.comparison.baseTip,
    ]);

    await expectLater(
      repository.applyMergePreview(
        comparison: fixture.comparison,
        treeSha: fixture.comparison.merge.treeSha!,
      ),
      throwsA(
        isA<GitRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('브랜치가 바뀌어 미리보기를 다시 계산'),
        ),
      ),
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
  });

  test(
    'rebase preview applies its virtual tip and restores both tips',
    () async {
      final fixture = await _branchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final repository = GitRepository(fixture.root.path);
      final session = await repository.openRebasePreview(
        baseRef: 'main',
        compareRef: 'feature',
      );
      addTearDown(session.dispose);
      final preview = await session.start();

      final applied = await repository.applyRebasePreview(
        comparison: fixture.comparison,
        virtualTip: preview.virtualTip!,
      );

      expect(applied.mode, BranchApplyMode.rebase);
      // main is checked out, so feature only has its ref moved.
      expect(applied.workingTreeUpdated, isFalse);
      expect(
        (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
        fixture.comparison.baseTip,
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
        preview.virtualTip,
      );

      await repository.restoreBranchApply(applied);

      expect(
        (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
        fixture.comparison.baseTip,
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
        fixture.comparison.compareTip,
      );
    },
  );

  test('rebase apply onto the checked-out branch updates the tree', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    await _git(fixture.root, ['switch', 'feature']);
    final repository = GitRepository(fixture.root.path);
    final session = await repository.openRebasePreview(
      baseRef: 'main',
      compareRef: 'feature',
    );
    addTearDown(session.dispose);
    final preview = await session.start();

    final applied = await repository.applyRebasePreview(
      comparison: fixture.comparison,
      virtualTip: preview.virtualTip!,
    );

    expect(applied.workingTreeUpdated, isTrue);
    expect(
      (await _git(fixture.root, ['rev-parse', 'HEAD'])).trim(),
      preview.virtualTip,
    );
    // Rebased onto main, so main's file is on disk now too.
    expect(File('${fixture.root.path}/main.txt').existsSync(), isTrue);
  });

  test(
    'remote rebase preview creates a local tracking branch and undo removes it',
    () async {
      final fixture = await _remoteBranchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final commands = <List<String>>[];
      final repository = GitRepository(
        fixture.root.path,
        runner: (executable, arguments, {workingDirectory, environment}) async {
          commands.add(List<String>.of(arguments));
          return runProcess(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
          );
        },
      );
      final session = await repository.openRebasePreview(
        baseRef: 'main',
        compareRef: 'origin/feature',
      );
      addTearDown(session.dispose);
      final preview = await session.start();

      final applied = await repository.applyRebasePreview(
        comparison: fixture.comparison,
        virtualTip: preview.virtualTip!,
      );

      expect(applied.compareBranch, 'feature');
      expect(applied.compareBranchCreated, isTrue);
      expect(
        (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
        preview.virtualTip,
      );
      expect(
        (await _git(fixture.root, [
          'rev-parse',
          '--abbrev-ref',
          'feature@{upstream}',
        ])).trim(),
        'origin/feature',
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'origin/feature'])).trim(),
        fixture.remoteTip,
      );

      await repository.restoreBranchApply(applied);

      final localFeature = await Process.run('git', [
        'show-ref',
        '--verify',
        'refs/heads/feature',
      ], workingDirectory: fixture.root.path);
      expect(localFeature.exitCode, isNot(0));
      expect(
        (await _git(fixture.root, ['rev-parse', 'origin/feature'])).trim(),
        fixture.remoteTip,
      );
      expect(
        commands.where(
          (arguments) =>
              arguments.isNotEmpty &&
              (arguments.first == 'push' || arguments.first == 'fetch'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'remote rebase apply rejects a divergent same-named local branch',
    () async {
      final fixture = await _remoteBranchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      await _git(fixture.root, ['branch', 'feature', 'main']);
      final repository = GitRepository(fixture.root.path);

      await expectLater(
        repository.applyRebasePreview(
          comparison: fixture.comparison,
          virtualTip: fixture.comparison.baseTip,
        ),
        throwsA(
          isA<GitRepositoryException>().having(
            (error) => error.message,
            'message',
            contains('기존 로컬 브랜치 기준으로 미리보기를 다시 계산'),
          ),
        ),
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
        fixture.comparison.baseTip,
      );
    },
  );

  test(
    'remote rebase reuses a matching local branch and undo keeps it',
    () async {
      final fixture = await _remoteBranchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      await _git(fixture.root, [
        'branch',
        '--no-track',
        'feature',
        'origin/feature',
      ]);
      final repository = GitRepository(fixture.root.path);
      final session = await repository.openRebasePreview(
        baseRef: 'main',
        compareRef: 'origin/feature',
      );
      addTearDown(session.dispose);
      final preview = await session.start();

      final applied = await repository.applyRebasePreview(
        comparison: fixture.comparison,
        virtualTip: preview.virtualTip!,
      );
      expect(applied.compareBranchCreated, isFalse);

      await repository.restoreBranchApply(applied);

      expect(
        (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
        fixture.remoteTip,
      );
      final upstream = await Process.run('git', [
        'rev-parse',
        '--abbrev-ref',
        'feature@{upstream}',
      ], workingDirectory: fixture.root.path);
      expect(upstream.exitCode, isNot(0));
    },
  );

  test(
    'rebase apply rejects a target checked out in another worktree',
    () async {
      final fixture = await _remoteBranchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      await _git(fixture.root, [
        'branch',
        '--no-track',
        'feature',
        'origin/feature',
      ]);
      final temporary = await Directory.systemTemp.createTemp(
        'yogit_apply_worktree_',
      );
      final worktreePath = temporary.path;
      await temporary.delete();
      await _git(fixture.root, ['worktree', 'add', worktreePath, 'feature']);
      addTearDown(() async {
        await Process.run('git', [
          'worktree',
          'remove',
          '--force',
          worktreePath,
        ], workingDirectory: fixture.root.path);
        final directory = Directory(worktreePath);
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final repository = GitRepository(fixture.root.path);

      await expectLater(
        repository.applyRebasePreview(
          comparison: fixture.comparison,
          virtualTip: fixture.comparison.baseTip,
        ),
        throwsA(
          isA<GitRepositoryException>().having(
            (error) => error.message,
            'message',
            contains('다른 worktree에서 체크아웃한 브랜치'),
          ),
        ),
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
        fixture.remoteTip,
      );
    },
  );

  test(
    'failed remote rebase apply removes its unchanged created branch',
    () async {
      final fixture = await _remoteBranchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final repository = GitRepository(
        fixture.root.path,
        runner: (executable, arguments, {workingDirectory, environment}) async {
          if (arguments case ['update-ref', 'refs/heads/feature', _, _]) {
            return ProcessResult(1, 1, '', 'forced update failure');
          }
          return runProcess(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
          );
        },
      );

      await expectLater(
        repository.applyRebasePreview(
          comparison: fixture.comparison,
          virtualTip: fixture.comparison.baseTip,
        ),
        throwsA(isA<ProcessException>()),
      );

      final localFeature = await Process.run('git', [
        'show-ref',
        '--verify',
        'refs/heads/feature',
      ], workingDirectory: fixture.root.path);
      expect(localFeature.exitCode, isNot(0));
      expect(
        (await _git(fixture.root, ['rev-parse', 'origin/feature'])).trim(),
        fixture.remoteTip,
      );
    },
  );

  test('branch preview apply rejects a dirty checked-out branch', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    await File('${fixture.root.path}/main.txt').writeAsString('dirty\n');

    await expectLater(
      repository.applyMergePreview(
        comparison: fixture.comparison,
        treeSha: fixture.comparison.merge.treeSha!,
      ),
      throwsA(isA<GitRepositoryException>()),
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
  });

  test('branch preview apply rejects a changed comparison tip', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    await _git(fixture.root, ['branch', '-f', 'feature', 'main']);

    await expectLater(
      repository.applyMergePreview(
        comparison: fixture.comparison,
        treeSha: fixture.comparison.merge.treeSha!,
      ),
      throwsA(isA<GitRepositoryException>()),
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
  });

  test(
    'merge restore ignores changes to its read-only comparison ref',
    () async {
      final fixture = await _branchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final repository = GitRepository(fixture.root.path);
      final applied = await repository.applyMergePreview(
        comparison: fixture.comparison,
        treeSha: fixture.comparison.merge.treeSha!,
      );
      await _git(fixture.root, [
        'branch',
        '-f',
        'feature',
        fixture.comparison.baseTip,
      ]);

      await repository.restoreBranchApply(applied);

      expect(
        (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
        fixture.comparison.baseTip,
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
        fixture.comparison.baseTip,
      );
    },
  );

  test('a clean merge names the files the base branch also changed', () async {
    final root = await Directory.systemTemp.createTemp('yogit_provenance_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    final shared = [for (var line = 1; line <= 20; line++) 'line $line'];
    await File(
      '${root.path}/shared.txt',
    ).writeAsString('${shared.join('\n')}\n');
    await File('${root.path}/moved.txt').writeAsString('moved\n');
    await File('${root.path}/gone.txt').writeAsString('gone\n');
    await _git(root, ['add', '.']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'feature']);
    await File(
      '${root.path}/shared.txt',
    ).writeAsString('${[...shared.take(19), 'feature tail'].join('\n')}\n');
    await File('${root.path}/added.txt').writeAsString('added\n');
    await _git(root, ['rm', '--quiet', 'gone.txt']);
    await _git(root, ['add', '.']);
    await _git(root, ['commit', '-m', 'feature']);
    await _git(root, ['switch', 'main']);
    await File(
      '${root.path}/shared.txt',
    ).writeAsString('${['main head', ...shared.skip(1)].join('\n')}\n');
    await _git(root, ['mv', 'moved.txt', 'renamed.txt']);
    await _git(root, ['commit', '-am', 'main']);

    final comparison = await GitRepository(
      root.path,
    ).compareBranches('main', 'feature');

    expect(comparison.merge.status, MergeConflictStatus.clean);
    // A rename counts on both of its paths, so either end flags the file.
    expect(comparison.merge.baseChangedFiles, {
      'shared.txt',
      'moved.txt',
      'renamed.txt',
    });
    expect(
      {
        for (final file in comparison.merge.resultFiles)
          file.path: file.status.substring(0, 1),
      },
      {'shared.txt': 'M', 'added.txt': 'A', 'gone.txt': 'D'},
    );
  });

  test('a criss-cross merge counts every common ancestor', () async {
    final root = await Directory.systemTemp.createTemp('yogit_crisscross_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/x.txt').writeAsString('0\n');
    await File('${root.path}/y.txt').writeAsString('0\n');
    await _git(root, ['add', '.']);
    await _git(root, ['commit', '-m', 'root']);
    await _git(root, ['switch', '-c', 'feature']);
    await File('${root.path}/y.txt').writeAsString('1\n');
    await _git(root, ['commit', '-am', 'feature y']);
    await _git(root, ['switch', 'main']);
    await File('${root.path}/x.txt').writeAsString('1\n');
    await _git(root, ['commit', '-am', 'main x']);
    final mainX = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    // Both sides merge the other, so they end up sharing two common ancestors.
    await _git(root, ['merge', '--no-edit', 'feature']);
    await _git(root, ['switch', 'feature']);
    await _git(root, ['merge', '--no-edit', mainX]);

    final comparison = await GitRepository(
      root.path,
    ).compareBranches('main', 'feature');

    expect(comparison.mergeBases, hasLength(2));
    expect(comparison.merge.status, MergeConflictStatus.clean);
    // y.txt changed since one base, x.txt since the other; either base alone
    // would name half of what main touched.
    expect(comparison.merge.baseChangedFiles, {'x.txt', 'y.txt'});
  });

  test('cherry-pick applies one commit and rejects a dirty worktree', () async {
    final root = await Directory.systemTemp.createTemp('yogit_cherrypick_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/base.txt').writeAsString('base\n');
    await _git(root, ['add', 'base.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'source']);
    await File('${root.path}/picked.txt').writeAsString('picked\n');
    await _git(root, ['add', 'picked.txt']);
    await _git(root, ['commit', '-m', 'picked']);
    final sourceSha = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    await _git(root, ['switch', 'main']);

    final repository = GitRepository(root.path);
    final result = await repository.cherryPick(sourceSha);

    expect(result.outcome, CherryPickOutcome.applied);
    expect(result.headSha, (await _git(root, ['rev-parse', 'HEAD'])).trim());
    expect(await File('${root.path}/picked.txt').readAsString(), 'picked\n');
    expect(await repository.loadCherryPickState(), isNull);

    await _git(root, ['reset', '--hard', 'HEAD^']);
    await File('${root.path}/base.txt').writeAsString('dirty\n');
    final head = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    await expectLater(
      repository.cherryPick(sourceSha),
      throwsA(isA<GitRepositoryException>()),
    );
    expect((await _git(root, ['rev-parse', 'HEAD'])).trim(), head);
    expect(await File('${root.path}/base.txt').readAsString(), 'dirty\n');
    expect(File('${root.path}/picked.txt').existsSync(), isFalse);
  });

  test('repository reports whether a Git operation is active', () async {
    final root = await Directory.systemTemp.createTemp(
      'yogit_operation_state_',
    );
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/base.txt').writeAsString('base\n');
    await _git(root, ['add', 'base.txt']);
    await _git(root, ['commit', '-m', 'base']);
    final repository = GitRepository(root.path);

    expect(await repository.operationInProgress(), isFalse);
    final head = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    await File('${root.path}/.git/MERGE_HEAD').writeAsString('$head\n');
    expect(await repository.operationInProgress(), isTrue);
  });

  test('cherry-pick conflict can be restored, staged, and continued', () async {
    final root = await Directory.systemTemp.createTemp(
      'yogit_cherrypick_conflict_',
    );
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/shared.txt').writeAsString('base\n');
    await _git(root, ['add', 'shared.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'source']);
    await File('${root.path}/shared.txt').writeAsString('source\n');
    await _git(root, ['commit', '-am', 'source']);
    final sourceSha = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    await _git(root, ['switch', 'main']);
    await File('${root.path}/shared.txt').writeAsString('main\n');
    await _git(root, ['commit', '-am', 'main']);

    final repository = GitRepository(root.path);
    final result = await repository.cherryPick(sourceSha);

    expect(result.outcome, CherryPickOutcome.conflicts);
    expect(result.state?.commitSha, sourceSha);
    expect(result.state?.conflicts, ['shared.txt']);
    expect((await repository.loadCherryPickState())?.conflicts, ['shared.txt']);
    await expectLater(
      repository.stageResolvedFile('shared.txt'),
      throwsA(isA<GitRepositoryException>()),
    );

    await File('${root.path}/shared.txt').writeAsString('resolved\n');
    await repository.stageResolvedFile('shared.txt');
    expect((await repository.loadCherryPickState())?.canContinue, isTrue);
    final continued = await repository.continueCherryPick();

    expect(continued.outcome, CherryPickOutcome.applied);
    expect(await repository.loadCherryPickState(), isNull);
    expect(await File('${root.path}/shared.txt').readAsString(), 'resolved\n');
  });

  test(
    'abortCherryPick restores the exact pre-pick HEAD and worktree',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yogit_cherrypick_abort_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/shared.txt').writeAsString('base\n');
      await _git(root, ['add', 'shared.txt']);
      await _git(root, ['commit', '-m', 'base']);
      await _git(root, ['switch', '-c', 'source']);
      await File('${root.path}/shared.txt').writeAsString('source\n');
      await _git(root, ['commit', '-am', 'source']);
      final sourceSha = (await _git(root, ['rev-parse', 'HEAD'])).trim();
      await _git(root, ['switch', 'main']);
      await File('${root.path}/shared.txt').writeAsString('main\n');
      await _git(root, ['commit', '-am', 'main']);
      final head = (await _git(root, ['rev-parse', 'HEAD'])).trim();

      final repository = GitRepository(root.path);
      expect(
        (await repository.cherryPick(sourceSha)).outcome,
        CherryPickOutcome.conflicts,
      );
      await repository.abortCherryPick();

      expect((await _git(root, ['rev-parse', 'HEAD'])).trim(), head);
      expect(await File('${root.path}/shared.txt').readAsString(), 'main\n');
      expect((await _git(root, ['status', '--porcelain'])).trim(), isEmpty);
      expect(await repository.loadCherryPickState(), isNull);
    },
  );

  test('cherry-pick skips an already applied empty change', () async {
    final root = await Directory.systemTemp.createTemp(
      'yogit_cherrypick_empty_',
    );
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/shared.txt').writeAsString('base\n');
    await _git(root, ['add', 'shared.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['switch', '-c', 'source']);
    await File('${root.path}/shared.txt').writeAsString('same\n');
    await _git(root, ['commit', '-am', 'source']);
    final sourceSha = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    await _git(root, ['switch', 'main']);
    await File('${root.path}/shared.txt').writeAsString('same\n');
    await _git(root, ['commit', '-am', 'main']);
    final head = (await _git(root, ['rev-parse', 'HEAD'])).trim();

    final result = await GitRepository(root.path).cherryPick(sourceSha);

    expect(result.outcome, CherryPickOutcome.empty);
    expect((await _git(root, ['rev-parse', 'HEAD'])).trim(), head);
    expect((await _git(root, ['status', '--porcelain'])).trim(), isEmpty);
  });

  test('working-tree path resolution rejects a symlink escape', () async {
    final root = await Directory.systemTemp.createTemp('yogit_safe_path_');
    final outside = await Directory.systemTemp.createTemp(
      'yogit_safe_path_outside_',
    );
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));
    final inside = File('${root.path}/inside.txt')..writeAsStringSync('inside');
    final escaped = File('${outside.path}/outside.txt')
      ..writeAsStringSync('outside');
    await Link('${root.path}/escape.txt').create(escaped.path);

    expect(
      (await resolveWorkingTreeFile(root.path, 'inside.txt')).path,
      await inside.resolveSymbolicLinks(),
    );
    await expectLater(
      resolveWorkingTreeFile(root.path, 'escape.txt'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('retains the commit SHA occupying each lane segment', () {
    final branch = _commit('B', [
      'R',
    ], committer: const GitIdentity(name: 'Bee', email: 'bee@example.com'));
    final commits = [
      _commit('C', ['A', 'B']),
      _commit('A', ['R']),
      branch,
      _commit('R', const []),
    ];

    final rows = layoutGraph(commits);

    expect(rows[0].activeLaneShas, {0: 'C'});
    expect(rows[0].nextLaneShas, {0: 'A', 1: 'B'});
    expect(rows[1].activeLaneShas[1], 'B');
    expect(rows[1].nextLaneShas[1], 'B');
  });

  test('paints untouched rails in the occupying branch line color', () async {
    final branch = _commit('B', [
      'R',
    ], committer: const GitIdentity(name: 'Bee', email: 'bee@example.com'));
    final commits = [
      _commit('C', ['A', 'B']),
      _commit('A', ['R']),
      branch,
      _commit('R', const []),
    ];
    final row = layoutGraph(commits)[1];
    final painter = CommitGraphPainter(
      row: row,
      selected: false,
      committerColor: AvatarService.color(row.commit.committer),
      committersBySha: {
        for (final commit in commits) commit.sha: commit.committer,
      },
    );

    final pixel = await _paintPixel(
      painter,
      x: painter.laneX(1).round(),
      y: 30,
    );

    // The rail is centred on the lane, so a stroke thinner than 2px straddles
    // the two pixels either side of it and the probe reads partial coverage —
    // half of it for today's 1px rail. Deriving the fraction from railWidth keeps
    // the expectation honest if the rail ever gets thicker, where the sampled
    // pixel goes fully covered.
    final coverage = (CommitGraphPainter.railWidth / 2).clamp(0.0, 1.0);
    Color rail(Color color) => _quantize(
      Color.alphaBlend(
        color.withValues(alpha: CommitGraphPainter.railOpacity * coverage),
        _canvasBackground,
      ),
    );

    // The rail passing this row belongs to B's line, not to the row's own line
    // and not to B's committer — the graph colors by branch.
    expect(row.branch, 0);
    expect(row.activeLaneBranches[1], 1);
    expect(pixel, rail(AvatarService.branchColor(row.activeLaneBranches[1]!)));
    // Same coverage math on both sides, so this still fails if the rail goes
    // back to being colored by the committer.
    expect(pixel, isNot(rail(AvatarService.color(branch.committer))));
  });

  test('uses one-pixel dashes for preview lanes', () {
    final row = layoutGraph([
      _commit('virtual', ['parent']),
      _commit('parent', const []),
    ]).first;
    final painter = CommitGraphPainter(
      row: row,
      selected: false,
      committerColor: const Color(0xFF00AAFF),
      dashedLanes: const {0},
    );

    expect(painter.isDashedLane(0), isTrue);
    expect(CommitGraphPainter.previewRailWidth, 1);
  });

  test('a converged lane leaves no phantom rail above the next bend', () async {
    final rows = layoutGraph([
      _commit('T', ['C', 'B']),
      _commit('B', ['C']),
      _commit('C', ['P', 'N']),
      _commit('N', ['P']),
      _commit('P', const []),
    ]);
    final row = rows[2];
    final painter = CommitGraphPainter(
      row: row,
      previous: rows[1],
      selected: false,
      committerColor: AvatarService.branchColor(row.branch),
    );

    expect(rows[1].transitions, [(from: 1, to: 0, sha: 'C')]);
    expect(row.transitions, [(from: 0, to: 1, sha: 'N')]);
    expect(
      await _paintPixel(painter, x: painter.laneX(1).round(), y: 17),
      _canvasBackground,
    );
  });

  test('selected band spans the full row to the graph boundary', () {
    final row = layoutGraph([_commit('C', const [])]).single;
    final painter = CommitGraphPainter(
      row: row,
      selected: true,
      committerColor: AvatarService.color(row.commit.committer),
      committersBySha: {row.commit.sha: row.commit.committer},
    );

    expect(
      painter.selectedBandRect(const Size(168, 36)),
      Rect.fromLTRB(painter.laneX(row.lane), 0, 168, 36),
    );
  });

  test('parses unified additions with new line numbers', () {
    const diff = '@@ -1,2 +1,2 @@\n unchanged\n-old\n+new\n';

    final lines = parseUnifiedDiff(diff);

    expect(
      lines.where((line) => line.kind == DiffLineKind.add).single.newNumber,
      2,
    );
  });

  test('retains diff headers, hunks, content, and line numbers', () {
    const diff =
        'diff --git a/lib/a.dart b/lib/a.dart\n'
        'index 1111111..2222222 100644\n'
        '--- a/lib/a.dart\n'
        '+++ b/lib/a.dart\n'
        '@@ -4,2 +4,2 @@\n'
        ' same\n'
        '-old\n'
        '+new\n';

    final lines = parseUnifiedDiff(diff);

    expect(lines.map((line) => line.kind), [
      DiffLineKind.header,
      DiffLineKind.header,
      DiffLineKind.header,
      DiffLineKind.header,
      DiffLineKind.hunk,
      DiffLineKind.context,
      DiffLineKind.delete,
      DiffLineKind.add,
    ]);
    expect(lines[5].oldNumber, 4);
    expect(lines[5].newNumber, 4);
    expect(lines[6].oldNumber, 5);
    expect(lines[7].newNumber, 5);
  });

  test('pairs consecutive deletions and additions side by side', () {
    final pairs = pairDiff([
      const DiffLine(kind: DiffLineKind.delete, text: 'old 1', oldNumber: 1),
      const DiffLine(kind: DiffLineKind.delete, text: 'old 2', oldNumber: 2),
      const DiffLine(kind: DiffLineKind.add, text: 'new 1', newNumber: 1),
    ]);

    expect(pairs, hasLength(2));
    expect(pairs.first.left?.kind, DiffLineKind.delete);
    expect(pairs.first.right?.kind, DiffLineKind.add);
    expect(pairs.last.left?.text, 'old 2');
    expect(pairs.last.right, isNull);
  });

  test('maps diff algorithms to git arguments', () {
    expect(DiffAlgorithm.values.map((value) => value.label), [
      'Git setting',
      'Myers',
      'Minimal',
      'Patience',
      'Histogram',
    ]);
    expect(DiffAlgorithm.values.map((value) => value.gitArguments), [
      const <String>[],
      const ['--diff-algorithm=myers'],
      const ['--diff-algorithm=minimal'],
      const ['--diff-algorithm=patience'],
      const ['--diff-algorithm=histogram'],
    ]);
  });

  test('resolves Git diff algorithm settings to concrete choices', () {
    final unset = parseGitDiffAlgorithmSetting(null);
    expect(unset.algorithm, DiffAlgorithm.myers);
    expect(unset.usesGitDefault, isTrue);
    expect(unset.configLabel, 'diff.algorithm 미설정');

    for (final entry in {
      'default': DiffAlgorithm.myers,
      'MYERS': DiffAlgorithm.myers,
      'minimal': DiffAlgorithm.minimal,
      'patience': DiffAlgorithm.patience,
      'histogram': DiffAlgorithm.histogram,
    }.entries) {
      expect(parseGitDiffAlgorithmSetting(entry.key).algorithm, entry.value);
    }

    const histogram = GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.histogram,
      configuredValue: 'histogram',
    );
    expect(
      histogram.normalizeSelection(DiffAlgorithm.histogram),
      DiffAlgorithm.gitSetting,
    );
    expect(
      histogram.resolveSelection(DiffAlgorithm.gitSetting),
      DiffAlgorithm.histogram,
    );
  });

  test('rejects unsupported Git diff algorithm settings', () {
    for (final value in ['', 'unknown']) {
      expect(
        () => parseGitDiffAlgorithmSetting(value),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test(
    'requests three context lines and optionally ignores whitespace',
    () async {
      final calls = <List<String>>[];
      final repository = GitRepository(
        '.',
        runner: (executable, arguments, {workingDirectory, environment}) async {
          calls.add(arguments);
          return ProcessResult(1, 0, '', '');
        },
      );
      final item = _commit('a', ['b']);

      await repository.loadDiff(item, _file('lib/a.dart'));
      await repository.loadDiff(
        item,
        _file('lib/a.dart'),
        algorithm: DiffAlgorithm.histogram,
        ignoreWhitespace: true,
      );

      expect(calls, hasLength(2));
      expect(calls.first, contains('--unified=3'));
      expect(calls.first, isNot(contains('--ignore-all-space')));
      expect(
        calls.last,
        containsAllInOrder([
          '--unified=3',
          '--ignore-all-space',
          '--diff-algorithm=histogram',
        ]),
      );
    },
  );

  test('loads root files and a numbered patch', () async {
    final root = await Directory.systemTemp.createTemp('yogit_root_diff_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/root.txt').writeAsString('root line\n');
    await _git(root, ['add', 'root.txt']);
    await _git(root, ['commit', '-m', 'root']);
    final commit = (await GitRepository(root.path).loadHistory()).single;

    final files = await GitRepository(root.path).loadFiles(commit);
    final lines = await GitRepository(
      root.path,
    ).loadDiff(commit, files.single, algorithm: DiffAlgorithm.minimal);

    expect(files, hasLength(1));
    expect(files.single.path, 'root.txt');
    expect(files.single.status, 'A');
    expect(files.single.additions, 1);
    expect(files.single.deletions, 0);
    expect(lines.any((line) => line.kind == DiffLineKind.header), isTrue);
    expect(
      lines.where((line) => line.kind == DiffLineKind.add).single.newNumber,
      1,
    );
  });

  test('loads committed blob bytes without decoding them', () async {
    final root = await Directory.systemTemp.createTemp('yogit_raw_blob_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    const bytes = [0xff, 0xfe, 0x00, 0x41];
    await File('${root.path}/raw.bin').writeAsBytes(bytes);
    await _git(root, ['add', 'raw.bin']);
    await _git(root, ['commit', '-m', 'raw bytes']);
    final commit = (await GitRepository(root.path).loadHistory()).single;

    final loaded = await GitRepository(
      root.path,
    ).loadBlobBytes(commit.sha, 'raw.bin');

    expect(loaded, bytes);
  });

  test(
    'uses the first parent by default and accepts another merge parent',
    () async {
      final root = await Directory.systemTemp.createTemp('yogit_merge_diff_');
      addTearDown(() => root.delete(recursive: true));
      await _initRepository(root);
      await File('${root.path}/base.txt').writeAsString('base\n');
      await _git(root, ['add', 'base.txt']);
      await _git(root, ['commit', '-m', 'base']);
      await _git(root, ['switch', '-c', 'feature']);
      await File('${root.path}/feature.txt').writeAsString('feature\n');
      await _git(root, ['add', 'feature.txt']);
      await _git(root, ['commit', '-m', 'feature']);
      final featureSha = (await _git(root, ['rev-parse', 'HEAD'])).trim();
      await _git(root, ['switch', '-']);
      await File('${root.path}/main.txt').writeAsString('main\n');
      await _git(root, ['add', 'main.txt']);
      await _git(root, ['commit', '-m', 'main']);
      await _git(root, ['merge', '--no-ff', 'feature', '-m', 'merge']);
      final repository = GitRepository(root.path);
      final merge = (await repository.loadHistory()).first;

      final firstParentFiles = await repository.loadFiles(merge);
      final secondParentFiles = await repository.loadFiles(
        merge,
        parent: featureSha,
      );

      expect(merge.parents, hasLength(2));
      expect(firstParentFiles.map((file) => file.path), ['feature.txt']);
      expect(secondParentFiles.map((file) => file.path), ['main.txt']);
    },
  );

  test('pages from the initial history after live refs advance', () async {
    final root = await Directory.systemTemp.createTemp('yogit_git_test_');
    addTearDown(() => root.delete(recursive: true));
    await _git(root, ['init']);
    await _git(root, ['config', 'user.name', 'Test User']);
    await _git(root, ['config', 'user.email', 'test@example.com']);
    await File('${root.path}/history.txt').writeAsString('first');
    await _git(root, ['add', 'history.txt']);
    await _git(root, ['commit', '-m', 'first']);
    await File('${root.path}/history.txt').writeAsString('second');
    await _git(root, ['commit', '-am', 'second']);

    final repository = GitRepository(root.path);
    final firstPage = await repository.loadHistory(limit: 1);
    await File('${root.path}/history.txt').writeAsString('third');
    await _git(root, ['commit', '-am', 'third']);
    final secondPage = await repository.loadHistory(skip: 1, limit: 1);

    expect(firstPage.single.subject, 'second');
    expect(secondPage.single.subject, 'first');
  });

  test('dedupes and reuses pinned revisions for every page', () async {
    const first = '1111111111111111111111111111111111111111';
    const second = '2222222222222222222222222222222222222222';
    var liveRefs = '$first\n$second\n$first\n';
    final calls = <List<String>>[];
    final repository = GitRepository(
      '/tmp/repository',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        calls.add(arguments);
        if (arguments.first == 'rev-parse') {
          return ProcessResult(1, 0, liveRefs, '');
        }
        return ProcessResult(1, 0, '', '');
      },
    );

    await repository.loadHistory(limit: 500);
    liveRefs = '3333333333333333333333333333333333333333\n';
    await repository.loadHistory(skip: 500, limit: 500);

    expect(calls.where((call) => call.first == 'rev-parse'), hasLength(1));
    expect(calls.first, ['rev-parse', '--revs-only', 'HEAD', '--all']);
    final logs = calls.where((call) => call.first == 'log').toList();
    expect(logs, hasLength(2));
    for (final log in logs) {
      expect(log, isNot(contains('--all')));
      expect(log.where((argument) => argument == first || argument == second), [
        first,
        second,
      ]);
    }
  });

  test(
    'uses parser-safe diff flags and caches the repository empty tree',
    () async {
      final calls = <List<String>>[];
      final repository = GitRepository(
        '/tmp/repository',
        gitExecutable: '/usr/bin/git',
        runner: (executable, arguments, {workingDirectory, environment}) async {
          calls.add(arguments);
          if (arguments.first == 'hash-object') {
            return ProcessResult(1, 0, 'sha256-empty-tree\n', '');
          }
          return ProcessResult(1, 0, '', '');
        },
      );
      final root = _commit('root', const []);

      await repository.loadDiff(root, _file('README.md'));
      await repository.loadFiles(root);

      expect(
        calls.where((arguments) => arguments.first == 'hash-object'),
        hasLength(1),
      );
      final diffs = calls.where((arguments) => arguments.first == 'diff');
      for (final arguments in diffs) {
        expect(
          arguments,
          containsAll([
            '--no-ext-diff',
            '--no-textconv',
            '--no-color',
            'sha256-empty-tree',
          ]),
        );
      }
    },
  );

  test('working tree row diffs HEAD against the working directory', () async {
    final calls = <List<String>>[];
    final repository = GitRepository(
      '/tmp/repository',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        calls.add(arguments);
        if (arguments.first == 'status') {
          return ProcessResult(1, 0, ' M lib/timeline.dart\n', '');
        }
        if (arguments.first == 'rev-parse') {
          return ProcessResult(1, 0, 'head-sha\n', '');
        }
        return ProcessResult(1, 0, '', '');
      },
    );

    final working = await repository.loadWorkingTree();
    expect(working, isNotNull);
    expect(working!.isWorkingTree, isTrue);
    expect(working.subject, 'Uncommitted changes');
    expect(working.parents, ['head-sha']);

    await repository.loadFiles(working);
    await repository.loadDiff(working, _file('lib/timeline.dart'));

    final diffs = calls
        .where((arguments) => arguments.first == 'diff')
        .toList();
    expect(diffs, hasLength(3));
    for (final arguments in diffs) {
      expect(arguments, contains('head-sha'));
      expect(arguments, isNot(contains('')));
    }
  });

  test('buckets refs into local, remote, and tags', () async {
    final calls = <List<String>>[];
    final repository = GitRepository(
      '/tmp/repository',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        calls.add(arguments);
        if (arguments.first == 'remote') {
          return ProcessResult(1, 0, 'company\n', '');
        }
        if (arguments.first == 'for-each-ref') {
          return ProcessResult(
            1,
            0,
            'refs/heads/main\x00aaa1\x001700000100'
                '\x00company/trunk\x00company\n'
                'refs/heads/feature/x\x00aaa2\x001700000200\x00\x00\n'
                'refs/remotes/company/HEAD\x00aaa1\x001700000100\x00\x00\n'
                'refs/remotes/company/trunk\x00aaa3\x001700000300\x00\x00\n'
                'refs/tags/undated\x00aaa5\x00\x00\x00\n'
                'refs/tags/v0.1.0\x00aaa4\x001700000400\x00\x00\n',
            '',
          );
        }
        if (arguments.first == 'reflog') {
          // Newest entry first, so the branch was created on the last line.
          return arguments.last.endsWith('/main')
              ? ProcessResult(1, 0, '1700000200\n1700000100\n', '')
              : ProcessResult(1, 0, '', '');
        }
        if (arguments.first == 'rev-list') {
          return ProcessResult(1, 0, '2\t3\n', '');
        }
        return ProcessResult(1, 0, 'main\n', '');
      },
    );

    final refs = await repository.loadRefs();

    expect(refs.local, ['main', 'feature/x']);
    expect(refs.remote, ['company/trunk']);
    expect(refs.remoteNames, ['company']);
    expect(refs.tags, ['undated', 'v0.1.0']);
    expect(refs.tagCreatorTimes, {'v0.1.0': 1700000400});
    expect(refs.branchActivityTimes, {
      'main': 1700000100,
      'feature/x': 1700000200,
      'company/trunk': 1700000300,
    });
    expect(refs.current, 'main');
    // company/HEAD is an alias, so it contributes neither a name nor a tip.
    expect(refs.tips, {
      'main': 'aaa1',
      'feature/x': 'aaa2',
      'company/trunk': 'aaa3',
      'undated': 'aaa5',
      'v0.1.0': 'aaa4',
    });
    expect(refs.localTips, {'main': 'aaa1', 'feature/x': 'aaa2'});
    expect(refs.upstreams, {'main': 'company/trunk'});
    expect(refs.upstreamRemotes, {'main': 'company'});
    expect(refs.aheadBehind['main']?.ahead, 2);
    expect(refs.aheadBehind['main']?.behind, 3);
    // Only local branches have a birth time, and an empty reflog just has none.
    expect(refs.birthTimes, {'main': 1700000100});
    expect(calls, [
      ['remote'],
      [
        'for-each-ref',
        '--format=%(refname)%00%(objectname)%00%(creatordate:unix)'
            '%00%(upstream:short)%00%(upstream:remotename)',
        'refs/heads',
        'refs/remotes',
        'refs/tags',
      ],
      ['reflog', 'show', '--format=%ct', 'refs/heads/main'],
      ['reflog', 'show', '--format=%ct', 'refs/heads/feature/x'],
      [
        'rev-list',
        '--left-right',
        '--count',
        'refs/heads/main...refs/remotes/company/trunk',
      ],
      ['branch', '--show-current'],
    ]);
    expect(
      calls
          .expand((arguments) => arguments)
          .where((argument) => !argument.startsWith('--format=')),
      everyElement(isNot(contains(' '))),
    );
  });

  test('a real repository answers what moved, and how', () async {
    // 가짜 runner는 인자를 그대로 되돌려줄 뿐 git이 그것을 알아듣는지는 모른다.
    // 실제 git에 물어야 잘못된 플래그가 잡힌다.
    final root = await Directory.systemTemp.createTemp('yogit_moved_');
    addTearDown(() => root.delete(recursive: true));
    await _initRepository(root);
    await File('${root.path}/file.txt').writeAsString('base\n');
    await _git(root, ['add', 'file.txt']);
    await _git(root, ['commit', '-m', 'base']);
    final before = (await _git(root, ['rev-parse', 'HEAD'])).trim();
    await File('${root.path}/file.txt').writeAsString('one\n');
    await _git(root, ['commit', '-am', 'first on top']);
    await File('${root.path}/file.txt').writeAsString('two\n');
    await _git(root, ['commit', '-am', 'second on top']);
    final after = (await _git(root, ['rev-parse', 'HEAD'])).trim();

    final repository = GitRepository(root.path);

    expect(await repository.countMovedCommits(before, after), (
      outgoing: 0,
      incoming: 2,
    ));
    final commits = await repository.loadMovedCommits(before, after);
    expect(commits.map((commit) => commit.subject), [
      'second on top',
      'first on top',
    ]);
    expect(commits.every((commit) => commit.incoming), isTrue);
    expect(commits.first.shortSha, isNotEmpty);
    expect(await repository.loadBranchOperation('main'), 'commit');
  });

  test('loadHistory decorates a tip without the origin/HEAD alias', () async {
    final root = await Directory.systemTemp.createTemp('yogit_head_log_');
    final remote = await Directory.systemTemp.createTemp(
      'yogit_head_log_bare_',
    );
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => remote.delete(recursive: true));

    await _git(remote, ['init', '--bare']);
    await _initRepository(root);
    await File('${root.path}/file.txt').writeAsString('base\n');
    await _git(root, ['add', 'file.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['remote', 'add', 'origin', remote.path]);
    await _git(root, ['push', '-u', 'origin', 'main']);
    await _git(root, ['remote', 'set-head', 'origin', 'main']);

    // git really does decorate the tip with both names, e.g.
    // `main, origin/main, origin/HEAD`. Only the alias goes.
    final commits = await GitRepository(root.path).loadHistory();
    final names = commits.first.refs.map((ref) => ref.name).toList();

    expect(names, contains('origin/main'));
    expect(names, isNot(contains('origin/HEAD')));
  });

  test('loadRefs leaves origin/HEAD out of the remote list', () async {
    final root = await Directory.systemTemp.createTemp('yogit_remote_head_');
    final remote = await Directory.systemTemp.createTemp('yogit_origin_head_');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => remote.delete(recursive: true));

    await _git(remote, ['init', '--bare']);
    await _initRepository(root);
    await File('${root.path}/file.txt').writeAsString('base\n');
    await _git(root, ['add', 'file.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['remote', 'add', 'origin', remote.path]);
    await _git(root, ['push', '-u', 'origin', 'main']);
    await _git(root, ['remote', 'set-head', 'origin', 'main']);

    final refs = await GitRepository(root.path).loadRefs();

    // The alias points at a branch that is already in the list; showing it
    // would only name the same thing twice.
    expect(refs.remote, contains('origin/main'));
    expect(refs.remote, isNot(contains('origin/HEAD')));
  });

  test('loadRefs reports local and origin divergence by direction', () async {
    final root = await Directory.systemTemp.createTemp('yogit_divergence_');
    final remote = await Directory.systemTemp.createTemp('yogit_origin_');
    final other = await Directory.systemTemp.createTemp('yogit_other_');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => remote.delete(recursive: true));
    addTearDown(() => other.delete(recursive: true));

    await _git(remote, ['init', '--bare']);
    await _initRepository(root);
    await File('${root.path}/file.txt').writeAsString('base\n');
    await _git(root, ['add', 'file.txt']);
    await _git(root, ['commit', '-m', 'base']);
    await _git(root, ['remote', 'add', 'origin', remote.path]);
    await _git(root, ['push', '-u', 'origin', 'main']);
    await _git(root, ['tag', 'main']);

    await File('${root.path}/local.txt').writeAsString('local\n');
    await _git(root, ['add', 'local.txt']);
    await _git(root, ['commit', '-m', 'local']);

    await _git(other, ['clone', remote.path, '.']);
    await _git(other, ['config', 'user.name', 'Other User']);
    await _git(other, ['config', 'user.email', 'other@example.com']);
    await File('${other.path}/remote.txt').writeAsString('remote\n');
    await _git(other, ['add', 'remote.txt']);
    await _git(other, ['commit', '-m', 'remote']);
    await _git(other, ['push', 'origin', 'main']);
    await _git(root, ['fetch', 'origin']);

    final refs = await GitRepository(root.path).loadRefs();

    expect(refs.aheadBehind['main']?.ahead, 1);
    expect(refs.aheadBehind['main']?.behind, 1);
  });

  test(
    'loadRefs reports remote divergence from a same-named local branch',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'yogit_remote_divergence_',
      );
      final remote = await Directory.systemTemp.createTemp(
        'yogit_remote_divergence_origin_',
      );
      final other = await Directory.systemTemp.createTemp(
        'yogit_remote_divergence_other_',
      );
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => remote.delete(recursive: true));
      addTearDown(() => other.delete(recursive: true));

      await _git(remote, ['init', '--bare']);
      await _initRepository(root);
      await File('${root.path}/file.txt').writeAsString('base\n');
      await _git(root, ['add', 'file.txt']);
      await _git(root, ['commit', '-m', 'base']);
      await _git(root, ['remote', 'add', 'foo/bar', remote.path]);
      await _git(root, ['push', '-u', 'foo/bar', 'main']);
      await _git(root, ['branch', '--unset-upstream', 'main']);

      await File('${root.path}/local.txt').writeAsString('local\n');
      await _git(root, ['add', 'local.txt']);
      await _git(root, ['commit', '-m', 'local']);

      await _git(other, ['clone', remote.path, '.']);
      await _git(other, ['config', 'user.name', 'Other User']);
      await _git(other, ['config', 'user.email', 'other@example.com']);
      await File('${other.path}/remote.txt').writeAsString('remote\n');
      await _git(other, ['add', 'remote.txt']);
      await _git(other, ['commit', '-m', 'remote']);
      await _git(other, ['push', 'origin', 'main']);
      await _git(root, ['fetch', 'foo/bar']);

      final refs = await GitRepository(root.path).loadRefs();

      expect(refs.aheadBehind, isEmpty);
      expect(refs.remoteAheadBehind['foo/bar/main']?.ahead, 1);
      expect(refs.remoteAheadBehind['foo/bar/main']?.behind, 1);
    },
  );

  test('fetchRemote distinguishes unchanged and updated refs', () async {
    final calls = <List<String>>[];
    Map<String, String>? fetchEnvironment;
    var output = '';
    final repository = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        calls.add(arguments);
        fetchEnvironment = environment;
        return ProcessResult(1, 0, output, '');
      },
    );

    expect(
      await repository.fetchRemote('company'),
      FetchOriginResult.unchanged,
    );
    output = '* refs/heads/main:refs/remotes/company/main\t[new branch]\n';
    expect(await repository.fetchRemote('company'), FetchOriginResult.updated);
    expect(calls, [
      [
        '-c',
        'credential.interactive=never',
        'fetch',
        '--porcelain',
        '--prune',
        'company',
      ],
      [
        '-c',
        'credential.interactive=never',
        'fetch',
        '--porcelain',
        '--prune',
        'company',
      ],
    ]);
    expect(fetchEnvironment?['GIT_TERMINAL_PROMPT'], '0');
    expect(fetchEnvironment?['GCM_INTERACTIVE'], 'Never');
  });

  test('fetchOrigin disables terminal prompts and handles no origin', () async {
    Map<String, String>? fetchEnvironment;
    final repository = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        if (arguments case ['remote', 'get-url', 'origin']) {
          return ProcessResult(1, 0, 'https://example.com/repo.git\n', '');
        }
        fetchEnvironment = environment;
        return ProcessResult(2, 0, '', '');
      },
    );

    expect(await repository.fetchOrigin(), FetchOriginResult.unchanged);
    expect(fetchEnvironment?['GIT_TERMINAL_PROMPT'], '0');
    expect(fetchEnvironment?['GCM_INTERACTIVE'], 'Never');

    final noOrigin = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(3, 2, '', 'missing'),
    );
    expect(await noOrigin.fetchOrigin(), FetchOriginResult.noOrigin);
  });

  group('remotePullState', () {
    const refs = RepoRefs(
      local: ['main', 'feature/lane'],
      remote: [
        'origin/main',
        'origin/feature/lane',
        'origin/feature/new-lane',
        'unknown-prefix',
      ],
      remoteNames: ['origin'],
      current: 'main',
      remoteAheadBehind: {
        'origin/main': BranchAheadBehind(ahead: 3, behind: 0),
        'origin/feature/lane': BranchAheadBehind(ahead: 2, behind: 3),
      },
    );

    test('an unknown remote prefix has no pull state', () {
      expect(remotePullState(refs, 'unknown-prefix'), isNull);
    });

    test('a branch without a local counterpart wants a tracking branch', () {
      final state = remotePullState(refs, 'origin/feature/new-lane')!;
      expect(state.kind, RemotePullKind.noLocal);
      expect(state.remote, 'origin');
      expect(state.localBranch, 'feature/new-lane');
    });

    test('a remote strictly ahead fast-forwards the checked out local', () {
      final state = remotePullState(refs, 'origin/main')!;
      expect(state.kind, RemotePullKind.fastForward);
      expect(state.ahead, 3);
      expect(state.behind, 0);
      expect(state.checkedOut, isTrue);
    });

    test('commits on both sides mean no fast-forward', () {
      final state = remotePullState(refs, 'origin/feature/lane')!;
      expect(state.kind, RemotePullKind.diverged);
      expect(state.ahead, 2);
      expect(state.behind, 3);
      expect(state.checkedOut, isFalse);
    });

    test('nothing to pull is up to date, even when local is ahead', () {
      const localAhead = RepoRefs(
        local: ['main'],
        remote: ['origin/main'],
        remoteNames: ['origin'],
        remoteAheadBehind: {
          'origin/main': BranchAheadBehind(ahead: 0, behind: 2),
        },
      );
      final state = remotePullState(localAhead, 'origin/main')!;
      expect(state.kind, RemotePullKind.upToDate);
      expect(state.behind, 2);
      expect(state.checkedOut, isFalse);
    });
  });

  test(
    'pullRemoteBranch pulls the checkout but fetches other branches',
    () async {
      final calls = <List<String>>[];
      Map<String, String>? pullEnvironment;
      final repository = GitRepository(
        '/repo',
        runner: (executable, arguments, {workingDirectory, environment}) async {
          calls.add(arguments);
          pullEnvironment = environment;
          return ProcessResult(1, 0, '', '');
        },
      );

      await repository.pullRemoteBranch('origin', 'main', checkedOut: true);
      await repository.pullRemoteBranch(
        'origin',
        'feature/lane',
        checkedOut: false,
      );

      expect(calls, [
        [
          '-c',
          'credential.interactive=never',
          'pull',
          '--ff-only',
          'origin',
          'main',
        ],
        [
          '-c',
          'credential.interactive=never',
          'fetch',
          'origin',
          'feature/lane:feature/lane',
        ],
      ]);
      expect(pullEnvironment?['GIT_TERMINAL_PROMPT'], '0');
      expect(pullEnvironment?['GCM_INTERACTIVE'], 'Never');
    },
  );

  test('pullRemoteBranch surfaces the git failure', () async {
    final repository = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 128, '', 'fatal: not possible to fast-forward'),
    );

    await expectLater(
      repository.pullRemoteBranch('origin', 'main', checkedOut: true),
      throwsA(isA<ProcessException>()),
    );
  });

  test(
    'checkoutRemoteBranch switches, creating a tracking branch when asked',
    () async {
      final calls = <List<String>>[];
      final repository = GitRepository(
        '/repo',
        runner: (executable, arguments, {workingDirectory, environment}) async {
          calls.add(arguments);
          return ProcessResult(1, 0, '', '');
        },
      );

      await repository.checkoutRemoteBranch(
        'origin',
        'feature/new-lane',
        createLocal: true,
      );
      await repository.checkoutRemoteBranch(
        'origin',
        'main',
        createLocal: false,
      );

      expect(calls, [
        [
          'switch',
          '-c',
          'feature/new-lane',
          '--track',
          'origin/feature/new-lane',
        ],
        ['switch', 'main'],
      ]);
    },
  );

  test(
    'deleteLocalBranch force-deletes and surfaces the git failure',
    () async {
      final calls = <List<String>>[];
      final repository = GitRepository(
        '/repo',
        runner: (executable, arguments, {workingDirectory, environment}) async {
          calls.add(arguments);
          return ProcessResult(1, 0, '', '');
        },
      );

      await repository.deleteLocalBranch('feature/lane');
      expect(calls, [
        ['branch', '-D', 'feature/lane'],
      ]);

      final failing = GitRepository(
        '/repo',
        runner:
            (executable, arguments, {workingDirectory, environment}) async =>
                ProcessResult(1, 1, '', "error: cannot delete branch 'main'"),
      );
      await expectLater(
        failing.deleteLocalBranch('main'),
        throwsA(isA<ProcessException>()),
      );
    },
  );

  test('removeWorktree force-removes the checkout', () async {
    final calls = <List<String>>[];
    final repository = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        calls.add(arguments);
        return ProcessResult(1, 0, '', '');
      },
    );

    await repository.removeWorktree('/repo/.worktrees/lane');
    expect(calls, [
      ['worktree', 'remove', '--force', '/repo/.worktrees/lane'],
    ]);
  });

  test('byteSizeLabel picks a readable unit', () {
    expect(byteSizeLabel(512), '512 B');
    expect(byteSizeLabel(1536), '1.5 KB');
    expect(byteSizeLabel(10 * 1024 * 1024), '10 MB');
    expect(byteSizeLabel(3 * 1024 * 1024 * 1024), '3.0 GB');
  });

  test('directorySizeBytes sums regular files only', () async {
    final directory = await Directory.systemTemp.createTemp('yogit_size_');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/a.txt').writeAsString('12345');
    await Directory('${directory.path}/sub').create();
    await File('${directory.path}/sub/b.txt').writeAsString('123');
    await Link('${directory.path}/loop').create(directory.path);

    expect(await directorySizeBytes(directory.path), 8);
  });

  test(
    'loadGitDirectories resolves the worktree and common git dirs',
    () async {
      final calls = <List<String>>[];
      final repository = GitRepository(
        '/repo',
        runner: (executable, arguments, {workingDirectory, environment}) async {
          calls.add(arguments);
          // A linked worktree: its own git dir, plus the shared one it borrows
          // refs from.
          return ProcessResult(
            1,
            0,
            '/repo/.git/worktrees/lane\n/repo/.git\n',
            '',
          );
        },
      );

      final dirs = await repository.loadGitDirectories();
      expect(dirs?.gitDir, '/repo/.git/worktrees/lane');
      expect(dirs?.commonDir, '/repo/.git');
      expect(calls.single, [
        'rev-parse',
        '--path-format=absolute',
        '--absolute-git-dir',
        '--git-common-dir',
      ]);
    },
  );

  test('loadGitDirectories reports null when git cannot answer', () async {
    expect(
      await GitRepository(
        '/repo',
        runner:
            (executable, arguments, {workingDirectory, environment}) async =>
                ProcessResult(1, 128, '', 'fatal: not a git repository'),
      ).loadGitDirectories(),
      isNull,
    );
    expect(
      await GitRepository(
        '/repo',
        runner:
            (executable, arguments, {workingDirectory, environment}) async =>
                throw const ProcessException('git', []),
      ).loadGitDirectories(),
      isNull,
    );
  });

  test('refWatchPaths covers HEAD, packed refs, and nested loose refs', () {
    // Main worktree: one git dir, so the list must not repeat it.
    expect(refWatchPaths(gitDir: '/repo/.git', commonDir: '/repo/.git'), [
      '/repo/.git',
      '/repo/.git/refs',
    ]);
    // Linked worktree: its own HEAD lives apart from the shared refs.
    expect(
      refWatchPaths(
        gitDir: '/repo/.git/worktrees/lane',
        commonDir: '/repo/.git',
      ),
      ['/repo/.git/worktrees/lane', '/repo/.git', '/repo/.git/refs'],
    );
  });

  test(
    'loadLocalStateSignature fingerprints HEAD and local branches',
    () async {
      final calls = <List<String>>[];
      final repository = GitRepository(
        '/repo',
        runner: (executable, arguments, {workingDirectory, environment}) async {
          calls.add(arguments);
          return ProcessResult(
            1,
            0,
            arguments.contains('--symbolic-full-name')
                ? 'aaa\nrefs/heads/main\n'
                : 'refs/heads/main aaa\n',
            '',
          );
        },
      );

      final signature = await repository.loadLocalStateSignature();
      // Both halves are present: where HEAD points, and every branch tip.
      expect(signature, contains('refs/heads/main'));
      expect(signature, contains('aaa'));
      expect(calls, [
        ['rev-parse', 'HEAD', '--symbolic-full-name', 'HEAD'],
        ['for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads'],
      ]);
    },
  );

  test(
    'a plain checkout changes the signature even with no tip moved',
    () async {
      // for-each-ref never matches HEAD, so a fingerprint built from branch tips
      // alone cannot see a checkout between two existing branches.
      GitRepository repositoryOn(String branch, String sha) => GitRepository(
        '/repo',
        runner:
            (executable, arguments, {workingDirectory, environment}) async =>
                ProcessResult(
                  1,
                  0,
                  arguments.contains('--symbolic-full-name')
                      ? '$sha\n$branch\n'
                      : 'refs/heads/main aaa\nrefs/heads/work bbb\n',
                  '',
                ),
      );

      final onMain = await repositoryOn(
        'refs/heads/main',
        'aaa',
      ).loadLocalStateSignature();
      final onWork = await repositoryOn(
        'refs/heads/work',
        'bbb',
      ).loadLocalStateSignature();
      expect(onMain, isNot(onWork));

      // Two branches on the same commit still differ by name, so switching
      // between them is noticed too.
      final sameCommit = await repositoryOn(
        'refs/heads/work',
        'aaa',
      ).loadLocalStateSignature();
      expect(sameCommit, isNot(onMain));
    },
  );

  test('loadLocalStateSignature reports null when git cannot answer', () async {
    final repository = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 128, '', 'fatal: not a git repository'),
    );

    expect(await repository.loadLocalStateSignature(), isNull);

    final unlaunchable = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          throw const ProcessException('git', [], 'No such file or directory'),
    );

    expect(await unlaunchable.loadLocalStateSignature(), isNull);
  });

  test('loadRecentCommits reads one ref, newest first', () async {
    final repository = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        expect(arguments, [
          'log',
          'dev',
          '-n',
          '3',
          '--format=%H%x00%s%x00%an%x00%ct',
        ]);
        return ProcessResult(
          1,
          0,
          'aaa\x00feat: lane cache\x00sc\x001754500000\n'
              'bbb\x00fix: plan audit\x00jh\x001754400000\n'
              'malformed-line\n'
              'ccc\x00feat: outline\x00mk\x001754300000\n',
          '',
        );
      },
    );

    final commits = await repository.loadRecentCommits('dev', limit: 3);

    expect(commits, hasLength(3));
    expect(commits.first.sha, 'aaa');
    expect(commits.first.subject, 'feat: lane cache');
    expect(commits.first.author, 'sc');
    expect(commits.first.time, 1754500000);
    expect(commits.last.sha, 'ccc');
  });

  test('a detached HEAD reports no current branch', () async {
    final repository = GitRepository(
      '/tmp/repository',
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          switch (arguments.first) {
            'branch' => ProcessResult(1, 0, '\n', ''),
            // A branch whose reflog is gone: the failure stays local to that branch.
            'reflog' => ProcessResult(1, 128, '', 'fatal: no reflog for main'),
            _ => ProcessResult(
              1,
              0,
              'refs/heads/main\x00aaa1\x00\x00\x00\n',
              '',
            ),
          },
    );

    final refs = await repository.loadRefs();

    expect(refs.local, ['main']);
    expect(refs.current, isNull);
    expect(refs.tips, {'main': 'aaa1'});
    expect(refs.birthTimes, isEmpty);
  });

  test('a clean working tree produces no uncommitted row', () async {
    final repository = GitRepository(
      '/tmp/repository',
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 0, '', ''),
    );

    expect(await repository.loadWorkingTree(), isNull);
  });

  test('both sides editing within ten lines reads as one region', () async {
    // 기준은 20번째 줄을, 브랜치는 26번째 줄을 고친다 — 6줄 차이라 한 구역이다.
    final fixture = await _proximityFixture(
      baseEdit: 20,
      compareEdit: 26,
      compareInsertAt: 5,
    );
    addTearDown(() => fixture.delete(recursive: true));

    final comparison = await GitRepository(
      fixture.path,
    ).compareBranches('main', 'feature');

    expect(comparison.merge.status, MergeConflictStatus.clean);
    // 멀리 떨어져 편집한 far.txt는 목록에 없다 — 파일별로 따로 잰다.
    expect(comparison.merge.proximity.keys, ['shared.txt']);
    final regions = comparison.merge.proximity['shared.txt'];
    expect(regions, hasLength(1));
    // 브랜치가 앞쪽에 3줄을 끼워 넣었으니 결과 좌표는 그만큼 밀린다.
    expect(regions!.single, (startLine: 23, endLine: 29));
  });

  test('edits further apart than the threshold form no region', () async {
    final fixture = await _proximityFixture(baseEdit: 20, compareEdit: 40);
    addTearDown(() => fixture.delete(recursive: true));

    final comparison = await GitRepository(
      fixture.path,
    ).compareBranches('main', 'feature');

    expect(comparison.merge.status, MergeConflictStatus.clean);
    expect(comparison.merge.baseChangedFiles, contains('shared.txt'));
    expect(comparison.merge.proximity, isEmpty);
  });

  test('a spaced or Korean filename still gets its region', () async {
    for (final name in ['my file.txt', '설정.txt']) {
      final fixture = await _proximityFixture(
        baseEdit: 20,
        compareEdit: 26,
        sharedName: name,
      );
      addTearDown(() => fixture.delete(recursive: true));

      final comparison = await GitRepository(
        fixture.path,
      ).compareBranches('main', 'feature');

      expect(comparison.merge.proximity[name]?.single, (
        startLine: 20,
        endLine: 26,
      ), reason: name);
    }
  });

  test('an insertion at the top of the file starts the region at 1', () async {
    // 브랜치가 첫 줄 앞에 3줄을 끼워 넣고 기준은 8번째 줄을 고친다. 삽입 hunk의
    // oldStart는 0이지만 0번째 줄을 가리키는 구역은 없다.
    final fixture = await _proximityFixture(
      baseEdit: 8,
      compareEdit: 40,
      compareInsertAt: 0,
    );
    addTearDown(() => fixture.delete(recursive: true));

    final comparison = await GitRepository(
      fixture.path,
    ).compareBranches('main', 'feature');

    expect(comparison.merge.proximity['shared.txt']!.single, (
      startLine: 1,
      endLine: 11,
    ));
  });

  test('an insertion is as close to a later edit as an edit is', () async {
    // 20번째 줄 뒤에 끼워 넣은 줄은 21번째 줄 자리에 앉으니, 31번째 줄 편집과는
    // 10줄 차이로 한 구역이 되고 32번째 줄과는 안 된다.
    for (final (baseEdit, expected) in [(31, 34), (32, null)]) {
      final fixture = await _proximityFixture(
        baseEdit: baseEdit,
        compareEdit: 5,
        compareInsertAt: 20,
      );
      addTearDown(() => fixture.delete(recursive: true));

      final comparison = await GitRepository(
        fixture.path,
      ).compareBranches('main', 'feature');

      expect(
        comparison.merge.proximity['shared.txt']?.single,
        expected == null ? isNull : (startLine: 20, endLine: expected),
        reason: 'base edit at $baseEdit',
      );
    }
  });

  test('a user who turned off diff prefixes still gets regions', () async {
    final fixture = await _proximityFixture(baseEdit: 20, compareEdit: 26);
    addTearDown(() => fixture.delete(recursive: true));
    await _git(fixture, ['config', 'diff.noprefix', 'true']);

    final comparison = await GitRepository(
      fixture.path,
    ).compareBranches('main', 'feature');

    expect(comparison.merge.proximity['shared.txt']!.single, (
      startLine: 20,
      endLine: 26,
    ));
  });

  test('a renamed file measures proximity under its old path', () async {
    final fixture = await _proximityFixture(
      baseEdit: 20,
      compareEdit: 26,
      compareRenameTo: 'moved.txt',
    );
    addTearDown(() => fixture.delete(recursive: true));

    final comparison = await GitRepository(
      fixture.path,
    ).compareBranches('main', 'feature');

    expect(comparison.merge.status, MergeConflictStatus.clean);
    expect(comparison.merge.proximity.keys, ['moved.txt']);
    expect(comparison.merge.proximity['moved.txt']!.single, (
      startLine: 20,
      endLine: 26,
    ));
  });

  test('a shared branch is recommended for a merge commit', () async {
    final fixture = await _remoteBranchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    final comparison = await repository.compareBranches(
      'main',
      'origin/feature',
    );

    final recommendation = await repository.recommendBranchIntegration(
      comparison: comparison,
      rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
    );

    expect(recommendation!.verdict, BranchIntegrationVerdict.merge);
    expect(recommendation.label, 'Merge');
    expect(recommendation.summary, '원격에 공유된 브랜치');
    expect(recommendation.reasons.first, contains('origin/feature'));
  });

  test('a local branch over linear history leans Rebase', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    await _padLinearHistory(fixture.root, conventionSampleFloor);

    final recommendation = await repository.recommendBranchIntegration(
      comparison: await repository.compareBranches('main', 'feature'),
      rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
    );

    expect(recommendation!.verdict, BranchIntegrationVerdict.rebase);
    expect(recommendation.summary, '커밋 1개 · 선형 유지');
    expect(recommendation.reasons.first, '브랜치가 로컬 전용이라 히스토리를 다시 써도 아무도 안 다칩니다');
    expect(recommendation.reasons.last, contains('선형 히스토리가 관례입니다'));
  });

  test('a history too short to hold a convention gets no chip', () async {
    // main의 first-parent 커밋은 둘뿐이다 — 이 표본으로 '관례'를 말할 수는 없다.
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));

    expect(
      await GitRepository(fixture.root.path).recommendBranchIntegration(
        comparison: fixture.comparison,
        rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
      ),
      isNull,
    );
  });

  test('a same-named but unrelated remote branch gets no chip', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    await _padLinearHistory(fixture.root, conventionSampleFloor);
    // 남이 같은 이름으로 만든 브랜치가 원격에 있을 뿐, feature는 올라간 적이 없다.
    await _git(fixture.root, ['remote', 'add', 'origin', '.']);
    await _git(fixture.root, [
      'update-ref',
      'refs/remotes/origin/feature',
      'main',
    ]);

    expect(
      await repository.recommendBranchIntegration(
        comparison: await repository.compareBranches('main', 'feature'),
        rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
      ),
      isNull,
    );
  });

  test(
    'a remote tip the local branch grew from still reads as shared',
    () async {
      final fixture = await _branchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final repository = GitRepository(fixture.root.path);
      await _git(fixture.root, ['remote', 'add', 'origin', '.']);
      await _git(fixture.root, [
        'update-ref',
        'refs/remotes/origin/feature',
        fixture.comparison.compareParent!,
      ]);

      final recommendation = await repository.recommendBranchIntegration(
        comparison: fixture.comparison,
        rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
      );

      expect(recommendation!.verdict, BranchIntegrationVerdict.merge);
      expect(recommendation.reasons.last, contains('커밋 1개가 로컬에 남아 있어도'));
    },
  );

  test('a branch tracking a local branch is not shared with anyone', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    await _padLinearHistory(fixture.root, conventionSampleFloor);
    // 원격이 하나도 없는 저장소에서도 upstream은 로컬 브랜치일 수 있다.
    await _git(fixture.root, ['branch', '--set-upstream-to=main', 'feature']);

    final recommendation = await repository.recommendBranchIntegration(
      comparison: await repository.compareBranches('main', 'feature'),
      rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
    );

    expect(recommendation!.verdict, BranchIntegrationVerdict.rebase);
    expect(recommendation.reasons.first, contains('로컬 전용'));
  });

  test(
    'a branch tracking a remote ref of another name reads as shared',
    () async {
      final fixture = await _branchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final repository = GitRepository(fixture.root.path);
      await _git(fixture.root, ['remote', 'add', 'origin', '.']);
      await _git(fixture.root, [
        'update-ref',
        'refs/remotes/origin/other',
        fixture.comparison.compareTip,
      ]);
      await _git(fixture.root, [
        'branch',
        '--set-upstream-to=origin/other',
        'feature',
      ]);

      final recommendation = await repository.recommendBranchIntegration(
        comparison: fixture.comparison,
        rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
      );

      expect(recommendation!.verdict, BranchIntegrationVerdict.merge);
      expect(recommendation.summary, '원격에 공유된 브랜치');
      expect(recommendation.reasons.first, contains('origin/other'));
    },
  );

  test('an upstream of another name is measured, not assumed', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    await _git(fixture.root, ['remote', 'add', 'origin', '.']);
    // 이름이 다른 upstream도 tip을 직접 재야 안 올라간 커밋을 셀 수 있다.
    await _git(fixture.root, [
      'update-ref',
      'refs/remotes/origin/other',
      fixture.comparison.compareParent!,
    ]);
    await _git(fixture.root, [
      'branch',
      '--set-upstream-to=origin/other',
      'feature',
    ]);

    final recommendation = await repository.recommendBranchIntegration(
      comparison: fixture.comparison,
      rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
    );

    expect(recommendation!.verdict, BranchIntegrationVerdict.merge);
    expect(recommendation.reasons.last, contains('커밋 1개가 로컬에 남아 있어도'));
  });

  test('a merge-bubble repository leans Rebase 후 Merge', () async {
    final fixture = await _mergeBubbleFixture();
    addTearDown(() => fixture.delete(recursive: true));
    final repository = GitRepository(fixture.path);
    final comparison = await repository.compareBranches('main', 'feature');

    final recommendation = await repository.recommendBranchIntegration(
      comparison: comparison,
      rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
    );

    expect(recommendation!.verdict, BranchIntegrationVerdict.rebaseThenMerge);
    expect(recommendation.label, 'Rebase 후 Merge');
    expect(recommendation.summary, '근거 3');
    expect(recommendation.reasons.last, contains('이 저장소의 관례입니다'));
  });

  test('a base branch that never moved gets no recommendation', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    // main을 병합 기점으로 되돌리면 fast-forward라 추천할 게 없다.
    await _git(fixture.root, [
      'reset',
      '--hard',
      fixture.comparison.baseParent!,
    ]);

    expect(
      await repository.recommendBranchIntegration(
        comparison: await repository.compareBranches('main', 'feature'),
        rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
      ),
      isNull,
    );
  });

  test('both previews stopping leaves no recommendation', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    final comparison = await repository.compareBranches('main', 'feature');

    expect(
      await repository.recommendBranchIntegration(
        comparison: _withMerge(
          comparison,
          const MergeConflictCheck(
            status: MergeConflictStatus.conflicts,
            files: ['shared.txt'],
          ),
        ),
        rebaseCheck: const RebaseCheckResult(
          status: RebaseCheckStatus.conflicts,
          files: ['shared.txt'],
        ),
      ),
      isNull,
    );
  });

  test('a failed check on either side leaves no recommendation', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);

    expect(
      await repository.recommendBranchIntegration(
        comparison: fixture.comparison,
        rebaseCheck: const RebaseCheckResult(
          status: RebaseCheckStatus.failed,
          error: 'boom',
        ),
      ),
      isNull,
    );
    // 머지 검사가 실패했으면 멈춘 파일 수를 말할 수 없으니 추천도 없다.
    expect(
      await repository.recommendBranchIntegration(
        comparison: _withMerge(
          fixture.comparison,
          const MergeConflictCheck(
            status: MergeConflictStatus.failed,
            error: 'boom',
          ),
        ),
        rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
      ),
      isNull,
    );
  });

  test(
    'rebase then merge moves both refs and builds the merge commit',
    () async {
      final fixture = await _branchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final repository = GitRepository(fixture.root.path);
      final virtualTip = await _rebasedTip(fixture.root, repository);

      final applied = await repository.applyRebaseThenMerge(
        comparison: fixture.comparison,
        virtualTip: virtualTip,
      );

      expect(applied.mode, BranchApplyMode.rebaseMerge);
      // main만 체크아웃돼 있으니 디스크에 반영되는 쪽도 main뿐이다.
      expect(applied.workingTreeUpdated, isTrue);
      expect(applied.compareWorkingTreeUpdated, isFalse);
      expect(applied.compareAfter, virtualTip);
      expect(
        (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
        virtualTip,
      );
      expect(
        (await _git(fixture.root, [
          'rev-list',
          '--parents',
          '-n',
          '1',
          'main',
        ])).trim().split(' '),
        [applied.baseAfter, fixture.comparison.baseTip, virtualTip],
      );
      // 트리는 재배치 결과 그대로다 — 미리보기 트리 == 적용 트리.
      expect(
        (await _git(fixture.root, ['rev-parse', 'main^{tree}'])).trim(),
        (await _git(fixture.root, ['rev-parse', '$virtualTip^{tree}'])).trim(),
      );
      expect(
        (await _git(fixture.root, ['log', '-1', '--format=%s', 'main'])).trim(),
        "Merge branch 'feature' into main",
      );
      expect(File('${fixture.root.path}/feature.txt').existsSync(), isTrue);

      await repository.restoreBranchApply(applied);

      expect(
        (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
        fixture.comparison.baseTip,
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
        fixture.comparison.compareTip,
      );
      expect(File('${fixture.root.path}/feature.txt').existsSync(), isFalse);
    },
  );

  test('rebase then merge writes the message it was handed', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    final virtualTip = await _rebasedTip(fixture.root, repository);
    const message =
        "Merge branch 'feature' into main\n"
        '\n'
        '재배치한 커밋 위에 얹은 머지입니다.\n'
        'Reviewed-by: 채수원';

    await repository.applyRebaseThenMerge(
      comparison: fixture.comparison,
      virtualTip: virtualTip,
      message: message,
    );

    expect(
      (await _git(fixture.root, ['log', '-1', '--format=%B', 'main'])).trim(),
      message,
    );
  });

  test(
    'rebase then merge onto a branch checked out nowhere only moves refs',
    () async {
      final fixture = await _branchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final repository = GitRepository(fixture.root.path);
      final virtualTip = await _rebasedTip(fixture.root, repository);
      await _git(fixture.root, ['switch', '--detach', 'HEAD']);
      final head = (await _git(fixture.root, ['rev-parse', 'HEAD'])).trim();

      final applied = await repository.applyRebaseThenMerge(
        comparison: fixture.comparison,
        virtualTip: virtualTip,
      );

      expect(applied.workingTreeUpdated, isFalse);
      expect(applied.compareWorkingTreeUpdated, isFalse);
      expect((await _git(fixture.root, ['rev-parse', 'HEAD'])).trim(), head);
      expect(File('${fixture.root.path}/feature.txt').existsSync(), isFalse);
    },
  );

  test(
    'a rebased tip off the base tip is refused before anything moves',
    () async {
      final fixture = await _branchPreviewFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final repository = GitRepository(fixture.root.path);

      await expectLater(
        repository.applyRebaseThenMerge(
          comparison: fixture.comparison,
          // 재배치하지 않은 브랜치는 기준 위에 얹혀 있지 않다.
          virtualTip: fixture.comparison.compareTip,
        ),
        throwsA(
          isA<GitRepositoryException>().having(
            (error) => error.message,
            'message',
            contains('기준 브랜치 위에 없어'),
          ),
        ),
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
        fixture.comparison.compareTip,
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
        fixture.comparison.baseTip,
      );
    },
  );

  test('a rebase with nothing left to replay makes no merge commit', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    // feature의 커밋이 이미 main에 들어가 있으면 재배치 결과가 곧 main이다.
    await _git(fixture.root, ['cherry-pick', 'feature']);
    final comparison = await repository.compareBranches('main', 'feature');
    final session = await repository.openRebasePreview(
      baseRef: 'main',
      compareRef: 'feature',
    );
    final preview = await session.start();
    await session.dispose();
    expect(preview.status, RebasePreviewStatus.clean);
    expect(preview.rewritten, isEmpty);
    expect(preview.virtualTip, comparison.baseTip);

    await expectLater(
      repository.applyRebaseThenMerge(
        comparison: comparison,
        virtualTip: preview.virtualTip!,
      ),
      throwsA(
        isA<GitRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('만들 머지 커밋이 없습니다'),
        ),
      ),
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      comparison.baseTip,
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
      comparison.compareTip,
    );
  });

  test('a branch held by another worktree stops rebase then merge', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    final virtualTip = await _rebasedTip(fixture.root, repository);
    final other = await Directory.systemTemp.createTemp('yogit_worktree_');
    await other.delete();
    await _git(fixture.root, ['worktree', 'add', other.path, 'feature']);
    addTearDown(
      () => _git(fixture.root, ['worktree', 'remove', '--force', other.path]),
    );

    await expectLater(
      repository.applyRebaseThenMerge(
        comparison: fixture.comparison,
        virtualTip: virtualTip,
      ),
      throwsA(isA<GitRepositoryException>()),
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
      fixture.comparison.compareTip,
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
  });

  test('a base branch that cannot move rolls the rebase back', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    final virtualTip = await _rebasedTip(fixture.root, repository);
    // main이 체크아웃된 채 작업 트리가 더러우면 2단계에서 막힌다.
    await File('${fixture.root.path}/base.txt').writeAsString('dirty\n');

    await expectLater(
      repository.applyRebaseThenMerge(
        comparison: fixture.comparison,
        virtualTip: virtualTip,
      ),
      throwsA(isA<GitRepositoryException>()),
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
    // 1단계로 옮긴 브랜치를 되돌려 두 ref 모두 적용 전 상태다.
    expect(
      (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
      fixture.comparison.compareTip,
    );
  });

  test('a dirty tree leaves the two-ref undo entirely undone', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    final virtualTip = await _rebasedTip(fixture.root, repository);
    // feature를 체크아웃해 두면 되돌릴 때 작업 트리를 건드리는 쪽이 feature다.
    await _git(fixture.root, ['switch', 'feature']);
    final applied = await repository.applyRebaseThenMerge(
      comparison: fixture.comparison,
      virtualTip: virtualTip,
    );
    expect(applied.compareWorkingTreeUpdated, isTrue);
    expect(applied.workingTreeUpdated, isFalse);
    await File('${fixture.root.path}/feature.txt').writeAsString('dirty\n');

    await expectLater(
      repository.restoreBranchApply(applied),
      throwsA(
        isA<GitRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('작업 트리와 인덱스가 깨끗해야'),
        ),
      ),
    );
    // 막힐 수 있는 쪽을 먼저 옮기니 한쪽만 되돌아간 상태가 남지 않는다.
    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      applied.baseAfter,
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
      applied.compareAfter,
    );

    // 그래서 트리를 정리하면 다시 시도해 두 ref가 함께 돌아온다.
    await _git(fixture.root, ['checkout', '--', 'feature.txt']);
    await repository.restoreBranchApply(applied);

    expect(
      (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
      fixture.comparison.baseTip,
    );
    expect(
      (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
      fixture.comparison.compareTip,
    );
  });

  test('a half-done undo says which ref moved and where both sit', () async {
    final fixture = await _branchPreviewFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final repository = GitRepository(fixture.root.path);
    final virtualTip = await _rebasedTip(fixture.root, repository);
    final applied = await repository.applyRebaseThenMerge(
      comparison: fixture.comparison,
      virtualTip: virtualTip,
    );
    // 적용한 뒤 다른 worktree가 feature를 잡으면 두 번째 이동만 막힌다.
    final other = await Directory.systemTemp.createTemp('yogit_worktree_');
    await other.delete();
    await _git(fixture.root, ['worktree', 'add', other.path, 'feature']);
    addTearDown(
      () => _git(fixture.root, ['worktree', 'remove', '--force', other.path]),
    );

    await expectLater(
      repository.restoreBranchApply(applied),
      throwsA(
        isA<GitRepositoryException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('main 브랜치는 ${fixture.comparison.baseTip}으로 되돌렸지만'),
            contains('feature 브랜치는 ${applied.compareAfter}에 그대로 있습니다'),
          ),
        ),
      ),
    );
  });

  test('the convention reason outlives a duplicate commit note', () async {
    final fixture = await _mergeBubbleFixture();
    addTearDown(() => fixture.delete(recursive: true));
    final repository = GitRepository(fixture.path);
    // feature의 커밋을 main에 cherry-pick해 두면 중복 근거가 하나 더 붙는다.
    await _git(fixture, ['cherry-pick', 'feature']);

    final recommendation = await repository.recommendBranchIntegration(
      comparison: await repository.compareBranches('main', 'feature'),
      rebaseCheck: const RebaseCheckResult(status: RebaseCheckStatus.clean),
    );

    expect(recommendation!.verdict, BranchIntegrationVerdict.rebaseThenMerge);
    // 판정을 그냥 Rebase와 갈라놓는 근거가 세 개 안에 남는다.
    expect(recommendation.reasons, hasLength(3));
    expect(recommendation.reasons.last, contains('이 저장소의 관례입니다'));
    expect(
      recommendation.reasons.where((reason) => reason.contains('알아서 빠집니다')),
      isEmpty,
    );
  });

  test('a duplicate commit tips a history with no clear convention', () async {
    final fixture = await _mergeBubbleFixture(merges: 2, linear: 8);
    addTearDown(() => fixture.delete(recursive: true));
    final repository = GitRepository(fixture.path);
    const clean = RebaseCheckResult(status: RebaseCheckStatus.clean);
    // 머지 커밋 비율이 어느 쪽 관례도 아니라 이대로는 고를 수 없다.
    expect(
      await repository.recommendBranchIntegration(
        comparison: await repository.compareBranches('main', 'feature'),
        rebaseCheck: clean,
      ),
      isNull,
    );

    await _git(fixture, ['cherry-pick', 'feature']);
    final recommendation = await repository.recommendBranchIntegration(
      comparison: await repository.compareBranches('main', 'feature'),
      rebaseCheck: clean,
    );

    // 재배치가 알아서 떨궈 주는 중복 커밋이 판정을 가른다.
    expect(recommendation!.verdict, BranchIntegrationVerdict.rebase);
    expect(recommendation.reasons.last, contains('알아서 빠집니다'));
  });

  // ── upstream 동기화의 git 층 (docs/upstream-sync-design.md P1) ──────────

  test('pushBranch advances the remote ref to the local tip', () async {
    final fixture = await _upstreamFixture();
    await File('${fixture.root.path}/file.txt').writeAsString('local\n');
    await _git(fixture.root, ['commit', '-am', 'local work']);
    final localTip = (await _git(fixture.root, ['rev-parse', 'main'])).trim();

    final repository = GitRepository(fixture.root.path);
    await repository.pushBranch('origin', 'main');

    expect(
      (await _git(fixture.remote, ['rev-parse', 'main'])).trim(),
      localTip,
      reason: '원격 main이 로컬 끝으로 움직인다',
    );
  });

  test('pushBranch refuses when the remote moved first', () async {
    final fixture = await _upstreamFixture();
    // 다른 사람이 원격을 먼저 움직였다.
    final other = await Directory.systemTemp.createTemp(
      'yogit_upstream_other_',
    );
    addTearDown(() => other.delete(recursive: true));
    await _git(other, ['clone', fixture.remote.path, '.']);
    await _git(other, ['config', 'user.name', 'Other']);
    await _git(other, ['config', 'user.email', 'other@example.com']);
    await File('${other.path}/other.txt').writeAsString('other\n');
    await _git(other, ['add', '.']);
    await _git(other, ['commit', '-m', 'other work']);
    await _git(other, ['push', 'origin', 'main']);
    final remoteTip = (await _git(fixture.remote, [
      'rev-parse',
      'main',
    ])).trim();

    await File('${fixture.root.path}/file.txt').writeAsString('local\n');
    await _git(fixture.root, ['commit', '-am', 'local work']);

    final repository = GitRepository(fixture.root.path);
    await expectLater(
      repository.pushBranch('origin', 'main'),
      throwsA(isA<ProcessException>()),
      reason: 'force 없는 push라 원격이 앞서 있으면 거절된다',
    );
    expect(
      (await _git(fixture.remote, ['rev-parse', 'main'])).trim(),
      remoteTip,
      reason: '거절된 push는 원격을 건드리지 않는다',
    );
  });

  test('pushBranch can create the upstream it will track', () async {
    final fixture = await _upstreamFixture();
    await _git(fixture.root, ['switch', '-c', 'feature']);
    await File('${fixture.root.path}/feature.txt').writeAsString('f\n');
    await _git(fixture.root, ['add', '.']);
    await _git(fixture.root, ['commit', '-m', 'feature work']);

    final repository = GitRepository(fixture.root.path);
    await repository.pushBranch('origin', 'feature', setUpstream: true);

    expect(
      (await _git(fixture.root, [
        'rev-parse',
        '--abbrev-ref',
        'feature@{upstream}',
      ])).trim(),
      'origin/feature',
      reason: 'push -u는 추적까지 연결한다',
    );
  });

  test(
    'a realized rebase moves the ref and leaves the checkout alone',
    () async {
      final fixture = await _divergedUpstreamFixture();
      final repository = GitRepository(fixture.root.path);
      // 기준 브랜치는 체크아웃 밖이다 — 작업 트리는 다른 브랜치의 것.
      await _git(fixture.root, ['switch', '-c', 'elsewhere']);
      await File('${fixture.root.path}/dirty.txt').writeAsString('untouched\n');

      final session = RebasePreviewSession(
        repository: repository,
        baseTip: fixture.remoteTip,
        compareTip: fixture.localTip,
        originalCommits: const [],
      );
      final preview = await session.start();
      await session.dispose();
      expect(preview.status, RebasePreviewStatus.clean);

      final updatedTree = await repository.applyUpstreamRebase(
        branch: 'main',
        expectedTip: fixture.localTip,
        virtualTip: preview.virtualTip!,
      );

      expect(updatedTree, isFalse, reason: '체크아웃 밖 브랜치는 ref만 움직인다');
      expect(
        (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
        preview.virtualTip,
      );
      expect(
        await File('${fixture.root.path}/dirty.txt').readAsString(),
        'untouched\n',
        reason: '작업 트리는 손대지 않는다',
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'main^'])).trim(),
        fixture.remoteTip,
        reason: '로컬 커밋이 원격 끝 위에 얹혀 있다 — 버려진 것이 아니라',
      );
      // 얹힌 뒤에는 force 없이 push가 된다 — 로컬이 원격 끝을 품었으니까.
      await repository.pushBranch('origin', 'main');
      expect(
        (await _git(fixture.remote, ['rev-parse', 'main'])).trim(),
        preview.virtualTip,
      );
    },
  );

  test('pushBranch pinned to a tip sends that tip and nothing newer', () async {
    final fixture = await _upstreamFixture();
    await File('${fixture.root.path}/file.txt').writeAsString('shown\n');
    await _git(fixture.root, ['commit', '-am', 'shown on the receipt']);
    final shownTip = (await _git(fixture.root, ['rev-parse', 'main'])).trim();
    // 확인창이 열린 사이에 커밋이 하나 더 붙었다.
    await File('${fixture.root.path}/file.txt').writeAsString('later\n');
    await _git(fixture.root, ['commit', '-am', 'landed mid-dialog']);

    final repository = GitRepository(fixture.root.path);
    await repository.pushBranch('origin', 'main', fromTip: shownTip);

    expect(
      (await _git(fixture.remote, ['rev-parse', 'main'])).trim(),
      shownTip,
      reason: '영수증이 보인 그 끝까지만 올라간다',
    );
  });

  test("pushBranch sends the branch to the upstream's own name", () async {
    final fixture = await _upstreamFixture();
    // main이 origin/trunk를 추적한다 — 이름이 다른 upstream.
    await _git(fixture.remote, ['branch', 'trunk', 'main']);
    await _git(fixture.root, ['fetch', 'origin']);
    await _git(fixture.root, ['branch', '-u', 'origin/trunk', 'main']);
    await File('${fixture.root.path}/file.txt').writeAsString('local\n');
    await _git(fixture.root, ['commit', '-am', 'local work']);
    final localTip = (await _git(fixture.root, ['rev-parse', 'main'])).trim();
    final mainTip = (await _git(fixture.remote, ['rev-parse', 'main'])).trim();

    final repository = GitRepository(fixture.root.path);
    await repository.pushBranch('origin', 'main', toBranch: 'trunk');

    expect(
      (await _git(fixture.remote, ['rev-parse', 'trunk'])).trim(),
      localTip,
      reason: '잰 그 브랜치로 올라간다',
    );
    expect(
      (await _git(fixture.remote, ['rev-parse', 'main'])).trim(),
      mainTip,
      reason: '이름이 같다는 짐작으로 엉뚱한 브랜치를 만들지 않는다',
    );
  });

  test(
    'a realized rebase stops whole when the branch moved meanwhile',
    () async {
      final fixture = await _divergedUpstreamFixture();
      final repository = GitRepository(fixture.root.path);
      final session = RebasePreviewSession(
        repository: repository,
        baseTip: fixture.remoteTip,
        compareTip: fixture.localTip,
        originalCommits: const [],
      );
      final preview = await session.start();
      await session.dispose();

      // 판정과 실행 사이에 로컬이 또 움직였다.
      await File('${fixture.root.path}/file.txt').writeAsString('newer\n');
      await _git(fixture.root, ['commit', '-am', 'newer work']);
      final movedTip = (await _git(fixture.root, ['rev-parse', 'main'])).trim();

      await expectLater(
        repository.applyUpstreamRebase(
          branch: 'main',
          expectedTip: fixture.localTip,
          virtualTip: preview.virtualTip!,
        ),
        throwsA(isA<GitRepositoryException>()),
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
        movedTip,
        reason: '아무것도 움직이지 않는다',
      );
    },
  );

  test(
    'a dirty checked-out tree refuses the realized rebase, with its reason',
    () async {
      final fixture = await _divergedUpstreamFixture();
      final repository = GitRepository(fixture.root.path);
      final session = RebasePreviewSession(
        repository: repository,
        baseTip: fixture.remoteTip,
        compareTip: fixture.localTip,
        originalCommits: const [],
      );
      final preview = await session.start();
      await session.dispose();

      // main이 체크아웃되어 있고 트리는 더럽다.
      await File(
        '${fixture.root.path}/file.txt',
      ).writeAsString('uncommitted\n');

      await expectLater(
        repository.applyUpstreamRebase(
          branch: 'main',
          expectedTip: fixture.localTip,
          virtualTip: preview.virtualTip!,
        ),
        throwsA(
          isA<GitRepositoryException>().having(
            (error) => error.message,
            'message',
            contains('깨끗해야'),
          ),
        ),
      );
      expect(
        (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
        fixture.localTip,
      );
    },
  );

  test('measureUpstreamRebase answers clean or names the conflict', () async {
    final fixture = await _divergedUpstreamFixture();
    final repository = GitRepository(fixture.root.path);

    final clean = await repository.measureUpstreamRebase(
      remoteTip: fixture.remoteTip,
      localTip: fixture.localTip,
    );
    expect(clean.status, RebasePreviewStatus.clean);
    expect(clean.virtualTip, isNotNull);

    // 같은 파일을 양쪽에서 고치면 재연이 충돌로 답한다.
    await File('${fixture.root.path}/remote.txt').writeAsString('mine\n');
    await _git(fixture.root, ['add', '.']);
    await _git(fixture.root, ['commit', '-m', 'collides with remote work']);
    final conflicted = await repository.measureUpstreamRebase(
      remoteTip: fixture.remoteTip,
      localTip: (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
    );
    expect(conflicted.status, RebasePreviewStatus.conflict);
    expect(conflicted.conflictFiles, ['remote.txt']);
  });

  test('moved commits split into what comes in and what goes up', () async {
    final fixture = await _divergedUpstreamFixture();
    final repository = GitRepository(fixture.root.path);

    final commits = await repository.loadMovedCommits(
      fixture.remoteTip,
      fixture.localTip,
    );

    expect(
      commits.where((commit) => !commit.incoming).map((c) => c.subject),
      ['remote work'],
      reason: '< 쪽은 원격에만 있어 pull로 들어올 커밋',
    );
    expect(
      commits.where((commit) => commit.incoming).map((c) => c.subject),
      ['local work'],
      reason: '> 쪽은 로컬에만 있어 push로 올라갈 커밋',
    );
  });
}

/// The layout invariants every fixture has to satisfy: a column index means the
/// same thing on every row (nothing ever slides), and each transition names one
/// real move into the column its destination sha occupies below that row.
void _expectStableColumns(List<GraphRow> rows) {
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    for (final entry in row.activeLaneShas.entries) {
      if (entry.key == row.lane) continue;
      expect(
        rows[index - 1].nextLaneShas[entry.key],
        entry.value,
        reason: 'column ${entry.key} shifted above ${row.commit.sha}',
      );
    }
    expect(
      row.transitions.toSet(),
      hasLength(row.transitions.length),
      reason: 'duplicate transition on ${row.commit.sha}',
    );
    // A branch id for exactly the occupied columns, and the node's own id.
    expect(
      row.activeLaneBranches.keys.toSet(),
      row.activeLaneShas.keys.toSet(),
      reason: 'entering branch ids on ${row.commit.sha}',
    );
    expect(
      row.nextLaneBranches.keys.toSet(),
      row.nextLaneShas.keys.toSet(),
      reason: 'leaving branch ids on ${row.commit.sha}',
    );
    expect(row.activeLaneBranches[row.lane], row.branch);
    // Each parent entry names the column that parent's own row sits in, not the
    // child's column — the tail of a converging first parent included.
    expect(row.parentLanes, hasLength(row.commit.parents.length));
    for (var at = 0; at < row.commit.parents.length; at++) {
      final parent = rows.where(
        (other) => other.commit.sha == row.commit.parents[at],
      );
      if (parent.isEmpty) continue;
      expect(
        row.parentLanes[at],
        parent.first.lane,
        reason: 'parent $at of ${row.commit.sha}',
      );
    }
    for (final move in row.transitions) {
      expect(move.from, isNot(move.to), reason: '$move');
      expect(row.nextLaneShas[move.to], move.sha, reason: '$move');
      expect(
        move.from == row.lane || row.nextLaneShas.containsKey(move.from),
        isTrue,
        reason: 'transition leaves an empty column: $move',
      );
    }
  }
}

GitCommit _commit(
  String sha,
  List<String> parents, {
  String? subject,
  GitIdentity committer = const GitIdentity(
    name: 'Committer',
    email: 'committer@example.com',
  ),
}) => GitCommit(
  sha: sha,
  shortSha: sha,
  parents: parents,
  author: committer,
  authorTimestamp: 1,
  committer: committer,
  committerTimestamp: 1,
  refs: const [],
  subject: subject ?? sha,
);

GitFileChange _file(String path) =>
    GitFileChange(path: path, status: 'M', additions: null, deletions: null);

/// Rails paint at [CommitGraphPainter.railOpacity] over this background, and a
/// thin stroke only partly covers the pixel it is centred on, so a probe reads a
/// blend rather than the branch color itself.
const _canvasBackground = Color(0xFF15171E);

/// The rasterized pixel is 8 bits per channel, so the blended expectation has
/// to drop to the same precision before comparing.
Color _quantize(Color color) => Color.fromARGB(
  (color.a * 255).round(),
  (color.r * 255).round(),
  (color.g * 255).round(),
  (color.b * 255).round(),
);

Future<Color> _paintPixel(
  CustomPainter painter, {
  required int x,
  required int y,
}) async {
  const size = Size(168, 36);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(Offset.zero & size, Paint()..color = _canvasBackground);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = (y * size.width.toInt() + x) * 4;
  return Color.fromARGB(
    bytes!.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

Future<String> _git(Directory root, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: root.path);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return result.stdout.toString();
}

/// [count] more first-parent commits on the checked-out branch, so a convention
/// measured from this history clears the sample floor.
Future<void> _padLinearHistory(Directory root, int count) async {
  for (var at = 0; at < count; at++) {
    await File('${root.path}/pad$at.txt').writeAsString('pad $at\n');
    await _git(root, ['add', 'pad$at.txt']);
    await _git(root, ['commit', '-m', 'pad $at']);
  }
}

/// The palette-merge shape: two of the four branch commits conflict with the
/// base tip on their own, the other two replay clean.
Future<
  ({
    Directory root,
    String baseTip,
    String compareTip,
    List<String> commits,
    String first,
    String second,
  })
>
_conflictForecastFixture() async {
  final root = await Directory.systemTemp.createTemp('yogit_forecast_');
  await _initRepository(root);
  await File('${root.path}/shared.txt').writeAsString('base\n');
  await File('${root.path}/second.txt').writeAsString('base\n');
  await _git(root, ['add', 'shared.txt', 'second.txt']);
  await _git(root, ['commit', '-m', 'base']);
  await _git(root, ['switch', '-c', 'feature']);
  await File('${root.path}/one.txt').writeAsString('one\n');
  await _git(root, ['add', 'one.txt']);
  await _git(root, ['commit', '-m', 'feature one']);
  final clean = (await _git(root, ['rev-parse', 'HEAD'])).trim();
  await File('${root.path}/shared.txt').writeAsString('feature\n');
  await _git(root, ['commit', '-am', 'feature touches shared']);
  final first = (await _git(root, ['rev-parse', 'HEAD'])).trim();
  await File('${root.path}/two.txt').writeAsString('two\n');
  await _git(root, ['add', 'two.txt']);
  await _git(root, ['commit', '-m', 'feature two']);
  final alsoClean = (await _git(root, ['rev-parse', 'HEAD'])).trim();
  await File('${root.path}/shared.txt').writeAsString('feature again\n');
  await File('${root.path}/second.txt').writeAsString('feature\n');
  await _git(root, ['commit', '-am', 'feature touches both']);
  final second = (await _git(root, ['rev-parse', 'HEAD'])).trim();
  await _git(root, ['switch', 'main']);
  await File('${root.path}/shared.txt').writeAsString('main\n');
  await File('${root.path}/second.txt').writeAsString('main\n');
  await _git(root, ['commit', '-am', 'main touches both']);
  return (
    root: root,
    baseTip: (await _git(root, ['rev-parse', 'HEAD'])).trim(),
    compareTip: second,
    commits: [clean, first, alsoClean, second],
    first: first,
    second: second,
  );
}

/// The forecast's own worktrees still registered with [root], so a test can say
/// the probe cleaned up after itself.
Future<List<String>> _probeWorktrees(Directory root) async => [
  for (final line in (await _git(root, const [
    'worktree',
    'list',
    '--porcelain',
  ])).split('\n'))
    if (line.startsWith('worktree ') && line.contains('yogit_conflict_probe_'))
      line,
];

Future<void> _initRepository(Directory root) async {
  await _git(root, ['init', '-b', 'main']);
  await _git(root, ['config', 'user.name', 'Test User']);
  await _git(root, ['config', 'user.email', 'test@example.com']);
}

Future<({Directory root, BranchComparisonResult comparison})>
_branchPreviewFixture() async {
  final root = await Directory.systemTemp.createTemp(
    'yogit_branch_preview_apply_',
  );
  await _initRepository(root);
  await File('${root.path}/base.txt').writeAsString('base\n');
  await _git(root, ['add', 'base.txt']);
  await _git(root, ['commit', '-m', 'base']);
  await _git(root, ['switch', '-c', 'feature']);
  await File('${root.path}/feature.txt').writeAsString('feature\n');
  await _git(root, ['add', 'feature.txt']);
  await _git(root, ['commit', '-m', 'feature']);
  await _git(root, ['switch', 'main']);
  await File('${root.path}/main.txt').writeAsString('main\n');
  await _git(root, ['add', 'main.txt']);
  await _git(root, ['commit', '-m', 'main']);
  return (
    root: root,
    comparison: await GitRepository(
      root.path,
    ).compareBranches('main', 'feature'),
  );
}

/// A 60 line file both branches edit: the base at [baseEdit], the branch at
/// [compareEdit]. [compareInsertAt] lets the branch also insert three lines
/// higher up, so result coordinates differ from merge-base coordinates. A second
/// both-sides file, far.txt, is always edited far apart, so a scan that leaked
/// one file's hunks into another would show up.
Future<Directory> _proximityFixture({
  required int baseEdit,
  required int compareEdit,
  int? compareInsertAt,
  String? compareRenameTo,
  String sharedName = 'shared.txt',
}) async {
  final root = await Directory.systemTemp.createTemp('yogit_proximity_');
  await _initRepository(root);
  final shared = File('${root.path}/$sharedName');
  final far = File('${root.path}/far.txt');
  String numbered() =>
      '${[for (var at = 1; at <= 60; at++) 'line $at'].join('\n')}\n';
  await shared.writeAsString(numbered());
  await far.writeAsString(numbered());
  await File('${root.path}/base-only.txt').writeAsString('base only\n');
  await _git(root, ['add', '.']);
  await _git(root, ['commit', '-m', 'shared file']);

  await _git(root, ['switch', '-c', 'feature']);
  final branchLines = shared.readAsLinesSync();
  branchLines[compareEdit - 1] = 'branch edit at $compareEdit';
  if (compareInsertAt != null) {
    branchLines.insertAll(compareInsertAt, [
      'inserted a',
      'inserted b',
      'inserted c',
    ]);
  }
  await shared.writeAsString('${branchLines.join('\n')}\n');
  final branchFar = far.readAsLinesSync();
  branchFar[9] = 'branch edit at 10';
  await far.writeAsString('${branchFar.join('\n')}\n');
  if (compareRenameTo != null) {
    await _git(root, ['mv', sharedName, compareRenameTo]);
  }
  await _git(root, ['add', '.']);
  await _git(root, ['commit', '-m', 'branch edit']);

  await _git(root, ['switch', 'main']);
  final baseLines = shared.readAsLinesSync();
  baseLines[baseEdit - 1] = 'base edit at $baseEdit';
  await shared.writeAsString('${baseLines.join('\n')}\n');
  final baseFar = far.readAsLinesSync();
  baseFar[49] = 'base edit at 50';
  await far.writeAsString('${baseFar.join('\n')}\n');
  await File('${root.path}/base-only.txt').writeAsString('base touched it\n');
  await _git(root, ['add', '.']);
  await _git(root, ['commit', '-m', 'base edit']);
  return root;
}

/// A base branch whose recent first-parent history is mostly merge commits, so
/// the measured convention comes out as merge bubbles. [merges] merge bubbles and
/// [linear] plain commits set the measured ratio.
Future<Directory> _mergeBubbleFixture({int merges = 8, int linear = 0}) async {
  final root = await Directory.systemTemp.createTemp('yogit_merge_bubble_');
  await _initRepository(root);
  await File('${root.path}/base.txt').writeAsString('base\n');
  await _git(root, ['add', 'base.txt']);
  await _git(root, ['commit', '-m', 'base']);
  // 관례 판정에는 최소 표본이 있어야 하니 first-parent 커밋이 열 개는 되게 쌓는다.
  for (var round = 0; round < merges; round++) {
    await _git(root, ['switch', '-c', 'topic$round']);
    await File('${root.path}/topic$round.txt').writeAsString('topic $round\n');
    await _git(root, ['add', 'topic$round.txt']);
    await _git(root, ['commit', '-m', 'topic $round']);
    await _git(root, ['switch', 'main']);
    await _git(root, [
      'merge',
      '--no-ff',
      '-m',
      'Merge topic $round',
      'topic$round',
    ]);
    await _git(root, ['branch', '-D', 'topic$round']);
  }
  await _padLinearHistory(root, linear);
  await _git(root, ['switch', '-c', 'feature']);
  await File('${root.path}/feature.txt').writeAsString('feature\n');
  await _git(root, ['add', 'feature.txt']);
  await _git(root, ['commit', '-m', 'feature']);
  await _git(root, ['switch', 'main']);
  await File('${root.path}/main.txt').writeAsString('main\n');
  await _git(root, ['add', 'main.txt']);
  await _git(root, ['commit', '-m', 'main']);
  return root;
}

/// The same comparison with a different merge check, for decision-table cases a
/// fixture cannot produce on its own.
BranchComparisonResult _withMerge(
  BranchComparisonResult comparison,
  MergeConflictCheck merge,
) => BranchComparisonResult(
  baseRef: comparison.baseRef,
  compareRef: comparison.compareRef,
  baseTip: comparison.baseTip,
  compareTip: comparison.compareTip,
  baseParent: comparison.baseParent,
  compareParent: comparison.compareParent,
  mergeBases: comparison.mergeBases,
  commits: comparison.commits,
  files: comparison.files,
  merge: merge,
);

/// The tip a real rebase preview produces for the fixture's branch.
Future<String> _rebasedTip(Directory root, GitRepository repository) async {
  final session = await repository.openRebasePreview(
    baseRef: 'main',
    compareRef: 'feature',
  );
  try {
    final result = await session.start();
    expect(result.status, RebasePreviewStatus.clean);
    return result.virtualTip!;
  } finally {
    await session.dispose();
  }
}

Future<({Directory root, BranchComparisonResult comparison, String remoteTip})>
_remoteBranchPreviewFixture() async {
  final fixture = await _branchPreviewFixture();
  final remoteTip = fixture.comparison.compareTip;
  await _git(fixture.root, ['remote', 'add', 'origin', '.']);
  await _git(fixture.root, [
    'update-ref',
    'refs/remotes/origin/feature',
    remoteTip,
  ]);
  await _git(fixture.root, ['branch', '-D', 'feature']);
  final repository = GitRepository(fixture.root.path);
  return (
    root: fixture.root,
    comparison: await repository.compareBranches('main', 'origin/feature'),
    remoteTip: remoteTip,
  );
}

/// 로컬 하나와 그 upstream이 될 bare 원격 하나. main은 push -u까지 끝나 있다.
Future<({Directory root, Directory remote})> _upstreamFixture() async {
  final remote = await Directory.systemTemp.createTemp('yogit_sync_remote_');
  addTearDown(() => remote.delete(recursive: true));
  await _git(remote, ['init', '--bare', '-b', 'main']);
  final root = await Directory.systemTemp.createTemp('yogit_sync_local_');
  addTearDown(() => root.delete(recursive: true));
  await _initRepository(root);
  await File('${root.path}/file.txt').writeAsString('base\n');
  await _git(root, ['add', '.']);
  await _git(root, ['commit', '-m', 'base']);
  await _git(root, ['remote', 'add', 'origin', remote.path]);
  await _git(root, ['push', '-u', 'origin', 'main']);
  return (root: root, remote: remote);
}

/// 어긋난 상태: 원격에 'remote work' 하나, 로컬에 'local work' 하나. 서로 다른
/// 파일을 건드려 재연은 깨끗하다.
Future<({Directory root, Directory remote, String localTip, String remoteTip})>
_divergedUpstreamFixture() async {
  final fixture = await _upstreamFixture();
  final other = await Directory.systemTemp.createTemp('yogit_sync_other_');
  addTearDown(() => other.delete(recursive: true));
  await _git(other, ['clone', fixture.remote.path, '.']);
  await _git(other, ['config', 'user.name', 'Other']);
  await _git(other, ['config', 'user.email', 'other@example.com']);
  await File('${other.path}/remote.txt').writeAsString('remote\n');
  await _git(other, ['add', '.']);
  await _git(other, ['commit', '-m', 'remote work']);
  await _git(other, ['push', 'origin', 'main']);

  await File('${fixture.root.path}/local.txt').writeAsString('local\n');
  await _git(fixture.root, ['add', '.']);
  await _git(fixture.root, ['commit', '-m', 'local work']);
  await _git(fixture.root, ['fetch', 'origin']);
  return (
    root: fixture.root,
    remote: fixture.remote,
    localTip: (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
    remoteTip: (await _git(fixture.root, ['rev-parse', 'origin/main'])).trim(),
  );
}
