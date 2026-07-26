# Full Diff Workspace Design

## Goal

Turn Yogit's Full Diff screen into a code-review workspace without losing its
fast commit and file navigation.

The default experience is a list of focused Hunk blocks. A user can open any
Hunk in the complete file without adding a separate Inline mode. Settings decide
whether a new Full Diff screen starts with Hunk blocks or with the complete file
focused on its first change.

## Approved Content Modes

The file header exposes four primary modes:

- `Hunk`
- `File`
- `Blame`
- `History`

There is no separately labeled Inline mode.

### Hunk

Hunk is the default mode and the primary review surface. Each parsed Git hunk is
one selectable block containing:

- a friendly old/new line-range heading;
- three context lines from Git on either side of a change;
- addition and deletion rows;
- a change count such as `2 / 7`;
- a `View in full file` action.

Raw `diff --git`, `index`, `---`, `+++`, and `@@` patch lines remain in the
model but are not rendered as source rows. The Hunk heading presents the parsed
range and function context instead.

Selecting `View in full file` switches to File mode and focuses the complete
file on that Hunk's first changed line. Returning to Hunk mode restores the same
Hunk as the active block.

Hunk rows use a normal one-column presentation by default. A `Split` toggle
pairs deletions and additions in two columns. Split is a Hunk presentation
option, not a separate content mode.

### File

File shows the complete file on the result side of the selected comparison.
Added and replaced result lines retain subdued backgrounds. A pure deletion has
no result line, so File shows a deletion marker between the adjacent surviving
lines and anchors focus to that marker. A deleted file uses its parent content
and marks the removed lines. The currently focused Hunk receives a stronger
focus marker.

Previous/next change controls move between Hunk anchors while staying in File
mode. They scroll by semantic line anchor rather than by a stored pixel offset,
so line wrap and syntax highlighting do not change the target.

When File mode was opened from a Hunk block, it focuses that Hunk. When File is
the configured initial mode, it focuses the first textual Hunk. A file with no
textual Hunk starts at the top and shows its applicable empty, binary, or
unsupported-encoding state.

### Blame

Blame uses the same complete-file rows as File and adds commit and author
information. Entering Blame preserves the active Hunk anchor.

### History

History lists the commits that changed the selected path. A history selection
may change the inspected commit only after the user explicitly activates it;
moving keyboard focus through the list does not replace the current diff.

## Initial View Setting

`AppSettings` gains:

```dart
enum FullDiffInitialView { hunk, fullFile }
```

`FullDiffInitialView.hunk` is the default. The JSON key is
`fullDiffInitialView`, with values `hunk` and `fullFile`. Missing or damaged
values fall back to `hunk`.

The Settings screen adds a `Full Diff` section with one radio group:

- `Hunk blocks` — open the diff as focused Hunk blocks.
- `Full file focused on first change` — open the complete file and focus its
  first changed line.

The setting seeds a Full Diff session when the screen opens. Manual mode changes
inside that screen remain in effect while the user moves between commits and
files. A new file resets the active anchor to its first Hunk but does not
override a manual Hunk/File choice. A settings change affects the next Full Diff
screen and does not replace the mode of an already open screen.

## Screen Layout

The screen has two fixed header rows above the existing three-pane body.

### File Header

The first row contains:

- selected path;
- file status and addition/deletion counts;
- `Open in editor`;
- `Hunk`, `File`, `Blame`, and `History`;
- detected content status: `UTF-8`, `Binary`, or `Unsupported encoding`.

The path and file statistics remain visible while content scrolls.

### Diff Toolbar

The second row contains:

- focus mode;
- previous and next change controls with the current change number;
- a `Split` toggle, enabled only in Hunk mode;
- a fixed dropdown trigger named `diff 알고리즘`;
- the selected algorithm in an adjacent always-visible value such as
  `Git setting` or `Histogram`;
- ignore-whitespace toggle;
- line-wrap toggle.

The algorithm menu contains `Git setting`, `Myers`, `Minimal`, `Patience`, and
`Histogram`. Choosing an item changes the adjacent value but never replaces the
trigger name `diff 알고리즘`.

