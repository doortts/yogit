# Full Diff whole-branch follow-up fix report

## Outcome

All nine follow-up findings against base commit `07e9ce5` are fixed.

- Implementation commit: `38bc5be` (`fix: close full diff follow-up findings`)
- Focused controller/header/workspace suite: 85 tests passed.
- Visual suite: 36 tests passed.
- Both full configurations: 428 tests passed in each configuration after the
  final characterization test.
- macOS release build: passed.
- Initial independent code review: no product findings. A final re-review
  found one stale documentation record and one explicit deleted-file coverage
  gap; both are addressed in the final follow-up below.

## Finding-to-change map

| # | Finding | Production or documentation change | Regression coverage |
| --- | --- | --- | --- |
| 1 | The algorithm control exposed no semantic tap action and could produce duplicate accessibility content. | `_AlgorithmMenu` now owns a stable popup key, exposes one button semantic node with a tap action, keeps the selected value in the label, places the explanation in the hint, and excludes the nested popup/tooltip semantics. | `algorithm semantics explain the setting and open the menu on semantic tap` |
| 2 | The algorithm tooltip did not explain the purpose of the setting. | Added `Git이 변경 구간을 나누는 방식을 정합니다.` and kept the tooltip as a readable two-line title/explanation shown after 500 ms. Capture 14 now records the complete purpose and Histogram description. | Strengthened hover timing/content coverage and capture 14 assertions. |
| 3 | Escape could pop the Full Diff route while an algorithm tooltip was visible. | The Full Diff Escape action calls `Tooltip.dismissAllToolTips()` first. The back button remains unaffected, and popup-menu Escape precedence is preserved. | `a visible algorithm tooltip consumes Escape before route navigation`, plus the existing popup-menu Escape test. |
| 4 | History Split used the whole window width instead of the local detail width. | The History detail is now wrapped in a `LayoutBuilder`, and `_diffContent` receives the detail pane's actual width. A local detail at or below 480 px hides the old Split side; wider details still show both sides. | Integrated 782/1440 px History test plus unchanged standalone 651/650/481/480 px Split tests. Captures 05 and 17 record the narrow-detail behavior. |
| 5 | History retries could discard the retained list/context or retry the wrong resource. | `retryFiles()` now reselects the retained History entry when History context exists. Patch errors always call `retryPatch()`, while file-list errors call context-sensitive `retryFiles()`. | Controller and widget tests cover unmatched current patches, historical file-list failures, list identity, context identity, and selection retention. |
| 6 | Selected-file byte-load failures appeared as generic loading/error output and broad History retries. | Added `retryFile()`. File and Diff views now render the structured unavailable panel with path, stats, `Git error`, reason, details, and a direct content-only retry. Deleted files use their old path. | File/Diff widget matrix verifies two content requests, one unchanged patch request, structured details, and recovery. A controller test covers historical context retention, and final characterization coverage explicitly covers the distinct-old-path deletion contract. |
| 7 | A failed algorithm refresh over an empty preserved document hid the refresh error. | `_withRefreshError()` now wraps both normal presentations and the no-changes panel, preserving the empty document below the compact error overlay. | `an empty preserved patch keeps refresh errors visible and can recover` |
| 8 | History list scroll position survived file/commit/parent/session context changes. | Added a pending History scroll reset that is triggered by History context changes or controller replacement, but not by selecting another row in the same History list. | Tests cover same-list row selection, file change, commit change, parent change, and controller replacement. RED assertions observed 300 px where 0 was required; GREEN assertions now pass. |
| 9 | The follow-up design still documented a stale 100,000-line limit. | Corrected the design to the enforced 200,000-line limit and documented the local History Split rule and intentional visual baseline scope. | Repository-wide text search finds no stale `100,000줄` or `100,000행` references in docs, production, tests, tools, or benchmarks. |

## TDD evidence

### RED

Each production change was preceded by a focused failing test:

- Algorithm semantics lacked `SemanticsAction.tap`.
- The hover tooltip lacked the setting-purpose sentence.
- The first Escape popped the route instead of dismissing the visible tooltip.
- The 782 px integrated History layout still mounted `split-old-pane` and
  produced overflow output even though its local detail width was below 480 px.
- Historical file retry replaced retained History state, and the unmatched
  current-patch UI retry timed out.
- `retryFile()` was undefined, and File/Diff byte failures did not mount
  `full-diff-unavailable`.
- The empty preserved document did not mount `diff-refresh-error`.
- History context changes left the list at 300 px instead of resetting to 0.
- Text search found the two stale 100,000-line design references.

The first visual comparison after the functional fixes failed only the three
captures directly affected by the changes:

| Capture | Changed pixels | Changed percent | Reason |
| --- | ---: | ---: | --- |
| `05-history-view` | 42,623 | 4.73% | Local History detail width now collapses Split to the result side. |
| `14-algorithm-tooltip` | 17,436 | 1.94% | Tooltip now includes the setting purpose. |
| `17-history-detail-split` | 27,492 | 3.05% | Narrow History detail now uses the result-side fallback. |

### GREEN

- Focused controller/header/workspace run: 85 tests passed.
- Resource-specific retry checks passed for patch, files, and file bytes.
- History scroll tests passed for stable and changed contexts.
- Algorithm semantics, hover timing, tooltip Escape, and popup-menu Escape
  tests passed.
- Visual suite passed all 36 tests after approving only captures 05, 14, and
  17.

