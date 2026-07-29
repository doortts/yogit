# Deleted Branch Name Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover the name of a deleted branch when its timeline lane is
selected, show it with a `삭제됨` badge, and persist successful results per
repository.

**Architecture:** Reuse `GraphRow.branch` to derive a stable lane-tip SHA.
Resolve a name lazily from settings, local merge/reflog data, then the existing
GitHub/GHE `gh` connection. Keep orchestration in `TimelineScreen`, Git parsing
in `git.dart`, PR parsing in `avatars.dart`, and persistence in `AppSettings`.

**Tech Stack:** Flutter/Dart, Git CLI, GitHub CLI (`gh`), existing
`SettingsStore`

## Global Constraints

- Add no package or service abstraction.
- Do not scan Git history or PRs at app startup.
- Lookup order is persistent cache, local Git data, then GitHub/GHE PR data.
- Persist successful names only, keyed by repository root and lane-tip SHA.
- A live branch, remote ref, or tag always wins over a recovered name.
- Show recovered data only on the selected row.
- Use the copy `브랜치 이름 찾는 중…` and `삭제됨`.
- A failed lookup must not block or replace the timeline.
- Do not call a real network service from tests.

---

### Task 1: Persist repository-scoped recovered names

**Files:**
- Modify: `lib/settings.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: existing `AppSettings.fromJson`, `toJson`, `copyWith`, equality,
  and `SettingsStore`
- Produces:
  `Map<String, Map<String, String>> AppSettings.deletedBranchNames`
  and
  `AppSettings.copyWith({Map<String, Map<String, String>>? deletedBranchNames})`

- [ ] **Step 1: Write the failing settings tests**

Add tests beside the existing `baseBranches` round-trip tests:

```dart
test('deleted branch names round-trip per repository', () {
  const settings = AppSettings(
    deletedBranchNames: {
      '/repos/one': {'tip-a': 'feature/one'},
      '/repos/two': {'tip-b': 'fix/two'},
    },
  );

  expect(AppSettings.fromJson(settings.toJson()), settings);
});

test('deleted branch names ignore malformed nested entries', () {
  expect(
    AppSettings.fromJson({
      'deletedBranchNames': {
        '/repos/one': {'tip-a': 'feature/one', 'bad': 42},
        '/repos/bad': 'not-a-map',
      },
    }).deletedBranchNames,
    {
      '/repos/one': {'tip-a': 'feature/one'},
    },
  );
});
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
flutter test test/app_test.dart --plain-name "deleted branch names"
```

Expected: compile failure because `deletedBranchNames` does not exist.

- [ ] **Step 3: Add the minimal settings field**

Add a nested-string-map parser and equality helper in `settings.dart`:

```dart
Map<String, Map<String, String>> _parseNestedStringMap(Object? value) => {
  if (value is Map)
    for (final repository in value.entries)
      if (repository.key is String && repository.value is Map)
        repository.key as String: {
          for (final entry in (repository.value as Map).entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        },
};

bool _nestedStringMapEquals(
  Map<String, Map<String, String>> left,
  Map<String, Map<String, String>> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!mapEquals(entry.value, right[entry.key])) return false;
  }
  return true;
}
```

Wire `deletedBranchNames` into the constructor, field, `copyWith`, `fromJson`,
`toJson`, equality, and `hashCode`. Keep the default `const {}` and preserve
unknown or malformed settings by dropping only the malformed cache entries.

- [ ] **Step 4: Run the focused tests**

Run:

```bash
flutter test test/app_test.dart --plain-name "deleted branch names"
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/settings.dart test/app_test.dart
git commit -m "feat: persist deleted branch name cache"
```

---

### Task 2: Recover names from merge subjects and reflog

**Files:**
- Modify: `lib/git.dart`
- Test: `test/git_test.dart`

**Interfaces:**
- Consumes: `GitCommit.subject`, `GitCommit.parents`, `GitRepository.runner`
- Produces:
  `String? deletedBranchNameFromMerge(Iterable<GitCommit> commits, String tipSha)`,
  `String? deletedBranchNameFromReflog(String output, String tipSha)`, and
  `Future<String?> GitRepository.loadLocalDeletedBranchName(String tipSha, Iterable<GitCommit> commits)`

- [ ] **Step 1: Write failing parser tests**

Add table-driven tests:

```dart
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

