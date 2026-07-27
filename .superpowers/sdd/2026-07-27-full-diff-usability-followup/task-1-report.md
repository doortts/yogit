# Task 1 report — 목록과 diff 글자 크기

## Status

DONE

## Files changed

- `lib/full_diff_code_row.dart`
- `lib/full_diff_hunk_header.dart`
- `lib/full_diff_header.dart`
- `lib/full_history_view.dart`
- `lib/diff_screen.dart`
- `test/full_diff_widgets_test.dart`
- `test/full_diff_header_test.dart`
- `test/full_diff_workspace_test.dart`

## RED

Command:

```bash
flutter test test/full_diff_widgets_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart --reporter expanded
```

Expected failure evidence: the new expectations failed only because the old
typography was still present. The output included `Expected: <11> Actual:
<14.0>` for the file path and commit titles, and `Expected: <10> Actual:
<14.0>` for diff source text and Hunk headers. After narrowing the History
finders to the History row, the repeated RED run reported only these expected
font-size mismatches.

## GREEN

Command:

```bash
dart format lib/full_diff_code_row.dart lib/full_diff_hunk_header.dart lib/full_diff_header.dart lib/full_history_view.dart lib/diff_screen.dart test/full_diff_widgets_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
flutter test test/full_diff_widgets_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart --reporter expanded
```

Passing output summary: formatter completed and all 63 targeted tests passed.

## Self-review notes

- Kept the diff line height at 21 pixels by changing only the approved font
  sizes and their matching `TextStyle.height` values.
- Preserved every existing padding value, control height, row height, and click
  target.
- Added widget-level assertions for diff source and gutter text, Hunk headers,
  the file path, commit/file lists, and each History-row text tier.
- Ran `git diff --check`; it reported no whitespace errors.

## Commit SHA

`06dc63fe918bcc1639235157b84a183abada7f6a`

## Concerns

None.
