// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.Lang;

// Preklady cele aplikace: 0 = cestina, 1 = anglictina, 2 = polstina.
// Tr.t(:klic) vrati text v aktualnim jazyce.
module Tr {
    const LANG_CODES = ["CZ", "EN", "PL"];
    var lang as Number = 0;
    var _table as Dictionary<Symbol, Array<String> >? = null;

    function t(key as Symbol) as String {
        if (_table == null) {
            _table = build();
        }
        var row = (_table as Dictionary<Symbol, Array<String> >)[key];
        return row == null ? key.toString() : row[lang];
    }

    function build() as Dictionary<Symbol, Array<String> > {
        return {
            // --- stav pripojeni ---
            :stStart => ["Start", "Start", "Start"],
            :stRegistering => ["Registrace", "Registering", "Rejestracja"],
            :stProfileErr => ["Chyba profilu", "Profile error", "Błąd profilu"],
            :stSearching => ["Hledám...", "Searching...", "Szukam..."],
            :stConnecting => ["Připojuji", "Connecting", "Łączenie"],
            :stPairErr => ["Chyba párování", "Pairing error", "Błąd parowania"],
            :stConnected => ["Připojeno", "Connected", "Połączono"],
            :stDisconnected => ["Odpojeno", "Disconnected", "Rozłączono"],
            :stNoService => ["Služba nenalezena", "Service not found", "Brak usługi"],
            :stProfile => ["Profil", "Profile", "Profil"],
            :stCccd => ["CCCD", "CCCD", "CCCD"],

            // --- obrazovky ---
            :alarmLimit => ["ALARM: překročena mez", "ALARM: limit exceeded", "ALARM: przekroczony próg"],
            :rapidRise => ["Prudký nárůst", "Rapid rise", "Gwałtowny wzrost"],
            :beeperOff => ["CVAKÁNÍ VYPNUTO", "CLICKING OFF", "KLIKANIE WYŁ."],
            :packets => ["pakety", "packets", "pakiety"],
            :refresh => ["obnova", "refresh", "odświeżanie"],
            :now => ["teď", "now", "teraz"],
            :chartWait => ["zatím", "so far", "na razie"],
            :watch => ["hodinky", "watch", "zegarek"],
            :collecting => ["sbírám data...", "collecting data...", "zbieram dane..."],

            // --- menu ---
            :reconnect => ["Znovu připojit", "Reconnect", "Połącz ponownie"],
            :mConn => ["Připojení", "Connection", "Połączenie"],
            :devPick => ["Vybraný Raysid", "Chosen Raysid", "Wybrany Raysid"],
            :devAny => ["kterýkoli", "any", "dowolny"],
            :devOnly => ["jen", "only", "tylko"],
            :devLast => ["naposledy připojený", "last connected", "ostatnio połączony"],
            :devForget => ["Zapomenout historii", "Forget history", "Zapomnij historię"],
            :devLock => ["Jen vybraný Raysid", "Only chosen Raysid", "Tylko wybrany"],
            :devPickFirst => ["nejdřív vyber Raysid", "pick a Raysid first", "najpierw wybierz"],
            :connPref => ["Více Raysidů", "Several Raysids", "Kilka Raysidów"],
            :prefKnown => ["vybraný, pak známý", "chosen, then known", "wybrany, potem znany"],
            :prefStrong => ["nejsilnější signál", "strongest signal", "najsilniejszy sygnał"],
            :mSignal => ["Signalizace", "Signals", "Sygnalizacja"],
            :inWatch => ["v hodinkách", "on the watch", "w zegarku"],
            :gDose => ["Dávka", "Dose rate", "Dawka"],
            :gCps => ["Cps", "CPS", "CPS"],
            :gRise => ["Prudký nárůst", "Rapid rise", "Gwałtowny wzrost"],
            :mAlarms => ["Alarmy", "Alarms", "Alarmy"],
            :mDevice => ["Raysid", "Raysid", "Raysid"],
            :mWatchSig => ["Hodinky", "Watch", "Zegarek"],
            :devSound => ["Cvakání", "Clicking", "Klikanie"],
            :devDiv => ["Dělička", "Divider", "Dzielnik"],
            :divLink => ["Sloučit děličku", "Link divider", "Połącz dzielnik"],
            :div1Note => ["(jen alarmy)", "(alarms only)", "(tylko alarmy)"],
            :divLinkSub => ["hodinky = Raysid", "watch = Raysid", "zegarek = Raysid"],
            :devDoseAl => ["Alarm dávky", "Dose rate alarm", "Alarm dawki"],
            :devCpsAl => ["Alarm cps", "CPS alarm", "Alarm cps"],
            :mAlarmOut => ["Projev alarmu", "Alarm output", "Sygnalizacja alarmu"],
            :mWeb => ["Web a odesílání", "Web and upload", "Web i wysyłanie"],
            :mDisplay => ["Displej", "Display", "Wyświetlacz"],
            :avgMode => ["Průměrování", "Averaging", "Uśrednianie"],
            :avgOff => ["Okamžité hodnoty", "Instant values", "Wartości chwilowe"],
            :avgTime => ["Podle času", "By time", "Według czasu"],
            :avgCount => ["Podle počtu měření", "By reading count", "Wg liczby pomiarów"],
            :avgSpan => ["Průměr přes", "Average over", "Średnia z"],
            :avgMeas => ["měření", "readings", "pomiarów"],
            :avgShort => ["prům.", "avg", "śr."],
            :mLanguage => ["Jazyk", "Language", "Język"],
            :mHelp => ["Nápověda", "Help", "Pomoc"],
            :beep => ["Cvakání", "Clicking", "Klikanie"],
            :vibration => ["Vibrace k impulzům", "Vibrate on pulses", "Wibracja impulsów"],
            :flash => ["Blikání svítilnou", "Flashlight blink", "Miganie latarką"],
            :divider => ["Dělička", "Divider", "Dzielnik"],
            :alarmsAll => ["Všechny alarmy", "All alarms", "Wszystkie alarmy"],
            :doseAlarm => ["Alarm dávky", "Dose alarm", "Alarm dawki"],
            :doseLimit => ["Mez dávky", "Dose limit", "Próg dawki"],
            :cpsAlarm => ["Alarm cps", "CPS alarm", "Alarm CPS"],
            :cpsLimit => ["Mez cps", "CPS limit", "Próg CPS"],
            :rise => ["Hlídání nárůstu", "Rise detection", "Wykrywanie wzrostu"],
            :sensitivity => ["Citlivost", "Sensitivity", "Czułość"],
            :sens1 => ["citlivá (+30 %)", "sensitive (+30 %)", "czuła (+30 %)"],
            :sens2 => ["střední (+50 %)", "medium (+50 %)", "średnia (+50 %)"],
            :sens3 => ["hrubá (+100 %)", "coarse (+100 %)", "zgrubna (+100 %)"],
            :alarmSound => ["Zvuk alarmu", "Alarm sound", "Dźwięk alarmu"],
            :alarmVibe => ["Vibrace alarmu", "Alarm vibration", "Wibracje alarmu"],
            :alarmFlash => ["Bliknutí displeje", "Screen flash", "Mignięcie ekranu"],
            :alarmRedLed => ["Červená svítilna", "Red flashlight", "Czerwona latarka"],
            :alarmLen => ["Délka alarmu", "Alarm length", "Długość alarmu"],
            :lenShort => ["krátký (1×)", "short (1×)", "krótki (1×)"],
            :lenMedium => ["střední (3×)", "medium (3×)", "średni (3×)"],
            :lenLong => ["dlouhý (8×)", "long (8×)", "długi (8×)"],
            :custom => ["Vlastní hodnota...", "Custom value...", "Własna wartość..."],
            :vibeMax => ["VIBRO MAX", "VIBRO MAX", "VIBRO MAX"],
            :avgOf => ["průměr po", "average of", "średnia z"],
            :aboveBg => ["nad pozadím", "above background", "ponad tłem"],
            :backlight => ["Stálé podsvícení", "Backlight always on", "Stałe podświetlenie"],
            :chartLen => ["Délka grafu", "Chart length", "Długość wykresu"],
            :debug => ["Ladicí obrazovka", "Debug screen", "Ekran diagnostyczny"],
            :on => ["zapnuto", "on", "wł."],
            :off => ["vypnuto", "off", "wył."],
            :langName => ["Čeština", "English", "Polski"],

            // --- napoveda ---
            :hControls => ["Ovládání", "Controls", "Sterowanie"],
            :hControlsT => [
                "START (pravé horní tlačítko, na displeji je u něj zvýrazněný oblouk) otevře menu. DOWN přepíná mezi hodnotami, grafem a při zapnutém mapování i obrazovkou Mapování. UP (žlutý oblouk) má na každé obrazovce vlastní akci: na hlavní prohodí dávku a cps (co je velké nahoře), u grafu přepne délku 10/20/30/60 s a na obrazovce Mapování zapne, pozastaví nebo po pauze obnoví nahrávání. BACK ukončí aplikaci. Dotyk displeje a swipe se ignorují, aby se nic nezměnilo omylem. Nastavení se pamatuje i po vypnutí aplikace.",
                "START (upper right button, marked by a highlighted arc on the screen) opens the menu. DOWN switches between the values, the chart and, with mapping on, the Mapping screen. UP (yellow arc) has its own action on each screen: on the main screen it swaps dose and cps (which one is big on top), on the chart it cycles the length 10/20/30/60 s and on the Mapping screen it starts, pauses or resumes recording. BACK exits the app. Touch and swipe are ignored so nothing changes by accident. Settings are kept after the app is closed.",
                "START (prawy górny przycisk, na ekranie oznaczony podświetlonym łukiem) otwiera menu. DOWN przełącza między wartościami, wykresem i przy włączonym mapowaniu ekranem Mapowanie. UP (żółty łuk) ma na każdym ekranie własną akcję: na głównym zamienia dawkę i cps (co jest duże u góry), na wykresie przełącza długość 10/20/30/60 s, a na ekranie Mapowanie włącza, wstrzymuje lub wznawia nagrywanie. BACK zamyka aplikację. Dotyk i przesunięcia są ignorowane, aby nic nie zmieniło się przypadkiem. Ustawienia są zapamiętywane po zamknięciu aplikacji."
            ],
            :hScreens => ["Obrazovky", "Screens", "Ekrany"],
            :hAbout => ["O aplikaci", "About", "O aplikacji"],
            :aboutBuild => ["build", "build", "build"],
            :aboutAuthor => ["Autor", "Author", "Autor"],
            :aboutCo => ["Spoluautor", "Co-author", "Współautor"],
            :hScreensT => [
                "Hlavní obrazovka ukazuje dávkový příkon v µSv/h (oranžově), count rate v cps (modře), obojí s jednotkou za číslem, a baterii Raysidu i hodinek. Graf ukazuje obě veličiny za zvolenou dobu, každou s vlastní automatickou stupnicí. Při zapnutém mapování je třetí obrazovka Mapování: stav záznamu a GPS, ujetá vzdálenost, počet bodů, doba nahrávání, nejvyšší dávka a cps v bodech od zapnutí nahrávání a stav odesílání na web. Délka grafu je 10, 20, 30 nebo 60 s a přepíná se tlačítkem UP na obrazovce grafu; u 60 s se měření průměrují po 4 s a tenké svislé čárky ukazují rozptyl cps. Zvolený rozsah je bíle pod grafem; dokud nejsou data za celou dobu, je za ním oranžově, za kolik sekund už jsou. Popisky stupnic jsou vždy nad čarami grafu. Hodnoty zešednou, když 5 s nepřijdou data. Raysid posílá data několikrát za sekundu. Menu > Displej > Průměrování: okamžité hodnoty, nebo průměr za posledních N sekund (Podle času) či posledních N měření (Podle počtu měření). Průměr platí pro čísla na hlavní obrazovce i pro čáru grafu, na hlavní obrazovce je pak šedě vedle hodin, přes kolik se průměruje. V grafu je průměr nejvýš pětina jeho délky (u 10 s grafu 2 s, u 60 s grafu 12 s), aby se čára nerozmazala; skutečný průměr je šedě pod grafem. Vlastní hodnota jde do 60 s nebo 30 měření. Alarmy, signalizace a body mapování jdou vždy z okamžitých hodnot, aby nic nezpozdily. Ladicí obrazovka ukazuje poslední interval mezi měřeními a jeho průměr v ms. Menu > Raysid > Připojení: Znovu připojit, Vybraný Raysid (z historie připojených), Jen vybraný Raysid (ostatní se ignorují) a co dělat, když je v dosahu víc Raysidů.",
                "The main screen shows the dose rate in µSv/h (orange), the count rate in cps (blue), each with its unit after the number, and the Raysid and watch batteries. The chart shows both over the chosen time, each with its own automatic scale. With mapping on, a third Mapping screen shows recording and GPS state, distance, point count, recording time, the highest dose and cps in points since recording started, and the upload state. The chart length is 10, 20, 30 or 60 s and is switched with UP on the chart screen; at 60 s readings are averaged over 4 s and thin vertical marks show the cps spread. The chosen span is shown in white below the chart; until there is data for the whole span, the seconds collected so far follow in orange. Scale labels are always drawn above the chart lines. Values turn grey when no data arrive for 5 s. Raysid sends data several times per second. Menu > Display > Averaging: instant values, or the average of the last N seconds (By time) or the last N readings (By reading count). The average applies to the main screen numbers and the chart line; the main screen then shows the averaging span in grey next to the clock. On the chart the average is at most a fifth of its length (2 s on a 10 s chart, 12 s on a 60 s chart) so the line does not smear; the actual average is shown in grey below the chart. A custom value can be up to 60 s or 30 readings. Alarms, signalling and mapping points always use instant values so nothing is delayed. The debug screen shows the last interval between readings and its average in ms. Menu > Raysid > Connection: Reconnect, Chosen Raysid (from the history of connected units), Only chosen Raysid (others are ignored) and what to do when several Raysids are nearby.",
                "Ekran główny pokazuje moc dawki w µSv/h (pomarańczowo), liczbę zliczeń w cps (niebiesko), każdą z jednostką za liczbą, oraz baterię Raysida i zegarka. Wykres pokazuje obie wartości w wybranym czasie, każdą z własną automatyczną skalą. Przy włączonym mapowaniu trzeci ekran Mapowanie pokazuje stan zapisu i GPS, przebytą odległość, liczbę punktów, czas nagrywania, najwyższą dawkę i cps w punktach od włączenia nagrywania oraz stan wysyłania na web. Długość wykresu to 10, 20, 30 lub 60 s i przełącza się przyciskiem UP na ekranie wykresu; przy 60 s pomiary są uśredniane co 4 s, a cienkie pionowe kreski pokazują rozrzut cps. Wybrany zakres jest na biało pod wykresem; dopóki nie ma danych z całego okresu, za nim na pomarańczowo jest, ile sekund już zebrano. Opisy skal są zawsze nad liniami wykresu. Wartości szarzeją, gdy przez 5 s nie ma danych. Raysid wysyła dane kilka razy na sekundę. Menu > Wyświetlacz > Uśrednianie: wartości chwilowe albo średnia z ostatnich N sekund (Według czasu) lub ostatnich N pomiarów (Według liczby pomiarów). Średnia dotyczy liczb na ekranie głównym i linii wykresu; ekran główny pokazuje wtedy na szaro obok zegara, z ilu jest średnia. Na wykresie średnia to najwyżej piąta część jego długości (2 s przy wykresie 10 s, 12 s przy 60 s), żeby linia się nie rozmywała; faktyczna średnia jest na szaro pod wykresem. Własna wartość może wynosić do 60 s lub 30 pomiarów. Alarmy, sygnalizacja i punkty mapowania zawsze używają wartości chwilowych, żeby nic nie opóźniać. Ekran debugowania pokazuje ostatni odstęp między pomiarami i jego średnią w ms. Menu > Raysid > Połączenie: Połącz ponownie, Wybrany Raysid (z historii połączonych), Tylko wybrany Raysid (inne są ignorowane) i co robić, gdy w zasięgu jest kilka Raysidów."
            ],
            :hSignal => ["Signalizace", "Signals", "Sygnalizacja"],
            :hSignalT => [
                "Menu Raysid obsahuje nastavení uložená přímo v dozimetru: dělička, cvakání a zapnutí alarmu dávky a cps, a k tomu Připojení. Sloučit děličku sváže děličku hodinek s děličkou Raysidu: změna v kterémkoli menu se propíše do obou. Stav se čte z Raysidu po připojení, měnit jde jen při připojeném Raysidu; ? znamená, že Raysid stav ještě nenahlásil. Menu Signalizace: cvakání, vibrace a blikání svítilnou v hodinkách běží rovnoměrně podle aktuálního cps: jeden signál na N impulzů podle děličky. Hodinky zvládnou nejvýš 10 signálů za sekundu; nad tím se signalizace dočasně vypne, ukáže se CVAKÁNÍ VYPNUTO a každé 2 s zazní varování. Vibrační motor potřebuje na každý puls zhruba 250 ms, proto vibrace k impulzům běží jen do 4 za sekundu. Nad tím se vynechávají (cvakání se svítilnou jedou dál) a hodinky to ohlásí sílící vibrací slabě-středně-silně, opakovaně po 10 s; na displeji je VIBRO MAX. Po poklesu pod 3 za sekundu vibrace k impulzům naskočí znovu. Dělička má hodnoty 1, 5, 10, 20, 50, 100 a 250 jako v aplikaci Raysid. Při 1:1 hodinky cvakání, vibrace i svítilnu vypnou a zůstanou jen alarmy. Cvakání potřebuje zapnuté tóny v nastavení hodinek.",
                "The Raysid menu holds the settings stored in the dosimeter itself: divider, clicking and the dose rate and CPS alarm switches, plus Connection. Link divider ties the watch divider to the Raysid divider: a change in either menu is applied to both. The state is read from the Raysid after connecting and can be changed only while it is connected; ? means the Raysid has not reported it yet. Signals menu: clicking, vibration and flashlight blinking on the watch run evenly from the current cps: one signal per N pulses set by the divider. The watch can do at most 10 signals per second; above that, signalling pauses, CLICKING OFF is shown and a warning sounds every 2 s. The vibration motor needs about 250 ms per pulse, so pulse vibration runs only up to 4 per second. Above that it is skipped (clicking and the flashlight continue) and the watch signals it with a rising weak-medium-strong vibration, repeated every 10 s; VIBRO MAX is shown. Below 3 per second pulse vibration resumes. The divider offers 1, 5, 10, 20, 50, 100 and 250, the same as the Raysid app. At 1:1 the watch turns clicking, vibration and flashlight off and only alarms remain. Clicking needs tones enabled in the watch settings.",
                "Menu Raysid zawiera ustawienia zapisane w samym dozymetrze: dzielnik, klikanie oraz włączenie alarmu dawki i cps, a także Połączenie. Połącz dzielnik wiąże dzielnik zegarka z dzielnikiem Raysida: zmiana w dowolnym menu trafia do obu. Stan jest odczytywany z Raysida po połączeniu, zmieniać można tylko przy połączonym Raysidzie; ? oznacza, że Raysid jeszcze nie zgłosił stanu. Menu Sygnalizacja: klikanie, wibracje i miganie latarką w zegarku działają równomiernie według bieżącego cps: jeden sygnał na N impulsów według dzielnika. Zegarek obsłuży najwyżej 10 sygnałów na sekundę; powyżej sygnalizacja jest wstrzymana, pojawia się KLIKANIE WYŁ. i co 2 s słychać ostrzeżenie. Silnik wibracyjny potrzebuje około 250 ms na impuls, dlatego wibracje przy impulsach działają tylko do 4 na sekundę. Powyżej są pomijane (klikanie i latarka działają dalej), a zegarek sygnalizuje to narastającą wibracją słaba-średnia-silna, powtarzaną co 10 s; na ekranie widać VIBRO MAX. Poniżej 3 na sekundę wibracje przy impulsach wracają. Dzielnik ma wartości 1, 5, 10, 20, 50, 100 i 250, jak w aplikacji Raysid. Przy 1:1 zegarek wyłącza klikanie, wibracje i latarkę, zostają tylko alarmy. Klikanie wymaga włączonych dźwięków w ustawieniach zegarka."
            ],
            :hAlarms => ["Alarmy", "Alarms", "Alarmy"],
            :hAlarmsT => [
                "Alarmy hodinek. Všechny alarmy vypne nebo zapne najednou; každý alarm (Dávka, Cps, Prudký nárůst) má vlastní podmenu s vypínačem a mezí (stav je vidět už v popisku); mez lze vybrat nebo zadat vlastní (po číslicích: UP/DOWN mění číslici, START jde na další a na poslední uloží, BACK o číslici zpět). Alarm se ozve při překročení meze a pak znovu až po poklesu pod 90 % meze. Mez jde nastavit jen pod přetížení Raysidu: nejvýš 5000 cps a 999 µSv/h. Při přetížení (červené blikající OVL místo hodnoty) se zapnutý alarm dávky nebo cps ozve vždy. V podmenu Projev alarmu lze zvlášť zapnout zvuk, vibrace, probliknutí displeje a červenou svítilnu a nastavit délku alarmu: krátký (1×), střední (3×) nebo dlouhý (8×, asi 15 s); umlčí ho jakékoli tlačítko na hlavní obrazovce nebo grafu, i vypnutí alarmu v menu. Hodnota nad mezí je červená a úseky s alarmem jsou v grafu podbarvené.",
                "Watch alarms. All alarms switches every alarm on or off at once; each alarm (Dose rate, CPS, Rapid rise) has its own submenu with a switch and a limit you can pick or enter (digit by digit: UP/DOWN change the digit, START moves to the next one and saves on the last, BACK goes back a digit). An alarm sounds when its limit is crossed and again only after dropping below 90 % of it. Limits can only be set below Raysid overload: at most 5000 cps and 999 µSv/h. During overload (red blinking OVL instead of the value) an enabled dose rate or CPS alarm always sounds. In the Alarm output submenu, sound, vibration, screen flash and red flashlight can be switched separately and the alarm length set: short (1×), medium (3×) or long (8×, about 15 s); any button on the main or chart screen silences it, as does switching the alarm off in the menu. The value above the limit turns red and alarm periods are shaded in the chart.",
                "Alarmy zegarka. Wszystkie alarmy włącza lub wyłącza wszystkie naraz; każdy alarm (Dawka, CPS, Gwałtowny wzrost) ma własne podmenu z przełącznikiem i progiem, który można wybrać lub wpisać (cyfra po cyfrze: UP/DOWN zmienia cyfrę, START przechodzi do następnej i na ostatniej zapisuje, BACK cofa o cyfrę). Alarm odzywa się po przekroczeniu progu, a ponownie dopiero po spadku poniżej 90 % progu. Próg można ustawić tylko poniżej przeciążenia Raysida: najwyżej 5000 cps i 999 µSv/h. Przy przeciążeniu (czerwone migające OVL zamiast wartości) włączony alarm dawki lub cps odzywa się zawsze. W podmenu Sygnalizacja alarmu można osobno włączać dźwięk, wibracje, mignięcie ekranu i czerwoną latarkę oraz ustawić długość alarmu: krótki (1×), średni (3×) lub długi (8×, ok. 15 s); wycisza go dowolny przycisk na ekranie głównym lub wykresie, a także wyłączenie alarmu w menu. Wartość ponad progiem jest czerwona, a okresy alarmu są zacienione na wykresie."
            ],
            // --- zaznam ---
            :mRecord => ["Žhavá místa", "Žhavá místa", "Žhavá místa"],
            :recPauseUp => ["pozastaveno", "paused", "wstrzymano"],
            :recPausedUp => ["UP = nahrávat", "UP = record", "UP = nagrywaj"],
            :recDist => ["Vzdálenost bodů", "Point spacing", "Odstęp punktów"],
            :recClear => ["Smazat neodeslané", "Delete unsent", "Usuń niewysłane"],
            :mStorage => ["Úložiště", "Storage", "Pamięć"],
            :stoPending => ["Neodesláno", "Not uploaded", "Niewysłane"],
            :cmpWhen => ["Když se zaplní", "When full", "Gdy pełna"],
            :cmpStop => ["Zastavit nahrávání", "Stop recording", "Zatrzymać nagrywanie"],
            :cmpMaxN => ["Sloučit nejvýš", "Merge at most", "Łączyć najwyżej"],
            :cmpAny => ["Slučovat bez omezení", "Merge without limit", "Łączyć bez limitu"],
            :cmpMaxS => ["nejvýš", "at most", "najwyżej"],
            :cmpUpTo => ["až", "up to", "do"],
            :recClearQ => ["Smazat všechny body?", "Delete all points?", "Usunąć wszystkie punkty?"],
            :points => ["bodů", "points", "pkt."],
            :recFull => ["plno", "full", "pełno"],
            :waitGps => ["čekám na GPS", "waiting for GPS", "czekam na GPS"],
            :waitRaysid => ["čekám na Raysid", "waiting for Raysid", "czekam na Raysid"],
            :mapping => ["Mapování zapnuto", "Mapping enabled", "Mapowanie włączone"],
            :mapOff => ["mapování vypnuto", "mapping off", "mapowanie wyłączone"],
            :autostart => ["Nahrávat po spuštění", "Record on start", "Nagrywaj po starcie"],
            :gpsQual => ["Kvalita GPS", "GPS quality", "Jakość GPS"],
            :qGood => ["dobrá (nejpřesnější)", "good (most accurate)", "dobra (najdokładniej)"],
            :qUsable => ["použitelná", "usable", "użyteczna"],
            :qPoor => ["slabá (nejvíc bodů)", "poor (most points)", "słaba (najwięcej pkt.)"],
            :gpsWeak => ["slabé GPS", "weak GPS", "słaby GPS"],
            :recPaused => ["nenahrává se", "not recording", "nie nagrywa"],
            :web => ["Web", "Web", "Web"],
            :apiKey => ["API klíč", "API key", "Klucz API"],
            :verify => ["Ověřit spojení", "Test connection", "Sprawdź połączenie"],
            :vfIdle => ["neověřeno", "not tested", "nie sprawdzono"],
            :vfRunning => ["ověřuji...", "testing...", "sprawdzam..."],
            :vfOk => ["v pořádku", "OK", "w porządku"],
            :vfBad => ["web klíč nepřijal", "key rejected", "klucz odrzucony"],
            :vfNoKey => ["chybí API klíč", "no API key", "brak klucza API"],
            :vfNoPhone => ["bez telefonu", "no phone", "brak telefonu"],
            :vfErr => ["chyba", "error", "błąd"],
            :keyWhere1 => ["web Žhavá místa >", "Žhavá místa web >", "strona Žhavá místa >"],
            :keyWhere2 => ["Nastavení profilu", "Profile settings", "Ustawienia profilu"],
            :keyHelp => ["START přidá, BACK maže", "START adds, BACK deletes", "START dodaje, BACK usuwa"],
            :mUpload => ["Odesílání na web", "Upload to web", "Wysyłanie na web"],
            :upOff => ["vypnuto", "off", "wyłączone"],
            :upNoKey => ["chybí klíč", "no API key", "brak klucza"],
            :upNoPhone => ["bez telefonu", "no phone", "brak telefonu"],
            :upSending => ["odesílám", "sending", "wysyłam"],
            :upWait => ["průběžně", "ongoing", "na bieżąco"],
            :upDone => ["vše odesláno", "all sent", "wszystko wysłane"],
            :upAuth => ["špatný API klíč", "wrong API key", "zły klucz API"],
            :upErr => ["chyba", "error", "błąd"],
            :upQueue => ["čeká", "queued", "czeka"],
            :hRecord => ["Mapování", "Mapping", "Mapowanie"],
            :hRecordT => [
                "Tlačítko UP na obrazovce Mapování zapne GPS a ukládá body do paměti hodinek: poloha, čas, dávka a cps. Dávka a cps u bodu jsou průměr měření od předchozího bodu (nejvýš za 10 s), bez ohledu na průměrování displeje. Nový bod vznikne, když se posuneš o nastavenou vzdálenost (5, 8, 10, 12, 15 m nebo vlastní) a z Raysidu přišlo čerstvé měření. Na hlavní obrazovce dole svítí červeně REC a počet bodů, dokud GPS nemá polohu, je tam čekám na GPS. Opětovné UP nahrávání pozastaví a další UP plynule naváže na stejnou trasu (vzdálenost, body i doba pokračují, úsek během pauzy se nepočítá). Zavřením aplikace se trasa ukončí. Hotové bloky po 50 bodech se samy odesílají přes telefon na Žhavá místa (každých 5000 bodů nová trasa) a z hodinek se pak smažou; API klíč (najdeš ho na webu v Nastavení profilu) se zadává v Žhavá místa > Web a odesílání > API klíč: UP/DOWN vybírá znak, START ho přidá, BACK smaže, OK na konci seznamu uloží. U aplikace ze Store jde zadat i v Garmin Connect. Stav je v Žhavá místa > Web a odesílání > Odesílání na web, výběrem se odeslání zkusí hned. Úložiště (Žhavá místa > Úložiště): Neodesláno ukazuje, kolik bodů čeká na odeslání (vejde se asi 4000). Když se zaplní určuje, co se pak stane. Zastavit nahrávání: nahrávání skončí. Sloučit nejvýš 1×, 2× nebo 3×: z každých dvou sousedních neodeslaných bodů zůstane ten s vyšší dávkou, takže se uvolní zhruba polovina místa a nahrává se dál; body jsou pak od sebe dvakrát dál (např. 5 m > 10 m). Stejné body se můžou sloučit znovu, nejvýš nastavený počet krát: 1× = rozestup až 2×, 2× = až 4×, 3× = až 8× (u 5 m tedy 10, 20 nebo 40 m). Slučovat bez omezení: slučuje se pokaždé znovu. Když už není co slučovat, nahrávání skončí s nápisem plno a dlouhou vibrací. Smazat neodeslané smaže všechny body, které ještě nejsou na webu. GPS zvyšuje spotřebu baterie. Body se ukládají jen od zvolené Kvality GPS (výchozí dobrá), jinak je dole slabé GPS. Nahrávat po spuštění zapne záznam automaticky při každém startu aplikace. Mapování zapnuto zapíná celý modul; vypnuté ho skryje.",
                "The UP button on the Mapping screen turns on GPS and stores points in the watch memory: position, time, dose and cps. The dose and cps of a point are the average of readings since the previous point (at most 10 s), regardless of the display averaging. A new point is added when you move by the set distance (5, 8, 10, 12, 15 m or custom) and a fresh Raysid reading has arrived. The main screen shows REC and the point count in red at the bottom, or waiting for GPS until there is a fix. UP again pauses recording and the next UP continues the same route (distance, points and time carry on, the paused stretch is not counted). Closing the app ends the route. Finished blocks of 50 points are uploaded through the phone to Žhavá místa (a new route every 5000 points) and then deleted from the watch; enter the API key (found in your profile settings on the website) in Žhavá místa > Web and upload > API key: UP/DOWN picks a character, START adds it, BACK deletes, OK at the end of the list saves. A Store install can also set it in Garmin Connect. The state is in Žhavá místa > Web and upload > Upload to web, selecting it retries right away. Storage (Žhavá místa > Storage): Not uploaded shows how many points wait for upload (about 4000 fit). When full sets what happens then. Stop recording: recording ends. Merge at most 1×, 2× or 3×: of every two neighbouring unsent points the one with the higher dose is kept, freeing about half the space so recording continues; points are then twice as far apart (e.g. 5 m > 10 m). The same points can be merged again, at most the set number of times: 1× = spacing up to 2×, 2× = up to 4×, 3× = up to 8× (10, 20 or 40 m at 5 m). Merge without limit merges again every time. When nothing is left to merge, recording stops with full shown and a long vibration. Delete unsent deletes all points not yet on the web. GPS increases battery use. Points are stored only from the chosen GPS quality (default good), otherwise weak GPS is shown. Record on start turns recording on automatically every time the app starts. Mapping enabled turns the whole module on; off hides it.",
                "Przycisk UP na ekranie Mapowanie włącza GPS i zapisuje punkty w pamięci zegarka: pozycję, czas, dawkę i cps. Dawka i cps punktu to średnia pomiarów od poprzedniego punktu (najwyżej z 10 s), niezależnie od uśredniania wyświetlacza. Nowy punkt powstaje po przesunięciu o ustawioną odległość (5, 8, 10, 12, 15 m lub własna), gdy z Raysida przyszedł świeży pomiar. Na ekranie głównym na dole świeci na czerwono REC i liczba punktów, a do uzyskania pozycji czekam na GPS. Ponowne UP wstrzymuje nagrywanie, a kolejne UP płynnie kontynuuje tę samą trasę (dystans, punkty i czas trwają dalej, odcinek z pauzy się nie liczy). Zamknięcie aplikacji kończy trasę. Gotowe bloki po 50 punktów wysyłają się przez telefon do Žhavá místa (co 5000 punktów nowa trasa), a potem są usuwane z zegarka; klucz API (w ustawieniach profilu na stronie) wpisuje się w Žhavá místa > Web i wysyłanie > Klucz API: UP/DOWN wybiera znak, START dodaje, BACK usuwa, OK na końcu listy zapisuje. Przy instalacji ze Store można też w Garmin Connect. Stan jest w Žhavá místa > Web i wysyłanie > Wysyłanie na web, wybranie ponawia wysyłkę od razu. Pamięć (Žhavá místa > Pamięć): Niewysłane pokazuje, ile punktów czeka na wysłanie (mieści się około 4000). Gdy pełna ustala, co wtedy. Zatrzymać nagrywanie: nagrywanie się kończy. Łączyć najwyżej 1×, 2× lub 3×: z każdych dwóch sąsiednich niewysłanych punktów zostaje ten z wyższą dawką, zwalnia się mniej więcej połowa miejsca i nagrywanie trwa dalej; punkty są wtedy dwa razy dalej od siebie (np. 5 m > 10 m). Te same punkty można łączyć ponownie, najwyżej ustawioną liczbę razy: 1× = odstęp do 2×, 2× = do 4×, 3× = do 8× (przy 5 m więc 10, 20 lub 40 m). Łączyć bez limitu łączy za każdym razem. Gdy nie ma już czego łączyć, nagrywanie kończy się napisem pełno i długą wibracją. Usuń niewysłane usuwa wszystkie punkty, których jeszcze nie ma w sieci. GPS zwiększa zużycie baterii. Punkty zapisują się tylko od wybranej jakości GPS (domyślnie dobra), inaczej na dole jest słaby GPS. Nagrywaj po starcie włącza zapis automatycznie przy każdym uruchomieniu aplikacji. Mapowanie włączone włącza cały moduł; wyłączone go ukrywa."
            ],
            :hRise => ["Hlídání nárůstu", "Rise detection", "Wykrywanie wzrostu"],
            :hRiseT => [
                "Měkký alarm hlídá prudký nárůst cps proti pozadí z posledních ~20 s. Citlivost určuje, o kolik procent musí cps vyskočit (30, 50, 100 % nebo vlastní hodnota); nárůst musí být zároveň statisticky významný, aby nespouštěl na šumu. Projeví se stejnými prvky jako ostatní alarmy, jen jemněji, a nahoře je Prudký nárůst. Je-li v Projevu alarmu zapnutá Červená svítilna, bliká po celou dobu alarmu (i při děličce 1:1). Trvá-li nová úroveň přes minutu, bere se jako nové pozadí.",
                "The soft alarm watches for a sharp rise in cps above the background of the last ~20 s. Sensitivity sets how many percent cps must jump (30, 50, 100 % or a custom value); the rise must also be statistically significant so noise does not trigger it. It uses the same signals as the other alarms, only softer, and Rapid rise is shown at the top. If Red flashlight is on in Alarm output, it blinks for the whole alarm (even at divider 1:1). If the new level lasts over a minute, it becomes the new background.",
                "Miękki alarm wykrywa gwałtowny wzrost cps ponad tło z ostatnich ~20 s. Czułość określa, o ile procent cps musi wzrosnąć (30, 50, 100 % lub własna wartość); wzrost musi być też istotny statystycznie, aby szum go nie wyzwalał. Używa tych samych sygnałów co inne alarmy, tylko łagodniej, a u góry pojawia się Gwałtowny wzrost. Jeśli w Sygnalizacji alarmu włączona jest Czerwona latarka, miga przez cały czas alarmu (także przy dzielniku 1:1). Jeśli nowy poziom trwa ponad minutę, staje się nowym tłem."
            ],
        };
    }
}
