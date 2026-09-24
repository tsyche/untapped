#!/usr/bin/env bash
# add — resolve a GitHub repo URL to a conf line and append it.
# Downloads the candidate asset only to sniff the binary path inside.
#
# Usage:
#   add.sh <github-url|owner/repo>
#   add.sh -c PATH [--yes] [--dry-run] [--asset NAME] [--name NAME] <url>
set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$LIB_DIR/.." && pwd)"
DEFAULT_USER_CONF="$HOME/.config/untapped/conf"

usage() {
  cat <<'EOF'
untapped add — inspect a GitHub release and append a conf line

Usage:
  untapped add <github-url|owner/repo>
  untapped add https://github.com/owner/repo

Options:
  -c, --config PATH        conf file to append (default: ~/.config/untapped/conf)
  -y, --yes                write without prompting
  -n, --dry-run            print the conf line; write nothing
      --asset NAME         pick this release asset by filename
      --name NAME          package/binary name (default: repo name)

Environment:
  GITHUB_TOKEN             optional; raises API rate limits
EOF
}

CONF="$DEFAULT_USER_CONF"
YES=false
DRY_RUN=false
ASSET_OVERRIDE=""
NAME_OVERRIDE=""
INPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      if [[ $# -lt 2 ]]; then
        echo "untapped add: -c requires a path" >&2
        exit 1
      fi
      CONF="$2"
      shift 2
      ;;
    --yes|-y) YES=true; shift ;;
    --dry-run|-n) DRY_RUN=true; shift ;;
    --asset)
      if [[ $# -lt 2 ]]; then
        echo "untapped add: --asset requires a name" >&2
        exit 1
      fi
      ASSET_OVERRIDE="$2"
      shift 2
      ;;
    --name)
      if [[ $# -lt 2 ]]; then
        echo "untapped add: --name requires a value" >&2
        exit 1
      fi
      NAME_OVERRIDE="$2"
      shift 2
      ;;
    help|--help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "untapped add: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$INPUT" ]]; then
        echo "untapped add: unexpected argument: $1" >&2
        exit 1
      fi
      INPUT="$1"
      shift
      ;;
  esac
done

if [[ -z "$INPUT" ]]; then
  usage >&2
  exit 1
fi

github_curl() {
  local url="$1"
  shift
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "$@" "$url"
  else
    curl -fsSL "$@" "$url"
  fi
}

# Accepts full GitHub URL or bare owner/repo.
parse_repo() {
  local u="$1"
  u="${u#https://}"
  u="${u#http://}"
  u="${u#github.com/}"
  u="${u#www.github.com/}"
  u="${u%%/releases*}"
  u="${u%%/tag/*}"
  u="${u%/}"
  if [[ "$u" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    printf '%s\n' "$u"
    return 0
  fi
  return 1
}

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux)  OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "untapped add: unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
  *)
    echo "untapped add: unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64)        ARCH="amd64" ;;
  *)
    echo "untapped add: unsupported arch: $(uname -m)" >&2
    exit 1
    ;;
esac

if ! REPO="$(parse_repo "$INPUT")"; then
  echo "untapped add: not a GitHub repo URL or owner/repo: $INPUT" >&2
  echo "Expected: https://github.com/owner/repo  (or owner/repo)" >&2
  exit 1
fi

release_json="$(github_curl "https://api.github.com/repos/$REPO/releases/latest")" || {
  echo "untapped add: could not fetch latest release for $REPO" >&2
  exit 1
}

TAG="$(printf '%s' "$release_json" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"//')"
VERSION="${TAG#v}"

ASSETS=()
while IFS= read -r u; do
  [[ -n "$u" ]] && ASSETS+=("$u")
done < <(printf '%s' "$release_json" \
  | grep -o '"browser_download_url": *"[^"]*"' \
  | sed 's/.*"browser_download_url": *"//;s/"$//')

if [[ ${#ASSETS[@]} -eq 0 ]]; then
  echo "untapped add: $REPO has no release assets (tag: ${TAG:-?})" >&2
  exit 1
fi

asset_name_from_url() {
  printf '%s\n' "${1##*/}"
}

os_of_name() {
  local n="$1"
  case "$n" in
    *darwin*|*macos*|*osx*|*apple*) echo darwin ;;
    *linux*) echo linux ;;
    *) echo "" ;;
  esac
}

arch_of_name() {
  local n="$1"
  case "$n" in
    *arm64*|*aarch64*) echo arm64 ;;
    *amd64*|*x86_64*) echo amd64 ;;
    *) echo "" ;;
  esac
}

is_candidate() {
  local n="$1"
  case "$n" in
    *.deb|*.rpm|*.msi|*.exe|*.dmg|*.pkg|*.asc|*.sig|*.pem|*.sbom|*.spdx*)
      return 1 ;;
    *checksums*|*sha256*|*SHA256*|*SHA512*|*md5sum*|*LICENSE*|*license*)
      return 1 ;;
    *.txt|*.json|*.yml|*.yaml|*.md)
      return 1 ;;
  esac
  return 0
}

