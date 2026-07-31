# Branch Lane Palette Assignments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the separate Branch/Tag and lane color controls with the approved eight-row palette, fixed Color 1 base-branch behavior, and deterministic Random or Lane 2–9 assignments.

**Architecture:** Extend the existing `AppSettings.refPalette` model with one parallel assignment list and keep the legacy base/lane fields only for backward compatibility. Reuse the current graph rebuild and `AvatarService.branchAssignments` path; one palette-index calculation supplies both chip Base colors and graph Text / line colors.

**Tech Stack:** Flutter, Dart 3.11, `flutter_test`; no new dependencies.

## Global Constraints

- Palette rows are Color 1, 3, 4, 5, 6, 7, 8, and 9; Color 2 must not exist.
- Color 1 is fixed to Base branch. Color 3–9 default to Random and may be pinned to Lane 2–9.
- Chip background uses Base at 18%; chip border uses Text / line at 30%; text and graph use Text / line at 100%.
- A pinned color is removed from the Random pool; selecting a claimed lane returns the previous color to Random.
- Random selection is deterministic across rebuilds and pagination.
- Existing comparison and rebase preview colors remain unchanged.
- Preserve unrelated untracked workspace files and add no dependency.

---

### Task 1: Persist the unified palette and assignments

**Files:**
- Modify: `lib/settings.dart:267-590`
- Test: `test/app_test.dart:6170-6300`

**Interfaces:**
- Produces: `AppSettings.refPaletteNumbers: List<int>` with `[1, 3, 4, 5, 6, 7, 8, 9]`.
- Produces: `AppSettings.refPaletteAssignments: List<int>` where `1` is fixed Base branch, `0` is Random, and `2..9` is a pinned lane.
- Produces: JSON key `refPaletteAssignments` and five-row legacy `refPalette` migration.

- [ ] **Step 1: Write failing settings tests**

Replace the old five-color expectations and add assignment validation:

```dart
expect(AppSettings.refPaletteNumbers, const [1, 3, 4, 5, 6, 7, 8, 9]);
expect(AppSettings.defaultRefPalette, const [
  (base: '#0E8A16', text: '#18E022'),
  (base: '#C5DEF5', text: '#C2DDF4'),
  (base: '#1D76DB', text: '#68A7EA'),
  (base: '#5319E7', text: '#DACFFA'),
  (base: '#B51D68', text: '#FF2D95'),
  (base: '#008FA3', text: '#00E5FF'),
  (base: '#B89B00', text: '#FFF01F'),
  (base: '#C94E10', text: '#FF6E27'),
]);
expect(AppSettings.defaultRefPaletteAssignments, const [1, 0, 0, 0, 0, 0, 0, 0]);

const custom = AppSettings(refPaletteAssignments: [1, 2, 0, 4, 0, 0, 0, 9]);
expect(AppSettings.fromJson(custom.toJson()), custom);
expect(
  AppSettings.fromJson({'refPaletteAssignments': [1, 2, 2, 0, 0, 0, 0, 0]}).refPaletteAssignments,
  AppSettings.defaultRefPaletteAssignments,
);
```

Add a legacy five-row input and expect the order `old[3], old[2], old[0], old[4]` plus the four new defaults, with every non-base assignment set to Random.

- [ ] **Step 2: Run the focused test and confirm failure**

Run: `flutter test test/app_test.dart --plain-name 'branch tag palette round-trips and rejects damaged records'`

Expected: FAIL because the new defaults and `refPaletteAssignments` do not exist.

- [ ] **Step 3: Add the minimum settings model changes**

Keep `RefPaletteEntry` and add constants and storage directly to `AppSettings`:

```dart
static const refPaletteNumbers = [1, 3, 4, 5, 6, 7, 8, 9];
static const defaultRefPaletteAssignments = [1, 0, 0, 0, 0, 0, 0, 0];
final List<int> refPaletteAssignments;
```

Update the constructor, `copyWith`, equality, hash code, `toJson`, and `fromJson`. Accept an assignment list only when it has eight entries, starts with `1`, contains only `0` or `2..9` after the first entry, and has no duplicate nonzero lane. When an eight-row palette is absent but a valid five-row palette exists, migrate it with:

```dart
final migrated = [
  refPalette[3],
  refPalette[2],
  refPalette[0],
  refPalette[4],
  ...defaultRefPalette.skip(4),
];
```

