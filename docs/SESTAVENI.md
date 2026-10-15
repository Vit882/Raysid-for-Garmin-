# Sestavení a instalace

Návod, jak aplikaci Raysid Garmin přeložit, podepsat, nahrát do hodinek a číst z nich logy. Je určený vývojáři nebo AI agentovi, který projekt přebírá bez dalšího kontextu. Popis protokolu je v `docs/PROTOKOL-RAYSID.md`, ovládání aplikace v `docs/NAVOD.md`.

## 1. Přehled

| Položka | Hodnota |
|---|---|
| Typ aplikace | Connect IQ `watch-app`, jazyk Monkey C |
| Cílové hodinky | fēnix 7X Pro, testováno na fēnix 7X Pro Sapphire Solar (id `fenix7xpro`), jediný produkt v `manifest.xml` |
| Minimální API | 3.2.0 (`minApiLevel` v `manifest.xml`) |
| Oprávnění | `BluetoothLowEnergy`, `Positioning`, `Communications` |
| Použité SDK | Connect IQ SDK 9.2.0 |
| Jungle | `monkey.jungle` (jen `project.manifest = manifest.xml`) |
| Výstup | `build/Raysid-<zařízení>.prg`, u fenix7xpro i kopie `build/Raysid.prg` |

Struktura repozitáře:

| Cesta | Obsah |
|---|---|
| `source/*.mc` | zdrojový kód |
| `source/BuildInfo.mc` | **generuje `build.sh`**, ručně neupravovat |
| `resources/drawables/` | spouštěcí ikona `launcher_icon.png` (40×40) |
| `resources/strings/strings.xml` | název aplikace a popisky nastavení v Garmin Connect |
| `resources/settings/` | nastavení aplikace v Garmin Connect (odesílání na Žhavá místa) |
| `build.sh` | sestavení s číslem buildu |
| `build/` | výstupy překladu a `build-number.txt` |

Texty uživatelského rozhraní (čeština, angličtina, polština) nejsou v `resources/strings`, ale v `source/Tr.mc`. Jazyk se přepíná v aplikaci, ne podle `<iq:languages>` v manifestu.

## 2. Co je potřeba

### Java

Překladač `monkeyc` je Java aplikace. Potřebuješ JDK nebo JRE v `PATH` (`java -version`). V cloudovém prostředí projektu je OpenJDK 21 a s ním překlad funguje.

### Connect IQ SDK

Projekt se překládá s **Connect IQ SDK 9.2.0**.

- **Běžný postup:** nainstalovat **Connect IQ SDK Manager** z https://developer.garmin.com/connect-iq/sdk/, přihlásit se Garmin účtem, stáhnout SDK 9.2.0 (nebo novější) a v záložce **Devices** zařízení „fēnix 7X Pro / Solar / Sapphire Solar“ (`fenix7xpro`).
- **Cloudové prostředí projektu:** v `/mnt/project-files/.toolchain/` je připravený toolchain mimo repozitář (popis v jeho `README.txt`):
  - `sdk/` – SDK 9.2.0, jen `bin/`, `share/` a `resources/` (bez dokumentace a ukázek),
  - `Devices/fenix7xpro/compiler.json` – ručně psaná definice zařízení (viz níže; starší `Devices/fenix7x` je jen pro fēnix 7X bez Pro),
  - `developer_key.der` – vývojářský klíč tohoto prostředí (viz kapitola 3).

Sdílený adresář může být připojený jako `noexec`, proto se `monkeyc` spouští přes `bash`: `bash /mnt/project-files/.toolchain/sdk/bin/monkeyc ...`.

Volitelně VS Code s rozšířením **Monkey C** (Garmin). Příkaz `Monkey C: Verify Installation` zkontroluje SDK.

### Definice zařízení

SDK hledá definice zařízení v `~/.Garmin/ConnectIQ/Devices/<id>/`.

**Oficiální definice** stahuje SDK Manager a stažení **vyžaduje přihlášení Garmin účtem**. Obsahují všechno: `compiler.json`, `simulator.json`, fonty, rozložení tlačítek, obrázek hodinek pro simulátor.

**Náhradní definice v repozitářovém toolchainu** (`/mnt/project-files/.toolchain/Devices/fenix7xpro/compiler.json`) vznikla, protože oficiální definici se bez přihlášení stáhnout nepodařilo. Instalace:

```bash
mkdir -p ~/.Garmin/ConnectIQ/Devices
cp -r /mnt/project-files/.toolchain/Devices/fenix7xpro ~/.Garmin/ConnectIQ/Devices/
```

Co náhradní definice umí a co ne:

