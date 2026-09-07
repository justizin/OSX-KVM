#!/usr/bin/env bash
# Copy the newest recorded frame of each locally-running VM to <id>.png so the
# dashboard tiles stay live. Falls back to a direct screendump if no frames.
#   refresh-shots.sh [interval=8]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET="$(cd "$HERE/.." && pwd)"; RUN="${XDG_RUNTIME_DIR:-/tmp}"; INT="${1:-8}"
while true; do
  for sock in "$RUN"/osx-*-qmp.sock; do
    [ -S "$sock" ] || continue
    id=$(basename "$sock"); id=${id#osx-}; id=${id%-qmp.sock}
    newest=$(ls -t "$FLEET/vms/$id/frames/"*.png 2>/dev/null | head -1)
    if [ -n "$newest" ]; then cp -f "$newest" "$HERE/$id.png"
    else VM="$id" "$FLEET/vmctl.py" shot "$HERE/$id.png" >/dev/null 2>&1 || true; fi
  done
  sleep "$INT"
done
