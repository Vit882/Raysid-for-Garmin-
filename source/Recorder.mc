// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Zaznam bodu s GPS do vlastniho uloziste aplikace (Application.Storage).
// Bod se ulozi, kdyz se hodinky posunou aspon o nastavenou vzdalenost
// od posledniho bodu a od Raysidu prislo cerstve mereni.
// Body jsou v blocich po CHUNK bodech pod klici "r0", "r1", ...; kazdy bod
// je 5 celych cisel: [lat*1e6, lon*1e6, unix cas, davka v nSv/h, cps*10].
// Bloky tvori frontu: "rHead" je prvni neodeslany, "rChunks" rozpracovany.
// Ke kazdemu uzavrenemu bloku patri "rm<i>" = [klic trasy, cislo davky,
// posledni davka trasy, nazev trasy]. Uploader bloky posila na web a
// odeslane maze. Trasa ma nejvys ROUTE_MAX bodu, pak zacne dalsi cast.
class Recorder {
    const CHUNK = 50;
    const FIELDS = 5;
    const MAX_POINTS = 4000;         // neodeslanych bodu v pameti
    const ROUTE_MAX = 5000;          // bodu v jedne trase na webu
    const FLUSH_EVERY = 10;          // zapis do uloziste po kazdych 10 bodech
    const FRESH_MS = 5000;
    const PT_AVG_MS = 10000;   // nejdelsi okno prumeru k bodu mapovani

    var enabled as Boolean = true;   // mapovani povolene (jinak skryte a vypnute)
    var autostart as Boolean = false; // zapnout nahravani pri spusteni aplikace
    var on as Boolean = false;
    var dist as Number = 5;          // metry mezi body
    var minQ as Number = 4;          // nejnizsi prijata kvalita GPS (Position.QUALITY_*)
    var count as Number = 0;         // neodeslanych bodu v pameti
    var session as Number = 0;       // bodu od zapnuti nahravani
    // Statistika od zapnuti nahravani (obrazovka Mapovani)
    var meters as Float = 0.0;       // ujeta vzdalenost mezi ulozenymi body
    var maxDose as Float = 0.0;      // nejvyssi davka v ulozenych bodech (uSv/h)
    var maxCps as Float = 0.0;
    var startTime as Number = 0;     // unix cas zapnuti nahravani
    var full as Boolean = false;
    var paused as Boolean = false;   // pozastaveno, dalsi start navaze na stejnou trasu
    private var _pausedSec as Number = 0;  // delka pauz od zapnuti nahravani
    private var _pauseAt as Number = 0;
    var gpsOk as Boolean = false;    // poloha s dobrou presnosti
    var gpsWeak as Boolean = false;  // poloha je, ale presnost nestaci
    var noData as Boolean = false;   // GPS je, ale z Raysidu nejsou platna data (body se neukladaji)
    private var _noKick as Boolean = false;  // behem mazani nic neodesilat
    private var _state as RaysidState;
    private var _head as Number = 0;      // prvni neodeslany blok
    private var _chunks as Number = 0;    // rozpracovany blok
    private var _buf as Array<Number> = [] as Array<Number>;
    private var _unsaved as Number = 0;
    private var _lastLat as Float? = null;
    private var _lastLon as Float? = null;
    private var _lastPtMs as Number = 0;  // casovac pri poslednim bodu (prumer od nej)
    // Prave nahravana trasa (null = dalsi bod zalozi novou)
    private var _route as String? = null;
    private var _routeName as String = "";
    private var _batch as Number = 0;
    private var _routePts as Number = 0;
    private var _part as Number = 1;
    private var _start as Number = 0;     // unix cas zapnuti nahravani
    // Slucovani pri plnem ulozisti: dalsi blok k projiti (-1 = neprobiha)
    private var _cmpNext as Number = -1;
    private var _cmpGain as Number = 0;
    const CMP_STEP = 4;              // bloku na jedno volani (kvuli watchdogu)
    const CMP_ANY = 99;              // slucovat bez omezeni
    var cmpMax as Number = 2;        // kolikrat smi byt kazdy bod sloucen (0 = nikdy)

