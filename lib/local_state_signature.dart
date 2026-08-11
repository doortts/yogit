/// The local fingerprint `GitRepository.loadLocalStateSignature` builds, read
/// as the thing it actually describes instead of as one opaque string.
///
/// Comparing the raw text only ever answers "something differs", which turns a
/// branch the user deleted from a terminal into the same modal as a rebase
/// nobody expected. Parsing it tells the two apart.
library;

const _branchPrefix = 'refs/heads/';

/// How many branches a summary names before it gives up and counts them. A
/// terminal sweep can delete a dozen at once, and a line that lists them all
/// stops being a line.
const _namedBranchLimit = 3;

/// Where HEAD sits and where every local branch points, at one moment.
class LocalState {
  const LocalState({
    required this.headCommit,
    required this.headRef,
    required this.branchTips,
  });

  final String headCommit;

  /// `refs/heads/main` while on a branch, the literal `HEAD` while detached —
  /// exactly what `rev-parse --symbolic-full-name HEAD` prints.
  final String headRef;

  /// Branch name to tip, with `refs/heads/` stripped, so the keys read the way
  /// the UI names them.
  final Map<String, String> branchTips;

  bool get detached => !headRef.startsWith(_branchPrefix);

  String? get currentBranch =>
      detached ? null : headRef.substring(_branchPrefix.length);
}

/// One branch that stayed but stopped pointing where it did.
typedef MovedTip = ({String branch, String before, String after});

/// What actually changed between two readings.
class LocalStateChange {
  const LocalStateChange({
    required this.added,
    required this.removed,
    required this.moved,
    required this.headCommitMoved,
    required this.headRefChanged,
    required this.currentBranch,
  });

  /// All three are sorted by name, so a summary reads the same way twice.
  final List<String> added;
  final List<String> removed;
  final List<MovedTip> moved;

  final bool headCommitMoved;
  final bool headRefChanged;

  /// The branch HEAD names after the change, null while detached.
  final String? currentBranch;

  bool get isEmpty =>
      added.isEmpty &&
      removed.isEmpty &&
      moved.isEmpty &&
      !headCommitMoved &&
      !headRefChanged;

  /// Branches disappeared and nothing else happened. The user cannot lose work
  /// to a deletion they just performed, so this is the one shape the timeline
  /// can take on without asking.
  ///
  /// A deletion that took the checked-out branch with it does not count: HEAD
  /// then names a ref that is gone, which is a repository worth looking at
  /// rather than a tidy-up to absorb.
  bool get isPureDeletion =>
      removed.isNotEmpty &&
      added.isEmpty &&
      moved.isEmpty &&
      !headCommitMoved &&
      !headRefChanged &&
      !removed.contains(currentBranch);
}

/// Splits the fingerprint back into its parts. Anything git could not answer
/// reads as empty rather than throwing, because the caller is a watcher and a
/// watcher must never be the thing that breaks the screen.
LocalState parseLocalState(String signature) {
  final lines = signature.split('\n');
  final tips = <String, String>{};
  for (final line in lines.skip(2)) {
    final trimmed = line.trim();
    if (!trimmed.startsWith(_branchPrefix)) continue;
    // The name is everything up to the last space, so a branch whose name
    // holds one still lands in the map whole.
    final split = trimmed.lastIndexOf(' ');
    if (split < 0) continue;
    tips[trimmed.substring(_branchPrefix.length, split)] = trimmed
        .substring(split + 1)
        .trim();
  }
  return LocalState(
    headCommit: lines.isEmpty ? '' : lines[0].trim(),
    headRef: lines.length < 2 ? '' : lines[1].trim(),
    branchTips: tips,
  );
}

LocalStateChange diffLocalState(LocalState before, LocalState after) {
  final added = <String>[];
  final removed = <String>[];
  final moved = <MovedTip>[];
  for (final entry in after.branchTips.entries) {
    final was = before.branchTips[entry.key];
    if (was == null) {
      added.add(entry.key);
    } else if (was != entry.value) {
      moved.add((branch: entry.key, before: was, after: entry.value));
    }
  }
  for (final name in before.branchTips.keys) {
    if (!after.branchTips.containsKey(name)) removed.add(name);
  }
  return LocalStateChange(
    added: added..sort(),
    removed: removed..sort(),
    moved: moved..sort((a, b) => a.branch.compareTo(b.branch)),
    headCommitMoved: before.headCommit != after.headCommit,
    headRefChanged: before.headRef != after.headRef,
    currentBranch: after.currentBranch,
  );
}

/// One line naming what the reload just took in, or null when there is nothing
/// to report. Branches are named while there are few enough to read and
/// counted once there are not.
String? localStateChangeSummary(LocalStateChange change) {
  if (change.isEmpty) return null;
  final parts = <String>[];
  if (change.headRefChanged) {
    parts.add(
      change.currentBranch == null ? 'HEAD 분리됨' : '${change.currentBranch} 체크아웃',
    );
  } else if (change.headCommitMoved &&
      !change.moved.any((tip) => tip.branch == change.currentBranch)) {
    // A commit on the checked-out branch moves HEAD and the tip together, and
    // the tip line below already says so. Only a HEAD nothing else explains —
    // a detached one, most often — needs its own words.
    parts.add('HEAD 이동됨');
  }
  final moved = [for (final tip in change.moved) tip.branch];
  if (moved.isNotEmpty) parts.add(_branchPart(moved, '갱신됨'));
  if (change.added.isNotEmpty) parts.add(_branchPart(change.added, '추가됨'));
  if (change.removed.isNotEmpty) parts.add(_branchPart(change.removed, '삭제됨'));
  return parts.isEmpty ? null : parts.join(', ');
}

String _branchPart(List<String> names, String verb) =>
    names.length <= _namedBranchLimit
    ? '${names.join(', ')} 브랜치 $verb'
    : '브랜치 ${names.length}개 $verb';
