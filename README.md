# claude-github-config

Tool for applying Claude Code and GitHub workflow configuration to existing weareinto projects.

## What it does

Installs and configures two layers on any existing repo:

- **`.claude/`** — Claude Code hooks, permissions, and skills (`/branch`, `/start`, `/issue`, `/review`, `/pr-description`, `/pr-submit`, `/changelog`)
- **`.github/`** — Issue templates, PR template, and 8 GitHub Actions workflows covering the full ticket → branch → PR → deploy → release lifecycle
- **`CONTRIBUTING.md`** — Workflow source of truth, pre-filled with your org/repo/board values

## Usage

From within any existing project:

```bash
cd /path/to/your-project
bash <(curl -fsSL https://raw.githubusercontent.com/weareinto/claude-github-config/main/install.sh)
```

The installer asks for three values (org, repo name, Project board number), then applies all configuration files. For files that already exist, it shows a diff and asks before overwriting — your existing customizations are preserved.

Re-running is safe — the installer is idempotent.

## After install

1. Add the `PROJECT_PAT` secret (fine-grained PAT with `project:write` + `repo:read`):
   ```bash
   gh secret set PROJECT_PAT --repo <org>/<repo>
   ```
2. Verify your GitHub Project v2 board has these Status columns:
   `Backlog → Ready → In progress → In review → Ready to deploy → Staging → Production → Done`
3. Fill in the tech stack section in `CONTRIBUTING.md`.
4. Create a `CLAUDE.local.md` (gitignored) with any personal Claude Code preferences.

## Updating a project

Re-run the installer to pick up changes from this repo. Only modified files are touched; unchanged files are skipped.

## Workflows overview

| Workflow | Trigger | What it does |
|---|---|---|
| `auto-label.yml` | Issue opened | Applies `type:*` label from title prefix |
| `checklist-to-ready.yml` | Issue edited | Promotes Backlog → Ready when all checklist boxes are ticked |
| `assign-pr-to-project.yml` | PR opened | Adds PR to project board, sets In review |
| `request-copilot-review.yml` | PR opened | Requests GitHub Copilot review |
| `inject-design-section.yml` | `needs:design` label added | Injects Design/Mockup section into issue |
| `generate-changelog.yml` | Manual dispatch | Rolls changelog fragments into CHANGELOG.md, opens release PR |
| `tag-on-release-merge.yml` | Release PR merged | Creates annotated tag + GitHub Release |
| `sync-deploy-status.yml` | Push to staging/production | Moves linked issues' cards to Staging or Production |

## Full documentation

For a complete reference of every component — hooks, skills, workflows, scripts, placeholders, and maintenance guide — see [DOCUMENTATION.md](DOCUMENTATION.md).
