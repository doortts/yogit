# Timeline Pane Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match the approved timeline mockup by adding a collapsible left pane, widening the preview range, removing its duplicate SHA, and joining Branch / Tag chips to commit markers with open arrows.

**Architecture:** Keep `TimelineScreen` as the single owner of pane state and reuse its existing sidebar, preview resizer, and graph painter. Add one compact sidebar body and one small custom-painted pane icon; extend the existing ref connector rather than introducing another graph layer.

**Tech Stack:** Dart, Flutter widgets, Flutter custom painters, Flutter widget and paint tests

## Global Constraints

- Add no dependency.
- Preserve the expanded sidebar width and restore it after reopening.
- Keep the pane icons exactly `18 × 18` logical pixels.
- Show pane action tooltips with `Duration.zero`.
- Keep ordinary timeline rails, preview rails, diff rendering, and the bottom status bar unchanged.
- Keep ref connector shafts and open arrowheads at `1.0` logical pixel.
- Increase the preview maximum width from `560` to `840` logical pixels.

---

### Task 1: Collapsible left pane and approved icons

**Files:**
- Modify: `lib/timeline.dart:780-825`
- Modify: `lib/timeline.dart:2587-2665`
- Modify: `lib/timeline.dart` after `_TimelineScreenState`
- Test: `test/app_test.dart:10170-10265`

**Interfaces:**
- Adds: `_sidebarCollapsed`
- Adds: `_sidebarToggleButton({required bool collapsed})`
- Adds: `_collapsedSidebarBody()`
- Adds: `_PaneToggleIcon` and `_PaneToggleIconPainter`
- Produces: `sidebar-collapse-button`, `sidebar-expand-button`, and compact section keys

- [x] **Step 1: Add a failing sidebar behavior test**

Add a widget test that pumps local, remote, and tag refs and verifies:

```dart
expect(tester.getSize(find.byKey(const Key('sidebar'))).width, 150);
expect(find.byKey(const Key('sidebar-collapse-button')), findsOneWidget);
expect(
  tester.getSize(find.byKey(const Key('sidebar-collapse-icon'))),
  const Size(18, 18),
);
expect(
  tester
      .widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const Key('sidebar-collapse-button')),
          matching: find.byType(Tooltip),
        ),
      )
      .waitDuration,
  Duration.zero,
);
```

Tap `sidebar-collapse-button`, then verify the sidebar is 52 pixels wide, the filter is absent, compact local/remote/tag groups are visible with counts, the 18 × 18 expand icon is present, and its tooltip also has zero delay. Tap `sidebar-expand-button` and verify the 150-pixel sidebar and filter return.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name "the sidebar collapses to group icons and restores its width"
```

Expected: FAIL because the pane action buttons and compact sidebar do not exist.

- [x] **Step 3: Implement the smallest sidebar state change**

Store `_sidebarCollapsed` in `_TimelineScreenState`. Build `_sidebarBody()` at `_sidebarWidth` when open and `_collapsedSidebarBody()` at 52 pixels when closed. Omit the drag handle while closed, preserving `_sidebarWidth` for reopening.

Place the close button to the right of the filter. Put the open button above the compact local, remote, and tag groups.

- [x] **Step 4: Paint the approved icon and tooltips**

Use `CustomPaint(size: Size(18, 18))` with a rounded outline and one vertical divider. Draw the close divider at 25% of the width and the open divider at 36% of the width. Wrap both buttons in `Tooltip` with `waitDuration: Duration.zero`.

- [x] **Step 5: Run the focused test and verify GREEN**

Run the command from Step 2.

Expected: PASS.

---

### Task 2: Preview header and width range

**Files:**
- Modify: `lib/timeline.dart:690-705`
- Modify: `lib/timeline.dart:5635-5700`
- Modify: `lib/settings.dart:420-432`
- Test: `test/app_test.dart:10710-10795`
- Test: `test/app_test.dart:11485-11555`
- Test: `test/app_test.dart:12935-12955`

**Interfaces:**
- Changes: `_previewWidthRange.max` from `560` to `840`
- Changes: `AppSettings.fromJson` preview-width maximum from `560` to `840`
- Removes: the redundant `preview-hash` label from the preview header

- [x] **Step 1: Add failing preview assertions**

Change the preview resizing test to drag far enough to the new limit and expect:

```dart
expect(previewWidth(), 840);
```

Add to the preview-header test:

```dart
expect(find.byKey(const Key('preview-hash')), findsNothing);
```

Change the typography test to assert the shortcut still uses the technical font while `preview-hash` is absent.

- [x] **Step 2: Run both focused tests and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name "the preview panel resizes, persists, and clamps"
flutter test test/app_test.dart --plain-name "the preview header carries the compact green Show Diff"
```