### Three-Pane Body

The body keeps Yogit's current structure:

1. nearby commits;
2. selected commit details and changed files;
3. the selected content mode.

Focus mode hides both navigation panes and gives the body width to the content
pane. Leaving focus mode restores the saved widths and the previous commit and
file selections.

At narrow widths, the nearby-commits pane collapses first and the changed-files
pane collapses second. The content pane never shrinks below its current minimum
width.

## Delivery Phases

The phases follow their actual data dependencies. Every phase leaves the screen
usable and can ship independently.

### Phase 1: Diff Foundation and Hunk Reader

- Introduce the shared document, Hunk, row, and anchor models.
- Move Full Diff session state and request ordering out of `DiffScreen`.
- Preserve raw Git metadata while rendering friendly Hunk headings.
- Add the two-level file header and toolbar.
- Make Hunk blocks the default surface.
- Add focus mode and previous/next Hunk navigation.
- Add line wrap and ignore-whitespace support.
- Add the fixed `diff 알고리즘` trigger and visible selected value.
- Preserve merge-parent selection, resizable columns, loading behavior, cache
  behavior, text selection, and existing keyboard navigation.
- Add the byte-preserving Git command boundary needed by later file modes.

Phase 1 does not expose the Full File setting because File mode is delivered in
Phase 2.

### Phase 2: Full File and Rich Diff Rendering

- Add File mode and `View in full file` on every Hunk block.
- Add the Full Diff initial-view setting.
- Classify and expose UTF-8, binary, and unsupported-encoding content states.
- Add syntax highlighting.
- Add word-level highlighting inside paired deletion/addition rows.
- Add the Hunk-only Split toggle.
- Keep line-number gutters continuous through context and change rows.
- Render a striped placeholder where one Split side has no corresponding line.
- Add a minimap with Hunk marks and a visible viewport indicator.
- Add large-file fallbacks and semantic scroll anchors.

### Phase 3: Investigation and External Workflow

- Add Blame mode.
- Add History mode with rename following.
- Add `Open in editor`.

## Component Boundaries

No state-management framework is added. Full Diff uses one dedicated controller
and focused widgets.

### `FullDiffSessionController`

The controller owns:

- selected commit, parent, and path;
- selected content mode;
- selected Hunk anchor;
- Split, wrap, ignore-whitespace, and algorithm choices;
- per-resource loading and errors;
- stale-request generation counters;
- caches for committed content.

It exposes immutable session snapshots and commands. `DiffScreen` listens to the
controller and arranges the screen but does not coordinate Git requests itself.

### Data Models

`DiffDocument` retains:

- patch metadata;
- source and result paths;
- file status;
- content status;
- ordered `DiffHunk` objects;
- flat rows for rendering and navigation.

`DiffHunk` retains:

- stable Hunk index;
- old and new ranges;
- optional function context;
- context and change rows;
- first old and new changed lines.

`DiffAnchor` identifies a Hunk and its old/new source line. It is the common
currency for previous/next navigation, File focus, Blame focus, minimap
selection, and restoring the active Hunk.

### Widgets

- `DiffFileHeader` renders file identity and primary content modes.
- `DiffToolbar` renders Hunk navigation and display controls.
- `DiffNavigationPanes` owns the two resizable navigation columns.
- `HunkListView` renders lazy Hunk blocks.
- `FullFileView` renders complete-file rows and changed-line overlays.
- `DiffMinimap` renders Hunk positions and the viewport.
- `FileHistoryView` renders path history.

Widgets receive state and callbacks. They do not run Git commands or maintain
duplicate selections.

## Git and Content Boundary

The current string-only process boundary is split into two explicit paths:

- text Git commands decode stdout as UTF-8 and return structured failures;
- file-content commands retain stdout bytes until content classification and
  decoding finish.

The first release recognizes:

- valid UTF-8 text;
- Git-reported binary content;
- non-binary content that is not valid UTF-8, shown as
  `Unsupported encoding`.

