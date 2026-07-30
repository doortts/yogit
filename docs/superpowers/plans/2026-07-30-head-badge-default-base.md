# HEAD Badge and Initial Base Branch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the checked-out branch row fill with a `HEAD` badge and make a new timeline start from Git's checked-out branch.

**Architecture:** Reuse `RepoRefs.current`, the existing branch-name row, and the existing `_baseBranch` session state. The first ref load resolves from Git; later ref loads resolve from the session selection. No new persistence model or component is introduced.

**Tech Stack:** Dart, Flutter, `flutter_test`

## Global Constraints

- `HEAD` appears only beside `RepoRefs.current`.
- The checked-out branch row has no selected background.
- A new timeline starts from `RepoRefs.current`.
- A user-selected base branch survives later ref reloads.
- Do not add dependencies or settings.

---

### Task 1: Replace the checked-out row fill with a HEAD badge

**Files:**
- Modify: `lib/timeline.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `RepoRefs.current`, `_refTreeRow()`, and the row's existing `iconColor`.
- Produces: `Key('sidebar-head-<branch>')`.

- [ ] **Step 1: Write the failing widget test**

Replace the checked-out branch color-role case with a focused test:

```dart
final row = tester.widget<Container>(
  find.byKey(const Key('sidebar-row-main')),
);
expect((row.decoration! as BoxDecoration).color, isNull);
final badge = find.byKey(const Key('sidebar-head-main'));
expect(badge, findsOneWidget);
expect(find.descendant(of: badge, matching: find.text('HEAD')), findsOneWidget);
expect(find.byKey(const Key('sidebar-head-release')), findsNothing);
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name "checked-out branch uses a HEAD badge without a selected row fill"
```

Expected: failure because the row still uses `selectedRow` and no HEAD badge
exists.

- [ ] **Step 3: Implement the badge**

Remove `current ? _palette.selectedRow : null` from the row decoration. Insert
an outlined badge after the branch-name text:

```dart
if (current)
  Tooltip(
    message: '현재 체크아웃된 브랜치입니다',
    child: Container(
      key: Key('sidebar-head-$name'),
      child: const Text('HEAD'),
    ),
  ),
```

Use the existing branch `iconColor` for the badge outline and text.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the test from Step 2. Expected: PASS.

---

### Task 2: Start a new timeline from the checked-out branch

**Files:**
- Modify: `lib/timeline.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `_refsLoaded`, `_baseBranch`, `RepoRefs.current`, and the existing
  pending user-selection fields.
- Produces: first-load current-branch selection with session selection
  preservation.

- [ ] **Step 1: Write failing startup and reload tests**

Set stored `release` with checked-out `main`, then assert the selector and
stored value become `main`. Select `release`, trigger a ref reload through a
successful remote refresh, and assert `release` remains selected.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
flutter test test/app_test.dart --name "starts from the checked-out branch|keeps the session base branch across ref reloads"
```

Expected: the startup test restores `release`, or the reload test resets the
session selection.

- [ ] **Step 3: Implement first-load resolution**

In `_loadRefs()`:

```dart
final branch = resolveBaseBranch(
  refs,
  _refsLoaded ? _baseBranch : null,
);
```

When settings first become ready, keep `_baseBranch` unless a pending user
selection exists. Keep the existing later preference-update path.

- [ ] **Step 4: Run focused and full checks**

Run:

```bash
flutter test test/app_test.dart
flutter analyze --no-pub
flutter build macos --debug --no-pub
```

Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: mark HEAD and start timeline from checkout"
```
