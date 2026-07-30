# Branch Preview Choice and Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the separate Merge/Rebase preview pills with one single-choice segmented control and clarify successful comparison results with semantic green and signed diff-colored commit counts.

**Architecture:** Keep all production changes inside `TimelineScreen`. Use Flutter's native `SegmentedButton<BranchPreviewMode>` with the existing preview state, and use one small rich-text helper for the signed branch counts shown in both comparison summaries.

**Tech Stack:** Flutter, Dart, Material `SegmentedButton`, `flutter_test`

## Global Constraints

- Use approved mockup A.
- Preserve the 204px toolbar allocation and 32px control height.
- Preserve the existing labels, keys, callbacks, saved mode, graph updates, and keyboard activation.
- Exactly one preview mode is selected at all times.
- Use success green `#34C759`.
- Use deletion red `#EF6C63` for base-only counts and addition green `#8AD6A1` for compare-only counts.
- Keep zero counts visible with their directional sign.
- Apply signed counts to both the preview summary and comparison status bar.
- Do not change Git commands, comparison calculations, graph layout, preview sessions, or conflict handling.
- Do not add a dependency or reusable design-system component.

---

### Task 1: Replace the two preview pills with one segmented control

**Files:**
- Modify: `lib/timeline.dart:1635-1685`
- Test: `test/app_test.dart:2606-2654`

**Interfaces:**
- Consumes: `_branchPreviewMode`, `_setBranchPreviewMode(BranchPreviewMode)`, `TimelineThemePalette`
- Produces: `SegmentedButton<BranchPreviewMode>` keyed `branch-preview-segmented`, with label keys `branch-preview-merge` and `branch-preview-rebase`

- [ ] **Step 1: Write the failing segmented-selection assertions**

Extend `branch preview controls switch the summary above the timeline` after
the branch comparison opens:

```dart
final segmented = tester.widget<SegmentedButton<BranchPreviewMode>>(
  find.byKey(const Key('branch-preview-segmented')),
);
expect(segmented.selected, {BranchPreviewMode.merge});
expect(segmented.showSelectedIcon, isFalse);
expect(find.byKey(const Key('branch-preview-merge')), findsOneWidget);
expect(find.byKey(const Key('branch-preview-rebase')), findsOneWidget);
```

After tapping `branch-preview-rebase`, add:

```dart
expect(
  tester
      .widget<SegmentedButton<BranchPreviewMode>>(
        find.byKey(const Key('branch-preview-segmented')),
      )
      .selected,
  {BranchPreviewMode.rebase},
);
```

