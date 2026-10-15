#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build Raysid.prg: zapise datum buildu do source/BuildInfo.mc a prelozi.
# Pouziti: bash build.sh [zarizeni]   (vychozi fenix7xpro)
set -e
cd "$(dirname "$0")"
DEV="${1:-fenix7xpro}"
TC="${TOOLCHAIN:-/mnt/project-files/.toolchain}"
# Poradove cislo buildu poslaneho na test (jen pro kontrolu prelozeni
# volat monkeyc primo, at se cislo nezvysuje)
mkdir -p build
NUM=$(( $(cat build/build-number.txt 2>/dev/null || echo 0) + 1 ))
cat > source/BuildInfo.mc <<MC
// SPDX-License-Identifier: GPL-3.0-or-later
// Generuje build.sh, rucne neupravovat
const APP_VERSION = "1.1";
const APP_YEAR = "2026";
const BUILD_DATE = "$(date +%-d.%-m.%Y)";
const BUILD_NUM = $NUM;
MC
bash "$TC/sdk/bin/monkeyc" -d "$DEV" -f monkey.jungle -o "build/Raysid-$DEV.prg" -y "$TC/developer_key.der" -l 3 -w
# Cislo buildu se ulozi az po uspesnem prekladu
echo "$NUM" > build/build-number.txt
[ "$DEV" = fenix7xpro ] && cp "build/Raysid-$DEV.prg" build/Raysid.prg
echo "OK build/Raysid-$DEV.prg (build $NUM)"
