# Remote-Behind Branch Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the selected local branch's upstream-only commit count in red and refresh it from the configured upstream remote every three minutes while the app is active.

**Architecture:** Reuse the existing `RepoRefs.aheadBehind`, five-minute origin fetch loop, and sidebar divergence row. Extend the single `for-each-ref` query with upstream metadata, make the existing fetch operation accept that remote, then narrow rendering and scheduling to `_baseBranch`. No new files, services, settings, or dependencies are needed.

**Tech Stack:** Dart, Flutter desktop, Git CLI, `flutter_test`

## Global Constraints

- Load cached refs before any network refresh so the timeline never waits on the network.
- Refresh on repository open, selected-branch change, and every three minutes while the app is active.
- Skip refreshes when another refresh is running.
- Compare against the selected branch's configured upstream; do not assume `origin/<same-name>`.
- Show a red number only when the selected local branch is behind by more than zero commits.
- Use the exact tooltip copy `원격보다 N개 커밋 뒤처져 있습니다`.
- Keep the last successful count after a fetch failure.
- Do not add ahead badges, all-branch badges, interval settings, or a manual refresh control.
- Do not add a dependency or extract a new abstraction.

## File map

- Modify `lib/git.dart`: parse upstream metadata in `loadRefs()`, calculate divergence against that upstream, and fetch a named remote without terminal prompts.
- Modify `test/git_test.dart`: verify upstream parsing, divergence direction, and named-remote fetch arguments.
- Modify `lib/timeline.dart`: change the interval, coordinate the initial load, refresh only the selected branch's remote, and render the selected branch's red count and tooltip.
- Modify `test/app_test.dart`: verify selected-only rendering, tooltip copy, three-minute scheduling, inactive and overlapping skips, branch-change refresh, and failure retention.

---

### Task 1: Use configured upstream metadata and fetch its remote

**Files:**
- Modify: `lib/git.dart:1317-1360`
- Modify: `lib/git.dart:2435-2571`
- Test: `test/git_test.dart:1648-1787`

**Interfaces:**
- Consumes: `GitRepository._run(List<String>)`, `CommandRunner`, and the existing `BranchAheadBehind`.
- Produces:
  - `RepoRefs.upstreams: Map<String, String>`
  - `RepoRefs.upstreamRemotes: Map<String, String>`
  - `GitRepository.fetchRemote(String remote): Future<FetchOriginResult>`
  - Existing `RepoRefs.aheadBehind` values calculated against the configured upstream.

- [ ] **Step 1: Update the repository tests to describe configured upstreams**

Change the `for-each-ref` fixture to return NUL-separated fields for ref name,
object name, creator time, upstream short name, and upstream remote name:

```dart
const refFormat =
    '--format=%(refname)%00%(objectname)%00%(creatordate:unix)'
    '%00%(upstream:short)%00%(upstream:remotename)';

return ProcessResult(
  1,
  0,
  'refs/heads/main\x00aaa1\x001700000100\x00company/trunk\x00company\n'
  'refs/heads/feature/x\x00aaa2\x001700000200\x00\x00\n'
  'refs/remotes/company/trunk\x00aaa3\x001700000300\x00\x00\n'
  'refs/tags/v0.1.0\x00aaa4\x001700000400\x00\x00\n',
  '',
);
```

Assert the exact upstream maps and the upstream-aware `rev-list` call:

```dart
expect(refs.upstreams, {'main': 'company/trunk'});
expect(refs.upstreamRemotes, {'main': 'company'});
expect(refs.aheadBehind['main']?.ahead, 2);
expect(refs.aheadBehind['main']?.behind, 3);
expect(
  calls,
  contains([
    'rev-list',
    '--left-right',
    '--count',
    'main...refs/remotes/company/trunk',
  ]),
);
```

- [ ] **Step 2: Add a failing named-remote fetch test**

Add a test that records arguments and environment:

