# untapped

[![CI](https://github.com/tsyche/untapped/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tsyche/untapped/actions/workflows/ci.yml?query=branch%3Amain)

**TL;DR:** Install CLI binaries and macOS `.app` bundles from GitHub releases or any plain HTTPS host — the packages brew doesn't bottle — via one plain-text package list. Zero deps beyond `curl` and standard archive tools; add a line, no script changes.

## Why

Homebrew covers most tools. For the rest — no formula, abandoned tap, lagging bottle — you end up hand-rolling `curl | tar` into `~/.local/bin`. `untapped` is that loop, one conf file:

- **Declarative** — pipe-delimited conf, not YAML, not a script
- **Filtered before download** — OS/arch mismatches skip with a reason, before any network I/O
- **Checksummed when available** — best-effort sha256 against the release's checksums file
- **Entitlement-safe `.app` installs** — whole bundle preserved under `~/.local/opt` (macOS Virtualization/Hypervisor tools get SIGKILLed if flattened)
- **Honest exit summary** — every run ends with `Installed / Updated / Skipped / Failed` counts and reasons; exit 1 on failure

macOS (arm64) and Linux (amd64/arm64) are supported, including WSL; Windows (Git Bash) is planned and exits with a clear message.

## Quick start

```sh
git clone https://github.com/tsyche/untapped.git
cd untapped

./bin/untapped help
./bin/ut                      # shortcut — identical binary, shorter name
./bin/untapped                 # first run: prompt to seed conf from example (Enter = yes)
./bin/untapped add https://github.com/xo/usql
./bin/untapped list            # conf entries + install status (offline)
./bin/untapped doctor          # conf path, dirs, counts, OS/arch (offline)
./bin/untapped outdated        # installed vs latest; report only
./bin/untapped lint            # validate every conf line (offline)
./bin/untapped why <name>      # one entry: conf line, filters, status (offline)
./bin/untapped --yes           # install anything missing + upgrade anything behind
./bin/untapped upgrade --yes   # alias of the bare command
./bin/untapped remove <name>   # drop conf entry + uninstall
```

First run with no conf:

- **Interactive** — `Seed from packaged example? [Y/n]`; Enter copies the example conf into `~/.config/untapped/conf` and prints next steps; decline seeds an empty conf with an `add` hint
- **`--yes`** — seeds the example; no install until you run again
- **No TTY, no `--yes`** — empty conf + guidance; the packaged example is never installed from implicitly

Put `bin/` on `PATH` or symlink it — `bin/ut` is a shortcut symlink to `bin/untapped`, either name works:

```sh
ln -s "$PWD/bin/untapped" ~/.local/bin/untapped   # or name it ut
```

### Conf discovery order

1. `-c /path/to/conf`
2. `~/.config/untapped/conf` (first run: seed prompt, or empty if non-interactive without `--yes`)
3. packaged `conf/untapped.conf.example` only when passed via `-c` — never used implicitly as install source

<details>
<summary>Environment variables</summary>

| Var | Purpose |
|-----|---------|
| `GITHUB_TOKEN` | optional; raises GitHub API rate limits (Bearer auth) |
| `GH_TOKEN` | fallback when `GITHUB_TOKEN` is unset (matches `gh`'s env) |
| `UNTAPPED_BIN_DIR` | override install dir (default `~/.local/bin`) |
| `UNTAPPED_SHARE_DIR` | override version state dir (default `~/.local/share/untapped`) |
| `UNTAPPED_JOBS` | default for `-j` |
| `UNTAPPED_RETRIES` | default for `--retries` |

</details>

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

**Notes:** every command works as `ut …` too. Non-interactive runs without `--yes` fail fast (no hang) — cron/launchd should pass `--yes`. From brew: `outdated` ≈ `brew outdated`, bare `untapped` ≈ `brew update && brew upgrade` (versions fetch live — no update step); it also installs missing conf entries, since conf is intent. Installs, upgrades, and tag fetches run 4-way parallel (`-j 1` = serial) with retry + backoff (`--retries`, default 2), draining in submission order.

### `untapped add`

Points at a GitHub repo (URL or `owner/repo`): fetches the latest release, scores assets for your OS/arch, sniffs the binary inside, shows the conf line, asks before appending:

```sh
untapped add https://github.com/xo/usql
untapped add xo/usql --dry-run          # print line only
untapped add openai/tart --asset tart.tar.gz
untapped add owner/repo --yes           # write without prompt
```

Flags: `-c PATH` (conf to append), `--name` (override package name), `--asset` (GitHub: asset filename; generic source: full download URL). Refuses to write the packaged example conf. Then run `untapped` to install.

<details>
<summary>Non-GitHub version pages, direct download URLs, platform spellings</summary>

Noncanonical platform spellings (`macos`, `aarch64`) are preserved with their filters — review the printed line before sharing across machines.

Any `https://` version-page URL works too (see [Non-GitHub sources](#non-github-sources)): probes the page for a version, lists every archive link it finds (numbered pick; `--yes` takes the best version/OS/arch match; `--asset` forces a URL), derives `{VERSION}`/`{OS}`/`{ARCH}` plus filters, sniffs the binary, appends. Unfetchable page, no version, or no TTY → prints an editable conf line instead:

```sh
untapped add https://dl.k8s.io/release/stable.txt
untapped add --asset 'https://releases.hashicorp.com/terraform/1.16.4/terraform_1.16.4_darwin_arm64.zip' \
  https://checkpoint-api.hashicorp.com/v1/check/terraform
```

Shorter: pass the **direct download URL** itself — version and version source come from the URL, name/placeholders/filters from the filename; it prompts for a version page only when discovery fails:

```sh
untapped add https://releases.hashicorp.com/terraform/1.16.4/terraform_1.16.4_darwin_arm64.zip
```

</details>

### `untapped remove`

Unmanages a package: drops its conf line, deletes the binary (plus the `.app` bundle under `~/.local/opt`), clears version state — offline, so filtered entries still clean up on any host.

```sh
untapped remove usql
untapped remove usql tart --yes     # several at once; skip prompt
untapped remove usql --dry-run      # show what would go; touch nothing
```

<details>
<summary>Prompt order and safety guarantees</summary>

Confirms first (default **No**; `--yes` skips). The conf line is rewritten before artifacts delete — through a conf symlink without replacing it — so a failed delete can't reinstall on the next run. PATH binaries untapped didn't install (e.g. brew) are left alone. Refuses the packaged example conf.

</details>

## Conf format

```
name | source | asset_pattern | binary_in_archive | os_filter | arch_filter | version_pin | version_rule
```

Placeholders: `{VERSION}` (release tag, `v` stripped; or `version_pin` if set), `{OS}` (`darwin`/`linux`), `{ARCH}` (`arm64`/`amd64`). Omit `os_filter` / `arch_filter` / `version_pin` to match any / use latest — mismatched entries are skipped with a reason before download.

<details>
<summary>Column reference</summary>

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

</details>

### Non-GitHub sources

<details>
<summary>Generic-source behavior and notes</summary>

A `source` starting with `https://` makes the entry generic: fetch that URL, extract the latest version by `version_rule` (first match; default picks a dotted version), download `asset_pattern` with placeholders substituted. Works for plain-text version endpoints, project pages, CDNs — anywhere with stable URLs:

```
# name | source | asset_pattern (full URL) | binary | os | arch | pin | version_rule
tool | https://dl.example.com/tool/latest | https://cdn.example.com/tool/{VERSION}/tool-{VERSION}-{OS}-{ARCH}.tar.gz | tool | | | |
```

Pin with `version_pin` to skip discovery; tighten `version_rule` (e.g. `[0-9]+\.[0-9]+\.[0-9]+`) against decoy numbers; checksums are skipped (no convention outside GitHub); `untapped add` handles these too (see [`untapped add`](#untapped-add)). `GITHUB_TOKEN` (or `GH_TOKEN`) is never sent to non-GitHub hosts.

</details>

### Examples

<details>
<summary>Four packaging shapes, comments, supported archives</summary>

Four common packaging shapes live in [`conf/untapped.conf.example`](conf/untapped.conf.example):

| Shape | Example entry |
|-------|----------------|
| Flat archive, OS+arch in filename | `usql \| xo/usql \| usql-{VERSION}-{OS}-{ARCH}.tar.bz2 \| usql \| \|` |
| macOS `.app` bundle (entitlement-preserving) | `tart \| openai/tart \| tart.tar.gz \| tart.app/Contents/MacOS/tart \| darwin \|` |
| Fixed asset name, macOS-only | `softnet \| openai/softnet \| softnet.tar.gz \| softnet \| darwin \|` |
| Bare AppImage, Linux amd64 | `shotcut \| mltframework/shotcut \| shotcut-linux-x86_64-{VERSION}.AppImage \| shotcut \| linux \| amd64` |

Lines starting with `#` (after optional whitespace) are comments; blank lines are ignored.

Supported assets: `.tar.gz`/`.tgz`, `.tar.bz2`/`.tbz`, `.tar.xz`/`.txz`, `.tar`, `.zip`, and bare binaries. Absolute paths, parent traversal, and links escaping extraction are rejected. Only install releases from publishers you trust; checksums are best-effort and do not authenticate a publisher.

</details>

## Exit summary

Every run ends with `Installed / Updated / Skipped / Failed` counts and reason lists; exit code `1` if anything failed. Dry runs print `[dry-run] …` plus `Would install:` / `Would update:` lists.

<details>
<summary>Example output</summary>

```
Installed: 2  Updated: 1  Skipped: 3  Failed: 0

Skipped:
  • softnet — not available on linux

Failed:
  • broken — checksum mismatch
```

</details>

## Development

```sh
just setup && just test && just lint && just check-docs
```

CI: shellcheck + check-docs on `ubuntu-26.04`; bats on `ubuntu-26.04` and `macos-latest` ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)). Tests mock `curl` with fixtures — no network needed. See [CONTRIBUTING.md](CONTRIBUTING.md) for PR basics and [ROADMAP.md](ROADMAP.md) for planned work.

## License

MIT — see [LICENSE](LICENSE).
