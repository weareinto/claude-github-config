#!/usr/bin/env bash
# install.sh — apply weareinto/claude-github-config to the current repository.
#
# Behavior:
#   - New files are created directly.
#   - Existing files: shows diff and asks (interactive) or overwrites (--ci).
#   - Files listed in .claude-github-config-ignore are never overwritten.
#   - Files added locally (not in the template) are never touched.
#   - Running it again is safe (idempotent).
#
# Usage (interactive):
#   cd /path/to/your-project
#   bash <(curl -fsSL https://raw.githubusercontent.com/weareinto/claude-github-config/main/install.sh)
#
# Usage (CI / non-interactive) — reads values from .claude-github-config.json:
#   bash install.sh --ci
#
# Usage (sandbox) — installs into ./repo-test/ without touching the current repo:
#   bash install.sh --test

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ---- Parse flags -----------------------------------------------------------

CI_MODE=false
BATCH_ACTION=""   # "a"=apply-all  "s"=skip-all  ""=ask per-file
for arg in "$@"; do
  case "$arg" in
    --ci)           CI_MODE=true ;;
    --batch-apply)  CI_MODE=true; BATCH_ACTION="a" ;;
    --batch-skip)   CI_MODE=true; BATCH_ACTION="s" ;;
    --test)         TEST_MODE=true ;;
  esac
done

TARGET_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"

# ---- Test mode: install into ./repo-test/ ----------------------------------
if [ "${TEST_MODE:-false}" = true ]; then
  TARGET_DIR="$SCRIPT_DIR/repo-test"
  mkdir -p "$TARGET_DIR"
  if ! git -C "$TARGET_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    git -C "$TARGET_DIR" init -q
    git -C "$TARGET_DIR" config user.email "test@example.com"
    git -C "$TARGET_DIR" config user.name "Test"
  fi
  # Seed the saved config from the current repo so the user is not prompted
  # to re-enter org/repo/project from scratch.
  local_config="$SCRIPT_DIR/.claude-github-config.json"
  if [ -f "$local_config" ]; then
    cp "$local_config" "$TARGET_DIR/.claude-github-config.json"
  fi
fi

CONFIG_FILE="$TARGET_DIR/.claude-github-config.json"
IGNORE_FILE="$TARGET_DIR/.claude-github-config-ignore"

# If template dir not found (e.g. run via curl), clone the repo to a temp dir.
if [ ! -d "$TEMPLATE_DIR" ]; then
  TMPDIR_CLONE="$(mktemp -d)"
  echo -e "${BLUE}Fetching template from GitHub...${NC}"
  git clone --quiet --depth 1 https://github.com/weareinto/claude-github-config.git "$TMPDIR_CLONE"
  TEMPLATE_DIR="$TMPDIR_CLONE/template"
  trap 'rm -rf "$TMPDIR_CLONE"' EXIT
fi

echo ""
echo -e "${BOLD}=== INTO Claude-Github-Config Installer ===${NC}"
echo ""
echo -e "Target directory: ${BOLD}$TARGET_DIR${NC}"
echo ""

# Verify we're inside a git repo.
if ! git -C "$TARGET_DIR" rev-parse --git-dir > /dev/null 2>&1; then
  echo -e "${RED}Error: $TARGET_DIR is not a git repository.${NC}"
  echo "Run 'git init' first, or cd into an existing repo."
  exit 1
fi

# ---- Load ignore list ------------------------------------------------------
# Patterns are cached into IGNORED_PATTERNS before the file walk begins.
# This ensures the user's existing .claude-github-config-ignore is respected
# even if the installer later overwrites that file with the template version.

IGNORED_PATTERNS=()

load_ignore_patterns() {
  IGNORED_PATTERNS=()
  [ -f "$IGNORE_FILE" ] || return 0
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    IGNORED_PATTERNS+=("$pattern")
  done < "$IGNORE_FILE"
}

