#!/usr/bin/env bash
# Install or upgrade CLI binaries from GitHub releases.
# Scans a conf file for what's missing or outdated, prompts before acting
# (or use --yes). Verifies sha256 against the release's checksums file when
# one exists (best-effort — silent skip if not published).
#
# Usage:
#   install.sh                 install missing packages
#   install.sh upgrade         check for updates, reinstall anything behind
#   install.sh list            show conf entries + install status (no network)
#   install.sh --yes           non-interactive; accept all prompts
#   install.sh --dry-run       show what would change; install nothing
#   install.sh -c PATH         conf file (default: ~/.config/untapped/conf;
#                              example only when passed explicitly via -c)
set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$LIB_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
DEFAULT_USER_CONF="$HOME/.config/untapped/conf"
EXAMPLE_CONF="$ROOT/conf/untapped.conf.example"

usage() {
  cat <<'EOF'
untapped — install/upgrade CLI binaries from GitHub releases

Usage:
  untapped                 install missing packages
  untapped upgrade         check for updates, install anything behind
  untapped list            show conf entries + install status (no network)
  untapped add <url|o/r>   inspect a GH release; append a conf line
  untapped help            show this help

Options:
  -c, --config PATH        conf file
                           (default: ~/.config/untapped/conf)
  -y, --yes                non-interactive; accept all prompts
  -n, --dry-run            show what would change; install nothing
      --upgrade            same as the upgrade subcommand

Environment:
  GITHUB_TOKEN             optional; raises API rate limits
EOF
}

UPGRADE=false
LIST=false
YES=false
DRY_RUN=false
CONF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    upgrade|--upgrade)
      UPGRADE=true
      shift
      ;;
    list)
      LIST=true
      shift
      ;;
    --yes|-y)
      YES=true
      shift
      ;;
    --dry-run|-n)
      DRY_RUN=true
      shift
      ;;
    -c|--config)
      if [[ $# -lt 2 ]]; then
        echo "untapped: -c requires a path" >&2
        exit 1
      fi
      CONF="$2"
      shift 2
      ;;
    help|--help|-h)
      usage
      exit 0
      ;;
    *)
      echo "untapped: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux)  OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "untapped: unsupported OS: $(uname -s)"
    echo "Supported: macOS, Linux (incl. WSL)."
    echo "Windows (Git Bash) is planned; run from WSL for now."
    exit 1
    ;;
  *)
    echo "untapped: unsupported OS: $(uname -s)"
    echo "Supported: macOS, Linux (incl. WSL)."
    exit 1
    ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64)        ARCH="amd64" ;;
  *)
    echo "untapped: unsupported arch: $(uname -m)" >&2
    exit 1
    ;;
esac

if [[ -n "$CONF" ]]; then
  if [[ ! -f "$CONF" ]]; then
    echo "untapped: conf not found: $CONF" >&2
    exit 1
  fi
elif [[ -f "$DEFAULT_USER_CONF" ]]; then
  CONF="$DEFAULT_USER_CONF"
else
  # First run: seed an empty user conf, point at `untapped add`, exit.
  # Never auto-install from the packaged example.
  mkdir -p "$(dirname "$DEFAULT_USER_CONF")"
  cat > "$DEFAULT_USER_CONF" <<'EOF'
# untapped package list — one per line.
# Format: name | github_repo | asset_pattern | binary_in_archive | os_filter | arch_filter
# Add a package:  untapped add https://github.com/owner/repo
# Starter set:    cp conf/untapped.conf.example ~/.config/untapped/conf
EOF
  CONF="$DEFAULT_USER_CONF"
  echo "Created empty conf: $CONF"
  echo ""
  echo "Add packages with:"
  echo "  untapped add https://github.com/owner/repo"
  echo ""
  echo "Or seed from the example:"
  echo "  cp $EXAMPLE_CONF $DEFAULT_USER_CONF"
  echo ""
  echo "Optional — put untapped on PATH (symlink):"
  echo "  ln -s $ROOT/bin/untapped ~/.local/bin/untapped"
  echo ""
  echo "Then run:  untapped --yes"
  exit 0
