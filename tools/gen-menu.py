#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Generates docs/MENU.md: the app menu as a text tree in English, Czech and Polish.
# Labels come from source/Tr.mc; the structure below mirrors RaysidDelegate.mc,
# keep it in sync when the menu changes. Run from the repository root:
#   python3 tools/gen-menu.py
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = (root / "source" / "Tr.mc").read_text(encoding="utf-8")

def get(key, lang):
    m = re.search(r":" + key + r' => \[\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"', src, re.S)
    if not m:
        raise SystemExit("missing key " + key)
    return m.group(lang + 1)

# (key, note, children); note: "led" = only on watches with a flashlight,
# "map" = only with mapping on, "avg" = only when averaging is on
MENU = [
    ("mSignal", "", [("divider", "", []), ("beep", "", []), ("vibration", "", []), ("flash", "led", [])]),
    ("mAlarms", "", [
        ("alarmsAll", "", []),
        ("gDose", "", [("doseAlarm", "", []), ("doseLimit", "", [])]),
        ("gCps", "", [("cpsAlarm", "", []), ("cpsLimit", "", [])]),
        ("gRise", "", [("rise", "", []), ("sensitivity", "", [])]),
        ("mAlarmOut", "", [("alarmSound", "", []), ("alarmVibe", "", []), ("alarmFlash", "", []),
                           ("alarmRedLed", "led", []), ("alarmLen", "", [])]),
    ]),
    ("mDevice", "", [
        ("devDiv", "", []), ("divLink", "", []), ("devSound", "", []), ("devDoseAl", "", []), ("devCpsAl", "", []),
        ("mConn", "", [("reconnect", "", []), ("devPick", "", []), ("devLock", "", []), ("connPref", "", [])]),
    ]),
    ("mDisplay", "", [("avgMode", "", []), ("avgSpan", "avg", []), ("backlight", "", []), ("blMapSys", "", []), ("debug", "", [])]),
    ("mRecord", "", [
        ("mapping", "", []), ("autostart", "map", []), ("recDist", "map", []), ("gpsQual", "map", []),
        ("mWeb", "map", [("mUpload", "", []), ("apiKey", "", []), ("verify", "", [])]),
        ("mStorage", "map", [("stoPending", "", []), ("cmpWhen", "", []), ("recClear", "", [])]),
    ]),
    ("mHelp", "", []),
    ("mLanguage", "", []),
]

NOTES = {
    0: {"led": "flashlight watches only", "map": "with mapping on", "avg": "with averaging on"},
    1: {"led": "jen hodinky se svítilnou", "map": "při zapnutém mapování", "avg": "při zapnutém průměrování"},
    2: {"led": "tylko zegarki z latarką", "map": "przy włączonym mapowaniu", "avg": "przy włączonym uśrednianiu"},
}
TITLES = {0: "English", 1: "Česky", 2: "Polski"}
LANG = {0: 1, 1: 0, 2: 2}   # our order -> index in Tr.mc

def tree(items, lang, prefix, out):
    for i, (key, note, kids) in enumerate(items):
        last = i == len(items) - 1
        label = get(key, LANG[lang])
        if note:
            label += "  (" + NOTES[lang][note] + ")"
        out.append(prefix + ("└─ " if last else "├─ ") + label)
        tree(kids, lang, prefix + ("   " if last else "│  "), out)

lines = ["# Menu map", "",
         "Generated from `source/Tr.mc` by `tools/gen-menu.py`; do not edit by hand. "
         "Open the menu with START on the main screen. The UP and DOWN buttons and the screens are described in the [user guide](USER-GUIDE.md).", ""]
for lang in (0, 1, 2):
    lines += ["## " + TITLES[lang], "", "```", "Menu"]
    tree(MENU, lang, "", lines)
    lines += ["```", ""]
(root / "docs" / "MENU.md").write_text("\n".join(lines), encoding="utf-8")
print("docs/MENU.md")
