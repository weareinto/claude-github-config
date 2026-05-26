# Rules Configuration Reference

## Overview

Rules are modular instruction files in `.claude/rules/` that load into context like CLAUDE.md. They can be scoped to specific file paths so they only load when Claude works with matching files.

## Directory Structure

```
your-project/
├── .claude/
│   ├── CLAUDE.md           # Main project instructions
│   └── rules/
│       ├── code-style.md   # Code style guidelines
│       ├── testing.md      # Testing conventions
│       ├── security.md     # Security requirements
│       ├── frontend/       # Subdirectories supported
│       │   └── react.md
│       └── backend/
│           └── api.md
```

All `.md` files are discovered recursively within `.claude/rules/`.

## Where Rules Live

| Location              | Scope              | Priority   |
|:----------------------|:-------------------|:-----------|
| `~/.claude/rules/`   | All your projects  | Lower      |
| `.claude/rules/`     | Current project    | Higher     |

User-level rules load before project rules, giving project rules higher priority.

## File Format

### Unconditional Rules (always loaded)

Simple markdown file without frontmatter. Loaded at launch with same priority as `.claude/CLAUDE.md`.

```markdown
# Testing Conventions

- All new features must have unit tests
- Use pytest fixtures for database setup
- Mock external API calls in unit tests
```

### Path-Specific Rules (conditional)

Use YAML frontmatter with `paths` field. Only loaded when Claude works with files matching the patterns.

```markdown
---
paths:
  - "src/api/**/*.ts"
---

# API Development Rules

- All API endpoints must include input validation
- Use the standard error response format
- Include OpenAPI documentation comments
```

## Frontmatter Fields

| Field   | Required | Description                                                              |
|:--------|:---------|:-------------------------------------------------------------------------|
| `paths` | No       | Glob patterns that scope when the rule is loaded. Without it, rule loads unconditionally |

## Glob Patterns

| Pattern                | Matches                                  |
|:-----------------------|:-----------------------------------------|
| `**/*.ts`              | All TypeScript files in any directory    |
| `src/**/*`             | All files under `src/` directory         |
| `*.md`                 | Markdown files in the project root       |
| `src/components/*.tsx` | React components in a specific directory |

### Multiple patterns and brace expansion

```markdown
---
paths:
  - "src/**/*.{ts,tsx}"
  - "lib/**/*.ts"
  - "tests/**/*.test.ts"
---
```

## Rules vs CLAUDE.md vs Skills

| Mechanism    | Loaded when                        | Use for                                              |
|:-------------|:-----------------------------------|:-----------------------------------------------------|
| CLAUDE.md    | Every session (full file)          | Core project instructions, build commands, conventions |
| Rules        | Every session or on file match     | Modular topic-specific instructions, path-scoped guidance |
| Skills       | On invocation or relevance match   | Task-specific procedures, reusable workflows         |

## Sharing Rules Across Projects

### Symlinks

The `.claude/rules/` directory supports symlinks. Link shared rules from a central location:

```bash
# Link a shared directory
ln -s ~/shared-claude-rules .claude/rules/shared

# Link an individual file
ln -s ~/company-standards/security.md .claude/rules/security.md
```

Circular symlinks are detected and handled gracefully.

## Loading Behavior

- Rules without `paths` frontmatter load at launch (same as CLAUDE.md)
- Path-scoped rules load when Claude reads files matching the pattern
- Rules are loaded as context, not enforced configuration
- More specific and concise rules produce better adherence

## Excluding Rules

In large monorepos, use `claudeMdExcludes` in settings to skip irrelevant rules:

```json
{
  "claudeMdExcludes": [
    "/home/user/monorepo/other-team/.claude/rules/**"
  ]
}
```

## Examples

### Code Style Rule (unconditional)

`.claude/rules/code-style.md`:
```markdown
# Code Style

- Use 2-space indentation
- Prefer const over let
- No default exports
- Maximum line length: 100 characters
```

### Python Testing Rule (path-scoped)

`.claude/rules/python-testing.md`:
```markdown
---
paths:
  - "**/*.py"
  - "tests/**/*"
---

# Python Testing Standards

- Use pytest, not unittest
- Use async fixtures with pytest-asyncio
- Name test files test_*.py
- Use factories for test data creation
```

### Frontend Rule (path-scoped)

`.claude/rules/frontend.md`:
```markdown
---
paths:
  - "src/components/**/*.{tsx,jsx}"
  - "src/pages/**/*.{tsx,jsx}"
---

# Frontend Standards

- Use functional components with hooks
- Co-locate styles with components
- Use React.memo for expensive renders
- All props must have TypeScript interfaces
```

### Security Rule (unconditional)

`.claude/rules/security.md`:
```markdown
# Security Requirements

- Never log sensitive data (passwords, tokens, PII)
- Always validate user input at API boundaries
- Use parameterized queries for all database operations
- Never commit .env files or secrets
```