## Visual inspection

The refreshed images were inspected at original resolution:

- Capture 05 keeps the History list and selected state clear. Its 467 px detail
  shows the result side without clipping while the Split setting remains
  selected.
- Capture 14 shows `Diff 알고리즘 · Histogram` followed by the purpose and the
  Histogram-specific explanation on a high-contrast tooltip surface.
- Capture 17 keeps commit `65f4c80`, the History divider, result line numbers,
  signs, and every QA source line readable in the 467 px detail.

Reference, actual, difference, and side-by-side assets were regenerated only
where bytes genuinely changed. Capture 14 and 17 difference images were already
the same zero-difference bitmap, so only their side-by-side files changed.
Capture 05's difference image changed to zero difference with its new approved
reference.

Integrity checks confirmed:

- Reference and actual images for 05, 14, and 17 are byte-identical.
- Every unrelated reference, actual, difference, and side-by-side image is
  byte-identical to `07e9ce5`.
- `SHA256SUMS` validates all 21 listed files.

## Final verification

| Command | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test tool benchmark` | Passed: 51 files, 0 changed. |
| `flutter analyze` | Passed: no issues. |
| `flutter test test/full_diff_visual_test.dart --reporter expanded` | Passed: 36 tests. |
| `flutter test --reporter compact` | Passed: 427 tests. |
| `flutter test --dart-define=YOGIT_EXTENDED_SYNTAX=false --reporter compact` | Passed: 427 tests. |
| `flutter build macos --release --dart-define=YOGIT_EXTENDED_SYNTAX=true` | Passed: `yogit.app`, 55.3 MB. |
| `shasum -a 256 -c SHA256SUMS` | Passed: all 21 files. |
| Unrelated visual asset comparison against `07e9ce5` | Passed: no changes. |
| Stale 100,000-line text search | Passed: no matches. |
| `git diff --check` | Passed. |

## Review

The complete product change set was independently reviewed against `07e9ce5`,
including production code, tests, Korean documentation, and visual assets.

- The first review found no product correctness issues.
- The final re-review found a stale visual-review description and a missing
  explicit deleted-file edge assertion. It did not find another product bug.
- Self-review found one consistency improvement before the final gates:
  History detail file-list errors now call context-sensitive `retryFiles()`
  instead of the broader legacy retry method. Its focused controller and widget
  tests passed afterward.

## Files changed

Production:

- `lib/diff_screen.dart`
- `lib/full_diff_controller.dart`
- `lib/full_diff_header.dart`

Tests:

- `test/full_diff_controller_test.dart`
- `test/full_diff_header_test.dart`
- `test/full_diff_visual_test.dart`
- `test/full_diff_workspace_test.dart`

Documentation and visual assets:

- `docs/superpowers/specs/2026-07-27-full-diff-usability-followup-design.md`
- `docs/superpowers/specs/assets/full-diff-qa/{05,14,17}*.png`
- `docs/superpowers/specs/assets/full-diff-qa/SHA256SUMS`
- `docs/superpowers/verification/full-diff-qa/README.md`
- The corresponding actual and genuinely changed difference/side-by-side
  assets for captures 05, 14, and 17.

## Remaining concerns

No blockers or known correctness issues remain.

The responsive contract is intentional: Split remains the selected
presentation at a local detail width of 480 px or less, but only the result side
is rendered to prevent clipping. Wider History details render both Split sides.

## Final re-review follow-up

The final re-review did not find another product defect. It found one important
documentation inconsistency and one minor explicit edge-case coverage gap.

Documentation corrections:

- `docs/superpowers/verification/full-diff-qa/followup-review.md` now records
  capture 17's 467 px result-only fallback instead of old/result panes and a
  central divider.
- The same review now records that the later whole-branch fix intentionally
  refreshed references 05, 14, and 17. Only 05 changed within the `00`–`12`
  range; 00–04 and 06–12 remain byte-identical to `07e9ce5`.
- The Task 7 report now has an explicit superseding note, qualifies its original
  `00`–`12` immutability statements as Task 7 checkpoint results, and describes
  the current capture 17 result-side fallback.

Deleted-file characterization coverage:

- Added `deleted Diff content failure retries the old-side file resource`.
- The test uses distinct `path` and `oldPath` values and verifies that the
  structured unavailable panel shows the old path.
- It verifies that both content attempts target the old path, the recovered
  `FileDocument` keeps that path, content requests increase from one to two,
  and patch requests remain at one.
- The new test passed immediately against `38bc5be`. This is characterization
  coverage of existing correct behavior, not RED evidence, so no product code
  changed.

Fresh test evidence for this follow-up:

| Command | Result |
| --- | --- |
| Focused deleted-file test | Passed: 1 test. |
| `flutter test test/full_diff_workspace_test.dart --reporter expanded` | Passed: 54 tests. |
| `flutter test --reporter compact` | Passed: 428 tests. |
| `flutter test --dart-define=YOGIT_EXTENDED_SYNTAX=false --reporter compact` | Passed: 428 tests. |
| `dart format --output=none --set-exit-if-changed lib test tool benchmark` | Passed: 51 files, 0 changed. |
| `flutter analyze` | Passed: no issues. |
| `shasum -a 256 -c SHA256SUMS` | Passed: all 21 files. |
| Relative Markdown link check | Passed for the QA README, both review reports, and this report. |

No visual baseline or release build was rerun because this follow-up changes
only tests and documentation.
