# Protokol Raysid přes Bluetooth LE

Tento dokument popisuje komunikaci mezi hodinkami a dozimetrem Raysid tak, jak ji implementuje aplikace Raysid Garmin, a doplňuje, co jsme sami zjistili odposlechem. Je určený vývojáři nebo AI agentovi, který na projekt navazuje bez dalšího kontextu.

Kód, který protokol implementuje:

| Soubor | Co obsahuje |
|---|---|
| `source/RaysidProtocol.mc`, modul `RaysidProtocol` | UUID, rozpoznání Raysidu ve výsledcích skenování, rámec příkazu, CRC, ping, příkazy nastavení, kontrolní součet paketu, `unpackValue` |
| `source/RaysidProtocol.mc`, třída `RaysidParser` | skládání paketů z notifikací, hledání oddělovače, dekódování (`feed`, `decode`) |
| `source/BleManager.mc`, třída `BleManager` | skenování, párování, zapnutí notifikací, fronta zápisů, ping, čtení nastavení, předání dekódovaných hodnot do `RaysidState` |

Značení: bajty se píšou šestnáctkově (`0x12` nebo jen `12`). `p[i]` je i-tý bajt přijatého paketu včetně bajtu délky, tedy `p[0]` je délka a `p[1]` typ.

## 1. Zdroje

**Oficiální dokumentace:** https://raysid.com/api. Obsahuje `API.md` (popis protokolu), `connect.py` (připojení) a `cps-doserate.py` (čtení cps a dávkového příkonu). Kód se na ni odkazuje v hlavičce `RaysidProtocol.mc`. Kopie těchto souborů v repozitáři **není**. Kdo chce něco ověřit proti originálu, musí si stránku otevřít sám.

**Odposlech oficiální aplikace:** příkazy pro nastavení Raysidu (dělička, cvakání, alarmy) a rozložení paketu nastavení `0x0a` v `API.md` nejsou. Zjistili jsme je 14. 10. 2026 z btsnoop logu oficiální aplikace pro Android (postup je v kapitole 10).

**Ladicí log z hodinek:** typy paketů `0x18`, `0x22`, `0x21` a další, oddělovač mezi pakety a skutečná četnost dat pocházejí z logů, které aplikace zapisuje při zapnuté ladicí obrazovce (viz `docs/SESTAVENI.md`, kapitola o logech).

Kde se `API.md` a reálný přístroj liší, platí v kódu reálný přístroj. U každého takového místa je to níže uvedeno.

## 2. GATT: služba a charakteristiky

| Role | UUID | Funkce v kódu |
|---|---|---|
| Služba | `49535343-fe7d-4ae5-8fa9-9fafd205e455` | `RaysidProtocol.serviceUuid()` |
| RX (Raysid → hodinky), notify | `49535343-1e4d-4bd9-ba61-23c647249616` | `RaysidProtocol.notifyCharUuid()` |
| TX (hodinky → Raysid), write | `49535343-8841-43f4-a8d4-ecbe34729bb3` | `RaysidProtocol.writeCharUuid()` |

Jde o UUID transparentní UART služby Microchip (ISSC), Raysid ji zřejmě používá jako sériovou linku.

Connect IQ vyžaduje profil zaregistrovat předem. `RaysidProtocol.profile()` registruje službu s oběma charakteristikami, u RX i s deskriptorem CCCD. Registraci volá `BleManager.register()`. Když selže, `BleManager.restart()` ji zkusí znovu.

### Rozpoznání Raysidu ve výsledcích skenování

`RaysidProtocol.matches(r)` vrátí `true`, když:

1. jméno zařízení obsahuje `raysid` bez ohledu na velikost písmen (konstanta `NAME_PREFIX`; hledá se kdekoli ve jméně, ne jen na začátku), **nebo**
2. reklama obsahuje UUID služby výše.

Další výběr mezi více Raysidy dělá `BleManager.onScanResults()` a `BleManager.choose()`: nalezené kusy se sbírají `CHOOSE_MS` = 3 s, pak se vybere podle preference (`pref` 0 = vybraný nebo nejnověji použitý z historie, 1 = nejsilnější RSSI). Vybraný kus (`pin`) se připojí okamžitě, se zámkem (`lock`) se ostatní ignorují. Zařízení bez jména dostane jméno `Raysid`.

### Po připojení

`BleManager.onConnectedStateChanged()` → `BleManager.subscribe()`:

1. zápis `01 00` do CCCD na RX charakteristice (zapnutí notifikací),
2. sekvence `RaysidProtocol.initCommands()`, což je totéž co `settingsCommands()` (kapitola 5).

Connect IQ dovolí jen jeden rozpracovaný BLE požadavek, proto všechny zápisy jdou přes frontu (`BleManager.enqueue()`, `pump()`, potvrzení v `onDescriptorWrite()` a `onCharacteristicWrite()`). Když potvrzení nepřijde do 3 s, `onTick()` frontu odblokuje.

Zápisy jdou typem `WRITE_TYPE_WITH_RESPONSE` (`RaysidProtocol.WRITE_TYPE`). Oficiální Python skript posílá ping bez odpovědi; s odpovědí to na reálném Raysidu funguje.

Po aktualizaci aplikace může Raysid zůstat spojený s hodinkami z předchozí instance a pak nevysílá reklamu. `BleManager.adoptPaired()` proto po registraci profilu nejdřív projde `getPairedDevices()`, aktivní spojení převezme a neaktivní zruší (`unpairDevice`).

## 3. Rámec příkazu (hodinky → Raysid)

`RaysidProtocol.command(payload)` balí každý příkaz takto:

```
[0xFF] [CRC2] [0xEE] [CRC1: 4 B, big-endian] [payload ...] [TotalSize]
```

| Pole | Délka | Význam |
|---|---|---|
| `0xFF` | 1 | začátek rámce |
| `CRC2` | 1 | XOR všech bajtů od `0xEE` po konec payloadu (tedy `0xEE`, 4 bajty CRC1 a payload) |
| `0xEE` | 1 | pevná značka |
| `CRC1` | 4 | součet payloadu po 4bajtových blocích, zapsaný big-endian |
| payload | N | první bajt je kód příkazu, za ním parametry |
| `TotalSize` | 1 | délka celého rámce včetně tohoto bajtu, tedy N + 8 |

**CRC1** (`RaysidProtocol.crc1`): payload se rozdělí na 4bajtové bloky, každý se čte jako **little-endian** 32bitové číslo (neúplný poslední blok se doplní nulami nahoře), bloky se sečtou modulo 2³². Výsledek se do rámce zapíše **big-endian** (nejvyšší bajt první).

**CRC2**: prostý XOR bajtů `0xEE`, CRC1 (4 B) a payloadu.

Příklady spočítané podle kódu:

| Příkaz | Payload | Rámec |
|---|---|---|
| dělička 1:10 | `16 0A` | `FF EE EE 00 00 0A 16 16 0A 0A` |
| `1b 01` (vyžádání nastavení) | `1B 01` | `FF EE EE 00 00 01 1B 1B 01 0A` |

U dvoubajtového payloadu je CRC1 = `payload[1] << 8 | payload[0]`, proto se v rámci objeví stejné dva bajty v opačném pořadí.

## 4. Ping

```
payload = [0x12] [tab] [unix čas: 4 B big-endian]
```

Funkce `RaysidProtocol.ping(tab)`. `tab` říká Raysidu, kterou obrazovku má aplikace otevřenou: `0` = hlavní obrazovka s telemetrií (`ACTIVE_TAB`), `9` = obrazovka nastavení (`SETTINGS_TAB`). Čas je `Time.now().value()`, tedy sekundy od 1. 1. 1970 UTC.

**Raysid se odpojí, když 10 s nedostane ping.** Aplikace ho proto posílá každé 4 s (`POLL_MS` = 4000, časovač v `BleManager.start()`, odeslání v `BleManager.onTick()`). Ping se zařazuje na **začátek** fronty, aby se nezdržel za jinými příkazy. Výjimka: když je ve frontě rozpracované čtení nastavení (položky označené `:seq`), ping se vynechá, protože sekvence čtení sama končí pingem s `tab` 0 a vložený ping by ji rozdělil (Raysid by pak neodpověděl).

Celý rámec pingu má 14 bajtů.

## 5. Čtení nastavení Raysidu

Sekvence je převzatá z odposlechu oficiální aplikace, funkce `RaysidProtocol.settingsCommands()`:

| # | Payload | Význam |
|---|---|---|
| 1 | `12 09 <čas>` | ping s `tab` 9 (aplikace „otevřela“ nastavení) |
| 2 | `1F 00` | význam neznámý, oficiální aplikace ho posílá |
| 3 | `1B 01` | Raysid odpoví paketem `0x0a` s nastavením |
| 4 | `1B 02` | význam neznámý, oficiální aplikace ho posílá |
| 5 | `12 00 <čas>` | ping s `tab` 0, zpět na hlavní obrazovku |

