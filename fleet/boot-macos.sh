#!/usr/bin/env bash
# Launch one macOS VM by version key. Multiple versions can run concurrently:
# each gets its own image dir, its own OVMF_VARS (NVRAM), its own monitor/QMP
# sockets and its own forwarded SSH port.
#
#   ./boot-macos.sh mojave            # run (no install media attached)
#   ./boot-macos.sh mojave --install   # attach BaseSystem.img and boot to it
#   ./boot-macos.sh mojave --headless  # no window; VNC on 127.0.0.1:<offset>
#   VM_NAME=mojave-media PORT_OFFSET=20 ./boot-macos.sh mojave   # 2nd Mojave on the same host
#
# Env overrides: OSX_KVM (upstream checkout), FLEET_ROOT, RAM_MB, CORES, THREADS
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/versions.sh"

OSX_KVM="${OSX_KVM:-$HOME/OSX-KVM}"
FLEET_ROOT="${FLEET_ROOT:-$HERE}"
RAM_MB="${RAM_MB:-8192}"
# Stock upstream topology. Raising this deadlocked a Sonoma install on a
# 6c/12t Coffee Lake host (all vCPUs spinning, zero disk I/O, frozen kernel
# RIP). Do not raise it without re-testing that version end to end.
CORES="${CORES:-2}"
THREADS="${THREADS:-4}"

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: $0 <version> [--install] [--headless]" >&2
                       echo "versions: $(version_keys | tr '\n' ' ')" >&2; exit 2; }
shift || true
version_exists "$VERSION" || { echo "unknown version '$VERSION'" >&2
                               echo "versions: $(version_keys | tr '\n' ' ')" >&2; exit 2; }

INSTALL=false; HEADLESS=false
for a in "$@"; do
  case "$a" in
    --install)  INSTALL=true ;;
    --headless) HEADLESS=true ;;
    *) echo "unknown arg $a" >&2; exit 2 ;;
  esac
done

CPU_MODEL="$(version_field "$VERSION" 4)"
NIC="$(version_field "$VERSION" 5)"
NAME="$(version_field "$VERSION" 2)"

# Instance name: defaults to the version, but a SECOND VM of the same version on
# one host (e.g. an ISO-build VM beside an install VM) needs its own name and
# port block. Everything mutable is keyed by VM_NAME; vmctl/record/measure/
# health/publish take the same name as their first argument.
VM_NAME="${VM_NAME:-$VERSION}"
VM_DIR="$FLEET_ROOT/vms/$VM_NAME"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}"
MON_SOCK="$RUN_DIR/osx-$VM_NAME-mon.sock"
QMP_SOCK="$RUN_DIR/osx-$VM_NAME-qmp.sock"

# port block: default = this version's index in versions.sh; override with
# PORT_OFFSET (e.g. 20) for an extra instance so SSH/VNC/WS ports don't collide
OFFSET=0; i=0
while read -r k; do [ "$k" = "$VERSION" ] && OFFSET=$i; i=$((i+1)); done < <(version_keys)
OFFSET="${PORT_OFFSET:-$OFFSET}"
SSH_PORT=$((2222 + OFFSET))
VNC_DISP=$((10 + OFFSET))

[ -d "$OSX_KVM" ] || { echo "OSX-KVM checkout not found at $OSX_KVM (set OSX_KVM=)" >&2; exit 1; }
[ -f "$VM_DIR/mac_hdd_ng.img" ] || { echo "no disk at $VM_DIR/mac_hdd_ng.img -- run VM_NAME=$VM_NAME ./provision.sh $VERSION first" >&2; exit 1; }

# Per-VM NVRAM. Upstream points every VM at the repo's single OVMF_VARS file;
# two VMs sharing it will clobber each other's boot entries.
if [ ! -f "$VM_DIR/OVMF_VARS.fd" ]; then
  cp "$OSX_KVM/OVMF_VARS-1920x1080.fd" "$VM_DIR/OVMF_VARS.fd"
fi

