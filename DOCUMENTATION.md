# claude-github-config — Complete Reference

This document describes every component of the `claude-github-config` template: what it contains, what each piece does, how the parts connect, and how to maintain the template over time.

**Audience:** developers at weareinto who are applying this template to a project, or who want to understand or extend it.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Claude Code configuration (.claude/)](#2-claude-code-configuration-claude)
   - [settings.json — shared permissions and hooks](#21-settingsjson--shared-permissions-and-hooks)
   - [settings.local.json — local overrides](#22-settingslocaljson--local-overrides)
   - [Hooks](#23-hooks)
   - [Skills](#24-skills)
3. [GitHub configuration (.github/)](#3-github-configuration-github)
   - [Issue templates](#31-issue-templates)
   - [Pull request template](#32-pull-request-template)
   - [Workflows](#33-workflows)
   - [Helper scripts](#34-helper-scripts)
4. [The complete lifecycle](#4-the-complete-lifecycle)
5. [Installation reference](#5-installation-reference)
6. [Placeholder reference](#6-placeholder-reference)
7. [Maintenance guide](#7-maintenance-guide)

---

## 1. Overview

`claude-github-config` packages the development workflow used at weareinto into a reusable template. It covers two layers:

| Layer | Location | Purpose |
|---|---|---|
| **Claude Code** | `.claude/` | Controls how the AI agent behaves: what commands it can run, what files it can touch, and what skills it has access to |
| **GitHub** | `.github/` | Automates the ticket → branch → PR → deploy → release lifecycle via Actions workflows |

These two layers are designed to work together. Claude Code skills like `/branch` and `/pr-submit` call `gh` CLI commands that trigger GitHub Actions, which in turn move project board cards automatically.

### What is NOT included

The template deliberately excludes:
- **Deployment workflows** (too project-specific — paths, runners, and environments vary per project)
- **CI workflow** (linting, testing — stack-dependent; add your own `ci.yml`)
- **`CLAUDE.local.md`** (personal preferences — gitignored by design)
- **`wiki-brain.json`** (local Obsidian vault path — machine-specific)

---

## 2. Claude Code configuration (`.claude/`)

### 2.1 `settings.json` — shared permissions and hooks

**Committed to the repo. Applies to every team member.**

```
.claude/settings.json
```

#### Allowed commands (no confirmation prompt)

```json
"allow": [
  "Bash(git:*)",
  "Bash(gh:*)",
  "Bash(pytest:*)",
  "Bash(ruff:*)",
  "Bash(uv:*)",
  "Bash(python:*)",
  "Bash(python3:*)",
  "Bash(make:*)"
]
```

Claude can run these commands without asking for permission. Everything else triggers a confirmation dialog. Adjust this list for your project's stack (e.g., replace `pytest`/`ruff`/`uv` with `jest`/`eslint`/`npm` for a Node project).

#### Active hooks

Two `PreToolUse` hooks run automatically before every file operation:

| Hook | Triggers on | What it does |
|---|---|---|
| `protect-env.sh` | Read, Edit, Write | Blocks access to any `.env` file (except `.env.example`) |
| `protect-main.sh` | Edit, Write | Blocks file modifications when the current branch is `main` or HEAD is detached |

These hooks fire **before** the tool executes — they can fully block the operation by exiting with code `2`.

---

### 2.2 `settings.local.json` — local overrides

**Not committed. Created manually by each developer.**

This file lives at `.claude/settings.local.json` (gitignored) and can override anything in `settings.json`. Common uses:

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "skipDangerousModePermissionPrompt": true,
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/your/session-end-hook.sh",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

`defaultMode: bypassPermissions` disables all confirmation prompts locally. Use with care.

---

### 2.3 Hooks

Hooks are shell scripts that Claude Code calls automatically at specific moments. They receive a JSON payload on stdin and control behavior through their exit code.

```
.claude/hooks/
├── protect-env.sh
└── protect-main.sh
```

#### `protect-env.sh`

**Event:** `PreToolUse` on Read, Edit, Write  
**Purpose:** Prevent accidental exposure or modification of `.env` files.

Logic:
1. Extract `file_path` from the JSON input (without `jq`).
2. If the path contains `.env` AND does not contain `.env.example` → exit 2 (block).
3. Otherwise → exit 0 (allow).

Example blocked paths: `.env`, `.env.local`, `config/.env.prod`  
Example allowed paths: `.env.example`, `.env.template`

#### `protect-main.sh`

**Event:** `PreToolUse` on Edit, Write  
**Purpose:** Prevent direct commits to `main` by blocking all file writes when on the `main` branch.

Logic:
1. Extract `file_path` from input.
2. If the file is gitignored → exit 0 (allow — gitignored files are never committed, so branch protection is irrelevant).
3. Read current branch with `git rev-parse --abbrev-ref HEAD`.
4. If branch is empty, `HEAD` (detached), or `main` → exit 2 (block) with a descriptive message.
5. Otherwise → exit 0 (allow).

**Why the gitignore exception?** Tools like `uv.lock`, scratch files, and local configs often live at the project root but are gitignored. Blocking writes to them on `main` would be unnecessarily disruptive.

#### Hook exit code reference

| Exit code | Meaning | Effect |
|---|---|---|
| `0` | Success | Tool proceeds normally |
| `2` | Blocked | Tool is cancelled; stderr message shown to user |
| Other | Non-blocking error | Error logged; tool proceeds |

---

### 2.4 Skills

Skills are markdown files that Claude Code loads on demand when you invoke `/skill-name`. Each skill provides a specialized workflow or knowledge base.

```
.claude/skills/
├── branch/          → /branch
├── changelog/       → /changelog
├── claude-code-docs/→ /claude-code-docs
├── issue/           → /issue
├── pr-description/  → /pr-description
├── pr-submit/       → /pr-submit
├── review/          → /review
└── start/           → /start
```

#### `/start`

**Use when:** beginning a work session on a ticket.

Guides Claude through the mandatory pre-implementation checklist:
1. Verify a GitHub issue exists for the work.
2. Verify the issue is in **Ready** status on the project board (not Backlog).
3. Create the branch and link it to the issue (`gh issue develop`).
4. Move the card to **In progress** via the Project v2 GraphQL API.

This skill encodes the workflow rules from `CONTRIBUTING.md` so Claude cannot skip steps.

#### `/branch`

**Use when:** creating a new working branch.

Creates a branch following the naming convention `<type>/<username>/<slug>` and links it to a GitHub issue via `gh issue develop --name`. The `--name` flag registers the branch in the issue's Development sidebar immediately, before any PR exists.

#### `/issue`

**Use when:** creating or editing a GitHub issue.

Knows the Definition of Ready matrix for each template type (Feature, Bug, Chore, Research) and ensures the issue body contains all required sections before marking it ready. Issues created via this skill are well-formed by construction.

#### `/review`

**Use when:** a logical chunk of code is complete and needs review.

Runs a structured code review against the current plan and coding standards. Checks for correctness, coverage, and consistency with the project's existing patterns.

#### `/pr-description`

**Use when:** a PR has been opened as a draft and needs its description filled in.

Usage: `/pr-description <PR_NUMBER>`

Reads the diff and commits for the given PR, then writes a complete PR description following the template: Summary, Linked Issues, Changes, Testing, Screenshots, Checklist.

#### `/pr-submit`

**Use when:** the branch is ready to submit for review.

Handles the full PR submission flow:
1. Opens the PR as a draft (gets a PR number).
2. Fills the description with `/pr-description`.
3. Creates a changelog fragment if the change is user-visible.
4. Marks the PR ready for review.

#### `/changelog`

**Use when:** a user-visible change needs a changelog entry.

Usage: `/changelog <PR_NUMBER>`

Creates a `changelog/<PR>.<type>.md` fragment following the towncrier format. The type is inferred from the change (added / changed / fixed / deprecated / removed / other). Fragment files are consumed at release time and deleted.

#### `/claude-code-docs`

**Type:** Reference (not a workflow skill)  
**Frontmatter:** `disable-model-invocation: true` — loaded as passive reference, no LLM call.

Provides local documentation for configuring Claude Code itself:

| Reference file | Covers |
|---|---|
| `hooks-reference.md` | All hook events, handler types, exit codes, JSON schemas, examples |
| `skills-reference.md` | Skill frontmatter fields, invocation control, dynamic context |
| `subagents-reference.md` | Sub-agent config, tools, permission modes, invocation |
| `mcp-reference.md` | MCP server config, transport types, `.mcp.json` format |
| `rules-reference.md` | `.claude/rules/` path-specific rules, glob patterns |

Use this skill when you need to add or modify `.claude/` configuration in a project. Falls back to `WebFetch` on the official docs if local files are insufficient.

**Maintenance note:** this skill is manually maintained. No automation updates it. If Anthropic ships a new Claude Code feature, update the reference files manually and commit.

---

## 3. GitHub configuration (`.github/`)

### 3.1 Issue templates

```
.github/ISSUE_TEMPLATE/
├── config.yml      ← disables blank issues, links to CONTRIBUTING.md
├── feature.md      ← type:feature
├── bug.md          ← type:bug
├── chore.md        ← type:chore
└── research.md     ← type:research
```

#### `config.yml`

Disables the "blank issue" option so every issue must use a template. Provides a direct link to `CONTRIBUTING.md` as the alternative.

#### Template structure

All four templates follow the same pattern:

```markdown
---
name: <Type>
labels: ["type:<type>"]
---
## Type
## Summary / Overview
## [Type-specific sections]
## Approach & Plan
---
## Ready Checklist
- [ ] ...
```

The `## Ready Checklist` section is the gate between **Backlog** and **Ready**. The `checklist-to-ready.yml` workflow reads this section and promotes the card automatically when all boxes are ticked.

| Template | Required sections | Auto-label |
|---|---|---|
| Feature | Summary, Goals, Approach & Plan | `type:feature` |
| Bug | Summary, Current Behavior, Expected Behavior, Approach & Plan | `type:bug` |
| Chore | Summary | `type:chore` |
| Research | Summary | `type:research` |

---

### 3.2 Pull request template

```
.github/pull_request_template.md
```

Sections:

| Section | Required | Notes |
|---|---|---|
| Summary | Yes | 1-3 bullets |
| Linked Issues | Optional | `Closes #N` lines trigger auto-close on merge |
| Changes | Yes | Bullet list of what changed |
| Testing | Yes | How was this verified |
| Screenshots / Demo | Optional | For UI changes |
| Checklist | Yes | changelog fragment, tests, linter, docs |

The checklist is the last gate before requesting a review. Reviewers can see at a glance whether the basics are covered.

---

### 3.3 Workflows

Eight workflows cover the complete lifecycle. All use `ubuntu-latest` runners.

#### `auto-label.yml`

**Trigger:** `issues: [opened]`  
**Permissions:** `issues: write`

Reads the issue title and applies a `type:*` label based on the prefix:

| Title prefix | Label applied |
|---|---|
| `[Feature]` or `[feature]` | `type:feature` |
| `[Bug]` or `[bug]` | `type:bug` |
| `[Chore]` or `[chore]` | `type:chore` |
| `[Research]` or `[research]` | `type:research` |

No label is applied if the prefix doesn't match. Idempotent — won't add a duplicate if the label already exists.

---

#### `checklist-to-ready.yml`

**Trigger:** `issues: [opened, edited]`  
**Permissions:** `contents: read`, `issues: read`  
**Secret required:** `PROJECT_PAT`  
**Concurrency:** one run per issue, cancels duplicates (rapid box-tick events coalesce)

Reads the `## Ready Checklist` section of the issue body and counts checked vs unchecked items. If all items are checked AND the card is currently in **Backlog** on the project board → moves it to **Ready**.

Cards already past Backlog are never touched, so a toggle can't reset progress.

Has an additional gate: if a `## Design/Mockup` section exists, it must contain at least one URL (a Figma or mockup link) before the card can be promoted.

Degrades gracefully: if `PROJECT_PAT` is not configured, logs a warning and exits 0 (never blocks an issue edit).

---

#### `assign-pr-to-project.yml`

**Trigger:** `pull_request: [opened, reopened]`  
**Permissions:** `contents: read`  
**Secret required:** `PROJECT_PAT`  
**Concurrency:** one run per PR

When a PR is opened, adds it to the project board and sets its Status to **In review**. Uses `addProjectV2ItemById` (idempotent — safe to re-run on `reopened` events).

Resolves project metadata (project ID, Status field ID, option ID for "In review") via GraphQL at runtime, so nothing needs to be hardcoded beyond `ORG` and `PROJECT_NUMBER`.

---

#### `request-copilot-review.yml`

**Trigger:** `pull_request: [opened, reopened]`  
**Permissions:** `pull-requests: write`  
**Concurrency:** one run per PR

Calls the GitHub REST API to add Copilot as a reviewer on every new PR. If Copilot code review is not enabled on the repo (Settings → Copilot → Code review), logs a warning instead of failing.

Every PR therefore gets two reviews: a human review and a Copilot review, without any manual step.

---

#### `inject-design-section.yml`

**Trigger:** `issues: [labeled]` — only fires when `needs:design` label is added  
**Permissions:** `contents: read`, `issues: write`  
**Secret required:** `PROJECT_PAT` (optional — for status check only)

When the `needs:design` label is added to an issue:
1. Injects a `## Design/Mockup` section (with a Figma placeholder) before `## Ready Checklist`.
2. Injects a `- [ ] Design/Mockup complete` item into the checklist.
3. If the card is already past Backlog, posts a warning comment instead of silently injecting.

Idempotent — skips injection if `## Design/Mockup` already exists. Uses Python (embedded in the script) for reliable multi-line body manipulation.

---

#### `generate-changelog.yml`

**Trigger:** `workflow_dispatch` (manual) with inputs `version` (required) and `date` (optional)  
**Permissions:** `contents: write`, `pull-requests: write`

The release preparation workflow. Steps:

1. **Validate inputs** — `version` must match `X.Y.Z`; `date` must be `YYYY-MM-DD` if provided.
2. **Check fragments** — fails if `changelog/` has no `.md` files, or if any filename uses an invalid type. Valid types: `added`, `changed`, `fixed`, `deprecated`, `removed`, `other`.
3. **Preview** — runs `towncrier build --draft` to show what the changelog will look like.
4. **Build** — runs `towncrier build`, which compiles fragments into `CHANGELOG.md` and deletes them.
5. **Inject compare link** — calls `inject-compare-link.sh` to add a GitHub compare URL to the new version heading.
6. **Bump version file** — updates the version string in the project's version file (customize this step for your project's version file path).
7. **Open release PR** — creates a PR with the `release` label and title `chore: release v<X.Y.Z>`.

**Trigger the workflow:**
```bash
gh workflow run "Generate Changelog for Release" --ref main -f version=1.2.3
```

---

#### `tag-on-release-merge.yml`

**Trigger:** `pull_request: [closed]` — only fires when a PR with the `release` label is merged into `main`  
**Permissions:** `contents: write`

Automatically runs after `generate-changelog.yml`'s release PR is merged. Steps:

1. Extracts the version from the PR title (looks for `vX.Y.Z` pattern).
2. Calls `extract-changelog-entry.sh` to pull the release notes for that version from `CHANGELOG.md`.
3. Creates an annotated git tag `vX.Y.Z` with annotation `Release vX.Y.Z`.
4. Creates a GitHub Release whose body is the full changelog entry for that version.

Both the tag creation and release creation are idempotent — if they already exist, the step skips without error.

---

#### `sync-deploy-status.yml`

**Trigger:** `push` to `staging` or `production` branches  
**Permissions:** `contents: read`  
**Secret required:** `PROJECT_PAT`  
**Concurrency:** one run per branch (not cancelled — `cancel-in-progress: false`)

When code is pushed to a deployment branch:
1. Determines the target status (`Staging` or `Production`) from the branch name.
2. Walks the commits between `BEFORE_SHA` and `AFTER_SHA`.
3. For each commit, finds the merge PR (if any).
4. For each PR, finds linked issues (via `Closes #N` in the PR body).
5. Moves each linked issue's project card to the corresponding Status column.

This closes the automation gap that GitHub's built-in project workflows leave: there is no native "branch deployed" trigger, so this workflow fills it.

---

### 3.4 Helper scripts

```
.github/scripts/
├── assign-pr-to-project.sh     ← called by assign-pr-to-project.yml
├── checklist-to-ready.sh       ← called by checklist-to-ready.yml
├── extract-changelog-entry.sh  ← called by tag-on-release-merge.yml
├── inject-compare-link.sh      ← called by generate-changelog.yml
├── inject-design-section.sh    ← called by inject-design-section.yml
└── sync-deploy-status.sh       ← called by sync-deploy-status.yml
```

All scripts follow the same convention:
- Use `set -euo pipefail` for safety.
- Accept configuration via environment variables (set by the calling workflow).
- **Never fail a deploy** — scripts that touch the project board (assign-pr, sync-deploy) bail with `exit 0` when `PROJECT_PAT` is missing or a GraphQL call fails.
- Resolve project metadata (IDs, option IDs) at runtime via GraphQL, so no IDs need to be hardcoded.

#### `assign-pr-to-project.sh`

Required env: `PROJECT_PAT`, `PR_NODE_ID`, `ORG`, `PROJECT_NUMBER`

1. Resolves project ID, Status field ID, and "In review" option ID via GraphQL.
2. Calls `addProjectV2ItemById` (idempotent).
3. Calls `updateProjectV2ItemFieldValue` to set Status → In review.

#### `checklist-to-ready.sh`

Required env: `GH_TOKEN`, `ORG`, `PROJECT_NUMBER`, `ISSUE_NUMBER`, `FROM_STATUS`, `TO_STATUS`, `GITHUB_REPOSITORY`

1. Reads the issue body via the REST API.
2. Extracts the `## Ready Checklist` section with `awk`.
3. Counts checked/unchecked items with `grep`.
4. Checks for a `## Design/Mockup` section — if present, requires at least one URL.
5. Resolves the project item's current Status, then promotes only if it matches `FROM_STATUS`.

#### `extract-changelog-entry.sh`

Usage: `extract-changelog-entry.sh <version> <changelog-path> <output-file>`

Extracts the `## [X.Y.Z]` section from `CHANGELOG.md` into a temp file, which becomes the GitHub Release body.

#### `inject-compare-link.sh`

Usage: `inject-compare-link.sh <new-version> <repo-slug> <changelog-path>`

Rewrites the `## [X.Y.Z] - date` heading to `## [X.Y.Z](https://github.com/.../compare/vPREV...vNEW) - date` by detecting the previous version from the next heading in the file.

#### `inject-design-section.sh`

Uses an embedded Python snippet to safely insert and modify multi-line markdown sections in the issue body. Pure shell string manipulation would be fragile for this task.

#### `sync-deploy-status.sh`

Iterates `git log --merges` between two SHAs, extracts PR numbers, reads PR bodies for `Closes #N` patterns, and calls `updateProjectV2ItemFieldValue` for each linked issue.

---

## 4. The complete lifecycle

```
Issue created (with template)
    │
    ├─► [auto-label.yml] applies type:* label
    │
    ├─► [needs:design added?]
    │       └─► [inject-design-section.yml] injects Design/Mockup section
    │
    └─► Developer ticks Ready Checklist boxes
            └─► [checklist-to-ready.yml] moves card Backlog → Ready


Developer (or Claude Code) picks up the ticket
    │
    ├─► /start skill: verifies Ready status, creates branch, moves to In progress
    │       └─► gh issue develop → branch linked to issue immediately
    │
    └─► Implementation on feature branch


PR opened
    ├─► [assign-pr-to-project.yml] adds PR to board → In review
    ├─► [request-copilot-review.yml] requests Copilot review
    └─► Developer/Claude fills description with /pr-description
        Creates changelog fragment with /changelog


CI green + human approval → PR squash-merged to main
    └─► Card moves to Ready to deploy (GitHub native automation)


Code deployed to staging branch
    └─► [sync-deploy-status.yml] moves linked issue cards → Staging


Manual: gh workflow run "Generate Changelog for Release" -f version=X.Y.Z
    └─► [generate-changelog.yml]
          ├─ Compiles CHANGELOG.md from fragments
          ├─ Bumps version file
          └─ Opens release PR (label: release)

Release PR squash-merged to main
    └─► [tag-on-release-merge.yml]
          ├─ Creates annotated tag vX.Y.Z
          └─ Creates GitHub Release with changelog entry


Code deployed to production branch
    └─► [sync-deploy-status.yml] moves linked issue cards → Production
        └─► Issue closed → card moves to Done (GitHub native automation)
```

---

## 5. Installation reference

This tool applies configuration to **existing repositories**. It does not create new repos.

### Prerequisites

- `git` 2.40+
- `gh` (GitHub CLI) 2.40+, authenticated with scopes: `repo`, `workflow`, `project`, `read:org`
- Bash 3.2+ (macOS default)

### Run the installer

From within the existing project you want to configure:

```bash
cd /path/to/your-project
bash <(curl -fsSL https://raw.githubusercontent.com/weareinto/claude-github-config/main/install.sh)
```

Or clone first and run locally:
```bash
git clone https://github.com/weareinto/claude-github-config.git /tmp/cgc
cd /path/to/your-project
bash /tmp/cgc/install.sh
```

### What the installer does

1. Verifies the target directory is a git repository.
2. Prompts for three values: `ORG`, `REPO`, `PROJECT_NUMBER`.
3. Walks every file in `template/` and for each:
   - Substitutes `{{ORG}}`, `{{REPO}}`, `{{PROJECT_NUMBER}}` in the file content.
   - If the destination file does not exist → creates it.
   - If it already exists and content is identical → reports "ok", no write.
   - If it already exists and content differs → shows a diff (truncated to 30 lines) and asks: overwrite / skip / show full diff.
4. Sets `chmod +x` on `.sh` files automatically.
5. Prints a summary and next-steps checklist.

### After installation

```bash
# 1. Add the PROJECT_PAT secret (fine-grained PAT: project:write + repo:read)
gh secret set PROJECT_PAT --repo <ORG>/<REPO>

# 2. Verify the GitHub Project board has the required Status columns:
#    Backlog → Ready → In progress → In review → Ready to deploy → Staging → Production → Done

# 3. Fill in the tech stack setup in CONTRIBUTING.md (section "Quick start")

# 4. Add CI workflow for your stack (.github/workflows/ci.yml) — not included

# 5. Create CLAUDE.local.md (gitignored) with personal Claude Code preferences

# 6. Commit the applied files
git add .
git commit -m "chore: apply claude-github-config"
```

### Updating an existing project

Re-run the installer at any time to pick up changes from this repo:

```bash
cd /path/to/your-project
bash <(curl -fsSL https://raw.githubusercontent.com/weareinto/claude-github-config/main/install.sh)
```

Files you have customized (e.g. `CONTRIBUTING.md` with your tech stack details) will show a diff — choose "skip" to keep your version.

---

## 6. Placeholder reference

Three placeholders are substituted at install time. They appear as `{{NAME}}` in all template files.

| Placeholder | Description | Example |
|---|---|---|
| `{{ORG}}` | GitHub organization login | `weareinto` |
| `{{REPO}}` | Repository name (without org) | `my-project` |
| `{{PROJECT_NUMBER}}` | GitHub Project v2 board number | `15` |

### Files that contain placeholders

| File | Placeholders used |
|---|---|
| `CONTRIBUTING.md` | `{{ORG}}`, `{{REPO}}`, `{{PROJECT_NUMBER}}` |
| `.github/ISSUE_TEMPLATE/config.yml` | `{{ORG}}`, `{{REPO}}` |
| `.github/workflows/checklist-to-ready.yml` | `{{ORG}}`, `{{PROJECT_NUMBER}}` |
| `.github/workflows/assign-pr-to-project.yml` | `{{ORG}}`, `{{PROJECT_NUMBER}}` |
| `.github/workflows/sync-deploy-status.yml` | `{{ORG}}`, `{{PROJECT_NUMBER}}` |
| `.github/workflows/inject-design-section.yml` | `{{ORG}}`, `{{PROJECT_NUMBER}}` |

### Files with no placeholders (already generic)

- `.claude/settings.json` — no project-specific values
- `.claude/hooks/*.sh` — operate on the current git repo, no hardcoded paths
- `.claude/skills/**` — workflow instructions, fully generic
- `.github/ISSUE_TEMPLATE/{bug,chore,feature,research}.md` — generic templates
- `.github/pull_request_template.md` — generic
- `.github/copilot-instructions.md` — generic
- `.github/workflows/auto-label.yml` — no project values
- `.github/workflows/generate-changelog.yml` — uses `${{ github.repository }}` natively
- `.github/workflows/tag-on-release-merge.yml` — uses `${{ github.repository }}` natively
- `.github/workflows/request-copilot-review.yml` — generic
- `.github/scripts/*.sh` — all values passed via environment variables

---

## 7. Maintenance guide

### When to update this template

Update `claude-github-config` when:
- A workflow is improved or fixed in one project and should propagate to others.
- A new skill is added that should be standard across projects.
- Anthropic releases a new Claude Code feature that affects how `.claude/` is structured.
- A security issue is found (e.g., hook logic, PAT scopes).

### How to update

1. Make changes in this repo on a feature branch.
2. Open a PR, get a review.
3. Merge to `main`.

### How to propagate to existing projects

Re-run the installer in each project. It is idempotent and will show diffs for changed files:

```bash
cd /path/to/existing-project
bash <(curl -fsSL https://raw.githubusercontent.com/weareinto/claude-github-config/main/install.sh)
```

For files you've customized (e.g., `CONTRIBUTING.md` with project-specific tech stack details), choose "skip" when the installer asks — your customizations are preserved.

### Updating `claude-code-docs` skill

The `claude-code-docs` skill contains a local snapshot of Claude Code documentation. It is **not automatically updated**. When Anthropic ships notable changes:

1. Review the official docs at `https://code.claude.com/docs/en/`
2. Update the relevant reference file(s) in `.claude/skills/claude-code-docs/`
3. Commit to this template repo
4. Propagate with the installer

The skill has a `WebFetch` fallback — if a question is not answered by the local files, Claude fetches the live docs. But fresh local files are faster and work offline.

### Adding a new skill

1. Create `.claude/skills/<skill-name>/SKILL.md` in this repo.
2. Add any supporting files in the same directory.
3. The installer will copy it to all projects that run the update.

### Adding a new workflow

1. Create `.github/workflows/<name>.yml` in `template/.github/workflows/`.
2. If the workflow uses `ORG` or `PROJECT_NUMBER`, use `{{ORG}}` and `{{PROJECT_NUMBER}}` as placeholders.
3. If it needs a helper script, add it to `template/.github/scripts/`.
4. Update the workflows table in this document and in `README.md`.
5. Update `CONTRIBUTING.md` template's workflows reference section.

### Required GitHub secret

All project-board workflows depend on `PROJECT_PAT`:

> A **fine-grained personal access token** with:
> - Repository permission: `Contents: read`
> - Organization permission: `Projects: write`

Create it at `https://github.com/settings/personal-access-tokens/new` and add it as a repository secret:
```bash
gh secret set PROJECT_PAT --repo <ORG>/<REPO>
```

Without this secret, the four board-automation workflows (`checklist-to-ready`, `assign-pr-to-project`, `sync-deploy-status`, `inject-design-section`) degrade gracefully — they log a warning and exit 0, so they never block a PR or a deploy.
