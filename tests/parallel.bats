#!/usr/bin/env bats
# Parallel job pool (-j) and transient-failure retries (--retries).

load test_helper

setup() {
  setup_test_env
  export PATH="$UNTAPPED_BIN_DIR:$PATH"
}

teardown() {
  teardown_test_env
}

# make_pkg <name> <version> — release fixture: api json + versioned tarball.
make_pkg() {
  local n="$1" v="$2"
  local stage
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho %s\n' "$n" > "$stage/$n"
  chmod +x "$stage/$n"
  tar -czf "$TEST_TMP/$n.tar.gz" -C "$stage" "$n"
  rm -rf "$stage"
  write_api_json ex "$n" "v$v"
  write_asset "$n-$v.tar.gz" "$TEST_TMP/$n.tar.gz"
}

make_installed() {
  # make_installed <name> <version> — binary in bin dir + state line
  printf '#!/bin/sh\necho old\n' > "$UNTAPPED_BIN_DIR/$1"
  chmod +x "$UNTAPPED_BIN_DIR/$1"
  printf '%s=%s\n' "$1" "$2" >> "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "parallel install of multiple packages with -j 3" {
  make_pkg alpha 1.0.0
  make_pkg beta 1.0.0
  make_pkg gamma 1.0.0
  write_conf "$TEST_TMP/conf" \
    "alpha | ex/alpha | alpha-{VERSION}.tar.gz | alpha | |" \
    "beta  | ex/beta  | beta-{VERSION}.tar.gz  | beta  | |" \
    "gamma | ex/gamma | gamma-{VERSION}.tar.gz | gamma | |"

  run run_untapped --yes -j 3 -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed: 3"* ]]
  [[ "$output" == *"Failed: 0"* ]]
  [ -x "$UNTAPPED_BIN_DIR/alpha" ]
  [ -x "$UNTAPPED_BIN_DIR/beta" ]
  [ -x "$UNTAPPED_BIN_DIR/gamma" ]
  grep -q '^alpha=1.0.0$' "$UNTAPPED_SHARE_DIR/installed.conf"
  grep -q '^beta=1.0.0$' "$UNTAPPED_SHARE_DIR/installed.conf"
  grep -q '^gamma=1.0.0$' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "parallel run installs what it can and reports failures" {
  make_pkg alpha 1.0.0
  make_pkg broken 1.0.0
  rm "$FIXTURES/assets/broken-1.0.0.tar.gz"
  write_conf "$TEST_TMP/conf" \
    "alpha  | ex/alpha  | alpha-{VERSION}.tar.gz  | alpha  | |" \
    "broken | ex/broken | broken-{VERSION}.tar.gz | broken | |"

  run run_untapped --yes -j 2 -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Installed: 1"* ]]
  [[ "$output" == *"Failed: 1"* ]]
  [[ "$output" == *"broken"* ]]
  [ -x "$UNTAPPED_BIN_DIR/alpha" ]
  [ ! -e "$UNTAPPED_BIN_DIR/broken" ]
  run grep -q '^broken=' "$UNTAPPED_SHARE_DIR/installed.conf"
  [ "$status" -ne 0 ]
}

@test "-j 1 installs serially" {
  make_pkg alpha 1.0.0
  make_pkg beta 1.0.0
  write_conf "$TEST_TMP/conf" \
    "alpha | ex/alpha | alpha-{VERSION}.tar.gz | alpha | |" \
    "beta  | ex/beta  | beta-{VERSION}.tar.gz  | beta  | |"

  run run_untapped --yes -j 1 -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed: 2"* ]]
  [ -x "$UNTAPPED_BIN_DIR/alpha" ]
  [ -x "$UNTAPPED_BIN_DIR/beta" ]
}

@test "parallel upgrade updates all outdated packages" {
  make_pkg alpha 2.0.0
  make_pkg beta 2.0.0
  make_installed alpha 1.0.0
  make_installed beta 1.0.0
  write_conf "$TEST_TMP/conf" \
    "alpha | ex/alpha | alpha-{VERSION}.tar.gz | alpha | |" \
    "beta  | ex/beta  | beta-{VERSION}.tar.gz  | beta  | |"

  run run_untapped upgrade --yes -j 2 -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated: 2"* ]]
  grep -q '^alpha=2.0.0$' "$UNTAPPED_SHARE_DIR/installed.conf"
  grep -q '^beta=2.0.0$' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "upgrade tag-fetch failure does not block other upgrades" {
  make_pkg alpha 2.0.0
  make_installed alpha 1.0.0
  make_installed beta 1.0.0
  write_api_json ex beta v2.0.0
  write_conf "$TEST_TMP/conf" \
    "alpha | ex/alpha | alpha-{VERSION}.tar.gz | alpha | |" \
    "beta  | ex/beta  | beta-{VERSION}.tar.gz  | beta  | |"

  MOCK_CURL_FAIL='repos/ex/beta/releases/latest' run run_untapped upgrade --yes -j 2 -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not fetch latest release tag"* ]]
  [[ "$output" == *"Updated: 1"* ]]
  grep -q '^alpha=2.0.0$' "$UNTAPPED_SHARE_DIR/installed.conf"
  grep -q '^beta=1.0.0$' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "transient tag-fetch failure retries and succeeds" {
  make_pkg alpha 1.0.0
  write_conf "$TEST_TMP/conf" \
    "alpha | ex/alpha | alpha-{VERSION}.tar.gz | alpha | |"

  MOCK_CURL_FAIL_ONCE='repos/ex/alpha/releases/latest' UNTAPPED_RETRIES=1 \
    run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed: 1"* ]]
  [ -x "$UNTAPPED_BIN_DIR/alpha" ]
  attempts="$(grep -c 'releases/latest' "$FIXTURES/curl.log")"
  [ "$attempts" -eq 2 ]
}

@test "retries exhausted fails the package after bounded attempts" {
  make_pkg alpha 1.0.0
  write_conf "$TEST_TMP/conf" \
    "alpha | ex/alpha | alpha-{VERSION}.tar.gz | alpha | |"

  MOCK_CURL_FAIL='repos/ex/alpha/releases/latest' UNTAPPED_RETRIES=1 \
    run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not fetch latest release tag"* ]]
  attempts="$(grep -c 'releases/latest' "$FIXTURES/curl.log")"
  [ "$attempts" -eq 2 ]
  [ ! -e "$UNTAPPED_BIN_DIR/alpha" ]
}

@test "rejects invalid --jobs and --retries" {
  run run_untapped -j 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"--jobs must be a positive integer"* ]]

  run run_untapped --retries x
  [ "$status" -eq 1 ]
  [[ "$output" == *"--retries must be a non-negative integer"* ]]

  run run_untapped -j
  [ "$status" -eq 1 ]
  [[ "$output" == *"-j requires a number"* ]]
}

@test "help documents -j and --retries" {
  run run_untapped help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--jobs"* ]]
  [[ "$output" == *"--retries"* ]]
}
