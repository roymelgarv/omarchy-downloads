#!/usr/bin/env bash
# Deploy the working tree to the live plugin directory and reload the shell.
# Usage: scripts/dev.sh [--watch]
set -euo pipefail

PLUGIN_ID="roymelgarv.omarchy-downloads"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

STAMP="${XDG_RUNTIME_DIR:-/tmp}/omarchy-downloads-dev.stamp"

deploy() {
  mkdir -p "$DEST"
  rsync -a --delete --exclude '.git' --exclude 'node_modules' "$SRC/" "$DEST/"
  touch "$STAMP"
  omarchy plugin validate "$DEST"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  echo "Deployed to $DEST"
}

deploy

if [[ "${1:-}" == "--watch" ]]; then
  echo "Watching for changes (Ctrl+C to stop)..."
  while sleep 1; do
    if find "$SRC" -newer "$STAMP" \
      -not -path '*/.git/*' -not -path '*/node_modules/*' -print -quit |
      grep -q .; then
      deploy
    fi
  done
fi
