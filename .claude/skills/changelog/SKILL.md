---
name: changelog
description: Create changelog fragment files for the changes in a PR
---

Create changelog fragment files for the user-visible changes in this PR. The PR number is provided as an argument.

Fragments live in `changelog/` and are consumed by towncrier at release time. Filenames encode the PR number and the change type. The bullet text inside each file becomes the changelog entry.

## Arguments

```
/changelog <PR_NUMBER>
```

`PR_NUMBER` (required): the pull request number. The PR must already exist (open `gh pr create --draft` first if needed).

## When to skip

Skip the fragment for: internal-only refactors, tests, lint/format-only changes, CI changes, in-progress doc cleanups not visible to users. If unsure, ask: *"would an LDL stakeholder, integrator, or returning engineer want to know this changed?"* If no, skip.

## Steps

1. Verify the PR number exists:
   ```
   gh pr view <PR_NUMBER>
   ```

2. List the commits on the current branch vs `main`:
   ```
   git log main..HEAD --oneline
   ```

3. For each significant change, create a file in `changelog/` named `<PR_NUMBER>.<type>.md`. Multiple fragments of the same type for the same PR get a numeric suffix: `<PR_NUMBER>.<type>.2.md`, `.3.md`, etc.

4. Each file contains a single-line markdown bullet starting with `- `, no line wrapping.

   For complex changes, indent additional context lines under the main bullet.

5. Lead with **what users notice**. Implementation details go after, as secondary context.

   **Good:**
   ```
   - The `/auth/login` endpoint now returns the JWT under `data.token`. Previously it was at the root, which broke the official iOS client.
   ```

   **Bad** (implementation detail only):
   ```
   - Refactored AuthService.login to wrap the response in a data envelope.
   ```

6. For breaking changes, prefix the bullet with `**BREAKING:**`:
   ```
   - **BREAKING:** Removed the deprecated `/v1/users/list` endpoint. Use `/v2/users` instead.
   ```

## Allowed types

| Filename suffix | When to use |
|---|---|
| `.added.md` | New endpoint, parameter, capability, or surface area |
| `.changed.md` | Existing behavior changed (signature, default, response shape) |
| `.fixed.md` | Bug fix that affects behavior users could observe |
| `.deprecated.md` | Marked for removal in a future release |
| `.removed.md` | Deleted (a previously-deprecated capability is now gone) |
| `.other.md` | Genuinely doesn't fit above (rare) |

## Picking the right type

Look at what the change does, not at the commit message:

- New endpoint, parameter, capability → `added`
- Existing behavior changes (signature, default, response shape) → `changed`
- Bug fix users could observe → `fixed`
- Public surface marked for future removal → `deprecated`
- Previously-deprecated capability removed → `removed`
- Performance improvements users will notice → `changed`
- Breaking change → `removed` or `changed`, with `**BREAKING:**` prefix on the bullet
- Pure refactor / test-only / lint / CI / internal-doc → skip the fragment entirely

## Example

For PR #42 with a new endpoint and a bug fix:

`changelog/42.added.md`:
```
- Added `/auth/login` endpoint accepting an email + password and returning a JWT.
```

`changelog/42.fixed.md`:
```
- Fixed timezone handling in session timestamps. Sessions started before midnight UTC no longer appear under the previous day's report.
```