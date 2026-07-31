# Preview Scroll Priority Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Shift+Command+Up/Down` scroll an open adjacent diff before the preview, and select only a pane that can move in the requested direction.

**Architecture:** Keep the shared `PageScrollIntent` and `applyPageScroll` unchanged. Replace the direction-dependent ordering inside `TimelineScreen._previewPageScrollController` with one directional capability check, then use diff-first and preview-second priority.

**Tech Stack:** Flutter, Dart, `flutter_test`

## Global Constraints

- Add no dependency or reusable component.
- Preserve the half-viewport scroll distance and current shortcut label.
- Preserve `Command+Up/Down` file navigation.
- Never fall through to timeline navigation when neither pane can scroll.

---

### Task 1: Direction-aware preview scroll target

**Files:**
- Modify: `test/app_test.dart`
- Modify: `lib/timeline.dart`

**Interfaces:**
- Consumes: `_previewFilesScrollController`, `_previewDiffScrollController`, `_previewDiffOpen`, and `applyPageScroll`
- Produces: corrected `_previewPageScrollController(int direction)` selection

- [ ] **Step 1: Write the failing widget test**

Open a preview with enough files and diff lines for both panes to scroll. Send `Shift+Command+Down` and verify only the diff moves. Move the diff to its lower boundary, send the shortcut again, and verify the preview moves instead. At both lower boundaries, verify neither offset nor commit selection changes.

```dart
expect(previewPosition.pixels, 0);
expect(diffPosition.pixels, 0);
await pageDown();
expect(diffPosition.pixels, greaterThan(0));
expect(previewPosition.pixels, 0);

diffPosition.jumpTo(diffPosition.maxScrollExtent);
await pageDown();
expect(previewPosition.pixels, greaterThan(0));
```

- [ ] **Step 2: Run the test and verify the red state**

Run: `flutter test test/app_test.dart --plain-name 'preview page shortcut prioritizes a scrollable adjacent diff'`

Expected: FAIL because the current downward path scrolls the preview before the open diff.

- [ ] **Step 3: Implement the minimal selection rule**

Inside `_previewPageScrollController`, use a local predicate that checks `extentAfter` for down and `extentBefore` for up. Return the diff first when it is open and movable, then the preview when movable, otherwise return null.

```dart
bool canScroll(ScrollController controller) {
  if (!controller.hasClients) return false;
  final position = controller.position;
  return direction > 0 ? position.extentAfter > 0 : position.extentBefore > 0;
}

if (_previewDiffOpen && canScroll(_previewDiffScrollController)) {
  return _previewDiffScrollController;
}
if (canScroll(_previewFilesScrollController)) {
  return _previewFilesScrollController;
}
return null;
```

- [ ] **Step 4: Run focused tests**

Run:

```text
flutter test test/app_test.dart --plain-name 'preview page shortcut prioritizes a scrollable adjacent diff'
flutter test test/app_test.dart --plain-name 'preview shortcuts scroll and distinguish identities'
flutter test test/app_test.dart --plain-name 'preview file list and diff scroll independently'
```

Expected: all three tests pass.

- [ ] **Step 5: Format and verify the project**

Run:

```text
dart format lib/timeline.dart test/app_test.dart
flutter analyze
flutter test
```

Expected: no diagnostics and all tests pass.

- [ ] **Step 6: Commit and integrate**

Commit on `codex/preview-scroll-priority`, merge into local `main`, and rerun the focused priority test from `main`.
