# Architektura aplikace Raysid Garmin

Technická dokumentace pro vývojáře nebo AI agenta, který projekt přebírá bez předchozího kontextu. Popisuje stav zdrojového kódu ve `source/*.mc` (verze 1.1, build 82). Odkazuje na soubory a funkce, ne na čísla řádků. Mapování GPS a odesílání na web podrobně popisuje [MAPOVANI-A-ODESILANI.md](MAPOVANI-A-ODESILANI.md).

> Při rozporu mezi dokumentací a kódem platí kód; nesrovnalosti zapiš do [Známých nesrovnalostí](#16-známé-nesrovnalosti-v-kódu-a-dokumentaci).

## Obsah

1. [Přehled](#1-přehled)
2. [Moduly (soubory .mc)](#2-moduly-soubory-mc)
3. [Graf objektů](#3-graf-objektů)
4. [Tok dat od BLE notifikace po displej](#4-tok-dat-od-ble-notifikace-po-displej)
5. [Časovače](#5-časovače)
6. [Obrazovky a tlačítka](#6-obrazovky-a-tlačítka)
7. [Strom menu](#7-strom-menu)
8. [Stav a perzistence](#8-stav-a-perzistence)
9. [Překlady (Tr.mc)](#9-překlady-trmc)
10. [Přetížení (OVL)](#10-přetížení-ovl)
11. [Průměrování](#11-průměrování)
12. [Alarmy](#12-alarmy)
13. [Signalizace: cvakání, vibrace, svítilna](#13-signalizace-cvakání-vibrace-svítilna)
14. [Výkonová omezení (watchdog, paměť)](#14-výkonová-omezení-watchdog-paměť)
15. [Známá omezení](#15-známá-omezení)
16. [Známé nesrovnalosti v kódu a dokumentaci](#16-známé-nesrovnalosti-v-kódu-a-dokumentaci)

---

## 1. Přehled

- **Typ:** Connect IQ `watch-app` (`manifest.xml`), vstupní třída `RaysidApp`, `minApiLevel` 3.2.0, jediný produkt `fenix7xpro` (fēnix 7X Pro).
- **Oprávnění:** `BluetoothLowEnergy`, `Positioning`, `Communications`.
- **Jazyky v manifestu:** `ces`, `eng`. Aplikace ale překládá sama sebe přes `Tr.mc` (CZ/EN/PL), systémové řetězce v `resources/strings/strings.xml` jsou jen název aplikace a popisky nastavení v Garmin Connect.
- **Sestavení:** `bash build.sh [zařízení]` zapíše `source/BuildInfo.mc` (konstanty `APP_VERSION`, `APP_YEAR`, `BUILD_DATE`, `BUILD_NUM`; ručně neupravovat) a zavolá `monkeyc ... -l 3 -w` (nejpřísnější typová kontrola). Výstup jde do `build/Raysid-<zařízení>.prg`, u `fenix7xpro` i do `build/Raysid.prg`. `monkey.jungle` obsahuje jen `project.manifest = manifest.xml`.
- **Co aplikace dělá:** připojí se přes BLE k dozimetru Raysid, ukazuje dávkový příkon (µSv/h) a četnost impulzů (cps), kreslí graf, hlídá alarmy, signalizuje impulzy (tón/vibrace/svítilna). Volitelně zaznamenává body s GPS a posílá je přes telefon na web Žhavá místa.

## 2. Moduly (soubory .mc)

| Soubor | Odpovědnost | Klíčové třídy a funkce |
|---|---|---|
| `RaysidApp.mc` | Aplikace, sdílený stav měření a nastavení, historie pro graf, OVL, průměrování | `RaysidApp` (`onStart`, `onStop`, `onSettingsChanged`, `getInitialView`); `RaysidState` (`initialize` načte nastavení, `save`, `addSample`, `updateOvl`, `cpsDropped`, `smooth`, `smoothAt`, `avgSince`, `shownDose`, `shownCps`, `doseLimit`, `cpsLimit`, `softFactor`, `startAlarm`); globální `clamp()` a `put()` (zápis do `Storage`, který při plném úložišti vrátí `false` místo pádu) |
| `RaysidProtocol.mc` | Vše specifické pro Raysid: UUID, rámec příkazu, ping, kontrolní součty, dekódování paketů | modul `RaysidProtocol` (`profile`, `matches`, `initCommands`, `settingsCommands`, `pollCommand`, `ping`, `dividerCommand`, `soundCommand`, `doseAlarmCommand`, `cpsAlarmCommand`, `command`, `crc1`, `checksumOk`, `unpackValue`, `toHex`; konstanty `POLL_MS`, `WRITE_TYPE`, `UR_PER_USV`); třída `RaysidParser` (`feed`, `reset`, `decode`, `learnDelimiter`, `logPacket`); konstanta `KNOWN_TYPES` |
| `BleManager.mc` | Skenování, výběr Raysidu, párování, fronta zápisů, ping, obnova spojení, příjem dat a spuštění vyhodnocení | `BleManager extends BleDelegate` (`start`, `stop`, `restart`, `onScanResults`, `choose`, `connect`, `onConnectedStateChanged`, `subscribe`, `onTick`, `onCharacteristicChanged`, `send`, `requestSettings`, `syncDivider`, `enforcePin`, `adoptPaired`, `remember`, `clearHistory`, `pump`, `enqueue`) |
| `Alarms.mc` | Vyhodnocení pevného alarmu (meze) a měkkého alarmu (prudký nárůst) | `Alarms` (`evaluate`, `evaluateHard`, `evaluateSoft`, `reset`) |
| `Clicker.mc` | Časovač 100 ms: cvakání/vibrace/svítilna podle cps, sekvence alarmu, červená svítilna, stálé podsvícení, překreslení při probliknutí a blikání OVL | `Clicker` (`start`, `stop`, `onTick`, `click`, `alarmBurst`, `warn`, `updateVibeOver`, `alarmLed`, statická `hasLed`) |
| `Recorder.mc` | Záznam GPS bodů do `Application.Storage`, fronta bloků, slučování, mazání | `Recorder`; globální přístupová funkce `recorder()` |
| `Uploader.mc` | Odesílání bloků na Žhavá místa přes `Communications.makeWebRequest`, ověření klíče | `Uploader`; globální přístupová funkce `uploader()` |
| `RaysidView.mc` | Kreslení hlavní obrazovky, grafu, obrazovky Mapování a ladicí obrazovky | `RaysidView` (`onUpdate`, `drawChart`, `buildBuckets`, `drawBuckets`, `drawSeries`, `drawAlarmBands`, `drawMapping`, `drawRecord`, `drawDebug`, `drawMenuHint`, `drawClock`, `drawBatteries`, `fitText`, `fitFont`, `chordAt`); barvy `CHART_DOSE`, `CHART_CPS`, `UP_COLOR` |
| `RaysidDelegate.mc` | Tlačítka hlavních obrazovek, celé menu, výběrové seznamy, potvrzení mazání; konstanty nabídek a OVL; formátování čísel | `RaysidDelegate`, `RaysidMenuDelegate`, `ChoiceMenuDelegate`, `ClearConfirmDelegate`, `HelpMenuDelegate`, `DevicePickDelegate`; funkce `doseNum`, `cpsNum`, `doseLabel`, `cpsLabel`, `recordLabel`, `storeLabel`, `cmpLabel`, `cmpSubLabel`, `refreshItem`, `aboutText` … |
| `ValuePicker.mc` | Zadání vlastní číselné hodnoty po číslicích systémovým `Picker` | `DigitFactory`, `DigitPicker`, `DigitPickerDelegate` (`onAccept` ořízne hodnotu do rozsahu) |
| `KeyEntry.mc` | Zadání API klíče Žhavých míst přímo v hodinkách | `KeyEntryView`, `KeyEntryDelegate`; funkce `currentKey()`, `keyLabel()`; konstanty `KEY_CHARS`, `KEY_LEN` |
| `HelpView.mc` | Stránka nápovědy se zalamováním po slovech a posunem | `HelpView` (`wrap` jednou, `scroll`), `HelpDelegate` |
| `Tr.mc` | Překladová tabulka CZ/EN/PL | modul `Tr` (`t`, `build`, proměnná `lang`) |
| `BuildInfo.mc` | Verze a číslo buildu | generuje `build.sh` |

## 3. Graf objektů

```
RaysidApp (AppBase, entry v manifest.xml)
 ├─ state    : RaysidState     sdílený stav, nastavení, historie (vytvořen první)
 ├─ ble      : BleManager      dostane state; vlastní RaysidParser a Alarms
 ├─ clicker  : Clicker         dostane state
 ├─ uploader : Uploader        bez parametrů
 └─ recorder : Recorder        dostane state (vytvořen poslední)

Globální přístup (funkce na úrovni souboru):
  recorder() -> (Application.getApp() as RaysidApp).recorder     (Recorder.mc)
  uploader() -> (Application.getApp() as RaysidApp).uploader     (Uploader.mc)

Views:
  getInitialView() -> [RaysidView(state), RaysidDelegate(state, ble)]
  RaysidDelegate při přepnutí stránky vytváří novou dvojici View/Delegate
  (WatchUi.switchToView), stránka je v state.page.
```

Pořadí v `RaysidApp.onStart`: `BluetoothLowEnergy.setDelegate(ble)`, `ble.start()`, `clicker.start()`, `recorder.resume()`, `uploader.start()`.
Pořadí v `onStop`: `clicker.stop()`, `uploader.stop()`, `recorder.suspend()`, `ble.stop()`.
`onSettingsChanged` (změna v Garmin Connect) volá `uploader.settingsChanged()`.

Vazby mezi moduly jdou přes `state` (data) a přes globální `recorder()`/`uploader()`:
- `BleManager.onTick` volá `recorder().gcStep()` a `recorder().compactTick()` (postupné mazání a dobíhající slučování).
- `Recorder.closeChunk` volá `uploader().kick()`; `Recorder.clear` volá `uploader().cancel()`.
- `Uploader` čte frontu přes `recorder().headChunk()`, `dropHead()`, `pending()`, `enabled`, `on`, `paused`, `count`.
- `RaysidView` a menu čtou `recorder()` a `uploader()` pro popisky.

## 4. Tok dat od BLE notifikace po displej

```
Raysid ──notify (RX 49535343-1e4d-…-9616)──► BleManager.onCharacteristicChanged(value)
   │  state.packets++, _lastRx = teď, (ladění: state.lastRaw = hex)
   ▼
RaysidParser.feed(value)            skládá buffer, hledá oddělovač, ověří XOR součet
   │  vrací Dictionary jen s klíči, které v datech byly:
   │  :cps, :doseRate (µSv/h), :ovl, :battery, :temp, :devDiv/:devSound/:devDoseAl/:devCpsAl, :btn
   ▼
BleManager.onCharacteristicChanged
   ├─ :battery          → state.battery
   ├─ :devDiv …         → state.devDiv…, syncDivider(), updateDevMenu()   (jen nejnovější odpověď, viz _setReq)
   ├─ :btn              → requestSettings() (tlačítko na Raysidu změnilo nastavení)
   ├─ :ovl              → state.devOvl
   └─ :doseRate / :cps  → state.doseRate / state.cps, state.lastUpdate, intervalMs
          │  (jen když jsou známé obě hodnoty)
          ├─ state.updateOvl(now, dose, cps)                   → cpsOvlOn, doseOvlOn, ovl
          ├─ aDose/aCps = při OVL aspoň OVL_DOSE / OVL_CPS
          ├─ alarm = Alarms.evaluate(now, aDose, aCps)        → hardAlarm, softAlarm, flashUntil, seq*
          └─ state.addSample(now, doseRate, cps, alarm)       → kruhový buffer histT/histDose/histCps/histAlarm
   ▼
WatchUi.requestUpdate() → RaysidView.onUpdate (kreslí jen aktuální stránku)

Paralelně čtou stav:
  Clicker.onTick (100 ms)      state.cps, divider, overload, seqLeft …  → tóny, vibrace, svítilna
  Recorder.onPosition (~1 Hz)  state.lastUpdate, ovl, avgSince()        → body mapování (Storage)
  Uploader.kick (30 s / událost) recorder().headChunk()                 → HTTP POST
```

Podrobnosti parseru (`RaysidParser.feed`):
- Paket: `[Size] [Type] [Payload] [Checksum 3 B]`. Součet je XOR 3bajtových bloků; `RaysidProtocol.checksumOk` přijme little i big endian variantu (API.md a cps-doserate.py se liší).
- Mezi pakety může být oddělovač (pozorováno `0x84` i `0x10`). `learnDelimiter` ho přijme po 3 výskytech. Po `RELEARN_AFTER` = 10 notifikacích bez platného paketu se učí znovu.
- Ochrana proti watchdogu: nejvýš `JUNK_MAX` = 120 bajtů smetí se zkouškou součtu na jednu notifikaci; buffer nad 1024 B se zkrátí na posledních 512 B.
- Typ `0x17`: bloky `[range, LSB, MSB]`, hodnota `unpackValue(v) / 600`; range 0 = cps, 1 = dávka v µR/h, dělená `UR_PER_USV` = 100 → µSv/h. Bajt před součtem je příznak OVL Raysidu (jen když `(size - 5) % 3 == 1`).
- Typ `0x0a`: nastavení Raysidu (`p[4]` dělička, `p[6]` zvuk, `p[10]` bit `0x10` alarm dávky, bit `0x01` alarm cps).
- Typ `0x02`: teplota a baterie (baterie přímo v procentech, ne v desetinách, jak uvádí API.md).
- Typ `0x18`: stisk tlačítka na Raysidu (`:btn`).

BLE připojení (`BleManager`):
- `start` → `register()` (`registerProfile`) → `onProfileRegister` → `adoptPaired()` (převezme Raysid, který zůstal spojený z předchozí instance aplikace) nebo `startScan()`.
- `onScanResults`: Raysid se pozná podle jména obsahujícího „raysid“ nebo UUID služby (`RaysidProtocol.matches`). Vybraný Raysid (`pin`) se připojí hned (při `lock` nebo `pref == 0`), jinak se kandidáti sbírají `CHOOSE_MS` = 3 s a `choose()` vybere podle historie (`pref` 0) nebo nejsilnějšího signálu (`pref` 1). Historie má nejvýš `HISTORY_MAX` = 6 jmen.
- Po připojení `subscribe()`: zápis CCCD a `initCommands()` (= čtení nastavení: ping na obrazovku 9, `0x1f 00`, `0x1b 01`, `0x1b 02`, ping na obrazovku 0).
- Connect IQ dovolí jen jeden rozpracovaný BLE požadavek, proto fronta `_queue` + `_busy`; pojistka uvolní `_busy` po 3 s bez potvrzení. Zápis se posílá `WRITE_TYPE_WITH_RESPONSE`.
- Rámec příkazu (`RaysidProtocol.command`): `[0xFF] [CRC2] [0xEE] [CRC1 4 B BE] [payload] [celková délka]`.

## 5. Časovače

| Časovač | Kde | Perioda | Co dělá |
|---|---|---|---|
| Clicker | `Clicker._timer` → `onTick` | `TICK_MS` = 100 ms | zhasne svítilnu z minulého tiku; stálé podsvícení (každý 10. tik); `requestUpdate` pro probliknutí alarmu (jen stránka 0) a blikání OVL (po 500 ms); dávky alarmu (`seqLeft`, rozestup `SEQ_GAP_MS` = 2 s); červená svítilna při alarmu (každý 5. tik); rovnoměrné cvakání/vibrace/svítilna podle cps; varování při přetížení signalizace |
| BLE | `BleManager._timer` → `onTick` | `RaysidProtocol.POLL_MS` = 4000 ms | `recorder().gcStep()`, `recorder().compactTick()`; timeout párování `CONNECT_TIMEOUT_MS` = 15 s; obnova spojení po `RECOVER_MS` = 30 s bez spojení nebo bez dat; `choose()`; `requestUpdate` (hodiny, zešednutí); ping na začátek fronty (jen když ve frontě není rozpracované čtení nastavení `:seq`); uvolnění zaseknutého `_busy` |
| Uploader | `Uploader._timer` → `onTick` → `kick()` | `TICK_MS` = 30 000 ms | pokus o odeslání nejstaršího bloku; běží jen když je mapování povolené nebo zbývají neodeslané bloky (`Uploader.active`) |
| Poloha | `Position.enableLocationEvents(LOCATION_CONTINUOUS)` → `Recorder.onPosition` | systémově ~1 s | jen při běžícím nahrávání; vznik bodů |

Jiné časovače aplikace nemá. Kreslení spouští `WatchUi.requestUpdate()` z BLE notifikací (Raysid posílá měření zhruba každých 0,25 s), z BLE tiku, z Clickeru a z menu.

## 6. Obrazovky a tlačítka

Stránky (`state.page`, neukládá se):

| `page` | Obrazovka | Obsah | Akce UP |
|---|---|---|---|
| 0 | Hlavní | dávka (oranžově) a cps (modře) velkým písmem, stav připojení nebo text alarmu nahoře, hodiny, baterie Raysidu a hodinek, upozornění CVAKÁNÍ VYPNUTO / VIBRO MAX, stav nahrávání dole (`drawRecord`) | prohodí, co je nahoře (`swapMain`, klíč `swap`) |
| 1 | Graf | aktuální hodnoty, graf dávky a cps s vlastními stupnicemi, alarmové úseky podbarvené, rozsah a stav plnění | další délka z `CHART_LENGTHS` = 10/20/30/60 s (klíč `cw`) |
| 2 | Mapování | jen při `recorder().enabled`; stav REC/GPS, vzdálenost, body, doba, max. dávka a cps, stav webu | `recorder().start()` nebo `pause()` |
| – | Ladicí | překrývá všechny stránky, když `state.showDebug`: počet paketů, počty typů, hex posledního paketu, interval měření | nic |

Tlačítka (`RaysidDelegate`):

| Tlačítko | Chování |
|---|---|
| **DOWN** (`onNextPage`) | cyklí stránky 0 → 1 → (2) → 0 (`switchPage`, animace SLIDE_UP). Při ladicí obrazovce nic. |
| **UP** (`onPreviousPage`) | akce podle stránky (tabulka výše). Při ladicí obrazovce nic. |
| **START** | menu. Na fenixu chodí podle firmwaru jako `onKey(KEY_ENTER)` nebo `onSelect`; `onSelect` se ignoruje 700 ms po dotyku (`_lastTap`), protože klepnutí na displej volá také `onSelect`. |
| **BACK** | delegát `onBack` nepřepisuje, výchozí chování ukončí aplikaci (`onStop` trasu korektně uzavře). |
| **LIGHT** | aplikace ho nezpracovává (`onKey` vrací `false` pro vše kromě `KEY_ENTER`), zůstává systému. |
| **Podržení** | nic se nedrží: podržení UP/DOWN spouští systémové zkratky hodinek. `onMenu` (podržení UP) vrací `true` a nic nedělá. Stejné pravidlo platí pro `ValuePicker.mc` a `KeyEntry.mc`. |
| **Dotyk / swipe** | `onTap` a `onSwipe` vracejí `true` a nic nedělají. |
| **Jakékoli tlačítko při zvonění alarmu** | `onKey` při `state.seqLeft > 0` jen vynuluje `seqLeft` (umlčí) a událost spotřebuje. |

Značky u tlačítek kreslí `RaysidView.drawMenuHint` jako oblouky na okraji: START šedě, UP žlutě a tlustěji (má akci obrazovky), DOWN tmavě šedě.

Graf (`RaysidView.drawChart`): dokud nejsou data za celou délku, graf se roztáhne na souvislý úsek (přerušení > 5 s začíná nový úsek), nejméně 10 s. U délky nad 30 s (tedy 60 s) se kreslí úseky (`buildBuckets`): délka úseku `max(span / 24, 4000 ms)`, silná čára je průměr, u cps navíc tenká čárka min–max. Stupnice `scale()` mají minimální rozpětí 20 % středu (aspoň 0,005 µSv/h nebo 0,5 cps). Hodnoty zešednou, když 5 s nepřijde měření.

## 7. Strom menu

Menu staví `RaysidDelegate.openMenu` a `RaysidMenuDelegate.onSelect`. Výběr jedné hodnoty obsluhuje `ChoiceMenuDelegate` (`openChoice`), „Vlastní hodnota…“ otevře `DigitPicker`. Po návratu z podmenu `RaysidMenuDelegate.onBack` obnoví popisek nadřazené položky (`refreshItem`). Názvy jsou v češtině podle `Tr.mc`, v závorce ID položky.

```
Raysid (START)
├─ Signalizace (:mSignal)                       signalizace v hodinkách
│  ├─ Dělička (:divider)                        1:1 (jen alarmy), 1:5, 1:10, 1:20, 1:50, 1:100, 1:250   → state.divider
│  ├─ Cvakání (:beep)                           tón ke každému N-tému impulzu   → state.sound
│  ├─ Vibrace k impulzům (:vibration)           → state.vibrate
│  └─ Blikání svítilnou (:flash)                jen když Clicker.hasLed()   → state.led
├─ Alarmy (:mAlarms)                            popisek „zapnuto“ jen když je zapnutý hlavní vypínač a aspoň jeden alarm
│  ├─ Všechny alarmy (:alarmsAll)               hlavní vypínač → state.alarmsOn
│  ├─ Dávka (:gDose)
│  │  ├─ Alarm dávky (:doseAlarm)               → state.doseOn
│  │  └─ Mez dávky (:doseLimit)                 0.3 … 500 µSv/h (DOSE_LIMITS) + vlastní 000.00 (0,05–999)
│  ├─ Cps (:gCps)
│  │  ├─ Alarm cps (:cpsAlarm)                  → state.cpsOn
│  │  └─ Mez cps (:cpsLimit)                    50 … 5000 (CPS_LIMITS) + vlastní 4 číslice (5–5000)
│  ├─ Prudký nárůst (:gRise)
│  │  ├─ Hlídání nárůstu (:rise)                → state.softOn
│  │  └─ Citlivost (:sensitivity)               +30 / +50 / +100 % + vlastní 3 číslice (10–300)
│  └─ Projev alarmu (:mAlarmOut)
│     ├─ Zvuk alarmu (:alarmSound)
│     ├─ Vibrace alarmu (:alarmVibe)
│     ├─ Bliknutí displeje (:alarmFlash)
│     ├─ Červená svítilna (:alarmRedLed)        jen když Clicker.hasLed()
│     └─ Délka alarmu (:alarmLen)               krátký (1×) / střední (3×) / dlouhý (8×)
├─ Raysid (:mDevice)                            nastavení uložená přímo v dozimetru; při otevření requestSettings()
│  ├─ Dělička (:devDiv)                         posílá 0x16 N; bez spojení jen „Odpojeno“
│  ├─ Sloučit děličku (:divLink)                dělička hodinek = dělička Raysidu (syncDivider)
│  ├─ Cvakání (:devSound)                       posílá 0x03 0/1; „?“ dokud Raysid stav nenahlásí
│  ├─ Alarm dávky (:devDoseAl)                  posílá 0x18 0/1
│  ├─ Alarm cps (:devCpsAl)                     posílá 0x17 0/1
│  └─ Připojení (:mConn)
│     ├─ Znovu připojit (:reconnect)            ble.restart(), zavře všechna menu
│     ├─ Vybraný Raysid (:devPick)              kterýkoli / jména z historie / Zapomenout historii
│     ├─ Jen vybraný Raysid (:devLock)          nejde zapnout bez vybraného („nejdřív vyber Raysid“)
│     └─ Více Raysidů (:connPref)               vybraný, pak známý / nejsilnější signál
├─ Displej (:mDisplay)
│  ├─ Průměrování (:avgMode)                    Okamžité hodnoty / Podle času / Podle počtu měření
│  ├─ Průměr přes (:avgSpan)                    jen při průměrování: 2/4/6/10 s nebo 2/3/5/10/20 měření + vlastní (do 60 s / 30 měření)
│  ├─ Stálé podsvícení (:backlight)
│  └─ Ladicí obrazovka (:debug)                 neukládá se
├─ Žhavá místa (:mRecord)
│  ├─ Mapování zapnuto (:mapping)               celý modul; vypnuté skryje stránku Mapování i zbytek podmenu
│  ├─ Nahrávat po spuštění (:autostart)
│  ├─ Vzdálenost bodů (:recDist)                5/8/10/12/15 m + vlastní 3 číslice (2–200 m)
│  ├─ Kvalita GPS (:gpsQual)                    dobrá (4) / použitelná (3) / slabá (2)
│  ├─ Web a odesílání (:mWeb)
│  │  ├─ Odesílání na web (:upload)             stav; výběr = uploader().retry()
│  │  ├─ API klíč (:apiKey)                     KeyEntryView
│  │  └─ Ověřit spojení (:verify)               uploader().startVerify()
│  └─ Úložiště (:mStorage)
│     ├─ Neodesláno (:stoPending)               počet bodů a % z MAX_POINTS; výběr obnoví popisek
│     ├─ Když se zaplní (:cmpMax)               Zastavit nahrávání / Sloučit nejvýš 1×, 2×, 3× / Slučovat bez omezení
│     └─ Smazat neodeslané (:recClear)          potvrzení → recorder().clear()
├─ Nápověda (:mHelp)                            Ovládání, Obrazovky, Mapování (jen při zapnutém mapování),
│                                               Signalizace, Alarmy, Hlídání nárůstu, O aplikaci
└─ Jazyk (:mLanguage)                           Čeština / English / Polski; po změně se menu zavře
```

Nahrávání se nespouští z menu, ale tlačítkem UP na stránce Mapování (nebo automaticky volbou Nahrávat po spuštění).

Vlastní hodnoty (`ChoiceMenuDelegate.openPicker`): `DigitPicker(title, intDigits, decDigits, current)` + `DigitPickerDelegate(decDigits, min, max, callback)`. UP/DOWN mění číslici, START jde na další a na poslední potvrdí, BACK se vrací. Hodnota mimo rozsah se v `onAccept` posune na okraj.

## 8. Stav a perzistence

### 8.1 Application.Storage

Zápis jde přes globální `put()` (nespadne při plném úložišti). Čtení nastavení v `RaysidState` přes privátní `load()`, který vrátí výchozí hodnotu, když chybí nebo má jiný typ. `RaysidState.save()` zapisuje všechna nastavení najednou (volá se z menu); UP na hlavní obrazovce a grafu zapisuje jen `swap` nebo `cw`.

**Nastavení měření a signalizace (vlastník `RaysidState`, `RaysidApp.mc`)**

| Klíč | Typ | Výchozí | Význam |
|---|---|---|---|
| `bl` | Boolean | false | stálé podsvícení |
| `snd` | Boolean | false | cvakání (tón k impulzům) |
| `led` | Boolean | false | blikání svítilnou k impulzům |
| `vib` | Boolean | false | vibrace k impulzům |
| `div` | Number | 10 | dělička hodinek 1:N; při načtení se přichytí k nejbližší z `DIVIDERS` |
| `dvL` | Boolean | false | sloučit děličku hodinek s Raysidem |
| `cw` | Number | 30 | délka grafu v s, ořez 10–60 |
| `swap` | Boolean | false | hlavní obrazovka: cps nahoře |
| `avM` | Number | 0 | průměrování: 0 okamžité, 1 podle času, 2 podle počtu (ořez 0–2) |
| `avS` | Number | 10 | délka průměru v s (ořez 2–60) |
| `avN` | Number | 5 | počet měření průměru (ořez 2–30) |
| `aOn` | Boolean | true | hlavní vypínač alarmů |
| `adOn` | Boolean | false (podle `ad`) | alarm dávky zapnut |
| `ad` | Float | 1.0 | mez dávky µSv/h (0,05–999); starší verze měly 0 = vypnuto |
| `acOn` | Boolean | podle `ac` | alarm cps zapnut |
| `ac` | Number | 1000 | mez cps (5–`ALARM_CPS_MAX` = 5000) |
| `slOn` | Boolean | podle `sl` | hlídání nárůstu zapnuto |
| `sp` | Number | 50 | citlivost nárůstu v % (10–300) |
| `sl` | Number | – | jen čtení: starší kódování citlivosti (0 vypnuto, 1–3 = 30/50/100 %), migruje se do `slOn` + `sp` |
| `aSnd` / `aVib` / `aFl` / `aRed` | Boolean | true | projev alarmu: zvuk / vibrace / probliknutí / červená svítilna |
| `aLen` | Number | 1 | délka alarmu 0 krátký, 1 střední, 2 dlouhý |
| `lang` | Number | podle jazyka hodinek | 0 čeština, 1 angličtina, 2 polština (`Tr.lang`) |
| `lgI`, `lg0`…`lg19` | – | – | pozůstatek buildu 68; `RaysidState.initialize` je smaže, pokud `lgI` existuje |

Pozn.: výchozí hodnoty při úplně první instalaci: `ac` chybí → `acOn = load("acOn", 1000 > 0)` = **true**; `sl` chybí → výchozí 2 → `slOn` = **true**; `ad` chybí → `adOn` = **false**. Alarm cps a hlídání nárůstu jsou tedy po instalaci zapnuté, alarm dávky vypnutý.

**Připojení (vlastník `BleManager`)**

| Klíč | Typ | Význam |
|---|---|---|
| `devPin` | String | vybraný Raysid (jméno); smaže se při „kterýkoli“ |
| `devLock` | Boolean | připojovat jen vybraný |
| `devPref` | Number | při více kusech: 0 vybraný/známý, 1 nejsilnější signál |
| `devHist` | Array `[[jméno, unix čas], …]` | historie připojených, nejnovější první, max. 6 |

**Mapování (vlastník `Recorder`)** – formát a význam podrobně v [MAPOVANI-A-ODESILANI.md](MAPOVANI-A-ODESILANI.md#2-formát-v-úložišti):
`rEn`, `rAuto`, `rDist`, `rQual`, `rCmp`, `rHead`, `rChunks`, `rCount`, `rFull`, `rGc`, `rRoute`, `rRName`, `rBatch`, `rRPts`, `rPart`, `rStart`, `rSess`, `rMeters`, `rMaxD`, `rMaxC`, `rOn` (jen zápis), bloky `r<i>` a popisy `rm<i>`.

**Odesílání (vlastník `KeyEntry.mc`)**

| Klíč | Typ | Význam |
|---|---|---|
| `zmKeyBak` | String | záloha API klíče pro případ, že se `Properties` při aktualizaci aplikace ztratí; čte ji `currentKey()` |

Nepersistentní: `state.page`, `state.showDebug`, živé hodnoty, historie grafu, stav alarmů, stav OVL, nastavení Raysidu (`devDiv` …, čtou se po připojení).

### 8.2 Application.Properties (nastavení v Garmin Connect)

Definice v `resources/settings/properties.xml` a `settings.xml`, čte je `Uploader.prop()` a `currentKey()`:

| Klíč | Typ | Výchozí | Význam |
|---|---|---|---|
| `zmUpload` | boolean | true | odesílat na Žhavá místa (`Uploader.enabled()`) |
| `zmKey` | string (password) | "" | API klíč; zapisuje ho i `KeyEntryDelegate.save` |
| `zmUrl` | string (alphaNumeric) | "" | jiná adresa endpointu, prázdné = `Uploader.DEFAULT_URL` |

U aplikace nahrané přes USB nastavení v Garmin Connect nejde použít, proto se klíč zadává v hodinkách (`KeyEntry.mc`).

## 9. Překlady (Tr.mc)

- Modul `Tr`: `Tr.lang` (0 CZ, 1 EN, 2 PL) a `Tr.t(:klíč)`. Tabulka se postaví jednou (`build()`) při prvním volání a pak zůstává v paměti. Chybějící klíč vrátí jméno symbolu (nespadne, ale na displeji je vidět např. `myKey`).
- Výchozí jazyk při prvním spuštění: `System.LANGUAGE_CES` → 0, `LANGUAGE_POL` → 2, jinak 1 (`RaysidState.initialize`). Uloženo pod `lang`.
- Stav připojení i stav odesílání se ukládají jako symboly (`state.status`, `Uploader.status`, `Uploader.verify`) a překládají se až při kreslení, takže změna jazyka platí hned.
- Texty nápovědy jsou dlouhé řetězce (`:hControlsT`, `:hScreensT`, `:hSignalT`, `:hAlarmsT`, `:hRecordT`, `:hRiseT`); `HelpView` je zalamuje po mezerách, samostatné slovo `\n` znamená nový řádek. Text „O aplikaci“ skládá `aboutText()` z `BuildInfo.mc`.
- Na MIP displeji se některé znaky (šipky, výpustka) můžou zobrazit jako čtverečky; v textech se proto používá `>` a `...`.

**Jak přidat řetězec:**
1. Do slovníku v `Tr.build()` přidat řádek `:mujKlic => ["česky", "English", "polski"],` (vždy tři položky ve stejném pořadí).
2. V kódu použít `Tr.t(:mujKlic)`.
3. Ověřit délku na kulatém displeji (položky menu a stavové řádky se zkracují jen někde, viz `RaysidView.fitText`).

**Jak přidat jazyk:** přidat čtvrtý prvek do každého pole v `Tr.build()`, doplnit `LANG_NAMES` v `RaysidDelegate.mc`, rozšířit `clamp(..., 0, 2)` u `lang` v `RaysidState.initialize` a výchozí volbu podle `systemLanguage`; případně `LANG_CODES` v `Tr.mc` (zatím se nikde nepoužívá) a jazyk v `manifest.xml`.

## 10. Přetížení (OVL)

Při velmi vysoké četnosti impulzů se detektor Raysidu zahltí a hlásí useknuté (nízké) cps. Aplikace pak místo čísla ukazuje blikající „OVL“, nezapisuje body mapování a vynutí alarmy. Logika je v `RaysidState.updateOvl` a `cpsDropped`, konstanty v `RaysidDelegate.mc`.

Stav: `state.cpsOvlOn`, `state.doseOvlOn`, souhrnně `state.ovl = cpsOvlOn || doseOvlOn`. OVL se zobrazuje jen u veličiny, která do něj spadla (`cpsOvl()`, `doseOvl()`).

**1. Raysid posílá příznak** (`state.devOvl != null`, bajt v paketu `0x17`): `cpsOvlOn = devOvl`. Vlastní odhad se nepoužívá.

**2. Raysid příznak neposílá** – odhad z průběhu (`cpsDropped`):
- Špička cps a dávka v ní za posledních `OVL_DROP_MS` = 10 s.
- Nespustí se, když špička < `OVL_DROP_MIN_CPS` = 2000 cps nebo dávka < `OVL_RESET_DOSE` = 10 µSv/h.
- Rychlé pravidlo: cps ≤ `OVL_FAST_CPS` (0,90) × špička a dávka ≥ `OVL_FAST_DOSE` (0,95) × dávka ve špičce.
- Pravidlo poklesu: cps ≤ `OVL_DROP_CPS` (0,5) × špička a poměr dávky ≥ `OVL_DROP_GAP` (1,5) × poměr cps a zároveň dávka neklesla.
- Strop `OVL_CPS` = 7200 cps se uplatní jen při `OVL_CPS_ON` = **false** (vypnuto na test, komentář „Vít, 14.10.2026“).
- Konec cps OVL: návrat ke špičce (`cps ≥ OVL_EXIT_CPS` 0,9 × špička, dávka ≤ `OVL_EXIT_DOSE` 1,3 × dávka ve špičce, dávka neroste) `OVL_EXIT_N` = 2 měření po sobě; nebo cps a dávka jdou stejným směrem (krok ≥ `OVL_SAME_STEP` 5 %) `OVL_SAME_N` = 3 měření po sobě; nebo dávka < `OVL_RESET_DOSE` = 10 µSv/h.

**Dávka (v obou režimech):** `doseOvlOn` při dávce > `OVL_DOSE` = 999 µSv/h, konec pod `OVL_DOSE_RESET` = 900 µSv/h.

**Důsledky OVL:**
- `BleManager.onCharacteristicChanged` předá alarmům aspoň `OVL_DOSE` / `OVL_CPS` (do historie jdou surové hodnoty).
- `Alarms.evaluateHard`: při OVL a zapnutém alarmu dávky nebo cps je alarm aktivní bez ohledu na mez.
- `Recorder.onPosition`: `noData = true`, bod se nezapíše a průměr k dalšímu bodu začne až po konci OVL.
- Po odpojení a při novém připojení `BleManager.clearLive()` OVL i alarmy vynuluje a `devOvl` nastaví na `null`.

Meze alarmů jsou omezené pod OVL: `ALARM_CPS_MAX` = 5000 (Raysid hlásí OVL od ~5,4–5,8 kcps), `ALARM_DOSE_MAX` = 999.

## 11. Průměrování

- Ukládá se jen surové měření (`addSample`). Průměr se počítá při kreslení, takže změna nastavení platí hned i pro celý graf.
- `avgMode` 0 okamžité, 1 podle času (`avgSec`), 2 podle počtu (`avgN`).
- Čísla nahoře: `shownDose()` / `shownCps()` → `smoothAt(nejnovější, 60000)`; okno je navíc omezené na 60 s zpět, aby po výpadku nemíchalo staré hodnoty.
- Graf: `smooth(tMin, capMs)` jedním průchodem s klouzavým oknem (každé měření se přičte a odečte jednou) naplní `smDose`/`smCps`. `capMs = chartSec × 200`, tedy průměr v grafu je nejvýš pětina délky grafu.
- **Alarmy, signalizace a body mapování vždy používají okamžité hodnoty**, ne zobrazený průměr. Body mapování mají vlastní průměr `avgSince()` (viz druhý dokument).

## 12. Alarmy

Vyhodnocuje `Alarms.evaluate(now, dose, cps)` při každém měření (kdy jsou známé dávka i cps). Výsledek 0/1/2 jde do `histAlarm` pro podbarvení grafu. Účinné meze vrací `RaysidState.doseLimit()`, `cpsLimit()`, `softFactor()` (0 = vypnuto; respektují hlavní vypínač `alarmsOn`).

**Pevný alarm (`evaluateHard`):**
- Spustí se, když `ovl` (a je zapnutý alarm dávky nebo cps), nebo dávka ≥ mez, nebo cps ≥ mez.
- Zhasne až když není OVL a obě veličiny jsou pod **90 %** své meze (hystereze).
- Při spuštění: `flashUntil = now + 1500` (je-li zapnuté probliknutí), barva červená, `startAlarm(2)`.
- Na displeji je pak místo stavového řádku červené „ALARM: překročena mez“ a hodnota nad mezí je červená (podle okamžité hodnoty).

**Měkký alarm – prudký nárůst (`evaluateSoft`), časový:**
- Pozadí `_baseline` je exponenciální průměr s časovou konstantou `BASE_MS` = 20 s (`a = dt / 20000`), učí se jen mimo alarm.
- Před prvním alarmem zahřátí `WARMUP_MS` = 20 s.
- Spuštění: `rise > baseline × f` a zároveň `rise > 3σ`, kde `σ = sqrt(baseline / 2 + 1)` (Poissonův šum cps měřených ~2 s).
- Konec: cps pod `baseline × (1 + f/2)` po `QUIET_MS` = 4 s, nebo po `SOFT_MAX_MS` = 60 s trvání (pak se pozadí přenastaví na aktuální cps).
- Probliknutí 600 ms tmavě červeně a `startAlarm(1)` jen pokud zrovna neběží pevný alarm.

**Sekvence alarmu:** `RaysidState.startAlarm` nastaví `seqLeft` = 1 / 3 / 8 dávek podle `alarmLen`; `Clicker.onTick` je přehrává po `SEQ_GAP_MS` = 2 s (dlouhý alarm ≈ 15 s). Pevný: `TONE_ALERT_HI` + dvojitá vibrace 300 ms. Měkký: stoupající dvojtón + vibrace 200 ms. Zvuk a vibrace se řídí `alarmSound` / `alarmVibe`.

**Umlčení a vypnutí:** jakékoli tlačítko, které dostane `RaysidDelegate.onKey` na kterékoli stránce (`seqLeft = 0`); vypnutí kteréhokoli alarmu v menu utne sekvenci; vypnutí `alarmsOn` zhasne oba stavy; odpojení Raysidu volá `Alarms.reset()`.

## 13. Signalizace: cvakání, vibrace, svítilna

Raysid neposílá jednotlivé impulzy, jen cps. `Clicker.onTick` proto generuje signály rovnoměrně: akumulátor `_acc += (cps / divider) × dt` a signál při každé celé jednotce. `dt` je skutečně uplynulý čas (zpožděný tik se dorovná), nad 1 s se bere 100 ms.

Pravidla:
- Signalizace běží jen při čerstvých datech (< 5 s) a známém cps.
- **Dělička 1:1** nebo všechny tři signály vypnuté → signalizace v hodinkách vypnutá, zůstávají jen alarmy.
- **Přetížení signalizace:** rychlost `cps / divider > MAX_RATE` = 10/s → `state.overload` (hystereze: konec pod 8/s); signály se nedávají, na displeji „CVAKÁNÍ VYPNUTO“, každé 2 s (`WARN_EVERY_TICKS` = 20) varování 3× tón/vibrace, ale ne během sekvence alarmu ani 2 s po jeho dávce.
- **Vibrace:** jen do `VIBE_MAX_RATE` = 4/s (motor potřebuje ~250 ms). Nad tím `state.vibeOver`, vibrace k impulzům se vynechávají a každých `VIBE_OVER_EVERY_MS` = 10 s zazní sílící vibrace slabá–střední–silná, na displeji „VIBRO MAX“. Konec pod 3/s.
- **Tón impulzu:** 3000 Hz, 25 ms; ne do 1 s po dávce alarmu. Vibrace impulzu 40 ms; ne do 1,2 s po dávce alarmu.
- **Svítilna:** bílý záblesk k impulzu (`state.led`), zhasne na začátku dalšího tiku (≈100 ms). Během alarmu (`alarmRedLed` a hodinky umí červenou) bliká svítilna jen červeně každých 500 ms po celou dobu alarmu, nezávisle na děličce a přetížení cvakání.
- **Podsvícení:** při `state.backlight` `Attention.backlight(true)` každou sekundu.
- **Probliknutí displeje:** jen na stránce 0 a ne při ladicí obrazovce; Clicker volá `requestUpdate` do `flashUntil`.
- **Sloučená dělička** (`divLink`): po přečtení nastavení Raysidu `BleManager.syncDivider()` pošle děličku hodinek do Raysidu (jeden pokus na rozdíl); změna v menu Raysid se propíše do hodinek. Hodinky jsou hlavní.

## 14. Výkonová omezení (watchdog, paměť)

Connect IQ ukončí aplikaci, když jedno volání (kreslení, callback, časovač) trvá příliš mnoho instrukcí. Pravidlo projektu: **`onUpdate` a callbacky časovačů musí být lineární a omezené**.

| Místo | Opatření |
|---|---|
| Historie grafu | kruhový buffer `RaysidState.HIST` = 600 měření (`histT`, `histDose`, `histCps`, `histAlarm`, plus `smDose`, `smCps`); při ~4 měřeních/s pokrývá ~150 s, graf má nejvýš 60 s a průměr nejvýš 60 s |
| `smooth()` | jedním průchodem s klouzavým oknem |
| Kreslení | kreslí se jen viditelná stránka; smyčky přes historii končí na začátku okna |
| `HelpView` | text se zalomí jen jednou (`_lines`) |
| Parser | `JUNK_MAX` = 120 bajtů zkoušek součtu na notifikaci, buffer max. 1024 B |
| Mazání bloků | `Recorder.gcStep` nejvýš 10 bloků za BLE tik (4 s) |
| Slučování | `Recorder.compactStep` nejvýš `CMP_STEP` = 4 bloky na volání |
| Start Recorderu | přepočet `count` jen při ≤ 100 čekajících blocích |
| `RaysidState.updateOvl` / `cpsDropped` / `avgSince` | procházejí jen posledních 10 s historie |

Při úpravách: nepřidávat do `onUpdate` ani do `onTick` smyčky přes celé úložiště, nevolat `Storage.getValue` ve smyčce bez stropu a nevytvářet velká pole při každém snímku.

## 15. Známá omezení

- Nic z toho nebylo podle `docs/test-ui-2026-10-15.md` ověřeno v simulátoru Garmin (chybí oficiální definice fenix 7X Pro v cloudu); na hodinkách jen částečně.
- Když v jedné notifikaci přijde víc paketů `0x17`, započítá se jen poslední (`decode` přepisuje `out[:cps]`).
- `System.getTimer()` přeteče asi po 24,8 dne běhu; graf pak na jedno okno ukáže prázdno.
- Při ukončení aplikace s úplně plným úložištěm se může ztratit nejvýš ~100 posledních bodů.
- Ping a fronta BLE předpokládají jediný rozpracovaný požadavek; zápis bez potvrzení se po 3 s považuje za ztracený.
- Při výpadku spojení graf spojí čarou poslední bod před výpadkem s prvním po něm.
- GPS běží jen při otevřené aplikaci; zavření aplikace nahrávání ukončí (trasa se uzavře).
- Kontrolní součet paketů a jednotka dávky jsou odvozené z neúplného API Raysidu a odposlechu (viz `docs/PROTOKOL-RAYSID.md`).

## 16. Známé nesrovnalosti v kódu a dokumentaci

Stav k buildu 82; před opravou ověřit v kódu.

- **Mrtvý kód `:chartLen`:** `openChoice` a `ChoiceMenuDelegate` umějí vybrat délku grafu, ale žádná položka menu `:chartLen` nevytváří; délka se mění jen UP na grafu.
- **Nepoužívané překladové klíče:** `:mWatchSig`, `:avgOf`, `:aboveBg`, `:recPaused`; konstanta `Tr.LANG_CODES` se nepoužívá.
- **Klíč `rOn`** se zapisuje, ale nikde nečte (nahrávání se po startu obnovuje jen přes `rAuto`).
- **Odhad šumu σ** v `evaluateSoft` předpokládá, že Raysid počítá cps z okna asi 2 s (neověřeno), i když data posílá asi každých 0,25 s.
- **Komentář v hlavičce `RaysidState`** „Sdílený stav měření…“ stojí nad funkcí `clamp`, ne nad třídou.
- **Manifest** uvádí jazyky jen `ces` a `eng`, aplikace přitom umí i polštinu (vlastní `Tr`).
- **`OVL_CPS_ON = false`** je dočasné testovací vypnutí stropu cps; rozhodnout, zda vrátit.
