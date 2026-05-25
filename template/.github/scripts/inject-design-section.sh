#!/usr/bin/env bash
# When needs:design is added to an issue:
#   1. Inject ## Design/Mockup section before ## Ready Checklist (idempotent).
#   2. Inject "- [ ] Design/Mockup complete" into ## Ready Checklist (idempotent).
#   3. If the project card is already past Backlog, post a warning comment.
#
# Bails (exit 0) — never fails the workflow — when:
#   - the issue has no body
#   - the issue is not on the configured project (for the status check)
#
# If ## Design/Mockup already exists, the script skips injection but still
# continues to the project-status check / warning logic.
#
# Required env:
#   GH_TOKEN           GITHUB_TOKEN with issues:write (body update + comment)
#   PROJECT_PAT        Fine-grained PAT with project:write + repo:read (status check)
#   ISSUE_NUMBER
#   ORG
#   PROJECT_NUMBER
#   GITHUB_REPOSITORY  set automatically by Actions

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${ORG:?ORG is required}"
: "${PROJECT_NUMBER:?PROJECT_NUMBER is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

REPO_NAME="${GITHUB_REPOSITORY##*/}"
INJECTED=false
NEEDS_MANUAL_ADD=false

# ----- 1. Read current body --------------------------------------------------
BODY=$(GH_TOKEN="$GH_TOKEN" gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUMBER" --jq '.body // ""')

if [ -z "$BODY" ]; then
  echo "Issue #$ISSUE_NUMBER has no body; nothing to inject."
  NEEDS_MANUAL_ADD=true
else
  # ----- 2. Idempotency check ------------------------------------------------
  if echo "$BODY" | grep -q "^## Design/Mockup"; then
    echo "Design/Mockup section already exists on issue #$ISSUE_NUMBER; skipping injection."
  else
    # Write body to a temp file to avoid shell quoting issues in Python.
    BODY_FILE=$(mktemp)
    NEW_BODY_FILE=$(mktemp)
    STATUS_FILE=$(mktemp)
    trap 'rm -f "$BODY_FILE" "$NEW_BODY_FILE" "$STATUS_FILE"' EXIT

    printf '%s' "$BODY" > "$BODY_FILE"

    BODY_FILE="$BODY_FILE" NEW_BODY_FILE="$NEW_BODY_FILE" STATUS_FILE="$STATUS_FILE" python3 << 'PYEOF'
import os

with open(os.environ['BODY_FILE']) as f:
    body = f.read()

lines = body.split('\n')

DESIGN_HEADER = '## Design/Mockup'
DESIGN_PLACEHOLDER = '<!-- Add a Figma link or Claude Design mockup link. -->'
CHECKLIST_ITEM = '- [ ] Design/Mockup complete'

# Pass 1: inject ## Design/Mockup section before ## Ready Checklist.
with_section = []
for line in lines:
    if line.strip() == '## Ready Checklist':
        with_section.extend([DESIGN_HEADER, '', DESIGN_PLACEHOLDER, ''])
    with_section.append(line)

# Pass 2: inject checklist item at the end of ## Ready Checklist section.
result = []
in_checklist = False
item_injected = False

for line in with_section:
    if line.strip() == '## Ready Checklist':
        in_checklist = True
        result.append(line)
        continue
    if in_checklist and line.startswith('## ') and not item_injected:
        result.append(CHECKLIST_ITEM)
        item_injected = True
        in_checklist = False
    result.append(line)

if in_checklist and not item_injected:
    result.append(CHECKLIST_ITEM)

new_body = '\n'.join(result)
with open(os.environ['NEW_BODY_FILE'], 'w') as f:
    f.write(new_body)

# Write status so the shell can check without fighting set -e exit codes.
with open(os.environ['STATUS_FILE'], 'w') as f:
    f.write('changed' if new_body != body else 'unchanged')
PYEOF

    if [ "$(cat "$STATUS_FILE")" = "unchanged" ]; then
      echo "Issue #$ISSUE_NUMBER has no ## Ready Checklist section; nothing to inject."
      NEEDS_MANUAL_ADD=true
    else
      NEW_BODY=$(cat "$NEW_BODY_FILE")

      GH_TOKEN="$GH_TOKEN" gh api --method PATCH \
        "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUMBER" \
        --field "body=$NEW_BODY" > /dev/null

      INJECTED=true
      echo "Issue #$ISSUE_NUMBER: injected ## Design/Mockup section and checklist item."
    fi
  fi
fi

# ----- 3. Check project status and warn if past Backlog ----------------------
if [ -z "${PROJECT_PAT:-}" ]; then
  echo "::warning::PROJECT_PAT not set; skipping project status check."
  exit 0
fi

PROJECT_META=$(GH_TOKEN="$PROJECT_PAT" gh api graphql -f query='
  query($org: String!, $number: Int!) {
    organization(login: $org) {
      projectV2(number: $number) {
        id
        field(name: "Status") {
          ... on ProjectV2SingleSelectField {
            options { id name }
          }
        }
      }
    }
  }
' -F org="$ORG" -F number="$PROJECT_NUMBER")

PROJECT_ID=$(jq -r '.data.organization.projectV2.id // empty' <<<"$PROJECT_META")
BACKLOG_OPTION_ID=$(jq -r '.data.organization.projectV2.field.options[]? | select(.name=="Backlog") | .id' <<<"$PROJECT_META")

if [ -z "$PROJECT_ID" ]; then
  echo "::warning::Could not resolve project metadata; skipping status check."
  exit 0
fi

ITEM_QUERY=$(GH_TOKEN="$PROJECT_PAT" gh api graphql -f query='
  query($org: String!, $repo: String!, $number: Int!) {
    repository(owner: $org, name: $repo) {
      issue(number: $number) {
        projectItems(first: 20) {
          nodes {
            id
            project { id }
            fieldValueByName(name: "Status") {
              ... on ProjectV2ItemFieldSingleSelectValue { optionId name }
            }
          }
        }
      }
    }
  }
' -F org="$ORG" -F repo="$REPO_NAME" -F number="$ISSUE_NUMBER")

CURRENT_OPTION_ID=$(jq -r --arg pid "$PROJECT_ID" \
  '.data.repository.issue.projectItems.nodes[]? | select(.project.id==$pid) | .fieldValueByName.optionId // empty' \
  <<<"$ITEM_QUERY")
CURRENT_STATUS=$(jq -r --arg pid "$PROJECT_ID" \
  '.data.repository.issue.projectItems.nodes[]? | select(.project.id==$pid) | .fieldValueByName.name // empty' \
  <<<"$ITEM_QUERY")

if [ -z "$CURRENT_OPTION_ID" ] || [ "$CURRENT_OPTION_ID" = "$BACKLOG_OPTION_ID" ]; then
  if [ "$NEEDS_MANUAL_ADD" = "true" ]; then
    GH_TOKEN="$GH_TOKEN" gh api --method POST \
      "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUMBER/comments" \
      --field "body=:warning: \`needs:design\` was added but the \`## Design/Mockup\` section could not be auto-injected (body may be empty or missing a \`## Ready Checklist\` section). Please add it manually before continuing." \
      > /dev/null
    echo "Issue #$ISSUE_NUMBER: injection failed; manual-add warning comment posted."
  else
    echo "Issue #$ISSUE_NUMBER is in Backlog or not on the board; no comment needed."
  fi
  exit 0
fi

if [ "$INJECTED" = "true" ]; then
  INJECT_NOTE="A \`## Design/Mockup\` section and checklist item have been injected into the issue body. Please complete the mockup before continuing."
else
  INJECT_NOTE="The \`## Design/Mockup\` section could not be auto-injected (body may be empty or missing a \`## Ready Checklist\` section). Please add it manually before continuing."
fi

GH_TOKEN="$GH_TOKEN" gh api --method POST \
  "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUMBER/comments" \
  --field "body=:warning: \`needs:design\` was added while this issue is already in **${CURRENT_STATUS}**. ${INJECT_NOTE}" \
  > /dev/null

echo "Issue #$ISSUE_NUMBER is in '${CURRENT_STATUS}'; warning comment posted."
