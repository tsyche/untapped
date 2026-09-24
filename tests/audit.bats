#!/usr/bin/env bats
load test_helper
setup() {
  setup_test_env
  export PATH="$UNTAPPED_BIN_DIR:$PATH"
}
teardown() { teardown_test_env; }

make_archive() {
  mkdir -p "$TEST_TMP/stage/pkg/bin"
  printf '#!/bin/sh\necho installed\n' > "$TEST_TMP/stage/pkg/bin/demo"
  tar -czf "$TEST_TMP/demo.tar.gz" -C "$TEST_TMP/stage" pkg
  write_api_json ex demo v1.0
  write_asset demo.tar.gz "$TEST_TMP/demo.tar.gz"
}

@test "nested binary paths install from archives" {
  make_archive
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo.tar.gz | pkg/bin/demo | |'
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [ -x "$UNTAPPED_BIN_DIR/demo" ]
}

@test "copy failure cannot record a successful installation" {
  write_api_json ex demo v1.0
  write_asset demo <<< 'new binary'
  mkdir -p "$UNTAPPED_BIN_DIR/demo"
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo | demo | |'
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  run grep -q '^demo=' "$UNTAPPED_SHARE_DIR/installed.conf"
  [ "$status" -eq 1 ]
}

@test "failed extraction cannot install a partially extracted binary" {
  make_archive
  rm "$MOCK_BIN/tar"
  cat > "$MOCK_BIN/tar" <<'MOCK'
#!/bin/bash
if [[ "$1" == -x* ]]; then
  /usr/bin/tar "$@"
  exit 2
fi
exec /usr/bin/tar "$@"
MOCK
  chmod +x "$MOCK_BIN/tar"
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo.tar.gz | demo | |'
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [ ! -e "$UNTAPPED_BIN_DIR/demo" ]
}

@test "invalid package paths are rejected before installation" {
  write_api_json ex demo v1.0
  write_asset demo <<< 'untrusted'
  write_conf "$TEST_TMP/conf" '../escaped | ex/demo | demo | demo | |'
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_TMP/escaped" ]
}

@test "add rejects conf delimiter injection in package name" {
  write_api_release ex demo v1.0 demo
  write_asset demo <<< 'binary'
  run run_untapped add --yes --name $'demo\nother | ex/other' -c "$TEST_TMP/conf" ex/demo
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_TMP/conf" ]
}

@test "add and install round trip works for tar xz and versioned paths" {
  mkdir -p "$TEST_TMP/stage/demo-1.0"
  printf '#!/bin/sh\necho demo\n' > "$TEST_TMP/stage/demo-1.0/demo"
  tar -cJf "$TEST_TMP/demo.tar.xz" -C "$TEST_TMP/stage" demo-1.0
  write_api_release ex demo v1.0 demo-1.0.tar.xz
  write_asset demo-1.0.tar.xz "$TEST_TMP/demo.tar.xz"
  run run_untapped add --yes -c "$TEST_TMP/conf" ex/demo
  [ "$status" -eq 0 ]
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [ -x "$UNTAPPED_BIN_DIR/demo" ]
}

@test "version state keys are literal and release tags preserve slash and ampersand" {
  printf '#!/bin/sh\n' > "$UNTAPPED_BIN_DIR/demo.tool"
  chmod +x "$UNTAPPED_BIN_DIR/demo.tool"
  printf 'demoXtool=old\ndemo.tool=old\n' > "$UNTAPPED_SHARE_DIR/installed.conf"
  write_api_json ex demo 'vfeature/1&2'
  write_asset demo <<< 'binary'
  write_conf "$TEST_TMP/conf" 'demo.tool | ex/demo | demo | demo | |'
  run run_untapped upgrade --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  grep -Fxq 'demoXtool=old' "$UNTAPPED_SHARE_DIR/installed.conf"
  grep -Fxq 'demo.tool=feature/1&2' "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "binary-mode checksums are enforced" {
  write_api_json ex demo v1.0
  write_asset demo <<< 'binary'
  write_asset checksums.txt <<< '0000000000000000000000000000000000000000000000000000000000000000 *demo'
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo | demo | |'
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [ ! -e "$UNTAPPED_BIN_DIR/demo" ]
}

@test "indented comments and whitespace-only lines are ignored" {
  write_conf "$TEST_TMP/conf" '   # comment' $'\t' '  '
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Failed: 0'* ]]
}

@test "add preserves noncanonical platform tokens" {
  write_api_release ex demo v1.0 demo-macos-aarch64 demo-linux-x86_64
  write_asset demo-macos-aarch64 <<< 'binary'
  write_asset demo-linux-x86_64 <<< 'binary'
  cat > "$MOCK_BIN/uname" <<'MOCK'
#!/bin/sh
case "$1" in -s) echo Darwin;; -m) echo arm64;; esac
MOCK
  chmod +x "$MOCK_BIN/uname"
  run run_untapped add --yes -c "$TEST_TMP/conf" ex/demo
  [ "$status" -eq 0 ]
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [ -x "$UNTAPPED_BIN_DIR/demo" ]
}

