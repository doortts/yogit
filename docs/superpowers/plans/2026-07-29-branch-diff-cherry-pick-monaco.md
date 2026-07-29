# Branch Diff, Cherry-pick, and Internal Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two-branch comparison, current-branch cherry-pick workflows, origin divergence badges, and an offline Monaco-based internal editor without replacing Yogit's timeline-first interface.

**Architecture:** Keep Git behavior in the existing `GitRepository` and session orchestration in `TimelineScreen`. Extend the existing repository/branch selector, preview, external-editor path validation, and full-diff controls; add only one focused screen file for Monaco. Fast comparison data and slow rebase simulation are loaded separately and guarded by request serials.

**Tech Stack:** Flutter 3.44.4, Dart 3.12.2, Git CLI, `flutter_monaco: ^3.4.2`, Flutter widget tests, and real temporary Git repositories for integration tests.

## Global Constraints

- Display the choices exactly as `내장 에디터` and `외부 에디터`; do not expose `Monaco` in those user-facing labels.
- Compare local and remote branches, but never tags; allow `main` and `origin/main` as distinct refs.
- Compare branch tip snapshots with `git diff <base-tip> <compare-tip>`, not a three-dot diff.
- Show only the two selected branch lanes and every common boundary returned by `git merge-base --all`.
- Cherry-pick exactly one commit into the currently checked-out branch; never target another branch.
- Run merge/rebase checks with real Git commands while leaving the user's branch, index, worktree, hooks, `rerere`, and refs untouched.
- Bundle Monaco through `flutter_monaco`; do not add CDN access, LSP, tabs, extensions, or a hand-written JavaScript bridge.
- Preserve UTF-8 BOM and CRLF/LF when saving working-tree files; never write a historical blob back into the worktree.
- Do not add a generic repository interface, editor factory, or persistent comparison cache.
- Keep the user's existing changes in `docs/superpowers/plans/2026-07-27-full-diff-hunk-workspace.md` and `.superpowers/brainstorm/` untouched.

---

### Task 1: Noninteractive Git execution, origin fetch, and divergence data

**Files:**
- Modify: `lib/git.dart:8-40`
- Modify: `lib/git.dart:765-803`
- Modify: `lib/git.dart:852-890`
- Modify: `lib/git.dart:1277-1365`
- Modify: `test/git_test.dart`
- Modify: `test/app_test.dart:10004-10090`

**Interfaces:**
- Consumes: Existing `GitRepository.runner`, `RepoRefs`, and `loadRefs()`.
- Produces:
  - `BranchAheadBehind({required int ahead, required int behind})`
  - `RepoRefs.aheadBehind: Map<String, BranchAheadBehind>`
  - `FetchOriginResult.updated` and `FetchOriginResult.noOrigin`
  - `GitRepository.fetchOrigin(): Future<FetchOriginResult>`
  - `CommandRunner` support for an optional `environment` map.

- [ ] **Step 1: Write failing integration tests for divergence and noninteractive fetch**

Add tests that create a temporary repository and bare `origin`, push `main`, then create one local-only and one remote-only commit. Verify the directional counts and that a missing `origin` returns `FetchOriginResult.noOrigin`.

```dart
test('loadRefs reports local and origin divergence by direction', () async {
  final root = await Directory.systemTemp.createTemp('yogit_divergence_');
  final remote = await Directory.systemTemp.createTemp('yogit_origin_');
  addTearDown(() => root.delete(recursive: true));
  addTearDown(() => remote.delete(recursive: true));
  await _git(remote, ['init', '--bare']);
  await _initRepository(root);
  await File('${root.path}/file.txt').writeAsString('base\n');
  await _git(root, ['add', 'file.txt']);
  await _git(root, ['commit', '-m', 'base']);
  await _git(root, ['remote', 'add', 'origin', remote.path]);
  await _git(root, ['push', '-u', 'origin', 'main']);
  await File('${root.path}/file.txt').writeAsString('local\n');
  await _git(root, ['commit', '-am', 'local']);

  final refs = await GitRepository(root.path).loadRefs();

  expect(refs.aheadBehind['main']?.ahead, 1);
  expect(refs.aheadBehind['main']?.behind, 0);
});

test('fetchOrigin disables terminal prompts', () async {
  Map<String, String>? fetchEnvironment;
  final repository = GitRepository(
    '/repo',
    runner: (
      executable,
      arguments, {
      workingDirectory,
      environment,
    }) async {
      if (arguments case ['remote', 'get-url', 'origin']) {
        return ProcessResult(1, 0, 'https://example.com/repo.git\n', '');
      }
      fetchEnvironment = environment;
      return ProcessResult(2, 0, '', '');
    },
  );

  expect(await repository.fetchOrigin(), FetchOriginResult.updated);
  expect(fetchEnvironment?['GIT_TERMINAL_PROMPT'], '0');
  expect(fetchEnvironment?['GCM_INTERACTIVE'], 'Never');
});
```

- [ ] **Step 2: Run the new repository tests and confirm failure**

Run:

```bash
flutter test test/git_test.dart --plain-name "loadRefs reports local and origin divergence by direction"
flutter test test/git_test.dart --plain-name "fetchOrigin disables terminal prompts"
```

Expected: compilation fails because the new types, field, method, and runner argument do not exist.

- [ ] **Step 3: Extend the runner and ref models**

Use one runner shape everywhere instead of adding a second command abstraction.

```dart
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

class BranchAheadBehind {
  const BranchAheadBehind({required this.ahead, required this.behind});

  final int ahead;
  final int behind;

  bool get differs => ahead != 0 || behind != 0;
}

enum FetchOriginResult { updated, noOrigin }
```

