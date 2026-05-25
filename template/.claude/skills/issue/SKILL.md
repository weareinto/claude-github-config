---
name: issue
description: Create a new GitHub issue or update an existing one using this repo's templates
---

Create a new GitHub issue from one of this repo's templates, or rewrite an existing issue's body if an issue number is passed. The skill builds a body that matches the per-type template (required sections, optional sections, helper comments) and submits it via `gh`.

## Arguments

```
/issue [<ISSUE_NUMBER>] [--type <feature|bug|chore|research>] [--assignee <login>[,<login>...]]
```

- `ISSUE_NUMBER` (optional): if present, edit that issue instead of creating a new one. Pull the current title, body, labels, and assignees via `gh issue view`, preserve what's already filled, and only fill in what's missing or what the user asks to change.
- `--type` (optional): one of `feature`, `bug`, `chore`, `research`. If omitted on create, ask the user which template to use. If omitted on update, infer from the existing `type:*` label on the issue.
- `--assignee` (optional): GitHub login(s) to assign to the issue. Comma-separated for multiple. On create, sets the initial assignees; on update, **replaces** the current assignees with this set (use `@me` as a shorthand for the current user). Omit to leave assignees alone on update, or unassigned on create.

Examples:
- `/issue` — create a new issue, ask for the type.
- `/issue --type feature` — create a new feature issue, unassigned.
- `/issue --type bug --assignee qutaiba` — create a bug assigned to `qutaiba`.
- `/issue --type chore --assignee qutaiba,mehdimehni` — create a chore co-assigned.
- `/issue 123` — update existing issue #123, infer type from its label, leave assignees as-is.
- `/issue 123 --assignee @me` — reassign #123 to the current user.
- `/issue 123 --type bug` — update #123 and switch its type to bug (re-label and reshape the body).

## When to skip

If the user only wants to *comment* on an existing issue, use `gh issue comment` directly — don't run this skill.

## Required sections and checklist per type

These tables drive the body the skill produces. Required sections must be present with a `## <heading>` matching the table exactly and have non-empty content; the checklist below the body must contain every listed item as `- [ ]` (left unchecked at creation — the author ticks them after self-review).

| Type | Required sections | Checklist items |
|---|---|---|
| `feature` | `Summary / Overview`, `Goals`, `Approach & Plan` | `Summary/Overview written`, `Goals defined`, `Approach & Plan documented` |
| `bug` | `Summary / Overview`, `Current Behavior`, `Expected Behavior`, `Approach & Plan` | `Summary/Overview written`, `Current Behavior written`, `Expected Behavior written`, `Approach & Plan documented` |
| `chore` | `Summary / Overview` | `Summary/Overview written` |
| `research` | `Summary / Overview` | `Summary/Overview written` |

Optional sections (e.g. `Goals` on `chore`, `Steps to Reproduce` on `bug`, `References` on `research`) live in the templates and may be filled in or dropped per the author's judgment — they are not in the table above because they are not required.

For everything else (title prefix, label, section order, helper HTML comments), read the corresponding `.github/ISSUE_TEMPLATE/<type>.md` at runtime — the template is authoritative for presentation.

## Before drafting — mandatory for create

Before writing a single line of the issue body, complete both steps below. No exceptions.

1. **Ask clarifying questions first.** Identify every ambiguity in what the user described (auth, identifiers, edge cases, scope, affected components, expected behavior) and ask them all in a single block. Do not draft anything until you have enough context to write accurately.

2. **Explore the codebase for technical context.** For any technical point that could be verified from the code (existing auth patterns, relevant models, related endpoints, status enums, background tasks, etc.), search the repo before assuming. Use the findings to write a precise Approach & Plan — do not invent integration details that the code could have answered.

Only after both steps: proceed to the drafting steps below.

---

## Steps — create

1. Confirm the type. If `--type` was passed, use it. Otherwise ask the user.

2. Look up the type in the table above for required sections + checklist items, and read `.github/ISSUE_TEMPLATE/<type>.md` for title prefix, label, section order, optional sections, and HTML comment hints.

