// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Sdileny stav mereni. Aktualizuje ho BleManager, kresli RaysidView.
function clamp(v as Number, lo as Number, hi as Number) as Number {
    return v < lo ? lo : (v > hi ? hi : v);
}

// Zapis do uloziste aplikace, ktery pri plnem ulozisti nespadne
// (vrati false; volajici muze nahravani zastavit)
function put(key as String, value as Storage.ValueType) as Boolean {
    try {
        Storage.setValue(key, value);
        return true;
    } catch (e) {
        return false;
    }
}

class RaysidState {
    var status as Symbol = :stStart;   // klic prekladu (Tr), preklada se az pri kresleni
    var statusArg as String = "";       // pripadny kod chyby za stavem
    var deviceName as String? = null;
    var doseRate as Float? = null;     // uSv/h
    var cps as Float? = null;          // impulzy za sekundu
    var battery as Float? = null;      // baterie Raysidu v %
    // Nastaveni v Raysidu podle jeho posledniho hlaseni (null = zatim neprislo)
    var devDiv as Number? = null;
    var devSound as Boolean? = null;
    var devDoseAl as Boolean? = null;
    var devCpsAl as Boolean? = null;
    var lastUpdate as Number? = null;  // System.getTimer() ms
    var packets as Number = 0;
    var lastRaw as String = "";        // hex posledniho paketu (debug)
    var showDebug as Boolean = false;
    var devOvl as Boolean? = null;     // priznak pretizeni od Raysidu (null = neprisel)

    // Nastaveni (ukladaji se mezi spustenimi)
    var backlight as Boolean = false;  // displej sviti po celou dobu behu
    var sound as Boolean = false;      // pipani podle cps
    var led as Boolean = false;        // bliknuti svitilnou podle cps
    var divider as Number = 10;        // 1 pipnuti na N impulzu
    var divLink as Boolean = false;    // delicka hodinek svazana s delickou Raysidu
    var overload as Boolean = false;   // pipak docasne vypnut kvuli vysokemu cps
    var vibeOver as Boolean = false;   // vibrace k impulzum nad limitem motoru (4/s)
    var chartSec as Number = 30;       // delka grafu v sekundach (10 az 60)
    var swapMain as Boolean = false;   // hlavni obrazovka: cps velke nahore, davka pod nim
    var vibrate as Boolean = false;    // vibrace k impulzum (jen do VIBE_MAX_RATE za sekundu)
    var alarmSound as Boolean = true;  // ton u alarmu
    var alarmVibe as Boolean = true;   // vibrace u alarmu
    var alarmFlash as Boolean = true;  // probliknuti obrazovky u alarmu
    var alarmRedLed as Boolean = true; // cervena svitilna behem alarmu (pri zapnutem blikani)
    var alarmLen as Number = 1;        // delka alarmu: 0 kratky, 1 stredni, 2 dlouhy
    var alarmsOn as Boolean = true;    // hlavni vypinac vsech alarmu
    var doseOn as Boolean = false;
    var alarmDose as Float = 1.0;      // mez alarmu davky v uSv/h
    var cpsOn as Boolean = false;
    var alarmCps as Number = 1000;     // mez alarmu cps
    var softOn as Boolean = false;
    var softPct as Number = 50;        // citlivost hlidani narustu v % nad pozadim

    var hardAlarm as Boolean = false;
    var softAlarm as Boolean = false;
    var flashUntil as Number = 0;      // do kdy problikava obrazovka (System.getTimer)
    var flashColor as Number = 0xFF0000;

    // Probihajici signalizace alarmu: zbyvajici davky, druh (1 mekky, 2 pevny), cas dalsi davky
    var seqLeft as Number = 0;
    var seqKind as Number = 0;
    var seqNext as Number = 0;

    var page as Number = 0;            // 0 = hodnoty, 1 = graf, 2 = mapovani
    var intervalMs as Float? = null;   // prumerny interval mezi merenimi z Raysidu
    var lastIntervalMs as Number? = null;
    var ovl as Boolean = false;       // nektera velicina v OVL (body se nezapisuji)
    var cpsOvlOn as Boolean = false;  // cps v OVL: drzi, dokud davka neklesne pod OVL_RESET_DOSE
    var doseOvlOn as Boolean = false; // davka nad OVL_DOSE: drzi, dokud neklesne pod OVL_DOSE_RESET
    // Prumerovani zobrazenych hodnot: 0 okamzite, 1 podle casu, 2 podle poctu mereni.
    // Uklada se jen surove mereni; prumer se pocita pri kresleni, takze zmena
    // nastaveni se hned projevi i v celem grafu. Alarmy, cvakani a body
    // mapovani pouzivaji vzdy okamzite hodnoty.
    var avgMode as Number = 0;
    var avgSec as Number = 10;
    var avgN as Number = 5;
    var smDose as Array<Float> = new Array<Float>[HIST];   // prumerovane hodnoty pro graf
    var smCps as Array<Float> = new Array<Float>[HIST];
    var typeInfo as String = "";       // pocty prijatych typu paketu (debug)

