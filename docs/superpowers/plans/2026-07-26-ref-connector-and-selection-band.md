# Ref Connector and Selection Band Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render ref connectors as solid 1px lines and begin a selected commit row's background at its focused graph lane.

**Architecture:** Keep `CommitGraphPainter` responsible for the connector and the lane-relative graph tint. Build the row on its normal background, then place a selected background layer from the focused lane's global x-coordinate to the right edge; ref chips always use their normal style.

**Tech Stack:** Flutter, Dart, `CustomPainter`, Flutter widget and paint matchers

## Global Constraints

- The ref connector is a solid `1.0` logical-pixel line.
- Graph rails, transition curves, commit nodes, chip borders, hover behavior, and date-heading selection remain unchanged.
- Everything left of the selected commit's vertical graph line uses the normal timeline background.
- Ref chips use normal unselected styling even when their commit row is selected.
- Existing selected styling to the right of the focused lane remains unchanged.

---

### Task 1: Make the ref connector a solid 1px line

**Files:**
- Modify: `lib/timeline.dart:3425`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `CommitGraphPainter.paint(Canvas, Size)` with `refConnector: true`
- Produces: `CommitGraphPainter.connectorWidth == 1.0`

- [ ] **Step 1: Write the failing painter test**

Add this test near the existing graph painter tests in `test/app_test.dart`:

```dart
test('ref connector is a solid one-pixel line', () {
  const size = Size(120, TimelineScreen.rowHeight);
  const color = Color(0xFF00E5FF);
  final row = layoutGraph([commit('tip', 'tip')]).single;
  final painter = CommitGraphPainter(
    row: row,
    selected: false,
    committerColor: color,
    refConnector: true,
  );

  expect(
    (Canvas canvas) => painter.paint(canvas, size),
    paints
      ..line(
        p1: const Offset(0, TimelineScreen.rowHeight / 2),
        p2: const Offset(
          CommitGraphPainter.laneInset,
          TimelineScreen.rowHeight / 2,
        ),
        color: color,
        strokeWidth: 1.0,
      ),
  );
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
/Users/doortts/repos/flutter/bin/flutter test test/app_test.dart \
  --plain-name 'ref connector is a solid one-pixel line'
```

Expected: FAIL because the connector paint uses `strokeWidth: 2.0`.

- [ ] **Step 3: Make the minimal production change**

Change only the connector constant in `lib/timeline.dart`:

```dart
static const connectorWidth = 1.0;
```

Keep the connector's existing `drawLine`, color, and `StrokeCap.round`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
/Users/doortts/repos/flutter/bin/flutter test test/app_test.dart \
  --plain-name 'ref connector is a solid one-pixel line'
```

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: render ref connectors at one pixel"
```

---

### Task 2: Start the selected background at the focused lane

**Files:**
- Modify: `lib/timeline.dart:23-24`
- Modify: `lib/timeline.dart:1930-2175`
- Test: `test/app_test.dart:35-80`
- Test: `test/app_test.dart:1912-1945`

**Interfaces:**
- Consumes: `CommitGraphPainter.laneX(int lane)` and the current Branch / Tag column width from `_w('refs')`
- Produces: a `ColoredBox` keyed as `selection-band-<commit sha>` whose left edge is `_w('refs') + painter.laneX(row.lane)`

- [ ] **Step 1: Replace the whole-row selection assertions with focused-lane assertions**

In `keyboard and pointer control selection and preview`, replace the
whole-row blue background expectations with:

```dart
final selected = find.byKey(const Key('selected-row-2'));
expect(selected, findsOneWidget);

final selectedBase =
    tester.widget<GestureDetector>(selected).child! as ColoredBox;
expect(selectedBase.color, const Color(0xFF15171E));

final band = find.byKey(const Key('selection-band-2'));
final bandRect = tester.getRect(band);
final graphRect = tester.getRect(find.byKey(const Key('graph-cell-1')));
final refsRect = tester.getRect(find.byKey(const Key('refs-cell-1')));
final graphPainter = tester.widget<CustomPaint>(
  find.byKey(const Key('graph-painter-1')),
).painter! as CommitGraphPainter;

expect(
  bandRect.left,
  graphRect.left + graphPainter.laneX(graphPainter.row.lane),
);
expect(bandRect.left, greaterThan(refsRect.right));
expect(bandRect.right, tester.getRect(selected).right);
```

