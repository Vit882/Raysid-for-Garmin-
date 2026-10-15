// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Odesilani zaznamenanych bodu na web Zhava mista. Hodinky nemaji vlastni
// internet, pozadavky jdou pres Garmin Connect v telefonu. Posila se po
// jednom bloku z fronty Recorderu (nejstarsi prvni); az server potvrdi,
// blok se z hodinek smaze. Kdyz telefon neni v dosahu nebo server neodpovi,
// zkusi se to znovu pri dalsim tiku. Format pozadavku popisuje
// docs/zhavamista/navrh-endpointu.md.
class Uploader {
    const TICK_MS = 30000;
    const DEFAULT_URL = "https://www.zhavamista.cz/api/1.0/all/route-points";

    var status as Symbol = :upOff;   // klic prekladu (Tr)
    var lastCode as Number = 0;      // HTTP kod nebo chyba Connect IQ u :upErr
    var sent as Number = 0;          // odeslanych bodu od spusteni aplikace
    private var _busy as Boolean = false;
    private var _busySince as Number = 0;
    private var _lost as Number = 0;   // odpovedi po vyprseni, ktere jeste muzou prijit
    const BUSY_MAX_MS = 120000;     // odpoved neprisla: povazovat za ztracenou
    private var _sentId as String = "";   // trasa#davka prave odesilaneho bloku
    private var _authFailed as Boolean = false;
    private var _timer as Timer.Timer = new Timer.Timer();

    function initialize() {
    }

    private var _running as Boolean = false;

    // Bezi pri povolenem mapovani, nebo dokud zbyvaji neodeslane body
    function start() as Void {
        if (_running || !active()) {
            return;
        }
        _running = true;
        _timer.start(method(:onTick), TICK_MS, true);
        // Pri startu overit spojeni s webem, je-li zadany klic
        if (apiKey().length() > 0 && verify == :vfIdle) {
            startVerify(null);
        }
        kick();
    }

    private function chunkId(meta as Array) as String {
        var a = meta[0] as Object;
        var b = meta[1] as Object;
        return a.toString() + "#" + b.toString();
    }

    private function active() as Boolean {
        var r = recorder();
        return r.enabled || r.pending() > 0;
    }

    // Uloziste smazano: odpoved na rozeslany blok uz nic nemaze. _busy
    // zustava, dokud odpoved neprijde, at nejdou dva pozadavky najednou.
    function cancel() as Void {
        _sentId = "";
    }

    function stop() as Void {
        if (_running) {
            _timer.stop();
            _running = false;
        }
    }

    // Zmena nastaveni v Garmin Connect: novy klic zkusit hned (a overit)
    function settingsChanged() as Void {
        _authFailed = false;
        if (verify != :vfRunning) {
            verify = :vfIdle;
            if (apiKey().length() > 0) {
                startVerify(null);
            }
        }
        kick();
    }

    function onTick() as Void {
        kick();
    }

    // Vyber "Odesilani na web" v menu: zkusit hned znovu
    function retry() as Void {
        _authFailed = false;
        kick();
    }

    private function prop(key as String) as Application.Properties.ValueType or Null {
        try {
            return Application.Properties.getValue(key);
        } catch (e) {
            return null;
        }
    }

    function enabled() as Boolean {
        var v = prop("zmUpload");
        return v instanceof Boolean ? v : true;
    }

    private function apiKey() as String {
        return currentKey();
    }

    // --- overeni spojeni s webem ---
    // Necha si od webu vratit profil uzivatele s danym klicem. Vysledek je
    // ve verify (:vfIdle, :vfRunning, :vfOk, :vfBad, :vfNoPhone, :vfErr).
    var verify as Symbol = :vfIdle;
    var verifyName as String = "";
    var verifyCode as Number = 0;
    private var _verifyItem as WatchUi.MenuItem? = null;

    function startVerify(item as WatchUi.MenuItem?) as Void {
        if (item != null || verify != :vfRunning) {
            _verifyItem = item;
        }
        // Overeni uz bezi: pockat na nej (starsi odpoved by prepsala novejsi)
        if (verify == :vfRunning) {
            return;
        }
        var key = apiKey();
        if (key.length() == 0) {
            setVerify(:vfNoKey);
            return;
        }
        if (!System.getDeviceSettings().phoneConnected) {
            setVerify(:vfNoPhone);
            return;
        }
        var u = url();
        var i = u.find("route-points");
        u = i != null ? u.substring(0, i) + "user-info" : "https://www.zhavamista.cz/api/1.0/all/user-info";
        setVerify(:vfRunning);
        try {
            Communications.makeWebRequest(u, null, {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {"Authorization" => "Bearer " + key},
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            }, method(:onVerify));
        } catch (e) {
            verifyCode = 0;
            setVerify(:vfErr);
        }
    }

    function onVerify(code as Number, data as Dictionary or String or Null) as Void {
        verifyCode = code;
        if (code == 200 && data instanceof Dictionary) {
            var st = (data as Dictionary)["state"];
            if (st instanceof String && st.equals("ok")) {
                var user = (data as Dictionary)["user"];
                var nick = user instanceof Dictionary ? (user as Dictionary)["nickname"] : null;
                verifyName = nick instanceof String ? nick : "";
                // Klic plati: pripadny zakaz odesilani po 401 zrusit
                _authFailed = false;
                setVerify(:vfOk);
                kick();
                return;
            }
            setVerify(:vfBad);
            return;
        }
        setVerify(code == 401 || code == 403 ? :vfBad : (code < 0 ? :vfNoPhone : :vfErr));
    }

