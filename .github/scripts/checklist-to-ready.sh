#!/usr/bin/env bash
# Move an issue's project card from $FROM_STATUS to $TO_STATUS when every
# task-list item under the "## Ready Checklist" heading is checked.
#
# Bails (exit 0) — never fails the workflow — when:
#   - the section is missing or empty
#   - any item is still unchecked
#   - the issue is not on the configured Project
#   - the card's current Status is not $FROM_STATUS (so we never reset progress)
#
# Errors loudly when project metadata can't be resolved or the mutation fails.
#
# Required env:
#   GH_TOKEN           PAT with `project: write` and `repo: read`
#   ORG                org login (e.g. weareinto)
#   PROJECT_NUMBER     Project v2 number
#   ISSUE_NUMBER       the issue this run should evaluate
#   FROM_STATUS        Status option to move FROM (e.g. Backlog)
#   TO_STATUS          Status option to move TO (e.g. Ready)
#   GITHUB_REPOSITORY  <owner>/<repo>, set automatically by Actions

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${ORG:?ORG is required}"
: "${PROJECT_NUMBER:?PROJECT_NUMBER is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${FROM_STATUS:?FROM_STATUS is required}"
: "${TO_STATUS:?TO_STATUS is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

REPO_NAME="${GITHUB_REPOSITORY##*/}"

# ----- 1. Read the issue body and isolate the Ready Checklist section --------
BODY=$(gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUMBER" --jq '.body // ""')

if [ -z "$BODY" ]; then
  echo "Issue #$ISSUE_NUMBER has no body; nothing to evaluate."
  exit 0
fi

# Capture lines after `## Ready Checklist` until the next `## ` heading or EOF.
SECTION=$(awk '
  /^## Ready Checklist[[:space:]]*$/ { capturing = 1; next }
  /^## / && capturing { exit }
  capturing { print }
' <<<"$BODY")

if [ -z "${SECTION//[[:space:]]/}" ]; then
  echo "Issue #$ISSUE_NUMBER has no \"## Ready Checklist\" section; skipping."
  exit 0
fi

# Count task-list items (allow a leading whitespace indent for nested lists).
UNCHECKED=$(grep -cE '^[[:space:]]*-[[:space:]]+\[[[:space:]]\][[:space:]]' <<<"$SECTION" || true)
CHECKED=$(grep -cE '^[[:space:]]*-[[:space:]]+\[[xX]\][[:space:]]' <<<"$SECTION" || true)

if [ "$CHECKED" -eq 0 ]; then
  echo "Issue #$ISSUE_NUMBER has no checked items in Ready Checklist; skipping."
  exit 0
fi

if [ "$UNCHECKED" -gt 0 ]; then
  echo "Issue #$ISSUE_NUMBER still has $UNCHECKED unchecked item(s); not ready yet."
  exit 0
fi

echo "Issue #$ISSUE_NUMBER checklist is fully ticked ($CHECKED checked, 0 unchecked)."

# ----- 1b. Validate Design/Mockup section if present ------------------------
# If ## Design/Mockup header exists it must contain at least one URL before we promote.
# Gate on header presence (not content) so an empty section also blocks promotion.
DESIGN_HEADER_COUNT=$(grep -cE '^## Design/Mockup[[:space:]]*$' <<<"$BODY" || true)

if [ "$DESIGN_HEADER_COUNT" -gt 0 ]; then
  DESIGN_SECTION=$(awk '
    /^## Design\/Mockup[[:space:]]*$/ { capturing = 1; next }
    /^## / && capturing { exit }
    capturing { print }
  ' <<<"$BODY")

  if ! echo "$DESIGN_SECTION" | grep -qE 'https?://'; then
    echo "Issue #$ISSUE_NUMBER has a ## Design/Mockup section but no URL; not promoting to Ready."
    exit 0
  fi
  echo "Design/Mockup section contains a URL — OK."
fi

# ----- 2. Resolve project metadata in one round trip -------------------------
echo "Resolving Project v2 metadata for $ORG / project #$PROJECT_NUMBER..."

PROJECT_META=$(gh api graphql -f query='
  query($org: String!, $number: Int!) {
    organization(login: $org) {
      projectV2(number: $number) {
        id
        field(name: "Status") {
          ... on ProjectV2SingleSelectField {
            id
            options { id name }
          }
        }
      }
    }
  }
' -F org="$ORG" -F number="$PROJECT_NUMBER")

PROJECT_ID=$(jq -r '.data.organization.projectV2.id // empty' <<<"$PROJECT_META")
FIELD_ID=$(jq -r '.data.organization.projectV2.field.id // empty' <<<"$PROJECT_META")
FROM_OPTION_ID=$(jq -r --arg n "$FROM_STATUS" \
  '.data.organization.projectV2.field.options[]? | select(.name==$n) | .id' \
  <<<"$PROJECT_META")
TO_OPTION_ID=$(jq -r --arg n "$TO_STATUS" \
  '.data.organization.projectV2.field.options[]? | select(.name==$n) | .id' \
  <<<"$PROJECT_META")

if [ -z "$PROJECT_ID" ] || [ -z "$FIELD_ID" ]; then
  echo "::error::Could not resolve project '#$PROJECT_NUMBER' or its 'Status' field. Verify PROJECT_PAT scopes and PROJECT_NUMBER."
  exit 1
fi

if [ -z "$FROM_OPTION_ID" ] || [ -z "$TO_OPTION_ID" ]; then
  echo "::error::Status option '$FROM_STATUS' or '$TO_STATUS' does not exist on project #$PROJECT_NUMBER."
  exit 1
fi

# ----- 3. Find the issue's project item and read its current Status ---------
ITEM_QUERY=$(gh api graphql -f query='
  query($org: String!, $repo: String!, $number: Int!) {
    repository(owner: $org, name: $repo) {
      issue(number: $number) {
        projectItems(first: 20) {
          nodes {
            id
            project { id }
            fieldValueByName(name: "Status") {
              ... on ProjectV2ItemFieldSingleSelectValue { optionId }
            }
          }
        }
      }
    }
  }
' -F org="$ORG" -F repo="$REPO_NAME" -F number="$ISSUE_NUMBER")

ITEM_ID=$(jq -r --arg pid "$PROJECT_ID" \
  '.data.repository.issue.projectItems.nodes[]? | select(.project.id==$pid) | .id' \
  <<<"$ITEM_QUERY")
CURRENT_OPTION=$(jq -r --arg pid "$PROJECT_ID" \
  '.data.repository.issue.projectItems.nodes[]? | select(.project.id==$pid) | .fieldValueByName.optionId // empty' \
  <<<"$ITEM_QUERY")

if [ -z "$ITEM_ID" ]; then
  echo "Issue #$ISSUE_NUMBER is not on project #$PROJECT_NUMBER; skipping."
  exit 0
fi

if [ "$CURRENT_OPTION" != "$FROM_OPTION_ID" ]; then
  echo "Issue #$ISSUE_NUMBER is not in '$FROM_STATUS' (current option id: ${CURRENT_OPTION:-<unset>}); not promoting."
  exit 0
fi

# ----- 4. Promote -----------------------------------------------------------
gh api graphql -f query='
  mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
    updateProjectV2ItemFieldValue(
      input: {
        projectId: $projectId,
        itemId: $itemId,
        fieldId: $fieldId,
        value: { singleSelectOptionId: $optionId }
      }
    ) { projectV2Item { id } }
  }
' -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" \
   -F fieldId="$FIELD_ID" -F optionId="$TO_OPTION_ID" >/dev/null

echo "Issue #$ISSUE_NUMBER → $TO_STATUS"