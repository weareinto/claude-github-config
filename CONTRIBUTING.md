# Contributing to claude-github-config

This is the **single source of truth** for how work flows through this repo: from creating an issue, through implementing it on a branch, to merging the PR, recording the change in the changelog, and cutting a release. All contributors (team members, partners, Claude Code, GitHub Copilot) follow these rules on every action.

For what the project *is* (architecture, domain concepts, business rules), see [`doc/PROJECT.md`](doc/PROJECT.md).

**Language rule:** all written artifacts in this repo MUST be in English — specs, READMEs, design docs, PR descriptions, commit bodies, code comments, docstrings. Conversations may be in any language; checked-in text is English only.

---

## 1. Quick start

You should be:

- A member of the `weareinto` GitHub organization
- A collaborator on `weareinto/claude-github-config`
- A member of the `weareinto/22` GitHub Project (https://github.com/orgs/weareinto/projects/22)

Install:

- `git` 2.40+
- `gh` (GitHub CLI) 2.40+ — run `gh auth login` (HTTPS, scopes: `repo`, `workflow`, `project`, `read:org`)
- `make` — GNU Make, used to run the targets defined in the repo's `Makefile`

```bash
# Testing (requires bats-core)
brew install bats-core        # macOS — install once
bats tests/install.bats       # run the full test suite
```

---

## 2. The lifecycle in one picture

Every ticket on the GitHub Project board moves through this status flow:

```
Backlog ──► Ready ──► In progress ──► In review ──► Ready to deploy ──► Staging ──► Production ──► Done
                │
                └──► Blocked  (when waiting on a decision or external party)
```

Most transitions are wired up as **GitHub Project automations** (configured in the Project UI):

| Trigger | Card moves to |
|---|---|
| Branch pushed / PR opened against `main` | In review |
| PR merged to `main` | Ready to deploy |
| Code reaches `staging` branch | Staging |
| Code reaches `production` branch | Production |
| Issue closed | Done |

You move cards manually when the board can't infer the state (e.g., `Backlog → Ready`, `Blocked`).

---

## 3. Creating an issue

Pick the right template at https://github.com/weareinto/claude-github-config/issues/new/choose:

| Template | Use when… | Auto-label |
|---|---|---|
| **Feature** | Adding a new capability (backend, UI, or both) | `type:feature` |
| **Bug** | Something doesn't work as expected | `type:bug` |
| **Chore** | Maintenance, refactor, tooling, CI, internal docs | `type:chore` |
| **Research** | Focused investigation that produces a finding/decision (no PR/branch usually) | `type:research` |

The label is applied automatically by `auto-label.yml` based on the `[Feature]` / `[Bug]` / `[Chore]` / `[Research]` prefix in the title.

### Definition of Ready (DoR)

Before a ticket can move from **Backlog** to **Ready**, the issue body must contain the required sections for its type and the Ready Checklist must be ticked:

| Section | 🎨 Feature | 🐛 Bug | 🧹 Chore | 🔬 Research |
|---|:---:|:---:|:---:|:---:|
| Summary / Overview | required | required | required | required |
| Goals | required | — | optional | — |
| Current Behavior | — | required | — | — |
| Expected Behavior | — | required | — | — |
| Steps to Reproduce | — | optional | — | — |
| Approach & Plan | required | required | optional | optional |
| References | — | — | — | optional |

The `/issue` Claude skill consumes this matrix when authoring or editing an issue, so issues created via the skill are well-formed by construction. There is no server-side validator — once the body is complete and every Ready Checklist box is ticked, the author moves the card from **Backlog** to **Ready** themselves.

---

## 4. Working on a ticket

### Pre-implementation checklist (mandatory)

Before writing a single line of code, every contributor — human or Claude Code — must complete this sequence in order:

1. **A ticket must exist.** If there is no GitHub issue for the work you are about to do, create one now using the appropriate template. Do not skip this step even for "small" changes.

2. **The ticket must be in Ready status.** Check the issue's project card on [Project board #22](https://github.com/orgs/weareinto/projects/22):
   - If the card is **Ready** → proceed.
   - If the card is **Backlog** → the Definition of Ready is not satisfied. Identify which required sections are missing or incomplete, offer to help the author fill them in, and wait until every box in the `## Ready Checklist` is ticked and the card has moved to **Ready** before continuing.
   - Never start implementation on a Backlog ticket.

3. **Create the branch and link it to the ticket.**
   - **Claude Code:** run `/branch --issues <ISSUE_NUMBER> --link` — the `--link` flag triggers `gh issue develop`, which registers the branch in the issue's Development sidebar immediately.
   - **Humans (manual):**
     ```bash
     gh issue develop <ISSUE_NUMBER> --name "<type>/<github_username>/<short-slug>" --checkout
     ```

4. **Move the card to In progress** — see [Moving the card to In progress](#moving-the-card-to-in-progress) below. Do this before the first file edit.

Only after all four steps are complete may implementation begin.

### Branch naming

```
<type>/<github_username>/<short-slug>
```

- `<type>`: one of `feature`, `chore`, `fix`. Documentation/refactor/test/perf work goes under `chore/`.
- `<github_username>`: your GitHub login.
- `<short-slug>`: kebab-case description.

Examples:

```
feature/alice/add-llm-billing
fix/bob/jwt-expiry
chore/alice/refactor-ticket-lifecycle
```

### Moving the card to In progress

As soon as work begins on a branch, move the linked issue's project card from **Ready** to **In progress**. No automation covers this transition — do it manually before writing the first line of code.

- **Humans:** drag the card in the [Project board UI](https://github.com/orgs/weareinto/projects/22).
- **Claude Code:** call the Project v2 GraphQL mutation to update the Status field to `In progress`.

### Branch protection on `main`

Enforced by GitHub settings:

- No direct pushes.
- PR required, 1 approval.
- All CI checks must pass.
- Branch must be up to date with `main` before merging.
- Squash-merge is the default.

---

## 5. Opening a PR

The flow Claude Code follows (and that humans should mirror):

1. **Open as draft first** — gets you a PR number immediately:
   ```bash
   gh pr create --base main --draft \
     --title "Your PR title" \
     --body ""
   ```
   If this PR closes any issues, include `Closes #N` lines in the body.
2. **Update the description** — Claude Code: `/pr-description <PR>`. Otherwise: fill the PR template manually.
3. **Add a changelog fragment** if the change is user-visible — Claude Code: `/changelog <PR>`. Otherwise create the file by hand:
   - Path: `changelog/<PR>.<type>.md`
   - Types: `added`, `changed`, `fixed`, `deprecated`, `removed`, `other`
   - Content: a single bullet starting with `- `, leading with **what users notice**
   - Skip for: pure refactor / test-only / lint / CI / internal-doc-only changes.
4. **Mark the PR ready for review:**
   ```bash
   gh pr ready <PR>
   ```
5. Wait for **CI green** + **1 approval**. Squash-merge via the GitHub UI.

---

## 6. Releasing

Releases are produced by **towncrier** + two GitHub Actions workflows:

- **`generate-changelog.yml`** (manual, `workflow_dispatch`) — rolls every `changelog/*.md` fragment into a new section in `CHANGELOG.md`, opens a release PR labeled `release`.
- **`tag-on-release-merge.yml`** (auto, on PR merge with `release` label) — extracts the version from the PR title, pushes an annotated tag `v<X.Y.Z>`, and creates a GitHub Release.

### Step-by-step

1. **Inspect pending fragments:**
   ```bash
   ls -1 changelog/*.md | grep -v _template.md.j2
   ```

2. **Find the latest tag:**
   ```bash
   git fetch --tags && git tag --sort=-v:refname | head -1
   ```

3. **Dispatch the workflow:**
   ```bash
   gh workflow run "Generate Changelog for Release" --ref main -f version=<X.Y.Z>
   ```

4. **Find, review, and squash-merge the release PR.** `tag-on-release-merge.yml` then auto-creates the tag and GitHub Release.

### SemVer rules

- Only `*.fixed.md` fragments → `PATCH`
- Any `*.added.md` or `*.changed.md` → `MINOR`
- Breaking change or `*.removed.md` of a public surface → `MAJOR`

---

## 7. Definition of Done

A ticket is **Done** when:

- [ ] Code merged to `main` (PR squash-merged).
- [ ] CI green (lint, format, tests).
- [ ] DoR sections satisfied by the implementation.
- [ ] Changelog fragment added if user-visible.
- [ ] Documentation updated if public behavior changed.
- [ ] Deployed to staging and verified.
- [ ] Linked issues (if any) auto-closed by `Closes #ID` lines in the PR body.

---

## 8. Workflows reference

| Workflow | Trigger | Purpose |
|---|---|---|
| `auto-label.yml` | Issue opened | Apply `type:*` label by title prefix |
| `checklist-to-ready.yml` | Issue opened or edited | Promote Backlog → Ready when checklist is complete |
| `assign-pr-to-project.yml` | PR opened or reopened | Add PR to project board, set In review |
| `request-copilot-review.yml` | PR opened or reopened | Request GitHub Copilot review automatically |
| `inject-design-section.yml` | `needs:design` label added | Inject Design/Mockup section into issue body |
| `generate-changelog.yml` | Manual dispatch with version | Roll fragments into `CHANGELOG.md`, open release PR |
| `tag-on-release-merge.yml` | Release PR merged | Create annotated `vX.Y.Z` tag and GitHub Release |
| `sync-deploy-status.yml` | Push to `staging` or `production` | Move linked issues' cards to Staging or Production |

Helper scripts: [`.github/scripts/`](.github/scripts/).

### Project board automation (PROJECT_PAT)

`sync-deploy-status.yml`, `checklist-to-ready.yml`, `assign-pr-to-project.yml`, and `inject-design-section.yml` need the **`PROJECT_PAT`** secret — a fine-grained PAT with `project: write` + `repo: read` scopes. Without that secret each workflow no-ops with a warning.

---

## 9. Repo structure

```
/
├── README.md
├── CLAUDE.md                   # Claude Code entry point (imports CONTRIBUTING + PROJECT)
├── CONTRIBUTING.md             # This file — workflow source of truth
├── DOCUMENTATION.md            # Full reference documentation
├── install.sh                  # The installer — sole production artifact
├── template/                   # Files deployed into target repos by install.sh
│   ├── .claude/                # Skills, hooks, settings
│   ├── .github/                # Workflows, issue/PR templates, helper scripts
│   ├── .claude-github-config-ignore
│   ├── CONTRIBUTING.md         # Template version (placeholders substituted at install time)
│   └── doc/
│       ├── PROJECT.md          # Blank project context template
│       └── claude-github-config.md  # Reference doc template
├── tests/
│   ├── install.bats            # bats-core test suite (25 tests)
│   └── README.md
├── .claude/                    # Claude Code config for THIS repo
├── .github/                    # Workflows for THIS repo
└── doc/
    ├── PROJECT.md              # Project context for THIS repo (gitignore-protected)
    └── claude-github-config.md # Reference doc with substituted values
```