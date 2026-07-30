# HEAD Badge and Initial Base Branch Design

## Goal

Make the sidebar's checked-out branch state unambiguous and start each newly
opened timeline from that checked-out branch.

## Approved behavior

- Remove the full-row background from the checked-out local branch.
- Show a compact `HEAD` badge immediately after its branch name.
- Show the badge only for `RepoRefs.current`.
- Keep the timeline base-branch selector independent from the checked-out
  branch after startup.
- On a timeline's first ref load, choose `RepoRefs.current`; fall back to the
  first local branch when Git reports no current branch.
- Do not restore a saved base branch over that initial choice when settings
  finish loading.
- Preserve a base branch the user selects during the current timeline session,
  including ref reloads and remote refreshes.
- Preserve a selection made while settings are still loading.

No new setting, state service, dependency, or Git command is needed.

## UI

The branch-name row contains, in order:

1. branch name;
2. `HEAD` badge when checked out;
3. remote-behind count when applicable.

The `HEAD` badge uses the branch's existing graph color for its outline and
text. A tooltip says `현재 체크아웃된 브랜치입니다`.

## State flow

`TimelineScreen._loadRefs()` distinguishes its first ref load from later
reloads:

- first load: resolve from `RepoRefs.current`;
- later loads: resolve from `_baseBranch`.

When `preferredBranchReady` changes from false to true, the screen keeps its
already resolved checked-out branch unless the user made a pending selection.
Later user-driven preference changes continue to use the existing update path.

## Verification

- A checked-out branch has a `HEAD` badge and no row fill.
- Other local branches have no `HEAD` badge.
- A stale saved base branch does not replace the checked-out branch at startup.
- A user selection made during the session survives a ref reload.
- A selection made before settings finish loading still wins.
