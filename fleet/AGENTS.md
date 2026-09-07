# macOS fleet — runbook for a Claude Code agent on a host

You are running on one physical host. Your job is to install one or more macOS
versions on it, record what happened, and (if the install succeeds) leave behind
a reusable golden image. Another agent is doing the same on other hosts; results
are merged by host + version, so **stay in your lane and report accurately**.

Read this whole file before starting. The failure modes below cost the first
run seven hours; they are all avoidable.

---

## 0. The one strategic rule

**Install each version ONCE across the whole fleet, then clone the image.**

The install is the expensive part: a ~13 GB download, 30–60 min of work, and two
screens (the Apple EULA and Setup Assistant) that a human must complete. Doing
that per host per version is *versions × hosts* of human time. Doing it once per
version and shipping the qcow2 is *versions* of human time.

So before you install anything, check `results/` — if another host already has a
golden image for your target version, ask for the image instead of installing.

---

## 1. Preflight (always, before anything else)

```bash
VM_DIR=$HOME/OSX-KVM ./preflight.sh > results/$(hostname).json
```

Read the human summary on stderr. It tells you:
- which macOS versions this host can run (**AVX2 gates Ventura and newer**)
- how many VMs fit concurrently (RAM and disk)
- any blockers, with the fix

Do not proceed while `blockers` is non-empty. The common ones need root:

```bash
# Arch
yay -S --needed qemu-desktop dmg2img
# every distro: macOS needs this or it faults on MSR access
sudo cp ~/OSX-KVM/kvm.conf /etc/modprobe.d/kvm.conf
echo 1 | sudo tee /sys/module/kvm/parameters/ignore_msrs
```

If you cannot get root, stop and report that — do not work around it.

---

## 2. Provision and install

```bash
./provision.sh mojave            # download + convert + create disk (idempotent)
./boot-macos.sh mojave --install # boots to the OpenCore picker
```

Then drive it with `vmctl.py` (QMP). Coordinates below are for the 1280x800
framebuffer; re-screenshot and re-measure if yours differs.

```bash
./vmctl.py shot /tmp/s.png     # look before every click
./vmctl.py key right ret       # OpenCore picker: select install media, boot
# ~110 s to Recovery
./vmctl.py dclick 640 451      # Disk Utility
```

In Disk Utility the sidebar shows three entries. **Erase the one reporting
~274.88 GB / Uninitialized** — that is the 256 GiB qcow2. The other
`QEMU HARDDISK Media` is OpenCore's boot disk; erasing it breaks the VM.
Defaults in the Erase dialog (APFS + GUID Partition Map) are already correct.

Then quit Disk Utility (`chord meta_l q`) and run the installer.

### Two screens you must NOT automate

- **The Apple software licence agreement.** Accepting a EULA is the operator's
  decision, not the agent's. Stop, tell the human, let them click Agree.
- **Setup Assistant** (country, account name, password). Account credentials are
  the human's to choose.

Everything between and around those two is fair game to automate.

---

## 3. When it looks stuck — check, do not wait

The installer displays a countdown that keeps counting *after it has
deadlocked*. The first run sat at "About 20 minutes remaining" for seven hours.
Upstream's README actively encourages waiting this out; ignore that advice.

```bash
./health.sh mojave 60
```

Verdicts:
- **healthy** — writing MB/s, carry on
- **idle** — no writes but vCPUs quiet: parked at a prompt, look at the screen
- **WEDGED** — no writes *and* all vCPUs pegged, and/or the guest RIP is frozen

