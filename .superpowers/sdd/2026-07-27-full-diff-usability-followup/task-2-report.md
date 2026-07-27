# Task 2 report — restore Full Diff navigation

## Status

DONE_WITH_CONCERNS

## Implementation summary

- Added an accessible top-left return button to `GlobalFileBar`.
- Routed both the button and unconsumed Escape through `_returnToTimeline()`,
  which calls `Navigator.of(context).maybePop()`.
- Removed the focus-mode-only Escape branch, so one unconsumed Escape now
  returns to the timeline even while focus mode is active.
- Preserved popup-menu Escape handling and added route-level coverage for it.

## Files changed

- `lib/full_diff_header.dart`
- `lib/diff_screen.dart`
- `test/full_diff_header_test.dart`
- `test/full_diff_workspace_test.dart`
- `test/app_test.dart`

## RED

Command:

```bash
flutter test test/full_diff_header_test.dart test/full_diff_workspace_test.dart test/app_test.dart --reporter expanded
```

Evidence: the header test did not compile because `GlobalFileBar` had no
`onBack` parameter. The integration test also failed because no
`full-diff-back` control existed, and the focus-mode route test remained on
the Full Diff screen after its first Escape because the old handler only
disabled focus mode.

## GREEN

Commands:

```bash
dart format lib/full_diff_header.dart lib/diff_screen.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart test/app_test.dart
flutter test test/full_diff_header_test.dart test/full_diff_workspace_test.dart test/app_test.dart --reporter expanded
```

Evidence: formatting completed and all 172 focused tests passed.

Additional focused visual-layout check:

```bash
flutter test test/full_diff_visual_test.dart --plain-name '782px keeps each global header on one line' --reporter expanded
```

Evidence: passed.

## Full suite

Command:

```bash
flutter test
```

Result: functional tests completed, but 14 visual golden checks failed. The
new leading return button intentionally changes the Full Diff header pixels;
the existing captured images still represent the prior header. No unrelated
golden assets were changed in this task.

## Self-review

- The button has the requested key, tooltip, compact 32×32 target, and an
  explicit Korean accessibility label.
- Button and Escape share exactly one navigation path.
- The existing `Shortcuts`/`Actions` arrangement stays around the route's
  autofocus `Focus`, retaining descendant key-event propagation; focused-code
  navigation is covered by integration test.
- The popup menu consumes its first Escape before a second Escape returns.
- `git diff --check` passed before the implementation commit.

## Commit SHA

`98a2eb4`

## Concerns

The repository's visual-golden baselines need a deliberate follow-up update
for the new header control; this task intentionally left those generated
assets unchanged.
