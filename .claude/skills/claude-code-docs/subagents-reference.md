# Sub-agents Configuration Reference

## Overview

Subagents are specialized AI assistants that run in their own context window with custom system prompts, specific tool access, and independent permissions.

## Built-in Subagents

| Agent             | Model   | Tools      | Purpose                                      |
|:------------------|:--------|:-----------|:---------------------------------------------|
| Explore           | Haiku   | Read-only  | File discovery, code search, codebase exploration |
| Plan              | Inherit | Read-only  | Codebase research for planning               |
| general-purpose   | Inherit | All tools  | Complex research, multi-step operations      |
| statusline-setup  | Sonnet  | Read, Edit | Configure status line                        |
| Claude Code Guide | Haiku   | Read-only  | Answer questions about Claude Code features  |

## Where Subagents Live

| Location                     | Scope              | Priority    |
|:-----------------------------|:-------------------|:------------|
| Managed settings             | Organization-wide  | 1 (highest) |
| `--agents` CLI flag          | Current session    | 2           |
| `.claude/agents/`            | Current project    | 3           |
| `~/.claude/agents/`          | All your projects  | 4           |
| Plugin's `agents/` directory | Where plugin enabled | 5 (lowest) |

## File Format

```markdown
---
name: code-reviewer
description: Reviews code for quality and best practices
tools: Read, Glob, Grep
model: sonnet
---

You are a code reviewer. Analyze the code and provide
specific, actionable feedback on quality, security, and best practices.
```

The frontmatter defines configuration. The body becomes the system prompt.

## Supported Frontmatter Fields

| Field             | Required | Description                                                                                                |
|:------------------|:---------|:-----------------------------------------------------------------------------------------------------------|
| `name`            | Yes      | Unique identifier using lowercase letters and hyphens                                                      |
| `description`     | Yes      | When Claude should delegate to this subagent                                                               |
| `tools`           | No       | Tools the subagent can use. Inherits all tools if omitted                                                  |
| `disallowedTools` | No       | Tools to deny, removed from inherited or specified list                                                    |
| `model`           | No       | `sonnet`, `opus`, `haiku`, full model ID (e.g. `claude-opus-4-7`), or `inherit`. Default: `inherit`       |
| `permissionMode`  | No       | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, or `plan`                               |
| `maxTurns`        | No       | Maximum agentic turns before the subagent stops                                                            |
| `skills`          | No       | Skills to preload into context at startup (full content injected, not just available)                      |
| `mcpServers`      | No       | MCP servers: string references or inline definitions                                                       |
| `hooks`           | No       | Lifecycle hooks scoped to this subagent                                                                    |
| `memory`          | No       | Persistent memory scope: `user`, `project`, or `local`                                                    |
| `background`      | No       | `true` to always run as background task. Default: `false`                                                  |
| `effort`          | No       | `low`, `medium`, `high`, `xhigh`, `max`. Overrides session effort level                                   |
| `isolation`       | No       | `worktree` to run in a temporary git worktree (auto-cleaned if no changes)                                |
| `color`           | No       | Display color: `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan`                       |
| `initialPrompt`   | No       | Auto-submitted as first user turn when agent runs as main session (via `--agent`)                          |

## Model Resolution Order

1. `CLAUDE_CODE_SUBAGENT_MODEL` environment variable
2. Per-invocation `model` parameter
3. Subagent definition's `model` frontmatter
4. Main conversation's model

## Tool Configuration

### Allowlist (only these tools)

```yaml
---
name: safe-researcher
tools: Read, Grep, Glob, Bash
---
```

### Denylist (all tools except these)

```yaml
---
name: no-writes
disallowedTools: Write, Edit
---
```

### Restrict which subagents can be spawned

```yaml
---
name: coordinator
tools: Agent(worker, researcher), Read, Bash
---
```

If both `tools` and `disallowedTools` are set, `disallowedTools` is applied first.

## Permission Modes

