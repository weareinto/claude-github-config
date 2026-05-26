# Project Overview

What this repo is — product, architecture, business rules. For workflow rules (issues, branches, PRs, releases), see [`/CONTRIBUTING.md`](../CONTRIBUTING.md).

## What we're building

Internal tooling that deploys the standard INTO AI development configuration onto any repository in minutes. A single `bash <(curl ...)` command installs Claude Code skills, GitHub Actions workflows, hooks, issue/PR templates, and a contributing guide — all pre-wired to the INTO AI project board workflow.

- **Client:** INTO AI internal engineering teams
- **Execution team:** INTO AI (weareinto)
- **Commercial partner (if any):** —

## Architecture

This repo is a **template installer**, not a service. There is no runtime component.

- **`install.sh`** — the sole production artifact. Bash script that walks `template/`, substitutes `{{ORG}}`, `{{REPO}}`, `{{PROJECT_NUMBER}}` placeholders, and copies files into the target repo. Handles conflicts interactively (diff + prompt) or silently in CI (`--ci` flag). Idempotent.

- **`template/`** — the file tree deployed into target repos:
  - `.claude/` — Claude Code settings, hooks (protect-main, protect-env), and 8 skills
  - `.github/` — 4 issue templates, PR template, 8 Actions workflows, 6 helper scripts
  - `CONTRIBUTING.md` — the INTO AI development lifecycle (single source of truth)
  - `doc/PROJECT.md` — blank project context skeleton, loaded by Claude Code at session start

- **`tests/`** — bats-core test suite (25 tests) covering install.sh behaviour: fresh install, idempotency, CI mode, ignore list, batch conflict handling, project status columns.

- **No build step, no dependencies, no runtime.** The only external tools required are `bash`, `git`, `gh`, `python3`, `jq`, and `sed`.

## Key domain concepts

- **Template** — the `template/` directory. Everything inside gets deployed verbatim (after placeholder substitution) into the target repo.
- **Target repo** — the INTO AI project repository where `install.sh` is run.
- **Placeholder** — `{{ORG}}`, `{{REPO}}`, `{{PROJECT_NUMBER}}` — substituted by `install.sh` at deploy time via `sed`.
- **Ignore list** — `.claude-github-config-ignore` in the target repo. Files listed here are never overwritten by re-runs or the `update-config.yml` workflow. Patterns are cached in memory before the file walk so the ignore file itself cannot clobber user entries mid-run.
- **CI mode** (`--ci`) — non-interactive mode used by the `update-config.yml` GitHub workflow. Reads values from `.claude-github-config.json`, overwrites all conflicts silently.
- **Batch mode** (`--batch-apply` / `--batch-skip`) — apply or skip all conflicts at once without per-file prompts. Shown as an interactive choice (`[a]pply all / [s]kip all / [p]ick individually`) when multiple conflicts are detected.
- **Project board** — a GitHub Project v2 board linked to the target repo. Required columns: `Backlog → Ready → Blocked → In progress → In review → Ready to deploy → Staging → Production → Done`. The installer auto-creates any missing columns.

## Technology stack

- **Language / tooling:** Bash (install.sh), bats-core (tests)
- **Key platforms / libraries:** GitHub Actions, GitHub Project v2 GraphQL API, `gh` CLI, `jq`, `python3` (JSON parsing), `sed` (placeholder substitution)

Vendor candidates or decisions still open:

| Component | Options / Decision |
|-----------|--------------------|
| — | — |

## Critical business rules

- **`install.sh` is the only production artifact.** Everything in `template/` is data, not code. Never add logic to template files.
- **Idempotency is non-negotiable.** Re-running install.sh on an already-configured repo must produce no changes unless the template has actually changed.
- **User customizations are never silently lost.** Files that differ from the template always trigger a diff + prompt (interactive) or are listed in the conflict summary (batch). The ignore list provides permanent protection.
- **`doc/PROJECT.md` in the template stays blank.** It must be a skeleton — the engineer fills it in for each project. Never put project-specific content in the template version.
- **All placeholder substitution happens at install time via `sed`.** No runtime templating, no environment variables at execution time in the installed files.

## Specifications

- [`DOCUMENTATION.md`](../DOCUMENTATION.md) — full reference: every hook, skill, workflow, script, placeholder, and maintenance guide
- [`tests/README.md`](../tests/README.md) — how to install bats-core and run the test suite
