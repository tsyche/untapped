# untapped

Conf-driven installer for CLI binaries (and `.app` bundles) straight from GitHub releases. Zero runtime deps beyond `curl` and standard archive tools.

## Stack

- Bash (`bin/untapped`, `lib/install.sh`, `lib/add.sh`)
- bats + shellcheck (CI: Ubuntu + macOS)
- Task runner: `just` (default recipe lists commands)

## Key commands

```sh
just setup           # verify shellcheck + bats
just test            # bats tests/*.bats
just lint            # shellcheck -x lib/install.sh lib/add.sh bin/untapped tests/test_helper.bash
just check-docs      # mechanical doc checks (scripts/check-docs.sh)
just sync-docs       # CLAUDE.md <-> AGENTS.md
```

## Key files

- `bin/untapped` — CLI entry; dispatches `add` → `lib/add.sh`, else `lib/install.sh`
- `lib/install.sh` — install/upgrade engine + conf discovery + first-run seed
- `lib/add.sh` — GitHub URL → conf line (asset pick, binary sniff, append)
- `conf/untapped.conf.example` — packaging shapes; never used implicitly
- `tests/` — bats; `curl` mocked via `tests/test_helper.bash`
- `.github/workflows/ci.yml` — shellcheck + bats + check-docs

## Notes

- First run with no conf seeds empty `~/.config/untapped/conf` and exits with `untapped add` guidance.
- Version state: `~/.local/share/untapped/installed.conf` (one-time import from legacy ghr path if present).
- Personal package list lives in scriptorium conf, not this repo.
