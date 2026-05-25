#!/usr/bin/env bash
# install.sh — apply weareinto/claude-github-config to the current repository.
#
# Works for new and existing projects alike:
#   - New files are created directly.
#   - Existing files show a diff and ask before overwriting.
#   - Running it again is safe (idempotent).
#
# Usage:
#   1. Clone this repo: git clone https://github.com/weareinto/claude-github-config.git
#   2. cd into your target project
#   3. bash /path/to/claude-github-config/install.sh
#
# Or one-liner (always fetches latest):
#   bash <(curl -fsSL https://raw.githubusercontent.com/weareinto/claude-github-config/main/install.sh)

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

TARGET_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"

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

# ---- Gather project-specific values ----------------------------------------

read -rp "$(echo -e "${BOLD}GitHub organization${NC} (e.g. weareinto): ")" ORG
read -rp "$(echo -e "${BOLD}Repository name${NC} (e.g. my-project): ")" REPO
read -rp "$(echo -e "${BOLD}GitHub Project board number${NC} (e.g. 15): ")" PROJECT_NUMBER

echo ""
echo -e "  ORG=${BOLD}$ORG${NC}  REPO=${BOLD}$REPO${NC}  PROJECT_NUMBER=${BOLD}$PROJECT_NUMBER${NC}"
echo ""
read -rp "Proceed? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }
echo ""

SKIPPED=0
CREATED=0
UPDATED=0
UNCHANGED=0

# ---- Substitute placeholders in content ------------------------------------

substitute() {
  sed \
    -e "s|{{ORG}}|$ORG|g" \
    -e "s|{{REPO}}|$REPO|g" \
    -e "s|{{PROJECT_NUMBER}}|$PROJECT_NUMBER|g"
}

# ---- Apply a single file ---------------------------------------------------

apply_file() {
  local src="$1"
  local rel="$2"           # relative path within the project
  local dst="$TARGET_DIR/$rel"
  local dst_dir
  dst_dir="$(dirname "$dst")"

  local new_content
  new_content=$(substitute < "$src")

  mkdir -p "$dst_dir"

  if [ ! -f "$dst" ]; then
    printf '%s' "$new_content" > "$dst"
    # Preserve executable bit for shell scripts.
    [[ "$src" == *.sh ]] && chmod +x "$dst"
    echo -e "  ${GREEN}created${NC}  $rel"
    CREATED=$((CREATED + 1))
    return
  fi

  local existing_content
  existing_content="$(cat "$dst")"

  if [ "$new_content" = "$existing_content" ]; then
    echo -e "  ${NC}ok${NC}       $rel"
    UNCHANGED=$((UNCHANGED + 1))
    return
  fi

  echo -e "  ${YELLOW}conflict${NC} $rel (already exists — showing diff)"
  diff --color=always <(echo "$existing_content") <(echo "$new_content") | head -30 | sed 's/^/    /'
  echo ""
  read -rp "    Overwrite? [y/N/d=full diff] " CHOICE
  case "$CHOICE" in
    [yY])
      printf '%s' "$new_content" > "$dst"
      [[ "$src" == *.sh ]] && chmod +x "$dst"
      echo -e "    ${GREEN}overwritten${NC}"
      UPDATED=$((UPDATED + 1))
      ;;
    [dD])
      diff <(echo "$existing_content") <(echo "$new_content") | less
      read -rp "    Overwrite now? [y/N] " CHOICE2
      if [[ "$CHOICE2" =~ ^[yY]$ ]]; then
        printf '%s' "$new_content" > "$dst"
        [[ "$src" == *.sh ]] && chmod +x "$dst"
        echo -e "    ${GREEN}overwritten${NC}"
        UPDATED=$((UPDATED + 1))
      else
        echo -e "    ${YELLOW}skipped${NC}"
        SKIPPED=$((SKIPPED + 1))
      fi
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
echo -e "  ${NC}unchanged${NC} $UNCHANGED file(s)"
[ "$SKIPPED" -gt 0 ] && echo -e "  ${YELLOW}skipped${NC}   $SKIPPED file(s)"

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Add the PROJECT_PAT secret to your GitHub repo:"
echo "     gh secret set PROJECT_PAT --repo $ORG/$REPO"
echo ""
echo "  2. Create the GitHub Project board (if not already done):"
echo "     https://github.com/orgs/$ORG/projects/new"
echo "     → set the number to $PROJECT_NUMBER in the workflow env vars"
echo ""
echo "  3. Create a CLAUDE.local.md (gitignored) with your personal preferences."
echo ""
echo "  4. Review CONTRIBUTING.md and fill in the tech stack section."
echo ""
