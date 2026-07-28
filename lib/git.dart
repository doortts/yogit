import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'full_diff_limits.dart';

typedef CommandRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(executable, arguments, workingDirectory: workingDirectory);

typedef RawCommandRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

Future<ProcessResult> runRawProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final stderr = process.stderr.transform(utf8.decoder).join();
  final stdout = BytesBuilder(copy: false);
  var captured = 0;
  const captureLimit = fullDiffPatchByteLimit + 1;
  await for (final chunk in process.stdout) {
    final remaining = captureLimit - captured;
    if (remaining <= 0) continue;
    final length = min(remaining, chunk.length);
    stdout.add(length == chunk.length ? chunk : chunk.sublist(0, length));
    captured += length;
  }
  final exitCode = await process.exitCode;
  return ProcessResult(process.pid, exitCode, stdout.takeBytes(), await stderr);
}

String resolveExecutable(
  String name, {
  Map<String, String>? environment,
  bool Function(String path)? exists,
}) =>
    resolveOptionalExecutable(name, environment: environment, exists: exists) ??
    name;

String? resolveOptionalExecutable(
  String name, {
  Map<String, String>? environment,
  bool Function(String path)? exists,
}) {
  final env = environment ?? Platform.environment;
  final fileExists = exists ?? isExecutableFile;
  final pathSeparator = Platform.isWindows ? ';' : ':';
  final candidates = <String>[
    for (final directory in (env['PATH'] ?? '').split(pathSeparator))
      if (directory.isNotEmpty) '$directory/$name',
    '/opt/homebrew/bin/$name',
    '/usr/local/bin/$name',
    '/usr/bin/$name',
  ];
  for (final candidate in candidates.toSet()) {
    if (fileExists(candidate)) return candidate;
  }
  return null;
}

bool isExecutableFile(String path) {
  final stat = FileStat.statSync(path);
  return stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0;
}

Future<String> resolveRepositoryRoot(
  String path, {
  String? gitExecutable,
  CommandRunner runner = runProcess,
}) async {
  final executable = gitExecutable ?? resolveExecutable('git');
  final result = await runner(executable, [
    '-C',
    path,
    'rev-parse',
    '--show-toplevel',
  ]);
  final root = result.stdout.toString().trim();
  if (result.exitCode != 0 || root.isEmpty) {
    throw GitRepositoryException(path, result.stderr.toString().trim());
  }
  return root;
}

class GitRepositoryException implements Exception {
  const GitRepositoryException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => message.isEmpty ? path : '$path: $message';
}

enum FullDiffPatchOutputLimitReason { byteLimit, lineLimit }

class FullDiffPatchOutputLimitException implements Exception {
  const FullDiffPatchOutputLimitException(this.path, this.reason);

  final String path;
  final FullDiffPatchOutputLimitReason reason;

  @override
  String toString() => switch (reason) {
    FullDiffPatchOutputLimitReason.byteLimit =>
      '$path: 전체 파일 diff 결과가 처리할 수 있는 크기를 초과했습니다.',
    FullDiffPatchOutputLimitReason.lineLimit =>
      '$path: 전체 파일 diff 결과가 처리할 수 있는 줄 수를 초과했습니다.',
  };
}

class GitIdentity {
  const GitIdentity({required this.name, required this.email});

  final String name;
  final String email;
}

class GitRef {
  const GitRef({required this.name, this.isHead = false, this.isTag = false});

  final String name;
  final bool isHead;
  final bool isTag;
}

class GitCommit {
  const GitCommit({
    required this.sha,
    required this.shortSha,
    required this.parents,
    required this.author,
    required this.authorTimestamp,
    required this.committer,
    required this.committerTimestamp,
    required this.refs,
    required this.subject,
  });

  final String sha;
  final String shortSha;
  final List<String> parents;
  final GitIdentity author;
  final int authorTimestamp;
  final GitIdentity committer;
  final int committerTimestamp;
  final List<GitRef> refs;
  final String subject;

  /// The synthetic newest row: the working directory ahead of `HEAD`.
  bool get isWorkingTree => sha.isEmpty;
}

List<GitCommit> parseGitLog(String output) {
  return output.split('\x1e').where((record) => record.trim().isNotEmpty).map((
    record,
  ) {
    final fields = record.trimLeft().split('\x1f');
    if (fields.length < 11) {
      throw const FormatException('Invalid git log record');
    }
    final sha = fields[0];
    return GitCommit(
      sha: sha,
      shortSha: sha.substring(0, min(7, sha.length)),
      parents: fields[2].trim().isEmpty
          ? const []
          : fields[2].trim().split(RegExp(r'\s+')),
      author: GitIdentity(name: fields[3], email: fields[4]),
      authorTimestamp: int.parse(fields[5]),
      committer: GitIdentity(name: fields[6], email: fields[7]),
      committerTimestamp: int.parse(fields[8]),
      refs: _parseRefs(fields[9]),
      subject: fields[10],
    );
  }).toList();
}

List<GitRef> _parseRefs(String decorations) {
  if (decorations.isEmpty) return const [];
  return decorations.split(', ').map((decoration) {
    if (decoration.startsWith('HEAD -> ')) {
      return GitRef(name: decoration.substring(8), isHead: true);
    }
    if (decoration.startsWith('tag: ')) {
      return GitRef(name: decoration.substring(5), isTag: true);
    }
    return GitRef(name: decoration);
  }).toList();
}

/// A lane change happening across this row's lower half: the rail in [from]
/// sweeps into [to] between this row's center and the next row's center. Covers
/// merge edges (listed on the child's row) and branch lines converging on their
/// first parent (listed on the row *above* the parent). [sha] is the commit
/// occupying [to] below this row.
typedef LaneTransition = ({int from, int to, String sha});

class GraphRow {
  const GraphRow({
    required this.commit,
    required this.lane,
    required this.parentLanes,
    this.activeLanes = const [],
    this.nextLanes = const [],
    this.activeLaneShas = const {},
    this.nextLaneShas = const {},
    this.transitions = const [],
    this.branch = 0,
    this.activeLaneBranches = const {},
    this.nextLaneBranches = const {},
  });

