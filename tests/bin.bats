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

# The exclusion must apply to the part of the path below the watched folder,
# not the whole path: a folder that itself lives under a dot-directory (a
# Syncthing/Nextcloud tree, ~/.local/share/downloads) is a legal setting for
# the `folder` option, and every file under it used to be excluded — the hero
# read "0 B · 0 files" over a list the panel was still showing.
@test "downloads-stats counts files when the watched folder is inside a dot-directory" {
  deep="$FIXTURE/.local/share/Downloads"
  mkdir -p "$deep"
  printf 'aaaa' > "$deep/a.txt"             # 4 bytes, counted
  printf 'bbbb' > "$deep/b.txt"             # 4 bytes, counted
  printf 'hidden' > "$deep/.secret"         # still not counted
  mkdir "$deep/.cache"
  printf 'nope' > "$deep/.cache/x.txt"      # still not counted

  run "$BIN/downloads-stats" "$deep"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq .count)" -eq 2 ]
  [ "$(echo "$output" | jq .bytes)" -eq 8 ]
}

@test "downloads-stats counts files when the watched folder is itself hidden" {
  deep="$FIXTURE/.downloads"
  mkdir -p "$deep/.cache"
  printf 'aaaa' > "$deep/a.txt"             # 4 bytes, counted
  printf 'hidden' > "$deep/.secret"         # not counted
  printf 'nope' > "$deep/.cache/x.txt"      # not counted

  run "$BIN/downloads-stats" "$deep"
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

# The three bounds below exist because this script runs on a timer inside the
# long-lived shell process, where an unbounded walk of a large or adversarial
# tree amplifies CPU/memory. They're env-overridable purely so these tests
# don't have to build a 20,000-file fixture.

@test "downloads-stats stops counting at its output cap" {
  for i in $(seq 1 10); do printf 'a' > "$FIXTURE/f$i.txt"; done

  run env DOWNLOADS_STATS_MAX_FILES=4 "$BIN/downloads-stats" "$FIXTURE"
  [ "$status" -eq 0 ]
  # A cap, not a failure: the totals become a floor rather than an exact count.
  [ "$(echo "$output" | jq .count)" -eq 4 ]
  [ "$(echo "$output" | jq .bytes)" -eq 4 ]
}

@test "downloads-stats stops descending at its traversal cap" {
  mkdir -p "$FIXTURE/one/two/three"
  printf 'a' > "$FIXTURE/top.txt"              # depth 1, counted
  printf 'bb' > "$FIXTURE/one/mid.txt"         # depth 2, counted
  printf 'cccc' > "$FIXTURE/one/two/deep.txt"  # depth 3, past the cap

  run env DOWNLOADS_STATS_MAX_DEPTH=2 "$BIN/downloads-stats" "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq .count)" -eq 2 ]
  [ "$(echo "$output" | jq .bytes)" -eq 3 ]
}

@test "downloads-stats gives up on a walk that outruns its deadline" {
  printf 'aaaa' > "$FIXTURE/a.txt"

  # A stubbed `find` that never returns stands in for a tree too large or too
  # slow (a stalled network mount) to finish. Shadowing the real binary is
  # what makes this deterministic — a tiny deadline against a small real tree
  # doesn't trip, because find wins the race every time.
  stub="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nsleep 30\n' > "$stub/find"
  chmod +x "$stub/find"

  local -i start=$SECONDS
  run env PATH="$stub:$PATH" DOWNLOADS_STATS_DEADLINE=1 "$BIN/downloads-stats" "$FIXTURE"
  local -i elapsed=$(( SECONDS - start ))
  rm -rf "$stub"

  # Bounded: it returns on the deadline, not when the walk feels like it.
  [ "$elapsed" -lt 15 ]
  # And degrades to a valid, empty result rather than erroring or emitting a
  # truncated object — the panel shows a stale/zero total, not a broken one.
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq .count)" -eq 0 ]
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

@test "downloads-file-size reports a file's real on-disk byte size" {
  printf 'aaaaaaaa' > "$FIXTURE/growing.part"   # 8 bytes
  run "$BIN/downloads-file-size" "$FIXTURE/growing.part"
  [ "$status" -eq 0 ]
  [ "$output" -eq 8 ]
}

@test "downloads-file-size fails cleanly on a missing file" {
  run "$BIN/downloads-file-size" "$FIXTURE/ghost.part"
  [ "$status" -ne 0 ]
}
