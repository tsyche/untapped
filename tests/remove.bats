#!/usr/bin/env bats
# untapped remove: conf line, binary, version state, .app bundle, symlink safety.

load test_helper

setup() {
  setup_test_env
  export PATH="$UNTAPPED_BIN_DIR:$PATH"
}

teardown() {
  teardown_test_env
}

# make_installed <name> [version] — binary in bin dir + conf line + state line.
make_installed() {
  local n="$1" v="${2:-1.2.3}"
  printf '#!/bin/sh\necho %s\n' "$n" > "$UNTAPPED_BIN_DIR/$n"
  chmod +x "$UNTAPPED_BIN_DIR/$n"
  printf '%s | ex/%s | %s-{VERSION}.tar.gz | %s | |\n' "$n" "$n" "$n" "$n" >> "$TEST_TMP/conf"
  printf '%s=%s\n' "$n" "$v" >> "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "remove drops conf line, binary, and version state" {
  printf '# header\nkeepme | ex/keepme | keepme-{VERSION}.tar.gz | keepme | |\n' > "$TEST_TMP/conf"
  make_installed demobin 1.2.3
  printf 'keepme=9.9.9\n' >> "$UNTAPPED_SHARE_DIR/installed.conf"

  run run_untapped remove --yes -c "$TEST_TMP/conf" demobin
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed demobin"* ]]
  [[ "$output" == *"Removed: 1  Failed: 0"* ]]
  [ ! -e "$UNTAPPED_BIN_DIR/demobin" ]
  run grep -q '^demobin' "$TEST_TMP/conf"
  [ "$status" -ne 0 ]
  grep -q '^# header$' "$TEST_TMP/conf"
  grep -q '^keepme | ex/keepme' "$TEST_TMP/conf"
  run grep -q '^demobin=' "$UNTAPPED_SHARE_DIR/installed.conf"
  [ "$status" -ne 0 ]
  grep -q '^keepme=9.9.9$' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "remove accepts multiple names in one run" {
  make_installed onebin
  make_installed twobin
  printf 'thirdbin | ex/thirdbin | t-{VERSION}.tar.gz | thirdbin | |\n' >> "$TEST_TMP/conf"
  printf 'thirdbin=0.1.0\n' >> "$UNTAPPED_SHARE_DIR/installed.conf"

  run run_untapped remove --yes -c "$TEST_TMP/conf" onebin twobin thirdbin
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed: 3  Failed: 0"* ]]
  [ ! -e "$UNTAPPED_BIN_DIR/onebin" ]
  [ ! -e "$UNTAPPED_BIN_DIR/twobin" ]
  run grep -qE '^(onebin|twobin|thirdbin) \|' "$TEST_TMP/conf"
  [ "$status" -ne 0 ]
}

@test "remove unknown package fails and changes nothing" {
  make_installed demobin

  run run_untapped remove --yes -c "$TEST_TMP/conf" nosuch
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in conf: nosuch"* ]]
  [ -x "$UNTAPPED_BIN_DIR/demobin" ]
  grep -q '^demobin |' "$TEST_TMP/conf"
  grep -q '^demobin=' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "remove dry-run changes nothing" {
  make_installed demobin

  run run_untapped remove --dry-run --yes -c "$TEST_TMP/conf" demobin
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove demobin"* ]]
  [[ "$output" == *"[dry-run] nothing changed"* ]]
  [ -x "$UNTAPPED_BIN_DIR/demobin" ]
  grep -q '^demobin |' "$TEST_TMP/conf"
  grep -q '^demobin=' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "remove without --yes fails when stdin is not a TTY" {
  make_installed demobin

  run run_untapped remove -c "$TEST_TMP/conf" demobin
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a TTY"* ]] || [[ "$output" == *"--yes"* ]]
  [ -x "$UNTAPPED_BIN_DIR/demobin" ]
}

run_remove_prompt() {
  export MOCK_FIXTURES="$FIXTURES"
  "$TEST_PYTHON" "$REPO_ROOT/tests/tty_prompt.py" "$UNTTAPPED_BIN" "$@"
}

@test "interactive remove prompt declined leaves everything" {
  make_installed demobin
  PROMPT_REPLY=$'n\n' run run_remove_prompt remove -c "$TEST_TMP/conf" demobin
  [ "$status" -eq 1 ]
  [[ "$output" == *"Remove 1 package(s)"* ]]
  [[ "$output" == *"aborted; nothing changed"* ]]
  [ -x "$UNTAPPED_BIN_DIR/demobin" ]
  grep -q '^demobin |' "$TEST_TMP/conf"
  grep -q '^demobin=' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "interactive remove prompt accepted removes package" {
  make_installed demobin
  PROMPT_REPLY=$'y\n' run run_remove_prompt remove -c "$TEST_TMP/conf" demobin
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed demobin"* ]]
  [ ! -e "$UNTAPPED_BIN_DIR/demobin" ]
  run grep -q '^demobin' "$TEST_TMP/conf"
  [ "$status" -ne 0 ]
}

@test "remove writes through conf symlink and keeps the link" {
  real="$TEST_TMP/real-conf"
  link="$TEST_TMP/conf-link"
  printf 'keepme | ex/keepme | keepme-{VERSION}.tar.gz | keepme | |\n' > "$real"
  make_installed demobin
  # make_installed appends to $TEST_TMP/conf; copy demobin line into real conf
  grep '^demobin' "$TEST_TMP/conf" >> "$real"
  ln -s "$real" "$link"

  run run_untapped remove --yes -c "$link" demobin
  [ "$status" -eq 0 ]
  [ -L "$link" ]
  run grep -q '^demobin' "$link"
  [ "$status" -ne 0 ]
  grep -q '^keepme' "$real"
  [ ! -e "$UNTAPPED_BIN_DIR/demobin" ]
}

@test "remove leaves foreign PATH binary alone" {
  printf '#!/bin/sh\necho foreign\n' > "$MOCK_BIN/foreignbin"
  chmod +x "$MOCK_BIN/foreignbin"
  write_conf "$TEST_TMP/conf" \
    "foreignbin | ex/foreignbin | f-{VERSION}.tar.gz | foreignbin | |"
  printf 'foreignbin=1.0.0\n' > "$UNTAPPED_SHARE_DIR/installed.conf"

  run run_untapped remove --yes -c "$TEST_TMP/conf" foreignbin
  [ "$status" -eq 0 ]
  [[ "$output" == *"not managed by untapped"* ]]
  [ -x "$MOCK_BIN/foreignbin" ]
  run grep -q '^foreignbin' "$TEST_TMP/conf"
  [ "$status" -ne 0 ]
  run grep -q '^foreignbin=' "$UNTAPPED_SHARE_DIR/installed.conf"
  [ "$status" -ne 0 ]
}

@test "remove cleans .app bundle under ~/.local/opt" {
  bundle="$HOME/.local/opt/demo/demo.app/Contents/MacOS"
  mkdir -p "$bundle"
  printf '#!/bin/sh\necho demo\n' > "$bundle/demo"
  chmod +x "$bundle/demo"
  ln -s "$bundle/demo" "$UNTAPPED_BIN_DIR/demo"
  write_conf "$TEST_TMP/conf" \
    "demo | ex/demo | demo.tar.gz | demo.app/Contents/MacOS/demo | darwin |"
  printf 'demo=0.1.0\n' > "$UNTAPPED_SHARE_DIR/installed.conf"

  run run_untapped remove --yes -c "$TEST_TMP/conf" demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"bundle"* ]]
  [ ! -e "$UNTAPPED_BIN_DIR/demo" ]
  [ ! -d "$HOME/.local/opt/demo" ]
  run grep -q '^demo' "$TEST_TMP/conf"
  [ "$status" -ne 0 ]
  run grep -q '^demo=' "$UNTAPPED_SHARE_DIR/installed.conf"
  [ "$status" -ne 0 ]
}

@test "remove reports absent binary but still drops conf and state" {
  write_conf "$TEST_TMP/conf" \
    "ghostbin | ex/ghostbin | g-{VERSION}.tar.gz | ghostbin | |"
  printf 'ghostbin=0.9.0\n' > "$UNTAPPED_SHARE_DIR/installed.conf"

  run run_untapped remove --yes -c "$TEST_TMP/conf" ghostbin
  [ "$status" -eq 0 ]
  [[ "$output" == *"binary not installed"* ]]
  [[ "$output" == *"Removed: 1  Failed: 0"* ]]
  run grep -q '^ghostbin' "$TEST_TMP/conf"
  [ "$status" -ne 0 ]
  run grep -q '^ghostbin=' "$UNTAPPED_SHARE_DIR/installed.conf"
  [ "$status" -ne 0 ]
}

@test "remove refuses the packaged example conf" {
  run run_untapped remove --yes -c "$REPO_ROOT/conf/untapped.conf.example" usql
  [ "$status" -eq 1 ]
  [[ "$output" == *"packaged example"* ]]
}

@test "remove without a name prints usage" {
  run run_untapped remove
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "remove rejects invalid package names" {
  run run_untapped remove --yes -c "$TEST_TMP/conf" "../evil"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid package name"* ]]
}

@test "help mentions remove" {
  run run_untapped help
  [ "$status" -eq 0 ]
  [[ "$output" == *"untapped remove"* ]]
}

@test "help remove shows remove usage" {
  run run_untapped help remove
  [ "$status" -eq 0 ]
  [[ "$output" == *"untapped remove"* ]]
  [[ "$output" == *"<name>..."* ]]
}
