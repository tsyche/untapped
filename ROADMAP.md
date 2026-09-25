# untapped roadmap

**TL;DR:** Active installer work. Shipped history lives in the ledger.

Conf-driven release installer (GitHub + plain HTTPS) — active work only. Shipped history: [docs/ledger/ROADMAP_SHIPPED.md](docs/ledger/ROADMAP_SHIPPED.md).

## Recommended next

1. **Generic sources: sha256 sidecar checksums** — closes the integrity gap for non-GitHub installs. Effort: M

## High priority backlog

- [ ] **Generic sources: sha256 sidecar checksums** — probe `.sha256`/`SHA256SUMS` sibling URLs next to a generic asset and verify when present (GitHub convention stays as-is). Effort: M
- [ ] **`untapped test-rule <url>`** — dry-run version discovery + candidate scrape against any page; prints extracted version and numbered links without touching conf. Effort: S
- [ ] **`outdated --json` / CI exit codes** — machine-readable mode so a cron job can fail when updates exist (self-updating CLI runner pattern). Effort: S
- [ ] **`doctor --check` reachability probe** — HEAD every conf source URL, report dead hosts/404s before an install run needs them. Effort: M
- [ ] **Shell completions (zsh/bash)** — commands, flags, and package names read from conf. Effort: S

## Remaining backlog

- [ ] **Resume partial downloads** — `curl -C -` on retries so a flaky 200MB asset doesn't restart from zero. Effort: M
- [ ] **Mirror prefix support** — `UNTAPPED_MIRROR` (e.g. ghproxy-style) rewrites github.com URLs for slow/blocked networks. Effort: M
- [ ] **`import --brew`** — read `brew leaves`, generate conf stubs for tools you'd migrate off brew (import ≠ replace, stays out-of-scope's spirit). Effort: M
- [ ] **Install bootstrap script** — `curl | sh` that installs untapped itself (unblocked by the first tagged release). Effort: M
- [ ] **Git-synced conf** — `untapped sync` pulls conf from a git remote (codifies the current scriptorium symlink workflow). Effort: M
- [ ] **`verify` — re-check installed binaries against recorded hashes** — detects corruption/tamper, prints per-package status. Effort: M
- [ ] Windows Git Bash support — either ship path handling or close as WSL-only. Effort: L · 🧑 needs-human: product decision ship vs WSL-only
- [ ] Optional: Homebrew formula/cask mirror for popular entries — Effort: M · 🧑 needs-human: brew tap/account and publish

## Out of scope

- Replacing brew for bottles that already work well
- Interactive TUI (conf stays plain text)
