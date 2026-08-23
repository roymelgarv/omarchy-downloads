#!/usr/bin/env bash
# Deploy the working tree to the live plugin directory and reload the shell.
# Usage: scripts/dev.sh [--watch] [--restart]
#
#   --watch     redeploy whenever a file changes
#   --restart   restart the shell instead of hot-reloading it
#
# Reach for --restart after any structural QML change — new child items,
# a changed root type — not just a property tweak. `rescanPlugins` has been
# observed to keep rendering the previously compiled component in that case,
# with no error and a successful deploy, so an edit can appear to do nothing
# while the code is already correct. Editing a `kind: "service"` file always
# needs it: hot reload never reinstantiates a running service.
set -euo pipefail

PLUGIN_ID="roymelgarv.omarchy-downloads"
# Service.qml's IpcHandler target; the readiness probe below only answers once
# the service is up, which is what makes it a real "shell is back" signal.
IPC_TARGET="downloads"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

STAMP="${XDG_RUNTIME_DIR:-/tmp}/omarchy-downloads-dev.stamp"

WATCH=0
RESTART=0
for arg in "$@"; do
  case "$arg" in
    --watch) WATCH=1 ;;
    --restart) RESTART=1 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

# The shell process itself. Matched on the quickshell command rather than the
# string "omarchy-shell", which is the CLI client: `pgrep -f omarchy-shell`
# also matches the very shell command running this script.
SHELL_PROC_PATTERN='quickshell .*-p /usr/share/omarchy/shell'

shell_pid() { pgrep -f "$SHELL_PROC_PATTERN" | head -n1; }

# Restart, then block until a *new* process is answering IPC.
#
# Both halves matter. `omarchy restart shell` returns immediately while the
# outgoing shell is still serving IPC, so waiting on the status call alone gets
# an answer from the dying process and reports success before the new code has
# loaded — the same false "it's live" that this flag exists to eliminate.
# Waiting for the pid to change alone is not enough either: the new process
# exists well before it has finished loading plugins.
restart_shell() {
  local before after
  before="$(shell_pid)"
  omarchy restart shell
  for _ in $(seq 1 60); do
    sleep 0.5
    after="$(shell_pid)"
    [[ -n "$after" && "$after" != "$before" ]] || continue
    if omarchy-shell "$IPC_TARGET" status >/dev/null 2>&1; then
      echo "Shell restarted (pid ${before:-none} -> $after)"
      return 0
    fi
  done
  echo "warning: shell did not come back within 30s after restart." >&2
}

deploy() {
  mkdir -p "$DEST"
  # .claude/.agents/skills-lock.json are Claude Code's local skill-loading
  # artifacts (symlinks included) — never part of the plugin, and
  # `omarchy plugin validate` below hard-fails on any symlink it finds.
  rsync -a --delete \
    --exclude '.git' --exclude 'node_modules' \
    --exclude '.claude' --exclude '.agents' --exclude 'skills-lock.json' \
    "$SRC/" "$DEST/"
  touch "$STAMP"
  omarchy plugin validate "$DEST"
  if ((RESTART)); then
    restart_shell
  elif ! omarchy-shell shell rescanPlugins >/dev/null 2>&1; then
    echo "warning: rescanPlugins failed — is omarchy-shell running? Deployed files may not be live yet." >&2
  fi
  echo "Deployed to $DEST"
}

deploy

if ((WATCH)); then
  echo "Watching for changes (Ctrl+C to stop)..."
  while sleep 1; do
    if find "$SRC" -newer "$STAMP" \
      -not -path '*/.git/*' -not -path '*/node_modules/*' \
      -not -path '*/.claude/*' -not -path '*/.agents/*' \
      -not -name 'skills-lock.json' -print -quit |
      grep -q .; then
      deploy
    fi
  done
fi
