# Deploying fleet services on og128x01 (Mac Pro, always-on: 128GB / 24c / 1TB)

Prereqs on og128x01: docker + docker compose, git, this fork cloned to ~/OSX-KVM.

## 1. Mirror data (self-contained; no dependency on any other host)
    cd ~/OSX-KVM/fleet/mirror
    OSX_KVM=~/OSX-KVM ./populate.sh ./data      # re-downloads ~6 GB from Apple
    # (or seed once from another host: rsync -a otherhost:~/OSX-KVM/fleet/mirror/data/ ./data/)

## 2. Bring up both services
    cd ~/OSX-KVM/fleet/deploy
    docker compose up -d --build
    #   mirror     -> http://<og128x01>:8080
    #   dashboard  -> http://<og128x01>:8090   (open ?view=rotate on the projector)

## 3. Point workers at og128x01 over Tailscale (survives the wired bridge)
    export MACOS_RECOVERY_MIRROR=http://og128x01.hydra-hammerhead.ts.net:8080
    export DASHBOARD_URL=http://og128x01.hydra-hammerhead.ts.net:8090

## Network resilience — the wired switch is bridged over an unreliable wifi extender
- Tailscale already gives a direct, interface-agnostic path; keep it running.
- Add a WiFi backup so Tailscale has a second physical path if the bridge drops:
    nmcli device wifi list
    nmcli device wifi connect "<SSID>" password "<pw>"
    nmcli connection modify "<SSID>" connection.autoconnect yes
- Mac Pro WiFi (Broadcom) on Debian usually needs firmware. Identify + install:
    lspci -nn | grep -i network
    sudo apt-get install -y firmware-brcm80211    # some chips need broadcom-sta-dkms
- Fleet transfers already tolerate a flaky link: fetch-macOS falls back to Apple
  on a mirror miss, dashboard pushes are best-effort, and golden images should
  move with rsync (resumable), never scp.
