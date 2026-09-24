#!/usr/bin/env bats
# CLI surface, conf discovery, filters, dry-run summary.
# Each Bats test deliberately has an isolated PATH.
# shellcheck disable=SC2030,SC2031

load test_helper

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "help exits 0 and shows usage" {
  run run_untapped help
  [ "$status" -eq 0 ]
  [[ "$output" == *"untapped"* ]]
  [[ "$output" == *"upgrade"* ]]
  [[ "$output" == *"list"* ]]
  [[ "$output" == *"doctor"* ]]
  [[ "$output" == *"outdated"* ]]
  [[ "$output" == *"remove"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--jobs"* ]]
}

@test "help conf default does not claim packaged example" {
  run run_untapped help
  [ "$status" -eq 0 ]
  [[ "$output" != *"else example"* ]]
  [[ "$output" == *"(default: ~/.config/untapped/conf)"* ]]
}

@test "list shows conf entries with install status" {
  printf '#!/bin/sh\necho fake\n' > "$UNTAPPED_BIN_DIR/herebin"
  chmod +x "$UNTAPPED_BIN_DIR/herebin"
  PATH="$UNTAPPED_BIN_DIR:$PATH"
  export PATH
  printf 'herebin=1.2.3\n' > "$UNTAPPED_SHARE_DIR/installed.conf"
  write_conf "$TEST_TMP/conf" \
    "herebin  | ex/herebin  | herebin-{VERSION}.tar.gz  | herebin  | |" \
    "awaybin  | ex/awaybin  | awaybin-{VERSION}.tar.gz  | awaybin  | |"
  run run_untapped list -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"herebin"*"installed (1.2.3)"* ]]
  [[ "$output" == *"awaybin"*"not on PATH"* ]]
}

@test "list marks OS-filter mismatches without installing" {
  other_os=linux
  [[ "$(uname -s)" == Linux ]] && other_os=darwin
  write_conf "$TEST_TMP/conf" \
    "onlylinux | ex/onlylinux | x-{VERSION}.tar.gz | onlylinux | $other_os |"
  run run_untapped list -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"onlylinux"*"not available on"* ]]
  [ ! -e "$UNTAPPED_BIN_DIR/onlylinux" ]
}

@test "unknown flag exits 1" {
  run run_untapped --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown argument"* ]]
}

@test "missing -c conf exits 1" {
  run run_untapped -c /no/such/conf
  [ "$status" -eq 1 ]
  [[ "$output" == *"conf not found"* ]]
}

@test "os_filter skips non-matching entries before download" {
  write_conf "$TEST_TMP/conf" \
    "onlydarwin | ex/onlydarwin | x-{VERSION}.tar.gz | onlydarwin | darwin |" \
    "onlylinux  | ex/onlylinux  | x-{VERSION}.tar.gz | onlylinux  | linux  |"
  run run_untapped --dry-run --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"onlydarwin — not available on"* ]] || [[ "$output" == *"onlylinux — not available on"* ]]
  # Exactly one should be skipped for OS depending on host; the other may "would install"
  [[ "$output" == *"Skipped:"* ]]
  [[ "$output" == *"[dry-run] Installed: 0  Updated: 0"* ]]
}

@test "arch_filter skips non-matching arch" {
  host_arch="$(uname -m)"
  case "$host_arch" in
    arm64|aarch64) other="amd64" ;;
    *)             other="arm64" ;;
  esac
  write_conf "$TEST_TMP/conf" \
    "wrongarch | ex/wrongarch | x-{VERSION}.tar.gz | wrongarch | | $other"
  run run_untapped --dry-run --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wrongarch — not available on"* ]]
}

@test "dry-run does not install anything" {
  write_conf "$TEST_TMP/conf" \
    "neverbin | ex/neverbin | neverbin-{VERSION}.tar.gz | neverbin | |"
  run run_untapped --dry-run --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would install:"* ]]
  [[ "$output" == *"neverbin"* ]]
  [ ! -e "$UNTAPPED_BIN_DIR/neverbin" ]
}

@test "already installed package is skipped with reason" {
  printf '#!/bin/sh\necho fake\n' > "$UNTAPPED_BIN_DIR/fakebin"
  chmod +x "$UNTAPPED_BIN_DIR/fakebin"
  # Put test bin dir on PATH so command -v finds it
  PATH="$UNTAPPED_BIN_DIR:$PATH"
  export PATH
  write_conf "$TEST_TMP/conf" \
    "fakebin | ex/fakebin | fakebin-{VERSION}.tar.gz | fakebin | |"
  run run_untapped --dry-run --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fakebin — already installed"* ]]
}

@test "summary always prints counts" {
  write_conf "$TEST_TMP/conf" \
    "# only a comment"
  run run_untapped --dry-run --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Installed: 0  Updated: 0  Skipped:"* ]]
  [[ "$output" == *"Failed: 0"* ]]
  [[ "$output" == *"No packages configured yet"* ]]
}

@test "first run without TTY seeds empty conf and points at add" {
  # No -c, no ~/.config/untapped/conf under fake HOME; bats stdin is not a TTY
  run run_untapped
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created empty conf"* ]]
  [[ "$output" == *"untapped add https://github.com/owner/repo"* ]]
  [ -f "$HOME/.config/untapped/conf" ]
  [ ! -e "$UNTAPPED_BIN_DIR/usql" ]
}

