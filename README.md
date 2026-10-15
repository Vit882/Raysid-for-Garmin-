# Raysid Garmin

Aplikace pro hodinky Garmin (Connect IQ), která se přes Bluetooth připojí k dozimetru **Raysid** a ukazuje dávkový příkon a count rate přímo na zápěstí. Umí alarmy, cvakání, graf a mapování radiace s GPS, včetně odesílání tras na web **[Žhavá místa](https://zhavamista.cz)**.

*English summary below.*

| | |
|---|---|
| Hodinky | Garmin fēnix 7X Pro (id `fenix7xpro`, vyvíjeno a testováno na fēnix 7X Pro Sapphire Solar); další podobné modely podle potřeby, viz [Podporované hodinky](#podporované-hodinky) |
| Dozimetr | [Raysid](https://raysid.com) (BLE) |
| Jazyky aplikace | čeština, angličtina, polština |
| Verze | 1.1 (číslo buildu je v aplikaci v Nápověda → O aplikaci) |
| Licence | [GPL-3.0-or-later](LICENSE) |

## Co aplikace umí

- **Měření:** dávkový příkon v µSv/h (oranžově) a cps (modře), baterie Raysidu i hodinek. Hodnoty můžou být okamžité, nebo průměr za nastavený čas či počet měření.
- **Graf** posledních 10, 20, 30 nebo 60 s s vlastní stupnicí pro každou veličinu a podbarvenými úseky alarmu.
- **Přetížení:** při přetížení Raysidu (OVL) se místo hodnoty ukáže blikající OVL. Raysid ho hlásí sám; aplikace má navíc záložní odhad.
- **Signalizace v hodinkách:** cvakání, vibrace a blikání svítilnou podle cps, s děličkou 1:N (1, 5, 10, 20, 50, 100, 250).
- **Alarmy hodinek:**
  - mez dávky, mez cps a prudký nárůst proti pozadí;
  - zvlášť se nastaví zvuk, vibrace, probliknutí displeje a červená svítilna a délka alarmu.
- **Nastavení přímo v Raysidu:** dělička, cvakání, alarm dávky a cps a sloučení děličky hodinek s Raysidem.
- **Mapování:**
  - GPS bod každých 5–15 m (nebo vlastní vzdálenost) s průměrem dávky a cps od předchozího bodu;
  - obrazovka Mapování se statistikou;
  - pauza a obnovení nahrávání;
  - hlídání plného úložiště se slučováním bodů.
- **Odesílání na Žhavá místa:** po blocích po 50 bodech přes telefon (Garmin Connect). API klíč se zadává přímo v hodinkách.
- **Připojení:** historie Raysidů, „jen vybraný Raysid“ a volba, který kus vybrat, když je jich v dosahu víc.
- **Nápověda v hodinkách** ve třech jazycích.

Podrobný popis ovládání je v [uživatelském návodu](docs/NAVOD.md) ([English](docs/GUIDE-EN.md)).

## Instalace do hodinek

Aplikace není v Connect IQ Store, instaluje se ručně (sideload):

1. Stáhni hotový soubor `Raysid.prg` pro svůj model. Najdeš ho v [Releases](../../releases) nebo na webu Žhavá místa. Nebo si ho sestav podle [docs/SESTAVENI.md](docs/SESTAVENI.md).
2. Připoj hodinky USB kabelem k počítači. Pozor, některé kabely jen nabíjejí.
   - Windows: hodinky se ukážou jako přenosné zařízení.
   - macOS: potřebuješ OpenMTP nebo Android File Transfer.
   - Linux: MTP, třeba přes správce souborů KDE (kio-extras) nebo `mtp-tools`.
3. Zkopíruj `Raysid.prg` do složky `GARMIN/APPS`.
4. Odpoj hodinky. Aplikace „Raysid“ se objeví v seznamu aplikací.
5. Zapni Raysid a zavři aplikaci Raysid v telefonu. Bluetooth spojení může mít Raysid jen s jedním zařízením.

Při aktualizaci stačí soubor přepsat. Nastavení i neodeslané body zůstanou, pokud je nový build podepsaný stejným vývojářským klíčem.

## Podporované hodinky

Aplikace je napsaná pro kulaté hodinky s tlačítky podobné fēnixu: START, BACK, UP, DOWN a LIGHT, Bluetooth LE a GPS. Pro každý model je potřeba oficiální definice zařízení z Garmin SDK Manageru a kontrola rozložení na displeji, hlavně značek u tlačítek. Postup je v [docs/SESTAVENI.md](docs/SESTAVENI.md#8-podpora-dalšího-modelu-hodinek).

## Dokumentace

| Soubor | Pro koho | Obsah |
|---|---|---|
| [docs/NAVOD.md](docs/NAVOD.md) | uživatel | ovládání a všechny funkce (stejný text jako nápověda v hodinkách) |
| [docs/SESTAVENI.md](docs/SESTAVENI.md) | vývojář | SDK, vývojářský klíč, sestavení, nahrání, logy, další modely, vydání verze |
| [docs/ARCHITEKTURA.md](docs/ARCHITEKTURA.md) | vývojář | moduly, tok dat, časovače, menu, uložená data, alarmy, OVL |
| [docs/PROTOKOL-RAYSID.md](docs/PROTOKOL-RAYSID.md) | vývojář | Bluetooth protokol Raysidu, oficiální i odposlechnutá část |
| [docs/MAPOVANI-A-ODESILANI.md](docs/MAPOVANI-A-ODESILANI.md) | vývojář | záznam bodů, úložiště, slučování, odesílání na web |
| [docs/zhavamista/navrh-endpointu.md](docs/zhavamista/navrh-endpointu.md) | vývojář webu | rozhraní webu Žhavá místa pro příjem tras |
| [AGENTS.md](AGENTS.md) | AI agent i člověk | jak na projektu pracovat: pravidla, omezení hodinek, konvence, kontrolní seznam |
| [CHANGELOG.md](CHANGELOG.md) | všichni | historie verzí a buildů |
| [docs/kontrola-2026-10-14.md](docs/kontrola-2026-10-14.md), [docs/test-ui-2026-10-15.md](docs/test-ui-2026-10-15.md) | vývojář | zprávy z revizí kódu a testu UI |

## Rychlý start pro vývojáře

```bash
# Connect IQ SDK a Java; definice zařízení fenix7xpro ze SDK Manageru
# vlastní vývojářský klíč (nikdy ho necommituj):
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt

# kontrola překladu (nejpřísnější typová kontrola)
monkeyc -d fenix7xpro -f monkey.jungle -o /tmp/t.prg -y developer_key.der -l 3 -w

# build k vydání (zvýší číslo buildu, zapíše source/BuildInfo.mc)
TOOLCHAIN=/cesta/k/toolchainu bash build.sh fenix7xpro
```

Podrobnosti jsou v [docs/SESTAVENI.md](docs/SESTAVENI.md).

## Soukromí

- Aplikace posílá data jen na web Žhavá místa, a to jen když je zapnuté mapování a zadaný API klíč. Jde o polohu, čas, dávku a cps bodů trasy.
- API klíč se ukládá jen v hodinkách.
- Ladicí log, pokud ho zapneš, se zapisuje jen do hodinek.

## Licence a autoři

Copyright © 2026 Vít Cenek a přispěvatelé ([AUTHORS.md](AUTHORS.md)). Spoluautor kódu: Claude (Anthropic).

Program je svobodný software pod licencí **GNU GPL verze 3 nebo pozdější** ([LICENSE](LICENSE)):
- Můžeš ho volně používat, kopírovat a šířit, i upravený.
- Při šíření musíš zachovat autory a licenci.
- Upravené verze, které šíříš (včetně hotových `.prg`), musí zůstat open source pod stejnou licencí.

Raysid je produkt společnosti Raysid. Garmin, fēnix a Connect IQ jsou ochranné známky Garmin Ltd. Projekt s nimi není spojený.

---

## English summary

**Raysid Garmin** is a Garmin Connect IQ watch app (fēnix 7X Pro and similar round button watches) for the **Raysid** BLE dosimeter. It shows:
- dose rate (µSv/h) and count rate (cps), with a chart and overload (OVL) detection;
- watch alarms (dose, CPS, rapid rise) and click/vibration/flashlight signalling with a divider.

It can change settings stored in the Raysid. It records GPS radiation maps and uploads them through the phone to the Czech community map **[Žhavá místa](https://zhavamista.cz)**. UI languages: Czech, English, Polish.

Install by copying `Raysid.prg` to `GARMIN/APPS` over USB. Start with:
- [docs/GUIDE-EN.md](docs/GUIDE-EN.md) (user guide)
- [AGENTS.md](AGENTS.md) (how to work on the code; written for both humans and AI agents)

The other technical documentation is in Czech.

License: GPL-3.0-or-later. Authors: Vít Cenek, co-authored with Claude (Anthropic).
