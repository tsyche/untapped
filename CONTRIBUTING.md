# Contributing to untapped

**TL;DR:** Bug reports, conf-format fixes, and small shell improvements welcome. Large features: open an issue first.

## Develop

```sh
git clone https://github.com/tsyche/untapped.git
cd untapped
just setup   # needs shellcheck + bats + Python 3
just test
just lint
just check-docs
```

No build step. Edit `bin/`, `lib/`, `tests/`, `conf/`, docs; re-run `just test` and `just lint`.

## Tests

- bats runs every `tests/*.bats` file
- Python 3 runs the terminal helper for interactive prompt tests; production has no Python dependency
- Seeded validation cases report their seed and iteration on failure
- `curl` is mocked via `tests/test_helper.bash` — no network in CI or locally
- Add a test for every behavior change; keep fixtures in `test_helper.bash`

## Lint

- `just lint` — shellcheck on `lib/*.sh`, `bin/untapped`, `scripts/*.sh`, `tests/test_helper.bash`, and `tests/*.bats`
- shellcheck has no autofix; fix findings at the source

## Docs

- Keep `README.md` accurate for user-facing behavior
- `CLAUDE.md` and `AGENTS.md` stay identical: edit `AGENTS.md`, run `just sync-docs`
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
