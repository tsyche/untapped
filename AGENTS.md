# untapped

**TL;DR:** Conf-driven installer for CLI binaries (and `.app` bundles) straight from GitHub releases. Zero runtime deps beyond `curl` and standard archive tools.

## Stack

- Bash (`bin/untapped`, `lib/install.sh`, `lib/add.sh`)
- bats (Ubuntu + macOS); shellcheck + check-docs (Ubuntu)
- Task runner: `just` (default recipe lists commands)

## Key commands

```sh
just setup           # verify shellcheck + bats + Python 3
just test            # bats tests/*.bats
just lint            # shellcheck on all shell code and Bats tests
just check-docs      # mechanical doc checks (scripts/check-docs.sh)
just sync-docs       # CLAUDE.md <-> AGENTS.md
```

## Key files

- `bin/untapped` — CLI entry; dispatches `add` → `lib/add.sh`, else `lib/install.sh`
- `lib/install.sh` — install/upgrade/list/doctor/outdated engine + conf discovery + first-run seed
- `lib/common.sh` — shared field validation, GitHub downloads, archive inspection
- `lib/add.sh` — GitHub URL → conf line (asset pick, binary sniff, append)
- `conf/untapped.conf.example` — packaging shapes; never used implicitly
- `tests/` — bats; mocked curl, seeded validation cases, Python PTY helper for real prompts
- `.github/workflows/ci.yml` — shellcheck (Ubuntu); bats (Ubuntu + macOS); check-docs (Ubuntu)

## Notes

- First run with no conf: interactive prompt seeds from example (Enter = yes) or empty conf; `--yes` seeds example; no TTY without `--yes` seeds empty. Never auto-installs on first run.
- Version state: `~/.local/share/untapped/installed.conf` (one-time import from legacy ghr path if present).
- Personal package list lives in scriptorium conf, not this repo.
