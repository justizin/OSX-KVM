#!/usr/bin/env bash
# Grab the macOS VM's framebuffer via the QEMU monitor socket.
OUT="${1:-/tmp/osx-shot}"
printf 'screendump %s.ppm\n' "$OUT" | socat -u - UNIX-CONNECT:/run/user/1000/osx-kvm-mon.sock >/dev/null 2>&1
sleep 1
magick "$OUT.ppm" "$OUT.png" && rm -f "$OUT.ppm" && echo "$OUT.png"
