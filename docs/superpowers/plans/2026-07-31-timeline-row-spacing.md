# Timeline Row Spacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce every timeline commit and date row from `32px` to `30px`, removing `1px` above and below each row's centered content.

**Architecture:** Keep the existing single fixed-height timeline model. Change `TimelineScreen.rowHeight`; the list extent, graph geometry, selection bounds, and scrolling already derive from that value.

**Tech Stack:** Flutter, Dart, `flutter_test`

## Global Constraints

- Timeline commit and date rows use one fixed height of `30px`.
- Do not add separate padding or variable-height row calculations.
- Keep graph nodes, rails, selection bands, keyboard movement, and scrolling derived from `TimelineScreen.rowHeight`.
- Add no dependencies or new abstractions.

---

### Task 1: Reduce the common timeline row height

**Files:**
- Modify: `test/app_test.dart:331`
- Modify: `lib/timeline.dart:628`

**Interfaces:**
- Consumes: `TimelineScreen.rowHeight`, the existing public `double` constant used by timeline layout and tests.
- Produces: `TimelineScreen.rowHeight == 30.0`; all existing consumers inherit the new height.

- [ ] **Step 1: Write the failing test**

Change the existing timeline list assertion in `test/app_test.dart`:

```dart
expect(TimelineScreen.rowHeight, 30);
expect(list.itemExtent, TimelineScreen.rowHeight);
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'keyboard and pointer control selection and preview'
```

Expected: FAIL because `TimelineScreen.rowHeight` is still `32.0`.

- [ ] **Step 3: Apply the minimal implementation**

Change the shared constant in `lib/timeline.dart`:

```dart
/// Every row is this tall — commits and date headings alike.
static const rowHeight = 30.0;
```

- [ ] **Step 4: Run focused layout tests**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'keyboard and pointer control selection and preview'
flutter test test/app_test.dart \
  --plain-name 'date rows head their group, boxed at the hash column'
flutter test test/app_test.dart \
  --plain-name 'the date heading row paints its rails at full row size'
```

Expected: all three tests PASS.

- [ ] **Step 5: Run project verification**

Run:

```bash
rg --files test -g '*_test.dart' \
  | rg -v '^test/full_diff_visual_test\.dart$' \
  | xargs flutter test
flutter analyze
/Users/doortts/repos/flutter/bin/cache/dart-sdk/bin/dart \
  format --output=none --set-exit-if-changed lib test
git diff --check
```

Expected: tests and analysis pass, formatting changes no files, and `git diff --check` prints nothing. The known `full_diff_visual_test.dart` golden baseline remains outside this unrelated timeline-spacing change.

- [ ] **Step 6: Commit**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: tighten timeline row spacing"
```
