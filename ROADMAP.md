# untapped roadmap

**TL;DR:** Active installer work. Shipped history lives in the ledger.

Conf-driven release installer (GitHub + plain HTTPS) — active work only. Shipped history: [docs/ledger/ROADMAP_SHIPPED.md](docs/ledger/ROADMAP_SHIPPED.md).

## Recommended next

1. **First tagged release** — cut `v0.1.0` + `gh release create`. Effort: S · 🧑 needs-human: version choice and public publish decision

## Remaining backlog

- [ ] Windows Git Bash support — either ship path handling or close as WSL-only. Effort: L · 🧑 needs-human: product decision ship vs WSL-only
- [ ] Optional: Homebrew formula/cask mirror for popular entries — Effort: M · 🧑 needs-human: brew tap/account and publish

## Out of scope

- Replacing brew for bottles that already work well
- Interactive TUI (conf stays plain text)
