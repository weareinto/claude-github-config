# Hooks Configuration Reference

## Overview

Hooks are automated actions that fire at specific points in Claude Code's lifecycle. They receive JSON input via stdin (command hooks) or HTTP POST body (HTTP hooks) and control behavior through exit codes and JSON output.

## Hook Events

### Session-level (once per session)

| Event          | Matcher input   | When it fires                    |
|:---------------|:----------------|:---------------------------------|
| `SessionStart` | Session source (`startup`, `resume`, `clear`, `compact`) | When session begins/resumes |
| `SessionEnd`   | End reason (`clear`, `resume`, `logout`, `other`) | When session terminates |

### Turn-level (once per turn)

| Event               | Matcher input | When it fires                          |
|:---------------------|:-------------|:---------------------------------------|
| `UserPromptSubmit`   | No matcher   | Before Claude processes prompt         |
| `Stop`               | No matcher   | When Claude finishes responding        |
| `StopFailure`        | Error type (`rate_limit`, `authentication_failed`, `server_error`) | When turn ends due to API error |

### Tool execution (per tool call)

| Event               | Matcher input | When it fires                          |
|:---------------------|:-------------|:---------------------------------------|
| `PreToolUse`         | Tool name    | Before tool executes (can block)       |
| `PostToolUse`        | Tool name    | After tool succeeds                    |
| `PostToolUseFailure` | Tool name    | After tool fails                       |
| `PermissionRequest`  | Tool name    | When permission dialog appears         |
| `PermissionDenied`   | Tool name    | Auto mode classifier denies tool       |

### Subagent events

| Event           | Matcher input   | When it fires                    |
|:----------------|:----------------|:---------------------------------|
| `SubagentStart` | Agent type name | When subagent spawned            |
| `SubagentStop`  | Agent type name | When subagent finishes           |

### Other events

| Event              | Matcher input       | When it fires                          |
|:-------------------|:--------------------|:---------------------------------------|
| `Notification`     | Notification type   | When Claude sends notifications        |
| `TaskCreated`      | No matcher          | When task being created                |
| `TaskCompleted`    | No matcher          | When task marked complete              |
| `TeammateIdle`     | No matcher          | Agent teammate about to idle           |
| `InstructionsLoaded` | Load reason       | CLAUDE.md or rules file loaded         |
| `ConfigChange`     | Config source       | Configuration file changes             |
| `CwdChanged`       | No matcher          | Working directory changes              |
| `FileChanged`      | Literal filenames   | Watched file changes on disk           |
| `WorktreeCreate`   | No matcher          | Worktree being created                 |
| `WorktreeRemove`   | No matcher          | Worktree being removed                 |
| `PreCompact`       | Compaction trigger   | Before context compaction             |
| `PostCompact`      | Compaction trigger   | After context compaction              |
| `Elicitation`      | MCP server name     | MCP server requests user input        |
| `ElicitationResult`| MCP server name     | User responds to MCP elicitation      |

## Configuration Locations (Priority Order)

1. Managed policy settings (organization-wide)
2. `~/.claude/settings.json` (user-wide)
3. `.claude/settings.json` (project, shareable)
4. `.claude/settings.local.json` (project-local, gitignored)
5. Plugin `hooks/hooks.json`
6. Skill/Agent frontmatter (while component active)

## Configuration Schema

```json
{
  "hooks": {
    "EventName": [
      {
        "matcher": "ToolName|OtherTool|regex.*pattern",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/validate.sh",
            "timeout": 600,
            "if": "Bash(rm *)",
            "statusMessage": "Checking...",
            "once": false,
            "async": false,
            "asyncRewake": false,
            "shell": "bash"
          }
        ]
      }
    ]
  }
}
```

## Hook Handler Types

### 1. Command Hooks

Execute shell commands. Receive JSON on stdin.

```json
{
  "type": "command",
  "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/validate.sh",
  "timeout": 600,
  "async": false,
  "asyncRewake": false,
  "shell": "bash"
}
```

### 2. HTTP Hooks

Send JSON POST request to endpoint.

```json
{
  "type": "http",
  "url": "http://localhost:8080/hooks/pre-tool-use",
  "timeout": 30,
  "headers": {
    "Authorization": "Bearer $MY_TOKEN"
  },
  "allowedEnvVars": ["MY_TOKEN"]
}
```

### 3. Prompt Hooks

Send prompt to Claude for evaluation.

```json
{
  "type": "prompt",
  "prompt": "Is this command safe? $ARGUMENTS",
  "model": "sonnet",
  "timeout": 30
}
```

### 4. Agent Hooks

Spawn subagent for verification.

```json
{
  "type": "agent",
  "prompt": "Verify this configuration: $ARGUMENTS",
  "timeout": 60
}
```

## Hook Fields Reference

| Field            | Type    | Description                                                              |
|:-----------------|:--------|:-------------------------------------------------------------------------|
| `type`           | string  | `command`, `http`, `prompt`, or `agent`                                  |
| `command`        | string  | Shell command to execute (command type only)                             |
| `url`            | string  | Endpoint URL (http type only)                                            |
| `prompt`         | string  | Prompt text (prompt/agent types)                                         |
| `model`          | string  | Model for prompt/agent hooks                                             |
| `timeout`        | number  | Timeout in seconds (default varies by type)                              |
| `if`             | string  | Conditional: only fire if tool matches pattern (e.g. `Bash(rm *)`)       |
| `matcher`        | string  | Pattern to filter which events trigger hooks                             |
| `statusMessage`  | string  | Message shown while hook runs                                            |
| `once`           | boolean | Fire only once per session                                               |
| `async`          | boolean | Run without blocking (command type only)                                 |
| `asyncRewake`    | boolean | Re-wake Claude when async hook completes                                 |
| `shell`          | string  | `bash` or `powershell` (command type only)                               |
| `headers`        | object  | HTTP headers (http type only)                                            |
| `allowedEnvVars` | array   | Env vars expanded in headers (http type only)                            |

