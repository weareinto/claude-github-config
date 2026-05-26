---
name: branch
description: Create a working branch following the repo naming convention, optionally linked to one or more GitHub issues
---

Create a local working branch following the repo's `<type>/<github_username>/<slug>` convention, optionally linked to one or more GitHub issues. Issue numbers are stashed in the branch's local git config so `/pr-description` and `/pr-submit` can pick them up later and emit `Closes #N` lines on the PR.

## Arguments

```
/branch [<type>] [<slug>] [--issues <N>[,<N>...]] [--link]
```

- `type` (optional positional): one of `feature`, `chore`, `fix`. If omitted, ask the user.
- `slug` (optional positional): kebab-case description, e.g., `add-llm-billing`, `fix-jwt-expiry`. If omitted, ask the user (or derive from issue titles when `--issues` is given).
- `--issues` (optional): comma-separated issue numbers this branch will close. They'll be stored in `git config branch.<name>.linkedIssues` and consumed by `/pr-description` later.
- `--link` (optional flag): also create the **first** issue's GitHub *Development* sidebar link via `gh issue develop`. Off by default — most teams are happy waiting for the PR's `Closes #N` line to populate the sidebar at PR-open time. **Required** when following this repo's pre-implementation checklist (CONTRIBUTING.md § 4, step 3).

Examples:
- `/branch` — ask everything.
- `/branch feature add-llm-billing` — create `feature/<me>/add-llm-billing` off `main`, no issue linkage.
- `/branch chore refactor-tests --issues 54` — create the branch and stash `54` for the PR.
- `/branch fix jwt-expiry --issues 42,77 --link` — same, but also register the branch in issue #42's Development sidebar immediately.

## Branch naming

`<type>/<github_username>/<slug>`:

- `<type>`: `feature`, `chore`, or `fix`. Documentation/refactor/test/perf/CI work goes under `chore/`.
- `<github_username>`: from `gh api user --jq .login` — never hard-code.
- `<slug>`: lowercase kebab-case, no leading/trailing dash, no spaces.

A branch is independent of issues — it may close one, several, or none. The `--issues` arg is a *convenience* that wires up the eventual PR's `Closes #N` lines; it does not change the branch's identity.

## Steps

1. Resolve `type` and `slug`:
   - If `--type` was passed positionally, use it. Otherwise ask.
   - If `--slug` was passed positionally, use it. Otherwise:
     - If `--issues` was given and the first issue has a clean title, propose a slug derived from it (e.g., `[Feature] Add LLM billing` → `add-llm-billing`).
     - Otherwise ask.
   - Validate `slug` matches `^[a-z0-9]+(-[a-z0-9]+)*$`.

2. Resolve the GitHub username:
   ```
   gh api user --jq .login
   ```

3. Build the branch name: `<type>/<username>/<slug>`. If a local branch with that name already exists, ask the user whether to switch to it or pick a different slug — never silently overwrite.

4. **Confirm before creating.** Show the user:
   - The full branch name.
   - The base branch (`main`).
   - The list of issues to be stashed (if any), and whether `--link` will register the first one in GitHub's Development sidebar.

   Wait for explicit go-ahead.

5. Make sure the working tree is clean and we're up to date:
   ```
   git fetch origin
   git status
   ```
   If there are uncommitted changes, ask the user how to proceed (stash, commit elsewhere, abort).

6. Create the branch:
   - **Without `--link`** (or no issues passed): create locally off `origin/main`:
     ```
     git checkout -b <branch> origin/main
     ```
   - **With `--link` and at least one issue**: let `gh` create the linked branch on the remote and check it out:
     ```
     gh issue develop <FIRST_ISSUE> --name <branch> --base main --checkout
     ```
     `gh issue develop` only links one issue per branch — additional issues from `--issues` will be linked at PR-open time via `Closes #N`.

7. Push the branch to `origin` and set upstream:
   ```
   git push -u origin <branch>
   ```
   This is unconditional — pushing a fresh branch costs nothing, and it makes the branch visible to teammates and to CI immediately. If `--link` was used, the remote branch already exists (from `gh issue develop`), so this is effectively a no-op that just confirms the upstream tracking.

8. If `--issues` was passed, stash the list in the branch's local git config:
   ```
   git config --local branch.<branch>.linkedIssues "<N>,<N>,..."
   ```
   `/pr-description` reads this when `--closes` isn't passed explicitly.

9. Print a summary:
   - The branch name, base, and the fact that it was pushed to `origin`.
   - The stashed issue list, if any.
   - Whether the first issue got an early sidebar link.
   - Next steps: do the work, then run `/pr-submit` to open the PR (which will see the stashed issues and pass them along).

## Notes

- Pushing the branch is independent of opening a PR — `/branch` pushes immediately so the branch is visible on GitHub and CI can warm up; `/pr-submit` handles the actual PR creation later.
- Branch protection on `main` blocks direct pushes to `main`, but feature/chore/fix branches push freely — `/branch` always branches off `main` (never the current branch), so you can run it from any branch state.
- `--link` is opt-in because the early sidebar visibility is only useful for some teams and the PR's `Closes #N` populates the link anyway. Use it when reviewers/PMs need to see "someone is on this" before the PR exists.
- `gh issue develop` requires write access to the repo. If it fails (forks, restricted permissions), fall back to `git checkout -b` and skip the early link — the PR's `Closes #N` will still work.
