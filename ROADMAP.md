# untapped roadmap

**TL;DR:** Active installer work. Shipped history lives in the ledger.

Conf-driven GitHub-release installer — active work only. Shipped history: [docs/ledger/ROADMAP_SHIPPED.md](docs/ledger/ROADMAP_SHIPPED.md).

## Recommended next 3

1. **`untapped remove <name>`** — drop a conf line + uninstall binary/version state. Effort: S
2. **Parallel installs / retry** — faster multi-package runs; retry transient download failures. Effort: M
3. **Non-GitHub hosts (generic HTTP assets)** — install from plain HTTPS release URLs, not only github.com. Effort: L

## High priority backlog

- [ ] First tagged release — cut `v0.1.0` + `gh release create`. Effort: S · 🧑 needs-human: version choice and public publish decision

## Remaining backlog

- [ ] Windows Git Bash support — either ship path handling or close as WSL-only. Effort: L · 🧑 needs-human: product decision ship vs WSL-only
- [ ] Optional: Homebrew formula/cask mirror for popular entries — Effort: M · 🧑 needs-human: brew tap/account and publish

## Out of scope

- Replacing brew for bottles that already work well
- Interactive TUI (conf stays plain text)
