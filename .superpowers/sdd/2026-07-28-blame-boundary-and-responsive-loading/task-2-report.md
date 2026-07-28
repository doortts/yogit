# Task 2 Report: Show Blame Source While Loading

## Result

`FullBlameView.loading` now renders file source and line numbers before blame
metadata is available. Its normal and loading constructors use the same widget
type, so a stable key preserves selection state; the supplied focus node and
scroll controller remain attached when loaded metadata replaces the loading
view.

Loading rows use muted `Blame 계산 중…` metadata, a muted rail, and an empty
avatar slot. They do not resolve a remote avatar. The selected-line commit card
is created only after a real `BlameLine` is available, so no commit message is
requested during loading. Arrow and Vim navigation now use the source file line
count, which is present in both states.

## RED

Command:

```bash
flutter test test/full_diff_content_views_test.dart --plain-name "loaded blame keeps loading selection focus and scroll"
```

Observed expected failure before production changes:

```text
Error: Member not found: 'FullBlameView.loading'.
```

## GREEN and Verification

Focused commands (all exited successfully):

```bash
flutter test test/full_diff_content_views_test.dart --plain-name "loaded blame keeps loading selection focus and scroll"
flutter test test/full_diff_content_views_test.dart --plain-name "blame focus selects, navigates, and returns to files"
flutter test test/full_diff_content_views_test.dart --plain-name "blame retains a constant number of row GlobalKeys"
flutter test test/full_diff_content_views_test.dart --plain-name "blame rows expose one exact semantics label"
```

Each reported `+1: All tests passed!`.

Additional verification:

```bash
dart format lib/full_blame_view.dart test/full_diff_content_views_test.dart
git diff --check
flutter test test/full_diff_content_views_test.dart
```

The complete content-view suite passed: `44` tests, `0` failures.

## Files Changed

- `lib/full_blame_view.dart`
  - Added `FullBlameView.loading` plus `file` and nullable `lines` state.
  - Rendered loading-safe rows from file content and made navigation operate on
    file lines.
  - Deferred the card, avatar resolution, and metadata presentation until blame
    data exists.
- `test/full_diff_content_views_test.dart`
  - Added a keyed loading-to-loaded host and an interaction test proving focus,
    selection, and scroll retention.

## Test Correction

The brief's `find.text('Loaded summary 6')` assertion matched both the restored
row and the existing commit card, which intentionally displays the same
fallback summary. It was narrowed to
`find.byKey(const Key('blame-summary-6'))` so the test verifies the required
loaded-row replacement without changing the existing card behavior.

## Self-Review

- The same `ValueKey` and widget type are used for loading and loaded displays;
  no state recreation is introduced by the view itself.
- All former `widget.document` reads were replaced by `file` or nullable
  `lines` as appropriate.
- Loading rows have no `BlameLine`, so `_avatar` returns before any
  `AvatarService.resolve` call and the selected card condition remains false.
- No Git, cache, request-race, commit-card, package, or unrelated-file changes
  were made.

## Concerns

- None. The only brief adjustment was the row-specific matcher described above;
  it avoids an ambiguous assertion while preserving the stated behavior.