is_ignored() {
  local rel="$1"
  local pattern
  for pattern in "${IGNORED_PATTERNS[@]+"${IGNORED_PATTERNS[@]}"}"; do
    # shellcheck disable=SC2254
    case "$rel" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

# ---- Pre-flight validation -------------------------------------------------
# Runs before any file is written. Stops immediately if gh is not
# authenticated or if org / repo / project number don't exist on GitHub.

validate_inputs() {
  echo -e "${BOLD}Validating org, repo and project...${NC}"

  # 1. gh CLI present?
  if ! command -v gh &>/dev/null; then
    echo -e "${RED}Error: gh CLI not found.${NC}"
    echo "Install it: https://cli.github.com  then run: gh auth login"
    exit 1
  fi

  # 2. gh authenticated?
  if ! gh auth status &>/dev/null; then
    echo -e "${RED}Error: gh CLI is not authenticated.${NC}"
    echo "Run: gh auth login"
    exit 1
  fi

  local errors=0

  # 3. Org exists?
  if ! gh api "orgs/$ORG" &>/dev/null; then
    echo -e "  ${RED}✗${NC}  org '${BOLD}$ORG${NC}' — not found on GitHub"
    errors=$((errors + 1))
  else
    echo -e "  ${GREEN}✓${NC}  org '${BOLD}$ORG${NC}'"
  fi

  # 4. Repo exists?
  if ! gh api "repos/$ORG/$REPO" &>/dev/null; then
    echo -e "  ${RED}✗${NC}  repo '${BOLD}$ORG/$REPO${NC}' — not found on GitHub"
    errors=$((errors + 1))
  else
    echo -e "  ${GREEN}✓${NC}  repo '${BOLD}$ORG/$REPO${NC}'"
  fi

  # 5. Project exists?
  local project_data project_id project_title
  project_data=$(gh api graphql -f query='
    query($org: String!, $number: Int!) {
      organization(login: $org) {
        projectV2(number: $number) { id title }
      }
    }
  ' -F org="$ORG" -F number="$PROJECT_NUMBER" 2>/dev/null) || true

  project_id=$(jq -r '.data.organization.projectV2.id // empty' <<<"$project_data" 2>/dev/null)
  project_title=$(jq -r '.data.organization.projectV2.title // empty' <<<"$project_data" 2>/dev/null)

  if [ -z "$project_id" ]; then
    echo -e "  ${RED}✗${NC}  project #${BOLD}$PROJECT_NUMBER${NC} — not found in org '$ORG'"
    errors=$((errors + 1))
  else
    echo -e "  ${GREEN}✓${NC}  project #${BOLD}$PROJECT_NUMBER${NC} '${project_title}'"
  fi

  if [ "$errors" -gt 0 ]; then
    echo ""
    echo -e "${RED}Aborted: $errors error(s) above. Correct the values and try again.${NC}"
    exit 1
  fi

  echo ""
}

# ---- Gather project-specific values ----------------------------------------

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    ORG=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d['org'])" 2>/dev/null || true)
    REPO=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d['repo'])" 2>/dev/null || true)
    PROJECT_NUMBER=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d['project_number'])" 2>/dev/null || true)
  fi
}

ORG=""
REPO=""
PROJECT_NUMBER=""
load_config

if [ "$CI_MODE" = true ]; then
  if [ -z "$ORG" ] || [ -z "$REPO" ] || [ -z "$PROJECT_NUMBER" ]; then
    echo -e "${RED}Error: --ci mode requires a .claude-github-config.json file in the target directory.${NC}"
    echo "Run the installer interactively first to create it."
    exit 1
  fi
  echo -e "Using saved config: ORG=${BOLD}$ORG${NC}  REPO=${BOLD}$REPO${NC}  PROJECT_NUMBER=${BOLD}$PROJECT_NUMBER${NC}"
