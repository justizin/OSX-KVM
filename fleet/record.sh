#!/usr/bin/env bash
# Record a headless macOS install: periodic framebuffer capture + a human log,
# and emit a line on each MATERIAL screen change (for a Monitor to relay).
#
#   ./record.sh <version> [interval_sec=20]
#
# Writes:
#   vms/<version>/frames/NNNNNN.png   timelapse frames
#   vms/<version>/install.log         timestamped, human-readable event log
# Stdout: one "CHANGE" line per material screen change, and "VM GONE" on exit.
# Frames come from QMP screendump, so this needs no display (headless-safe).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:?usage: record.sh <version> [interval]}"
INTERVAL="${2:-20}"
FLEET_ROOT="${FLEET_ROOT:-$HERE}"
DIR="$FLEET_ROOT/vms/$VERSION"
FRAMES="$DIR/frames"; LOG="$DIR/install.log"
mkdir -p "$FRAMES"
THRESH="${THRESH:-1.0}"

log(){ printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
sig(){ magick "$1" -colorspace Gray -resize 32x20! -depth 8 txt:- \
       | sed -n 's/.*gray(\([0-9]*\)).*/\1/p' | tr '\n' ' '; }

log "=== recording $VERSION (interval ${INTERVAL}s) ==="
n=0; prev=""
while true; do
  f="$FRAMES/$(printf '%06d' "$n").png"
  if ! VM="$VERSION" "$HERE/vmctl.py" shot "$f" >/dev/null 2>&1; then
    log "VM GONE (screendump failed)"; echo "VM GONE: $VERSION at $(date '+%H:%M:%S')"; exit 0
  fi
  cur="$(sig "$f")"
  if [ -n "$prev" ]; then
    d=$(python3 -c "
a='''$prev'''.split(); b='''$cur'''.split()
print(round(sum(abs(int(x)-int(y)) for x,y in zip(a,b))/len(a),1) if len(a)==len(b) and a else 999)")
    if awk -v d="$d" -v t="$THRESH" 'BEGIN{exit !(d>t)}'; then
      log "*** screen changed (delta=$d) -> frame $(basename "$f")"
      echo "CHANGE $VERSION delta=$d frame=$f at $(date '+%H:%M:%S')"
    fi
  else
    log "first frame -> $(basename "$f")"; echo "CHANGE $VERSION first frame=$f"
  fi
  prev="$cur"; n=$((n+1))
  sleep "$INTERVAL"
done
