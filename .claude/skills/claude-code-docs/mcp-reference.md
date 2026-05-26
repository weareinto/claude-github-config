# MCP (Model Context Protocol) Configuration Reference

## Overview

MCP servers give Claude Code access to external tools, databases, and APIs via the [Model Context Protocol](https://modelcontextprotocol.io/introduction).

## Transport Types

### HTTP (Recommended for remote servers)

```bash
claude mcp add --transport http <name> <url>

# With Bearer token
claude mcp add --transport http secure-api https://api.example.com/mcp \
  --header "Authorization: Bearer your-token"
```

### SSE (Deprecated — use HTTP instead)

```bash
claude mcp add --transport sse <name> <url>

# With authentication header
claude mcp add --transport sse private-api https://api.company.com/sse \
  --header "X-API-Key: your-key-here"
```

### Stdio (Local processes)

```bash
claude mcp add [options] <name> -- <command> [args...]

# Example with env vars
claude mcp add --transport stdio --env AIRTABLE_API_KEY=YOUR_KEY airtable \
  -- npx -y airtable-mcp-server
```

**Windows Note**: On native Windows (not WSL), use `cmd /c` wrapper:
```bash
claude mcp add --transport stdio my-server -- cmd /c npx -y @some/package
```

### WebSocket (ws)

Used for inline subagent MCP definitions. Same schema as other types.

## Option Ordering

All options (`--transport`, `--env`, `--scope`, `--header`) must come **before** the server name. The `--` separates the server name from the command/args.

```bash
claude mcp add --transport stdio --env KEY=value myserver -- python server.py --port 8080
```

## Installation Scopes

| Scope   | Loads in             | Shared with team         | Stored in                   |
|:--------|:---------------------|:-------------------------|:----------------------------|
| Local   | Current project only | No                       | `~/.claude.json`            |
| Project | Current project only | Yes, via version control | `.mcp.json` in project root |
| User    | All your projects    | No                       | `~/.claude.json`            |

### Scope Precedence (highest to lowest)

1. Local scope
2. Project scope
3. User scope
4. Plugin-provided servers
5. claude.ai connectors

### Setting Scope

```bash
# Local (default)
claude mcp add --transport http stripe https://mcp.stripe.com

# Explicit local
claude mcp add --transport http stripe --scope local https://mcp.stripe.com

# Project (shared via .mcp.json)
claude mcp add --transport http paypal --scope project https://mcp.paypal.com/mcp

# User (all projects)
claude mcp add --transport http hubspot --scope user https://mcp.hubspot.com/anthropic
```

## Config File Formats

### Local/User scope (`~/.claude.json`)

```json
{
  "projects": {
    "/path/to/your/project": {
      "mcpServers": {
        "stripe": {
          "type": "http",
          "url": "https://mcp.stripe.com"
        }
      }
    }
  }
}
```

### Project scope (`.mcp.json` in project root)

```json
{
  "mcpServers": {
    "shared-server": {
      "command": "/path/to/server",
      "args": [],
      "env": {}
    }
  }
}
```

### HTTP Server Config

```json
{
  "mcpServers": {
    "api-server": {
      "type": "http",
      "url": "https://api.example.com/mcp",
      "headers": {
        "Authorization": "Bearer ${API_KEY}"
      }
    }
  }
}
```

### Stdio Server Config

```json
{
  "mcpServers": {
    "database-tools": {
      "command": "npx",
      "args": ["-y", "@some/mcp-server"],
      "env": {
        "DB_URL": "${DB_URL}"
      }
    }
  }
}
```

## Environment Variable Expansion in `.mcp.json`

**Supported syntax:**
- `${VAR}` — expands to value of `VAR`
- `${VAR:-default}` — expands to `VAR` if set, otherwise uses `default`

**Expansion locations:** `command`, `args`, `env`, `url`, `headers`

```json
{
  "mcpServers": {
    "api-server": {
      "type": "http",
      "url": "${API_BASE_URL:-https://api.example.com}/mcp",
      "headers": {
        "Authorization": "Bearer ${API_KEY}"
      }
    }
  }
}
```

## Managing Servers

```bash
# List all configured servers
claude mcp list

# Get details for a specific server
claude mcp get github

# Remove a server
claude mcp remove github

# Reset project-scoped approval choices
claude mcp reset-project-choices

# Check server status (within Claude Code)
/mcp
```

## Plugin-Provided MCP Servers

Plugins can bundle MCP servers in `.mcp.json` at plugin root or inline in `plugin.json`:

```json
{
  "mcpServers": {
    "database-tools": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/db-server",
      "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"],
      "env": {
        "DB_URL": "${DB_URL}"
      }
    }
  }
}
```

Special variables:
- `${CLAUDE_PLUGIN_ROOT}` — path to bundled plugin files
- `${CLAUDE_PLUGIN_DATA}` — persistent state directory

## Subagent-Scoped MCP Servers

MCP servers can be scoped to subagents via the `mcpServers` frontmatter field:

```yaml
---
name: browser-tester
description: Tests features using Playwright
mcpServers:
  # Inline definition: scoped to this subagent only
  - playwright:
      type: stdio
      command: npx
      args: ["-y", "@playwright/mcp@latest"]
  # Reference by name: reuses already-configured server
  - github
---
```

Inline servers connect when the subagent starts and disconnect when it finishes.

## Dynamic Tool Updates

MCP servers can send `list_changed` notifications to dynamically update available tools without reconnecting.

## Push Messages (Channels)

MCP servers can push messages into sessions via the `claude/channel` capability. Enable with `--channels` flag at startup.

## Environment Variables

| Variable              | Description                                                    |
|:----------------------|:---------------------------------------------------------------|
| `MCP_TIMEOUT`         | Server startup timeout in ms (e.g., `MCP_TIMEOUT=10000 claude`) |
| `MAX_MCP_OUTPUT_TOKENS` | Max tokens for MCP tool output (default: 10,000)             |

## OAuth Authentication

Remote servers requiring OAuth 2.0 can be authenticated via `/mcp` command within Claude Code.
