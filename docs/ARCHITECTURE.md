# Raysid Garmin app architecture

Technical documentation for a developer or AI agent taking over the project without prior context. It describes the state of the source code in `source/*.mc` (version 1.1, build 82). It refers to files and functions, not line numbers. GPS mapping and uploading to the web are described in detail in [MAPPING-AND-UPLOAD.md](MAPPING-AND-UPLOAD.md).

> If documentation and code disagree, the code wins; record discrepancies under [Known discrepancies](#16-known-discrepancies-in-code-and-documentation).

## Contents

1. [Overview](#1-overview)
2. [Modules (.mc files)](#2-modules-mc-files)
3. [Object graph](#3-object-graph)
4. [Data flow from BLE notification to display](#4-data-flow-from-ble-notification-to-display)
5. [Timers](#5-timers)
6. [Screens and buttons](#6-screens-and-buttons)
7. [Menu tree](#7-menu-tree)
8. [State and persistence](#8-state-and-persistence)
9. [Translations (Tr.mc)](#9-translations-trmc)
10. [Overload (OVL)](#10-overload-ovl)
11. [Averaging](#11-averaging)
12. [Alarms](#12-alarms)
13. [Signals: clicking, vibration, flashlight](#13-signals-clicking-vibration-flashlight)
14. [Performance limits (watchdog, memory)](#14-performance-limits-watchdog-memory)
15. [Known limitations](#15-known-limitations)
16. [Known discrepancies in code and documentation](#16-known-discrepancies-in-code-and-documentation)

---

## 1. Overview

- **Type:** Connect IQ `watch-app` (`manifest.xml`), entry class `RaysidApp`, `minApiLevel` 3.2.0, single product `fenix7xpro` (fēnix 7X Pro).
- **Permissions:** `BluetoothLowEnergy`, `Positioning`, `Communications`.
- **Languages in the manifest:** `ces`, `eng`. The app translates itself through `Tr.mc` (CZ/EN/PL); the system strings in `resources/strings/strings.xml` are only the app name and the setting labels in Garmin Connect.
- **Build:** `bash build.sh [device]` writes `source/BuildInfo.mc` (constants `APP_VERSION`, `APP_YEAR`, `BUILD_DATE`, `BUILD_NUM`; do not edit by hand) and calls `monkeyc ... -l 3 -w` (strictest type checking). Output goes to `build/Raysid-<device>.prg`, and for `fenix7xpro` also to `build/Raysid.prg`. `monkey.jungle` contains only `project.manifest = manifest.xml`.
- **What the app does:** connects over BLE to the Raysid dosimeter, shows dose rate (µSv/h) and pulse count rate (cps), draws a chart, watches alarms, signals pulses (tone/vibration/flashlight). Optionally records points with GPS and sends them through the phone to the Žhavá místa website (zhavamista.cz).

## 2. Modules (.mc files)

| File | Responsibility | Key classes and functions |
|---|---|---|
| `RaysidApp.mc` | Application, shared measurement state and settings, chart history, OVL, averaging | `RaysidApp` (`onStart`, `onStop`, `onSettingsChanged`, `getInitialView`); `RaysidState` (`initialize` loads settings, `save`, `addSample`, `updateOvl`, `cpsDropped`, `smooth`, `smoothAt`, `avgSince`, `shownDose`, `shownCps`, `doseLimit`, `cpsLimit`, `softFactor`, `startAlarm`); global `clamp()` and `put()` (writes to `Storage`, returns `false` instead of crashing when storage is full) |
| `RaysidProtocol.mc` | Everything Raysid-specific: UUIDs, command frame, ping, checksums, packet decoding | module `RaysidProtocol` (`profile`, `matches`, `initCommands`, `settingsCommands`, `pollCommand`, `ping`, `dividerCommand`, `soundCommand`, `doseAlarmCommand`, `cpsAlarmCommand`, `command`, `crc1`, `checksumOk`, `unpackValue`, `toHex`; constants `POLL_MS`, `WRITE_TYPE`, `UR_PER_USV`); class `RaysidParser` (`feed`, `reset`, `decode`, `learnDelimiter`, `logPacket`); constant `KNOWN_TYPES` |
| `BleManager.mc` | Scanning, choosing a Raysid, pairing, write queue, ping, connection recovery, receiving data and triggering evaluation | `BleManager extends BleDelegate` (`start`, `stop`, `restart`, `onScanResults`, `choose`, `connect`, `onConnectedStateChanged`, `subscribe`, `onTick`, `onCharacteristicChanged`, `send`, `requestSettings`, `syncDivider`, `enforcePin`, `adoptPaired`, `remember`, `clearHistory`, `pump`, `enqueue`) |
| `Alarms.mc` | Evaluation of the hard alarm (limits) and the soft alarm (rapid rise) | `Alarms` (`evaluate`, `evaluateHard`, `evaluateSoft`, `reset`) |
| `Clicker.mc` | 100 ms timer: clicking/vibration/flashlight by cps, alarm sequence, red flashlight, backlight always on, redraw for the screen flash and OVL blinking | `Clicker` (`start`, `stop`, `onTick`, `click`, `alarmBurst`, `warn`, `updateVibeOver`, `alarmLed`, static `hasLed`) |
| `Recorder.mc` | Recording GPS points into `Application.Storage`, chunk queue, merging, deletion | `Recorder`; global accessor `recorder()` |
| `Uploader.mc` | Uploading chunks to Žhavá místa via `Communications.makeWebRequest`, key verification | `Uploader`; global accessor `uploader()` |
| `RaysidView.mc` | Drawing the main screen, chart, Mapping screen and debug screen | `RaysidView` (`onUpdate`, `drawChart`, `buildBuckets`, `drawBuckets`, `drawSeries`, `drawAlarmBands`, `drawMapping`, `drawRecord`, `drawDebug`, `drawMenuHint`, `drawClock`, `drawBatteries`, `fitText`, `fitFont`, `chordAt`); colors `CHART_DOSE`, `CHART_CPS`, `UP_COLOR` |
| `RaysidDelegate.mc` | Buttons of the main screens, the whole menu, choice lists, delete confirmation; menu and OVL constants; number formatting | `RaysidDelegate`, `RaysidMenuDelegate`, `ChoiceMenuDelegate`, `ClearConfirmDelegate`, `HelpMenuDelegate`, `DevicePickDelegate`; functions `doseNum`, `cpsNum`, `doseLabel`, `cpsLabel`, `recordLabel`, `storeLabel`, `cmpLabel`, `cmpSubLabel`, `refreshItem`, `aboutText` … |
| `ValuePicker.mc` | Entering a custom numeric value digit by digit with the system `Picker` | `DigitFactory`, `DigitPicker`, `DigitPickerDelegate` (`onAccept` clamps the value to the range) |
| `KeyEntry.mc` | Entering the Žhavá místa API key directly on the watch | `KeyEntryView`, `KeyEntryDelegate`; functions `currentKey()`, `keyLabel()`; constants `KEY_CHARS`, `KEY_LEN` |
| `HelpView.mc` | Help page with word wrapping and scrolling | `HelpView` (`wrap` once, `scroll`), `HelpDelegate` |
| `Tr.mc` | CZ/EN/PL translation table | module `Tr` (`t`, `build`, variable `lang`) |
| `BuildInfo.mc` | Version and build number | generated by `build.sh` |

## 3. Object graph

```
RaysidApp (AppBase, entry in manifest.xml)
 ├─ state    : RaysidState     shared state, settings, history (created first)
 ├─ ble      : BleManager      gets state; owns RaysidParser and Alarms
 ├─ clicker  : Clicker         gets state
 ├─ uploader : Uploader        no parameters
 └─ recorder : Recorder        gets state (created last)

Global access (file-level functions):
  recorder() -> (Application.getApp() as RaysidApp).recorder     (Recorder.mc)
  uploader() -> (Application.getApp() as RaysidApp).uploader     (Uploader.mc)

Views:
  getInitialView() -> [RaysidView(state), RaysidDelegate(state, ble)]
  On page switch RaysidDelegate creates a new View/Delegate pair
  (WatchUi.switchToView); the page is in state.page.
```

Order in `RaysidApp.onStart`: `BluetoothLowEnergy.setDelegate(ble)`, `ble.start()`, `clicker.start()`, `recorder.resume()`, `uploader.start()`.
Order in `onStop`: `clicker.stop()`, `uploader.stop()`, `recorder.suspend()`, `ble.stop()`.
`onSettingsChanged` (a change in Garmin Connect) calls `uploader.settingsChanged()`.

Modules are linked through `state` (data) and through the global `recorder()`/`uploader()`:
- `BleManager.onTick` calls `recorder().gcStep()` and `recorder().compactTick()` (gradual deletion and ongoing merging).
- `Recorder.closeChunk` calls `uploader().kick()`; `Recorder.clear` calls `uploader().cancel()`.
- `Uploader` reads the queue via `recorder().headChunk()`, `dropHead()`, `pending()`, `enabled`, `on`, `paused`, `count`.
- `RaysidView` and the menu read `recorder()` and `uploader()` for labels.

## 4. Data flow from BLE notification to display

```
Raysid ──notify (RX 49535343-1e4d-…-9616)──► BleManager.onCharacteristicChanged(value)
   │  state.packets++, _lastRx = now, (debug: state.lastRaw = hex)
   ▼
RaysidParser.feed(value)            builds the buffer, finds the delimiter, checks the XOR checksum
   │  returns a Dictionary with only the keys present in the data:
   │  :cps, :doseRate (µSv/h), :ovl, :battery, :temp, :devDiv/:devSound/:devDoseAl/:devCpsAl, :btn
   ▼
BleManager.onCharacteristicChanged
   ├─ :battery          → state.battery
   ├─ :devDiv …         → state.devDiv…, syncDivider(), updateDevMenu()   (only the latest reply, see _setReq)
   ├─ :btn              → requestSettings() (a button on the Raysid changed a setting)
   ├─ :ovl              → state.devOvl
   └─ :doseRate / :cps  → state.doseRate / state.cps, state.lastUpdate, intervalMs
          │  (only when both values are known)
          ├─ state.updateOvl(now, dose, cps)                   → cpsOvlOn, doseOvlOn, ovl
          ├─ aDose/aCps = during OVL at least OVL_DOSE / OVL_CPS
          ├─ alarm = Alarms.evaluate(now, aDose, aCps)        → hardAlarm, softAlarm, flashUntil, seq*
          └─ state.addSample(now, doseRate, cps, alarm)       → ring buffer histT/histDose/histCps/histAlarm
   ▼
WatchUi.requestUpdate() → RaysidView.onUpdate (draws only the current page)

Reading the state in parallel:
  Clicker.onTick (100 ms)      state.cps, divider, overload, seqLeft …  → tones, vibration, flashlight
  Recorder.onPosition (~1 Hz)  state.lastUpdate, ovl, avgSince()        → mapping points (Storage)
  Uploader.kick (30 s / event) recorder().headChunk()                 → HTTP POST
```

Parser details (`RaysidParser.feed`):
- Packet: `[Size] [Type] [Payload] [Checksum 3 B]`. The checksum is an XOR of 3-byte blocks; `RaysidProtocol.checksumOk` accepts both little and big endian variants (API.md and cps-doserate.py differ).
- There may be a delimiter between packets (both `0x84` and `0x10` observed). `learnDelimiter` accepts it after 3 occurrences. After `RELEARN_AFTER` = 10 notifications without a valid packet it learns again.
- Watchdog protection: at most `JUNK_MAX` = 120 bytes of junk with a checksum attempt per notification; a buffer over 1024 B is truncated to the last 512 B.
- Type `0x17`: blocks `[range, LSB, MSB]`, value `unpackValue(v) / 600`; range 0 = cps, 1 = dose rate in µR/h, divided by `UR_PER_USV` = 100 → µSv/h. The byte before the checksum is the Raysid OVL flag (only when `(size - 5) % 3 == 1`).
- Type `0x0a`: Raysid settings (`p[4]` divider, `p[6]` sound, `p[10]` bit `0x10` dose alarm, bit `0x01` cps alarm).
- Type `0x02`: temperature and battery (battery directly in percent, not in tenths as API.md states).
- Type `0x18`: button press on the Raysid (`:btn`).

BLE connection (`BleManager`):
- `start` → `register()` (`registerProfile`) → `onProfileRegister` → `adoptPaired()` (takes over a Raysid that stayed connected from a previous app instance) or `startScan()`.
- `onScanResults`: a Raysid is recognized by a name containing "raysid" or by the service UUID (`RaysidProtocol.matches`). The chosen Raysid (`pin`) is connected immediately (with `lock` or `pref == 0`); otherwise candidates are collected for `CHOOSE_MS` = 3 s and `choose()` picks by history (`pref` 0) or strongest signal (`pref` 1). The history holds at most `HISTORY_MAX` = 6 names.
- After connecting, `subscribe()`: CCCD write and `initCommands()` (= reading settings: ping to screen 9, `0x1f 00`, `0x1b 01`, `0x1b 02`, ping to screen 0).
- Connect IQ allows only one BLE request in progress, hence the `_queue` + `_busy` queue; a safeguard releases `_busy` after 3 s without confirmation. Writes are sent with `WRITE_TYPE_WITH_RESPONSE`.
- Command frame (`RaysidProtocol.command`): `[0xFF] [CRC2] [0xEE] [CRC1 4 B BE] [payload] [total length]`.

## 5. Timers

| Timer | Where | Period | What it does |
|---|---|---|---|
| Clicker | `Clicker._timer` → `onTick` | `TICK_MS` = 100 ms | turns off the flashlight from the previous tick; backlight always on (every 10th tick); `requestUpdate` for the alarm screen flash (page 0 only) and OVL blinking (every 500 ms); alarm bursts (`seqLeft`, spacing `SEQ_GAP_MS` = 2 s); red flashlight during an alarm (every 5th tick); evenly spaced clicking/vibration/flashlight by cps; warning on signal overload |
| BLE | `BleManager._timer` → `onTick` | `RaysidProtocol.POLL_MS` = 4000 ms | `recorder().gcStep()`, `recorder().compactTick()`; pairing timeout `CONNECT_TIMEOUT_MS` = 15 s; connection recovery after `RECOVER_MS` = 30 s without connection or without data; `choose()`; `requestUpdate` (clock, graying out); ping at the head of the queue (only when no settings read `:seq` is in progress in the queue); releasing a stuck `_busy` |
| Uploader | `Uploader._timer` → `onTick` → `kick()` | `TICK_MS` = 30 000 ms | attempt to upload the oldest chunk; runs only when mapping is enabled or unsent chunks remain (`Uploader.active`) |
| Position | `Position.enableLocationEvents(LOCATION_CONTINUOUS)` → `Recorder.onPosition` | system, ~1 s | only while recording; creates points |

The app has no other timers. Drawing is triggered by `WatchUi.requestUpdate()` from BLE notifications (the Raysid sends a measurement roughly every 0.25 s), from the BLE tick, from the Clicker and from the menu.

## 6. Screens and buttons

Pages (`state.page`, not saved):

| `page` | Screen | Content | UP action |
|---|---|---|---|
| 0 | Main | dose rate (orange) and cps (blue) in large font, connection status or alarm text at the top, clock, Raysid and watch battery, warnings CLICKING OFF (CVAKÁNÍ VYPNUTO) / VIBRO MAX, recording status at the bottom (`drawRecord`) | swaps what is on top (`swapMain`, key `swap`) |
| 1 | Chart | current values, dose rate and cps chart with separate scales, alarm periods shaded, range and fill status | next length from `CHART_LENGTHS` = 10/20/30/60 s (key `cw`) |
| 2 | Mapping | only with `recorder().enabled`; REC/GPS status, distance, points, duration, max dose rate and cps, web status | `recorder().start()` or `pause()` |
| – | Debug | overlays all pages when `state.showDebug`: packet count, counts per type, hex of the last packet, measurement interval | nothing |

Buttons (`RaysidDelegate`):

| Button | Behavior |
|---|---|
| **DOWN** (`onNextPage`) | cycles pages 0 → 1 → (2) → 0 (`switchPage`, SLIDE_UP animation). Nothing on the debug screen. |
| **UP** (`onPreviousPage`) | action by page (table above). Nothing on the debug screen. |
| **START** | menu. On the fenix it arrives, depending on firmware, as `onKey(KEY_ENTER)` or `onSelect`; `onSelect` is ignored for 700 ms after a touch (`_lastTap`), because tapping the display also calls `onSelect`. |
| **BACK** | the delegate does not override `onBack`; the default behavior exits the app (`onStop` closes the route properly). |
| **LIGHT** | not handled by the app (`onKey` returns `false` for everything except `KEY_ENTER`); left to the system. |
| **Hold** | nothing uses holds: holding UP/DOWN triggers the watch's system shortcuts. `onMenu` (holding UP) returns `true` and does nothing. The same rule applies to `ValuePicker.mc` and `KeyEntry.mc`. |
| **Touch / swipe** | `onTap` and `onSwipe` return `true` and do nothing. |
| **Any button while an alarm is sounding** | `onKey` with `state.seqLeft > 0` only resets `seqLeft` (silences) and consumes the event. |

Button marks are drawn by `RaysidView.drawMenuHint` as arcs on the edge: START gray, UP yellow and thicker (it has a screen action), DOWN dark gray.

Chart (`RaysidView.drawChart`): until there is data for the full length, the chart stretches over the continuous segment (a gap > 5 s starts a new segment), at least 10 s. For lengths over 30 s (i.e. 60 s) buckets are drawn (`buildBuckets`): bucket length `max(span / 24, 4000 ms)`, the thick line is the average, and for cps there is also a thin min–max bar. The `scale()` scales have a minimum span of 20 % of the center (at least 0.005 µSv/h or 0.5 cps). Values gray out when no measurement arrives for 5 s.

## 7. Menu tree

The menu is built by `RaysidDelegate.openMenu` and `RaysidMenuDelegate.onSelect`. Single-value choices are handled by `ChoiceMenuDelegate` (`openChoice`); "Custom value..." opens `DigitPicker`. After returning from a submenu, `RaysidMenuDelegate.onBack` refreshes the label of the parent item (`refreshItem`). Names are the English labels from `Tr.mc`, with the item ID in parentheses.

```
Raysid (START)
├─ Signals (:mSignal)                           signals on the watch
│  ├─ Divider (:divider)                        1:1 (alarms only), 1:5, 1:10, 1:20, 1:50, 1:100, 1:250   → state.divider
│  ├─ Clicking (:beep)                          tone on every Nth pulse   → state.sound
│  ├─ Vibrate on pulses (:vibration)            → state.vibrate
│  └─ Flashlight blink (:flash)                 only when Clicker.hasLed()   → state.led
├─ Alarms (:mAlarms)                            label "on" only when the main switch and at least one alarm are on
│  ├─ All alarms (:alarmsAll)                   main switch → state.alarmsOn
│  ├─ Dose rate (:gDose)
│  │  ├─ Dose alarm (:doseAlarm)                → state.doseOn
│  │  └─ Dose limit (:doseLimit)                0.3 … 500 µSv/h (DOSE_LIMITS) + custom 000.00 (0.05–999)
│  ├─ CPS (:gCps)
│  │  ├─ CPS alarm (:cpsAlarm)                  → state.cpsOn
│  │  └─ CPS limit (:cpsLimit)                  50 … 5000 (CPS_LIMITS) + custom 4 digits (5–5000)
│  ├─ Rapid rise (:gRise)
│  │  ├─ Rise detection (:rise)                 → state.softOn
│  │  └─ Sensitivity (:sensitivity)             +30 / +50 / +100 % + custom 3 digits (10–300)
│  └─ Alarm output (:mAlarmOut)
│     ├─ Alarm sound (:alarmSound)
│     ├─ Alarm vibration (:alarmVibe)
│     ├─ Screen flash (:alarmFlash)
│     ├─ Red flashlight (:alarmRedLed)          only when Clicker.hasLed()
│     └─ Alarm length (:alarmLen)               short (1×) / medium (3×) / long (8×)
├─ Raysid (:mDevice)                            settings stored in the dosimeter itself; requestSettings() on open
│  ├─ Divider (:devDiv)                         sends 0x16 N; without a connection only "Disconnected"
│  ├─ Link divider (:divLink)                   watch divider = Raysid divider (syncDivider)
│  ├─ Clicking (:devSound)                      sends 0x03 0/1; "?" until the Raysid reports its state
│  ├─ Dose rate alarm (:devDoseAl)              sends 0x18 0/1
│  ├─ CPS alarm (:devCpsAl)                     sends 0x17 0/1
│  └─ Connection (:mConn)
│     ├─ Reconnect (:reconnect)                 ble.restart(), closes all menus
│     ├─ Chosen Raysid (:devPick)               any / names from history / Forget history
│     ├─ Only chosen Raysid (:devLock)          cannot be turned on without a chosen one ("pick a Raysid first")
│     └─ Several Raysids (:connPref)            chosen, then known / strongest signal
├─ Display (:mDisplay)
│  ├─ Averaging (:avgMode)                      Instant values / By time / By reading count
│  ├─ Average over (:avgSpan)                   only with averaging: 2/4/6/10 s or 2/3/5/10/20 readings + custom (up to 60 s / 30 readings)
│  ├─ Backlight always on (:backlight)
│  └─ Debug screen (:debug)                     not saved
├─ Žhavá místa (:mRecord)
│  ├─ Mapping enabled (:mapping)                the whole module; off hides the Mapping page and the rest of the submenu
│  ├─ Record on start (:autostart)
│  ├─ Point spacing (:recDist)                  5/8/10/12/15 m + custom 3 digits (2–200 m)
│  ├─ GPS quality (:gpsQual)                    good (4) / usable (3) / poor (2)
│  ├─ Web and upload (:mWeb)
│  │  ├─ Upload to web (:upload)                status; select = uploader().retry()
│  │  ├─ API key (:apiKey)                      KeyEntryView
│  │  └─ Test connection (:verify)              uploader().startVerify()
│  └─ Storage (:mStorage)
│     ├─ Not uploaded (:stoPending)             number of points and % of MAX_POINTS; select refreshes the label
│     ├─ When full (:cmpMax)                    Stop recording / Merge at most 1×, 2×, 3× / Merge without limit
│     └─ Delete unsent (:recClear)              confirmation → recorder().clear()
├─ Help (:mHelp)                                Controls, Screens, Mapping (only with mapping enabled),
│                                               Signals, Alarms, Rise detection, About
└─ Language (:mLanguage)                        Čeština / English / Polski; the menu closes after a change
```

Recording is not started from the menu but with the UP button on the Mapping page (or automatically with the Record on start option).

Custom values (`ChoiceMenuDelegate.openPicker`): `DigitPicker(title, intDigits, decDigits, current)` + `DigitPickerDelegate(decDigits, min, max, callback)`. UP/DOWN change the digit, START moves to the next one and confirms on the last, BACK goes back. An out-of-range value is moved to the boundary in `onAccept`.

## 8. State and persistence

### 8.1 Application.Storage

Writes go through the global `put()` (does not crash when storage is full). Settings are read in `RaysidState` via the private `load()`, which returns the default value when the key is missing or has a different type. `RaysidState.save()` writes all settings at once (called from the menu); UP on the main screen and the chart writes only `swap` or `cw`.

**Measurement and signal settings (owner `RaysidState`, `RaysidApp.mc`)**

| Key | Type | Default | Meaning |
|---|---|---|---|
| `bl` | Boolean | false | backlight always on |
| `snd` | Boolean | false | clicking (tone on pulses) |
| `led` | Boolean | false | flashlight blink on pulses |
| `vib` | Boolean | false | vibration on pulses |
| `div` | Number | 10 | watch divider 1:N; snapped to the nearest value in `DIVIDERS` on load |
| `dvL` | Boolean | false | link the watch divider with the Raysid |
| `cw` | Number | 30 | chart length in s, clamped 10–60 |
| `swap` | Boolean | false | main screen: cps on top |
| `avM` | Number | 0 | averaging: 0 instant, 1 by time, 2 by count (clamped 0–2) |
| `avS` | Number | 10 | averaging length in s (clamped 2–60) |
| `avN` | Number | 5 | number of readings to average (clamped 2–30) |
| `aOn` | Boolean | true | main alarm switch |
| `adOn` | Boolean | false (based on `ad`) | dose alarm on |
| `ad` | Float | 1.0 | dose limit µSv/h (0.05–999); older versions had 0 = off |
| `acOn` | Boolean | based on `ac` | cps alarm on |
| `ac` | Number | 1000 | cps limit (5–`ALARM_CPS_MAX` = 5000) |
| `slOn` | Boolean | based on `sl` | rise detection on |
| `sp` | Number | 50 | rise sensitivity in % (10–300) |
| `sl` | Number | – | read only: older sensitivity encoding (0 off, 1–3 = 30/50/100 %), migrated to `slOn` + `sp` |
| `aSnd` / `aVib` / `aFl` / `aRed` | Boolean | true | alarm output: sound / vibration / screen flash / red flashlight |
| `aLen` | Number | 1 | alarm length 0 short, 1 medium, 2 long |
| `lang` | Number | based on watch language | 0 Czech, 1 English, 2 Polish (`Tr.lang`) |
| `lgI`, `lg0`…`lg19` | – | – | leftover from build 68; `RaysidState.initialize` deletes them if `lgI` exists |

Note: defaults on a completely fresh install: `ac` missing → `acOn = load("acOn", 1000 > 0)` = **true**; `sl` missing → default 2 → `slOn` = **true**; `ad` missing → `adOn` = **false**. So the cps alarm and rise detection are on after installation, the dose alarm is off.

**Connection (owner `BleManager`)**

| Key | Type | Meaning |
|---|---|---|
| `devPin` | String | chosen Raysid (name); deleted on "any" |
| `devLock` | Boolean | connect only the chosen one |
| `devPref` | Number | with several units: 0 chosen/known, 1 strongest signal |
| `devHist` | Array `[[name, unix time], …]` | history of connected units, newest first, max. 6 |

**Mapping (owner `Recorder`)**: format and meaning in detail in [MAPPING-AND-UPLOAD.md](MAPPING-AND-UPLOAD.md#2-storage-format):
`rEn`, `rAuto`, `rDist`, `rQual`, `rCmp`, `rHead`, `rChunks`, `rCount`, `rFull`, `rGc`, `rRoute`, `rRName`, `rBatch`, `rRPts`, `rPart`, `rStart`, `rSess`, `rMeters`, `rMaxD`, `rMaxC`, `rOn` (write only), chunks `r<i>` and descriptors `rm<i>`.

**Upload (owner `KeyEntry.mc`)**

| Key | Type | Meaning |
|---|---|---|
| `zmKeyBak` | String | backup of the API key in case `Properties` are lost during an app update; read by `currentKey()` |

Not persisted: `state.page`, `state.showDebug`, live values, chart history, alarm state, OVL state, Raysid settings (`devDiv` …, read after connecting).

### 8.2 Application.Properties (settings in Garmin Connect)

Defined in `resources/settings/properties.xml` and `settings.xml`, read by `Uploader.prop()` and `currentKey()`:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `zmUpload` | boolean | true | upload to Žhavá místa (`Uploader.enabled()`) |
| `zmKey` | string (password) | "" | API key; also written by `KeyEntryDelegate.save` |
| `zmUrl` | string (alphaNumeric) | "" | alternative endpoint address, empty = `Uploader.DEFAULT_URL` |

For an app sideloaded over USB, the Garmin Connect settings cannot be used, so the key is entered on the watch (`KeyEntry.mc`).

## 9. Translations (Tr.mc)

- Module `Tr`: `Tr.lang` (0 CZ, 1 EN, 2 PL) and `Tr.t(:key)`. The table is built once (`build()`) on the first call and then stays in memory. A missing key returns the symbol name (no crash, but the display shows e.g. `myKey`).
- Default language on first start: `System.LANGUAGE_CES` → 0, `LANGUAGE_POL` → 2, otherwise 1 (`RaysidState.initialize`). Stored under `lang`.
- Connection status and upload status are stored as symbols (`state.status`, `Uploader.status`, `Uploader.verify`) and translated only when drawing, so a language change applies immediately.
- Help texts are long strings (`:hControlsT`, `:hScreensT`, `:hSignalT`, `:hAlarmsT`, `:hRecordT`, `:hRiseT`); `HelpView` wraps them at spaces, and a standalone word `\n` means a new line. The "About" text is assembled by `aboutText()` from `BuildInfo.mc`.
- On the MIP display some characters (arrows, ellipsis) may render as squares; texts therefore use `>` and `...`.

**How to add a string:**
1. Add a line `:mujKlic => ["česky", "English", "polski"],` to the dictionary in `Tr.build()` (always three entries in the same order).
2. Use `Tr.t(:mujKlic)` in code.
3. Check the length on the round display (menu items and status lines are shortened only in some places, see `RaysidView.fitText`).

**How to add a language:** add a fourth element to every array in `Tr.build()`, extend `LANG_NAMES` in `RaysidDelegate.mc`, widen `clamp(..., 0, 2)` for `lang` in `RaysidState.initialize` and the default choice based on `systemLanguage`; optionally `LANG_CODES` in `Tr.mc` (not used anywhere yet) and the language in `manifest.xml`.

## 10. Overload (OVL)

At a very high pulse rate the Raysid detector saturates and reports clipped (low) cps. The app then shows a blinking "OVL" instead of the number, does not record mapping points and forces alarms. The logic is in `RaysidState.updateOvl` and `cpsDropped`, the constants in `RaysidDelegate.mc`.

State: `state.cpsOvlOn`, `state.doseOvlOn`, combined `state.ovl = cpsOvlOn || doseOvlOn`. OVL is shown only for the quantity that went into it (`cpsOvl()`, `doseOvl()`).

**1. The Raysid sends the flag** (`state.devOvl != null`, a byte in packet `0x17`): `cpsOvlOn = devOvl`. The app's own estimate is not used.

**2. The Raysid does not send the flag**: estimate from the trend (`cpsDropped`):
- Peak cps and the dose rate at that peak over the last `OVL_DROP_MS` = 10 s.
- Does not trigger when the peak < `OVL_DROP_MIN_CPS` = 2000 cps or dose rate < `OVL_RESET_DOSE` = 10 µSv/h.
- Fast rule: cps ≤ `OVL_FAST_CPS` (0.90) × peak and dose rate ≥ `OVL_FAST_DOSE` (0.95) × dose rate at the peak.
- Drop rule: cps ≤ `OVL_DROP_CPS` (0.5) × peak and dose rate ratio ≥ `OVL_DROP_GAP` (1.5) × cps ratio, and the dose rate has not decreased.
- The ceiling `OVL_CPS` = 7200 cps applies only with `OVL_CPS_ON` = **false** (disabled for testing, comment "Vít, 14.10.2026").
- End of cps OVL: return to the peak (`cps ≥ OVL_EXIT_CPS` 0.9 × peak, dose rate ≤ `OVL_EXIT_DOSE` 1.3 × dose rate at the peak, dose rate not rising) for `OVL_EXIT_N` = 2 consecutive readings; or cps and dose rate move in the same direction (step ≥ `OVL_SAME_STEP` 5 %) for `OVL_SAME_N` = 3 consecutive readings; or dose rate < `OVL_RESET_DOSE` = 10 µSv/h.

**Dose rate (in both modes):** `doseOvlOn` at dose rate > `OVL_DOSE` = 999 µSv/h, ends below `OVL_DOSE_RESET` = 900 µSv/h.

**Consequences of OVL:**
- `BleManager.onCharacteristicChanged` passes at least `OVL_DOSE` / `OVL_CPS` to the alarms (raw values go to the history).
- `Alarms.evaluateHard`: during OVL with the dose or cps alarm on, the alarm is active regardless of the limit.
- `Recorder.onPosition`: `noData = true`, the point is not written and the average for the next point starts only after OVL ends.
- After disconnecting and on a new connection, `BleManager.clearLive()` resets OVL and alarms and sets `devOvl` to `null`.

Alarm limits are capped below OVL: `ALARM_CPS_MAX` = 5000 (the Raysid reports OVL from ~5.4–5.8 kcps), `ALARM_DOSE_MAX` = 999.

## 11. Averaging

- Only raw measurements are stored (`addSample`). The average is computed when drawing, so a settings change applies immediately, including to the whole chart.
- `avgMode` 0 instant, 1 by time (`avgSec`), 2 by count (`avgN`).
- Numbers at the top: `shownDose()` / `shownCps()` → `smoothAt(newest, 60000)`; the window is also limited to 60 s back so that it does not mix in old values after an outage.
- Chart: `smooth(tMin, capMs)` fills `smDose`/`smCps` in one pass with a sliding window (each measurement is added and subtracted once). `capMs = chartSec × 200`, so the chart average is at most one fifth of the chart length.
- **Alarms, signals and mapping points always use instant values**, not the displayed average. Mapping points have their own average `avgSince()` (see the other document).

## 12. Alarms

Evaluated by `Alarms.evaluate(now, dose, cps)` on every measurement (when both dose rate and cps are known). The result 0/1/2 goes into `histAlarm` for chart shading. The effective limits are returned by `RaysidState.doseLimit()`, `cpsLimit()`, `softFactor()` (0 = off; they respect the main switch `alarmsOn`).

**Hard alarm (`evaluateHard`):**
- Triggers when `ovl` (and the dose or cps alarm is on), or dose rate ≥ limit, or cps ≥ limit.
- Clears only when there is no OVL and both quantities are below **90 %** of their limit (hysteresis).
- On trigger: `flashUntil = now + 1500` (if screen flash is on), color red, `startAlarm(2)`.
- The display then shows a red "ALARM: limit exceeded" instead of the status line, and the value above its limit is red (based on the instant value).

**Soft alarm, rapid rise (`evaluateSoft`), time-based:**
- The background `_baseline` is an exponential average with time constant `BASE_MS` = 20 s (`a = dt / 20000`), learned only outside an alarm.
- Warm-up `WARMUP_MS` = 20 s before the first alarm.
- Trigger: `rise > baseline × f` and also `rise > 3σ`, where `σ = sqrt(baseline / 2 + 1)` (Poisson noise of cps measured over ~2 s).
- End: cps below `baseline × (1 + f/2)` for `QUIET_MS` = 4 s, or after `SOFT_MAX_MS` = 60 s duration (then the background is reset to the current cps).
- A 600 ms dark red screen flash and `startAlarm(1)` only if no hard alarm is currently active.

**Alarm sequence:** `RaysidState.startAlarm` sets `seqLeft` = 1 / 3 / 8 bursts according to `alarmLen`; `Clicker.onTick` plays them every `SEQ_GAP_MS` = 2 s (long alarm ≈ 15 s). Hard: `TONE_ALERT_HI` + double vibration 300 ms. Soft: rising two-tone + vibration 200 ms. Sound and vibration follow `alarmSound` / `alarmVibe`.

**Silencing and turning off:** any button received by `RaysidDelegate.onKey` on any page (`seqLeft = 0`); turning off any alarm in the menu cuts the sequence; turning off `alarmsOn` clears both states; disconnecting the Raysid calls `Alarms.reset()`.

## 13. Signals: clicking, vibration, flashlight

The Raysid does not send individual pulses, only cps. `Clicker.onTick` therefore generates signals evenly: accumulator `_acc += (cps / divider) × dt` and a signal for every whole unit. `dt` is the actual elapsed time (a delayed tick catches up); above 1 s, 100 ms is used.

Rules:
- Signals run only with fresh data (< 5 s) and a known cps.
- **Divider 1:1** or all three signals off → signals on the watch are off, only alarms remain.
- **Signal overload:** rate `cps / divider > MAX_RATE` = 10/s → `state.overload` (hysteresis: ends below 8/s); no signals are given, the display shows "CLICKING OFF" ("CVAKÁNÍ VYPNUTO"), every 2 s (`WARN_EVERY_TICKS` = 20) a warning of 3× tone/vibration, but not during an alarm sequence or within 2 s after an alarm burst.
- **Vibration:** only up to `VIBE_MAX_RATE` = 4/s (the motor needs ~250 ms). Above that, `state.vibeOver`, pulse vibrations are skipped and every `VIBE_OVER_EVERY_MS` = 10 s a rising weak–medium–strong vibration plays; the display shows "VIBRO MAX". Ends below 3/s.
- **Pulse tone:** 3000 Hz, 25 ms; not within 1 s after an alarm burst. Pulse vibration 40 ms; not within 1.2 s after an alarm burst.
- **Flashlight:** white flash on a pulse (`state.led`), turns off at the start of the next tick (≈100 ms). During an alarm (`alarmRedLed` and the watch supports red) the flashlight blinks only red every 500 ms for the whole alarm, regardless of the divider and clicking overload.
- **Backlight:** with `state.backlight`, `Attention.backlight(true)` every second.
- **Screen flash:** only on page 0 and not with the debug screen; the Clicker calls `requestUpdate` until `flashUntil`.
- **Linked divider** (`divLink`): after reading the Raysid settings, `BleManager.syncDivider()` sends the watch divider to the Raysid (one attempt per difference); a change in the Raysid menu is copied to the watch. The watch is the master.

## 14. Performance limits (watchdog, memory)

Connect IQ terminates the app when a single call (drawing, callback, timer) takes too many instructions. Project rule: **`onUpdate` and timer callbacks must be linear and bounded**.

| Place | Measure |
|---|---|
| Chart history | ring buffer `RaysidState.HIST` = 600 measurements (`histT`, `histDose`, `histCps`, `histAlarm`, plus `smDose`, `smCps`); at ~4 measurements/s it covers ~150 s, the chart is at most 60 s and the average at most 60 s |
| `smooth()` | one pass with a sliding window |
| Drawing | only the visible page is drawn; loops over the history stop at the start of the window |
| `HelpView` | text is wrapped only once (`_lines`) |
| Parser | `JUNK_MAX` = 120 bytes of checksum attempts per notification, buffer max. 1024 B |
| Chunk deletion | `Recorder.gcStep` at most 10 chunks per BLE tick (4 s) |
| Merging | `Recorder.compactStep` at most `CMP_STEP` = 4 chunks per call |
| Recorder start | `count` recalculated only with ≤ 100 pending chunks |
| `RaysidState.updateOvl` / `cpsDropped` / `avgSince` | go through only the last 10 s of history |

When making changes: do not add loops over the whole storage to `onUpdate` or `onTick`, do not call `Storage.getValue` in a loop without a cap, and do not create large arrays on every frame.

## 15. Known limitations

- According to `docs/ui-test-2026-10-15.md`, none of this has been verified in the Garmin simulator (the official fenix 7X Pro definition is missing in the cloud); on the watch only partially.
- When several `0x17` packets arrive in one notification, only the last one counts (`decode` overwrites `out[:cps]`).
- `System.getTimer()` overflows after about 24.8 days of uptime; the chart then shows empty for one window.
- When the app exits with completely full storage, at most ~100 of the last points may be lost.
- The ping and the BLE queue assume a single request in progress; a write without confirmation is considered lost after 3 s.
- During a connection outage the chart joins the last point before the outage and the first one after it with a line.
- GPS runs only while the app is open; closing the app ends recording (the route is closed).
- The packet checksum and the dose rate unit are derived from the incomplete Raysid API and from sniffing (see `docs/RAYSID-PROTOCOL.md`).

## 16. Known discrepancies in code and documentation

State as of build 82; verify in the code before fixing.

- **Dead code `:chartLen`:** `openChoice` and `ChoiceMenuDelegate` can choose the chart length, but no menu item creates `:chartLen`; the length is changed only with UP on the chart.
- **Unused translation keys:** `:mWatchSig`, `:avgOf`, `:aboveBg`, `:recPaused`; the constant `Tr.LANG_CODES` is not used.
- **Key `rOn`** is written but never read (recording is resumed after start only via `rAuto`).
- **Noise estimate σ** in `evaluateSoft` assumes the Raysid computes cps over a window of about 2 s (unverified), even though it sends data about every 0.25 s.
- **Comment in the `RaysidState` header** "Shared measurement state…" sits above the `clamp` function, not above the class.
- **The manifest** lists only the languages `ces` and `eng`, although the app also supports Polish (its own `Tr`).
- **`OVL_CPS_ON = false`** is a temporary test disabling of the cps ceiling; decide whether to restore it.
