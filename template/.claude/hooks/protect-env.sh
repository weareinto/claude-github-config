#!/bin/bash
INPUT=$(cat)

# Extract file_path without jq — use grep + sed
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')

if echo "$FILE_PATH" | grep -q '\.env' && ! echo "$FILE_PATH" | grep -q '\.env\.example'; then
  echo "Blocked: .env files are protected from reading and editing" >&2
  exit 2
fi

exit 0