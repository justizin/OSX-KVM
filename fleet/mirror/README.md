# mirror/ — local HTTP mirror for macOS recovery images

`fetch-macOS-v2.py` (with the `mirror-env-var` patch) honours two env vars:

- `MACOS_RECOVERY_MIRROR=http://host:8080` — try `<mirror>/<product>/<file>` first, fall back to Apple
- `MACOS_RECOVERY_OUTDIR=/path` — where downloads land (overrides `-o` and the interactive default `.`)

Populate once, on any host with internet:

    ./populate.sh ./data            # all versions;  ./populate.sh ./data mojave sonoma

Serve it:

    docker compose up -d            # nginx on :8080, tree from ./data (MIRROR_ROOT to override)
    ./serve.sh ./data 8080          # or, without a container

Clients:

    export MACOS_RECOVERY_MIRROR=http://mirror-host:8080
    fleet/provision.sh mojave       # now pulls from the LAN

What it does NOT cache: the ~13 GB full installer that "Reinstall macOS" pulls
from Apple's CDN during the install itself. Only the recovery images
(BaseSystem.dmg/.chunklist, 0.7–3 GB per version) go through fetch-macOS-v2.py.
The full-installer bandwidth is what the golden-image strategy avoids.

## Snapshot 2026-09-07

`populate.sh` pulled all nine versions in one run: 5.8 GB total, product ids
and sha256s recorded in `fleet/results/mirror-index-2026-09-07.json`. Product
ids are what Apple's recovery service handed out on that date; re-run
`populate.sh` to pick up newer builds (the index keys by shortname, so a new
product id for a version replaces the old entry).

## If `docker compose` says permission denied

Check the group *database*, not just your shell: `getent group docker` must
list your user. A `usermod -aG docker` run without the username on the end
succeeds silently and adds nobody. Until the container runs, `./serve.sh` is
functionally equivalent.
