# Mapování GPS a odesílání na Žhavá místa

Technická dokumentace modulů `source/Recorder.mc` (záznam bodů do úložiště hodinek) a `source/Uploader.mc` (odesílání na web), plus `source/KeyEntry.mc` (API klíč). Popisuje stav kódu ve verzi 1.1, build 82; odkazuje na funkce, ne na čísla řádků. Celkovou architekturu popisuje [ARCHITEKTURA.md](ARCHITEKTURA.md).

## Obsah

1. [Záznam bodů](#1-záznam-bodů)
2. [Formát v úložišti](#2-formát-v-úložišti)
3. [Fronta bloků a postupné mazání](#3-fronta-bloků-a-postupné-mazání)
4. [Plné úložiště a slučování](#4-plné-úložiště-a-slučování)
5. [Uploader](#5-uploader)
6. [API klíč v hodinkách](#6-api-klíč-v-hodinkách)
7. [Kontrakt webového endpointu](#7-kontrakt-webového-endpointu)
8. [Životní cyklus a okrajové případy](#8-životní-cyklus-a-okrajové-případy)

---

## 1. Záznam bodů

### 1.1 Zapnutí a stavy

`Recorder` má tyto příznaky:

| Pole | Význam |
|---|---|
| `enabled` | modul mapování povolen (menu Žhavá místa → Mapování zapnuto, klíč `rEn`, výchozí true). Vypnutý skryje stránku Mapování a podmenu. |
| `autostart` | nahrávat automaticky po spuštění aplikace (`rAuto`) |
| `on` | nahrávání běží, GPS je zapnutá |
| `paused` | pozastaveno, trasa zůstává otevřená |
| `full` | úložiště plné, nahrávání nejde spustit (`rFull`) |
| `gpsOk` / `gpsWeak` | poloha s dostatečnou / nedostatečnou kvalitou |
| `noData` | GPS je, ale z Raysidu nejsou platná data (body se neukládají) |

Ovládání: tlačítko **UP na stránce Mapování** (`RaysidDelegate.onPreviousPage`) volá `recorder().pause()`, když `on`, jinak `recorder().start()`. Po spuštění aplikace `Recorder.resume()` uzavře trasu, kterou minule nic neukončilo (pád aplikace), a při `autostart` zavolá `start()`. Samotné `initialize` nastaví vždy `on = false`.

```
           start()                 pause()
  stop ───────────────► on ───────────────────► paused
   ▲                    │ ▲                       │
   │  stop()/suspend()  │ └──────── start() ──────┘   (stejná trasa, statistika pokračuje)
   └────────────────────┘
   storageFull() z kteréhokoli stavu → full (on = paused = false, GPS vypnutá)
```

- **`start()`**: nic nedělá při `full` nebo `!enabled`. Z pauzy jen pokračuje: připočte délku pauzy do `_pausedSec`, vynuluje poslední polohu (první bod po pauze se uloží hned a úsek ujetý během pauzy se nepočítá). Jinak nejdřív uzavře případnou otevřenou trasu (`closeChunk(true)`; když to nejde, `storageFull()` a konec), vynuluje statistiku (`session`, `meters`, `maxDose`, `maxCps`), nastaví `_start = Time.now()`, `_part = 1` a zapne GPS.
- **`pause()`**: vypne GPS, uloží rozpracované body (`flush`) a statistiku. Trasa zůstane otevřená.
- **`stop()`**: vypne GPS a uzavře trasu `closeChunk(true)`, takže poslední blok odejde na web s `final = true`.
- **`suspend()`** (z `RaysidApp.onStop`): jako `stop()`, ale s `_noKick = true`, aby se při ukončení aplikace neposílal požadavek, na který už nemůže přijít odpověď. Blok odejde při dalším spuštění.
- **`setEnabled(false)`** běžící nebo pozastavené nahrávání zastaví (`stop()`).

GPS (`gpsOn`): `LOCATION_CONTINUOUS`, zkouší konfigurace `GPS_GLONASS_GALILEO_BEIDOU_L1_L5`, pak `…_L1`, pak `GPS_GALILEO`, jinak výchozí.

### 1.2 Filtr kvality a rozestup (`Recorder.onPosition`)

1. Hodinky dávají jen stupeň kvality (`info.accuracy`), ne přesnost v metrech. Fix je, když `accuracy >= QUALITY_POOR` a `position != null`. `gpsOk = fix && accuracy >= minQ`; `minQ` je volba Kvalita GPS: 4 dobrá (výchozí), 3 použitelná, 2 slabá (klíč `rQual`).
2. Bez `gpsOk` nebo když `!on` se nic neuloží.
3. **Čerstvá data z Raysidu:** `state.lastUpdate` mladší než `FRESH_MS` = 5 s, známá dávka i cps a **žádné OVL** (`state.ovl`). Jinak `noData = true`, bod se neuloží a `_lastPtMs` se posune na „teď“, takže průměr k dalšímu bodu začne až po konci výpadku nebo přetížení.
4. **Rozestup:** vzdálenost od posledního uloženého bodu `Recorder.distance()` (rovinná aproximace, 111 132 m na stupeň šířky, 111 320 × cos(šířky) na stupeň délky). Bod vznikne, když `d >= dist` (volba Vzdálenost bodů, 5/8/10/12/15 m nebo vlastní 2–200 m, klíč `rDist`). První bod po startu nebo pauze se uloží hned.
5. `meters += d`, poloha se zapamatuje a volá se `addPoint`.

Na displeji (`RaysidView.drawRecord`, `drawMapping`): červeně „REC N“ jen když `on && gpsOk && !noData`; oranžově „čekám na GPS“, „slabé GPS“, „čekám na Raysid“ nebo „OVL“; „pozastaveno“, „plno“.

### 1.3 Hodnota bodu (`Recorder.pointValues`)

- Dávka a cps bodu = **průměr všech měření od předchozího bodu, nejvýš za posledních `PT_AVG_MS` = 10 s** (`RaysidState.avgSince(from)`; vždy aspoň poslední měření).
- Po startu, pauze, výpadku dat nebo OVL je začátek okna posunutý (viz `_lastPtMs`), takže se nemíchají hodnoty z doby, kdy se body neukládaly.
- Nezávisí na nastavení průměrování displeje.
- Čas bodu je `Time.now()` hodinek v okamžiku uložení (unix, UTC), ne čas GPS fixu.

### 1.4 Trasy

- `newRoute()` při prvním bodu trasy:
  - `client_route_id = "garmin-" + prvních 6 znaků System.getDeviceSettings().uniqueIdentifier (jinak "watch") + "-" + _start + "-" + _part`
  - název `"Raysid Garmin D. M. RRRR HH:MM"`, u dalších částí s ` (N)`.
- Trasa má nejvýš **`ROUTE_MAX` = 5000 bodů** (`_routePts`). Bod číslo 5000 uzavře blok s `final = true`, `_part++` a další bod založí novou trasu se stejným `_start`.
- Statistika obrazovky Mapování (`session`, `meters`, `maxDose`, `maxCps`, `activeSec()`) platí od zapnutí nahrávání, přes pauzy pokračuje.

## 2. Formát v úložišti

Vše v `Application.Storage`, zápisy přes globální `put()` (vrací `false` místo pádu při plném úložišti).

### 2.1 Bloky bodů `r<i>`

- Pole celých čísel, **5 čísel na bod** (`FIELDS`), nejvýš **50 bodů na blok** (`CHUNK`):

| Index v bodu | Hodnota | Jednotka |
|---|---|---|
| 0 | zeměpisná šířka × 10⁶ | celé číslo |
| 1 | zeměpisná délka × 10⁶ | celé číslo |
| 2 | unix čas | s (UTC) |
| 3 | dávkový příkon | nSv/h (µSv/h × 1000, zaokrouhleno) |
| 4 | cps × 10 | zaokrouhleno |

- `r<rChunks>` je **rozpracovaný** blok (v paměti `_buf`, na disk ho zapisuje `flush()` každých `FLUSH_EVERY` = 10 bodů a při pauze/ukončení).
- Bloky `r<rHead>` … `r<rChunks − 1>` jsou **uzavřené** a čekají na odeslání.

### 2.2 Popis bloku `rm<i>`

Ke každému uzavřenému bloku (zapisuje `closeChunk`):

| Index | Význam |
|---|---|
| `meta[0]` | `client_route_id` (String) |
| `meta[1]` | číslo dávky v trase od 0 (`batch`) |
| `meta[2]` | `final`: poslední dávka trasy (Boolean); může být i prázdný blok, aby se server dozvěděl konec |
| `meta[3]` | název trasy |
| `meta[4]` | **úroveň sloučení**: kolikrát už byl blok sloučen (přidává `compactStep`; starší bloky prvek nemají = 0) |

Blok ze starší verze bez `rm<i>` dostane v `headChunk()` náhradní popis `["garmin-old-<i>", 0, true, "Raysid Garmin"]`.

### 2.3 Ostatní klíče Recorderu

| Klíč | Typ | Význam |
|---|---|---|
| `rEn` | Boolean | mapování povoleno |
| `rAuto` | Boolean | nahrávat po spuštění |
| `rDist` | Number | rozestup bodů v m (ořez 2–200) |
| `rQual` | Number | nejnižší kvalita GPS (`Position.QUALITY_*`, ořez POOR–GOOD) |
| `rCmp` | Number | `cmpMax`: 0, 1, 2, 3 nebo 99 (bez omezení); výchozí 2 |
| `rHead` | Number | index nejstaršího neodeslaného bloku |
| `rChunks` | Number | index rozpracovaného bloku (= počet bloků, které kdy vznikly) |
| `rCount` | Number | neodeslaných bodů celkem (včetně rozpracovaného bloku); po sloučení nejde odvodit z počtu bloků |
| `rFull` | Boolean | úložiště plné (drží i přes restart) |
| `rGc` | Array `[from, to]` | rozsah bloků čekajících na postupné smazání |
| `rRoute` | String | `client_route_id` otevřené trasy (chybí = další bod založí novou) |
| `rRName` | String | název otevřené trasy |
| `rBatch` | Number | číslo další dávky v otevřené trase |
| `rRPts` | Number | bodů v otevřené trase (kvůli `ROUTE_MAX`) |
| `rPart` | Number | pořadí části trasy (`_part`) |
| `rStart` | Number | unix čas zapnutí nahrávání (součást id trasy) |
| `rSess`, `rMeters`, `rMaxD`, `rMaxC` | Number / Float | statistika od zapnutí nahrávání |
| `rOn` | Boolean | zapisuje se, ale nikde se nečte |

Pořadí zápisů v `closeChunk` je záměrné: nejdřív `r<i>` a `rm<i>`, pak `rBatch`, `rRPts`, `rCount` a **`rChunks` až nakonec**. Při pádu mezi zápisy tak nevznikne blok se starým číslem dávky (server by ho zahodil jako duplicitu). Při startu `Recorder.initialize` přepočítá `count` z bloků (jen při ≤ 100 čekajících blocích, kvůli watchdogu).

Kapacita: `MAX_POINTS` = 4000 neodeslaných bodů (měkký strop, viz kap. 4); skutečné úložiště aplikace může dojít i dřív, to řeší návratová hodnota `put()`.

## 3. Fronta bloků a postupné mazání

```
 rHead                               rChunks
   │                                    │
   ▼                                    ▼
 [r5][r6][r7][r8] ... [r11]          [r12 rozpracovaný]
  ▲ odesílá Uploader                  ▲ plní addPoint / flush
  └ dropHead() po potvrzení
```

- `pending()` = `rChunks − rHead` (uzavřené bloky).
- `headChunk()` vrátí `[body, meta]` nejstaršího bloku; poškozený blok (chybí body) přeskočí přes `dropHead()`.
- `dropHead()` smaže `r<head>` a `rm<head>`, posune `rHead`, sníží `rCount` a při `count < MAX_POINTS` zruší `full`.

**Smazat neodeslané** (`Recorder.clear`, menu Úložiště → potvrzení):
1. `uploader().cancel()`: odpověď na právě odesílaný blok už nic nesmaže (`_sentId = ""`).
2. Běžící nebo pozastavené nahrávání se ukončí (`stop()` s `_noKick`, nic se neodešle). Další trasa tak dostane nové id a na webu se nesrazí s už odeslanými dávkami.
3. Číslování pokračuje: `_chunks++`, `_head = _chunks`; zapíše se `rHead`, `rChunks` a **pak** `rGc = [from, to]` (`from` = začátek dřívějšího nedokončeného `rGc`, jinak starý `_head`; `to` = starý `_chunks`). Při pádu mezi zápisy zůstanou nanejvýš staré bloky, nic nového se nesmaže.
4. Vynuluje `count`, `session`, `full`, `paused`, otevřenou trasu a běžící slučování.

Samotné mazání dělá `Recorder.gcStep()` z časovače BLE (každé 4 s), **nejvýš 10 bloků** (`r<i>` i `rm<i>`) za volání. Smazat stovky bloků najednou by mohlo shodit watchdog.

## 4. Plné úložiště a slučování

### 4.1 Kdy je „plno“

| Spouštěč | Kde | Reakce |
|---|---|---|
| `count >= MAX_POINTS` (4000) po přidání bodu | `addPoint` | `startCompact()` |
| `put("r<i>")` v `flush()` selže | `flush` | `startCompact()` |
| `put` bloku nebo popisu v `closeChunk()` selže | `closeChunk` | smaže `r<i>` (blok bez popisu nejde odeslat), body zůstanou v `_buf`; když neběží slučování a `_buf` má aspoň 100 bodů (2 bloky), `storageFull()`, jinak `startCompact()` |
| `cmpMax == 0` (Zastavit nahrávání) | `startCompact` | `stop()` a `storageFull()` |
| slučování nic neuvolnilo nebo nestačilo | konec `compactStep` | `stop()` a `storageFull()` |

`storageFull()`: jednou dlouhá vibrace 1,5 s (jen při přechodu do plna), `full = true` (`rFull`), `on = paused = false`, GPS vypnout. Už uložené body zůstanou a odejdou na web. Trasu neuzavírá; uzavře ji příští `start()`, a pokud to nejde, zůstane plno.

`full` se zruší: `dropHead()` po odeslání (při `count < MAX_POINTS`), zvýšení `cmpMax` v menu (`setCmpMax`), úspěšné sloučení, `clear()`, nebo při startu, když `count < MAX_POINTS` a nic nečeká.

### 4.2 Volby „Když se zaplní“ (`cmpMax`, `CMP_OPTS`)

| Volba | `cmpMax` | Chování | Největší rozestup při 5 m |
|---|---|---|---|
| Zastavit nahrávání | 0 | nahrávání skončí | 5 m |
| Sloučit nejvýš 1× | 1 | každý blok nejvýš jednou | 10 m |
| Sloučit nejvýš 2× (výchozí) | 2 | nejvýš dvakrát | 20 m |
| Sloučit nejvýš 3× | 3 | nejvýš třikrát | 40 m |
| Slučovat bez omezení | 99 (`CMP_ANY`) | dokud bloky mají aspoň 2 body | – |

Popisek s rozestupem počítá `cmpSubLabel()` jako `dist << n`. Podle `docs/kontrola-2026-10-14.md` (simulace) se bez odeslání vejde asi 4 000 / 8 000 / 15 000 / 27 000 bodů.

### 4.3 Algoritmus (`startCompact`, `compactStep`)

- `startCompact()` nastaví `_cmpNext = rHead + 1` (**nejstarší blok se přeskakuje**, protože se může právě odesílat) a `_cmpGain = 0`.
- `compactStep()` zpracuje nejvýš `CMP_STEP` = 4 bloky na volání. Volá se po každém přidaném bodu (`addPoint`) a z časovače BLE přes `compactTick()`, když nahrávání neběží, takže rozběhnuté slučování doběhne.
- Blok se přeskočí, když má méně než 2 body, chybí mu `rm<i>`, nebo `meta[4] >= cmpMax` (kromě 99).
- **Z každé dvojice sousedních bodů zůstane ten s vyšší dávkou** (index 3) i s jeho skutečnou polohou, časem a cps; lichý poslední bod zůstane. Hotspoty se tak nerozmažou, jen se zvětší rozestup.
- Nově se zapíše `rm<i>` s `meta[4] + 1` a pak `r<i>`; `count` se sníží o uvolněné body.
- Rozpracovaný blok `_buf` se neslučuje (smyčka končí před `rChunks`).
- **Konec průchodu** (`_cmpNext >= rChunks`): uloží `rCount`; když `_cmpGain == 0` (nebylo co slučovat) nebo `count` je stále ≥ `MAX_POINTS`, `stop()` + `storageFull()`. Jinak, pokud bylo plno, `full = false`.
- Číslo dávky (`meta[1]`) se slučováním nemění; server jen dostane menší dávku.

## 5. Uploader

Hodinky nemají vlastní internet: `Communications.makeWebRequest` jde přes aplikaci Garmin Connect v telefonu (telefon spárovaný a v dosahu). Posílá se **jeden blok najednou, nejstarší první**; po potvrzení se blok z hodinek smaže.

### 5.1 Kdy běží

- `Uploader.start()` (z `RaysidApp.onStart` a při zapnutí mapování v menu) spustí časovač `TICK_MS` = 30 s, jen když `active()` = mapování povolené nebo `recorder().pending() > 0`. Při startu s vyplněným klíčem a `verify == :vfIdle` spustí ověření.
- `kick()` se volá z časovače, z `Recorder.closeChunk` (nový blok), po každé úspěšné nebo zahozené odpovědi (hned další blok), z `retry()` (výběr Odesílání na web v menu), ze `settingsChanged()` a po úspěšném ověření.
- Po vypnutí mapování se časovač zastaví jen když nic nečeká; neodeslané body se posílají dál.

### 5.2 `kick()` krok za krokem

1. Rozpracovaný požadavek mladší než `BUSY_MAX_MS` = 120 s → nic. Starší → považuje se za ztracený, `_lost++` (pozdní odpověď se pak ignoruje) a pokračuje se.
2. `!active()` → konec bez změny stavu.
3. Vlastnost `zmUpload` false → stav `:upOff` („vypnuto“).
4. Chybí klíč (`currentKey()`) → `:upNoKey`.
5. Dřívější 401/403 (`_authFailed`) → `:upAuth`, neposílá se, dokud klíč nezmění `settingsChanged()`, `retry()` nebo úspěšné ověření.
6. Žádný uzavřený blok → `:upWait` („průběžně“, když se nahrává nebo je pauza), jinak `:upDone` („vše odesláno“).
7. Telefon nepřipojen (`System.getDeviceSettings().phoneConnected`) → `:upNoPhone`.
8. Sestaví tělo a hlavičky, `_busy = true`, `_sentId = meta[0] + "#" + meta[1]`, stav `:upSending` a `makeWebRequest(url(), body, options, method(:onResponse))`. Výjimka při odeslání → `_busy = false`, `:upErr`.

### 5.3 Požadavek

```
POST https://www.zhavamista.cz/api/1.0/all/route-points      (Uploader.DEFAULT_URL; přepíše vlastnost zmUrl)
Content-Type: application/json                                (Communications.REQUEST_CONTENT_TYPE_JSON)
Authorization: Bearer <API klíč>
X-API-Key: <API klíč>
```

Tělo (`Dictionary` převedený Connect IQ na JSON):

| Pole | Zdroj | Poznámka |
|---|---|---|
| `client_route_id` | `meta[0]` | např. `garmin-3a9f1c-1791916357-1` |
| `batch` | `meta[1]` | pořadí dávky v trase od 0 |
| `final` | `meta[2]` | poslední dávka trasy |
| `name` | `meta[3]` | `Raysid Garmin 13. 10. 2026 18:40` |
| `device` | konstanta | `"RAYSID"` |
| `points` | blok `r<i>` | pole `[lat, lon, unix čas, µSv/h, cps]`; převod `lat/1e6` (Double), `dávka/1000`, `cps/10` |

### 5.4 Zpracování odpovědi (`onResponse`)

| Situace | Rozhodnutí | Důsledek |
|---|---|---|
| `_lost > 0` | pozdní odpověď na požadavek, který vypršel | `_lost--`, nic dalšího (blok se mezitím poslal znovu; server dávku podle `client_route_id` + `batch` nezdvojí) |
| 2xx a tělo bez `state`/`status`, nebo `"ok"` | úspěch | `sent += počet bodů`, `dropHead()`, hned `kick()`; případné `verify == :vfBad` se změní na `:vfOk` |
| 2xx, ale `state`/`status` není `"ok"` | chyba | `:upErr`, zkusí se při dalším tiku |
| **400, 409, 413, 422** | server trvale odmítl obsah dávky | blok se **zahodí** (`dropHead()`) a pokračuje se dalším, aby jedna vadná dávka nezablokovala frontu |
| **401, 403** | špatný klíč | `_authFailed = true`, `:upAuth` („špatný API klíč“), dál se neposílá |
| ostatní (404, 405, 408, 429, 5xx, záporné kódy Connect IQ) | výpadek, špatná adresa, později | `:upErr` + kód, data zůstanou, zkusí se znovu za 30 s |

Ochrana proti smazání špatného bloku: `dropHead()` se zavolá jen když `chunkId(headChunk().meta)` je stále rovno `_sentId`. Po `clear()` (`cancel()` vynuluje `_sentId`) nebo po jiné změně fronty tak odpověď nic nesmaže.

### 5.5 Ověření klíče (`startVerify`, `onVerify`)

- Adresa: v `url()` se `route-points` nahradí `user-info`; když vlastní adresa `route-points` neobsahuje, použije se `https://www.zhavamista.cz/api/1.0/all/user-info`.
- `GET` s hlavičkou `Authorization: Bearer <klíč>` (bez `X-API-Key`), odpověď JSON.
- 200 a `state == "ok"` → `:vfOk`, jméno z `user.nickname` (`verifyName`), zruší `_authFailed` a zavolá `kick()`. 200 s jiným `state` → `:vfBad`.
- 401/403 → `:vfBad` („web klíč nepřijal“); záporný kód → `:vfNoPhone`; jinak `:vfErr` + kód. Bez klíče `:vfNoKey`, bez telefonu `:vfNoPhone`.
- Běžící ověření se neopakuje (starší odpověď by přepsala novější); nová položka menu se jen zapamatuje, aby se jí obnovil popisek.
- Spouští se při startu aplikace, po uložení klíče v hodinkách, po změně nastavení v Garmin Connect a ručně položkou Ověřit spojení.

### 5.6 Sekvence

```
Recorder                    Uploader                       Garmin Connect (telefon)        Žhavá místa
   │ closeChunk(final?)        │                                  │                              │
   │── kick() ────────────────►│                                  │                              │
   │                           │ headChunk() → [body, meta]       │                              │
   │◄──────────────────────────│                                  │                              │
   │                           │ makeWebRequest(POST JSON) ──────►│── HTTPS POST route-points ──►│
   │                           │   _busy, _sentId = id#batch      │                              │ uloží dávku
   │                           │                                  │◄─ 200 {"state":"ok",…} ──────│ (duplicitu id+batch ignoruje)
   │                           │◄──────── onResponse(200, data) ──│                              │
   │ dropHead() ◄──────────────│ (jen když head == _sentId)       │                              │
   │                           │ kick() → další blok …            │                              │
   │                           │                                  │                              │
   │        bez odpovědi 120 s: další kick() → _lost++ a stejný blok znovu;                     │
   │        pozdní odpověď na první pokus se zahodí (_lost--)                                   │
```

### 5.7 Stavy pro uživatele

`Uploader.label()` = text stavu (`:upOff`, `:upNoKey`, `:upNoPhone`, `:upSending`, `:upWait`, `:upDone`, `:upAuth`, `:upErr` + kód) a při neodeslaných bodech „, čeká N“ (`recorder().count`). Obrazovka Mapování ukazuje řádek „Web: …“ červeně při chybě nebo nepřijatém klíči, zeleně po úspěšném ověření.

## 6. API klíč v hodinkách

- Kde: menu **Žhavá místa → Web a odesílání → API klíč** (`KeyEntryView` + `KeyEntryDelegate`). U aplikace ze Store jde klíč nastavit i v Garmin Connect (vlastnost `zmKey`, typ password); u aplikace nahrané přes USB nastavení v Garmin Connect nefunguje.
- Klíč Žhavých míst je 48 hexadecimálních znaků (`KEY_LEN`), nabídka znaků je jen `0123456789abcdef` (`KEY_CHARS`) a na konci `OK`.
- Ovládání: UP/DOWN vybírá znak, START ho přidá (po 48. znaku skočí kurzor na OK), START na OK uloží, BACK smaže poslední znak a u prázdného zadání obrazovku zavře. Dotyk a swipe se ignorují, nic se nedrží. Když je klíč už zadaný, kurzor začíná na OK (START = zavřít beze změny).
- Zobrazení: zadaný text po čtveřicích, 16 znaků na řádek, vidět jsou poslední 3 řádky; v menu jen konec klíče `...abcd` (`keyLabel()`).
- Uložení (`KeyEntryDelegate.save`): `Application.Properties.setValue("zmKey", …)` a **záloha** `Storage` `zmKeyBak` (kdyby se nastavení při aktualizaci aplikace ztratilo), pak `uploader().settingsChanged()` a `startVerify()`. Délka se neověřuje, uložit jde i kratší klíč.
- Čtení: `currentKey()` vrací `zmKey`, a když je prázdný, `zmKeyBak`.
- Bezpečnost: klíč je v úložišti hodinek uložený jako prostý text (Properties i záloha). Do dokumentace, logů ani commitů ho nepatří.

## 7. Kontrakt webového endpointu

Endpoint vznikl na žádost projektu; návrh pro správce API je v [zhavamista/navrh-endpointu.md](zhavamista/navrh-endpointu.md). Web ho provozuje od 14. 10. 2026. Oficiální dokumentace API Žhavých míst: <https://mapa.zhavamista.cz/api-docs.html> .

Shrnutí návrhu:

- **Proč nový endpoint:** trasy šly dřív založit jen nahráním souboru (multipart), který `makeWebRequest` neumí (jen JSON nebo urlencoded). Endpoint pro stanice nepřijímá polohu. Hodinky mají málo paměti, proto posílají po dávkách.
- **Požadavek:** `POST /api/1.0/all/route-points`, `Content-Type: application/json`, přihlášení `Authorization: Bearer <token>` nebo `X-API-Key` (aplikace posílá obojí).
- **Tělo:** `client_route_id`, `batch`, `final`, `name`, `device`, `points` (viz kap. 5.3).
  - První požadavek s novým `client_route_id` založí trasu, další do ní přidávají.
  - Server má dávku poznat podle dvojice `client_route_id` + `batch` a podruhé ji neuložit, ale odpovědět normálně `ok` (hodinky po vypršení posílají znovu).
  - `final: true` u poslední dávky; server může trasu dokončit. Trasa má nejvýš 5000 bodů, pak hodinky začnou novou s dalším `client_route_id`.
  - Bod `[lat, lng, čas (unix s, UTC), µSv/h, cps]`, typicky 50 bodů v dávce. `name` a `device` stačí z první dávky.
- **Odpověď:** `{"state": "ok", "route_id": …, "points": …}`; chyba HTTP 4xx s `{"state": "error", "message": "…"}`. Na 401 hodinky ukážou špatný klíč a neposílají; na 5xx zkusí později.
- **Přihlášení:** ideálně dlouhodobý klíč uživatele (Bearer token z `/login` platí jen 30 dní).

Rozdíly mezi návrhem a kódem, o kterých je dobré vědět:
- Návrh uvádí název `Garmin 13. 10. 2026 18:40`, kód posílá `Raysid Garmin …`.
- Kód kromě 401 zastavuje odesílání i na 403 a dávky zahazuje na 400/409/413/422 (návrh to nespecifikuje). Jiné 4xx (404, 405, 408, 429) se opakují.
- Úspěch kód pozná i podle pole `status`, nebo když JSON stav vůbec nemá.
- Ověření používá `GET …/user-info` (není součástí návrhu) a čte `state` a `user.nickname`.

## 8. Životní cyklus a okrajové případy

| Situace | Co se stane |
|---|---|
| Pád aplikace během nahrávání | Při dalším startu `resume()` uzavře otevřenou trasu (`rRoute`) blokem s `final = true`; `count` se přepočítá. |
| Ukončení aplikace (BACK) | `suspend()` trasu uzavře bez odesílání; blok odejde při dalším spuštění. |
| Pauza | GPS vypnutá, trasa otevřená; další UP naváže na stejnou trasu. |
| Raysid odpojen / OVL během nahrávání | GPS běží, body se neukládají (`noData`), na displeji „čekám na Raysid“ / „OVL“. |
| Plné úložiště | Viz kap. 4; nahrávání skončí s „plno“ a dlouhou vibrací. |
| Telefon mimo dosah | `:upNoPhone`, pokus každých 30 s. |
| Web neodpovídá | po 120 s nový pokus se stejnou dávkou, pozdní odpověď se ignoruje. |
| Smazání během odesílání | odpověď nic nesmaže (`cancel()`), mazání bloků postupně přes `gcStep`. |
| Vypnutí mapování | nahrávání se zastaví a trasa uzavře; neodeslané bloky se dál posílají. |
| Trasa přes 5000 bodů | uzavře se s `final = true`, další bod založí část `(2)` se stejným `rStart`. |
