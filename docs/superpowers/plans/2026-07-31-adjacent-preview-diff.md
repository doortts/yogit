# Adjacent Preview Diff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open a separately resizable diff beside the commit preview only after the user selects a changed file.

**Architecture:** Keep the existing preview widget and diff renderer, but make them sibling panes in `TimelineScreen._workspaceLayout`. Store one optional diff extent for each preview placement in `AppSettings`; a null value means the first file click should leave 100 logical pixels for the timeline. Reuse the existing preview file cache, diff cache, layout switch, and scroll helpers.

**Tech Stack:** Flutter, Dart, `flutter_test`, existing Yogit settings JSON store

## Global Constraints

- Add no dependencies.
- The preview pane size must not change while the adjacent diff pane is resized.
- Clicking outside the diff pane must not close it.
- Escape closes the diff pane before it closes the preview pane.
- User-resized extents persist separately for left, right, and bottom placements.

---

### Task 1: Adjacent pane behavior

**Files:**
- Modify: `test/app_test.dart`
- Modify: `lib/timeline.dart`

**Interfaces:**
- Consumes: existing `_previewFilesFor`, `_previewDiff`, `_previewFileList`, and `DiffLayout`
- Produces: `_previewDiffOpen`, `_adjacentPreviewDiff`, and the `preview-diff-close` control

- [ ] **Step 1: Write the failing widget test**

Add a test that opens the preview, verifies no `preview-diff` exists, taps a changed file, and then verifies that the diff appears between the timeline and a right-side preview while the preview width stays unchanged.

```dart
await tester.sendKeyEvent(LogicalKeyboardKey.enter);
await tester.pumpAndSettle();
expect(find.byKey(const Key('preview-diff')), findsNothing);
final previewWidth = tester.getSize(find.byKey(const Key('preview-panel'))).width;
await tester.tap(find.byKey(const Key('preview-state-lib/a.dart')));
await tester.pumpAndSettle();
expect(find.byKey(const Key('preview-diff')), findsOneWidget);
expect(tester.getSize(find.byKey(const Key('preview-panel'))).width, previewWidth);
expect(
  tester.getRect(find.byKey(const Key('preview-diff'))).right,
  tester.getRect(find.byKey(const Key('preview-panel'))).left,
);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/app_test.dart --plain-name 'a file click opens an adjacent diff without resizing the preview'`

Expected: FAIL because the current preview eagerly renders the first file diff inside the preview.

- [ ] **Step 3: Implement the minimal sibling layout**

In `TimelineScreen`, retain the existing preview file and diff loaders, stop defaulting the preview file to the first entry, set `_previewDiffOpen` on file selection, and place `_previewDiff(commit, file)` in a sibling pane selected by the current preview placement.

```dart
var _previewDiffOpen = false;

void _selectPreviewFile(GitCommit commit, String path) {
  setState(() {
    _previewPaths[_previewKey(commit)] = path;
    _previewDiffOpen = true;
  });
  _focusNode.requestFocus();
}
```

- [ ] **Step 4: Run the focused test**

Run: `flutter test test/app_test.dart --plain-name 'a file click opens an adjacent diff without resizing the preview'`

Expected: PASS.

### Task 2: Splitter range and persisted sizes

**Files:**
- Modify: `test/app_test.dart`
- Modify: `lib/settings.dart`
- Modify: `lib/main.dart`
- Modify: `lib/timeline.dart`

**Interfaces:**
- Consumes: `PreviewPlacement`, `AppSettings.copyWith`, and `TimelineScreen.onPreviewSizeChanged`
- Produces: `previewDiffLeftWidth`, `previewDiffRightWidth`, `previewDiffBottomHeight`, and `onPreviewDiffSizeChanged`

- [ ] **Step 1: Write failing settings and widget tests**

Add literal round-trip assertions for all three optional extents. Add a widget test that checks an unsaved right-side diff leaves 100 pixels of timeline, drags the splitter to both endpoints, and records the final extent without changing the preview width.