@test "first run --yes seeds conf from example without installing" {
  run run_untapped --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Seeded conf from example"* ]]
  [[ "$output" == *"Next:"* ]]
  [[ "$output" == *"untapped add https://github.com/owner/repo"* ]]
  [[ "$output" == *"untapped --yes"* ]]
  grep -Fq 'usql' "$HOME/.config/untapped/conf"
  [ ! -e "$UNTAPPED_BIN_DIR/usql" ]
}

run_first_run_prompt() {
  export MOCK_FIXTURES="$FIXTURES"
  "$TEST_PYTHON" "$REPO_ROOT/tests/tty_prompt.py" "$UNTTAPPED_BIN" "$@"
}

@test "first run Enter seeds conf from example on system Bash" {
  PROMPT_REPLY=$'\n' run run_first_run_prompt
  [ "$status" -eq 0 ]
  [[ "$output" == *"Seed from packaged example?"* ]]
  [[ "$output" == *"Seeded conf from example"* ]]
  grep -Fq 'usql' "$HOME/.config/untapped/conf"
  [ ! -e "$UNTAPPED_BIN_DIR/usql" ]
}

@test "first run declining seed creates empty conf" {
  PROMPT_REPLY=$'n\n' run run_first_run_prompt
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created empty conf"* ]]
  [ -f "$HOME/.config/untapped/conf" ]
  run grep -Fq 'usql' "$HOME/.config/untapped/conf"
  [ "$status" -ne 0 ]
}

@test "empty conf (no packages) hints at add without installing" {
  mkdir -p "$HOME/.config/untapped"
  write_conf "$HOME/.config/untapped/conf" \
    "# nothing yet"
  run run_untapped --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"No packages configured yet"* ]]
  [[ "$output" == *"untapped add"* ]]
  [[ "$output" == *"Installed: 0"* ]]
}

@test "doctor prints conf path, dirs, counts, os and arch" {
  printf '#!/bin/sh\necho fake\n' > "$UNTAPPED_BIN_DIR/herebin"
  chmod +x "$UNTAPPED_BIN_DIR/herebin"
  PATH="$UNTAPPED_BIN_DIR:$PATH"
  export PATH
  other_os=linux
  [[ "$(uname -s)" == Linux ]] && other_os=darwin
  write_conf "$TEST_TMP/conf" \
    "herebin  | ex/herebin  | herebin-{VERSION}.tar.gz  | herebin  | |" \
    "awaybin  | ex/awaybin  | awaybin-{VERSION}.tar.gz  | awaybin  | |" \
    "onlyother | ex/onlyother | x-{VERSION}.tar.gz | onlyother | $other_os |"
  run run_untapped doctor -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"conf:"*"$TEST_TMP/conf"* ]]
  [[ "$output" == *"bin dir:"* ]]
  [[ "$output" == *"share dir:"* ]]
  [[ "$output" == *"os:"* ]]
  [[ "$output" == *"arch:"* ]]
  [[ "$output" == *"packages:"*"3 configured, 1 installed, 1 missing, 1 filtered"* ]]
}

@test "doctor does not hit the network" {
  write_conf "$TEST_TMP/conf" \
    "herebin | ex/herebin | herebin-{VERSION}.tar.gz | herebin | |"
  MOCK_CURL_FAIL=api.github.com run run_untapped doctor -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"packages:"* ]]
}

@test "outdated lists installed vs latest without installing" {
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho v1\n' > "$stage/oldbin"
  chmod +x "$stage/oldbin"
  tar -czf "$TEST_TMP/oldbin.tar.gz" -C "$stage" oldbin
  rm -rf "$stage"
  printf '#!/bin/sh\necho v1\n' > "$UNTAPPED_BIN_DIR/oldbin"
  chmod +x "$UNTAPPED_BIN_DIR/oldbin"
  PATH="$UNTAPPED_BIN_DIR:$PATH"
  export PATH
  printf 'oldbin=1.0.0\n' > "$UNTAPPED_SHARE_DIR/installed.conf"
  write_api_json ex oldbin v2.0.0
  write_asset "oldbin-2.0.0.tar.gz" "$TEST_TMP/oldbin.tar.gz"
  write_conf "$TEST_TMP/conf" \
    "oldbin | ex/oldbin | oldbin-{VERSION}.tar.gz | oldbin | |"
  run run_untapped outdated -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Outdated:"* ]]
  [[ "$output" == *"oldbin: 1.0.0 → 2.0.0"* ]]
  grep -q '^oldbin=1.0.0$' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "outdated reports current when versions match" {
  printf '#!/bin/sh\necho v2\n' > "$UNTAPPED_BIN_DIR/curbin"
  chmod +x "$UNTAPPED_BIN_DIR/curbin"
  PATH="$UNTAPPED_BIN_DIR:$PATH"
  export PATH
  printf 'curbin=2.0.0\n' > "$UNTAPPED_SHARE_DIR/installed.conf"
  write_api_json ex curbin v2.0.0
  write_conf "$TEST_TMP/conf" \
    "curbin | ex/curbin | curbin-{VERSION}.tar.gz | curbin | |"
  run run_untapped outdated -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All installed utilities are current."* ]]
  [[ "$output" != *"Outdated:"* ]]
}
