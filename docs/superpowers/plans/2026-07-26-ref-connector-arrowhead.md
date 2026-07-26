# Ref Connector Arrowhead Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** End each branch or tag connector with a one-pixel open chevron that stops four logical pixels before the visible commit marker.

**Architecture:** Keep all connector geometry and painting in `CommitGraphPainter`. First add testable shaft and chevron geometry for an ordinary 22px avatar, then make the arrow tip account for the smaller merge dot and working-tree ring while preserving the current pass-through and compact-mode behavior.

**Tech Stack:** Flutter, Dart, `CustomPainter`, Flutter paint matchers

## Global Constraints

- Keep the connector shaft and open chevron at `1.0` logical pixel.
- Use the connector's existing branch color, `StrokeCap.round`, and `StrokeJoin.round`.
- Use a `7.0`px-long, `10.0`px-tall open chevron.
- Leave `4.0` logical pixels between the arrow tip and the marker radius.
- Use marker radii of `11.0` for ordinary avatars, `nodeRadius` for merge dots, and `wipNodeRadius` for working-tree rings.
- Keep branch/tag chips, selected-row boundaries, rails, transition curves, nodes, hover behavior, date headings, and graph compression unchanged.
- Rows without refs and pass-through date headings must not draw the shaft or arrowhead.

---

### Task 1: Draw the one-pixel open arrow for an ordinary commit

**Files:**
- Modify: `lib/timeline.dart:3435-3450`
- Modify: `lib/timeline.dart:3638-3653`
- Test: `test/app_test.dart:501-525`

**Interfaces:**
- Adds: `CommitGraphPainter.avatarRadius`
- Adds: `CommitGraphPainter.refArrowGap`
- Adds: `CommitGraphPainter.refArrowLength`
- Adds: `CommitGraphPainter.refArrowHalfHeight`
- Adds: `CommitGraphPainter.refMarkerRadius`
- Adds: `CommitGraphPainter.refArrowTipX`
- Adds: `CommitGraphPainter.refArrowheadPath(double centerY)`
- Changes: `CommitGraphPainter.paint(Canvas, Size)` when `refConnector` is true

- [ ] **Step 1: Replace the straight-connector test with a failing open-arrow test**

Replace `ref connector is a solid one-pixel line` in `test/app_test.dart` with:

```dart
test('ref connector points at an ordinary commit with a one-pixel chevron', () {
  const size = Size(120, TimelineScreen.rowHeight);
  const color = Color(0xFF00E5FF);
  final row = layoutGraph([commit('tip', 'tip')]).single;
  final painter = CommitGraphPainter(
    row: row,
    selected: false,
    committerColor: color,
    refConnector: true,
  );
  const centerY = TimelineScreen.rowHeight / 2;
  const tip = Offset(13, centerY);

  expect(
    (Canvas canvas) => painter.paint(canvas, size),
    paints
      ..line(
        p1: const Offset(0, centerY),
        p2: tip,
        color: color,
        strokeWidth: 1.0,
      )
      ..path(
        color: color,
        strokeWidth: 1.0,
        style: PaintingStyle.stroke,
      ),
  );
});
```

The expected tip is `28 - 11 - 4 = 13`: lane zero's center minus the
ordinary avatar radius and the approved gap.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
/Users/doortts/repos/flutter/bin/flutter test test/app_test.dart \
  --plain-name 'ref connector points at an ordinary commit with a one-pixel chevron'
```

Expected: FAIL because the current shaft ends at `x = 28` and no arrowhead path
is painted.

- [ ] **Step 3: Add the approved arrow constants and testable geometry**

Add these constants beside the existing connector and node constants in
`CommitGraphPainter`:

```dart
static const connectorWidth = 1.0;
static const avatarRadius = 11.0;
static const refArrowGap = 4.0;
static const refArrowLength = 7.0;
static const refArrowHalfHeight = 5.0;
static const nodeRadius = 6.0;
static const wipNodeRadius = 8.0;
```

Add these members after `laneX`:

```dart
double get refMarkerRadius => avatarRadius;

double get refArrowTipX =>
    laneX(row.lane) - refMarkerRadius - refArrowGap;

Path refArrowheadPath(double centerY) {
  final tipX = refArrowTipX;
  return Path()
    ..moveTo(
      tipX - refArrowLength,
      centerY - refArrowHalfHeight,
    )
    ..lineTo(tipX, centerY)
    ..lineTo(
      tipX - refArrowLength,
      centerY + refArrowHalfHeight,
    );
}
```

- [ ] **Step 4: Paint the shaft and open chevron with one shared paint**

Replace the `refConnector` block in `paint` with:

```dart
if (refConnector) {
  final connectorPaint = Paint()
    ..color = committerColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = connectorWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.drawLine(
    Offset(0, centerY),
    Offset(refArrowTipX, centerY),
    connectorPaint,
  );
  canvas.drawPath(refArrowheadPath(centerY), connectorPaint);
}
```

Leave `_drawNode` after this block so merge dots and working-tree rings remain
visually above the connector.

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```bash
/Users/doortts/repos/flutter/bin/flutter test test/app_test.dart \
  --plain-name 'ref connector points at an ordinary commit with a one-pixel chevron'
```

Expected: PASS.

- [ ] **Step 6: Commit Task 1**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: point ref connectors at commits"
```