```dart
test('fetchRemote fetches the named remote without terminal prompts', () async {
  List<String>? call;
  Map<String, String>? fetchEnvironment;
  final repository = GitRepository(
    '/repo',
    runner: (executable, arguments, {workingDirectory, environment}) async {
      call = arguments;
      fetchEnvironment = environment;
      return ProcessResult(1, 0, '', '');
    },
  );

  expect(await repository.fetchRemote('company'), FetchOriginResult.updated);
  expect(call, [
    '-c',
    'credential.interactive=never',
    'fetch',
    '--prune',
    'company',
  ]);
  expect(fetchEnvironment?['GIT_TERMINAL_PROMPT'], '0');
  expect(fetchEnvironment?['GCM_INTERACTIVE'], 'Never');
});
```

Keep the existing `fetchOrigin()` no-origin compatibility test.

- [ ] **Step 3: Run the focused tests and verify they fail**

Run:

```bash
flutter test test/git_test.dart --plain-name "buckets refs into local, remote, and tags"
flutter test test/git_test.dart --plain-name "fetchRemote fetches the named remote without terminal prompts"
```

Expected: failures because `RepoRefs` has no upstream maps, `loadRefs()` still
assumes `origin/<same-name>`, and `fetchRemote()` does not exist.

- [ ] **Step 4: Parse upstream metadata in the existing ref query**

Add these constructor defaults and fields to `RepoRefs`:

```dart
this.upstreams = const {},
this.upstreamRemotes = const {},

final Map<String, String> upstreams;
final Map<String, String> upstreamRemotes;
```

Replace the space-delimited `for-each-ref` format with the `refFormat` from the
test. Split each non-empty line with `line.split('\x00')`, require five fields,
and keep the existing local, remote, tag, tip, and creator-time behavior.
Populate upstream maps only for local branches whose upstream short name and
remote name are both non-empty and whose remote name is not `.`.

Change `_loadAheadBehind` to accept the upstream:

```dart
Future<BranchAheadBehind> _loadAheadBehind(
  String branch,
  String upstream,
) async {
  final counts = (await _run([
    'rev-list',
    '--left-right',
    '--count',
    '$branch...refs/remotes/$upstream',
  ])).trim().split(RegExp(r'\s+'));
  if (counts.length != 2) {
    throw FormatException('Invalid ahead/behind counts for $branch');
  }
  return BranchAheadBehind(
    ahead: int.parse(counts[0]),
    behind: int.parse(counts[1]),
  );
}
```

Build `aheadBehind` only for entries in `upstreams`:

```dart
for (final entry in upstreams.entries) {
  aheadBehind[entry.key] = await _loadAheadBehind(entry.key, entry.value);
}
```

- [ ] **Step 5: Reuse the existing fetch implementation for any remote**

Move the shared fetch body into:

```dart
Future<FetchOriginResult> fetchRemote(String remote) async {
  final arguments = [
    '-c',
    'credential.interactive=never',
    'fetch',
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
  return FetchOriginResult.updated;
}
```

Keep `fetchOrigin()` as a compatibility wrapper:

```dart
Future<FetchOriginResult> fetchOrigin() async {
  if (await loadOriginUrl() == null) return FetchOriginResult.noOrigin;
  return fetchRemote('origin');
}
```

- [ ] **Step 6: Run repository tests**

Run:

```bash
dart format lib/git.dart test/git_test.dart
flutter test test/git_test.dart
```

Expected: all repository tests pass.