Kdy se sekvence posílá (`BleManager`):

- hned po připojení (`subscribe()` → `initCommands()`),
- po každém příkazu nastavení (`send()` volá `requestSettings()`), aby hodinky věděly, co Raysid opravdu přijal,
- po paketu `0x18` (někdo stiskl tlačítko na Raysidu a mohl změnit nastavení).

Počitadlo `_setReq` zajišťuje, že se do menu propíše jen odpověď na **poslední** čtení. Odpověď na starší čtení by jinak na chvíli vrátila právě přepnutý přepínač. Nevyřízená čtení starší než 3 s se považují za ztracená.

### Paket `0x0a` (nastavení)

Dekóduje `RaysidParser.decode()`, jen když má paket aspoň 14 bajtů:

| Bajt | Význam | Klíč ve výsledku |
|---|---|---|
| `p[4]` | dělička zvuku 1:N, hodnota N přímo | `:devDiv` |
| `p[6]` | zvuk (cvakání) v Raysidu, 0 = vypnuto | `:devSound` |
| `p[10]` bit `0x10` | alarm dávkového příkonu zapnutý | `:devDoseAl` |
| `p[10]` bit `0x01` | alarm cps zapnutý | `:devCpsAl` |

Ostatní bajty neznáme (meze alarmů, jas, režim a podobně tam nejspíš jsou, ale nikdo je neověřil).

## 6. Příkazy nastavení (odposlechnuto 14. 10. 2026)

Žádný z těchto příkazů není v `API.md`. Zjistili jsme je z btsnoop logu oficiální aplikace pro Android.

| Payload | Funkce v `RaysidProtocol` | Význam |
|---|---|---|
| `16 N` | `dividerCommand(n)` | dělička zvuku 1:N. Oficiální aplikace nabízí 1, 5, 10, 20, 50, 100, 250. Hodnota 1 se v logu neobjevila, ostatní ano. |
| `03 01` / `03 00` | `soundCommand(on)` | zvuková signalizace (cvakání) v Raysidu zapnout / vypnout |
| `18 01` / `18 00` | `doseAlarmCommand(on)` | alarm dávkového příkonu zapnout / vypnout |
| `17 01` / `17 00` | `cpsAlarmCommand(on)` | alarm cps zapnout / vypnout |

Pozor: kódy příkazů `0x17` a `0x18` se shodují s typy **příchozích** paketů `0x17` a `0x18`, ale nemají s nimi nic společného. Směr hodinky → Raysid a Raysid → hodinky jsou oddělené.

Příkazy posílá `BleManager.send()`; vrací `false`, když Raysid není připojený. Sloučení děličky (`BleManager.syncDivider()`): když je zapnuté `state.divLink` a dělička v Raysidu se liší od děličky hodinek, pošle se Raysidu dělička hodinek (jen hodnoty do 255, jeden pokus na každý rozdíl, aby se při odmítnutí nezacyklil).

## 7. Příchozí pakety (Raysid → hodinky)

### Formát paketu

```
[Size] [Type] [Payload ...] [Checksum: 3 B]
```

- `Size` je délka celého paketu včetně bajtu `Size` a kontrolního součtu. Minimum, které parser přijme, je 4.
- Jeden paket může přijít rozdělený do více notifikací a jedna notifikace může obsahovat více paketů. Parser proto data skládá do bufferu (kapitola 8).

### Kontrolní součet

`RaysidProtocol.checksumOk()`: XOR 3bajtových bloků všech bajtů před součtem (od `Size` po konec payloadu; neúplný poslední blok se doplní nulami). `API.md` a `cps-doserate.py` se liší v pořadí bajtů, proto kód přijme **obě** varianty. Po bajtech to znamená:

- varianta `le` v kódu: bajt součtu k (k = 0, 1, 2) = XOR bajtů na pozicích ≡ k (mod 3),
- varianta `be` v kódu: bajt součtu k = XOR bajtů na pozicích ≡ 2 − k (mod 3).

Reálný Raysid (log z 14. 10. 2026) posílá variantu `be`. Součet s hodnotou 0 se odmítá, aby nuly nebyly „platné pakety“.

Příklad skutečného paketu `0x17` (12 bajtů): `0C 17 00 77 20 01 6E 1A 00 01 2D 15`. Součet `01 2D 15`: `01` = `00^01^00` (pozice 2, 5, 8), `2D` = `17^20^1A` (pozice 1, 4, 7), `15` = `0C^77^6E` (pozice 0, 3, 6).

