#!/usr/bin/env bash
# Move linked issues' project cards to a target Status column.
#
# Walks BEFORE_SHA..AFTER_SHA, finds each commit's merge PR, reads each PR's
# `closingIssuesReferences`, and for every distinct linked issue, calls
# `updateProjectV2ItemFieldValue` to set Status to STATUS_NAME on the
# configured Project.
#
# Required env:
#   GH_TOKEN          PAT with `project: write` and `repo: read`
#   ORG               org login (e.g. weareinto)
#   PROJECT_NUMBER    Project v2 number
#   STATUS_NAME       target Status option name (e.g. Staging, Production)
#   BEFORE_SHA        SHA before the push (all zeros on first push)
#   AFTER_SHA         SHA after the push
#   GITHUB_REPOSITORY <owner>/<repo>, set automatically by Actions

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${ORG:?ORG is required}"
: "${PROJECT_NUMBER:?PROJECT_NUMBER is required}"
: "${STATUS_NAME:?STATUS_NAME is required}"
: "${BEFORE_SHA:?BEFORE_SHA is required}"
: "${AFTER_SHA:?AFTER_SHA is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

REPO_NAME="${GITHUB_REPOSITORY##*/}"

# ----- 1. Resolve project metadata in one round trip --------------------------
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
OPTION_ID=$(jq -r --arg name "$STATUS_NAME" \
  '.data.organization.projectV2.field.options[]? | select(.name==$name) | .id' \
  <<<"$PROJECT_META")

if [ -z "$PROJECT_ID" ] || [ -z "$FIELD_ID" ]; then
  echo "::error::Could not resolve project '#$PROJECT_NUMBER' or its 'Status' field. Verify PROJECT_PAT has 'project' + 'repo' scopes and PROJECT_NUMBER is correct."
  exit 1
fi

if [ -z "$OPTION_ID" ]; then
  echo "::error::Status option '$STATUS_NAME' does not exist on project #$PROJECT_NUMBER. Add the column to the project, or update the workflow's branch→status mapping."
  exit 1
fi

# ----- 2. Determine commit range ----------------------------------------------
if [ "$BEFORE_SHA" = "0000000000000000000000000000000000000000" ]; then
  echo "First push to this branch; treating only AFTER_SHA as new."
  COMMIT_RANGE="$AFTER_SHA"
else
  COMMIT_RANGE="${BEFORE_SHA}..${AFTER_SHA}"
fi

# ----- 3. Walk commits → merge PRs → linked issues ----------------------------
mapfile -t COMMITS < <(git rev-list "$COMMIT_RANGE" 2>/dev/null || true)
echo "Walking ${#COMMITS[@]} commit(s) in $COMMIT_RANGE..."

# Explicit `=()` initializer is required: under `set -u`, an associative array
# declared without one is treated as "unbound" by `${#arr[@]}` when no keys are
# ever assigned, which crashes the workflow on pushes whose commits don't
# resolve to any linked issues.
declare -A SEEN_ISSUES=()
declare -A SEEN_PRS=()

# Long-lived deployment branches. A PR whose head AND base are both in this
# set is a sync/promotion PR (e.g. `main → staging`). Squash-merging such a
# PR collapses many feature commits into one on the deployment branch, hiding
# the original `Closes #N` references behind a sync PR with an empty body.
# We detect this case and recurse into the sync PR's commit list to find the
# original feature PRs that were rolled up.
DEPLOY_BRANCHES_RE='^(main|staging|production)$'

# collect_issues_for_pr <pr_number>
#
# Records every issue closed by the given PR into SEEN_ISSUES. If the PR is a
# sync/promotion PR, recurses into its commits to find the original feature
# PRs first. SEEN_PRS guards against reprocessing the same PR or pathological
# cycles in commit history.
collect_issues_for_pr() {
  local pr_number="$1"

  if [ -n "${SEEN_PRS[$pr_number]:-}" ]; then
    return 0
  fi
  SEEN_PRS["$pr_number"]=1

  local pr_meta head_ref base_ref
  pr_meta=$(gh pr view "$pr_number" \
    --json headRefName,baseRefName,closingIssuesReferences 2>/dev/null) || {
    echo "  Could not read PR #$pr_number; skipping."
    return 0
  }
  head_ref=$(jq -r '.headRefName' <<<"$pr_meta")
  base_ref=$(jq -r '.baseRefName' <<<"$pr_meta")

  if [[ "$head_ref" =~ $DEPLOY_BRANCHES_RE ]] && \
     [[ "$base_ref" =~ $DEPLOY_BRANCHES_RE ]]; then
    echo "  PR #$pr_number is a $head_ref → $base_ref sync; unwrapping its commits."
    while read -r inner_sha; do
      [ -z "$inner_sha" ] && continue
      local inner_pr
      inner_pr=$(gh api "repos/$GITHUB_REPOSITORY/commits/$inner_sha/pulls" \
        --jq '.[0].number // empty' 2>/dev/null || true)
      if [ -n "$inner_pr" ]; then
        collect_issues_for_pr "$inner_pr"
      fi
    done < <(gh api "repos/$GITHUB_REPOSITORY/pulls/$pr_number/commits" \
      --paginate --jq '.[].sha' 2>/dev/null || true)
    return 0
  fi

  while read -r issue; do
    [ -z "$issue" ] && continue
    SEEN_ISSUES["$issue"]=1
  done < <(jq -r '.closingIssuesReferences[].number' <<<"$pr_meta" 2>/dev/null || true)
}

for sha in "${COMMITS[@]}"; do
  pr_number=$(gh api "repos/$GITHUB_REPOSITORY/commits/$sha/pulls" \
    --jq '.[0].number // empty' 2>/dev/null || true)
  if [ -z "$pr_number" ]; then
    continue
  fi
  collect_issues_for_pr "$pr_number"
done

if [ ${#SEEN_ISSUES[@]} -eq 0 ]; then
  echo "No linked issues found in this push; nothing to update."
  exit 0
fi

echo "Linked issues to update: ${!SEEN_ISSUES[*]}"

# ----- 4. For each issue, look up its project item and set Status -------------
for issue in "${!SEEN_ISSUES[@]}"; do
  ITEM_QUERY=$(gh api graphql -f query='
    query($org: String!, $repo: String!, $number: Int!) {
      repository(owner: $org, name: $repo) {
        issue(number: $number) {
          projectItems(first: 20) {
            nodes {
              id
              project { id }
            }
          }
        }
      }
    }
  ' -F org="$ORG" -F repo="$REPO_NAME" -F number="$issue")

  ITEM_ID=$(jq -r --arg pid "$PROJECT_ID" \
    '.data.repository.issue.projectItems.nodes[]? | select(.project.id==$pid) | .id' \
    <<<"$ITEM_QUERY")

  if [ -z "$ITEM_ID" ]; then
    echo "Issue #$issue is not on project #$PROJECT_NUMBER; skipping."
    continue
  fi

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
     -F fieldId="$FIELD_ID" -F optionId="$OPTION_ID" >/dev/null

  echo "Updated issue #$issue → $STATUS_NAME"
done

echo "Done."