- [ ] **Step 7: Commit the repository change**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: compare branches with configured upstreams"
```

---

### Task 2: Refresh and render only the selected branch's behind count

**Files:**
- Modify: `lib/timeline.dart:562-782`
- Modify: `lib/timeline.dart:1716-1738`
- Modify: `lib/timeline.dart:2550-2696`
- Modify: `lib/timeline.dart:2710-2755`
- Test: `test/app_test.dart:2425-2568`
- Test: `test/app_test.dart:11869-11990`

**Interfaces:**
- Consumes:
  - `RepoRefs.upstreamRemotes`
  - `RepoRefs.aheadBehind`
  - `GitRepository.fetchRemote(String remote)`
  - `_baseBranch` as the user's selected timeline working branch.
- Produces:
  - Three-minute, active-app refresh behavior.
  - `Key('sidebar-behind-<branch>')` only for the selected branch.
  - Tooltip text `원격보다 N개 커밋 뒤처져 있습니다`.

- [ ] **Step 1: Replace the all-branch badge test with selected-only behavior**

Create refs where both local branches are behind, but select `release` through
`preferredBranch`:

```dart
refs: const RepoRefs(
  local: ['main', 'release', 'local-only'],
  current: 'main',
  upstreams: {
    'main': 'origin/main',
    'release': 'company/release',
  },
  upstreamRemotes: {'main': 'origin', 'release': 'company'},
  aheadBehind: {
    'main': BranchAheadBehind(ahead: 2, behind: 4),
    'release': BranchAheadBehind(ahead: 0, behind: 3),
  },
),
```

Pump `TimelineScreen(preferredBranch: 'release', ...)` and assert:

```dart
expect(find.byKey(const Key('sidebar-ahead-main')), findsNothing);
expect(find.byKey(const Key('sidebar-behind-main')), findsNothing);
final badge = find.byKey(const Key('sidebar-behind-release'));
expect(badge, findsOneWidget);
expect(find.descendant(of: badge, matching: find.text('3')), findsOneWidget);
expect(
  tester.widget<Tooltip>(
    find.ancestor(of: badge, matching: find.byType(Tooltip)),
  ).message,
  '원격보다 3개 커밋 뒤처져 있습니다',
);
```

Also assert zero and missing-upstream branches have no badge.

- [ ] **Step 2: Add scheduling and selected-remote tests**

Extend `FakeGitRepository` with:

```dart
final Future<FetchOriginResult> Function(String remote)? fetchRemoteCallback;

@override
Future<FetchOriginResult> fetchRemote(String remote) =>
    fetchRemoteCallback?.call(remote) ?? Future.value(FetchOriginResult.noOrigin);
```

Add three focused widget tests:

1. Initial load fetches the selected branch's remote and a second fetch occurs
   only after three minutes:

```dart
await tester.pump(const Duration(minutes: 2, seconds: 59));
expect(remotes, ['company']);
await tester.pump(const Duration(seconds: 1));
expect(remotes, ['company', 'company']);
```

2. A pending fetch suppresses the three-minute tick, preserving the existing
   overlap test with the interval changed from five to three minutes.
3. After `handleAppLifecycleStateChanged(AppLifecycleState.paused)`, a
   three-minute pump adds no call. After resuming, the next three-minute tick
   fetches again.

Add a branch-selection test that selects another branch from
`RepositoryBranchSelector` and expects an immediate fetch of its mapped remote.

- [ ] **Step 3: Add a failing failure-retention test**

Return refs with a selected branch behind by one commit. Make the first
`fetchRemote` fail and the retry succeed with refs behind by two commits.
Assert the first failure leaves `1` visible and the retry replaces it with `2`.
The status bar may continue to offer the existing retry action, but its label
must be the remote-neutral `원격 갱신 실패`.

- [ ] **Step 4: Run the focused widget tests and verify they fail**

Run:

```bash
flutter test test/app_test.dart --plain-name "selected local branch shows only its nonzero upstream behind count"
flutter test test/app_test.dart --plain-name "selected upstream refresh runs every three minutes while active"
flutter test test/app_test.dart --plain-name "selected upstream refresh skips an overlapping request"
flutter test test/app_test.dart --plain-name "selected upstream refresh pauses with the app"
flutter test test/app_test.dart --plain-name "changing the base branch refreshes its upstream remote"
flutter test test/app_test.dart --plain-name "remote refresh failure keeps the selected branch count"
```

Expected: failures because the current UI shows ahead and behind arrows for
every local branch, the timer is five minutes, and refresh is hard-coded to
origin.

- [ ] **Step 5: Narrow the existing refresh loop**

Change:

```dart
static const _fetchInterval = Duration(minutes: 3);
```

Rename `_refreshOrigin()` to `_refreshSelectedRemote()` and resolve the remote
from the current refs:

```dart
Future<void> _refreshSelectedRemote() async {
  final branch = _baseBranch;
  final remote = branch == null ? null : _refs.upstreamRemotes[branch];
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
      remote == null ||
      _fetchingOrigin ||
      _cherryPickState != null) {
    return;
  }
  setState(() => _fetchingOrigin = true);
  try {
    final result = await widget.repository.fetchRemote(remote);
    if (!mounted) return;
    if (result == FetchOriginResult.updated) await _loadRefs();
    if (mounted) setState(() => _fetchError = null);
  } catch (error) {
    if (mounted) setState(() => _fetchError = error);
  } finally {
    if (mounted) setState(() => _fetchingOrigin = false);
  }
}
```

Keep the current in-flight flag instead of introducing another coordinator.

Remove the standalone initial `_loadRefs()` call. In
`_restoreCherryPickThenRefresh()`, wait for refs and cherry-pick state together,
then refresh:

```dart
await Future.wait([_loadRefs(), _reloadCherryPickState()]);
if (_cherryPickState == null) await _refreshSelectedRemote();
```

Point `Timer.periodic`, the retry button, and `_selectBaseBranch()` at
`_refreshSelectedRemote()`. The branch selector calls it after `_baseBranch`
has been updated. Keep the current timer cancellation in `dispose()`.

- [ ] **Step 6: Render one plain red number with a tooltip**

In `_refTreeRow`, distinguish the checked-out row from the selected working
branch:

```dart
final selectedLocal =
    section == _RefSection.local && name != null && name == _baseBranch;