Add `aheadBehind` to `RepoRefs`, update every `CommandRunner` test closure with the new optional named argument, and keep existing call sites unchanged when they need no environment.

- [ ] **Step 4: Compute matching `origin` divergence and implement fetch**

After refs are parsed, run `rev-list --left-right --count` only for local branches that have `origin/<name>`. Preserve zero values in the model so UI tests can prove they are hidden.

```dart
Future<BranchAheadBehind> _loadAheadBehind(String branch) async {
  final output = (await _run([
    'rev-list',
    '--left-right',
    '--count',
    '$branch...refs/remotes/origin/$branch',
  ])).trim().split(RegExp(r'\s+'));
  return BranchAheadBehind(
    ahead: int.parse(output[0]),
    behind: int.parse(output[1]),
  );
}

Future<FetchOriginResult> fetchOrigin() async {
  if (await loadOriginUrl() == null) return FetchOriginResult.noOrigin;
  final result = await runner(
    gitExecutable,
    const ['-c', 'credential.interactive=never', 'fetch', '--prune', 'origin'],
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
      const ['fetch', '--prune', 'origin'],
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return FetchOriginResult.updated;
}
```

- [ ] **Step 5: Run repository and existing tests**

Run:

```bash
dart format lib/git.dart test/git_test.dart test/app_test.dart
flutter test test/git_test.dart test/full_diff_git_test.dart test/app_test.dart
```

Expected: all tests pass, including existing command-runner tests.

- [ ] **Step 6: Commit the repository primitives**

```bash
git add lib/git.dart test/git_test.dart test/app_test.dart
git commit -m "feat: fetch origin and report branch divergence"
```

---

### Task 2: Divergence badges and automatic origin refresh

**Files:**
- Modify: `lib/timeline.dart:367-610`
- Modify: `lib/timeline.dart:1300-1665`
- Modify: `lib/timeline.dart:1666-1765`
- Modify: `test/app_test.dart`

**Interfaces:**
- Consumes: `RepoRefs.aheadBehind`, `GitRepository.fetchOrigin()`, `GitRepository.loadRefs()`.
- Produces:
  - A green `↑N` and orange `↓N` at the right edge of local branch rows.
  - One fetch at screen startup, then at most one fetch every five minutes.
  - A status-bar retry control and a short nonmodal fetch error.

- [ ] **Step 1: Write failing widget tests for badge visibility and color**

Add a test with `main` at `ahead: 2, behind: 1`, `release` at zero, and `local-only` without a matching origin. Assert only `main` has badges, the arrows are present in semantics/text, and the colors differ.

```dart
expect(find.byKey(const Key('sidebar-ahead-main')), findsOneWidget);
expect(find.text('↑2'), findsOneWidget);
expect(find.byKey(const Key('sidebar-behind-main')), findsOneWidget);
expect(find.text('↓1'), findsOneWidget);
expect(find.byKey(const Key('sidebar-ahead-release')), findsNothing);
expect(find.byKey(const Key('sidebar-ahead-local-only')), findsNothing);
expect(
  tester.widget<Text>(find.text('↑2')).style?.color,
  isNot(tester.widget<Text>(find.text('↓1')).style?.color),
);
```

Add a second test with a completer-backed `fetchOrigin` callback on `FakeGitRepository`; call a visible-for-testing refresh method or tap the retry action twice while the first request is incomplete and assert the callback runs once.

- [ ] **Step 2: Run the widget tests and confirm failure**

Run:

```bash
flutter test test/app_test.dart --plain-name "local branch rows show only nonzero origin divergence"
flutter test test/app_test.dart --plain-name "origin refresh skips an overlapping request"
```

Expected: badge keys and fetch hooks are missing.

- [ ] **Step 3: Add fetch session state to `TimelineScreen`**

Use the screen lifecycle already scoped to one repository.

```dart
static const _fetchInterval = Duration(minutes: 5);
Timer? _fetchTimer;
var _fetchingOrigin = false;
Object? _fetchError;

@override
void initState() {
  super.initState();
  _ownsPreviewController = widget.controller == null;
  _previewController = widget.controller ?? WindowFrameController();
  _scrollController.addListener(_maybeLoadNextPage);
  _loadNextPage();
  unawaited(_loadRefs());
  unawaited(_refreshOrigin());
  _fetchTimer = Timer.periodic(
    _fetchInterval,
    (_) => unawaited(_refreshOrigin()),
  );
}

Future<void> _refreshOrigin() async {
  if (_fetchingOrigin) return;
  _fetchingOrigin = true;
  try {
    final result = await widget.repository.fetchOrigin();
    if (!mounted) return;
    if (result == FetchOriginResult.updated) await _loadRefs();
    if (mounted) setState(() => _fetchError = null);
  } catch (error) {
    if (mounted) setState(() => _fetchError = error);
  } finally {
    _fetchingOrigin = false;
  }
}
```

Cancel `_fetchTimer` in `dispose`.

- [ ] **Step 4: Render badges in local leaf rows and the refresh status**

In `_refTreeRow`, append badges only when `section == _RefSection.local`, `name != null`, and the stored count is nonzero. Use `_main` for ahead and a distinct orange constant for behind; retain arrows and numbers as visible text.

```dart
final divergence = section == _RefSection.local && name != null
    ? _refs.aheadBehind[name]
    : null;

if ((divergence?.ahead ?? 0) > 0)
  Text(
    key: Key('sidebar-ahead-$name'),
    '↑${divergence!.ahead}',
    style: const TextStyle(color: _main, fontSize: 11),
  ),
if ((divergence?.behind ?? 0) > 0)
  Text(
    key: Key('sidebar-behind-$name'),
    '↓${divergence!.behind}',
    style: const TextStyle(color: _behind, fontSize: 11),
  ),
```