- [ ] **Step 2: Run the focused test and verify that it fails**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'branch preview controls switch the summary above the timeline'
```

Expected: FAIL because no widget has the `branch-preview-segmented` key.

- [ ] **Step 3: Replace the custom row with Flutter's segmented control**

Replace `_branchPreviewControls()` and remove `_branchPreviewButton(...)`:

```dart
Widget _branchPreviewControls() => SizedBox(
  height: 32,
  child: SegmentedButton<BranchPreviewMode>(
    key: const Key('branch-preview-segmented'),
    segments: const [
      ButtonSegment(
        value: BranchPreviewMode.merge,
        label: Text(
          'Merge 미리보기',
          key: Key('branch-preview-merge'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      ButtonSegment(
        value: BranchPreviewMode.rebase,
        label: Text(
          'Rebase 미리보기',
          key: Key('branch-preview-rebase'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
    selected: {_branchPreviewMode},
    showSelectedIcon: false,
    onSelectionChanged: (selected) =>
        _setBranchPreviewMode(selected.single),
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? _palette.text
            : _palette.muted,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? _palette.selectedRow
            : _palette.background,
      ),
      side: WidgetStatePropertyAll(
        BorderSide(color: _palette.border),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 6),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  ),
);
```

The toolbar's existing `SizedBox(width: 204, ...)` remains unchanged.

- [ ] **Step 4: Run the focused test and verify that it passes**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'branch preview controls switch the summary above the timeline'
```

Expected: PASS.

- [ ] **Step 5: Commit the segmented control**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "style: segment branch preview modes"
```

---

### Task 2: Apply semantic success and signed commit-count colors

**Files:**
- Modify: `lib/timeline.dart:24-45`
- Modify: `lib/timeline.dart:2805-2865`
- Modify: `lib/timeline.dart:2955-3045`
- Test: `test/app_test.dart:2606-2665`

**Interfaces:**
- Consumes: `BranchComparisonResult`, `_main`, `_hash`, `_palette.muted`
- Produces: `_branchCommitCount(...) -> Widget`, keys `branch-preview-base-count`, `branch-preview-compare-count`, `comparison-status-base-count`, and `comparison-status-compare-count`

- [ ] **Step 1: Add the failing success and signed-count test**

Add this widget test beside the preview-control test, using the same real
timeline setup and `branchComparison()` fixture:

```dart
testWidgets('branch preview summary uses success and signed diff colors', (
  tester,
) async {
  await tester.pumpWidget(
    app(
      FakeGitRepository(
        (_, _) async => [commit('normal', 'normal history')],
        refs: const RepoRefs(
          local: ['main', 'feature'],
          current: 'main',
          tips: {'main': 'main-tip', 'feature': 'feature-tip'},
        ),
        compareBranchesCallback: (_, _) async => branchComparison(),
        simulateRebaseCallback: ({required baseRef, required compareRef}) =>
            Future.value(
              const RebaseCheckResult(status: RebaseCheckStatus.clean),
            ),
      ),
      controller,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('branch-diff-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
  await tester.pumpAndSettle();

  expect(
    tester.widget<Text>(find.text('Merge 성공')).style?.color,
    const Color(0xFF34C759),
  );
  expect(
    tester
        .widget<Icon>(
          find.byKey(const Key('branch-preview-success-icon')),
        )
        .color,
    const Color(0xFF34C759),
  );

  void expectCount(
    String key,
    String text,
    Color color,
  ) {
    final widget = tester.widget<Text>(find.byKey(Key(key)));
    final span = widget.textSpan! as TextSpan;
    expect(span.toPlainText(), text);
    expect(
      (span.children!.single as TextSpan).style?.color,
      color,
    );
  }

  for (final key in [
    'branch-preview-base-count',
    'comparison-status-base-count',
  ]) {
    expectCount(key, 'main −1', const Color(0xFFEF6C63));
  }
  for (final key in [
    'branch-preview-compare-count',
    'comparison-status-compare-count',
  ]) {
    expectCount(key, 'feature +1', const Color(0xFF8AD6A1));
  }
});
```

- [ ] **Step 2: Run the new test and verify that it fails**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'branch preview summary uses success and signed diff colors'
```

Expected: FAIL because `Merge 성공` still uses `_main` and the signed-count
keys do not exist.

- [ ] **Step 3: Add the semantic success color**

Add beside the existing timeline color constants:

```dart
const _success = Color(0xFF34C759);
```

In `_branchPreviewSummary()`, change the success icon and successful result
label from `_main` to `_success`. Leave conflict, failure, and loading colors
unchanged.

- [ ] **Step 4: Add one rich-text helper for directional counts**

Add this private widget helper near the two comparison summary methods:

```dart
Widget _branchCommitCount({
  required Key key,
  required String branch,
  required int count,
  required bool added,
}) => Text.rich(
  TextSpan(
    text: '$branch ',
    style: TextStyle(color: _palette.muted, fontSize: 10),
    children: [
      TextSpan(
        text: '${added ? '+' : '−'}$count',
        style: TextStyle(
          color: added ? _main : _hash,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ),
  key: key,
);
```

- [ ] **Step 5: Use signed counts in the bottom comparison status**

In `_comparisonStatusBar()`, replace the `List<String> labels` with a
`List<Widget> items`.

For a loaded comparison, keep ordinary status text as muted `Text` widgets and
insert:

```dart
_branchCommitCount(
  key: const Key('comparison-status-base-count'),
  branch: comparison.baseRef,
  count: comparison.commits
      .where((entry) => entry.side == BranchCommitSide.baseOnly)
      .length,
  added: false,
),
_branchCommitCount(
  key: const Key('comparison-status-compare-count'),
  branch: comparison.compareRef,
  count: comparison.commits
      .where((entry) => entry.side == BranchCommitSide.compareOnly)
      .length,
  added: true,
),
```

Keep the existing separator, horizontal scrolling, error label color, merge
status, and rebase status. Change `itemCount` and `itemBuilder` to render
`items`.

- [ ] **Step 6: Use the same signed counts above the timeline**

In `_branchPreviewSummary()`, change `details` to `List<Widget>` and insert:

```dart
_branchCommitCount(
  key: const Key('branch-preview-base-count'),
  branch: comparison.baseRef,
  count: comparison.commits
      .where((entry) => entry.side == BranchCommitSide.baseOnly)
      .length,
  added: false,
),
_branchCommitCount(
  key: const Key('branch-preview-compare-count'),
  branch: comparison.compareRef,
  count: comparison.commits
      .where((entry) => entry.side == BranchCommitSide.compareOnly)
      .length,
  added: true,
),
```

Build the unchanged parent, common, and progress labels as muted `Text`
widgets. Render each detail widget directly:

```dart
for (final detail in details) ...[
  const SizedBox(width: 12),
  detail,
],
```

- [ ] **Step 7: Run focused branch-preview tests**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'branch preview controls switch the summary above the timeline'
flutter test test/app_test.dart \
  --plain-name 'branch preview summary uses success and signed diff colors'
flutter test test/app_test.dart \
  --plain-name 'rebase conflict focuses the actual commit row'
```

Expected: all three pass.

- [ ] **Step 8: Format and verify the complete project**

Run:

```bash
dart format lib/timeline.dart test/app_test.dart
git diff --check
flutter analyze
flutter test
flutter build macos --debug
```

Expected: formatting makes no unrelated changes, analysis reports no issues,
all tests pass, and the macOS debug app builds.

The complete test suite currently conflicts with an active external
`yogit_rebase_preview_*` worktree because an existing test scans the global
temporary directory. Do not delete another live preview worktree. Run the suite
when that external preview closes, then require a clean run before integration.

- [ ] **Step 9: Commit the status presentation**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "style: clarify branch comparison status"
```
