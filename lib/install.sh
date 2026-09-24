#!/usr/bin/env bash
# Install or upgrade CLI binaries from GitHub releases or generic HTTPS hosts.
# Scans a conf file for what's missing or outdated, prompts before acting
# (or use --yes). Verifies sha256 against the release's checksums file when
# one exists (best-effort — silent skip if not published; GitHub entries
# only — generic sources have no checksum convention).
# Downloads run in parallel (-j, default 4) with bounded retries for
# transient failures (--retries, default 2).
#
# Usage:
#   install.sh                 install missing packages
#   install.sh upgrade         check for updates, reinstall anything behind
#   install.sh list            show conf entries + install status (no network)
#   install.sh doctor          print conf/paths/counts (no network)
#   install.sh outdated        list installed vs latest (no install)
#   remove.sh <name>...        drop conf line + uninstall (see lib/remove.sh)
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
untapped — install/upgrade CLI binaries from release hosts (GitHub or plain HTTPS)

Usage:
  untapped                 install missing packages
  untapped upgrade         check for updates, install anything behind
  untapped list            show conf entries + install status (no network)
  untapped doctor          print conf/paths/counts (no network)
  untapped outdated        list installed vs latest (no install)
  untapped add <url|o/r>   inspect a GH release; append a conf line
  untapped remove <name>... drop conf line + uninstall binary/state
  untapped help            show this help

Options:
  -c, --config PATH        conf file
                           (default: ~/.config/untapped/conf)
  -y, --yes                non-interactive; accept all prompts
  -n, --dry-run            show what would change; install nothing
  -j, --jobs N             parallel install jobs (default: 4; 1 = serial)
      --retries N          retries for transient download/API failures
                           (default: 2; 0 = off)
      --upgrade            same as the upgrade subcommand

Environment:
  GITHUB_TOKEN             optional; raises API rate limits
  UNTAPPED_JOBS            default for -j
  UNTAPPED_RETRIES         default for --retries
EOF
}