- **Číslo dílu** (`partNumber`) v náhradní definici není ověřené; na sideload nemá vliv.
- **Stačí na kontrolu překladu** včetně přísné typové kontroly (`-l 3`) a na vytvoření `.prg`.
- Obsahuje jen základní údaje: kulatý displej 280×280, 8 bitů na pixel, rodina `round-280x280`, ikona 40×40, limit paměti watch-app 786 432 B, Connect IQ 5.2.0, jazyky `ces`, `eng` a `pol`. Hodnoty jsou odhadnuté, ne převzaté od Garminu (`displayName` je „fenix 7X Pro (stub for compile check; part number not verified)“).
- **Simulátor s ní nespustíš** (chybí `simulator.json`, fonty a další soubory; v cloudu navíc chybí knihovny simulátoru).
- Není jisté, že `.prg` sestavené proti ní poběží na hodinkách stejně jako build proti oficiální definici. Zatím na hodinkách funguje, ale při jakémkoli podivném chování (pád při startu, špatné fonty, chyba paměti) nejdřív zkus sestavit proti oficiální definici.
- Do Connect IQ Store se s ní nahrávat nemá (balík `.iq` stav vždy proti oficiálním definicím).

## 3. Vývojářský klíč

Connect IQ každý build podepisuje soukromým klíčem RSA 4096 ve formátu DER.

**Každý vývojář si generuje vlastní klíč** (nebo použije `Monkey C: Generate a Developer Key` ve VS Code):

```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

Pravidla:

- **Klíč nikdy necommituj** a nevkládej do dokumentace, issue ani chatu. Patří mimo repozitář (např. vedle SDK). Soubor `.gitignore` v repozitáři je hlídá (`*.der`, `*.pem`, `developer_key*`, `build/`).
- **Klíč nevyměňuj u nainstalované aplikace.** Aktualizace nahraná přes USB se stejným id aplikace (`manifest.xml`, atribut `id`) a **stejným klíčem** zachová úložiště aplikace v hodinkách: nastavení, historii Raysidů, zaznamenané a neodeslané body. Build podepsaný jiným klíčem se chová jako jiná aplikace a o data přijdeš.
- V cloudovém prostředí projektu je klíč v `/mnt/project-files/.toolchain/developer_key.der`. Je jím podepsaný `build/Raysid.prg`, a protože tento build je nainstalovaný v testovacích hodinkách, další testovací buildy pro ně se musí podepisovat **tímto** klíčem.
- Id aplikace v `manifest.xml` neměň. Na něm závisí úložiště v hodinkách i identita v Connect IQ Store.

## 4. Sestavení přes `build.sh`

```bash
bash build.sh            # fenix7xpro
bash build.sh fenix7     # jiné zařízení (musí být v manifest.xml a mít definici)
```

Co skript dělá (v tomto pořadí):

1. Přejde do adresáře repozitáře. Toolchain bere z proměnné `TOOLCHAIN`, výchozí je `/mnt/project-files/.toolchain`. Očekává v něm `sdk/bin/monkeyc` a `developer_key.der`. Na vlastním počítači tedy nastav `TOOLCHAIN` na adresář, kde máš `sdk/` (nebo symlink na SDK) a svůj klíč.
2. Spočítá další pořadové číslo buildu z `build/build-number.txt` (chybí-li soubor, začne od 1; adresář `build/` si vytvoří sám).
3. Přepíše `source/BuildInfo.mc` konstantami `APP_VERSION`, `APP_YEAR`, `BUILD_DATE` (dnešní datum) a `BUILD_NUM`. Zobrazují se v aplikaci v Nápověda → O aplikaci (funkce `aboutText()` v `RaysidDelegate.mc`).
4. Přeloží `monkeyc -d <zařízení> -f monkey.jungle -o build/Raysid-<zařízení>.prg -y <klíč> -l 3 -w`.
5. Po úspěšném překladu uloží nové číslo do `build/build-number.txt` a u fenix7xpro zkopíruje výsledek do `build/Raysid.prg`.

**Verze aplikace** (`APP_VERSION`, teď `"1.1"`) a rok (`APP_YEAR`) jsou napevno v `build.sh`. Při novém vydání je měň tam, ne v `BuildInfo.mc`, protože ten se při dalším buildu přepíše.

Číslo buildu slouží k rozlišení testovacích buildů poslaných na hodinky. Zvyšuje se jen úspěšným `build.sh`; na pouhou kontrolu překladu volej `monkeyc` přímo (kapitola 5).

## 5. Jen kontrola překladu

Když chceš jen ověřit, že se kód přeloží (po úpravě, při review), volej `monkeyc` přímo s výstupem mimo repozitář. Číslo buildu se nezvýší a `BuildInfo.mc` se nezmění:

```bash
bash /mnt/project-files/.toolchain/sdk/bin/monkeyc \
  -d fenix7xpro -f /mnt/project-files/raysid-garmin/monkey.jungle \
  -o /tmp/raysid-check/check.prg \
  -y /mnt/project-files/.toolchain/developer_key.der \
  -l 3 -w
