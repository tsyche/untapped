#!/usr/bin/env bash
# add — resolve a GitHub repo URL or a non-GitHub version-page URL to a
# conf line and append it. Downloads the candidate asset only to sniff the
# binary path inside.
#
# Usage:
#   add.sh <github-url|owner/repo>
#   add.sh <https-version-page-url>
#   add.sh -c PATH [--yes] [--dry-run] [--asset NAME|URL] [--name NAME] <url>
set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$LIB_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
DEFAULT_USER_CONF="$HOME/.config/untapped/conf"

usage() {
  cat <<'EOF'
untapped add — resolve a package URL to a conf line and append it

Usage:
  untapped add <github-url|owner/repo>
  untapped add https://github.com/owner/repo
  untapped add <https-version-page-url>     # non-GitHub source
  untapped add <direct-download-url>        # non-GitHub, one-shot

Options:
  -c, --config PATH        conf file to append (default: ~/.config/untapped/conf)
  -y, --yes                write without prompting
  -n, --dry-run            print the conf line; write nothing
      --asset NAME         GitHub: pick this release asset by filename;
                           generic source: full https download URL
      --name NAME          package/binary name (default: repo name / derived)

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

# Accepts full GitHub URL or bare owner/repo.
parse_repo() {
  local u="$1"
  case "$u" in
    https://github.com/*|http://github.com/*|https://www.github.com/*|http://www.github.com/*)
      u="${u#*://}"; u="${u#*/}" ;;
    *://*) return 1 ;;
  esac
  u="${u%/}"
  if [[ "$u" =~ ^([^/]+/[^/]+)(/(releases|tag)(/.*)?)?$ ]]; then
    u="${BASH_REMATCH[1]}"
  else
    return 1
  fi
  if valid_repo "$u"; then
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

pick_binary() {
  local pkg="$1"
  local listing="$2"
  local line

  line="$(printf '%s\n' "$listing" | awk -v p="$pkg" '
    /\.app\/Contents\/MacOS\/[^\/]+$/ {
      if (!first) first=$0
      base=$0; sub(/^.*\//, "", base)
      if (base == p) {chosen=$0; exit}
    }
    END {if (chosen) print chosen; else if (first) print first}')"
  if [[ -n "$line" ]]; then
    printf '%s\n' "$line"
    return 0
  fi

  line="$(printf '%s\n' "$listing" | awk -v p="$pkg" '
    $0 !~ /\/$/ {
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

check_dup() {
  if [[ -f "$CONF" ]] && awk -F'|' -v n="$1" '
    {gsub(/[[:space:]]/, "", $1); if ($1 == n) found=1}
    END {exit !found}' "$CONF"; then
    echo "untapped add: already in conf: $1 ($CONF)" >&2
    exit 1
  fi
}

finish_write() {
  local line="$1"
  local reply
  if $DRY_RUN; then
    echo "[dry-run] conf not modified"
    exit 0
  fi
  if [[ "$CONF" -ef "$ROOT/conf/untapped.conf.example" ]]; then
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
    if [[ -n "$reply" && "$reply" != [yY] ]]; then
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
}

os_of_name() {
  local n="$1"
  case "$n" in
    *darwin*|*macos*|*osx*|*apple*) echo darwin ;;
    *linux*) echo linux ;;
    *windows*|*win32*|*win64*|*mingw*) echo windows ;;
    *) echo "" ;;
  esac
}

arch_of_name() {
  local n="$1"
  case "$n" in
    *arm64*|*aarch64*) echo arm64 ;;
    *amd64*|*x86_64*|*x64*) echo amd64 ;;
    *i386*|*i686*) echo x86 ;;
    *armv7*|*armhf*) echo arm ;;
    *) echo "" ;;
  esac
}

