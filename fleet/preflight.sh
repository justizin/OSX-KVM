#!/usr/bin/env bash
# Probe this host and report which macOS versions it can run.
# Emits a human summary on stderr and one JSON object on stdout, so:
#   ./preflight.sh > results/$(hostname).json
# Safe: read-only, no root needed (it will TELL you what needs root).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/versions.sh"

VM_DIR="${VM_DIR:-$HOME/OSX-KVM}"
say() { printf '%s\n' "$*" >&2; }

# ---------- probe ----------
HOSTNAME_="$(hostname)"
KERNEL="$(uname -r)"
DISTRO="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-unknown}}")"
CPU_MODEL="$(awk -F: '/^model name/{gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo)"
CPU_VENDOR="$(awk -F: '/^vendor_id/{gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo)"
THREADS="$(nproc)"
CORES="$(awk -F: '/^cpu cores/{gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo)"
CORES="${CORES:-$THREADS}"
MEM_GB="$(awk '/^MemTotal:/{printf "%.0f", $2/1048576}' /proc/meminfo)"

has_flag() { grep -qw "$1" /proc/cpuinfo; }
VIRT="none"; has_flag vmx && VIRT="vmx"; has_flag svm && VIRT="svm"
HAS_AVX2=false; has_flag avx2 && HAS_AVX2=true
HAS_SSE42=false; has_flag sse4_2 && HAS_SSE42=true

KVM_DEV=false; [ -e /dev/kvm ] && KVM_DEV=true
KVM_RW=false;  [ -r /dev/kvm ] && [ -w /dev/kvm ] && KVM_RW=true

QEMU_BIN="$(command -v qemu-system-x86_64 || true)"
QEMU_VER=""; [ -n "$QEMU_BIN" ] && QEMU_VER="$("$QEMU_BIN" --version 2>/dev/null | awk 'NR==1{print $4}')"
DMG2IMG="$(command -v dmg2img || true)"

IGNORE_MSRS="$(cat /sys/module/kvm/parameters/ignore_msrs 2>/dev/null || echo '?')"

# free space on the dir that will hold the images (fall back to $HOME)
DISK_TARGET="$VM_DIR"; [ -d "$DISK_TARGET" ] || DISK_TARGET="$HOME"
DISK_FREE_GB="$(df -BG --output=avail "$DISK_TARGET" 2>/dev/null | tail -1 | tr -dc '0-9')"
DISK_FREE_GB="${DISK_FREE_GB:-0}"

# QEMU >= 8.2.2 per upstream README
qemu_ok=false
if [ -n "$QEMU_VER" ]; then
  if printf '8.2.2\n%s\n' "$QEMU_VER" | sort -V -C; then qemu_ok=true; fi
fi

# ---------- verdict ----------
BLOCKERS=()
[ "$VIRT" = "none" ] && BLOCKERS+=("no VT-x/AMD-V (vmx|svm) in /proc/cpuinfo")
$KVM_DEV || BLOCKERS+=("/dev/kvm missing (load kvm_intel/kvm_amd)")
$KVM_DEV && ! $KVM_RW && BLOCKERS+=("/dev/kvm not read-writable by $(id -un) (add to 'kvm' group)")
[ -z "$QEMU_BIN" ] && BLOCKERS+=("qemu-system-x86_64 not installed")
[ -n "$QEMU_VER" ] && ! $qemu_ok && BLOCKERS+=("QEMU $QEMU_VER < 8.2.2 required by upstream")
[ -z "$DMG2IMG" ] && BLOCKERS+=("dmg2img not installed (AUR on Arch)")
$HAS_SSE42 || BLOCKERS+=("no SSE4.2")
[ "$IGNORE_MSRS" != "Y" ] && [ "$IGNORE_MSRS" != "1" ] && \
  BLOCKERS+=("kvm ignore_msrs is '$IGNORE_MSRS', needs 1/Y (see kvm.conf)")