Unsupported text is not mislabeled as binary. Converting arbitrary encodings is
out of scope.

Repository operations cover:

- `git diff --unified=3` with the selected algorithm and optional
  ignore-whitespace argument;
- complete committed content through Git object lookup;
- working-tree content through direct file bytes;
- `git blame --line-porcelain`;
- working-tree blame through `git blame --contents` against HEAD;
- path history through `git log --follow`.

Each resource has its own cache key. Patch keys contain commit, parent, path,
algorithm, and ignore-whitespace state. File keys contain commit, path, and
source side. Blame keys contain commit and path. History keys contain the
rename-following path. Working-tree diff and file results bypass the long-lived
cache so changing a file cannot leave stale content on screen.

## File-State Behavior

| Selected state | Hunk comparison | File and focus source | Open in editor |
| --- | --- | --- | --- |
| Modified commit file | Parent to commit | Commit result path | Working-tree result path when present |
| Added commit file | Empty file to commit | Added commit content | Working-tree result path when present |
| Renamed or copied file | Old path to result path | Result path, with history following the old path | Working-tree result path when present |
| Deleted commit file | Parent to empty file | Parent content, labeled `Deleted in selected commit` | Disabled |
| Merge commit file | Chosen parent to merge result | Merge result; changing parent rebuilds anchors | Working-tree result path when present |
| Working-tree file | HEAD to working tree | Current disk content | Current disk path |
| Binary file | Metadata-only Hunk state | No text renderer | Enabled when a working-tree path exists |
| Unsupported encoding | Metadata and changed-byte state | No decoded text renderer | Enabled when a working-tree path exists |

Changing a merge parent resets the active anchor to the first Hunk. The File
content of the merge result may remain the same, but its highlights and Hunk
anchors reload for the new comparison.

Blame uses the result commit for modified, added, renamed, copied, and merge
files. A deleted file uses its parent content and parent blame. Working-tree
Blame compares the current disk content against HEAD so uncommitted lines remain
visible as working-tree lines. Binary and unsupported-encoding files do not
offer Blame. History remains available for deleted files and follows renames
across the old and result paths.

## Rendering Rules

### Typography and Color

- Use the normal UI font for navigation and controls.
- Use D2Coding for source, paths, hashes, and line numbers.
- Remove the current screen-wide monospace theme.
- Preserve syntax colors on text.
- Encode additions and deletions with subdued backgrounds, gutters, and
  explicit `+`/`−` markers.
- Give the focused Hunk a separate border or gutter marker instead of replacing
  its diff colors.

### Syntax and Word Highlighting

Language selection comes from the result path. The first release must support
Pascal/Delphi because the DRL acceptance fixture uses `.pas` files. Dart, Swift,
Kotlin/Java, JavaScript/TypeScript, Python, C/C++, Rust, Go, shell, JSON, YAML,
and XML are supported when the chosen highlighting engine recognizes them.
Unknown extensions fall back to plain text.

Syntax highlighting runs after Git row matching and cannot change line pairing.
Word highlighting runs only on paired deletion/addition rows and applies a
background over the syntax-colored text.

Word matching tokenizes whitespace and punctuation boundaries. A line with more
than 512 tokens or 20,000 characters falls back to row-level highlighting.

### Scroll and Minimap

Every changed range has a widget key derived from `DiffAnchor`. Navigation and
minimap actions scroll the anchor into view instead of guessing a pixel offset.
This remains correct when wrapped rows change height.

Minimap marks use source-line ratios. The viewport indicator uses the current
scroll extent. Selecting a mark targets the nearest Hunk anchor.

## Performance and Large Files

Hunk blocks and complete-file rows are built lazily. The UI does not construct
an entire large file as one eager `Column`.

Normal rich rendering applies while the decoded file is at most 2 MiB and
50,000 lines.

Large-file mode applies above either limit:

- syntax and word highlighting are disabled;
- wrap defaults off;
- Hunk navigation and the minimap remain available;
- rows remain virtualized.