    // Historie pro graf: kruhovy buffer, plni se vzdy (je levny),
    // kresli se jen kdyz je graf na obrazovce.
    // 600 mereni: pri ~0,25 s mezi merenimi asi 2,5 min, na 60s graf staci
    const HIST = 600;
    var histT as Array<Number> = new Array<Number>[HIST];
    var histDose as Array<Float> = new Array<Float>[HIST];
    var histCps as Array<Float> = new Array<Float>[HIST];
    var histAlarm as Array<Number> = new Array<Number>[HIST];   // 0 nic, 1 mekky, 2 pevny alarm
    var histHead as Number = 0;        // index dalsiho zapisu
    var histCount as Number = 0;

    function initialize() {
        backlight = load("bl", backlight) as Boolean;
        sound = load("snd", sound) as Boolean;
        led = load("led", led) as Boolean;
        divider = load("div", divider) as Number;
        divLink = load("dvL", divLink) as Boolean;
        // Starsi vlastni hodnota: nejblizsi z nabidky (1, 5, 10, 20, 50, 100, 250)
        var best = 1;
        for (var i = 0; i < DIVIDERS.size(); i++) {
            var d = DIVIDERS[i] as Number;
            if ((d - divider).abs() < (best - divider).abs()) {
                best = d;
            }
        }
        if (best != divider) {
            divider = best;
        }
        chartSec = load("cw", chartSec) as Number;
        swapMain = load("swap", swapMain) as Boolean;
        avgMode = load("avM", avgMode) as Number;
        avgSec = load("avS", avgSec) as Number;
        avgN = load("avN", avgN) as Number;
        // Poskozena nebo stara hodnota by shodila menu (index mimo pole)
        avgMode = clamp(avgMode, 0, 2);
        avgSec = clamp(avgSec, 2, 60);
        avgN = clamp(avgN, 2, 30);
        // Starsi verze mely i jine rozsahy; povolene jsou 10 az 60 s
        if (chartSec > 60) {
            chartSec = 60;
        } else if (chartSec < 10) {
            chartSec = 10;
        }
        vibrate = load("vib", vibrate) as Boolean;
        // Starsi verze mely 0 = vypnuto primo v hodnote; prevedeme na vypinace
        var sl = load("sl", 2) as Number;
        softOn = load("slOn", sl > 0) as Boolean;
        softPct = clamp(load("sp", [50, 30, 50, 100][sl < 0 || sl > 3 ? 0 : sl] as Number) as Number, 10, 300);
        alarmSound = load("aSnd", alarmSound) as Boolean;
        alarmVibe = load("aVib", alarmVibe) as Boolean;
        alarmFlash = load("aFl", alarmFlash) as Boolean;
        alarmRedLed = load("aRed", alarmRedLed) as Boolean;
        alarmLen = clamp(load("aLen", alarmLen) as Number, 0, 2);
        // Uklid zrusene zalozni logu z buildu 68
        if (Storage.getValue("lgI") != null) {
            for (var i = 0; i < 20; i++) {
                Storage.deleteValue("lg" + i);
            }
            Storage.deleteValue("lgI");
        }
        var ac = load("ac", alarmCps) as Number;
        cpsOn = load("acOn", ac > 0) as Boolean;
        alarmCps = ac > 0 ? clamp(ac, 5, ALARM_CPS_MAX) : 1000;
        var ad = Storage.getValue("ad");
        var adv = ad instanceof Float ? ad : (ad instanceof Number ? ad.toFloat() : alarmDose);
        doseOn = load("adOn", ad != null && adv > 0.0) as Boolean;
        alarmDose = adv > 0.0 ? (adv > ALARM_DOSE_MAX ? ALARM_DOSE_MAX : (adv < 0.05 ? 0.05 : adv)) : 1.0;
        alarmsOn = load("aOn", alarmsOn) as Boolean;
        // Jazyk: pri prvnim spusteni podle jazyka hodinek (cestina, polstina, jinak anglictina)
        var sysLang = System.getDeviceSettings().systemLanguage;
        var defLang = sysLang == System.LANGUAGE_CES ? 0 : (sysLang == System.LANGUAGE_POL ? 2 : 1);
        Tr.lang = clamp(load("lang", defLang) as Number, 0, 2);
    }

