# Preview Surface Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the branch comparison status bar, apply the same Branch / Tag chip margins everywhere, and render normal and branch previews with one file-list and diff-view path.

**Architecture:** Reuse the existing comparison status bar and branch-preview diff presentation. Remove mode-specific layout branches from the timeline preview instead of adding another widget hierarchy, and give the shared full-diff presentation one layout state and one scroll controller.

**Tech Stack:** Dart, Flutter, Flutter widget tests

## Global Constraints

- Add no dependency.
- Preserve commit metadata and branch conflict/action cards.
- Keep the normal timeline graph and preview placement behavior unchanged.
- Use one file-row style and one Unified / Side-by-side diff renderer for both preview modes.

---

### Task 1: Keep status bar and Branch / Tag margins consistent

**Files:**
- Modify: `lib/timeline.dart:1500-1540`
- Modify: `lib/timeline.dart:5169-5220`
- Test: `test/app_test.dart:2836-2915`
- Test: `test/app_test.dart:6610-6660`

**Interfaces:**
- Consumes: `_statusBar()`, which already selects normal or comparison content
- Produces: a visible `comparison-status` bar and 14-pixel chip margins in both modes

- [ ] **Step 1: Add failing behavior assertions**

After selecting a comparison branch:

```dart
expect(find.byKey(const Key('comparison-status')), findsOneWidget);
```

For a normal multi-ref row:

```dart
expect(chip.left - cell.left, 14);
expect(
  cell.right -
      tester.getRect(find.byKey(const Key('ref-chip-multi-main'))).right,
  14,
);
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
flutter test test/app_test.dart --plain-name "branch comparison keeps only two branch lanes"
flutter test test/app_test.dart --plain-name "a multi-ref row shares its cell between chips, no avatars"
```

Expected: the comparison status bar is absent and the normal chip margins differ from 14 pixels.

- [ ] **Step 3: Remove the two mode-specific layout conditions**

Always build the existing status bar:

```dart
_statusBar(),
```

Use one chip inset and width:

```dart
const inset = 14.0;
final width = constraints.maxWidth - inset * 2;
...
width: slot,
```

- [ ] **Step 4: Run both tests and verify they pass**

Run the two commands from Step 2.

Expected: PASS.

### Task 2: Reuse one preview file-list and diff renderer

**Files:**
- Modify: `lib/timeline.dart:6000-6220`
- Modify: `lib/timeline.dart:6820-7325`
- Test: `test/app_test.dart:683-735`

**Interfaces:**
- Consumes: the existing diff future, `DiffDocument`, `UnifiedPresentationView`, and `SideBySidePresentationView`
- Produces: one `_previewDiffView` path with the same toolbar, layout switch, titles, compact rows, file-row spacing, and scrolling in both modes

- [ ] **Step 1: Add a failing normal-preview parity test**

Extend the normal preview fixture with one modified file and a hunk, then assert:

```dart
expect(
  find.byKey(const Key('branch-preview-diff-toolbar')),
  findsOneWidget,
);
expect(
  find.byKey(const Key('branch-preview-layout-switch')),
  findsOneWidget,
);
expect(find.byType(UnifiedPresentationView), findsOneWidget);
expect(find.text('+1 -1'), findsOneWidget);

final state = tester.widget<Container>(
  find.byKey(const Key('preview-state-lib/first.dart')),
);
expect(state.decoration, isNull);

await tester.tap(
  find.byKey(const Key('branch-preview-layout-side-by-side')),
);
await tester.pump();
expect(find.byType(SideBySidePresentationView), findsOneWidget);
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
flutter test test/app_test.dart --plain-name "preview loads real files before the first file diff once"
```

Expected: the normal preview still uses the legacy line renderer and has no shared layout controls.

- [ ] **Step 3: Share layout state and file-row presentation**

Rename `_branchPreviewLayout` to `_previewDiffLayout`. Remove `_comparison`-based row height, status-chip, border, text-color, and stats branches from `_previewFileRow`; keep the current branch-preview values for both modes.

- [ ] **Step 4: Build one diff presentation**

Make `_previewDiff` compute mode-specific labels and ranges, then pass both modes into one `_previewDiffView` method. The method owns:

```dart
Column(
  children: [
    preview diff toolbar,
    Expanded(
      child: FutureBuilder<List<DiffLine>>(
        builder: UnifiedPresentationView or SideBySidePresentationView,
      ),
    ),
    optional branch conflict choices,
  ],
)
```

Pass `_previewDiffScrollController` to both presentation views. Keep branch conflict titles and actions conditional, but do not keep a second diff renderer.

- [ ] **Step 5: Remove the normal-only diff padding and outer scroll view**

Use `EdgeInsets.zero` for both modes. Keep `preview-diff-scroll` as the shared pointer/scroll notification boundary while the presentation view owns the actual list.

- [ ] **Step 6: Run focused preview tests**

Run:

```bash
flutter test test/app_test.dart --plain-name "preview loads real files before the first file diff once"
flutter test test/app_test.dart --plain-name "the preview diff starts at the hunk, not the git header"
flutter test test/app_test.dart --plain-name "preview file and diff panes scroll independently"
flutter test test/app_test.dart --plain-name "branch preview diff switches between both full diff layouts"
flutter test test/app_test.dart --plain-name "branch preview diff names both sides of a merge conflict"
```

Expected: PASS.

### Task 3: Verify and commit

**Files:**
- Modify: `docs/superpowers/plans/2026-07-31-preview-surface-unification.md`

**Interfaces:**
- Consumes: the completed implementation
- Produces: a formatted, analyzed, fully tested branch commit

- [ ] **Step 1: Format and inspect**

Run:

```bash
dart format lib/timeline.dart test/app_test.dart
git diff --check
```

- [ ] **Step 2: Run full verification**

Run:

```bash
flutter analyze
flutter test
```

Expected: no analysis issues and all tests pass.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-07-31-preview-surface-unification.md lib/timeline.dart test/app_test.dart
git commit -m "refactor: unify timeline preview diff surfaces"
```
