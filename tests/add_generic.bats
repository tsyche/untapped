#!/usr/bin/env bats
# untapped add with a non-GitHub version-page URL (generic source flow).

load test_helper

setup() {
  setup_test_env
  SRC_URL="https://dl.example.com/tool/latest"
  host_os=darwin
  [[ "$(uname -s)" == Linux ]] && host_os=linux
  host_arch=arm64
  [[ "$(uname -m)" == x86_64 ]] && host_arch=amd64
  ASSET_URL="https://cdn.example.com/tool/1.4.2/tool-1.4.2-${host_os}-${host_arch}.tar.gz"
}

teardown() {
  teardown_test_env
}

write_generic_tool() {
  local stage
  stage="$(mktemp -d)"
  printf '#!/bin/sh\necho tool\n' > "$stage/tool"
  chmod +x "$stage/tool"
  tar -czf "$TEST_TMP/tool.tgz" -C "$stage" tool
  rm -rf "$stage"
  write_host_text "$SRC_URL" 'tool 1.4.2 is out'
  write_host_file "$ASSET_URL" "$TEST_TMP/tool.tgz"
}

run_add_prompt() {
  export MOCK_FIXTURES="$FIXTURES"
  "$TEST_PYTHON" "$REPO_ROOT/tests/tty_prompt.py" "$UNTTAPPED_BIN" "$@"
}

@test "generic add appends derived conf line with --asset URL" {
  write_generic_tool
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --yes -c "$conf" --asset "$ASSET_URL" "$SRC_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Version: 1.4.2"* ]]
  [[ "$output" == *"added tool"* ]]
  awk -F'|' '
    {for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)}
    $1 == "tool" && $2 == src && NF == 8 &&
      $3 == "https://cdn.example.com/tool/{VERSION}/tool-{VERSION}-{OS}-{ARCH}.tar.gz" &&
      $4 == "tool" && $5 == "" && $6 == "" && $7 == "" && $8 == "" { ok = 1 }
    END { exit !ok }' src="$SRC_URL" "$conf"
}

@test "generic add --dry-run prints the line without writing" {
  write_generic_tool
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --dry-run --yes -c "$conf" --asset "$ASSET_URL" "$SRC_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] conf not modified"* ]]
  [[ "$output" == *"{VERSION}"* ]]
  [ ! -s "$conf" ]
}

@test "generic add prints a template when the version page is unreachable" {
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --yes -c "$conf" --asset "$ASSET_URL" "$SRC_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not fetch version page"* ]]
  [[ "$output" == *"conf line (edit"* ]]
  [[ "$output" == *"$SRC_URL"* ]]
  [ ! -s "$conf" ]
}

@test "generic add without TTY prints a template instead of prompting" {
  write_host_text "$SRC_URL" 'tool 1.4.2 is out'
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add -c "$conf" "$SRC_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stdin is not a TTY"* ]]
  [[ "$output" == *"conf line (edit"* ]]
  [[ "$output" == *"--asset"* ]]
  [ ! -s "$conf" ]
}

@test "generic add rejects a download URL for another platform" {
  write_host_text "$SRC_URL" 'tool 1.4.2 is out'
  other_os=linux
  [[ "$(uname -s)" == Linux ]] && other_os=darwin
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --yes -c "$conf" \
    --asset "https://cdn.example.com/tool/1.4.2/tool-1.4.2-${other_os}-amd64.tar.gz" \
    "$SRC_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"looks like"* ]]
  [[ "$output" == *"conf line (edit"* ]]
  [ ! -s "$conf" ]
}

@test "generic add surfaces a template when the download 404s" {
  write_generic_tool
  conf="$TEST_TMP/conf"
  : > "$conf"
  export MOCK_CURL_FAIL=cdn.example.com

  run run_untapped add --yes -c "$conf" --asset "$ASSET_URL" "$SRC_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"download failed"* ]]
  [[ "$output" == *"conf line (edit"* ]]
  [ ! -s "$conf" ]
}

@test "generic add derives the name from the version page path" {
  write_generic_tool
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --yes -c "$conf" --asset "$ASSET_URL" "$SRC_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name:    tool"* ]]
  grep -q '^tool |' "$conf"
}

@test "generic add prompts for the download URL over a TTY" {
  write_generic_tool
  conf="$TEST_TMP/conf"
  : > "$conf"

  PROMPT_REPLY_URL="$ASSET_URL"$'\n' PROMPT_REPLY=$'Y\n' \
    run run_add_prompt add -c "$conf" "$SRC_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Download URL for this release"* ]]
  [[ "$output" == *"added tool"* ]]
  grep -Fq "$SRC_URL" "$conf"
}

@test "one-shot add from a direct download URL discovers the source dir" {
  write_generic_tool
  write_host_text "https://cdn.example.com/tool" 'tool 1.4.2 is out'
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --yes -c "$conf" "$ASSET_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Source:  https://cdn.example.com/tool"* ]]
  [[ "$output" == *"Version: 1.4.2"* ]]
  [[ "$output" == *"Name:    tool"* ]]
  awk -F'|' '
    {for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)}
    $1 == "tool" && $2 == "https://cdn.example.com/tool" && NF == 8 &&
      $3 == "https://cdn.example.com/tool/{VERSION}/tool-{VERSION}-{OS}-{ARCH}.tar.gz" &&
      $4 == "tool" && $5 == "" && $6 == "" { ok = 1 }
    END { exit !ok }' "$conf"
}