### Přehled typů

Seznam známých typů je v konstantě `KNOWN_TYPES` v `RaysidProtocol.mc`. Parser ho používá při hledání oddělovače (kapitola 8).

| Typ | Co obsahuje | Co s ním aplikace dělá |
|---|---|---|
| `0x17` | cps a dávkový příkon, příznak přetížení | dekóduje `:cps`, `:doseRate`, `:ovl` |
| `0x02` | teplota a baterie Raysidu | dekóduje `:temp`, `:battery` (do stavu se ukládá jen baterie) |
| `0x0a` | nastavení Raysidu | dekóduje `:devDiv`, `:devSound`, `:devDoseAl`, `:devCpsAl` |
| `0x18` | událost tlačítka na Raysidu | nastaví `:btn`, `BleManager` pak znovu načte nastavení |
| `0x22` | událost alarmu nebo LED | jen ladicí log |
| `0x21` | spektrum, asi 182 bajtů | nic (v logu se vynechává) |
| `0x03`, `0x06`, `0x23` | neznámé | nic, jen počítadlo typů na ladicí obrazovce a ladicí log (`0x23` vždy, `0x03` při změně, `0x06` nikdy) |

### `0x17`: cps a dávkový příkon

Za typem následují 3bajtové bloky `[RangeType] [LSB] [MSB]`, za nimi jeden bajt příznaku a pak součet:

```
[Size] [0x17] {[RangeType] [LSB] [MSB]} ... [OVL] [Checksum: 3 B]
```

- `RangeType` 0 = cps, 1 = dávkový příkon.
- 16bitová hodnota `LSB | MSB << 8` je komprimovaná. `RaysidProtocol.unpackValue(v)`: výsledek je `v % 6000` vynásobený deseti tolikrát, kolik je `v / 6000` (celočíselně). Pak se dělí 600.
- Dávkový příkon vychází v **µR/h**. Aplikace ho dělí `UR_PER_USV` = 100 a pracuje v µSv/h (1 µSv/h ≈ 100 µR/h). Ověřeno proti displeji Raysidu 13. 10. 2026.
- Bajt těsně před součtem je **příznak přetížení** (`01`, když Raysid bliká červenou LED; odposlechnuto 14. 10. 2026). Kód ho čte jen tehdy, když délka odpovídá „bloky + 1 bajt“, tedy `(Size − 5) % 3 == 1`, a vrací ho jako `:ovl`. `BleManager` ho uloží do `state.devOvl` a `RaysidState.updateOvl()` (`RaysidApp.mc`) ho pak použije přímo jako přetížení cps. Vlastní odhad přetížení z průběhu cps a dávky běží jen tehdy, když příznak nepřišel (starší firmware nebo jiný Raysid).

Výpočet pro příklad výše: blok `00 77 20` → v = 0x2077 = 8311 → 8311 / 6000 = 1, 2311 × 10 = 23 110 → / 600 = **38,5 cps**. Blok `01 6E 1A` → v = 6766 → 766 × 10 / 600 = 12,8 µR/h → **0,128 µSv/h**. Příznak `00`.

V logu se objevil i delší paket `0x17` (42 bajtů) s bloky `RangeType` 0 až 9. Kód bloky s typem 2 a vyšším ignoruje a jejich význam neznáme (viz otevřené otázky).

Pokud v jedné notifikaci přijde víc paketů `0x17`, `feed()` vrátí jen hodnoty posledního (klíče se přepisují). Při četnosti asi 240 ms to vědomě nevadí.

### `0x02`: teplota a baterie

| Bajty | Výpočet | Klíč |
|---|---|---|
| `p[2]`, `p[3]` (LE) | hodnota / 10 − 100 = teplota v °C | `:temp` |
| `p[4]`, `p[5]` (LE) | baterie v % | `:battery` |

Dekóduje se jen paket s délkou aspoň 9. `API.md` uvádí u baterie dělení deseti, skutečný Raysid ale posílá přímo procenta (ověřeno na přístroji). Typický paket `0x02` má 27 bajtů, význam zbytku neznáme.

### `0x18`: tlačítko na Raysidu

Payload `[funkce] [nový stav]`. Funkce `02` = cvakání, `03` = alarmy (odposlechnuto 14. 10. 2026). Kód obsah nečte, jen nastaví `:btn` a `BleManager.onCharacteristicChanged()` zavolá `requestSettings()`, aby se změna propsala do menu Raysid.