  final GitCommit commit;
  final int lane;

  /// The column each of [commit]'s parents ends up in, in parent order. A parent
  /// that is not in the laid-out list reads as [lane], so its edge draws as this
  /// row's own rail rather than as a sweep to nowhere.
  final List<int> parentLanes;
  final List<int> activeLanes;
  final List<int> nextLanes;
  final Map<int, String> activeLaneShas;
  final Map<int, String> nextLaneShas;
  final List<LaneTransition> transitions;

  /// Stable id of the branch line this row's node sits on. Branch lines are
  /// numbered in birth order top-down, so ids survive page appends. The
  /// palette color of a rail is `palette[branch % palette.length]`.
  final int branch;

  /// Lane → branch-line id for the columns entering/leaving this row.
  final Map<int, int> activeLaneBranches;
  final Map<int, int> nextLaneBranches;

  /// The rightmost column this row touches. Columns are never slid left, so a
  /// row can leave interior columns free and this is not `nextLanes.length - 1`.
  int get maxLane => nextLanes.isEmpty
      ? activeLanes.last
      : max(activeLanes.last, nextLanes.last);
}

/// One graph column, holding the single edge it currently carries. [sha] is the
/// commit the column is waiting for, or null while the column is free, and [row]
/// is where that state began: the row of the commit whose line the column
/// carries, or the last row the column was busy before it went free. One int is
/// all the forbidden-column test in [layoutGraph] needs. [line] is the id of the
/// branch line filling the column, i.e. of this one continuous occupancy.
typedef _Column = ({String? sha, int row, int line});

class _RowBuffer {
  _RowBuffer({
    required this.commit,
    required this.lane,
    required this.branch,
    required this.entering,
    required this.leaving,
    required this.enteringBranches,
    required this.leavingBranches,
    required this.parentLanes,
  });

  final GitCommit commit;
  final int lane;
  final int branch;
  final Map<int, String> entering;
  final Map<int, String> leaving;
  final Map<int, int> enteringBranches;
  final Map<int, int> leavingBranches;
  final List<int> parentLanes;
  final transitions = <LaneTransition>[];
}

/// Column layout following pvigier's straight-branches algorithm
/// (https://pvigier.github.io/2019/05/06/commit-graph-drawing-algorithms.html).
///
/// One top-down pass. A commit takes the column of its leftmost *branch child*
/// (a child whose first parent it is), so a first-parent chain runs straight
/// down one column for its whole life; failing that it reuses the leftmost free
/// column, or opens a new one on the right. Columns never slide, so a
/// pass-through rail is always vertical and a column index means the same thing
/// on every row.
///
/// A merge edge leaves its child horizontally and then drops vertically in the
/// *parent's* column — which is only chosen when the parent is reached. So the
/// parent may not take a column that carried anything else between its topmost
/// merge child and its own row (pvigier's forbidden set), and the rows in
/// between get that vertical filled in after the fact. Together with
/// convergences, which belong to the row above the commit they sweep into
/// because the painter splits a transition across two rows, that is why rows are
/// buffered here and materialized at the end.
///
/// When a preferred tip is known, column 0 is reserved for it. An edge to that
/// tip can therefore be materialized as soon as its child is placed instead of
/// waiting for the tip row; short and extended pages then share the same
/// transition and line identity.
///
/// Every continuous occupancy of a column is one branch line and gets an id in
/// birth order, so a first-parent chain keeps one id for its whole life and
/// colors uniformly. Ids only ever come from placements already made, so
/// appending a page never renumbers the rows above it.
List<GraphRow> layoutGraph(List<GitCommit> commits, {String? preferredTip}) {
  final columns = <_Column>[
    if (preferredTip != null) (sha: null, row: -1, line: -1),
  ];
  var preferredStarted = false;
  final mergeChildRows = <String, List<int>>{};
  final rows = <_RowBuffer>[];
  var lines = 0;

  for (var index = 0; index < commits.length; index++) {
    final commit = commits[index];
    final mergeChildren = mergeChildRows[commit.sha] ?? const <int>[];
    // The merge edges below drop through this commit's column, so the column has
    // to be clear from the topmost merge child down to here.
    final span = mergeChildren.isEmpty ? index : mergeChildren.first;
    bool clear(int column) {
      final state = columns[column];
      // A line already waiting for this very commit is no obstacle — it ends
      // here — but only from its own commit's row down: above that row the
      // column carries something else, or that commit's node itself.
      return state.sha == null
          ? state.row < span
          : state.sha == commit.sha && state.row <= span;
    }

    final workingTreeStartsPreferred =
        !preferredStarted &&
        index == 0 &&
        commit.sha.isEmpty &&
        commit.parents.isNotEmpty &&
        commit.parents.first == preferredTip;
    final startsPreferred =
        !preferredStarted &&
        (commit.sha == preferredTip || workingTreeStartsPreferred);
    final firstCandidate =
        preferredTip != null && !preferredStarted && !startsPreferred ? 1 : 0;

    var lane = startsPreferred ? 0 : -1;
    if (startsPreferred) preferredStarted = true;
    for (
      var column = firstCandidate;
      column < columns.length && lane < 0;
      column++
    ) {
      if (columns[column].sha == commit.sha && clear(column)) lane = column;
    }
    for (
      var column = firstCandidate;
      column < columns.length && lane < 0;
      column++
    ) {
      if (columns[column].sha == null && clear(column)) lane = column;
    }
    if (lane < 0) {
      lane = columns.length;
      columns.add((sha: null, row: -1, line: -1));
    }
    // Taking over a column continues its line; a fresh or reused one is a birth.
    final branch = columns[lane].sha == commit.sha
        ? columns[lane].line
        : lines++;

    // Every other line waiting for this commit converges into its column. The
    // sweep is drawn from the row above, so the column is busy up to there.
    for (var column = 0; column < columns.length; column++) {
      if (column == lane || columns[column].sha != commit.sha) continue;
      // That line was opened by a child expecting its first parent in its own
      // column; the parent landed here instead, so the child has to say so.
      rows[columns[column].row].parentLanes[0] = lane;
      columns[column] = (sha: null, row: index - 1, line: -1);
      rows[index - 1].transitions.add((
        from: column,
        to: lane,
        sha: commit.sha,
      ));
    }

    final entering = {
      for (var column = 0; column < columns.length; column++)
        column: ?columns[column].sha,
      lane: commit.sha,
    };
    final enteringBranches = {
      for (var column = 0; column < columns.length; column++)
        if (columns[column].sha != null) column: columns[column].line,
      lane: branch,
    };
    // The column now carries this commit's own line, starting at its node.
    columns[lane] = commit.parents.isEmpty
        ? (sha: null, row: index, line: -1)
        : (sha: commit.parents.first, row: index, line: branch);
    final preferredParent = preferredTip != null && !preferredStarted
        ? commit.parents.indexOf(preferredTip)
        : -1;
    if (preferredParent >= 0) {
      if (preferredParent == 0) {
        columns[lane] = (sha: null, row: index, line: -1);
      }
      if (columns[0].sha == null) {
        columns[0] = (sha: preferredTip, row: index, line: lines++);
      }
    }
    final parentLanes = [for (final _ in commit.parents) lane];
    if (preferredParent >= 0) parentLanes[preferredParent] = 0;
    rows.add(
      _RowBuffer(
        commit: commit,
        lane: lane,
        branch: branch,
        entering: entering,
        leaving: {
          for (var column = 0; column < columns.length; column++)
            column: ?columns[column].sha,
        },
        enteringBranches: enteringBranches,
        leavingBranches: {
          for (var column = 0; column < columns.length; column++)
            if (columns[column].sha != null) column: columns[column].line,
        },
        // One entry per parent. Both a first parent continuing this column and a
        // parent that never loads read as this row's own lane; the entry is
        // patched to the parent's real column when the parent is placed.
        parentLanes: parentLanes,
      ),
    );
    if (preferredParent >= 0 && lane != 0) {
      rows.last.transitions.add((from: lane, to: 0, sha: preferredTip!));
    }

    // Ordinary merge edges waiting above only learn their column here.
    for (final child in mergeChildren) {
      for (var row = child; row < index; row++) {
        rows[row].leaving[lane] = commit.sha;
        rows[row].leavingBranches[lane] = branch;
        if (row > child) {
          rows[row].entering[lane] = commit.sha;
          rows[row].enteringBranches[lane] = branch;
        }
      }
      // Merge parents are never the first, so the search starts past it.
      final parent = rows[child].commit.parents.indexOf(commit.sha, 1);
      rows[child].parentLanes[parent] = lane;
      if (rows[child].lane != lane) {
        rows[child].transitions.add((
          from: rows[child].lane,
          to: lane,
          sha: commit.sha,
        ));
      }
    }
    for (final parent in commit.parents.skip(1)) {
      if (parent == preferredTip) continue;
      final children = mergeChildRows[parent] ??= [];
      if (children.isEmpty || children.last != index) children.add(index);
    }
  }

  return [
    for (final row in rows)
      GraphRow(
        commit: row.commit,
        lane: row.lane,
        parentLanes: row.parentLanes,
        activeLanes: row.entering.keys.toList()..sort(),
        nextLanes: row.leaving.keys.toList()..sort(),
        activeLaneShas: row.entering,
        nextLaneShas: row.leaving,
        branch: row.branch,
        activeLaneBranches: row.enteringBranches,
        nextLaneBranches: row.leavingBranches,
        transitions: row.transitions,
      ),
  ];
}

