# untapped

Install CLI binaries straight from GitHub releases when brew doesn't bottle them (or even if they are — anything with a release is fair game).

Zero runtime deps beyond `curl` and standard archive tools. Conf-driven: add a line, no script changes.

## Why

Homebrew covers most tools. For the rest — no formula, abandoned tap, lagging bottle — you end up hand-rolling `curl | tar` into `~/.local/bin`. `untapped` is that loop, one conf file:

- **Declarative** — pipe-delimited conf, not YAML, not a script
- **Filtered before download** — OS/arch mismatches skip with a reason, before any network I/O
- **Checksummed when available** — best-effort sha256 against the release's checksums file
- **Entitlement-safe `.app` installs** — preserves the whole bundle under `~/.local/opt` (macOS Virtualization/Hypervisor tools get SIGKILLed if you flatten them out)
- **Honest exit summary** — every run ends with `Installed / Updated / Skipped / Failed` counts and reason lists; exit 1 on any failure

## Supported platforms

| Platform | Status |
|----------|--------|
| macOS (arm64) | supported |
| Linux (amd64/arm64) | supported |
| WSL | supported (Linux path) |
| Windows (Git Bash) | planned; exits with a clear message |

## Quick start

```sh
git clone https://github.com/tsyche/untapped.git
cd untapped

./bin/untapped help
./bin/untapped                 # first run: creates empty ~/.config/untapped/conf
./bin/untapped add https://github.com/xo/usql
./bin/untapped --yes           # install anything missing
./bin/untapped upgrade --yes   # check for updates
```

First run with no conf seeds an empty `~/.config/untapped/conf` and exits with that `add` hint (plus an optional PATH symlink one-liner) — it never installs from the packaged example. Optional starter set instead:

```sh
cp conf/untapped.conf.example ~/.config/untapped/conf
$EDITOR ~/.config/untapped/conf
```

Optional: put `bin/` on `PATH`, or symlink:

```sh
ln -s "$PWD/bin/untapped" ~/.local/bin/untapped
```

### Conf discovery order

1. `-c /path/to/conf`
2. `~/.config/untapped/conf` (created empty on first run if missing)
3. packaged `conf/untapped.conf.example` only when you pass `-c` at it — never used implicitly

### Environment

| Var | Purpose |
|-----|---------|
| `GITHUB_TOKEN` | optional; raises GitHub API rate limits (Bearer auth) |
| `UNTAPPED_BIN_DIR` | override install dir (default `~/.local/bin`) |
| `UNTAPPED_SHARE_DIR` | override version state dir (default `~/.local/share/untapped`) |

## CLI

```
untapped                 install missing packages
untapped upgrade         check for updates, install anything behind
untapped add <url|o/r>   inspect a GH release; append a conf line
untapped help            show help

Options:
  -c, --config PATH      conf file
  -y, --yes              non-interactive; accept all prompts
  -n, --dry-run          show what would change; install nothing
      --upgrade          same as the upgrade subcommand
```

Non-interactive runs without `--yes` fail fast with a clear message (no silent hang). Cron/launchd should pass `--yes`.

### `untapped add`

Point it at a GitHub repo (URL or `owner/repo`). It fetches the latest release, scores assets for your OS/arch, downloads the winner just long enough to find the binary path inside, then shows the conf line and asks before appending:

```sh
untapped add https://github.com/xo/usql
untapped add xo/usql --dry-run          # print line only
untapped add openai/tart --asset tart.tar.gz
untapped add owner/repo --yes           # write without prompt
```

Flags: `-c PATH` (conf to append), `--name` (override package name), `--asset` (force asset filename). Refuses to write the packaged example conf. Then run `untapped` to install.

## Conf format

```
name | github_repo | asset_pattern | binary_in_archive | os_filter | arch_filter
```

| Column | Required | Notes |
|--------|----------|-------|
| `name` | yes | binary name on PATH |
| `github_repo` | yes | `owner/repo` |
| `asset_pattern` | yes | may use `{VERSION}` `{OS}` `{ARCH}` |
| `binary_in_archive` | yes | path inside archive; `*.app/Contents/MacOS/*` keeps the whole bundle |
| `os_filter` | no | `darwin` or `linux` |
| `arch_filter` | no | `arm64` or `amd64` |

Placeholders:

- `{VERSION}` — latest release tag, `v` prefix stripped (e.g. `0.21.4`)
- `{OS}` — `darwin` or `linux`
- `{ARCH}` — `arm64` or `amd64`

Omit (or leave empty) `os_filter` / `arch_filter` to match any. Mismatched entries are skipped with a reason in the exit summary, before download.

### Examples

Four common packaging shapes live in [`conf/untapped.conf.example`](conf/untapped.conf.example):

| Shape | Example entry |
|-------|----------------|
| Flat archive, OS+arch in filename | `usql \| xo/usql \| usql-{VERSION}-{OS}-{ARCH}.tar.bz2 \| usql \| \|` |
| macOS `.app` bundle (entitlement-preserving) | `tart \| openai/tart \| tart.tar.gz \| tart.app/Contents/MacOS/tart \| darwin \|` |
| Fixed asset name, macOS-only | `softnet \| openai/softnet \| softnet.tar.gz \| softnet \| darwin \|` |
| Bare AppImage, Linux amd64 | `shotcut \| mltframework/shotcut \| shotcut-linux-x86_64-{VERSION}.AppImage \| shotcut \| linux \| amd64` |

`#` starts a comment. Blank lines ignored.

## Exit summary

Every run ends with counts:

```
Installed: 2  Updated: 1  Skipped: 3  Failed: 0

Skipped:
  • softnet — not available on linux
  • shotcut — not available on arm64

Failed:
  • broken — checksum mismatch
```

Dry-run variants print `[dry-run] Installed: 0  Updated: 0 ...` plus `Would install:` / `Would update:` lists. Exit code `1` if anything failed.

## Why not brew?

For tools with no maintained formula/cask — or a tap that lags upstream releases — `untapped` installs the upstream GitHub release directly. Complements brew; doesn't replace it.

## Development

```sh
just setup   # verify shellcheck + bats
just test    # bats tests/*.bats
just lint    # shellcheck -x lib/install.sh lib/add.sh bin/untapped tests/test_helper.bash
just check-docs
```

CI runs shellcheck + bats + check-docs on `ubuntu-24.04` and `macos-latest` ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

Tests mock `curl` with fixtures; no network required.

## License

MIT — see [LICENSE](LICENSE).