else
  if [ -n "$ORG" ] && [ -n "$REPO" ] && [ -n "$PROJECT_NUMBER" ]; then
    echo -e "Found saved config from previous install:"
    echo -e "  ORG=${BOLD}$ORG${NC}  REPO=${BOLD}$REPO${NC}  PROJECT_NUMBER=${BOLD}$PROJECT_NUMBER${NC}"
    echo ""
    read -rp "Use these values? [Y/n] " USE_SAVED
    if [[ "$USE_SAVED" =~ ^[nN]$ ]]; then
      ORG=""
      REPO=""
      PROJECT_NUMBER=""
    else
      echo ""
      echo -e "  ORG=${BOLD}$ORG${NC}  REPO=${BOLD}$REPO${NC}  PROJECT_NUMBER=${BOLD}$PROJECT_NUMBER${NC}"
    fi
  fi

  if [ -z "$ORG" ]; then
    ORG="weareinto"
    read -rp "$(echo -e "${BOLD}GitHub organization${NC} (press Enter to use ${BOLD}weareinto${NC}): ")" INPUT_ORG
    [ -n "$INPUT_ORG" ] && ORG="$INPUT_ORG"
  fi
  if [ -z "$REPO" ]; then
    read -rp "$(echo -e "${BOLD}Repository name${NC} (e.g. my-project): ")" REPO
  fi
  if [ -z "$PROJECT_NUMBER" ]; then
    read -rp "$(echo -e "${BOLD}GitHub Project board number${NC} (e.g. 15): ")" PROJECT_NUMBER
  fi

  # Only ask "Proceed?" when values were entered manually (not confirmed from saved config)
  if [ -z "${USE_SAVED:-}" ] || [[ "$USE_SAVED" =~ ^[nN]$ ]]; then
    echo ""
    echo -e "  ORG=${BOLD}$ORG${NC}  REPO=${BOLD}$REPO${NC}  PROJECT_NUMBER=${BOLD}$PROJECT_NUMBER${NC}"
    echo ""
    read -rp "Proceed? [y/N] " CONFIRM
    [[ "$CONFIRM" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }
  fi
fi

echo ""

validate_inputs

# ---- Save config for future runs -------------------------------------------

python3 - << PYEOF
import json
with open('$CONFIG_FILE', 'w') as f:
    json.dump({"org": "$ORG", "repo": "$REPO", "project_number": "$PROJECT_NUMBER"}, f, indent=2)
PYEOF

SKIPPED=0
IGNORED=0
CREATED=0
UPDATED=0
UNCHANGED=0

# ---- Install mode: detect existing Claude Code config ----------------------
# If .claude/settings.json or .claude/CLAUDE.md already exist, offer a
# "skills & hooks only" mode so the user doesn't accidentally overwrite
# a hand-tuned configuration.

INSTALL_MODE="full"

if [ "$CI_MODE" = false ]; then
  if [ -f "$TARGET_DIR/.claude/settings.json" ] || [ -f "$TARGET_DIR/.claude/CLAUDE.md" ]; then
    echo ""
    echo -e "${BOLD}Existing Claude Code configuration detected.${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Full reinstall   — apply all template files (may overwrite your config)"
    echo -e "  ${BOLD}2)${NC} Skills & hooks   — update .claude/skills/, .claude/hooks/ and doc/"
    echo ""
    read -rp "  Your choice [1/2, default: 2]: " _mode_choice
    case "${_mode_choice}" in
      1) INSTALL_MODE="full"        ;;
      *) INSTALL_MODE="skills-only" ;;
    esac
    unset _mode_choice
    echo ""
  fi
fi

# ---- Substitution function -------------------------------------------------

substitute() {
  sed \
    -e "s|{{ORG}}|$ORG|g" \
    -e "s|{{REPO}}|$REPO|g" \
    -e "s|{{PROJECT_NUMBER}}|$PROJECT_NUMBER|g"
}

# ---- Apply a single file ---------------------------------------------------