Expected: the width test stops at 560 and the header test finds `preview-hash`.

- [x] **Step 3: Implement the range and remove the duplicate label**

Set both runtime and persisted width maxima to `840`. Remove only the SHA widget and its adjacent spacing from the normal preview header; keep `Show Diff` unchanged.

- [x] **Step 4: Run the focused tests and verify GREEN**

Run the commands from Step 2 and the typography test that contains the shortcut assertion.

Expected: PASS.

---

### Task 3: Continuous ref connector with an open arrow

**Files:**
- Modify: `lib/timeline.dart:4730-4765`
- Modify: `lib/timeline.dart:5170-5225`
- Modify: `lib/timeline.dart:7850-8260`
- Test: `test/app_test.dart:865-910`
- Test: `test/app_test.dart:3600-3710`

**Interfaces:**
- Adds: a one-pixel chip-to-graph connector keyed by `ref-chip-connector-<sha>`
- Adds: marker-aware `CommitGraphPainter.refArrowTipX`
- Adds: `CommitGraphPainter.refArrowheadPath(double centerY)`
- Changes: comparison rows with refs also request a ref connector

- [x] **Step 1: Add failing painter and widget tests**

Replace the straight-line painter assertion with one that expects a shaft ending four pixels before the visible marker and an open stroked chevron. Cover ordinary avatars, merge dots, working-tree rings, compact rows, rows without refs, and pass-through rows.

Extend the branch comparison preview test to assert that a ref chip has `ref-chip-connector-<sha>` and its row paints the connector in comparison mode.

- [x] **Step 2: Run focused tests and verify RED**

Run:

```bash
flutter test test/app_test.dart --plain-name "ref connector points at an ordinary commit with a one-pixel chevron"
flutter test test/app_test.dart --plain-name "rebase preview adds rewritten commits to the timeline"
```

Expected: the painter has no arrowhead and comparison rows do not expose continuous ref connectors.

- [x] **Step 3: Implement the connector once**

Draw the missing 14-pixel tail from the right edge of the last Branch / Tag chip to the graph boundary. Pass `refConnector: refs.isNotEmpty` in normal and comparison rows.

In `CommitGraphPainter`, reuse one stroked paint for the shaft and open chevron. Choose marker radii of 11 pixels for avatars, `nodeRadius` for merge dots, and `wipNodeRadius` for working-tree rings.

- [x] **Step 4: Run focused tests and verify GREEN**

Run the commands from Step 2 plus:

```bash
flutter test test/app_test.dart --plain-name "ref arrow keeps its gap for merge, working-tree, and compact rows"
```

Expected: PASS.

---

### Task 4: Verify the integrated screen

**Files:**
- Modify: `docs/superpowers/plans/2026-07-31-timeline-pane-controls.md`

**Interfaces:**
- Consumes: Tasks 1–3
- Produces: a formatted, analyzed, tested feature branch

- [x] **Step 1: Format and inspect**

Run:

```bash
dart format lib/timeline.dart lib/settings.dart test/app_test.dart
git diff --check
```

- [x] **Step 2: Run full verification**

Run:

```bash
flutter analyze
flutter test
```

Expected: no analysis issues and zero test failures.

- [x] **Step 3: Compare with the approved mockup**

Run the debug app and compare the expanded sidebar, collapsed rail, 18 × 18 icons, instant tooltips, preview header, maximum preview width, and ref connector geometry with `timeline-preview-pane-icons-v37.html`.