test('ignores arbitrary subjects and first-parent matches', () {
  expect(
    deletedBranchNameFromMerge([
      _commit('merge', ['tip', 'side'], subject: 'Merge feature/local'),
    ], 'tip'),
    isNull,
  );
});

test('finds a checkout source whose previous reflog sha is the tip', () {
  const output =
      'main-tip\x00checkout: moving from feature/gone to main\n'
      'gone-tip\x00commit: finish feature\n';
  expect(
    deletedBranchNameFromReflog(output, 'gone-tip'),
    'feature/gone',
  );
});
```

Update the local `_commit` test helper to accept:

```dart
String subject = 'subject',
```

- [ ] **Step 2: Run the parser tests and verify they fail**

Run:

```bash
flutter test test/git_test.dart --plain-name "deleted branch"
```

Expected: compile failure because the parser functions do not exist.

- [ ] **Step 3: Implement the two pure parsers**

Use anchored patterns only:

```dart
final _mergedBranchPatterns = <RegExp>[
  RegExp(r"^Merge branch '([^']+)'(?: into .+)?$"),
  RegExp(r"^Merge remote-tracking branch '[^/']+/([^']+)'(?: into .+)?$"),
  RegExp(r'^Merge pull request #\d+ from [^/]+/(.+)$'),
];
```

`deletedBranchNameFromMerge` must inspect only commits whose
`parents.skip(1)` contains `tipSha`. `deletedBranchNameFromReflog` must pair a
checkout entry with the immediately older reflog entry and reject `HEAD`, `-`,
and 7–40 digit hexadecimal detached-HEAD values.

- [ ] **Step 4: Write the failing repository command test**

```dart
test('local deleted branch lookup falls back from merge to HEAD reflog', () async {
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
  expect(arguments, [
    'reflog',
    'show',
    '--format=%H%x00%gs',
    'HEAD',
  ]);
});
```

- [ ] **Step 5: Implement the repository method**

`loadLocalDeletedBranchName` must return the merge-subject result first. When
that is null, run the exact reflog command above and return the pure parser
result. Catch `ProcessException` and return null because a missing or expired
reflog is an expected miss.

- [ ] **Step 6: Run the local recovery tests**

Run:

```bash
flutter test test/git_test.dart --plain-name "deleted branch"
flutter test test/git_test.dart --plain-name "local deleted branch"
```

Expected: all focused tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: recover deleted branch names from git history"
```

---

### Task 3: Resolve names from GitHub and GHE pull requests

**Files:**
- Modify: `lib/avatars.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `RemoteRepository`, `AvatarService.ghExecutable`,
  `AvatarService.runner`
- Produces:
  `Future<String?> AvatarService.resolveMergedBranchName(String tipSha)`

- [ ] **Step 1: Write the failing PR-selection test**

```dart
test('deleted branch PR lookup prefers exact head sha then latest merge', () async {
  final requests = <List<String>>[];
  final service = AvatarService(
    remote: const RemoteRepository(
      host: 'github.com',
      owner: 'team',
      repository: 'yogit',
    ),
    ghExecutable: '/usr/bin/gh',
    runner: (executable, arguments, {workingDirectory, environment}) async {
      requests.add(arguments);
      return ProcessResult(1, 0, '''
[
  {"merged_at":"2026-07-28T12:00:00Z","head":{"sha":"other","ref":"newer"}},
  {"merged_at":"2026-07-27T12:00:00Z","head":{"sha":"tip","ref":"exact"}}
]
''', '');
    },
  );

  expect(await service.resolveMergedBranchName('tip'), 'exact');
  expect(requests.single, [
    'api',
    '--hostname',
    'github.com',
    'repos/team/yogit/commits/tip/pulls',
  ]);
});
```

Add one test where no `head.sha` matches and the newest merged PR wins. Add a
test that null `merged_at`, malformed JSON, and a non-zero exit code return
null.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
flutter test test/app_test.dart --plain-name "deleted branch PR"
```