    // Skutecne platne meze (0 = alarm neaktivni)
    function doseLimit() as Float {
        return alarmsOn && doseOn ? alarmDose : 0.0;
    }

    function cpsLimit() as Number {
        return alarmsOn && cpsOn ? alarmCps : 0;
    }

    // Pomerny narust nad pozadim pro mekky alarm, 0 = vypnuto
    function softFactor() as Float {
        return alarmsOn && softOn ? softPct / 100.0 : 0.0;
    }

    // Zahaji signalizaci alarmu; pocet davek podle nastavene delky
    function startAlarm(kind as Number, now as Number) as Void {
        var bursts = [1, 3, 8];
        seqKind = kind;
        seqLeft = bursts[alarmLen < 0 || alarmLen > 2 ? 1 : alarmLen] as Number;
        seqNext = now;
    }

    function addSample(t as Number, dose as Float, cps as Float, alarm as Number) as Void {
        histAlarm[histHead] = alarm;
        histT[histHead] = t;
        histDose[histHead] = dose;
        histCps[histHead] = cps;
        histHead = (histHead + 1) % HIST;
        if (histCount < HIST) {
            histCount++;
        }
    }

    // Prumer davky a cps k mereni na indexu i historie: podle casu (mereni za
    // poslednich avgSec s) nebo podle poctu (poslednich avgN mereni)
    // capMs omezuje okno prumeru (v grafu podle jeho delky)
    function smoothAt(i as Number, capMs as Number) as Array<Float> {
        var t0 = histT[i] as Number;
        var sd = 0.0;
        var sc = 0.0;
        var n = 0;
        var back = (histHead - 1 - i + HIST) % HIST;   // kolik mereni je novejsich
        for (var k = 0; back + k < histCount; k++) {
            var j = (i - k + HIST) % HIST;
            var age = t0 - (histT[j] as Number);
            if (n > 0 && (age >= capMs || (avgMode == 1 ? age >= avgSec * 1000 : n >= avgN))) {
                break;
            }
            sd += histDose[j] as Float;
            sc += histCps[j] as Float;
            n++;
        }
        return [sd / n, sc / n] as Array<Float>;
    }

    // Naplni smDose/smCps pro mereni novejsi nez tMin. Klouzave okno se
    // posouva jednim pruchodem (kazde mereni se pricte a odecte jen jednou),
    // aby kresleni grafu nevycerpalo casovy limit hodinek (watchdog).
    function smooth(tMin as Number, capMs as Number) as Void {
        var lim = capMs;
        if (avgMode == 1 && avgSec * 1000 < lim) {
            lim = avgSec * 1000;
        }
        // Kolik mereni je potreba: okno grafu plus delka prumeru pred nim
        var m = 0;
        while (m < histCount && (histT[(histHead - 1 - m + HIST) % HIST] as Number) >= tMin - lim) {
            m++;
        }
        var sd = 0.0;
        var sc = 0.0;
        var n = 0;
        var kl = m - 1;   // nejstarsi mereni v okne
        for (var k = m - 1; k >= 0; k--) {
            var i = (histHead - 1 - k + HIST) % HIST;
            var t = histT[i] as Number;
            if (avgMode == 0) {
                if (t >= tMin) {
                    smDose[i] = histDose[i];
                    smCps[i] = histCps[i];
                }
                continue;
            }
            sd += histDose[i] as Float;
            sc += histCps[i] as Float;
            n++;
            while (n > 1) {
                var j = (histHead - 1 - kl + HIST) % HIST;
                if (t - (histT[j] as Number) < lim && (avgMode != 2 || n <= avgN)) {
                    break;
                }
                sd -= histDose[j] as Float;
                sc -= histCps[j] as Float;
                n--;
                kl--;
            }
            if (t >= tMin) {
                smDose[i] = sd / n;
                smCps[i] = sc / n;
            }
        }
    }

