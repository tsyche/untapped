# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-24

First release.

### Added
- Conf-driven installs from GitHub releases and plain HTTPS sources; pipe-delimited conf, one file
- OS/arch filters skipped before any network I/O; per-package version pins; best-effort sha256 on GitHub assets
- Entitlement-safe macOS `.app` installs under `~/.local/opt`
- Parallel installs and latest-tag fetches (`-j`, default 4) with bounded retry + backoff (`--retries`)
- Commands: bare `untapped` (install missing + upgrade behind), `upgrade` (alias), `list`, `doctor`, `outdated`, `lint`, `why <name>`, `add <url|o/r>`, `remove`, `help`
- `add` supports GitHub releases, version-page URLs, and direct download URLs; scrapes pages for archive candidates with numbered selection
- Honest exit summary with counts and reason lists; `--dry-run` preview; non-interactive runs fail fast without `--yes`
- CI: shellcheck + check-docs (ubuntu), bats (ubuntu + macOS)
