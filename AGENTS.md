# AGENTS.md – jak na projektu pracovat

Návod pro každého, kdo projekt přebírá: AI agenta (Claude, Codex a jiné) i člověka. Přečti ho celý dřív, než začneš měnit kód. Pak podle úkolu otevři odpovídající dokument v `docs/`.

## O co jde

`Raysid Garmin` je Connect IQ **watch-app** v jazyce **Monkey C** pro Garmin fēnix 7X Pro. Přes Bluetooth LE čte dozimetr Raysid a umí:
- zobrazit hodnoty, graf a přetížení (OVL);
- alarmy a cvakání, vibrace a svítilnu podle cps;
- měnit nastavení přímo v Raysidu;
- nahrávat GPS body s dávkou a odesílat je přes telefon na web Žhavá místa.

Uživatelé jsou čeští a polští hledači radioaktivních míst. Aplikace se šíří mimo Connect IQ Store jako `.prg` pro konkrétní model hodinek.

## Mapa repozitáře

```
source/                Monkey C zdrojaky (vse, co bezi v hodinkach)
  RaysidApp.mc         vstup aplikace, RaysidState (sdileny stav + nastaveni), put(), clamp()
  BleManager.mc        skenovani, pripojeni, fronta zapisu, prijem dat, ping
  RaysidProtocol.mc    UUID, ramce prikazu, parser paketu (RaysidParser)
  Alarms.mc            pevne meze a prudky narust
  Clicker.mc           cvakani, vibrace, svitilna, davky alarmu (casovac 100 ms)
  RaysidView.mc        obrazovky: hlavni, graf, mapovani, ladici
  RaysidDelegate.mc    tlacitka, cele menu, formatovani hodnot, konstanty OVL
  Recorder.mc          GPS body, bloky v Application.Storage, slucovani
  Uploader.mc          odesilani bloku na web, overeni API klice
  KeyEntry.mc          zadani API klice v hodinkach
  ValuePicker.mc       zadani vlastni hodnoty po cislicich
  HelpView.mc          posuvny text napovedy
  Tr.mc                VSECHNY texty UI ve 3 jazycich (CZ, EN, PL)
  BuildInfo.mc         generuje build.sh (verze, cislo a datum buildu)
resources/             ikona, retezce manifestu, nastaveni pro Garmin Connect
docs/                  dokumentace (viz README.md)
tools/gen-navod.py     generuje docs/NAVOD.md a docs/GUIDE-EN.md z Tr.mc
build.sh               build k vydani (zvysi cislo buildu)
manifest.xml           id aplikace, podporovane modely, opravneni, jazyky
```

## Nepřekročitelná pravidla

1. **Žádná tajemství v repozitáři.** Vývojářský klíč (`*.der`, `*.pem`), API klíče Žhavých míst ani logy z hodinek (obsahují polohu) se necommitují; `.gitignore` je hlídá. API klíč se nikdy nevypisuje do logu ani na displej, v menu je vidět jen konec klíče.
2. **Překlad bez chyb.** Každá změna musí projít `monkeyc ... -l 3 -w` (nejpřísnější typová kontrola, viz [docs/SESTAVENI.md](docs/SESTAVENI.md)). Bez toho práce není hotová.
3. **Watchdog.** Connect IQ ukončí aplikaci, když jedna obsluha (onUpdate, časovač, BLE callback) běží příliš dlouho. Smyčky musí být lineární a omezené: graf prochází jen viditelné okno, parser má strop `JUNK_MAX`, slučování bodů dělá `CMP_STEP` bloků na volání a mazání `gcStep` 10 bloků. Nic kvadratického, žádná rekurze přes data.
4. **Tlačítka:**
   - Podržení tlačítek se nepoužívá: dlouhé DOWN otevře systémové alarmy a dlouhé UP nastavení hodinek. LIGHT patří hodinkám.
   - Dotyk a swipe se ignorují.
   - START otevírá menu, DOWN přepíná obrazovky, UP dělá akci aktuální obrazovky a BACK ukončí aplikaci.
