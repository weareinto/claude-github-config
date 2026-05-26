#!/usr/bin/env bats
# tests/install.bats — bats-core test suite for install.sh
#
# Run:
#   bats tests/install.bats
#
# Install bats-core:
#   brew install bats-core          # macOS
#   apt-get install bats            # Debian/Ubuntu
#
# All tests run in --ci mode against isolated temp directories.
# A mock `gh` CLI is placed in PATH so no real GitHub API calls are made.

# REPO_ROOT, INSTALL_SH and TEMPLATE_DIR are resolved in setup() via BATS_TEST_FILENAME

# ── Setup / teardown ──────────────────────────────────────────────────────────

setup() {
  # BATS_TEST_FILENAME is the real path to this .bats file (not the bats temp copy)
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  INSTALL_SH="$REPO_ROOT/install.sh"
  TEMPLATE_DIR="$REPO_ROOT/template"

  TARGET_DIR="$(mktemp -d)"
  MOCK_BIN="$(mktemp -d)"

  # Minimal git repo in target dir
  git -C "$TARGET_DIR" init -q
  git -C "$TARGET_DIR" config user.email "test@test.com"
  git -C "$TARGET_DIR" config user.name "Test"

  # Config file required by CI mode
  printf '%s\n' '{"org":"testorg","repo":"testrepo","project_number":"42"}' \
    > "$TARGET_DIR/.claude-github-config.json"

  # Default mock: gh succeeds for everything
  _mock_gh ok
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  rm -rf "$TARGET_DIR" "$MOCK_BIN"
}

# ── Mock gh factory ───────────────────────────────────────────────────────────
#
# _mock_gh <mode>
#   ok            — all calls succeed; project has all 9 status columns
#   fail_auth     — gh auth status exits 1
#   fail_org      — gh api orgs/... exits 1
#   fail_repo     — gh api repos/... exits 1
#   fail_project  — graphql returns null projectV2
#   fail_both     — org AND repo both fail (tests multi-error reporting)
#   missing_cols  — project has only 2 of 9 status columns

