---
name: pr-submit
description: Create and submit a GitHub PR from the current branch
---

Submit the current changes as a GitHub pull request following this repo's conventions.

## Branch naming

Branches follow `<type>/<github_username>/<short-slug>`:

- `<type>` is one of: `feature`, `chore`, `fix`. Documentation/refactor/test/perf work goes under `chore/`.
- `<github_username>` is the human's GitHub login (e.g., `qutaiba`, `mehdimehni`).
- `<short-slug>` is a kebab-case description, e.g., `add-llm-billing`, `fix-jwt-expiry`.

Example: `feature/qutaiba/add-llm-billing`

A branch is independent of issues — it may map to one issue, several, or none. If it does close issues, list each on its own `Closes #N` line in the PR body.

## Steps

1. Check the current state:
   ```
   git status
   git diff
   git log --oneline -10
   ```

2. If there are uncommitted changes for this PR:
   - Confirm the branch name with the user (or pick one matching the pattern above).
   - If you're on `main`, create and check out the branch.
   - Commit changes — use multiple commits if they're unrelated.

3. Push the branch with `-u`:
   ```
   git push -u origin <branch>
   ```

4. Open the PR as a **draft** so a number is allocated immediately:
   ```
   gh pr create --base main --draft --title "<clear, descriptive title>" --body "<short summary, or empty — /pr-description will fill it in>"
   ```

   Capture the PR number from the output. If the PR closes any issues, you can include `Closes #N` lines in the body now or let `/pr-description` add them.

5. Run the post-PR steps **in this order**:
   1. `/pr-description <PR_NUMBER>` — generate a proper description.
   2. `/changelog <PR_NUMBER>` — generate fragment file(s) in `changelog/`. Commit and push them on the same branch.
   3. `/review <PR_NUMBER>` — run a review on the PR's diff against `main`. Address any actionable findings via new commits on the same branch before moving on. If `/review` errors or is unavailable, surface the error and continue to step 4 — never block on the review tool.
   4. Mark the PR ready for review:
      ```
      gh pr ready <PR_NUMBER>
      ```

6. Return the PR URL to the user.

## Notes

- Don't push directly to `main`. Branch protection blocks it.
- The PR template asks for a changelog-fragment checkbox — `/changelog` handles that automatically.
- If the change has no user-visible impact (pure refactor, internal docs), skip `/changelog` and tick the "doesn't need one" branch of the PR template checkbox.
