# Odposlech nastavení Raysidu (postup pro btsnoop log)

Cíl: zjistit, jak Raysid po připojení hlásí svoje nastavení (dělička, zvuk klikání a zapnutí alarmů dávky a cps v Raysidu), aby je hodinky uměly vyčíst.

## Jak to funguje

Po připojení si oficiální aplikace vyžádá z Raysidu balík s nastavením a přístroj ho jednou pošle. Při každém novém připojení přijde znovu. Když mezi připojeními změníš vždy **jen jednu věc**, porovnám balíky a uvidím, který bajt se změnil.

**Stačí jeden log.** Snoop log zapisuje průběžně všechno od zapnutí Bluetooth, takže se do něj vejde i dvacet odpojení a připojení. Bluetooth na telefonu ale během měření **nevypínej**. Každé vypnutí a zapnutí totiž začne nový soubor a starý se přejmenuje na `btsnoop_hci.log.last`, ještě starší se ztratí.

## Příprava

1. Snoop log nech nastavený na **Enabled**.
2. Na hodinkách **zavři aplikaci Raysid**, aby se k dozimetru nepřipojovala místo telefonu.
3. Na telefonu jednou vypni a zapni Bluetooth (začne čistý log). Pak už Bluetooth nevypínej.
4. Připrav si papír nebo poznámku. Ke každému kroku zapiš **čas z telefonu** a co jsi udělal, třeba `14:12 – krok 3 – dělička 1:10`. Stačí hodina a minuta, sekundy nejsou potřeba. Důležitější je dodržet pořadí z tabulky, kroky v logu poznám podle sledu příkazů a čas mi jen pomůže, kdyby se něco opakovalo nebo vynechalo.

## Jeden krok = jedna změna a nové připojení

Pro každý řádek tabulky níže:

1. V oficiální aplikaci **změň jednu položku**, počkej 5 s.
2. **Odpoj se** (tlačítkem v aplikaci; když ho nenajdeš, vypni Raysid tlačítkem). Počkej 10 s.
3. **Připoj se znovu** (případně zapni Raysid). Počkej 15 s, než začnou chodit hodnoty.
4. Zapiš čas a co jsi změnil.

Nejdřív udělej jedno připojení bez změny jako výchozí stav a zapiš, jak je všechno nastavené (stačí screenshot obrazovky SETS).

## Pořadí měření

| # | Změna | Proč |
|---|---|---|
| 0 | nic, jen připojit (výchozí stav + screenshot SETS) | základ pro porovnání |
| 1 | dělička 1:1 | |
| 2 | dělička 1:5 | |
| 3 | dělička 1:10 | |
| 4 | dělička 1:20 | |
| 5 | dělička 1:50 | |
| 6 | dělička 1:100 | |
| 7 | dělička 1:250 | sedm hodnot = jistota, který bajt to je |
| 8 | Sound Clicks vypnout | |
| 9 | Sound Clicks zapnout | |
| 10 | Dose rate alarm vypnout | |
| 11 | Dose rate alarm zapnout | |
| 12 | CPS alarm vypnout | |
| 13 | CPS alarm zapnout | |

„Enable Clicks“ ani další položky ze SETS neměň: Enable Clicks je klikání v mobilu, ne v Raysidu.

## Odeslání

1. Udělej `adb bugreport raysid2.zip` jako minule.
2. Vytáhni log: `unzip -j raysid2.zip 'FS/data/misc/bluetooth/logs/btsnoop_hci.log*'`
3. Pošli mi `btsnoop_hci.log` (a `.last`, pokud vznikl) a svoje poznámky s časy.
4. Snoop log pak můžeš vypnout.

## Poznámky

- Log obsahuje i provoz ostatních Bluetooth zařízení (třeba notifikace do jiných hodinek). Čtu jen komunikaci s Raysidem. Pokud ti to vadí, odpoj ostatní zařízení na dobu měření.
- Když se během měření něco pokazí (spadne připojení, splete se pořadí), nic se neděje. Jen to poznamenej s časem a pokračuj dalším krokem.
