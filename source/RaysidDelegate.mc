// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Menu se otevira jen tlacitkem START. Dotyk, swipe ani podrzeni UP nic nedelaji.
class RaysidDelegate extends WatchUi.BehaviorDelegate {
    private var _state as RaysidState;
    private var _ble as BleManager;

    function initialize(state as RaysidState, ble as BleManager) {
        BehaviorDelegate.initialize();
        _state = state;
        _ble = ble;
    }

    // START na fenixu chodi podle firmwaru bud jako onKey(KEY_ENTER), nebo jako
    // onSelect. Klepnuti na displej vola taky onSelect, proto ho podle casu
    // posledniho dotyku odfiltrujeme.
    private var _lastTap as Number = -10000;

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        // Jakekoli tlacitko behem zvoneni alarmu ho jen umlci
        if (_state.seqLeft > 0) {
            _state.seqLeft = 0;
            return true;
        }
        if (keyEvent.getKey() == WatchUi.KEY_ENTER) {
            openMenu();
            return true;
        }
        return false;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        _lastTap = System.getTimer();
        return true;
    }

    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean {
        return true;
    }

    // DOWN prepina mezi hodnotami, grafem a (pri zapnutem mapovani)
    // obrazovkou mapovani
    function onNextPage() as Boolean {
        // Ladici obrazovka prekryva vsechny stranky: tlacitka nic nedelaji,
        // at se skryte nic nezmeni (napr. nespusti nahravani)
        if (_state.showDebug) {
            return true;
        }
        return switchPage(1);
    }

    // UP ma na kazde obrazovce vlastni akci: hlavni obrazovka prohodi davku
    // a cps, graf prepne delku, mapovani zapne nebo pozastavi nahravani
    function onPreviousPage() as Boolean {
        if (_state.showDebug) {
            return true;
        }
        if (_state.page == 0) {
            _state.swapMain = !_state.swapMain;
            put("swap", _state.swapMain);
        } else if (_state.page == 1) {
            var i = CHART_LENGTHS.indexOf(_state.chartSec);
            _state.chartSec = CHART_LENGTHS[(i + 1) % CHART_LENGTHS.size()] as Number;
            put("cw", _state.chartSec);
        } else if (_state.page == 2) {
            var r = recorder();
            if (r.on) {
                r.pause();
            } else {
                r.start();
            }
        }
        WatchUi.requestUpdate();
        return true;
    }

    // Nova obrazovka vyjede zdola (DOWN = dalsi), aby prepnuti nebylo trhane
    private function switchPage(step as Number) as Boolean {
        var n = recorder().enabled ? 3 : 2;
        _state.page = (_state.page + step + n) % n;
        WatchUi.switchToView(new RaysidView(_state), new RaysidDelegate(_state, _ble),
            step > 0 ? WatchUi.SLIDE_UP : WatchUi.SLIDE_DOWN);
        return true;
    }

    function onSelect() as Boolean {
        if (System.getTimer() - _lastTap > 700) {
            openMenu();
        }
        return true;
    }

    function onMenu() as Boolean {
        return true;
    }

    private function openMenu() as Void {
        var menu = new WatchUi.Menu2({:title => "Raysid"});
        // Podle predpokladane cetnosti pouziti: nejcastejsi nahore
        // Signalizace a Alarmy jsou v hodinkach, Raysid je vse ulozene v dozimetru
        menu.addItem(new WatchUi.MenuItem(Tr.t(:mSignal), Tr.t(:inWatch), :mSignal, null));
        menu.addItem(new WatchUi.MenuItem(Tr.t(:mAlarms), alarmsLabel(_state), :mAlarms, null));
        menu.addItem(new WatchUi.MenuItem(Tr.t(:mDevice), Tr.t(_state.status), :mDevice, null));
        menu.addItem(new WatchUi.MenuItem(Tr.t(:mDisplay), null, :mDisplay, null));
        menu.addItem(new WatchUi.MenuItem(Tr.t(:mRecord), recordLabel(), :mRecord, null));
        menu.addItem(new WatchUi.MenuItem(Tr.t(:mHelp), null, :mHelp, null));
        menu.addItem(new WatchUi.MenuItem(Tr.t(:mLanguage), Tr.t(:langName), :mLanguage, null));
        WatchUi.pushView(menu, new RaysidMenuDelegate(_state, _ble, null), WatchUi.SLIDE_UP);
    }
}

// Delicka hodinek i Raysidu: jen hodnoty, ktere nabizi aplikace Raysid
const DIVIDERS = [1, 5, 10, 20, 50, 100, 250];
// Delicka primo v Raysidu: hodnoty jako v oficialni aplikaci

const CHART_LENGTHS = [10, 20, 30, 60];
const AVG_MODE_KEYS = [:avgOff, :avgTime, :avgCount];
const AVG_SECS = [2, 4, 6, 10];
const AVG_COUNTS = [2, 3, 5, 10, 20];
const AVG_SEC_MAX = 60;     // strop vlastni hodnoty (historie v pameti je 600 mereni)
const AVG_COUNT_MAX = 30;
const DOSE_LIMITS = [0.3, 0.5, 1.0, 2.0, 5.0, 10.0, 50.0, 100.0, 500.0];
const CPS_LIMITS = [50, 100, 200, 500, 1000, 2000, 3000, 5000];
// Meze alarmu jen pod pretizenim: Raysid hlasi OVL cps od ~5,4-5,8 kcps
// (log 14. 10. 2026), davka je OVL nad OVL_DOSE
const ALARM_CPS_MAX = 5000;
const ALARM_DOSE_MAX = 999.0;
const LANG_NAMES = ["Čeština", "English", "Polski"];
const SENS_KEYS = [:sens1, :sens2, :sens3];
const SENS_PCTS = [30, 50, 100];
const ALARM_LEN_KEYS = [:lenShort, :lenMedium, :lenLong];
const CUSTOM_ID = -1;
const REC_DISTS = [5, 8, 10, 12, 15];
const GPS_QUALS = [4, 3, 2];   // Position.QUALITY_GOOD, USABLE, POOR
const GPS_QUAL_KEYS = [:qGood, :qUsable, :qPoor];
// Kolikrat smi byt bod pri plnem ulozisti sloucen (99 = bez omezeni)
const CMP_OPTS = [0, 1, 2, 3, 99];

