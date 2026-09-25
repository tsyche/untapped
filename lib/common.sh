#!/usr/bin/env bash
# Shared validation and archive handling. Compatible with macOS Bash 3.2.

valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]
}

valid_repo() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

safe_relative_path() {
  case "$1" in
    ''|/*|*\\*|*'|'*|*[[:cntrl:]]*) return 1 ;;
  esac
  case "/$1/" in */../*) return 1 ;; esac
  return 0
}

valid_asset() {
  safe_relative_path "$1" && [[ "$1" != */* && "$1" != . && "$1" != .. ]]
}

valid_version_pin() {
  [[ -z "$1" ]] && return 0
  [[ "$1" != *[[:cntrl:]]* && "$1" != *'|'* ]]
}

validate_entry() {
  valid_name "$1" || return 1
  safe_relative_path "$4" || return 1
  [[ "$5" == '' || "$5" == darwin || "$5" == linux ]] || return 1
  [[ "$6" == '' || "$6" == arm64 || "$6" == amd64 ]] || return 1
  valid_version_pin "${7:-}" || return 1
  valid_version_rule "${8:-}" || return 1
  if is_generic_source "$2"; then
    valid_source "$2" && valid_url_template "$3"
  else
    valid_repo "$2" && valid_asset "$3"
  fi
}

# A generic source is an https URL whose response body carries the latest
# version. Anything else is a GitHub owner/repo.
is_generic_source() {
  [[ "$1" == https://* ]]
}

valid_source() {
  if [[ "$1" == https://* ]]; then
    [[ "$1" != *[[:space:]]* && "$1" != *[[:cntrl:]]* && "$1" != *'|'* ]]
  else
    valid_repo "$1"
  fi
}

# Generic asset_pattern: a full https URL template with a usable filename
# (query/fragment stripped when probing the final segment).
valid_url_template() {
  local f
  [[ "$1" == https://* && "$1" != *[[:space:]]* && "$1" != *[[:cntrl:]]* && "$1" != *'|'* ]] || return 1
  f="${1##*/}"
  f="${f%%\?*}"
  f="${f%%#*}"
  [[ -n "$f" ]]
}

# Optional POSIX ERE applied to the generic source body; the regex must match
# exactly the version text (first match wins). grep exit 2 = invalid regex.
valid_version_rule() {
  local st=0
  [[ -z "$1" ]] && return 0
  [[ "$1" != *[[:cntrl:]]* ]] || return 1
  printf '' | grep -Eq "$1" 2>/dev/null || st=$?
  [[ $st -ne 2 ]]
}

# HTTPS-only fetch for every request (GitHub API, release assets, checksum
# probes, generic version/download URLs). GITHUB_TOKEN — or GH_TOKEN when
# GITHUB_TOKEN is unset (matches gh's env) — goes to GitHub hosts only —
# never to other hosts.
http_curl() {
  local url="$1"
  shift
  case "$url" in
    https://*) ;;
    *) echo 'untapped: refusing non-HTTPS download URL' >&2; return 1 ;;
  esac
  case "$url" in
    https://api.github.com/*|https://github.com/*)
      local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
      if [[ -n "$token" ]]; then
        curl -fsSL --proto '=https' --proto-redir '=https' -H "Authorization: Bearer $token" "$@" "$url"
        return
      fi
      ;;
  esac
  curl -fsSL --proto '=https' --proto-redir '=https' "$@" "$url"
}

# Retry wrapper for transient failures (network drops, 5xx, rate limits).
# UNTAPPED_RETRIES = attempts after the first (default 2; 0 = no retries).
# Linear backoff: 1s, 2s, ... Not used for checksum probes — a missing
# checksums file is the common case and must stay a cheap single miss.
http_curl_retry() {
  local retries=2 n=1
  if [[ -n "${UNTAPPED_RETRIES:-}" && "${UNTAPPED_RETRIES}" =~ ^[0-9]+$ ]]; then
    retries="${UNTAPPED_RETRIES}"
  fi
  while true; do
    if http_curl "$@"; then
      return 0
    fi
    if (( n > retries )); then
      return 1
    fi
    sleep "$n"
    n=$((n + 1))
  done
}

list_archive() {
  case "$1" in
    *.tar.gz|*.tgz) tar -tzf "$1" ;;
    *.tar.bz2|*.tbz) tar -tjf "$1" ;;
    *.tar.xz|*.txz) tar -tJf "$1" ;;
    *.tar) tar -tf "$1" ;;
    *.zip) unzip -Z1 "$1" ;;
    *) basename "$1" ;;
  esac
}

validate_listing() {
  local member
  while IFS= read -r member; do
    safe_relative_path "$member" || return 1
  done <<< "$1"
}

# Resolve links only inside the private extraction directory. Relative links
# within app bundles are allowed; escaping links and special files are not.
validate_extraction() {
  local root link target parent resolved
  root=$(cd "$1" && pwd -P) || return 1
  while IFS= read -r -d '' link; do
    target=$(readlink "$link") || return 1
    [[ "$target" != /* ]] || return 1
    parent=${link%/*}
    if [[ -d "$parent/$target" ]]; then
      resolved=$(cd -P "$parent/$target" && pwd) || return 1
    else
      resolved=$(cd -P "$parent" && cd -P "$(dirname "$target")" && pwd) || return 1
    fi
    case "$resolved/" in "$root/"*) ;; *) return 1 ;; esac
  done < <(find "$root" -type l -print0)
  [[ -z "$(find "$root" ! -type f ! -type d ! -type l -print)" ]]
}
