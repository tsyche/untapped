#!/usr/bin/env bash
# remove — drop conf entries and uninstall packages managed by untapped.
# Conf line first (a failed artifact delete must never reinstall on the
# next run), then binary, .app bundle under ~/.local/opt, and version state.
# Offline: no network, no OS/arch filtering (cleanup works everywhere).
#
# Usage:
#   remove.sh <name>...
#   remove.sh -c PATH [--yes] [--dry-run] <name>...
set -euo pipefail

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$LIB_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
DEFAULT_USER_CONF="$HOME/.config/untapped/conf"
EXAMPLE_CONF="$ROOT/conf/untapped.conf.example"

usage() {
  cat <<'EOF'
untapped remove — drop conf entries and uninstall packages

Usage:
  untapped remove <name>...
  untapped remove usql tart

Options:
  -c, --config PATH        conf file
                           (default: ~/.config/untapped/conf)
  -y, --yes                skip the confirmation prompt
  -n, --dry-run            show what would be removed; change nothing
EOF
}

CONF=""
YES=false
DRY_RUN=false
NAMES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)
      if [[ $# -lt 2 ]]; then
        echo "untapped remove: -c requires a path" >&2
        exit 1
      fi
      CONF="$2"
      shift 2
      ;;
    --yes|-y) YES=true; shift ;;
    --dry-run|-n) DRY_RUN=true; shift ;;
    help|--help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "untapped remove: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      NAMES+=("$1")
      shift
      ;;
  esac
done

