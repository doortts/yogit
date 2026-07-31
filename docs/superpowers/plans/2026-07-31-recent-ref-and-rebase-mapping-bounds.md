# Recent Ref Ordering and Rebase Mapping Bounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Order branch and tag choices by recency and keep Rebase same-commit mapping lines inside the Graph column.

**Architecture:** Preserve the selector as a rendering-only widget. Capture branch tip dates from the existing `for-each-ref` result, sort lists in the timeline, and pass ordered groups to the selector. Keep mapping rendering in `RebaseMappingPainter`, but use half-lane route spacing, clip its canvas, and fall back to the focused mapping when every route cannot fit.

**Tech Stack:** Dart, Flutter, Flutter widget tests, direct `Canvas` painter tests, Git CLI metadata already loaded by `GitRepository`.

## Global Constraints

- Do not add a dependency or another Git process call.
- Base branch choices remain local branches only.
- Branch diff choices use `LOCAL`, `REMOTE`, and `TAG` groups.
- Mapping routes remain one-pixel solid lines with their existing colors and open arrowheads.
- Mapping route spacing is exactly 50% of the commit-lane spacing.
- No mapping pixel may be painted outside the Graph column.

---

### Task 1: Capture and sort reference recency

**Files:**
- Modify: `lib/git.dart`
- Modify: `lib/ref_tree.dart`
- Test: `test/git_test.dart`
- Test: `test/ref_tree_test.dart`

**Interfaces:**
- Produces: `RepoRefs.branchActivityTimes`, a `Map<String, int>` containing local and remote branch tip dates.
- Produces: `sortRefsNewestFirst(Iterable<String>, Map<String, int>)`.

- [ ] **Step 1: Write failing metadata and sorting tests**

Add a literal expectation to the existing `loadRefs` test:

```dart
expect(refs.branchActivityTimes, {
  'main': 1700000100,
  'feature/x': 1700000200,
  'company/trunk': 1700000300,
});
```

Replace the tag-only sorting test with a generic behavior test:

```dart
test('sorts dated refs newest first and undated refs by name last', () {
  expect(
    sortRefsNewestFirst(
      ['undated-z', 'v1', 'v3', 'undated-a', 'v2'],
      {'v1': 100, 'v2': 200, 'v3': 200},
    ),
    ['v2', 'v3', 'v1', 'undated-a', 'undated-z'],
  );
});
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
flutter test test/git_test.dart test/ref_tree_test.dart
```

Expected: compilation fails because `branchActivityTimes` and `sortRefsNewestFirst` do not exist.

- [ ] **Step 3: Store existing Git dates and generalize the sorter**

Add the optional field to `RepoRefs`:

```dart
this.branchActivityTimes = const {},
...
final Map<String, int> branchActivityTimes;
```

In `loadRefs`, record `creatorTime` for local and remote buckets:

```dart
if ((bucket.value == local || bucket.value == remote) &&
    creatorTime != null) {
  branchActivityTimes[short] = creatorTime;
}
```

Rename `sortTagsNewestFirst` to `sortRefsNewestFirst` without changing its comparator, then update its existing timeline call.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

```bash
flutter test test/git_test.dart test/ref_tree_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/git.dart lib/ref_tree.dart lib/timeline.dart test/git_test.dart test/ref_tree_test.dart
git commit -m "feat: retain ref activity times"
```

### Task 2: Present recently active branch and tag groups

