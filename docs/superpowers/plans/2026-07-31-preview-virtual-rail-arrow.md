# Preview Virtual Rail and Arrow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved 14-pixel Branch / Tag inset, uninterrupted dashed virtual rails, and open Rebase mapping arrowheads.

**Architecture:** Keep the existing preview graph data and painters. Correct the compact painter so the upper and lower halves use their own dashed state, change only the mapping arrowhead path, and adjust the existing preview-only chip inset.

**Tech Stack:** Dart, Flutter custom painters, Flutter widget and pixel tests

## Global Constraints

- Add no dependency or new abstraction.
- Do not change ordinary timeline rail geometry.
- Keep virtual rails 1 pixel wide and dashed for their full length.
- Keep mapping lines 1 pixel wide and solid.

---

### Task 1: Preview Branch / Tag inset

**Files:**
- Modify: `lib/timeline.dart:5169-5215`
- Test: `test/app_test.dart:3607-3630`

**Interfaces:**
- Consumes: `_comparison`, which is non-null in Merge and Rebase previews
- Produces: a 14-pixel horizontal inset inside `refs-cell-*`

- [x] **Step 1: Change the widget expectation to 14 pixels**

```dart
expect(
  tester.getTopLeft(virtualChip).dx - tester.getTopLeft(virtualCell).dx,
  14,
);
```

- [x] **Step 2: Run the test and verify it fails**

Run: `flutter test test/app_test.dart --plain-name "rebase preview adds rewritten commits to the timeline"`

Expected: FAIL because the current preview inset is 16 pixels.

- [x] **Step 3: Change the preview-only inset**

```dart
final inset = _comparison == null ? 0.0 : 14.0;
```

- [x] **Step 4: Run the test and verify it passes**

Run: `flutter test test/app_test.dart --plain-name "rebase preview adds rewritten commits to the timeline"`

Expected: PASS.

### Task 2: Uninterrupted compact virtual rail

**Files:**
- Modify: `lib/timeline.dart:8125-8155`
- Test: `test/app_test.dart:860-900`

**Interfaces:**
- Consumes: `dashedLanes` for the lower half and `previousDashedLanes` for the upper half
- Produces: compact graph rows whose virtual upper segment stays dashed while the real lower segment stays solid

- [x] **Step 1: Add a failing compact-painter pixel test**

```dart
test('compact preview keeps the virtual segment dashed above its real parent', () async {
  final virtual = graphRow(
    commit: commit('virtual', 'virtual', parents: const ['base']),
    lane: 0,
    activeLanes: const [0],
    nextLanes: const [0],
    activeLaneShas: const {0: 'virtual'},
    nextLaneShas: const {0: 'base'},
  );
  final base = graphRow(
    commit: commit('base', 'base', parents: const ['root']),
    lane: 0,
    activeLanes: const [0],
    nextLanes: const [0],
    activeLaneShas: const {0: 'base'},
    nextLaneShas: const {0: 'root'},
  );
  final painter = CommitGraphPainter(
    row: base,
    previous: virtual,
    selected: false,
    compact: true,
    committerColor: const Color(0xFF34C759),
    previousDashedLanes: const {0},
    previewRailColor: const Color(0xFFC69AFF),
  );
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(56, 36));
  final image = await recorder.endRecording().toImage(56, 36);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  int alphaAt(int y) => bytes!.getUint8((y * 56 + 28) * 4 + 3);

  expect(alphaAt(1), greaterThan(0));
  expect(alphaAt(4), 0);
  expect(alphaAt(20), greaterThan(0));
});
```

- [x] **Step 2: Run the test and verify it fails**

Run: `flutter test test/app_test.dart --plain-name "compact preview keeps the virtual segment dashed above its real parent"`

Expected: FAIL because compact painting currently applies `dashedLanes` to the whole row and ignores `previousDashedLanes`.

- [x] **Step 3: Paint compact upper and lower halves separately**

