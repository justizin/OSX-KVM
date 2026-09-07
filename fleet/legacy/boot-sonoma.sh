#!/usr/bin/env bash

# Special thanks to:
# https://github.com/Leoyzen/KVM-Opencore
# https://github.com/thenickdude/KVM-Opencore/
# https://github.com/qemu/qemu/blob/master/docs/usb2.txt
#
# qemu-img create -f qcow2 mac_hdd_ng.img 128G
#
# echo 1 > /sys/module/kvm/parameters/ignore_msrs (this is required)

###############################################################################
# NOTE: Tweak the "MY_OPTIONS" line in case you are having booting problems!
###############################################################################
#
# Change `Penryn` to `Haswell-noTSX` in OpenCore-Boot.sh file for macOS Sonoma!
#
###############################################################################


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

# This script works for Big Sur, Catalina, Mojave, and High Sierra. Tested with
# macOS 10.15.6, macOS 10.14.6, and macOS 10.13.6.

ALLOCATED_RAM="8192" # MiB (host has 62 GiB)
CPU_SOCKETS="1"
CPU_CORES="2"
CPU_THREADS="4"

REPO_PATH="/home/zin/Work/OSX-KVM"
OVMF_DIR="."

# shellcheck disable=SC2054
args=(
  # -enable-kvm -m "$ALLOCATED_RAM" -cpu Penryn,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,"$MY_OPTIONS"
  -enable-kvm -m "$ALLOCATED_RAM" -cpu Skylake-Client,-hle,-rtm,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,"$MY_OPTIONS"  # ATTENTION: Enable this line for macOS Sequoia and Tahoe
  -machine q35
  -device qemu-xhci,id=xhci
  -device usb-kbd,bus=xhci.0 -device usb-tablet,bus=xhci.0
  -smp "$CPU_THREADS",cores="$CPU_CORES",sockets="$CPU_SOCKETS"
  -device usb-ehci,id=ehci
  # -device usb-kbd,bus=ehci.0
  # -device usb-mouse,bus=ehci.0
  # -device nec-usb-xhci,id=xhci
  # -global nec-usb-xhci.msi=off
  # -global ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off
  # -device usb-host,vendorid=0x8086,productid=0x0808  # 2 USD USB Sound Card
  # -device usb-host,vendorid=0x1b3f,productid=0x2008  # Another 2 USD USB Sound Card
  -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"
  -drive if=pflash,format=raw,readonly=on,file="$REPO_PATH/$OVMF_DIR/OVMF_CODE_4M.fd"
  -drive if=pflash,format=raw,file="$REPO_PATH/$OVMF_DIR/OVMF_VARS-1920x1080.fd"
  -smbios type=2
  -device ich9-intel-hda -device hda-duplex
  -device ich9-ahci,id=sata
  -drive id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file="$REPO_PATH/OpenCore/OpenCore.qcow2"
  -device ide-hd,bus=sata.2,drive=OpenCoreBoot
  -device ide-hd,bus=sata.3,drive=InstallMedia
  -drive id=InstallMedia,if=none,file="$REPO_PATH/BaseSystem.img",format=raw
  -drive id=MacHDD,if=none,file="$REPO_PATH/mac_hdd_ng.img",format=qcow2
  -device ide-hd,bus=sata.4,drive=MacHDD
  # -netdev tap,id=net0,ifname=tap0,script=no,downscript=no -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:c9:18:27
  -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:c9:18:27
  # -netdev user,id=net0 -device vmxnet3,netdev=net0,id=net0,mac=52:54:00:c9:18:27  # Note: Use this line for High Sierra
  -monitor unix:/run/user/1000/osx-kvm-mon.sock,server,nowait
  -qmp unix:/run/user/1000/osx-kvm-qmp.sock,server,nowait
  -device vmware-svga
  # -spice port=5900,addr=127.0.0.1,disable-ticketing=on
)

qemu-system-x86_64 "${args[@]}"