Expected: compile failure because `resolveMergedBranchName` does not exist.

- [ ] **Step 3: Implement the minimal PR parser**

Run the command asserted above. Accept only list entries containing a valid
ISO-8601 `merged_at`, a non-empty `head.sha`, and a non-empty `head.ref`. Sort
candidates by:

1. `head.sha == tipSha`
2. parsed `merged_at`, newest first

Return the first `head.ref`. Return null for process failure, malformed JSON,
or no merged candidate. Do not add authentication, retry, or caching code;
`gh` and the persistent timeline cache already cover those responsibilities.

- [ ] **Step 4: Run the PR lookup tests**

Run:

```bash
flutter test test/app_test.dart --plain-name "deleted branch PR"
```

Expected: all focused tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/avatars.dart test/app_test.dart
git commit -m "feat: resolve deleted branch names from pull requests"
```

---

### Task 4: Show and persist the recovered name in the timeline

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/timeline.dart`
- Modify: `test/app_test.dart`

**Interfaces:**
- Consumes:
  `AppSettings.deletedBranchNames`,
  `GitRepository.loadLocalDeletedBranchName`,
  `AvatarService.resolveMergedBranchName`,
  `RepoRefs.tips`, and `GraphRow.branch`
- Produces these optional `TimelineScreen` parameters:

```dart
Map<String, String> deletedBranchNames = const {},
bool deletedBranchNamesReady = true,
ValueChanged<Map<String, String>>? onDeletedBranchNamesChanged,
```

- [ ] **Step 1: Write the failing lane-tip helper test**

Add a visible-for-testing helper:

```dart
String? branchLineTipSha(List<GraphRow> rows, int branch)
```

Test that it returns the first non-working-tree SHA on the requested branch
line and ignores the synthetic working-tree row:

```dart
test('deleted branch lookup uses the first real commit on a branch line', () {
  final rows = layoutGraph([
    workingTreeCommit('tip'),
    commit('tip', 'tip'),
    commit('older', 'older'),
  ]);

  expect(branchLineTipSha(rows, rows.last.branch), 'tip');
});
```

- [ ] **Step 2: Write the failing widget test**

Extend `FakeGitRepository` with:

```dart
Future<String?> Function(String tipSha, Iterable<GitCommit> commits)?
deletedBranchNameCallback,
```

and override `loadLocalDeletedBranchName`.

Build a merged history whose side lane has no live ref. Select the side commit
and complete a `Completer<String?>` in the fake repository. Assert:

```dart
expect(find.text('브랜치 이름 찾는 중…'), findsOneWidget);
resolver.complete('feature/gone');
await tester.pumpAndSettle();
expect(find.byKey(const Key('deleted-branch-badge-side-tip')), findsOneWidget);
expect(find.text('삭제됨'), findsOneWidget);
expect(find.text('feature/gone'), findsOneWidget);
```

Inspect the badge decoration and assert that its background has a non-zero red
component and opacity below 1.0. Move selection to a different lane and assert
that the recovered label leaves the old row.

- [ ] **Step 3: Add lazy recovery state and orchestration**

In `_TimelineScreenState`, keep:

```dart
late Map<String, String> _deletedBranchNames;
final _deletedBranchLookupAttempts = <String>{};
String? _resolvingDeletedBranchTip;
var _deletedBranchLookupSerial = 0;
```

Listen to `_selectedIndex` and start lookup only when:

- settings are ready;
- normal timeline mode is active;
- the selected entry is a real commit;
- `branchLineTipSha` returns a SHA;
- `_refs.tips` does not already contain that SHA;
- the cache has no name; and
- the SHA was not fully attempted in this app session.

Call local recovery first and then
`widget.avatarService?.resolveMergedBranchName(tipSha)`. If no avatar service
exists, remove the SHA from the attempts set so a later discovered service can
try. Before changing visible state, compare the lookup serial, repository
widget, selected commit SHA, and current tip SHA. Cache successful results even
when the selection moved while the lookup was running.

Initialize the cache from `widget.deletedBranchNames`. In `didUpdateWidget`,
replace it when persisted settings finish loading and trigger the selected-row
lookup. Remove the selection listener in `dispose`.

- [ ] **Step 4: Render the selected-row status**

Pass the selected row's loading state or recovered name into `_refsCell`.
When the existing `refs` list is empty:

- show `브랜치 이름 찾는 중…` in muted text while resolving;
- otherwise show a compact `삭제됨` badge and ellipsized branch name.

Use these keys:

```dart
Key('deleted-branch-loading-${commit.sha}')
Key('deleted-branch-badge-${commit.sha}')
Key('deleted-branch-name-${commit.sha}')
```

Use `Theme.of(context).colorScheme.error.withValues(alpha: 0.18)` for the
badge background and the opaque error color for its text. Keep the recovered
name in the branch lane color.

- [ ] **Step 5: Wire persistence through `YogitApp`**

Pass only the current repository's map:

```dart
deletedBranchNames:
    _settings.deletedBranchNames[_repository.root] ?? const {},
deletedBranchNamesReady: _settingsLoaded,
```

The callback must copy the outer and inner maps, replace the current
repository entry, then call `_changeSettings`:

```dart
onDeletedBranchNamesChanged: _settingsLoaded
    ? (names) {
        final all = {
          for (final entry in _settings.deletedBranchNames.entries)
            entry.key: Map<String, String>.of(entry.value),
        }..[_repository.root] = Map<String, String>.of(names);
        _changeSettings(_settings.copyWith(deletedBranchNames: all));
      }
    : null,
```

- [ ] **Step 6: Add failure, live-ref, cache, and stale-result tests**

Add focused widget tests proving:

- a live ref at the lane tip prevents local and PR lookup;
- an initial cache value renders immediately without a lookup;
- a successful result reaches `MemorySettingsStore` under the repository root;
- null/error results remove the loading copy and keep the timeline usable;
- selecting another commit before completion never labels the new row;
- the same failed SHA with an available avatar service is attempted only once
  per app session.

- [ ] **Step 7: Run the timeline tests**

Run:

```bash
flutter test test/app_test.dart --plain-name "deleted branch"
```

Expected: all deleted-branch settings, PR, and widget tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/main.dart lib/timeline.dart test/app_test.dart
git commit -m "feat: show recovered deleted branch names"
```

---

### Task 5: Verify the complete change

**Files:**
- Verify only

**Interfaces:**
- Consumes: Tasks 1–4
- Produces: a clean, tested feature branch ready to merge

- [ ] **Step 1: Format changed Dart files**

Run:

```bash
dart format lib/settings.dart lib/git.dart lib/avatars.dart lib/main.dart lib/timeline.dart test/git_test.dart test/app_test.dart
```

Expected: formatter exits successfully.

- [ ] **Step 2: Run focused tests**

Run:

```bash
flutter test test/git_test.dart
flutter test test/app_test.dart --plain-name "deleted branch"
```

Expected: all tests pass.

- [ ] **Step 3: Run the full verification suite**

Run:

```bash
flutter analyze
flutter test
flutter build macos --debug
```

Expected: no analyzer findings, all tests pass, and the macOS debug app builds.

- [ ] **Step 4: Inspect the final diff and working tree**

Run:

```bash
git diff main...HEAD --check
git status --short
```

Expected: no whitespace errors and no uncommitted files.