    function initialize(state as RaysidState) {
        _state = state;
        dist = clamp(num("rDist", 5), 2, 200);
        minQ = clamp(num("rQual", Position.QUALITY_GOOD as Number), Position.QUALITY_POOR as Number, Position.QUALITY_GOOD as Number);
        cmpMax = num("rCmp", cmpMax);
        cmpMax = cmpMax >= 99 ? 99 : clamp(cmpMax, 0, 3);
        var e = Storage.getValue("rEn");
        enabled = !(e instanceof Boolean) || e;
        e = Storage.getValue("rAuto");
        autostart = e instanceof Boolean && e;
        _head = num("rHead", 0);
        _chunks = num("rChunks", 0);
        var v = Storage.getValue("r" + _chunks);
        _buf = v instanceof Array ? v as Array<Number> : [] as Array<Number>;
        v = Storage.getValue("rRoute");
        _route = v instanceof String ? v : null;
        v = Storage.getValue("rRName");
        _routeName = v instanceof String ? v : "";
        _batch = num("rBatch", 0);
        _routePts = num("rRPts", 0);
        _part = num("rPart", 1);
        _start = num("rStart", 0);
        session = num("rSess", 0);
        meters = flt("rMeters");
        maxDose = flt("rMaxD");
        maxCps = flt("rMaxC");
        startTime = _start;
        // Po slouceni maji bloky min bodu, proto se pocet uklada zvlast
        var c = Storage.getValue("rCount");
        count = c instanceof Number ? c : (_chunks - _head) * CHUNK + _buf.size() / FIELDS;
        // Pocet znovu secist (kdyby se po padu rozesel se skutecnosti);
        // jen pri rozumnem poctu bloku, at start netrva
        if (_chunks - _head <= 100) {
            var n = _buf.size() / FIELDS;
            for (var i = _head; i < _chunks; i++) {
                var p = Storage.getValue("r" + i);
                n += p instanceof Array ? p.size() / FIELDS : 0;
            }
            count = n;
        }
        // Plno zustava i po restartu (jinak by se zalozila kratka trasa a hned skoncila)
        var f = Storage.getValue("rFull");
        full = f instanceof Boolean && f;
        if (count < MAX_POINTS && pending() == 0) {
            full = false;
        }
        // Nahravani se po spusteni samo nezapina (jen s volbou Nahravat vzdy po spusteni)
        on = false;
    }

    private function flt(key as String) as Float {
        var v = Storage.getValue(key);
        return v instanceof Float ? v : 0.0;
    }

    private function saveStats() as Void {
        put("rSess", session);
        put("rMeters", meters);
        put("rMaxD", maxDose);
        put("rMaxC", maxCps);
    }

    private function num(key as String, def as Number) as Number {
        var v = Storage.getValue(key);
        return v instanceof Number ? v : def;
    }

    // Pri startu aplikace: pokracovat v nahravani, nebo ho zapnout (autostart)
    function resume() as Void {
        if (!enabled) {
            return;
        }
        // Trasa, kterou minule nic neukoncilo (napr. pad aplikace): uzavrit,
        // aby jeji posledni body odesly na web
        if (_route != null) {
            closeChunk(true);
        }
        if (autostart) {
            start();
        }
    }

    // GPS co nejpresneji: fenix 7X Pro Sapphire umi vsechny systemy na L1 i L5
    private function gpsOn() as Void {
        if (Position has :hasConfigurationSupport) {
            var cfgs = [
                Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5,
                Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1,
                Position.CONFIGURATION_GPS_GALILEO
            ];
            for (var i = 0; i < cfgs.size(); i++) {
                if (Position.hasConfigurationSupport(cfgs[i] as Position.Configuration)) {
                    try {
                        Position.enableLocationEvents({
                            :acquisitionType => Position.LOCATION_CONTINUOUS,
                            :configuration => cfgs[i] as Position.Configuration
                        }, method(:onPosition));
                        return;
                    } catch (e) {
                    }
                }
            }
        }
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    }

    function setEnabled(v as Boolean) as Void {
        if (!v && (on || paused)) {
            stop();
        }
        enabled = v;
        put("rEn", v);
    }

