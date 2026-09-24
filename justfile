# Project task runner. Run `just --list` to see all available commands.

# Show available commands
default:
    @just --list

# Verify lint/test tools are installed
setup:
    @command -v shellcheck >/dev/null || { echo "shellcheck missing — brew install shellcheck"; exit 1; }
    @command -v bats >/dev/null || { echo "bats missing — brew install bats-core"; exit 1; }
    @command -v python3 >/dev/null || { echo "python3 missing (terminal prompt tests)"; exit 1; }
    @echo "tools ok"

# Run the bats suite (curl mocked; no network)
test:
    bats tests/*.bats

# Lint all shell code and Bats tests
lint:
    @command -v shellcheck >/dev/null || { echo "shellcheck not installed — brew install shellcheck"; exit 1; }
    shellcheck -x lib/*.sh bin/untapped scripts/*.sh tests/test_helper.bash tests/*.bats

# shellcheck has no autofix — kept for init-repo parity
lintfix: lint

# Remove local artifacts (none generated today)
clean:
    @echo "nothing to clean"

# Confirm a clean tree after clean (fresh clone-like check)
fresh: clean
    @git status --porcelain

# Validate documentation claims that can be checked mechanically
check-docs:
    ./scripts/check-docs.sh

# Sync CLAUDE.md <-> AGENTS.md (copy whichever is newer onto the other)
sync-docs:
    @if [ AGENTS.md -nt CLAUDE.md ]; then cp AGENTS.md CLAUDE.md && echo "synced AGENTS.md -> CLAUDE.md"; \
     elif [ CLAUDE.md -nt AGENTS.md ]; then cp CLAUDE.md AGENTS.md && echo "synced CLAUDE.md -> AGENTS.md"; \
     else echo "already in sync"; fi