## Matcher Patterns

| Pattern                          | Evaluation        | Examples                        |
|:---------------------------------|:------------------|:--------------------------------|
| `"*"`, `""`, or omitted         | Match all         | Fires on every occurrence       |
| Letters, digits, `_`, `\|` only | Exact or `\|` list | `Bash`, `Edit\|Write`          |
| Contains other characters        | JavaScript regex  | `^Notebook`, `mcp__.*`         |

## Environment Variables Available to Hooks

| Variable              | Description                              |
|:----------------------|:-----------------------------------------|
| `$CLAUDE_PROJECT_DIR` | Project root directory                   |
| `$CLAUDE_ENV_FILE`    | Available in SessionStart/CwdChanged/FileChanged (append exports) |
| `$CLAUDE_CODE_REMOTE` | Set to `"true"` in web environments      |
| `${CLAUDE_PLUGIN_ROOT}` | Plugin installation directory          |
| `${CLAUDE_PLUGIN_DATA}` | Plugin persistent data directory       |

## Exit Code Behavior

| Exit Code | Meaning            | Behavior                                                     |
|:----------|:-------------------|:-------------------------------------------------------------|
| **0**     | Success            | Parse stdout for JSON output                                 |
| **2**     | Blocking error     | Ignore stdout. Feed stderr to Claude or show user error      |
| **Other** | Non-blocking error | Show first line of stderr in transcript. Continue execution   |

### Exit Code 2 Effects by Event

| Event                                     | Effect                              |
|:------------------------------------------|:------------------------------------|
| `PreToolUse`, `PermissionRequest`, `UserPromptSubmit` | Block the action          |
| `Stop`, `SubagentStop`, `TeammateIdle`, `ConfigChange`, `PreCompact` | Prevent action |
| `TaskCreated`, `TaskCompleted`            | Roll back creation                  |
| `PostToolUse`, `PostToolUseFailure`, `PermissionDenied` | Non-blocking (already executed) |
| `WorktreeCreate`                          | Any non-zero code fails creation    |
| Other events                              | Non-blocking (log only)             |

## JSON Output Schema

All hooks can return JSON on stdout (exit 0):

```json
{
  "continue": true,
  "stopReason": "User-facing message when continue=false",
  "suppressOutput": false,
  "systemMessage": "Warning message",
  "decision": "block",
  "reason": "Human-readable reason",
  "hookSpecificOutput": {
    "hookEventName": "EventName",
    "additionalContext": "Added to Claude's context"
  }
}
```

## Event-Specific Output

### PreToolUse

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask|defer",
    "permissionDecisionReason": "Explanation",
    "updatedInput": { "field": "modified_value" },
    "additionalContext": "Context for Claude"
  }
}
```

### PostToolUse

```json
{
  "decision": "block",
  "reason": "Why tool output is problematic",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Additional feedback",
    "updatedMCPToolOutput": "replacement output"
  }
}
```

### PermissionRequest

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow|deny",
      "updatedInput": { "command": "modified" },
      "message": "Denial reason"
    }
  }
}
```

### UserPromptSubmit

```json
{
  "decision": "block",
  "reason": "Why prompt is rejected",
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Added context",
    "sessionTitle": "Auto-generated title"
  }
}
```

### SessionStart

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Environment setup info"
  }
}
```

### Stop / SubagentStop / TeammateIdle

```json
{
  "decision": "block",
  "reason": "Why stopping is blocked"
}
```

## Common Hook Input Fields

All hooks receive via stdin:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/directory",
  "permission_mode": "default|plan|acceptEdits|auto|dontAsk|bypassPermissions",
  "hook_event_name": "EventName",
  "agent_id": "agent-xyz",
  "agent_type": "Explore"
}
```

### PreToolUse/PostToolUse additional fields

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  }
}
```

## Tool Input Schemas (for PreToolUse hooks)

### Bash
```json
{ "command": "npm test", "description": "Run tests", "timeout": 120000 }
```

### Write
```json
{ "file_path": "/path/to/file", "content": "file content" }
```

### Edit
```json
{ "file_path": "/path/to/file", "old_string": "original", "new_string": "replacement" }
```

### Read
```json
{ "file_path": "/path/to/file", "offset": 10, "limit": 50 }
```

## Examples

### Protect .env files (PreToolUse)

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-env.sh"
          }
        ]
      }
    ]
  }
}
```

### Block destructive commands

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(rm *)",
            "command": "./.claude/hooks/block-rm.sh"
          }
        ]
      }
    ]
  }
}
```

### Auto-lint after file edits

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "./scripts/run-linter.sh"
          }
        ]
      }
    ]
  }
}
```

### Inject context on session start

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/load-context.sh"
          }
        ]
      }
    ]
  }
}
```

### Watch file changes

```json
{
  "hooks": {
    "FileChanged": [
      {
        "matcher": ".env|.env.local",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/reload-env.sh"
          }
        ]
      }
    ]
  }
}
```

### Match MCP tools

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__memory__.*",
        "hooks": [{ "type": "command", "command": "log-memory.sh" }]
      }
    ]
  }
}
```

### Hooks in skill/agent frontmatter

```yaml
---
name: secure-operations
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/security-check.sh"
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/lint.sh"
---
```

For subagents, `Stop` hooks in frontmatter automatically convert to `SubagentStop`.

## Disable Hooks

```json
{
  "disableAllHooks": true
}
```

## The `/hooks` Menu

Type `/hooks` in Claude Code to browse configured hooks with event type, matcher, handler details, source location, and full configuration (read-only).
