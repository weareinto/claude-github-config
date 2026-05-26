#!/usr/bin/env bash
# Extract a single version's section from CHANGELOG.md.
#
# Usage:
#   extract-changelog-entry.sh <version> <changelog-path> <output-path>
#
# Example:
#   extract-changelog-entry.sh 0.0.13 CHANGELOG.md "$RUNNER_TEMP/entry.md"
#
# Reads the section between `## [<version>]` and the next `## [` heading
# (or end of file). Writes it to <output-path>. Used to build the annotation
# for the release tag.

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <version> <changelog-path> <output-path>" >&2
  exit 2
fi

VERSION="$1"
CHANGELOG="$2"
OUTPUT="$3"

if [[ ! -f "$CHANGELOG" ]]; then
  echo "Error: changelog file not found: $CHANGELOG" >&2
  exit 1
fi

awk -v ver="$VERSION" '
  $0 ~ "^## \\["ver"\\]" { found = 1; print; next }
  found && /^## \[/      { exit }
  found                   { print }
' "$CHANGELOG" > "$OUTPUT"

if [[ ! -s "$OUTPUT" ]]; then
  echo "Error: no section found for version [$VERSION] in $CHANGELOG" >&2
  exit 1
fi

echo "Extracted [$VERSION] section to $OUTPUT ($(wc -l < "$OUTPUT") lines)"