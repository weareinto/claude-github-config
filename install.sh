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
echo -e "${BOLD}=== claude-github-config installer ===${NC}"
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
    fi
  fi

  if [ -z "$ORG" ]; then
    ORG="weareinto"
    read -rp "$(echo -e "${BOLD}GitHub organization${NC} [${BOLD}weareinto${NC}]: ")" INPUT_ORG
    [ -n "$INPUT_ORG" ] && ORG="$INPUT_ORG"
  fi
  if [ -z "$REPO" ]; then
    read -rp "$(echo -e "${BOLD}Repository name${NC} (e.g. my-project): ")" REPO
  fi
  if [ -z "$PROJECT_NUMBER" ]; then
    read -rp "$(echo -e "${BOLD}GitHub Project board number${NC} (e.g. 15): ")" PROJECT_NUMBER
  fi

  echo ""
  echo -e "  ORG=${BOLD}$ORG${NC}  REPO=${BOLD}$REPO${NC}  PROJECT_NUMBER=${BOLD}$PROJECT_NUMBER${NC}"
  echo ""
  read -rp "Proceed? [y/N] " CONFIRM
  [[ "$CONFIRM" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }
fi

echo ""

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

  # Check ignore list first
  if is_ignored "$rel"; then
    echo -e "  ${BLUE}ignored${NC}  $rel  (in .claude-github-config-ignore)"
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
  diff --color=always <(echo "$existing_content") <(echo "$new_content") | head -30 | sed 's/^/    /'
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
      diff <(echo "$existing_content") <(echo "$new_content") | less
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

# ---- Walk the template directory and apply every file ----------------------

while IFS= read -r -d '' src_file; do
  rel="${src_file#$TEMPLATE_DIR/}"
  apply_file "$src_file" "$rel"
done < <(find "$TEMPLATE_DIR" -type f -print0 | sort -z)

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
  echo -e "  ${BOLD}1. Fill in doc/PROJECT.md${NC}  ← do this first"
  echo "     Claude Code loads this file at every session start."
  echo "     Without it, the AI has no context about what this project is."
  echo ""
  echo "  2. Add the PROJECT_PAT secret to your GitHub repo:"
  echo "     gh secret set PROJECT_PAT --repo $ORG/$REPO"
  echo ""
  echo "  3. Add the CONFIG_PAT secret (read access to claude-github-config):"
  echo "     gh secret set CONFIG_PAT --repo $ORG/$REPO"
  echo ""
  echo "  4. Verify your GitHub Project v2 board (#$PROJECT_NUMBER) has these Status columns:"
  echo "     Backlog → Ready → In progress → In review → Ready to deploy → Staging → Production → Done"
  echo ""
  echo "  5. Fill in the tech stack setup section in CONTRIBUTING.md."
  echo ""
  echo "  6. Create a CLAUDE.local.md (gitignored) with your personal Claude Code preferences."
  echo ""
  echo "  7. Commit the applied files:"
  echo "     git add . && git commit -m \"chore: apply claude-github-config\""
  echo ""
fi
