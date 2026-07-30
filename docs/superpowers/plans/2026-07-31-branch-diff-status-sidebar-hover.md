# Branch Diff Status Bar and Sidebar Hover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the redundant Merge preview badge, reuse the normal timeline status bar in Branch Diff, and make sidebar hover feedback geometry-stable.

**Architecture:** Keep all behavior in the existing `TimelineScreen` code path. Reuse `_normalStatusBar()` for every timeline mode and render sidebar hover decoration behind the unchanged branch content.

**Tech Stack:** Flutter, Dart, `flutter_test`

## Global Constraints

- Do not add dependencies or new production files.
- Keep the existing Branch Diff summary height and remaining badges unchanged.
- Extend only the visual hover background 5 pixels left; do not move content or enlarge the hit target.

---

### Task 1: Branch Diff summary and status bar

**Files:**
- Modify: `lib/timeline.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `TimelineScreen._normalStatusBar()`
- Produces: one shared status bar presentation for normal and comparison modes

- [ ] **Step 1: Write the failing widget test**

Update the Branch Diff widget test to assert:

```dart
expect(find.text('두 부모'), findsNothing);
expect(find.byKey(const Key('status-timestamp')), findsOneWidget);
expect(find.text('commit'), findsOneWidget);
expect(find.byKey(const Key('comparison-status')), findsNothing);
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
flutter test test/app_test.dart --plain-name 'branch comparison keeps only two branch lanes'
```

Expected: failure because `두 부모` is still visible and the normal status bar
is hidden in Branch Diff.

- [ ] **Step 3: Implement the minimal change**

In `lib/timeline.dart`:

```dart
// Build the status bar unconditionally.
_statusBar(),

Widget _statusBar() => _normalStatusBar();
```

Remove both `detail('두 부모')` entries and delete the now-unused
`_comparisonStatusBar()`.

- [ ] **Step 4: Run the focused test**

Run the command from Step 2. Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: align branch diff summary and status"
```

### Task 2: Stable sidebar hover geometry

**Files:**
- Modify: `lib/timeline.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: existing `_HoverBuilder`
- Produces: `Key('sidebar-ref-hover-background-$name')` for the decoration layer

- [ ] **Step 1: Write the failing widget test**

Add a test that records the branch icon and text rectangles, hovers the branch,
and verifies:

```dart
expect(iconAfter, iconBefore);
expect(textAfter, textBefore);
expect(hoverBackground.left, rowContent.left - 5);
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
flutter test test/app_test.dart --plain-name 'sidebar hover extends left without moving branch content'
```

Expected: failure because the current border changes content geometry and there
is no separate 5-pixel background layer.

- [ ] **Step 3: Implement the minimal change**

Replace the decorated content container with a clipped-open stack:

```dart
Stack(
  clipBehavior: Clip.none,
  children: [
    Positioned(
      key: Key('sidebar-ref-hover-background-$name'),
      left: -5,
      top: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(decoration: hoverDecoration),
    ),
    branchContent,
  ],
)
```

The background owns the fill and left edge. The foreground row keeps identical
padding in both states.

- [ ] **Step 4: Run focused and neighboring tests**

Run:

```bash
flutter test test/app_test.dart --plain-name 'sidebar hover extends left without moving branch content'
flutter test test/app_test.dart --plain-name 'sidebar lists refs as collapsible trees, filters them, and moves the selection'
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: stabilize sidebar branch hover"
```

### Task 3: Final verification and integration

**Files:**
- Verify all modified files

**Interfaces:**
- Consumes: Tasks 1 and 2
- Produces: a verified local `main` merge

- [ ] **Step 1: Run formatting and static analysis**

```bash
dart format lib/timeline.dart test/app_test.dart
flutter analyze
```

Expected: no issues.

- [ ] **Step 2: Run the complete test suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 3: Merge into local main**

Merge the verified feature branch into local `main` with a non-fast-forward
merge, verify the merge result again, then remove only this task's temporary
worktree and feature branch.
