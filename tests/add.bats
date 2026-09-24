#!/usr/bin/env bats
# untapped add: URL parse, asset pick, binary sniff, conf append.

load test_helper

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "add rejects non-repo input" {
  run run_untapped add "not a url"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a GitHub repo URL"* ]]
}

@test "add dry-run prints conf line and does not write" {
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho demo\n' > "$stage/democtl"
  chmod +x "$stage/democtl"
  tar -czf "$TEST_TMP/democtl.tar.gz" -C "$stage" democtl
  rm -rf "$stage"

  write_api_release ex demorepo v1.0.0 "demorepo-1.0.0.tar.gz"
  write_asset "demorepo-1.0.0.tar.gz" "$TEST_TMP/democtl.tar.gz"

  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --dry-run --yes -c "$conf" https://github.com/ex/demorepo
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] conf not modified"* ]]
  [[ "$output" == *"demorepo | ex/demorepo"* ]]
  [[ "$output" == *"{VERSION}"* ]]
  [ ! -s "$conf" ]
}

@test "add --yes appends line with binary path from archive" {
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho demo\n' > "$stage/democtl"
  chmod +x "$stage/democtl"
  tar -czf "$TEST_TMP/democtl.tar.gz" -C "$stage" democtl
  rm -rf "$stage"

  write_api_release ex demorepo v1.0.0 "demorepo-1.0.0.tar.gz"
  write_asset "demorepo-1.0.0.tar.gz" "$TEST_TMP/democtl.tar.gz"

  conf="$TEST_TMP/conf"
  printf '# header\n' > "$conf"

  run run_untapped add --yes -c "$conf" ex/demorepo
  [ "$status" -eq 0 ]
  [[ "$output" == *"added demorepo"* ]]
  grep -q '^demorepo | ex/demorepo |' "$conf"
  grep -q '| democtl |' "$conf"
}

@test "add fails when package already in conf" {
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho demo\n' > "$stage/democtl"
  chmod +x "$stage/democtl"
  tar -czf "$TEST_TMP/democtl.tar.gz" -C "$stage" democtl
  rm -rf "$stage"

  write_api_release ex demorepo v1.0.0 "demorepo-1.0.0.tar.gz"
  write_asset "demorepo-1.0.0.tar.gz" "$TEST_TMP/democtl.tar.gz"

  conf="$TEST_TMP/conf"
  write_conf "$conf" "demorepo | ex/demorepo | demorepo-{VERSION}.tar.gz | democtl | |"

  run run_untapped add --yes -c "$conf" ex/demorepo
  [ "$status" -eq 1 ]
  [[ "$output" == *"already in conf"* ]]
}

@test "add skips OS-mismatched assets and picks host match" {
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho demo\n' > "$stage/democtl"
  chmod +x "$stage/democtl"
  tar -czf "$TEST_TMP/democtl-darwin-arm64.tar.gz" -C "$stage" democtl
  tar -czf "$TEST_TMP/democtl-linux-amd64.tar.gz" -C "$stage" democtl
  rm -rf "$stage"

  other_os="linux"
  [[ "$(uname -s)" == "Linux" ]] && other_os="darwin"

  write_api_release ex demorepo v1.0.0 \
    "democtl-1.0.0-${other_os}-x64.tar.gz" \
    "democtl-1.0.0-$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/darwin/darwin/')-$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/').tar.gz"

  # Simpler: host-named asset + other-OS asset
  host_os="darwin"
  [[ "$(uname -s)" == "Linux" ]] && host_os="linux"
  host_arch="arm64"
  [[ "$(uname -m)" == "x86_64" ]] && host_arch="amd64"

  write_api_release ex demorepo v1.0.0 \
    "democtl-1.0.0-${host_os}-${host_arch}.tar.gz" \
    "democtl-1.0.0-${other_os}-amd64.tar.gz"

  write_asset "democtl-1.0.0-${host_os}-${host_arch}.tar.gz" "$TEST_TMP/democtl-${host_os}-${host_arch}.tar.gz"
  write_asset "democtl-1.0.0-${other_os}-amd64.tar.gz" "$TEST_TMP/democtl-${other_os}-amd64.tar.gz"

  # ensure host tarball exists (created above under host name)
  if [[ ! -f "$TEST_TMP/democtl-${host_os}-${host_arch}.tar.gz" ]]; then
    cp "$TEST_TMP/democtl-darwin-arm64.tar.gz" "$TEST_TMP/democtl-${host_os}-${host_arch}.tar.gz" 2>/dev/null || {
      stage="$(mktemp -d)"
      printf '#!/bin/sh\necho demo\n' > "$stage/democtl"
      chmod +x "$stage/democtl"
      tar -czf "$TEST_TMP/democtl-${host_os}-${host_arch}.tar.gz" -C "$stage" democtl
      rm -rf "$stage"
    }
  fi

  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --dry-run --yes -c "$conf" ex/demorepo
  [ "$status" -eq 0 ]
  [[ "$output" == *"democtl-1.0.0-${host_os}-${host_arch}.tar.gz"* ]]
  [[ "$output" != *"democtl-1.0.0-${other_os}-amd64.tar.gz"* ]]
}

@test "add bare binary uses filename as binary_in_archive" {
  write_api_release ex barebin v2.0.0 "barebin-2.0.0"
  write_asset "barebin-2.0.0" <<<"#!/bin/sh
echo bare"

  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --yes -c "$conf" https://github.com/ex/barebin/releases
  [ "$status" -eq 0 ]
  grep -q '| barebin-2.0.0 | barebin-2.0.0 |' "$conf" || grep -q 'barebin-2.0.0 |' "$conf"
  grep -q 'barebin | ex/barebin |' "$conf"
}

@test "add without --yes fails when stdin is not a TTY" {
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho demo\n' > "$stage/democtl"
  chmod +x "$stage/democtl"
  tar -czf "$TEST_TMP/democtl.tar.gz" -C "$stage" democtl
  rm -rf "$stage"

  write_api_release ex demorepo v1.0.0 "demorepo-1.0.0.tar.gz"
  write_asset "demorepo-1.0.0.tar.gz" "$TEST_TMP/democtl.tar.gz"

  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add -c "$conf" ex/demorepo
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a TTY"* ]] || [[ "$output" == *"--yes"* ]]
}

@test "help mentions add" {
  run run_untapped help
  [ "$status" -eq 0 ]
  [[ "$output" == *"untapped add"* ]]
}
