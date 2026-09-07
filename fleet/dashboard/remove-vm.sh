#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; F="$HERE/status.json"
python3 - "$F" "$1" <<'PY'
import json,sys; f,id=sys.argv[1:3]; d=json.load(open(f))
d["vms"]=[v for v in d.get("vms",[]) if v.get("id")!=id]; json.dump(d,open(f,"w"),indent=2)
PY
