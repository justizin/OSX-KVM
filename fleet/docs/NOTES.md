# OSX-KVM on Omarchy/Arch — build log & contribution notes

Started: 2026-09-05
Repo: https://github.com/kholia/OSX-KVM.git @ 4c378a4 ("Support for macOS Tahoe", 2026-01-26)
Target: macOS Sonoma (14) — the RECOMMENDED default in `fetch-macOS-v2.py`

## Host

| | |
|---|---|
| Distro | Omarchy 4.0.2 (Arch-based, `ID_LIKE=arch`) |
| Kernel | 7.1.9-arch1-2 |
| CPU | Intel Core i7-9750H (Coffee Lake-H, 6C/12T), VT-x |
| CPU flags | `vmx sse4_2 avx avx2 aes xsave` — meets AVX2 requirement for >= Ventura |
| RAM | 62 GiB |
| Disk | 880 GiB free on /home (LUKS `/dev/mapper/root`) |
| KVM | `kvm_intel` loaded, `/dev/kvm` mode 0666 |
| QEMU | 11.1.0 (repo requires >= 8.2.2) |

## Findings so far (candidate contributions)

### 1. README's dependency list is Debian-only
`README.md` "Installation Preparation" gives a single `apt-get install` line and says
"This step may need to be adapted for your Linux distribution." No Arch/Fedora
equivalents anywhere in the repo. Arch mapping worked out here:

| Debian package | Arch package | Needed for |
|---|---|---|
| `qemu-system` | `qemu-desktop` (extra) | core; `qemu-full` also fine |
| `dmg2img` | `dmg2img` (**AUR**) | BaseSystem.dmg -> .img |
| `p7zip-full` | `7zip` (p7zip renamed) | optional |
| `uml-utilities` | `uml_utilities` (**AUR**) | only for tap/bridge networking |
| `libguestfs-tools` | `libguestfs` (**AUR**) | not needed for base install |
| `genisoimage` | `cdrtools` / `cdrkit` | only for the ISO scripts |
| `tesseract-ocr` | `tesseract` + `tesseract-data-eng` | only for OCR automation |
| `net-tools`, `screen`, `vim`, `make`, `wget` | same names | mostly optional |

Minimal set actually required for a CLI install: **`qemu-desktop` + `dmg2img`**.
`edk2-ovmf` is NOT needed — the repo ships its own `OVMF_CODE_4M.fd` / `OVMF_VARS-*.fd`.

-> PR idea: add a distro matrix table to README (Arch/Fedora/openSUSE), and mark
   which packages are optional vs required. Low-risk docs PR, directly matches the
   maintainer's "Robustness improvements / documentation" asks in `Contributing Back`.

### 2. `-cpu` model guidance is contradictory
- `OpenCore-Boot.sh` header comment: "Change `Penryn` to `Haswell-noTSX` for macOS Sonoma!"
- `notes.md` "macOS Sonoma support": same advice.
- But the *active, uncommented* line in `OpenCore-Boot.sh` is already
  `-cpu Skylake-Client,-hle,-rtm,...` labelled "Enable this line for macOS Sequoia and Tahoe",
  and `Penryn` is the commented-out one.

So both comments reference a state of the file that no longer exists. A first-time
user following the Sonoma advice literally goes looking for a `Penryn` to edit and
finds it already disabled.

-> PR idea: rewrite those comments as a version->CPU-model table and delete the stale
   "change Penryn to X" instructions.

### 3. `fetch-macOS-v2.py -s <shortname>` is undocumented
README only shows the interactive menu. The script accepts `-s sonoma` (also
`high-sierra`, `mojave`, `catalina`, `big-sur`, `monterey`, `ventura`, `sequoia`,
`tahoe`) for a non-interactive download — essential for scripting/CI/build-farm use,
which is itself one of the maintainer's listed wanted contributions.

Caveat found by reading the code: if the shortname doesn't match any product, the
loop falls through and `index` ends up == len(products), which would IndexError.
The interactive path guards bad input; the `-s` path does not.

-> PR idea (code): document `-s` in README + make an unknown shortname exit with a
   clear error listing valid names, instead of an IndexError traceback.

## Paying for assistance

The maintainer (Dhiru Kholia) states availability in README for **commercial support
options only**, via dhiru.kholia@gmail.com. Two distinct tracks in the README:

1. **Commercial support** — mailto link with subject
   `[GitHub] OSX-KVM Commercial Support Request`. Mentions `Content Caching` help.
2. **Sponsorship** — "Project sponsors get access to the `Private OSX-KVM` repository,
   and direct support."
