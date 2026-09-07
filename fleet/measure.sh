#!/usr/bin/env bash
# Sample a VM's QEMU process so installs can be compared across hosts.
#   measure.sh <version> [interval=30]        -> appends vms/<version>/metrics.csv until the VM exits
#   measure.sh <version> --summary            -> wall time, CPU-seconds, peak RSS, disk written
# Run the SAME script on every host so numbers are comparable.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; FLEET_ROOT="${FLEET_ROOT:-$HERE}"
V="${1:?usage: measure.sh <version> [interval|--summary]}"; ARG="${2:-30}"
OUT="$FLEET_ROOT/vms/$V/metrics.csv"
if [ "$ARG" = "--summary" ]; then
  [ -f "$OUT" ] || { echo "no metrics for $V" >&2; exit 1; }
  python3 - "$OUT" "$V" <<'PY'
import csv,sys
rows=list(csv.DictReader(open(sys.argv[1])))
if not rows: sys.exit("empty")
f=rows[0]; l=rows[-1]
wall=int(l["elapsed_s"]); cpu=float(l["cpu_s"])
print(f"{sys.argv[2]} on {f['host']}: wall {wall//60}m{wall%60:02d}s  cpu {cpu:.0f}s ({cpu/max(wall,1):.2f} cores avg)"
      f"  peakRSS {max(float(r['rss_mb']) for r in rows):.0f}MB  written {float(l['write_mb']):.0f}MB  read {float(l['read_mb']):.0f}MB"
      f"  samples {len(rows)}  first {f['ts']}  last {l['ts']}")
PY
  exit 0
fi
INT="$ARG"; mkdir -p "$(dirname "$OUT")"
pid_of(){ for p in $(pgrep -f "osx-$V-qmp.sock"); do case "$(cat /proc/$p/comm 2>/dev/null)" in qemu*) echo "$p"; return;; esac; done; }
PID="$(pid_of)"; [ -n "$PID" ] || { echo "VM $V not running" >&2; exit 2; }
CLK=$(getconf CLK_TCK); T0=$(date +%s); HOST=$(hostname)
[ -f "$OUT" ] || echo "ts,host,elapsed_s,cpu_s,rss_mb,write_mb,read_mb,load1" > "$OUT"
while [ -d "/proc/$PID" ]; do
  st=$(cat /proc/$PID/stat 2>/dev/null) || break
  # fields after the ")" : utime=14 stime=15 (1-indexed in full stat)
  set -- ${st##*) }; cpu=$(( ($12 + $13) / CLK ))
  rss=$(awk '/VmRSS/{print int($2/1024)}' /proc/$PID/status 2>/dev/null)
  w=$(awk '/^write_bytes/{print int($2/1048576)}' /proc/$PID/io 2>/dev/null)
  r=$(awk '/^read_bytes/{print int($2/1048576)}' /proc/$PID/io 2>/dev/null)
  l1=$(cut -d' ' -f1 /proc/loadavg)
  echo "$(date -Is),$HOST,$(( $(date +%s) - T0 )),$cpu,${rss:-0},${w:-0},${r:-0},$l1" >> "$OUT"
  sleep "$INT"
done
echo "VM $V exited; metrics in $OUT"
