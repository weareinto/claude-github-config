---
name: review
description: Review a GitHub PR against the repo's own conventions and general best practices. Auto-discovers project rules from CONTRIBUTING.md, linter configs, and PR templates — no hardcoded project knowledge. Safe to copy to any repo as-is.
---

Review a pull request for correctness, security, and adherence to the repo's own conventions.

## Arguments

```
/review <PR_NUMBER>
```

## Steps

### 1. Gather PR context

```bash
gh pr view <PR_NUMBER> --json number,title,body,baseRefName,headRefName,additions,deletions
gh pr diff <PR_NUMBER>
git log <baseRefName>..<headRefName> --oneline
```

If `gh pr diff` errors (e.g. no GitHub remote), fall back to `git diff <baseRefName>..HEAD`.

### 2. Auto-discover project conventions

Read each of the following if it exists — skip silently if not:

| File / path | What to extract |
|---|---|
| `CONTRIBUTING.md` or `DEVELOPMENT.md` | Coding standards, workflow rules, forbidden patterns |
| `pyproject.toml` (ruff section) | Python lint rules and formatter settings |
| `ruff.toml` | Same |
| `.eslintrc*` / `eslint.config.*` | JS/TS lint rules |
| `prettier.config.*` / `.prettierrc*` | JS/TS format rules |
| `.github/pull_request_template.md` | Expected PR sections |
| `towncrier.toml` or presence of `changelog/` dir | Changelog fragment convention |
| `Makefile` | Test targets (look for `test`, `check`, `lint` targets) |
| `pytest.ini` / `jest.config.*` | Test framework present |

Only read; do not run any linter or test suite.

### 3. Review the diff

Evaluate across four dimensions. Flag only what you can verify from the diff and discovered conventions — no speculation.

**Correctness**
- Logic errors, missing null/bounds checks, off-by-one
- Unhandled error paths or exceptions
- Race conditions or state mutation issues

**Security**
- Hardcoded secrets, tokens, API keys, passwords
- Shell injection (unquoted variables, user-controlled input in commands)
- SQL / XSS / path traversal injection
- Overly broad permissions or exposed sensitive data in logs

**Project conventions** (from step 2)
- Naming, structure, and patterns from CONTRIBUTING.md
- Style violations inferrable from linter config (don't re-run the linter)
- Changelog fragment: if `towncrier.toml` or `changelog/` exists and the change is user-visible, check that a `changelog/<PR>.<type>.md` fragment was added
- Test coverage: if a test framework is detected, check whether new logic has corresponding tests

**PR hygiene**
- Description is complete (not just the template placeholder)
- Linked issues present if the branch name or commits reference one
- No leftover debug code, `TODO`s introduced without a tracking issue, or commented-out blocks

### 4. Output the report

```
## Review: PR #<N> — <title>

### Blocking
- [ ] <concise description> — `<file>:<line>` — <why it matters>

### Suggestions
- [ ] <concise description> — `<file>:<line>` — <rationale>

### Looks good
- <something done well — always include at least one>

---
**Verdict:** APPROVE | REQUEST CHANGES | COMMENT
```

- **Blocking** — must be fixed before merge: bugs, security issues, explicit rule violations from CONTRIBUTING.md
- **Suggestions** — non-blocking: style, test coverage, readability improvements
- **Looks good** — acknowledge what is done well; a review is not only criticism
- **Verdict**:
  - `APPROVE` — no blocking issues
  - `REQUEST CHANGES` — one or more blocking issues found
  - `COMMENT` — only questions or non-blocking suggestions

## Notes

- Be concise: one line per finding, `file:line` reference when possible.
- For large diffs (>500 lines), focus on the highest-risk areas first and say so.
- Do not re-run linters or tests — infer from the diff and known configs only.
- If no CONTRIBUTING.md or linter config is found, apply general best practices only and note the absence.