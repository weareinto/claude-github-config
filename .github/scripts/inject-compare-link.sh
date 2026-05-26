#!/usr/bin/env bash
# Add a GitHub compare link to the most recent version heading in CHANGELOG.md.
#
# Usage:
#   inject-compare-link.sh <new-version> <repo-slug> <changelog-path>
#
# Example:
#   inject-compare-link.sh 0.0.13 weareinto/ldl-voice-eval-agent CHANGELOG.md
#
# Rewrites the first `## [<new-version>] - <date>` heading into
# `## [<new-version>](https://github.com/<repo-slug>/compare/v<prev>...v<new-version>) - <date>`
# by detecting <prev> from the next `## [<X.Y.Z>]` heading. If no previous
# version is found, leaves the heading untouched.

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <new-version> <repo-slug> <changelog-path>" >&2
  exit 2
fi

NEW_VERSION="$1"
REPO_SLUG="$2"
CHANGELOG="$3"

if [[ ! -f "$CHANGELOG" ]]; then
  echo "Error: changelog file not found: $CHANGELOG" >&2
  exit 1
fi

PREV_VERSION="$(awk -v new="$NEW_VERSION" '
  match($0, /^## \[([0-9]+\.[0-9]+\.[0-9]+)\]/, m) {
    if (m[1] == new) { seen_new = 1; next }
    if (seen_new)    { print m[1]; exit }
  }
' "$CHANGELOG")"

if [[ -z "$PREV_VERSION" ]]; then
  echo "No previous version found before [$NEW_VERSION]; leaving heading untouched."
  exit 0
fi

COMPARE_URL="https://github.com/${REPO_SLUG}/compare/v${PREV_VERSION}...v${NEW_VERSION}"

# Rewrite only the FIRST occurrence of the new-version heading.
awk -v new="$NEW_VERSION" -v url="$COMPARE_URL" '
  !done && $0 ~ "^## \\["new"\\] - " {
    sub("\\["new"\\]", "[" new "](" url ")")
    done = 1
  }
  { print }
' "$CHANGELOG" > "${CHANGELOG}.tmp"

mv "${CHANGELOG}.tmp" "$CHANGELOG"
echo "Injected compare link for v${PREV_VERSION}...v${NEW_VERSION}"