# Package name derived from a version-page URL: last path segment with a
# well-known text suffix stripped, then the host, then a sanitized host.
name_from_url() {
  local u="$1" seg
  u="${u%%\?*}"
  u="${u%%\#*}"
  u="${u%/}"
  seg="${u##*/}"
  case "$seg" in
    *.txt|*.html|*.htm|*.json|*.xml|*.csv|*.yml|*.yaml|*.md|*.php) seg="${seg%.*}" ;;
  esac
  case "$seg" in
    latest|stable|current|version|versions|releases|release|download|index)
      local parent="${u%/*}"
      parent="${parent##*/}"
      if valid_name "$parent"; then
        seg="$parent"
      fi
      ;;
  esac
  if ! valid_name "$seg"; then
    seg="${u#*://}"
    seg="${seg%%/*}"
    seg="${seg#www.}"
    seg="$(printf '%s' "$seg" | sed 's/[^A-Za-z0-9._+-]/-/g')"
  fi
  valid_name "$seg" || return 1
  printf '%s\n' "$seg"
}

# Shown whenever a conf line could not be derived automatically.
print_generic_template() {
  local url="$1" name="${2:-}" asset="${3:-}" binary="${4:-}"
  if [[ -z "$name" ]]; then
    name="$(name_from_url "$url" || true)"
  fi
  [[ -n "$name" ]] || name="tool"
  [[ -n "$asset" ]] || asset="https://example.com/path/{VERSION}/${name}-{VERSION}-{OS}-{ARCH}.tar.gz"
  [[ -n "$binary" ]] || binary="$name"
  echo "conf line (edit, then append to conf):"
  echo "  $name | $url | $asset | $binary | | | |"
}

# First dotted version in a body (the default rule install also applies).
extract_dotted_version() {
  printf '%s' "$1" | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true
}

# Sets G_PATTERN / G_OS_FILTER / G_ARCH_FILTER from the URL path — never the
# host, so a hostname that happens to contain darwin/linux/arm64 is safe.
derive_generic_pattern() {
  local asset_url="$1" version="$2" hostpart rest ph
  hostpart="${asset_url%%/*}"
  rest="${asset_url#"$hostpart"}"
  G_PATTERN=""
  G_OS_FILTER=""
  G_ARCH_FILTER=""
  ph='{VERSION}'
  if [[ -n "$version" ]]; then
    rest="${rest//"$version"/$ph}"
  fi
  ph='{OS}'
  if [[ "$rest" == *"$OS"* ]]; then
    rest="${rest//"$OS"/$ph}"
  else
    G_OS_FILTER="$(os_of_name "$rest")"
  fi
  ph='{ARCH}'
  if [[ "$rest" == *"$ARCH"* ]]; then
    rest="${rest//"$ARCH"/$ph}"
  else
    G_ARCH_FILTER="$(arch_of_name "$rest")"
  fi
  G_PATTERN="$hostpart$rest"
}

# A concrete download URL (supported archive, or a filename carrying a
# version) rather than a version page.
is_direct_asset_url() {
  local u="$1" f
  u="${u%%\?*}"
  u="${u%%\#*}"
  u="${u%/}"
  f="${u##*/}"
  case "$f" in
    *.tar.gz|*.tgz|*.tar.bz2|*.tbz|*.tar.xz|*.txz|*.tar|*.zip|*.AppImage)
      return 0 ;;
  esac
  [[ -n "$(extract_dotted_version "$f")" ]]
}

# Package name from an asset filename: drop the extension, then trailing
# version/platform tokens (terraform_1.16.4_darwin_arm64.zip → terraform).
name_from_asset_filename() {
  local stem="$1" version="$2" tok
  case "$stem" in
    *.tar.gz) stem="${stem%.tar.gz}" ;;
    *.tar.bz2) stem="${stem%.tar.bz2}" ;;
    *.tar.xz) stem="${stem%.tar.xz}" ;;
    *) stem="${stem%.*}" ;;
  esac
  while :; do
    case "$stem" in
      *[-_]*) tok="${stem##*[-_]}" ;;
      *) break ;;
    esac
    if [[ -n "$version" && ( "$tok" == "$version" || "$tok" == "v$version" ) ]] \
      || [[ "$tok" =~ ^[0-9]+(\.[0-9]+)*$ ]] \
      || [[ -n "$(os_of_name "$tok")" || -n "$(arch_of_name "$tok")" ]]; then
      case "$stem" in
        *"-$tok") stem="${stem%"-$tok"}" ;;
        *"_${tok}") stem="${stem%"_$tok"}" ;;
        *) break ;;
      esac
    else
      break
    fi
  done
  valid_name "$stem" || return 1
  printf '%s\n' "$stem"
}

