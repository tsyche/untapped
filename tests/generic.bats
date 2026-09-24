#!/usr/bin/env bats
# Generic (non-GitHub) HTTPS sources: conf-driven installs from anywhere.

load test_helper

setup() {
  setup_test_env
  export PATH="$UNTAPPED_BIN_DIR:$PATH"
}

teardown() {
  teardown_test_env
}

# make_tgz <name> <version> — release tarball fixture file in TEST_TMP
make_tgz() {
  local n="$1" v="$2"
  local stage
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho %s\n' "$n" > "$stage/$n"
  chmod +x "$stage/$n"
  tar -czf "$TEST_TMP/$n-$v.tar.gz" -C "$stage" "$n"
  rm -rf "$stage"
}

@test "installs from a generic HTTPS source with default version extraction" {
  write_host_text 'https://dl.example.com/tool/latest' 'tool 1.2.3 is out'
  make_tgz tool 1.2.3
  write_host_file 'https://cdn.example.com/tool/1.2.3/tool-1.2.3.tar.gz' "$TEST_TMP/tool-1.2.3.tar.gz"
  write_conf "$TEST_TMP/conf" \
    'tool | https://dl.example.com/tool/latest | https://cdn.example.com/tool/{VERSION}/tool-{VERSION}.tar.gz | tool | | | |'

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed: 1"* ]]
  [ -x "$UNTAPPED_BIN_DIR/tool" ]
  grep -q '^tool=1.2.3$' "$UNTAPPED_SHARE_DIR/installed.conf"

  # Exactly version page + asset download; no github.com, no auth headers.
  [ "$(grep -c '^https://' "$FIXTURES/curl.log")" -eq 2 ]
  run grep 'github.com' "$FIXTURES/curl.log"
  [ "$status" -ne 0 ]
  run grep 'hdr:' "$FIXTURES/curl.log"
  [ "$status" -ne 0 ]
}

