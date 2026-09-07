#!/usr/bin/env bash
# Emit a line whenever the VM screen changes materially. Signature = 32x20 gray
# jitter by comparing a 16x10 grayscale signature). One line per change event.
SIG_PREV=""
THRESH="${THRESH:-1.0}"          # mean abs difference, 0-255 scale
SHOTDIR="${SHOTDIR:-/tmp/claude-1000/-home-zin-Work/b83d5d24-c2bd-4c12-a1a3-6cdca1e4a85c/scratchpad/watch}"
mkdir -p "$SHOTDIR"
n=0
while true; do
  out="$SHOTDIR/w$(printf '%03d' $n).png"
  if ! /home/zin/Work/osx-kvm-notes/vmctl.py shot "$out" >/dev/null 2>&1; then
    echo "VM GONE: qmp screendump failed at $(date +%H:%M:%S)"
    exit 1
  fi
  SIG=$(magick "$out" -colorspace Gray -resize 32x20! -depth 8 txt:- \
        | sed -n 's/.*gray(\([0-9]*\)).*/\1/p' | tr '\n' ' ')
  if [ -n "$SIG_PREV" ]; then
    D=$(python3 -c "
a='''$SIG_PREV'''.split(); b='''$SIG'''.split()
if len(a)==len(b) and a:
    print(round(sum(abs(int(x)-int(y)) for x,y in zip(a,b))/len(a),1))
else:
    print(999)
")
    awk -v d="$D" -v t="$THRESH" 'BEGIN{exit !(d>t)}' && \
      echo "SCREEN CHANGED (delta=$D) at $(date +%H:%M:%S) -> $out"
  else
    echo "watching from $(date +%H:%M:%S) -> $out"
  fi
  SIG_PREV="$SIG"
  n=$((n+1))
  sleep 120
done
