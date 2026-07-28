# Sidebar Ref Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render LOCAL, REMOTE, and TAGS as collapsible slash-delimited trees, with type icons and only the ten newest tags shown until the user expands the remainder.

**Architecture:** Keep `RepoRefs` as the repository-facing flat ref snapshot and add tag creator timestamps to it. Convert ordered ref names into a small immutable tree in a new pure-Dart module, then let `TimelineScreen` own only session expansion state and recursive row rendering. Filtering derives a temporary fully expanded tree and never mutates the stored section, folder, or tag-overflow state.

**Tech Stack:** Dart 3, Flutter Material widgets, `git for-each-ref`, `flutter_test`

## Global Constraints

- LOCAL, REMOTE, and TAGS start expanded and have a matching leading icon plus a disclosure control.
- Split every ref name on `/`; intermediate segments are folders and the final segment remains selectable.
- All folders start expanded and expansion state lasts only for the current `TimelineScreen` session.
- Preserve current-branch highlighting, branch birth labels, ref selection, filtering, and sidebar resizing.
- Sort tags by Git creator timestamp descending. Undated tags follow dated tags and sort by complete name.
- Show ten tags initially and put all remaining tags behind one `나머지 N개` row that can expand and collapse them.
- Filtering searches all refs, including hidden tags, and temporarily reveals matching ancestors without changing saved expansion state.
- Add no package dependency.

---

### Task 1: Load Tag Creator Timestamps

**Files:**
- Modify: `lib/git.dart:711-728`
- Modify: `lib/git.dart:1200-1250`
- Test: `test/git_test.dart:774-835`

**Interfaces:**
- Consumes: Existing `GitRepository.loadRefs()` and `RepoRefs`.
- Produces: `RepoRefs.tagCreatorTimes` with type `Map<String, int>` keyed by complete short tag name.

- [ ] **Step 1: Write the failing repository tests**

Extend the existing `buckets refs into local, remote, and tags` test so the
fixture contains creator dates and one missing date:

```dart
'refs/heads/main aaa1 1700000100\n'
'refs/heads/feature/x aaa2 1700000200\n'
'refs/remotes/origin/HEAD aaa1 1700000100\n'
'refs/remotes/origin/main aaa3 1700000300\n'
'refs/tags/v0.1.0 aaa4 1700000400\n'
'refs/tags/undated aaa5 \n'
```

Add these expectations:

```dart
expect(refs.tags, ['undated', 'v0.1.0']);
expect(refs.tagCreatorTimes, {'v0.1.0': 1700000400});
expect(calls.first, [
  'for-each-ref',
  '--format=%(refname) %(objectname) %(creatordate:unix)',
  'refs/heads',
  'refs/remotes',
  'refs/tags',
]);
```

The list expectation follows Git's ref-name order; timestamp sorting belongs to
the presentation helper in Task 2.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/git_test.dart --plain-name "buckets refs into local, remote, and tags"
```

Expected: compilation fails because `RepoRefs.tagCreatorTimes` does not exist,
or the command-format expectation fails before the field is added.

- [ ] **Step 3: Add the timestamp field and parse the third column**

Add the optional field without breaking existing const fixtures:

```dart
class RepoRefs {
  const RepoRefs({
    this.local = const [],
    this.remote = const [],
    this.tags = const [],
    this.current,
    this.tips = const {},
    this.birthTimes = const {},
    this.tagCreatorTimes = const {},
  });

  final List<String> local;
  final List<String> remote;
  final List<String> tags;
  final String? current;
  final Map<String, int> birthTimes;
  final Map<String, String> tips;
  final Map<String, int> tagCreatorTimes;
}
```

Change the Git format and parse the first two spaces rather than splitting on
every space:

```dart
final lines = (await _run([
  'for-each-ref',
  '--format=%(refname) %(objectname) %(creatordate:unix)',
  'refs/heads',
  'refs/remotes',
  'refs/tags',
])).split('\n').where((line) => line.isNotEmpty);