_mock_gh() {
  local mode="${1:-ok}"
  local gh="$MOCK_BIN/gh"

  # Pre-build the JSON strings to avoid quoting issues inside case blocks
  local FULL_PROJECT='{"data":{"organization":{"projectV2":{"id":"PVT_t","title":"Board","field":{"id":"FLD_t","options":[{"id":"o1","name":"Backlog","color":"GRAY","description":""},{"id":"o2","name":"Ready","color":"BLUE","description":""},{"id":"o3","name":"Blocked","color":"RED","description":""},{"id":"o4","name":"In progress","color":"YELLOW","description":""},{"id":"o5","name":"In review","color":"PURPLE","description":""},{"id":"o6","name":"Ready to deploy","color":"GREEN","description":""},{"id":"o7","name":"Staging","color":"ORANGE","description":""},{"id":"o8","name":"Production","color":"GREEN","description":""},{"id":"o9","name":"Done","color":"GRAY","description":""}]}}}}}'
  local PARTIAL_PROJECT='{"data":{"organization":{"projectV2":{"id":"PVT_t","title":"Board","field":{"id":"FLD_t","options":[{"id":"o1","name":"Backlog","color":"GRAY","description":""},{"id":"o2","name":"Ready","color":"BLUE","description":""}]}}}}}'
  local NULL_PROJECT='{"data":{"organization":{"projectV2":null}}}'

  case "$mode" in
    ok)
      printf '#!/usr/bin/env bash\n'                                        > "$gh"
      printf 'CMD="${1:-}"; SUBCMD="${2:-}"\n'                             >> "$gh"
      printf '[ "$CMD" = "auth" ] && exit 0\n'                            >> "$gh"
      printf 'if [ "$CMD" = "api" ] && [ "$SUBCMD" = "graphql" ]; then\n' >> "$gh"
      printf '  for arg in "$@"; do\n'                                     >> "$gh"
      printf '    [ "$arg" = "--input" ] && echo '"'"'{"data":{}}'"'"' && exit 0\n' >> "$gh"
      printf '  done\n'                                                    >> "$gh"
      printf "  printf '%%s\\\\n' '%s'\n" "$FULL_PROJECT"                 >> "$gh"
      printf '  exit 0\n'                                                  >> "$gh"
      printf 'fi\n'                                                        >> "$gh"
      printf '[ "$CMD" = "api" ] && echo '"'"'{"ok":true}'"'"' && exit 0\n' >> "$gh"
      printf 'exit 0\n'                                                    >> "$gh"
      ;;
    fail_auth)
      printf '#!/usr/bin/env bash\n'                                 > "$gh"
      printf '[ "${1:-}" = "auth" ] && exit 1\n'                   >> "$gh"
      printf 'echo '"'"'{"ok":true}'"'"'; exit 0\n'                >> "$gh"
      ;;
    fail_org)
      printf '#!/usr/bin/env bash\n'                                              > "$gh"
      printf 'CMD="${1:-}"; SUBCMD="${2:-}"\n'                                   >> "$gh"
      printf '[ "$CMD" = "auth" ] && exit 0\n'                                  >> "$gh"
      printf '[ "$CMD" = "api" ] && [[ "$SUBCMD" == orgs/* ]] && exit 1\n'     >> "$gh"
      printf 'echo '"'"'{"ok":true}'"'"'; exit 0\n'                             >> "$gh"
      ;;
    fail_repo)
      printf '#!/usr/bin/env bash\n'                                              > "$gh"
      printf 'CMD="${1:-}"; SUBCMD="${2:-}"\n'                                   >> "$gh"
      printf '[ "$CMD" = "auth" ] && exit 0\n'                                  >> "$gh"
      printf '[ "$CMD" = "api" ] && [[ "$SUBCMD" == repos/* ]] && exit 1\n'    >> "$gh"
      printf 'echo '"'"'{"ok":true}'"'"'; exit 0\n'                             >> "$gh"
      ;;
    fail_project)
      printf '#!/usr/bin/env bash\n'                                                 > "$gh"
      printf 'CMD="${1:-}"; SUBCMD="${2:-}"\n'                                      >> "$gh"
      printf '[ "$CMD" = "auth" ] && exit 0\n'                                     >> "$gh"
      printf 'if [ "$CMD" = "api" ] && [ "$SUBCMD" = "graphql" ]; then\n'         >> "$gh"
      printf "  echo '%s'; exit 0\n" "$NULL_PROJECT"                              >> "$gh"
      printf 'fi\n'                                                                >> "$gh"
      printf 'echo '"'"'{"ok":true}'"'"'; exit 0\n'                               >> "$gh"
      ;;
    fail_both)
      printf '#!/usr/bin/env bash\n'                                              > "$gh"
      printf 'CMD="${1:-}"; SUBCMD="${2:-}"\n'                                   >> "$gh"
      printf '[ "$CMD" = "auth" ] && exit 0\n'                                  >> "$gh"
      printf 'if [ "$CMD" = "api" ] && [ "$SUBCMD" = "graphql" ]; then\n'       >> "$gh"
      printf '  for arg in "$@"; do [ "$arg" = "--input" ] && echo '\''{"data":{}}'\'' && exit 0; done\n' >> "$gh"
      printf "  printf '%%s\\\\n' '%s'\\n" "$FULL_PROJECT"              >> "$gh"
      printf '  exit 0\n'                                                        >> "$gh"
      printf 'fi\n'                                                              >> "$gh"
      printf '[ "$CMD" = "api" ] && [[ "$SUBCMD" == orgs/*  ]] && exit 1\n'    >> "$gh"
      printf '[ "$CMD" = "api" ] && [[ "$SUBCMD" == repos/* ]] && exit 1\n'    >> "$gh"
      printf '[ "$CMD" = "api" ] && echo '\''{"ok":true}'\'' && exit 0\n' >> "$gh"
      printf 'exit 0\n'                                                            >> "$gh"
      ;;
    missing_cols)
      printf '#!/usr/bin/env bash\n'                                        > "$gh"
      printf 'CMD="${1:-}"; SUBCMD="${2:-}"\n'                             >> "$gh"
      printf '[ "$CMD" = "auth" ] && exit 0\n'                            >> "$gh"
      printf 'if [ "$CMD" = "api" ] && [ "$SUBCMD" = "graphql" ]; then\n' >> "$gh"
      printf '  for arg in "$@"; do\n'                                     >> "$gh"
      printf '    [ "$arg" = "--input" ] && echo '"'"'{"data":{}}'"'"' && exit 0\n' >> "$gh"
      printf '  done\n'                                                    >> "$gh"
      printf "  printf '%%s\\\\n' '%s'\n" "$PARTIAL_PROJECT"              >> "$gh"
      printf '  exit 0\n'                                                  >> "$gh"
      printf 'fi\n'                                                        >> "$gh"
      printf '[ "$CMD" = "api" ] && echo '"'"'{"ok":true}'"'"' && exit 0\n' >> "$gh"
      printf 'exit 0\n'                                                    >> "$gh"
      ;;
  esac

  chmod +x "$gh"
}