When `_fetchError != null`, replace the ordinary left status legend with `origin 갱신 실패` and a keyboard-accessible `다시 시도` button. Do not show a dialog or repeated snackbar.

- [ ] **Step 5: Run the badge and lifecycle tests**

Run:

```bash
dart format lib/timeline.dart test/app_test.dart
flutter test test/app_test.dart --plain-name "local branch rows show only nonzero origin divergence"
flutter test test/app_test.dart --plain-name "origin refresh skips an overlapping request"
flutter test test/app_test.dart --plain-name "fetch failure keeps existing refs and offers retry"
```

Expected: all three tests pass.

- [ ] **Step 6: Commit the visible origin status**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: show origin divergence in branch rows"
```

---

### Task 3: Fast two-branch comparison and two-lane graph data

**Files:**
- Modify: `lib/git.dart:133-220`
- Modify: `lib/git.dart:731-852`
- Modify: `lib/git.dart:895-1276`
- Modify: `test/git_test.dart`

**Interfaces:**
- Consumes: `parseGitLog`, `safeDiffArguments`, existing diff/file parsers.
- Produces:
  - `BranchCommitSide.baseOnly`, `.compareOnly`, `.commonBoundary`
  - `BranchComparisonCommit`
  - `MergeConflictCheck`
  - `BranchComparisonResult`
  - `GitRepository.compareBranches(String baseRef, String compareRef)`
  - `GitRepository.loadDiffBetween(String fromRef, String toRef, GitFileChange file, ...)`
  - `layoutBranchComparison(List<BranchComparisonCommit>)`.

- [ ] **Step 1: Write failing real-Git comparison tests**

Create a shared base, one commit on `main`, two on `feature`, and a file changed differently on both tips. Assert:

```dart
final result = await GitRepository(root.path).compareBranches('main', 'feature');

expect(result.baseRef, 'main');
expect(result.compareRef, 'feature');
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
expect(result.merge.files, ['shared.txt']);
```

Add a sibling-tip fixture and assert `sameFirstParent` is true when both tips have the same direct parent. Add a criss-cross fixture or command-runner fixture that returns two merge bases and assert both appear once as `commonBoundary`. Add a diff-direction test whose deleted/added lines prove `main → feature`.

- [ ] **Step 2: Run comparison tests and confirm failure**

Run:

```bash
flutter test test/git_test.dart --plain-name "compares branch tips with unique commits and common boundaries"
flutter test test/git_test.dart --plain-name "keeps every merge base in comparison results"
flutter test test/git_test.dart --plain-name "branch diff runs from base tip to compare tip"
```

Expected: comparison types and methods are undefined.

- [ ] **Step 3: Add immutable comparison result types**

```dart
enum BranchCommitSide { baseOnly, compareOnly, commonBoundary }

class BranchComparisonCommit {
  const BranchComparisonCommit({required this.commit, required this.side});
  final GitCommit commit;
  final BranchCommitSide side;
}

enum MergeConflictStatus { clean, conflicts, failed }

