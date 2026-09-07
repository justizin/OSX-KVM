#!/usr/bin/env bash
# Prepare the image set for one macOS version: download recovery, convert it,
# create the qcow2. Idempotent -- skips any step whose output already exists.
#
#   ./provision.sh mojave [disk_size]     # default disk 256G
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/versions.sh"

OSX_KVM="${OSX_KVM:-$HOME/OSX-KVM}"
FLEET_ROOT="${FLEET_ROOT:-$HERE}"
VERSION="${1:-}"
DISK="${2:-256G}"

[ -n "$VERSION" ] || { echo "usage: $0 <version> [disk_size]" >&2
                       echo "versions: $(version_keys | tr '\n' ' ')" >&2; exit 2; }
version_exists "$VERSION" || { echo "unknown version '$VERSION'" >&2; exit 2; }

SHORT="$(version_field "$VERSION" 3)"
NAME="$(version_field "$VERSION" 2)"
VM_DIR="$FLEET_ROOT/vms/$VERSION"
mkdir -p "$VM_DIR"

command -v dmg2img >/dev/null || { echo "dmg2img missing" >&2; exit 1; }
[ -x "$OSX_KVM/fetch-macOS-v2.py" ] || { echo "fetch-macOS-v2.py not found in $OSX_KVM" >&2; exit 1; }

echo "== provisioning $NAME into $VM_DIR"

if [ ! -f "$VM_DIR/BaseSystem.dmg" ]; then
  echo "-- downloading recovery image ($SHORT)"
  ( cd "$VM_DIR" && "$OSX_KVM/fetch-macOS-v2.py" -s "$SHORT" )
else
  echo "-- BaseSystem.dmg present, skipping download"
fi
[ -f "$VM_DIR/BaseSystem.dmg" ] || { echo "download produced no BaseSystem.dmg" >&2; exit 1; }

if [ ! -f "$VM_DIR/BaseSystem.img" ]; then
  echo "-- converting dmg -> img"
  dmg2img -i "$VM_DIR/BaseSystem.dmg" "$VM_DIR/BaseSystem.img" >/dev/null
else
  echo "-- BaseSystem.img present, skipping convert"
fi

if [ ! -f "$VM_DIR/mac_hdd_ng.img" ]; then
  echo "-- creating $DISK qcow2"
  qemu-img create -f qcow2 "$VM_DIR/mac_hdd_ng.img" "$DISK" >/dev/null
else
  echo "-- mac_hdd_ng.img present, skipping create"
fi

if [ ! -f "$VM_DIR/OVMF_VARS.fd" ]; then
  cp "$OSX_KVM/OVMF_VARS-1920x1080.fd" "$VM_DIR/OVMF_VARS.fd"
fi

echo "== ready. next: $HERE/boot-macos.sh $VERSION --install"
ls -lh "$VM_DIR"
