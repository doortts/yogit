# Remote Branch Preview Local Apply Design

**Date:** 2026-07-31

## Goal

Allow Merge Preview and Rebase Preview results that include remote-tracking
branches to be applied safely. A preview may read local or remote-tracking refs,
but applying and undoing a result must change local branches only.

Yogit never pushes as part of this workflow. There is no Push confirmation,
`Do not ask again` preference, or related Settings entry.

## Current Behavior

The preview accepts local and remote-tracking refs, but the apply button is
enabled only when both refs are local branches. The Git layer also resolves both
tips through `refs/heads/*`, so a remote-tracking source or destination cannot
reach the existing apply path.

## Decisions

- Remote-tracking refs are read-only inputs.
- Merge changes the local form of the base ref.
- Rebase changes the local form of the comparison ref.
- A remote source does not need a matching local branch.
- A remote destination is mapped to a writable local branch before applying.
- Existing local branches are never reset to a remote SHA.
- Apply, undo, and failure cleanup never change `refs/remotes/*`.
- No Git command in this workflow uses `push`.

## Destination Rules

The operation determines which ref must be writable:

| Preview | Base ref | Comparison ref | Local branch changed |
| --- | --- | --- | --- |
| Merge | local | remote | Existing local base |
| Merge | remote | local or remote | Local form of the base |
| Rebase | local or remote | local | Existing local comparison |
| Rebase | local or remote | remote | Local form of the comparison |

When both refs are local, the current behavior remains unchanged.

### Mapping a Remote Destination

The local candidate is the remote-tracking name without its remote prefix.
For example, `origin/team/feature` maps to `team/feature`.

- If the local candidate does not exist, applying creates it at the remote
  destination tip and records the selected remote ref as its upstream.
- If the local candidate exists at the same SHA, Yogit reuses it.
- If it exists at another SHA, Yogit does not move it. The remote-destination
  preview is replaced with a preview against the current local candidate, and
  the user must confirm that recalculated result.
- An existing local candidate keeps its current upstream configuration.

This prevents a same-named local branch from losing commits or being silently
repurposed.

## Preview and Apply Flow

1. Resolve the selected base and comparison refs and calculate the preview as
   today.
2. Determine the writable destination from the preview mode.
3. If the destination is remote and a different same-named local branch exists,
   switch the destination to that local branch and recalculate the preview.
4. Show the exact local branch that will change in the result card and
   confirmation dialog.
5. Immediately before applying, verify every preview input ref still points to
   the recorded SHA.
6. Create the local destination when it does not exist.
7. Apply the preview result to that local branch.
8. Record enough state to undo the local change exactly.

The existing remote refresh policy is unchanged. Applying does not fetch from or
push to a network remote.

## Merge Apply

The Merge destination is the base branch. The comparison ref may remain a
remote-tracking ref because it is only a merge parent.

Yogit creates the Merge commit from the preview tree, the current local base
tip, and the recorded comparison tip. It then moves only the local base branch
to the Merge commit.

If the selected base was remote, the confirmation and completion views use the
mapped local name:

`origin/main` selected → create or reuse local `main` → apply to local `main`

## Rebase Apply

The Rebase destination is the comparison branch. The base ref may remain a
remote-tracking ref because it is only the new parent.

If the comparison ref was remote, Yogit creates or reuses its local form and
moves only that local branch to the verified virtual tip. The commit-by-commit
focus animation remains unchanged.

## User Interface

The disabled remote-branch message is replaced with a local-only explanation.

- Remote source, local destination:
  `origin/feature는 입력으로만 사용합니다. 실제 변경은 로컬 main에 적용됩니다.`
- Remote destination without a local branch:
  `로컬 feature를 origin/feature에서 만든 뒤 결과를 적용합니다.`
- Existing local destination with another SHA:
  `기존 로컬 feature 기준으로 미리보기를 다시 계산했습니다.`

The apply button always names the writable local destination:

- Merge: `origin/feature를 main에 Merge 실제 적용`
- Rebase: `origin/main 위로 feature Rebase 실제 적용`

The confirmation dialog states that only the named local branch changes and
that no Push is performed. The completion card shows the local branch before
and after SHA and labels the selected remote refs as unchanged.

There is no Push button, Push dialog, or Settings control.

## Apply Result and Undo

The apply result records the one local branch that may change:

- operation mode
- selected base and comparison refs and their preview tips
- applied local branch name
- local branch tip before apply, or no value when the branch was created
- local branch tip after apply
- whether applying created the local branch

Undo first verifies that the local branch still points to the applied SHA.

- For an existing branch, undo moves it back to its recorded previous SHA.
- For a branch created by apply, undo deletes it with an expected-old-SHA
  check.
- If the branch changed after apply, undo stops without moving or deleting it.

Remote-tracking refs are not part of undo because the workflow never changes
them.

## Failure Handling

- If an input ref changed after preview, apply stops and asks for a new preview.
- If an existing local destination changed after recalculation, apply stops.
- If a destination branch is checked out in another worktree, apply reports
  that the branch must be made available instead of forcing the ref.
- If creating a local branch succeeds but applying fails, Yogit deletes that
  branch only when it still points to the expected creation SHA.
- If the current destination branch is checked out, the existing clean worktree
  and no-other-Git-operation checks still apply.
- A local name collision never causes a reset, forced checkout, or upstream
  rewrite.

## Git Layer Changes

The Git layer resolves refs by their real namespace during verification instead
of assuming `refs/heads/*` for both inputs. It resolves a single local apply
target separately from the preview inputs.

The existing compare-and-swap behavior for moving local refs remains the
authority for safe updates. Branch creation and deletion also use expected SHA
checks so cleanup cannot remove later user work.

No new dependency or network integration is required.

## Tests

### Git tests

- Merge from a remote comparison ref into a local base.
- Merge with a remote base creates and updates only its local form.
- Rebase onto a remote base updates the existing local comparison branch.
- Rebase of a remote comparison creates and updates its local form.
- Both selected refs may be remote while only the operation destination is
  localized.
- A different same-named local branch is not reset and forces recalculation.
- Undo restores an existing local destination exactly.
- Undo removes a destination created by apply.
- Apply failure cleans up only an unchanged newly created branch.
- Changed local or remote-tracking tips reject stale previews.
- Recorded Git commands contain no `push`.

### Widget tests

- Remote previews show an enabled apply button when a writable local target can
  be resolved.
- Apply labels and confirmation text name the local destination.
- A newly created local destination is explained before confirmation.
- Recalculation feedback appears when a same-named local branch differs.
- Completion and undo views show local changes and remote refs as unchanged.
- No Push action or Push setting is rendered.

## Out of Scope

- Pushing, force-pushing, or deleting remote branches
- Remembering Push preferences
- Automatically fetching during apply
- Resetting an existing local branch to match a remote branch
- Creating temporary shadow branches when a same-named local branch exists