class MergeConflictCheck {
  const MergeConflictCheck({
    required this.status,
    this.files = const [],
    this.error,
  });
  final MergeConflictStatus status;
  final List<String> files;
  final String? error;
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
```

- [ ] **Step 4: Implement the fast Git commands and reuse diff parsing**

Resolve tips with `rev-parse --verify <ref>^{commit}`, parents with `rev-list --parents -n 1`, bases with `merge-base --all`, and unique commits with a `%m`-prefixed left/right log. Load each common boundary with the existing log format and deduplicate by SHA while keeping Git order.

Run merge inspection without touching the index:

```dart
final merge = await runner(
  gitExecutable,
  ['merge-tree', '--write-tree', '--name-only', '-z', baseTip, compareTip],
  workingDirectory: root,
);
```

Treat exit `0` as clean, `1` as conflicts, and every other exit as `failed`. Strip the leading tree object id and diagnostic records, deduplicate conflict paths in insertion order, and keep a failure local to `MergeConflictCheck`.

Implement `loadDiffBetween` with the same algorithm, whitespace, scope, byte, and line limits as `loadDiff`, but pass revisions `[fromRef, toRef]`.

- [ ] **Step 5: Add the fixed two-lane graph layout**

`layoutBranchComparison` must assign lane `0` to base-only/common rows and lane `1` to compare-only rows. Keep at most lanes `{0, 1}` active; converge lane `1` into lane `0` immediately before the first common boundary.

```dart
final lane = entry.side == BranchCommitSide.compareOnly ? 1 : 0;
final branch = entry.side == BranchCommitSide.compareOnly ? 1 : 0;
```

Add a unit test that feeds interleaved unique commits plus two common boundaries and asserts every `GraphRow.maxLane <= 1`.

- [ ] **Step 6: Run comparison repository tests**

Run:

```bash
dart format lib/git.dart test/git_test.dart
flutter test test/git_test.dart
```

Expected: every Git and graph comparison test passes.

- [ ] **Step 7: Commit fast comparison support**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: compare branch histories and tip snapshots"
```

---

### Task 4: Exact rebase simulation and stale-worktree cleanup

**Files:**
- Modify: `lib/git.dart`
- Modify: `test/git_test.dart`

**Interfaces:**
- Consumes: Environment-aware `CommandRunner`, repository root and Git executable.
- Produces:
  - `RebaseCheckStatus.clean`, `.conflicts`, `.failed`
  - `RebaseCheckResult`
  - `GitRepository.simulateRebase({required String baseRef, required String compareRef})`
  - `GitRepository.cleanupStaleRebaseWorktrees()`.

- [ ] **Step 1: Write failing success, conflict, and cleanup tests**

Use real temporary repositories. For the conflict fixture, make two sequential feature commits and a conflicting main change so the second feature commit stops first.

```dart
final result = await GitRepository(root.path).simulateRebase(
  baseRef: 'main',
  compareRef: 'feature',
);

expect(result.status, RebaseCheckStatus.conflicts);
expect(result.stoppedCommit, conflictingCommitSha);
expect(result.files, ['shared.txt']);
expect(await _yogitRebaseDirectories(), isEmpty);
expect(await _git(root, ['status', '--porcelain']), isEmpty);
expect((await _git(root, ['branch', '--show-current'])).trim(), 'main');
```

Also force the command future to complete after a caller has discarded the result and verify `finally` still removes the worktree.

- [ ] **Step 2: Run rebase tests and confirm failure**

Run:

```bash
flutter test test/git_test.dart --plain-name "simulates a clean rebase outside the user worktree"
flutter test test/git_test.dart --plain-name "reports the first conflicting rebase commit and file"
flutter test test/git_test.dart --plain-name "always removes the temporary rebase worktree"
```

Expected: rebase types and methods are undefined.

- [ ] **Step 3: Add the result types and app-owned path check**

```dart
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

bool _isYogitRebasePath(String path) {
  final parent = Directory(path).parent.path;
  final name = path.split(Platform.pathSeparator).last;
  return parent == Directory.systemTemp.path &&
      name.startsWith('yogit_rebase_');
}
```

- [ ] **Step 4: Implement detached worktree simulation with unconditional cleanup**

Create an app-prefixed temporary directory, add a detached worktree at `compareRef`, and run:

```text
git -c core.hooksPath=/dev/null
    -c rerere.enabled=false
    -c rebase.autoStash=false
    -c rebase.updateRefs=false
    -c commit.gpgSign=false
    rebase --no-autostash <baseRef>
```

Pass `GIT_EDITOR=true`, `GIT_SEQUENCE_EDITOR=true`, and `GIT_TERMINAL_PROMPT=0`. On failure, read `REBASE_HEAD` and `git diff --name-only --diff-filter=U -z`. In `finally`, attempt `rebase --abort`, `git worktree remove --force <path>`, directory deletion, and `git worktree prune` in that order.

`cleanupStaleRebaseWorktrees` must parse `git worktree list --porcelain` and remove only paths for which `_isYogitRebasePath` is true.

Call `cleanupStaleRebaseWorktrees` once from comparison-session startup before the first rebase simulation. Cleanup failure must not hide the fast comparison result; return it only as the rebase check's local failure.

- [ ] **Step 5: Run rebase and full Git tests**

Run:

```bash
dart format lib/git.dart test/git_test.dart
flutter test test/git_test.dart test/full_diff_git_test.dart
```

Expected: clean/conflict/failure results are isolated and no test leaves an app worktree behind.

- [ ] **Step 6: Commit rebase simulation**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: simulate branch rebases safely"
```

---

### Task 5: Searchable branch-diff selector and comparison timeline mode

**Files:**
- Modify: `lib/repository_branch_selector.dart`
- Modify: `lib/timeline.dart`
- Modify: `test/repository_branch_selector_test.dart`
- Modify: `test/app_test.dart`

**Interfaces:**
- Consumes: `BranchComparisonResult`, `RebaseCheckResult`, `layoutBranchComparison`, `loadDiffBetween`.
- Produces:
  - Searchable `브랜치 diff` menu beside `기준 브랜치`.
  - Session-only caches keyed by `({String baseTip, String compareTip})`.
  - Fixed two-lane comparison rows, branch-tip preview diff, and comparison status.

- [ ] **Step 1: Write failing selector tests**

Extend `RepositoryBranchSelector` tests with local `main`, `feature/a`, remote `origin/main`, and a tag-like value kept out of the supplied lists. Assert search filtering, separate `LOCAL`/`REMOTE` headings, exclusion of the exact base ref, selection checkmark, and clear action.

```dart
await tester.tap(find.byKey(const Key('branch-diff-selector')));
await tester.enterText(
  find.byKey(const Key('branch-diff-search')),
  'origin',
);
await tester.pump();
expect(find.text('origin/main'), findsOneWidget);
expect(find.text('feature/a'), findsNothing);
await tester.tap(find.byKey(const Key('branch-diff-menu-origin/main')));
expect(selectedComparison, 'origin/main');
```

- [ ] **Step 2: Write failing timeline comparison tests**

Extend `FakeGitRepository` with callbacks for `compareBranches`, `simulateRebase`, and `loadDiffBetween`. Assert:

- only comparison commits are visible;
- `main만`, `feature만`, and `공통` are visible;
- no graph row uses a lane above `1`;
- preview files and diff remain unchanged when commit selection moves;
- clearing comparison restores the already loaded normal timeline;
- a late result from the old selected branch is ignored.
- stale app-owned rebase worktree cleanup runs once before the first rebase check.

- [ ] **Step 3: Run selector and timeline tests and confirm failure**

Run:

```bash
flutter test test/repository_branch_selector_test.dart
flutter test test/app_test.dart --plain-name "branch comparison keeps only two branch lanes"
flutter test test/app_test.dart --plain-name "comparison preview stays on the branch tip diff"
flutter test test/app_test.dart --plain-name "late comparison results cannot replace a newer selection"
```

Expected: comparison controls and state do not exist.

- [ ] **Step 4: Extend the existing selector instead of adding another toolbar component**

Add these constructor fields:

```dart
final List<String> remoteBranches;
final String? comparedBranch;
final ValueChanged<String> onComparisonSelected;
final VoidCallback onComparisonCleared;
```

Implement a stateful popup body in `repository_branch_selector.dart` with one `TextField`, two labeled result groups, checkmarks, and a clear row. Reuse `_SelectorField` so the new field follows the approved toolbar sizing and theme.

- [ ] **Step 5: Add comparison state, request invalidation, and caches**

In `_TimelineScreenState` add:

```dart
String? _compareRef;
BranchComparisonResult? _comparison;
RebaseCheckResult? _rebaseCheck;
Object? _comparisonError;
var _comparisonRequestSerial = 0;
final _comparisonCache =
    <({String baseTip, String compareTip}), Future<BranchComparisonResult>>{};
final _rebaseCache =
    <({String baseTip, String compareTip}), Future<RebaseCheckResult>>{};
String? _comparisonPreviewPath;
```

When the selection changes, increment the serial, resolve the fast result first, render it, then start rebase simulation. Before either completion calls `setState`, verify `mounted`, serial equality, repository identity, selected base ref, selected compare ref, and matching tip SHAs.

Start one `_rebaseCleanup` future when `TimelineScreen` initializes. Await it before the first `simulateRebase` call, reuse it for later selections, and convert cleanup failure into only the current rebase status error.

- [ ] **Step 6: Switch only the visible timeline data**

Keep `_commits`, `_rows`, and `_entries` as the normal cached timeline. Add getters for active comparison rows and commits rather than overwriting the normal lists. In comparison mode:

- use `layoutBranchComparison(result.commits)`;
- label rows from `BranchCommitSide`;
- disable pagination;
- keep keyboard movement and selection on the active list;
- show branch-tip files from `result.files`;
- load selected file patches with `loadDiffBetween(result.baseTip, result.compareTip, file)`;
- replace the ordinary status bar with parent/base/count/merge/rebase values.

If a refreshed ref disappears, call `_clearComparison()` and retain the normal timeline. If tip SHA changes, use a new cache key and reload.

- [ ] **Step 7: Run focused UI tests**

Run:

```bash
dart format lib/repository_branch_selector.dart lib/timeline.dart test/repository_branch_selector_test.dart test/app_test.dart
flutter test test/repository_branch_selector_test.dart
flutter test test/app_test.dart --name "branch comparison"
flutter test test/app_test.dart --name "comparison preview"
flutter test test/app_test.dart --name "late comparison"
```

Expected: selector, two-lane timeline, preview, status, restoration, and stale-request tests pass.

- [ ] **Step 8: Commit comparison UI**

```bash
git add lib/repository_branch_selector.dart lib/timeline.dart test/repository_branch_selector_test.dart test/app_test.dart
git commit -m "feat: compare branches in the timeline"
```

---

### Task 6: Cherry-pick repository workflow

**Files:**
- Modify: `lib/git.dart`
- Modify: `test/git_test.dart`

**Interfaces:**
- Consumes: Environment-aware runner and safe literal path arguments.
- Produces:
  - `resolveWorkingTreeFile(String repositoryRoot, String relativePath)`
  - `CherryPickOutcome.applied`, `.conflicts`, `.empty`
  - `CherryPickState`
  - `CherryPickResult`
  - `GitRepository.loadCherryPickState()`
  - `GitRepository.cherryPick(String sha)`
  - `GitRepository.continueCherryPick()`
  - `GitRepository.abortCherryPick()`
  - `GitRepository.stageResolvedFile(String relativePath)`.

- [ ] **Step 1: Write failing real-Git cherry-pick tests**

Cover successful HEAD movement, dirty-worktree rejection, conflict restoration from `CHERRY_PICK_HEAD`, continue, abort, and an already-applied/empty change.

```dart
final result = await repository.cherryPick(sourceSha);
expect(result.outcome, CherryPickOutcome.conflicts);
expect(result.state?.commitSha, sourceSha);
expect(result.state?.conflicts, ['shared.txt']);

await File('${root.path}/shared.txt').writeAsString('resolved\n');
await repository.stageResolvedFile('shared.txt');
final continued = await repository.continueCherryPick();
expect(continued.outcome, CherryPickOutcome.applied);
expect(await repository.loadCherryPickState(), isNull);
```

Assert the dirty fixture leaves HEAD and files unchanged. Assert `abortCherryPick` restores the exact pre-pick HEAD and worktree.

- [ ] **Step 2: Run cherry-pick tests and confirm failure**

Run:

```bash
flutter test test/git_test.dart --name "cherry-pick"
```

Expected: workflow types and repository methods are undefined.

- [ ] **Step 3: Add the shared path resolver, result types, and preflight checks**

```dart
Future<File> resolveWorkingTreeFile(
  String repositoryRoot,
  String relativePath,
) async {
  final root = await Directory(repositoryRoot).resolveSymbolicLinks();
  final target = File('$root${Platform.pathSeparator}$relativePath');
  final resolved = await target.resolveSymbolicLinks();
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

enum CherryPickOutcome { applied, conflicts, empty }

class CherryPickState {
  const CherryPickState({
    required this.commitSha,
    required this.conflicts,
  });
  final String commitSha;
  final List<String> conflicts;
  bool get canContinue => conflicts.isEmpty;
}

class CherryPickResult {
  const CherryPickResult({
    required this.outcome,
    this.state,
    this.headSha,
  });
  final CherryPickOutcome outcome;
  final CherryPickState? state;
  final String? headSha;
}
```

Before `git cherry-pick <sha>`, reject detached HEAD, missing current branch, another merge/rebase/cherry-pick, dirty status, a noncommit SHA, and an ancestor of HEAD. Return user-readable `GitRepositoryException` messages without changing the repository. Put the resolver in `git.dart` so `GitRepository.stageResolvedFile` and the editor services can share it without a circular import. Add a symlink-escape test before using the resolved path.

- [ ] **Step 4: Implement start, state restore, continue, empty, and abort**

Use `git status --porcelain=v1 -z`, `rev-parse --verify <sha>^{commit}`, and `merge-base --is-ancestor`. After a nonzero cherry-pick:

- if `CHERRY_PICK_HEAD` exists and unmerged files exist, return `conflicts`;
- if `CHERRY_PICK_HEAD` exists with no staged change, run `git cherry-pick --skip` and return `empty`;
- otherwise throw the command error.

Run continue with `-c core.editor=true` and `GIT_EDITOR=true`. `loadCherryPickState` reads `CHERRY_PICK_HEAD` plus `git diff --name-only --diff-filter=U -z`.

`stageResolvedFile` must resolve the safe working-tree file, run `git diff --check -- <path>`, and refuse staging only when output contains `leftover conflict marker`; otherwise run `git add -- <path>`.

- [ ] **Step 5: Run all cherry-pick and Git tests**

Run:

```bash
dart format lib/git.dart test/git_test.dart
flutter test test/git_test.dart test/full_diff_git_test.dart
```

Expected: success/conflict/empty/continue/abort/restoration tests pass.

- [ ] **Step 6: Commit cherry-pick Git support**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: manage cherry-pick workflows"
```

---

### Task 7: Cherry-pick menu, drag target, confirmation, and conflict panel

**Files:**
- Modify: `lib/timeline.dart`
- Modify: `test/app_test.dart`

**Interfaces:**
- Consumes: Task 6 cherry-pick methods and current `GitCommit` selection.
- Produces:
  - `현재 브랜치로 체리픽` commit menu action.
  - Dragging an eligible commit to only the checked-out local branch row.
  - One confirmation dialog shared by menu and drag.
  - Restored conflict panel with file selection, continue, and abort.

- [ ] **Step 1: Write failing interaction tests**

Add tests that invoke a row's secondary action and drag the same commit to `sidebar-row-main`. Capture the repository callback and assert both paths show the same SHA/title/target confirmation dialog.

```dart
expect(find.text('현재 브랜치로 체리픽'), findsOneWidget);
expect(find.text(sourceCommit.sha), findsOneWidget);
expect(find.text(sourceCommit.subject), findsOneWidget);
expect(find.text('main'), findsWidgets);
```

Add negative tests for working-tree rows, common-boundary rows, ancestor commits, remote rows, tags, and noncurrent local rows. Add a restart test where `loadCherryPickState()` initially returns a conflict state.

- [ ] **Step 2: Write failing conflict-panel tests**

Verify two conflict files, selected-file state, disabled `계속` while conflicts remain, enabled `계속` after reload returns none, and abort confirmation:

```dart
expect(
  tester.widget<FilledButton>(find.byKey(const Key('cherry-pick-continue')))
      .onPressed,
  isNull,
);
```

- [ ] **Step 3: Run cherry-pick widget tests and confirm failure**

Run:

```bash
flutter test test/app_test.dart --plain-name "commit menu and drag open the same cherry-pick confirmation"
flutter test test/app_test.dart --plain-name "cherry-pick conflict panel restores and gates continue"
```

Expected: menu, drag target, and conflict panel are missing.

- [ ] **Step 4: Add shared start and refresh methods**

```dart
Future<void> _confirmCherryPick(GitCommit commit) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('현재 브랜치로 체리픽'),
      content: Text('${commit.shortSha}\n${commit.subject}\n→ ${_refs.current}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('체리픽'),
        ),
      ],
    ),
  );
  if (approved == true) await _runCherryPick(commit.sha);
}
```

On success, reload refs/history/comparison/divergence and select the new HEAD. On conflict, store the returned state. On startup, replace the direct initial fetch with `_restoreCherryPickThenRefresh`: await `_reloadCherryPickState`, then call `_refreshOrigin` only when no cherry-pick is active. On app resume, call `_reloadCherryPickState`; this lets externally staged files enable continue without polling.

Update `_refreshOrigin` to return while `_cherryPickState != null`, so automatic and manual fetches do not run during an active cherry-pick.

- [ ] **Step 5: Add menu fallback and current-row drag target**

Use `showMenu` from the commit row's secondary tap and a `Draggable<GitCommit>` only for eligible commits. Wrap only the checked-out local row with `DragTarget<GitCommit>`. Highlight it during a valid hover and route both actions to `_confirmCherryPick`.

Keep ordinary tap, selection, keyboard navigation, and sidebar branch selection unchanged.

- [ ] **Step 6: Render and operate the conflict panel**

When `_cherryPickState != null`, keep the timeline visible and replace the preview body with:

- conflict summary and selectable files;
- `체리픽 중단`;
- `계속`, enabled only when `conflicts.isEmpty`.

Abort requires a confirmation dialog. Continue/abort failures reload state and show a local error in the panel rather than dismissing it.

- [ ] **Step 7: Run focused widget tests**

Run:

```bash
dart format lib/timeline.dart test/app_test.dart
flutter test test/app_test.dart --name "cherry-pick"
flutter test test/app_test.dart --name "commit menu and drag"
```

Expected: confirmation, eligibility, restored conflicts, continue, abort, and accessibility tests pass.

- [ ] **Step 8: Commit cherry-pick UI**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: cherry-pick commits from the timeline"
```

---

### Task 8: Safe text document handling and Monaco internal editor

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `lib/external_editor.dart`
- Create: `lib/monaco_editor_screen.dart`
- Modify: `test/external_editor_test.dart`
- Create: `test/monaco_editor_screen_test.dart`

**Interfaces:**
- Consumes: `resolveWorkingTreeFile` from `git.dart` and `flutter_monaco`.
- Produces:
  - `WorkingTreeTextDocument.load(...)`
  - `WorkingTreeTextDocument.save(String text)`
  - `MonacoEditorScreen({required String title, required String initialText, required MonacoLanguage language, required bool readOnly, Future<void> Function(String text)? onSave, Future<void> Function()? onOpenExternal, Widget? editorForTesting})`
  - editable and read-only modes, one editor instance, and one save path.

- [ ] **Step 1: Add the pinned compatible package**

Run:

```bash
flutter pub add flutter_monaco:^3.4.2
```

Expected: `pubspec.yaml` and `pubspec.lock` resolve under Flutter 3.44.4/Dart 3.12.2. Do not add Monaco asset entries; the package bundles and extracts its own assets.

- [ ] **Step 2: Write failing file-boundary and encoding tests**

Move the existing root/path tests to cover the shared resolver, then add UTF-8 BOM, CRLF, invalid UTF-8, NUL/binary, directory, missing file, and escaping symlink cases.

```dart
final document = await WorkingTreeTextDocument.load(
  repositoryRoot: root.path,
  relativePath: 'windows.dart',
);
expect(document.text, 'one\ntwo\n');
expect(document.hasBom, isTrue);
expect(document.lineEnding, TextLineEnding.crlf);

await document.save('changed\ntext\n');
expect(
  await File('${root.path}/windows.dart').readAsBytes(),
  [0xEF, 0xBB, 0xBF, ...utf8.encode('changed\r\ntext\r\n')],
);
```

- [ ] **Step 3: Run document tests and confirm failure**

Run:

```bash
flutter test test/external_editor_test.dart
flutter test test/monaco_editor_screen_test.dart
```

Expected: shared resolver and document codec are undefined.

- [ ] **Step 4: Reuse the shared safe resolver**

Remove the inline root and symbolic-link validation from `ExternalEditorService.open` and call `resolveWorkingTreeFile` from `git.dart`. Make the new document loader call the same function so both editor paths keep identical boundary behavior.

- [ ] **Step 5: Implement the text codec**

In `monaco_editor_screen.dart`, decode UTF-8 with `allowMalformed: false`, reject NUL bytes, strip/remember BOM, normalize CRLF to LF for Monaco, and restore the original line ending and BOM on save. Use `File.writeAsBytes(..., flush: true)`.

Map common extensions to `MonacoLanguage` and fall back to `MonacoLanguage.plaintext`; do not add language services.

- [ ] **Step 6: Write failing editor chrome tests**

Use a small `editorForTesting` widget override on `MonacoEditorScreen`, not a production editor factory. Assert:

- title is `내장 에디터`;
- editable mode shows `저장` and `수정 가능`;
- read-only mode shows `읽기 전용` and no save action;
- a save failure keeps the route open and displays the error;
- the save callback receives the editor text exactly once.
- a Monaco boot failure shows `외부 에디터` only when `onOpenExternal` is available.

- [ ] **Step 7: Implement the Monaco screen and save keybinding**

Build one `MonacoEditor` with `initialText`, `EditorOptions(language: ..., readOnly: ...)`, no CDN font access, and theme inherited from app brightness. Capture `MonacoController` in `onReady`.

For editable documents register:

```dart
final saveAction = await controller.addAction(
  const MonacoActionDescriptor(
    id: MonacoAction('yogit.save'),
    label: 'Save',
    keybindings: [
      MonacoKeybinding(key: MonacoKey.keyS, ctrlCmd: true),
    ],
  ),
  _save,
);
```

The toolbar save button and action callback both call the same `_save` method, which reads `controller.document.getText()`. Dispose the returned action when the screen closes. Show the package boot error in place and leave the route dismissible. When `onOpenExternal` is nonnull, show an `외부 에디터` fallback button that closes the route and invokes that callback; omit it for historical blobs.

- [ ] **Step 8: Run editor tests and static analysis**

Run:

```bash
dart format lib/external_editor.dart lib/monaco_editor_screen.dart test/external_editor_test.dart test/monaco_editor_screen_test.dart
flutter test test/external_editor_test.dart test/monaco_editor_screen_test.dart
flutter analyze
```

Expected: codec/chrome tests pass and analysis has no errors.

- [ ] **Step 9: Commit the internal editor**

```bash
git add pubspec.yaml pubspec.lock lib/external_editor.dart lib/monaco_editor_screen.dart test/external_editor_test.dart test/monaco_editor_screen_test.dart
git commit -m "feat: add the Monaco internal editor"
```

---

### Task 9: Editor choice integration in full diff and cherry-pick conflicts

**Files:**
- Modify: `lib/diff_screen.dart`
- Modify: `lib/full_diff_header.dart`
- Modify: `lib/timeline.dart`
- Modify: `test/app_test.dart`
- Modify: `test/full_diff_header_test.dart`
- Modify: `test/monaco_editor_screen_test.dart`

**Interfaces:**
- Consumes: `MonacoEditorScreen`, `WorkingTreeTextDocument`, `ExternalEditorService`, `stageResolvedFile`.
- Produces:
  - Exact `내장 에디터` / `외부 에디터` choice on both entry points.
  - Editable working-tree route and read-only historical-blob route.
  - Conflict save followed by staging only the selected resolved path.

- [ ] **Step 1: Write failing full-diff editor-choice tests**

Tap `open-editor`, then assert both exact labels appear. In working-tree mode choose the internal editor and assert editable mode. For a historical commit, choose the internal editor and assert read-only mode; `외부 에디터` must be disabled because there is no working-tree target.

Update the header tooltip expectation from “외부 편집기” to a neutral “내장 또는 외부 에디터로 엽니다”.

- [ ] **Step 2: Write failing conflict-save tests**

First assert that `편집기로 열기` exposes the exact labels `내장 에디터` and `외부 에디터`. Open a conflict file through `내장 에디터`, invoke save, and use a fake repository callback to assert:

```dart
expect(savedPaths, ['lib/login_form.dart']);
expect(stagedPaths, ['lib/login_form.dart']);
expect(stagedPaths, isNot(contains('lib/session_banner.dart')));
```

Return a leftover-marker result and assert the file is saved but not staged, the panel still says `해결 필요`, and continue remains disabled. Add unsupported cases for deleted file, binary bytes, malformed UTF-8, and repository escape.

- [ ] **Step 3: Run integration widget tests and confirm failure**

Run:

```bash
flutter test test/app_test.dart --plain-name "editor choice"
flutter test test/app_test.dart --plain-name "internal editor saves and stages only the resolved conflict"
flutter test test/full_diff_header_test.dart
```

Expected: full diff still opens the external editor directly and conflict routing is absent.

- [ ] **Step 4: Replace direct external opening with one choice popup**

In `DiffScreen`, change `_openEditor` to show the two choices. Keep the existing `_editorRequestSerial` guard for late completions.

- Working tree: resolve/load `WorkingTreeTextDocument`, push editable `MonacoEditorScreen` with the existing `ExternalEditorService` action as `onOpenExternal`, or call that service directly.
- Historical commit: read existing `loadFileBytes`, push read-only `MonacoEditorScreen`, and do not offer a writable external path.
- Binary, malformed UTF-8, deleted, or missing working-tree target: disable `내장 에디터` with a visible reason.

Do not remember the last choice.

- [ ] **Step 5: Wire conflict save and refresh**

From `TimelineScreen`, make `편집기로 열기` show the same two exact choices. `외부 에디터` calls the existing `ExternalEditorService`; `내장 에디터` loads the selected conflict document and pushes `MonacoEditorScreen` with the external action as its boot-failure fallback. Its save callback must:

1. call `WorkingTreeTextDocument.save(text)`;
2. call `repository.stageResolvedFile(relativePath)`;
3. reload `CherryPickState`;
4. return to the conflict panel with the updated resolved count.

If staging rejects leftover markers, keep the saved file, show the reason, and leave the file unresolved.

- [ ] **Step 6: Run all editor integration tests**

Run:

```bash
dart format lib/diff_screen.dart lib/full_diff_header.dart lib/timeline.dart test/app_test.dart test/full_diff_header_test.dart test/monaco_editor_screen_test.dart
flutter test test/full_diff_header_test.dart test/monaco_editor_screen_test.dart
flutter test test/app_test.dart --name "editor"
flutter test test/app_test.dart --name "conflict"
```

Expected: both entry points use exact labels, read-only mode never writes, and conflict staging is path-specific.

- [ ] **Step 7: Commit editor integration**

```bash
git add lib/diff_screen.dart lib/full_diff_header.dart lib/timeline.dart test/app_test.dart test/full_diff_header_test.dart test/monaco_editor_screen_test.dart
git commit -m "feat: choose internal or external file editors"
```

---

### Task 10: End-to-end regression and macOS verification

**Files:**
- Modify only files required by failures found in this task.

**Interfaces:**
- Consumes: All previous task outputs.
- Produces: A passing repository, analyzer, macOS debug build, and recorded manual checks.

- [ ] **Step 1: Run formatting and inspect the final diff**

Run:

```bash
dart format lib test
git diff --check
git status --short
```

Expected: no formatting or whitespace errors; only intended feature files plus the user's pre-existing unrelated changes appear.

- [ ] **Step 2: Run the complete automated suite**

Run:

```bash
flutter test
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: no analyzer errors or warnings.

- [ ] **Step 4: Build the macOS debug app**

Run:

```bash
flutter build macos --debug
```

Expected: build succeeds and the app bundle contains the `flutter_monaco` plugin assets without CDN configuration.

- [ ] **Step 5: Perform the manual Monaco checks**

Run the macOS app against a temporary repository and verify:

1. `내장 에디터` accepts typing.
2. `Command-S` and the save button write identical content.
3. Leaving and returning to the editor restores keyboard focus.
4. A historical blob says `읽기 전용` and has no save action.
5. A boot error remains dismissible and still permits `외부 에디터`.

Record pass/fail in the task notes; fix any failure before continuing.

- [ ] **Step 6: Perform the manual Git workflow checks**

In a disposable repository:

1. Compare local/local and local/remote branch pairs.
2. Confirm timeline rows stay on two lanes and preview stays on the branch-tip diff.
3. Produce a cherry-pick conflict.
4. Resolve one file in the internal editor and confirm only it is staged.
5. Complete a conflict-free cherry-pick.
6. Start another conflict and confirm abort restores the original HEAD/worktree.
7. Confirm `↑N` and `↓N` change after an origin fetch.

- [ ] **Step 7: Re-run automated verification after manual fixes**

Run:

```bash
flutter test
flutter analyze
flutter build macos --debug
git diff --check
```

Expected: every command exits successfully.

- [ ] **Step 8: Confirm verification left no uncommitted feature files**

Run:

```bash
git status --short -- lib test pubspec.yaml pubspec.lock macos
```

Expected: no output. If a verification failure required a code change, add its failing test and fix to the task that owns that behavior, commit the exact files listed by that task, then repeat Task 10 from Step 1. Do not create an empty integration commit.
