#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Generates the user guides docs/USER-GUIDE.md (English), docs/USER-GUIDE-CS.md
# (Czech) and docs/USER-GUIDE-PL.md (Polish) from the help texts in
# source/Tr.mc. Run from the repository root:
#   python3 tools/gen-guide.py
import re
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
src = (root / "source" / "Tr.mc").read_text(encoding="utf-8")

def get(key, lang):
    m = re.search(r":" + key + r' => \[\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"', src, re.S)
    if not m:
        raise SystemExit("missing key " + key)
    return m.group(lang + 1)

TOPICS = [("hControls", "hControlsT"), ("hScreens", "hScreensT"), ("hRecord", "hRecordT"),
          ("hSignal", "hSignalT"), ("hAlarms", "hAlarmsT"), ("hRise", "hRiseT")]
# index in Tr.mc: 0 = cz, 1 = en, 2 = pl
OUT = [
    (1, "USER-GUIDE.md", "# Raysid Garmin – user guide\n\n",
     "The same text is shown on the watch under Help (Czech, English, Polish). "
     "Also available in [Czech](USER-GUIDE-CS.md) and [Polish](USER-GUIDE-PL.md). "
     "This file is generated from `source/Tr.mc` by `tools/gen-guide.py`; do not edit it by hand.\n"),
    (0, "USER-GUIDE-CS.md", "# Raysid Garmin – uživatelský návod\n\n",
     "Stejný text je v hodinkách v menu Nápověda. [English](USER-GUIDE.md), [polski](USER-GUIDE-PL.md). "
     "Soubor se generuje z `source/Tr.mc` skriptem `tools/gen-guide.py`, ručně ho neupravuj.\n"),
    (2, "USER-GUIDE-PL.md", "# Raysid Garmin – instrukcja obsługi\n\n",
     "Ten sam tekst jest w zegarku w menu Pomoc. [English](USER-GUIDE.md), [česky](USER-GUIDE-CS.md). "
     "Plik jest generowany z `source/Tr.mc` skryptem `tools/gen-guide.py`, nie edytuj go ręcznie.\n"),
]
for lang, name, title, note in OUT:
    parts = [title, note]
    for t, b in TOPICS:
        parts.append("\n## " + get(t, lang) + "\n\n" + get(b, lang) + "\n")
    (root / "docs" / name).write_text("".join(parts), encoding="utf-8")
    print("wrote docs/" + name)