    function setCmpMax(n as Number) as Void {
        var old = cmpMax;
        cmpMax = n;
        put("rCmp", n);
        // Vic slucovani po zaplneni: zase jde nahravat (dalsi bod slouci)
        if (full && n > old) {
            setFull(false);
        }
    }

    private function setFull(v as Boolean) as Void {
        full = v;
        put("rFull", v);
    }

    function setMinQ(q as Number) as Void {
        minQ = q;
        put("rQual", q);
    }

    function setAutostart(v as Boolean) as Void {
        autostart = v;
        put("rAuto", v);
    }

    function start() as Void {
        if (full || !enabled) {
            return;
        }
        if (paused) {
            // Pokracovat po pauze: stejna trasa i statistika. Prvni bod po
            // pauze se ulozi hned a usek ujety behem pauzy se nepocita.
            paused = false;
            on = true;
            _pausedSec += Time.now().value() - _pauseAt;
            _lastLat = null;
            _lastPtMs = 0;
            _lastLon = null;
            put("rOn", true);
            gpsOn();
            return;
        }
        // Predchozi trasa zustala otevrena (napr. po plnem ulozisti): uzavrit
        // ji, aby jeji zbytek neodesel jako zacatek nove trasy
        if (_route != null) {
            closeChunk(true);
            if (_route != null) {
                storageFull();   // stale plno, nelze zacit
                return;
            }
        }
        _pausedSec = 0;
        on = true;
        _lastLat = null;
        _lastPtMs = 0;
        _lastLon = null;
        _route = null;
        _part = 1;
        _start = Time.now().value();
        startTime = _start;
        session = 0;
        meters = 0.0;
        maxDose = 0.0;
        maxCps = 0.0;
        saveStats();
        put("rOn", true);
        put("rPart", 1);
        put("rStart", _start);
        put("rSess", 0);
        Storage.deleteValue("rRoute");
        gpsOn();
    }

    // Pozastavit: GPS vypnout, trasa zustane otevrena pro pokracovani
    function pause() as Void {
        if (!on) {
            return;
        }
        on = false;
        paused = true;
        _pauseAt = Time.now().value();
        gpsOk = false;
        gpsWeak = false;
        noData = false;
        put("rOn", false);
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        flush();
        saveStats();
    }

    // Doba nahravani bez pauz v sekundach
    function activeSec() as Number {
        if (startTime <= 0 || (!on && !paused)) {
            return 0;
        }
        var end = paused ? _pauseAt : Time.now().value();
        var s = end - startTime - _pausedSec;
        return s > 0 ? s : 0;
    }

    function stop() as Void {
        on = false;
        paused = false;
        gpsOk = false;
        gpsWeak = false;
        noData = false;
        put("rOn", false);
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        // Ukoncit trasu, aby rozpracovany blok mohl odejit na web
        if (_route != null) {
            closeChunk(true);
        }
        flush();
    }

    // Pri ukonceni aplikace: nahravani skonci (trasa se uzavre a jeji
    // posledni blok odejde na web pri dalsim spusteni)
    function suspend() as Void {
        // Pri ukonceni aplikace uz nic neodesilat (odpoved by neprisla,
        // blok odejde pri dalsim spusteni)
        _noKick = true;
        if (on || paused) {
            stop();
        }
        _noKick = false;
        flush();
        saveStats();
    }

    function setDist(m as Number) as Void {
        dist = m;
        put("rDist", m);
    }

    function clear() as Void {
        // Odpoved na prave odesilany blok uz nic nemaze a nic dalsiho
        // (ani posledni rozpracovany blok) se uz neodesle
        uploader().cancel();
        // Bezici nahravani ukoncit; dalsi trasa dostane nove id, aby se na
        // webu nesrazila s uz odeslanymi davkami
        _noKick = true;
        if (on || paused) {
            stop();
        }
        _noKick = false;
        // Mazat stovky bloku najednou by mohlo shodit watchdog: stare bloky
        // se smazou postupne (gcStep), cislovani pokracuje za nimi
        var gc = Storage.getValue("rGc");
        var from = gc instanceof Array ? gc[0] as Number : _head;
        var to = _chunks;
        _chunks++;
        _head = _chunks;
        // Nejdriv nova fronta, pak rozsah k mazani (pri padu mezi nimi
        // zustanou nanejvys stare bloky, nesmaze se nic noveho)
        put("rHead", _head);
        put("rChunks", _chunks);
        put("rGc", [from, to] as Array<Storage.ValueType>);
        _buf = [] as Array<Number>;
        _unsaved = 0;
        count = 0;
        session = 0;
        setFull(false);
        paused = false;   // smazana trasa: dalsi nahravani zacne novou
        _lastLat = null;
        _lastPtMs = 0;
        _lastLon = null;
        _route = null;
        put("rSess", 0);
        put("rCount", 0);
        _cmpNext = -1;
        Storage.deleteValue("rRoute");
    }

