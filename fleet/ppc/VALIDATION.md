# Tiger (10.4, PowerPC) validation against real hardware

Goal: use a Tiger VM to pre-validate software configurations destined for a
Titanium PowerBook G4 and a dual-G3 Power Mac, then confirm on the metal.

## What the VM can and cannot tell you (read CAVEATS.md)
- CAN: does the config install, launch, and run its self-checks on 10.4 PPC.
- CANNOT: SMP behaviour (QEMU has no PPC SMP for OS X), timing/perf (TCG only),
  AltiVec correctness for the G3 unless booted with `--cpu g3` (the default).
So every VM result is a *candidate*; the hardware run is the verdict.

## Harness (same tools as the Intel fleet)
`boot-tiger.sh --headless` uses the fleet layout (vms/tiger, osx-tiger-*.sock,
noVNC ws :5709), so these work unchanged: `VM=tiger vmctl.py`, `record.sh tiger`,
`measure.sh tiger`, `dashboard/publish.sh tiger ...`. Kernel/console output goes
to vms/tiger/serial.log.

Pointer: Tiger's USB tablet support is untested; if absolute pointing fails,
fall back to relative homing (see fleet/docs/NOTES.md, Mojave HID section).

## Validation stages
1. Boot: reaches Finder/login. Evidence: screenshot + serial.log has no panic.
2. Identity: in-guest `sw_vers; sysctl hw.model hw.cputype hw.optional.altivec`
   -- confirm AltiVec is ABSENT for the G3 profile, PRESENT for the TiBook profile.
3. Config under test: install/launch the target software; run its own checks.
4. Report: the guest publishes its own result straight to the dashboard --
   10.4 ships curl, so a guest-side script can do
   `curl -X POST http://og128x01.hydra-hammerhead.ts.net:8090/state/tiger -d '{...}'`
   (interim :8090; :80 after the gateway). No SSH needed.
5. Hardware pass: same script on the physical machine; diff the two reports.

## Prerequisites (not yet in place)
- `qemu-system-ppc` on the host running it (Arch: `sudo pacman -S qemu-system-ppc`).
- Your own Tiger PowerPC install media (Apple serves nothing older than 10.13).
- Verify `-M mac99 -cpu g3` boots Tiger; if not, `--cpu g4` + the AltiVec caveat.
