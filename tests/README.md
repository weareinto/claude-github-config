# Tests

The installer is covered by a [bats-core](https://github.com/bats-core/bats-core) test suite.

## Prerequisites

```bash
brew install bats-core   # macOS
# or
apt-get install bats     # Debian / Ubuntu
```

## Running the tests

```bash
cd /path/to/claude-github-config
bats tests/install.bats
```

All 23 tests should pass in under 30 seconds.

## What is tested

| Group | Tests |
|-------|-------|
| Prerequisites | git repo check, CI config check |
| `validate_inputs` | gh not in PATH, auth failure, org / repo / project missing, multi-error |
| Fresh install | file count, config.json values, placeholder substitution, `.sh` executability, doc file |
| Idempotency | no content changes on re-run, no extra files created |
| CI conflict | CI mode overwrites modified files |
| Ignore list | existing protected files are skipped, absent files are still created |
| CI behaviour | `CLAUDE.local.md` is not generated in CI mode |
| Project status columns | all 9 columns ok, missing columns added |
