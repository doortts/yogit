# Merge·Rebase Manual Test Fixture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a resettable local and remote Git fixture for manually testing Yogit's Merge and Rebase preview, apply, and undo flows.

**Architecture:** Initialize one local repository at `/Users/doortts/repos/pr-test-yogit-fixture` and connect it to the empty `pr-test` repository. Keep one shared `main`, two local comparison branches, two remote-only comparison branches, and three immutable fixture tags. A committed shell script restores every local branch without changing the remote.

**Tech Stack:** Git, POSIX shell, Yogit desktop app

## Global Constraints

- Remote repository: `https://oss.navercorp.com/sw-chae/pr-test`
- Local repository: `/Users/doortts/repos/pr-test-yogit-fixture`
- Do not modify Yogit source code.
- Do not force-push the remote.
- Do not delete untracked files during reset.
- Use deterministic fixture author data and commit dates.

---

### Task 1: Create and publish the fixture history

**Files:**
- Create: `/Users/doortts/repos/pr-test-yogit-fixture/README.md`
- Create: `/Users/doortts/repos/pr-test-yogit-fixture/shared.txt`
- Create: `/Users/doortts/repos/pr-test-yogit-fixture/base.txt`
- Create: `/Users/doortts/repos/pr-test-yogit-fixture/reset-fixture.sh`
- Create on branches: `/Users/doortts/repos/pr-test-yogit-fixture/clean/*`
- Create on branches: `/Users/doortts/repos/pr-test-yogit-fixture/conflict/*`

**Interfaces:**
- Consumes: empty `https://oss.navercorp.com/sw-chae/pr-test`
- Produces: `main`, `local/clean`, `local/conflict`, `origin/remote/clean`, `origin/remote/conflict`, and `fixture/*` tags

- [ ] **Step 1: Recheck the destructive-action boundary**

Run:

```bash
test ! -e /Users/doortts/repos/pr-test-yogit-fixture
git ls-remote --heads https://oss.navercorp.com/sw-chae/pr-test
```

Expected: the local path does not exist and the remote has no heads. Stop instead of overwriting either location if this expectation is false.

- [ ] **Step 2: Initialize the repository**

Run:

```bash
mkdir /Users/doortts/repos/pr-test-yogit-fixture
git init -b main /Users/doortts/repos/pr-test-yogit-fixture
git -C /Users/doortts/repos/pr-test-yogit-fixture remote add origin https://oss.navercorp.com/sw-chae/pr-test
git -C /Users/doortts/repos/pr-test-yogit-fixture config user.name "Yogit Fixture"
git -C /Users/doortts/repos/pr-test-yogit-fixture config user.email "fixture@yogit.test"
```

Expected: `git remote -v` lists the requested URL for fetch and push.

- [ ] **Step 3: Create the shared root commit**

Create `shared.txt` with `shared value from root`, `base.txt` with a short fixture description, and a `README.md` that identifies the branch roles. Create this reset script:

```sh
#!/bin/sh
set -eu

git fetch origin --prune --tags
git switch main
git reset --hard fixture/base
git branch -f local/clean fixture/clean
git branch -f local/conflict fixture/conflict
git branch -D remote/clean remote/conflict 2>/dev/null || true
git status --short --branch
```

Run:

```bash
chmod +x reset-fixture.sh
git add README.md base.txt shared.txt reset-fixture.sh
GIT_AUTHOR_DATE=2026-07-28T09:00:00+09:00 GIT_COMMITTER_DATE=2026-07-28T09:00:00+09:00 git commit -m "chore: initialize Yogit preview fixture"
```

Expected: the worktree is clean and `main` has one root commit.

- [ ] **Step 4: Create the clean comparison history**

Create `local/clean` from the root commit. Make three commits dated 2026-07-29 that add `clean/one.txt`, add `clean/two.txt`, and update `clean/one.txt` while adding `clean/three.txt`. Use these subjects in order:

```text
feat: add clean preview file
docs: add clean preview notes
fix: finalize clean preview result
```

Tag the final commit as `fixture/clean`.

