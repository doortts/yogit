# Sidebar Ref Tree Design

## Goal

Replace the flat LOCAL, REMOTE, and TAGS lists in the timeline sidebar with
collapsible trees that follow slash-separated Git ref names. Keep ref selection,
current-branch highlighting, branch birth labels, and filtering intact.

## Scope

- Add a leading type icon and disclosure control to the LOCAL, REMOTE, and TAGS
  section headers.
- Split local branches, remote branches, and tags on `/` and render intermediate
  segments as folders.
- Let users independently collapse sections and folders. All sections and folders
  start expanded when a repository opens.
- Show the ten newest tags initially. Put any remaining tags behind one
  `나머지 N개` row that expands and collapses the complete tag list.
- Preserve the existing ref click behavior: a leaf selects its decorated commit,
  while a section or folder only changes expansion.
- Keep all expansion state in the current timeline session. Do not add persisted
  settings.

## Data Model

`RepoRefs` will carry an optional creator timestamp for every tag in addition to
its current flat name and tip maps. `GitRepository.loadRefs()` will read ref name,
object SHA, and creator date from one `git for-each-ref` command. Git's
`creatordate` gives annotated tags their tagger date and lightweight tags the
referenced object's date.

The sidebar will convert each ref bucket into a small immutable tree:

- Intermediate slash-separated segments become folder nodes.
- The final segment becomes a selectable ref leaf that retains the complete ref
  name.
- Siblings are ordered by their existing bucket rules. Local branches keep the
  checked-out branch first and then follow timeline proximity. Tags are ordered
  by creator timestamp descending, with undated tags placed last and ordered by
  complete name. A folder takes the position of its first descendant in that
  ordered flat list.
- A segment can hold both a complete ref and child segments. Its disclosure
  control toggles the children, while its label selects the complete ref, so no
  Git ref disappears and no duplicate row is needed.

Remote names use the same rule, so `origin/feature/login` renders as
`REMOTE → origin → feature → login`.

## Interaction and Presentation

Section headers use these icons:

- LOCAL: computer
- REMOTE: cloud
- TAGS: tag

Each section and folder has a disclosure arrow. Folder rows use a folder icon;
leaves use a branch or tag icon. Indentation increases once per tree level.
Section headers show their total leaf count.

The current local branch keeps its existing accent background and branch birth
label. A ref leaf continues to expose the existing `sidebar-ref-<full-name>` key
and selects the same timeline row as before.

When tags exceed ten, the collapsed view contains only the ten newest leaves and
the `나머지 N개` control. Expanding that control shows every tag while retaining
the tree structure. Collapsing it returns to the newest ten.

Filtering searches complete ref names across all refs, including tags hidden by
the ten-item limit. While a filter is active, every ancestor of a matching leaf
is shown and expanded without overwriting the user's stored section or folder
state. Clearing the filter restores the previous expansion state.

## State and Data Flow

1. `TimelineScreen` loads `RepoRefs` beside the first history page as it does now.
2. The repository returns the existing ref buckets plus tag creator timestamps.
3. The sidebar orders each bucket and derives its tree during rendering.
4. Section, folder, and tag-overflow expansion sets live in
   `_TimelineScreenState`.
5. Ref leaves call the existing `_selectRef` path with their complete names.

The tree builder will be independent of Flutter widgets so ordering, collisions,
and the ten-tag projection can be tested directly.

## Error Handling

- A failed ref query keeps the existing behavior: the sidebar remains empty and
  the timeline still loads.
- A missing or invalid tag timestamp does not remove the tag. The tag sorts after
  dated tags.
- An empty bucket still shows its section header with count zero.
- Filtering with no matches leaves the three section headers visible and shows no
  leaf rows.

## Testing

- Repository tests verify creator-date parsing for annotated and lightweight tag
  output, plus safe handling of missing dates.
- Tree unit tests cover slash grouping, stable sibling order, and a ref that is
  both a leaf and a folder prefix.
- Widget tests cover section icons and counts, default expansion, independent
  section and folder toggles, indentation, current-branch styling, and ref
  selection.
- Widget tests verify that only the ten newest tags appear initially, the
  `나머지 N개` row expands and collapses them, and filtering can find a hidden
  tag without changing saved expansion state.
- Existing sidebar resize, branch birth, timeline selection, and full test suites
  remain green.