enum DiffLineKind { header, hunk, context, add, delete }

class DiffLine {
  const DiffLine({
    required this.kind,
    required this.text,
    this.oldNumber,
    this.newNumber,
  });

  final DiffLineKind kind;
  final String text;
  final int? oldNumber;
  final int? newNumber;
}

class GitBlameLine {
  const GitBlameLine({
    required this.lineNumber,
    required this.sha,
    required this.author,
    required this.uncommitted,
    this.authorEmail = '',
    this.authorTimestamp,
    this.summary = '',
  });

  final int lineNumber;
  final String sha;
  final String author;
  final String authorEmail;
  final int? authorTimestamp;
  final String summary;
  final bool uncommitted;
}

List<DiffLine> parseUnifiedDiff(String diff) {
  final lines = <DiffLine>[];
  int? oldLine;
  int? newLine;
  final hunk = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');

  for (final line in diff.split('\n')) {
    final match = hunk.firstMatch(line);
    if (match != null) {
      oldLine = int.parse(match.group(1)!);
      newLine = int.parse(match.group(2)!);
      lines.add(DiffLine(kind: DiffLineKind.hunk, text: line));
      continue;
    }
    if (oldLine == null || newLine == null) {
      if (line.isNotEmpty) {
        lines.add(DiffLine(kind: DiffLineKind.header, text: line));
      }
      continue;
    }
    if (line.startsWith(' ')) {
      lines.add(
        DiffLine(
          kind: DiffLineKind.context,
          text: line.substring(1),
          oldNumber: oldLine++,
          newNumber: newLine++,
        ),
      );
    } else if (line.startsWith('-')) {
      lines.add(
        DiffLine(
          kind: DiffLineKind.delete,
          text: line.substring(1),
          oldNumber: oldLine++,
        ),
      );
    } else if (line.startsWith('+')) {
      lines.add(
        DiffLine(
          kind: DiffLineKind.add,
          text: line.substring(1),
          newNumber: newLine++,
        ),
      );
    } else if (line.isNotEmpty) {
      lines.add(DiffLine(kind: DiffLineKind.header, text: line));
    }
  }
  return lines;
}

class DiffPair {
  const DiffPair({this.left, this.right});

  final DiffLine? left;
  final DiffLine? right;
}