3. **Funded work** — the "Setting Expectations Right" section explicitly asks for
   funding to resume work on GPU accel / sound / USB 3:
   mailto subject `[GitHub] OSX-KVM Funding Support`.

No public price list, no GitHub Sponsors button seen in-repo. Sponsorship is the
lever if we want the private repo + direct support; funded work is the lever if we
specifically need graphics/sound/USB3 to be better.

## Build log

### Steps that worked (Omarchy/Arch, 2026-09-05)

```bash
git clone https://github.com/kholia/OSX-KVM.git      # -> 4c378a4
yay -S --needed qemu-desktop dmg2img                 # only 2 packages actually needed
sudo cp OSX-KVM/kvm.conf /etc/modprobe.d/kvm.conf    # persist ignore_msrs=1
echo 1 | sudo tee /sys/module/kvm/parameters/ignore_msrs   # apply now

cd OSX-KVM
./fetch-macOS-v2.py -s sonoma          # non-interactive; product 696-08090, 789 MB, ~40s
dmg2img -i BaseSystem.dmg BaseSystem.img   # 7.5s -> 3.0 GB raw, 8 partitions
qemu-img create -f qcow2 mac_hdd_ng.img 256G
./OpenCore-Boot.sh
```

Timings on this host: download ~40 s, dmg2img 7.5 s, qcow2 create instant.
First boot to OpenCore picker: a few seconds. OpenCore build shown: REL-106-2025-11-03.

No changes to `OpenCore-Boot.sh` were needed. The stock `Skylake-Client` `-cpu` line
booted Sonoma fine on Coffee Lake — contradicting the repo's "use Haswell-noTSX for
Sonoma" advice (see finding #2). Local tuning lives in a *copy* of the script
(`../osx-kvm-notes/boot-sonoma.sh`, 8 GiB / 4c8t) so the upstream tree stays clean
for PRs — `git status` is empty apart from the generated .img files.

Note: `BaseSystem.dmg`, `BaseSystem.img`, `mac_hdd_ng.img` are untracked build
artifacts sitting in the repo working dir; upstream `.gitignore` covers them.

### 4. No headless/automated verification path
There is no way to check "did it boot?" without a GUI. Useful trick worth
documenting: swap `-monitor stdio` for a unix socket and use `screendump`:

```bash
# in the boot script
-display none -vnc 127.0.0.1:1
-monitor unix:/run/user/1000/osx-kvm-mon.sock,server,nowait
# then, from the host
echo "screendump /tmp/shot.ppm" | socat -u - UNIX-CONNECT:/run/user/1000/osx-kvm-mon.sock
```

This gives a scriptable smoke test (boot -> screendump -> confirm OpenCore picker),
which is exactly what the maintainer's "launch a bunch of headless macOS VMs (build
farm)" and "automate the macOS installation via OpenCV" work items would need as a
foundation. `boot-macOS-headless.sh` exists but is for running an *already installed*
VM, not for verifying a boot.

-> PR idea: add a `--smoke-test` or a small `run-diagnostics`-style script that boots,
   screendumps, and exits non-zero if the picker never appears. Pairs naturally with
   the OpenCV item, since screendump is the frame source OpenCV would consume.

## Automating the installer (QMP) — 2026-09-05

Built `vmctl.py` (in this dir) to drive the VM programmatically. Findings:

### 5. HMP cannot click; you need QMP
This is the key technical blocker for the maintainer's "automate the macOS
installation via OpenCV" work item, and it is written down nowhere:

- `OpenCore-Boot.sh` attaches `-device usb-tablet`, an **absolute** pointer.
- QEMU's HMP `mouse_move x y` only emits **relative** events. An absolute
  device ignores them, so the cursor never moves. Confirmed by screendump:
  cursor stayed at its origin after `mouse_move 640 451`.
- HMP `sendkey` *does* work (verified: `sendkey right` moved the OpenCore
  picker selection).
- The working approach is QMP `input-send-event` with `abs` axes, values
  scaled to **0..32767** over the framebuffer:

  ```json
  {"execute":"input-send-event","arguments":{"events":[
    {"type":"abs","data":{"axis":"x","value": x*32767/width }},
    {"type":"abs","data":{"axis":"y","value": y*32767/height}}]}}
  ```

  followed by `{"type":"btn","data":{"down":true,"button":"left"}}` / `false`.

So a scripted install needs `-qmp unix:...,server,nowait` added to the boot
script. Upstream ships neither a QMP socket nor a HMP socket — it hardcodes
`-monitor stdio`, which is unusable from a script.

