#!/usr/bin/env bats
# untapped lint (conf validation) and untapped why (single-entry debug).

load test_helper

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "lint accepts valid GitHub and generic entries" {
  conf="$TEST_TMP/conf"
  write_conf "$conf" \
    'tool | o/r | tool-{VERSION}.tar.gz | tool | | | |' \
    'gen | https://dl.example.com/latest | https://cdn.example.com/g-{VERSION}-{OS}-{ARCH}.tar.gz | gen | darwin | arm64 | |'

  run run_untapped lint -c "$conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lint: 2 entries, 0 errors"* ]]
}

@test "lint reports each problem with its line number" {
  conf="$TEST_TMP/conf"
  write_conf "$conf" \
    '# comment line' \
    '' \
    'bad_name! | o/r | a.tar.gz | bad' \
    'tname | o/r | a.tar.gz | tname | solaris | | |' \
    'tool | o/r | a.tar.gz | tool | | badarch | |' \
    'ghx | notarepo | /abs.zip | ghx | | | |' \
    'gen | https://x.example/v | https://x.example/g-1.0.tar.gz | gen | | | |' \
    'tool | o/r2 | b.tar.gz | tool | | | |'

  run run_untapped lint -c "$conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 3: invalid package name"* ]]
  [[ "$output" == *"line 4: invalid os_filter 'solaris'"* ]]
  [[ "$output" == *"line 5: invalid arch_filter 'badarch'"* ]]
  [[ "$output" == *"line 6: GitHub source must be owner/repo"* ]]
  [[ "$output" == *"line 6: asset must be a plain filename"* ]]
  [[ "$output" == *"line 7: asset_pattern has no {VERSION} placeholder"* ]]
  [[ "$output" == *"line 8: duplicate package name: 'tool'"* ]]
  [[ "$output" == *"lint: 6 entries, 7 errors"* ]]
}

@test "lint flags invalid version_rule regex" {
  conf="$TEST_TMP/conf"
  write_conf "$conf" 'gen | https://x.example/v | https://x.example/g-{VERSION}.tar.gz | gen | | | | (['

  run run_untapped lint -c "$conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid version_rule regex"* ]]
}

@test "lint on comments and blanks only succeeds" {
  conf="$TEST_TMP/conf"
  write_conf "$conf" '# just a comment' '' '   '

  run run_untapped lint -c "$conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lint: 0 entries, 0 errors"* ]]
}

@test "why shows the conf entry and PATH status" {
  conf="$TEST_TMP/conf"
  write_conf "$conf" \
    'tool | o/r | tool-{VERSION}.tar.gz | tool | | | |' \
    'other | p/q | other.zip | other | | | |'

  run run_untapped why tool -c "$conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"package:  tool"* ]]
  [[ "$output" == *"conf:     $conf:1"* ]]
  [[ "$output" == *"source:   o/r"* ]]
  [[ "$output" == *"asset:    tool-{VERSION}.tar.gz"* ]]
  [[ "$output" == *"filters:  none"* ]]
  [[ "$output" == *"status:   not on PATH"* ]]
}

@test "why reports the installed path and recorded version" {
  conf="$TEST_TMP/conf"
  write_conf "$conf" 'tool | o/r | tool-{VERSION}.tar.gz | tool | | | |'
  mkdir -p "$TEST_TMP/shim"
  printf '#!/bin/sh\necho tool\n' > "$TEST_TMP/shim/tool"
  chmod +x "$TEST_TMP/shim/tool"
  printf 'tool=1.4.2\n' > "$UNTAPPED_SHARE_DIR/installed.conf"

  PATH="$TEST_TMP/shim:$PATH" run run_untapped why tool -c "$conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status:   installed: $TEST_TMP/shim/tool (1.4.2)"* ]]
}

@test "why reports a filtered entry without consulting PATH" {
  conf="$TEST_TMP/conf"
  other=linux
  [[ "$(uname -s)" == Linux ]] && other=darwin
  write_conf "$conf" "tool | o/r | tool.tar.gz | tool | $other | | |"

  run run_untapped why tool -c "$conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"filters:  os=$other"* ]]
  [[ "$output" == *"status:   not applied on"* ]]
  [[ "$output" == *"(filtered by os=$other)"* ]]
}

@test "why exits 1 for a package that is not in conf" {
  conf="$TEST_TMP/conf"
  write_conf "$conf" 'tool | o/r | tool.tar.gz | tool | | | |'

  run run_untapped why ghost -c "$conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"package not in conf: ghost"* ]]
  [[ "$output" == *"untapped list"* ]]
}

@test "why without a name prints an error" {
  conf="$TEST_TMP/conf"
  write_conf "$conf" 'tool | o/r | tool.tar.gz | tool | | | |'

  run run_untapped why -c "$conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"why requires a package name"* ]]
}

@test "help documents lint and why" {
  run run_untapped help
  [ "$status" -eq 0 ]
  [[ "$output" == *"untapped lint"* ]]
  [[ "$output" == *"untapped why <name>"* ]]
}
