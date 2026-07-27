# Task 7 Report: Visual QA and full verification

## Outcome

Task 7 is complete.

- Refreshed the intentionally stale implementation captures `00`–`12`.
- Kept approved reference images `00`–`12` byte-for-byte unchanged.
- Added reviewed reference, actual, difference, and side-by-side assets for
  captures `13`–`17`.
- Corrected the stale focus-mode assertion for the restored leading back
  button.
- Completed the independent review from `c2219a8` and fixed one P2 typography
  issue found by that review.
- Passed formatting, analysis, visual tests, both full test configurations,
  checksum verification, and the macOS release build.

## Visual QA implementation

### Harness and capture states

`test/support/full_diff_qa_harness.dart` now supplies:

- an empty patch paired with valid UTF-8 file content;
- a historical file list and patch for commit `65f4c80`;
- a short historical Split fixture whose old and new source lines remain
  readable inside the detail pane.

`test/full_diff_visual_test.dart` now captures:

- `13-font-and-back`;
- `14-algorithm-tooltip`;
- `15-unavailable-panel`;
- `16-history-detail`;
- `17-history-detail-split`.

The Histogram capture moves a mouse pointer over the algorithm control, waits
for the 500 ms tooltip delay and its fade-in, and captures the overlay with the
screen.

`tool/full_diff_visual_diff.dart` now generates comparison artifacts and
metrics for all captures `00`–`17`.

### Deferred baseline cleanup

Before Task 7:

- captures `00`–`12` differed from their stored implementation goldens because
  Tasks 1–6 intentionally changed the product;
- the focus-mode position check still expected the path chip itself at the
  left edge, even though Task 2 restored a back button before the file icon
  and path.

The corrected position check now verifies:

1. the back button begins before `x=80`;
2. the back button is left of the file icon;
3. the file icon is left of the path chip;
4. the lower panel also reaches the content edge.

The targeted assertion passed before refreshing any capture.

## Visual TDD evidence

### RED

After the `00`–`12` baseline and focus assertion were corrected, the first full
run with the new cases passed 31 tests and failed only captures `13`–`17`
because their implementation goldens did not exist.

The first tooltip candidate revealed that the tooltip overlay had been
inserted but was still at zero opacity at 600 ms. Adding 100 ms for the fade
made the previous candidate fail by `22,271` pixels (`2.47%`), proving that the
new image contained the visible tooltip.

The first History Split fixture did not make the no-clipping criterion clear.
Two fixture reductions produced deliberate old-golden failures:

- first revision: capture 16 changed by `9,400` pixels (`1.04%`) and capture 17
  by `6,112` pixels (`0.68%`);
- final revision: capture 16 changed by `4,592` pixels (`0.51%`) and capture 17
  by `4,249` pixels (`0.47%`).

The final fixture shows every QA source line in both panes.

### GREEN

```text
flutter test test/full_diff_visual_test.dart --reporter expanded
```

Result: all `36` tests passed.

```text
dart run tool/full_diff_visual_diff.dart
```

Result:

- captures `13`–`17`: `0` changed pixels;
- captures `00`–`12`: comparison images regenerated against the unchanged
  approved references.

## Per-image inspection

### 13 — Font and back

- The 32 px back button is the first control.
- File icon and path chip follow in that order.
- Commit and file list tiers remain readable at 11/10/9 px.
- Diff source and gutters remain readable at 10/8 px.
- Existing row heights keep the compact text from touching or clipping.

### 14 — Algorithm tooltip

- The closed control reads `diff 알고리즘 · Histogram`.
- The visible tooltip includes the selected algorithm title and its
  description.
- Text, popover background, and screen controls remain legible together.

### 15 — Unavailable panel

- Information order is
  `src/drlua.pas` → `M · +12 −4` → `UTF-8` → reason → current options.
- The review fix reduced the reason text from 14 px to the specified 10 px.
- The final image remains centered and readable.

### 16 — History Hunk detail

- Commit `65f4c80` remains selected in the left list.
- The list is 280 px wide and separated by a one-pixel divider.
- The historical file context and right-side Hunk are distinct and readable.

### 17 — History Split detail

- The selected History row and divider remain clear.
- Old and result panes, line numbers, signs, and the central divider are all
  visible.
- Every QA source line fits inside the History detail width.

## Independent follow-up review

The review covered `c2219a8` through the Task 7 implementation and recorded its
result in
`docs/superpowers/verification/full-diff-qa/followup-review.md`.

### P2 finding

The design specifies 10 px for diff empty/error guidance. Several defensive
or shared paths still used earlier sizes:

- unavailable and resource-state guidance: 14 px;
- Hunk, Inline, and Split empty fallbacks: 14 px;
- diff refresh error: 12 px;
- unwrapped Hunk width estimation: measured the rendered 10 px source as
  14 px, creating excess blank horizontal scroll.

Focused RED evidence:

- seven panel/loading checks: expected `10`, actual `14`;
- presentation fallback check: expected `10`, actual `14`;
- refresh error check: expected `10`, actual `12`;
- Hunk width check: expected `6,534`, actual `9,110`;
- capture 15: `4,235` pixels (`0.47%`) differed from the first Task 7
  candidate.

The production values and width calculation now use 10 px. All focused checks
pass, capture 15 was visually reviewed again, and its reviewed image replaced
only the new Task 7 reference.

No P0, P1, P2, or P3 findings remain.

## Final verification

```text
dart format --output=none --set-exit-if-changed lib test tool benchmark
```

Result: `51` files checked, `0` changed.

```text
flutter analyze
```

Result: no issues.

```text
flutter test test/full_diff_visual_test.dart --reporter expanded
```

Result: `36` passed.

```text
flutter test --reporter compact
```

Result: `413` passed.

```text
flutter test --dart-define=YOGIT_EXTENDED_SYNTAX=false --reporter compact
```

Result: `413` passed.

```text
flutter build macos --release --dart-define=YOGIT_EXTENDED_SYNTAX=true
```

Result: built `yogit.app` successfully, `55.3 MB`.

```text
shasum -a 256 -c SHA256SUMS
```

Run from `docs/superpowers/specs/assets/full-diff-qa`.

Result: captures `00`–`17`, both HTML references, and
`user-approved-default.png` all passed.

```text
git diff --exit-code c2219a8 -- <approved reference images 00-12>
git diff --check
```

Result: approved reference images `00`–`12` are unchanged and no whitespace
errors remain.

## Commits

- `56491b2 test: verify full diff usability follow-up`
- `2818a74 chore: close full diff follow-up review`

## Concerns

None. The implementation, visual evidence, and independent review are ready
for integration.