    // Spicka cps (a davka v ni) pred zahlcenim, k ni se porovnava navrat
    private var _ovlPeak as Float = 0.0;
    private var _ovlPeakDose as Float = 0.0;
    private var _ovlOk as Number = 0;     // kolik mereni po sobe vypada jako navrat
    private var _ovlPrevDose as Float = 0.0;
    private var _ovlPrevCps as Float = 0.0;
    private var _ovlSame as Number = 0;
    private var _pk as Float = 0.0;       // spicka z posledniho cpsDropped
    private var _pkD as Float = 0.0;

    // Zapne OVL pri prekroceni meze nebo pri prudkem poklesu cps, ktery
    // davka nenasleduje. Vypne ho navrat pres spicku (cps zase vystoupaly
    // skoro na spicku a davka klesla na svou uroven ve spicce, OVL_EXIT_N
    // mereni po sobe), nebo davka pod OVL_RESET_DOSE. Vola se pred ulozenim
    // noveho mereni do historie.
    function updateOvl(now as Number, dose as Float, cps as Float) as Void {
        // cps: strop nebo prudky pokles; davka se dal ukazuje (Raysid ji
        // pocita i pri zahlcenych cps)
        // Raysid sam hlasi pretizeni (stejne jako jeho cervena LED); vlastni
        // odhad z prubehu cps a davky jen kdyz priznak neposila
        if (devOvl != null) {
            cpsOvlOn = devOvl as Boolean;
            if (dose > OVL_DOSE) {
                doseOvlOn = true;
            } else if (doseOvlOn && dose < OVL_DOSE_RESET) {
                doseOvlOn = false;
            }
            ovl = cpsOvlOn || doseOvlOn;
            return;
        }
        var hit = cpsDropped(now, dose, cps) || (OVL_CPS_ON && cps > OVL_CPS);
        if (hit && !cpsOvlOn) {
            cpsOvlOn = true;
            _ovlPeak = _pk;
            _ovlPeakDose = _pkD;
            _ovlOk = 0;
            _ovlSame = 0;
            _ovlPrevCps = cps;
            _ovlPrevDose = dose;
        } else if (cpsOvlOn && !hit) {
            // Pri zahlceni cps klesaji a davka roste; pri odchodu ze zahlceni
            // naopak cps stoupaji a davka klesa. Navrat = cps zpet u spicky pri
            // davce nejvys jako ve spicce; potvrzeni dalsim merenim, kdy davka
            // zustala dole (cps uz pak smi klesat spolu s ni)
            // Davka v Raysidu se zpozduje (pri nabehu zustane ve spicce nizko,
            // pri odchodu chvili drzi vys), proto jen volna mez OVL_EXIT_DOSE a
            // potvrzeni dalsim merenim, ze davka uz neroste
            var lowDose = dose <= _ovlPeakDose * OVL_EXIT_DOSE;
            var nearPeak = cps >= _ovlPeak * OVL_EXIT_CPS;
            var notRising = _ovlOk == 0 || dose <= _ovlPrevDose * 1.05;
            // Pri rychlem odchodu cps spicku hned preskoci a klesaji spolu s
            // davkou: druhe mereni proto staci s klesajici davkou
            var back = _ovlPeak > 0.0 && lowDose && notRising
                && (nearPeak || (_ovlOk > 0 && dose < _ovlPrevDose));
            _ovlOk = back ? _ovlOk + 1 : 0;
            // Druhy zpusob: cps a davka se hybou stejnym smerem (obe klesaji
            // nebo obe rostou) OVL_SAME_N mereni po sobe. Pri zahlceni jdou
            // vzdy proti sobe, takze tohle nastane az mimo nej.
            var same = _ovlPrevCps > 0.0 && ((cps < _ovlPrevCps * (1.0 - OVL_SAME_STEP) && dose < _ovlPrevDose)
                || (cps > _ovlPrevCps * (1.0 + OVL_SAME_STEP) && dose > _ovlPrevDose));
            _ovlSame = same ? _ovlSame + 1 : 0;
            _ovlPrevDose = dose;
            _ovlPrevCps = cps;
            if (_ovlOk >= OVL_EXIT_N || _ovlSame >= OVL_SAME_N || dose < OVL_RESET_DOSE) {
                cpsOvlOn = false;
            }
        }
        // davka: nad 999 uSv/h se nikdy neukaze cislo
        if (dose > OVL_DOSE) {
            doseOvlOn = true;
        } else if (doseOvlOn && dose < OVL_DOSE_RESET) {
            doseOvlOn = false;
        }
        ovl = cpsOvlOn || doseOvlOn;
    }

