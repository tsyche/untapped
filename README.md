# untapped

[![CI](https://github.com/tsyche/untapped/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tsyche/untapped/actions/workflows/ci.yml?query=branch%3Amain)

**TL;DR:** Install CLI binaries and macOS app bundles straight from GitHub releases — or from any plain HTTPS host — when brew doesn't bottle them (or even if it does; anything with a release is fair game) — via a plain-text package list. Add a repository, then install or upgrade its release assets.

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
./bin/untapped                 # first run: prompt to seed conf from example (Enter = yes)
./bin/untapped add https://github.com/xo/usql
./bin/untapped list            # conf entries + installed / not on PATH (offline)
./bin/untapped doctor         # conf path, dirs, counts, OS/arch (offline)
./bin/untapped outdated        # installed vs latest; report only
./bin/untapped lint            # validate every conf line (offline)
./bin/untapped why <name>      # one entry: conf line, filters, status (offline)
./bin/untapped --yes           # install anything missing + upgrade anything behind
./bin/untapped upgrade --yes   # alias of the bare command
./bin/untapped remove <name>   # drop conf entry + uninstall
```

First run with no conf:

- **Interactive** — prompt `Seed from packaged example? [Y/n]`; Enter copies `conf/untapped.conf.example` → `~/.config/untapped/conf`, then prints next steps (review, `untapped add`, `untapped --yes`). Decline seeds an empty conf + `add` hint.
- **`--yes`** — takes the default (seed from example); no install until you run again.
- **No TTY, no `--yes`** — empty conf + guidance (script-safe); never installs from the packaged example implicitly.

Optional: put `bin/` on `PATH`, or symlink — `bin/ut` ships as a symlink to `bin/untapped`, so either name works:

```sh
ln -s "$PWD/bin/untapped" ~/.local/bin/untapped   # or name it ut
```

### Conf discovery order

1. `-c /path/to/conf`
2. `~/.config/untapped/conf` (first run: prompt to seed from example, or empty if non-interactive without `--yes`)
3. packaged `conf/untapped.conf.example` only when you pass `-c` at it — never used implicitly as install source

### Environment

| Var | Purpose |
|-----|---------|
| `GITHUB_TOKEN` | optional; raises GitHub API rate limits (Bearer auth) |
| `GH_TOKEN` | fallback when `GITHUB_TOKEN` is unset (matches `gh`'s env) |
| `UNTAPPED_BIN_DIR` | override install dir (default `~/.local/bin`) |
| `UNTAPPED_SHARE_DIR` | override version state dir (default `~/.local/share/untapped`) |
| `UNTAPPED_JOBS` | default for `-j` |
| `UNTAPPED_RETRIES` | default for `--retries` |

## CLI

```
untapped                 install missing packages; upgrade outdated ones
untapped upgrade         same as bare untapped (familiar from brew)
untapped list            show conf entries + install status (no network)
untapped doctor          print conf/paths/counts (no network)
untapped outdated        list installed vs latest (no install)
untapped lint            validate every conf line (no network)
untapped why <name>      show one entry: conf line, filters, install state
untapped add <url|o/r>   inspect a GH release; append a conf line
untapped remove <name>... drop conf line + uninstall binary/state
untapped help            show help

Options:
  -c, --config PATH      conf file
  -y, --yes              non-interactive; accept all prompts
  -n, --dry-run          show what would change; install nothing
  -j, --jobs N           parallel install jobs (default: 4; 1 = serial)
      --retries N        retries for transient failures (default: 2; 0 = off)
      --upgrade          same as the upgrade subcommand
```

Every command works as `ut …` too — `bin/ut` is a symlink to `bin/untapped`.

Non-interactive runs without `--yes` fail fast with a clear message (no silent hang). Cron/launchd should pass `--yes`.

Coming from brew? `untapped outdated` ≈ `brew outdated`, and the bare `untapped` (or `untapped upgrade`) ≈ `brew update && brew upgrade` — no separate update step, because version metadata is fetched live on each run rather than cached. The bare run also installs anything in your conf that's missing: your conf declares intent, so one command converges reality to it.

Installs, upgrades, and latest-tag fetches run up to 4 jobs in parallel (`-j 1` restores strict serial), with bounded retry + backoff on transient download/API failures (`--retries`, default 2). Output drains in submission order, so the console and exit summary read like a serial run.

### `untapped add`

Point it at a GitHub repo (URL or `owner/repo`). It fetches the latest release, scores assets for your OS/arch, downloads the winner just long enough to find the binary path inside, then shows the conf line and asks before appending:

```sh
untapped add https://github.com/xo/usql
untapped add xo/usql --dry-run          # print line only
untapped add openai/tart --asset tart.tar.gz
untapped add owner/repo --yes           # write without prompt
```

Generated conf entries preserve noncanonical platform spellings such as `macos` and `aarch64` with platform filters. Review the printed line before sharing it across machines.

It also accepts any `https://` version-page URL (see [Non-GitHub sources](#non-github-sources)): it probes the page for a version, lists every archive link it finds there (numbered pick; `--yes` takes the best version/OS/arch match), or falls back to asking for one concrete download URL when the page has no usable links (`--asset` forces a full URL either way). It then derives `{VERSION}`/`{OS}`/`{ARCH}` plus platform filters, sniffs the binary inside, and appends the line. When the page can't be fetched, has no version, or stdin isn't a TTY, it prints an editable conf line instead:

```sh
untapped add https://dl.k8s.io/release/stable.txt
untapped add --asset 'https://releases.hashicorp.com/terraform/1.16.4/terraform_1.16.4_darwin_arm64.zip' \
  https://checkpoint-api.hashicorp.com/v1/check/terraform
```

Shorter: pass the **direct download URL** itself. One-shot flow takes the version from the URL, discovers the version source from the parent directory (stripped of the version segment), derives name/placeholders/filters from the filename, and only prompts for a version page when discovery fails:

```sh
untapped add https://releases.hashicorp.com/terraform/1.16.4/terraform_1.16.4_darwin_arm64.zip
```

Flags: `-c PATH` (conf to append), `--name` (override package name), `--asset` (GitHub: asset filename; generic source: full download URL). Refuses to write the packaged example conf. Then run `untapped` to install.

### `untapped remove`

Unmanages a package: drops its conf line, deletes the installed binary (plus the `.app` bundle under `~/.local/opt` when applicable), and clears its version state. Offline — no OS/arch filtering, so a filtered entry still cleans up on any host.

```sh
untapped remove usql
untapped remove usql tart --yes     # several at once; skip prompt
untapped remove usql --dry-run      # show what would go; touch nothing
```

Confirms first (default **No**; `--yes` skips). Conf line is rewritten before artifacts delete — through a conf symlink without replacing it — so a failed delete can't reinstall on the next run. PATH binaries untapped didn't install (e.g. brew) are reported and left alone. Refuses the packaged example conf.

## Conf format

```
name | source | asset_pattern | binary_in_archive | os_filter | arch_filter | version_pin | version_rule
```

| Column | Required | Notes |
|--------|----------|-------|
| `name` | yes | binary name on PATH; starts with a letter/digit, then letters, digits, `.`, `_`, `+`, or `-` |
| `source` | yes | GitHub `owner/repo`, or an `https://` URL whose response body carries the latest version |
| `asset_pattern` | yes | GitHub: asset filename; generic source: full `https://` download URL. May use `{VERSION}` `{OS}` `{ARCH}` |
| `binary_in_archive` | yes | relative path inside archive; supports `{VERSION}`; `*.app/Contents/MacOS/*` keeps the whole bundle |
| `os_filter` | no | `darwin` or `linux` |
| `arch_filter` | no | `arm64` or `amd64` |
| `version_pin` | no | pin a release tag (e.g. `v1.2.3`); empty = latest |
| `version_rule` | no | generic sources only: POSIX ERE matched against the `source` response (default: a dotted version like `1.2.3`); must match exactly the version text; may contain `\|` (last field) |

Placeholders:

- `{VERSION}` — release tag, `v` prefix stripped (latest, or `version_pin` if set)
- `{OS}` — `darwin` or `linux`
- `{ARCH}` — `arm64` or `amd64`

Omit (or leave empty) `os_filter` / `arch_filter` / `version_pin` to match any / use latest. Mismatched entries are skipped with a reason in the exit summary, before download.

### Non-GitHub sources

A `source` that starts with `https://` makes the entry generic: `untapped` fetches that URL, extracts the latest version by `version_rule` (first match; default picks a dotted version), then downloads `asset_pattern` with the placeholders substituted. Works for plain-text version endpoints, project pages, CDNs — anywhere with stable URLs:

```
# name | source | asset_pattern (full URL) | binary | os | arch | pin | version_rule
tool | https://dl.example.com/tool/latest | https://cdn.example.com/tool/{VERSION}/tool-{VERSION}-{OS}-{ARCH}.tar.gz | tool | | | |
```

Notes: pin with `version_pin` to skip discovery entirely; if the page has decoy numbers, tighten `version_rule` (e.g. `[0-9]+\.[0-9]+\.[0-9]+`); checksum verification is skipped (no convention outside GitHub); `untapped add` handles these too — version-page URLs or direct download URLs (see [`untapped add`](#untapped-add)). `GITHUB_TOKEN` (or `GH_TOKEN`) is never sent to non-GitHub hosts.

### Examples

Four common packaging shapes live in [`conf/untapped.conf.example`](conf/untapped.conf.example):

| Shape | Example entry |
|-------|----------------|
| Flat archive, OS+arch in filename | `usql \| xo/usql \| usql-{VERSION}-{OS}-{ARCH}.tar.bz2 \| usql \| \|` |
| macOS `.app` bundle (entitlement-preserving) | `tart \| openai/tart \| tart.tar.gz \| tart.app/Contents/MacOS/tart \| darwin \|` |
| Fixed asset name, macOS-only | `softnet \| openai/softnet \| softnet.tar.gz \| softnet \| darwin \|` |
| Bare AppImage, Linux amd64 | `shotcut \| mltframework/shotcut \| shotcut-linux-x86_64-{VERSION}.AppImage \| shotcut \| linux \| amd64` |

Lines starting with `#` (after optional whitespace) are comments. Blank lines are ignored.

Supported assets: `.tar.gz`/`.tgz`, `.tar.bz2`/`.tbz`, `.tar.xz`/`.txz`, `.tar`, `.zip`, and bare binaries. Absolute paths, parent traversal, and links escaping extraction are rejected. Only install releases from publishers you trust; checksums are best-effort and do not authenticate a publisher.

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

## Development

```sh
just setup && just test && just lint && just check-docs
```

CI: shellcheck + check-docs on `ubuntu-24.04`; bats on `ubuntu-24.04` and `macos-latest` ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

Tests mock `curl` with fixtures; no network required. See [CONTRIBUTING.md](CONTRIBUTING.md) for PR basics and [ROADMAP.md](ROADMAP.md) for planned work.

## License

MIT — see [LICENSE](LICENSE).
