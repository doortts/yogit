# Full Diff Workspace Design

## Goal

Turn Yogit's Full Diff screen into a code-review workspace without losing its
fast commit and file navigation.

The approved direction keeps the existing three-pane layout and adds a focus
mode that collapses both navigation panes when more code width is needed.

## Approved Layout

The screen has two fixed header rows above the existing three-pane body.

### File Header

The first row identifies the selected file and owns file-level actions:

- selected path;
- file status and addition/deletion counts;
- `Open in editor`;
- `File`, `Diff`, `Blame`, and `History` content modes;
- detected encoding.

The path and file statistics remain visible while the diff scrolls.

### Diff Toolbar

The second row owns presentation controls:

- focus mode;
- `Hunk`, `Inline`, and `Split` layouts;
- previous and next change navigation with the current change number;
- a fixed dropdown trigger named `diff 알고리즘`;
- `Git setting`, `Myers`, `Minimal`, `Patience`, and `Histogram` menu items;
- ignore-whitespace toggle;
- line-wrap toggle.

The dropdown trigger keeps the name `diff 알고리즘` after a selection. The
selected algorithm is indicated inside the menu and in the existing status
text, rather than replacing the trigger name.

### Three-Pane Body

The body keeps Yogit's current structure:

1. nearby commits;
2. selected commit details and changed files;
3. the selected content mode.

Focus mode hides the first two panes and gives the full body width to the
content pane. Leaving focus mode restores the saved navigation widths and the
previous commit and file selections.

At narrow widths, the nearby-commits pane collapses first and the changed-files
pane collapses second. The content pane never shrinks below its current minimum
width.

## Feature Rollout

The work is split into three independently testable phases. Each phase leaves
the screen usable and can ship before the next phase.

### Phase 1: Navigation and Controls

- Add the two-level file header and toolbar.
- Add focus mode.
- Add previous/next change navigation.
- Add line wrap.
- Add ignore-whitespace support.
- Hide raw Git patch headers in the normal reader.
- Rename the algorithm control trigger to `diff 알고리즘`.
- Preserve merge-parent selection, algorithm selection, resizable columns,
  selection, loading behavior, caching, and keyboard navigation.

Focus mode, wrap, layout, and ignore-whitespace choices are session state in
the first release. Existing saved column widths remain persistent.

### Phase 2: Diff Reader

- Add `Hunk`, `Inline`, and `Split` layouts.
- Add syntax highlighting.
- Add word-level highlighting inside paired delete/add lines.
- Keep line-number gutters continuous through context and change rows.
- Render a striped placeholder where one split side has no corresponding line.
- Add a file minimap with change marks and a visible viewport indicator.
- Keep syntax colors on text. Additions and deletions use subdued row
  backgrounds plus explicit `+` and `−` markers.

`Hunk` is the compact review layout: hunk headings, changed lines, and the Git
context supplied around each hunk. `Inline` shows old and new lines in one
column. `Split` pairs old and new lines in two columns.

The minimap is derived from the displayed rows. Selecting a mark moves to that
change and updates the change counter.

### Phase 3: File Investigation

- `File` shows the complete file at the selected commit.
- `Diff` shows the selected comparison.
- `Blame` adds commit and author information to complete-file lines.
- `History` lists commits that changed the selected path.
- `Open in editor` opens the working-tree path in the user's default editor.
- The file header reports UTF-8 or binary content in the first release.

`File`, `Blame`, and `History` load only when first selected. Their results are
cached separately by commit, parent, and path.

`Open in editor` is disabled for deleted files and paths that do not exist in
the working tree. It never writes a committed file back to the working tree.

## Visual Rules

Four visual rules apply to every phase:

1. Use the normal UI font for navigation and controls. Use D2Coding only for
   source, paths, hashes, and line numbers.
2. Keep file identity and content-mode actions in the first header row. Keep
   diff presentation controls in the second row.
3. Preserve syntax colors. Encode additions and deletions with subtle
   backgrounds, gutters, and `+`/`−` markers rather than recoloring the whole
   line.
4. Use text labels for primary modes. Use icons with tooltips for secondary
   actions such as previous/next change.