final tagCreatorTimes = <String, int>{};
for (final line in lines) {
  final firstSpace = line.indexOf(' ');
  final secondSpace = line.indexOf(' ', firstSpace + 1);
  final name = line.substring(0, firstSpace);
  final sha = secondSpace < 0
      ? line.substring(firstSpace + 1)
      : line.substring(firstSpace + 1, secondSpace);
  final creatorTime = secondSpace < 0
      ? null
      : int.tryParse(line.substring(secondSpace + 1).trim());

  for (final bucket in buckets.entries) {
    if (!name.startsWith(bucket.key)) continue;
    final short = name.substring(bucket.key.length);
    if (bucket.value == remote && short.endsWith('/HEAD')) break;
    bucket.value.add(short);
    tips[short] = sha;
    if (bucket.value == tags && creatorTime != null) {
      tagCreatorTimes[short] = creatorTime;
    }
    break;
  }
}
```

Return all fields explicitly:

```dart
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
  tagCreatorTimes: tagCreatorTimes,
);
```

- [ ] **Step 4: Run repository tests and verify GREEN**

Run:

```bash
flutter test test/git_test.dart
```

Expected: all `git_test.dart` tests pass.

- [ ] **Step 5: Commit the repository change**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: load tag creator times"
```

---

### Task 2: Build Ordered Ref Trees

**Files:**
- Create: `lib/ref_tree.dart`
- Create: `test/ref_tree_test.dart`

**Interfaces:**
- Consumes: Ordered complete ref names and `Map<String, int>` tag creator timestamps.
- Produces:
  - `RefTreeNode`
  - `List<RefTreeNode> buildRefTree(Iterable<String> names)`
  - `List<String> sortTagsNewestFirst(Iterable<String> names, Map<String, int> creatorTimes)`

- [ ] **Step 1: Write failing tree and tag-order tests**

Create `test/ref_tree_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/ref_tree.dart';

void main() {
  test('builds slash-delimited refs without duplicating prefix refs', () {
    final roots = buildRefTree([
      'feature',
      'feature/login',
      'feature/payments/api',
      'main',
    ]);

    expect(roots.map((node) => node.segment), ['feature', 'main']);
    expect(roots.first.fullName, 'feature');
    expect(roots.first.children.map((node) => node.segment), [
      'login',
      'payments',
    ]);
    expect(roots.first.children.first.fullName, 'feature/login');
    expect(
      roots.first.children.last.children.single.fullName,
      'feature/payments/api',
    );
  });

  test('preserves first-descendant order at every tree level', () {
    final roots = buildRefTree([
      'origin/release/z',
      'upstream/main',
      'origin/main',
      'origin/release/a',
    ]);

    expect(roots.map((node) => node.segment), ['origin', 'upstream']);
    expect(roots.first.children.map((node) => node.segment), [
      'release',
      'main',
    ]);
    expect(
      roots.first.children.first.children.map((node) => node.segment),
      ['z', 'a'],
    );
  });

  test('sorts dated tags newest first and undated tags by name last', () {
    expect(
      sortTagsNewestFirst(
        ['undated-z', 'v1', 'v3', 'undated-a', 'v2'],
        {'v1': 100, 'v2': 200, 'v3': 200},
      ),
      ['v2', 'v3', 'v1', 'undated-a', 'undated-z'],
    );
  });
}
```

- [ ] **Step 2: Run the new test and verify RED**

Run:

```bash
flutter test test/ref_tree_test.dart
```

Expected: compilation fails because `package:yogit/ref_tree.dart` and its public
interfaces do not exist.

- [ ] **Step 3: Implement the minimal pure-Dart tree module**

Create `lib/ref_tree.dart`:

```dart
class RefTreeNode {
  const RefTreeNode({
    required this.segment,
    this.fullName,
    this.children = const [],
  });

  final String segment;
  final String? fullName;
  final List<RefTreeNode> children;
}

class _MutableRefTreeNode {
  _MutableRefTreeNode(this.segment);

  final String segment;
  String? fullName;
  final Map<String, _MutableRefTreeNode> children = {};

  RefTreeNode freeze() => RefTreeNode(
    segment: segment,
    fullName: fullName,
    children: [for (final child in children.values) child.freeze()],
  );
}

List<RefTreeNode> buildRefTree(Iterable<String> names) {
  final roots = <String, _MutableRefTreeNode>{};
  for (final name in names) {
    final segments = name.split('/');
    var level = roots;
    _MutableRefTreeNode? node;
    for (final segment in segments) {
      node = level.putIfAbsent(
        segment,
        () => _MutableRefTreeNode(segment),
      );
      level = node.children;
    }
    node!.fullName = name;
  }
  return [for (final root in roots.values) root.freeze()];
}

List<String> sortTagsNewestFirst(
  Iterable<String> names,
  Map<String, int> creatorTimes,
) {
  final sorted = names.toList();
  sorted.sort((left, right) {
    final leftTime = creatorTimes[left];
    final rightTime = creatorTimes[right];
    if (leftTime != null && rightTime != null) {
      final byTime = rightTime.compareTo(leftTime);
      if (byTime != 0) return byTime;
      return left.compareTo(right);
    }
    if (leftTime != null) return -1;
    if (rightTime != null) return 1;
    return left.compareTo(right);
  });
  return sorted;
}
```

- [ ] **Step 4: Run the tree tests and verify GREEN**

Run:

```bash
flutter test test/ref_tree_test.dart
```

Expected: all three tests pass.

- [ ] **Step 5: Format and commit the tree module**

```bash
dart format lib/ref_tree.dart test/ref_tree_test.dart
git add lib/ref_tree.dart test/ref_tree_test.dart
git commit -m "feat: build ordered ref trees"
```

---

### Task 3: Render Collapsible Sidebar Trees

**Files:**
- Modify: `lib/timeline.dart:1-16`
- Modify: `lib/timeline.dart:400-490`
- Modify: `lib/timeline.dart:1174-1385`
- Test: `test/app_test.dart:1920-1988`
- Test: `test/app_test.dart:7280-7330`

**Interfaces:**
- Consumes: `buildRefTree()`, complete ref names, existing `_selectRef()`, `_localBranches`, and `_refs`.
- Produces: Section rows keyed as `sidebar-section-<local|remote|tags>`, folder rows keyed as `sidebar-folder-<section>-<full-path>`, and the existing leaf keys `sidebar-ref-<complete-name>`.

- [ ] **Step 1: Replace the flat-list widget test with failing tree expectations**

Update the existing sidebar test fixture to include nested refs and commits
decorated with their complete names:

```dart
refs: const RepoRefs(
  local: ['main', 'feature/login', 'feature/payments/api'],
  remote: ['origin/main', 'origin/hotfix/urgent'],
  tags: ['release/v1.0.0'],
  current: 'main',
),
```

Assert the structure and icons by stable keys:

```dart
for (final section in ['local', 'remote', 'tags']) {
  expect(find.byKey(Key('sidebar-section-$section')), findsOneWidget);
  expect(find.byKey(Key('sidebar-section-icon-$section')), findsOneWidget);
  expect(find.byKey(Key('sidebar-section-count-$section')), findsOneWidget);
}
expect(find.byKey(const Key('sidebar-folder-local-feature')), findsOneWidget);
expect(
  find.byKey(const Key('sidebar-folder-local-feature/payments')),
  findsOneWidget,
);
expect(find.byKey(const Key('sidebar-folder-remote-origin')), findsOneWidget);
expect(
  find.byKey(const Key('sidebar-ref-feature/payments/api')),
  findsOneWidget,
);
```

Then tap `sidebar-folder-local-feature`, verify both feature leaves disappear,
tap it again, and verify they return. Tap `sidebar-section-remote`, verify
`sidebar-ref-origin/main` disappears, and tap again to restore it. Keep the
existing assertion that tapping a leaf selects the decorated commit.

Finally collapse `sidebar-folder-local-feature`, enter `login` in `ref-filter`,
and verify `sidebar-ref-feature/login` is temporarily visible. Clear the filter
and verify the leaf is hidden again, proving that filtering did not overwrite
the saved folder state.

Add a second focused test with `refs: const RepoRefs()` and verify all three
section keys remain present while each keyed count renders `0`:

```dart
for (final section in ['local', 'remote', 'tags']) {
  expect(find.byKey(Key('sidebar-section-$section')), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(Key('sidebar-section-count-$section')),
      matching: find.text('0'),
    ),
    findsOneWidget,
  );
}
```

- [ ] **Step 2: Run the focused widget test and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name "sidebar lists refs as collapsible trees, filters them, and moves the selection"
flutter test test/app_test.dart --plain-name "empty ref trees keep their section headers"
```

Expected: the new section and folder keys are absent because the sidebar still
renders a flat list; the empty-tree test also fails because the keyed section
headers do not exist.

- [ ] **Step 3: Add session expansion state and section rendering**

Import `ref_tree.dart` and add private section metadata:

```dart
enum _RefSection {
  local('LOCAL', Icons.computer_outlined),
  remote('REMOTE', Icons.cloud_outlined),
  tags('TAGS', Icons.sell_outlined);

  const _RefSection(this.label, this.icon);
  final String label;
  final IconData icon;
}
```

Add state fields:

```dart
final _collapsedRefSections = <_RefSection>{};
final _collapsedRefFolders = <String>{};
```

Replace `_sidebarSection()` with `_refSection()` and a recursive
`_refTreeRows()` helper. Use these rules in the implementation:

```dart
final filtering = _filter.trim().isNotEmpty;
final sectionCollapsed =
    !filtering && _collapsedRefSections.contains(section);
final folderKey = '${section.name}:$path';
final folderCollapsed =
    !filtering && _collapsedRefFolders.contains(folderKey);
```

The section header must:

- Use `sidebar-section-${section.name}` as its key.
- Toggle only `_collapsedRefSections`.
- Render a disclosure icon, the keyed type icon, the uppercase label, a spacer,
  and the total complete-ref count in `sidebar-section-count-${section.name}`.

The recursive node row must:

- Indent by `8 + depth * 16` logical pixels.
- Render a disclosure control when `children.isNotEmpty`.
- Use `Icons.folder_outlined` for a folder-only node,
  `Icons.call_split` for a local or remote ref, and `Icons.sell_outlined` for a
  tag ref.
- Give folders `sidebar-folder-${section.name}-$path`.
- Keep selectable rows keyed `sidebar-ref-${node.fullName}`.
- Let the disclosure control toggle children without selecting the ref.
- Let the label select `node.fullName` when it is present.
- Preserve current-branch accent styling and the existing birth-time second
  line on local ref rows.

For filtering, derive matching names before calling `buildRefTree()`:

```dart
final query = _filter.trim().toLowerCase();
final visibleNames = query.isEmpty
    ? names
    : names.where((name) => name.toLowerCase().contains(query)).toList();
```

Because the filtered tree contains only matching complete names and filtering
ignores collapse sets, every matching ancestor appears without mutating saved
state.

- [ ] **Step 4: Run the focused widget tests and verify GREEN**

Run:

```bash
flutter test test/app_test.dart --plain-name "sidebar lists refs as collapsible trees, filters them, and moves the selection"
flutter test test/app_test.dart --plain-name "empty ref trees keep their section headers"
flutter test test/app_test.dart --plain-name "local branches show when they were cut, when the reflog knows"
flutter test test/app_test.dart --plain-name "the sidebar resizes, persists, and clamps"
```

Expected: all four tests pass.

- [ ] **Step 5: Commit the collapsible tree UI**

```bash
dart format lib/timeline.dart test/app_test.dart
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: render sidebar ref trees"
```

---

### Task 4: Limit Tags to the Ten Newest

**Files:**
- Modify: `lib/timeline.dart:1174-1385`
- Test: `test/app_test.dart` beside the sidebar tree tests

**Interfaces:**
- Consumes: `sortTagsNewestFirst()`, `_refs.tags`, and `_refs.tagCreatorTimes`.
- Produces: `sidebar-tags-overflow`, showing `나머지 N개` while collapsed and `태그 접기` while expanded.

- [ ] **Step 1: Write the failing tag-overflow widget test**

Add a helper fixture inside the test:

```dart
final tags = [for (var index = 1; index <= 12; index++) 'release/v$index'];
final tagTimes = {
  for (var index = 1; index <= 12; index++) 'release/v$index': index * 100,
};
```

Pump a repository with those tags and assert:

```dart
expect(find.byKey(const Key('sidebar-ref-release/v12')), findsOneWidget);
expect(find.byKey(const Key('sidebar-ref-release/v3')), findsOneWidget);
expect(find.byKey(const Key('sidebar-ref-release/v2')), findsNothing);
expect(find.byKey(const Key('sidebar-ref-release/v1')), findsNothing);
expect(find.text('나머지 2개'), findsOneWidget);