# how many concurrent VMs at 8 GiB + ~80 GiB each, leaving 8 GiB / 100 GiB headroom
MAX_BY_RAM=$(( (MEM_GB - 8) / 8 )); [ "$MAX_BY_RAM" -lt 0 ] && MAX_BY_RAM=0
MAX_BY_DISK=$(( (DISK_FREE_GB - 100) / 80 )); [ "$MAX_BY_DISK" -lt 0 ] && MAX_BY_DISK=0
MAX_VMS=$(( MAX_BY_RAM < MAX_BY_DISK ? MAX_BY_RAM : MAX_BY_DISK ))

# ---------- report ----------
say "=== host: $HOSTNAME_ ==="
say "distro    : $DISTRO ($KERNEL)"
say "cpu       : $CPU_MODEL [$CPU_VENDOR] ${CORES}c/${THREADS}t"
say "virt      : $VIRT   avx2=$HAS_AVX2   kvm=$KVM_DEV rw=$KVM_RW  ignore_msrs=$IGNORE_MSRS"
say "qemu      : ${QEMU_VER:-MISSING} (>=8.2.2 ok: $qemu_ok)   dmg2img: ${DMG2IMG:-MISSING}"
say "resources : ${MEM_GB} GiB RAM, ${DISK_FREE_GB} GiB free on $DISK_TARGET"
say "capacity  : ~$MAX_VMS concurrent VM(s) at 8 GiB RAM / 80 GiB disk each"
say ""

json_versions=""
say "supported macOS versions:"
while read -r key; do
  name="$(version_field "$key" 2)"
  gate="$(version_field "$key" 6)"
  cpu="$(version_field "$key" 4)"
  ok=true; why="ok"
  if [ "$gate" = "avx2" ] && ! $HAS_AVX2; then ok=false; why="host lacks AVX2"; fi
  if ! $HAS_SSE42; then ok=false; why="host lacks SSE4.2"; fi
  if [ "${#BLOCKERS[@]}" -gt 0 ]; then ok=false; why="host blocked: ${BLOCKERS[0]}"; fi
  printf -v line "  %-12s %-22s %-26s %s" "$key" "$name" "$cpu" "$( $ok && echo YES || echo "no  ($why)")"
  say "$line"
  json_versions="$json_versions{\"key\":\"$key\",\"name\":\"$name\",\"cpu\":\"$cpu\",\"gate\":\"$gate\",\"supported\":$ok,\"reason\":\"$why\"},"
done < <(version_keys)
json_versions="${json_versions%,}"

if [ "${#BLOCKERS[@]}" -gt 0 ]; then
  say ""; say "BLOCKERS (fix before any install):"
  for b in "${BLOCKERS[@]}"; do say "  - $b"; done
fi

json_blockers=""
for b in "${BLOCKERS[@]}"; do json_blockers="$json_blockers\"${b//\"/\\\"}\","; done
json_blockers="${json_blockers%,}"

cat <<JSON
{
  "host": "$HOSTNAME_",
  "probed_at": "$(date -Is)",
  "distro": "$DISTRO",
  "kernel": "$KERNEL",
  "cpu": {"model": "$CPU_MODEL", "vendor": "$CPU_VENDOR", "cores": $CORES, "threads": $THREADS,
          "virt": "$VIRT", "avx2": $HAS_AVX2, "sse4_2": $HAS_SSE42},
  "kvm": {"device": $KVM_DEV, "rw": $KVM_RW, "ignore_msrs": "$IGNORE_MSRS"},
  "qemu": {"path": "${QEMU_BIN:-}", "version": "${QEMU_VER:-}", "meets_min": $qemu_ok},
  "dmg2img": "${DMG2IMG:-}",
  "mem_gb": $MEM_GB,
  "disk_free_gb": $DISK_FREE_GB,
  "max_concurrent_vms": $MAX_VMS,
  "blockers": [$json_blockers],
  "versions": [$json_versions]
}
JSON