List<DiffPair> pairDiff(List<DiffLine> lines) {
  final pairs = <DiffPair>[];
  var index = 0;
  while (index < lines.length) {
    if (lines[index].kind == DiffLineKind.delete) {
      final deletes = <DiffLine>[];
      final adds = <DiffLine>[];
      while (index < lines.length && lines[index].kind == DiffLineKind.delete) {
        deletes.add(lines[index++]);
      }
      while (index < lines.length && lines[index].kind == DiffLineKind.add) {
        adds.add(lines[index++]);
      }
      for (var pair = 0; pair < max(deletes.length, adds.length); pair++) {
        pairs.add(
          DiffPair(
            left: pair < deletes.length ? deletes[pair] : null,
            right: pair < adds.length ? adds[pair] : null,
          ),
        );
      }
      continue;
    }
    final line = lines[index++];
    pairs.add(
      line.kind == DiffLineKind.add
          ? DiffPair(right: line)
          : DiffPair(left: line, right: line),
    );
  }
  return pairs;
}

enum DiffScope { hunks, fullFile }

enum DiffAlgorithm { gitSetting, myers, minimal, patience, histogram }

extension DiffAlgorithmArguments on DiffAlgorithm {
  String get label => switch (this) {
    DiffAlgorithm.gitSetting => 'Git setting',
    DiffAlgorithm.myers => 'Myers',
    DiffAlgorithm.minimal => 'Minimal',
    DiffAlgorithm.patience => 'Patience',
    DiffAlgorithm.histogram => 'Histogram',
  };

  String get tooltip => switch (this) {
    DiffAlgorithm.gitSetting => 'Use Git’s configured diff algorithm.',
    DiffAlgorithm.myers => 'Use Git’s standard greedy diff algorithm.',
    DiffAlgorithm.minimal => 'Spend extra time to produce the smallest diff.',
    DiffAlgorithm.patience => 'Anchor changes on unique matching lines.',
    DiffAlgorithm.histogram => 'Match low-frequency lines for clearer diffs.',
  };

  List<String> get gitArguments => switch (this) {
    DiffAlgorithm.gitSetting => const [],
    DiffAlgorithm.myers => const ['--diff-algorithm=myers'],
    DiffAlgorithm.minimal => const ['--diff-algorithm=minimal'],
    DiffAlgorithm.patience => const ['--diff-algorithm=patience'],
    DiffAlgorithm.histogram => const ['--diff-algorithm=histogram'],
  };

  String get status =>
      gitArguments.isEmpty ? 'Git setting (no option)' : gitArguments.single;
}

class GitFileChange {
  const GitFileChange({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
    this.oldPath,
    this.isBinary = false,
    this.sizeBytes,
  });

  final String path;
  final String? oldPath;
  final String status;
  final int? additions;
  final int? deletions;
  final bool isBinary;
  final int? sizeBytes;
}

class GitFileHistoryRecord {
  const GitFileHistoryRecord({
    required this.commit,
    required this.path,
    required this.oldPath,
    required this.status,
  });

  final GitCommit commit;
  final String path;
  final String? oldPath;
  final String status;
}

class RepoRefs {
  const RepoRefs({
    this.local = const [],
    this.remote = const [],
    this.tags = const [],
    this.current,
    this.tips = const {},
    this.birthTimes = const {},
  });

  final List<String> local;
  final List<String> remote;
  final List<String> tags;
  final String? current;

  /// Local branch name → creation unix time, read from the branch's oldest
  /// reflog entry. Absent when the reflog no longer records the birth.
  final Map<String, int> birthTimes;

  /// Short ref name → tip commit sha, for every entry in the three lists.
  final Map<String, String> tips;
}

String? resolveBaseBranch(RepoRefs refs, String? savedBranch) {
  if (savedBranch != null && refs.local.contains(savedBranch)) {
    return savedBranch;
  }
  final current = refs.current;
  if (current != null && refs.local.contains(current)) return current;
  return refs.local.isEmpty ? null : refs.local.first;
}

abstract interface class FullDiffRepository {
  String get root;

  Future<List<GitFileChange>> loadFiles(GitCommit commit, {String? parent});

  Future<List<DiffLine>> loadDiff(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
    bool ignoreWhitespace = false,
    DiffScope scope = DiffScope.hunks,
  });

  Future<Uint8List> loadFileBytes(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
  });

  Future<List<GitBlameLine>> loadBlame(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    Uint8List? workingTreeBytes,
  });

  Future<List<GitFileHistoryRecord>> loadFileHistory(
    GitCommit commit,
    GitFileChange file,
  );
}

const safeDiffArguments = <String>[
  '--no-ext-diff',
  '--no-textconv',
  '--no-color',
  '--find-renames=50%',
];

List<String> pathspecsFor(GitFileChange file) => [?file.oldPath, file.path];

class GitRepository implements FullDiffRepository {
  GitRepository(
    this.root, {
    this.gitExecutable = 'git',
    CommandRunner? runner,
    RawCommandRunner? rawRunner,
  }) : runner = runner ?? runProcess,
       rawRunner = rawRunner ?? runRawProcess,
       _diffRunner = rawRunner ?? runRawProcess;

  @override
  final String root;
  final String gitExecutable;
  final CommandRunner runner;
  final RawCommandRunner rawRunner;
  final RawCommandRunner _diffRunner;
  Future<String>? _emptyTree;
  Future<List<String>>? _startingRevisions;
  final _untrackedFiles = Expando<bool>();

  Future<List<GitCommit>> loadHistory({int limit = 500, int skip = 0}) async {
    final revisions = await (_startingRevisions ??= _loadStartingRevisions());
    if (revisions.isEmpty) return const [];
    final args = [
      'log',
      '--topo-order',
      '--date-order',
      '--max-count=$limit',
      '--skip=$skip',
      '--format=%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%cn%x1f%ce%x1f%ct%x1f%D%x1f%s%x1e',
      ...revisions,
    ];
    return parseGitLog(await _run(args));
  }