UPGRADE=false
LIST=false
DOCTOR=false
OUTDATED=false
YES=false
DRY_RUN=false
CONF=""
JOBS_ARG=""
RETRIES_ARG=""

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
    doctor)
      DOCTOR=true
      shift
      ;;
    outdated)
      OUTDATED=true
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
    -j|--jobs)
      if [[ $# -lt 2 ]]; then
        echo "untapped: -j requires a number" >&2
        exit 1
      fi
      JOBS_ARG="$2"
      shift 2
      ;;
    --retries)
      if [[ $# -lt 2 ]]; then
        echo "untapped: --retries requires a number" >&2
        exit 1
      fi
      RETRIES_ARG="$2"
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

# Flag > env > default. Export the effective retries value so background
# install jobs and http_curl_retry agree on it.
JOBS="${JOBS_ARG:-${UNTAPPED_JOBS:-4}}"
RETRIES="${RETRIES_ARG:-${UNTAPPED_RETRIES:-2}}"
if ! [[ "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "untapped: --jobs must be a positive integer: $JOBS" >&2
  exit 1
fi
if ! [[ "$RETRIES" =~ ^[0-9]+$ ]]; then
  echo "untapped: --retries must be a non-negative integer: $RETRIES" >&2
  exit 1
fi
export UNTAPPED_RETRIES="$RETRIES"

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
  # First run: no conf. Interactive: prompt to seed from example (default Y).
  # --yes takes the default. No TTY and no --yes: empty conf (script-safe).
  # Never auto-install from the packaged example.
  mkdir -p "$(dirname "$DEFAULT_USER_CONF")"
  seed_from_example=false
  if $YES; then
    seed_from_example=true
  elif [[ -t 0 ]]; then
    reply=""
    read -r -p "No conf found. Seed from packaged example? [Y/n] " reply || true
    if [[ -z "$reply" || "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]; then
      seed_from_example=true
    fi
  fi

  if $seed_from_example; then
    cp "$EXAMPLE_CONF" "$DEFAULT_USER_CONF"
    CONF="$DEFAULT_USER_CONF"
    echo "Seeded conf from example: $CONF"
    echo ""
    echo "Next:"
    echo "  Review the conf:  \$EDITOR $CONF"
    echo "  Add a package:    untapped add https://github.com/owner/repo"
    echo "  Install:          untapped --yes"
    exit 0
  fi

  cat > "$DEFAULT_USER_CONF" <<'EOF'
# untapped package list — one per line.
# Format: name | source | asset_pattern | binary_in_archive | os_filter | arch_filter | version_pin | version_rule
# source: owner/repo (GitHub) or an https URL returning the latest version.
# Add a package:  untapped add https://github.com/owner/repo
# Starter set:    cp conf/untapped.conf.example ~/.config/untapped/conf
EOF
  CONF="$DEFAULT_USER_CONF"
  echo "Created empty conf: $CONF"
  echo ""
  echo "Add packages with:"
  echo "  untapped add https://github.com/owner/repo"
  echo ""
  echo "Or seed from the example (interactive first run offers this):"
  echo "  cp $EXAMPLE_CONF $DEFAULT_USER_CONF"
  echo ""
  echo "Optional — put untapped on PATH (symlink):"
  echo "  ln -s $ROOT/bin/untapped ~/.local/bin/untapped"
  echo ""
  echo "Then run:  untapped --yes"
  exit 0
fi

# Friendly hint when conf has no package lines (comments/blank only).
if ! $LIST && ! $DOCTOR && ! grep -qve '^[[:space:]]*#' -e '^[[:space:]]*$' "$CONF"; then
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

# --- doctor: local paths + package counts (no network) ---
if $DOCTOR; then
  total=0
  installed_n=0
  missing_n=0
  filtered_n=0
  while IFS='|' read -r name source pattern binary os_filter arch_filter version_pin version_rule || [[ -n "$name" ]]; do
    name="${name//[[:space:]]/}"
    [[ -z "$name" || "$name" == \#* ]] && continue
    os_filter="${os_filter// /}"
    arch_filter="${arch_filter// /}"
    version_pin="${version_pin// /}"
    total=$((total + 1))
    if [[ -n "$os_filter" && "$os_filter" != "$OS" ]] \
      || [[ -n "$arch_filter" && "$arch_filter" != "$ARCH" ]]; then
      filtered_n=$((filtered_n + 1))
    elif command -v "$name" &>/dev/null; then
      installed_n=$((installed_n + 1))
    else
      missing_n=$((missing_n + 1))
    fi
  done < "$CONF"
  echo "conf:          $CONF"
  echo "bin dir:       $INSTALL_DIR"
  echo "share dir:     $VERSION_DIR"
  echo "version state: $VERSION_FILE"
  echo "os:            $OS"
  echo "arch:          $ARCH"
  echo "packages:      $total configured, $installed_n installed, $missing_n missing, $filtered_n filtered"
  exit 0
fi

# --- list: local inventory only (conf + PATH + version state; no network) ---
if $LIST; then
  printf '%-24s %s\n' "PACKAGE" "STATUS"
  while IFS='|' read -r name source pattern binary os_filter arch_filter version_pin version_rule || [[ -n "$name" ]]; do
    name="${name//[[:space:]]/}"
    [[ -z "$name" || "$name" == \#* ]] && continue
    valid_name "$name" || { echo "untapped: invalid package name: $name" >&2; exit 1; }
    os_filter="${os_filter// /}"
    arch_filter="${arch_filter// /}"
    version_pin="${version_pin// /}"

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

# Latest version for a conf source:
#   owner/repo  → GitHub API releases/latest tag
#   https URL   → first match of version_rule in the response body
#                 (default rule: a dotted version, e.g. 1.2.3 or v1.2.3)
fetch_latest_tag() {
  local source="$1" rule="${2:-}"
  if is_generic_source "$source"; then
    http_curl_retry "$source" 2>/dev/null \
      | LC_ALL=C grep -Eao "${rule:-[0-9]+(\.[0-9]+)+}" 2>/dev/null | head -1 || true
  else
    http_curl_retry "https://api.github.com/repos/$source/releases/latest" \
      | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' || true
  fi
}

# Failure wording depends on the source kind (tests and users key on it).
fetch_fail_reason() {
  if is_generic_source "$1"; then
    echo "could not fetch latest version"
  else
    echo "could not fetch latest release tag"
  fi
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
    if http_curl "https://github.com/$repo/releases/download/${tag}/${cand}" -o "$workdir/checksums.txt" 2>/dev/null; then
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
  local name="$1" source="$2" pattern="$3" binary="$4" tag="$5" version="$6"
  local asset="${pattern//\{VERSION\}/$version}"
  asset="${asset//\{OS\}/$OS}"
  asset="${asset//\{ARCH\}/$ARCH}"
  binary="${binary//\{VERSION\}/$version}"
  local url fname ok=true
  if is_generic_source "$source"; then
    # asset_pattern is already a full https URL template.
    if [[ "$asset" != https://* || "$asset" == *[[:space:]]* || "$asset" == *[[:cntrl:]]* ]]; then
      ok=false
    fi
    fname="${asset##*/}"
    fname="${fname%%\?*}"
    fname="${fname%%#*}"
    [[ -n "$fname" ]] || ok=false
    url="$asset"
  else
    valid_asset "$asset" || ok=false
    fname="$asset"
    url="https://github.com/$source/releases/download/${tag}/${asset}"
  fi
  safe_relative_path "$binary" || ok=false
  if ! $ok; then
    echo "FAILED: $name (invalid asset or binary path)"
    return 1
  fi
  local tmpdir staged="" listing found bundle_name found_bundle bundle_root backup=""
  tmpdir=$(mktemp -d) || return 1
  tmpdir=$(cd "$tmpdir" && pwd -P) || return 1
  trap 'rm -rf "$tmpdir"; if [[ -n "$staged" ]]; then rm -f "$staged"; fi' EXIT
  if ! http_curl_retry "$url" -o "$tmpdir/$fname"; then
    echo "FAILED: $name (download failed: $url)"
    return 1
  fi
  # Checksum probes follow GitHub release conventions only; generic hosts
  # have no standard checksums-file location.
  if ! is_generic_source "$source"; then
    verify_checksum "$name" "$source" "$tag" "$version" "$fname" "$tmpdir/$fname" "$tmpdir" || return 1
  fi
  mkdir "$tmpdir/unpacked" || return 1
  if ! listing=$(list_archive "$tmpdir/$fname") || ! validate_listing "$listing"; then
    echo "FAILED: $name (unsafe archive or unreadable asset)"
    return 1
  fi
  case "$fname" in
    *.tar.gz|*.tgz) tar -xzf "$tmpdir/$fname" -C "$tmpdir/unpacked" || return 1 ;;
    *.tar.bz2|*.tbz) tar -xjf "$tmpdir/$fname" -C "$tmpdir/unpacked" || return 1 ;;
    *.tar.xz|*.txz) tar -xJf "$tmpdir/$fname" -C "$tmpdir/unpacked" || return 1 ;;
    *.tar) tar -xf "$tmpdir/$fname" -C "$tmpdir/unpacked" || return 1 ;;
    *.zip) unzip -q "$tmpdir/$fname" -d "$tmpdir/unpacked" || return 1 ;;
    *)
      mkdir -p "$tmpdir/unpacked/$(dirname "$binary")" || return 1
      cp "$tmpdir/$fname" "$tmpdir/unpacked/$binary" || return 1 ;;
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
  # Version state is recorded by the caller after the job drains —
  # concurrent subshells writing the state file would race.
  echo "$name $version -> $INSTALL_DIR/$name"
)

# --- Parallel job pool ---
# Jobs run as background subshells (up to $JOBS at once); stdout is buffered
# per job and printed FIFO on drain, so output stays in submission order.
# The parent alone writes counters and version state.
JOB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/untapped-jobs.XXXXXX")"
trap 'rm -rf "$JOB_DIR"' EXIT

IP_PID=()
IP_OUT=()
IP_ST=()
IP_META=()
IP_KIND=()
IP_HEAD=0

fetch_tag_job() (
  local source="$1" rule="${2:-}" stf="$3" tag
  tag="$(fetch_latest_tag "$source" "$rule")"
  if [[ -z "$tag" ]]; then
    exit 1
  fi
  printf '%s\n' "$tag" > "$stf"
)

run_install_job() (
  local name="$1" source="$2" pattern="$3" binary="$4" version_pin="$5" rule="$6" statusf="$7"
  local tag version
  if [[ -n "$version_pin" ]]; then
    tag="$version_pin"
  else
    tag="$(fetch_latest_tag "$source" "$rule")"
  fi
  if [[ -z "$tag" ]]; then
    fetch_fail_reason "$source" > "$statusf"
    exit 1
  fi
  version="${tag#v}"
  if install_binary "$name" "$source" "$pattern" "$binary" "$tag" "$version"; then
    printf 'ok|%s\n' "$version" > "$statusf"
    exit 0
  fi
  echo "install failed (see above)" > "$statusf"
  exit 1
)

run_upgrade_job() (
  local name="$1" source="$2" pattern="$3" binary="$4" tag="$5" version="$6" statusf="$7"
  if install_binary "$name" "$source" "$pattern" "$binary" "$tag" "$version"; then
    printf 'ok|%s\n' "$version" > "$statusf"
    exit 0
  fi
  echo "upgrade failed (see above)" > "$statusf"
  exit 1
)

process_install_result() {
  local i="$1"
  local entry="${IP_META[i]}" kind="${IP_KIND[i]}"
  local name st reason version
  cat "${IP_OUT[i]}" 2>/dev/null || true
  name="${entry%%|*}"
  st="$(cat "${IP_ST[i]}" 2>/dev/null || true)"
  if [[ "$st" == ok\|* ]]; then
    version="${st#ok|}"
    if set_installed_version "$name" "$version"; then
      if [[ "$kind" == upgrade ]]; then
        updated_count=$((updated_count + 1))
      else
        installed_count=$((installed_count + 1))
      fi
    else
      failed+=("$name|$kind failed (see above)")
    fi
  else
    reason="${st#fail|}"
    [[ -n "$reason" ]] || reason="$kind failed (see above)"
    failed+=("$name|$reason")
  fi
}

pool_wait_front() {
  wait "${IP_PID[IP_HEAD]}" || true
  IP_HEAD=$((IP_HEAD + 1))
}

pool_capacity_wait() {
  while (( ${#IP_PID[@]} - IP_HEAD >= JOBS )); do
    pool_wait_front
    process_install_result "$((IP_HEAD - 1))"
  done
}

pool_drain() {
  while (( IP_HEAD < ${#IP_PID[@]} )); do
    pool_wait_front
    process_install_result "$((IP_HEAD - 1))"
  done
}

pool_submit() {
  local kind="$1" entry="$2"
  local name source pattern binary version_pin rule tag version
  local outf="$JOB_DIR/out.${#IP_PID[@]}" stf="$JOB_DIR/st.${#IP_PID[@]}"
  pool_capacity_wait
  if [[ "$kind" == install ]]; then
    # rule rides last so it may itself contain '|' (regex alternation).
    IFS='|' read -r name source pattern binary version_pin rule <<< "$entry"
    echo "installing $name..."
    run_install_job "$name" "$source" "$pattern" "$binary" "$version_pin" "$rule" "$stf" > "$outf" 2>&1 &
  else
    IFS='|' read -r name source pattern binary tag version <<< "$entry"
    echo "upgrading $name..."
    run_upgrade_job "$name" "$source" "$pattern" "$binary" "$tag" "$version" "$stf" > "$outf" 2>&1 &
  fi
  IP_PID+=($!)
  IP_META+=("$entry")
  IP_KIND+=("$kind")
  IP_OUT+=("$outf")
  IP_ST+=("$stf")
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
    read -r -p "$prompt [Y/n] " reply || return 1
    [[ -z "$reply" || "$reply" == [yY] ]]
  else
    read -r -p "$prompt [y/N] " reply || return 1
    [[ "$reply" == [yY] ]]
  fi
}

# --- Collect work ---
# Pass 1 partitions conf entries offline; pass 2 fetches latest tags for
# installed unpinned entries in parallel; pass 3 decides in conf order so
# display order stays stable.
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
PEND_META=()
PEND_PIN=()
PEND_RULE=()

while IFS='|' read -r name source pattern binary os_filter arch_filter version_pin version_rule || [[ -n "$name" ]]; do
  name="${name//[[:space:]]/}"
  [[ -z "$name" || "$name" == \#* ]] && continue
  source="${source// /}"
  pattern="${pattern// /}"
  binary="${binary// /}"
  os_filter="${os_filter// /}"
  arch_filter="${arch_filter// /}"
  version_pin="${version_pin// /}"
  # version_rule: trim conf padding only — inner spaces matter in regexes.
  version_rule="${version_rule#"${version_rule%%[![:space:]]*}"}"
  version_rule="${version_rule%"${version_rule##*[![:space:]]}"}"

  if ! validate_entry "$name" "$source" "$pattern" "$binary" "$os_filter" "$arch_filter" "$version_pin" "$version_rule"; then
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
      to_install+=("$name|$source|$pattern|$binary|$version_pin|$version_rule")
      to_install_names+=("$name")
    else
      PEND_META+=("$name|$source|$pattern|$binary")
      PEND_PIN+=("$version_pin")
      PEND_RULE+=("$version_rule")
    fi
  else
    if ! command -v "$name" &>/dev/null; then
      to_install+=("$name|$source|$pattern|$binary|$version_pin|$version_rule")
      to_install_names+=("$name")
    else
      echo "skip $name (already installed: $(command -v "$name"))"
      skipped+=("$name|already installed")
    fi
  fi
done < "$CONF"

# Pass 2: parallel latest-tag fetches (installed, unpinned entries only).
TF_ST=()
TF_PID=()
TF_HEAD=0
if [[ ${#PEND_META[@]} -gt 0 ]]; then
  for i in "${!PEND_META[@]}"; do
    TF_ST[i]="$JOB_DIR/tag.$i.st"
    if [[ -n "${PEND_PIN[i]}" ]]; then
      continue
    fi
    while (( ${#TF_PID[@]} - TF_HEAD >= JOBS )); do
      wait "${TF_PID[TF_HEAD]}" || true
      TF_HEAD=$((TF_HEAD + 1))
    done
    tf_meta="${PEND_META[i]}"
    tf_source="${tf_meta#*|}"
    tf_source="${tf_source%%|*}"
    fetch_tag_job "$tf_source" "${PEND_RULE[i]}" "${TF_ST[i]}" > "$JOB_DIR/tag.$i.out" 2>&1 &
    TF_PID+=($!)
  done
  while (( TF_HEAD < ${#TF_PID[@]} )); do
    wait "${TF_PID[TF_HEAD]}" || true
    TF_HEAD=$((TF_HEAD + 1))
  done

  # Pass 3: decide in conf order from pins or fetched tags.
  for i in "${!PEND_META[@]}"; do
    meta="${PEND_META[i]}"
    name="${meta%%|*}"
    rest="${meta#*|}"
    source="${rest%%|*}"
    rest="${rest#*|}"
    pattern="${rest%%|*}"
    binary="${rest#*|}"
    if [[ -n "${PEND_PIN[i]}" ]]; then
      local_tag="${PEND_PIN[i]}"
    else
      local_tag="$(cat "${TF_ST[i]}" 2>/dev/null || true)"
    fi
    latest="${local_tag#v}"
    installed=$(get_installed_version "$name")
    if [[ -z "$local_tag" ]]; then
      failed+=("$name|$(fetch_fail_reason "$source")")
    elif [[ -z "$installed" || "$installed" != "$latest" ]]; then
      to_upgrade+=("$name|$source|$pattern|$binary|$local_tag|$latest")
      if [[ -n "${PEND_PIN[i]}" ]]; then
        to_upgrade_display+=("$name: ${installed:-unknown} → $latest (pinned)")
      else
        to_upgrade_display+=("$name: ${installed:-unknown} → $latest")
      fi
    elif [[ -n "${PEND_PIN[i]}" ]]; then
      echo "current $name ($installed, pinned)"
    else
      echo "current $name ($installed)"
    fi
  done
fi

# --- outdated: report only, never install ---
if $OUTDATED; then
  echo ""
  if [[ ${#to_upgrade_display[@]} -gt 0 ]]; then
    echo "Outdated:"
    for d in "${to_upgrade_display[@]}"; do echo "  • $d"; done
  else
    echo "All installed utilities are current."
  fi
  if [[ ${#to_install_names[@]} -gt 0 ]]; then
    echo ""
    echo "Not installed:"
    for n in "${to_install_names[@]}"; do echo "  • $n"; done
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
fi

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
      pool_submit install "$entry"
    done
    pool_drain
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
      pool_submit upgrade "$entry"
    done
    pool_drain
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