Files above 10 MiB or 200,000 lines do not render complete text inside Yogit.
The screen explains the limit and keeps metadata, Hunk summary, History, and
Open in editor available where applicable.

Hunk blocks remain individually selectable. Large-file mode does not promise a
single selection spanning unloaded blocks.

## Keyboard and Accessibility

Keyboard commands use focus-aware `Shortcuts` and `Actions` rather than a
single screen-wide arrow handler.

When a menu, radio group, or selectable text control owns focus, it receives its
native keys. Otherwise:

- Up/Down selects files.
- Command-Up/Command-Down selects nearby commits.
- Option-Up/Option-Down moves between Hunk anchors.
- Command-Shift-F toggles focus mode.
- Escape returns to the timeline.

All actions expose semantic labels and selected states. The algorithm trigger
and its adjacent value are read as one control. Focus mode, Split, wrap, and
ignore-whitespace expose pressed state.

## Loading and Errors

- Changing algorithm or ignore-whitespace keeps the last successful Hunk
  document visible with a loading indicator.
- A failed option change restores the last successfully displayed options.
- File, Blame, and History have separate loading and error states.
- A failure in one mode does not clear successful content in another mode.
- Stale results from an earlier commit, parent, or path cannot replace the
  current session snapshot.
- Empty diffs show a no-changes state.
- Deleted, binary, unsupported, and oversized files use the behavior in the
  file-state and performance sections.
- `Open in editor` first uses a resolvable `VISUAL` or `EDITOR` executable and
  otherwise asks macOS to open the working-tree path with its associated
  application. Launch failures appear beside the action without replacing the
  current content.

## Verification

### Unit Tests

- settings round-trip, missing values, and damaged-value fallback to Hunk;
- Git arguments for every algorithm and ignore-whitespace combination;
- patch metadata, Hunk ranges, function context, and Hunk anchors;
- modified, added, renamed, deleted, merge, and working-tree source selection;
- UTF-8, binary, and unsupported-encoding classification from bytes;
- Split pairing and missing-side rows;
- word spans and the 512-token/20,000-character fallback;
- minimap source-line positions;
- committed cache keys and working-tree cache bypass;
- complete-file, blame, and rename-following history parsing.

### Widget Tests

- Settings shows Hunk as the default and persists both initial-view choices.
- A new Full Diff screen opens in the configured mode.
- Manual Hunk/File changes survive file and commit navigation in one session.
- Every Hunk block opens File at its own anchor and returns to the same Hunk.
- The fixed `diff 알고리즘` trigger always shows the selected adjacent value.
- Focus mode collapses and restores navigation widths.
- Split changes Hunk presentation without running Git again.
- Previous/next navigation works in Hunk, File, and Blame.
- Wrap and minimap navigation keep the same semantic target.
- Large and oversized files use their specified fallback.
- Mode-specific loading, stale requests, binary states, and failures remain
  isolated.
- Menus and text selection retain their native keyboard behavior.

### Manual DRL Acceptance Fixture

Use repository `/Users/doortts/repos/drl` with:

- commit `40aff6d75bd16c5ccd9d45de615df8e9cbbb9fb0`;
- path `src/drlgfxio.pas`;
- default parent;
- nine expected Hunk blocks from the current fixture.

Acceptance checks:

- Hunk headings correspond to the nine Git ranges.
- `View in full file` focuses the matching Pascal source line.
- Pascal syntax and word-level changes remain readable.
- Previous/next and minimap navigation visit the same nine anchors.
- Hunk and Full File initial settings open at the expected first anchor.
- Split pairs deletion and addition rows without changing Hunk count.

Rename, deletion, binary, unsupported-encoding, merge-parent, working-tree, and
large-file behavior use deterministic test fixtures rather than mutable
repository history.

## Non-Goals

- A separately labeled Inline mode
- Editing, staging, discarding, or committing inside the reader
- Merge-conflict resolution
- Arbitrary character-set conversion
- User-defined syntax themes
- User-defined toolbar layouts
- Persisting manual Hunk/File changes beyond the configured initial view
- Selecting across unloaded blocks in oversized files