```dart
const settings = AppSettings(
  previewDiffLeftWidth: 240,
  previewDiffRightWidth: 360,
  previewDiffBottomHeight: 420,
);
expect(AppSettings.fromJson(settings.toJson()), settings);
expect(tester.getSize(find.byKey(const Key('timeline-viewport'))).width, 100);
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `flutter test test/app_test.dart --plain-name 'adjacent diff size defaults, persists, and reaches both endpoints'`

Expected: FAIL because no adjacent diff size settings or splitter exist.

- [ ] **Step 3: Implement optional per-placement settings and splitter**

Add nullable settings fields, JSON parsing/serialization, equality, app plumbing, and one placement-aware splitter. Clamp a saved extent to the available workspace. When the saved extent is null, use `max(0, available - 100)` without saving it.

```dart
final double? previewDiffLeftWidth;
final double? previewDiffRightWidth;
final double? previewDiffBottomHeight;

final extent = (savedExtent ?? math.max(0, available - 100)).clamp(
  0,
  available,
);
```

- [ ] **Step 4: Run the focused tests**

Run: `flutter test test/app_test.dart --plain-name 'adjacent diff size defaults, persists, and reaches both endpoints'`

Expected: PASS.

### Task 3: Closing hierarchy and navigation regression

**Files:**
- Modify: `test/app_test.dart`
- Modify: `lib/timeline.dart`

**Interfaces:**
- Consumes: `_onKeyEvent`, `_stepPreviewFile`, and the existing preview controller
- Produces: `_closePreviewDiff` and hierarchical Escape handling

- [ ] **Step 1: Write failing interaction tests**

Add tests proving that an outside timeline click leaves the diff open, the first Escape closes only the diff, the second Escape closes the preview, the close button closes only the diff, and Command+Up/Down opens or switches the adjacent diff without moving the commit selection.

```dart
await tester.sendKeyEvent(LogicalKeyboardKey.escape);
await tester.pumpAndSettle();
expect(find.byKey(const Key('preview-diff')), findsNothing);
expect(find.byKey(const Key('preview-panel')), findsOneWidget);
await tester.sendKeyEvent(LogicalKeyboardKey.escape);
await tester.pumpAndSettle();
expect(find.byKey(const Key('preview-panel')), findsNothing);
```

- [ ] **Step 2: Run the interaction tests to verify they fail**

Run: `flutter test test/app_test.dart --plain-name 'escape closes the adjacent diff before the preview'`

Expected: FAIL because Escape currently closes the preview immediately.

- [ ] **Step 3: Implement the minimal close hierarchy**

Handle an open diff before calling `WindowFrameController.setPreview(closed)`, add the toolbar close button, retain file selections in `_previewPaths`, and keep the root timeline focus after file or toolbar clicks.

```dart
if (event.logicalKey == LogicalKeyboardKey.escape) {
  if (_previewDiffOpen) {
    _closePreviewDiff();
  } else {
    unawaited(_previewController.setPreview(PreviewPlacement.closed));
  }
  return KeyEventResult.handled;
}
```

- [ ] **Step 4: Run preview tests and update obsolete embedded-layout assertions**

Run: `flutter test test/app_test.dart`

Expected: PASS after assertions that depended on the old embedded diff and shared scrolling are rewritten for the approved sibling layout.

### Task 4: Verification and integration

**Files:**
- Modify: only files required by failures found during verification

**Interfaces:**
- Consumes: completed Tasks 1-3
- Produces: verified feature branch ready for local integration

- [ ] **Step 1: Format and analyze**

Run: `dart format lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart && flutter analyze`

Expected: no diagnostics.

- [ ] **Step 2: Run the complete test suite**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 3: Review the diff against the design**

Check every requirement in `docs/superpowers/specs/2026-07-31-adjacent-preview-diff-design.md`, confirm no unrelated files changed, and verify no new dependency was added.

- [ ] **Step 4: Commit and merge locally**

Commit the verified implementation on `codex/adjacent-preview-diff`, merge it into local `main`, and rerun the focused preview tests from `main`.
