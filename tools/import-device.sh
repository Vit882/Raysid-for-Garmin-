#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build-environment side of export-device.sh: unpacks the zip into the toolchain
# (TOOLCHAIN, default /mnt/project-files/.toolchain) and into ~/.Garmin/ConnectIQ,
# then prints the facts that matter when porting the app to that model.
#
# Usage:  bash tools/import-device.sh /path/to/raysid-devices.zip
set -e
ZIP="$1"
[ -f "$ZIP" ] || { echo "Usage: bash tools/import-device.sh <zip>"; exit 1; }
TC="${TOOLCHAIN:-/mnt/project-files/.toolchain}"
CIQ="$HOME/.Garmin/ConnectIQ"
TMP=$(mktemp -d)
unzip -q "$ZIP" -d "$TMP"
mkdir -p "$TC/Devices" "$TC/Fonts" "$CIQ/Devices" "$CIQ/Fonts"
for D in "$TMP"/Devices/*/; do
    ID=$(basename "$D")
    rm -rf "$TC/Devices/$ID" "$CIQ/Devices/$ID"
    cp -r "$D" "$TC/Devices/$ID"
    cp -r "$D" "$CIQ/Devices/$ID"
    python3 - "$D" <<'PY'
import json, math, os, sys
d = sys.argv[1]
c = json.load(open(os.path.join(d, "compiler.json")))
s = json.load(open(os.path.join(d, "simulator.json")))
mem = {a["type"]: a["memoryLimit"] for a in c.get("appTypes", [])}
disp = s.get("display", {})
loc = disp.get("location", {})
print("== %s (%s)" % (c["deviceId"], c.get("displayName")))
print("   %s, %dx%d, %s, %s bpp, API %s, part %s" % (disp.get("shape"), c["resolution"]["width"], c["resolution"]["height"],
      c.get("displayType"), c.get("bitsPerPixel"), c.get("deviceGroup"), c.get("worldWidePartNumber")))
print("   launcher icon %sx%s, watchApp memory %s B, storage %s B, touch %s" % (c["launcherIcon"]["width"], c["launcherIcon"]["height"],
      mem.get("watchApp"), s.get("appStorageCapacity"), disp.get("isTouch")))
if loc:
    cx, cy = loc["x"] + loc["width"] / 2, loc["y"] + loc["height"] / 2
    for k in s.get("keys", []):
        if k.get("isHold"):
            continue
        l = k["location"]
        a = math.degrees(math.atan2(-(l["y"] + l["height"] / 2 - cy), l["x"] + l["width"] / 2 - cx)) % 360
        print("   key %-6s %-13s at %3.0f deg (from 3 o'clock, counterclockwise)" % (k["id"], k.get("behavior", ""), a))
print("   flashlight: %s" % ("yes" if s.get("flashlightConfiguration") else "no"))
PY
done
[ -d "$TMP/Fonts" ] && cp "$TMP"/Fonts/* "$TC/Fonts/" && cp "$TMP"/Fonts/* "$CIQ/Fonts/"
rm -rf "$TMP"
echo "Installed into $TC and $CIQ. Next: add <iq:product id=\"...\"/> to manifest.xml and run: bash build.sh <id>"