    private function setVerify(s as Symbol) as Void {
        verify = s;
        if (_verifyItem != null) {
            (_verifyItem as WatchUi.MenuItem).setSubLabel(verifyLabel());
        }
        WatchUi.requestUpdate();
    }

    function verifyLabel() as String {
        if (verify == :vfOk) {
            return Tr.t(:vfOk) + (verifyName.length() > 0 ? ": " + verifyName : "");
        }
        if (verify == :vfErr) {
            return Tr.t(:vfErr) + " " + verifyCode;
        }
        return Tr.t(verify);
    }

    private function url() as String {
        var v = prop("zmUrl");
        return v instanceof String && v.length() > 0 ? v : DEFAULT_URL;
    }

    // Pokusi se odeslat nejstarsi blok, pokud nic jineho neprobiha
    function kick() as Void {
        if (_busy && System.getTimer() - _busySince < BUSY_MAX_MS) {
            return;
        }
        if (_busy) {
            _lost++;   // odpoved neprisla; kdyby prisla pozde, ignorovat ji
        }
        _busy = false;
        var r = recorder();
        if (!active()) {
            return;
        }
        if (!enabled()) {
            setStatus(:upOff);
            return;
        }
        var key = apiKey();
        if (key.length() == 0) {
            setStatus(:upNoKey);
            return;
        }
        if (_authFailed) {
            setStatus(:upAuth);
            return;
        }
        var chunk = r.headChunk();
        if (chunk == null) {
            setStatus(r.on || r.paused ? :upWait : :upDone);
            return;
        }
        if (!System.getDeviceSettings().phoneConnected) {
            setStatus(:upNoPhone);
            return;
        }
        var pts = chunk[0] as Array<Number>;
        var meta = chunk[1] as Array;
        var points = [] as Array<Array<Numeric> >;
        for (var i = 0; i + 4 < pts.size(); i += 5) {
            points.add([
                pts[i] / 1000000.0d,
                pts[i + 1] / 1000000.0d,
                pts[i + 2],
                pts[i + 3] / 1000.0,
                pts[i + 4] / 10.0
            ] as Array<Numeric>);
        }
        var body = ({
            "client_route_id" => meta[0],
            "batch" => meta[1],
            "final" => meta[2],
            "name" => meta[3],
            "device" => "RAYSID",
            "points" => points
        }) as Dictionary<Object, Object>;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                "Authorization" => "Bearer " + key,
                "X-API-Key" => key
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        _busy = true;
        _busySince = System.getTimer();
        _sentId = chunkId(meta);
        setStatus(:upSending);
        try {
            Communications.makeWebRequest(url(), body, options, method(:onResponse));
        } catch (e) {
            _busy = false;
            setStatus(:upErr);
        }
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        // Opozdena odpoved na pozadavek po vyprseni: nic nemazat (blok se
        // poslal znovu a server davku podle id trasy a cisla nezdvoji)
        if (_lost > 0) {
            _lost--;
            return;
        }
        _busy = false;
        lastCode = code;
        var ok = code >= 200 && code < 300;
        if (ok && data instanceof Dictionary) {
            var st = (data as Dictionary)["state"];
            if (st == null) {
                st = (data as Dictionary)["status"];
            }
            ok = st == null || (st instanceof String && st.equals("ok"));
        }
        // Trvale odmitnuta davka (spatna data) by zablokovala celou frontu:
        // zahodit ji a pokracovat dalsi. Jen u kodu, kterymi server odmita
        // obsah davky; 404/405 apod. = spatna adresa nebo vypadek webu, data
        // zustanou a zkusi se znovu (401/403 = klic, 408/429 = pozdeji).
        var reject = code == 400 || code == 409 || code == 413 || code == 422;
        if (ok || reject) {
            // Web klic prijal: pripadne stare "klic nepřijat" uz neplati
            if (ok && verify == :vfBad) {
                verify = :vfOk;
            }
            var r = recorder();
            var chunk = r.headChunk();
            // Jen kdyz je na rade stale ten odeslany blok (mezitim mohlo byt
            // uloziste smazane a na jeho miste je novy, neodeslany)
            if (chunk != null && chunkId(chunk[1] as Array).equals(_sentId)) {
                if (ok) {
                    sent += (chunk[0] as Array).size() / 5;
                }
                r.dropHead();
            }
            // Dalsi blok hned, at se fronta vyprazdni
            kick();
            return;
        }
        if (code == 401 || code == 403) {
            _authFailed = true;
            setStatus(:upAuth);
        } else {
            setStatus(:upErr);
        }
    }

    private function setStatus(s as Symbol) as Void {
        if (s != status) {
            status = s;
            WatchUi.requestUpdate();
        }
    }

    // Popisek stavu pro menu
    function label() as String {
        var t = Tr.t(status);
        if (status == :upErr) {
            t += " " + lastCode;
        }
        var n = recorder().count;
        if (n > 0 && status != :upOff) {
            t += ", " + Tr.t(:upQueue) + " " + n;
        }
        return t;
    }
}

function uploader() as Uploader {
    return (Application.getApp() as RaysidApp).uploader;
}
