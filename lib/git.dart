import 'dart:io';
import 'dart:math';

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
  });

  final GitCommit commit;
  final int lane;
  final List<int> parentLanes;
  final List<int> activeLanes;
  final List<int> nextLanes;
  final Map<int, String> activeLaneShas;
  final Map<int, String> nextLaneShas;
  final List<LaneTransition> transitions;

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
/// all the forbidden-column test in [layoutGraph] needs.
typedef _Column = ({String? sha, int row});

class _RowBuffer {
  _RowBuffer({
    required this.commit,
    required this.lane,
    required this.entering,
    required this.leaving,
    required this.parentLanes,
  });

  final GitCommit commit;
  final int lane;
  final Map<int, String> entering;
  final Map<int, String> leaving;
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
List<GraphRow> layoutGraph(List<GitCommit> commits) {
  final columns = <_Column>[];
  final mergeChildRows = <String, List<int>>{};
  final rows = <_RowBuffer>[];

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

    var lane = -1;
    for (var column = 0; column < columns.length && lane < 0; column++) {
      if (columns[column].sha == commit.sha && clear(column)) lane = column;
    }
    for (var column = 0; column < columns.length && lane < 0; column++) {
      if (columns[column].sha == null && clear(column)) lane = column;
    }
    if (lane < 0) {
      lane = columns.length;
      columns.add((sha: null, row: -1));
    }

    // Every other line waiting for this commit converges into its column. The
    // sweep is drawn from the row above, so the column is busy up to there.
    for (var column = 0; column < columns.length; column++) {
      if (column == lane || columns[column].sha != commit.sha) continue;
      columns[column] = (sha: null, row: index - 1);
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
    // The column now carries this commit's own line, starting at its node.
    columns[lane] = commit.parents.isEmpty
        ? (sha: null, row: index)
        : (sha: commit.parents.first, row: index);
    rows.add(
      _RowBuffer(
        commit: commit,
        lane: lane,
        entering: entering,
        leaving: {
          for (var column = 0; column < columns.length; column++)
            column: ?columns[column].sha,
        },
        parentLanes: [if (commit.parents.isNotEmpty) lane],
      ),
    );

    // The merge edges waiting above only learn their column here.
    for (final child in mergeChildren) {
      for (var row = child; row < index; row++) {
        rows[row].leaving[lane] = commit.sha;
        if (row > child) rows[row].entering[lane] = commit.sha;
      }
      rows[child].parentLanes.add(lane);
      if (rows[child].lane != lane) {
        rows[child].transitions.add((
          from: rows[child].lane,
          to: lane,
          sha: commit.sha,
        ));
      }
    }
    for (final parent in commit.parents.skip(1)) {
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
  });

  final String path;
  final String? oldPath;
  final String status;
  final int? additions;
  final int? deletions;
}

class RepoRefs {
  const RepoRefs({
    this.local = const [],
    this.remote = const [],
    this.tags = const [],
    this.current,
  });

  final List<String> local;
  final List<String> remote;
  final List<String> tags;
  final String? current;
}

class GitRepository {
  GitRepository(
    this.root, {
    this.gitExecutable = 'git',
    this.runner = runProcess,
  });

  final String root;
  final String gitExecutable;
  final CommandRunner runner;
  Future<String>? _emptyTree;
  Future<List<String>>? _startingRevisions;

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

  Future<List<GitFileChange>> loadFiles(
    GitCommit commit, {
    String? parent,
  }) async {
    final revisions = await _revisionsFor(commit, parent);
    const safe = ['--no-ext-diff', '--no-textconv', '--no-color'];
    final statuses = _parseNameStatus(
      await _run(['diff', ...safe, '--name-status', '-z', ...revisions, '--']),
    );
    final stats = _parseNumstat(
      await _run(['diff', ...safe, '--numstat', '-z', ...revisions, '--']),
    );
    return [
      for (final status in statuses)
        GitFileChange(
          path: status.path,
          oldPath: status.oldPath,
          status: status.status,
          additions: stats[status.path]?.additions,
          deletions: stats[status.path]?.deletions,
        ),
    ];
  }

  Future<List<DiffLine>> loadDiff(
    GitCommit commit,
    String path, {
    String? parent,
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
  }) async {
    return parseUnifiedDiff(
      await _run([
        'diff',
        '--no-ext-diff',
        '--no-textconv',
        '--no-color',
        ...algorithm.gitArguments,
        ...await _revisionsFor(commit, parent),
        '--',
        path,
      ]),
    );
  }

  /// Sidebar data: local branches, remote branches, and tags, plus the
  /// currently checked-out branch (null when detached).
  Future<RepoRefs> loadRefs() async {
    final names = (await _run([
      'for-each-ref',
      '--format=%(refname)',
      'refs/heads',
      'refs/remotes',
      'refs/tags',
    ])).split('\n').where((line) => line.isNotEmpty);
    final local = <String>[];
    final remote = <String>[];
    final tags = <String>[];
    for (final name in names) {
      if (name.startsWith('refs/heads/')) {
        local.add(name.substring('refs/heads/'.length));
      } else if (name.startsWith('refs/remotes/')) {
        final short = name.substring('refs/remotes/'.length);
        if (!short.endsWith('/HEAD')) remote.add(short);
      } else if (name.startsWith('refs/tags/')) {
        tags.add(name.substring('refs/tags/'.length));
      }
    }
    final current = (await _run(['branch', '--show-current'])).trim();
    return RepoRefs(
      local: local,
      remote: remote,
      tags: tags,
      current: current.isEmpty ? null : current,
    );
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
}

typedef _StatusEntry = ({String status, String path, String? oldPath});
typedef _Stats = ({int? additions, int? deletions});

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
    );
  }
  return stats;
}