await tester.tap(find.byKey(const Key('sidebar-tags-overflow')));
await tester.pump();
expect(find.byKey(const Key('sidebar-ref-release/v1')), findsOneWidget);
expect(find.text('태그 접기'), findsOneWidget);

await tester.tap(find.byKey(const Key('sidebar-tags-overflow')));
await tester.pump();
expect(find.byKey(const Key('sidebar-ref-release/v1')), findsNothing);
```

Continue in the same test by entering `v1` in `ref-filter`. Verify both
`release/v1` and `release/v10` through `release/v12` appear, the overflow row is
hidden while filtering, and clearing the filter restores the collapsed ten-tag
view.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name "tags show the newest ten and filtering reveals hidden matches"
```

Expected: all twelve tags are visible immediately and
`sidebar-tags-overflow` is absent.

- [ ] **Step 3: Add the tag projection and overflow row**

Add:

```dart
static const _collapsedTagLimit = 10;
var _showAllTags = false;

List<String> get _sortedTags =>
    sortTagsNewestFirst(_refs.tags, _refs.tagCreatorTimes);
```

In the TAGS section:

```dart
final filtering = _filter.trim().isNotEmpty;
final sortedTags = _sortedTags;
final hiddenTagCount = math.max(0, sortedTags.length - _collapsedTagLimit);
final names = filtering || _showAllTags
    ? sortedTags
    : sortedTags.take(_collapsedTagLimit).toList();
```

After the visible tag tree, render the overflow row only when
`!filtering && hiddenTagCount > 0`. Key it `sidebar-tags-overflow`, use a
disclosure icon, and toggle `_showAllTags`:

```dart
Text(_showAllTags ? '태그 접기' : '나머지 $hiddenTagCount개')
```

The TAGS section count must remain `_refs.tags.length`, not the projected count.
Collapsing the entire TAGS section must preserve `_showAllTags`.

- [ ] **Step 4: Run sidebar tests and verify GREEN**

Run:

```bash
flutter test test/app_test.dart --plain-name "tags show the newest ten and filtering reveals hidden matches"
flutter test test/app_test.dart --plain-name "sidebar lists refs as collapsible trees, filters them, and moves the selection"
```

Expected: both tests pass.

- [ ] **Step 5: Commit the tag limit**

```bash
dart format lib/timeline.dart test/app_test.dart
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: collapse older sidebar tags"
```

---

### Task 5: Verify the Complete Change

**Files:**
- Verify: `lib/git.dart`
- Verify: `lib/ref_tree.dart`
- Verify: `lib/timeline.dart`
- Verify: `test/git_test.dart`
- Verify: `test/ref_tree_test.dart`
- Verify: `test/app_test.dart`

**Interfaces:**
- Consumes: All completed task outputs.
- Produces: A formatted, analyzer-clean change with all tests passing.

- [ ] **Step 1: Format all Dart sources**

Run:

```bash
dart format lib test
```

Expected: formatter completes without errors. Review any changed file and include
only formatting caused by this feature.

- [ ] **Step 2: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run the focused suites**

Run:

```bash
flutter test test/git_test.dart test/ref_tree_test.dart test/app_test.dart
```

Expected: all focused tests pass.

- [ ] **Step 4: Run the complete test suite**

Run:

```bash
flutter test
```

Expected: all tests pass with exit code 0.

- [ ] **Step 5: Check the final diff**

Run:

```bash
git diff --check
git status --short
git log --oneline -5
```

Expected: no whitespace errors; only the user's pre-existing unrelated changes
may remain unstaged; the feature commits are visible at the branch tip.
