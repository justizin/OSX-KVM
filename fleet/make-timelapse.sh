#!/usr/bin/env bash
# Assemble a recorded install's frames into a timelapse mp4.
#   ./make-timelapse.sh <version> [fps=8]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:?usage: make-timelapse.sh <version> [fps]}"
FPS="${2:-8}"
FLEET_ROOT="${FLEET_ROOT:-$HERE}"
FRAMES="$FLEET_ROOT/vms/$VERSION/frames"
OUT="$FLEET_ROOT/vms/$VERSION/$VERSION-timelapse.mp4"
[ -d "$FRAMES" ] || { echo "no frames dir $FRAMES" >&2; exit 1; }
count=$(ls "$FRAMES"/*.png 2>/dev/null | wc -l)
[ "$count" -gt 0 ] || { echo "no frames captured yet" >&2; exit 1; }
# pad to even dimensions for h264; glob in numeric order
ffmpeg -y -framerate "$FPS" -pattern_type glob -i "$FRAMES/*.png" \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p" \
  -c:v libx264 -preset veryfast -crf 26 "$OUT" >/dev/null 2>&1
ls -lh "$OUT" | awk '{print "wrote", $NF, "("$5", '"$count"' frames)"}'
