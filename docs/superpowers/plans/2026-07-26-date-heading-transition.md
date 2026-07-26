# Date Heading Transition Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep parent-side graph transitions vertical through a date heading and bend them beside the actual parent commit.

**Architecture:** `layoutGraph` remains the source of the repository graph. `timelineEntries` creates display-only `GraphRow` copies at date boundaries: source-side merge transitions stay on the commit above, while parent-side joins move to the synthetic date row. The existing one-row `CommitGraphPainter` then draws the deferred join from the date row center to the parent commit center without learning about multi-row spans.

**Tech Stack:** Dart 3, Flutter, `flutter_test`, existing `GraphRow` and `CommitGraphPainter` APIs

## Global Constraints

- Preserve date heading height, label styling, and selection behavior.
- Keep source-side merge edges bending beside their source commit.
- Keep branch ids and colors unchanged.
- Do not modify `layoutGraph`.
- Do not add dependencies or new asynchronous work.
- Preserve the user's existing `pubspec.lock` change.

## File Structure

- Modify `lib/timeline.dart`: share transition classification and build display-only intermediate graph state at date boundaries.
- Modify `test/app_test.dart`: add a minimal `drl`-shaped topology that proves the join stays vertical in the heading and bends at the parent.

---

### Task 1: Defer parent-side transitions across date headings

**Files:**
- Modify: `test/app_test.dart:3360-3460`
- Modify: `lib/timeline.dart:65-125`
- Modify: `lib/timeline.dart:3120-3142`

**Interfaces:**
- Consumes: `GraphRow`, `LaneTransition`, `timelineEntries(List<GraphRow>, DateTime)`, and `CommitGraphPainter.transitionPath`
- Produces: `bool transitionBendsAtSource(GraphRow row, LaneTransition transition)` and date-heading `TimelineEntry` rows whose `activeLanes` represent the state before deferred joins and whose `nextLanes` represent the original final state

- [ ] **Step 1: Write the failing graph-state and geometry test**

Add this test beside the existing §17.1 date-heading tests in `test/app_test.dart`:

```dart
test('a parent-side join bends at its parent after a date heading', () {
  const size = Size(168, 36);
  final now = DateTime(2026, 7, 26, 12);
  int at(int day) =>
      DateTime(2026, 7, day, 12).millisecondsSinceEpoch ~/ 1000;
  final rows = layoutGraph([
    commit(
      'M',
      'merge',
      parents: const ['P', 'B'],
      timestamp: at(26),
    ),
    commit(
      'B',
      'branch tail',
      parents: const ['P'],
      timestamp: at(26),
    ),
    commit('P', 'parent', timestamp: at(25)),
  ]);
  final originalJoin = rows[1].transitions.single;
  expect(originalJoin, (from: 1, to: 0, sha: 'P'));

  final entries = timelineEntries(rows, now);
  final headingIndex = entries.indexWhere(
    (entry) => entry.label == 'Yesterday',
  );
  final above = entries[headingIndex - 1];
  final heading = entries[headingIndex];
  final parent = entries[headingIndex + 1];

  expect(above.row.commit.sha, 'B');
  expect(above.row.transitions, isEmpty);
  expect(above.row.nextLaneShas[1], 'P');
  expect(heading.row.transitions, [originalJoin]);
  expect(heading.row.activeLaneShas[1], 'P');
  expect(heading.row.nextLaneShas, rows[1].nextLaneShas);
  expect(parent.row.commit.sha, 'P');

  final headingPainter = CommitGraphPainter(
    row: heading.row,
    previous: above.row,
    selected: false,
    committerColor: AvatarService.branchColor(0),
  );
  final headingPath = headingPainter.transitionPath(
    originalJoin.from,
    originalJoin.to,
    size.height / 2,
    size,
  );
  expect(
    _samples(headingPath)
        .where((point) => point.dy <= size.height)
        .map((point) => point.dx),
    everyElement(58),
  );

  final parentPainter = CommitGraphPainter(
    row: parent.row,
    previous: heading.row,
    selected: false,
    committerColor: AvatarService.branchColor(0),
  );
  final arrivalPath = parentPainter.transitionPath(
    originalJoin.from,
    originalJoin.to,
    size.height / 2 - size.height,
    size,
  );
  expect(arrivalPath.getBounds(), const Rect.fromLTRB(28, -18, 58, 18));
  expect(_touches(arrivalPath, const Offset(28, 18)), isTrue);
  expect(
    arrivalPath
        .computeMetrics()
        .single
        .getTangentForOffset(
          arrivalPath.computeMetrics().single.length,
        )!
        .vector
        .dx,
    lessThan(-0.99),
  );
});
```

- [ ] **Step 2: Run the focused test and confirm the current behavior fails**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'a parent-side join bends at its parent after a date heading'
```

Expected: FAIL because `above.row.transitions` still contains `(from: 1, to: 0, sha: P)` and the synthetic heading has no transition.

- [ ] **Step 3: Extract the shared transition classification**

Add a top-level pure function above `timelineEntries` in `lib/timeline.dart`:

```dart
bool transitionBendsAtSource(
  GraphRow row,
  LaneTransition transition,
) =>
    transition.from == row.lane &&
    !(row.parentLanes.isNotEmpty &&
        transition.to == row.parentLanes.first);
```

Keep the public painter method for existing callers but delegate it to the shared function:

```dart
static bool isMergeEdge(GraphRow row, LaneTransition transition) =>
    transitionBendsAtSource(row, transition);
