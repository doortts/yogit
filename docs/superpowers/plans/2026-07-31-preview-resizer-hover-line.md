# Preview Diff Resizer Hover Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a bright blue line only while the pointer hovers the left/right preview diff splitter.

**Architecture:** Extend the existing `TimelineScreen._previewDiffResizer` with one hover flag and a centered colored child. Keep the current drag handlers, persistence, and bottom splitter unchanged.

**Tech Stack:** Flutter, Dart, `flutter_test`

## Global Constraints

- Add no dependencies or new reusable components.
- Keep the neutral one-pixel divider at rest.
- Use a 12-pixel pointer target and a centered two-pixel `#5AB0FF` line on hover.
- Apply the accent only to left/right preview placements.

---

### Task 1: Hover-only splitter accent

**Files:**
- Modify: `test/app_test.dart`
- Modify: `lib/timeline.dart`

**Interfaces:**
- Consumes: `TimelineScreen._previewDiffResizer(PreviewPlacement)` and key `preview-diff-resizer`
- Produces: state field `_previewDiffResizerHovered` and key `preview-diff-hover-line`

- [ ] **Step 1: Write the failing widget test**

Open a right preview diff, create a mouse gesture, and assert that the keyed line changes from transparent to `Color(0xFF5AB0FF)` only while hovered.

```dart
final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
await mouse.addPointer(location: Offset.zero);
expect(_hoverLineColor(tester), Colors.transparent);
await mouse.moveTo(tester.getCenter(find.byKey(const Key('preview-diff-resizer'))));
await tester.pump();
expect(_hoverLineColor(tester), const Color(0xFF5AB0FF));
await mouse.moveTo(Offset.zero);
await tester.pump();
expect(_hoverLineColor(tester), Colors.transparent);
```

- [ ] **Step 2: Run the test and verify the red state**

Run: `flutter test test/app_test.dart --plain-name 'preview diff resizer shows blue line only on hover'`

Expected: FAIL because `preview-diff-hover-line` does not exist.

- [ ] **Step 3: Add the minimal hover state and line**

Add one boolean state field. Use `MouseRegion.onEnter` and `onExit` for left/right placements, then give the existing `GestureDetector` a centered two-pixel child.

```dart
onEnter: vertical ? null : (_) => setState(() => _previewDiffResizerHovered = true),
onExit: vertical ? null : (_) => setState(() => _previewDiffResizerHovered = false),
child: vertical
    ? const SizedBox.expand()
    : Center(
        child: ColoredBox(
          key: const Key('preview-diff-hover-line'),
          color: _previewDiffResizerHovered
              ? const Color(0xFF5AB0FF)
              : Colors.transparent,
          child: const SizedBox(width: 2, height: double.infinity),
        ),
      ),
```

Change only the left/right hit-target width from 8 to 12.

- [ ] **Step 4: Run focused and existing resize tests**

Run:

```text
flutter test test/app_test.dart --plain-name 'preview diff resizer shows blue line only on hover'
flutter test test/app_test.dart --plain-name 'adjacent diff size defaults, persists, and reaches both endpoints'
```

Expected: both tests pass.

- [ ] **Step 5: Format, analyze, and run the full suite**

Run:

```text
dart format lib/timeline.dart test/app_test.dart
flutter analyze
flutter test
```

Expected: no diagnostics and all tests pass.

- [ ] **Step 6: Commit and integrate**

Commit the implementation on `codex/preview-resizer-hover-line`, merge it into local `main`, and rerun the focused hover test from `main`.