### `0x22`: událost alarmu nebo LED

Z logu jsme vyčetli tento sled payloadů:

| Payload | Kdy |
|---|---|
| `01 05` | začátek alarmu |
| `04 00` | opakovaně každé asi 2 s, dokud alarm trvá |
| `02 xx` | konec alarmu (`xx` neznámé) |
| `03 00` | asi 15 s po konci |

Aplikace paket nedekóduje. Alarmy si vyhodnocuje sama z hodnot `0x17` (třída `Alarms`), přetížení z příznaku v `0x17`. Paket se jen vždy zapisuje do ladicího logu.

### `0x21`: spektrum

Asi 182 bajtů (`Size` = `0xB6`), přichází v několika notifikacích. Aplikace ho nepoužívá a do logu ho nezapisuje. Formát neznáme. Pro parser je důležitý jen tím, že je dlouhý a rozdělený, takže na něm se nejčastěji ukáže chyba skládání.

## 8. Oddělovač mezi pakety a resynchronizace

Reálný Raysid posílá mezi pakety jeden bajt navíc, který `API.md` nepopisuje. Viděli jsme hodnotu `0x84` a po restartu Raysidu (bez odpojení hodinek) `0x10`. Proto ho parser nemá napevno, ale **učí se ho**.

Jak funguje `RaysidParser.feed(value)`:

1. Notifikace se přidá do `_buf`. Když buffer přeroste 1024 B, nechá se posledních 512 B a parser se označí jako rozsynchronizovaný.
2. Na aktuální pozici:
   - Je-li tam známý oddělovač a jsme hned za paketem (nebo rozsynchronizovaní), přeskočí se a pokračuje se jako na začátku paketu.
   - Je-li oddělovač známý a parser je rozsynchronizovaný, přeskakuje se bez počítání součtů až k dalšímu oddělovači.
   - Je-li na pozici bajt délky a sedí kontrolní součet, paket se dekóduje.
   - Jinak se zkusí, jestli aktuální bajt není oddělovač: hned za ním musí začínat paket známého typu (`KNOWN_TYPES`) s platným součtem. Pak se bajt započítá jako kandidát (`learnDelimiter`). Hodnota, která se takhle ukáže **třikrát**, se stane oddělovačem `_delim`.
   - Chybí-li zbytek paketu a jsme synchronizovaní, čeká se na další notifikaci.
   - Jinak je bajt smetí a přeskočí se.
3. Ochrana proti watchdogu: v jedné notifikaci se zkouší součet nejvýš na `JUNK_MAX` = 120 bajtech smetí, pak se zbytek bufferu zahodí.
4. Když `RELEARN_AFTER` = 10 notifikací po sobě nepřinese žádný platný paket, oddělovač se zapomene a učí se znovu (restart Raysidu změní `0x84` na `0x10`).
5. `RaysidParser.reset()` (volá se při každém novém připojení) zapomene buffer i oddělovač.

Parser byl otestovaný simulací (oddělovač `0x84` i `0x10`, rozdělené pakety, smetí, 5000 notifikací s náhodnými chybami), viz `docs/test-ui-2026-10-15.md`.

## 9. Časování

| Co | Hodnota | Kde v kódu |
|---|---|---|
| ping | každé 4 s | `RaysidProtocol.POLL_MS`, `BleManager.onTick()` |
| odpojení bez pingu | 10 s (chování Raysidu) | |
| data `0x17` na reálném přístroji | asi každých **240 ms** | měřeno, ladicí obrazovka ukazuje průměrný interval |
| timeout párování | 15 s | `BleManager.CONNECT_TIMEOUT_MS` |
| nové připojení bez spojení nebo bez dat | 30 s | `BleManager.RECOVER_MS` |
| hodnoty zešednou | 5 s bez nového měření | `RaysidView` |
| sběr kandidátů při skenování | 3 s | `BleManager.CHOOSE_MS` |

Starší dokumentace a komentáře uvádějí, že Raysid posílá data asi každé 2 s. Na reálném přístroji je to asi 240 ms. Proto se alarmy a průměrování počítají podle času, ne podle počtu měření (`Alarms.mc`). Komentáře v `Clicker.mc` („cps každé ~2 s“) a v `Alarms.mc` u výpočtu `sigma` („cps změřeného za ~2 s“) jsou z doby před tímto zjištěním.

## 10. Jak odposlechnout oficiální aplikaci (btsnoop)