apply_file() {
  local src="$1"
  local rel="$2"
  local dst="$TARGET_DIR/$rel"
  local dst_dir
  dst_dir="$(dirname "$dst")"

  # Skills-only mode: process only .claude/skills/ and .claude/hooks/
  if [ "$INSTALL_MODE" = "skills-only" ]; then
    case "$rel" in
      .claude/skills/*|.claude/hooks/*|doc/*) ;;
      *) return 0 ;;
    esac
  fi

  # Only protect files that already exist — never block initial creation.
  if [ -f "$dst" ] && is_ignored "$rel"; then
    echo -e "  ${BLUE}ignored${NC}  $rel  (protected by .claude-github-config-ignore)"
    IGNORED=$((IGNORED + 1))
    return
  fi

  local new_content
  new_content=$(substitute < "$src")

  mkdir -p "$dst_dir"

  if [ ! -f "$dst" ]; then
    printf '%s' "$new_content" > "$dst"
    [[ "$src" == *.sh ]] && chmod +x "$dst"
    echo -e "  ${GREEN}created${NC}  $rel"
    CREATED=$((CREATED + 1))
    return
  fi

  local existing_content
  existing_content="$(cat "$dst")"

  if [ "$new_content" = "$existing_content" ]; then
    echo -e "  ok       $rel"
    UNCHANGED=$((UNCHANGED + 1))
    return
  fi

  # --batch-skip: keep the user's version intact
  if [ "$BATCH_ACTION" = "s" ]; then
    echo -e "  ${YELLOW}skipped${NC}  $rel"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  # --ci or --batch-apply: overwrite silently
  if [ "$CI_MODE" = true ]; then
    printf '%s' "$new_content" > "$dst"
    [[ "$src" == *.sh ]] && chmod +x "$dst"
    echo -e "  ${GREEN}updated${NC}  $rel"
    UPDATED=$((UPDATED + 1))
    return
  fi

  echo -e "  ${YELLOW}conflict${NC} $rel (already exists — showing diff)"
  diff --color=always <(echo "$existing_content") <(echo "$new_content") | head -30 | sed 's/^/    /' || true
  echo ""
  read -rp "    [o]verwrite / [s]kip / [i]gnore permanently / [d]iff full ? " CHOICE < /dev/tty
  case "$CHOICE" in
    [oO])
      printf '%s' "$new_content" > "$dst"
      [[ "$src" == *.sh ]] && chmod +x "$dst"
      echo -e "    ${GREEN}overwritten${NC}"
      UPDATED=$((UPDATED + 1))
      ;;
    [iI])
      # Add to .claude-github-config-ignore
      echo "$rel" >> "$IGNORE_FILE"
      echo -e "    ${BLUE}added to .claude-github-config-ignore — will never be overwritten again${NC}"
      IGNORED=$((IGNORED + 1))
      ;;
    [dD])
      diff <(echo "$existing_content") <(echo "$new_content") | less || true
      read -rp "    [o]verwrite / [s]kip / [i]gnore permanently ? " CHOICE2 < /dev/tty
      case "$CHOICE2" in
        [oO])
          printf '%s' "$new_content" > "$dst"
          [[ "$src" == *.sh ]] && chmod +x "$dst"
          echo -e "    ${GREEN}overwritten${NC}"
          UPDATED=$((UPDATED + 1))
          ;;
        [iI])
          echo "$rel" >> "$IGNORE_FILE"
          IGNORED_PATTERNS+=("$rel")
          echo -e "    ${BLUE}added to .claude-github-config-ignore${NC}"
          IGNORED=$((IGNORED + 1))
          ;;
        *)
          echo -e "    ${YELLOW}skipped${NC}"
          SKIPPED=$((SKIPPED + 1))
          ;;
      esac
      ;;
    *)
      echo -e "    ${YELLOW}skipped${NC}"
      SKIPPED=$((SKIPPED + 1))
      ;;
  esac
}


# ---- Verify / add GitHub Project status columns ----------------------------
# Queries project #PROJECT_NUMBER and ensures all 9 required Status options
# exist. Missing options are added automatically via the GraphQL API.
# Requires: gh CLI authenticated with `project` scope.

ensure_project_statuses() {
  echo ""
  echo -e "${BOLD}Checking GitHub Project #${PROJECT_NUMBER} status columns...${NC}"

  if ! command -v gh &>/dev/null; then
    echo -e "  ${YELLOW}skipped${NC}  gh CLI not found"
    return
  fi

  local field_data api_exit
  field_data=$(gh api graphql -f query='
    query($org: String!, $number: Int!) {
      organization(login: $org) {
        projectV2(number: $number) {
          id
          field(name: "Status") {
            ... on ProjectV2SingleSelectField {
              id
              options { id name color description }
            }
          }
        }
      }
    }
  ' -F org="$ORG" -F number="$PROJECT_NUMBER" 2>/dev/null) || true
  api_exit=$?

  local project_id field_id
  project_id=$(jq -r '.data.organization.projectV2.id // empty' <<<"$field_data" 2>/dev/null)
  field_id=$(jq -r '.data.organization.projectV2.field.id // empty' <<<"$field_data" 2>/dev/null)

  if [ -z "$project_id" ]; then
    if [ $api_exit -ne 0 ] && [ -z "$field_data" ]; then
      echo -e "  ${YELLOW}warning${NC}  Cannot reach GitHub API — check: gh auth status"
    else
      echo -e "  ${YELLOW}warning${NC}  Project #${PROJECT_NUMBER} not found in org ${ORG}"
    fi
    return
  fi

  if [ -z "$field_id" ]; then
    echo -e "  ${YELLOW}warning${NC}  Project #${PROJECT_NUMBER} exists but has no Status field"
    return
  fi

  # Compute missing statuses and full options list via Python
  local py_result
  py_result=$(FIELD_DATA="$field_data" python3 << 'INNEREOF'
import json, os

EXPECTED = [
    ("Backlog",         "GRAY"),
    ("Ready",           "BLUE"),
    ("Blocked",         "RED"),
    ("In progress",     "YELLOW"),
    ("In review",       "PURPLE"),
    ("Ready to deploy", "GREEN"),
    ("Staging",         "ORANGE"),
    ("Production",      "GREEN"),
    ("Done",            "GRAY"),
]

fd = json.loads(os.environ["FIELD_DATA"])
current = fd["data"]["organization"]["projectV2"]["field"]["options"]
current_names = {o["name"] for o in current}
missing = [(n, c) for n, c in EXPECTED if n not in current_names]

if not missing:
    print("STATUS:ok")
else:
    print("STATUS:missing:" + ", ".join(n for n, _ in missing))
    # Full list: existing options (preserve id) + new ones (no id)
    all_opts = [
        {"id": o["id"], "name": o["name"],
         "color": o.get("color") or "GRAY",
         "description": o.get("description") or ""}
        for o in current
    ]
    for name, color in missing:
        all_opts.append({"name": name, "color": color, "description": ""})
    print("OPTIONS:" + json.dumps(all_opts))
INNEREOF
  )

  local status_line missing_names
  status_line=$(grep "^STATUS:" <<<"$py_result")

  if [[ "$status_line" == "STATUS:ok" ]]; then
    echo -e "  ${GREEN}ok${NC}       All 9 status columns verified"
    return
  fi

  missing_names=$(sed 's/STATUS:missing://' <<<"$status_line")
  local options_json
  options_json=$(grep "^OPTIONS:" <<<"$py_result" | sed 's/OPTIONS://')

  echo -e "  ${YELLOW}adding${NC}   Missing: $missing_names"

  # Build the full GraphQL request body and call the mutation
  local mut_file
  mut_file=$(mktemp)

  FIELD_ID="$field_id" OPTIONS="$options_json" python3 << 'INNEREOF' > "$mut_file"
import json, os
body = {
    "query": (
        "mutation($fieldId:ID!,$options:[ProjectV2SingleSelectFieldOptionInput!]!){"
        "updateProjectV2Field(input:{fieldId:$fieldId,singleSelectOptions:$options}){"
        "projectV2Field{...on ProjectV2SingleSelectField{options{name}}}}}"
    ),
    "variables": {
        "fieldId": os.environ["FIELD_ID"],
        "options": json.loads(os.environ["OPTIONS"]),
    },
}
print(json.dumps(body))
INNEREOF

  if gh api graphql --input "$mut_file" > /dev/null 2>&1; then
    echo -e "  ${GREEN}added${NC}    $missing_names"
  else
    echo -e "  ${RED}failed${NC}   Could not add columns — add them manually in project settings:"
    echo -e "           $missing_names"
  fi
  rm -f "$mut_file"
}


# ---- Tech stack setup (CONTRIBUTING.md) ------------------------------------
# Interactive only. Asks which stacks the project uses and replaces the
# TECH_STACK_SETUP_PLACEHOLDER marker in the installed CONTRIBUTING.md.

setup_tech_stack() {
  [ "$CI_MODE" = true ] && return
  [ "$INSTALL_MODE" = "skills-only" ] && return 0

  local contributing="$TARGET_DIR/CONTRIBUTING.md"
  [ -f "$contributing" ] || return 0
  grep -q "TECH_STACK_SETUP_PLACEHOLDER" "$contributing" || return 0

  echo ""
  echo -e "${BOLD}Tech stack setup${NC}"
  echo "Which stacks does this project use? Enter numbers separated by spaces."
  echo ""
  echo "  1) Python   (pyenv + uv)"
  echo "  2) Node     (nvm + npm)"
  echo "  3) Docker   (docker compose)"
  echo "  4) Skip — I'll fill in CONTRIBUTING.md manually"
  echo ""
  read -rp "Your choice (e.g. 1 4): " STACK_CHOICES

  # Build the code block via Python to avoid heredoc escaping issues
  local tmp_block
  tmp_block=$(CHOICES="$STACK_CHOICES" python3 << 'INNEREOF'
import os

STACKS = {
    "1": ("Python", [
        "pyenv install          # version pinned in .python-version",
        "uv sync                # install dependencies",
        "cp .env.example .env   # fill in the values",
    ]),
    "2": ("Node", [
        "nvm use                # version pinned in .nvmrc",
        "npm install",
        "cp .env.example .env   # fill in the values",
    ]),
    "3": ("Docker", [
        "docker compose up -d",
        "cp .env.example .env   # fill in the values",
    ]),
}

choices = os.environ.get("CHOICES", "").split()
blocks = []
for c in choices:
    if c == "4":
        break
    if c in STACKS:
        name, lines = STACKS[c]
        block = "# " + name + "\n" + "\n".join(lines)
        blocks.append(block)

if not blocks:
    print("SKIP")
else:
    print("```bash")
    print("\n\n".join(blocks))
    print("```")
INNEREOF
  )

  if [ "$tmp_block" = "SKIP" ] || [ -z "$tmp_block" ]; then
    echo -e "  ${YELLOW}skipped${NC}  CONTRIBUTING.md — fill in the tech stack section manually"
    return
  fi

  # Replace the placeholder in CONTRIBUTING.md
  BLOCK="$tmp_block" CONTRIBUTING="$contributing" python3 << 'INNEREOF'
import os
block = os.environ["BLOCK"]
path  = os.environ["CONTRIBUTING"]
with open(path) as f:
    content = f.read()
content = content.replace("<!-- TECH_STACK_SETUP_PLACEHOLDER -->", block)
with open(path, "w") as f:
    f.write(content)
INNEREOF

  echo -e "  ${GREEN}updated${NC}  CONTRIBUTING.md — tech stack section filled in"
  # Protect CONTRIBUTING.md from future updates overwriting the tech stack
  if ! grep -qxF "CONTRIBUTING.md" "$IGNORE_FILE" 2>/dev/null; then
    # Ensure file ends with a newline before appending
    [ -s "$IGNORE_FILE" ] && [ "$(tail -c1 "$IGNORE_FILE" | wc -l)" -eq 0 ] && echo "" >> "$IGNORE_FILE"
    echo "CONTRIBUTING.md" >> "$IGNORE_FILE"
    IGNORED_PATTERNS+=("CONTRIBUTING.md")
  fi
}


# ---- Create CLAUDE.local.md (personal preferences) -------------------------
# Interactive only. Generates a gitignored CLAUDE.local.md with personal
# Claude Code preferences (language, notes).

setup_claude_local() {
  [ "$CI_MODE" = true ] && return
  [ "$INSTALL_MODE" = "skills-only" ] && return 0

  local claude_local="$TARGET_DIR/CLAUDE.local.md"

  if [ -f "$claude_local" ]; then
    echo -e "  ok       CLAUDE.local.md already exists — skipping"
    return
  fi

  cat > "$claude_local" << 'MDEOF'
# Personal Claude Code preferences
# This file is gitignored — your local settings only, never committed.

## Personal notes

<!-- Add any personal context, reminders, or workflow rules here. -->
MDEOF

  echo -e "  ${GREEN}created${NC}  CLAUDE.local.md"
}

# ---- Walk the template directory and apply every file ----------------------

load_ignore_patterns

# ---- Pre-scan: list conflicts and (optionally) ask for a batch decision -----
# Always run except in plain --ci mode (no BATCH_ACTION set).

if [ "$CI_MODE" = false ] || [ -n "$BATCH_ACTION" ]; then
  _conflict_files=()
  while IFS= read -r -d '' _src; do
    _rel="${_src#$TEMPLATE_DIR/}"
    _dst="$TARGET_DIR/$_rel"
    is_ignored "$_rel" && continue
    [ -f "$_dst" ] || continue
    if [ "$INSTALL_MODE" = "skills-only" ]; then
      case "$_rel" in
        .claude/skills/*|.claude/hooks/*|doc/*) ;;
        *) continue ;;
      esac
    fi
    _nc=$(substitute < "$_src")
    _ec=$(cat "$_dst")
    [ "$_nc" != "$_ec" ] && _conflict_files+=("$_rel")
  done < <(find "$TEMPLATE_DIR" -type f -print0 | sort -z)
  unset _src _rel _dst _nc _ec

  if [ "${#_conflict_files[@]}" -gt 0 ]; then
    echo ""
    echo -e "${BOLD}${#_conflict_files[@]} file(s) differ from the template:${NC}"
    printf '  %s\n' "${_conflict_files[@]}"
    echo ""

    # Interactive run without a pre-set batch action: ask once
    if [ "$CI_MODE" = false ] && [ -z "$BATCH_ACTION" ]; then
      if [ "${#_conflict_files[@]}" -gt 1 ]; then
        read -rp "  [a]pply all / [s]kip all / [p]ick individually [default] ? " _choice
        case "$(echo "$_choice" | tr '[:upper:]' '[:lower:]')" in
          a) BATCH_ACTION="a" ;;
          s) BATCH_ACTION="s" ;;
        esac
        unset _choice
        echo ""
      fi
    fi
  fi
  unset _conflict_files
fi

while IFS= read -r -d '' src_file; do
  rel="${src_file#$TEMPLATE_DIR/}"
  apply_file "$src_file" "$rel"
done < <(find "$TEMPLATE_DIR" -type f -print0 | sort -z)

setup_tech_stack
setup_claude_local
ensure_project_statuses

# ---- Summary ---------------------------------------------------------------

echo ""
echo -e "${BOLD}Done.${NC}"
echo -e "  ${GREEN}created${NC}   $CREATED file(s)"
echo -e "  ${GREEN}updated${NC}   $UPDATED file(s)"
echo -e "  ok        $UNCHANGED file(s) unchanged"
[ "$SKIPPED"  -gt 0 ] && echo -e "  ${YELLOW}skipped${NC}   $SKIPPED file(s)"
[ "$IGNORED"  -gt 0 ] && echo -e "  ${BLUE}ignored${NC}   $IGNORED file(s)  (protected by .claude-github-config-ignore)"

[ "$INSTALL_MODE" = "skills-only" ] && echo -e "  ${BLUE}mode${NC}      skills & hooks & doc only"

if [ "$CI_MODE" = false ] && [ "$INSTALL_MODE" != "skills-only" ]; then
  echo ""
  echo -e "${BOLD}Next steps:${NC}"
  echo ""
  echo -e "  ${BOLD}1. Fill in doc/PROJECT.md${NC}  ← do this first"
  echo -e "     Claude Code loads this file at every session start."
  echo -e "     Ask Claude Code: ${BLUE}"fill in doc/PROJECT.md based on what you know about this project"${NC}"
  echo ""
  echo -e "  ${BOLD}2. Fill in CONTRIBUTING.md — tech stack section${NC}"
  echo -e "     Re-run the installer interactively to pick your stacks,"
  echo -e "     or edit the section manually."
  echo ""
  echo -e "  ${BOLD}3. Fill in CONTRIBUTING.md — section 9 repo structure${NC}"
  echo -e "     Ask Claude Code: ${BLUE}"document the repo structure for section 9 of CONTRIBUTING.md"${NC}"
  echo ""
  echo -e "  ${BOLD}4. Fill in CLAUDE.local.md${NC}  (gitignored — your personal preferences)"
  echo ""
  echo -e "  ${BOLD}5. Add GitHub secrets:${NC}"
  echo -e "     gh secret set PROJECT_PAT --repo $ORG/$REPO"
  echo -e "     gh secret set CONFIG_PAT  --repo $ORG/$REPO"
  echo ""
  echo -e "  ${BOLD}6. Commit:${NC}"
  echo -e "     git add . && git commit -m "chore: apply claude-github-config""
  echo ""
  echo -e "  Full reference: ${BLUE}doc/claude-github-config.md${NC}"
  echo ""
fi