```

- `-l 3` je nejpřísnější typová kontrola (0 vypnuto, 1 postupná, 2 informativní, 3 striktní). Kód ji teď prochází bez chyb a bez varování a tak by to mělo zůstat.
- `-w` vypíše varování.
- Výsledkem má být `BUILD SUCCESSFUL`.
- `monkeyc` vytvoří vedle výstupu i pomocné adresáře (`gen/`, `internal-mir/`, `external-mir/`) a soubory `*.debug.xml` a `*-settings.json`. Proto výstup směruj do dočasného adresáře, ne do `source/`.
- `-y` je povinné i pro kontrolu. Klíč může být libovolný.

## 6. Nahrání do hodinek (sideload)

1. Připoj hodinky USB kabelem. **Pozor na kabely jen pro nabíjení**: hodinky se nabíjejí, ale počítač je nevidí. Když se nic neobjeví, zkus jiný kabel.
2. Hodinky používají **MTP**, ne USB disk:
   - Windows: objeví se jako přenosné zařízení.
   - macOS: OpenMTP nebo Android File Transfer.
   - Linux (KDE): Dolphin s `kio-extras` (protokol `mtp:/`).
   - Linux (příkazová řádka): balík `mtp-tools` (`mtp-detect`, `mtp-files`, `mtp-sendfile`, `mtp-getfile`), nebo připojení přes `jmtpfs` či `go-mtpfs`. Někdy pomůže hodinky odpojit a připojit znovu, když je zabere jiný program (např. GNOME gvfs).
3. Zkopíruj `build/Raysid.prg` do `GARMIN/APPS/` v hodinkách.
4. Hodinky odpoj. Aplikace „Raysid“ je v seznamu aplikací (START → Aplikace, případně na konci seznamu aktivit).
5. Před spuštěním zavři aplikaci Raysid v telefonu. Raysid udrží BLE spojení jen s jedním zařízením.

Při aktualizaci přepiš stávající soubor stejným jménem a podepiš build stejným klíčem (kapitola 3).

## 7. Logy z hodinek

Všechno je v `GARMIN/APPS/LOGS/` v hodinkách.

### Ladicí log aplikace

Aplikace zapisuje `System.println()` jen při zapnuté **ladicí obrazovce** (menu Displej → Ladicí obrazovka). Hodinky výstup uloží do `GARMIN/APPS/LOGS/<jméno souboru aplikace>.TXT`, ale **jen když tento soubor už existuje**. Hodinky ho samy nevytvoří, je potřeba ho založit prázdný přes MTP.

Jméno souboru odpovídá jménu, pod kterým hodinky aplikaci vedou. To nemusí být `Raysid`: hodinky mohou nahranou aplikaci zaregistrovat třeba jako `Raysid (1)` a log se pak jmenuje `Raysid (1).TXT`. Podívej se, jak se soubor jmenuje v `GARMIN/APPS/`, a když si nejsi jistý, založ oba (`Raysid.TXT` i `Raysid (1).TXT`). Když log naroste, hodinky ho mohou odsunout do `.BAK` vedle něj.

Formáty řádků (oddělovač `;`, první sloupec je `System.getTimer()` v ms):

| Řádek | Kdo ho píše | Význam |
|---|---|---|
| `čas;cps;dávka;XY` | `BleManager.onCharacteristicChanged()`, nejvýš každé 2 s | cps, dávka v µSv/h, `X` = OVL cps, `Y` = OVL dávky (0/1) |
| `čas;P;HEX` | `RaysidParser.logPacket()` | celý paket hexadecimálně: `0x22`, `0x18`, `0x23` vždy, `0x17` při změně příznaku přetížení, ostatní při změně obsahu; `0x21`, `0x02` a `0x06` se nelogují |

Logy mohou obsahovat jméno Raysidu a čas měření. Do repozitáře je nedávej.

### Pády

Pád aplikace se zapíše do `GARMIN/APPS/LOGS/CIQ_LOG.YML` (u některých firmwarů `CIQ_LOG.TXT`). Obsahuje typ chyby a zásobník volání s čísly řádků. K jejich dohledání se hodí soubor `build/Raysid-<zařízení>.prg.debug.xml` ze **stejného** buildu.

## 8. Podpora dalšího modelu hodinek

Aplikace je psaná a testovaná jen pro fēnix 7X Pro Sapphire Solar. Pro další model:

1. **Manifest:** přidej `<iq:product id="..."/>` do `<iq:products>` v `manifest.xml`. Id najdeš v SDK Manageru nebo v názvu adresáře v `~/.Garmin/ConnectIQ/Devices/`.
2. **Definice zařízení:** stáhni oficiální definici přes SDK Manager (Garmin účet). Ruční náhradu jako u fenix7xpro dělej jen pro kontrolu překladu.
3. **Překlad:** `bash build.sh <id>` vytvoří `build/Raysid-<id>.prg` (`build/Raysid.prg` se kopíruje jen pro fenix7xpro).
4. **BLE:** zařízení musí podporovat `Toybox.BluetoothLowEnergy` a Connect IQ aspoň 3.2.0.
5. **Značky tlačítek:** `RaysidView.drawMenuHint()` kreslí oblouky na okraji displeje u tlačítek fēnixu, úhly jsou napevno (stupně od 3 hodin proti směru hodinových ručiček): START 24–36°, UP 174–186°, DOWN 204–216°. Platí pro pětitlačítkové hodinky fēnix, epix, Forerunner 9xx a podobné. U hodinek s jiným rozložením tlačítek nebo jen s dotykem je potřeba úhly upravit (například podle `System.getDeviceSettings()` nebo přes resource podle zařízení), případně značky vypnout.
6. **Ovládání:** aplikace počítá s tlačítky START, UP, DOWN a BACK. Dotyk, swipe ani podržení nic nedělají. Dotykové hodinky bez tlačítek by potřebovaly upravit `RaysidDelegate`.
7. **Ikona:** velikost spouštěcí ikony se liší podle modelu (`launcherIcon` v `compiler.json` definice zařízení). Pro fenix7xpro je 40×40 px. Pro jiné modely přidej ikonu ve správné velikosti do adresáře resources s kvalifikátorem zařízení (např. `resources-fenix7/drawables/` se stejným `drawables.xml`). Adresáře `resources-<id>` SDK použije pro dané zařízení automaticky. Jinak kompilátor ikonu přeškáluje s horší kvalitou.
8. **Displej:** rozložení je počítané jako podíl šířky a výšky (`h * 0.22` a podobně) a předpokládá **kulatý** displej. Tvar displeje (`screenShape`) se nikde nekontroluje. Na obdélníkových displejích (Venu Sq, Edge) a jiných poměrech je potřeba rozložení zkontrolovat. Texty se zkracují tak, aby nepřetekly přes kulatý okraj.
9. **Barvy:** ikona i rozhraní jsou laděné pro MIP displej s omezenou paletou. Na AMOLED (epix, Venu) zvaž menší plochy svítivé barvy a chování stálého podsvícení.
10. **Paměť:** limit paměti watch-app se liší podle modelu. Graf drží v paměti až 600 měření a záznam trasy používá úložiště aplikace (asi 4000 bodů). Na slabších hodinkách to ověř v simulátoru (zobrazení paměti) s oficiální definicí zařízení.

## 9. Kontrolní seznam před vydáním

1. Zvyš `APP_VERSION` (případně `APP_YEAR`) v `build.sh`.
2. Spusť `bash build.sh` a ověř, že překlad s `-l 3 -w` prošel bez chyb a varování.
3. Zkontroluj, že `build.sh` vygeneroval `source/BuildInfo.mc` se správnou verzí, datem a číslem buildu, a že je v Nápověda → O aplikaci.
4. Zkontroluj konstanty, které se dají přepnout na test, např. `OVL_CPS_ON` v `RaysidDelegate.mc` (teď `false`, „vypnuto na test“).
5. Na skutečných hodinkách s Raysidem ověř:
   - hledání a připojení, včetně výběru při více Raysidech,
   - že se Raysid po více než 10 s neodpojí (ping),
   - hodnoty µSv/h a cps proti displeji Raysidu,
   - menu Raysid: načtení nastavení a změna děličky, cvakání a alarmů,
   - alarmy, signalizaci a OVL,
   - nahrávání bodů a odesílání na Žhavá místa,
   - aktualizaci přes existující instalaci (stejný klíč): nastavení a záznamy zůstanou.
6. Projdi logy a `CIQ_LOG.YML`, jestli aplikace nepadala.
7. **Bez tajemství:** v repozitáři není `developer_key.*`, API klíč Žhavých míst ani surové logy (btsnoop, logy z hodinek). Výchozí `zmKey` v `resources/settings/properties.xml` musí zůstat prázdný.
8. Aktualizuj `README.md` a dokumenty v `docs/`, pokud se změnilo chování nebo protokol.
9. Pro Connect IQ Store: sestav balík `.iq` (`monkeyc -e -r ...` nebo `Monkey C: Export Project` ve VS Code) proti **oficiálním** definicím všech produktů z manifestu, vlastním klíčem, který budeš používat i pro všechny další verze.
