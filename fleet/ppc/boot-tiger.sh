#!/usr/bin/env bash
# Mac OS X 10.4 "Tiger" (PowerPC) under QEMU -- a SEPARATE track from the
# Intel/OSX-KVM fleet. Nothing here shares code with OSX-KVM, because nothing
# can: OpenCore, AppleSMC and KVM are all x86-only.
#
#   ./boot-tiger.sh --install /path/to/tiger.iso
#   ./boot-tiger.sh
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE TRUSTING RESULTS FROM THIS VM
#
# 1. NO KVM. PowerPC on an x86 host is full software emulation (TCG). It is
#    slow and effectively uniprocessor. Fine for "does this config work",
#    useless for "is this fast enough".
#
# 2. YOU CANNOT EMULATE A DUAL G3. QEMU's PowerMac emulation does not do SMP
#    for Mac OS X. Your dual-processor box cannot be reproduced here; anything
#    you are testing that depends on two CPUs has to be tested on the metal.
#
# 3. ALTIVEC IS THE BIG TRAP. `-M mac99` emulates a G4, and G4s have AltiVec
#    (the Velocity Engine). Your G3s do NOT. Software that requires AltiVec
#    will run happily in this VM and then fail on your dual G3. If the G3 is
#    the real target, force `-cpu g3` (the default below) so AltiVec is absent
#    and that class of failure shows up here instead of on the hardware.
#    Use CPU=g4 only when the Titanium PowerBook is the target.
#
# 4. APPLE'S RECOVERY SERVERS DO NOT SERVE 10.4. `fetch-macOS-v2.py` starts at
#    High Sierra. You must supply your own Tiger install media -- the retail
#    PowerPC install DVD you already own for these machines. There is no
#    download step in this script by design.
#
# 5. 10.4 REQUIRES BUILT-IN FIREWIRE, which the beige Power Macintosh G3 lacks;
#    Apple's installer refuses it. Blue & White G3 and later are fine. QEMU's
#    `-M g3beige` models the unsupported beige machine, which is why this
#    script uses `mac99` (a New World machine) even when targeting a G3 CPU.
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="${VM_DIR:-$HERE/vm}"
DISK="$VM_DIR/tiger.qcow2"
DISK_SIZE="${DISK_SIZE:-32G}"
RAM_MB="${RAM_MB:-1024}"     # OS X PPC tops out around 2 GiB; 1-1.5 GiB is safe
CPU="${CPU:-g3}"             # g3 = no AltiVec (matches the dual G3). g4 = TiBook.
RES="${RES:-1024x768x32}"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}"

command -v qemu-system-ppc >/dev/null || {
  echo "qemu-system-ppc not installed." >&2
  echo "  Arch:   sudo pacman -S qemu-system-ppc" >&2
  echo "  Debian: sudo apt install qemu-system-ppc" >&2
  exit 1; }

ISO=""
INSTALL=false
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=true; ISO="${2:-}"; shift 2 ;;
    --cpu)     CPU="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$VM_DIR"
if [ ! -f "$DISK" ]; then
  echo "-- creating $DISK_SIZE disk"
  qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
fi

args=(
  -M mac99,via=pmu
  -cpu "$CPU"
  -m "$RAM_MB"
  -g "$RES"
  -drive "file=$DISK,format=qcow2,media=disk,if=none,id=hd"
  -device "ide-hd,drive=hd,bus=ide.0"
  -netdev user,id=net0
  -device sungem,netdev=net0
  -monitor "unix:$RUN_DIR/tiger-mon.sock,server,nowait"
  -qmp "unix:$RUN_DIR/tiger-qmp.sock,server,nowait"
)

if $INSTALL; then
  [ -n "$ISO" ] && [ -f "$ISO" ] || { echo "--install needs a readable Tiger ISO/DMG path" >&2; exit 1; }
  args+=( -drive "file=$ISO,format=raw,media=cdrom,if=none,id=cd"
          -device "ide-cd,drive=cd,bus=ide.1"
          -boot d )
fi

echo "== Mac OS X 10.4 (PowerPC, emulated -- no KVM)"
echo "   machine=mac99  cpu=$CPU$( [ "$CPU" = g3 ] && echo '  (no AltiVec, matches dual G3)' || echo '  (AltiVec present, matches TiBook)')"
echo "   ram=${RAM_MB}M  disk=$DISK"
$INSTALL && echo "   installing from $ISO"
exec qemu-system-ppc "${args[@]}"
