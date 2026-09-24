#!/usr/bin/env bash
# Install or upgrade CLI binaries from GitHub releases.
# Scans a conf file for what's missing or outdated, prompts before acting
# (or use --yes). Verifies sha256 against the release's checksums file when
# one exists (best-effort — silent skip if not published).
#
# Usage:
#   install.sh                 install missing packages
#   install.sh --upgrade       check for updates, reinstall anything behind
#   install.sh --yes           non-interactive; accept all prompts
#   install.sh --dry-run       show what would change; install nothing
#   install.sh -c PATH         conf file (default: ~/.config/untapped/conf,
#                              else packaged example)
set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$LIB_DIR/.." && pwd)"
DEFAULT_USER_CONF="$HOME/.config/untapped/conf"
EXAMPLE_CONF="$ROOT/conf/untapped.conf.example"

usage() {
  cat <<'EOF'
untapped — install/upgrade CLI binaries from GitHub releases

Usage:
  untapped                 install missing packages
  untapped upgrade         check for updates, install anything behind
  untapped help            show this help

Options:
  -c, --config PATH        conf file
                           (default: ~/.config/untapped/conf, else example)
  -y, --yes                non-interactive; accept all prompts
  -n, --dry-run            show what would change; install nothing
      --upgrade            same as the upgrade subcommand

Environment:
  GITHUB_TOKEN             optional; raises API rate limits
EOF
}

UPGRADE=false
YES=false
DRY_RUN=false
CONF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    upgrade|--upgrade)
      UPGRADE=true
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
elif [[ -f "$EXAMPLE_CONF" ]]; then
  CONF="$EXAMPLE_CONF"
  echo "note: using example conf ($CONF)"
  echo "      copy it to $DEFAULT_USER_CONF to customize"
else
  echo "untapped: no conf found (looked for $DEFAULT_USER_CONF and $EXAMPLE_CONF)" >&2
  exit 1
fi

INSTALL_DIR="${UNTAPPED_BIN_DIR:-$HOME/.local/bin}"
VERSION_DIR="${UNTAPPED_SHARE_DIR:-$HOME/.local/share/untapped}"
VERSION_FILE="$VERSION_DIR/installed.conf"
mkdir -p "$INSTALL_DIR" "$VERSION_DIR"
touch "$VERSION_FILE"

github_curl() {
  local url="$1"
  shift
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "$@" "$url"
  else
    curl -fsSL "$@" "$url"
  fi
}

get_installed_version() {
  local name="$1"
  grep "^${name}=" "$VERSION_FILE" 2>/dev/null | cut -d= -f2 || echo ""
}

set_installed_version() {
  local name="$1" version="$2"
  if grep -q "^${name}=" "$VERSION_FILE" 2>/dev/null; then
    if [[ "$OS" == "darwin" ]]; then
      sed -i '' "s/^${name}=.*/${name}=${version}/" "$VERSION_FILE"
    else
      sed -i "s/^${name}=.*/${name}=${version}/" "$VERSION_FILE"
    fi
  else
    echo "${name}=${version}" >> "$VERSION_FILE"
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
      expected=$(awk -v f="$asset" '$2==f {print $1; exit}' "$workdir/checksums.txt")
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

install_binary() {
  local name="$1" repo="$2" pattern="$3" binary="$4" tag="$5" version="$6"

  local asset="${pattern//\{VERSION\}/$version}"
  asset="${asset//\{OS\}/$OS}"
  asset="${asset//\{ARCH\}/$ARCH}"
  local url="https://github.com/$repo/releases/download/${tag}/${asset}"

  local tmpdir
  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  if ! github_curl "$url" -o "$tmpdir/$asset"; then
    echo "FAILED: $name (download failed: $url)"
    return 1
  fi

  if ! verify_checksum "$name" "$repo" "$tag" "$version" "$asset" "$tmpdir/$asset" "$tmpdir"; then
    return 1
  fi

  case "$asset" in
    *.tar.gz|*.tgz)  tar -xzf "$tmpdir/$asset" -C "$tmpdir" ;;
    *.tar.bz2|*.tbz) tar -xjf "$tmpdir/$asset" -C "$tmpdir" ;;
    *.zip)           unzip -q "$tmpdir/$asset" -d "$tmpdir" ;;
    *)               cp "$tmpdir/$asset" "$tmpdir/$binary" ;;
  esac

  # macOS .app bundles: entitlement-gated tools (Virtualization/Hypervisor,
  # etc.) get SIGKILLed if you flatten the binary out — the entitlement
  # check is tied to the bundle, not the raw Mach-O. Preserve the bundle.
  if [[ "$binary" == *.app/Contents/MacOS/* ]]; then
    local bundle_name="${binary%%.app/*}.app"
    local found_bundle
    found_bundle=$(find "$tmpdir" -name "$bundle_name" -type d -not -path "*/__MACOSX/*" | head -1)
    if [[ -z "$found_bundle" ]]; then
      echo "FAILED: $name (bundle '$bundle_name' not found in archive)"
      return 1
    fi
    local bundle_root="$HOME/.local/opt/$name"
    rm -rf "$bundle_root"
    mkdir -p "$bundle_root"
    cp -R "$found_bundle" "$bundle_root/"
    ln -sfn "$bundle_root/$bundle_name/${binary#*.app/}" "$INSTALL_DIR/$name"
  else
    local found
    found=$(find "$tmpdir" -name "$binary" -not -path "*/__MACOSX/*" -type f | head -1)
    if [[ -z "$found" ]]; then
      echo "FAILED: $name (binary '$binary' not found in archive)"
      return 1
    fi
    cp "$found" "$INSTALL_DIR/$name"
  fi

  chmod +x "$INSTALL_DIR/$name"
  set_installed_version "$name" "$version"
  echo "$name $version -> $INSTALL_DIR/$name"
}

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
    read -r -p "$prompt [Y/n] " reply
    [[ -z "$reply" || "${reply,,}" == "y" ]]
  else
    read -r -p "$prompt [y/N] " reply
    [[ "${reply,,}" == "y" ]]
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
  [[ -z "$name" || "$name" == \#* ]] && continue
  name="${name// /}"
  repo="${repo// /}"
  pattern="${pattern// /}"
  binary="${binary// /}"
  os_filter="${os_filter// /}"
  arch_filter="${arch_filter// /}"

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
