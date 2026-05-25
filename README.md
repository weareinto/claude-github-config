# claude-github-config

**Internal tool for INTO AI engineers.** Deploys the standard Claude Code and GitHub workflow configuration onto any INTO AI repository in minutes.

Every INTO AI project uses the same development workflow: structured GitHub issues, a project board with automated status transitions, Claude Code with guardrails and skills, and a towncrier-based release process. This tool packages that configuration and applies it to any repo with a single command.

## What it installs

| Layer | What gets configured |
|---|---|
| **Claude Code** (`.claude/`) | Permissions, hooks (branch and `.env` protection), and 8 workflow skills |
| **GitHub** (`.github/`) | 4 issue templates, PR template, 8 Actions workflows, and 6 helper scripts |
| **Contributing guide** | `CONTRIBUTING.md` — the single source of truth for the INTO AI development lifecycle |
| **Project context** | `doc/PROJECT.md` — skeleton for describing what the project is; loaded by Claude Code at every session start |

### Claude Code skills installed

| Skill | Purpose |
|---|---|
| `/start` | Begin a work session: verify ticket, create branch, move card to In progress |
| `/branch` | Create a branch and link it to a GitHub issue |
| `/issue` | Create or edit a GitHub issue following the Definition of Ready |
| `/review` | Run a structured code review |
| `/pr-description` | Generate a PR description from the diff |
| `/pr-submit` | Full PR submission flow (draft → description → changelog → ready) |
| `/changelog` | Create a towncrier changelog fragment for a PR |

### GitHub workflows installed

| Workflow | Trigger | Purpose |
|---|---|---|
| `auto-label.yml` | Issue opened | Applies `type:*` label from title prefix |
| `checklist-to-ready.yml` | Issue edited | Promotes Backlog → Ready when all checklist boxes are ticked |
| `assign-pr-to-project.yml` | PR opened | Adds PR to the project board, sets In review |
| `request-copilot-review.yml` | PR opened | Requests GitHub Copilot review automatically |
| `inject-design-section.yml` | `needs:design` label added | Injects Design/Mockup section into the issue body |
| `generate-changelog.yml` | Manual dispatch | Compiles changelog fragments into CHANGELOG.md, opens release PR |
| `tag-on-release-merge.yml` | Release PR merged | Creates annotated git tag and GitHub Release |
| `sync-deploy-status.yml` | Push to staging/production | Moves linked issue cards to Staging or Production |

## Usage

From within any existing INTO AI repository:

```bash
cd /path/to/your-repo
bash <(curl -fsSL https://raw.githubusercontent.com/weareinto/claude-github-config/main/install.sh)
```

The installer prompts for three values:
- **Organization** — GitHub org (e.g. `weareinto`)
- **Repository name** — the repo slug (e.g. `my-project`)
- **Project board number** — the GitHub Project v2 number linked to the repo

It then applies all configuration files. For files that already exist, it shows a diff and asks before overwriting — existing customizations are never silently lost.

Re-running is safe. The installer is idempotent.

## After install

```bash
# 1. Add the PROJECT_PAT secret (fine-grained PAT: project:write + repo:read)
gh secret set PROJECT_PAT --repo <org>/<repo>

# 2. Verify your GitHub Project v2 board has these Status columns:
#    Backlog → Ready → In progress → In review → Ready to deploy → Staging → Production → Done

# 3. Fill in the tech stack setup section in CONTRIBUTING.md

# 4. Create a CLAUDE.local.md (gitignored) with your personal Claude Code preferences

# 5. Commit the applied files
git add .
git commit -m "chore: apply claude-github-config"
```

## Updating a project

Re-run the installer to pick up changes from this repo:

```bash
cd /path/to/your-repo
bash <(curl -fsSL https://raw.githubusercontent.com/weareinto/claude-github-config/main/install.sh)
```

Files you have customized (e.g. `CONTRIBUTING.md` with project-specific tech stack details) will show a diff — choose "skip" to keep your version.

## Full documentation

For a complete reference of every component — hooks, skills, workflows, scripts, placeholders, and maintenance guide — see [DOCUMENTATION.md](DOCUMENTATION.md).
