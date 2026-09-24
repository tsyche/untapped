# untapped

**TL;DR:** Conf-driven installer for CLI binaries (and `.app` bundles) from GitHub releases or any plain HTTPS host. Zero runtime deps beyond `curl` and standard archive tools.

## Stack

- Bash (`bin/untapped`, `lib/install.sh`, `lib/add.sh`, `lib/remove.sh`)
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

- `bin/untapped` — CLI entry; dispatches `add` → `lib/add.sh`, `remove` → `lib/remove.sh`, else `lib/install.sh`
- `lib/install.sh` — install/upgrade/list/doctor/outdated engine + conf discovery + first-run seed
- `lib/common.sh` — shared field validation, HTTPS downloads (token sent to GitHub hosts only), archive inspection
- `lib/add.sh` — GitHub URL → conf line (asset pick, binary sniff, append)
- `lib/remove.sh` — drop conf line first, then binary/`.app` bundle/version state
- `conf/untapped.conf.example` — packaging shapes; never used implicitly
- `tests/` — bats; mocked curl, seeded validation cases, Python PTY helper for real prompts
- `.github/workflows/ci.yml` — shellcheck (Ubuntu); bats (Ubuntu + macOS); check-docs (Ubuntu)

## Notes

- First run with no conf: interactive prompt seeds from example (Enter = yes) or empty conf; `--yes` seeds example; no TTY without `--yes` seeds empty. Never auto-installs on first run.
- Version state: `~/.local/share/untapped/installed.conf` (one-time import from legacy ghr path if present).
- Parallelism: `-j N` (default 4, env `UNTAPPED_JOBS`) covers installs, upgrades, and latest-tag fetches; transient fetch/download failures retry with backoff (`--retries N`, default 2, env `UNTAPPED_RETRIES`). Version state is written by the parent only — never from parallel jobs, which would race on the state file.
- Generic sources: conf field 2 may be an `https://` URL (version discovery) with a full-URL `asset_pattern` in field 3 and optional `version_rule` regex as the last field (may contain `|` — it's the last field, so `read` keeps the remainder). Checksums skipped (GitHub convention only); `add` stays GitHub-only.
- `remove` rewrites the conf (through any symlink) before deleting artifacts, so a failed delete can never resurrect on the next run; foreign PATH binaries are left alone.
- Personal package list lives in scriptorium conf, not this repo.
