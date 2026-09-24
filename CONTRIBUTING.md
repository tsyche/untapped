# Contributing to untapped

Bug reports, conf-format fixes, and small shell improvements welcome. Large features: open an issue first.

## Develop

```sh
git clone https://github.com/tsyche/untapped.git
cd untapped
just setup   # needs shellcheck + bats
just test
just lint
just check-docs
```

No build step. Edit `bin/`, `lib/`, `tests/`, `conf/`, docs; re-run `just test` and `just lint`.

## Tests

- bats under `tests/` (`add.bats`, `cli.bats`, `install.bats`)
- `curl` is mocked via `tests/test_helper.bash` — no network in CI or locally
- Add a test for every behavior change; keep fixtures in `test_helper.bash`

## Lint

- `just lint` — shellcheck on `lib/install.sh`, `lib/add.sh`, `bin/untapped`, `tests/test_helper.bash`
- shellcheck has no autofix; fix findings at the source

## Docs

- Keep `README.md` accurate for user-facing behavior
- `CLAUDE.md` and `AGENTS.md` stay identical: edit one, run `just sync-docs`
- `just check-docs` must pass (links, recipe references, agent-doc paths)

## Pull requests

1. Branch from `main` (`fix/…`, `docs/…`, or a short topic name)
2. One logical change per PR
3. CI must be green: shellcheck, bats (Ubuntu + macOS), check-docs
4. No Co-Authored-By trailer required; conventional-commit prefixes not required — short imperative summary

## Code style

- Bash: `set -euo pipefail`, portable coreutils where practical
- Prefer conf-driven behavior over new flags when the data already fits the conf format
- Windows exits early with a clear message until Git Bash support lands (see `ROADMAP.md`)
