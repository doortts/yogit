# Sidebar And Toolbar Hover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved hover feedback to clickable timeline controls and let the preview use up to 75% of the app window.

**Architecture:** Reuse the current sidebar rows and toolbar controls. Keep hover state local to a small builder widget so only the hovered control rebuilds. Preserve the saved preferred width and apply the current window's 75% ceiling during layout and dragging.

**Tech Stack:** Dart, Flutter widgets, Flutter widget tests

## Global Constraints

- Add no dependency.
- Keep all control geometry and click targets unchanged.
- Use a rectangular sidebar hover fill with a straight 2-pixel leading line.
- Use `#3FB950` for the enabled `Show Diff` hover color.
- Keep the preview minimum at 240 and default at 288 logical pixels.
- Set the preview maximum to 75% of the current app-window width.
- Do not apply a fixed pixel maximum when reading a saved preview width.

---

### Task 1: Sidebar and toolbar hover feedback

**Files:**
- Modify: `lib/timeline.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Adds: `_HoverBuilder`
- Changes: `_ShowDiffButton` to a hover-aware button
- Produces: hover-only keys for focused widget assertions

- [x] **Step 1: Add failing mouse hover tests**

Move a mouse pointer onto `sidebar-ref-main`, an unselected placement button,
`toolbar-full-diff`, and `open-settings`. Assert the sidebar hover decoration is
rectangular with a two-pixel leading border, the placement background changes,
the diff background is `Color(0xFF3FB950)`, and the settings icon is rotated.

- [x] **Step 2: Run the focused tests and verify RED**

```bash
flutter test test/app_test.dart --plain-name "sidebar refs use the approved rectangular hover surface"
flutter test test/app_test.dart --plain-name "toolbar controls expose their approved hover feedback"
```

Expected: FAIL because the new hover decorations and colors do not exist.

- [x] **Step 3: Implement the smallest hover state**

Add one local hover builder and use it around clickable reference rows,
unselected placement buttons, `Show Diff`, and the settings button.

- [x] **Step 4: Run the focused tests and verify GREEN**

Run the commands from Step 2.

Expected: PASS.

---

### Task 2: Responsive preview width ceiling

**Files:**
- Modify: `lib/timeline.dart`
- Modify: `lib/settings.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Adds: `_previewWidthFraction = 0.75`
- Changes: preview layout and resizing to use the current app-window width
- Changes: `AppSettings.fromJson` to keep finite saved widths without a fixed maximum

- [x] **Step 1: Change the width assertions and verify RED**

At a 1,600-pixel window width, expect a large drag to stop at 1,200 pixels.
Resize the test window to 1,200 pixels and expect the visible preview to shrink
to 900 pixels. Expect a saved width of 1,400 pixels to remain 1,400 until the
runtime window limit is applied.

```bash
flutter test test/app_test.dart --plain-name "the preview panel resizes, persists, and clamps"
```

Expected: FAIL because the drag still stops at 840 and settings still clamp.

- [x] **Step 2: Change both width limits**

Replace the fixed runtime maximum with 75% of `MediaQuery.sizeOf(context).width`.
Apply the same limit while laying out and dragging the panel. Replace the saved
width clamp with finite-number validation and the existing 240-pixel minimum.

- [x] **Step 3: Run the focused test and verify GREEN**

Run the command from Step 1.

Expected: PASS.

---

### Task 3: Integrated verification

**Files:**
- Modify: `docs/superpowers/plans/2026-07-31-sidebar-toolbar-hover.md`

**Interfaces:**
- Consumes: Tasks 1 and 2
- Produces: a verified macOS debug build

- [x] **Step 1: Format and inspect**

```bash
dart format lib/timeline.dart lib/settings.dart test/app_test.dart
git diff --check
```

- [x] **Step 2: Run the complete checks**

```bash
flutter analyze
flutter test
flutter build macos --debug --no-pub
```

- [x] **Step 3: Restart the debug app**

Start the debug app against this worktree and leave it running for manual review.