# Prints score; exits 1 when unusable for this host.
score_asset() {
  local name="$1"
  local score=0
  local aos aarch repo_base

  aos="$(os_of_name "$name")"
  aarch="$(arch_of_name "$name")"

  if [[ -n "$aos" && "$aos" != "$OS" ]]; then
    return 1
  fi
  if [[ -n "$aarch" && "$aarch" != "$ARCH" ]]; then
    return 1
  fi

  case "$name" in
    *.tar.gz|*.tgz|*.tar.bz2|*.tbz|*.tar.xz|*.txz|*.zip) score=$((score + 40)) ;;
    *.AppImage) score=$((score + 30)) ;;
    *.tar) score=$((score + 20)) ;;
    *) score=$((score + 10)) ;;
  esac

  [[ -n "$aos" && "$aos" == "$OS" ]] && score=$((score + 20))
  [[ -n "$aarch" && "$aarch" == "$ARCH" ]] && score=$((score + 20))

  repo_base="${REPO#*/}"
  if [[ "$name" == "$repo_base"* || "$name" == *"$repo_base"* ]]; then
    score=$((score + 10))
  fi

  if [[ -n "$VERSION" && "$name" == *"$VERSION"* ]]; then
    score=$((score + 5))
  fi

  printf '%s\n' "$score"
}

CHOSEN_URL=""
CHOSEN_NAME=""

if [[ -n "$ASSET_OVERRIDE" ]]; then
  for u in "${ASSETS[@]}"; do
    n="$(asset_name_from_url "$u")"
    if [[ "$n" == "$ASSET_OVERRIDE" ]]; then
      CHOSEN_URL="$u"
      CHOSEN_NAME="$n"
      break
    fi
  done
  if [[ -z "$CHOSEN_URL" ]]; then
    echo "untapped add: asset not in latest release: $ASSET_OVERRIDE" >&2
    echo "Assets:" >&2
    for u in "${ASSETS[@]}"; do
      echo "  • $(asset_name_from_url "$u")" >&2
    done
    exit 1
  fi
else
  best_score=-1
  for u in "${ASSETS[@]}"; do
    n="$(asset_name_from_url "$u")"
    is_candidate "$n" || continue
    if s="$(score_asset "$n")"; then
      if [[ "$s" -gt "$best_score" ]]; then
        best_score="$s"
        CHOSEN_URL="$u"
        CHOSEN_NAME="$n"
      fi
    fi
  done
fi

if [[ -z "$CHOSEN_URL" ]]; then
  echo "untapped add: no usable asset for $OS/$ARCH in $REPO (tag: ${TAG:-?})" >&2
  echo "Assets seen:" >&2
  for u in "${ASSETS[@]}"; do
    echo "  • $(asset_name_from_url "$u")" >&2
  done
  echo "Hint: pass --asset NAME to force one." >&2
  exit 1
fi

has_other_os=false
has_other_arch=false
for u in "${ASSETS[@]}"; do
  n="$(asset_name_from_url "$u")"
  aos="$(os_of_name "$n")"
  aarch="$(arch_of_name "$n")"
  if [[ -n "$aos" && "$aos" != "$OS" ]]; then
    has_other_os=true
  fi
  if [[ -n "$aarch" && "$aarch" != "$ARCH" ]]; then
    has_other_arch=true
  fi
done

tmpdir="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$tmpdir'" EXIT
asset_path="$tmpdir/$CHOSEN_NAME"

if ! github_curl "$CHOSEN_URL" -o "$asset_path"; then
  echo "untapped add: download failed: $CHOSEN_URL" >&2
  exit 1
fi

list_archive() {
  local file="$1"
  case "$file" in
    *.tar.gz|*.tgz)  tar -tzf "$file" 2>/dev/null || true ;;
    *.tar.bz2|*.tbz) tar -tjf "$file" 2>/dev/null || true ;;
    *.tar.xz|*.txz)  tar -tJf "$file" 2>/dev/null || true ;;
    *.tar)           tar -tf  "$file" 2>/dev/null || true ;;
    *.zip)
      if command -v unzip >/dev/null 2>&1; then
        unzip -Z1 "$file" 2>/dev/null \
          || unzip -l "$file" 2>/dev/null | awk 'NR>3 && $NF!="----" && $NF!="Name" && $NF!="--------" {print $NF}'
      fi
      ;;
    *)
      printf '%s\n' "$(basename "$file")"
      ;;
  esac
}