function cmpLabel(n as Number) as String {
    if (n <= 0) {
        return Tr.t(:cmpStop);
    }
    return n >= 99 ? Tr.t(:cmpAny) : Tr.t(:cmpMaxN) + " " + n + "×";
}

// Popisek s nejvetsim rozestupem bodu po slouceni (kazde slouceni ho zdvojnasobi)
function cmpSubLabel(n as Number, dist as Number) as String {
    if (n <= 0 || n >= 99) {
        return cmpLabel(n);
    }
    return Tr.t(:cmpMaxS) + " " + n + "×, " + Tr.t(:cmpUpTo) + " " + (dist << n) + " m";
}

function storeLabel() as String {
    var r = recorder();
    return r.count + " " + Tr.t(:points) + " (" + (r.count * 100 / r.MAX_POINTS) + " %)";
}

function qualLabel(q as Number) as String {
    var i = GPS_QUALS.indexOf(q);
    return Tr.t(GPS_QUAL_KEYS[i < 0 ? 0 : i] as Symbol);
}
const HELP_TOPICS = [:hControls, :hScreens, :hRecord, :hSignal, :hAlarms, :hRise, :hAbout];
const HELP_TEXTS = [:hControlsT, :hScreensT, :hRecordT, :hSignalT, :hAlarmsT, :hRiseT, :hAbout];

// Text O aplikaci: verze a datum buildu z BuildInfo.mc (generuje build.sh)
function aboutText() as String {
    return "Raysid Garmin " + APP_VERSION + " \n " + Tr.t(:aboutBuild) + " " + BUILD_NUM + " (" + BUILD_DATE + "), © " + APP_YEAR
        + " \n \n " + Tr.t(:aboutAuthor) + ": Vít Cenek \n vitcenek@gmail.com"
        + " \n \n " + Tr.t(:aboutCo) + ": Claude (Anthropic)"
        + " \n \n Žhavá místa: zhavamista.cz \n Raysid: raysid.com";
}

// Popisek prumerovani ("10 s" nebo "5x"), null pri okamzitych hodnotach
function avgLabel(state as RaysidState) as String? {
    if (state.avgMode == 1) {
        return Tr.t(:avgShort) + " " + state.avgSec + " s";
    } else if (state.avgMode == 2) {
        return Tr.t(:avgShort) + " " + state.avgN + "x";
    }
    return null;
}

function avgSpanLabel(state as RaysidState) as String {
    return state.avgMode == 1 ? state.avgSec + " s" : state.avgN + " " + Tr.t(:avgMeas);
}

// Podmenu Displej: nahore prumerovani, pri okamzitych hodnotach bez delky
function displayMenu(state as RaysidState) as WatchUi.Menu2 {
    var m = new WatchUi.Menu2({:title => Tr.t(:mDisplay)});
    m.addItem(new WatchUi.MenuItem(Tr.t(:avgMode), Tr.t(AVG_MODE_KEYS[state.avgMode] as Symbol), :avgMode, null));
    if (state.avgMode != 0) {
        m.addItem(new WatchUi.MenuItem(Tr.t(:avgSpan), avgSpanLabel(state), :avgSpan, null));
    }
    m.addItem(new WatchUi.ToggleMenuItem(Tr.t(:backlight), null, :backlight, state.backlight, null));
    m.addItem(new WatchUi.ToggleMenuItem(Tr.t(:debug), null, :debug, state.showDebug, null));
    return m;
}

// Polozka skupiny alarmu, ze ktere je otevrene podmenu (pro obnovu popisku)
var gGroupItem as WatchUi.MenuItem? = null;

// Popisek skupiny alarmu: zapnuto/vypnuto a mez
function alarmGroupLabel(state as RaysidState, id as Symbol) as String {
    if (id == :gDose) {
        return onOff(state.doseOn) + ", " + doseLabel(state.alarmDose);
    } else if (id == :gCps) {
        return onOff(state.cpsOn) + ", " + cpsLabel(state.alarmCps);
    }
    return onOff(state.softOn) + ", " + pctLabel(state.softPct);
}

function refreshGroup(state as RaysidState) as Void {
    var it = gGroupItem;
    if (it != null) {
        it.setSubLabel(alarmGroupLabel(state, it.getId() as Symbol));
    }
}

function onOff(v as Boolean) as String {
    return Tr.t(v ? :on : :off);
}

// Popisek polozky Zaznam: zapnuto/vypnuto a pocet bodu
function recordLabel() as String {
    var r = recorder();
    if (!r.enabled) {
        return Tr.t(:mapOff) + (r.count > 0 ? ", " + Tr.t(:upQueue) + " " + r.count : "");
    }
    return (r.full ? Tr.t(:recFull) : (r.paused ? Tr.t(:recPauseUp) : onOff(r.on))) + ", " + r.count + " " + Tr.t(:points);
}

// Hlavni menu Alarmy: zapnuto jen kdyz je zapnuty aspon jeden alarm
function alarmsLabel(state as RaysidState) as String {
    return onOff(state.alarmsOn && (state.doseOn || state.cpsOn || state.softOn));
}

// Obnovi popisek polozky po navratu z jejiho podmenu (stav se mezitim
// mohl zmenit: overeni webu, smazani, alarmy, pripojeni)
function refreshItem(state as RaysidState, ble as BleManager, item as WatchUi.MenuItem) as Void {
    var id = item.getId();
    if (id == :mRecord) {
        item.setSubLabel(recordLabel());
    } else if (id == :mWeb) {
        item.setSubLabel(uploader().verifyLabel());
    } else if (id == :mStorage) {
        item.setSubLabel(storeLabel());
    } else if (id == :mAlarms) {
        item.setSubLabel(alarmsLabel(state));
    } else if (id == :mConn) {
        item.setSubLabel(connLabel(ble));
    } else if (id == :mDevice) {
        item.setSubLabel(Tr.t(state.status));
    } else if (id == :gDose || id == :gCps || id == :gRise) {
        item.setSubLabel(alarmGroupLabel(state, id as Symbol));
    }
}

// Popisek polozky Pripojeni: vybrany Raysid, pripadne zamek
function connLabel(ble as BleManager) as String {
    var p = ble.pin;
    if (p == null) {
        return Tr.t(:devAny);
    }
    return (ble.lock ? Tr.t(:devOnly) + " " : "") + p;
}

