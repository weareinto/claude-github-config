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

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ---- Parse flags -----------------------------------------------------------

CI_MODE=false
for arg in "$@"; do
  case "$arg" in
    --ci) CI_MODE=true ;;
  esac
done

TARGET_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"
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
# Files in .claude-github-config-ignore are never overwritten by the installer.

is_ignored() {
  local rel="$1"
  if [ ! -f "$IGNORE_FILE" ]; then
    return 1
  fi
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    # Skip empty lines and comments
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    # Simple glob match against the relative path
    # shellcheck disable=SC2254
    case "$rel" in
      $pattern) return 0 ;;
    esac
  done < "$IGNORE_FILE"
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
  read -rp "    [o]verwrite / [s]kip / [i]gnore permanently / [d]iff full ? " CHOICE
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
      read -rp "    [o]verwrite / [s]kip / [i]gnore permanently ? " CHOICE2
      case "$CHOICE2" in
        [oO])
          printf '%s' "$new_content" > "$dst"
          [[ "$src" == *.sh ]] && chmod +x "$dst"
          echo -e "    ${GREEN}overwritten${NC}"
          UPDATED=$((UPDATED + 1))
          ;;
        [iI])
          echo "$rel" >> "$IGNORE_FILE"
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

  local contributing="$TARGET_DIR/CONTRIBUTING.md"
  [ -f "$contributing" ] || return
  grep -q "TECH_STACK_SETUP_PLACEHOLDER" "$contributing" || return

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
  fi
}


# ---- Create CLAUDE.local.md (personal preferences) -------------------------
# Interactive only. Generates a gitignored CLAUDE.local.md with personal
# Claude Code preferences (language, notes).

setup_claude_local() {
  [ "$CI_MODE" = true ] && return

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

if [ "$CI_MODE" = false ]; then
  echo ""
  echo -e "${BOLD}Next steps:${NC}"
  echo ""
  echo -e "  See the configuration reference installed in this repo:"
  echo -e "  ${BLUE}doc/claude-github-config.md${NC}"
  echo ""
fi
