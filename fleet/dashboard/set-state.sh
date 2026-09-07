#!/usr/bin/env bash
# Upsert a VM's dashboard entry.
#   set-state.sh <id> <host> <title> <state> <attention 0|1> "<sentence>"
# state: booting|installing|waiting|done|ready|idle  (drives the status dot)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="$1"; host="$2"; title="$3"; state="$4"; attn="$5"; sent="${6:-}"
F="$HERE/status.json"; [ -f "$F" ] || echo '{"vms":[]}' > "$F"
python3 - "$F" "$id" "$host" "$title" "$state" "$attn" "$sent" <<'PY'
import json,sys,datetime
f,id,host,title,state,attn,sent=sys.argv[1:8]
d=json.load(open(f)); vms=d.get("vms",[])
now=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
e={"id":id,"host":host,"title":title,"state":state,
   "attention":attn in("1","true","yes"),"sentence":sent,"img":id+".png","updated":now}
vms=[v for v in vms if v.get("id")!=id]+[e]
order={"waiting":0,"installing":1,"booting":2,"ready":3,"done":4,"idle":5}
vms.sort(key=lambda v:(0 if v["attention"] else 1, order.get(v["state"],9), v["id"]))
d["vms"]=vms; d["updated"]=now
json.dump(d,open(f,"w"),indent=2)
print("set",id,"->",state,"attention="+str(e["attention"]))
PY