const CONN_PREF_KEYS = [:prefKnown, :prefStrong];

function dividerLabel(n as Number) as String {
    return "1:" + n;
}

// Delicka Raysidu; pri sloucene delicce plati poznamka i pro hodinky
function devDivLabel(state as RaysidState, n as Number) as String {
    return state.divLink ? watchDivLabel(n) : dividerLabel(n);
}

// Delicka hodinek: pri 1:1 se signalizace vypne, zustanou jen alarmy
function watchDivLabel(n as Number) as String {
    return n <= 1 ? "1:1 " + Tr.t(:div1Note) : "1:" + n;
}

function doseLabel(v as Float) as String {
    // Tolik mist, aby byla videt i vlastni mez (napr. 0.05 nebo 1.5)
    var s = v.format("%.2f");
    if (s.find(".") != null) {
        while ((s.substring(s.length() - 1, s.length()) as String).equals("0")) {
            s = s.substring(0, s.length() - 1) as String;
        }
        if ((s.substring(s.length() - 1, s.length()) as String).equals(".")) {
            s = s.substring(0, s.length() - 1) as String;
        }
    }
    return s + " uSv/h";
}

function cpsLabel(v as Number) as String {
    return v + " cps";
}

// Pretizeni Raysidu: nad temito okamzitymi hodnotami se misto cisla
// ukaze OVL. Predbezne podle mereni, upresnit u vyrobce. Stav OVL drzi
// (state.cpsOvlOn / doseOvlOn), viz RaysidState.updateOvl.
const OVL_CPS = 7200.0;        // cps
const OVL_CPS_ON = false;      // strop cps vypnuty na test (Vit, 14.10.2026), true = vratit
const OVL_DOSE = 999.0;        // uSv/h, nad tuto mez se nikdy nic neukaze
const OVL_RESET_DOSE = 10.0;   // uSv/h, konec OVL u cps
const OVL_DOSE_RESET = 900.0;  // uSv/h, konec OVL u davky (hystereze pod 999)
// Zahlceni podle poklesu: cps byly v poslednich OVL_DROP_MS aspon
// OVL_DROP_MIN_CPS, pak spadly nejvys na OVL_DROP_CPS jejich spicky a davka
// proti tomu klesla aspon OVL_DROP_GAP-krat mene (pomer davka/cps vyskocil).
// Pri vzdalovani od zdroje klesa davka i cps stejne, takze se nespusti.
// Odhad, doladit podle mereni se zdrojem.
const OVL_DROP_MS = 10000;
const OVL_DROP_MIN_CPS = 2000.0;
const OVL_DROP_CPS = 0.5;
const OVL_DROP_GAP = 1.5;
// Rychle pravidlo: cps spadly aspon o 10 % spicky a davka pritom stoji,
// klesla nejvys o OVL_FAST_DOSE nebo roste
const OVL_FAST_CPS = 0.90;
const OVL_FAST_DOSE = 0.95;
// Konec OVL u cps: cps zase aspon na OVL_EXIT_CPS spicky pred zahlcenim a
// davka nejvys na OVL_EXIT_DOSE sve hodnoty ve spicce, OVL_EXIT_N mereni po
// sobe. Pojistka: davka pod OVL_RESET_DOSE.
const OVL_EXIT_CPS = 0.9;
const OVL_EXIT_DOSE = 1.3;   // volne: davka Raysidu se zpozduje
const OVL_EXIT_N = 2;
// nebo: cps i davka jdou stejnym smerem (cps aspon o OVL_SAME_STEP za
// mereni) OVL_SAME_N mereni po sobe
const OVL_SAME_STEP = 0.05;
const OVL_SAME_N = 3;

// OVL se ukazuje jen u veliciny, ktera do nej spadla
function cpsOvl(state as RaysidState) as Boolean {
    return state.cpsOvlOn;
}

function doseOvl(state as RaysidState) as Boolean {
    return state.doseOvlOn;
}

// Davka: pod 10 uSv/h na dve desetinna mista (0.12, 1.23), pak 12.3 a 123 uSv/h,
// od 1000 uSv/h stejne v mSv/h (hranice po zaokrouhleni, at nevznikne 1.000)
function doseNum(v as Float?) as String {
    if (v == null) {
        return "--";
    }
    var x = v >= 999.5 ? v / 1000.0 : v;
    if (x < 9.995) {
        return x.format("%.2f");
    } else if (x < 99.95) {
        return x.format("%.1f");
    }
    return x.format("%.0f");
}

function doseUnit(v as Float?) as String {
    return v != null && v >= 999.5 ? "mSv/h" : "uSv/h";
}

// Cps: do 1000 s jednim desetinnym mistem, nad tim kcps jako 1.23,
// nad 10 000 jako 12.3 a nad 100 000 jako 123
function cpsNum(v as Float?) as String {
    if (v == null) {
        return "--";
    }
    if (v < 999.95) {
        return v.format("%.1f");
    }
    var k = v / 1000.0;
    return k.format(k < 9.995 ? "%.2f" : (k < 99.95 ? "%.1f" : "%.0f"));
}

function cpsUnit(v as Float?) as String {
    return v != null && v >= 999.95 ? "kcps" : "cps";
}

function pctLabel(v as Number) as String {
    return "+" + v + " %";
}

