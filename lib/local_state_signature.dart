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

/// One commit a branch gained or lost when it moved. [incoming] separates the
/// two: what the branch now has, and what it stopped having.
typedef MovedCommit = ({bool incoming, String shortSha, String subject});

/// The name of what git did, read from the branch's own reflog line. The verb
/// is the first word: `pull: Fast-forward` is a pull, `rebase (pick): …` a
/// rebase, `merge feature/x: …` a merge.
///
/// `commit (amend)` and `commit (merge)` are the exception worth catching —
/// their first word says commit, but what happened was an amend or a merge,
/// and that is the part a reader wants.
String? branchOperationFromReflog(String subject) {
  final head = subject.split(':').first.trim();
  if (head.isEmpty) return null;
  final qualified = RegExp(r'^commit \(([^)]+)\)$').firstMatch(head);
  if (qualified != null) return qualified.group(1);
  final word = head.split(' ').first;
  return word.isEmpty ? null : word;
}

/// The commits `git log --left-right --oneline before...after` names. The left
/// side of that range is the tip the branch left, so `<` is what went out and
/// `>` is what came in.
List<MovedCommit> parseMovedCommits(String output) {
  final line = RegExp(r'^([<>]) ([0-9a-f]+) (.*)$');
  return [
    for (final text in output.split('\n'))
      if (line.firstMatch(text.trimRight()) case final match?)
        (
          incoming: match.group(1) == '>',
          shortSha: match.group(2)!,
          subject: match.group(3)!,
        ),
  ];
}

/// The two numbers `git rev-list --left-right --count before...after` prints,
/// in that order: how many the branch left behind, how many it took on.
({int outgoing, int incoming})? parseMovedCounts(String output) {
  final parts = output.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  final outgoing = int.tryParse(parts[0]);
  final incoming = int.tryParse(parts[1]);
  if (outgoing == null || incoming == null) return null;
  return (outgoing: outgoing, incoming: incoming);
}

/// The line a moved branch gets: its name, what git did to it, and what that
/// cost it in commits — `main · pull · 커밋 3개 들어옴`.
///
/// A plain commit says nothing extra: the line already says a commit came in,
/// and naming the operation `commit` beside it only repeats itself.
///
/// Counts the caller could not get leave the SHAs to say what little they can.
/// That is the shape a repository with no reflog left ends up with, and it is
/// still better than "갱신됨" alone.
String movedBranchLine(
  String branch, {
  required String? operation,
  required int? outgoing,
  required int? incoming,
  String? before,
  String? after,
}) {
  if (outgoing == null || incoming == null || (outgoing == 0 && incoming == 0)) {
    return before == null || after == null
        ? '$branch 브랜치 갱신됨'
        : '$branch 갱신됨 · $before → $after';
  }
  final movement = outgoing == 0
      ? '커밋 $incoming개 들어옴'
      : incoming == 0
      ? '커밋 $outgoing개 물러남'
      : '커밋 $outgoing개 나가고 $incoming개 들어옴';
  final named = operation == null || operation == 'commit'
      ? null
      : operation;
  return [branch, ?named, movement].join(' · ');
}

/// One line per branch, until there are more branches than a card can hold —
/// then one line that counts them. The same limit the single-line summary
/// uses, so the two never disagree about when a list stops being a list.
List<String> branchLines(List<String> names, String verb) => names.isEmpty
    ? const []
    : names.length <= _namedBranchLimit
    ? [for (final name in names) '$name 브랜치 $verb']
    : ['브랜치 ${names.length}개 $verb'];