Takhle byly zjištěny příkazy v kapitole 6 a rozložení paketu `0x0a`. Postup se hodí, když bude potřeba dekódovat další nastavení.

**Princip:** oficiální aplikace si po připojení vyžádá balík s nastavením (`0x0a`) a Raysid ho pošle. Při každém novém připojení přijde znovu. Když se mezi připojeními změní vždy **jen jedna věc**, z porovnání balíků je vidět, který bajt se změnil. Příkaz, kterým aplikace změnu poslala, je v logu hned před tím.

**Příprava (Android):**

1. V možnostech pro vývojáře zapnout **Bluetooth HCI snoop log** (Enabled).
2. Na hodinkách zavřít aplikaci Raysid, aby se k dozimetru nepřipojila místo telefonu (BLE spojení má Raysid jen s jedním zařízením).
3. Jednou vypnout a zapnout Bluetooth na telefonu (začne čistý log). Pak už Bluetooth **nevypínat**: každé vypnutí začne nový soubor, starý se přejmenuje na `btsnoop_hci.log.last` a ještě starší se ztratí. Jeden log pojme klidně dvacet připojení.
4. Ke každému kroku si zapsat čas z telefonu (hodina a minuta) a co se změnilo.

**Jeden krok = jedna změna a nové připojení:**

1. V oficiální aplikaci změnit jednu položku, počkat 5 s.
2. Odpojit se (tlačítkem v aplikaci, případně vypnout Raysid), počkat 10 s.
3. Připojit se znovu, počkat 15 s, než začnou chodit hodnoty.
4. Zapsat čas a změnu.

Nejdřív jedno připojení bez změny jako výchozí stav (se screenshotem obrazovky SETS).

**Pořadí použité 14. 10. 2026:**

| # | Změna |
|---|---|
| 0 | nic, výchozí stav |
| 1–7 | dělička 1:1, 1:5, 1:10, 1:20, 1:50, 1:100, 1:250 (sedm hodnot jednoznačně určí bajt) |
| 8, 9 | Sound Clicks vypnout, zapnout |
| 10, 11 | Dose rate alarm vypnout, zapnout |
| 12, 13 | CPS alarm vypnout, zapnout |

„Enable Clicks“ v oficiální aplikaci je cvakání v telefonu, ne v Raysidu, proto se neměnilo.

**Získání logu:**

```
adb bugreport raysid.zip
unzip -j raysid.zip 'FS/data/misc/bluetooth/logs/btsnoop_hci.log*'
```

Log obsahuje i provoz ostatních Bluetooth zařízení v telefonu. Surové logi do repozitáře nepatří (mohou obsahovat osobní údaje a adresy zařízení), v repozitáři žádné nejsou. Log se dá otevřít ve Wiresharku (filtr `btatt`) a hledat zápisy na TX charakteristiku a notifikace z RX.

## 11. Otevřené otázky

1. **Význam `1F 00` a `1B 02`** v sekvenci čtení nastavení. Posíláme je, protože je posílá oficiální aplikace.
2. **Zbytek paketu `0x0a`**: kde jsou meze alarmů a další nastavení.
3. **Bloky `RangeType` 2 až 9** v delším paketu `0x17` (možná cps za různá časová okna nebo jiné rozsahy).
4. **Typy `0x03`, `0x06`, `0x23`**: obsah neznámý. `0x06` chodí periodicky, `0x23` se loguje vždy, protože jde nejspíš o událost.
5. **Druhý bajt `0x22 02 xx`** a co přesně znamená `0x22 03 00`.
6. **Formát spektra `0x21`.**
7. **Původ oddělovače `0x84` / `0x10`** a proč se po restartu Raysidu mění. Parser se ho učí, takže na odpovědi funkčnost nezávisí.
8. **Kontrolní součet:** reálný přístroj posílá variantu `be`. Jestli jiný firmware neposílá `le`, nevíme, proto zůstávají obě.
9. **Přetížení bez příznaku:** když Raysid příznak OVL v `0x17` neposílá, aplikace přetížení odhaduje sama z průběhu hodnot (konstanty `OVL_*` v `RaysidDelegate.mc`, odhadnuté, `OVL_CPS_ON` je vypnuté na test). Přetížení dávky (nad `OVL_DOSE` = 999 µSv/h) se počítá vždy z hodnoty. Jestli Raysid pošle příznak i pro přetížení dávky, nevíme.
10. **Dělička 1:1** příkazem `16 01` nebyla v odposlechu vidět.