fi

# Friendly hint when conf has no package lines (comments/blank only).
if ! $LIST && ! grep -qve '^[[:space:]]*#' -e '^[[:space:]]*$' "$CONF"; then
  echo "No packages configured yet."
  echo "  untapped add https://github.com/owner/repo"
  echo ""
fi

INSTALL_DIR="${UNTAPPED_BIN_DIR:-$HOME/.local/bin}"
VERSION_DIR="${UNTAPPED_SHARE_DIR:-$HOME/.local/share/untapped}"
VERSION_FILE="$VERSION_DIR/installed.conf"
mkdir -p "$INSTALL_DIR" "$VERSION_DIR"

# One-time migrate from the old ghr state file so upgrades don't show
# every package as "unknown" after switching tools.
LEGACY_VERSION_FILE="$HOME/.local/share/gh-releases/installed.conf"
if [[ ! -s "$VERSION_FILE" && -f "$LEGACY_VERSION_FILE" ]]; then
  cp "$LEGACY_VERSION_FILE" "$VERSION_FILE"
  echo "note: imported installed versions from legacy ghr state"
fi
touch "$VERSION_FILE"

get_installed_version() {
  local name="$1"
  awk -F= -v n="$name" '$1 == n {sub(/^[^=]*=/, ""); print; exit}' "$VERSION_FILE"
}