    // Rozbehnute slucovani dobehne i bez novych bodu (napr. kdyz nejde
    // uzavrit blok); vola se z casovace BLE
    function compactTick() as Void {
        if (_cmpNext >= 0 && !on) {
            compactStep();
        }
    }

    // Postupne mazani bloku po Smazat neodeslane (vola se z casovace BLE)
    function gcStep() as Void {
        var gc = Storage.getValue("rGc");
        if (!(gc instanceof Array)) {
            return;
        }
        var from = gc[0] as Number;
        var to = gc[1] as Number;
        var end = from + 10;
        for (; from <= to && from < end; from++) {
            Storage.deleteValue("r" + from);
            Storage.deleteValue("rm" + from);
        }
        if (from > to) {
            Storage.deleteValue("rGc");
        } else {
            put("rGc", [from, to] as Array<Storage.ValueType>);
        }
    }

    // Uzavrene bloky cekajici na odeslani
    function pending() as Number {
        return _chunks - _head;
    }

    // Nejstarsi neodeslany blok: [body, [klic, davka, posledni, nazev]]
    function headChunk() as Array? {
        while (_head < _chunks) {
            var pts = Storage.getValue("r" + _head);
            var meta = Storage.getValue("rm" + _head);
            if (pts instanceof Array && !(meta instanceof Array)) {
                // Blok ze starsi verze aplikace bez popisu trasy
                meta = ["garmin-old-" + _head, 0, true, "Raysid Garmin"];
            }
            if (pts instanceof Array && meta instanceof Array) {
                return [pts, meta];
            }
            // Poskozeny blok: preskocit
            dropHead();
        }
        return null;
    }

    // Nejstarsi blok byl odeslan: smazat ho z pameti
    function dropHead() as Void {
        if (_head >= _chunks) {
            return;
        }
        var pts = Storage.getValue("r" + _head);
        Storage.deleteValue("r" + _head);
        Storage.deleteValue("rm" + _head);
        _head++;
        put("rHead", _head);
        count -= pts instanceof Array ? pts.size() / FIELDS : 0;
        if (count < 0) {
            count = 0;
        }
        put("rCount", count);
        if (full && count < MAX_POINTS) {
            setFull(false);
        }
    }

    function onPosition(info as Position.Info) as Void {
        // Hodinky davaji jen stupen kvality, ne presnost v metrech. Body se
        // ukladaji jen od nastaveneho stupne (vychozi GOOD), horsi se zahodi.
        var acc = info.accuracy;
        var fix = acc != null && acc >= Position.QUALITY_POOR && info.position != null;
        gpsOk = fix && acc >= minQ;
        gpsWeak = fix && !gpsOk;
        if (!gpsOk || !on) {
            noData = false;
            return;
        }
        var fresh = _state.lastUpdate != null && System.getTimer() - (_state.lastUpdate as Number) < FRESH_MS;
        // Pri pretizeni Raysidu se body nezapisuji (hodnoty nejsou platne)
        noData = !fresh || _state.doseRate == null || _state.cps == null || _state.ovl;
        if (noData) {
            // Prumer k dalsimu bodu az od konce vypadku/pretizeni
            _lastPtMs = System.getTimer();
            return;
        }
        var deg = (info.position as Position.Location).toDegrees();
        var lat = deg[0].toFloat();
        var lon = deg[1].toFloat();
        var d = _lastLat != null ? distance(_lastLat as Float, _lastLon as Float, lat, lon) : 0.0;
        if (_lastLat != null && d < dist) {
            return;
        }
        meters += d;
        _lastLat = lat;
        _lastLon = lon;
        addPoint(deg[0], deg[1]);
    }