```dart
final rail = compactRail(size);
void draw(double top, double bottom, {required bool dashed}) {
  if (bottom <= top) return;
  final paint = Paint()
    ..color = dashed ? previewRailColor ?? committerColor : committerColor
    ..strokeWidth = dashed ? previewRailWidth : railWidth
    ..strokeCap = StrokeCap.round;
  _drawVerticalRail(
    canvas,
    Offset(laneInset, top),
    Offset(laneInset, bottom),
    paint,
    dashed: dashed,
  );
}

draw(
  rail.top,
  math.min(rail.bottom, centerY),
  dashed: isDashedAbove(row.lane),
);
draw(
  math.max(rail.top, centerY),
  rail.bottom,
  dashed: isDashedLane(row.lane),
);
```

- [x] **Step 4: Run the compact-painter and preview graph tests**

Run: `flutter test test/app_test.dart --plain-name "compact preview keeps the virtual segment dashed above its real parent"`

Run: `flutter test test/app_test.dart --plain-name "merge preview keeps each parent edge dashed until its parent node"`

Expected: PASS.

### Task 3: Open Rebase mapping arrowhead

**Files:**
- Modify: `lib/timeline.dart:7914-7925`
- Test: `test/app_test.dart:5079-5130`

**Interfaces:**
- Consumes: the mapping line tip and `mapping.color`
- Produces: an unfilled 1-pixel chevron arrowhead

- [x] **Step 1: Add a failing arrowhead pixel test**

```dart
test('rebase mapping arrowhead is an open one-pixel chevron', () async {
  final rows = [
    for (var index = 0; index < 3; index++)
      graphRow(
        commit: commit('row-$index', 'row $index'),
        lane: 0,
        activeLanes: const [0],
        nextLanes: const [0],
      ),
  ];
  final painter = RebaseMappingPainter(
    rows: rows,
    mappings: const [
      (
        originalSha: 'row-2',
        rewrittenSha: 'row-0',
        originalRow: 2,
        rewrittenRow: 0,
        routeLane: 0,
        color: Color(0xFF547C68),
      ),
    ],
    rowIndex: 0,
    laneSpacing: 30.5,
    compact: false,
  );
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(100, 36));
  final image = await recorder.endRecording().toImage(100, 36);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  int alphaAt(int x, int y) => bytes!.getUint8((y * 100 + x) * 4 + 3);

  expect(alphaAt(42, 15), greaterThan(0));
  expect(alphaAt(43, 16), 0);
  expect(alphaAt(42, 21), greaterThan(0));
});
```

- [x] **Step 2: Run the test and verify it fails**

Run: `flutter test test/app_test.dart --plain-name "rebase mapping arrowhead is an open one-pixel chevron"`

Expected: FAIL because the current arrowhead closes and fills a triangle.

- [x] **Step 3: Draw an open stroked chevron**

```dart
final arrow = Path()
  ..moveTo(tip.dx + 5, tip.dy - 4)
  ..lineTo(tip.dx, tip.dy)
  ..lineTo(tip.dx + 5, tip.dy + 4);
canvas.drawPath(
  arrow,
  Paint()
    ..color = mapping.color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round,
);
```

- [x] **Step 4: Run the mapping tests**

Run: `flutter test test/app_test.dart --plain-name "rebase mapping arrowhead is an open one-pixel chevron"`

Run: `flutter test test/app_test.dart --plain-name "rebase mapping lines are one pixel with no outline or gaps"`

Expected: PASS.

### Task 4: Reference and final verification

**Files:**
- Modify: `docs/superpowers/specs/assets/merge-rebase-preview/rebase-preview-refinement-v34.html`

**Interfaces:**
- Consumes: the approved mockup
- Produces: a repository reference matching production

- [x] **Step 1: Update the reference**

Set Branch / Tag cell padding to 14 pixels, keep every virtual rail entirely dashed, and draw mapping arrowheads as open chevrons.

- [x] **Step 2: Format and verify**

Run: `dart format lib/timeline.dart test/app_test.dart`

Run: `flutter analyze`

Run: `flutter test`

Expected: analyzer exits with no issues and the full test suite reports zero failures.

- [ ] **Step 3: Commit**

```bash
git add lib/timeline.dart test/app_test.dart docs/superpowers/specs/2026-07-31-preview-virtual-rail-arrow-design.md docs/superpowers/plans/2026-07-31-preview-virtual-rail-arrow.md docs/superpowers/specs/assets/merge-rebase-preview/rebase-preview-refinement-v34.html
git commit -m "style: refine preview virtual rail details"
```