Keep `baseBranchColor` and `laneColors` readable and writable for existing settings, but stop using them in the normal timeline in Task 3.

- [ ] **Step 4: Run the focused settings test**

Run: `flutter test test/app_test.dart --plain-name 'branch tag palette round-trips and rejects damaged records'`

Expected: PASS.

- [ ] **Step 5: Commit the settings model**

```bash
git add lib/settings.dart test/app_test.dart
git commit -m "feat: persist branch palette assignments"
```

---

### Task 2: Replace the settings controls with the unified editor

**Files:**
- Modify: `lib/settings.dart:660-760,981-1145`
- Test: `test/app_test.dart:7000-7140`

**Interfaces:**
- Consumes: `AppSettings.refPaletteNumbers`, `refPaletteAssignments`, and the eight palette rows from Task 1.
- Produces: widget keys `ref-palette-assignment-<index>` for palette rows 1–7; values are `0` and `2..9`.

- [ ] **Step 1: Write a failing widget test**

```dart
expect(find.text('Branch / Tag & graph palette'), findsOneWidget);
expect(find.text('Base branch and lane fallback'), findsNothing);
expect(find.byKey(const Key('base-branch-color')), findsNothing);
expect(find.byKey(const Key('lane-color-0')), findsNothing);
expect(find.text('Color 2'), findsNothing);
expect(find.text('Color 9'), findsOneWidget);

await tester.tap(find.byKey(const Key('ref-palette-assignment-1')));
await tester.tap(find.text('Lane 2').last);
await tester.pumpAndSettle();
expect(saved.last.refPaletteAssignments[1], 2);

await tester.tap(find.byKey(const Key('ref-palette-assignment-2')));
await tester.tap(find.text('Lane 2').last);
await tester.pumpAndSettle();
expect(saved.last.refPaletteAssignments[1], 0);
expect(saved.last.refPaletteAssignments[2], 2);
```

- [ ] **Step 2: Run the widget test and confirm failure**

Run: `flutter test test/app_test.dart --plain-name 'branch tag palette editor applies Base and Text and resets'`

Expected: FAIL because the unified title and assignment dropdowns do not exist.

- [ ] **Step 3: Implement the unified editor**

Delete the legacy base/lane controllers, callbacks, reset button, and editor rows. Rename the section to `Branch / Tag & graph palette`. Render labels with `AppSettings.refPaletteNumbers[index]`, show `Base branch` beside Color 1, and render this selector for indexes 1–7:

```dart
DropdownButton<int>(
  key: Key('ref-palette-assignment-$index'),
  value: _settings.refPaletteAssignments[index],
  items: const [
    DropdownMenuItem(value: 0, child: Text('Random')),
    for (var lane = 2; lane <= 9; lane++)
      DropdownMenuItem(value: lane, child: Text('Lane $lane')),
  ],
  onChanged: (lane) => _changeRefPaletteAssignment(index, lane!),
)
```

When assigning a nonzero lane, map every other occurrence of that lane to `0` before setting the chosen row. Reset both `refPalette` and `refPaletteAssignments` in `_resetRefPalette`.

- [ ] **Step 4: Run the settings widget test**

Run: `flutter test test/app_test.dart --plain-name 'branch tag palette editor applies Base and Text and resets'`

Expected: PASS.

- [ ] **Step 5: Commit the editor**

```bash
git add lib/settings.dart test/app_test.dart
git commit -m "feat: unify timeline palette settings"
```

---

### Task 3: Use one deterministic assignment for graph lines and ref chips

**Files:**
- Modify: `lib/main.dart:285-320`
- Modify: `lib/timeline.dart:526-676,690-770,817-823,1191-1193,1363-1372,5230-5235,5672-5936`
- Test: `test/app_test.dart:5935-6010,8125-8270,11080-11290`

**Interfaces:**
- Consumes: the eight palette rows and assignment values from Task 1.
- Produces: `randomRefPaletteIndexes(List<int>) -> List<int>`.
- Produces: `refPaletteIndexForName(String, List<int>) -> int`.
- Produces: `assignBranchPaletteIndexes(List<GraphRow>, int, {Map<int,String>, List<int>}) -> Map<int,int>`.
- Keeps: `assignBranchColors(...) -> Map<int,Color>` as the test seam, now derived from palette indexes.

