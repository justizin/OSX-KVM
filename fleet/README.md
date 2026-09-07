# fleet/ — multi-version, multi-host macOS VM tooling (fork-only)

This directory is NOT part of upstream OSX-KVM. It lives on this fork's `main`
branch; `master` mirrors upstream and stays pristine so PR branches can be
rebased cleanly.

- `AGENTS.md`      — runbook for a Claude Code agent (or a human) on one host. Start here.
- `preflight.sh`   — what can this host run? emits JSON into `results/`
- `versions.sh`    — version -> -cpu / NIC / host-gate table (single source of truth)
- `provision.sh`   — download + convert + create disk for one version (idempotent)
- `boot-macos.sh`  — launch one version; concurrent-safe (own NVRAM, sockets, ports)
- `health.sh`      — wedged vs idle vs healthy, in 60 s
- `vmctl.py`       — drive the VM over QMP (click/key/type/screenshot)
- `ppc/`           — Mac OS X 10.4 Tiger (PowerPC) track; separate toolchain
- `docs/NOTES.md`  — the running build log and the list of upstream findings/PRs
- `legacy/`        — the single-VM Sonoma scripts the fleet tooling grew out of
- `results/`       — per-host preflight JSON and per-attempt outcomes

Branch layout:
- `master`            upstream mirror (kholia/OSX-KVM)
- `main`              master + fleet/ (this)
- `macos/<version>`   one per release, branched from main; per-version work/results
- `ppc/tiger`         placeholder for the PowerPC track
- `fix-*`, `docs-*`, `add-*`   upstream PR branches, based on master, no fleet/
