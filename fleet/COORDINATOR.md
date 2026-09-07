# Coordinator handoff — running the fleet from omarchiMac (not the laptop)

The coordinator role is PORTABLE: everything it needs is in this fork, not in any
chat. To coordinate from omarchiMac instead of ugnomarchy (a laptop that should
not be infrastructure):

1. On omarchiMac: clone/pull this fork; ensure `gh auth status` is logged in (for
   pushes) and RC peer messaging is available. Start a Claude Code session there
   and point it at this file + fleet/AGENTS.md.
2. State lives in git:
   - fleet/assignments.json  per-host policy + version assignment (coordinator edits)
   - fleet/results/          per-host/version outcomes (coordinator merges to main)
   - fleet/docs/NOTES.md     findings + upstream PR branches

## Topology (2026-09-07)
- og128x01  Mac Pro, 128GB/24c/1TB, always-on. SERVICES host: mirror :8080 +
  dashboard :8090 (fleet/deploy). Heavy pre-Ventura parallel installs. Reached
  over Tailscale og128x01.hydra-hammerhead.ts.net (+ wifi backup). No AVX2 -> Monterey and older only.
- omarchiMac  i7-7700K, 31GB, AVX2. COORDINATOR + one AVX2 install at a time.
- ugnomarchy  laptop. Disposable worker. NOT infrastructure.

## Live state at handoff
- Mojave installing on ugnomarchy (Penryn / vmxnet3 / ehci HID), paused at the EULA.
- Sonoma workstation image cut: golden/sonoma-workstation.qcow2 (28 GB).
- Preflight in: ugnomarchy (AVX2), omarchiMac (AVX2), og128x01 (no AVX2).
  "Remac macOS configuration tool" preflight still pending; 2 hosts offline.
- Services NOT yet deployed on og128x01 (blocked there: clone approval, docker,
  qemu/dmg2img, kvm group). See deploy/DEPLOY.md.

## Driving one install
    fleet/provision.sh <version>                      # from mirror
    fleet/boot-macos.sh <version> --install [--headless]
    VM=<version> fleet/vmctl.py shot /tmp/s.png        # drive via QMP
    fleet/health.sh <version> 60                       # wedged vs idle vs healthy
    fleet/record.sh <version> &                        # frames + log (run under a watch)
    DASHBOARD_URL=http://og128x01.hydra-hammerhead.ts.net fleet/dashboard/publish.sh <version> ...
Stop at the FIRST Setup Assistant screen and cut the template (before any account).
EULA (Agree) is a human gate on every install. Assign Ventura+ only to AVX2 hosts.