# ── Convenience runner ────────────────────────────────────────────────────────

_install_ci() {
  run bash -c "cd '$TARGET_DIR' && bash '$INSTALL_SH' --ci 2>&1"
}

# Count files in the template directory
_template_file_count() {
  find "$TEMPLATE_DIR" -type f | wc -l | tr -d ' '
}

# Count installed files (excludes .git internals, installer metadata, CLAUDE.local.md)
_installed_file_count() {
  find "$TARGET_DIR" \
    -not -path "*/.git/*" \
    -not -name ".claude-github-config.json" \
    -not -name "CLAUDE.local.md" \
    -type f | wc -l | tr -d ' '
}


# ═══════════════════════════════════════════════════════════════════════════════
# 1. PREREQUISITES
# ═══════════════════════════════════════════════════════════════════════════════

@test "exits with error when target directory is not a git repo" {
  rm -rf "$TARGET_DIR/.git"
  _install_ci
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF "is not a git repository"
}

@test "CI mode exits with error when .claude-github-config.json is missing" {
  rm -f "$TARGET_DIR/.claude-github-config.json"
  _install_ci
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF ".claude-github-config.json"
}


# ═══════════════════════════════════════════════════════════════════════════════
# 2. VALIDATE INPUTS
# ═══════════════════════════════════════════════════════════════════════════════

@test "validate_inputs: fails when gh is not in PATH" {
  # Find the *real* gh binary (not the mock in $MOCK_BIN) so we can exclude
  # its directory from safe_path. We must skip $MOCK_BIN because setup()
  # prepends it and it shadows the real binary.
  local real_gh_dir safe_path
  real_gh_dir="$(printf '%s' "$PATH" | tr ':' '\n' \
    | grep -vxF "$MOCK_BIN" \
    | while IFS= read -r d; do [ -x "$d/gh" ] && echo "$d" && break; done)"
  safe_path="$(printf '%s' "$PATH" | tr ':' '\n' \
    | grep -vxF "$MOCK_BIN" \
    | { [ -n "$real_gh_dir" ] && grep -vxF "$real_gh_dir" || cat; } \
    | tr '\n' ':' | sed 's/:$//')"
  run bash -c "cd '$TARGET_DIR' && PATH='$safe_path' bash '$INSTALL_SH' --ci 2>&1"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF "gh CLI not found"
}
@test "validate_inputs: fails when gh is not authenticated" {
  _mock_gh fail_auth
  _install_ci
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF "not authenticated"
}

@test "validate_inputs: fails when org is not found on GitHub" {
  _mock_gh fail_org
  _install_ci
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF "not found on GitHub"
}

@test "validate_inputs: fails when repo is not found on GitHub" {
  _mock_gh fail_repo
  _install_ci
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF "not found on GitHub"
}

@test "validate_inputs: fails when project number does not exist" {
  _mock_gh fail_project
  _install_ci
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF "not found in org"
}

@test "validate_inputs: reports all errors together before aborting" {
  _mock_gh fail_both
  _install_ci
  [ "$status" -ne 0 ]
  echo "$output" | grep -qF "2 error(s)"
}


# ═══════════════════════════════════════════════════════════════════════════════
# 3. FRESH INSTALL
# ═══════════════════════════════════════════════════════════════════════════════

@test "creates all template files on first install" {
  _install_ci
  [ "$status" -eq 0 ]

  EXPECTED="$(_template_file_count)"
  ACTUAL="$(_installed_file_count)"
  [ "$ACTUAL" -eq "$EXPECTED" ]
}

@test "saves .claude-github-config.json with correct org, repo and project_number" {
  _install_ci
  [ "$status" -eq 0 ]
  [ -f "$TARGET_DIR/.claude-github-config.json" ]

  python3 - "$TARGET_DIR/.claude-github-config.json" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert d['org']            == 'testorg',  f"org mismatch: {d['org']}"
assert d['repo']           == 'testrepo', f"repo mismatch: {d['repo']}"
assert d['project_number'] == '42',       f"project_number mismatch: {d['project_number']}"
PYEOF
}

@test "substitutes {{ORG}} placeholder in installed files" {
  _install_ci
  [ "$status" -eq 0 ]
  grep -qF "testorg"  "$TARGET_DIR/CONTRIBUTING.md"
  ! grep -qF "{{ORG}}" "$TARGET_DIR/CONTRIBUTING.md"
}

@test "substitutes {{REPO}} placeholder in installed files" {
  _install_ci
  [ "$status" -eq 0 ]
  grep -qF "testrepo"  "$TARGET_DIR/CONTRIBUTING.md"
  ! grep -qF "{{REPO}}" "$TARGET_DIR/CONTRIBUTING.md"
}

