#!/usr/bin/env bats
# Install path with mocked curl: flat binary, checksum, .app bundle, failures.

load test_helper

setup() {
  setup_test_env
  export PATH="$UNTAPPED_BIN_DIR:$PATH"
}

teardown() {
  teardown_test_env
}

@test "installs flat binary from tar.gz and records version" {
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho hello-untapped\n' > "$stage/flatbin"
  chmod +x "$stage/flatbin"
  tar -czf "$TEST_TMP/flatbin.tar.gz" -C "$stage" flatbin
  rm -rf "$stage"

  write_api_json ex flatbin v1.2.3
  write_asset "flatbin-1.2.3.tar.gz" "$TEST_TMP/flatbin.tar.gz"

  write_conf "$TEST_TMP/conf" \
    "flatbin | ex/flatbin | flatbin-{VERSION}.tar.gz | flatbin | |"

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed: 1"* ]]
  [[ "$output" == *"flatbin 1.2.3"* ]]
  [ -x "$UNTAPPED_BIN_DIR/flatbin" ]
  grep -q '^flatbin=1.2.3$' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "checksum match verifies and installs" {
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho ok\n' > "$stage/sumbin"
  chmod +x "$stage/sumbin"
  tar -czf "$TEST_TMP/sumbin.tar.gz" -C "$stage" sumbin
  rm -rf "$stage"

  if command -v shasum >/dev/null 2>&1; then
    sum="$(shasum -a 256 "$TEST_TMP/sumbin.tar.gz" | awk '{print $1}')"
  else
    sum="$(sha256sum "$TEST_TMP/sumbin.tar.gz" | awk '{print $1}')"
  fi
  # checksums.txt format: <hash>  <filename>
  write_asset "checksums.txt" <<<"$sum  sumbin-9.9.9.tar.gz"

  write_api_json ex sumbin v9.9.9
  write_asset "sumbin-9.9.9.tar.gz" "$TEST_TMP/sumbin.tar.gz"

  write_conf "$TEST_TMP/conf" \
    "sumbin | ex/sumbin | sumbin-{VERSION}.tar.gz | sumbin | |"

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checksum verified for sumbin"* ]]
  [[ "$output" == *"Installed: 1"* ]]
  [ -x "$UNTAPPED_BIN_DIR/sumbin" ]
}

@test "checksum mismatch fails the package and exits 1" {
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho bad\n' > "$stage/badsum"
  chmod +x "$stage/badsum"
  tar -czf "$TEST_TMP/badsum.tar.gz" -C "$stage" badsum
  rm -rf "$stage"

  write_asset "checksums.txt" <<<"0000000000000000000000000000000000000000000000000000000000000000  badsum-1.0.0.tar.gz"

  write_api_json ex badsum v1.0.0
  write_asset "badsum-1.0.0.tar.gz" "$TEST_TMP/badsum.tar.gz"

  write_conf "$TEST_TMP/conf" \
    "badsum | ex/badsum | badsum-{VERSION}.tar.gz | badsum | |"

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [[ "$output" == *"Failed:"* ]]
  [[ "$output" == *"badsum"* ]]
  [ ! -e "$UNTAPPED_BIN_DIR/badsum" ]
}

@test ".app bundle path preserves bundle under ~/.local/opt and symlinks binary" {
  stage="$(mktemp -d)"
  mkdir -p "$stage/demo.app/Contents/MacOS"
  printf '#!/bin/sh\necho demo\n' > "$stage/demo.app/Contents/MacOS/demo"
  chmod +x "$stage/demo.app/Contents/MacOS/demo"
  tar -czf "$TEST_TMP/demo.tar.gz" -C "$stage" demo.app
  rm -rf "$stage"

  write_api_json ex demo v0.1.0
  write_asset "demo.tar.gz" "$TEST_TMP/demo.tar.gz"

  write_conf "$TEST_TMP/conf" \
    "demo | ex/demo | demo.tar.gz | demo.app/Contents/MacOS/demo | darwin |"

  # .app entries are darwin-filtered; on Linux this should skip cleanly.
  if [[ "$(uname -s)" != "Darwin" ]]; then
    run run_untapped --yes -c "$TEST_TMP/conf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not available on"* ]]
    return 0
  fi

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed: 1"* ]]
  [ -d "$HOME/.local/opt/demo/demo.app" ]
  [ -L "$UNTAPPED_BIN_DIR/demo" ]
}

@test "download failure records Failed and exits 1" {
  write_api_json ex nofile v1.0.0
  # no asset fixture → mock curl exits 22
  write_conf "$TEST_TMP/conf" \
    "nofile | ex/nofile | nofile-{VERSION}.tar.gz | nofile | |"

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed:"* ]]
  [[ "$output" == *"nofile"* ]]
}

@test "non-interactive without --yes fails when installs are needed" {
  write_conf "$TEST_TMP/conf" \
    "needtty | ex/needtty | needtty-{VERSION}.tar.gz | needtty | |"
  # bats has no TTY on stdin
  run run_untapped -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a TTY"* ]] || [[ "$output" == *"--yes"* ]]
}
