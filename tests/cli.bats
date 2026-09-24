#!/usr/bin/env bats
# CLI surface, conf discovery, filters, dry-run summary.

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
  [[ "$output" == *"--dry-run"* ]]
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

@test "first run seeds empty conf and points at add" {
  # No -c, no ~/.config/untapped/conf under fake HOME
  run run_untapped --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created empty conf"* ]]
  [[ "$output" == *"untapped add https://github.com/owner/repo"* ]]
  [ -f "$HOME/.config/untapped/conf" ]
  # Did not install anything
  [ ! -e "$UNTAPPED_BIN_DIR/usql" ]
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