  Future<List<String>> _loadStartingRevisions() async => (await _run([
    'rev-parse',
    '--revs-only',
    'HEAD',
    '--all',
  ])).split(RegExp(r'\s+')).where((value) => value.isNotEmpty).toSet().toList();

  /// The uncommitted working directory as the newest row, or `null` when clean.
  Future<GitCommit?> loadWorkingTree() async {
    if ((await _run(['status', '--porcelain'])).trim().isEmpty) return null;
    final head = (await _run(['rev-parse', '--revs-only', 'HEAD'])).trim();
    return GitCommit(
      sha: '',
      shortSha: '',
      parents: head.isEmpty ? const [] : [head],
      author: const GitIdentity(name: '', email: ''),
      authorTimestamp: 0,
      committer: const GitIdentity(name: '', email: ''),
      committerTimestamp: 0,
      refs: const [],
      subject: 'Uncommitted changes',
    );
  }

  @override
  Future<List<GitFileChange>> loadFiles(
    GitCommit commit, {
    String? parent,
  }) async {
    final revisions = await _revisionsFor(commit, parent);
    final statuses = _parseNameStatus(
      await _run([
        'diff',
        ...safeDiffArguments,
        '--name-status',
        '-z',
        ...revisions,
        '--',
      ]),
    );
    final stats = _parseNumstat(
      await _run([
        'diff',
        ...safeDiffArguments,
        '--numstat',
        '-z',
        ...revisions,
        '--',
      ]),
    );
    final files = [
      for (final status in statuses)
        GitFileChange(
          path: status.path,
          oldPath: status.oldPath,
          status: status.status,
          additions: stats[status.path]?.additions,
          deletions: stats[status.path]?.deletions,
          isBinary: stats[status.path]?.isBinary ?? false,
        ),
    ];
    if (commit.isWorkingTree) {
      final existing = {for (final file in files) file.path};
      final untracked = (await _run([
        'ls-files',
        '--others',
        '--exclude-standard',
        '-z',
      ])).split('\x00').where((path) => path.isNotEmpty);
      for (final path in untracked) {
        if (existing.add(path)) {
          final file = GitFileChange(
            path: path,
            status: 'A',
            additions: null,
            deletions: null,
          );
          _untrackedFiles[file] = true;
          files.add(file);
        }
      }
    }
    return _withFileSizes(commit, files, parent: parent);
  }

  Future<List<GitFileChange>> _withFileSizes(
    GitCommit commit,
    List<GitFileChange> files, {
    required String? parent,
  }) async {
    final sizes = <GitFileChange, int?>{};
    if (commit.isWorkingTree) {
      for (final file in files) {
        if (!file.status.startsWith('D')) {
          sizes[file] = await _worktreeFileSize(file.path);
        }
      }
    } else {
      final resultFiles = files.where((file) => !file.status.startsWith('D'));
      final resultSizes = await _loadLsTreeSizes(
        commit.sha,
        resultFiles.map((file) => file.path),
      );
      for (final file in resultFiles) {
        sizes[file] = resultSizes[file.path];
      }
    }

    final deletedFiles = files
        .where((file) => file.status.startsWith('D'))
        .toList();
    final deletedPaths = {
      for (final file in deletedFiles) file: file.oldPath ?? file.path,
    };
    if (deletedPaths.isNotEmpty) {
      final deletedSizes = await _loadLsTreeSizes(
        await _baseFor(commit, parent),
        deletedPaths.values,
      );
      for (final entry in deletedPaths.entries) {
        sizes[entry.key] = deletedSizes[entry.value];
      }
    }

    return [for (final file in files) _copyWithSize(file, sizes[file])];
  }

  Future<int?> _worktreeFileSize(String path) async {
    final absolutePath = '$root/$path';
    try {
      final type = await FileSystemEntity.type(
        absolutePath,
        followLinks: false,
      );
      return switch (type) {
        FileSystemEntityType.file => (await FileStat.stat(absolutePath)).size,
        FileSystemEntityType.link =>
          utf8.encode(await Link(absolutePath).target()).length,
        _ => null,
      };
    } on FileSystemException {
      return null;
    }
  }

  Future<Map<String, int>> _loadLsTreeSizes(
    String revision,
    Iterable<String> paths,
  ) async {
    final pathList = paths.toList();
    if (pathList.isEmpty) return const {};
    try {
      return _parseLsTreeSizes(
        await _run([
          'ls-tree',
          '-rlz',
          revision,
          '--',
          ...pathList.map((path) => ':(literal)$path'),
        ]),
      );
    } on ProcessException {
      return const {};
    }
  }

  GitFileChange _copyWithSize(GitFileChange file, int? sizeBytes) {
    final copy = GitFileChange(
      path: file.path,
      oldPath: file.oldPath,
      status: file.status,
      additions: file.additions,
      deletions: file.deletions,
      isBinary: file.isBinary,
      sizeBytes: sizeBytes,
    );
    if (_untrackedFiles[file] ?? false) _untrackedFiles[copy] = true;
    return copy;
  }

