// Raysid Garmin - Connect IQ app for the Raysid dosimeter
// Copyright (C) 2026 Vít Cenek and contributors (see AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 3 or (at your
// option) any later version, as published by the Free Software Foundation.
// It is distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Uploads recorded points to the Zhava mista website. The watch has no internet
// of its own, requests go through Garmin Connect on the phone. Points are held back
// until there are enough of them (SEND_MIN) or the route ended; then one chunk at a time
// is sent from the Recorder queue (oldest first) until it is empty; once the server confirms,
// the chunk is deleted from the watch. If the phone is out of range or the server does not reply,
// it is retried on the next tick. The request format is described in
// docs/zhavamista/endpoint-proposal.md.
class Uploader {
    const TICK_MS = 30000;
    const DEFAULT_URL = "https://www.zhavamista.cz/api/1.0/all/route-points";
    // The web joins batches of one route only when they arrive less than 1 h apart.
    // So nothing is sent until SEND_MIN unsent points have gathered or the route ended;
    // then the whole queue is sent at once. While a route that was already partly
    // sent stays open, the rest is sent at least every KEEP_SEC, so it stays joined.
    const SEND_MIN = 500;
    const KEEP_SEC = 2400;

    var status as Symbol = :upOff;   // translation key (Tr)
    var lastCode as Number = 0;      // HTTP code or Connect IQ error for :upErr
    var sent as Number = 0;          // points sent since app start
    private var _busy as Boolean = false;
    private var _busySince as Number = 0;
    private var _lost as Number = 0;   // replies after a timeout that may still arrive
    const BUSY_MAX_MS = 120000;     // no reply came: treat it as lost
    private var _sentId as String = "";   // route#batch of the chunk being sent
    private var _authFailed as Boolean = false;
    private var _timer as Timer.Timer = new Timer.Timer();

    function initialize() {
    }

    private var _running as Boolean = false;

    // Runs while mapping is enabled, or as long as unsent points remain
    function start() as Void {
        if (_running || !active()) {
            return;
        }
        _running = true;
        _timer.start(method(:onTick), TICK_MS, true);
        // On start, verify the connection to the web if a key is set
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

    // Storage deleted: the reply to the chunk in flight no longer deletes anything. _busy
    // stays set until the reply arrives, so two requests do not go out at once.
    function cancel() as Void {
        _sentId = "";
    }

    function stop() as Void {
        if (_running) {
            _timer.stop();
            _running = false;
        }
    }

    // Settings changed in Garmin Connect: try the new key at once (and verify it)
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

    // "Web upload" selected in the menu: retry immediately
    function retry() as Void {
        _authFailed = false;
        // Sending was asked for by hand: send whatever is ready
        recorder().setSendReq(true);
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

    // --- verifying the connection to the web ---
    // Asks the web to return the user profile for the given key. The result is
    // in verify (:vfIdle, :vfRunning, :vfOk, :vfBad, :vfNoPhone, :vfErr).
    var verify as Symbol = :vfIdle;
    var verifyName as String = "";
    var verifyCode as Number = 0;
    private var _verifyItem as WatchUi.MenuItem? = null;

    function startVerify(item as WatchUi.MenuItem?) as Void {
        if (item != null || verify != :vfRunning) {
            _verifyItem = item;
        }
        // Verification already running: wait for it (an older reply would overwrite a newer one)
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
                // The key is valid: lift any upload block set after a 401
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

    // Tries to send the oldest chunk if nothing else is in progress
    function kick() as Void {
        if (_busy && System.getTimer() - _busySince < BUSY_MAX_MS) {
            return;
        }
        if (_busy) {
            _lost++;   // no reply came; if it arrives late, ignore it
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
        if (!r.sendReq) {
            if (r.count >= SEND_MIN) {
                r.setSendReq(true);
            } else if (r.lastUpAt > 0 && Time.now().value() - r.lastUpAt >= KEEP_SEC) {
                // Part of the open route is on the web already: send the rest before the web
                // stops joining it (closing the chunk calls kick() again and that one sends)
                r.setSendReq(true);
                r.closePartial();
                if (_busy) {
                    return;
                }
            }
        }
        var chunk = r.headChunk();
        if (chunk == null) {
            r.setSendReq(false);
            setStatus(r.count > 0 ? :upHold : (r.on || r.paused ? :upWait : :upDone));
            return;
        }
        if (!r.sendReq) {
            setStatus(:upHold);
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
        // Late reply to a request after a timeout: delete nothing (the chunk was
        // sent again and the server does not duplicate the batch by route id and number)
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
        // A permanently rejected batch (bad data) would block the whole queue:
        // drop it and continue with the next one. Only for codes by which the server rejects
        // the batch content; 404/405 etc. = wrong address or website outage, the data
        // stays and is retried (401/403 = key, 408/429 = later).
        var reject = code == 400 || code == 409 || code == 413 || code == 422;
        if (ok || reject) {
            // The web accepted the key: any old "key not accepted" no longer applies
            if (ok && verify == :vfBad) {
                verify = :vfOk;
            }
            var r = recorder();
            var chunk = r.headChunk();
            // Only if the sent chunk is still next in line (in the meantime storage
            // may have been deleted and a new, unsent chunk is in its place)
            if (chunk != null && chunkId(chunk[1] as Array).equals(_sentId)) {
                if (ok) {
                    sent += (chunk[0] as Array).size() / 5;
                    // Keep-alive clock only for the route still being recorded
                    if (!((chunk[1] as Array)[2] as Boolean)) {
                        r.setLastUp(Time.now().value());
                    }
                }
                r.dropHead();
            }
            // Next chunk right away, so the queue drains
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

    // Status label for the menu
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
