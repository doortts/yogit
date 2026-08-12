/// The working tree as `git status --porcelain=v2` reports it: one path
/// carrying two states at once, the index axis and the worktree axis.
///
/// `GitFileChange` cannot hold that — its status is a single letter, and
/// untrackedness rides on an `Expando` beside it — so the commit panel reads
/// the two axes here and projects one of them into a `GitFileChange` when a
/// diff view needs the older shape.
library;

import 'git.dart' show GitFileChange;

/// Which side of the index a row belongs to. Unstaged is worktree ↔ index,
/// staged is index ↔ HEAD.
enum WorkingTreeArea { unstaged, staged }

/// One `git diff --numstat` cell. Binary paths count nothing, matching
/// numstat's own `-` fields.
typedef NumstatCounts = ({int? additions, int? deletions, bool isBinary});

/// The letter an untracked file wears in the Unstaged section — porcelain v2
/// gives a `?` record no XY pair, and the panel reads a new file as an add.
const _untrackedLetter = 'A';

class WorkingTreeEntry {
  const WorkingTreeEntry({
    required this.path,
    required this.indexStatus,
    required this.worktreeStatus,
    this.origPath,
    this.untracked = false,
    this.conflicted = false,
    this.submodule = false,
    this.symlink = false,
    this.unstagedAdditions,
    this.unstagedDeletions,
    this.stagedAdditions,
    this.stagedDeletions,
    this.unstagedBinary = false,
    this.stagedBinary = false,
  });

  final String path;

  /// Only a rename or copy record has one, and it is the path the change
  /// started from.
  final String? origPath;

  /// X. `.`, `M`, `T`, `A`, `D`, `R`, `C` — or the conflict's own XY letter.
  final String indexStatus;

  /// Y, from the same set.
  final String worktreeStatus;

  final bool untracked;
  final bool conflicted;
  final bool submodule;
  final bool symlink;

  final int? unstagedAdditions;
  final int? unstagedDeletions;
  final int? stagedAdditions;
  final int? stagedDeletions;
  final bool unstagedBinary;
  final bool stagedBinary;

  bool get inUnstaged => untracked || conflicted || worktreeStatus != '.';

  bool get inStaged => !untracked && !conflicted && indexStatus != '.';

  WorkingTreeEntry _withCounts(NumstatCounts? unstaged, NumstatCounts? staged) =>
      WorkingTreeEntry(
        path: path,
        origPath: origPath,
        indexStatus: indexStatus,
        worktreeStatus: worktreeStatus,
        untracked: untracked,
        conflicted: conflicted,
        submodule: submodule,
        symlink: symlink,
        unstagedAdditions: unstaged?.additions,
        unstagedDeletions: unstaged?.deletions,
        stagedAdditions: staged?.additions,
        stagedDeletions: staged?.deletions,
        unstagedBinary: unstaged?.isBinary ?? false,
        stagedBinary: staged?.isBinary ?? false,
      );
}

class WorkingTreeStatus {
  const WorkingTreeStatus(this.entries);

  final List<WorkingTreeEntry> entries;

  /// An `MM` path is in both sections at once, as the same entry.
  List<WorkingTreeEntry> get unstaged =>
      entries.where((entry) => entry.inUnstaged).toList();

  List<WorkingTreeEntry> get staged =>
      entries.where((entry) => entry.inStaged).toList();

  bool get hasConflict => entries.any((entry) => entry.conflicted);
}

/// Space-separated fields ahead of the path, per record type.
const _leadingFields = {'1': 8, '2': 9, 'u': 10};

/// Parses `git status --porcelain=v2 --untracked-files=all -z` output.
List<WorkingTreeEntry> parseStatusV2(String output) {
  final records = output.split('\x00');
  final entries = <WorkingTreeEntry>[];
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    if (record.isEmpty) continue;
    final type = record[0];
    if (type == '?') {
      if (record.length < 3 || record[1] != ' ') continue;
      final path = record.substring(2);
      entries.add(
        WorkingTreeEntry(
          path: path,
          indexStatus: '.',
          worktreeStatus: _untrackedLetter,
          untracked: true,
        ),
      );
      continue;
    }
    final leading = _leadingFields[type];
    if (leading == null) continue;
    final split = _splitRecord(record, leading);
    if (split == null) continue;
    final (fields, path) = split;
    final xy = fields[1];
    if (xy.length < 2) continue;
    entries.add(
      WorkingTreeEntry(
        path: path,
        origPath: type == '2' && index + 1 < records.length
            ? records[++index]
            : null,
        indexStatus: xy[0],
        worktreeStatus: xy[1],
        conflicted: type == 'u',
        submodule: fields[2].startsWith('S'),
        symlink: fields
            .sublist(3, type == 'u' ? 7 : 6)
            .contains('120000'),
      ),
    );
  }
  return entries;
}

/// Splits off [leading] space-separated fields; the rest is the path, spaces
/// and all. Null when the record is too short to hold them.
(List<String>, String)? _splitRecord(String record, int leading) {
  var cut = 0;
  for (var field = 0; field < leading; field++) {
    cut = record.indexOf(' ', cut);
    if (cut < 0) return null;
    cut += 1;
  }
  final path = record.substring(cut);
  if (path.isEmpty) return null;
  return (record.substring(0, cut - 1).split(' '), path);
}

/// Puts `git diff --numstat` counts on the axis they were measured for, keyed
/// by path. Untracked and conflicted paths have no diff to count and keep
/// their nulls.
List<WorkingTreeEntry> mergeNumstat(
  List<WorkingTreeEntry> entries, {
  Map<String, NumstatCounts> unstaged = const {},
  Map<String, NumstatCounts> staged = const {},
}) => [
  for (final entry in entries)
    if (entry.untracked || entry.conflicted)
      entry
    else
      entry._withCounts(unstaged[entry.path], staged[entry.path]),
];

/// The `GitFileChange` [entry] shows as in [area], or null when that area does
/// not hold it. The letter is the area's own axis — Unstaged reads Y, Staged
/// reads X.
GitFileChange? areaFileChange(WorkingTreeEntry entry, WorkingTreeArea area) {
  final unstaged = area == WorkingTreeArea.unstaged;
  if (unstaged ? !entry.inUnstaged : !entry.inStaged) return null;
  final status = unstaged ? entry.worktreeStatus : entry.indexStatus;
  return GitFileChange(
    path: entry.path,
    status: status,
    oldPath: status == 'R' || status == 'C' ? entry.origPath : null,
    additions: unstaged ? entry.unstagedAdditions : entry.stagedAdditions,
    deletions: unstaged ? entry.unstagedDeletions : entry.stagedDeletions,
    isBinary: unstaged ? entry.unstagedBinary : entry.stagedBinary,
  );
}
