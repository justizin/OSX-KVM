#!/usr/bin/env bash
# Single source of truth for per-macOS-version VM configuration.
# Sourced by preflight.sh and boot-macos.sh. Edit here, not in callers.
#
# Fields, pipe-separated:
#   key | display name | fetch-macOS shortname | -cpu model | NIC device | host gate
#
# host gate is the CPU feature the HOST must have:
#   sse4_2 -> effectively every 64-bit host
#   avx2   -> required by macOS Ventura (13) and newer
#
# CPU model mapping comes from OpenCore-Boot.sh: `Penryn` is the legacy line
# (commented out upstream) and `Skylake-Client` is the current active default.
# NOTE: treat the Penryn assignments below as a HYPOTHESIS. Upstream now ships
# Skylake-Client active for everything; the per-version split is inferred from
# the script's own comments, not from a tested matrix. Validating it is one of
# the points of the fleet run -- record what actually worked.

MACOS_VERSIONS=(
  "high-sierra|High Sierra (10.13)|high-sierra|Penryn|vmxnet3|sse4_2"
  "mojave|Mojave (10.14)|mojave|Penryn|vmxnet3|sse4_2"
  "catalina|Catalina (10.15)|catalina|Penryn|virtio-net-pci|sse4_2"
  "big-sur|Big Sur (11)|big-sur|Penryn|virtio-net-pci|sse4_2"
  "monterey|Monterey (12)|monterey|Penryn|virtio-net-pci|sse4_2"
  "ventura|Ventura (13)|ventura|Skylake-Client,-hle,-rtm|virtio-net-pci|avx2"
  "sonoma|Sonoma (14)|sonoma|Skylake-Client,-hle,-rtm|virtio-net-pci|avx2"
  "sequoia|Sequoia (15)|sequoia|Skylake-Client,-hle,-rtm|virtio-net-pci|avx2"
  "tahoe|Tahoe (26)|tahoe|Skylake-Client,-hle,-rtm|virtio-net-pci|avx2"
)

# field <key> <n>  -> nth pipe-separated field for that version key
version_field() {
  local want="$1" n="$2" row
  for row in "${MACOS_VERSIONS[@]}"; do
    if [ "${row%%|*}" = "$want" ]; then
      printf '%s\n' "$row" | cut -d'|' -f"$n"
      return 0
    fi
  done
  return 1
}

version_keys() {
  local row
  for row in "${MACOS_VERSIONS[@]}"; do printf '%s\n' "${row%%|*}"; done
}

version_exists() { version_field "$1" 1 >/dev/null 2>&1; }