@test "substitutes {{PROJECT_NUMBER}} placeholder in installed files" {
  _install_ci
  [ "$status" -eq 0 ]
  # .claude/skills/start/SKILL.md uses {{PROJECT_NUMBER}}
  grep -qF "42"                 "$TARGET_DIR/.claude/skills/start/SKILL.md"
  ! grep -qF "{{PROJECT_NUMBER}}" "$TARGET_DIR/.claude/skills/start/SKILL.md"
}

@test "makes every installed .sh file executable" {
  _install_ci
  [ "$status" -eq 0 ]

  local failed=0
  while IFS= read -r src_sh; do
    rel="${src_sh#$TEMPLATE_DIR/}"
    installed="$TARGET_DIR/$rel"
    if [ ! -x "$installed" ]; then
      echo "Not executable: $rel" >&3
      failed=1
    fi
  done < <(find "$TEMPLATE_DIR" -name "*.sh" -type f)

  [ "$failed" -eq 0 ]
}

@test "installs doc/claude-github-config.md with substituted values" {
  _install_ci
  [ "$status" -eq 0 ]
  [ -f "$TARGET_DIR/doc/claude-github-config.md" ]
  grep -qF "testorg" "$TARGET_DIR/doc/claude-github-config.md"
}


# ═══════════════════════════════════════════════════════════════════════════════
# 4. IDEMPOTENCY
# ═══════════════════════════════════════════════════════════════════════════════

@test "re-running install does not change file contents" {
  _install_ci
  [ "$status" -eq 0 ]

  # Snapshot content of a file known to use placeholders
  local snap_before
  snap_before="$(cat "$TARGET_DIR/.claude/CLAUDE.md")"

  _install_ci
  [ "$status" -eq 0 ]

  local snap_after
  snap_after="$(cat "$TARGET_DIR/.claude/CLAUDE.md")"

  [ "$snap_before" = "$snap_after" ]
}

@test "re-running install does not create additional files" {
  _install_ci
  [ "$status" -eq 0 ]
  local count_first
  count_first="$(_installed_file_count)"

  _install_ci
  [ "$status" -eq 0 ]
  local count_second
  count_second="$(_installed_file_count)"

  [ "$count_first" -eq "$count_second" ]
}


# ═══════════════════════════════════════════════════════════════════════════════
# 5. CI MODE CONFLICT HANDLING
# ═══════════════════════════════════════════════════════════════════════════════

@test "CI mode overwrites files that have been modified locally" {
  _install_ci
  [ "$status" -eq 0 ]

  # Inject content that does not exist in the template
  local target_file="$TARGET_DIR/.claude/CLAUDE.md"
  local original_content
  original_content="$(cat "$target_file")"
  printf '\nINJECTED_CONTENT\n' >> "$target_file"
  grep -qF "INJECTED_CONTENT" "$target_file"

  # Second CI run must revert the file
  _install_ci
  [ "$status" -eq 0 ]

  ! grep -qF "INJECTED_CONTENT" "$target_file"

  # Content must match original template output
  local reverted_content
  reverted_content="$(cat "$target_file")"
  [ "$original_content" = "$reverted_content" ]
}


# ═══════════════════════════════════════════════════════════════════════════════
# 6. IGNORE LIST
# ═══════════════════════════════════════════════════════════════════════════════

@test "existing file listed in .claude-github-config-ignore is not overwritten" {
  # First install creates all files
  _install_ci
  [ "$status" -eq 0 ]

  # Customise a file and add it to the ignore list
  local target_file="$TARGET_DIR/.claude/CLAUDE.md"
  printf '\nMY_CUSTOM_LINE\n' >> "$target_file"
  # Use printf to guarantee a newline separator before the entry
  # (installed files strip trailing newlines via bash $(...), so echo alone
  #  would merge the entry with the previous line)
  printf '\n.claude/CLAUDE.md\n' >> "$TARGET_DIR/.claude-github-config-ignore"

  # Second install: ignored file must be left untouched
  _install_ci
  [ "$status" -eq 0 ]

  grep -qF "MY_CUSTOM_LINE" "$target_file"
  echo "$output" | grep -qF "ignored"
}

@test "file listed in .claude-github-config-ignore is still created when absent" {
  # Protect a file BEFORE it has ever been created
  echo ".claude/CLAUDE.md" > "$TARGET_DIR/.claude-github-config-ignore"

  _install_ci
  [ "$status" -eq 0 ]

  # The ignore list must NOT block initial creation
  [ -f "$TARGET_DIR/.claude/CLAUDE.md" ]
}


