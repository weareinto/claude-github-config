# Skills Configuration Reference

## Directory Structure

```
.claude/skills/<skill-name>/
  SKILL.md           # Main instructions (required)
  template.md        # Template for Claude to fill in
  examples/
    sample.md        # Example output
  scripts/
    validate.sh      # Script Claude can execute
```

## Where Skills Live

| Location   | Path                                       | Applies to                     |
|:-----------|:-------------------------------------------|:-------------------------------|
| Enterprise | Managed settings directory                 | All users in your organization |
| Personal   | `~/.claude/skills/<skill-name>/SKILL.md`   | All your projects              |
| Project    | `.claude/skills/<skill-name>/SKILL.md`     | This project only              |
| Plugin     | `<plugin>/skills/<skill-name>/SKILL.md`    | Where plugin is enabled        |

Priority: enterprise > personal > project. Plugin skills use `plugin-name:skill-name` namespace.

## Frontmatter Reference

All fields are optional. Only `description` is recommended.

```yaml
---
name: my-skill
description: What this skill does
when_to_use: Additional trigger context
argument-hint: "[issue-number]"
disable-model-invocation: true
user-invocable: false
allowed-tools: Read Grep Bash(git *)
model: sonnet
effort: high
context: fork
agent: Explore
shell: bash
paths: "src/**/*.ts, tests/**"
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate.sh"
---
```

### Field Details

| Field                      | Required    | Description                                                                                                     |
|:---------------------------|:------------|:----------------------------------------------------------------------------------------------------------------|
| `name`                     | No          | Display name. Lowercase letters, numbers, hyphens only (max 64 chars). Defaults to directory name.              |
| `description`              | Recommended | What the skill does. Claude uses this to decide when to apply it. Truncated at 1,536 chars in listing.          |
| `when_to_use`              | No          | Additional trigger phrases/examples. Appended to description, counts toward 1,536-char cap.                     |
| `argument-hint`            | No          | Hint shown during autocomplete. Example: `[issue-number]` or `[filename] [format]`.                            |
| `disable-model-invocation` | No          | `true` = only user can invoke via `/name`. Prevents Claude from auto-loading. Default: `false`.                 |
| `user-invocable`           | No          | `false` = hidden from `/` menu. For background knowledge only. Default: `true`.                                 |
| `allowed-tools`            | No          | Tools Claude can use without permission when skill is active. Space-separated string or YAML list.              |
| `model`                    | No          | Model to use when skill is active.                                                                              |
| `effort`                   | No          | Effort level: `low`, `medium`, `high`, `xhigh`, `max`. Overrides session effort level.                         |
| `context`                  | No          | Set to `fork` to run in a forked subagent context.                                                              |
| `agent`                    | No          | Which subagent type to use when `context: fork` is set (e.g., `Explore`, `Plan`, `general-purpose`, or custom). |
| `hooks`                    | No          | Hooks scoped to this skill's lifecycle.                                                                         |
| `paths`                    | No          | Glob patterns limiting when skill auto-activates. Comma-separated or YAML list.                                 |
| `shell`                    | No          | Shell for inline commands: `bash` (default) or `powershell`. Requires `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`.      |

## Invocation Control

| Frontmatter                      | User can invoke | Claude can invoke | Context loading                                              |
|:---------------------------------|:----------------|:------------------|:-------------------------------------------------------------|
| (default)                        | Yes             | Yes               | Description always in context, full skill loads when invoked |
| `disable-model-invocation: true` | Yes             | No                | Description not in context, full skill loads when you invoke |
| `user-invocable: false`          | No              | Yes               | Description always in context, full skill loads when invoked |

## String Substitutions

| Variable               | Description                                                          |
|:-----------------------|:---------------------------------------------------------------------|
| `$ARGUMENTS`           | All arguments passed when invoking the skill                         |
| `$ARGUMENTS[N]`        | Specific argument by 0-based index (e.g., `$ARGUMENTS[0]`)          |
| `$N`                   | Shorthand for `$ARGUMENTS[N]` (e.g., `$0`, `$1`)                    |
| `${CLAUDE_SESSION_ID}` | Current session ID                                                   |
| `${CLAUDE_SKILL_DIR}`  | Directory containing the skill's SKILL.md file                       |

## Dynamic Context Injection

Use `` !`command` `` to run shell commands before content is sent to Claude:

```yaml
---
name: pr-summary
context: fork
agent: Explore
---

PR diff: !`gh pr diff`
Changed files: !`gh pr diff --name-only`
```

Multi-line version with fenced code block:

````markdown
```!
node --version
npm --version
git status --short
```
````

Disable with `"disableSkillShellExecution": true` in settings.

## Skill Content Lifecycle

- Skill content enters as a single message and stays for the session
- Auto-compaction keeps first 5,000 tokens of each skill
- Combined budget of 25,000 tokens across all re-attached skills
- Most recently invoked skills have priority

## Permission Control

```text
# Allow specific skills
Skill(commit)
Skill(review-pr *)

# Deny specific skills (in deny rules)
Skill(deploy *)

# Disable all skills
Skill
```

## Examples

### Reference Skill (auto-invoked by Claude)

```yaml
---
name: api-conventions
description: API design patterns for this codebase
---

When writing API endpoints:
- Use RESTful naming conventions
- Return consistent error formats
```

### Task Skill (user-invoked only)

```yaml
---
name: deploy
description: Deploy the application to production
context: fork
disable-model-invocation: true
allowed-tools: Bash(*)
---

Deploy $ARGUMENTS to production:
1. Run tests
2. Build
3. Push to deployment target
```

### Skill with Supporting Files

```yaml
---
name: code-review
description: Review code against team standards
---

Review code following our standards.

## Additional resources
- For complete API details, see [reference.md](reference.md)
- For usage examples, see [examples.md](examples.md)
```
