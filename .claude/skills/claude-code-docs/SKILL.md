---
name: claude-code-docs
description: Reference guide for the .claude directory structure, skills, sub-agents, hooks, memory, rules, and MCP configuration. Use when the user asks how Claude Code works, how to configure the .claude directory, or how to create skills/agents/hooks/rules.
disable-model-invocation: true
---

# Claude Code Configuration Reference

This skill provides a comprehensive reference for configuring and extending Claude Code via the `.claude` directory and `~/.claude` user directory.

## Documentation URLs

- **Main docs**: https://code.claude.com/docs/en/
- **Features overview**: https://code.claude.com/docs/en/features-overview
- **.claude directory**: https://code.claude.com/docs/en/claude-directory
- **Skills (.claude/skills/)**: https://code.claude.com/docs/en/skills
- **Sub-agents (.claude/agents/)**: https://code.claude.com/docs/en/sub-agents
- **Hooks (.claude/hooks/, settings.json)**: https://code.claude.com/docs/en/hooks-guide
- **Hooks reference**: https://code.claude.com/docs/en/hooks
- **MCP (root .mcp.json, ~/.claude.json)**: https://code.claude.com/docs/en/mcp
- **Memory (CLAUDE.md, CLAUDE.local.md)**: https://code.claude.com/docs/en/memory
- **Rules (.claude/rules/)**: https://code.claude.com/docs/en/memory#organize-rules-with-claude/rules/
- **Permissions**: https://code.claude.com/docs/en/permissions
- **Settings (.claude/settings.json, settings.local.json)**: https://code.claude.com/docs/en/settings
- **Plugins (settings.json enabledPlugins)**: https://code.claude.com/docs/en/plugins
- **Agent teams**: https://code.claude.com/docs/en/agent-teams
- **Full docs index**: https://code.claude.com/docs/llms.txt

When the user asks about a specific topic, first check the supporting reference files below.

## Detailed Reference Files

- For **Skills** configuration (frontmatter fields, invocation control, string substitutions, dynamic context): see [skills-reference.md](skills-reference.md)
- For **MCP** configuration (transport types, scopes, .mcp.json format, env variable expansion, plugin servers): see [mcp-reference.md](mcp-reference.md)
- For **Sub-agents** configuration (frontmatter fields, tools, permission modes, memory, hooks, invocation methods): see [subagents-reference.md](subagents-reference.md)
- For **Hooks** configuration (all event types, handler types, exit codes, matchers, JSON output, examples): see [hooks-reference.md](hooks-reference.md)
- For **Rules** configuration (.claude/rules/, path-specific rules, glob patterns, frontmatter, sharing): see [rules-reference.md](rules-reference.md)

If the reference files above don't contain enough information to answer the user's question, fetch the relevant Documentation URL using WebFetch to get the latest and most complete documentation.

---

## Project & User Directory Structure

```
your-project/
├── .mcp.json                    # MCP server configuration
├── .claude/
│   ├── CLAUDE.md                # Project instructions (loaded every session)
│   ├── settings.json            # Project settings & hooks (commit to repo)
│   ├── settings.local.json      # Local project settings (gitignored)
│   ├── skills/                  # Project skills
│   │   └── <skill-name>/
│   │       ├── SKILL.md         # Skill entrypoint (required)
│   │       └── ...              # Supporting files
│   ├── agents/                  # Project sub-agents
│   │   └── <agent-name>.md     # Agent definition
│   ├── rules/                   # Organized rules (loaded like CLAUDE.md)
│   │   └── <rule-name>.md
│   ├── hooks/                   # Hook scripts
│   │   └── <script>.sh
│   └── agent-memory-local/      # Local agent memory (gitignored)
│       └── <agent-name>/        # Per-agent persistent memory
```