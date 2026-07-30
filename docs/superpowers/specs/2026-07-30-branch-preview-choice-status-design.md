# Branch Preview Choice and Status Design

## Goal

Make the Merge/Rebase preview control read as a single-choice selector and
make branch comparison outcomes easier to scan without changing comparison or
preview behavior.

## Approved direction

Use mockup A, the segmented control.

- Place `Merge 미리보기` and `Rebase 미리보기` inside one shared rounded
  container.
- Split the container into two equal segments.
- Fill only the selected segment. The unselected segment has no independent
  pill outline.
- Keep the current 204px toolbar allocation, 32px control height, labels, keys,
  callbacks, saved mode, and keyboard activation.
- Exactly one segment is selected at all times.

## Preview result colors

Use a dedicated semantic success green for successful Merge and Rebase
previews:

- Success icon and label: macOS system green `#34C759`.
- Badge surface, padding, shape, and non-success colors remain unchanged.
- Conflict, failure, and loading states keep their existing colors.

The success green is intentionally separate from the softer diff addition
green.

## Branch commit counts

Show comparison direction directly beside each branch name:

- Base-only commits: `<base branch> −<count>`.
- Compare-only commits: `<compare branch> +<count>`.
- The branch name stays in the current muted text color.
- The signed count alone uses the existing diff colors:
  - removed/base-only count: deletion red `#EF6C63`;
  - added/compare-only count: addition green `#8AD6A1`.
- Keep `부모 동일` / `부모 다름` and `공통 <count>` unchanged.
- Use the same signed count treatment in both the preview summary above the
  timeline and the comparison status bar at the bottom.
- Keep zero counts visible with their directional sign so the row layout and
  meaning remain stable.

## Scope

Keep the change inside `TimelineScreen` in `lib/timeline.dart`.

- Reuse the current preview mode state and callbacks.
- Reuse the existing diff color constants.
- Add only the success semantic color needed by this design.
- Do not change Git commands, comparison calculations, graph layout, preview
  sessions, or conflict handling.
- Do not add a dependency or a reusable design-system component.

## Accessibility and interaction

- Each segment remains individually focusable and activatable.
- The selected state is exposed to accessibility APIs.
- Selecting the active segment is a no-op.
- Selecting the other segment follows the existing preview-mode transition and
  updates the graph and summary as it does today.

## Verification

Widget tests will verify:

1. The two controls render inside one segmented surface with exactly one
   selected state.
2. Switching segments still updates the preview mode and summary.
3. Successful Merge and Rebase results use `#34C759`.
4. Base-only and compare-only counts use the correct sign and existing diff
   color in both summary locations.
5. Conflict, failure, loading, graph, and preview workflows remain unchanged.

Run focused widget tests, static analysis, the complete Flutter test suite, and
the macOS debug build before integration.