| Mode                | Behavior                                                                |
|:--------------------|:------------------------------------------------------------------------|
| `default`           | Standard permission checking with prompts                               |
| `acceptEdits`       | Auto-accept file edits and common filesystem commands                   |
| `auto`              | Background classifier reviews commands and protected-directory writes   |
| `dontAsk`           | Auto-deny permission prompts (explicitly allowed tools still work)      |
| `bypassPermissions` | Skip permission prompts (use with caution)                              |
| `plan`              | Plan mode (read-only exploration)                                       |

Parent `bypassPermissions` or `acceptEdits` takes precedence. Parent `auto` mode is inherited and cannot be overridden.

## Persistent Memory

```yaml
---
name: code-reviewer
description: Reviews code for quality
memory: project
---
```

| Scope     | Location                                      | Use when                                       |
|:----------|:----------------------------------------------|:-----------------------------------------------|
| `user`    | `~/.claude/agent-memory/<name>/`              | Learnings across all projects                  |
| `project` | `.claude/agent-memory/<name>/`                | Project-specific, shareable via version control |
| `local`   | `.claude/agent-memory-local/<name>/`          | Project-specific, not in version control       |

When enabled: system prompt includes memory instructions, first 200 lines/25KB of `MEMORY.md` is included, Read/Write/Edit tools are auto-enabled.

## MCP Servers in Subagents

```yaml
---
name: browser-tester
mcpServers:
  - playwright:
      type: stdio
      command: npx
      args: ["-y", "@playwright/mcp@latest"]
  - github  # reference already-configured server
---
```

Inline definitions connect on subagent start and disconnect on finish.

## Preloading Skills

```yaml
---
name: api-developer
description: Implement API endpoints
skills:
  - api-conventions
  - error-handling-patterns
---
```

Full skill content is injected at startup. Subagents don't inherit skills from parent.

## Hooks in Subagents

### In frontmatter (runs while subagent is active)

```yaml
---
name: code-reviewer
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-command.sh"
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/run-linter.sh"
---
```

### In settings.json (project-level lifecycle events)

```json
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "db-agent",
        "hooks": [
          { "type": "command", "command": "./scripts/setup-db.sh" }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "./scripts/cleanup.sh" }
        ]
      }
    ]
  }
}
```

## Invocation Methods

### Automatic delegation
Claude delegates based on task description matching subagent's `description` field.

### Natural language
```text
Use the test-runner subagent to fix failing tests
```

### @-mention (guarantees specific subagent)
```text
@"code-reviewer (agent)" look at the auth changes
```

### Session-wide (whole session uses subagent config)
```bash
claude --agent code-reviewer
```

Or in `.claude/settings.json`:
```json
{
  "agent": "code-reviewer"
}
```

### CLI-defined (session-only, not saved to disk)

```bash
claude --agents '{
  "code-reviewer": {
    "description": "Expert code reviewer",
    "prompt": "You are a senior code reviewer.",
    "tools": ["Read", "Grep", "Glob", "Bash"],
    "model": "sonnet"
  }
}'
```

## Foreground vs Background

- **Foreground**: Blocks main conversation. Permission prompts passed through.
- **Background**: Runs concurrently. Permissions pre-approved at launch. Set `background: true` in frontmatter or ask Claude to "run this in the background". Press **Ctrl+B** to background a running task.

Disable background tasks: `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`

## Disabling Subagents

In settings deny rules:
```json
{
  "permissions": {
    "deny": ["Agent(Explore)", "Agent(my-custom-agent)"]
  }
}
```

Or via CLI:
```bash
claude --disallowedTools "Agent(Explore)"
```

## Plugin Subagent Restrictions

Plugin subagents do NOT support `hooks`, `mcpServers`, or `permissionMode` fields (these are ignored for security). Copy the agent file to `.claude/agents/` if you need these features.

## Example: Full Subagent Definition

```markdown
---
name: db-reader
description: Execute read-only database queries
tools: Bash
model: haiku
permissionMode: dontAsk
memory: project
effort: medium
color: blue
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-readonly-query.sh"
---

You are a database query specialist. Only execute SELECT queries.
Never modify data. Always explain query results clearly.

Update your agent memory with schema discoveries and query patterns.
```