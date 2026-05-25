---
name: pr-description
description: Update a GitHub PR description with a summary of changes
---

Update a GitHub pull request description based on the changes in the PR. PRs may or may not be linked to issues — only include the Linked Issues section when there's something to close. When listing issues, use `Closes #` (the convention in this repo's PR template).

## Arguments

```
/pr-description <PR_NUMBER> [--closes <ISSUE_NUMBERS>]
```

- `PR_NUMBER` (required): the pull request number to update
- `--closes` (optional): comma-separated issue numbers this PR closes (e.g., `--closes 123,456`). If omitted, the skill falls back to `git config --local branch.<current>.linkedIssues` (set by `/branch --issues ...`). Pass an explicit empty list (`--closes ""`) to force "no issues linked" even when the branch has stashed issues.

Examples:
- `/pr-description 42` — use the issue list stashed by `/branch`, or none if there isn't one
- `/pr-description 42 --closes 123`
- `/pr-description 42 --closes 123,456,789`
- `/pr-description 42 --closes ""` — force no Linked Issues section

## Steps

1. Gather PR context:
   - `gh pr view <PR_NUMBER>` — title, current description, base branch
   - `git log main..HEAD --oneline` — commits
   - `git diff main..HEAD` — actual diff
   - Parse `--closes` argument if provided

2. Decide whether to update:
   - If the existing description is complete and accurate, do nothing.
   - If sections are missing, the description is the template placeholder, or the description is stale relative to the diff, regenerate.

3. Analyze the changes:
   - What is the user-visible purpose of the change?
   - Are there breaking changes? (API signatures, removed features, behavior shifts.)
   - Resolve which issues to close. Precedence (highest first):
     1. `--closes` if it was passed (use it as-is; an empty string means "no issues").
     2. The branch-local config: `git config --local branch.<current>.linkedIssues` — set by `/branch --issues N,N`.
     3. `Closes #N` / `Fixes #N` / `Resolves #N` mentions in commit messages on this branch.
     4. The branch's existing GitHub-side links (`gh issue develop --list <issue>` per candidate, or the issue's Development sidebar).

4. Write the description using the GitHub REST API — **do not use `gh pr edit`** (it triggers a Projects (classic) deprecation error on this repo and exits 1):

   ```bash
   gh api repos/{owner}/{repo}/pulls/<PR_NUMBER> \
     --method PATCH \
     --field body='<generated body>'
   ```

   Resolve `{owner}/{repo}` from `gh repo view --json nameWithOwner --jq '.nameWithOwner'`.

## PR description format

### Summary (always)

1–3 bullets focused on **why** and **impact**, not implementation:

```markdown
## Summary

- Added X to enable Y.
- Fixed bug where Z would happen under condition W.
```

### Breaking Changes (only if applicable)

```markdown
## Breaking Changes

- `ClassName.method()` now requires a `param` argument.
- Removed deprecated `old_function()` — use `new_function()` instead.
```

### Testing (only when non-obvious)

```markdown
## Testing

- Run `pytest tests/test_auth.py::test_login_returns_token`.
- Manual repro: call `/auth/login` with stale credentials, expect 401.
```

### Linked Issues (only if there are any)

If the PR closes one or more issues:

```markdown
## Linked Issues

Closes #123
Closes #456
```

Use **`Closes #`** — matches the PR template convention. One per line so GitHub auto-closes each. **Omit this section entirely** if the PR is standalone work with no related issues.

## Guidelines

- Be concise. Reviewers should understand the PR in 30 seconds.
- Lead with *why*, since the diff already shows *what*.
- Skip empty sections.
- Bullet points beat paragraphs.
- Do not list every changed file or line.

## Checklist before updating

- [ ] Verified the existing description is incomplete / stale.
- [ ] Summary reflects user-visible impact, not implementation.
- [ ] Breaking changes are flagged if any.
- [ ] If the PR closes issues, every one of them is listed with a `Closes #` line. If not, the Linked Issues section is omitted.
