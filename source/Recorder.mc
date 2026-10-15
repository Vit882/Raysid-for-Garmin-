// Raysid Garmin - Connect IQ app for the Raysid dosimeter
// Copyright (C) 2026 Vít Cenek and contributors (see AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 3 or (at your
// option) any later version, as published by the Free Software Foundation.
// It is distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Records GPS points into the app's own storage (Application.Storage).
// A point is saved when the watch has moved at least the set distance
// from the last point and a fresh measurement has arrived from the Raysid.
// Points are stored in chunks of CHUNK points under keys "r0", "r1", ...; each point
// is 5 integers: [lat*1e6, lon*1e6, unix time, dose in nSv/h, cps*10].
// Chunks form a queue: "rHead" is the first unsent one, "rChunks" the one in progress.
// Each closed chunk has "rm<i>" = [route key, batch number,
// last batch of the route, route name]. The Uploader sends chunks to the web and
// deletes sent ones. A route has at most ROUTE_MAX points, then a new part starts.
class Recorder {
    const CHUNK = 50;
    const FIELDS = 5;
    const MAX_POINTS = 4000;         // unsent points in memory
    const ROUTE_MAX = 5000;          // points in one route on the web
    const FLUSH_EVERY = 10;          // write to storage after every 10 points
    const FRESH_MS = 5000;
    const PT_AVG_MS = 10000;   // longest averaging window for a mapping point

    var enabled as Boolean = true;   // mapping allowed (otherwise hidden and off)
    var autostart as Boolean = false; // start recording when the app starts
    var on as Boolean = false;
    var dist as Number = 5;          // meters between points
    var minQ as Number = 4;          // lowest accepted GPS quality (Position.QUALITY_*)
    var count as Number = 0;         // unsent points in memory
    var session as Number = 0;       // points since recording was started
    // Statistics since recording was started (Mapping screen)
    var meters as Float = 0.0;       // distance traveled between saved points
    var maxDose as Float = 0.0;      // highest dose among saved points (uSv/h)
    var maxCps as Float = 0.0;
    var startTime as Number = 0;     // unix time when recording was started
    var full as Boolean = false;
    var paused as Boolean = false;   // paused, the next start continues the same route
    private var _pausedSec as Number = 0;  // total pause time since recording was started
    private var _pauseAt as Number = 0;
    var gpsOk as Boolean = false;    // position with good accuracy
    var gpsWeak as Boolean = false;  // position available, but accuracy is not sufficient
    var noData as Boolean = false;   // GPS available, but no valid data from the Raysid (points are not saved)
    private var _noKick as Boolean = false;  // send nothing while deleting
    private var _state as RaysidState;
    private var _head as Number = 0;      // first unsent chunk
    private var _chunks as Number = 0;    // chunk in progress
    private var _buf as Array<Number> = [] as Array<Number>;
    private var _unsaved as Number = 0;
    private var _lastLat as Float? = null;
    private var _lastLon as Float? = null;
    private var _lastPtMs as Number = 0;  // timer at the last point (averaging starts from it)
    // Route being recorded (null = the next point creates a new one)
    private var _route as String? = null;
    private var _routeName as String = "";
    private var _batch as Number = 0;
    private var _routePts as Number = 0;
    private var _part as Number = 1;
    private var _start as Number = 0;     // unix time when recording was started
    // Merging when storage is full: next chunk to process (-1 = not in progress)
    private var _cmpNext as Number = -1;
    private var _cmpGain as Number = 0;
    const CMP_STEP = 4;              // chunks per call (because of the watchdog)
    const CMP_ANY = 99;              // merge without limit
    var cmpMax as Number = 2;        // how many times each point may be merged (0 = never)

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
        // After merging, chunks have fewer points, so the count is stored separately
        var c = Storage.getValue("rCount");
        count = c instanceof Number ? c : (_chunks - _head) * CHUNK + _buf.size() / FIELDS;
        // Recount (in case it drifted from reality after a crash);
        // only with a reasonable number of chunks, so startup is not slow
        if (_chunks - _head <= 100) {
            var n = _buf.size() / FIELDS;
            for (var i = _head; i < _chunks; i++) {
                var p = Storage.getValue("r" + i);
                n += p instanceof Array ? p.size() / FIELDS : 0;
            }
            count = n;
        }
        // Full stays full after a restart too (otherwise a short route would be created and end at once)
        var f = Storage.getValue("rFull");
        full = f instanceof Boolean && f;
        if (count < MAX_POINTS && pending() == 0) {
            full = false;
        }
        // Recording does not start by itself after launch (only with the Record always after launch option)
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

