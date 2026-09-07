#!/usr/bin/env bash
# Populate the mirror tree with every recovery image fetch-macOS-v2.py knows.
#   ./populate.sh [root=./data] [version ...]     (default: all versions)
# Idempotent: a product dir that already verifies is skipped.
# Layout: <root>/<product id>/BaseSystem.{dmg,chunklist} + <root>/index.json
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../versions.sh"
OSX_KVM="${OSX_KVM:-$HOME/OSX-KVM}"
ROOT="${1:-$HERE/data}"; shift || true
FETCH="$OSX_KVM/fetch-macOS-v2.py"
[ -x "$FETCH" ] || { echo "fetch-macOS-v2.py not found at $FETCH (set OSX_KVM=)" >&2; exit 1; }
mkdir -p "$ROOT"
INDEX="$ROOT/index.json"; [ -f "$INDEX" ] || echo '{}' > "$INDEX"

want=("$@"); [ ${#want[@]} -gt 0 ] || mapfile -t want < <(version_keys)

for key in "${want[@]}"; do
  version_exists "$key" || { echo "!! unknown version $key" >&2; continue; }
  short="$(version_field "$key" 3)"
  # already have it? (index maps shortname -> product)
  prod="$(python3 -c "import json,sys;print(json.load(open('$INDEX')).get('$key',{}).get('product',''))")"
  if [ -n "$prod" ] && [ -s "$ROOT/$prod/BaseSystem.dmg" ] && [ -s "$ROOT/$prod/BaseSystem.chunklist" ]; then
    echo "== $key: have $prod, skipping"; continue
  fi
  stage="$(mktemp -d "$ROOT/.stage-$key.XXXX")"
  echo "== $key ($short): downloading"
  # the product id is only known once Apple answers; it is printed as "Downloading <id>..."
  log="$stage/fetch.log"
  if ! MACOS_RECOVERY_OUTDIR="$stage" "$FETCH" -s "$short" 2>&1 | tr '\r' '\n' | tee "$log" | grep -aE "^Downloading|complete|Mirror|Error" ; then :; fi
  prod="$(grep -aoE '^Downloading [0-9A-Za-z-]+' "$log" | head -1 | awk '{print $2}' | tr -d '.')"
  if [ -z "$prod" ] || [ ! -s "$stage/BaseSystem.dmg" ] || [ ! -s "$stage/BaseSystem.chunklist" ]; then
    echo "!! $key: download failed (see $log)" >&2; continue
  fi
  mkdir -p "$ROOT/$prod"
  mv -f "$stage/BaseSystem.dmg" "$stage/BaseSystem.chunklist" "$ROOT/$prod/"
  sha="$(sha256sum "$ROOT/$prod/BaseSystem.dmg" | cut -d' ' -f1)"
  size="$(stat -c %s "$ROOT/$prod/BaseSystem.dmg")"
  python3 - "$INDEX" "$key" "$short" "$prod" "$sha" "$size" <<'PY'
import json,sys,datetime
p,key,short,prod,sha,size=sys.argv[1:]
d=json.load(open(p)); d[key]={"shortname":short,"product":prod,"dmg_sha256":sha,"dmg_bytes":int(size),
  "fetched":datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}
json.dump(d,open(p,"w"),indent=2,sort_keys=True)
PY
  rm -rf "$stage"
  echo "== $key -> $prod ($size bytes, sha256 $sha)"
done
echo; echo "index:"; cat "$INDEX"
