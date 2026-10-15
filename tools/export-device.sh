#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs on the maintainer's computer (where the Garmin SDK Manager downloaded
# the devices). Packs the official definition of one or more watch models plus
# only the fonts they need, so the build environment can use them.
#
# Usage:  bash export-device.sh <device_id> [device_id...]
#   e.g.  bash export-device.sh fenix7xpro epix2pro47mm
# Or straight from GitHub:
#   curl -sL https://raw.githubusercontent.com/Vit882/raysid-for-garmin-/main/tools/export-device.sh | bash -s fenix8solar51mm
#
# Result: ~/raysid-devices.zip (Garmin license: do not publish it).
set -e
CIQ="${CIQ_HOME:-$HOME/.Garmin/ConnectIQ}"
[ $# -ge 1 ] || { echo "Usage: bash export-device.sh <device_id> [device_id...]"; echo "Downloaded devices:"; ls "$CIQ/Devices" 2>/dev/null | tr '\n' ' '; echo; exit 1; }
cd "$CIQ"
LIST=$(mktemp)
for ID in "$@"; do
    if [ ! -f "Devices/$ID/compiler.json" ]; then
        echo "Device '$ID' is not downloaded. Open the SDK Manager > Devices and download it."
        echo "Downloaded devices that look similar:"; ls Devices | grep -i "${ID:0:5}" | tr '\n' ' '; echo
        exit 1
    fi
    echo "Devices/$ID" >> "$LIST"
    # fonts of the worldwide font set ("ww") named in simulator.json
    python3 - "$ID" >> "$LIST" <<'PY'
import json, sys, os
s = json.load(open(os.path.join("Devices", sys.argv[1], "simulator.json")))
for fs in s.get("fonts", []):
    if fs.get("fontSet") != "ww":
        continue
    for f in fs.get("fonts", []):
        for ext in (".cft", ".md5", ".ttf"):
            p = os.path.join("Fonts", f["filename"] + ext)
            if os.path.exists(p):
                print(p)
PY
done
OUT="$HOME/raysid-devices.zip"
rm -f "$OUT"
sort -u "$LIST" | zip -q -r "$OUT" -@
rm -f "$LIST"
ls -lh "$OUT"
echo "Send $OUT to Claude (it contains: $*)."