    // On app start: resume recording, or start it (autostart)
    function resume() as Void {
        if (!enabled) {
            return;
        }
        // A route that nothing closed last time (e.g. an app crash): close it
        // so its last points go to the web
        if (_route != null) {
            closeChunk(true);
        }
        if (autostart) {
            start();
        }
    }

    // GPS as precise as possible: the fenix 7X Pro Sapphire supports all systems on L1 and L5
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
        // More merging after storage filled up: recording is possible again (the next point merges)
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
            // Resume after a pause: same route and statistics. The first point after
            // the pause is saved immediately and the distance covered during the pause is not counted.
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
        // The previous route was left open (e.g. after storage was full): close
        // it so its rest is not sent as the start of the new route
        if (_route != null) {
            closeChunk(true);
            if (_route != null) {
                storageFull();   // still full, cannot start
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

    // Pause: turn off GPS, the route stays open for resuming
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

    // Recording time without pauses, in seconds
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
        // End the route so the chunk in progress can go to the web
        if (_route != null) {
            closeChunk(true);
        }
        flush();
    }

    // On app exit: recording ends (the route is closed and its
    // last chunk goes to the web on the next launch)
    function suspend() as Void {
        // On app exit, send nothing more (the reply would not arrive,
        // the chunk goes on the next launch)
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
        // The reply to the chunk being sent no longer deletes anything, and nothing else
        // (not even the last chunk in progress) will be sent
        uploader().cancel();
        // End running recording; the next route gets a new id so that on the
        // web it does not collide with batches already sent
        _noKick = true;
        if (on || paused) {
            stop();
        }
        _noKick = false;
        // Deleting hundreds of chunks at once could trigger the watchdog: old chunks
        // are deleted gradually (gcStep), numbering continues after them
        var gc = Storage.getValue("rGc");
        var from = gc instanceof Array ? gc[0] as Number : _head;
        var to = _chunks;
        _chunks++;
        _head = _chunks;
        // New queue first, then the range to delete (a crash between them
        // leaves at most old chunks, nothing new is deleted)
        put("rHead", _head);
        put("rChunks", _chunks);
        put("rGc", [from, to] as Array<Storage.ValueType>);
        _buf = [] as Array<Number>;
        _unsaved = 0;
        count = 0;
        session = 0;
        setFull(false);
        paused = false;   // deleted route: the next recording starts a new one
        _lastLat = null;
        _lastPtMs = 0;
        _lastLon = null;
        _route = null;
        put("rSess", 0);
        put("rCount", 0);
        _cmpNext = -1;
        Storage.deleteValue("rRoute");
    }

    // A running merge finishes even without new points (e.g. when a chunk
    // cannot be closed); called from the BLE timer
    function compactTick() as Void {
        if (_cmpNext >= 0 && !on) {
            compactStep();
        }
    }

    // Gradual deletion of chunks after Delete unsent (called from the BLE timer)
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

    // Closed chunks waiting to be sent
    function pending() as Number {
        return _chunks - _head;
    }

    // Oldest unsent chunk: [points, [key, batch, last, name]]
    function headChunk() as Array? {
        while (_head < _chunks) {
            var pts = Storage.getValue("r" + _head);
            var meta = Storage.getValue("rm" + _head);
            if (pts instanceof Array && !(meta instanceof Array)) {
                // Chunk from an older app version without route metadata
                meta = ["garmin-old-" + _head, 0, true, "Raysid Garmin"];
            }
            if (pts instanceof Array && meta instanceof Array) {
                return [pts, meta];
            }
            // Damaged chunk: skip
            dropHead();
        }
        return null;
    }

    // The oldest chunk was sent: delete it from memory
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
        // The watch only gives a quality level, not accuracy in meters. Points are
        // saved only from the set level up (default GOOD), worse ones are dropped.
        var acc = info.accuracy;
        var fix = acc != null && acc >= Position.QUALITY_POOR && info.position != null;
        gpsOk = fix && acc >= minQ;
        gpsWeak = fix && !gpsOk;
        if (!gpsOk || !on) {
            noData = false;
            return;
        }
        var fresh = _state.lastUpdate != null && System.getTimer() - (_state.lastUpdate as Number) < FRESH_MS;
        // During Raysid overload no points are written (the values are not valid)
        noData = !fresh || _state.doseRate == null || _state.cps == null || _state.ovl;
        if (noData) {
            // Averaging for the next point starts only at the end of the outage/overload
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

    // Value for a point: average of measurements since the previous point, at most over the last
    // 10 s (after start or pause only 10 s). Independent of display averaging.
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

    // Creates a new route (at the first point after starting or after ROUTE_MAX points)
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

    // Closes the chunk in progress and adds it to the send queue.
    // final = last batch of the route (even empty, so the server learns it ended).
    private function closeChunk(final as Boolean) as Void {
        if (_route == null || (_buf.size() == 0 && !final)) {
            return;
        }
        // A chunk without metadata could not be sent: if the metadata does not fit, delete the points too
        if (!put("r" + _chunks, _buf as Array<Storage.ValueType>)
                || !put("rm" + _chunks, [_route, _batch, final, _routeName] as Array<Storage.ValueType>)) {
            Storage.deleteValue("r" + _chunks);
            // The points stay in memory and closing the chunk is retried after merging;
            // when there is nothing left to merge or memory keeps growing, recording ends
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
        // rChunks last: a crash between writes cannot create a chunk with
        // an old batch number (the server would drop it as a duplicate)
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

    // Storage full or MAX_POINTS: go through unsent chunks (except the oldest, which
    // may be being sent right now) and from each pair of points keep the one with the higher
    // dose (real position and values, hotspots are not smeared). Points then end up
    // roughly twice as far apart; on the next fill, again.
    private function startCompact() as Void {
        if (cmpMax <= 0) {
            // Merging disabled: recording ends
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
            _cmpNext = _head + 1;   // the oldest chunk was sent in the meantime
        }
        var end = _cmpNext + CMP_STEP;
        for (; _cmpNext < end && _cmpNext < _chunks; _cmpNext++) {
            var key = "r" + _cmpNext;
            var pts = Storage.getValue(key);
            var meta = Storage.getValue("rm" + _cmpNext);
            // meta[4] = how many times the chunk was already merged (older chunks lack it)
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
            // Nothing to merge (everything already merged the set number of times), or
            // merging did not get below MAX_POINTS (old points already merged the most)
            if (_cmpGain == 0 || count >= MAX_POINTS) {
                if (on) {
                    stop();
                }
                storageFull();
            } else if (full) {
                setFull(false);   // merging freed space: recording is possible again
            }
        }
    }

    // Storage is full: stop recording, turn off GPS, already saved points stay
    // and go to the web; warn once with a long vibration
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

    // Distance in meters; for a few dozen meters a planar approximation is enough
    static function distance(lat1 as Float, lon1 as Float, lat2 as Float, lon2 as Float) as Float {
        var dy = (lat2 - lat1) * 111132.0;
        var dx = (lon2 - lon1) * 111320.0 * Math.cos(Math.toRadians((lat1 + lat2) / 2.0)).toFloat();
        return Math.sqrt(dx * dx + dy * dy).toFloat();
    }
}

function recorder() as Recorder {
    return (Application.getApp() as RaysidApp).recorder;
}