The existing dark palette remains the source of truth. New fills derive from
the current added, deleted, surface, border, accent, and muted colors.

## Component Boundaries

`DiffScreen` remains the coordinator for selection, loading, caching, and
keyboard commands. The current file should be split into focused widgets as the
new UI is added:

- `DiffFileHeader` renders file identity and content-mode actions.
- `DiffToolbar` renders layout and display controls.
- `DiffNavigationPanes` owns the two resizable navigation columns.
- `DiffContentView` switches between file, diff, blame, and history content.
- `DiffCodeView` renders Hunk, Inline, and Split layouts from shared rows.
- `DiffMinimap` renders and selects change positions.

These widgets receive state and callbacks. They do not run Git commands or own
independent selection state.

Repository methods remain responsible for Git operations:

- patch diff with algorithm and whitespace options;
- complete file at a commit;
- blame data for a file at a commit;
- path history.

No separate state-management framework is introduced.

## Data Flow

Selecting a commit loads its changed files. Selecting a file then loads the
patch diff and restores the content pane to its last chosen mode.

Algorithm or ignore-whitespace changes extend the diff cache key and request a
new patch. The old patch remains visible with a loading indicator until the new
request succeeds. A failed request restores the last successfully displayed
options.

Layout, focus, wrap, hunk navigation, and minimap interactions operate on the
loaded model and do not run Git again.

File, blame, and history requests use the existing stale-request protection so
results from a previously selected commit or path cannot replace the current
content.

## Rendering Model

The parser should separate raw patch metadata from displayed rows and retain:

- hunk ranges and headings;
- old and new line numbers;
- context, addition, deletion, and missing-side rows;
- change-group indices;
- source text before syntax and word highlighting.

Word highlighting runs only for paired delete/add rows. It compares
whitespace-delimited tokens with punctuation boundaries and returns unchanged,
deleted, and added spans. Very long lines fall back to row-level highlighting
to avoid quadratic work.

Syntax highlighting is applied after diff pairing so it cannot affect line
matching. Word-level spans take visual precedence over syntax colors only in
their highlighted background.

## Keyboard and Accessibility

Existing shortcuts remain:

- Up/Down selects files.
- Command-Up/Command-Down selects nearby commits.
- Escape returns to the timeline.

Add:

- Option-Up/Option-Down moves between change groups.
- Command-Shift-F toggles focus mode.

All toolbar actions remain reachable by keyboard and expose tooltips or
semantic labels. Selected modes and toggles expose their selected state.

## Error and Special States

- Loading an alternative diff keeps the current diff visible.
- File, blame, and history failures show an error within the content pane and
  leave the header and navigation usable.
- Binary files show metadata and editor actions but no text renderer.
- Empty diffs show a clear no-changes message.
- Deleted files keep Diff and History available but disable File, Blame, and
  Open in editor where content is unavailable.
- Merge commits continue to reload every view when the comparison parent
  changes.

## Verification

Unit tests will cover:

- Git arguments for every algorithm and ignore-whitespace combination;
- patch-header filtering and hunk grouping;
- split pairing and missing-side rows;
- word-level spans and the long-line fallback;
- minimap change positions;
- complete-file, blame, and history parsing.

Widget tests will cover:

- the fixed `diff 알고리즘` trigger and all algorithm menu items;
- file-header and toolbar layout at wide and narrow sizes;
- focus-mode collapse and width restoration;
- Hunk, Inline, and Split switching without a Git reload;
- change navigation and minimap selection;
- wrap and ignore-whitespace states;
- File, Diff, Blame, and History lazy loading;
- editor-action enablement;
- loading, stale requests, binary files, empty results, and failures;
- keyboard shortcuts and semantic selected states.

Manual acceptance uses the DRL repository to compare the same commit and file
in Yogit and GitKraken. The comparison checks line pairing, hunk boundaries,
path history, blame ownership, focus-mode width, and minimap positions.

## Non-Goals

- Editing, staging, discarding, or committing inside the diff reader
- Merge-conflict resolution
- Arbitrary character-set conversion
- User-defined syntax themes
- User-defined toolbar layouts
- Persisting every display toggle between application launches