# QEMU's GTK display mismaps ABSOLUTE pointer input when GDK_SCALE is set:
# it reads pointer position in GTK's scaled coordinate space but maps it onto
# the guest framebuffer unscaled, so the cursor moves at GDK_SCALE times the
# right rate and only part of the guest screen is reachable. Omarchy sets
# GDK_SCALE=2 session-wide in ~/.config/hypr/monitors.lua for HiDPI, which
# makes the mouse effectively unusable in every macOS VM, at any resolution,
# tiled or fullscreen. Override it for this process only -- do NOT change the
# desktop-wide setting, that would shrink every other app.
export GDK_SCALE=1
# Run under XWayland: the compositor then scales a plain bitmap instead of
# asking GTK to render at a fractional/2x buffer scale, and GTK's Wayland
# pointer path is bypassed. Test candidate for smeared rendering + bad tracking.
export GDK_BACKEND=x11
unset GDK_DPI_SCALE

MY_OPTIONS="+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check"

args=(
  -enable-kvm -m "$RAM_MB"
  -cpu "$CPU_MODEL,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,$MY_OPTIONS"
  -machine q35
  -smp "$THREADS,cores=$CORES,sockets=1"
  -device qemu-xhci,id=xhci
  -device usb-ehci,id=ehci
  # HID on the USB 2.0 (ehci) bus. Older macOS (Mojave and earlier) does not
  # track a USB 3.0 (xhci) keyboard or tablet in the installer environment --
  # the mouse and keyboard look dead. USB 2.0 HID is read by every version.
  -device usb-kbd,bus=ehci.0 -device usb-tablet,bus=ehci.0
  -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"
  -drive "if=pflash,format=raw,readonly=on,file=$OSX_KVM/OVMF_CODE_4M.fd"
  -drive "if=pflash,format=raw,file=$VM_DIR/OVMF_VARS.fd"
  -smbios type=2
  -device ich9-intel-hda -device hda-duplex
  -device ich9-ahci,id=sata
  -drive "id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file=$OSX_KVM/OpenCore/OpenCore.qcow2"
  -device ide-hd,bus=sata.2,drive=OpenCoreBoot
  -drive "id=MacHDD,if=none,file=$VM_DIR/mac_hdd_ng.img,format=qcow2"
  -device ide-hd,bus=sata.4,drive=MacHDD
  -netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
  -device "$NIC,netdev=net0,id=net0,mac=52:54:00:c9:18:$(printf '%02x' $((0x27 + OFFSET)))"
  -monitor "unix:$MON_SOCK,server,nowait"
  -qmp "unix:$QMP_SOCK,server,nowait"
  -device vmware-svga
)

if $INSTALL; then
  [ -f "$VM_DIR/BaseSystem.img" ] || { echo "no BaseSystem.img in $VM_DIR" >&2; exit 1; }
  args+=( -device ide-hd,bus=sata.3,drive=InstallMedia
          -drive "id=InstallMedia,if=none,file=$VM_DIR/BaseSystem.img,format=raw" )
fi

VNC_BIND="${VNC_BIND:-127.0.0.1}"   # set to this host's Tailscale IP (or 0.0.0.0) for remote noVNC
WS_PORT=$((5700 + OFFSET))
if $HEADLESS; then
  # QEMU serves RFB (5900+disp) AND a WebSocket (WS_PORT) for noVNC -- no proxy needed.
  args+=( -display none -vnc "$VNC_BIND:$VNC_DISP,websocket=$WS_PORT" )
  cat > "$VM_DIR/vnc.env" <<VEOF
VNC_BIND=$VNC_BIND
VNC_WS_PORT=$WS_PORT
VNC_RFB_PORT=$((5900 + VNC_DISP))
VEOF
fi

rm -f "$MON_SOCK" "$QMP_SOCK"
echo "== $NAME ($VERSION) instance=$VM_NAME offset=$OFFSET"
echo "   cpu=$CPU_MODEL  ram=${RAM_MB}M  smp=$THREADS(${CORES}c)  nic=$NIC"
echo "   disk=$VM_DIR/mac_hdd_ng.img"
echo "   ssh=localhost:$SSH_PORT  qmp=$QMP_SOCK$( $HEADLESS && echo "  vnc-ws=$VNC_BIND:$WS_PORT (novnc)  rfb=$VNC_BIND:$((5900+VNC_DISP))" )"
exec qemu-system-x86_64 "${args[@]}"
