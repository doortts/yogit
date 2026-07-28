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
      runner: (executable, args, {workingDirectory}) async {
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
        runner: (executable, arguments, {workingDirectory}) async {
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
      runner: (executable, arguments, {workingDirectory}) async {
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
        runner: (executable, arguments, {workingDirectory}) async {
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
      runner: (executable, arguments, {workingDirectory}) async {
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
      runner: (executable, arguments, {workingDirectory}) async {
        calls.add(arguments);
        if (arguments.first == 'for-each-ref') {
          return ProcessResult(
            1,
            0,
            'refs/heads/main aaa1\n'
                'refs/heads/feature/x aaa2\n'
                'refs/remotes/origin/HEAD aaa1\n'
                'refs/remotes/origin/main aaa3\n'
                'refs/tags/v0.1.0 aaa4\n',
            '',
          );
        }
        if (arguments.first == 'reflog') {
          // Newest entry first, so the branch was created on the last line.
          return arguments.last.endsWith('/main')
              ? ProcessResult(1, 0, '1700000200\n1700000100\n', '')
              : ProcessResult(1, 0, '', '');
        }
        return ProcessResult(1, 0, 'main\n', '');
      },
    );

    final refs = await repository.loadRefs();

    expect(refs.local, ['main', 'feature/x']);
    expect(refs.remote, ['origin/main']);
    expect(refs.tags, ['v0.1.0']);
    expect(refs.current, 'main');
    // origin/HEAD is an alias, so it contributes neither a name nor a tip.
    expect(refs.tips, {
      'main': 'aaa1',
      'feature/x': 'aaa2',
      'origin/main': 'aaa3',
      'v0.1.0': 'aaa4',
    });
    // Only local branches have a birth time, and an empty reflog just has none.
    expect(refs.birthTimes, {'main': 1700000100});
    expect(calls, [
      [
        'for-each-ref',
        '--format=%(refname) %(objectname)',
        'refs/heads',
        'refs/remotes',
        'refs/tags',
      ],
      ['reflog', 'show', '--format=%ct', 'refs/heads/main'],
      ['reflog', 'show', '--format=%ct', 'refs/heads/feature/x'],
      ['branch', '--show-current'],
    ]);
    // Arguments stay single tokens — only the format string carries a space, and
    // it reaches git as one argument rather than through a shell.
    expect(
      calls
          .expand((arguments) => arguments)
          .where((argument) => !argument.startsWith('--format=')),
      everyElement(isNot(contains(' '))),
    );
  });

  test('a detached HEAD reports no current branch', () async {
    final repository = GitRepository(
      '/tmp/repository',
      runner: (executable, arguments, {workingDirectory}) async =>
          switch (arguments.first) {
            'branch' => ProcessResult(1, 0, '\n', ''),
            // A branch whose reflog is gone: the failure stays local to that branch.
            'reflog' => ProcessResult(1, 128, '', 'fatal: no reflog for main'),
            _ => ProcessResult(1, 0, 'refs/heads/main aaa1\n', ''),
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
      runner: (executable, arguments, {workingDirectory}) async =>
          ProcessResult(1, 0, '', ''),
    );

    expect(await repository.loadWorkingTree(), isNull);
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
  subject: sha,
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

Future<void> _initRepository(Directory root) async {
  await _git(root, ['init', '-b', 'main']);
  await _git(root, ['config', 'user.name', 'Test User']);
  await _git(root, ['config', 'user.email', 'test@example.com']);
}