5. **Zápis do úložiště jen přes `put(key, value)`** (RaysidApp.mc). Ten při plném úložišti nespadne a vrátí `false`. Nový klíč v `Application.Storage` zapiš do tabulky v [docs/ARCHITEKTURA.md](docs/ARCHITEKTURA.md). Načítání musí zvládnout chybějící hodnotu i hodnotu jiného typu: použij `load()` nebo `instanceof` a omez ji na platný rozsah.
6. **Texty jen v `Tr.mc`, vždy ve všech třech jazycích** (`:klic => ["cz", "en", "pl"]`):
   - V kódu se volá `Tr.t(:klic)`.
   - Popisky v menu drž krátké, asi do 20 znaků; kulatý displej je úzký.
   - Používej jen znaky, které písma hodinek určitě mají: latinka s diakritikou, `×` a `µ` ano, šipky `→` a výpustka `…` ne (piš `>` a `...`).
   - Po změně nápovědy spusť `python3 tools/gen-navod.py`.
7. **Bezpečnost měření:**
   - Alarmy, cvakání i body mapování počítají s **okamžitými** hodnotami, nikdy s průměrem pro displej.
   - Za přetížení (OVL) se body neukládají a zapnutý alarm dávky nebo cps se ozve vždy.
   - Meze alarmů zůstávají pod přetížením Raysidu (`ALARM_CPS_MAX`, `ALARM_DOSE_MAX`).
8. **Nikdy nemazat neodeslaná data** kvůli dočasné chybě. Uploader zahazuje jen dávky, které server odmítl kvůli obsahu (400/409/413/422). Ostatní chyby se zkoušejí znovu.

## Konvence

- **Komentáře v kódu** jsou česky **bez diakritiky**, stručně, a vysvětlují proč. **Texty pro uživatele** jsou s diakritikou.
- **Názvy:** třídy `PascalCase`, funkce a proměnné `camelCase`, soukromé pole `_jmeno`, konstanty `VELKA_PISMENA`.
- **Barvy** (MIP displej, 64 barev):
  - dávka oranžová `0xFFAA00`, cps modrá `0x00AAFF`;
  - oblouk a text u UP žlutá `0xFFFF00`;
  - alarm červená;
  - zastaralé hodnoty tmavě šedé.
  Jiné barvy než z palety MIP se na displeji rozpadnou do rastru.
- **Formát hodnot:** dávka `0.12 / 1.23 / 12.3 / 123 uSv/h`, nad 999,5 v mSv/h; cps `30.6`, nad 1000 `1.23 / 12.3 kcps` (`doseNum`, `cpsNum` v RaysidDelegate.mc).
- **Terminologie v UI:** „cvakání“ (ne pípání ani klikání), „dělička“, „Žhavá místa“, „mapování“.
- **Verze:** `APP_VERSION` se nastavuje v `build.sh` a mění se jen na pokyn správce projektu. `BUILD_NUM` počítá buildy poslané na test a zvyšuje ho jen `build.sh`. Pro pouhou kontrolu překladu volej `monkeyc` přímo.

## Postup při změně

1. Přečti dotčené moduly celé a v `docs/` příslušnou kapitolu. Kód je hustě provázaný přes `RaysidState`.
2. Udělej změnu co nejmenší a ve stylu okolního kódu.
3. Projdi dopady:
   - menu (popisky a jejich obnovení po návratu, `refreshItem`);
   - uložení a načtení nastavení;
   - všechny tři jazyky a nápovědu;
   - obrazovky ve všech stavech: bez spojení, bez dat, OVL, alarm, ladicí obrazovka, mapování vypnuté, zapnuté, pozastavené nebo plné.
4. Přelož s `-l 3`.
5. Aktualizuj dokumentaci (`docs/*.md`, nápovědu přes `tools/gen-navod.py`) a `CHANGELOG.md`.
6. Build na test: `bash build.sh`. Výsledek je v `build/Raysid.prg`.

## Testování

