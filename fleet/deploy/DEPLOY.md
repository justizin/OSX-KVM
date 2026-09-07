# Fleet services on og128x01 (Mac Pro, always-on: 128GB / 24c / 1TB)

One published port (**80**), path-routed by an nginx gateway:
- `http://og128x01.hydra-hammerhead.ts.net/`         -> dashboard (add `?view=rotate` on the projector)
- `http://og128x01.hydra-hammerhead.ts.net/mirror/`  -> recovery-image mirror

noVNC live consoles connect the browser directly to each worker's WebSocket port
(not through :80), so workers must be reachable on the tailnet.

## Deploy
    cd ~/OSX-KVM/fleet
    # 1. mirror data (self-contained; ~6 GB, re-downloadable from Apple)
    OSX_KVM=~/OSX-KVM mirror/populate.sh mirror/data
    # 2. bring up gateway + dashboard
    cd deploy
    docker compose config        # validate
    docker compose up -d --build
    curl -sS localhost/status.json            # dashboard alive
    curl -sSI localhost/mirror/index.json     # mirror alive (Accept-Ranges: bytes)

## Point workers at it (Tailscale MagicDNS)
    export MACOS_RECOVERY_MIRROR=http://og128x01.hydra-hammerhead.ts.net/mirror
    export DASHBOARD_URL=http://og128x01.hydra-hammerhead.ts.net
    export VNC_HOST=<this-worker>.hydra-hammerhead.ts.net   # so its console is reachable
    # then: boot-macos.sh <version> --install --headless ; dashboard/publish.sh ...

## Network resilience (wired switch bridged over an unreliable wifi extender)
- Keep Tailscale up; it uses whatever interface is available.
- Add a WiFi backup so Tailscale has a second physical path:
    nmcli device wifi connect "<SSID>" password "<pw>"
    nmcli connection modify "<SSID>" connection.autoconnect yes
- Mac Pro WiFi (Broadcom) on Debian usually needs firmware:
    lspci -nn | grep -i network ; sudo apt-get install -y firmware-brcm80211
- Transfers already tolerate a flaky link: nginx serves /mirror with byte ranges
  (resumable), fetch-macOS falls back to Apple on a miss, dashboard pushes are
  best-effort, and golden images should move with rsync, never scp.

## Troubleshooting "can't reach the dashboard"
    docker compose ps                 # both services Up?
    docker compose logs gateway       # nginx errors?
    ss -ltn | grep ':80 '             # gateway listening on the host?
    # from another tailnet node:
    curl -sS http://og128x01.hydra-hammerhead.ts.net/status.json
