import 'dart:async';
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
      Map<String, String>? environment,
    });

Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
);

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

Future<File> resolveWorkingTreeFile(
  String repositoryRoot,
  String relativePath,
) async {
  final root = await Directory(repositoryRoot).resolveSymbolicLinks();
  final resolved = await File(
    '$root${Platform.pathSeparator}$relativePath',
  ).resolveSymbolicLinks();
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  if (!resolved.startsWith(prefix)) {
    throw FileSystemException('File escapes repository root', resolved);
  }
  if ((await FileStat.stat(resolved)).type != FileSystemEntityType.file) {
    throw FileSystemException('Editor target is not a regular file', resolved);
  }
  return File(resolved);
}

/// Total size of the regular files under [path] — what deleting the directory
/// would free.
Future<int> directorySizeBytes(String path) async {
  var total = 0;
  await for (final entity in Directory(
    path,
  ).list(recursive: true, followLinks: false)) {
    if (entity is File) total += (await entity.stat()).size;
  }
  return total;
}

/// `1536` reads as `1.5 KB`.
String byteSizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}

/// The directories to watch for a ref change, most specific first. Git rewrites
/// `HEAD` and loose refs by renaming a lock file over them, so the *directory*
/// is what reports the change, not the file. `refs` is watched recursively
/// because a branch name like `codex/lane` nests. `objects` is left alone: a
/// fetch churns it constantly and none of it moves a branch.
List<String> refWatchPaths({
  required String gitDir,
  required String commonDir,
}) => [
  gitDir,
  if (commonDir != gitDir) commonDir,
  '$commonDir${Platform.pathSeparator}refs',
];

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

const _gitLogFormat =
    '%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%cn%x1f%ce%x1f%ct%x1f%D%x1f%s%x1e';

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
  return decorations
      .split(', ')
      .map((decoration) {
        if (decoration.startsWith('HEAD -> ')) {
          return GitRef(name: decoration.substring(8), isHead: true);
        }
        if (decoration.startsWith('tag: ')) {
          return GitRef(name: decoration.substring(5), isTag: true);
        }
        return GitRef(name: decoration);
      })
      // `origin/HEAD` is a symbolic alias for another remote branch, and that
      // branch decorates the same commit, so drawing it only doubles the chip.
      // The ref listing leaves it out for the same reason.
      .where((ref) => ref.isHead || ref.isTag || !_isRemoteHeadAlias(ref.name))
      .toList();
}

/// `origin/HEAD`, `upstream/HEAD` — a remote's symbolic default, not a branch.
/// A branch merely *named* `HEADroom` keeps its place.
bool _isRemoteHeadAlias(String name) =>
    name.endsWith('/HEAD') && name.indexOf('/') == name.length - 5;

final _mergedBranchPatterns = <RegExp>[
  RegExp(r"^Merge branch '([^']+)'(?: into .+)?$"),
  RegExp(r"^Merge remote-tracking branch '[^/']+/([^']+)'(?: into .+)?$"),
  RegExp(r'^Merge pull request #\d+ from [^/]+/(.+)$'),
];

