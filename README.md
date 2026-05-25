# claude-github-config

Claude Code + GitHub workflow configuration template for weareinto projects.

## What's included

- **`.claude/`** — Claude Code hooks, permissions, and skills (`/branch`, `/start`, `/issue`, `/review`, `/pr-description`, `/pr-submit`, `/changelog`)
- **`.github/`** — Issue templates, PR template, and 8 GitHub Actions workflows covering the full ticket → branch → PR → deploy → release lifecycle
- **`CONTRIBUTING.md`** — Workflow source of truth (pre-filled with your org/repo values after install)

## Usage

### New project

```bash
gh repo create weareinto/my-project --private
git clone https://github.com/weareinto/my-project.git
cd my-project
bash <(curl -fsSL https://raw.githubusercontent.com/weareinto/claude-github-config/main/install.sh)
```

### Existing project

```bash
cd /path/to/existing-project
bash <(curl -fsSL https://raw.githubusercontent.com/weareinto/claude-github-config/main/install.sh)
```

The installer asks for your org, repo name, and Project board number, then applies all files. For files that already exist, it shows a diff and asks before overwriting.

## After install

1. Add the `PROJECT_PAT` secret (fine-grained PAT with `project:write` + `repo:read`):
   ```bash
   gh secret set PROJECT_PAT --repo <org>/<repo>
   ```
2. Create a GitHub Project v2 board with these Status columns:
   `Backlog → Ready → In progress → In review → Ready to deploy → Staging → Production → Done`
3. Fill in the tech stack section in `CONTRIBUTING.md`.
4. Create a `CLAUDE.local.md` (gitignored) with any personal preferences.

## Updating an existing project

Re-run the installer — it only touches files that have changed, and asks before overwriting anything you've customized.

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
