#!/usr/bin/env bash
# Send QEMU monitor command(s) quietly. Usage: ./mon.sh "sendkey right"
for c in "$@"; do printf '%s\n' "$c"; sleep 0.3; done \
  | socat -u - UNIX-CONNECT:/run/user/1000/osx-kvm-mon.sock >/dev/null 2>&1
