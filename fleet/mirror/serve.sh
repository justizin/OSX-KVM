#!/usr/bin/env bash
# No-container fallback: serve the mirror tree with python's http.server.
# Usage: ./serve.sh [root=./data] [port=8080]
ROOT="${1:-$(dirname "$0")/data}"; PORT="${2:-8080}"
echo "serving $ROOT on http://0.0.0.0:$PORT  (clients: export MACOS_RECOVERY_MIRROR=http://<this-host>:$PORT)"
exec python3 -m http.server "$PORT" --directory "$ROOT"
