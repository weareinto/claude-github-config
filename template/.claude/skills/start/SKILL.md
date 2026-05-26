---
name: start
description: Guided 4-step pre-implementation gate — verify ticket exists, status is Ready, create linked branch, move card to In progress. Run before any code changes. Uses {{ORG}}, {{REPO}}, {{PROJECT_NUMBER}} — substituted at install time.
---

Guides the contributor through the mandatory 4-step pre-implementation gate defined in CONTRIBUTING.md § 4. Run this skill whenever you are about to start work on a GitHub issue.

## Arguments

```
/start [ISSUE_NUMBER]
```

- `ISSUE_NUMBER` (optional): the GitHub issue number to start working on. If omitted, ask the user which issue to work on.

## Steps

### Step 1 — Ticket exists

If no `ISSUE_NUMBER` was provided, ask the user: "Which GitHub issue are you starting work on?"

Once you have a number, fetch the issue:

```bash
gh issue view <ISSUE_NUMBER> --json number,title,state,labels,projectItems,body
```

If the issue does not exist or is already closed, stop and tell the user.

### Step 2 — Ticket is in Ready status

Check the issue's current project card status on Project board #15 (project ID resolved via GraphQL if needed):

```bash
gh issue view <ISSUE_NUMBER> --json projectItems
```

Parse `projectItems[].status.name` for the item on project #15.

**If status is Ready** → proceed to Step 3.

**If status is In progress** → warn the user that the ticket already has implementation underway (possibly on another branch, or a previous `/start` run), and ask them to confirm before continuing. The pre-implementation checklist (CONTRIBUTING.md § 4) gates on `Ready`; rerunning on an `In progress` ticket is supported only as a recovery path (e.g., lost branch, new contributor picking up abandoned work).

**If status is Backlog** → stop and explain:

> "Issue #N is still in **Backlog**. The Definition of Ready is not yet satisfied. Here is what's missing:"

Then inspect the issue body:
- List any required sections that are empty or absent (per CONTRIBUTING.md § 3, see the DoR matrix for the issue's type).
- List unchecked `- [ ]` items in `## Ready Checklist`.
- If `needs:design` label is present but `## Design/Mockup` section has no URL, flag it.

Offer to help fill in the missing sections. Do not proceed until the card is in Ready status.

**If status is any other in-flight status (In review, Ready to deploy, etc.)** → warn the user that the ticket appears to already have downstream work, and ask them to confirm before continuing.

### Step 3 — Create the branch

Use the `/branch` skill to create the branch and link it to the issue:

```
/branch --issues <ISSUE_NUMBER> --link
```

The `--link` flag is required — it triggers `gh issue develop` which registers the branch in the issue's Development sidebar. Without `--link`, `/branch` creates a local branch via `git checkout -b` and no sidebar link is created.

If the `/branch` skill is unavailable, fall back to `gh issue develop` directly (the `--checkout` flag creates the branch on the remote and checks it out locally in one step):

```bash
gh issue develop <ISSUE_NUMBER> --name "<type>/<github_username>/<short-slug>" --checkout
```

Confirm the branch name with the user before running.

### Step 4 — Move card to In progress

If the card is already **In progress** (from Step 2), skip this step — the status is already correct.

Otherwise, update the issue's project card status from Ready to **In progress** via the GitHub Project v2 GraphQL API:

```bash
# 1. Resolve project metadata
gh api graphql -f query='
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
' -F org="{{ORG}}" -F number={{PROJECT_NUMBER}}

# 2. Resolve the item ID for this issue
gh api graphql -f query='
  query($org: String!, $repo: String!, $number: Int!) {
    repository(owner: $org, name: $repo) {
      issue(number: $number) {
        projectItems(first: 10) {
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
' -F org="{{ORG}}" -F repo="{{REPO}}" -F number=<ISSUE_NUMBER>

# 3. Mutate status to In progress
gh api graphql -f query='
  mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
    updateProjectV2ItemFieldValue(
      input: {
        projectId: $projectId
        itemId: $itemId
        fieldId: $fieldId
        value: { singleSelectOptionId: $optionId }
      }
    ) { projectV2Item { id } }
  }
' -F projectId="<PROJECT_ID>" -F itemId="<ITEM_ID>" \
  -F fieldId="<STATUS_FIELD_ID>" -F optionId="<IN_PROGRESS_OPTION_ID>"
```

Confirm to the user: "Issue #N is now **In progress** on the project board."

### Done

Report a summary:

```
✔ Issue #N: <title>
✔ Status: In progress
✔ Branch: <branch-name>

Implementation may now begin.
```