Recovery from WEDGED: kill QEMU, confirm `CORES=2 THREADS=4`, boot again and
select the **macOS Installer** entry in the picker. It does *not* auto-boot
after a hard reset (it does after the installer's own reboot — different case).

### Do not "tune" the VM

Raising `-smp` from the stock `4,cores=2` to `8,cores=4` is the prime suspect for
that deadlock. It is not a proven cause — the fix was confounded with a reboot —
but stock topology completed the phase the tuned one died in. If you want to
test the tuned config, do it deliberately and record it as an experiment, not as
a default. Extra RAM (8192) appeared harmless.

---

## 4. Golden image

Once Setup Assistant is done and the VM boots to a desktop:

```bash
pkill -f "osx-<version>-qmp"          # shut the VM down cleanly first
qemu-img convert -O qcow2 -c \
  vms/<version>/mac_hdd_ng.img golden/<version>-golden.qcow2
qemu-img info golden/<version>-golden.qcow2
sha256sum golden/<version>-golden.qcow2 > golden/<version>-golden.sha256
```

`-c` compresses; a 30 GB Sonoma image shrinks a lot and ships faster. Receiving
hosts drop it in as `vms/<version>/mac_hdd_ng.img` and run `boot-macos.sh` with
no `--install`.

**Each VM needs its own `OVMF_VARS.fd`** — that file is NVRAM. `boot-macos.sh`
copies one per VM automatically. Upstream points every VM at the single file in
the repo, so two concurrent VMs would corrupt each other's boot entries. Do not
share it, and do not copy a golden image's NVRAM between hosts.

---

## 5. What to report back

Append one JSON object per (host, version) attempt to `results/<hostname>.json`
under an `attempts` key, or write `results/<hostname>-<version>.json`:

```json
{
  "host": "...", "version": "mojave", "started": "...", "ended": "...",
  "outcome": "success | wedged | failed | blocked",
  "cpu_model_used": "Penryn",
  "smp": "4,cores=2", "ram_mb": 8192,
  "install_minutes": 47,
  "golden_image": "golden/mojave-golden.qcow2",
  "sha256": "...",
  "notes": "what actually happened, including anything you had to do by hand"
}
```

Report failures as failures. A wedged install that you rebooted into working is
`"outcome": "success"` with the wedge described in `notes` — that detail is the
most valuable thing the matrix produces.

---

## 6. What the matrix is actually testing

`versions.sh` maps each release to a `-cpu` model:

- High Sierra … Monterey → `Penryn`
- Ventura and newer → `Skylake-Client,-hle,-rtm` (and these need host AVX2)

**Treat that mapping as a hypothesis, not fact.** Upstream now ships
`Skylake-Client` active for *everything*, with `Penryn` commented out; the split
above is inferred from the script's own comments, which are themselves stale
(they still tell you to change `Penryn` to `Haswell-noTSX` for Sonoma, though
`Penryn` is already disabled). Nobody has published a tested matrix. Producing
one is the point of this exercise, and it is a genuine contribution back to the
project.

So when a version works, record **which `-cpu` you actually used**. When one
fails, try the other model before calling it unsupported.

### Mojave specifically

Mojave (10.14) is the last macOS that runs 32-bit applications — Catalina
removed them entirely. It is the correct target for pre-subscription Adobe and
similar Intel-era software, and it is worth getting right even if newer versions
prove easier.

---

## 7. Second track: Mac OS X 10.4 (PowerPC)

`ppc/` is a **separate track** that shares no code with the above, because it
cannot: OpenCore, AppleSMC and KVM are x86-only. It targets a Titanium PowerBook
(G4) and a dual G3 PowerMac via `qemu-system-ppc -M mac99`.

Read `ppc/CAVEATS.md` first. The three that change conclusions:

- **No SMP** — a dual G3 cannot be reproduced in a VM at all.
- **AltiVec** — `mac99` is a G4 and has it; G3s do not. Software needing AltiVec
  passes in the VM and fails on the real G3. `boot-tiger.sh` defaults to
  `-cpu g3` to surface that class of failure in the VM instead.
- **No download path** — Apple serves 10.13+ only. Retail PPC media required.

Also full software emulation (no KVM), so it answers "does this config work",
never "is this fast enough".

Before trusting it, verify `-M mac99` boots Tiger with `-cpu g3` on your host and
record the result — that combination is assumed, not yet proven.

---

## 8. Display on Wayland / HiDPI hosts (confirmed fix)

On Hyprland/Omarchy (and likely GNOME/KDE Wayland) the VM *looks* broken:
untrackable cursor, smeared rendering, shimmering controls. The guest is fine —
`screendump` frames are pixel-stable. It's the GTK display path under fractional
scaling. `boot-macos.sh` already exports the fix:

```bash
export GDK_SCALE=1
export GDK_BACKEND=x11     # run QEMU under XWayland
```

Consequences to know:
- Window class becomes `Qemu-system-x86_64` (XWayland) instead of `qemu`.
  Match both in any window rule.
- GTK hotkeys: **Ctrl+Alt+F** fullscreen toggle (hides the menu bar),
  **Ctrl+Alt+G** release grab, **Ctrl+Alt+U** native size, View → Zoom To Fit.
- Inside macOS: physical **Alt = Option**, **Super = Command**. Alt+letter types
  accented characters (Option+A = `å`). Tab only reaches text fields until Full
  Keyboard Access is on. Neither is a bug.

Do not float, resize or fullscreen the operator's windows from a script.

---

## 9. Where to freeze the template (decided 2026-09-07)

Freeze each version's golden image **at the first Setup Assistant screen**
("Select Your Country or Region"), *before* any account exists. Clones then run
Setup Assistant themselves and get their own account, hostname and identifiers.

Procedure: when Setup Assistant appears, do NOT click anything. Shut the VM
down cleanly from the host (`vmctl.py`/QMP `system_powerdown`, or just kill
QEMU — the installer has already committed), then:

    qemu-img convert -O qcow2 -c vms/<v>/mac_hdd_ng.img golden/<v>-template.qcow2

A VM that has gone past account creation is a *workstation* image, not a
template — keep it if useful, name it `<v>-workstation.qcow2`, but do not clone
it to other hosts.

Sonoma on the first host went past this point before the rule existed; its
template will come from a second install (cheap now: recovery image is
mirrored, the process is scripted).
