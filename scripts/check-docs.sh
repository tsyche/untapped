#!/usr/bin/env bash
# Validate documentation claims that can be checked without project-specific code.
# Repositories can add executable scripts/check-docs.local.sh for local assertions.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

failures=0

fail() {
  printf 'check-docs: %s\n' "$*" >&2
  failures=$((failures + 1))
}

markdown_files=()
while IFS= read -r -d '' file; do
  markdown_files+=("${file#./}")
done < <(find . \
  \( -name .git -o -name node_modules -o -name .next -o -name dist -o -name build \) -prune -o \
  -type f -name '*.md' -print0)

if [[ -f AGENTS.md && -f CLAUDE.md ]] && ! cmp -s AGENTS.md CLAUDE.md; then
  fail 'AGENTS.md and CLAUDE.md differ; run just sync-docs and review the result.'
fi

if [[ -f justfile || -f Justfile ]]; then
  justfile=justfile
  [[ -f Justfile ]] && justfile=Justfile
  recipes="$(sed -nE 's/^([[:alnum:]_-]+)([[:space:]]+[^:]*)?:.*/\1/p' "$justfile" | sort -u)"

  while IFS= read -r recipe; do
    [[ -z "$recipe" || "$recipe" == *- ]] && continue
    if ! printf '%s\n' "$recipes" | grep -Fxq "$recipe"; then
      fail "documented just recipe does not exist: just $recipe"
    fi
  done < <(awk '
    /^```/ { in_fence = !in_fence; next }
    {
      line = $0
      pattern = in_fence ? "just[ \\t]+[[:alnum:]_-]+" : "`just[ \\t]+[[:alnum:]_-]+"
      while (match(line, pattern)) {
        command = substr(line, RSTART, RLENGTH)
        sub(/^`/, "", command)
        print command
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "${markdown_files[@]}" | sed -E 's/^just[[:space:]]+//' | sort -u)
fi

is_repo_path() {
  case "$1" in
    /*|\~*|http:*|https:*|*' '*|*'*'*) return 1 ;;
    ./*|../*) return 0 ;;
    */*) [[ -d "${1%%/*}" ]] ;;
    justfile|Justfile|Makefile|Dockerfile|.env.example|.tool-versions) return 0 ;;
    *.md|*.json|*.toml|*.yml|*.yaml|*.sh) [[ -e "$1" ]] ;;
    *) return 1 ;;
  esac
}

for agent_doc in AGENTS.md CLAUDE.md; do
  [[ -f "$agent_doc" ]] || continue
  while IFS= read -r code; do
    path="${code#\`}"; path="${path%\`}"
    path="${path%%#*}"; path="${path%/}"
    [[ -z "$path" ]] && continue
    is_repo_path "$path" || continue
    [[ "$path" == *'*'* ]] && continue
    case "$path" in node_modules/*|.next/*|dist/*|build/*) continue ;; esac
    if [[ ! -e "$path" ]]; then
      fail "$agent_doc references missing repo path: $path"
    fi
  done < <(grep -Eo "\`[^\`]+\`" "$agent_doc" 2>/dev/null || true)
done

for markdown_file in "${markdown_files[@]}"; do
  while IFS= read -r link; do
    target="${link#*(}"; target="${target%)}"
    target="${target#<}"; target="${target%>}"
    target="${target%%[[:space:]]*}"; target="${target%%#*}"; target="${target%%\?*}"
    case "$target" in
      ''|\#*|/*|~*|http:*|https:*|mailto:*) continue ;;
    esac
    if [[ ! -e "$(dirname "$markdown_file")/$target" ]]; then
      fail "$markdown_file has a broken relative link: $target"
    fi
  done < <(grep -Eo '\[[^]]*\]\([^)]*\)' "$markdown_file" 2>/dev/null || true)
done

if [[ -d docs ]]; then
  while IFS= read -r -d '' doc; do
    first_content="$(awk 'NR == 1 && /^# / { next } NF { print; exit }' "$doc")"
    if [[ "$first_content" != '**TL;DR:'* ]]; then
      fail "${doc#./} must start with **TL;DR:** after its title"
    fi
  done < <(find docs -type f -name '*.md' -print0)
fi

extension="${DOCS_CHECK_EXTENSION:-scripts/check-docs.local.sh}"
if [[ -e "$extension" ]]; then
  if [[ ! -x "$extension" ]]; then
    fail "$extension exists but is not executable"
  elif ! "$extension"; then
    fail "repo-specific extension failed: $extension"
  fi
fi

if (( failures > 0 )); then
  exit 1
fi

printf 'check-docs: passed\n'