@test "installation replaces destination symlink without overwriting its target" {
  printf 'keep me\n' > "$TEST_TMP/victim"
  ln -s "$TEST_TMP/victim" "$UNTAPPED_BIN_DIR/demo"
  write_api_json ex demo v1.0
  write_asset demo <<< 'new binary'
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo | demo | |'
  run run_untapped upgrade --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMP/victim")" = 'keep me' ]
  [ ! -L "$UNTAPPED_BIN_DIR/demo" ]
}

@test "archive symlink cannot supply a binary from outside extraction" {
  mkdir -p "$TEST_TMP/stage/pkg" "$TEST_TMP/outside"
  printf 'external\n' > "$TEST_TMP/outside/demo"
  ln -s "$TEST_TMP/outside" "$TEST_TMP/stage/pkg/bin"
  tar -czf "$TEST_TMP/demo.tar.gz" -C "$TEST_TMP/stage" pkg
  write_api_json ex demo v1.0
  write_asset demo.tar.gz "$TEST_TMP/demo.tar.gz"
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo.tar.gz | pkg/bin/demo | |'
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [[ "$output" == *'unsafe archive'* ]]
  [ ! -e "$UNTAPPED_BIN_DIR/demo" ]
}

@test "add ignores archive directories when selecting the executable" {
  mkdir -p "$TEST_TMP/stage/demo/bin"
  printf '#!/bin/sh\necho demo\n' > "$TEST_TMP/stage/demo/bin/demo"
  tar -czf "$TEST_TMP/demo.tar.gz" -C "$TEST_TMP/stage" demo
  write_api_release ex demo v1.0 demo.tar.gz
  write_asset demo.tar.gz "$TEST_TMP/demo.tar.gz"
  run run_untapped add --yes -c "$TEST_TMP/conf" ex/demo
  [ "$status" -eq 0 ]
  grep -Fq '| demo/bin/demo |' "$TEST_TMP/conf"
}

@test "add rejects Windows archives on Unix" {
  write_api_release ex demo v1.0 demo-windows-x64.zip demo-linux-x64
  write_asset demo-linux-x64 <<< 'binary'
  cat > "$MOCK_BIN/uname" <<'MOCK'
#!/bin/sh
case "$1" in -s) echo Linux;; -m) echo x86_64;; esac
MOCK
  chmod +x "$MOCK_BIN/uname"
  run run_untapped add --yes -c "$TEST_TMP/conf" ex/demo
  [ "$status" -eq 0 ]
  grep -Fq 'demo-linux-x64' "$TEST_TMP/conf"
}

@test "add rejects an empty release response with a useful error" {
  mkdir -p "$FIXTURES/api"
  printf '{}\n' > "$FIXTURES/api/ex_demo.json"
  run run_untapped add --yes ex/demo
  [ "$status" -eq 1 ]
  [[ "$output" == *'release tag'* ]]
}

@test "add only accepts GitHub URLs and bare repos" {
  write_api_release ex demo v1.0 demo
  write_asset demo <<< 'binary'
  run run_untapped add --yes -c "$TEST_TMP/conf" https://ex/demo
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_TMP/conf" ]
}

@test "destination directory symlinks cannot redirect installs" {
  mkdir "$TEST_TMP/victim-dir"
  ln -s "$TEST_TMP/victim-dir" "$UNTAPPED_BIN_DIR/demo"
  write_api_json ex demo v1.0
  write_asset demo <<< 'binary'
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo | demo | |'
  run run_untapped upgrade --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [ -z "$(ls -A "$TEST_TMP/victim-dir")" ]
}

# A real terminal exercises read and Bash 3.2 on macOS.
run_prompt() {
  export MOCK_FIXTURES="$FIXTURES"
  "$TEST_PYTHON" "$REPO_ROOT/tests/tty_prompt.py" "$UNTTAPPED_BIN" "$@" -c "$TEST_TMP/conf"
}

@test "interactive install accepts uppercase Y on system Bash" {
  write_api_json ex demo v1.0
  write_asset demo <<< 'binary'
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo | demo | |'
  run run_prompt
  [ "$status" -eq 0 ]
  [ -x "$UNTAPPED_BIN_DIR/demo" ]
}

@test "interactive add accepts uppercase Y on system Bash" {
  write_api_release ex demo v1.0 demo
  write_asset demo <<< 'binary'
  run run_prompt add ex/demo
  [ "$status" -eq 0 ]
  grep -Fq 'demo | ex/demo' "$TEST_TMP/conf"
}

