#!/usr/bin/env bash
# Is a macOS VM making progress, or is it wedged?
#
#   ./health.sh mojave [sample_seconds]      # default 60
#
# The guest screen is NOT a reliable indicator: a deadlocked macOS installer
# happily displays "About 20 minutes remaining" forever. These four signals
# separate hung from merely slow (all observed on a real deadlock):
#
#                     hung                        healthy
#   write throughput  ~16 KB/60s, 1-byte syscalls  MB/s
#   image mtime       frozen for tens of minutes   current
#   vCPU threads      ALL pegged ~99%              bursty / idle
#   guest RIP         identical across samples     moves
#
# Exit: 0 healthy or idle, 1 wedged, 2 can't tell (VM not running, etc.)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-}"
WINDOW="${2:-60}"
FLEET_ROOT="${FLEET_ROOT:-$HERE}"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}"

[ -n "$VERSION" ] || { echo "usage: $0 <version> [sample_seconds]" >&2; exit 2; }

IMG="$FLEET_ROOT/vms/$VERSION/mac_hdd_ng.img"
MON="$RUN_DIR/osx-$VERSION-mon.sock"

PID="$(pgrep -f "qmp.*osx-$VERSION-qmp.sock" | head -1)"
[ -n "$PID" ] || { echo "VM '$VERSION' is not running"; exit 2; }

io() { awk -v k="$1" '$1==k":"{print $2}' "/proc/$PID/io" 2>/dev/null; }
rip() {
  [ -S "$MON" ] || return 0
  printf 'info registers\n' | timeout 8 socat - "UNIX-CONNECT:$MON" 2>/dev/null \
    | tr -d '\r' | grep -ao 'RIP=[0-9a-f]*' | head -1
}

w1="$(io wchar)"; c1="$(io syscw)"; m1="$(stat -c %Y "$IMG" 2>/dev/null || echo 0)"
r1="$(rip)"
sleep "$WINDOW"
w2="$(io wchar)"; c2="$(io syscw)"; m2="$(stat -c %Y "$IMG" 2>/dev/null || echo 0)"
r2="$(rip)"; sleep 2; r3="$(rip)"

BYTES=$(( ${w2:-0} - ${w1:-0} ))
SYSC=$(( ${c2:-0} - ${c1:-0} ))
KB=$(( BYTES / 1024 ))
PER=0; [ "$SYSC" -gt 0 ] && PER=$(( BYTES / SYSC ))
MTIME_AGE=$(( $(date +%s) - m2 ))

# all vCPU threads pegged?
BUSY=0; TOTAL=0
while read -r tid; do
  case "$(cat "/proc/$PID/task/$tid/comm" 2>/dev/null)" in
    CPU*) TOTAL=$((TOTAL+1))
          s=$(awk '{print $3}' "/proc/$PID/task/$tid/stat" 2>/dev/null)
          [ "$s" = "R" ] && BUSY=$((BUSY+1)) ;;
  esac
done < <(ls "/proc/$PID/task" 2>/dev/null)

echo "VM        : $VERSION (pid $PID), sampled ${WINDOW}s"
echo "writes    : ${KB} KiB in ${SYSC} syscalls (${PER} B/syscall)"
echo "img mtime : ${MTIME_AGE}s ago"
echo "vCPUs     : ${BUSY}/${TOTAL} running"
echo "RIP       : ${r1:-?} ${r2:-?} ${r3:-?}"

# A wedged VM and an idle one BOTH show "no progress". What separates them is
# CPU: a deadlock spins every vCPU, a VM parked at a prompt spins none.
# (Measured: idle at Setup Assistant = 107 KiB/20s with 0/4 vCPUs running.)
PROGRESSING=false; [ "$KB" -ge 1024 ] && PROGRESSING=true
SPINNING=false;    [ "$TOTAL" -gt 0 ] && [ "$BUSY" -eq "$TOTAL" ] && SPINNING=true
RIP_FROZEN=false;  [ -n "${r1:-}" ] && [ "$r1" = "$r2" ] && [ "$r2" = "$r3" ] && RIP_FROZEN=true
POLL_SPIN=false;   [ "$SYSC" -gt 100 ] && [ "$PER" -le 2 ] && POLL_SPIN=true

echo
if $PROGRESSING; then
  echo "VERDICT   : healthy (${KB} KiB written in ${WINDOW}s)"
  exit 0
fi

if $SPINNING || $RIP_FROZEN; then
  echo "VERDICT   : WEDGED"
  $SPINNING   && echo "  - all $TOTAL vCPUs pegged with no disk progress"
  $RIP_FROZEN && echo "  - guest RIP frozen at $r1 across 3 samples"
  $POLL_SPIN  && echo "  - write syscalls are ~${PER} byte each (QEMU poll loop, not guest I/O)"
  [ "$MTIME_AGE" -gt 900 ] && echo "  - disk image untouched for ${MTIME_AGE}s"
  echo "  recovery : kill the VM, confirm CORES=2/THREADS=4, reboot and pick the"
  echo "             'macOS Installer' entry in the OpenCore picker (it does NOT"
  echo "             auto-boot after a hard reset)."
  exit 1
fi

echo "VERDICT   : idle (no disk progress, but vCPUs are not spinning)"
echo "  Most likely parked at a prompt waiting for input -- check the screen."
exit 0
