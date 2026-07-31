# Adjacent Preview Diff Design

## Goal

Keep the commit preview focused on commit information and changed files, then open a separate resizable diff pane only when a changed file is selected.

## Layout

- The existing preview pane keeps its configured size and placement.
- With a right preview, the diff pane opens immediately to its left.
- With a left preview, the diff pane opens immediately to its right.
- With a bottom preview, the diff pane opens immediately above it.
- Growing the diff pane reduces only the timeline area. It never reduces the preview pane.
- The diff splitter can move across the full remaining workspace, including either endpoint.

## Opening and closing

- Opening the preview does not load or show a file diff.
- Clicking a changed file opens the adjacent diff pane for that file.
- The first file click leaves exactly 100 logical pixels of timeline space when no saved diff size exists.
- Clicking another file replaces the diff content without closing the pane.
- Clicking outside the diff pane does not close it.
- The close button closes only the diff pane.
- Escape closes the diff pane first. A second Escape closes the preview pane.

## Persistence

- User-resized diff extents are stored separately for left, right, and bottom preview placements.
- A stored extent is restored when the diff pane is reopened or the application restarts.
- The automatic first-open extent is not stored until the user drags the splitter.
- Stored extents are clamped to the current workspace size.

## Existing behavior retained

- Unified and Side-by-side remain available in the diff toolbar.
- Preview file keyboard navigation continues to select and reveal files.
- Preview and diff scrolling remain independent.
- Existing branch merge/rebase preview file diffs use the same adjacent pane.

