# Task 6 report: lazy selectable Hunk widgets

## Status

Implementation complete. The task adds only:

- `lib/full_diff_hunk_view.dart`
- `test/full_diff_widgets_test.dart`

The intended commit subject is `feat: render selectable hunk blocks`.

## RED evidence

The widget tests were written before the production widget file existed.

Command:

```text
dart format test/full_diff_widgets_test.dart && flutter test test/full_diff_widgets_test.dart
```

Result: failed during test compilation for the intended missing-widget reason.
The relevant output was:

```text
Error when reading 'lib/full_diff_hunk_view.dart': No such file or directory
Error: Undefined name 'HunkCard'.
Error: Method not found: 'HunkListView'.
00:00 +0 -1: Some tests failed.
```

This established that the focused test suite could not pass without the new
public widget boundary.

## GREEN evidence

The first implementation run exercised the real interaction and found one
behavioral issue rather than a fixture or framework error:

```text
flutter test test/full_diff_widgets_test.dart
```

Result:

```text
00:01 +7 -1: Some tests failed.
Expected: <0>
Actual: <null>
```

The per-card `SelectionArea` was nested inside the `InkWell`, so selection won
the gesture arena when the test tapped source text. Reversing that nesting
kept selection around the entire Hunk while allowing the inner ink response to
win taps.

Command after that correction:

```text
dart format lib/full_diff_hunk_view.dart && flutter test test/full_diff_widgets_test.dart
```

Result:

```text
00:01 +8: All tests passed!
```

The eight widget tests cover:

1. readable range, function context, position, add/delete markers, and omission
   of raw patch headers;
2. three context lines on both sides of a delete/add pair and the exact 15%
   add/delete fills;
3. selected border, selected/button/tap semantics, and the selection callback;
4. one local `SelectionArea` per mounted Hunk and no list-wide selection area;
5. the deliberate empty state with no `ListView`;
6. observable lazy construction across 100 Hunks and a
   `SliverChildBuilderDelegate`;
7. measured horizontal overflow and a moving horizontal scroll position when
   wrapping is off;
8. real source wrapping with no horizontal scroller when wrapping is on.

## Layout and interaction decisions

- `HunkListView` uses `ListView.builder`, the required `Key('hunk-list')`, the
  supplied vertical controller, and exactly `document.hunks.length` items.
- Each card receives either the caller-supplied `GlobalKey` for its stable
  anchor ID or a `ValueKey` based on that same ID. No transient list index is
  used as the card key.
- Empty documents render `No changes` on the list background and do not build
  a list.
- `HunkCard` owns only presentation and selection state passed by its caller.
  It exposes selected/button/tap semantics and makes the visible Material card
  tappable.
- Each card has one `SelectionArea`; the `InkWell` sits inside it so source
  selection drags remain local while taps still select the card.
- The header renders only the model's readable range, optional context, and
  position. Empty context contributes no widget, and raw patch headers are
  never read.
- The function context uses the system font. Range, position, gutter, marker,
  and source text use `technicalFontFamily` and
  `technicalFontFallback` directly from `typography.dart`.
- Every source row keeps 42 px old-number, 42 px new-number, and 20 px marker
  slots. Numbered gutters use the raised fill; missing numbers stay blank.
- The selected border uses `0xFF3A4657`; row fills remain independently visible
  at `0xFF8AD6A1`/`0xFFF29AB2` with 0.15 alpha.
- Wrapped rows use a bounded `Row` and `Expanded` source column, so continuation
  text stays under the source column rather than the gutter.
- Non-wrapped rows measure their longest source text with `TextPainter` and the
  same Menlo-backed style used to paint it. The measured source width plus the
  104 px gutter and source padding is clamped to at least the viewport width,
  then placed in a non-primary horizontal `SingleChildScrollView`. The
  `Expanded` source field is therefore always inside a fixed-width `SizedBox`,
  never an unbounded horizontal flex.
- The new view imports the model, `git.dart` for `DiffLineKind`, and
  `typography.dart` directly. It does not import `diff_screen.dart` or
  `timeline.dart`.

## Analysis and self-review

Scoped analysis command:

```text
flutter analyze lib/full_diff_hunk_view.dart test/full_diff_widgets_test.dart
```

Result:

```text
Analyzing 2 items...
No issues found! (ran in 0.9s)
```

Self-review checks:

- Public scope is limited to `HunkListView` and `HunkCard`; all row/header
  helpers and palette values are file-private.
- No `DiffDocument.headers` or `DiffDocument.rows` value is rendered.
- Add/delete fills are not replaced by selected-card fill.
- The horizontal scroller has no vertical controller and is explicitly
  non-primary.
- The lazy-list test verifies both initial absence and later construction of a
  distant anchor.
- `git diff --check` reported no whitespace errors.
- No unrelated file was modified.

## Final verification

Before commit, the implementation and test files were also checked for
formatting and whitespace:

```text
dart format --output=none --set-exit-if-changed lib/full_diff_hunk_view.dart test/full_diff_widgets_test.dart
flutter test test/full_diff_widgets_test.dart
flutter analyze lib/full_diff_hunk_view.dart test/full_diff_widgets_test.dart
git diff --check
```

Recorded results:

```text
Formatted 2 files (0 changed) in 0.01 seconds.
00:01 +8: All tests passed!
Analyzing 2 items...
No issues found! (ran in 0.4s)
git diff --check: exit 0, no output
```