```

- [ ] **Step 4: Add display-only row copying and intermediate-state helpers**

Add these helpers below `TimelineEntry` in `lib/timeline.dart`:

```dart
GraphRow _copyGraphRow(
  GraphRow row, {
  List<int>? activeLanes,
  List<int>? nextLanes,
  Map<int, String>? activeLaneShas,
  Map<int, String>? nextLaneShas,
  List<LaneTransition>? transitions,
  Map<int, int>? activeLaneBranches,
  Map<int, int>? nextLaneBranches,
}) =>
    GraphRow(
      commit: row.commit,
      lane: row.lane,
      parentLanes: row.parentLanes,
      activeLanes: activeLanes ?? row.activeLanes,
      nextLanes: nextLanes ?? row.nextLanes,
      activeLaneShas: activeLaneShas ?? row.activeLaneShas,
      nextLaneShas: nextLaneShas ?? row.nextLaneShas,
      transitions: transitions ?? row.transitions,
      branch: row.branch,
      activeLaneBranches:
          activeLaneBranches ?? row.activeLaneBranches,
      nextLaneBranches: nextLaneBranches ?? row.nextLaneBranches,
    );

({GraphRow above, GraphRow heading}) _dateHeadingRows({
  required GraphRow above,
  required GitCommit below,
}) {
  final deferred = above.transitions
      .where((transition) => !transitionBendsAtSource(above, transition))
      .toList();
  if (deferred.isEmpty) {
    return (
      above: above,
      heading: passThroughRow(commit: below, above: above),
    );
  }

  final middleShas = Map<int, String>.of(above.nextLaneShas);
  final middleBranches = Map<int, int>.of(above.nextLaneBranches);
  for (final transition in deferred.reversed) {
    final previousSha = above.activeLaneShas[transition.to];
    final previousBranch = above.activeLaneBranches[transition.to];
    if (previousSha == null) {
      middleShas.remove(transition.to);
      middleBranches.remove(transition.to);
    } else {
      middleShas[transition.to] = previousSha;
      if (previousBranch == null) {
        middleBranches.remove(transition.to);
      } else {
        middleBranches[transition.to] = previousBranch;
      }
    }

    middleShas[transition.from] = transition.sha;
    final sourceBranch =
        above.activeLaneBranches[transition.from] ??
        (transition.from == above.lane ? above.branch : null);
    if (sourceBranch == null) {
      middleBranches.remove(transition.from);
    } else {
      middleBranches[transition.from] = sourceBranch;
    }
  }
  final middleLanes = middleShas.keys.toList()..sort();
  final kept = above.transitions
      .where((transition) => transitionBendsAtSource(above, transition))
      .toList();
  final visualAbove = _copyGraphRow(
    above,
    nextLanes: middleLanes,
    nextLaneShas: middleShas,
    nextLaneBranches: middleBranches,
    transitions: kept,
  );
  return (
    above: visualAbove,
    heading: GraphRow(
      commit: below,
      lane: -1,
      parentLanes: const [],
      activeLanes: middleLanes,
      nextLanes: above.nextLanes,
      activeLaneShas: middleShas,
      nextLaneShas: above.nextLaneShas,
      transitions: deferred,
      activeLaneBranches: middleBranches,
      nextLaneBranches: above.nextLaneBranches,
    ),
  );
}
```

- [ ] **Step 5: Use the intermediate rows when inserting a date heading**

Replace the date-boundary insertion inside `timelineEntries` with:

```dart
if (group != date) {
  group = date;
  var heading = passThroughRow(
    commit: row.commit,
    above: index == 0 ? null : rows[index - 1],
  );
  if (index > 0 && entries.isNotEmpty) {
    final previousEntry = entries.removeLast();
    final split = _dateHeadingRows(
      above: previousEntry.row,
      below: row.commit,
    );
    entries.add((
      rowIndex: previousEntry.rowIndex,
      label: previousEntry.label,
      row: split.above,
    ));
    heading = split.heading;
  }
  entries.add((rowIndex: -1, label: dateGroupLabel(date, now), row: heading));
}
```

This changes display entries only. Keep `_rows` and branch-color assignment untouched.

- [ ] **Step 6: Format and run the focused test**

Run:

```bash
dart format lib/timeline.dart test/app_test.dart
flutter test test/app_test.dart \
  --plain-name 'a parent-side join bends at its parent after a date heading'
```

Expected: PASS.

- [ ] **Step 7: Run the existing date-heading and transition tests**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'a date separator carries the rails and the sweep across itself'
flutter test test/app_test.dart \
  --plain-name 'a date heading carries a non-main lane through, not just lane 0'
flutter test test/app_test.dart \
  --plain-name 'a converging line holds its column, then slides in at its parent'
flutter test test/app_test.dart \
  --plain-name 'a newborn branch line leaves the source node center'
```

Expected: all four commands PASS.

- [ ] **Step 8: Run the full verification suite**

Run:

```bash
flutter test
flutter analyze
git diff --check
```

Expected: all tests pass, analysis reports no issues, and `git diff --check` prints nothing.

- [ ] **Step 9: Review the diff and commit only the fix**

Run:

```bash
git diff -- lib/timeline.dart test/app_test.dart
git status --short
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: bend joins after date headings"
```

Confirm that `pubspec.lock` remains unstaged and unchanged by this task.