    // Hodnota k bodu: prumer mereni od predchoziho bodu, nejvys za poslednich
    // 10 s (po startu nebo pauze jen 10 s). Nezavisi na prumerovani displeje.
    private function pointValues() as Array<Float> {
        var now = System.getTimer();
        var from = now - PT_AVG_MS;
        if (_lastPtMs > from && _lastPtMs <= now) {
            from = _lastPtMs;
        }
        _lastPtMs = now;
        var v = _state.avgSince(from);
        return v != null ? v as Array<Float> : [_state.doseRate as Float, _state.cps as Float] as Array<Float>;
    }

    // Zalozi novou trasu (pri prvnim bodu po zapnuti nebo po ROUTE_MAX bodech)
    private function newRoute() as Void {
        var id = System.getDeviceSettings().uniqueIdentifier;
        var dev = id != null && id.length() >= 6 ? id.substring(0, 6) : "watch";
        _route = "garmin-" + dev + "-" + _start + "-" + _part;
        var d = Gregorian.info(new Time.Moment(_start), Time.FORMAT_SHORT);
        _routeName = "Raysid Garmin " + d.day + ". " + d.month + ". " + d.year + " "
            + d.hour.format("%02d") + ":" + d.min.format("%02d") + (_part > 1 ? " (" + _part + ")" : "");
        _batch = 0;
        _routePts = 0;
        put("rRoute", _route as String);
        put("rRName", _routeName);
        put("rBatch", 0);
        put("rPart", _part);
    }

    private function addPoint(lat as Double, lon as Double) as Void {
        if (_route == null) {
            newRoute();
        }
        _buf.add((lat * 1000000.0d).toNumber());
        _buf.add((lon * 1000000.0d).toNumber());
        _buf.add(Time.now().value());
        var v = pointValues();
        _buf.add((v[0] * 1000.0 + 0.5).toNumber());
        _buf.add((v[1] * 10.0 + 0.5).toNumber());
        count++;
        session++;
        _routePts++;
        if (v[0] > maxDose) {
            maxDose = v[0];
        }
        if (v[1] > maxCps) {
            maxCps = v[1];
        }
        _unsaved++;
        var last = _routePts >= ROUTE_MAX;
        if (_buf.size() >= CHUNK * FIELDS || last) {
            closeChunk(last);
            if (last && _route == null) {
                _part++;
            }
        } else if (_unsaved >= FLUSH_EVERY) {
            flush();
        }
        if (count >= MAX_POINTS) {
            startCompact();
        }
        compactStep();
    }

    // Uzavre rozpracovany blok a zaradi ho do fronty k odeslani.
    // final = posledni davka trasy (i prazdna, aby se server dozvedel konec).
    private function closeChunk(final as Boolean) as Void {
        if (_route == null || (_buf.size() == 0 && !final)) {
            return;
        }
        // Blok bez popisu by se nedal odeslat: kdyz se popis nevejde, smazat i body
        if (!put("r" + _chunks, _buf as Array<Storage.ValueType>)
                || !put("rm" + _chunks, [_route, _batch, final, _routeName] as Array<Storage.ValueType>)) {
            Storage.deleteValue("r" + _chunks);
            // Body zustanou v pameti a blok se zkusi zavrit znovu po slouceni;
            // kdyz uz neni co slucovat nebo pamet roste, nahravani skonci
            if (_cmpNext < 0 && _buf.size() >= 2 * CHUNK * FIELDS) {
                storageFull();
            } else {
                startCompact();
            }
            return;
        }
        _chunks++;
        _batch++;
        _buf = [] as Array<Number>;
        _unsaved = 0;
        // rChunks az nakonec: pri padu mezi zapisy nevznikne blok se
        // starym cislem davky (server by ho zahodil jako duplicitu)
        put("rBatch", _batch);
        put("rRPts", _routePts);
        put("rCount", count);
        put("rChunks", _chunks);
        saveStats();
        if (final) {
            _route = null;
            Storage.deleteValue("rRoute");
        }
        if (!_noKick) {
            uploader().kick();
        }
    }

