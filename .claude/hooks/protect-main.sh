#!/bin/bash
# Block Edit and Write tool calls when the current branch is any of:
#   - `main`                                 (protected branch)
#   - detached HEAD                          (no named branch to identify the work)
#   - undeterminable (git rev-parse fails)   (cannot verify we're not on main)
# Read is allowed — this hook is registered only for Edit|Write in settings.json.
#
# Exception: gitignored files are never committed, so they don't need branch protection.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')

if [ -n "$FILE_PATH" ] && git check-ignore -q "$FILE_PATH" 2>/dev/null; then
  exit 0
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -z "$CURRENT_BRANCH" ] || [ "$CURRENT_BRANCH" = "HEAD" ]; then
  echo "Blocked: could not determine current git branch (not a git repo, safe.directory error, or detached HEAD). Create a named branch before editing files." >&2
  exit 2
fi

if [ "$CURRENT_BRANCH" = "main" ]; then
  echo "Blocked: you are on branch 'main'. Create a feature/fix/chore branch before editing files." >&2
  exit 2
fi

exit 0