    // Spicka cps v poslednich OVL_DROP_MS a davka v ni proti aktualnimu mereni
    private function cpsDropped(now as Number, dose as Float, cps as Float) as Boolean {
        var peak = 0.0;
        var peakDose = 0.0;
        for (var k = 0; k < histCount; k++) {
            var i = (histHead - 1 - k + HIST) % HIST;
            if (now - (histT[i] as Number) > OVL_DROP_MS) {
                break;
            }
            if ((histCps[i] as Float) > peak) {
                peak = histCps[i] as Float;
                peakDose = histDose[i] as Float;
            }
        }
        _pk = peak;
        _pkD = peakDose;
        // Pod OVL_RESET_DOSE zahlceni nehrozi (falesne OVL po odchodu od zdroje,
        // kdy cps klesaji rychleji nez opozdena davka)
        if (peak < OVL_DROP_MIN_CPS || peakDose <= 0.0 || dose < OVL_RESET_DOSE) {
            return false;
        }
        var rc = cps / peak;
        var rd = dose / peakDose;
        return (rc <= OVL_FAST_CPS && rd >= OVL_FAST_DOSE) || (rc <= OVL_DROP_CPS && rd >= rc * OVL_DROP_GAP && rd >= 1.0);
    }

    // Prumer davky a cps za mereni novejsi nez tFrom (ms systemoveho casovace),
    // vzdy aspon z posledniho mereni; pro body mapovani nezavisle na nastaveni
    function avgSince(tFrom as Number) as Array<Float>? {
        var sd = 0.0;
        var sc = 0.0;
        var n = 0;
        for (var k = 0; k < histCount; k++) {
            var i = (histHead - 1 - k + HIST) % HIST;
            if (n > 0 && (histT[i] as Number) <= tFrom) {
                break;
            }
            sd += histDose[i] as Float;
            sc += histCps[i] as Float;
            n++;
        }
        return n == 0 ? null : [sd / n, sc / n] as Array<Float>;
    }

    // Zobrazovane hodnoty: okamzite, nebo prumer podle nastaveni
    function shownDose() as Float? {
        if (avgMode == 0 || histCount == 0 || doseRate == null) {
            return doseRate;
        }
        return smoothAt((histHead - 1 + HIST) % HIST, 60000)[0];
    }

    function shownCps() as Float? {
        if (avgMode == 0 || histCount == 0 || cps == null) {
            return cps;
        }
        return smoothAt((histHead - 1 + HIST) % HIST, 60000)[1];
    }

    // Ulozena hodnota stejneho typu jako vychozi; jinak (chybi, poskozena) vychozi
    private function load(key as String, def as Boolean or Number) as Boolean or Number {
        var v = Storage.getValue(key);
        if (def instanceof Boolean) {
            return v instanceof Boolean ? v : def;
        }
        return v instanceof Number ? v : def;
    }

    function save() as Void {
        put("bl", backlight);
        put("snd", sound);
        put("led", led);
        put("div", divider);
        put("dvL", divLink);
        put("cw", chartSec);
        put("swap", swapMain);
        put("avM", avgMode);
        put("avS", avgSec);
        put("avN", avgN);
        put("vib", vibrate);
        put("sp", softPct);
        put("aSnd", alarmSound);
        put("aVib", alarmVibe);
        put("aFl", alarmFlash);
        put("aRed", alarmRedLed);
        put("aLen", alarmLen);
        put("ac", alarmCps);
        put("ad", alarmDose);
        put("aOn", alarmsOn);
        put("adOn", doseOn);
        put("acOn", cpsOn);
        put("slOn", softOn);
        put("lang", Tr.lang);
    }
}

class RaysidApp extends Application.AppBase {
    var state as RaysidState;
    var ble as BleManager;
    var clicker as Clicker;
    var recorder as Recorder;
    var uploader as Uploader;

    function initialize() {
        AppBase.initialize();
        state = new RaysidState();
        ble = new BleManager(state);
        clicker = new Clicker(state);
        uploader = new Uploader();
        recorder = new Recorder(state);
    }

    function onStart(params as Dictionary?) as Void {
        BluetoothLowEnergy.setDelegate(ble);
        ble.start();
        clicker.start();
        recorder.resume();
        uploader.start();
    }

    function onStop(params as Dictionary?) as Void {
        clicker.stop();
        uploader.stop();
        recorder.suspend();
        ble.stop();
    }

    // Klic nebo prepinac odesilani zmeneny v Garmin Connect
    function onSettingsChanged() as Void {
        uploader.settingsChanged();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new RaysidView(state), new RaysidDelegate(state, ble)];
    }
}
