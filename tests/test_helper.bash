#!/usr/bin/env bash
# Shared setup for untapped bats tests.
# shellcheck shell=bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNTTAPPED_BIN="$REPO_ROOT/bin/untapped"

setup_test_env() {
  TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP/home"
  export UNTAPPED_BIN_DIR="$TEST_TMP/bin"
  export UNTAPPED_SHARE_DIR="$TEST_TMP/share"
  MOCK_BIN="$TEST_TMP/mockbin"
  FIXTURES="$TEST_TMP/fixtures"
  mkdir -p "$HOME" "$UNTAPPED_BIN_DIR" "$UNTAPPED_SHARE_DIR" "$MOCK_BIN" "$FIXTURES"

  # Isolate PATH: mock tools first, then a minimal real path (no user bins)
  ORIG_PATH="$PATH"
  export PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"

  install_mock_curl
}

teardown_test_env() {
  export PATH="$ORIG_PATH"
  rm -rf "$TEST_TMP"
}

# Mock curl: routes by URL shape using $MOCK_ROUTES env (dir of sidecar files).
# Layout expected under $FIXTURES:
#   api/<owner>_<repo>.json          → API releases/latest body
#   assets/<escaped-or-slug>         → raw body written when -o used
# Optional: $FIXTURES/curl_fail_urls  → newline substrings; matching URLs fail
install_mock_curl() {
  cat > "$MOCK_BIN/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
url=""
out=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  a="${args[$i]}"
  case "$a" in
    -o)
      i=$((i + 1))
      out="${args[$i]}"
      ;;
    -H)
      i=$((i + 1))
      ;;
    -fsSL|-s|-S|-f|-L|-sS)
      ;;
    http://*|https://*)
      url="$a"
      ;;
  esac
  i=$((i + 1))
done

if [[ -z "$url" ]]; then
  echo "mock curl: no url" >&2
  exit 2
fi

if [[ -n "${MOCK_CURL_FAIL:-}" && "$url" == *"${MOCK_CURL_FAIL}"* ]]; then
  exit 22
fi

fixtures="${MOCK_FIXTURES:?MOCK_FIXTURES not set}"

# GitHub API releases/latest
if [[ "$url" == *"/releases/latest"* ]]; then
  # https://api.github.com/repos/owner/repo/releases/latest
  path="${url#*api.github.com/repos/}"
  path="${path%/releases/latest}"
  owner="${path%%/*}"
  repo="${path#*/}"
  body="$fixtures/api/${owner}_${repo}.json"
  if [[ ! -f "$body" ]]; then
    exit 22
  fi
  if [[ -n "$out" ]]; then
    cp "$body" "$out"
  else
    cat "$body"
  fi
  exit 0
fi

# Release asset / checksum download
# https://github.com/owner/repo/releases/download/tag/name
name="$(basename "$url")"
tag_dir="$(basename "$(dirname "$url")")"
# Prefer tag-specific fixture, then bare name
for candidate in \
  "$fixtures/assets/${tag_dir}__${name}" \
  "$fixtures/assets/${name}"; do
  if [[ -f "$candidate" ]]; then
    if [[ -n "$out" ]]; then
      cp "$candidate" "$out"
    else
      cat "$candidate"
    fi
    exit 0
  fi
done

# Missing checksum candidate → soft-fail like real curl -f
exit 22
MOCK
  chmod +x "$MOCK_BIN/curl"

  # Minimal stand-ins so tests don't need a full toolchain in PATH
  for tool in grep sed awk cut head find mkdir mktemp chmod cp rm ln tar unzip cat touch; do
    if [[ -x "/bin/$tool" ]]; then
      ln -sf "/bin/$tool" "$MOCK_BIN/$tool" 2>/dev/null || true
    elif [[ -x "/usr/bin/$tool" ]]; then
      ln -sf "/usr/bin/$tool" "$MOCK_BIN/$tool" 2>/dev/null || true
    fi
  done
}

write_conf() {
  local path="$1"
  shift
  printf '%s\n' "$@" > "$path"
}

write_api_json() {
  local owner="$1" repo="$2" tag="$3"
  mkdir -p "$FIXTURES/api"
  printf '{"tag_name": "%s"}\n' "$tag" > "$FIXTURES/api/${owner}_${repo}.json"
}

# write_api_release owner repo tag asset1 [asset2...]
# Builds a releases/latest body with browser_download_url entries.
write_api_release() {
  local owner="$1" repo="$2" tag="$3"
  shift 3
  mkdir -p "$FIXTURES/api"
  {
    printf '{"tag_name": "%s", "assets": [' "$tag"
    local first=1 a
    for a in "$@"; do
      if [[ $first -eq 0 ]]; then
        printf ','
      fi
      first=0
      printf '{"name": "%s", "browser_download_url": "https://github.com/%s/%s/releases/download/%s/%s"}' \
        "$a" "$owner" "$repo" "$tag" "$a"
    done
    printf ']}\n'
  } > "$FIXTURES/api/${owner}_${repo}.json"
}

write_asset() {
  # write_asset <filename> <<< content  OR write_asset <filename> from path
  local name="$1"
  mkdir -p "$FIXTURES/assets"
  if [[ -n "${2:-}" && -f "${2:-}" ]]; then
    cp "$2" "$FIXTURES/assets/$name"
  else
    cat > "$FIXTURES/assets/$name"
  fi
}

run_untapped() {
  export MOCK_FIXTURES="$FIXTURES"
  "$UNTTAPPED_BIN" "$@"
}