-> PR idea: add commented-out `-monitor unix:...` and `-qmp unix:...` lines to
   `OpenCore-Boot.sh` with a one-line comment on why (absolute pointer needs QMP).
   Tiny diff, unblocks every automation effort downstream.

### 6. OpenCore's boot picker ignores tablet input
Mouse events reach macOS fine but do **nothing** in the OpenCore picker — the
cursor doesn't even repaint in a screendump. Keyboard (`right`/`ret`) works.
So automation must drive the picker by keyboard and only switch to mouse once
macOS itself is up. Worth documenting; it looks like a broken harness otherwise.

### Installer walkthrough (all driven over QMP, coords at 1280x800)
1. Boot picker: `key right`, `key ret`  -> Recovery in ~110 s
2. Recovery menu: double-click Disk Utility at (640, 451)
3. Sidebar lists 3 entries. The install target is the one showing
   **274.88 GB / Uninitialized** (= the 256 GiB qcow2). The *other*
   `QEMU HARDDISK Media` is OpenCore's boot disk — do not erase it.
   Recovery's own volume shows as `disk2s1`, 2.87 GB, macOS 14.6.1 (23G93).
4. Erase toolbar button at (968, 150). Dialog defaults are already correct:
   APFS + GUID Partition Map. Typed name "Macintosh HD", Erase at (827, 512).
   Completed in <15 s.
5. `chord meta_l q` to quit Disk Utility, back to Recovery menu.
6. Double-click "Reinstall macOS Sonoma" at (640, 267).
7. Continue at (640, 642) -> "Loading installation information..." ~75 s.
8. **License agreement — stopped here.** Accepting Apple's EULA is the operator's
   decision, not something to automate on someone else's behalf. Note the pane
   reads "The license agreement is unavailable" (text not fetched in Recovery).

Reality check on step 8 for any future full automation: a build-farm script would
have to click Agree, i.e. programmatically accept the Apple EULA. That is a
licensing question the project should probably address explicitly in its docs
rather than leave implicit in an automation script.

---

## Prepared PR branches (local only — nothing pushed)

All four branch off upstream `master` (4c378a4) in `/home/zin/Work/OSX-KVM`.
Each is one self-contained change, which is how this maintainer's tree is
organised (README: "This repository uses rebase based workflows heavily").

| Branch | Type | Change |
|---|---|---|
| `fix-product-selection` | code | `fetch-macOS-v2.py`: 3 bad-input paths -> clear error + exit 1 |
| `add-monitor-sockets` | code (comments) | `OpenCore-Boot.sh`: document `-monitor unix:` / `-qmp unix:` + why QMP is required |
| `fix-stale-cpu-advice` | docs | Remove the "Penryn -> Haswell-noTSX for Sonoma" advice that no longer matches the file |
| `docs-distro-deps` | docs | README: Arch package names, which deps are optional, no edk2/ovmf needed |

### Evidence gathered for `fix-product-selection`
Reproduced all three against upstream before patching, and re-ran after:

| Input | Before | After |
|---|---|---|
| `-s bogus` | `IndexError: list index out of range` | error naming all 9 valid shortnames, exit 1 |
| interactive `abc` | **silently downloaded Tahoe** (`140-93589`) | `ERROR: Enter a number between 1 and 9.` |
| interactive `20` | `IndexError` | `ERROR: Enter a number between 1 and 9.` |
| `-s sonoma` | `Downloading 696-08090...` | unchanged |
| interactive `3` | Catalina `2Z694-25616` | unchanged |

The `abc` case is the nastiest: `index` leaks from the earlier
`for index, product in enumerate(products)` loop, so `except: pass` leaves it
at `len(products)-1`. Garbage input silently gets you the *newest* macOS
instead of an error — a build farm could be pulling the wrong OS for months.

### Submitting
Upstream takes PRs on GitHub (kholia/OSX-KVM). Suggested order — lead with the
two docs PRs (uncontroversial, build trust), then `fix-product-selection`
(clear repro, tiny diff), then `add-monitor-sockets` (comments only, but it is
really a proposal about automation direction, so it may attract discussion).

Nothing has been pushed and no fork has been created. `master` is untouched at
4c378a4 and the working tree is clean apart from gitignored build artifacts.

## Open question worth raising upstream before any paid work