# ═══════════════════════════════════════════════════════════════════════════════
# 7. CI-SPECIFIC BEHAVIOUR
# ═══════════════════════════════════════════════════════════════════════════════

@test "CI mode does not create CLAUDE.local.md" {
  _install_ci
  [ "$status" -eq 0 ]
  [ ! -f "$TARGET_DIR/CLAUDE.local.md" ]
}


# ═══════════════════════════════════════════════════════════════════════════════
# 8. PROJECT STATUS COLUMNS
# ═══════════════════════════════════════════════════════════════════════════════

@test "ensure_project_statuses: reports ok when all 9 columns are present" {
  # Default mock already returns all 9 columns
  _install_ci
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "All 9 status columns"
}

@test "ensure_project_statuses: reports and adds missing status columns" {
  _mock_gh missing_cols
  _install_ci
  [ "$status" -eq 0 ]
  # Must list the columns that were missing
  echo "$output" | grep -qF "Missing:"
  echo "$output" | grep -qF "Blocked"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 9. BATCH CONFLICT HANDLING
# ═══════════════════════════════════════════════════════════════════════════════

@test "batch: --batch-skip preserves all conflicted files" {
  _install_ci
  [ "$status" -eq 0 ]

  # Modify two template-managed files
  printf '\nMY_CHANGE\n' >> "$TARGET_DIR/CONTRIBUTING.md"
  printf '\nMY_CHANGE\n' >> "$TARGET_DIR/.github/copilot-instructions.md"

  run bash -c "cd '$TARGET_DIR' && bash '$INSTALL_SH' --batch-skip 2>&1"
  [ "$status" -eq 0 ]

  # Both modifications must be preserved
  grep -qF "MY_CHANGE" "$TARGET_DIR/CONTRIBUTING.md"
  grep -qF "MY_CHANGE" "$TARGET_DIR/.github/copilot-instructions.md"
}

@test "batch: --batch-skip output lists every conflicted file" {
  _install_ci
  [ "$status" -eq 0 ]

  printf '\nMY_CHANGE\n' >> "$TARGET_DIR/CONTRIBUTING.md"
  printf '\nMY_CHANGE\n' >> "$TARGET_DIR/.github/copilot-instructions.md"

  run bash -c "cd '$TARGET_DIR' && bash '$INSTALL_SH' --batch-skip 2>&1"
  [ "$status" -eq 0 ]

  # Summary line must mention the count
  echo "$output" | grep -qE "[0-9]+ file\(s\) differ from the template"
  # Both file names must appear in the conflict list
  echo "$output" | grep -qF "CONTRIBUTING.md"
  echo "$output" | grep -qF "copilot-instructions.md"
}


# ═══════════════════════════════════════════════════════════════════════════════
# 10. INSTALL MODE (skills-only vs full reinstall)
# ═══════════════════════════════════════════════════════════════════════════════

@test "install mode: no detection prompt on fresh install" {
  # TARGET_DIR has no .claude/settings.json — mode prompt must not appear
  # Input: y (confirm config) + 4 (skip tech stack)
  run bash -c "cd '$TARGET_DIR' && printf 'y\n4\n' | bash '$INSTALL_SH' 2>&1"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qF "Existing Claude Code configuration detected"
}

@test "install mode: detection prompt shown when .claude/settings.json exists" {
  mkdir -p "$TARGET_DIR/.claude"
  echo '{}' > "$TARGET_DIR/.claude/settings.json"

  # Input: y (confirm config) + 2 (skills-only) + 4 (skip tech stack)
  run bash -c "cd '$TARGET_DIR' && printf 'y\n2\n4\n' | bash '$INSTALL_SH' 2>&1"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "Existing Claude Code configuration detected"
}

@test "install mode: skills-only suppresses non-skill files from output" {
  # Full install first so .claude/settings.json exists
  _install_ci
  [ "$status" -eq 0 ]

  # Input: y (confirm config) + 2 (skills-only) + 4 (skip tech stack)
  run bash -c "cd '$TARGET_DIR' && printf 'y\n2\n4\n' | bash '$INSTALL_SH' 2>&1"
  [ "$status" -eq 0 ]
  # Non-skill files must be silent — not appear in output
  ! echo "$output" | grep -qF "CONTRIBUTING.md"
  ! echo "$output" | grep -qF "doc/PROJECT.md"
  # Skills must appear
  echo "$output" | grep -qF ".claude/skills/"
  # Summary must show mode note
  echo "$output" | grep -qF "skills & hooks only"
}
