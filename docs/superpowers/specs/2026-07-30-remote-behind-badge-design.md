# Remote-Behind Branch Badge Design

## Goal

Show when the local branch selected as the timeline's working target is behind
its configured upstream branch, and keep that information current without
making the sidebar wait on the network.

## Approved behavior

- Load cached refs immediately when a repository opens.
- Refresh the selected branch's upstream remote in the background when the
  repository opens, when the selected branch changes, and every three minutes
  while the app is active.
- Skip a scheduled refresh when another refresh is already running.
- Stop checking when the timeline is disposed. A scheduled check does no work
  while the app is not active.
- Compare the selected local branch with its configured upstream, rather than
  assuming an `origin/<same-name>` branch.
- Show only the upstream-only commit count. When the count is greater than zero,
  place the number in red immediately to the right of the selected branch name
  in the `LOCAL` sidebar section.
- Give the number the tooltip
  `원격보다 N개 커밋 뒤처져 있습니다`.
- Show no badge when the branch has no upstream or the count is zero.

This deliberately does not add ahead counts, divergence badges, status for
every local branch, a user-configurable interval, or a manual refresh control.

## Git semantics

Git's user-facing commands describe the same state as follows:

- `git status -sb`: `main...origin/main [behind 3]`
- `git branch -vv`: `[origin/main: behind 3]`
- A diverged branch may be shown as `[ahead 2, behind 3]`.

These values compare local refs with locally cached remote-tracking refs. A
fetch must run first when the application needs the remote server's latest
state.

## Data flow

Extend the existing `GitRepository.loadRefs()` query rather than adding a
second branch-discovery path.

1. `for-each-ref` also returns each local branch's upstream short name, upstream
   remote name, and upstream tracking text.
2. `RepoRefs` stores the selected branch data needed by the sidebar: upstream
   name, remote name, and behind count.
3. `TimelineScreen` renders cached `RepoRefs` immediately.
4. A background refresh fetches only the selected branch's configured upstream
   remote with pruning enabled.
5. After the fetch finishes, `TimelineScreen` calls the existing ref loader
   again and replaces the cached sidebar state in one update.

The tracking parser must accept Git's behind-only and diverged forms, while
ignoring ahead-only, up-to-date, gone, and missing-upstream values.

## Refresh lifecycle

`TimelineScreen` owns one three-minute `Timer.periodic` and one in-flight
refresh future.

- Start the timer in `initState`.
- Request an immediate background refresh after the first cached ref load.
- Request another immediate refresh when `_baseBranch` changes.
- Before each request, confirm that the app is active, the selected branch has
  an upstream remote, and no refresh is already running.
- Cancel the timer in `dispose`.

This keeps scheduling beside the UI state that owns the selected branch and
keeps Git commands inside `GitRepository`.

## Failure handling

- A fetch failure does not clear the current count or block the timeline.
- After a failed fetch, do not reload refs; retain the last successful
  `RepoRefs`.
- Do not show a modal or repeated notification for background network errors.
- A later scheduled check retries normally.
- Guard all asynchronous UI updates with the existing mounted checks.

## Verification

Add focused tests for:

1. Parsing no-upstream, behind-only, ahead-only, and diverged tracking values.
2. Rendering the red count only beside the selected local branch.
3. Rendering the Korean tooltip with the exact count.
4. Starting an immediate refresh and a three-minute periodic refresh.
5. Skipping overlapping and inactive-app refreshes.
6. Preserving the last displayed count after a fetch failure.
7. Cancelling the timer when the timeline is disposed.

Run static analysis and the existing Flutter test suite before integration.
