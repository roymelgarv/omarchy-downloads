#!/usr/bin/env bats
# Tests for the bin/ helper scripts. Pure-logic scripts (stats, uri encoding)
# are tested for real; scripts needing a live desktop (clipboard, D-Bus file
# manager, trash daemon) are skipped when the environment lacks them.

setup() {
  BIN="$BATS_TEST_DIRNAME/../bin"
  FIXTURE="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "downloads-stats reports bytes and file count as JSON" {
  printf 'aaaa' > "$FIXTURE/a.txt"          # 4 bytes
  printf 'bbbbbbbb' > "$FIXTURE/b.bin"      # 8 bytes
  mkdir "$FIXTURE/sub"
  printf 'cc' > "$FIXTURE/sub/c.txt"        # 2 bytes, nested

  run "$BIN/downloads-stats" "$FIXTURE"
  [ "$status" -eq 0 ]
  count="$(echo "$output" | jq .count)"
  bytes="$(echo "$output" | jq .bytes)"
  [ "$count" -eq 3 ]
  [ "$bytes" -eq 14 ]
}

@test "downloads-stats excludes dotfiles and dot-directories, matching the panel's file list" {
  printf 'aaaa' > "$FIXTURE/a.txt"          # 4 bytes, counted
  printf 'hidden' > "$FIXTURE/.secret"      # not counted
  mkdir "$FIXTURE/.cache"
  printf 'nope' > "$FIXTURE/.cache/x.txt"   # not counted

  run "$BIN/downloads-stats" "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq .count)" -eq 1 ]
  [ "$(echo "$output" | jq .bytes)" -eq 4 ]
}

@test "downloads-stats handles an empty folder" {
  run "$BIN/downloads-stats" "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq .count)" -eq 0 ]
}

@test "downloads-stats fails cleanly on a missing folder" {
  run "$BIN/downloads-stats" "$FIXTURE/nope"
  [ "$status" -ne 0 ]
}

@test "downloads-copy encodes the file path as a percent-encoded file URI" {
  touch "$FIXTURE/my file (1).pdf"
  run "$BIN/downloads-copy" --print-uri "$FIXTURE/my file (1).pdf"
  [ "$status" -eq 0 ]
  [[ "$output" == "file://$FIXTURE/my%20file%20%281%29.pdf" ]]
}

@test "downloads-copy percent-encodes non-ASCII bytes (UTF-8), not code points" {
  touch "$FIXTURE/café 中.pdf"
  run "$BIN/downloads-copy" --print-uri "$FIXTURE/café 中.pdf"
  [ "$status" -eq 0 ]
  [[ "$output" == "file://$FIXTURE/caf%C3%A9%20%E4%B8%AD.pdf" ]]
}

@test "downloads-copy fails on a missing file" {
  run "$BIN/downloads-copy" --print-uri "$FIXTURE/ghost.pdf"
  [ "$status" -ne 0 ]
}

@test "downloads-trash moves a file to the trash" {
  command -v gio >/dev/null || skip "gio not available"
  # gio refuses to trash from system mounts like /tmp, so the fixture must
  # live on the home filesystem (as the real Downloads folder does).
  home_fixture="$(mktemp -d "$HOME/.cache/omarchy-downloads-test.XXXXXX")" || skip "cannot create home tmpdir"
  touch "$home_fixture/junk.txt"
  run "$BIN/downloads-trash" "$home_fixture/junk.txt"
  rmdir "$home_fixture" 2>/dev/null || rm -rf "$home_fixture"
  if [ "$status" -ne 0 ] && [[ "$output" == *"not supported"* ]]; then
    skip "trash not supported on this filesystem"
  fi
  [ "$status" -eq 0 ]
}

@test "downloads-trash fails on a missing file" {
  run "$BIN/downloads-trash" "$FIXTURE/ghost.txt"
  [ "$status" -ne 0 ]
}

@test "downloads-reveal fails without an argument" {
  run "$BIN/downloads-reveal"
  [ "$status" -ne 0 ]
}