- **Simulátor** potřebuje oficiální definici zařízení (Garmin SDK Manager, přihlášení). Se zjednodušenou definicí jde jen přeložit.
- **Logika bez hodinek:** složitější logiku (parser, slučování bodů, fronta odesílání) ověřuj malým modelem v Pythonu, podobně jako v revizích v `docs/`.
- **Na hodinkách:**
  - Zapni Displej → Ladicí obrazovka. Měření a události se pak zapisují přes `System.println` do `GARMIN/APPS/LOGS/<jméno .prg>.TXT`. Soubor musí na hodinkách předem existovat; hodinky můžou aplikaci vést pod jménem jako „Raysid (1)“.
  - Pády jsou v `GARMIN/APPS/LOGS/CIQ_LOG.YML`.
- **Kontrolní seznam po změně:**
  - připojení a odpojení Raysidu;
  - hodnoty a graf;
  - alarm (zvuk, vibrace, svítilna, umlčení);
  - OVL;
  - menu Raysid při spojení i bez něj;
  - mapování: start, pauza, obnovení, ukončení aplikace;
  - odesílání s telefonem i bez něj.

## Omezení hodinek a Raysidu, která už stála čas

- **Raysid:**
  - Bez pingu každé 4 s se po 10 s odpojí.
  - Bluetooth spojení má jen s jedním zařízením (zavřít aplikaci v telefonu).
  - Data posílá asi každých 240 ms, starší dokumentace uvádí 2 s.
  - Po restartu může změnit oddělovač paketů (0x84 → 0x10).
  - Nastavení se čte stejnou sekvencí, jakou používá oficiální aplikace (ping s obrazovkou 9 před 0x1b 01); bez ní neodpoví.
  - Viz [docs/PROTOKOL-RAYSID.md](docs/PROTOKOL-RAYSID.md).
- **Hodinky:**
  - Connect IQ dovolí jen jeden rozpracovaný BLE požadavek, proto má BleManager frontu.
  - Vibrační motor rozliší nejvýš asi 4 pulzy za sekundu.
  - Časovač cvakání má 100 ms, takže víc než 10 signálů za sekundu nejde.
  - Spouštěcí ikona pro fenix7xpro má 40×40 px.
  - RSSI je k dispozici jen při hledání.
  - Aplikace nahraná přes USB (sideload) nedostane nastavení z Garmin Connect, proto se API klíč zadává v hodinkách.
- **Odesílání:**
  - Jde jen přes telefon (`Communications.makeWebRequest`): jen HTTPS a JSON, bez multipart.
  - Web proto má vlastní endpoint, viz [docs/zhavamista/navrh-endpointu.md](docs/zhavamista/navrh-endpointu.md).

## Vydávání (GitHub Releases)

- **Kdy:** release s hotovými `.prg` se dělá **jen na pokyn správce projektu**.
- **Jeden `.prg` na model hodinek.** V názvu souboru je verze, build a id zařízení z Connect IQ, třeba `Raysid-1.1-b82-fenix7xpro.prg`. V popisu releasu je u každého souboru celý název modelu.
- **Další modely:** když se na žádost uživatele udělá build pro další model (záznam v `manifest.xml` a ověření rozložení), přidá se do releasu a od té doby se přikládá ke **každému dalšímu** releasu.
- **Seznam podporovaných modelů** a stav jejich ověření je v README v části Podporované hodinky.

## Komunikace se správcem

Správce projektu je Vít Cenek a píše česky. Testuje na fēnixu 7X Pro Sapphire Solar s Raysidem a posílá logy z hodinek. Uživatelské texty a dokumentaci piš česky. Změny chování, které uživatel uvidí, popiš v `CHANGELOG.md` srozumitelně, bez interních názvů.

## Licence

GPL-3.0-or-later. Každý nový zdrojový soubor začíná stejnou hlavičkou jako ostatní (SPDX identifikátor a odkaz na `AUTHORS.md`). Nové přispěvatele připiš do `AUTHORS.md`.