A fully automated install has to click **Agree** on Apple's SLA
programmatically. The README is careful to put the EULA decision on the user
("It is your responsibility to understand, and accept (or not accept) the Apple
EULA"), but the "automate the macOS installation via OpenCV" work item quietly
requires automating exactly that acceptance. Worth getting the maintainer's
position in writing before funding work in that direction — it affects whether
a build-farm setup can be distributed at all, or only run privately.

## Reboot behaviour (useful for unattended installs)

At 15:48, ~13 min after starting, the installer finished its download phase and
rebooted itself. **OpenCore auto-booted the correct volume with no keypress.**
`OpenCore/config.plist` has `Timeout = 2` (and `ShowPicker = true`), so the
picker appears for 2 s and then boots the default entry, which the installer has
blessed via NVRAM. Phase 2 ("About 29 minutes remaining") then runs on its own.

This matters for the build-farm idea: the reboot in the middle of an install
does *not* need a driver to hit the picker, despite the picker ignoring mouse
input. Only the pre-install steps (Disk Utility, installer wizard) need driving.

Caveat: NVRAM persistence depends on `OVMF_VARS-*.fd` being writable, which the
boot script does provide (`-drive if=pflash,...` without `readonly=on`). Note
that file is tracked in git *and* matched by the `.gitignore` pattern
`OVMF_VARS*.fd` — gitignore does not apply to already-tracked files, so a VM
that writes NVRAM would show `OVMF_VARS-1920x1080.fd` as modified in
`git status`. (Not observed in this run — the file's mtime never changed, so
OpenCore/macOS did not write to it here.)

---

## 7. The install hung hard — and the repo has zero troubleshooting guidance

**What happened.** Phase 2 of the Sonoma install wedged at 15:58, ~10 min after
the post-download reboot. It stayed wedged for **>7 hours** while *looking* like
it was working: Apple logo, progress bar, "About 20 minutes remaining...".

**How to tell a wedged macOS VM from a slow one.** The screen is useless — the
progress text is a stale extrapolation, not a live readout. What actually
distinguishes them:

| Signal | Hung | Healthy |
|---|---|---|
| `wchar` delta on the QEMU pid | ~16 KB/60 s (all 1-byte poll syscalls) | ~500 MiB/60 s |
| disk image mtime | frozen (83+ min stale) | current |
| vCPU threads (`top -H`) | *all* pegged ~99% | mostly idle/bursty |
| `RIP` from `info registers`, sampled 3x | identical every time | moves |

The RIP check is the clincher: `RIP=ffffff8020380b12` (an XNU kernel address)
was byte-identical across samples seconds apart. All vCPUs spinning + a frozen
kernel RIP + zero I/O = spinlock deadlock, not slowness.

Grep the whole repo for `hang|stuck|freez|spin|black screen` and you get nothing
relevant. The README's only advice is the opposite — "let setup sit ... for a
while if things are being slow" — which actively encourages waiting out a real
deadlock. I waited 7 hours on that advice.

**Suspected cause: my own SMP tuning.** I had raised the stock
`-smp 4,cores=2,sockets=1` to `-smp 8,cores=4,sockets=1` (and RAM 4096 -> 8192).
Reverting *only* the topology to stock and rebooting resumed the install
immediately, and it wrote 499 MiB in the first 60 s.

**Honest caveat:** this is not a controlled result. I changed the topology *and*
hard-reset the VM in one step, so I cannot separate "wrong topology" from "the
reset cleared a transient deadlock". To attribute it properly you would need to
re-run the install at 4c/8t and see whether it wedges again. What *is* solid is
that the stock topology completed the phase the tuned one deadlocked in.

-> PR idea (docs): a short "My install is stuck" section with the four checks
   above. It is cheap, and it converts the single most common failure from
   "wait indefinitely" into a 60-second diagnosis. This is also the strongest
   candidate of everything found here, because the current README text makes
   the problem *worse*.

-> Related: if CPU topology really is the trigger, `OpenCore-Boot.sh` deserves a
   warning next to `CPU_CORES`/`CPU_THREADS` saying macOS is topology-sensitive
   and that raising them is not a free win. Needs the controlled re-run first.

### Correction to the earlier "auto-boot" note
Section "Reboot behaviour" above says OpenCore auto-boots without a keypress.
That holds for the installer's *own* reboot, but **not** after a hard reset: on
restart the picker gained a third entry (`macOS Installer`) and sat there
waiting, defaulting to `EFI`. Resuming needed `key right right` + `ret`. So an
unattended build farm still needs picker automation for any crash-recovery path.

## 9. Host display stack makes the VM look broken (Omarchy/Hyprland, HiDPI)

Symptom reported by the operator: mouse impossible to track while moving,
rendering artifacts, "constant idle fluctuation in some of the controls",
keyboard navigation apparently ineffective. Reproduces on multiple Omarchy
machines at any resolution, tiled or fullscreen.

What was PROVEN (screendump reads the guest framebuffer, bypassing the display):
- 6 consecutive idle guest frames: 0 pixels differ. The guest is stable.
- QMP absolute pointer -> guest lands pixel-exact. Tablet mapping is correct.
So macOS, the tablet device and QEMU's input path are all fine. The corruption
is introduced between QEMU's GTK display and the screen.

What was NOT measured: actual host rendering. Two host captures were invalid
(idle animation, then the lock screen) -- the operator was remote. Do not
repeat my mistake of diffing host frames without first viewing one.

Omarchy-specific, resolution-independent factors on that path, all of which
reproduce on every machine sharing the same config:
1. Every window gets `default-opacity` 0.985/0.96 -- and the wallpaper is an
   ANIMATED starfield. Stars drifting behind flat UI = "fluctuation in controls".
2. Hyprland fractional scale 1.5 -> GTK renders at 2x buffer scale, compositor
   downscales -> smeared cursor trails / edges = "hard to track when moving".
3. `GDK_SCALE=2` exported session-wide (~/.config/hypr/monitors.lua) on top.
4. Optimus laptop: i915 + nvidia proprietary, __GLX_VENDOR_LIBRARY_NAME=nvidia.

Mitigation applied to both launchers (TEST, not yet confirmed by the operator):
`export GDK_SCALE=1; export GDK_BACKEND=x11` -> QEMU runs under XWayland, the
compositor scales a plain bitmap, GTK's Wayland fractional-scale and pointer
paths are bypassed. Side effect: window class becomes `Qemu-system-x86_64`
(was `qemu`), so window rules must match both.

Still to do: an `opaque`/opacity-1 window rule for the QEMU window (removes the
animated-wallpaper bleed regardless of backend). Config change -> needs OK.

-> Upstream: OSX-KVM's scripts assume a plain X11 desktop. A short "HiDPI /
   Wayland desktops" note (GDK_SCALE, XWayland, compositor opacity rules) would
   save every GNOME/KDE/Hyprland user from concluding macOS's mouse is broken.

### 9 — RESOLVED (operator-confirmed 2026-09-07)
`export GDK_BACKEND=x11; export GDK_SCALE=1` in the launcher (QEMU under
XWayland) fixed the mouse tracking and the rendering artifacts. Operator: "that
fixed it." The opacity/animated-wallpaper idea was not needed and was not applied.

The "keyboard doesn't work" part turned out to be macOS semantics, not the
input path: physical Alt = Option (Option+A types `å`), physical Super = Command,
and Tab only cycles text fields until Full Keyboard Access is enabled
(System Settings > Keyboard > Keyboard navigation). Stray `å` characters in
Setup Assistant's Full Name field were Alt+A from Linux muscle memory.

QEMU GTK hotkeys worth knowing on this stack: Ctrl+Alt+F toggle fullscreen
(hides the menu bar -- easy to "lose" the controls), Ctrl+Alt+G release grab,
Ctrl+Alt+U restore native size, View > Zoom To Fit (menu only).

-> Upstream PR candidate #5: a "Wayland / HiDPI desktops" note in README plus the
   two exports in OpenCore-Boot.sh. Reproduced on multiple Omarchy machines;
   would apply to GNOME/KDE Wayland users too.

## 10. Local recovery-image mirror (PR branch `mirror-env-var`, f53f2d9)

`fetch-macOS-v2.py` now honours `MACOS_RECOVERY_MIRROR` (try
`<mirror>/<product>/<file>` first, fall back to Apple) and `MACOS_RECOVERY_OUTDIR`
(replaces the hard-coded `.` on the interactive path). Both no-ops when unset.

Gotcha that the first version of the patch got wrong: `run_query()` handles
HTTPError by calling `sys.exit(1)` itself, so a caller cannot catch a 404 from
`save_image()`. A mirror miss killed the script and left a 0-byte chunklist.
Fixed with a HEAD probe before handing the mirror URL to `save_image()`.
Tested: hit, 404, connection refused, env unset.

`fleet/mirror/`: nginx Containerfile + compose, `serve.sh` (python http.server
fallback), `populate.sh` (all versions -> `<root>/<product>/`, `index.json`
with sha256, idempotent). Product ids come from the script's own
"Downloading <id>..." line, since Apple only reveals them per query.

Scope limit worth stating upstream: this caches the *recovery* image only. The
~13 GB full installer that "Reinstall macOS" streams from Apple's CDN during
the install is not touched by fetch-macOS-v2.py; the golden-image strategy is
what removes that cost.
