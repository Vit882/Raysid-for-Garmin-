#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Vygeneruje docs/NAVOD.md (cestina) a docs/GUIDE-EN.md (anglictina)
# z textu napovedy v source/Tr.mc. Spoustet z korene repozitare:
#   python3 tools/gen-navod.py
import re
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
src = (root / "source" / "Tr.mc").read_text(encoding="utf-8")

def get(key, lang):
    m = re.search(r":" + key + r' => \[\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"', src, re.S)
    if not m:
        raise SystemExit("chybi klic " + key)
    return m.group(lang + 1)

TOPICS = [("hControls", "hControlsT"), ("hScreens", "hScreensT"), ("hRecord", "hRecordT"),
          ("hSignal", "hSignalT"), ("hAlarms", "hAlarmsT"), ("hRise", "hRiseT")]
OUT = [
    (0, "NAVOD.md", "# Raysid Garmin – uživatelský návod\n\n",
     "Stejný text je v hodinkách v menu Nápověda (čeština, angličtina, polština). "
     "Soubor se generuje z `source/Tr.mc` skriptem `tools/gen-navod.py`, ručně ho neupravuj.\n"),
    (1, "GUIDE-EN.md", "# Raysid Garmin – user guide\n\n",
     "The same text is shown on the watch under Help (Czech, English, Polish). "
     "This file is generated from `source/Tr.mc` by `tools/gen-navod.py`; do not edit it by hand.\n"),
]
for lang, name, title, note in OUT:
    parts = [title, note]
    for t, b in TOPICS:
        parts.append("\n## " + get(t, lang) + "\n\n" + get(b, lang) + "\n")
    (root / "docs" / name).write_text("".join(parts), encoding="utf-8")
    print("zapsano docs/" + name)
