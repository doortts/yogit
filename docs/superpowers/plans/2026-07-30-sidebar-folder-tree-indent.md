# Sidebar Folder Tree Indent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align each top-level folder chevron with its section icon and indent the folder's descendants by one additional tree level without moving top-level branches.

**Architecture:** Keep the existing recursive ref-tree layout and its 16-pixel depth step. Add one base offset only to folder-tree rows, leaving top-level leaf refs at their current position.

**Tech Stack:** Flutter, Dart widget tests

## Global Constraints

- Reuse `_refTreeRow`; do not add a new widget or dependency.
- Preserve the current position of top-level leaf branches.
- Verify geometry with real rendered widgets.

---

### Task 1: Align folder-tree rows

**Files:**
- Modify: `lib/timeline.dart:2568-2610`
- Test: `test/app_test.dart:2320-2385`

**Interfaces:**
- Consumes: `_refTreeRow(_RefSection section, RefTreeNode node, String path, int depth)`
- Produces: The existing sidebar rows with a conditional folder-tree base offset.

- [x] **Step 1: Write the failing test**

Add geometry assertions to the existing sidebar tree widget test:

```dart
final sectionIcon = tester.getRect(
  find.byKey(const Key('sidebar-section-icon-local')),
);
final folderChevron = tester.getRect(
  find.byKey(const Key('sidebar-folder-local-feature')),
);
expect(folderChevron.left, sectionIcon.left);

final folderName = tester.getRect(find.text('feature'));
final childName = tester.getRect(find.text('login'));
expect(childName.left - folderName.left, 16);
```

Also assert that the top-level `main` label remains 18 pixels left of the top-level folder label.

- [x] **Step 2: Run the test to verify it fails**

Run:

```bash
flutter test test/app_test.dart --plain-name "sidebar lists refs as collapsible trees, filters them, and moves the selection"
```

Expected: failure because the folder chevron still starts at the same 4-pixel inset as a top-level branch.

- [x] **Step 3: Write the minimal implementation**

In `_refTreeRow`, add 18 pixels only for folder nodes and their descendants:

```dart
final inFolderTree = name == null || depth > 0;
padding: EdgeInsets.only(
  left: 4 + (inFolderTree ? 18 : 0) + depth * 16.0,
  right: 4,
),
```

- [x] **Step 4: Run verification**

Run:

```bash
flutter test test/app_test.dart --plain-name "sidebar lists refs as collapsible trees, filters them, and moves the selection"
flutter analyze
```

Expected: both commands exit successfully without warnings.

- [x] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-07-30-sidebar-folder-tree-indent.md lib/timeline.dart test/app_test.dart
git commit -m "style: indent sidebar folder trees"
```
