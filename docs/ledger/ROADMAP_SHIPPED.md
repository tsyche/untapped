# Shipped Roadmap Items

**TL;DR:** Compact index of completed roadmap work followed by the original entries.

## Shipped index

- [x] 2026-09-24 — Non-GitHub hosts (generic HTTPS sources)
- [x] 2026-09-24 — Parallel installs / retry
- [x] 2026-09-24 — `untapped remove`
- [x] 2026-09-24 — `untapped doctor`
- [x] 2026-09-24 — `untapped outdated`
- [x] 2026-09-24 — Per-package version pin
- [x] 2026-09-23 — `untapped list`
- [x] 2026-09-23 — Fix `-c` help default
- [x] 2026-09-23 — CI path filters: include `conf/**`
- [x] 2026-09-23 — Conf engine: install/upgrade, OS/arch filters, sha256, exit summary
- [x] 2026-09-23 — First-run empty-conf seed + `untapped add`
- [x] 2026-09-23 — Entitlement-safe `.app` installs under `~/.local/opt`
- [x] 2026-09-23 — Dev workflow: justfile, shellcheck + bats + check-docs CI, CLAUDE/AGENTS
- [x] 2026-09-23 — One-time legacy ghr version-state migration

## Archived entries

### 2026-09-24 — Non-GitHub hosts (generic HTTPS sources)

1. **Non-GitHub hosts (generic HTTP assets)** — install from plain HTTPS release URLs, not only github.com. Effort: L

### 2026-09-24 — Parallel installs / retry

2. **Parallel installs / retry** — faster multi-package runs; retry transient download failures. Effort: M

### 2026-09-24 — `untapped remove`

1. **`untapped remove <name>`** — drop a conf line + uninstall binary/version state. Effort: S

### 2026-09-24 — `untapped doctor`

1. **`untapped doctor`** — print conf path, bin/share dirs, package counts, OS/arch. Effort: S

### 2026-09-24 — `untapped outdated`

2. **`untapped outdated`** — list installed vs latest without installing (dry-run upgrade view). Effort: M

### 2026-09-24 — Per-package version pin

3. **Per-package version pin** — optional conf field/tag pin so `{VERSION}` isn't always latest. Effort: M

### 2026-09-23 — `untapped list`

1. **`untapped list`** — show every conf entry + installed/not on PATH; quick inventory win. Effort: S

### 2026-09-23 — Fix `-c` help default

2. **Fix `-c` help default** — `lib/install.sh` usage still says "else packaged example"; code never uses the example implicitly (README is correct). Effort: S

### 2026-09-23 — CI path filters: include `conf/**`

3. **CI path filters: include `conf/**`** — example-conf edits don't currently trigger CI. Effort: S

### 2026-09-23 — Conf engine: install/upgrade, OS/arch filters, sha256, exit summary

- ✅ Conf engine: install/upgrade, OS/arch filters, sha256, exit summary

### 2026-09-23 — First-run empty-conf seed + `untapped add`

- ✅ First-run empty-conf seed + `untapped add` (asset pick, binary sniff, append)

### 2026-09-23 — Entitlement-safe `.app` installs under `~/.local/opt`

- ✅ Entitlement-safe `.app` installs under `~/.local/opt`

### 2026-09-23 — Dev workflow: justfile, shellcheck + bats + check-docs CI, CLAUDE/AGENTS

- ✅ Dev workflow: justfile, shellcheck + bats + check-docs CI, CLAUDE/AGENTS

### 2026-09-23 — One-time legacy ghr version-state migration

- ✅ One-time legacy ghr version-state migration
