# Rebase Mapping Hue Ladder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render successful Rebase mapping lines as a same-hue lightness/saturation ladder and inset preview Branch / Tag chips to match the approved reference.

**Architecture:** Generate the five mapping colors inside `layoutRebasePreviewGraph` from the compare branch's existing graph color, then clamp later mappings to the fifth color. Apply a 16-pixel horizontal inset inside the existing refs cell only while a branch comparison is active so ordinary timeline geometry remains unchanged.

**Tech Stack:** Dart, Flutter widgets and custom painters, Flutter test

## Global Constraints

- Add no dependency or new abstraction.
- Keep each mapping line a single solid color.
- Preserve the existing ordinary timeline rail and chip behavior.
- Keep at most five distinct mapping colors.

---

### Task 1: Compare-branch mapping color ladder

**Files:**
- Modify: `lib/timeline.dart:52-67`
- Modify: `lib/timeline.dart:166-312`
- Modify: `test/app_test.dart:3497-3704`
- Modify: `test/app_test.dart:5042-5060`
- Modify: `test/app_test.dart:5160-5338`
- Modify: `test/git_test.dart:1117-1123`

**Interfaces:**
- Consumes: `AvatarService.branchColor(int branch)` and the compare-tip `GraphRow.branch`
- Produces: `List<Color> rebaseMappingColors(Color branchColor)` and `layoutRebasePreviewGraph(BranchComparisonResult comparison, RebasePreviewResult preview)`

- [x] **Step 1: Write the failing color tests**

```dart
test('rebase mapping colors keep the compare hue and step darker', () {
  const branchColor = Color(0xFF16CBE7);
  final colors = rebaseMappingColors(branchColor);
  final hsl = colors.map(HSLColor.fromColor).toList();

  expect(colors, hasLength(5));
  expect(hsl.map((color) => color.hue), everyElement(closeTo(HSLColor.fromColor(branchColor).hue, 0.5)));
  for (var index = 1; index < hsl.length; index++) {
    expect(hsl[index].saturation, lessThan(hsl[index - 1].saturation));
    expect(hsl[index].lightness, lessThan(hsl[index - 1].lightness));
  }
});
```

- [x] **Step 2: Run the color test and verify it fails**

Run: `flutter test test/app_test.dart --plain-name "rebase mapping colors keep the compare hue and step darker"`

Expected: FAIL because `rebaseMappingColors` still accepts a reserved-color iterable and generates unrelated hues.

- [x] **Step 3: Implement the five-step same-hue palette**

```dart
List<Color> rebaseMappingColors(Color branchColor) {
  final source = HSLColor.fromColor(branchColor);
  final startLightness =
      source.lightness + (1 - source.lightness) * 0.12;
  return [
    for (var index = 0; index < 5; index++)
      source
          .withSaturation(source.saturation * (0.92 - index * 0.11))
          .withLightness(startLightness * (1 - index * 0.09))
          .toColor(),
  ];
}
```

Inside `layoutRebasePreviewGraph`, derive the colors from `AvatarService.branchColor(compare.branch)` and use `colors[index.clamp(0, colors.length - 1)]`. Remove the caller-supplied color parameter and update callers.

- [x] **Step 4: Run the color and graph tests**

Run: `flutter test test/app_test.dart --plain-name "rebase mapping colors keep the compare hue and step darker"`

Run: `flutter test test/app_test.dart --plain-name "preview graph adds virtual merge and rewritten rebase commits"`

Run: `flutter test test/git_test.dart --plain-name "first rebase conflict has no rewritten commits"`

Expected: PASS.

### Task 2: Preview Branch / Tag chip inset

**Files:**
- Modify: `lib/timeline.dart:5186-5238`
- Modify: `test/app_test.dart:3497-3704`

**Interfaces:**
- Consumes: `_comparison`, which is non-null only in branch comparison previews
- Produces: a 16-pixel horizontal inset inside `refs-cell-*` during Merge and Rebase previews

- [x] **Step 1: Write the failing widget assertion**

```dart
final virtualChip = find.byKey(
  const Key('ref-chip-3333333333333333333333333333333333333333-feature · 가상'),
);
final virtualCell = find.ancestor(
  of: virtualChip,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('refs-cell-'),
  ),
);
expect(
  tester.getTopLeft(virtualChip).dx - tester.getTopLeft(virtualCell).dx,
  16,
);
```

- [x] **Step 2: Run the widget test and verify it fails**

Run: `flutter test test/app_test.dart --plain-name "rebase preview adds rewritten commits to the timeline"`

Expected: FAIL because preview chips currently start at the refs-cell edge.

- [x] **Step 3: Add preview-only cell padding**

```dart
final inset = _comparison == null ? 0.0 : 16.0;
final width = constraints.maxWidth - inset * 2;
final slot = width / shown.length;

Positioned(
  left: inset + index * slot,
  width: slot - (_comparison == null ? 2 : 0),
  ...
),
```

- [x] **Step 4: Run the widget test**

Run: `flutter test test/app_test.dart --plain-name "rebase preview adds rewritten commits to the timeline"`

Expected: PASS with both the mapping-border assertions and the 16-pixel chip inset assertion.

### Task 3: Reference and final verification

**Files:**
- Modify: `docs/superpowers/specs/assets/merge-rebase-preview/rebase-preview-refinement-v34.html`

**Interfaces:**
- Consumes: the approved inline mockup and production palette behavior
- Produces: a repository reference with the same-hue mapping ladder and 16-pixel Branch / Tag inset

- [x] **Step 1: Update the human reference**

Set `--map-1`, `--map-2`, and `--map-3` to successively darker colors derived from `--cyan`, keep each mapping stroke solid, and retain `.commit-row > div { padding: 0 16px; }`.

- [x] **Step 2: Format and verify**

Run: `dart format lib/timeline.dart test/app_test.dart test/git_test.dart`

Run: `flutter analyze`

Run: `flutter test`

Expected: analyzer exits with no issues and the full test suite reports zero failures.

- [x] **Step 3: Compare the running app with the reference**

Open a successful Rebase preview and confirm:

1. all mapping lines share the compare-branch hue;
2. the oldest replayed commit is brightest;
3. later mappings step darker without gradients;
4. both mapped avatars use their mapping color as a border;
5. Branch / Tag chips have 16-pixel left and right insets.

- [x] **Step 4: Commit**

```bash
git add lib/timeline.dart test/app_test.dart test/git_test.dart docs/superpowers/specs/2026-07-31-rebase-mapping-hue-ladder-design.md docs/superpowers/plans/2026-07-31-rebase-mapping-hue-ladder.md docs/superpowers/specs/assets/merge-rebase-preview/rebase-preview-refinement-v34.html
git commit -m "style: align rebase mapping color ladder"
```
