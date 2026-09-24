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

validate_entry() {
  valid_name "$1" && valid_repo "$2" && valid_asset "$3" && safe_relative_path "$4" \
    && [[ "$5" == '' || "$5" == darwin || "$5" == linux ]] \
    && [[ "$6" == '' || "$6" == arm64 || "$6" == amd64 ]]
}

github_curl() {
  local url="$1"
  shift
  case "$url" in
    https://api.github.com/*|https://github.com/*) ;;
    *) echo 'untapped: refusing non-GitHub download URL' >&2; return 1 ;;
  esac
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL --proto '=https' --proto-redir '=https' -H "Authorization: Bearer $GITHUB_TOKEN" "$@" "$url"
  else
    curl -fsSL --proto '=https' --proto-redir '=https' "$@" "$url"
  fi
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