---

### Task 2: Preserve the four-pixel gap for every marker and graph mode

**Files:**
- Modify: `lib/timeline.dart:3473-3480`
- Test: `test/app_test.dart` near the connector and date-separator painter tests

**Interfaces:**
- Refines: `CommitGraphPainter.refMarkerRadius`
- Changes: `CommitGraphPainter.refArrowTipX` to use the row's visible marker

- [ ] **Step 1: Add failing marker-aware geometry tests**

Add this test after the ordinary connector test:

```dart
test('ref arrow keeps its gap for merge, working-tree, and compact rows', () {
  CommitGraphPainter painter(
    GraphRow row, {
    bool compact = false,
  }) => CommitGraphPainter(
    row: row,
    selected: false,
    committerColor: const Color(0xFF00E5FF),
    refConnector: true,
    compact: compact,
  );

  final merge = painter(
    graphRow(
      commit: commit('merge', 'merge', parents: const ['a', 'b']),
      lane: 0,
    ),
  );
  final workingTree = painter(
    graphRow(commit: workingTreeCommit('head'), lane: 0),
  );
  final compact = painter(
    graphRow(commit: commit('tip', 'tip'), lane: 3),
    compact: true,
  );

  expect(merge.refMarkerRadius, CommitGraphPainter.nodeRadius);
  expect(merge.refArrowTipX, 18.0);
  expect(workingTree.refMarkerRadius, CommitGraphPainter.wipNodeRadius);
  expect(workingTree.refArrowTipX, 16.0);
  expect(compact.laneX(compact.row.lane), CommitGraphPainter.laneInset);
  expect(compact.refMarkerRadius, CommitGraphPainter.avatarRadius);
  expect(compact.refArrowTipX, 13.0);
});
```

Add these geometry and no-ref assertions to the ordinary connector test:

```dart
expect(painter.refMarkerRadius, CommitGraphPainter.avatarRadius);
expect(painter.refArrowTipX, tip.dx);
expect(
  painter.refArrowheadPath(centerY).getBounds(),
  const Rect.fromLTRB(6, 11, 13, 21),
);

final noRefPainter = CommitGraphPainter(
  row: row,
  selected: false,
  committerColor: color,
);
expect(
  (Canvas canvas) => noRefPainter.paint(canvas, size),
  isNot(paints..line(p1: const Offset(0, centerY))),
);
```

- [ ] **Step 2: Strengthen the date-heading test to prohibit arrowheads**

In `a date separator carries the rails and the sweep across itself`, set
`refConnector: true` on the pass-through painter and add:

```dart
expect(
  (Canvas canvas) => painter.paint(canvas, size),
  isNot(
    paints..line(
      p1: const Offset(0, 18),
      p2: const Offset(13, 18),
    ),
  ),
);
```

This proves that `passThrough` still returns before connector painting even
when a caller supplies `refConnector: true`. Rows without refs remain covered
by constructing their painters with `refConnector: false`.

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```bash
/Users/doortts/repos/flutter/bin/flutter test test/app_test.dart \
  --name 'ref connector points at an ordinary commit with a one-pixel chevron|ref arrow keeps its gap for merge, working-tree, and compact rows|a date separator carries the rails and the sweep across itself'
```

Expected: FAIL because `refMarkerRadius` and `refArrowTipX` still assume an
ordinary avatar for every row. The merge and working-tree assertions fail
while the ordinary and compact assertions continue to pass.

- [ ] **Step 4: Make the arrow tip marker-aware**

Add this getter and update `refArrowTipX`:

```dart
double get refMarkerRadius {
  if (row.commit.isWorkingTree) return wipNodeRadius;
  if (showsMergeDot) return nodeRadius;
  return avatarRadius;
}

double get refArrowTipX =>
    laneX(row.lane) - refMarkerRadius - refArrowGap;
```

Do not add special compact-mode code: `laneX` already collapses every lane to
`laneInset`, so the same formula preserves the gap.

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run:

```bash
/Users/doortts/repos/flutter/bin/flutter test test/app_test.dart \
  --name 'ref connector points at an ordinary commit with a one-pixel chevron|ref arrow keeps its gap for merge, working-tree, and compact rows|a date separator carries the rails and the sweep across itself'
```

Expected: all three tests PASS.

- [ ] **Step 6: Format and run the full verification**

Run:

```bash
/Users/doortts/repos/flutter/bin/dart format lib/timeline.dart test/app_test.dart
/Users/doortts/repos/flutter/bin/flutter test test/app_test.dart
/Users/doortts/repos/flutter/bin/flutter analyze
```

Expected: formatting makes no further changes after the first run, the full
timeline test file passes, and analysis reports no issues.

- [ ] **Step 7: Review the diff against the approved design**

Run:

```bash
git diff --check
git diff -- lib/timeline.dart test/app_test.dart
```

Confirm:

- the arrow is an open chevron, not a filled triangle;
- the shaft and chevron share the branch color and `1.0` stroke width;
- the arrow tip stays four pixels from ordinary, merge, and working-tree
  markers;
- pass-through date rows paint no connector or arrow;
- no chip, selection, rail, transition, or avatar behavior changed.

- [ ] **Step 8: Commit Task 2**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: keep ref arrow gap marker-aware"
```