3. Gather content for each required section by asking the user once, in a single block. For features and bugs, also offer to draft the Approach & Plan from any context the user has already shared in this conversation.

4. Build the issue body:
   - Keep the section headings exactly as they appear in the table (`## Summary / Overview`, etc.) — don't paraphrase.
   - Drop the HTML comment placeholders (`<!-- ... -->`) once the section is filled.
   - Leave optional sections (those in the template but not in the table) as empty `## Heading` blocks if the user wants them retained, or omit them entirely if not.
   - Reproduce the checklist using the exact strings from the table, leaving every box **unchecked** (`- [ ]`).

5. Pick a clear, concise title with the right prefix (`[Feature] `, `[Bug] `, etc.). Title-case the rest, no trailing punctuation.

6. **Confirm before creating.** Show the user the proposed title, full body, and the assignee list (if `--assignee` was passed), then wait for explicit go-ahead or edits. Do not run `gh issue create` until the user has approved. If the user requests changes, revise and re-confirm.

7. Create the issue:
   ```
   gh issue create \
     --title "<title>" \
     --body-file <tmpfile> \
     --label "type:<type>" \
     [--assignee "<login>[,<login>...]"]
   ```
   - `auto-label.yml` will also add the type label based on the title prefix — passing `--label` here is belt-and-suspenders so the issue is correctly labeled even if the workflow lags.
   - Pass `--assignee` only if the user supplied logins. `gh` accepts comma-separated logins and the `@me` shorthand.

8. Return the issue URL to the user.

## Steps — update

1. Fetch the current issue:
   ```
   gh issue view <ISSUE_NUMBER> --json title,body,labels,assignees,number
   ```

2. Determine the type:
   - If `--type` was passed and it differs from the current `type:*` label, plan a re-label step and reshape the body to match the new template.
   - Otherwise infer from the existing `type:*` label.

3. Look up the resolved type in the table above for required sections + checklist, and read `.github/ISSUE_TEMPLATE/<type>.md` for layout / optional sections.

4. Reconcile the existing body with the template:
   - Preserve any non-empty section content the user has already written.
   - Add missing required sections, with the headings matching the table literally.
   - If the user described changes in this conversation, fold them into the right section(s).
   - Keep the checklist at the bottom. Preserve any boxes the user has already ticked; add boxes for sections that are now present.

5. If `--assignee` was passed, compute the assignee diff against the current assignees:
   - Logins to **add**: in the new set, not in the current set.
   - Logins to **remove**: in the current set, not in the new set.
   - If `--assignee` was *not* passed, leave assignees alone.

6. **Confirm before editing.** Show the user a before/after of the proposed title, body, label/type change (if any), and assignee changes (if any), then wait for explicit go-ahead or edits. Do not run `gh issue edit` until the user has approved. If the user requests changes, revise and re-confirm.

7. If the type changed, update labels:
   ```
   gh issue edit <ISSUE_NUMBER> --remove-label "type:<old>" --add-label "type:<new>"
   ```
   Also update the title prefix (`[Feature] ` → `[Bug] ` etc.) if it no longer matches.

8. Push the new body:
   ```
   gh issue edit <ISSUE_NUMBER> --title "<title>" --body-file <tmpfile>
   ```

9. If the assignee diff is non-empty, apply it:
   ```
   gh issue edit <ISSUE_NUMBER> \
     [--add-assignee "<login>[,<login>...]"] \
     [--remove-assignee "<login>[,<login>...]"]
   ```
   Pass only the flags that have logins to send. `@me` is allowed in `--add-assignee`.

10. Tell the user what changed.

## Notes

- Don't link the issue to a PR/branch from here — branches are independent of issues in this repo (see `CONTRIBUTING.md`). PRs close issues via `Closes #N` lines.
- For features touching both backend and skill_eval_agent, write one issue, not two — the `feature-ui` / `feature-backend` split was retired.
- If the per-type requirements change, update the table in this file and mirror the change in `.github/ISSUE_TEMPLATE/<type>.md`.