- [ ] **Step 1: Write failing assignment tests**

```dart
final rows = [
  born(0, const {0: 0}),
  born(1, const {0: 0, 1: 1}),
  born(2, const {0: 0, 1: 1, 2: 2}),
  born(9, const {0: 0, 9: 9}),
];
const assignments = [1, 0, 3, 0, 0, 0, 0, 0];
final indexes = assignBranchPaletteIndexes(
  rows,
  7,
  refPaletteAssignments: assignments,
);
expect(indexes[0], 0);
expect(indexes[2], 2);
expect(indexes[1], isNot(2));
expect(indexes[9], isNot(2));
expect(
  assignBranchPaletteIndexes(rows, 7, refPaletteAssignments: assignments),
  indexes,
);
```

Add a no-Random-candidates test with assignments `[1,2,3,4,5,6,7,8]` and verify branch 9 still receives an index from `1..7`.

- [ ] **Step 2: Run the assignment test and confirm failure**

Run: `flutter test test/app_test.dart --plain-name 'branch colors use fixed lanes and a deterministic random pool'`

Expected: FAIL because palette-index assignment is not implemented.

- [ ] **Step 3: Implement palette-index assignment**

Remove `_branchColorPool` and `_secondBranchColors`. Calculate candidates from assignment value `0`, falling back to palette indexes `1..7` when none remain. Use the pinned palette index when `assignment == branchId + 1`; otherwise select deterministically:

```dart
final key = branchNames[id] ?? '$seed:$id';
indexes[id] = candidates[stableRefPaletteIndex(key, candidates.length)];
```

Always assign palette index `0` to branch ID `0`. Make `assignBranchColors` parse the Text / line color at every chosen index.

- [ ] **Step 4: Wire settings into the timeline and chips**

Add `refPaletteAssignments` to `TimelineScreen`, pass it from `main.dart`, and rebuild when either palette list changes. Store the latest branch-to-palette-index map in `_branchPaletteIndexes` during `_rebuildGraph`, then derive `AvatarService.branchAssignments` from it.

Pass `row.branch` into `_refsCell`. For the first sorted ref in a normal row, use `_branchPaletteIndexes[row.branch]`; for secondary refs use `refPaletteIndexForName`. Apply the same rule to modal accent colors. Comparison rows continue using their existing `rowAccentColor` without reading this map.

- [ ] **Step 5: Run focused graph and chip tests**

```bash
flutter test test/app_test.dart --plain-name 'ref chip and graph use the same palette text color'
flutter test test/app_test.dart --plain-name 'branch colors use fixed lanes and a deterministic random pool'
flutter test test/app_test.dart --plain-name 'the selected multi-ref row lists its refs in a floating modal'
```

Expected: PASS with Color 1 green on the base branch, Color 4 blue when assigned, and secondary refs restricted to Random colors.

- [ ] **Step 6: Commit graph integration**

```bash
git add lib/main.dart lib/timeline.dart test/app_test.dart
git commit -m "feat: apply branch palette to graph lanes"
```

---

### Task 4: Verify the complete change

**Files:**
- Modify only if verification finds a defect: `lib/settings.dart`, `lib/main.dart`, `lib/timeline.dart`, `test/app_test.dart`

**Interfaces:**
- Consumes: all preceding tasks.
- Produces: analyzer-clean code and a passing full test file.

- [ ] **Step 1: Format and check the diff**

```bash
dart format lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart
git diff --check
```

Expected: formatter exits 0 and `git diff --check` prints nothing.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`.

- [ ] **Step 3: Run the complete app test file**

Run: `flutter test test/app_test.dart`

Expected: all tests pass.

- [ ] **Step 4: Verify exact rendered colors in widget tests**

```dart
expect(baseDecoration.color, const Color(0xFF0E8A16).withValues(alpha: .18));
expect(baseDecoration.border!.top.color, const Color(0xFF18E022).withValues(alpha: .30));
expect(basePainter.committerColor, const Color(0xFF18E022));
expect(color4Painter.committerColor, const Color(0xFF68A7EA));
```

Expected: every RGB channel matches the approved palette exactly; Flutter alpha composition is asserted from the same source value.

- [ ] **Step 5: Commit any verification fix**

If Step 1–4 required a correction:

```bash
git add lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart
git commit -m "fix: align branch palette rendering"
```

If no correction was needed, do not create an empty commit.