pick_binary() {
  local pkg="$1"
  local listing="$2"
  local line

  line="$(printf '%s\n' "$listing" | grep -E '\.app/Contents/MacOS/' | grep -E "/${pkg}(/|$)" | head -1 || true)"
  if [[ -z "$line" ]]; then
    line="$(printf '%s\n' "$listing" | grep -E '\.app/Contents/MacOS/' | head -1 || true)"
  fi
  if [[ -n "$line" ]]; then
    printf '%s\n' "$line"
    return 0
  fi

  line="$(printf '%s\n' "$listing" | awk -v p="$pkg" '
    {
      n=$0
      sub(/\/$/, "", n)
      base=n
      sub(/^.*\//, "", base)
      if (base == p || base == p ".exe" || base == p ".AppImage") { print n; exit }
    }')"
  if [[ -n "$line" ]]; then
    printf '%s\n' "$line"
    return 0
  fi

  line="$(printf '%s\n' "$listing" | awk '
    NF && $0 !~ /\/$/ {
      if ($0 !~ /\//) { c++; last=$0 }
    }
    END { if (c==1) print last }')"
  if [[ -n "$line" ]]; then
    printf '%s\n' "$line"
    return 0
  fi

  return 1
}

PKG_NAME="${REPO#*/}"
if [[ -n "$NAME_OVERRIDE" ]]; then
  PKG_NAME="$NAME_OVERRIDE"
fi

listing="$(list_archive "$asset_path")"
if [[ -z "$listing" ]]; then
  echo "untapped add: could not read archive: $CHOSEN_NAME" >&2
  exit 1
fi

if ! BINARY_IN_ARCHIVE="$(pick_binary "$PKG_NAME" "$listing")"; then
  echo "untapped add: could not find a binary inside $CHOSEN_NAME" >&2
  echo "Archive contents:" >&2
  printf '%s\n' "$listing" | sed 's/^/  • /' >&2
  echo "Hint: try --asset NAME or --name to match a file inside the archive." >&2
  exit 1
fi

pattern="$CHOSEN_NAME"
if [[ -n "$VERSION" && "$pattern" == *"$VERSION"* ]]; then
  ph='{VERSION}'
  pattern="${pattern//"$VERSION"/$ph}"
fi

os_filter=""
arch_filter=""

if $has_other_os; then
  ph_os='{OS}'
  pattern="${pattern//darwin/$ph_os}"
  pattern="${pattern//macos/$ph_os}"
  pattern="${pattern//osx/$ph_os}"
  pattern="${pattern//linux/$ph_os}"
else
  inferred_os="$(os_of_name "$CHOSEN_NAME")"
  if [[ -z "$inferred_os" ]]; then
    only_os=""
    for u in "${ASSETS[@]}"; do
      aos="$(os_of_name "$(asset_name_from_url "$u")")"
      [[ -z "$aos" ]] && continue
      if [[ -z "$only_os" ]]; then
        only_os="$aos"
      elif [[ "$only_os" != "$aos" ]]; then
        only_os=""
        break
      fi
    done
    inferred_os="$only_os"
  fi
  os_filter="$inferred_os"
fi

if $has_other_arch; then
  ph_arch='{ARCH}'
  pattern="${pattern//arm64/$ph_arch}"
  pattern="${pattern//aarch64/$ph_arch}"
  pattern="${pattern//amd64/$ph_arch}"
  pattern="${pattern//x86_64/$ph_arch}"
else
  arch_filter="$(arch_of_name "$CHOSEN_NAME")"
fi

if [[ "$pattern" == *"{ARCH}"* ]]; then
  arch_filter=""
fi
if [[ "$pattern" == *"{OS}"* ]]; then
  os_filter=""
fi

# Strip leftover arch token from pattern when pinning via filter.
if [[ -n "$arch_filter" && "$pattern" == *"$arch_filter"* && "$has_other_arch" == false ]]; then
  # Keep the literal token in the pattern — matches the exact filename.
  :
fi

if [[ -f "$CONF" ]] && grep -qE "^[[:space:]]*${PKG_NAME}[[:space:]]*\|" "$CONF"; then
  echo "untapped add: already in conf: $PKG_NAME ($CONF)" >&2
  exit 1
fi

line="$(printf '%s | %s | %s | %s | %s | %s' \
  "$PKG_NAME" "$REPO" "$pattern" "$BINARY_IN_ARCHIVE" "$os_filter" "$arch_filter")"

echo "Repo:    $REPO"
echo "Tag:     ${TAG:-latest}"
echo "Asset:   $CHOSEN_NAME"
echo "Binary:  $BINARY_IN_ARCHIVE"
echo "Conf:    $CONF"
echo ""
echo "Line:"
echo "  $line"
echo ""

if $DRY_RUN; then
  echo "[dry-run] conf not modified"
  exit 0
fi

if [[ "$CONF" == "$ROOT/conf/untapped.conf.example" ]]; then
  echo "untapped add: refusing to write the packaged example conf" >&2
  echo "Copy it to $DEFAULT_USER_CONF first, or pass -c PATH" >&2
  exit 1
fi

if ! $YES; then
  if [[ ! -t 0 ]]; then
    echo "untapped add: stdin is not a TTY; pass --yes to write non-interactively" >&2
    exit 1
  fi
  read -r -p "Append this line to conf? [Y/n] " reply
  if [[ -n "$reply" && "${reply,,}" != "y" ]]; then
    echo "aborted; conf not modified"
    exit 1
  fi
fi

mkdir -p "$(dirname "$CONF")"
if [[ -f "$CONF" && -s "$CONF" ]]; then
  if [[ -n "$(tail -c1 "$CONF")" ]]; then
    echo >> "$CONF"
  fi
fi
printf '%s\n' "$line" >> "$CONF"
echo "added $PKG_NAME → $CONF"
echo "run 'untapped' to install it"
exit 0