if [[ ${#NAMES[@]} -eq 0 ]]; then
  usage >&2
  exit 1
fi

# Validate + dedupe names (bash 3.2-safe: never expand a possibly-empty array).
DEDUPED=()
for n in "${NAMES[@]}"; do
  if ! valid_name "$n"; then
    echo "untapped remove: invalid package name: $n" >&2
    exit 1
  fi
  dup=false
  if [[ ${#DEDUPED[@]} -gt 0 ]]; then
    for d in "${DEDUPED[@]}"; do
      if [[ "$d" == "$n" ]]; then
        dup=true
        break
      fi
    done
  fi
  $dup || DEDUPED+=("$n")
done
NAMES=("${DEDUPED[@]}")

if [[ -n "$CONF" ]]; then
  if [[ ! -f "$CONF" ]]; then
    echo "untapped remove: conf not found: $CONF" >&2
    exit 1
  fi
elif [[ -f "$DEFAULT_USER_CONF" ]]; then
  CONF="$DEFAULT_USER_CONF"
else
  echo "untapped remove: conf not found: $DEFAULT_USER_CONF" >&2
  echo "Add a package first: untapped add https://github.com/owner/repo" >&2
  exit 1
fi

if [[ -f "$EXAMPLE_CONF" && "$CONF" -ef "$EXAMPLE_CONF" ]]; then
  echo "untapped remove: refusing to modify the packaged example conf" >&2
  exit 1
fi

INSTALL_DIR="${UNTAPPED_BIN_DIR:-$HOME/.local/bin}"
VERSION_DIR="${UNTAPPED_SHARE_DIR:-$HOME/.local/share/untapped}"
VERSION_FILE="$VERSION_DIR/installed.conf"
OPT_ROOT="$HOME/.local/opt"

# Look up every requested name in conf; any miss aborts before changes.
FOUND_NAMES=()
FOUND_BINARY=()
missing=()
for n in "${NAMES[@]}"; do
  hit=false
  # shellcheck disable=SC2034  # fields split positionally; only name/binary used
  while IFS='|' read -r name repo pattern binary os_filter arch_filter version_pin || [[ -n "$name" ]]; do
    name="${name//[[:space:]]/}"
    [[ -z "$name" || "$name" == \#* ]] && continue
    if [[ "$name" == "$n" ]]; then
      binary="${binary// /}"
      FOUND_BINARY+=("$binary")
      hit=true
      break
    fi
  done < "$CONF"
  if $hit; then
    FOUND_NAMES+=("$n")
  else
    missing+=("$n")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "untapped remove: not in conf: ${missing[*]}" >&2
  exit 1
fi

# Plan what each removal touches (computed once; dry-run and execute share it).
PLAN_BIN=()
PLAN_HAS_BIN=()
PLAN_OPT=()
PLAN_HAS_OPT=()
PLAN_HAS_STATE=()
PLAN_NOTE=()

for i in "${!FOUND_NAMES[@]}"; do
  n="${FOUND_NAMES[$i]}"
  binary="${FOUND_BINARY[$i]}"
  bin_path="$INSTALL_DIR/$n"

  opt=""
  if [[ "$binary" == *.app/Contents/MacOS/* ]]; then
    opt="$OPT_ROOT/$n"
  elif [[ -L "$bin_path" ]]; then
    target="$(readlink "$bin_path" 2>/dev/null || true)"
    case "$target" in
      "$OPT_ROOT/$n"/*) opt="$OPT_ROOT/$n" ;;
    esac
  fi

  has_bin=false
  if [[ -e "$bin_path" || -L "$bin_path" ]]; then
    has_bin=true
  fi
  has_opt=false
  if [[ -n "$opt" && -e "$opt" ]]; then
    has_opt=true
  fi
  has_state=false
  if [[ -f "$VERSION_FILE" ]] \
    && awk -F= -v n="$n" '$1 == n {found=1} END {exit !found}' "$VERSION_FILE"; then
    has_state=true
  fi
  note=""
  if ! $has_bin; then
    if command -v "$n" &>/dev/null; then
      note="PATH binary not managed by untapped: $(command -v "$n")"
    else
      note="binary not installed"
    fi
  fi

  PLAN_BIN+=("$bin_path")
  PLAN_HAS_BIN+=("$has_bin")
  PLAN_OPT+=("$opt")
  PLAN_HAS_OPT+=("$has_opt")
  PLAN_HAS_STATE+=("$has_state")
  PLAN_NOTE+=("$note")
done

describe_actions() {
  local i="$1" out="conf"
  [[ "${PLAN_HAS_BIN[$i]}" == true ]] && out+=", binary"
  [[ "${PLAN_HAS_OPT[$i]}" == true ]] && out+=", bundle"
  [[ "${PLAN_HAS_STATE[$i]}" == true ]] && out+=", state"
  printf '%s' "$out"
}

if $DRY_RUN; then
  for i in "${!FOUND_NAMES[@]}"; do
    line="would remove ${FOUND_NAMES[$i]} ($(describe_actions "$i"))"
    [[ -n "${PLAN_NOTE[$i]}" ]] && line+=" — ${PLAN_NOTE[$i]}"
    echo "$line"
  done
  echo "[dry-run] nothing changed"
  exit 0
fi

if ! $YES; then
  if [[ ! -t 0 ]]; then
    echo "untapped remove: stdin is not a TTY; pass --yes to proceed non-interactively" >&2
    exit 1
  fi
  read -r -p "Remove ${#FOUND_NAMES[@]} package(s) (conf, binary, state)? [y/N] " reply
  if [[ "$reply" != [yY] && "$reply" != [yY][eE][sS] ]]; then
    echo "aborted; nothing changed"
    exit 1
  fi
fi

# Conf line(s) first, written through any symlink (never mv over the conf).
names_csv=""
for n in "${FOUND_NAMES[@]}"; do
  names_csv+="${names_csv:+,}$n"
done
conf_tmp="$(mktemp "${TMPDIR:-/tmp}/untapped-conf.XXXXXX")" || exit 1
if ! awk -F'|' -v names="$names_csv" '
  BEGIN { n = split(names, arr, ",") }
  {
    orig = $0
    nm = $1
    gsub(/[[:space:]]/, "", nm)
    for (i = 1; i <= n; i++) if (nm == arr[i]) next
    print orig
  }
' "$CONF" > "$conf_tmp"; then
  rm -f "$conf_tmp"
  echo "untapped remove: failed to rewrite conf" >&2
  exit 1
fi
if ! cat "$conf_tmp" > "$CONF"; then
  rm -f "$conf_tmp"
  echo "untapped remove: failed to write conf: $CONF" >&2
  exit 1
fi
rm -f "$conf_tmp"

removed=0
failed=0
failed_notes=()

for i in "${!FOUND_NAMES[@]}"; do
  n="${FOUND_NAMES[$i]}"
  pkg_failed=false

  if [[ "${PLAN_HAS_BIN[$i]}" == true ]]; then
    if ! rm -f "${PLAN_BIN[$i]}"; then
      pkg_failed=true
      failed_notes+=("$n: could not delete ${PLAN_BIN[$i]}")
    fi
  fi
  if [[ "${PLAN_HAS_OPT[$i]}" == true ]]; then
    if ! rm -rf "${PLAN_OPT[$i]}"; then
      pkg_failed=true
      failed_notes+=("$n: could not delete ${PLAN_OPT[$i]}")
    fi
  fi
  if [[ "${PLAN_HAS_STATE[$i]}" == true ]]; then
    state_tmp="$(mktemp "$VERSION_DIR/.installed.XXXXXX" 2>/dev/null || true)"
    if [[ -z "$state_tmp" ]] \
      || ! awk -F= -v n="$n" '$1 != n' "$VERSION_FILE" > "$state_tmp" \
      || ! mv -f "$state_tmp" "$VERSION_FILE"; then
      [[ -n "$state_tmp" ]] && rm -f "$state_tmp"
      pkg_failed=true
      failed_notes+=("$n: could not update $VERSION_FILE")
    fi
  fi

  if $pkg_failed; then
    failed=$((failed + 1))
  else
    removed=$((removed + 1))
    extra=""
    [[ -n "${PLAN_NOTE[$i]}" ]] && extra=" — ${PLAN_NOTE[$i]}"
    echo "removed $n ($(describe_actions "$i"))$extra"
  fi
done

echo ""
echo "Removed: $removed  Failed: $failed"

if [[ $failed -gt 0 ]]; then
  echo ""
  echo "Failed:"
  for x in "${failed_notes[@]}"; do
    echo "  • $x"
  done
  echo ""
  echo "note: conf entries were already removed; re-add the line if you want installs again"
  exit 1
fi

exit 0
