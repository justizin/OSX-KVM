#!/usr/bin/env bash
# Push a VM's latest frame + state to the dashboard (runs on the worker host).
#   DASHBOARD_URL=http://<og128x01>:8090 ./publish.sh <id> <host> <title> <state> <attn 0|1> "<sentence>"
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; FLEET="$(cd "$HERE/.." && pwd)"
DASH="${DASHBOARD_URL:-http://og128x01.hydra-hammerhead.ts.net:8090}"   # og128x01 over Tailscale by default
id="$1"; host="$2"; title="$3"; state="$4"; attn="$5"; sent="${6:-}"
# console endpoints (from boot-macos.sh --headless). VNC_HOST overrides the bind
# address with a routable one (this worker's Tailscale IP) for the projector browser.
vnc=""; vncn=""
if [ -f "$FLEET/vms/$id/vnc.env" ]; then
  . "$FLEET/vms/$id/vnc.env"
  addr="${VNC_HOST:-$VNC_BIND}"
  vnc="ws://$addr:$VNC_WS_PORT"; vncn="vnc://$addr:$VNC_RFB_PORT"
fi
newest=$(ls -t "$FLEET/vms/$id/frames/"*.png 2>/dev/null | head -1)
[ -n "$newest" ] && curl -fsS -X PUT --data-binary @"$newest" "$DASH/shot/$id" >/dev/null || true
at=$([ "$attn" = 1 ] && echo true || echo false)
if curl -fsS -X POST "$DASH/state/$id" -H 'content-type: application/json' \
  -d "{\"host\":\"$host\",\"title\":\"$title\",\"state\":\"$state\",\"attention\":$at,\"sentence\":\"$sent\",\"vnc\":\"$vnc\",\"vnc_native\":\"$vncn\"}" >/dev/null; then
  echo "published $id ($state, attention=$at) -> $DASH"
else
  echo "warn: dashboard unreachable ($DASH) -- state not pushed; install continues" >&2
fi
