# (revived 2026-09-06 — was briefly parked; see boot-tiger.sh)
# Tiger (PowerPC) track — constraints

## Mac OS X 10.4 (PowerPC) — what you are signing up for

Revived 2026-09-06. There IS a working path (QEMU `mac99` runs Tiger PPC), but
these constraints are real and shape what the VM can tell you:

- PowerPC targets (Titanium PowerBook G4, dual G3 PowerMac) share **nothing**
  with OSX-KVM. OpenCore, AppleSMC and KVM are all x86-only.
- No KVM => full TCG emulation. Fine for config testing, useless for perf.
- QEMU's PowerMac emulation has **no SMP for Mac OS X**, so a dual G3 cannot be
  reproduced in a VM at all.
- **AltiVec trap**: `-M mac99` emulates a G4, which has AltiVec; G3s do not.
  Software needing AltiVec would pass in the VM and fail on the real G3.
  `boot-tiger.sh` defaults to `-cpu g3` specifically to avoid this.
- Apple's recovery servers start at 10.13, so `fetch-macOS-v2.py` cannot fetch
  Tiger. Retail PowerPC install media must be supplied by hand.
- 10.4 requires built-in FireWire, which the beige G3 lacks (Apple's installer
  refuses it); QEMU's `-M g3beige` models exactly that unsupported machine.

## Status: needs empirical verification

Two things below are **assumed, not yet tested on this host**, because
`qemu-system-ppc` is not installed:

1. That `-M mac99` accepts `-cpu g3` *and* still boots Tiger. `mac99` models a
   G4-era New World machine and normally runs `-cpu g4`. The G3 variant is the
   whole point for your dual G3, so it needs proving before it is trusted. If it
   will not boot, the fallback is `-cpu g4` plus the standing AltiVec warning.
2. Which QEMU PPC CPU names this build actually exposes (`g3`, `750`, `7400`,
   `g4` are the likely spellings).

To settle both:

```bash
sudo pacman -S qemu-system-ppc          # Arch
qemu-system-ppc -M help | grep -i mac
qemu-system-ppc -cpu help | grep -iE '750|7400|g3|g4'
```

Then boot with real media and record which combination works. That is the same
matrix method used for the Intel versions.

## What you must supply

Retail Mac OS X 10.4 PowerPC install media (the DVD image for the machines you
already own). There is no download path — Apple's recovery servers start at
10.13, so `fetch-macOS-v2.py` cannot reach Tiger.