@test "one-shot add prints a template when no version source is discoverable" {
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --yes -c "$conf" "$ASSET_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not discover a version source"* ]]
  [[ "$output" == *"(version-page URL)"* ]]
  [[ "$output" == *"{VERSION}/tool-{VERSION}-{OS}-{ARCH}.tar.gz"* ]]
  [ ! -s "$conf" ]
}

@test "one-shot add rejects another platform's download URL early" {
  write_host_text "$SRC_URL" 'tool 1.4.2 is out'
  other_os=linux
  [[ "$(uname -s)" == Linux ]] && other_os=darwin
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --yes -c "$conf" \
    "https://cdn.example.com/tool/1.4.2/tool-1.4.2-${other_os}-amd64.tar.gz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"looks like"* ]]
  [ ! -s "$conf" ]
}

@test "one-shot add prompts for a version page when the parent dir is unusable" {
  write_generic_tool
  write_host_text "https://dl.example.com/tool/versions" 'tool 1.4.2 is out'
  conf="$TEST_TMP/conf"
  : > "$conf"

  PROMPT_REPLY_PAGE="https://dl.example.com/tool/versions"$'\n' PROMPT_REPLY=$'Y\n' \
    run run_add_prompt add -c "$conf" "$ASSET_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Version page URL"* ]]
  [[ "$output" == *"Source:  https://dl.example.com/tool/versions"* ]]
  [[ "$output" == *"added tool"* ]]
  grep -Fq 'https://dl.example.com/tool/versions' "$conf"
}

@test "generic add lists scraped candidates and takes the selected one" {
  write_generic_tool
  page="tool 1.4.2 is out
<a href=\"https://cdn.example.com/tool/1.4.2/tool-9.9.9.zip\">nope</a>
<a href='$ASSET_URL'>good</a>
<a href=\"/tool/1.4.2/tool-1.4.2-other.tar.gz\">rel</a>"
  write_host_text "$SRC_URL" "$page"
  conf="$TEST_TMP/conf"
  : > "$conf"

  PROMPT_REPLY_SELECT="2"$'\n' PROMPT_REPLY=$'Y\n' \
    run run_add_prompt add -c "$conf" "$SRC_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Candidates found on $SRC_URL"* ]]
  [[ "$output" == *"2) $ASSET_URL"* ]]
  [[ "$output" == *"https://dl.example.com/tool/1.4.2/tool-1.4.2-other.tar.gz"* ]]
  [[ "$output" == *"added tool"* ]]
  grep -Fq "$SRC_URL" "$conf"
}

@test "generic add --yes auto-picks the best candidate" {
  write_generic_tool
  page="tool 1.4.2 is out
<a href=\"https://cdn.example.com/tool/1.4.2/tool-9.9.9.zip\">nope</a>
<a href=\"$ASSET_URL\">good</a>"
  write_host_text "$SRC_URL" "$page"
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add --yes -c "$conf" "$SRC_URL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Candidates found on $SRC_URL"* ]]
  [[ "$output" == *"added tool"* ]]
  awk -F'|' '
    {for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)}
    $1 == "tool" && $2 == src && NF == 8 &&
      $3 == "https://cdn.example.com/tool/{VERSION}/tool-{VERSION}-{OS}-{ARCH}.tar.gz" &&
      $4 == "tool" { ok = 1 }
    END { exit !ok }' src="$SRC_URL" "$conf"
}

@test "generic add without TTY prints candidates and a template" {
  write_generic_tool
  page="tool 1.4.2 is out
<a href=\"$ASSET_URL\">good</a>"
  write_host_text "$SRC_URL" "$page"
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add -c "$conf" "$SRC_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Candidates found on $SRC_URL"* ]]
  [[ "$output" == *"stdin is not a TTY"* ]]
  [[ "$output" == *"conf line (edit"* ]]
  [ ! -s "$conf" ]
}

@test "generic add reports no viable candidates before falling back" {
  write_host_text "$SRC_URL" 'tool 1.4.2 is out'
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add -c "$conf" "$SRC_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no viable candidates found on $SRC_URL"* ]]
  [[ "$output" == *"conf line (edit"* ]]
  [ ! -s "$conf" ]
}

@test "version-page URL ending in a bare version dir goes to the page flow" {
  u="https://dl.example.com/tool/1.4.2/"
  write_host_text "$u" 'tool 1.4.2 is out'
  conf="$TEST_TMP/conf"
  : > "$conf"

  run run_untapped add -c "$conf" "$u"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no viable candidates found on $u"* ]]
  [[ "$output" != *"invalid asset filename"* ]]
  [[ "$output" == *"conf line (edit"* ]]
  [[ "$output" == *"tool | $u |"* ]]
  [ ! -s "$conf" ]
}