# Shared tail for generic sources: derive pattern, download, sniff the
# binary, print, append. $1 source  $2 version  $3 name  $4 asset_url.
generic_from_asset() {
  local source="$1" version="$2" name="$3" asset_url="$4"
  local fname listing binary line tmpdir ph pattern os_filter arch_filter

  derive_generic_pattern "$asset_url" "$version"
  pattern="$G_PATTERN"
  os_filter="$G_OS_FILTER"
  arch_filter="$G_ARCH_FILTER"

  if [[ -n "$os_filter" && "$os_filter" != "$OS" ]]; then
    echo "untapped add: download URL looks like $os_filter, this host is $OS"
    print_generic_template "$source" "$name" "$pattern"
    exit 1
  fi
  if [[ -n "$arch_filter" && "$arch_filter" != "$ARCH" ]]; then
    echo "untapped add: download URL looks like $arch_filter, this host is $ARCH"
    print_generic_template "$source" "$name" "$pattern"
    exit 1
  fi

  fname="${asset_url%%\?*}"
  fname="${fname%%\#*}"
  fname="${fname##*/}"
  if ! valid_asset "$fname"; then
    echo "untapped add: invalid asset filename: $fname" >&2
    exit 1
  fi

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  if ! http_curl "$asset_url" -o "$tmpdir/$fname"; then
    echo "untapped add: download failed: $asset_url"
    print_generic_template "$source" "$name" "$pattern"
    exit 1
  fi

  if ! listing="$(list_archive "$tmpdir/$fname")" || ! validate_listing "$listing"; then
    echo 'untapped add: unsafe archive or unreadable asset' >&2
    exit 1
  fi
  if [[ -z "$listing" ]]; then
    echo "untapped add: could not read archive: $fname" >&2
    exit 1
  fi
  if ! binary="$(pick_binary "$name" "$listing")"; then
    echo "untapped add: could not find a binary inside $fname" >&2
    echo "Archive contents:" >&2
    printf '%s\n' "$listing" | sed 's/^/  • /' >&2
    echo "Hint: pass --name to match a file inside the archive." >&2
    exit 1
  fi
  if [[ -n "$version" ]]; then
    ph='{VERSION}'
    binary="${binary//"$version"/$ph}"
  fi

  if ! validate_entry "$name" "$source" "$pattern" "$binary" "$os_filter" "$arch_filter" '' ''; then
    echo 'untapped add: invalid generated conf entry' >&2
    exit 1
  fi
  check_dup "$name"

  line="$(printf '%s | %s | %s | %s | %s | %s | |' \
    "$name" "$source" "$pattern" "$binary" "$os_filter" "$arch_filter")"

  echo "Source:  $source"
  echo "Version: $version"
  echo "Name:    $name"
  echo "Asset:   $fname"
  echo "Binary:  $binary"
  echo "Conf:    $CONF"
  echo ""
  echo "Line:"
  echo "  $line"
  echo ""
  PKG_NAME="$name"
  finish_write "$line"
}

