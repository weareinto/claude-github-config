#!/usr/bin/env bash
# Add a PR to Project v2 and set its Status to "In review".
#
# Called on pull_request: [opened, reopened].
# addProjectV2ItemById is idempotent — if the PR is already on the board it
# returns the existing item id, so re-runs on reopened PRs are safe.
#
# Bails (exit 0) — never fails the workflow — when:
#   - PROJECT_PAT is not set
#   - any GraphQL call fails (auth, rate limit, transient outage)
#   - project metadata can't be resolved
#   - the PR is not found on the project after add (edge case)
#
# Required env:
#   PROJECT_PAT      Fine-grained PAT with project:write + repo:read
#   PR_NODE_ID       node_id of the pull request
#   ORG              org login (e.g. weareinto)
#   PROJECT_NUMBER   Project v2 number

set -euo pipefail

# PROJECT_PAT: soft check — missing secret should skip, not fail the job.
if [ -z "${PROJECT_PAT:-}" ]; then
  echo "::warning::PROJECT_PAT is not set; skipping project assignment."
  exit 0
fi

: "${PR_NODE_ID:?PR_NODE_ID is required}"
: "${ORG:?ORG is required}"
: "${PROJECT_NUMBER:?PROJECT_NUMBER is required}"

# ----- 1. Resolve project metadata -------------------------------------------
echo "Resolving Project v2 metadata for $ORG / project #$PROJECT_NUMBER..."

if ! PROJECT_META=$(GH_TOKEN="$PROJECT_PAT" gh api graphql -f query='
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
' -F org="$ORG" -F number="$PROJECT_NUMBER" 2>&1); then
  echo "::warning::GraphQL call failed while resolving project metadata: $PROJECT_META"
  exit 0
fi

PROJECT_ID=$(jq -r '.data.organization.projectV2.id // empty' <<<"$PROJECT_META")
FIELD_ID=$(jq -r '.data.organization.projectV2.field.id // empty' <<<"$PROJECT_META")
IN_REVIEW_OPTION_ID=$(jq -r '.data.organization.projectV2.field.options[]? | select(.name=="In review") | .id' <<<"$PROJECT_META")

if [ -z "$PROJECT_ID" ] || [ -z "$FIELD_ID" ]; then
  echo "::warning::Could not resolve project '#$PROJECT_NUMBER' or its 'Status' field. Verify PROJECT_PAT scopes and PROJECT_NUMBER."
  exit 0
fi

if [ -z "$IN_REVIEW_OPTION_ID" ]; then
  echo "::warning::Status option 'In review' does not exist on project #$PROJECT_NUMBER. Check the board configuration."
  exit 0
fi

# ----- 2. Add PR to project (idempotent) -------------------------------------
echo "Adding PR ($PR_NODE_ID) to project #$PROJECT_NUMBER..."

if ! ITEM_ID=$(GH_TOKEN="$PROJECT_PAT" gh api graphql -f query='
  mutation($projectId: ID!, $contentId: ID!) {
    addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
      item { id }
    }
  }
' -F projectId="$PROJECT_ID" -F contentId="$PR_NODE_ID" \
  --jq '.data.addProjectV2ItemById.item.id // empty' 2>&1); then
  echo "::warning::GraphQL call failed while adding PR to project: $ITEM_ID"
  exit 0
fi

if [ -z "$ITEM_ID" ]; then
  echo "::warning::addProjectV2ItemById returned no item id; skipping status update."
  exit 0
fi

echo "Project item id: $ITEM_ID"

# ----- 3. Set Status → "In review" ------------------------------------------
if ! GH_TOKEN="$PROJECT_PAT" gh api graphql -f query='
  mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId,
      itemId: $itemId,
      fieldId: $fieldId,
      value: { singleSelectOptionId: $optionId }
    }) { projectV2Item { id } }
  }
' -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" \
  -F fieldId="$FIELD_ID" -F optionId="$IN_REVIEW_OPTION_ID" > /dev/null 2>&1; then
  echo "::warning::GraphQL call failed while setting Status to 'In review'."
  exit 0
fi

echo "PR added to project #$PROJECT_NUMBER and status set to 'In review'."