    function flush() as Void {
        if (_unsaved == 0) {
            return;
        }
        if (put("r" + _chunks, _buf as Array<Storage.ValueType>)) {
            put("rRPts", _routePts);
            put("rCount", count);
            _unsaved = 0;
        } else {
            startCompact();
        }
    }

    // Plne uloziste nebo MAX_POINTS: neodeslane bloky (krome nejstarsiho, ten se
    // muze prave odesilat) projit a z kazde dvojice bodu nechat ten s vyssi
    // davkou (skutecna poloha i hodnoty, hotspoty se nerozmazou). Bod pak
    // vychazi zhruba na dvojnasobnou vzdalenost; pri dalsim zaplneni znovu.
    private function startCompact() as Void {
        if (cmpMax <= 0) {
            // Slucovani vypnute: nahravani skonci
            if (on) {
                stop();
            }
            storageFull();
            return;
        }
        if (_cmpNext < 0) {
            _cmpNext = _head + 1;
            _cmpGain = 0;
        }
    }

    private function compactStep() as Void {
        if (_cmpNext < 0) {
            return;
        }
        if (_cmpNext <= _head) {
            _cmpNext = _head + 1;   // nejstarsi blok se mezitim odeslal
        }
        var end = _cmpNext + CMP_STEP;
        for (; _cmpNext < end && _cmpNext < _chunks; _cmpNext++) {
            var key = "r" + _cmpNext;
            var pts = Storage.getValue(key);
            var meta = Storage.getValue("rm" + _cmpNext);
            // meta[4] = kolikrat uz byl blok sloucen (starsi bloky ho nemaji)
            if (!(pts instanceof Array) || pts.size() < 2 * FIELDS || !(meta instanceof Array)) {
                continue;
            }
            var level = meta.size() > 4 ? meta[4] as Number : 0;
            if (cmpMax != CMP_ANY && level >= cmpMax) {
                continue;
            }
            var n = pts.size() / FIELDS;
            var out = [] as Array<Number>;
            for (var p = 0; p < n; p += 2) {
                var k = p * FIELDS;
                if (p + 1 < n && (pts[k + FIELDS + 3] as Number) > (pts[k + 3] as Number)) {
                    k += FIELDS;
                }
                for (var f = 0; f < FIELDS; f++) {
                    out.add(pts[k + f] as Number);
                }
            }
            var m2 = [meta[0], meta[1], meta[2], meta[3], level + 1] as Array<Storage.ValueType>;
            if (put("rm" + _cmpNext, m2) && put(key, out as Array<Storage.ValueType>)) {
                var gain = n - out.size() / FIELDS;
                _cmpGain += gain;
                count -= gain;
            }
        }
        if (_cmpNext >= _chunks) {
            _cmpNext = -1;
            put("rCount", count);
            // Neni co slucovat (vse uz sloucene nastaveny pocet krat), nebo
            // slouceni nestacilo pod MAX_POINTS (stare body uz sloucene nejvic)
            if (_cmpGain == 0 || count >= MAX_POINTS) {
                if (on) {
                    stop();
                }
                storageFull();
            } else if (full) {
                setFull(false);   // slouceni uvolnilo misto: zase jde nahravat
            }
        }
    }

    // Uloziste je plne: dal nenahravat, GPS vypnout, uz ulozene body zustanou
    // a odejdou na web; jednou upozornit dlouhou vibraci
    private function storageFull() as Void {
        if (!full && Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, 1500)] as Array<Attention.VibeProfile>);
        }
        setFull(true);
        noData = false;
        on = false;
        paused = false;
        gpsOk = false;
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        put("rOn", false);
    }

    // Vzdalenost v metrech; na par desitek metru staci rovinna aproximace
    static function distance(lat1 as Float, lon1 as Float, lat2 as Float, lon2 as Float) as Float {
        var dy = (lat2 - lat1) * 111132.0;
        var dx = (lon2 - lon1) * 111320.0 * Math.cos(Math.toRadians((lat1 + lat2) / 2.0)).toFloat();
        return Math.sqrt(dx * dx + dy * dy).toFloat();
    }
}

function recorder() as Recorder {
    return (Application.getApp() as RaysidApp).recorder;
}