  @override
  Future<List<DiffLine>> loadDiff(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
    bool ignoreWhitespace = false,
    DiffScope scope = DiffScope.hunks,
  }) async {
    if (commit.isWorkingTree && (_untrackedFiles[file] ?? false)) {
      final snapshot = await _readWorktreeSnapshot(file.path);
      return snapshot.exceeded
          ? const <DiffLine>[]
          : _untrackedDiff(snapshot.bytes);
    }
    final args = [
      'diff',
      ...safeDiffArguments,
      '--unified=${scope == DiffScope.hunks ? 3 : fullDiffTextLineLimit}',
      if (ignoreWhitespace) '--ignore-all-space',
      ...algorithm.gitArguments,
      ...await _revisionsFor(commit, parent),
      '--',
      ...pathspecsFor(file),
    ];
    if (scope == DiffScope.hunks) {
      return parseUnifiedDiff(await _run(args));
    }
    final output = await _runDiff(args);
    return parseUnifiedDiff(output);
  }

  @override
  Future<Uint8List> loadFileBytes(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
  }) async {
    final deleted = file.status.startsWith('D');
    if (commit.isWorkingTree && !deleted) {
      return (await _readWorktreeSnapshot(file.path)).bytes;
    }
    final revision = deleted ? await _baseFor(commit, parent) : commit.sha;
    final path = deleted ? file.oldPath ?? file.path : file.path;
    return loadBlobBytes(revision, path);
  }

  @override
  Future<List<GitBlameLine>> loadBlame(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    Uint8List? workingTreeBytes,
  }) async {
    if (commit.isWorkingTree &&
        ((_untrackedFiles[file] ?? false) || file.status.startsWith('A'))) {
      final before = await _readWorktreeSnapshot(file.path);
      final expected = workingTreeBytes == null
          ? before
          : _snapshotForBytes(workingTreeBytes);
      _verifyWorktreeSnapshot(before, expected);
      final blame = _uncommittedBlame(expected.bytes);
      _verifyWorktreeSnapshot(await _readWorktreeSnapshot(file.path), expected);
      return blame;
    }

    final base = await _baseFor(commit, parent);
    if (commit.isWorkingTree && !file.status.startsWith('D')) {
      final expected = workingTreeBytes;
      if (expected == null) {
        throw StateError('Working tree bytes are required');
      }
      final expectedSnapshot = _snapshotForBytes(expected);
      _verifyWorktreeSnapshot(
        await _readWorktreeSnapshot(file.path),
        expectedSnapshot,
      );
      final contentsDirectory = await Directory.systemTemp.createTemp(
        'yogit_blame_',
      );
      final contents = File('${contentsDirectory.path}/contents');
      late final String output;
      try {
        await contents.writeAsBytes(expectedSnapshot.bytes, flush: true);
        output = await _run(
          blameArguments(
            commit: commit,
            file: file,
            base: base,
            contentsPath: contents.path,
          ),
        );
      } finally {
        await contentsDirectory.delete(recursive: true);
      }
      _verifyWorktreeSnapshot(
        await _readWorktreeSnapshot(file.path),
        expectedSnapshot,
      );
      return _parseBlamePorcelain(output);
    }

    return _parseBlamePorcelain(
      await _run(blameArguments(commit: commit, file: file, base: base)),
    );
  }

  Future<_WorktreeSnapshot> _readWorktreeSnapshot(String path) async {
    final absolutePath = '$root/$path';
    final type = await FileSystemEntity.type(absolutePath, followLinks: false);
    if (type == FileSystemEntityType.link) {
      return (
        bytes: Uint8List.fromList(
          utf8.encode(await Link(absolutePath).target()),
        ),
        exceeded: false,
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in File(
      absolutePath,
    ).openRead(0, fullDiffTextByteLimit + 1)) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    return (bytes: bytes, exceeded: bytes.length > fullDiffTextByteLimit);
  }

  @override
  Future<List<GitFileHistoryRecord>> loadFileHistory(
    GitCommit commit,
    GitFileChange file,
  ) async {
    return _parseFileHistory(
      await _run([
        'log',
        '--follow',
        '--find-renames=50%',
        '--date-order',
        '--format=%x1e%H%x00%h%x00%P%x00%an%x00%ae%x00%at%x00%cn%x00%ce%x00%ct%x00%s%x00',
        '--name-status',
        '-z',
        commit.isWorkingTree ? 'HEAD' : commit.sha,
        '--',
        commit.isWorkingTree && file.status.startsWith('R')
            ? file.oldPath ?? file.path
            : file.path,
      ]),
    );
  }

  Future<Uint8List> loadBlobBytes(String revision, String path) async {
    final object = '$revision:$path';
    final sizeOutput = await _run(['cat-file', '-s', object]);
    final size = int.tryParse(sizeOutput.trim());
    if (size == null) {
      throw FormatException('Invalid blob size: ${sizeOutput.trim()}');
    }
    if (size > fullDiffTextByteLimit) {
      return Uint8List(fullDiffTextByteLimit + 1)
        ..fillRange(0, fullDiffTextByteLimit + 1, 0x20);
    }
    final result = await rawRunner(gitExecutable, [
      'show',
      object,
    ], workingDirectory: root);
    if (result.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        ['show', '$revision:$path'],
        result.stderr.toString(),
        result.exitCode,
      );
    }
    final bytes = result.stdout as List<int>;
    final boundedLength = min(bytes.length, fullDiffTextByteLimit + 1);
    if (bytes is Uint8List) {
      return boundedLength == bytes.length
          ? bytes
          : Uint8List.sublistView(bytes, 0, boundedLength);
    }
    return Uint8List.fromList(bytes.sublist(0, boundedLength));
  }

  /// Sidebar data: local branches, remote branches, and tags, plus the
  /// currently checked-out branch (null when detached) and each ref's tip sha,
  /// which is what decides the row a branch or tag chip belongs on.
  Future<RepoRefs> loadRefs() async {
    final lines = (await _run([
      'for-each-ref',
      '--format=%(refname) %(objectname)',
      'refs/heads',
      'refs/remotes',
      'refs/tags',
    ])).split('\n').where((line) => line.isNotEmpty);
    final local = <String>[];
    final remote = <String>[];
    final tags = <String>[];
    final tips = <String, String>{};
    final buckets = {
      'refs/heads/': local,
      'refs/remotes/': remote,
      'refs/tags/': tags,
    };
    for (final line in lines) {
      // A ref name cannot contain a space, so the split is exactly two fields.
      final [name, sha] = line.split(' ');
      for (final bucket in buckets.entries) {
        if (!name.startsWith(bucket.key)) continue;
        final short = name.substring(bucket.key.length);
        // `origin/HEAD` is an alias for another branch, not a branch of its own.
        if (bucket.value == remote && short.endsWith('/HEAD')) break;
        bucket.value.add(short);
        tips[short] = sha;
        break;
      }
    }
    final births = await Future.wait(local.map(_birthTime));
    final current = (await _run(['branch', '--show-current'])).trim();
    return RepoRefs(
      local: local,
      remote: remote,
      tags: tags,
      current: current.isEmpty ? null : current,
      tips: tips,
      birthTimes: {
        for (var index = 0; index < local.length; index++)
          local[index]: ?births[index],
      },
    );
  }

  /// When a branch was created: the timestamp of its oldest reflog entry, which
  /// `git reflog show` prints last. Null when the reflog cannot tell us — pruned,
  /// never enabled, or the ref is gone — which is not an error worth failing the
  /// whole sidebar over.
  Future<int?> _birthTime(String branch) async {
    try {
      final entries = (await _run([
        'reflog',
        'show',
        '--format=%ct',
        'refs/heads/$branch',
      ])).trim().split('\n');
      return int.tryParse(entries.last.trim());
    } on ProcessException {
      return null;
    }
  }

  Future<String?> loadOriginUrl() async {
    try {
      final value = (await _run(['remote', 'get-url', 'origin'])).trim();
      return value.isEmpty ? null : value;
    } on ProcessException {
      return null;
    }
  }

  /// The working tree row compares its base against the checkout, so it passes
  /// the base alone and lets `git diff` read the working directory.
  Future<List<String>> _revisionsFor(GitCommit commit, String? parent) async {
    final base = await _baseFor(commit, parent);
    return commit.isWorkingTree ? [base] : [base, commit.sha];
  }

  Future<String> _baseFor(GitCommit commit, String? parent) async =>
      parent ??
      (commit.parents.isEmpty
          ? await (_emptyTree ??= _loadEmptyTree())
          : commit.parents.first);

  Future<String> _loadEmptyTree() async =>
      (await _run(['hash-object', '-t', 'tree', '/dev/null'])).trim();

  Future<String> _run(List<String> args) async {
    final result = await runner(gitExecutable, args, workingDirectory: root);
    if (result.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        args,
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return result.stdout.toString();
  }

  Future<String> _runDiff(List<String> args) async {
    final result = await _diffRunner(
      gitExecutable,
      args,
      workingDirectory: root,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        args,
        result.stderr.toString(),
        result.exitCode,
      );
    }
    final stdout = result.stdout;
    final bytes = stdout is String
        ? utf8.encode(stdout)
        : stdout is List<int>
        ? stdout
        : utf8.encode(stdout.toString());
    if (bytes.length > fullDiffPatchByteLimit) {
      throw FullDiffPatchOutputLimitException(
        root,
        FullDiffPatchOutputLimitReason.byteLimit,
      );
    }
    if (_exceedsLineLimit(bytes, fullDiffPatchLineLimit)) {
      throw FullDiffPatchOutputLimitException(
        root,
        FullDiffPatchOutputLimitReason.lineLimit,
      );
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

typedef _StatusEntry = ({String status, String path, String? oldPath});
typedef _Stats = ({int? additions, int? deletions, bool isBinary});

List<_StatusEntry> _parseNameStatus(String output) {
  final fields = output.split('\x00');
  final entries = <_StatusEntry>[];
  var index = 0;
  while (index < fields.length && fields[index].isNotEmpty) {
    final field = fields[index++];
    final tab = field.indexOf('\t');
    final status = tab < 0 ? field : field.substring(0, tab);
    var path = tab < 0 ? fields[index++] : field.substring(tab + 1);
    String? oldPath;
    if (status.startsWith('R') || status.startsWith('C')) {
      oldPath = path;
      path = fields[index++];
    }
    entries.add((status: status, path: path, oldPath: oldPath));
  }
  return entries;
}

Map<String, _Stats> _parseNumstat(String output) {
  final fields = output.split('\x00');
  final stats = <String, _Stats>{};
  var index = 0;
  while (index < fields.length && fields[index].isNotEmpty) {
    final parts = fields[index++].split('\t');
    if (parts.length < 3) continue;
    var path = parts.sublist(2).join('\t');
    if (path.isEmpty && index + 1 < fields.length) {
      index++;
      path = fields[index++];
    }
    stats[path] = (
      additions: int.tryParse(parts[0]),
      deletions: int.tryParse(parts[1]),
      isBinary: parts[0] == '-' && parts[1] == '-',
    );
  }
  return stats;
}

Map<String, int> _parseLsTreeSizes(String output) {
  final result = <String, int>{};
  for (final record in output.split('\x00')) {
    if (record.isEmpty) continue;
    final tab = record.indexOf('\t');
    if (tab < 0) continue;
    final metadata = record.substring(0, tab).trim().split(RegExp(r'\s+'));
    if (metadata.length < 4) continue;
    final size = int.tryParse(metadata[3]);
    if (size != null) result[record.substring(tab + 1)] = size;
  }
  return result;
}

List<String> blameArguments({
  required GitCommit commit,
  required GitFileChange file,
  required String base,
  String? contentsPath,
}) {
  if (commit.isWorkingTree && !file.status.startsWith('D')) {
    if (contentsPath == null) {
      throw ArgumentError.notNull('contentsPath');
    }
    return [
      'blame',
      '--line-porcelain',
      '--contents',
      contentsPath,
      base,
      '--',
      file.oldPath ?? file.path,
    ];
  }
  return [
    'blame',
    '--line-porcelain',
    commit.isWorkingTree || file.status.startsWith('D') ? base : commit.sha,
    '--',
    file.status.startsWith('D') ? file.oldPath ?? file.path : file.path,
  ];
}

List<DiffLine> _untrackedDiff(Uint8List bytes) {
  var sourceLines = const <String>[];
  if (!bytes.contains(0)) {
    try {
      sourceLines = _sourceLines(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      // Unsupported encodings still get a valid empty hunk header.
    }
  }
  return [
    DiffLine(
      kind: DiffLineKind.hunk,
      text: '@@ -0,0 +1,${sourceLines.length} @@',
    ),
    for (var index = 0; index < sourceLines.length; index++)
      DiffLine(
        kind: DiffLineKind.add,
        text: sourceLines[index],
        newNumber: index + 1,
      ),
  ];
}

List<GitBlameLine> _uncommittedBlame(Uint8List bytes) {
  late final List<String> sourceLines;
  try {
    sourceLines = _sourceLines(utf8.decode(bytes, allowMalformed: false));
  } on FormatException {
    return const [];
  }
  return [
    for (var index = 0; index < sourceLines.length; index++)
      GitBlameLine(
        lineNumber: index + 1,
        sha: '',
        author: 'Uncommitted',
        uncommitted: true,
      ),
  ];
}

List<String> _sourceLines(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (text.endsWith('\n')) lines.removeLast();
  return lines;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

typedef _WorktreeSnapshot = ({Uint8List bytes, bool exceeded});

bool _exceedsLineLimit(List<int> bytes, int limit) {
  var lineCount = 0;
  for (final byte in bytes) {
    if (byte == 0x0A && ++lineCount > limit) return true;
  }
  return lineCount == limit && bytes.isNotEmpty && bytes.last != 0x0A;
}

_WorktreeSnapshot _snapshotForBytes(Uint8List bytes) {
  final bounded = bytes.length <= fullDiffTextByteLimit + 1
      ? bytes
      : Uint8List.sublistView(bytes, 0, fullDiffTextByteLimit + 1);
  return (bytes: bounded, exceeded: bytes.length > fullDiffTextByteLimit);
}

void _verifyWorktreeSnapshot(
  _WorktreeSnapshot actual,
  _WorktreeSnapshot expected,
) {
  if (actual.exceeded != expected.exceeded ||
      !_sameBytes(actual.bytes, expected.bytes)) {
    throw StateError('Working tree file changed');
  }
  if (expected.exceeded) {
    throw StateError('Working tree file exceeds the full diff byte limit');
  }
}

typedef _BlameMetadata = ({
  String author,
  String email,
  int? timestamp,
  String summary,
});

const _emptyBlameMetadata = (
  author: '',
  email: '',
  timestamp: null,
  summary: '',
);

List<GitBlameLine> _parseBlamePorcelain(String output) {
  final lines = <GitBlameLine>[];
  final metadataBySha = <String, _BlameMetadata>{};
  String? sha;
  _BlameMetadata? metadata;
  int? lineNumber;

  for (final line in output.split('\n')) {
    if (line.startsWith('\t')) {
      if (sha != null && lineNumber != null) {
        final normalizedSha = sha.startsWith('^') ? sha.substring(1) : sha;
        final completedMetadata = metadata ?? _emptyBlameMetadata;
        metadataBySha[normalizedSha] = completedMetadata;
        lines.add(
          GitBlameLine(
            lineNumber: lineNumber,
            sha: normalizedSha,
            author: completedMetadata.author,
            authorEmail: completedMetadata.email,
            authorTimestamp: completedMetadata.timestamp,
            summary: completedMetadata.summary,
            uncommitted:
                normalizedSha.isNotEmpty &&
                normalizedSha.codeUnits.every((unit) => unit == 0x30),
          ),
        );
      }
      sha = null;
      metadata = null;
      lineNumber = null;
      continue;
    }

    final fields = line.split(' ');
    final parsedLine = fields.length >= 3 ? int.tryParse(fields[2]) : null;
    if (fields.length >= 3 &&
        RegExp(r'^\^?[0-9a-f]+$').hasMatch(fields[0]) &&
        int.tryParse(fields[1]) != null &&
        parsedLine != null) {
      sha = fields[0];
      lineNumber = parsedLine;
      final normalizedSha = sha.startsWith('^') ? sha.substring(1) : sha;
      metadata = metadataBySha[normalizedSha] ?? _emptyBlameMetadata;
      continue;
    }
    if (line.startsWith('author ') && sha != null) {
      metadata = (
        author: line.substring('author '.length),
        email: metadata!.email,
        timestamp: metadata.timestamp,
        summary: metadata.summary,
      );
      continue;
    }
    if (line.startsWith('author-mail ') && sha != null) {
      final email = line.substring('author-mail '.length);
      metadata = (
        author: metadata!.author,
        email: email.startsWith('<') && email.endsWith('>')
            ? email.substring(1, email.length - 1)
            : email,
        timestamp: metadata.timestamp,
        summary: metadata.summary,
      );
      continue;
    }
    if (line.startsWith('author-time ') && sha != null) {
      metadata = (
        author: metadata!.author,
        email: metadata.email,
        timestamp: int.tryParse(line.substring('author-time '.length)),
        summary: metadata.summary,
      );
      continue;
    }
    if (line.startsWith('summary ') && sha != null) {
      metadata = (
        author: metadata!.author,
        email: metadata.email,
        timestamp: metadata.timestamp,
        summary: line.substring('summary '.length),
      );
    }
  }
  return lines;
}

List<GitFileHistoryRecord> _parseFileHistory(String output) {
  final history = <GitFileHistoryRecord>[];
  for (final record in output.split('\x1e').skip(1)) {
    final fields = record.split('\x00');
    if (fields.length < 11) continue;
    final commit = GitCommit(
      sha: fields[0],
      shortSha: fields[1],
      parents: fields[2].isEmpty ? const [] : fields[2].split(' '),
      author: GitIdentity(name: fields[3], email: fields[4]),
      authorTimestamp: int.parse(fields[5]),
      committer: GitIdentity(name: fields[6], email: fields[7]),
      committerTimestamp: int.parse(fields[8]),
      refs: const [],
      subject: fields[9],
    );
    var index = 10;
    while (index < fields.length) {
      final status = fields[index++].replaceFirst(RegExp(r'^\n+'), '');
      if (status.isEmpty || index >= fields.length) continue;
      String? oldPath;
      late final String path;
      if (status.startsWith('R') || status.startsWith('C')) {
        if (index + 1 >= fields.length) break;
        oldPath = fields[index++];
        path = fields[index++];
      } else {
        path = fields[index++];
      }
      history.add(
        GitFileHistoryRecord(
          commit: commit,
          path: path,
          oldPath: oldPath,
          status: status,
        ),
      );
    }
  }
  return history;
}