@test "version_rule picks the version when the page has decoy numbers" {
  write_host_text 'https://dl.example.com/tool/latest' 'Copyright 2024.1 — Tool version 5.6.7 released'
  make_tgz tool 5.6.7
  write_host_file 'https://cdn.example.com/tool/5.6.7/tool-5.6.7.tar.gz' "$TEST_TMP/tool-5.6.7.tar.gz"
  write_conf "$TEST_TMP/conf" \
    'tool | https://dl.example.com/tool/latest | https://cdn.example.com/tool/{VERSION}/tool-{VERSION}.tar.gz | tool | | | | [0-9]+\.[0-9]+\.[0-9]+'

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  grep -q '^tool=5.6.7$' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "version_rule may contain regex alternation (pipe in last conf field)" {
  write_host_text 'https://dl.example.com/tool/latest' 'build-42'
  make_tgz tool build-42
  write_host_file 'https://cdn.example.com/tool/build-42/tool-build-42.tar.gz' "$TEST_TMP/tool-build-42.tar.gz"
  write_conf "$TEST_TMP/conf" \
    'tool | https://dl.example.com/tool/latest | https://cdn.example.com/tool/{VERSION}/tool-{VERSION}.tar.gz | tool | | | | [0-9]+\.[0-9]+\.[0-9]+|build-[0-9]+'

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  grep -q '^tool=build-42$' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "generic upgrade detects a newer version" {
  write_host_text 'https://dl.example.com/tool/latest' 'tool 1.0.0'
  make_tgz tool 1.0.0
  write_host_file 'https://cdn.example.com/tool/1.0.0/tool-1.0.0.tar.gz' "$TEST_TMP/tool-1.0.0.tar.gz"
  write_conf "$TEST_TMP/conf" \
    'tool | https://dl.example.com/tool/latest | https://cdn.example.com/tool/{VERSION}/tool-{VERSION}.tar.gz | tool | | | |'

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  grep -q '^tool=1.0.0$' "$UNTAPPED_SHARE_DIR/installed.conf"

  write_host_text 'https://dl.example.com/tool/latest' 'tool 2.0.0'
  make_tgz tool 2.0.0
  write_host_file 'https://cdn.example.com/tool/2.0.0/tool-2.0.0.tar.gz' "$TEST_TMP/tool-2.0.0.tar.gz"

  run run_untapped upgrade --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated: 1"* ]]
  grep -q '^tool=2.0.0$' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "version_pin on a generic source installs the pin without discovery" {
  make_tgz tool 9.9.9
  write_host_file 'https://cdn.example.com/tool/9.9.9/tool-9.9.9.tar.gz' "$TEST_TMP/tool-9.9.9.tar.gz"
  write_conf "$TEST_TMP/conf" \
    'tool | https://dl.example.com/tool/latest | https://cdn.example.com/tool/{VERSION}/tool-{VERSION}.tar.gz | tool | | | 9.9.9 |'

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  grep -q '^tool=9.9.9$' "$UNTAPPED_SHARE_DIR/installed.conf"
  # No version page was ever fetched (no fixture exists — it must not ask).
  run grep 'dl.example.com' "$FIXTURES/curl.log"
  [ "$status" -ne 0 ]
}

@test "generic version fetch failure reports could not fetch latest version" {
  write_conf "$TEST_TMP/conf" \
    'tool | https://dl.example.com/tool/latest | https://cdn.example.com/tool/{VERSION}/tool-{VERSION}.tar.gz | tool | | | |'

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not fetch latest version"* ]]
  [[ "$output" == *"Failed: 1"* ]]
}

@test "rejects invalid generic entries: http scheme, non-URL pattern, bad regex" {
  write_conf "$TEST_TMP/conf" \
    'a | http://dl.example.com/latest | https://cdn.example.com/a.tar.gz | a | | | |' \
    'b | https://dl.example.com/b | not-a-url.tar.gz | b | | | |' \
    'c | https://dl.example.com/c | https://cdn.example.com/c-{VERSION}.tar.gz | c | | | | ([0-9]' \
    'd | ex/demo | https://cdn.example.com/d-{VERSION}.tar.gz | d | | | |'

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [ "$(grep -c 'invalid conf entry' <<< "$output")" -eq 4 ]
}

@test "installs a bare binary (no archive) from a generic URL" {
  write_host_text 'https://dl.example.com/bare/latest' 'bare 0.5.0'
  printf '#!/bin/sh\necho bare\n' > "$TEST_TMP/bare-0.5.0"
  chmod +x "$TEST_TMP/bare-0.5.0"
  write_host_file 'https://dl.example.com/bare-0.5.0' "$TEST_TMP/bare-0.5.0"
  write_conf "$TEST_TMP/conf" \
    'bare | https://dl.example.com/bare/latest | https://dl.example.com/bare-{VERSION} | bare | | | |'

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed: 1"* ]]
  [ -x "$UNTAPPED_BIN_DIR/bare" ]
  grep -q '^bare=0.5.0$' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "GITHUB_TOKEN goes to GitHub hosts only, never generic hosts" {
  make_tgz ghpkg 1.0.0
  write_api_json ex ghpkg v1.0.0
  write_asset ghpkg-1.0.0.tar.gz "$TEST_TMP/ghpkg-1.0.0.tar.gz"
  write_host_text 'https://dl.example.com/tool/latest' 'tool 1.2.3'
  make_tgz tool 1.2.3
  write_host_file 'https://cdn.example.com/tool/1.2.3/tool-1.2.3.tar.gz' "$TEST_TMP/tool-1.2.3.tar.gz"
  write_conf "$TEST_TMP/conf" \
    'tool | https://dl.example.com/tool/latest | https://cdn.example.com/tool/{VERSION}/tool-{VERSION}.tar.gz | tool | | | |' \
    'ghpkg | ex/ghpkg | ghpkg-{VERSION}.tar.gz | ghpkg | | | |'
  export GITHUB_TOKEN=test-token

  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed: 2"* ]]

  # GitHub requests carry the bearer header...
  grep -A1 '^https://api.github.com' "$FIXTURES/curl.log" | grep -q 'hdr: Authorization: Bearer test-token'
  # ...generic ones never do.
  run grep -A1 -E '^https://(dl|cdn)\.example\.com' "$FIXTURES/curl.log"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Authorization"* ]]
}

@test "list and doctor survive a version_rule with spaces and pipes" {
  write_conf "$TEST_TMP/conf" \
    'tool | https://dl.example.com/tool/latest | https://cdn.example.com/tool/{VERSION}/tool-{VERSION}.tar.gz | tool | | | | release [0-9.]+|build-[0-9]+'

  run run_untapped list -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tool"* ]]

  run run_untapped doctor -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 configured"* ]]
}
