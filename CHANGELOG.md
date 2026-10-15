# Historie změn

Číslo buildu se zvyšuje s každým buildem poslaným na test (`build.sh`); verze (`APP_VERSION`) se mění jen při větších vydáních. Starší položky jsou sepsané zpětně ze záznamů vývoje, podrobnosti k posledním buildům jsou ve zprávách v `docs/`.

## 1.1

### Build 83 (15. 10. 2026)
- **Cílové hodinky:** build je teď pro fēnix 7X Pro (id `fenix7xpro`), na kterém se aplikace testuje. Dřív se překládala pro fēnix 7X. Funkce se nemění, nastavení i neodeslané body zůstanou.

### Build 82 (15. 10. 2026)
Hloubkový test celého UI, opraveno 40 chyb. Podrobně v [docs/test-ui-2026-10-15.md](docs/test-ui-2026-10-15.md). Hlavní:
- **Parser:** po poškozeném paketu se zotaví hned a čte data od první notifikace po připojení.
- **Odesílání:** neodeslané body se nemažou při chybě webu typu 404, zahodí se jen dávky odmítnuté kvůli obsahu.
- **Alarmy:**
  - Červená svítilna bliká po celou dobu alarmu i při děličce 1:1.
  - Alarm má přednost před cvakáním a varováním.
  - Při OVL se ozve každý zapnutý alarm dávky nebo cps.
  - Prudký nárůst počítá pozadí podle času.
- **Mapování:** ukazuje „čekám na Raysid“ nebo „OVL“, když se body neukládají. Stav „plno“ přežije restart aplikace.
- **Menu:**
  - Popisky se obnovují po návratu z podmenu.
  - Kratší texty se vejdou na kulatý displej.
  - Jazyk se při prvním spuštění vybere podle hodinek.
- **Ladicí obrazovka:** UP a DOWN nic nedělají.

### Build 81 (14. 10. 2026)
- **Úložiště:** nové menu Žhavá místa → Úložiště: Neodesláno, Když se zaplní (Zastavit, Sloučit nejvýš 1×/2×/3×, Bez omezení) a Smazat neodeslané.
- **Revize kódu:** opraveno 26 chyb, viz [docs/kontrola-2026-10-14.md](docs/kontrola-2026-10-14.md). Patří sem automatické obnovení Bluetooth spojení po 30 s, ping vždy na začátek fronty a postupné mazání bloků.

### Build 79–80 (14. 10. 2026)
- Verze 1.1.
- Při plném úložišti se sousední body slučují a z každé dvojice zůstane bod s vyšší dávkou.

## 1.0

### Build 76–78 (14. 10. 2026)
- **Meze alarmů:** jen pod přetížením Raysidu (cps nejvýš 5000, dávka nejvýš 999 µSv/h).
- **Dělička:** pevné hodnoty jako v Raysidu (1, 5, 10, 20, 50, 100, 250). Při 1:1 zůstanou v hodinkách jen alarmy.
- **Sloučení děličky:** hodinky a Raysid můžou mít jednu společnou děličku.
- **Plné úložiště:** zápis do úložiště je ošetřený a při zaplnění se nahrávání zastaví bez pádu.

### Build 59–75 (14. 10. 2026)
- **Přetížení (OVL):** zvlášť pro dávku a cps. Raysid ho hlásí příznakem v paketu 0x17, vlastní odhad slouží jako záloha.
- **Ladicí log:** do `GARMIN/APPS/LOGS`.
- **Nové pakety:** rozpoznání oddělovače po restartu Raysidu, události tlačítka Raysidu (0x18) a znovunačtení nastavení.

### Do buildu 58 (12.–14. 10. 2026)
- **Základ:** připojení k Raysidu, hodnoty µSv/h a cps, baterie, graf, alarmy (meze a prudký nárůst), cvakání, vibrace, svítilna, nápověda ve třech jazycích a ikona.
- **Nastavení Raysidu:** z hodinek (odposlechnuté příkazy): dělička, cvakání, alarmy.
- **Průměrování** hodnot podle času nebo počtu měření.
- **Mapování s GPS:** obrazovka Mapování, pauza, autostart, kvalita GPS a vzdálenost bodů.
- **Žhavá místa:** odesílání na web (endpoint `route-points`), zadání a ověření API klíče v hodinkách.
- **Připojení:** historie Raysidů, „jen vybraný“, preference při více kusech.