**Files:**
- Modify: `lib/repository_branch_selector.dart`
- Modify: `lib/timeline.dart`
- Test: `test/repository_branch_selector_test.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `RepoRefs.branchActivityTimes`.
- Consumes: `sortRefsNewestFirst`.
- Produces: `RepositoryBranchSelector.tags`.

- [ ] **Step 1: Write failing selector and timeline tests**

Extend the selector comparison test with tags:

```dart
tags: const ['v2.0.0', 'v1.0.0'],
...
expect(find.text('TAG'), findsOneWidget);
expect(find.byKey(const Key('branch-diff-menu-v2.0.0')), findsOneWidget);
```

Add a timeline widget test whose `RepoRefs` dates deliberately disagree with input order. Open both menus and assert the vertical positions:

```dart
expect(
  tester.getTopLeft(find.byKey(const Key('base-branch-menu-new'))).dy,
  lessThan(tester.getTopLeft(find.byKey(const Key('base-branch-menu-old'))).dy),
);
expect(
  tester.getTopLeft(find.byKey(const Key('branch-diff-menu-origin/new'))).dy,
  lessThan(
    tester.getTopLeft(find.byKey(const Key('branch-diff-menu-origin/old'))).dy,
  ),
);
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
flutter test test/repository_branch_selector_test.dart test/app_test.dart --plain-name "recent"
```

Expected: the selector has no `tags` parameter and the input order remains unchanged.

- [ ] **Step 3: Pass ordered groups into the selector**

Add `tags` to `RepositoryBranchSelector` and `_ComparisonSelector`, render it with the existing `_group` method, and include it in the empty-result condition.

In `TimelineScreen`, calculate only the three lists needed by the toolbar:

```dart
List<String> get _recentLocalBranches => sortRefsNewestFirst(
  _refs.local,
  {
    for (final name in _refs.local)
      if ((_refs.branchActivityTimes[name] ?? _refs.birthTimes[name]) != null)
        name: math.max(
          _refs.branchActivityTimes[name] ?? 0,
          _refs.birthTimes[name] ?? 0,
        ),
  },
);
```

Use `branchActivityTimes` for remotes and `tagCreatorTimes` for tags. Pass all three ordered lists to `RepositoryBranchSelector`.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

```bash
flutter test test/repository_branch_selector_test.dart
flutter test test/app_test.dart --plain-name "recent"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/repository_branch_selector.dart lib/timeline.dart test/repository_branch_selector_test.dart test/app_test.dart
git commit -m "feat: order branch choices by recency"
```

### Task 3: Bound and compress Rebase mapping routes

**Files:**
- Modify: `lib/timeline.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `_selectedIndex` and `_entries` to identify the focused commit.
- Produces: a `RebaseMappingPainter` that repaints when selection changes.

- [ ] **Step 1: Write failing painter tests**

Add a painter test with two routes and assert that their vertical strokes are separated by half of `laneSpacing`, not a full lane.

Add a narrow-width test with three mappings, a focused entry, and a recording canvas wider than the painter size:

```dart
final selectedIndex = ValueNotifier(1);
final painter = RebaseMappingPainter(
  rows: rows,
  entries: [
    for (var index = 0; index < rows.length; index++)
      (rowIndex: index, label: null, row: rows[index]),
  ],
  selectedIndex: selectedIndex,
  mappings: mappings,
  rowIndex: 1,
  laneSpacing: 30.5,
  compact: false,
);
painter.paint(canvas, const Size(70, 36));
```

Assert that only the focused mapping color appears and every pixel at `x >= 70` remains transparent.

- [ ] **Step 2: Run the painter tests and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name "rebase mapping"
```

Expected: the second route still uses full lane spacing, the painter lacks focus inputs, and painting is not explicitly clipped to its size.

- [ ] **Step 3: Implement half spacing, clipping, and focused fallback**

Change the Rebase ratchet contribution to the integer lane equivalent of half-spaced routes:

```dart
deepest = math.max(
  deepest,
  graphDeepest + ((mappings.length + 2) ~/ 2),
);
```

Pass `_selectedIndex` and `_entries` into `RebaseMappingPainter`, wire `selectedIndex` to `super(repaint: selectedIndex)`, and clip first:

```dart
canvas.clipRect(Offset.zero & size);
```

Use:

```dart
final routeSpacing = laneSpacing / 2;
final firstRouteX = _laneX(deepest + 1);
final fitsAll = mappings.every(
  (mapping) =>
      firstRouteX + mapping.routeLane * routeSpacing <= size.width - 1,
);
```

When `fitsAll` is false, keep only the mapping whose original or rewritten SHA matches the selected timeline entry and draw it at `min(firstRouteX, size.width - 1)`.

- [ ] **Step 4: Run painter and preview tests and verify GREEN**

Run:

```bash
flutter test test/app_test.dart --plain-name "rebase mapping"
flutter test test/app_test.dart --plain-name "rebase preview adds rewritten commits"
```

Expected: PASS.

- [ ] **Step 5: Run formatting and the affected suite**

Run:

```bash
dart format lib/git.dart lib/ref_tree.dart lib/repository_branch_selector.dart lib/timeline.dart test/git_test.dart test/ref_tree_test.dart test/repository_branch_selector_test.dart test/app_test.dart
flutter analyze
flutter test test/git_test.dart test/ref_tree_test.dart test/repository_branch_selector_test.dart
flutter test test/app_test.dart
```

Expected: no analyzer findings and all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: bound rebase mapping routes"
```