final behind = selectedLocal ? _refs.aheadBehind[name]?.behind ?? 0 : 0;
```

Remove the existing ahead widget and arrow-prefixed behind widget. Add:

```dart
if (behind > 0)
  Tooltip(
    message: '원격보다 $behind개 커밋 뒤처져 있습니다',
    child: SizedBox(
      key: Key('sidebar-behind-$name'),
      child: Text(
        '$behind',
        style: const TextStyle(color: _behind, fontSize: 11),
      ),
    ),
  ),
```

Keep the existing checked-out-row fill and cherry-pick drag target unchanged.
Change the status error copy from `origin 갱신 실패` to `원격 갱신 실패`.

- [ ] **Step 7: Run timeline tests**

Run:

```bash
dart format lib/timeline.dart test/app_test.dart
flutter test test/app_test.dart
```

Expected: all timeline widget tests pass.

- [ ] **Step 8: Commit the timeline change**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: show selected branch remote behind count"
```

---

### Task 3: Verify the integrated feature

**Files:**
- Verify only; formatting and tests must leave source files unchanged.

**Interfaces:**
- Consumes: the completed repository and timeline behavior from Tasks 1 and 2.
- Produces: evidence that the branch is safe to merge.

- [ ] **Step 1: Format the modified Dart files**

Run:

```bash
dart format --output=none --set-exit-if-changed \
  lib/git.dart lib/timeline.dart test/git_test.dart test/app_test.dart
```

Expected: formatter exits successfully without changing files.

- [ ] **Step 2: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run the full test suite**

Run:

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Run a macOS debug build**

Run:

```bash
flutter build macos --debug
```

Expected: build completes successfully and produces the debug app.

- [ ] **Step 5: Inspect the final diff**

Run:

```bash
git diff main...HEAD --check
git diff --stat main...HEAD
git status --short
```

Expected: no whitespace errors, only the spec, plan, Git repository, timeline,
and their tests differ from `main`, and the worktree has no tracked changes.

- [ ] **Step 6: Merge locally after review**

After the implementation review passes, merge the feature branch into the
local `main` branch without touching the untracked `.superpowers/brainstorm/`
files.