// Obsluha hlavniho menu i vsech podmenu. parentItem je polozka nadrazeneho
// menu, ktere se po zmene obnovi popisek (napr. Alarmy: zapnuto).
class RaysidMenuDelegate extends WatchUi.Menu2InputDelegate {
    // Navrat o uroven zpet s posuvnou animaci (vychozi je bez animace);
    // popisek polozky, ze ktere se podmenu otevrelo, se obnovi
    function onBack() as Void {
        var p = _parentItem;
        if (p != null) {
            if (p.getId() == :mDevice) {
                _ble.devMenu = null;
            }
            refreshItem(_state, _ble, p);
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    private var _state as RaysidState;
    private var _ble as BleManager;
    private var _parentItem as WatchUi.MenuItem?;

    function initialize(state as RaysidState, ble as BleManager, parentItem as WatchUi.MenuItem?) {
        Menu2InputDelegate.initialize();
        _state = state;
        _ble = ble;
        _parentItem = parentItem;
    }

    private function push(title as String, items as Array<WatchUi.MenuItem>, parent as WatchUi.MenuItem?) as Void {
        var m = new WatchUi.Menu2({:title => title});
        for (var i = 0; i < items.size(); i++) {
            m.addItem(items[i]);
        }
        WatchUi.pushView(m, new RaysidMenuDelegate(_state, _ble, parent), WatchUi.SLIDE_LEFT);
    }

    // Podmenu Pripojeni: znovu pripojit, vybrany Raysid, zamek, preference
    private function connMenu() as WatchUi.Menu2 {
        var m = new WatchUi.Menu2({:title => Tr.t(:mConn)});
        m.addItem(new WatchUi.MenuItem(Tr.t(:reconnect), _state.deviceName, :reconnect, null));
        m.addItem(new WatchUi.MenuItem(Tr.t(:devPick), _ble.pin != null ? _ble.pin : Tr.t(:devAny), :devPick, null));
        m.addItem(toggle(:devLock, _ble.lock));
        m.addItem(new WatchUi.MenuItem(Tr.t(:connPref), Tr.t(CONN_PREF_KEYS[_ble.pref == 1 ? 1 : 0] as Symbol), :connPref, null));
        return m;
    }

    // Podmenu Zaznam; pri vypnutem mapovani jen samotny vypinac
    private function recordMenu(parent as WatchUi.MenuItem?) as WatchUi.Menu2 {
        var r = recorder();
        var m = new WatchUi.Menu2({:title => Tr.t(:mRecord)});
        m.addItem(toggle(:mapping, r.enabled));
        if (r.enabled) {
            m.addItem(toggle(:autostart, r.autostart));
            m.addItem(new WatchUi.MenuItem(Tr.t(:recDist), r.dist + " m", :recDist, null));
            m.addItem(new WatchUi.MenuItem(Tr.t(:gpsQual), qualLabel(r.minQ), :gpsQual, null));
            m.addItem(new WatchUi.MenuItem(Tr.t(:mWeb), uploader().verifyLabel(), :mWeb, null));
            m.addItem(new WatchUi.MenuItem(Tr.t(:mStorage), storeLabel(), :mStorage, null));
        }
        return m;
    }

    // Prepinac nastaveni Raysidu; dokud Raysid stav nenahlasil, je u nej "?"
    private function devToggle(key as Symbol, value as Boolean?) as WatchUi.ToggleMenuItem {
        return new WatchUi.ToggleMenuItem(Tr.t(key), value == null ? "?" : null, key, value == true, null);
    }

    private function toggle(key as Symbol, value as Boolean) as WatchUi.ToggleMenuItem {
        return new WatchUi.ToggleMenuItem(Tr.t(key), null, key, value, null);
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :reconnect) {
            _ble.restart();
            // Zavrit podmenu Pripojeni, Raysid i hlavni menu
            _ble.devMenu = null;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :apiKey) {
            var v = new KeyEntryView(currentKey());
            // Polozka Overit spojeni je v podmenu hned pod klicem
            var menu = WatchUi.getCurrentView()[0];
            var vi = null;
            var ui = null;
            if (menu instanceof WatchUi.Menu2) {
                var idx = (menu as WatchUi.Menu2).findItemById(:verify);
                vi = idx >= 0 ? (menu as WatchUi.Menu2).getItem(idx) : null;
                idx = (menu as WatchUi.Menu2).findItemById(:upload);
                ui = idx >= 0 ? (menu as WatchUi.Menu2).getItem(idx) : null;
            }
            WatchUi.pushView(v, new KeyEntryDelegate(v, item, vi, ui), WatchUi.SLIDE_LEFT);
        } else if (id == :verify) {
            uploader().startVerify(item);
        } else if (id == :mConn) {
            WatchUi.pushView(connMenu(), new RaysidMenuDelegate(_state, _ble, item), WatchUi.SLIDE_LEFT);
        } else if (id == :devPick) {
            var m = new WatchUi.Menu2({:title => Tr.t(:devPick)});
            m.addItem(new WatchUi.MenuItem(Tr.t(:devAny), null, -1, null));
            var focus = 0;
            for (var i = 0; i < _ble.history.size(); i++) {
                var name = (_ble.history[i] as Array)[0] as String;
                m.addItem(new WatchUi.MenuItem(name, i == 0 ? Tr.t(:devLast) : null, i, null));
                if (_ble.pin != null && name.equals(_ble.pin)) {
                    focus = i + 1;
                }
            }
            m.addItem(new WatchUi.MenuItem(Tr.t(:devForget), null, -2, null));
            m.setFocus(focus);
            var conn = WatchUi.getCurrentView()[0];
            WatchUi.pushView(m, new DevicePickDelegate(_ble, item, _parentItem,
                conn instanceof WatchUi.Menu2 ? conn as WatchUi.Menu2 : null), WatchUi.SLIDE_LEFT);
        } else if (id == :mRecord) {
            WatchUi.pushView(recordMenu(item), new RaysidMenuDelegate(_state, _ble, item), WatchUi.SLIDE_LEFT);
        } else if (id == :mWeb) {
            // Odesilani, API klic a overeni spojeni pohromade
            push(Tr.t(:mWeb), [
                new WatchUi.MenuItem(Tr.t(:mUpload), uploader().label(), :upload, null),
                new WatchUi.MenuItem(Tr.t(:apiKey), keyLabel(), :apiKey, null),
                new WatchUi.MenuItem(Tr.t(:verify), uploader().verifyLabel(), :verify, null)
            ] as Array<WatchUi.MenuItem>, item);
        } else if (id == :mStorage) {
            // Neodeslane body, co delat pri zaplneni, smazani
            push(Tr.t(:mStorage), [
                new WatchUi.MenuItem(Tr.t(:stoPending), storeLabel(), :stoPending, null),
                new WatchUi.MenuItem(Tr.t(:cmpWhen), cmpSubLabel(recorder().cmpMax, recorder().dist), :cmpMax, null),
                new WatchUi.MenuItem(Tr.t(:recClear), null, :recClear, null)
            ] as Array<WatchUi.MenuItem>, item);
        } else if (id == :stoPending) {
            item.setSubLabel(storeLabel());
        } else if (id == :upload) {
            // Zkusit odeslat hned a obnovit stav
            uploader().retry();
            item.setSubLabel(uploader().label());
        } else if (id == :recClear) {
            // Po smazani obnovit pocet v Neodeslano i v nadrazene polozce Uloziste
            var cur = WatchUi.getCurrentView()[0];
            var pend = null;
            if (cur instanceof WatchUi.Menu2) {
                var idx = (cur as WatchUi.Menu2).findItemById(:stoPending);
                pend = idx >= 0 ? (cur as WatchUi.Menu2).getItem(idx) : null;
            }
            WatchUi.pushView(new WatchUi.Confirmation(Tr.t(:recClearQ)), new ClearConfirmDelegate(pend != null ? pend : item, _parentItem), WatchUi.SLIDE_LEFT);
        } else if (id == :mSignal) {
            var items = [
                new WatchUi.MenuItem(Tr.t(:divider), watchDivLabel(_state.divider), :divider, null),
                toggle(:beep, _state.sound),
                toggle(:vibration, _state.vibrate)
            ] as Array<WatchUi.MenuItem>;
            if (Clicker.hasLed()) {
                items.add(toggle(:flash, _state.led));
            }
            push(Tr.t(:mSignal), items, null);
        } else if (id == :mDevice) {
            item.setSubLabel(Tr.t(_state.status));
            // Nastaveni primo v Raysidu, stav podle jeho posledniho hlaseni
            var div = _state.devDiv;
            var m = new WatchUi.Menu2({:title => Tr.t(:mDevice)});
            m.addItem(new WatchUi.MenuItem(Tr.t(:devDiv), div != null ? devDivLabel(_state, div) : "?", :devDiv, null));
            m.addItem(new WatchUi.ToggleMenuItem(Tr.t(:divLink), Tr.t(:divLinkSub), :divLink, _state.divLink, null));
            m.addItem(devToggle(:devSound, _state.devSound));
            m.addItem(devToggle(:devDoseAl, _state.devDoseAl));
            m.addItem(devToggle(:devCpsAl, _state.devCpsAl));
            // Pripojeni k Raysidu patri sem, pouziva se zridka
            m.addItem(new WatchUi.MenuItem(Tr.t(:mConn), connLabel(_ble), :mConn, null));
            // Az Raysid posle nastaveni, polozky se v otevrenem menu obnovi
            _ble.devMenu = m;
            _ble.requestSettings();
            WatchUi.pushView(m, new RaysidMenuDelegate(_state, _ble, item), WatchUi.SLIDE_LEFT);
        } else if (id == :mAlarms) {
            // Hlavni vypinac, pak kazdy alarm jako podmenu (vypinac + mez),
            // stav je videt rovnou v popisku, takze se nemusi otevirat
            var items = [
                toggle(:alarmsAll, _state.alarmsOn),
                new WatchUi.MenuItem(Tr.t(:gDose), alarmGroupLabel(_state, :gDose), :gDose, null),
                new WatchUi.MenuItem(Tr.t(:gCps), alarmGroupLabel(_state, :gCps), :gCps, null),
                new WatchUi.MenuItem(Tr.t(:gRise), alarmGroupLabel(_state, :gRise), :gRise, null),
                new WatchUi.MenuItem(Tr.t(:mAlarmOut), null, :mAlarmOut, null)
            ] as Array<WatchUi.MenuItem>;
            push(Tr.t(:mAlarms), items, item);
        } else if (id == :gDose || id == :gCps || id == :gRise) {
            gGroupItem = item;
            var items = id == :gDose ? [
                toggle(:doseAlarm, _state.doseOn),
                new WatchUi.MenuItem(Tr.t(:doseLimit), doseLabel(_state.alarmDose), :doseLimit, null)
            ] : (id == :gCps ? [
                toggle(:cpsAlarm, _state.cpsOn),
                new WatchUi.MenuItem(Tr.t(:cpsLimit), cpsLabel(_state.alarmCps), :cpsLimit, null)
            ] : [
                toggle(:rise, _state.softOn),
                new WatchUi.MenuItem(Tr.t(:sensitivity), pctLabel(_state.softPct), :sensitivity, null)
            ]);
            push(Tr.t(id as Symbol), items as Array<WatchUi.MenuItem>, item);
        } else if (id == :mAlarmOut) {
            // Jak se alarm projevi: kazdy prvek jde vypnout zvlast
            var items = [
                toggle(:alarmSound, _state.alarmSound),
                toggle(:alarmVibe, _state.alarmVibe),
                toggle(:alarmFlash, _state.alarmFlash)
            ] as Array<WatchUi.MenuItem>;
            if (Clicker.hasLed()) {
                items.add(toggle(:alarmRedLed, _state.alarmRedLed));
            }
            items.add(new WatchUi.MenuItem(Tr.t(:alarmLen), Tr.t(ALARM_LEN_KEYS[_state.alarmLen] as Symbol), :alarmLen, null));
            push(Tr.t(:mAlarmOut), items, null);
        } else if (id == :mDisplay) {
            WatchUi.pushView(displayMenu(_state), new RaysidMenuDelegate(_state, _ble, null), WatchUi.SLIDE_LEFT);
        } else if (id == :mHelp) {
            var items = [] as Array<WatchUi.MenuItem>;
            for (var i = 0; i < HELP_TOPICS.size(); i++) {
                if (HELP_TOPICS[i] == :hRecord && !recorder().enabled) {
                    continue;
                }
                items.add(new WatchUi.MenuItem(Tr.t(HELP_TOPICS[i] as Symbol), null, i, null));
            }
            var m = new WatchUi.Menu2({:title => Tr.t(:mHelp)});
            for (var i = 0; i < items.size(); i++) {
                m.addItem(items[i]);
            }
            WatchUi.pushView(m, new HelpMenuDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :mLanguage || id == :divider || id == :doseLimit || id == :cpsLimit
                || id == :sensitivity || id == :chartLen || id == :devDiv || id == :alarmLen || id == :recDist || id == :gpsQual || id == :connPref || id == :cmpMax
                || id == :avgMode || id == :avgSpan) {
            openChoice(id as Symbol, item);
        } else if (item instanceof WatchUi.ToggleMenuItem) {
            var on = (item as WatchUi.ToggleMenuItem).isEnabled();
            if (id == :mapping) {
                recorder().setEnabled(on);
                if (on) {
                    uploader().start();
                } else if (recorder().pending() == 0) {
                    uploader().stop();   // neodeslane body se odesilaji dal
                }
                if (_parentItem != null) {
                    (_parentItem as WatchUi.MenuItem).setSubLabel(recordLabel());
                }
                // Prestavet podmenu: bez mapovani zustane jen vypinac
                WatchUi.switchToView(recordMenu(_parentItem), new RaysidMenuDelegate(_state, _ble, _parentItem), WatchUi.SLIDE_IMMEDIATE);
                WatchUi.requestUpdate();
                return;
            } else if (id == :divLink) {
                _state.divLink = on;
                _state.save();
                _ble.syncDivider();
                // Poznamka "(jen alarmy)" u Delicky zavisi na slouceni
                var cur = WatchUi.getCurrentView()[0];
                if (cur instanceof WatchUi.Menu2 && _state.devDiv != null) {
                    var idx = (cur as WatchUi.Menu2).findItemById(:devDiv);
                    if (idx >= 0) {
                        ((cur as WatchUi.Menu2).getItem(idx) as WatchUi.MenuItem).setSubLabel(devDivLabel(_state, _state.devDiv as Number));
                    }
                }
                return;
            } else if (id == :devLock) {
                // Bez vybraneho Raysidu nema zamek smysl
                if (on && _ble.pin == null) {
                    (item as WatchUi.ToggleMenuItem).setEnabled(false);
                    item.setSubLabel(Tr.t(:devPickFirst));
                    return;
                }
                item.setSubLabel(null);
                _ble.setLock(on);
                _ble.enforcePin();
                if (_parentItem != null) {
                    (_parentItem as WatchUi.MenuItem).setSubLabel(connLabel(_ble));
                }
            } else if (id == :devSound || id == :devDoseAl || id == :devCpsAl) {
                var cmd = id == :devSound ? RaysidProtocol.soundCommand(on)
                    : (id == :devDoseAl ? RaysidProtocol.doseAlarmCommand(on) : RaysidProtocol.cpsAlarmCommand(on));
                if (_ble.send(cmd)) {
                    item.setSubLabel(null);
                    if (id == :devSound) {
                        _state.devSound = on;
                    } else if (id == :devDoseAl) {
                        _state.devDoseAl = on;
                    } else {
                        _state.devCpsAl = on;
                    }
                } else {
                    (item as WatchUi.ToggleMenuItem).setEnabled(!on);
                    item.setSubLabel(Tr.t(:stDisconnected));
                }
                return;
            } else if (id == :autostart) {
                recorder().setAutostart(on);
            } else if (id == :backlight) {
                _state.backlight = on;
            } else if (id == :beep) {
                _state.sound = on;
            } else if (id == :vibration) {
                _state.vibrate = on;
            } else if (id == :flash) {
                _state.led = on;
            } else if (id == :debug) {
                _state.showDebug = on;
            } else if (id == :alarmsAll) {
                _state.alarmsOn = on;
                if (_parentItem != null) {
                    (_parentItem as WatchUi.MenuItem).setSubLabel(alarmsLabel(_state));
                }
            } else if (id == :doseAlarm) {
                _state.doseOn = on;
            } else if (id == :cpsAlarm) {
                _state.cpsOn = on;
            } else if (id == :rise) {
                _state.softOn = on;
            }
            if (id == :doseAlarm || id == :cpsAlarm || id == :rise) {
                refreshGroup(_state);
            } else if (id == :alarmSound) {
                _state.alarmSound = on;
            } else if (id == :alarmVibe) {
                _state.alarmVibe = on;
            } else if (id == :alarmFlash) {
                _state.alarmFlash = on;
            } else if (id == :alarmRedLed) {
                _state.alarmRedLed = on;
            }
            if (!on && (id == :alarmsAll || id == :doseAlarm || id == :cpsAlarm || id == :rise)) {
                _state.seqLeft = 0;   // dobihajici alarm utnout
            }
            if (!_state.alarmsOn) {
                _state.hardAlarm = false;
                _state.softAlarm = false;
            }
            _state.save();
            WatchUi.requestUpdate();
        }
    }

    // Podmenu s vyberem jedne hodnoty
    private function openChoice(id as Symbol, item as WatchUi.MenuItem) as Void {
        var labels = [] as Array<String>;
        var focus = -1;   // -1 = zadna predvolba nesedi (vlastni hodnota)
        if (id == :divider) {
            for (var i = 0; i < DIVIDERS.size(); i++) {
                labels.add(watchDivLabel(DIVIDERS[i] as Number));
                focus = DIVIDERS[i] == _state.divider ? i : focus;
            }
        } else if (id == :doseLimit) {
            for (var i = 0; i < DOSE_LIMITS.size(); i++) {
                labels.add(doseLabel(DOSE_LIMITS[i] as Float));
                focus = DOSE_LIMITS[i] == _state.alarmDose ? i : focus;
            }
        } else if (id == :cpsLimit) {
            for (var i = 0; i < CPS_LIMITS.size(); i++) {
                labels.add(cpsLabel(CPS_LIMITS[i] as Number));
                focus = CPS_LIMITS[i] == _state.alarmCps ? i : focus;
            }
        } else if (id == :sensitivity) {
            for (var i = 0; i < SENS_KEYS.size(); i++) {
                labels.add(Tr.t(SENS_KEYS[i] as Symbol));
                focus = SENS_PCTS[i] == _state.softPct ? i : focus;
            }
        } else if (id == :alarmLen) {
            for (var i = 0; i < ALARM_LEN_KEYS.size(); i++) {
                labels.add(Tr.t(ALARM_LEN_KEYS[i] as Symbol));
            }
            focus = _state.alarmLen;
        } else if (id == :recDist) {
            for (var i = 0; i < REC_DISTS.size(); i++) {
                labels.add(REC_DISTS[i] + " m");
                focus = REC_DISTS[i] == recorder().dist ? i : focus;
            }
        } else if (id == :connPref) {
            for (var i = 0; i < CONN_PREF_KEYS.size(); i++) {
                labels.add(Tr.t(CONN_PREF_KEYS[i] as Symbol));
            }
            focus = _ble.pref == 1 ? 1 : 0;
        } else if (id == :cmpMax) {
            for (var i = 0; i < CMP_OPTS.size(); i++) {
                labels.add(cmpLabel(CMP_OPTS[i] as Number));
                focus = CMP_OPTS[i] == recorder().cmpMax ? i : focus;
            }
        } else if (id == :gpsQual) {
            for (var i = 0; i < GPS_QUALS.size(); i++) {
                labels.add(Tr.t(GPS_QUAL_KEYS[i] as Symbol));
                focus = GPS_QUALS[i] == recorder().minQ ? i : focus;
            }
        } else if (id == :devDiv) {
            // Bez spojeni nejde delicku Raysidu zmenit: rovnou to rict
            if (!_ble.isConnected()) {
                item.setSubLabel(Tr.t(:stDisconnected));
                return;
            }
            var cur = _state.devDiv != null ? _state.devDiv : 0;
            var divs = DIVIDERS;
            for (var i = 0; i < divs.size(); i++) {
                labels.add(devDivLabel(_state, divs[i] as Number));
                focus = divs[i] == cur ? i : focus;
            }
        } else if (id == :avgMode) {
            for (var i = 0; i < AVG_MODE_KEYS.size(); i++) {
                labels.add(Tr.t(AVG_MODE_KEYS[i] as Symbol));
            }
            focus = _state.avgMode;
        } else if (id == :avgSpan) {
            var vals = _state.avgMode == 1 ? AVG_SECS : AVG_COUNTS;
            var cur = _state.avgMode == 1 ? _state.avgSec : _state.avgN;
            for (var i = 0; i < vals.size(); i++) {
                labels.add(_state.avgMode == 1 ? vals[i] + " s" : vals[i] + " " + Tr.t(:avgMeas));
                focus = vals[i] == cur ? i : focus;
            }
        } else if (id == :chartLen) {
            for (var i = 0; i < CHART_LENGTHS.size(); i++) {
                labels.add(CHART_LENGTHS[i] + " s");
                focus = CHART_LENGTHS[i] == _state.chartSec ? i : focus;
            }
        } else {
            for (var i = 0; i < LANG_NAMES.size(); i++) {
                labels.add(LANG_NAMES[i] as String);
            }
            focus = Tr.lang;
        }
        var m = new WatchUi.Menu2({:title => item.getLabel()});
        for (var i = 0; i < labels.size(); i++) {
            m.addItem(new WatchUi.MenuItem(labels[i], null, i, null));
        }
        // U mezi, citlivosti, vzdalenosti a prumeru jde zadat i vlastni hodnota
        var custom = id == :doseLimit || id == :cpsLimit || id == :sensitivity || id == :recDist || id == :avgSpan;
        if (custom) {
            m.addItem(new WatchUi.MenuItem(Tr.t(:custom), null, CUSTOM_ID, null));
        }
        // Nastavena vlastni hodnota: kurzor na Vlastni hodnota
        if (focus < 0) {
            focus = custom ? labels.size() : 0;
        }
        m.setFocus(focus);
        WatchUi.pushView(m, new ChoiceMenuDelegate(_state, _ble, id, item), WatchUi.SLIDE_LEFT);
    }
}

class ChoiceMenuDelegate extends WatchUi.Menu2InputDelegate {
    // Navrat o uroven zpet s posuvnou animaci (vychozi je bez animace)
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    private var _state as RaysidState;
    private var _ble as BleManager;
    private var _id as Symbol;
    private var _parentItem as WatchUi.MenuItem;

    function initialize(state as RaysidState, ble as BleManager, id as Symbol, parentItem as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        _state = state;
        _ble = ble;
        _id = id;
        _parentItem = parentItem;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var i = item.getId() as Number;
        if (i == CUSTOM_ID) {
            openPicker();
            return;
        }
        if (_id == :divider) {
            apply((DIVIDERS[i] as Number).toFloat());
        } else if (_id == :doseLimit) {
            apply(DOSE_LIMITS[i] as Float);
        } else if (_id == :cpsLimit) {
            apply((CPS_LIMITS[i] as Number).toFloat());
        } else if (_id == :sensitivity) {
            apply((SENS_PCTS[i] as Number).toFloat());
        } else if (_id == :chartLen) {
            _state.chartSec = CHART_LENGTHS[i] as Number;
            _parentItem.setSubLabel(_state.chartSec + " s");
        } else if (_id == :avgMode) {
            _state.avgMode = i;
            _state.save();
            // Prestavet menu Displej: polozka delky prumeru jen pri prumerovani
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.switchToView(displayMenu(_state), new RaysidMenuDelegate(_state, _ble, null), WatchUi.SLIDE_RIGHT);
            WatchUi.requestUpdate();
            return;
        } else if (_id == :avgSpan) {
            if (_state.avgMode == 1) {
                _state.avgSec = AVG_SECS[i] as Number;
            } else {
                _state.avgN = AVG_COUNTS[i] as Number;
            }
            _parentItem.setSubLabel(avgSpanLabel(_state));
            WatchUi.requestUpdate();
        } else if (_id == :devDiv) {
            var n = DIVIDERS[i] as Number;
            if (_ble.send(RaysidProtocol.dividerCommand(n))) {
                _state.devDiv = n;
                _parentItem.setSubLabel(devDivLabel(_state, n));
                if (_state.divLink) {
                    _state.divider = n;
                    _state.save();
                }
            } else {
                _parentItem.setSubLabel(Tr.t(:stDisconnected));
            }
        } else if (_id == :recDist) {
            recorder().setDist(REC_DISTS[i] as Number);
            _parentItem.setSubLabel(recorder().dist + " m");
        } else if (_id == :connPref) {
            _ble.setPref(i);
            _parentItem.setSubLabel(item.getLabel());
        } else if (_id == :cmpMax) {
            recorder().setCmpMax(CMP_OPTS[i] as Number);
            _parentItem.setSubLabel(cmpSubLabel(recorder().cmpMax, recorder().dist));
        } else if (_id == :gpsQual) {
            recorder().setMinQ(GPS_QUALS[i] as Number);
            _parentItem.setSubLabel(qualLabel(recorder().minQ));
        } else if (_id == :alarmLen) {
            _state.alarmLen = i;
            _parentItem.setSubLabel(item.getLabel());
        } else if (_id == :mLanguage) {
            Tr.lang = i;
            _state.save();
            // Menu je postavene ve starem jazyce: zavrit vyber jazyka i hlavni menu
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            WatchUi.requestUpdate();
            return;
        }
        _state.save();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    // Ulozi ciselnou hodnotu a obnovi popisek v nadrazenem menu
    private function apply(v as Float) as Void {
        if (_id == :divider) {
            _state.divider = v.toNumber();
            _parentItem.setSubLabel(watchDivLabel(_state.divider));
            if (_state.divLink) {
                _ble.syncDivider();
            }
        } else if (_id == :doseLimit) {
            _state.alarmDose = v;
            _parentItem.setSubLabel(doseLabel(v));
            refreshGroup(_state);
        } else if (_id == :cpsLimit) {
            _state.alarmCps = v.toNumber();
            _parentItem.setSubLabel(cpsLabel(_state.alarmCps));
            refreshGroup(_state);
        } else if (_id == :sensitivity) {
            _state.softPct = v.toNumber();
            _parentItem.setSubLabel(pctLabel(_state.softPct));
            refreshGroup(_state);
        } else if (_id == :recDist) {
            recorder().setDist(v.toNumber());
            _parentItem.setSubLabel(recorder().dist + " m");
        } else if (_id == :avgSpan) {
            if (_state.avgMode == 1) {
                _state.avgSec = v.toNumber();
            } else {
                _state.avgN = v.toNumber();
            }
            _parentItem.setSubLabel(avgSpanLabel(_state));
            WatchUi.requestUpdate();
        }
    }

    private function openPicker() as Void {
        var picker;
        var delegate;
        if (_id == :doseLimit) {
            picker = new DigitPicker("uSv/h", 3, 2, _state.alarmDose);
            delegate = new DigitPickerDelegate(2, 0.05, ALARM_DOSE_MAX, method(:onCustom));
        } else if (_id == :cpsLimit) {
            picker = new DigitPicker("cps", 4, 0, _state.alarmCps.toFloat());
            delegate = new DigitPickerDelegate(0, 5.0, ALARM_CPS_MAX.toFloat(), method(:onCustom));
        } else if (_id == :avgSpan && _state.avgMode == 1) {
            picker = new DigitPicker(Tr.t(:avgSpan) + " (s)", 2, 0, _state.avgSec.toFloat());
            delegate = new DigitPickerDelegate(0, 2.0, AVG_SEC_MAX.toFloat(), method(:onCustom));
        } else if (_id == :avgSpan) {
            picker = new DigitPicker(Tr.t(:avgMeas), 2, 0, _state.avgN.toFloat());
            delegate = new DigitPickerDelegate(0, 2.0, AVG_COUNT_MAX.toFloat(), method(:onCustom));
        } else if (_id == :recDist) {
            picker = new DigitPicker(Tr.t(:recDist) + " (m)", 3, 0, recorder().dist.toFloat());
            delegate = new DigitPickerDelegate(0, 2.0, 200.0, method(:onCustom));
        } else {
            picker = new DigitPicker("+ %", 3, 0, _state.softPct.toFloat());
            delegate = new DigitPickerDelegate(0, 10.0, 300.0, method(:onCustom));
        }
        WatchUi.pushView(picker, delegate, WatchUi.SLIDE_LEFT);
    }

    function onCustom(value as Float) as Void {
        apply(value);
        _state.save();
        // Zavrit zadavani i seznam hodnot, zpet do podmenu
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// Potvrzeni smazani zaznamu
class ClearConfirmDelegate extends WatchUi.ConfirmationDelegate {
    private var _item as WatchUi.MenuItem;
    private var _recItem as WatchUi.MenuItem?;

    function initialize(item as WatchUi.MenuItem, recItem as WatchUi.MenuItem?) {
        ConfirmationDelegate.initialize();
        _item = item;
        _recItem = recItem;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            recorder().clear();
            _item.setSubLabel(storeLabel());
            if (_recItem != null) {
                (_recItem as WatchUi.MenuItem).setSubLabel(storeLabel());
            }
        }
        return true;
    }
}

class HelpMenuDelegate extends WatchUi.Menu2InputDelegate {
    // Navrat o uroven zpet s posuvnou animaci (vychozi je bez animace)
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var i = item.getId() as Number;
        var text = HELP_TOPICS[i] == :hAbout ? aboutText() : Tr.t(HELP_TEXTS[i] as Symbol);
        var view = new HelpView(Tr.t(HELP_TOPICS[i] as Symbol), text);
        WatchUi.pushView(view, new HelpDelegate(view), WatchUi.SLIDE_LEFT);
    }
}

// Vyber Raysidu z historie: -1 kterykoli, -2 zapomenout historii
class DevicePickDelegate extends WatchUi.Menu2InputDelegate {
    // Navrat o uroven zpet s posuvnou animaci (vychozi je bez animace)
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    private var _ble as BleManager;
    private var _item as WatchUi.MenuItem;
    private var _connItem as WatchUi.MenuItem?;
    private var _connMenu as WatchUi.Menu2?;

    function initialize(ble as BleManager, item as WatchUi.MenuItem, connItem as WatchUi.MenuItem?, connMenu as WatchUi.Menu2?) {
        Menu2InputDelegate.initialize();
        _ble = ble;
        _item = item;
        _connItem = connItem;
        _connMenu = connMenu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var i = item.getId() as Number;
        if (i == -2) {
            _ble.clearHistory();
        } else if (i == -1) {
            _ble.setPin(null);
        } else {
            // Podle jmena, ne indexu: historie se mezitim mohla preradit
            _ble.setPin(item.getLabel());
        }
        _item.setSubLabel(_ble.pin != null ? _ble.pin : Tr.t(:devAny));
        // Bez vybraneho se "Jen vybrany" vypne; s jinym vybranym se prepoji
        var cm = _connMenu;
        if (cm != null) {
            var idx = cm.findItemById(:devLock);
            if (idx >= 0) {
                (cm.getItem(idx) as WatchUi.ToggleMenuItem).setEnabled(_ble.lock);
            }
        }
        _ble.enforcePin();
        if (_connItem != null) {
            (_connItem as WatchUi.MenuItem).setSubLabel(connLabel(_ble));
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
