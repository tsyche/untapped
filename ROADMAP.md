# untapped roadmap

**TL;DR:** Active installer work, with `doctor`, `outdated`, and version pinning recommended next. Completed work lives in the shipped ledger.

Conf-driven GitHub-release installer — active work only. Shipped history: [docs/ledger/ROADMAP_SHIPPED.md](docs/ledger/ROADMAP_SHIPPED.md).

## Recommended next 3

1. **`untapped doctor`** — print conf path, bin/share dirs, package counts, OS/arch. Effort: S
2. **`untapped outdated`** — list installed vs latest without installing (dry-run upgrade view). Effort: M
3. **Per-package version pin** — optional conf field/tag pin so `{VERSION}` isn't always latest. Effort: M

## High priority backlog

- [ ] First tagged release — cut `v0.1.0` + `gh release create`. Effort: S · 🧑 needs-human: version choice and public publish decision

## Remaining backlog

- [ ] Windows Git Bash support — either ship path handling or close as WSL-only. Effort: L · 🧑 needs-human: product decision ship vs WSL-only
- [ ] Non-GitHub hosts (generic HTTP assets) — Effort: L
- [ ] Parallel installs / retry — Effort: M
- [ ] `untapped remove <name>` subcommand — Effort: S
- [ ] Optional: Homebrew formula/cask mirror for popular entries — Effort: M · 🧑 needs-human: brew tap/account and publish

## Out of scope

- Replacing brew for bottles that already work well
- Interactive TUI (conf stays plain text)