This proves that the Branch / Tag cell and the graph area before the focused
lane remain outside the selection band.

- [ ] **Step 2: Change the ref-chip test to require stable normal styling**

Rename `selected row tints its ref chip and marks HEAD and tags` to
`selected row keeps normal ref chip styling and marks HEAD and tags`.

Capture the main chip color while its row is selected, move selection to the
tagged row, and verify the main chip color does not change:

```dart
Color chipColor(Key key) =>
    (tester.widget<Container>(find.byKey(key)).decoration! as BoxDecoration)
        .color!;

const mainKey = Key('ref-chip-3-main');
const tagKey = Key('ref-chip-tagged-v1.0');
final mainWhileSelected = chipColor(mainKey);
final tagWhileUnselected = chipColor(tagKey);

await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
await tester.pumpAndSettle();

expect(chipColor(mainKey), mainWhileSelected);
expect(chipColor(tagKey), tagWhileUnselected);
expect(find.text('✓'), findsOneWidget);
expect(find.text('◇'), findsOneWidget);
```

- [ ] **Step 3: Run both focused tests and verify RED**

Run:

```bash
/Users/doortts/repos/flutter/bin/flutter test test/app_test.dart \
  --name 'keyboard and pointer control selection and preview|selected row keeps normal ref chip styling and marks HEAD and tags'
```

Expected failures:

- `selection-band-2` does not exist and the selected base is still blue.
- The selected and unselected ref-chip colors differ.

- [ ] **Step 4: Add the lane-relative selection layer**

Keep the row's outer `ColoredBox` on the normal background when selected, and
place the selection band behind the row content:

```dart
child: ColoredBox(
  color: selected
      ? _background
      : hovered
      ? _accent.withValues(alpha: 0.48)
      : _background,
  child: Stack(
    children: [
      if (selected)
        Positioned(
          left: _w('refs') + painter.laneX(row.lane),
          top: 0,
          right: 0,
          bottom: 0,
          child: ColoredBox(
            key: Key('selection-band-${commit.sha}'),
            color: _selectedRow,
          ),
        ),
    ],
  ),
),
```

Move the current `Row` expression into the `Stack.children` list immediately
after the conditional `Positioned`; do not change its cell order or contents.

Keep `selected: selected` on `CommitGraphPainter`. Its existing
`selectedBandRect` adds the current graph tint from the same lane to the graph
cell's right edge.

- [ ] **Step 5: Remove selected styling from ref chips**

Remove `_selectedChip` and the `selected` parameter from `_refsCell` and
`_refChip`. Build chips with their normal colors:

```dart
decoration: BoxDecoration(
  color: color.withValues(alpha: 0.14),
  border: Border.all(color: color.withValues(alpha: 0.55)),
  borderRadius: BorderRadius.circular(5),
),
child: Row(
  children: [
    _refGlyph(ref, color, false),
    _refName(ref, color, false),
  ],
),
```

Update the `_rowContent` call to:

```dart
_refsCell(entry.rowIndex, commit, refs, branchColor),
```

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run:

```bash
/Users/doortts/repos/flutter/bin/flutter test test/app_test.dart \
  --name 'keyboard and pointer control selection and preview|selected row keeps normal ref chip styling and marks HEAD and tags'
```

Expected: both tests PASS.

- [ ] **Step 7: Format and run the full verification**

Run:

```bash
/Users/doortts/repos/flutter/bin/dart format lib/timeline.dart test/app_test.dart
/Users/doortts/repos/flutter/bin/flutter test test/app_test.dart
/Users/doortts/repos/flutter/bin/flutter analyze
```

Expected: formatting makes no further changes after the first run, the timeline
test file passes, and analysis reports no issues.

- [ ] **Step 8: Commit Task 2**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: start selection at the focused graph lane"
```