Expected: `git rev-list --count main..local/clean` prints `3` before `main` diverges.

- [ ] **Step 5: Create the conflicting comparison history**

Create `local/conflict` from the root commit. Make three commits dated 2026-07-30:

1. Add `conflict/step-one.txt` with subject `feat: add conflict preview setup`.
2. Change `shared.txt` to `shared value from conflict branch` with subject `feat: change shared value on topic`.
3. Add `conflict/step-three.txt` with subject `docs: add pending conflict follow-up`.

Tag the final commit as `fixture/conflict`.

Expected: the second commit is the first commit that conflicts when rebased onto the final `main`.

- [ ] **Step 6: Finish the base branch**

Switch to `main`, change `shared.txt` to `shared value from main`, and add `main-only.txt`. Commit both files with subject `feat: change shared value on main`, dated 2026-07-31, then tag the commit as `fixture/base`.

Expected: `main` has one commit that is not in either comparison branch.

- [ ] **Step 7: Publish remote-only branches and tags**

Run:

```bash
git push origin main
git push origin fixture/clean:refs/heads/remote/clean
git push origin fixture/conflict:refs/heads/remote/conflict
git push origin refs/tags/fixture/base refs/tags/fixture/clean refs/tags/fixture/conflict
git fetch origin --prune --tags
```

Expected: the remote contains `main`, `remote/clean`, and `remote/conflict`; it does not contain `local/clean` or `local/conflict`.

- [ ] **Step 8: Commit the fixture deliverable**

No additional commit is needed: the executable reset script and README are part of the shared root commit, so every branch already contains them.

### Task 2: Verify reset, preview topology, and handoff

**Files:**
- Verify: `/Users/doortts/repos/pr-test-yogit-fixture/reset-fixture.sh`
- Reference: `/Users/doortts/repos/yogit/docs/superpowers/specs/2026-07-31-merge-rebase-manual-test-fixture-design.md`

**Interfaces:**
- Consumes: branches and tags from Task 1
- Produces: verified fixture path and six manual test scenarios

- [ ] **Step 1: Verify branch and tag targets**

Run:

```bash
git rev-parse main fixture/base
git rev-parse local/clean fixture/clean origin/remote/clean
git rev-parse local/conflict fixture/conflict origin/remote/conflict
git status --short --branch
```

Expected: each group resolves to identical SHA values and the worktree is clean on `main`.

- [ ] **Step 2: Verify clean Merge and conflicting Merge**

Run:

```bash
git merge-tree --write-tree main local/clean
git merge-tree --write-tree main local/conflict
```

Expected: the clean command exits 0 with a tree SHA. The conflict command exits nonzero and names `shared.txt`.

- [ ] **Step 3: Verify clean and conflicting Rebase in disposable worktrees**

Create one temporary detached worktree per branch. Rebase `local/clean` onto `main` and expect success. Rebase `local/conflict` onto `main` and expect the operation to stop at `feat: change shared value on topic` with `shared.txt` unmerged. Abort the conflict and remove both temporary worktrees.

- [ ] **Step 4: Verify the reset script**

Move `local/clean` to `main`, run `./reset-fixture.sh`, and compare all local branch SHAs with their fixture tags again.

Expected: every local branch returns to its fixture tag; `remote/clean` and `remote/conflict` do not exist as local branches; untracked files remain untouched.

- [ ] **Step 5: Prepare the manual test handoff**

Give the user the local repository path and the reset command. Document these six scenarios with exact base and comparison choices:

1. Local clean Merge: `main` ← `local/clean`
2. Local clean Rebase: `local/clean` onto `main`
3. Local conflicting Merge: `main` ← `local/conflict`
4. Local conflicting Rebase: `local/conflict` onto `main`
5. Remote clean Merge: `main` ← `origin/remote/clean`
6. Remote clean Rebase: `origin/remote/clean` onto `main`

For each scenario, include expected preview state, file or commit to inspect, actual-apply result, undo result, and the instruction to run `./reset-fixture.sh` before continuing.