String? _mergedBranchName(String subject) {
  for (final pattern in _mergedBranchPatterns) {
    final name = pattern.firstMatch(subject)?.group(1)?.trim();
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}

String? deletedBranchNameFromMerge(Iterable<GitCommit> commits, String tipSha) {
  for (final commit in commits) {
    if (!commit.parents.skip(1).contains(tipSha)) continue;
    final name = _mergedBranchName(commit.subject);
    if (name != null) return name;
  }
  return null;
}

/// Every line a merge in [commits] named, keyed by the line's tip. One walk
/// answers for all of them, so a row asking whose line it sits on costs a map
/// lookup rather than a scan. [commits] comes newest first, which makes the
/// first name found for a tip the most recent one to have claimed it.
///
/// Only two-parent merges count. One subject names one branch, so an octopus
/// merge would have to hand the same name to every side it pulled in, and git
/// writes those as `Merge branches 'a' and 'b'` anyway.
Map<String, String> mergedBranchNamesByTip(Iterable<GitCommit> commits) {
  final names = <String, String>{};
  for (final commit in commits) {
    if (commit.parents.length != 2) continue;
    final name = _mergedBranchName(commit.subject);
    if (name == null) continue;
    names.putIfAbsent(commit.parents[1], () => name);
  }
  return names;
}

List<({String sha, String subject})> _reflogEntries(String output) => output
    .split('\n')
    .where((line) => line.isNotEmpty)
    .map((line) {
      final separator = line.indexOf('\x00');
      return separator < 0
          ? null
          : (
              sha: line.substring(0, separator),
              subject: line.substring(separator + 1),
            );
    })
    .whereType<({String sha, String subject})>()
    .toList();

final _reflogCheckout = RegExp(r'^checkout: moving from (.+) to .+$');
final _reflogDetached = RegExp(r'^[0-9a-fA-F]{7,40}$');

/// The branch a `checkout: moving from …` entry left behind, or null when it
/// left no branch at all — a detached head, a bare SHA, or `-`.
String? _reflogCheckoutSource(String subject) {
  final source = _reflogCheckout.firstMatch(subject)?.group(1)?.trim();
  if (source == null ||
      source.isEmpty ||
      source == 'HEAD' ||
      source == '-' ||
      _reflogDetached.hasMatch(source)) {
    return null;
  }
  return source;
}

String? deletedBranchNameFromReflog(String output, String tipSha) {
  final entries = _reflogEntries(output);
  for (var index = 0; index + 1 < entries.length; index++) {
    if (entries[index + 1].sha != tipSha) continue;
    final source = _reflogCheckoutSource(entries[index].subject);
    if (source != null) return source;
  }
  return null;
}

/// Every branch this repository was checked out from, keyed by the commit it
/// sat on at the time — the tip that branch had. Folding the whole reflog once
/// answers for all of them, so no later question re-reads it. [output] comes
/// newest first, so the first name found for a commit is the most recent.
Map<String, String> deletedBranchNamesFromReflog(String output) {
  final entries = _reflogEntries(output);
  final names = <String, String>{};
  for (var index = 0; index + 1 < entries.length; index++) {
    final source = _reflogCheckoutSource(entries[index].subject);
    if (source == null) continue;
    names.putIfAbsent(entries[index + 1].sha, () => source);
  }
  return names;
}

/// A lane change happening across this row's lower half: the rail in [from]
/// sweeps into [to] between this row's center and the next row's center. Covers
/// merge edges (listed on the child's row) and branch lines converging on their
/// first parent (listed on the row *above* the parent). [sha] is the commit
/// occupying [to] below this row.
typedef LaneTransition = ({int from, int to, String sha});

enum BranchCommitSide { baseOnly, compareOnly, commonBoundary }

class BranchComparisonCommit {
  const BranchComparisonCommit({required this.commit, required this.side});

  final GitCommit commit;
  final BranchCommitSide side;
}

enum MergeConflictStatus { clean, conflicts, failed }

/// An inclusive line span, in whichever coordinates its producer names.
typedef LineSpan = ({int startLine, int endLine});

/// How close two opposite-side edits have to be to count as one region.
const proximityLineGap = 10;

/// How many first-parent commits the base branch needs before its merge-commit
/// ratio counts as this repository's convention.
const conventionSampleFloor = 10;

class MergeConflictCheck {
  const MergeConflictCheck({
    required this.status,
    this.files = const [],
    this.treeSha,
    this.resultFiles = const [],
    this.baseChangedFiles = const {},
    this.proximity = const {},
    this.error,
  });

  final MergeConflictStatus status;
  final List<String> files;
  final String? treeSha;
  final List<GitFileChange> resultFiles;

  /// Paths the base branch itself changed since a merge base, so a result file
  /// both sides touched can say so. Empty without a merge base, and for
  /// conflicting or failed checks. [resultFiles] is a base tip → result diff, so
  /// every file in it was touched by the compared branch already.
  final Set<String> baseChangedFiles;

  /// Merge-result line spans where the two sides edited within
  /// [proximityLineGap] lines of each other, keyed by result path. Only clean
  /// merges, and only files both sides touched, are measured.
  final Map<String, List<LineSpan>> proximity;
  final String? error;
}

enum RebaseCheckStatus { clean, conflicts, failed }

class RebaseCheckResult {
  const RebaseCheckResult({
    required this.status,
    this.stoppedCommit,
    this.files = const [],
    this.error,
  });

  final RebaseCheckStatus status;
  final String? stoppedCommit;
  final List<String> files;
  final String? error;
}

enum MergePreviewStatus { clean, conflict, failed }

enum MergeConflictChoice { base, compare }

class MergePreviewResult {
  const MergePreviewResult({
    required this.status,
    required this.baseTip,
    required this.compareTip,
    this.treeSha,
    this.resultFiles = const [],
    this.conflictFiles = const [],
    this.error,
  });

  final MergePreviewStatus status;
  final String baseTip;
  final String compareTip;
  final String? treeSha;
  final List<GitFileChange> resultFiles;
  final List<String> conflictFiles;
  final String? error;
}

enum RebasePreviewStatus { clean, conflict, failed }

enum RebaseConflictChoice { base, commit }

typedef RewrittenCommit = ({GitCommit original, String rewrittenSha});

String _previewFilePath(String? worktreePath, String relativePath) {
  final parts = relativePath.split(RegExp(r'[/\\]'));
  if (worktreePath == null ||
      relativePath.isEmpty ||
      relativePath.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(relativePath) ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw FileSystemException('Invalid preview path', relativePath);
  }
  return '$worktreePath${Platform.pathSeparator}'
      '${parts.join(Platform.pathSeparator)}';
}

/// A resolution that still carries a marker git wrote. The message names the
/// file and the first offending line, and nothing else: the error surface prints
/// it verbatim.
class ConflictMarkerResidueException implements Exception {
  const ConflictMarkerResidueException(this.path, this.line);

  final String path;
  final int line;

  @override
  String toString() => '충돌 마커가 남아 있어 해결로 표시할 수 없습니다: $path $line행';
}

/// A line git would have written to mark a conflict. Whether such a line is
/// residue or the file's own content is decided by comparing it against the
/// three stage blobs, never by the line alone.
bool isConflictMarkerLine(String line) =>
    line.startsWith('<<<<<<<') ||
    line.startsWith('|||||||') ||
    line.startsWith('=======') ||
    line.startsWith('>>>>>>>');

/// One conflict region of a file both sides only added to: the base section was
/// empty, so nothing was overwritten and only the order is left to pick.
class KeepBothHunk {
  const KeepBothHunk({required this.ours, required this.theirs});

  final List<String> ours;
  final List<String> theirs;
}

/// A conflicted file where every region is a two-sided addition, with the two
/// combined results already built. Non-conflict regions are carried through
/// untouched, so applying one of these is a marker replacement and nothing more.
class KeepBothCandidate {
  const KeepBothCandidate({
    required this.hunks,
    required this.baseFirst,
    required this.branchFirst,
  });

  final List<KeepBothHunk> hunks;

  /// The whole file with the base side's addition placed first in every region.
  final String baseFirst;
  final String branchFirst;
}

/// Splits `git merge-file -p --diff3` output into its conflict regions. Null
/// unless every region's base section is empty — one region that overwrote
/// something is a real modification conflict, and a half-right suggestion there
/// is worse than none. The caller has already checked that no stage blob carried
/// a marker-shaped line, so every marker here is one merge-file wrote.
KeepBothCandidate? parseKeepBothCandidate(String merged) {
  final hunks = <KeepBothHunk>[];
  final baseFirst = <String>[];
  final branchFirst = <String>[];
  var ours = <String>[];
  var base = <String>[];
  var theirs = <String>[];
  var section = 0;
  for (final line in merged.split('\n')) {
    if (section == 0 && line.startsWith('<<<<<<<')) {
      section = 1;
      ours = [];
      base = [];
      theirs = [];
      continue;
    }
    if (section == 1 && line.startsWith('|||||||')) {
      section = 2;
      continue;
    }
    if (section == 2 && line.startsWith('=======')) {
      section = 3;
      continue;
    }
    if (section == 3 && line.startsWith('>>>>>>>')) {
      if (base.isNotEmpty) return null;
      hunks.add(KeepBothHunk(ours: ours, theirs: theirs));
      baseFirst
        ..addAll(ours)
        ..addAll(theirs);
      branchFirst
        ..addAll(theirs)
        ..addAll(ours);
      section = 0;
      continue;
    }
    switch (section) {
      case 0:
        baseFirst.add(line);
        branchFirst.add(line);
      case 1:
        ours.add(line);
      case 2:
        base.add(line);
      case 3:
        theirs.add(line);
    }
  }
  if (section != 0 || hunks.isEmpty) return null;
  return KeepBothCandidate(
    hunks: hunks,
    baseFirst: baseFirst.join('\n'),
    branchFirst: branchFirst.join('\n'),
  );
}

/// ponytail: 커밋 30개면 cherry-pick을 30번 도는 값이고 그 위는 사람이 기다릴
/// 시간이 아니다. 넘으면 예고를 아예 접는다 — 진행률 표시가 정말 필요해지면 그때
/// 상한을 올린다.
const conflictForecastCommitCeiling = 30;

/// 예고 프로브 worktree를 stale로 보는 나이. 30커밋을 다 돌아도 한 시간을 넘길
/// 일은 없으니, 이보다 오래된 프로브는 강제 종료가 남긴 것이다.
const staleConflictProbeAge = Duration(hours: 1);

class MergePreviewSession {
  MergePreviewSession({
    required GitRepository repository,
    required this.baseTip,
    required this.compareTip,
  }) : _repository = repository;

  final GitRepository _repository;
  final String baseTip;
  final String compareTip;
  String? _worktreePath;
  bool _disposed = false;

  String? get worktreePath => _worktreePath;

  String filePath(String relativePath) =>
      _previewFilePath(_worktreePath, relativePath);

  Future<List<DiffLine>> loadConflictDiff(String relativePath) =>
      _repository._loadPreviewConflictDiff(_worktreePath!, relativePath);

  Future<MergePreviewResult> start() async {
    if (_disposed) {
      throw StateError('Merge preview session has been disposed.');
    }
    if (_worktreePath != null) {
      throw StateError('Merge preview session has already started.');
    }
    final temporary = await Directory.systemTemp.createTemp(
      'yogit_merge_preview_',
    );
    final path = temporary.path;
    await temporary.delete();
    _worktreePath = path;
    final add = await _repository.runner(_repository.gitExecutable, [
      'worktree',
      'add',
      '--detach',
      path,
      baseTip,
    ], workingDirectory: _repository.root);
    if (add.exitCode != 0) {
      await dispose();
      return MergePreviewResult(
        status: MergePreviewStatus.failed,
        baseTip: baseTip,
        compareTip: compareTip,
        error: add.stderr.toString().trim(),
      );
    }
    final merge = await _repository.runner(
      _repository.gitExecutable,
      [
        '-c',
        'core.hooksPath=/dev/null',
        '-c',
        'commit.gpgSign=false',
        'merge',
        '--no-commit',
        '--no-ff',
        compareTip,
      ],
      workingDirectory: path,
      environment: {
        ...Platform.environment,
        'GIT_EDITOR': 'true',
        'GIT_TERMINAL_PROMPT': '0',
      },
    );
    if (merge.exitCode == 0) return finish();
    final conflicts = await _run(const [
      'diff',
      '--name-only',
      '--diff-filter=U',
      '-z',
    ]);
    final files = conflicts
        .split('\x00')
        .where((value) => value.isNotEmpty)
        .toList();
    return MergePreviewResult(
      status: files.isEmpty
          ? MergePreviewStatus.failed
          : MergePreviewStatus.conflict,
      baseTip: baseTip,
      compareTip: compareTip,
      conflictFiles: files,
      error: files.isEmpty ? merge.stderr.toString().trim() : null,
    );
  }

  Future<void> resolveFile(
    String relativePath,
    MergeConflictChoice choice,
  ) async {
    filePath(relativePath);
    await _run([
      'checkout',
      choice == MergeConflictChoice.base ? '--ours' : '--theirs',
      '--',
      relativePath,
    ]);
    await markResolved(relativePath);
  }

  Future<void> markResolved(String relativePath) async {
    filePath(relativePath);
    await _repository._rejectConflictMarkerResidue(
      _worktreePath!,
      relativePath,
    );
    await _run(['add', '--', relativePath]);
  }

  /// The two-sided-addition reading of a conflicted file, or null when the file
  /// does not qualify. See [GitRepository._keepBothCandidate].
  Future<KeepBothCandidate?> keepBothCandidate(String relativePath) =>
      _repository._keepBothCandidate(_worktreePath!, relativePath);

  /// Writes one of the combined orders and stages it. The file stays editable
  /// afterwards; this only replaces the markers with both sides.
  Future<void> applyKeepBoth(String relativePath, String content) async {
    await File(filePath(relativePath)).writeAsString(content);
    await markResolved(relativePath);
  }

  Future<MergePreviewResult> finish() async {
    final conflicts = await _run(const [
      'diff',
      '--name-only',
      '--diff-filter=U',
    ]);
    if (conflicts.trim().isNotEmpty) {
      throw GitRepositoryException(_worktreePath!, '해결되지 않은 충돌 파일이 남아 있습니다.');
    }
    final treeSha = (await _run(const ['write-tree'])).trim();
    return MergePreviewResult(
      status: MergePreviewStatus.clean,
      baseTip: baseTip,
      compareTip: compareTip,
      treeSha: treeSha,
      resultFiles: await _repository.loadFilesBetween(baseTip, treeSha),
    );
  }

  Future<String> _run(List<String> arguments) async {
    final result = await _repository.runner(
      _repository.gitExecutable,
      arguments,
      workingDirectory: _worktreePath,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        _repository.gitExecutable,
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return result.stdout.toString();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final path = _worktreePath;
    if (path == null) return;
    await _repository._ignoreCommand(const [
      'merge',
      '--abort',
    ], workingDirectory: path);
    await _repository._removePreviewWorktree(path);
  }
}

class RebasePreviewResult {
  const RebasePreviewResult({
    required this.status,
    required this.baseTip,
    required this.compareTip,
    this.rewritten = const [],
    this.currentCommit,
    this.completed = 0,
    this.total = 0,
    this.conflictFiles = const [],
    this.virtualTip,
    this.error,
  });

  final RebasePreviewStatus status;
  final String baseTip;
  final String compareTip;
  final List<RewrittenCommit> rewritten;
  final GitCommit? currentCommit;
  final int completed;
  final int total;
  final List<String> conflictFiles;
  final String? virtualTip;
  final String? error;
}

class RebasePreviewSession {
  RebasePreviewSession({
    required GitRepository repository,
    required this.baseTip,
    required this.compareTip,
    required List<GitCommit> originalCommits,
  }) : _repository = repository,
       _originalCommits = originalCommits;

  final GitRepository _repository;
  final String baseTip;
  final String compareTip;
  final List<GitCommit> _originalCommits;
  String? _worktreePath;
  bool _disposed = false;

  String? get worktreePath => _worktreePath;

  String filePath(String relativePath) =>
      _previewFilePath(_worktreePath, relativePath);

  Future<List<DiffLine>> loadConflictDiff(String relativePath) =>
      _repository._loadPreviewConflictDiff(_worktreePath!, relativePath);

  Future<RebasePreviewResult> start() async {
    if (_disposed) {
      throw StateError('Rebase preview session has been disposed.');
    }
    if (_worktreePath != null) {
      throw StateError('Rebase preview session has already started.');
    }
    final temporary = await Directory.systemTemp.createTemp(
      'yogit_rebase_preview_',
    );
    final path = temporary.path;
    await temporary.delete();
    _worktreePath = path;
    final add = await _repository.runner(_repository.gitExecutable, [
      'worktree',
      'add',
      '--detach',
      path,
      compareTip,
    ], workingDirectory: _repository.root);
    if (add.exitCode != 0) {
      await dispose();
      return RebasePreviewResult(
        status: RebasePreviewStatus.failed,
        baseTip: baseTip,
        compareTip: compareTip,
        total: _originalCommits.length,
        error: add.stderr.toString().trim(),
      );
    }
    final result = await _repository.runner(
      _repository.gitExecutable,
      [
        '-c',
        'core.hooksPath=/dev/null',
        '-c',
        'rerere.enabled=false',
        '-c',
        'rebase.autoStash=false',
        '-c',
        'rebase.updateRefs=false',
        '-c',
        'commit.gpgSign=false',
        'rebase',
        '--no-autostash',
        baseTip,
      ],
      workingDirectory: path,
      environment: {
        ...Platform.environment,
        'GIT_EDITOR': 'true',
        'GIT_SEQUENCE_EDITOR': 'true',
        'GIT_TERMINAL_PROMPT': '0',
      },
    );
    if (result.exitCode != 0) {
      return _conflictOrFailure(result);
    }
    final rewritten = await _rewrittenCommits();
    final virtualTip = (await _run(const ['rev-parse', 'HEAD'])).trim();
    return RebasePreviewResult(
      status: RebasePreviewStatus.clean,
      baseTip: baseTip,
      compareTip: compareTip,
      rewritten: rewritten,
      completed: rewritten.length,
      total: _originalCommits.length,
      virtualTip: virtualTip,
    );
  }

  Future<void> markResolved(String relativePath) async {
    filePath(relativePath);
    await _repository._rejectConflictMarkerResidue(
      _worktreePath!,
      relativePath,
    );
    final result = await _repository.runner(_repository.gitExecutable, [
      'add',
      '--',
      relativePath,
    ], workingDirectory: _worktreePath);
    if (result.exitCode != 0) {
      throw ProcessException(
        _repository.gitExecutable,
        ['add', '--', relativePath],
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }

  Future<void> resolveFile(
    String relativePath,
    RebaseConflictChoice choice,
  ) async {
    filePath(relativePath);
    await _run([
      'checkout',
      choice == RebaseConflictChoice.base ? '--ours' : '--theirs',
      '--',
      relativePath,
    ]);
    await markResolved(relativePath);
  }

  /// The two-sided-addition reading of a conflicted file, or null when the file
  /// does not qualify. See [GitRepository._keepBothCandidate].
  Future<KeepBothCandidate?> keepBothCandidate(String relativePath) =>
      _repository._keepBothCandidate(_worktreePath!, relativePath);

  /// Writes one of the combined orders and stages it. The file stays editable
  /// afterwards; this only replaces the markers with both sides.
  Future<void> applyKeepBoth(String relativePath, String content) async {
    await File(filePath(relativePath)).writeAsString(content);
    await markResolved(relativePath);
  }

  Future<RebasePreviewResult> continueAfterResolving() async {
    final conflicts = await _run(const [
      'diff',
      '--name-only',
      '--diff-filter=U',
    ]);
    if (conflicts.trim().isNotEmpty) {
      throw GitRepositoryException(_worktreePath!, '해결되지 않은 충돌 파일이 남아 있습니다.');
    }
    final result = await _repository.runner(
      _repository.gitExecutable,
      [
        '-c',
        'core.hooksPath=/dev/null',
        '-c',
        'rerere.enabled=false',
        '-c',
        'rebase.updateRefs=false',
        '-c',
        'commit.gpgSign=false',
        'rebase',
        '--continue',
      ],
      workingDirectory: _worktreePath,
      environment: {
        ...Platform.environment,
        'GIT_EDITOR': 'true',
        'GIT_SEQUENCE_EDITOR': 'true',
        'GIT_TERMINAL_PROMPT': '0',
      },
    );
    if (result.exitCode != 0) {
      return _conflictOrFailure(result);
    }
    final rewritten = await _rewrittenCommits();
    return RebasePreviewResult(
      status: RebasePreviewStatus.clean,
      baseTip: baseTip,
      compareTip: compareTip,
      rewritten: rewritten,
      completed: rewritten.length,
      total: _originalCommits.length,
      virtualTip: (await _run(const ['rev-parse', 'HEAD'])).trim(),
    );
  }

  Future<List<RewrittenCommit>> _rewrittenCommits() async {
    if (_originalCommits.isEmpty) return const [];
    if ((await _run(const ['rev-parse', 'HEAD'])).trim() == baseTip) {
      return const [];
    }
    final parents = _originalCommits.first.parents;
    if (parents.isEmpty) return const [];
    final originalBase = parents.first;
    final output = await _run([
      'range-diff',
      '--no-color',
      '--no-dual-color',
      '--abbrev=40',
      '$originalBase..$compareTip',
      '$baseTip..HEAD',
    ]);
    final originals = {
      for (final commit in _originalCommits) commit.sha: commit,
    };
    final pairs = RegExp(
      r'^\s*\d+:\s+([0-9a-f]{40})\s+[=!]\s+\d+:\s+([0-9a-f]{40})\s+',
      multiLine: true,
    ).allMatches(output);
    return [
      for (final pair in pairs)
        if (originals[pair.group(1)] case final original?)
          (original: original, rewrittenSha: pair.group(2)!),
    ];
  }

  Future<String> _run(List<String> arguments) async {
    final result = await _repository.runner(
      _repository.gitExecutable,
      arguments,
      workingDirectory: _worktreePath,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        _repository.gitExecutable,
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return result.stdout.toString();
  }

  Future<RebasePreviewResult> _conflictOrFailure(ProcessResult result) async {
    final path = _worktreePath!;
    final stopped = await _repository.runner(_repository.gitExecutable, const [
      'rev-parse',
      '--verify',
      'REBASE_HEAD',
    ], workingDirectory: path);
    final conflicts = await _repository.runner(
      _repository.gitExecutable,
      const ['diff', '--name-only', '--diff-filter=U', '-z'],
      workingDirectory: path,
    );
    final stoppedSha = stopped.exitCode == 0
        ? stopped.stdout.toString().trim()
        : null;
    final files = conflicts.exitCode == 0
        ? conflicts.stdout
              .toString()
              .split('\x00')
              .where((value) => value.isNotEmpty)
              .toList()
        : const <String>[];
    final currentIndex = stoppedSha == null
        ? -1
        : _originalCommits.indexWhere((commit) => commit.sha == stoppedSha);
    if (currentIndex >= 0 && files.isNotEmpty) {
      return RebasePreviewResult(
        status: RebasePreviewStatus.conflict,
        baseTip: baseTip,
        compareTip: compareTip,
        rewritten: await _rewrittenCommits(),
        currentCommit: _originalCommits[currentIndex],
        completed: currentIndex,
        total: _originalCommits.length,
        conflictFiles: files,
      );
    }
    return RebasePreviewResult(
      status: RebasePreviewStatus.failed,
      baseTip: baseTip,
      compareTip: compareTip,
      total: _originalCommits.length,
      error: result.stderr.toString().trim(),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final path = _worktreePath;
    if (path == null) return;
    await _repository._ignoreCommand(const [
      'rebase',
      '--abort',
    ], workingDirectory: path);
    await _repository._removePreviewWorktree(path);
  }
}

enum CherryPickOutcome { applied, conflicts, empty }

class CherryPickState {
  const CherryPickState({required this.commitSha, required this.conflicts});

  final String commitSha;
  final List<String> conflicts;

  bool get canContinue => conflicts.isEmpty;
}

class CherryPickResult {
  const CherryPickResult({required this.outcome, this.state, this.headSha});

  final CherryPickOutcome outcome;
  final CherryPickState? state;
  final String? headSha;
}

class BranchComparisonResult {
  const BranchComparisonResult({
    required this.baseRef,
    required this.compareRef,
    required this.baseTip,
    required this.compareTip,
    required this.baseParent,
    required this.compareParent,
    required this.mergeBases,
    required this.commits,
    required this.files,
    required this.merge,
  });

  final String baseRef;
  final String compareRef;
  final String baseTip;
  final String compareTip;
  final String? baseParent;
  final String? compareParent;
  final List<String> mergeBases;
  final List<BranchComparisonCommit> commits;
  final List<GitFileChange> files;
  final MergeConflictCheck merge;

  bool get sameFirstParent =>
      baseParent != null &&
      compareParent != null &&
      baseParent == compareParent;
}

enum BranchApplyMode { merge, rebase, rebaseMerge }

enum BranchIntegrationVerdict { merge, rebase, rebaseThenMerge }

/// What the measured git facts lean towards, and why. The engine hands the UI
/// finished text so nothing has to be decided twice.
class BranchRecommendation {
  const BranchRecommendation({
    required this.verdict,
    required this.summary,
    required this.reasons,
  });

  final BranchIntegrationVerdict verdict;

  /// The short why-text the chip shows beside the verdict.
  final String summary;

  /// At most three measured facts, strongest first.
  final List<String> reasons;

  String get label => switch (verdict) {
    BranchIntegrationVerdict.merge => 'Merge',
    BranchIntegrationVerdict.rebase => 'Rebase',
    BranchIntegrationVerdict.rebaseThenMerge => 'Rebase 후 Merge',
  };
}

class BranchApplyTarget {
  const BranchApplyTarget({
    required this.selectedRef,
    required this.selectedTip,
    required this.localBranch,
    required this.localTip,
  });

  final String selectedRef;
  final String selectedTip;
  final String localBranch;
  final String? localTip;

  bool get createsBranch => localTip == null;
  bool get needsRecalculation => localTip != null && localTip != selectedTip;
}

BranchApplyTarget? resolveBranchApplyTarget({
  required BranchApplyMode mode,
  required BranchComparisonResult comparison,
  required RepoRefs refs,
}) {
  final selectedRef = mode == BranchApplyMode.merge
      ? comparison.baseRef
      : comparison.compareRef;
  final selectedTip = mode == BranchApplyMode.merge
      ? comparison.baseTip
      : comparison.compareTip;

  if (refs.local.contains(selectedRef)) {
    return BranchApplyTarget(
      selectedRef: selectedRef,
      selectedTip: selectedTip,
      localBranch: selectedRef,
      localTip: refs.localTips[selectedRef] ?? refs.tips[selectedRef],
    );
  }
  if (mode == BranchApplyMode.merge || !refs.remote.contains(selectedRef)) {
    return null;
  }
  final separator = selectedRef.indexOf('/');
  if (separator <= 0 || separator == selectedRef.length - 1) return null;
  final localBranch = selectedRef.substring(separator + 1);
  return BranchApplyTarget(
    selectedRef: selectedRef,
    selectedTip: selectedTip,
    localBranch: localBranch,
    localTip: refs.localTips[localBranch],
  );
}

class BranchApplyResult {
  const BranchApplyResult({
    required this.mode,
    required this.baseBranch,
    required this.compareBranch,
    required this.baseBefore,
    required this.baseAfter,
    required this.compareBefore,
    required this.compareAfter,
    this.compareBranchCreated = false,
    this.workingTreeUpdated = false,
    this.compareWorkingTreeUpdated = false,
  });

  final BranchApplyMode mode;
  final String baseBranch;
  final String compareBranch;
  final String baseBefore;
  final String baseAfter;
  final String compareBefore;
  final String compareAfter;
  final bool compareBranchCreated;

  /// Whether the moved branch was the checked-out one, so the working tree holds
  /// the result on disk. False means only the branch ref moved. In
  /// [BranchApplyMode.rebaseMerge] this is the base branch's move; the compare
  /// branch has its own [compareWorkingTreeUpdated]. Only one of the two can be
  /// true, since a branch checked out elsewhere is refused before anything moves.
  final bool workingTreeUpdated;
  final bool compareWorkingTreeUpdated;
}

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

  /// Stable id of the branch line this row's node sits on. The preferred line
  /// reserves id 0; other lines are numbered in birth order top-down, so ids
  /// survive page appends.
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

List<GraphRow> layoutBranchComparison(List<BranchComparisonCommit> commits) {
  final firstCommon = commits.indexWhere(
    (entry) => entry.side == BranchCommitSide.commonBoundary,
  );
  final hasBaseOnly = commits.any(
    (entry) => entry.side == BranchCommitSide.baseOnly,
  );
  final hasCompareOnly = commits.any(
    (entry) => entry.side == BranchCommitSide.compareOnly,
  );
  return [
    for (var index = 0; index < commits.length; index++)
      () {
        final entry = commits[index];
        final lane = entry.side == BranchCommitSide.compareOnly ? 1 : 0;
        final beforeCommon = firstCommon < 0 || index < firstCommon;
        final convergesHere = firstCommon > 0 && index == firstCommon - 1;
        final activeLanes = beforeCommon
            ? [if (hasBaseOnly) 0, if (hasCompareOnly) 1]
            : const [0];
        final nextLanes = convergesHere || !beforeCommon
            ? const [0]
            : [if (hasBaseOnly) 0, if (hasCompareOnly) 1];
        return GraphRow(
          commit: entry.commit,
          lane: lane,
          parentLanes: [
            for (final _ in entry.commit.parents)
              if (convergesHere && lane == 1) 0 else lane,
          ],
          activeLanes: activeLanes,
          nextLanes: nextLanes,
          activeLaneShas: {
            for (final active in activeLanes)
              active: active == lane ? entry.commit.sha : '',
          },
          nextLaneShas: {
            for (final next in nextLanes)
              next: next == lane ? entry.commit.sha : '',
          },
          transitions: convergesHere && hasCompareOnly
              ? [(from: 1, to: 0, sha: commits[firstCommon].commit.sha)]
              : const [],
          branch: lane,
          activeLaneBranches: {
            for (final active in activeLanes) active: active,
          },
          nextLaneBranches: {for (final next in nextLanes) next: next},
        );
      }(),
  ];
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
/// transition and line identity. The reservation lasts for the whole layout, so
/// disconnected history cannot reuse column 0 after the preferred root.
///
/// Every continuous occupancy of a column is one branch line and gets an id in
/// birth order, so a first-parent chain keeps one id for its whole life and
/// colors uniformly. Ids only ever come from placements already made, so
/// appending a page never renumbers the rows above it.
List<GraphRow> layoutGraph(List<GitCommit> commits, {String? preferredTip}) {
  final columns = <_Column>[
    if (preferredTip != null) (sha: null, row: -1, line: -1),
  ];
  var preferredNodePlaced = false;
  var preferredTipLoaded = false;
  final mergeChildRows = <String, List<int>>{};
  final rows = <_RowBuffer>[];
  var lines = preferredTip == null ? 0 : 1;

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
        !preferredNodePlaced &&
        index == 0 &&
        commit.sha.isEmpty &&
        commit.parents.isNotEmpty &&
        commit.parents.first == preferredTip;
    final startsPreferred =
        !preferredNodePlaced &&
        (commit.sha == preferredTip || workingTreeStartsPreferred);
    final continuesPreferred =
        preferredTip != null && columns[0].sha == commit.sha;
    final firstCandidate =
        preferredTip != null && !startsPreferred && !continuesPreferred ? 1 : 0;

    var lane = startsPreferred ? 0 : -1;
    if (startsPreferred) preferredNodePlaced = true;
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
        : startsPreferred
        ? 0
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
    if (preferredTip != null && commit.sha == preferredTip) {
      preferredTipLoaded = true;
    }
    final preferredParent =
        preferredTip != null && !preferredTipLoaded && lane != 0
        ? commit.parents.indexOf(preferredTip)
        : -1;
    if (preferredParent >= 0) {
      if (preferredParent == 0) {
        columns[lane] = (sha: null, row: index, line: -1);
      }
      if (columns[0].sha == null) {
        columns[0] = (sha: preferredTip, row: index, line: 0);
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

const concreteDiffAlgorithms = <DiffAlgorithm>[
  DiffAlgorithm.myers,
  DiffAlgorithm.minimal,
  DiffAlgorithm.patience,
  DiffAlgorithm.histogram,
];

class GitDiffAlgorithmSetting {
  const GitDiffAlgorithmSetting({
    required this.algorithm,
    required this.configuredValue,
  });

  const GitDiffAlgorithmSetting.gitDefault()
    : algorithm = DiffAlgorithm.myers,
      configuredValue = null;

  final DiffAlgorithm algorithm;
  final String? configuredValue;

  bool get usesGitDefault =>
      configuredValue == null || configuredValue == 'default';

  String get configLabel => configuredValue == null
      ? 'diff.algorithm 미설정'
      : 'diff.algorithm=$configuredValue';

  DiffAlgorithm normalizeSelection(DiffAlgorithm selection) =>
      selection == DiffAlgorithm.gitSetting || selection == algorithm
      ? DiffAlgorithm.gitSetting
      : selection;

  DiffAlgorithm resolveSelection(DiffAlgorithm selection) =>
      selection == DiffAlgorithm.gitSetting ? algorithm : selection;
}

GitDiffAlgorithmSetting parseGitDiffAlgorithmSetting(String? value) {
  final normalized = value?.trim().toLowerCase();
  return switch (normalized) {
    null => const GitDiffAlgorithmSetting.gitDefault(),
    'default' => const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.myers,
      configuredValue: 'default',
    ),
    'myers' => const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.myers,
      configuredValue: 'myers',
    ),
    'minimal' => const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.minimal,
      configuredValue: 'minimal',
    ),
    'patience' => const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.patience,
      configuredValue: 'patience',
    ),
    'histogram' => const GitDiffAlgorithmSetting(
      algorithm: DiffAlgorithm.histogram,
      configuredValue: 'histogram',
    ),
    _ => throw FormatException('Unsupported diff.algorithm: $value'),
  };
}

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
    this.remoteNames = const [],
    this.tags = const [],
    this.current,
    this.tips = const {},
    this.localTips = const {},
    this.birthTimes = const {},
    this.branchActivityTimes = const {},
    this.tagCreatorTimes = const {},
    this.aheadBehind = const {},
    this.remoteAheadBehind = const {},
    this.upstreams = const {},
    this.upstreamRemotes = const {},
  });

  final List<String> local;
  final List<String> remote;
  final List<String> remoteNames;
  final List<String> tags;
  final String? current;

  /// Local branch name → creation unix time, read from the branch's oldest
  /// reflog entry. Absent when the reflog no longer records the birth.
  final Map<String, int> birthTimes;

  /// Local or remote branch name → tip commit unix time.
  final Map<String, int> branchActivityTimes;

  /// Short ref name → tip commit sha, for every entry in the three lists.
  final Map<String, String> tips;

  /// Local branch name → tip commit sha. Unlike [tips], this map cannot be
  /// overwritten by a same-named remote branch or tag.
  final Map<String, String> localTips;

  /// Tag name → creator unix time. Absent when Git has no creator date.
  final Map<String, int> tagCreatorTimes;

  /// Local branch name → commits unique to local and its configured upstream.
  final Map<String, BranchAheadBehind> aheadBehind;

  /// Remote branch name → commits unique to remote and its same-named local.
  final Map<String, BranchAheadBehind> remoteAheadBehind;

  /// Local branch name → configured remote-tracking branch.
  final Map<String, String> upstreams;

  /// Local branch name → remote that owns its configured upstream.
  final Map<String, String> upstreamRemotes;
}

class BranchAheadBehind {
  const BranchAheadBehind({required this.ahead, required this.behind});

  final int ahead;
  final int behind;
}

({String remote, String branch})? splitRemoteBranchName(
  String name,
  Iterable<String> remoteNames,
) {
  final longestFirst = remoteNames.toList()
    ..sort((left, right) => right.length.compareTo(left.length));
  for (final remote in longestFirst) {
    final prefix = '$remote/';
    if (name.startsWith(prefix)) {
      return (remote: remote, branch: name.substring(prefix.length));
    }
  }
  return null;
}

enum FetchOriginResult { updated, unchanged, noOrigin }

enum RemotePullKind { noLocal, fastForward, diverged, upToDate }

/// What selecting a remote branch can do to its local counterpart.
class RemotePullState {
  const RemotePullState({
    required this.remote,
    required this.localBranch,
    required this.kind,
    this.ahead = 0,
    this.behind = 0,
    this.checkedOut = false,
  });

  final String remote;
  final String localBranch;
  final RemotePullKind kind;

  /// Commits only the remote has — what a pull would bring in.
  final int ahead;

  /// Commits only the local branch has.
  final int behind;
  final bool checkedOut;
}

/// Null when [remoteBranch] does not belong to a known remote.
RemotePullState? remotePullState(RepoRefs refs, String remoteBranch) {
  final split = splitRemoteBranchName(remoteBranch, refs.remoteNames);
  if (split == null) return null;
  final localBranch = split.branch;
  if (!refs.local.contains(localBranch)) {
    return RemotePullState(
      remote: split.remote,
      localBranch: localBranch,
      kind: RemotePullKind.noLocal,
    );
  }
  final divergence = refs.remoteAheadBehind[remoteBranch];
  final ahead = divergence?.ahead ?? 0;
  final behind = divergence?.behind ?? 0;
  return RemotePullState(
    remote: split.remote,
    localBranch: localBranch,
    kind: ahead == 0
        ? RemotePullKind.upToDate
        : behind == 0
        ? RemotePullKind.fastForward
        : RemotePullKind.diverged,
    ahead: ahead,
    behind: behind,
    checkedOut: refs.current == localBranch,
  );
}

String? resolveBaseBranch(RepoRefs refs, String? savedBranch) {
  // 원격 브랜치를 기준으로 골라 뒀다면 그대로 되살린다.
  if (savedBranch != null &&
      (refs.local.contains(savedBranch) || refs.remote.contains(savedBranch))) {
    return savedBranch;
  }
  final current = refs.current;
  if (current != null && refs.local.contains(current)) return current;
  return refs.local.isEmpty ? null : refs.local.first;
}

abstract interface class FullDiffRepository {
  String get root;

  Future<GitDiffAlgorithmSetting> loadDiffAlgorithmSetting();

  Future<String> loadCommitMessage(String sha);

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

  @override
  Future<GitDiffAlgorithmSetting> loadDiffAlgorithmSetting() async {
    const args = ['config', '--get', 'diff.algorithm'];
    final result = await runner(gitExecutable, args, workingDirectory: root);
    final value = result.stdout.toString().trim();
    if (result.exitCode == 1 && value.isEmpty) {
      return const GitDiffAlgorithmSetting.gitDefault();
    }
    if (result.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        args,
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return parseGitDiffAlgorithmSetting(value);
  }

  @override
  Future<String> loadCommitMessage(String sha) =>
      _run(['show', '-s', '--format=%B', sha]);

  void invalidateHistory() => _startingRevisions = null;

  /// [hiddenTips] are commits the log should not start from. What they alone
  /// lead to disappears; anything another starting point also reaches stays,
  /// so hiding a branch never takes shared history with it.
  Future<List<GitCommit>> loadHistory({
    int limit = 500,
    int skip = 0,
    Set<String> hiddenTips = const {},
  }) async {
    final all = await (_startingRevisions ??= _loadStartingRevisions());
    final revisions = hiddenTips.isEmpty
        ? all
        : all.where((sha) => !hiddenTips.contains(sha)).toList();
    if (revisions.isEmpty) return const [];
    final args = [
      'log',
      '--topo-order',
      '--date-order',
      '--max-count=$limit',
      '--skip=$skip',
      '--format=$_gitLogFormat',
      ...revisions,
    ];
    return parseGitLog(await _run(args));
  }

  /// Every branch name the `HEAD` reflog still remembers, keyed by the commit
  /// that branch was sitting on. Read once and kept, so the rows asking whose
  /// line they are on never send git anything. A repository with no reflog —
  /// expired, or never written — folds to nothing rather than failing.
  ///
  /// [limit] caps how far back the read goes: an old repository's reflog runs
  /// to tens of megabytes, and the oldest entries name branches nobody is
  /// looking at.
  Future<Map<String, String>> loadReflogBranchNames({int limit = 20000}) async {
    try {
      return deletedBranchNamesFromReflog(
        await _run([
          'reflog',
          'show',
          '--format=%H%x00%gs',
          '-n',
          '$limit',
          'HEAD',
        ]),
      );
    } on ProcessException {
      return const {};
    } on GitRepositoryException {
      return const {};
    }
  }

  Future<String?> loadLocalDeletedBranchName(
    String tipSha,
    Iterable<GitCommit> commits,
  ) async {
    final merged = deletedBranchNameFromMerge(commits, tipSha);
    if (merged != null) return merged;
    try {
      return deletedBranchNameFromReflog(
        await _run(['reflog', 'show', '--format=%H%x00%gs', 'HEAD']),
        tipSha,
      );
    } on ProcessException {
      return null;
    }
  }

  Future<BranchComparisonResult> compareBranches(
    String baseRef,
    String compareRef,
  ) async {
    final baseTip = (await _run([
      'rev-parse',
      '--verify',
      '$baseRef^{commit}',
    ])).trim();
    final compareTip = (await _run([
      'rev-parse',
      '--verify',
      '$compareRef^{commit}',
    ])).trim();
    final baseParent = await _firstParent(baseTip);
    final compareParent = await _firstParent(compareTip);
    final mergeBases = await _mergeBases(baseTip, compareTip);
    final commits = await _comparisonCommits(baseTip, compareTip, mergeBases);
    final files = await _loadFilesBetween(baseTip, compareTip);
    final merge = await _checkMerge(baseTip, compareTip, mergeBases);
    return BranchComparisonResult(
      baseRef: baseRef,
      compareRef: compareRef,
      baseTip: baseTip,
      compareTip: compareTip,
      baseParent: baseParent,
      compareParent: compareParent,
      mergeBases: mergeBases,
      commits: commits,
      files: files,
      merge: merge,
    );
  }

  Future<String?> _firstParent(String tip) async {
    final fields = (await _run([
      'rev-list',
      '--parents',
      '-n',
      '1',
      tip,
    ])).trim().split(RegExp(r'\s+'));
    return fields.length > 1 ? fields[1] : null;
  }

  Future<List<String>> _mergeBases(String baseTip, String compareTip) async {
    final arguments = ['merge-base', '--all', baseTip, compareTip];
    final result = await runner(
      gitExecutable,
      arguments,
      workingDirectory: root,
    );
    if (result.exitCode == 1) return const [];
    if (result.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return result.stdout
        .toString()
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<List<BranchComparisonCommit>> _comparisonCommits(
    String baseTip,
    String compareTip,
    List<String> mergeBases,
  ) async {
    final output = await _run([
      'log',
      '--left-right',
      '--topo-order',
      '--date-order',
      '--format=%m%x1f$_gitLogFormat',
      '$baseTip...$compareTip',
    ]);
    final result = <BranchComparisonCommit>[];
    for (final record
        in output.split('\x1e').where((value) => value.trim().isNotEmpty)) {
      final fields = record.trimLeft().split('\x1f');
      if (fields.length < 12) {
        throw const FormatException('Invalid branch comparison log record');
      }
      final side = switch (fields.first) {
        '<' => BranchCommitSide.baseOnly,
        '>' => BranchCommitSide.compareOnly,
        _ => throw const FormatException('Invalid branch comparison side'),
      };
      result.add(
        BranchComparisonCommit(
          commit: parseGitLog('${fields.skip(1).join('\x1f')}\x1e').single,
          side: side,
        ),
      );
    }
    for (final sha in mergeBases) {
      final commit = parseGitLog(
        await _run(['show', '-s', '--format=$_gitLogFormat', sha]),
      ).single;
      result.add(
        BranchComparisonCommit(
          commit: commit,
          side: BranchCommitSide.commonBoundary,
        ),
      );
    }
    return result;
  }

  Future<MergeConflictCheck> _checkMerge(
    String baseTip,
    String compareTip,
    List<String> mergeBases,
  ) async {
    final arguments = [
      'merge-tree',
      '--write-tree',
      '--name-only',
      '-z',
      baseTip,
      compareTip,
    ];
    final result = await runner(
      gitExecutable,
      arguments,
      workingDirectory: root,
    );
    if (result.exitCode == 0) {
      final treeSha = result.stdout.toString().split('\x00').first.trim();
      final resultFiles = await _loadFilesBetween(baseTip, treeSha);
      // Criss-cross histories have several common ancestors in no set order,
      // so a file counts as ours once it changed since any one of them.
      final baseChangedFiles = {
        for (final base in mergeBases) ...await _changedPaths(base, baseTip),
      };
      return MergeConflictCheck(
        status: MergeConflictStatus.clean,
        treeSha: treeSha,
        resultFiles: resultFiles,
        baseChangedFiles: baseChangedFiles,
        proximity: await _proximityRegions(
          baseTip: baseTip,
          compareTip: compareTip,
          treeSha: treeSha,
          mergeBases: mergeBases,
          resultFiles: resultFiles,
          baseChangedFiles: baseChangedFiles,
        ),
      );
    }
    if (result.exitCode != 1) {
      return MergeConflictCheck(
        status: MergeConflictStatus.failed,
        error: result.stderr.toString().trim(),
      );
    }
    final fields = result.stdout.toString().split('\x00');
    final detailsStart = fields.indexOf('');
    final files = <String>{};
    for (
      var index = detailsStart + 1;
      detailsStart >= 0 && index + 3 < fields.length;
      index += 4
    ) {
      if (fields[index + 2].startsWith('CONFLICT')) {
        files.add(fields[index + 1]);
      }
    }
    return MergeConflictCheck(
      status: MergeConflictStatus.conflicts,
      files: files.toList(),
    );
  }

  /// Where the two sides edited close enough to read each other's work, for the
  /// files both of them touched. Line spans come back in merge-result
  /// coordinates so a click can land on the result diff.
  Future<Map<String, List<LineSpan>>> _proximityRegions({
    required String baseTip,
    required String compareTip,
    required String treeSha,
    required List<String> mergeBases,
    required List<GitFileChange> resultFiles,
    required Set<String> baseChangedFiles,
  }) async {
    final candidates = [
      for (final file in resultFiles)
        if (baseChangedFiles.contains(file.path) ||
            baseChangedFiles.contains(file.oldPath))
          file,
    ];
    // ponytail: 수백 개를 넘는 병합은 인자 길이 한계에 가까워지니 신호를 접는다.
    // 그런 병합이 실제로 나오면 경로를 나눠 여러 번 돌리면 된다.
    if (candidates.isEmpty || candidates.length > 500) return const {};
    final paths = [for (final file in candidates) ...pathspecsFor(file)];
    final spans = <String, List<LineSpan>>{};
    for (final base in mergeBases) {
      final ours = await _hunkRangesByFile(base, baseTip, paths);
      final theirs = await _hunkRangesByFile(base, compareTip, paths);
      final result = await _hunkRangesByFile(base, treeSha, paths);
      for (final file in candidates) {
        final ourSpans = _editedSpans(ours, file);
        final theirSpans = _editedSpans(theirs, file);
        if (ourSpans.isEmpty || theirSpans.isEmpty) continue;
        final near = _nearSpans(ourSpans, theirSpans);
        if (near.isEmpty) continue;
        final toResult = _lineMapper(_rangesFor(result, file));
        (spans[file.path] ??= []).addAll(
          near.map(
            // 파일 맨 위에 줄을 끼워 넣으면 hunk의 oldStart가 0이라 결과 좌표도
            // 0이 되는데 0번째 줄은 없으니 첫 줄로 당긴다.
            (span) => (
              startLine: max(1, toResult(span.startLine)),
              endLine: toResult(span.endLine),
            ),
          ),
        );
      }
    }
    return {
      for (final file in spans.entries) file.key: _mergeSpans(file.value),
    };
  }

  /// Lines one side rewrote, in merge-base coordinates. 끼워 넣기만 한 hunk는 지운
  /// 줄이 없어서 새 줄이 oldStart와 그 다음 줄 사이에 들어가니, 양쪽 이웃에 다 닿는
  /// 구간으로 잡아야 고친 줄과 같은 거리로 재진다.
  List<LineSpan> _editedSpans(
    Map<String, List<_HunkRange>> ranges,
    GitFileChange file,
  ) => [
    for (final hunk in _rangesFor(ranges, file))
      (
        startLine: hunk.oldStart,
        endLine: hunk.oldCount == 0
            ? hunk.oldStart + 1
            : hunk.oldStart + hunk.oldCount - 1,
      ),
  ];

  List<_HunkRange> _rangesFor(
    Map<String, List<_HunkRange>> ranges,
    GitFileChange file,
  ) => ranges[file.path] ?? ranges[file.oldPath] ?? const [];

  /// Every file's hunk ranges from one diff, keyed by both of its paths so a
  /// rename answers under either name. `-U0` keeps a hunk per edit instead of
  /// gluing neighbours together with context, and the indicator overrides stop a
  /// removed `--- a/x` line inside a patch file from reading as a file header.
  Future<Map<String, List<_HunkRange>>> _hunkRangesByFile(
    String from,
    String to,
    List<String> paths,
  ) async {
    final output = await _run([
      // 기본 설정은 한글 같은 non-ASCII 경로를 따옴표로 감싸 escape하니, 헤더에서
      // 뽑은 이름이 GitFileChange.path와 안 맞게 된다.
      '-c',
      'core.quotePath=false',
      'diff',
      ...safeDiffArguments,
      '-U0',
      // diff.noprefix 같은 설정을 쓰는 사용자에게도 헤더가 'a/'·'b/'로 시작해야
      // 아래에서 두 글자를 떼는 계산이 맞는다.
      '--src-prefix=a/',
      '--dst-prefix=b/',
      '--output-indicator-old=<',
      '--output-indicator-new=>',
      from,
      to,
      '--',
      ...paths,
    ]);
    final ranges = <String, List<_HunkRange>>{};
    var current = <_HunkRange>[];
    for (final line in output.split('\n')) {
      if (line.startsWith('diff --git ')) {
        current = <_HunkRange>[];
      } else if (line.startsWith('--- ') || line.startsWith('+++ ')) {
        var path = line.substring(4);
        // 공백이 든 경로는 git이 헤더 끝에 탭을 붙여 이름의 끝을 표시한다.
        if (path.endsWith('\t')) path = path.substring(0, path.length - 1);
        // 'a/'·'b/' 접두사를 떼면 저장소 기준 경로가 남고 두 이름이 같은 목록을
        // 가리키니 이름이 바뀐 파일도 한쪽 이름으로 찾을 수 있다.
        if (path != '/dev/null') ranges[path.substring(2)] = current;
      } else if (_diffHunkRange.firstMatch(line) case final hunk?) {
        current.add((
          oldStart: int.parse(hunk.group(1)!),
          oldCount: int.parse(hunk.group(2) ?? '1'),
          newStart: int.parse(hunk.group(3)!),
          newCount: int.parse(hunk.group(4) ?? '1'),
        ));
      }
    }
    return ranges;
  }

  Future<RebaseCheckResult> simulateRebase({
    required String baseRef,
    required String compareRef,
  }) async {
    final session = await openRebasePreview(
      baseRef: baseRef,
      compareRef: compareRef,
    );
    try {
      final result = await session.start();
      return switch (result.status) {
        RebasePreviewStatus.clean => const RebaseCheckResult(
          status: RebaseCheckStatus.clean,
        ),
        RebasePreviewStatus.conflict => RebaseCheckResult(
          status: RebaseCheckStatus.conflicts,
          stoppedCommit: result.currentCommit?.sha,
          files: result.conflictFiles,
        ),
        RebasePreviewStatus.failed => RebaseCheckResult(
          status: RebaseCheckStatus.failed,
          error: result.error,
        ),
      };
    } finally {
      await session.dispose();
    }
  }

  /// Which way the measured git facts lean for this comparison, or null when
  /// they conflict or say too little — a wrong recommendation is worse than
  /// none. Pass [rebaseCheck] when a simulation already ran, so the engine does
  /// not pay for a second one.
  Future<BranchRecommendation?> recommendBranchIntegration({
    required BranchComparisonResult comparison,
    RebaseCheckResult? rebaseCheck,
  }) async {
    if (comparison.mergeBases.isEmpty) return null;
    final counts = (await _run([
      'rev-list',
      '--left-right',
      '--count',
      '${comparison.baseTip}...${comparison.compareTip}',
    ])).trim().split(RegExp(r'\s+'));
    final baseAhead = int.tryParse(counts.first) ?? 0;
    final compareAhead = counts.length > 1 ? int.tryParse(counts[1]) ?? 0 : 0;
    // 기준 브랜치가 갈라진 뒤 안 움직였으면 fast-forward로 끝나고 가져올 커밋이
    // 없으면 할 일 자체가 없다. 둘 다 추천할 게 없는 자리다.
    if (baseAhead == 0 || compareAhead == 0) return null;

    final sharing = await _remoteSharingOf(comparison);
    // 이름만 같은 남의 브랜치인지 원격에서 다시 쓴 공유 브랜치인지 못 가리면 공유
    // 여부부터 틀릴 수 있으니 아무 추천도 하지 않는다.
    if (sharing?.unrelated ?? false) return null;
    if (sharing != null) {
      final reasons = [
        '브랜치가 원격 ${sharing.ref}에도 있어서 히스토리를 다시 쓰면 같이 쓰는 사람이 다칩니다',
      ];
      if (!sharing.tipMatches) {
        final unpushed =
            int.tryParse(
              (await _run([
                'rev-list',
                '--count',
                '${sharing.tip}..${comparison.compareTip}',
              ])).trim(),
            ) ??
            0;
        if (unpushed > 0) {
          reasons.add(
            '원격 ${sharing.ref}에 없는 커밋 $unpushed개가 로컬에 남아 있어도 '
            '브랜치는 이미 원격에 올라가 있습니다',
          );
        }
      }
      return BranchRecommendation(
        verdict: BranchIntegrationVerdict.merge,
        summary: '원격에 공유된 브랜치',
        reasons: reasons,
      );
    }

    final check =
        rebaseCheck ??
        await simulateRebase(
          baseRef: comparison.baseRef,
          compareRef: comparison.compareRef,
        );
    // 어느 한쪽을 재보지 못했으면 멈춘 횟수를 말할 수 없다.
    if (check.status == RebaseCheckStatus.failed ||
        comparison.merge.status == MergeConflictStatus.failed) {
      return null;
    }
    final mergeClean = comparison.merge.status == MergeConflictStatus.clean;
    final rebaseClean = check.status == RebaseCheckStatus.clean;
    if (!mergeClean && !rebaseClean) return null;
    const localOnly = '브랜치가 로컬 전용이라 히스토리를 다시 써도 아무도 안 다칩니다';
    if (!rebaseClean) {
      return BranchRecommendation(
        verdict: BranchIntegrationVerdict.merge,
        summary: '재배치는 충돌에서 멈춤',
        reasons: [
          'Rebase 시뮬레이션은 충돌 파일 ${check.files.length}개에서 멈추지만 '
              'Merge는 충돌이 없습니다',
        ],
      );
    }
    if (!mergeClean) {
      return BranchRecommendation(
        verdict: BranchIntegrationVerdict.rebase,
        summary: '근거 2',
        reasons: [
          'Merge는 충돌 파일 ${comparison.merge.files.length}개에서 멈추지만 '
              'Rebase 미리보기는 커밋 $compareAhead개를 전부 재생했습니다',
          localOnly,
        ],
      );
    }

    final mergeBase = comparison.mergeBases.first;
    final internalMerges =
        int.tryParse(
          (await _run([
            'rev-list',
            '--merges',
            '--count',
            '$mergeBase..${comparison.compareTip}',
          ])).trim(),
        ) ??
        0;
    // 재배치가 브랜치 안의 머지 커밋을 펴 버리니 어느 쪽도 자신 있게 못 고른다.
    if (internalMerges > 0) return null;
    final duplicates = (await duplicateCompareCommits(
      baseTip: comparison.baseTip,
      compareTip: comparison.compareTip,
    )).length;
    final share = await _mergeCommitShare(comparison.baseTip);
    // 커밋 몇 개짜리 히스토리로는 관례를 말할 수 없고, 남은 신호만으로는 어느 쪽도
    // 못 고른다.
    if (share.total < conventionSampleFloor) return null;
    final ratio = share.merges / share.total;
    final duplicateReason = duplicates > 0
        ? '이미 ${comparison.baseRef}에 들어간 커밋 $duplicates개는 재배치하면 알아서 빠집니다'
        : null;
    if (ratio >= 0.4) {
      // 관례 근거가 이 판정을 그냥 Rebase와 갈라놓는 유일한 사실이라 세 개로 자를 때
      // 밀려나면 안 된다. 밀려도 되는 쪽은 중복 커밋 이야기다.
      final reasons = [
        localOnly,
        'Rebase 미리보기 $compareAhead개 커밋 전부 충돌 없이 재생됐습니다',
        '최근 ${comparison.baseRef} 커밋 ${share.total}개 중 ${share.merges}개가 머지 커밋 — 이 저장소의 관례입니다',
        ?duplicateReason,
      ].take(3).toList();
      return BranchRecommendation(
        verdict: BranchIntegrationVerdict.rebaseThenMerge,
        summary: '근거 ${reasons.length}',
        reasons: reasons,
      );
    }
    // 관례가 선형이거나, 관례가 어느 쪽도 아니어도 재배치가 떨궈 줄 중복 커밋이
    // 있으면 Rebase로 기운다. 중복 근거가 있으면 세 개로 자를 때 관례 쪽이 밀린다 —
    // 이 판정에서 관례는 갈림길이 아니다.
    if (ratio < 0.15 || duplicates > 0) {
      return BranchRecommendation(
        verdict: BranchIntegrationVerdict.rebase,
        summary: '커밋 $compareAhead개 · 선형 유지',
        reasons: [
          localOnly,
          'Rebase 미리보기 $compareAhead개 커밋 전부 충돌 없이 재생됐습니다',
          ?duplicateReason,
          '최근 ${comparison.baseRef} 커밋 ${share.total}개 중 머지 커밋은 ${share.merges}개뿐이라 선형 히스토리가 관례입니다',
        ].take(3).toList(),
      );
    }
    // 관례가 어느 쪽도 아니라 남은 신호로는 고를 수 없다.
    return null;
  }

  /// The remote-tracking ref carrying the compared branch, or null when the
  /// branch only exists locally. A remote tip that trails unpushed local commits
  /// still counts as shared: the branch is already out there. A same-named
  /// remote ref settles it first; otherwise the branch's own upstream does, but
  /// only when it resolves under refs/remotes/ — an upstream can be a local
  /// branch, which says nothing about sharing. [unrelated] marks the case the
  /// match cannot settle — a remote tip that is neither the local tip nor its
  /// ancestor, so it may be a teammate's own branch or this one rebased on the
  /// remote.
  Future<({String ref, String tip, bool tipMatches, bool unrelated})?>
  _remoteSharingOf(BranchComparisonResult comparison) async {
    final compareRef = comparison.compareRef;
    final separator = compareRef.indexOf('/');
    final short = separator > 0 && !await _localBranchExists(compareRef)
        ? compareRef.substring(separator + 1)
        : compareRef;
    // 이름이 같아도 같은 히스토리라는 뜻은 아니다. 원격 tip이 로컬 tip이거나 그
    // 조상일 때만 이 브랜치가 올라가 있다고 말할 수 있다.
    Future<({String ref, String tip, bool tipMatches, bool unrelated})> sharing(
      String ref,
      String tip,
    ) async => (
      ref: ref,
      tip: tip,
      tipMatches: tip == comparison.compareTip,
      unrelated:
          tip != comparison.compareTip &&
          (await runner(gitExecutable, [
                'merge-base',
                '--is-ancestor',
                tip,
                comparison.compareTip,
              ], workingDirectory: root)).exitCode !=
              0,
    );
    for (final line in (await _run([
      'for-each-ref',
      '--format=%(refname:short)%09%(objectname)',
      'refs/remotes',
    ])).split('\n')) {
      final fields = line.trim().split('\t');
      if (fields.length < 2) continue;
      final slash = fields.first.indexOf('/');
      if (slash <= 0 || fields.first.substring(slash + 1) != short) continue;
      return sharing(fields.first, fields[1]);
    }
    // 이름이 다른 원격을 추적하고 있을 수도 있다. 다만 upstream은 로컬 브랜치일 수도
    // 있어서(`git branch --set-upstream-to=main feature`) 그건 공유와 무관하다 —
    // refs/remotes/로 풀리는 upstream만 원격 공유로 읽는다.
    const remotePrefix = 'refs/remotes/';
    final upstream = await runner(gitExecutable, [
      'rev-parse',
      '--symbolic-full-name',
      '$compareRef@{upstream}',
    ], workingDirectory: root);
    final name = upstream.stdout.toString().trim();
    if (upstream.exitCode != 0 || !name.startsWith(remotePrefix)) return null;
    final tip = (await runner(gitExecutable, [
      'rev-parse',
      '--verify',
      '--quiet',
      '$name^{commit}',
    ], workingDirectory: root)).stdout.toString().trim();
    // upstream 설정만 남고 원격 ref가 사라졌으면 무엇과 공유 중인지 말할 수 없다.
    return tip.isEmpty
        ? null
        : sharing(name.substring(remotePrefix.length), tip);
  }

  Future<bool> _localBranchExists(String branch) async =>
      (await runner(gitExecutable, [
        'rev-parse',
        '--verify',
        '--quiet',
        'refs/heads/$branch',
      ], workingDirectory: root)).exitCode ==
      0;

  /// How many of the base branch's last 50 first-parent commits are merge
  /// commits — this repository's own convention, measured rather than assumed.
  /// `--parents` rewrites parents under `--first-parent`, so the shas take a
  /// second pass to be counted.
  Future<({int merges, int total})> _mergeCommitShare(String tip) async {
    final shas = (await _run([
      'rev-list',
      '--first-parent',
      '--max-count=50',
      tip,
    ])).split('\n').where((line) => line.trim().isNotEmpty).toList();
    if (shas.isEmpty) return (merges: 0, total: 0);
    final merges = int.tryParse(
      (await _run([
        'rev-list',
        '--no-walk',
        '--min-parents=2',
        '--count',
        ...shas,
      ])).trim(),
    );
    return (merges: merges ?? 0, total: shas.length);
  }

  Future<MergePreviewSession> openMergePreview({
    required String baseRef,
    required String compareRef,
  }) async => MergePreviewSession(
    repository: this,
    baseTip: (await _run([
      'rev-parse',
      '--verify',
      '$baseRef^{commit}',
    ])).trim(),
    compareTip: (await _run([
      'rev-parse',
      '--verify',
      '$compareRef^{commit}',
    ])).trim(),
  );

  Future<RebasePreviewSession> openRebasePreview({
    required String baseRef,
    required String compareRef,
  }) async {
    final baseTip = (await _run([
      'rev-parse',
      '--verify',
      '$baseRef^{commit}',
    ])).trim();
    final compareTip = (await _run([
      'rev-parse',
      '--verify',
      '$compareRef^{commit}',
    ])).trim();
    final originalCommits = parseGitLog(
      await _run([
        'log',
        '--reverse',
        '--format=$_gitLogFormat',
        '$baseTip..$compareTip',
      ]),
    );
    return RebasePreviewSession(
      repository: this,
      baseTip: baseTip,
      compareTip: compareTip,
      originalCommits: originalCommits,
    );
  }

  /// Paths [to] changed since [from], both ends of a rename, so a merge result
  /// can name the files the base branch touched as well.
  Future<Set<String>> _changedPaths(String from, String to) async => {
    for (final status in _parseNameStatus(
      await _run([
        'diff',
        ...safeDiffArguments,
        '--name-status',
        '-z',
        from,
        to,
        '--',
      ]),
    )) ...[status.path, ?status.oldPath],
  };

  Future<void> _removePreviewWorktree(String path) async {
    await _ignoreCommand([
      'worktree',
      'remove',
      '--force',
      path,
    ], workingDirectory: root);
    final directory = Directory(path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await _ignoreCommand(const ['worktree', 'prune'], workingDirectory: root);
  }

  Future<void> cleanupStalePreviewWorktrees() async {
    final result = await runner(gitExecutable, const [
      'worktree',
      'list',
      '--porcelain',
    ], workingDirectory: root);
    if (result.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        const ['worktree', 'list', '--porcelain'],
        result.stderr.toString(),
        result.exitCode,
      );
    }
    final paths = result.stdout
        .toString()
        .split('\n')
        .where((line) => line.startsWith('worktree '))
        .map((line) => line.substring('worktree '.length))
        .where(_isYogitPreviewPath);
    for (final path in paths) {
      await _ignoreCommand([
        'worktree',
        'remove',
        '--force',
        path,
      ], workingDirectory: root);
      final directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
    await _ignoreCommand(const ['worktree', 'prune'], workingDirectory: root);
  }

  /// [message] is the merge commit's message, verbatim — subject, blank line,
  /// body and all. Omitting it keeps git's own wording.
  Future<BranchApplyResult> applyMergePreview({
    required BranchComparisonResult comparison,
    required String treeSha,
    String? message,
  }) async {
    final refs = await _verifyApplyTips(comparison);
    final target = resolveBranchApplyTarget(
      mode: BranchApplyMode.merge,
      comparison: comparison,
      refs: refs,
    );
    if (target == null || target.needsRecalculation) {
      throw GitRepositoryException(root, '로컬 기준 브랜치로 미리보기를 다시 계산해야 합니다.');
    }
    final tree = (await _run([
      'rev-parse',
      '--verify',
      '$treeSha^{tree}',
    ])).trim();
    final mergeCommit = (await _run([
      '-c',
      'commit.gpgSign=false',
      'commit-tree',
      tree,
      '-p',
      comparison.baseTip,
      '-p',
      comparison.compareTip,
      '-m',
      message ??
          "Merge branch '${comparison.compareRef}' into ${comparison.baseRef}",
    ])).trim();
    // A base branch that is not the checked-out one only has its ref moved, so
    // the user's working directory is never yanked from under them.
    final workingTreeUpdated = await _moveLocalBranch(
      branch: target.localBranch,
      expected: target.selectedTip,
      next: mergeCommit,
    );
    return BranchApplyResult(
      mode: BranchApplyMode.merge,
      baseBranch: target.localBranch,
      compareBranch: comparison.compareRef,
      baseBefore: comparison.baseTip,
      baseAfter: await _localBranchTip(target.localBranch),
      compareBefore: comparison.compareTip,
      compareAfter: comparison.compareTip,
      workingTreeUpdated: workingTreeUpdated,
    );
  }

  Future<BranchApplyResult> applyRebasePreview({
    required BranchComparisonResult comparison,
    required String virtualTip,
  }) async {
    final refs = await _verifyApplyTips(comparison);
    final rewrittenTip = (await _run([
      'rev-parse',
      '--verify',
      '$virtualTip^{commit}',
    ])).trim();
    final target = resolveBranchApplyTarget(
      mode: BranchApplyMode.rebase,
      comparison: comparison,
      refs: refs,
    );
    if (target == null || target.needsRecalculation) {
      throw GitRepositoryException(root, '기존 로컬 브랜치 기준으로 미리보기를 다시 계산해야 합니다.');
    }

    var created = false;
    try {
      if (target.createsBranch) {
        await _run([
          'branch',
          '--no-track',
          target.localBranch,
          target.selectedTip,
        ]);
        created = true;
        await _run([
          'branch',
          '--set-upstream-to=${target.selectedRef}',
          target.localBranch,
        ]);
        final refreshedRefs = await loadRefs();
        if (await _refTip(target.selectedRef, refreshedRefs) !=
                target.selectedTip ||
            await _localBranchTip(target.localBranch) != target.selectedTip) {
          throw GitRepositoryException(
            target.localBranch,
            '원격 브랜치가 바뀌어 미리보기를 다시 계산해야 합니다.',
          );
        }
      }
      final workingTreeUpdated = await _moveLocalBranch(
        branch: target.localBranch,
        expected: target.selectedTip,
        next: rewrittenTip,
      );
      return BranchApplyResult(
        mode: BranchApplyMode.rebase,
        baseBranch: comparison.baseRef,
        compareBranch: target.localBranch,
        baseBefore: comparison.baseTip,
        baseAfter: comparison.baseTip,
        compareBefore: comparison.compareTip,
        compareAfter: await _localBranchTip(target.localBranch),
        compareBranchCreated: created,
        workingTreeUpdated: workingTreeUpdated,
      );
    } catch (_) {
      if (created) {
        try {
          await _deleteLocalBranch(
            branch: target.localBranch,
            expected: target.selectedTip,
          );
        } on Object {
          // 예상 SHA가 아니면 사용자 작업일 수 있으므로 남긴다.
        }
      }
      rethrow;
    }
  }

  /// Moves the compared branch onto the rebased tip and then walks the base
  /// branch onto a merge commit over it. Both moves follow the same rules as the
  /// single-step applies: only a checked-out branch touches disk. [message] is
  /// the merge commit's message, verbatim; omitting it keeps git's own wording.
  Future<BranchApplyResult> applyRebaseThenMerge({
    required BranchComparisonResult comparison,
    required String virtualTip,
    String? message,
  }) async {
    final refs = await _verifyApplyTips(comparison);
    final baseTarget = resolveBranchApplyTarget(
      mode: BranchApplyMode.merge,
      comparison: comparison,
      refs: refs,
    );
    final compareTarget = resolveBranchApplyTarget(
      mode: BranchApplyMode.rebase,
      comparison: comparison,
      refs: refs,
    );
    if (baseTarget == null ||
        baseTarget.needsRecalculation ||
        compareTarget == null ||
        compareTarget.needsRecalculation) {
      throw GitRepositoryException(root, '기존 로컬 브랜치 기준으로 미리보기를 다시 계산해야 합니다.');
    }
    // 두 브랜치 중 하나라도 다른 worktree가 들고 있으면 아무것도 옮기기 전에 멈춘다.
    final current = (await _run(['branch', '--show-current'])).trim();
    for (final branch in {baseTarget.localBranch, compareTarget.localBranch}) {
      if (branch != current && await branchWorktreePath(branch) != null) {
        throw GitRepositoryException(
          branch,
          '다른 worktree에서 체크아웃한 브랜치라 적용할 수 없습니다.',
        );
      }
    }
    final rewrittenTip = (await _run([
      'rev-parse',
      '--verify',
      '$virtualTip^{commit}',
    ])).trim();
    // 재배치 결과가 기준 브랜치 그 자체면 부모가 하나뿐인 빈 커밋이 만들어지고,
    // 그 커밋은 머지가 아닌데 머지라고 적힌 히스토리가 된다.
    if (rewrittenTip == comparison.baseTip) {
      throw GitRepositoryException(root, '재배치 결과가 기준 브랜치와 같아 만들 머지 커밋이 없습니다.');
    }
    // 재배치 결과가 기준 브랜치 위에 얹혀 있어야 그 트리가 곧 병합 결과다.
    final ancestry = await runner(gitExecutable, [
      'merge-base',
      '--is-ancestor',
      comparison.baseTip,
      rewrittenTip,
    ], workingDirectory: root);
    if (ancestry.exitCode != 0) {
      throw GitRepositoryException(
        root,
        '재배치 결과가 기준 브랜치 위에 없어 머지 커밋을 만들 수 없습니다.',
      );
    }
    final tree = (await _run([
      'rev-parse',
      '--verify',
      '$rewrittenTip^{tree}',
    ])).trim();

    final rebased = await applyRebasePreview(
      comparison: comparison,
      virtualTip: virtualTip,
    );
    try {
      final mergeCommit = (await _run([
        '-c',
        'commit.gpgSign=false',
        'commit-tree',
        tree,
        '-p',
        comparison.baseTip,
        '-p',
        rewrittenTip,
        '-m',
        message ??
            "Merge branch '${comparison.compareRef}' into ${comparison.baseRef}",
      ])).trim();
      final baseUpdated = await _moveLocalBranch(
        branch: baseTarget.localBranch,
        expected: baseTarget.selectedTip,
        next: mergeCommit,
      );
      return BranchApplyResult(
        mode: BranchApplyMode.rebaseMerge,
        baseBranch: baseTarget.localBranch,
        compareBranch: rebased.compareBranch,
        baseBefore: comparison.baseTip,
        baseAfter: await _localBranchTip(baseTarget.localBranch),
        compareBefore: comparison.compareTip,
        compareAfter: rebased.compareAfter,
        compareBranchCreated: rebased.compareBranchCreated,
        workingTreeUpdated: baseUpdated,
        compareWorkingTreeUpdated: rebased.workingTreeUpdated,
      );
    } catch (error) {
      try {
        await restoreBranchApply(rebased);
      } on Object catch (rollbackError) {
        throw GitRepositoryException(
          root,
          '${baseTarget.localBranch}는 ${comparison.baseTip}에 그대로 있지만 '
          '${rebased.compareBranch}를 ${rebased.compareBefore}으로 되돌리지 못했습니다. '
          '지금 ${rebased.compareBranch}는 ${rebased.compareAfter}입니다. '
          '($error / $rollbackError)',
        );
      }
      rethrow;
    }
  }

  Future<void> restoreBranchApply(BranchApplyResult result) async {
    if (result.mode == BranchApplyMode.rebaseMerge) {
      if (await _localBranchTip(result.baseBranch) != result.baseAfter ||
          await _localBranchTip(result.compareBranch) != result.compareAfter) {
        throw GitRepositoryException(root, '적용 뒤 브랜치가 바뀌어 이전 시점으로 되돌릴 수 없습니다.');
      }
      Future<void> restoreBase() => _moveLocalBranch(
        branch: result.baseBranch,
        expected: result.baseAfter,
        next: result.baseBefore,
      );
      Future<void> restoreCompare() async {
        if (result.compareBranchCreated) {
          await _deleteLocalBranch(
            branch: result.compareBranch,
            expected: result.compareAfter,
          );
          return;
        }
        await _moveLocalBranch(
          branch: result.compareBranch,
          expected: result.compareAfter,
          next: result.compareBefore,
        );
      }

      // 체크아웃된 브랜치만 더러운 작업 트리에 막히니 그 쪽을 먼저 되돌린다. 순서가
      // 반대면 한쪽만 되돌아간 채로 끝나고, 그 뒤로는 적용 시점 SHA가 안 맞아 다시
      // 시도할 수도 없다.
      final current = (await _run(['branch', '--show-current'])).trim();
      final compareFirst = current == result.compareBranch;
      await (compareFirst ? restoreCompare() : restoreBase());
      try {
        await (compareFirst ? restoreBase() : restoreCompare());
      } on Object catch (error) {
        final restored = compareFirst
            ? result.compareBranch
            : result.baseBranch;
        final stuck = compareFirst ? result.baseBranch : result.compareBranch;
        throw GitRepositoryException(
          root,
          '되돌리는 중에 멈췄습니다. $restored 브랜치는 '
          '${compareFirst ? result.compareBefore : result.baseBefore}으로 '
          '되돌렸지만 $stuck 브랜치는 '
          '${compareFirst ? result.baseAfter : result.compareAfter}에 '
          '그대로 있습니다. ($error)',
        );
      }
      return;
    }
    if (result.mode == BranchApplyMode.merge) {
      if (await _localBranchTip(result.baseBranch) != result.baseAfter) {
        throw GitRepositoryException(root, '적용 뒤 브랜치가 바뀌어 이전 시점으로 되돌릴 수 없습니다.');
      }
      await _moveLocalBranch(
        branch: result.baseBranch,
        expected: result.baseAfter,
        next: result.baseBefore,
      );
      return;
    }
    if (result.compareBranchCreated) {
      await _deleteLocalBranch(
        branch: result.compareBranch,
        expected: result.compareAfter,
      );
      return;
    }
    if (await _localBranchTip(result.compareBranch) != result.compareAfter) {
      throw GitRepositoryException(root, '적용 뒤 브랜치가 바뀌어 이전 시점으로 되돌릴 수 없습니다.');
    }
    await _moveLocalBranch(
      branch: result.compareBranch,
      expected: result.compareAfter,
      next: result.compareBefore,
    );
  }

  Future<String> _refTip(String ref, RepoRefs refs) async {
    final fullRef = refs.local.contains(ref)
        ? 'refs/heads/$ref'
        : refs.remote.contains(ref)
        ? 'refs/remotes/$ref'
        : null;
    if (fullRef == null) {
      throw GitRepositoryException(ref, '브랜치를 찾을 수 없습니다.');
    }
    return (await _run(['rev-parse', '--verify', '$fullRef^{commit}'])).trim();
  }

  Future<RepoRefs> _verifyApplyTips(BranchComparisonResult comparison) async {
    final refs = await loadRefs();
    if (await _refTip(comparison.baseRef, refs) != comparison.baseTip ||
        await _refTip(comparison.compareRef, refs) != comparison.compareTip) {
      throw GitRepositoryException(root, '브랜치가 바뀌어 미리보기를 다시 계산해야 합니다.');
    }
    return refs;
  }

  Future<String> _localBranchTip(String branch) async {
    final result = await runner(gitExecutable, [
      'rev-parse',
      '--verify',
      'refs/heads/$branch^{commit}',
    ], workingDirectory: root);
    final sha = result.stdout.toString().trim();
    if (result.exitCode != 0 || sha.isEmpty) {
      throw GitRepositoryException(branch, '로컬 브랜치를 찾을 수 없습니다.');
    }
    return sha;
  }

  Future<void> _deleteLocalBranch({
    required String branch,
    required String expected,
  }) async {
    if (await _localBranchTip(branch) != expected) {
      throw GitRepositoryException(branch, '브랜치가 바뀌어 삭제하지 않았습니다.');
    }
    await _run(['branch', '-D', branch]);
  }

  /// The worktree that has [branch] checked out, or null.
  Future<String?> branchWorktreePath(String branch) async {
    final output = await _run(['worktree', 'list', '--porcelain']);
    String? path;
    for (final line in output.split('\n')) {
      if (line.startsWith('worktree ')) {
        path = line.substring('worktree '.length);
      } else if (line == 'branch refs/heads/$branch') {
        return path;
      } else if (line.isEmpty) {
        path = null;
      }
    }
    return null;
  }

  Future<void> _requireCleanWorktree() async {
    if (await _gitOperationInProgress()) {
      throw GitRepositoryException(root, '다른 Git 작업이 진행 중입니다.');
    }
    if ((await _run(['status', '--porcelain=v1', '-z'])).isNotEmpty) {
      throw GitRepositoryException(root, '작업 트리와 인덱스가 깨끗해야 실제 적용할 수 있습니다.');
    }
  }

  /// Whether the working tree was updated too, i.e. [branch] was the checked-out
  /// one and the reset brought [next] to disk. A branch checked out nowhere only
  /// has its ref moved, so a dirty working tree is none of its business.
  Future<bool> _moveLocalBranch({
    required String branch,
    required String expected,
    required String next,
  }) async {
    if (await _localBranchTip(branch) != expected) {
      throw GitRepositoryException(branch, '브랜치가 바뀌어 작업을 중단했습니다.');
    }
    final current = (await _run(['branch', '--show-current'])).trim();
    if (current == branch) {
      await _requireCleanWorktree();
      await _run(['reset', '--hard', next]);
      return true;
    }
    final worktreePath = await branchWorktreePath(branch);
    if (worktreePath != null) {
      throw GitRepositoryException(
        branch,
        '다른 worktree에서 체크아웃한 브랜치라 적용할 수 없습니다.',
      );
    }
    await _run(['update-ref', 'refs/heads/$branch', next, expected]);
    return false;
  }

  Future<CherryPickResult> cherryPick(String sha) async {
    final commitSha = await _cherryPickPreflight(sha);
    final arguments = ['cherry-pick', commitSha];
    return _cherryPickResult(await _runCherryPickCommand(arguments), arguments);
  }

  Future<CherryPickState?> loadCherryPickState() async {
    final head = await runner(gitExecutable, const [
      'rev-parse',
      '--verify',
      '-q',
      'CHERRY_PICK_HEAD',
    ], workingDirectory: root);
    final commitSha = head.stdout.toString().trim();
    if (head.exitCode != 0 || commitSha.isEmpty) return null;
    final conflicts = await runner(gitExecutable, const [
      'diff',
      '--name-only',
      '--diff-filter=U',
      '-z',
    ], workingDirectory: root);
    if (conflicts.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        const ['diff', '--name-only', '--diff-filter=U', '-z'],
        conflicts.stderr.toString(),
        conflicts.exitCode,
      );
    }
    return CherryPickState(
      commitSha: commitSha,
      conflicts: conflicts.stdout
          .toString()
          .split('\x00')
          .where((path) => path.isNotEmpty)
          .toList(),
    );
  }

  Future<CherryPickResult> continueCherryPick() async {
    final state = await loadCherryPickState();
    if (state == null) {
      throw GitRepositoryException(root, '진행 중인 체리픽이 없습니다.');
    }
    if (!state.canContinue) {
      throw GitRepositoryException(root, '충돌 파일을 모두 해결해야 계속할 수 있습니다.');
    }
    const arguments = ['-c', 'core.editor=true', 'cherry-pick', '--continue'];
    return _cherryPickResult(await _runCherryPickCommand(arguments), arguments);
  }

  Future<void> abortCherryPick() async {
    if (await loadCherryPickState() == null) {
      throw GitRepositoryException(root, '진행 중인 체리픽이 없습니다.');
    }
    await _run(['cherry-pick', '--abort']);
  }

  Future<void> stageResolvedFile(String relativePath) async {
    await resolveWorkingTreeFile(root, relativePath);
    final pathspec = ':(literal)$relativePath';
    final check = await runner(gitExecutable, [
      'diff',
      '--check',
      '--',
      pathspec,
    ], workingDirectory: root);
    final output = '${check.stdout}\n${check.stderr}';
    if (output.contains('leftover conflict marker')) {
      throw GitRepositoryException(relativePath, '충돌 표시가 남아 있습니다.');
    }
    if (check.exitCode > 1) {
      throw ProcessException(
        gitExecutable,
        ['diff', '--check', '--', pathspec],
        check.stderr.toString(),
        check.exitCode,
      );
    }
    await _run(['add', '--', pathspec]);
  }

  Future<String> _cherryPickPreflight(String sha) async {
    final current = (await _run(['branch', '--show-current'])).trim();
    if (current.isEmpty) {
      throw GitRepositoryException(root, '분리된 HEAD에서는 체리픽할 수 없습니다.');
    }
    final branch = await runner(gitExecutable, [
      'show-ref',
      '--verify',
      '--quiet',
      'refs/heads/$current',
    ], workingDirectory: root);
    if (branch.exitCode != 0) {
      throw GitRepositoryException(root, '현재 로컬 브랜치를 찾을 수 없습니다.');
    }
    if (await _gitOperationInProgress()) {
      throw GitRepositoryException(root, '다른 Git 작업이 진행 중입니다.');
    }
    if ((await _run(['status', '--porcelain=v1', '-z'])).isNotEmpty) {
      throw GitRepositoryException(root, '작업 트리와 인덱스가 깨끗해야 합니다.');
    }
    final verify = await runner(gitExecutable, [
      'rev-parse',
      '--verify',
      '--end-of-options',
      '$sha^{commit}',
    ], workingDirectory: root);
    final commitSha = verify.stdout.toString().trim();
    if (verify.exitCode != 0 || commitSha.isEmpty) {
      throw GitRepositoryException(sha, '유효한 커밋이 아닙니다.');
    }
    final ancestor = await runner(gitExecutable, [
      'merge-base',
      '--is-ancestor',
      commitSha,
      'HEAD',
    ], workingDirectory: root);
    if (ancestor.exitCode == 0) {
      throw GitRepositoryException(sha, '이미 현재 브랜치에 포함된 커밋입니다.');
    }
    if (ancestor.exitCode != 1) {
      throw ProcessException(
        gitExecutable,
        ['merge-base', '--is-ancestor', commitSha, 'HEAD'],
        ancestor.stderr.toString(),
        ancestor.exitCode,
      );
    }
    return commitSha;
  }

  Future<bool> operationInProgress() => _gitOperationInProgress();

  Future<bool> _gitOperationInProgress() async {
    for (final name in const [
      'CHERRY_PICK_HEAD',
      'MERGE_HEAD',
      'REBASE_HEAD',
    ]) {
      final result = await runner(gitExecutable, [
        'rev-parse',
        '--verify',
        '-q',
        name,
      ], workingDirectory: root);
      if (result.exitCode == 0) return true;
    }
    final gitDirectory = (await _run([
      'rev-parse',
      '--absolute-git-dir',
    ])).trim();
    return Directory('$gitDirectory/rebase-merge').existsSync() ||
        Directory('$gitDirectory/rebase-apply').existsSync();
  }

  Future<ProcessResult> _runCherryPickCommand(List<String> arguments) => runner(
    gitExecutable,
    arguments,
    workingDirectory: root,
    environment: {
      ...Platform.environment,
      'GIT_EDITOR': 'true',
      'GIT_TERMINAL_PROMPT': '0',
    },
  );

  Future<CherryPickResult> _cherryPickResult(
    ProcessResult result,
    List<String> arguments,
  ) async {
    if (result.exitCode == 0) {
      return CherryPickResult(
        outcome: CherryPickOutcome.applied,
        headSha: (await _run(['rev-parse', 'HEAD'])).trim(),
      );
    }
    final state = await loadCherryPickState();
    if (state != null && state.conflicts.isNotEmpty) {
      return CherryPickResult(
        outcome: CherryPickOutcome.conflicts,
        state: state,
      );
    }
    if (state != null) {
      final staged = await runner(gitExecutable, const [
        'diff',
        '--cached',
        '--quiet',
      ], workingDirectory: root);
      if (staged.exitCode == 0) {
        await _run(['cherry-pick', '--skip']);
        return CherryPickResult(
          outcome: CherryPickOutcome.empty,
          headSha: (await _run(['rev-parse', 'HEAD'])).trim(),
        );
      }
    }
    throw ProcessException(
      gitExecutable,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  }

  bool _isYogitPreviewPath(String path) {
    final directory = Directory(path).absolute;
    // `git worktree list`는 심볼릭 링크를 푼 경로를 찍는다(macOS의 /var는
    // /private/var 링크다). 두 모양 다 systemTemp로 인정해야 우리가 만든
    // worktree를 우리가 알아본다.
    if (!{
      Directory.systemTemp.absolute.path,
      Directory.systemTemp.resolveSymbolicLinksSync(),
    }.contains(directory.parent.path)) {
      return false;
    }
    final name = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (name.startsWith(RegExp(r'yogit_(?:merge|rebase)_preview_'))) {
      return true;
    }
    // 예고 프로브는 지금 돌고 있을 수 있다. 그래서 오래된 것만 청소한다 — 강제
    // 종료로 남은 디렉터리는 사라지고 진행 중 프로브는 건드리지 않는다. 디렉터리가
    // 이미 없으면 stat이 1970년을 주니 등록만 남은 것도 함께 정리된다.
    if (!name.startsWith('yogit_conflict_probe_')) return false;
    return DateTime.now().difference(directory.statSync().modified) >
        staleConflictProbeAge;
  }

  Future<void> _ignoreCommand(
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    try {
      await runner(
        gitExecutable,
        arguments,
        workingDirectory: workingDirectory,
      );
    } on ProcessException {
      // Best-effort cleanup continues with the remaining owned resources.
    }
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

  Future<List<GitFileChange>> _loadFilesBetween(
    String fromRef,
    String toRef,
  ) async {
    final statuses = _parseNameStatus(
      await _run([
        'diff',
        ...safeDiffArguments,
        '--name-status',
        '-z',
        fromRef,
        toRef,
        '--',
      ]),
    );
    final stats = _parseNumstat(
      await _run([
        'diff',
        ...safeDiffArguments,
        '--numstat',
        '-z',
        fromRef,
        toRef,
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
    final resultSizes = await _loadLsTreeSizes(
      toRef,
      files
          .where((file) => !file.status.startsWith('D'))
          .map((file) => file.path),
    );
    final deletedSizes = await _loadLsTreeSizes(
      fromRef,
      files
          .where((file) => file.status.startsWith('D'))
          .map((file) => file.oldPath ?? file.path),
    );
    return [
      for (final file in files)
        _copyWithSize(
          file,
          file.status.startsWith('D')
              ? deletedSizes[file.oldPath ?? file.path]
              : resultSizes[file.path],
        ),
    ];
  }

  Future<List<GitFileChange>> loadFilesBetween(String fromRef, String toRef) =>
      _loadFilesBetween(fromRef, toRef);

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

  Future<List<DiffLine>> loadDiffBetween(
    String fromRef,
    String toRef,
    GitFileChange file, {
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
    bool ignoreWhitespace = false,
    DiffScope scope = DiffScope.hunks,
  }) async {
    final arguments = [
      'diff',
      ...safeDiffArguments,
      '--unified=${scope == DiffScope.hunks ? 3 : fullDiffTextLineLimit}',
      if (ignoreWhitespace) '--ignore-all-space',
      ...algorithm.gitArguments,
      fromRef,
      toRef,
      '--',
      ...pathspecsFor(file),
    ];
    final output = scope == DiffScope.hunks
        ? await _run(arguments)
        : await _runDiff(arguments);
    return parseUnifiedDiff(output);
  }

  /// The unmerged stage blobs of [relativePath] — 1 base, 2 ours, 3 theirs.
  /// Empty when git records no conflict for the path.
  Future<Map<int, String>> _conflictFileStages(
    String worktreePath,
    String relativePath,
  ) async {
    _previewFilePath(worktreePath, relativePath);
    final arguments = ['ls-files', '-u', '-z', '--', ':(literal)$relativePath'];
    final unmerged = await runner(
      gitExecutable,
      arguments,
      workingDirectory: worktreePath,
    );
    if (unmerged.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        arguments,
        unmerged.stderr.toString(),
        unmerged.exitCode,
      );
    }
    final stages = <int, String>{};
    final record = RegExp(r'^[^ ]+ ([0-9a-f]+) ([123])\t');
    for (final line in unmerged.stdout.toString().split('\x00')) {
      if (record.firstMatch(line) case final match?) {
        stages[int.parse(match.group(2)!)] = match.group(1)!;
      }
    }
    return stages;
  }

  /// P1a — 스테이징하려는 내용에 git이 써 넣은 충돌 마커가 남아 있으면 거부한다.
  /// 근거는 세 stage 블롭뿐이다: 그 블롭들이 이미 갖고 있던 마커 모양 행(문서 속
  /// 예시 같은 것)은 원래 파일 내용이라 통과시킨다.
  Future<void> _rejectConflictMarkerResidue(
    String worktreePath,
    String relativePath,
  ) async {
    final file = File(_previewFilePath(worktreePath, relativePath));
    if (!file.existsSync()) return;
    final lines = const LineSplitter().convert(
      utf8.decode(await file.readAsBytes(), allowMalformed: true),
    );
    final markers = [
      for (var at = 0; at < lines.length; at++)
        if (isConflictMarkerLine(lines[at])) (line: lines[at], number: at + 1),
    ];
    if (markers.isEmpty) return;
    final stages = await _conflictFileStages(worktreePath, relativePath);
    // 스테이지 기록이 없으면 git은 이 파일을 충돌로 보지 않는다 — 대조할 근거가
    // 없으니 판정도 하지 않는다.
    if (stages.isEmpty) return;
    final known = <String>{};
    for (final blob in stages.values) {
      final show = await runner(gitExecutable, [
        'cat-file',
        'blob',
        blob,
      ], workingDirectory: worktreePath);
      if (show.exitCode != 0) continue;
      known.addAll(
        const LineSplitter()
            .convert(show.stdout.toString())
            .where(isConflictMarkerLine),
      );
    }
    for (final marker in markers) {
      if (!known.contains(marker.line)) {
        throw ConflictMarkerResidueException(relativePath, marker.number);
      }
    }
  }

  /// P3 — 세 stage 블롭을 diff3로 병합해 충돌 구역을 읽는다. 모든 구역에서 base가
  /// 비어 있으면(양쪽 모두 순수 추가) 순서만 고르면 되는 파일이라 후보로 돌려준다.
  /// 저장소의 코드를 코드로 읽는 곳은 없다 — 보는 것은 블롭과 마커 행뿐이다.
  Future<KeepBothCandidate?> _keepBothCandidate(
    String worktreePath,
    String relativePath,
  ) async {
    final stages = await _conflictFileStages(worktreePath, relativePath);
    if (stages.length != 3) return null;
    // merge-file은 stdin이 아니라 파일 경로 세 개를 받는다. worktree를 더럽히지
    // 않도록 저장소 plumbing 디렉터리에 풀어 놓고 바로 지운다.
    final gitDir = await runner(gitExecutable, const [
      'rev-parse',
      '--absolute-git-dir',
    ], workingDirectory: worktreePath);
    if (gitDir.exitCode != 0) return null;
    final scratch = await Directory(
      gitDir.stdout.toString().trim(),
    ).createTemp('yogit_keep_both_');
    try {
      for (final stage in const {1: 'base', 2: 'ours', 3: 'theirs'}.entries) {
        final blob = await runner(gitExecutable, [
          'cat-file',
          'blob',
          stages[stage.key]!,
        ], workingDirectory: worktreePath);
        if (blob.exitCode != 0) return null;
        final content = blob.stdout.toString();
        // merge-file 출력의 내용 행은 전부 이 세 블롭에서 온다. 어느 블롭이든 마커
        // 모양 행을 이미 갖고 있으면 파서가 내용과 진짜 마커를 구분할 수 없으니
        // 제안을 내지 않는다 — 어설픈 제안은 없느니만 못하다.
        if (const LineSplitter().convert(content).any(isConflictMarkerLine)) {
          return null;
        }
        // 블롭 바이트가 UTF-8로 왕복되지 않으면(EUC-KR 등) 결합 결과에 대체 문자가
        // 섞인다. 바이트를 보존할 수 없는 파일에도 제안을 내지 않는다. 디코딩 자체가
        // 실패하는 경우는 아래 FormatException이 받는다.
        final size = await runner(gitExecutable, [
          'cat-file',
          '-s',
          stages[stage.key]!,
        ], workingDirectory: worktreePath);
        if (size.exitCode != 0 ||
            int.tryParse(size.stdout.toString().trim()) !=
                utf8.encode(content).length) {
          return null;
        }
        await File(
          '${scratch.path}${Platform.pathSeparator}${stage.value}',
        ).writeAsString(content);
      }
      final merged = await runner(gitExecutable, [
        'merge-file',
        '-p',
        '--diff3',
        '${scratch.path}${Platform.pathSeparator}ours',
        '${scratch.path}${Platform.pathSeparator}base',
        '${scratch.path}${Platform.pathSeparator}theirs',
      ], workingDirectory: worktreePath);
      // merge-file의 종료 코드는 충돌 구역 수다(127에서 잘린다). 그보다 크면 실패.
      if (merged.exitCode > 127) return null;
      return parseKeepBothCandidate(merged.stdout.toString());
    } on FormatException {
      // 블롭이 UTF-8로 디코딩되지 않는 파일이다 — 바이트를 그대로 옮길 수 없으니
      // 제안하지 않는다.
      return null;
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  /// P1b — patch-id가 이미 base에 있는 비교 커밋들. `git cherry`의 `-` 항목이고
  /// 추천 엔진이 개수만 쓰던 그 신호를 커밋 단위로 돌려준다.
  Future<Set<String>> duplicateCompareCommits({
    required String baseTip,
    required String compareTip,
  }) async => {
    for (final line in const LineSplitter().convert(
      await _run(['cherry', baseTip, compareTip]),
    ))
      if (line.startsWith('- ')) line.substring(2).trim(),
  };

  /// P2 — 브랜치 커밋을 하나씩 [baseTip] 위에 단독으로 얹어 보고 충돌 파일을 모은다.
  /// 커밋 sha → 충돌 파일 목록. 단독 재생은 순차 재배치와 다르다 — 그 경고는 배지
  /// 툴팁이 한다. [cancelled]가 참이 되면 다음 커밋으로 넘어가지 않고 정리한다.
  ///
  /// patch-id가 이미 base에 있는 커밋은 재생해 보지 않는다. `git rebase`가 기본값
  /// 그대로(--no-reapply-cherry-picks) 그 커밋을 떨구니 단독 재생이 충돌해도 순차
  /// 재배치에서는 일어날 수 없는 충돌이다. 변경이 이미 적용돼 있어서 충돌하는 것이다.
  /// 건너뛴 커밋은 예고 항목이 아예 없다.
  Future<Map<String, List<String>>> probeRebaseConflicts({
    required String baseTip,
    required String compareTip,
    required List<String> commits,
    bool Function()? cancelled,
  }) async {
    if (commits.isEmpty || commits.length > conflictForecastCommitCeiling) {
      return const {};
    }
    final duplicates = await duplicateCompareCommits(
      baseTip: baseTip,
      compareTip: compareTip,
    );
    final replayed = [
      for (final sha in commits)
        if (!duplicates.contains(sha)) sha,
    ];
    if (replayed.isEmpty) return const {};
    // stale 청소는 이 접두사를 [staleConflictProbeAge]가 지난 뒤에만 건드린다 —
    // 예고가 도는 중에 다른 미리보기가 청소를 돌려도 발밑이 사라지지 않는다.
    final temporary = await Directory.systemTemp.createTemp(
      'yogit_conflict_probe_',
    );
    final path = temporary.path;
    await temporary.delete();
    final add = await runner(gitExecutable, [
      'worktree',
      'add',
      '--detach',
      path,
      baseTip,
    ], workingDirectory: root);
    if (add.exitCode != 0) {
      await _removePreviewWorktree(path);
      return const {};
    }
    final forecast = <String, List<String>>{};
    try {
      for (final sha in replayed) {
        if (cancelled?.call() ?? false) break;
        final pick = await runner(
          gitExecutable,
          [
            '-c',
            'core.hooksPath=/dev/null',
            '-c',
            'rerere.enabled=false',
            'cherry-pick',
            '--no-commit',
            sha,
          ],
          workingDirectory: path,
          environment: {
            ...Platform.environment,
            'GIT_EDITOR': 'true',
            'GIT_TERMINAL_PROMPT': '0',
          },
        );
        if (pick.exitCode != 0) {
          final unmerged = await runner(gitExecutable, const [
            'diff',
            '--name-only',
            '--diff-filter=U',
            '-z',
          ], workingDirectory: path);
          final files = unmerged.stdout
              .toString()
              .split('\x00')
              .where((value) => value.isNotEmpty)
              .toList();
          if (files.isNotEmpty) forecast[sha] = files;
        }
        await _ignoreCommand(const [
          'cherry-pick',
          '--abort',
        ], workingDirectory: path);
        await _ignoreCommand([
          'reset',
          '--hard',
          baseTip,
        ], workingDirectory: path);
        await _ignoreCommand(const ['clean', '-fdq'], workingDirectory: path);
      }
    } finally {
      await _removePreviewWorktree(path);
    }
    return forecast;
  }

  Future<List<DiffLine>> _loadPreviewConflictDiff(
    String worktreePath,
    String relativePath,
  ) async {
    final pathspec = ':(literal)$relativePath';
    final stages = await _conflictFileStages(worktreePath, relativePath);
    if (stages.isEmpty) {
      return _runPreviewDiff(worktreePath, [
        'diff',
        ...safeDiffArguments,
        '--unified=3',
        '--cached',
        'HEAD',
        '--',
        pathspec,
      ]);
    }
    final before = stages[2];
    final after = stages[3];
    if (before != null && after != null) {
      return _runPreviewDiff(worktreePath, [
        'diff',
        ...safeDiffArguments,
        '--unified=3',
        before,
        after,
        '--',
      ]);
    }
    final blob = before ?? after!;
    final show = await runner(gitExecutable, [
      'show',
      blob,
    ], workingDirectory: worktreePath);
    if (show.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        ['show', blob],
        show.stderr.toString(),
        show.exitCode,
      );
    }
    final text = show.stdout.toString();
    final content = text.endsWith('\n')
        ? text.substring(0, text.length - 1)
        : text;
    final lines = content.isEmpty ? const <String>[] : content.split('\n');
    return [
      DiffLine(
        kind: DiffLineKind.header,
        text: before == null ? '--- /dev/null' : '--- a/$relativePath',
      ),
      DiffLine(
        kind: DiffLineKind.header,
        text: after == null ? '+++ /dev/null' : '+++ b/$relativePath',
      ),
      DiffLine(
        kind: DiffLineKind.hunk,
        text: before == null
            ? '@@ -0,0 +1,${lines.length} @@'
            : '@@ -1,${lines.length} +0,0 @@',
      ),
      for (var index = 0; index < lines.length; index++)
        DiffLine(
          kind: before == null ? DiffLineKind.add : DiffLineKind.delete,
          text: lines[index],
          oldNumber: before == null ? null : index + 1,
          newNumber: before == null ? index + 1 : null,
        ),
    ];
  }

  Future<List<DiffLine>> _runPreviewDiff(
    String worktreePath,
    List<String> arguments,
  ) async {
    final result = await runner(
      gitExecutable,
      arguments,
      workingDirectory: worktreePath,
    );
    if (result.exitCode > 1) {
      throw ProcessException(
        gitExecutable,
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return parseUnifiedDiff(result.stdout.toString());
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
    final remoteNames = (await _run([
      'remote',
    ])).split('\n').where((name) => name.isNotEmpty).toList();
    final lines = (await _run([
      'for-each-ref',
      '--format=%(refname)%00%(objectname)%00%(creatordate:unix)'
          '%00%(upstream:short)%00%(upstream:remotename)',
      'refs/heads',
      'refs/remotes',
      'refs/tags',
    ])).split('\n').where((line) => line.isNotEmpty);
    final local = <String>[];
    final remote = <String>[];
    final tags = <String>[];
    final tips = <String, String>{};
    final localTips = <String, String>{};
    final branchActivityTimes = <String, int>{};
    final tagCreatorTimes = <String, int>{};
    final upstreams = <String, String>{};
    final upstreamRemotes = <String, String>{};
    final buckets = {
      'refs/heads/': local,
      'refs/remotes/': remote,
      'refs/tags/': tags,
    };
    for (final line in lines) {
      final fields = line.split('\x00');
      if (fields.length != 5) {
        throw FormatException('Invalid ref metadata: $line');
      }
      final [name, sha, creatorField, upstream, upstreamRemote] = fields;
      final creatorTime = int.tryParse(creatorField);
      for (final bucket in buckets.entries) {
        if (!name.startsWith(bucket.key)) continue;
        final short = name.substring(bucket.key.length);
        // `origin/HEAD` is an alias for another branch, not a branch of its own.
        if (bucket.value == remote && _isRemoteHeadAlias(short)) break;
        bucket.value.add(short);
        tips[short] = sha;
        if (bucket.value == local) {
          localTips[short] = sha;
          if (upstream.isNotEmpty &&
              upstreamRemote.isNotEmpty &&
              upstreamRemote != '.') {
            upstreams[short] = upstream;
            upstreamRemotes[short] = upstreamRemote;
          }
        }
        if (bucket.value == tags && creatorTime != null) {
          tagCreatorTimes[short] = creatorTime;
        }
        if ((bucket.value == local || bucket.value == remote) &&
            creatorTime != null) {
          branchActivityTimes[short] = creatorTime;
        }
        break;
      }
    }
    final births = await Future.wait(local.map(_birthTime));
    final aheadBehind = <String, BranchAheadBehind>{};
    for (final entry in upstreams.entries) {
      if (!remote.contains(entry.value)) continue;
      aheadBehind[entry.key] = await _loadAheadBehind(entry.key, entry.value);
    }
    final remoteAheadBehind = <String, BranchAheadBehind>{};
    for (final remoteBranch in remote) {
      final split = splitRemoteBranchName(remoteBranch, remoteNames);
      if (split == null) continue;
      final localBranch = split.branch;
      if (!local.contains(localBranch)) continue;
      final localDifference = upstreams[localBranch] == remoteBranch
          ? aheadBehind[localBranch]!
          : await _loadAheadBehind(localBranch, remoteBranch);
      remoteAheadBehind[remoteBranch] = BranchAheadBehind(
        ahead: localDifference.behind,
        behind: localDifference.ahead,
      );
    }
    final current = (await _run(['branch', '--show-current'])).trim();
    return RepoRefs(
      local: local,
      remote: remote,
      remoteNames: remoteNames,
      tags: tags,
      current: current.isEmpty ? null : current,
      tips: tips,
      localTips: localTips,
      branchActivityTimes: branchActivityTimes,
      tagCreatorTimes: tagCreatorTimes,
      birthTimes: {
        for (var index = 0; index < local.length; index++)
          local[index]: ?births[index],
      },
      aheadBehind: aheadBehind,
      remoteAheadBehind: remoteAheadBehind,
      upstreams: upstreams,
      upstreamRemotes: upstreamRemotes,
    );
  }

  Future<BranchAheadBehind> _loadAheadBehind(
    String branch,
    String upstream,
  ) async {
    final counts = (await _run([
      'rev-list',
      '--left-right',
      '--count',
      'refs/heads/$branch...refs/remotes/$upstream',
    ])).trim().split(RegExp(r'\s+'));
    if (counts.length != 2) {
      throw FormatException('Invalid ahead/behind counts for $branch');
    }
    return BranchAheadBehind(
      ahead: int.parse(counts[0]),
      behind: int.parse(counts[1]),
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

  Future<FetchOriginResult> fetchOrigin() async {
    if (await loadOriginUrl() == null) return FetchOriginResult.noOrigin;
    return fetchRemote('origin');
  }

  Future<FetchOriginResult> fetchRemote(String remote) async {
    final arguments = [
      '-c',
      'credential.interactive=never',
      'fetch',
      '--porcelain',
      '--prune',
      remote,
    ];
    final result = await runner(
      gitExecutable,
      arguments,
      workingDirectory: root,
      environment: {
        ...Platform.environment,
        'GIT_TERMINAL_PROMPT': '0',
        'GCM_INTERACTIVE': 'Never',
      },
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return result.stdout.toString().trim().isEmpty
        ? FetchOriginResult.unchanged
        : FetchOriginResult.updated;
  }

  /// Fast-forwards the local counterpart of `remote/branch`. The checked-out
  /// branch needs a real pull; any other branch fast-forwards in place with a
  /// fetch refspec, without touching the working tree.
  Future<void> pullRemoteBranch(
    String remote,
    String branch, {
    required bool checkedOut,
  }) => _runWithoutPrompts([
    '-c',
    'credential.interactive=never',
    if (checkedOut) ...[
      'pull',
      '--ff-only',
      remote,
      branch,
    ] else ...[
      'fetch',
      remote,
      '$branch:$branch',
    ],
  ]);

  Future<void> checkoutRemoteBranch(
    String remote,
    String branch, {
    required bool createLocal,
  }) => _runWithoutPrompts([
    'switch',
    if (createLocal) ...[
      '-c',
      branch,
      '--track',
      '$remote/$branch',
    ] else
      branch,
  ]);

  /// Deletes a local branch outright. Git itself refuses while the branch is
  /// checked out here or in another worktree, so that guard lives with it.
  Future<void> deleteLocalBranch(String branch) =>
      _run(['branch', '-D', branch]);

  /// Switches the checkout to an existing local branch.
  Future<void> checkoutLocalBranch(String branch) => _run(['switch', branch]);

  /// Where this repository keeps its refs: [gitDir] is this worktree's own
  /// (holding its `HEAD`), [commonDir] the shared one every worktree borrows
  /// refs from. They are the same directory outside a linked worktree.
  Future<({String gitDir, String commonDir})?> loadGitDirectories() async {
    try {
      final result = await runner(gitExecutable, const [
        'rev-parse',
        '--path-format=absolute',
        '--absolute-git-dir',
        '--git-common-dir',
      ], workingDirectory: root);
      if (result.exitCode != 0) return null;
      final lines = result.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.length < 2) return null;
      return (gitDir: lines[0], commonDir: lines[1]);
    } on ProcessException {
      return null;
    }
  }

  /// A cheap fingerprint of the repository's local state: where `HEAD` points
  /// plus every local branch tip. Comparing two readings spots a checkout,
  /// commit, or branch edit made outside the app without reloading the whole
  /// ref list. Null when Git cannot answer, so a transient failure reads as
  /// "unknown" rather than as "everything vanished".
  Future<String?> loadLocalStateSignature() async {
    try {
      // Two reads, because `for-each-ref` does not match HEAD: without the
      // first one a checkout between two existing branches moves no tip and
      // the fingerprint would not change at all. The symbolic name is part of
      // it so switching between branches on the same commit still counts.
      final head = await runner(gitExecutable, const [
        'rev-parse',
        'HEAD',
        '--symbolic-full-name',
        'HEAD',
      ], workingDirectory: root);
      final tips = await runner(gitExecutable, const [
        'for-each-ref',
        '--format=%(refname) %(objectname)',
        'refs/heads',
      ], workingDirectory: root);
      if (head.exitCode != 0 || tips.exitCode != 0) return null;
      return '${head.stdout.toString().trim()}\n'
          '${tips.stdout.toString().trim()}';
    } on ProcessException {
      // A watcher must never be the thing that breaks the screen, so a git
      // that cannot even be launched reads as "unknown" too.
      return null;
    }
  }

  /// Who this repository commits as right now, global config included. Empty
  /// strings where Git has nothing, so the caller can warn instead of guessing.
  Future<GitIdentity> loadCommitIdentity() async {
    Future<String> read(String key) async {
      final result = await runner(gitExecutable, [
        'config',
        '--get',
        key,
      ], workingDirectory: root);
      return result.exitCode == 0 ? result.stdout.toString().trim() : '';
    }

    return GitIdentity(
      name: await read('user.name'),
      email: await read('user.email'),
    );
  }

  /// Writes the identity into this repository's own config, so the CLI and
  /// every other Git tool see the same author the app shows.
  Future<void> setLocalCommitIdentity(GitIdentity identity) async {
    await _run(['config', '--local', 'user.name', identity.name]);
    await _run(['config', '--local', 'user.email', identity.email]);
  }

  /// Removes a worktree along with its directory, even when dirty.
  Future<void> removeWorktree(String path) =>
      _run(['worktree', 'remove', '--force', path]);

  /// The last [limit] commits reachable from [ref], newest first. Lines that
  /// do not parse are skipped — one odd reflog entry should not blank the
  /// monitor's lane.
  Future<List<({String sha, String subject, String author, int time})>>
  loadRecentCommits(String ref, {int limit = 20}) async {
    final output = await _run([
      'log',
      ref,
      '-n',
      '$limit',
      '--format=%H%x00%s%x00%an%x00%ct',
    ]);
    return [
      for (final line in output.split('\n'))
        if (line.split('\x00') case [
          final sha,
          final subject,
          final author,
          final time,
        ] when int.tryParse(time) != null)
          (sha: sha, subject: subject, author: author, time: int.parse(time)),
    ];
  }

  /// Like [_run], but with every interactive credential prompt disabled so a
  /// network command fails instead of hanging the app on a hidden prompt.
  Future<void> _runWithoutPrompts(List<String> arguments) async {
    final result = await runner(
      gitExecutable,
      arguments,
      workingDirectory: root,
      environment: {
        ...Platform.environment,
        'GIT_TERMINAL_PROMPT': '0',
        'GCM_INTERACTIVE': 'Never',
      },
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        gitExecutable,
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
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
typedef _HunkRange = ({int oldStart, int oldCount, int newStart, int newCount});

final _diffHunkRange = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
  multiLine: true,
);

/// Maps a line number through [hunks] into the other side's coordinates. A line
/// inside a rewritten hunk lands on that hunk's start; everything else shifts by
/// what the hunks before it added or removed.
int Function(int) _lineMapper(List<_HunkRange> hunks) => (line) {
  var delta = 0;
  for (final hunk in hunks) {
    if (hunk.oldCount > 0 &&
        line >= hunk.oldStart &&
        line <= hunk.oldStart + hunk.oldCount - 1) {
      return hunk.newStart;
    }
    final oldEnd = hunk.oldCount == 0
        ? hunk.oldStart
        : hunk.oldStart + hunk.oldCount - 1;
    if (oldEnd < line) delta += hunk.newCount - hunk.oldCount;
  }
  return line + delta;
};

/// Spans covering an edit from each side that touch or sit within
/// [proximityLineGap] lines of one another.
List<LineSpan> _nearSpans(List<LineSpan> ours, List<LineSpan> theirs) => [
  for (final ourSpan in ours)
    for (final theirSpan in theirs)
      if (_spanGap(ourSpan, theirSpan) <= proximityLineGap)
        (
          startLine: min(ourSpan.startLine, theirSpan.startLine),
          endLine: max(ourSpan.endLine, theirSpan.endLine),
        ),
];

int _spanGap(LineSpan left, LineSpan right) => left.startLine > right.endLine
    ? left.startLine - right.endLine
    : right.startLine > left.endLine
    ? right.startLine - left.endLine
    : 0;

/// Overlapping spans read as one region, so a file's regions never double-count
/// the same lines.
List<LineSpan> _mergeSpans(List<LineSpan> spans) {
  final sorted = [...spans]
    ..sort((left, right) => left.startLine.compareTo(right.startLine));
  final merged = <LineSpan>[];
  for (final span in sorted) {
    final last = merged.isEmpty ? null : merged.last;
    if (last != null && span.startLine <= last.endLine) {
      merged[merged.length - 1] = (
        startLine: last.startLine,
        endLine: max(last.endLine, span.endLine),
      );
      continue;
    }
    merged.add(span);
  }
  return merged;
}

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