# --- list: local inventory only (conf + PATH + version state; no network) ---
if $LIST; then
  printf '%-24s %s\n' "PACKAGE" "STATUS"
  while IFS='|' read -r name repo pattern binary os_filter arch_filter || [[ -n "$name" ]]; do
    name="${name//[[:space:]]/}"
    [[ -z "$name" || "$name" == \#* ]] && continue
    valid_name "$name" || { echo "untapped: invalid package name: $name" >&2; exit 1; }
    os_filter="${os_filter// /}"
    arch_filter="${arch_filter// /}"

    if [[ -n "$os_filter" && "$os_filter" != "$OS" ]]; then
      status="not available on $OS"
    elif [[ -n "$arch_filter" && "$arch_filter" != "$ARCH" ]]; then
      status="not available on $ARCH"
    elif command -v "$name" &>/dev/null; then
      ver="$(get_installed_version "$name")"
      status="installed${ver:+ ($ver)}"
    else
      status="not on PATH"
    fi
    printf '%-24s %s\n' "$name" "$status"
  done < "$CONF"
  exit 0
fi

set_installed_version() {
  local name="$1" version="$2"
  local state_tmp
  state_tmp=$(mktemp "$VERSION_DIR/.installed.XXXXXX") || return 1
  if ! awk -F= -v n="$name" '$1 != n' "$VERSION_FILE" > "$state_tmp" \
    || ! printf '%s=%s\n' "$name" "$version" >> "$state_tmp" \
    || ! mv -f "$state_tmp" "$VERSION_FILE"; then
    rm -f "$state_tmp"
    return 1
  fi
}

fetch_latest_tag() {
  local repo="$1"
  github_curl "https://api.github.com/repos/$repo/releases/latest" \
    | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' || true
}

sha256_of() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    return 1
  fi
}

# Best-effort sha256 verification — common checksums-file naming conventions.
# Miss = silent skip, not a failure.
verify_checksum() {
  local name="$1" repo="$2" tag="$3" version="$4" asset="$5" filepath="$6" workdir="$7"

  local candidates=(
    "${name}_${version}_checksums.txt"
    "checksums.txt"
    "SHA256SUMS"
    "sha256sum.txt"
  )
  local cand expected=""
  for cand in "${candidates[@]}"; do
    if github_curl "https://github.com/$repo/releases/download/${tag}/${cand}" -o "$workdir/checksums.txt" 2>/dev/null; then
      expected=$(awk -v f="$asset" '{n=$2; sub(/^\*/, "", n); if(n==f) {print $1; exit}}' "$workdir/checksums.txt")
      [[ -n "$expected" ]] && break
    fi
  done

  if [[ -z "$expected" ]]; then
    echo "  (no checksums file found for $name — skipping verification)"
    return 0
  fi

  local actual
  if ! actual=$(sha256_of "$filepath"); then
    echo "  (no sha256 tool available — skipping verification for $name)"
    return 0
  fi
  if [[ "$expected" != "$actual" ]]; then
    echo "FAILED: $name (checksum mismatch — expected $expected, got $actual)"
    return 1
  fi
  echo "  checksum verified for $name"
}

install_binary() (
  # A subshell gives each package its own cleanup trap. Every fallible operation
  # is checked explicitly: callers use this function in an `if`, disabling -e.
  local name="$1" repo="$2" pattern="$3" binary="$4" tag="$5" version="$6"
  local asset="${pattern//\{VERSION\}/$version}"
  asset="${asset//\{OS\}/$OS}"
  asset="${asset//\{ARCH\}/$ARCH}"
  binary="${binary//\{VERSION\}/$version}"
  if ! valid_asset "$asset" || ! safe_relative_path "$binary"; then
    echo "FAILED: $name (invalid asset or binary path)"
    return 1
  fi
  local url="https://github.com/$repo/releases/download/${tag}/${asset}"
  local tmpdir staged="" listing found bundle_name found_bundle bundle_root backup=""
  tmpdir=$(mktemp -d) || return 1
  tmpdir=$(cd "$tmpdir" && pwd -P) || return 1
  trap 'rm -rf "$tmpdir"; if [[ -n "$staged" ]]; then rm -f "$staged"; fi' EXIT
  if ! github_curl "$url" -o "$tmpdir/$asset"; then
    echo "FAILED: $name (download failed: $url)"
    return 1
  fi
  verify_checksum "$name" "$repo" "$tag" "$version" "$asset" "$tmpdir/$asset" "$tmpdir" || return 1
  mkdir "$tmpdir/unpacked" || return 1
  if ! listing=$(list_archive "$tmpdir/$asset") || ! validate_listing "$listing"; then
    echo "FAILED: $name (unsafe archive or unreadable asset)"
    return 1
  fi
  case "$asset" in
    *.tar.gz|*.tgz) tar -xzf "$tmpdir/$asset" -C "$tmpdir/unpacked" || return 1 ;;
    *.tar.bz2|*.tbz) tar -xjf "$tmpdir/$asset" -C "$tmpdir/unpacked" || return 1 ;;
    *.tar.xz|*.txz) tar -xJf "$tmpdir/$asset" -C "$tmpdir/unpacked" || return 1 ;;
    *.tar) tar -xf "$tmpdir/$asset" -C "$tmpdir/unpacked" || return 1 ;;
    *.zip) unzip -q "$tmpdir/$asset" -d "$tmpdir/unpacked" || return 1 ;;
    *)
      mkdir -p "$tmpdir/unpacked/$(dirname "$binary")" || return 1
      cp "$tmpdir/$asset" "$tmpdir/unpacked/$binary" || return 1 ;;
  esac
  if ! validate_extraction "$tmpdir/unpacked"; then
    echo "FAILED: $name (unsafe archive links or special files)"
    return 1
  fi
  if [[ "$binary" == */* ]]; then
    found="$tmpdir/unpacked/$binary"
  else
    found=$(find "$tmpdir/unpacked" -name "$binary" -not -path '*/__MACOSX/*' -type f | head -1)
  fi
  if [[ ! -f "$found" || -L "$found" ]]; then
    echo "FAILED: $name (binary '$binary' not found in archive)"
    return 1
  fi
  if [[ -d "$INSTALL_DIR/$name" ]]; then
    echo "FAILED: $name (destination is a directory)"
    return 1
  fi
  staged=$(mktemp "$INSTALL_DIR/.untapped.XXXXXX") || return 1
  if [[ "$binary" == *.app/Contents/MacOS/* ]]; then
    found_bundle="${found%%.app/*}.app"
    bundle_name="${found_bundle##*/}"
    bundle_root="$HOME/.local/opt/$name"
    mkdir -p "$HOME/.local/opt" || return 1
    local new_bundle
    new_bundle=$(mktemp -d "$HOME/.local/opt/.untapped.XXXXXX") || return 1
    if ! cp -R "$found_bundle" "$new_bundle/" \
      || ! validate_extraction "$new_bundle" \
      || ! chmod +x "$new_bundle/$bundle_name/${binary#*.app/}" \
      || ! rm -f "$staged" \
      || ! ln -s "$bundle_root/$bundle_name/${binary#*.app/}" "$staged"; then
      rm -rf "$new_bundle"
      return 1
    fi
    if [[ -e "$bundle_root" || -L "$bundle_root" ]]; then
      backup=$(mktemp -d "$HOME/.local/opt/.backup.XXXXXX") || { rm -rf "$new_bundle"; return 1; }
      if ! mv "$bundle_root" "$backup/bundle"; then
        rm -rf "$new_bundle" "$backup"
        return 1
      fi
    fi
    if ! mv "$new_bundle" "$bundle_root"; then
      [[ -z "$backup" ]] || mv "$backup/bundle" "$bundle_root"
      rm -rf "$new_bundle"
      return 1
    fi
  else
    cp "$found" "$staged" && chmod +x "$staged" || return 1
  fi
  if ! mv -f "$staged" "$INSTALL_DIR/$name"; then
    if [[ "$binary" == *.app/Contents/MacOS/* ]]; then
      rm -rf "$bundle_root"
      [[ -z "$backup" ]] || mv "$backup/bundle" "$bundle_root"
    fi
    return 1
  fi
  [[ -z "$backup" ]] || rm -rf "$backup"
  staged=""
  set_installed_version "$name" "$version" || return 1
  echo "$name $version -> $INSTALL_DIR/$name"
)

prompt_yes() {
  # default_yes: "Y/n" vs "y/N"
  local prompt="$1" default_yes="$2" reply=""
  if $YES || $DRY_RUN; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "untapped: stdin is not a TTY; pass --yes to proceed non-interactively" >&2
    exit 1
  fi
  if $default_yes; then
    read -r -p "$prompt [Y/n] " reply || return 1
    [[ -z "$reply" || "$reply" == [yY] ]]
  else
    read -r -p "$prompt [y/N] " reply || return 1
    [[ "$reply" == [yY] ]]
  fi
}

# --- Collect work ---
to_install=()
to_install_names=()
to_upgrade=()
to_upgrade_display=()
skipped=()
failed=()
installed_count=0
updated_count=0
would_install=()
would_upgrade=()

while IFS='|' read -r name repo pattern binary os_filter arch_filter || [[ -n "$name" ]]; do
  name="${name//[[:space:]]/}"
  [[ -z "$name" || "$name" == \#* ]] && continue
  repo="${repo// /}"
  pattern="${pattern// /}"
  binary="${binary// /}"
  os_filter="${os_filter// /}"
  arch_filter="${arch_filter// /}"

  if ! validate_entry "$name" "$repo" "$pattern" "$binary" "$os_filter" "$arch_filter"; then
    failed+=("$name|invalid conf entry")
    continue
  fi

  if [[ -n "$os_filter" && "$os_filter" != "$OS" ]]; then
    skipped+=("$name|not available on $OS")
    continue
  fi
  if [[ -n "$arch_filter" && "$arch_filter" != "$ARCH" ]]; then
    skipped+=("$name|not available on $ARCH")
    continue
  fi

  if $UPGRADE; then
    if ! command -v "$name" &>/dev/null; then
      to_install+=("$name|$repo|$pattern|$binary")
      to_install_names+=("$name")
    else
      local_tag=$(fetch_latest_tag "$repo")
      latest="${local_tag#v}"
      installed=$(get_installed_version "$name")
      if [[ -z "$local_tag" ]]; then
        failed+=("$name|could not fetch latest release tag")
      elif [[ -z "$installed" || "$installed" != "$latest" ]]; then
        to_upgrade+=("$name|$repo|$pattern|$binary|$local_tag|$latest")
        to_upgrade_display+=("$name: ${installed:-unknown} → $latest")
      else
        echo "current $name ($installed)"
      fi
    fi
  else
    if ! command -v "$name" &>/dev/null; then
      to_install+=("$name|$repo|$pattern|$binary")
      to_install_names+=("$name")
    else
      echo "skip $name (already installed: $(command -v "$name"))"
      skipped+=("$name|already installed")
    fi
  fi
done < "$CONF"

# --- Install missing ---
if [[ ${#to_install[@]} -gt 0 ]]; then
  echo ""
  echo "The following utilities are not installed:"
  for n in "${to_install_names[@]}"; do echo "  • $n"; done
  echo ""
  if $DRY_RUN; then
    would_install=("${to_install_names[@]}")
  elif prompt_yes "Install them now?" true; then
    for entry in "${to_install[@]}"; do
      IFS='|' read -r name repo pattern binary <<< "$entry"
      echo "installing $name..."
      tag=$(fetch_latest_tag "$repo")
      version="${tag#v}"
      if [[ -z "$tag" ]]; then
        failed+=("$name|could not fetch latest release tag")
        continue
      fi
      if install_binary "$name" "$repo" "$pattern" "$binary" "$tag" "$version"; then
        installed_count=$((installed_count + 1))
      else
        failed+=("$name|install failed (see above)")
      fi
    done
  elif ! $DRY_RUN; then
    for n in "${to_install_names[@]}"; do skipped+=("$n|user declined install"); done
  fi
elif ! $UPGRADE && ! $DRY_RUN; then
  echo "All configured utilities already installed."
fi

# --- Upgrade available ---
if [[ ${#to_upgrade[@]} -gt 0 ]]; then
  echo ""
  echo "Updates available:"
  for d in "${to_upgrade_display[@]}"; do echo "  • $d"; done
  echo ""
  if $DRY_RUN; then
    for d in "${to_upgrade_display[@]}"; do would_upgrade+=("$d"); done
  elif prompt_yes "Upgrade all?" true; then
    for entry in "${to_upgrade[@]}"; do
      IFS='|' read -r name repo pattern binary tag version <<< "$entry"
      echo "upgrading $name..."
      if install_binary "$name" "$repo" "$pattern" "$binary" "$tag" "$version"; then
        updated_count=$((updated_count + 1))
      else
        failed+=("$name|upgrade failed (see above)")
      fi
    done
  elif ! $DRY_RUN; then
    for d in "${to_upgrade_display[@]}"; do
      n="${d%%:*}"
      skipped+=("$n|user declined upgrade")
    done
  fi
elif $UPGRADE && [[ ${#to_install[@]} -eq 0 ]] && [[ ${#failed[@]} -eq 0 ]] && ! $DRY_RUN; then
  echo "All installed utilities are current."
fi

# --- Summary ---
echo ""
if $DRY_RUN; then
  echo "[dry-run] Installed: 0  Updated: 0  Skipped: ${#skipped[@]}  Failed: ${#failed[@]}"
  if [[ ${#would_install[@]} -gt 0 ]]; then
    echo ""
    echo "Would install:"
    for n in "${would_install[@]}"; do echo "  • $n"; done
  fi
  if [[ ${#would_upgrade[@]} -gt 0 ]]; then
    echo ""
    echo "Would update:"
    for d in "${would_upgrade[@]}"; do echo "  • $d"; done
  fi
else
  echo "Installed: $installed_count  Updated: $updated_count  Skipped: ${#skipped[@]}  Failed: ${#failed[@]}"
fi

if [[ ${#skipped[@]} -gt 0 ]]; then
  echo ""
  echo "Skipped:"
  for s in "${skipped[@]}"; do
    n="${s%%|*}"
    r="${s#*|}"
    echo "  • $n — $r"
  done
fi

if [[ ${#failed[@]} -gt 0 ]]; then
  echo ""
  echo "Failed:"
  for s in "${failed[@]}"; do
    n="${s%%|*}"
    r="${s#*|}"
    echo "  • $n — $r"
  done
  exit 1
fi

exit 0