@test "hostile archive paths fail without writing outside extraction" {
  export ATTACK_ARCHIVE="$TEST_TMP/attack.tar.gz" ATTACK_TARGET="$TEST_TMP/victim"
  printf 'original\n' > "$ATTACK_TARGET"
  "$TEST_PYTHON" - <<'PY'
import io, os, tarfile
with tarfile.open(os.environ['ATTACK_ARCHIVE'], 'w:gz') as archive:
    for name in (os.environ['ATTACK_TARGET'], 'demo'):
        member = tarfile.TarInfo(name)
        member.size = 7
        archive.addfile(member, io.BytesIO(b'changed'))
PY
  write_api_json ex demo v1.0
  write_asset demo.tar.gz "$ATTACK_ARCHIVE"
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo.tar.gz | demo | |'
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [ "$(cat "$ATTACK_TARGET")" = original ]
  [ ! -e "$UNTAPPED_BIN_DIR/demo" ]
}

@test "failed upgrade copy leaves installed executable and version intact" {
  printf '#!/bin/sh\necho original\n' > "$UNTAPPED_BIN_DIR/demo"
  chmod +x "$UNTAPPED_BIN_DIR/demo"
  printf 'demo=old\n' > "$UNTAPPED_SHARE_DIR/installed.conf"
  write_api_json ex demo v1.0
  write_asset demo <<< 'new binary'
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo | demo | |'
  rm "$MOCK_BIN/cp"
  cat > "$MOCK_BIN/cp" <<'MOCK'
#!/bin/bash
case "$2" in "$UNTAPPED_BIN_DIR"/*) exit 1;; esac
exec /bin/cp "$@"
MOCK
  chmod +x "$MOCK_BIN/cp"
  run run_untapped upgrade --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  grep -q original "$UNTAPPED_BIN_DIR/demo"
  grep -Fxq demo=old "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "shared validators reject seeded hostile fields and accept safe entries" {
  source "$REPO_ROOT/lib/common.sh"
  seed=71329
  for ((iteration=0; iteration<128; iteration++)); do
    seed=$(((seed * 48271) % 2147483647))
    name="demo${seed}"
    validate_entry "$name" "ex/$name" "$name-{VERSION}.tar.gz" "pkg/bin/$name" linux amd64
    case $((seed % 5)) in
      0) hostile="../$name" ;;
      1) hostile="/$name" ;;
      2) hostile="$name|other" ;;
      3) hostile="$name"$'\nother' ;;
      4) hostile="$name/../../other" ;;
    esac
    if validate_entry "$hostile" "ex/demo" demo demo '' ''; then
      echo "seed=71329 iteration=$iteration: accepted unsafe name" >&2
      return 1
    fi
    if safe_relative_path "$hostile"; then
      echo "seed=71329 iteration=$iteration: accepted unsafe path" >&2
      return 1
    fi
  done
}

@test "release metadata cannot redirect authenticated downloads to another host" {
  write_api_release ex demo v1.0 demo
  sed 's@https://github.com/ex/demo/releases/download/v1.0/demo@https://example.invalid/demo@' "$FIXTURES/api/ex_demo.json" > "$TEST_TMP/api.json"
  cp "$TEST_TMP/api.json" "$FIXTURES/api/ex_demo.json"
  write_asset demo <<< 'binary'
  export GITHUB_TOKEN=test-token
  run run_untapped add --yes -c "$TEST_TMP/conf" ex/demo
  [ "$status" -eq 1 ]
  [[ "$output" == *'refusing non-GitHub'* ]]
  [ ! -e "$TEST_TMP/conf" ]
}

@test "app upgrade copy failure preserves the previous bundle" {
  mkdir -p "$HOME/.local/opt/demo/demo.app/Contents/MacOS" "$TEST_TMP/stage/demo.app/Contents/MacOS"
  printf '#!/bin/sh\necho original\n' > "$HOME/.local/opt/demo/demo.app/Contents/MacOS/demo"
  chmod +x "$HOME/.local/opt/demo/demo.app/Contents/MacOS/demo"
  ln -s "$HOME/.local/opt/demo/demo.app/Contents/MacOS/demo" "$UNTAPPED_BIN_DIR/demo"
  printf 'demo=old\n' > "$UNTAPPED_SHARE_DIR/installed.conf"
  printf 'new binary\n' > "$TEST_TMP/stage/demo.app/Contents/MacOS/demo"
  tar -czf "$TEST_TMP/demo.tar.gz" -C "$TEST_TMP/stage" demo.app
  write_api_json ex demo v1.0
  write_asset demo.tar.gz "$TEST_TMP/demo.tar.gz"
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo.tar.gz | demo.app/Contents/MacOS/demo | |'
  rm "$MOCK_BIN/cp"
  cat > "$MOCK_BIN/cp" <<'MOCK'
#!/bin/bash
[[ "$1" != -R ]] || exit 1
exec /bin/cp "$@"
MOCK
  chmod +x "$MOCK_BIN/cp"
  run run_untapped upgrade --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  grep -q original "$UNTAPPED_BIN_DIR/demo"
  grep -Fxq demo=old "$UNTAPPED_SHARE_DIR/installed.conf"
}

@test "repo names beginning with releases remain intact" {
  write_api_release ex releases-demo v1.0 demo
  write_asset demo <<< 'binary'
  run run_untapped add --yes -c "$TEST_TMP/conf" ex/releases-demo
  [ "$status" -eq 0 ]
  grep -Fq '| ex/releases-demo |' "$TEST_TMP/conf"
}

@test "add finds app executable when package and executable names differ" {
  mkdir -p "$TEST_TMP/stage/demo.app/Contents/MacOS"
  printf 'binary\n' > "$TEST_TMP/stage/demo.app/Contents/MacOS/demo"
  tar -czf "$TEST_TMP/demo.tar.gz" -C "$TEST_TMP/stage" demo.app
  write_api_release ex demo-tools v1.0 demo.tar.gz
  write_asset demo.tar.gz "$TEST_TMP/demo.tar.gz"
  run run_untapped add --yes -c "$TEST_TMP/conf" ex/demo-tools
  [ "$status" -eq 0 ]
  grep -Fq '| demo.app/Contents/MacOS/demo |' "$TEST_TMP/conf"
}

@test "add refuses an alias of the packaged example conf" {
  mkdir -p "$TEST_TMP/repo/bin" "$TEST_TMP/repo/lib" "$TEST_TMP/repo/conf"
  cp "$REPO_ROOT/bin/untapped" "$TEST_TMP/repo/bin/"
  cp "$REPO_ROOT/lib/"*.sh "$TEST_TMP/repo/lib/"
  printf '# example\n' > "$TEST_TMP/repo/conf/untapped.conf.example"
  ln -s "$TEST_TMP/repo/conf/untapped.conf.example" "$TEST_TMP/example-alias"
  UNTTAPPED_BIN="$TEST_TMP/repo/bin/untapped"
  write_api_release ex demo v1.0 demo
  write_asset demo <<< 'binary'
  run run_untapped add --yes -c "$TEST_TMP/example-alias" ex/demo
  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_TMP/repo/conf/untapped.conf.example")" = '# example' ]
}

@test "interactive EOF declines installation" {
  write_api_json ex demo v1.0
  write_asset demo <<< 'binary'
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo | demo | |'
  export PROMPT_REPLY=$'\004'
  run run_prompt
  [ ! -e "$UNTAPPED_BIN_DIR/demo" ]
  [[ "$output" == *'user declined'* ]]
}

@test "app links must remain inside the installed package after relocation" {
  mkdir -p "$TEST_TMP/stage/pkg/deep/demo.app/Contents/MacOS" "$TEST_TMP/stage/shared"
  printf 'binary\n' > "$TEST_TMP/stage/pkg/deep/demo.app/Contents/MacOS/demo"
  ln -s ../../../shared "$TEST_TMP/stage/pkg/deep/demo.app/shared"
  tar -czf "$TEST_TMP/demo.tar.gz" -C "$TEST_TMP/stage" pkg shared
  write_api_json ex demo v1.0
  write_asset demo.tar.gz "$TEST_TMP/demo.tar.gz"
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo.tar.gz | pkg/deep/demo.app/Contents/MacOS/demo | |'
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 1 ]
  [ ! -e "$UNTAPPED_BIN_DIR/demo" ]
}

@test "safe relative links inside app bundles are preserved" {
  mkdir -p "$TEST_TMP/stage/demo.app/Contents/MacOS" "$TEST_TMP/stage/demo.app/Contents/Resources"
  printf 'binary\n' > "$TEST_TMP/stage/demo.app/Contents/MacOS/demo"
  printf 'resource\n' > "$TEST_TMP/stage/demo.app/Contents/Resources/data"
  ln -s ../Resources/data "$TEST_TMP/stage/demo.app/Contents/MacOS/data"
  tar -czf "$TEST_TMP/demo.tar.gz" -C "$TEST_TMP/stage" demo.app
  write_api_json ex demo v1.0
  write_asset demo.tar.gz "$TEST_TMP/demo.tar.gz"
  write_conf "$TEST_TMP/conf" 'demo | ex/demo | demo.tar.gz | demo.app/Contents/MacOS/demo | |'
  run run_untapped --yes -c "$TEST_TMP/conf"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.local/opt/demo/demo.app/Contents/MacOS/data")" = resource ]
}