# Version-page flow: probe the page, ask for one concrete download URL
# (or take --asset), then append via generic_from_asset.
add_generic() {
  local url="$1" body version asset_url name

  if [[ -n "$NAME_OVERRIDE" ]] && ! valid_name "$NAME_OVERRIDE"; then
    echo "untapped add: invalid package name: $NAME_OVERRIDE" >&2
    exit 1
  fi
  if ! body="$(http_curl "$url")"; then
    echo "untapped add: could not fetch version page: $url"
    print_generic_template "$url"
    exit 1
  fi
  version="$(extract_dotted_version "$body")"
  if [[ -z "$version" ]]; then
    echo "untapped add: no dotted version found at $url"
    print_generic_template "$url"
    exit 1
  fi

  name="$NAME_OVERRIDE"
  if [[ -z "$name" ]]; then
    name="$(name_from_url "$url" || true)"
  fi
  if [[ -z "$name" ]]; then
    echo "untapped add: could not derive a package name from $url; pass --name" >&2
    exit 1
  fi

  asset_url="$ASSET_OVERRIDE"
  if [[ -z "$asset_url" ]]; then
    if [[ ! -t 0 ]]; then
      echo "untapped add: stdin is not a TTY; pass --asset with a full download URL"
      print_generic_template "$url" "$name"
      exit 1
    fi
    printf 'Download URL for this release (%s): ' "$version"
    if ! read -r asset_url; then
      echo ""
      echo "aborted; conf not modified"
      exit 1
    fi
  fi
  if [[ -z "$asset_url" ]]; then
    echo "aborted; conf not modified"
    exit 1
  fi
  if [[ "$asset_url" != https://* ]]; then
    echo "untapped add: refusing non-HTTPS download URL: $asset_url"
    print_generic_template "$url" "$name"
    exit 1
  fi

  generic_from_asset "$url" "$version" "$name" "$asset_url"
}

# One-shot flow: the input IS the download URL. The version comes from the
# URL; the version source is the parent directory with the version segment
# removed (…/terraform/1.16.4/x.zip → …/terraform). Falls back to a prompt
# or a template when that page isn't usable.
add_generic_one_shot() {
  local asset_url="$1" version="" name="" fname dir cand body v page="" source_page=""

  if [[ -n "$ASSET_OVERRIDE" ]]; then
    echo "untapped add: --asset is for version-page inputs; this URL already names the download" >&2
    exit 1
  fi

  fname="${asset_url%%\?*}"
  fname="${fname%%\#*}"
  fname="${fname##*/}"
  if ! valid_asset "$fname"; then
    echo "untapped add: invalid asset filename: $fname" >&2
    exit 1
  fi

  version="$(extract_dotted_version "$asset_url")"

  name="$NAME_OVERRIDE"
  if [[ -z "$name" ]]; then
    name="$(name_from_asset_filename "$fname" "$version" || true)"
  fi
  if [[ -z "$name" ]]; then
    name="$(name_from_url "$asset_url" || true)"
  fi
  if [[ -z "$name" ]]; then
    echo "untapped add: could not derive a package name from $fname; pass --name" >&2
    exit 1
  fi

  derive_generic_pattern "$asset_url" "$version"
  if [[ -n "$G_OS_FILTER" && "$G_OS_FILTER" != "$OS" ]]; then
    echo "untapped add: download URL looks like $G_OS_FILTER, this host is $OS"
    print_generic_template "(version-page URL)" "$name" "$G_PATTERN"
    exit 1
  fi
  if [[ -n "$G_ARCH_FILTER" && "$G_ARCH_FILTER" != "$ARCH" ]]; then
    echo "untapped add: download URL looks like $G_ARCH_FILTER, this host is $ARCH"
    print_generic_template "(version-page URL)" "$name" "$G_PATTERN"
    exit 1
  fi

  dir="${asset_url%/*}"
  cand=""
  if [[ -n "$version" ]]; then
    case "${dir##*/}" in
      "$version"|"v$version") cand="${dir%/*}" ;;
    esac
  fi
  [[ -n "$cand" ]] || cand="$dir"

  if body="$(http_curl "$cand" 2>/dev/null)"; then
    v="$(extract_dotted_version "$body")"
    if [[ -n "$v" ]]; then
      source_page="$cand"
    fi
  fi
    if [[ -z "${source_page}" ]]; then
    if [[ ! -t 0 ]]; then
      echo "untapped add: could not discover a version source for $fname"
      derive_generic_pattern "$asset_url" "$version"
      print_generic_template "(version-page URL)" "$name" "$G_PATTERN"
      exit 1
    fi
    printf 'Version page URL (Enter to skip): '
    if ! read -r page; then
      echo ""
      echo "aborted; conf not modified"
      exit 1
    fi
    if [[ -z "$page" ]]; then
      derive_generic_pattern "$asset_url" "$version"
      print_generic_template "(version-page URL)" "$name" "$G_PATTERN"
      exit 1
    fi
    if ! body="$(http_curl "$page")"; then
      echo "untapped add: could not fetch version page: $page"
      derive_generic_pattern "$asset_url" "$version"
      print_generic_template "$page" "$name" "$G_PATTERN"
      exit 1
    fi
    v="$(extract_dotted_version "$body")"
    if [[ -z "$v" ]]; then
      echo "untapped add: no dotted version found at $page"
      derive_generic_pattern "$asset_url" "$version"
      print_generic_template "$page" "$name" "$G_PATTERN"
      exit 1
    fi
    source_page="$page"
  fi

  generic_from_asset "$source_page" "$version" "$name" "$asset_url"
}

# A scheme URL that is not on github.com goes through the generic flow:
# direct download URLs one-shot, version pages via the interactive probe.
if [[ "$INPUT" == *://* && "$INPUT" != *github.com/* ]]; then
  if is_direct_asset_url "$INPUT"; then
    add_generic_one_shot "$INPUT"
  fi
  add_generic "$INPUT"
fi

if ! REPO="$(parse_repo "$INPUT")"; then
  echo "untapped add: not a GitHub repo URL or owner/repo: $INPUT" >&2
  echo "Expected: https://github.com/owner/repo  (or owner/repo)" >&2
  echo "Missing scheme? Pass a full https:// URL so add can try the generic flow" >&2
  exit 1
fi

PKG_NAME="${NAME_OVERRIDE:-${REPO#*/}}"
if ! valid_name "$PKG_NAME"; then
  echo "untapped add: invalid package name: $PKG_NAME" >&2
  exit 1
fi

release_json="$(http_curl "https://api.github.com/repos/$REPO/releases/latest")" || {
  echo "untapped add: could not fetch latest release for $REPO" >&2
  exit 1
}

TAG="$(printf '%s' "$release_json" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"//' || true)"
if [[ -z "$TAG" ]]; then
  echo "untapped add: could not read release tag for $REPO" >&2
  exit 1
fi
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
trap 'rm -rf "$tmpdir"' EXIT
valid_asset "$CHOSEN_NAME" || { echo 'untapped add: invalid asset filename' >&2; exit 1; }
asset_path="$tmpdir/$CHOSEN_NAME"

# Asset URLs come from API metadata: keep add downloads on GitHub even though
# the shared fetch allows generic https hosts for conf-driven sources.
case "$CHOSEN_URL" in
  https://github.com/*) ;;
  *) echo 'untapped add: refusing non-GitHub asset URL' >&2; exit 1 ;;
esac

if ! http_curl "$CHOSEN_URL" -o "$asset_path"; then
  echo "untapped add: download failed: $CHOSEN_URL" >&2
  exit 1
fi

if ! listing="$(list_archive "$asset_path")" || ! validate_listing "$listing"; then
  echo "untapped add: unsafe archive or unreadable asset" >&2
  exit 1
fi
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
if [[ -n "$VERSION" ]]; then
  ph='{VERSION}'
  pattern="${pattern//"$VERSION"/$ph}"
  BINARY_IN_ARCHIVE="${BINARY_IN_ARCHIVE//"$VERSION"/$ph}"
fi

os_filter="$(os_of_name "$CHOSEN_NAME")"
arch_filter="$(arch_of_name "$CHOSEN_NAME")"
# Only substitute spellings the installer actually emits. Alias spellings
# remain literal and host-filtered (macos/aarch64, Rust target triples, etc.).
if $has_other_os && [[ "$CHOSEN_NAME" == *darwin* || "$CHOSEN_NAME" == *linux* ]]; then
  ph='{OS}'
  pattern="${pattern//"$OS"/$ph}"
  os_filter=""
fi
if $has_other_arch && [[ "$CHOSEN_NAME" == *"$ARCH"* ]]; then
  ph='{ARCH}'
  pattern="${pattern//"$ARCH"/$ph}"
  arch_filter=""
fi

if ! validate_entry "$PKG_NAME" "$REPO" "$pattern" "$BINARY_IN_ARCHIVE" "$os_filter" "$arch_filter"; then
  echo 'untapped add: invalid generated conf entry' >&2
  exit 1
fi
check_dup "$PKG_NAME"

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

finish_write "$line"
