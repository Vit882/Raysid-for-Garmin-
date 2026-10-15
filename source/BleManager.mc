// Raysid Garmin - Connect IQ app for the Raysid dosimeter
// Copyright (C) 2026 Vít Cenek and contributors (see AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 3 or (at your
// option) any later version, as published by the Free Software Foundation.
// It is distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Scanning, connecting to the Raysid, enabling notifications and receiving data.
// Connect IQ allows only one pending BLE request at a time,
// so writes (CCCD, commands) go through the _queue.
class BleManager extends BluetoothLowEnergy.BleDelegate {
    private var _state as RaysidState;
    private var _device as BluetoothLowEnergy.Device? = null;
    private var _profileReady as Boolean = false;
    private var _queue as Array = [];
    private var _busy as Boolean = false;
    private var _timer as Timer.Timer = new Timer.Timer();
    private var _parser as RaysidParser = new RaysidParser();
    private var _busySince as Number = 0;
    private var _alarms as Alarms;
    private var _pairSince as Number = 0;   // when connecting started (0 = not in progress)
    private var _logT as Number = 0;        // last measurement line in the debug log
    const CONNECT_TIMEOUT_MS = 15000;
    const RECOVER_MS = 30000;   // no connection or no data for this long: reconnect
    private var _downSince as Number = 0;   // when the connection dropped / service missing (0 = OK)
    private var _lastRx as Number = 0;      // last received data
    private var _lastPing as Number = 0;
    const CHOOSE_MS = 3000;     // how long to collect found Raysids before choosing one
    const HISTORY_MAX = 6;

    // Connection settings (persisted)
    var pin as String? = null;     // selected Raysid (name)
    var lock as Boolean = false;   // connect only to the selected one
    var pref as Number = 0;        // with several units: 0 selected/known, 1 strongest signal
    var history as Array<Array> = [] as Array<Array>;   // [[name, unix time], ...], newest first

    // Raysids found in the current scan: name -> ScanResult (strongest)
    private var _cands as Dictionary<String, BluetoothLowEnergy.ScanResult> = {} as Dictionary<String, BluetoothLowEnergy.ScanResult>;
    private var _firstSeen as Number = 0;

    function initialize(state as RaysidState) {
        BleDelegate.initialize();
        _state = state;
        _alarms = new Alarms(state);
        var v = Storage.getValue("devPin");
        pin = v instanceof String ? v : null;
        v = Storage.getValue("devLock");
        lock = v instanceof Boolean && v;
        v = Storage.getValue("devPref");
        pref = v instanceof Number ? v : 0;
        v = Storage.getValue("devHist");
        history = v instanceof Array ? v as Array<Array> : [] as Array<Array>;
    }

    function setPin(name as String?) as Void {
        pin = name;
        if (name == null) {
            Storage.deleteValue("devPin");
            // "Selected only" makes no sense without a selected one
            if (lock) {
                setLock(false);
            }
        } else {
            put("devPin", name);
        }
    }

    function setLock(v as Boolean) as Void {
        lock = v;
        put("devLock", v);
    }

    function setPref(v as Number) as Void {
        pref = v;
        put("devPref", v);
    }

    function isConnected() as Boolean {
        return _device != null && (_device as BluetoothLowEnergy.Device).isConnected();
    }

    // "Selected only" and a different Raysid is connected: connect the selected one
    function enforcePin() as Void {
        var p = pin;
        var n = _state.deviceName;
        if (lock && p != null && isConnected() && (n == null || !p.equals(n))) {
            restart();
        }
    }

    function clearHistory() as Void {
        history = [] as Array<Array>;
        Storage.deleteValue("devHist");
        setPin(null);
        setLock(false);
    }

    // Move the connected Raysid to the top of the history; the first one connected becomes selected
    private function remember(name as String?) as Void {
        if (name == null) {
            return;
        }
        var h = [[name, Time.now().value()]] as Array<Array>;
        for (var i = 0; i < history.size() && h.size() < HISTORY_MAX; i++) {
            if (!name.equals((history[i] as Array)[0] as String)) {
                h.add(history[i] as Array);
            }
        }
        // Only the very first connected Raysid becomes selected automatically; if the user
        // later chooses "any", it stays that way
        if (pin == null && history.size() == 0) {
            setPin(name);
        }
        history = h;
        put("devHist", h as Array<Storage.ValueType>);
    }

    private function historyRank(name as String) as Number {
        for (var i = 0; i < history.size(); i++) {
            if (name.equals((history[i] as Array)[0] as String)) {
                return i;
            }
        }
        return 999;
    }

    function start() as Void {
        register();
        // Periodic data request, if the protocol requires it
        _timer.start(method(:onTick), RaysidProtocol.POLL_MS, true);
    }

    function stop() as Void {
        _timer.stop();
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        if (_device != null) {
            BluetoothLowEnergy.unpairDevice(_device);
            _device = null;
        }
    }

    private function register() as Void {
        try {
            BluetoothLowEnergy.registerProfile(RaysidProtocol.profile());
            setStatus(:stRegistering, "");
        } catch (e) {
            setStatus(:stProfileErr, "");
        }
    }

    function restart() as Void {
        _pairSince = 0;
        if (_device != null) {
            BluetoothLowEnergy.unpairDevice(_device);
            _device = null;
        }
        _queue = [];
        _busy = false;
        _setReq = 0;
        _downSince = 0;
        clearLive();
        if (!_profileReady) {
            register();   // profile registration failed: try again
            return;
        }
        startScan();
    }

    // After losing the connection: clear alarms and overload, Raysid settings unknown
    private function clearLive() as Void {
        _alarms.reset();
        _state.cpsOvlOn = false;
        _state.doseOvlOn = false;
        _state.ovl = false;
        _state.devOvl = null;
    }

    private function startScan() as Void {
        if (!_profileReady) {
            return;
        }
        setStatus(:stSearching, "");
        _cands = {} as Dictionary<String, BluetoothLowEnergy.ScanResult>;
        _firstSeen = 0;
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            _profileReady = true;
            if (!adoptPaired()) {
                startScan();
            }
        } else {
            setStatus(:stProfile, status.toString());
        }
    }

    // After an app update (upload over USB) the Raysid may stay connected
    // to the watch from the previous instance. It then does not advertise and scanning
    // will not find it until the watch restarts. We take over such a connection, and if it
    // is no longer active, we unpair the device so it can be found again.
    private function adoptPaired() as Boolean {
        var adopted = false;
        try {
            var it = BluetoothLowEnergy.getPairedDevices();
            for (var d = it.next() as BluetoothLowEnergy.Device?; d != null; d = it.next() as BluetoothLowEnergy.Device?) {
                var dn = d.getName();
                var allowed = !lock || pin == null || (dn != null && dn.equals(pin));
                if (!adopted && allowed && d.isConnected()) {
                    adopted = true;
                    _device = d;
                    _lastRx = System.getTimer();
                    _state.deviceName = d.getName();
                    setStatus(:stConnected, "");
                    _parser.reset();
                    subscribe();
                } else {
                    BluetoothLowEnergy.unpairDevice(d);
                }
            }
        } catch (e) {
        }
        return adopted;
    }

    // Found Raysids are collected for a while so one can be chosen among several.
    // The selected Raysid connects immediately; with "selected only" the others are ignored.
    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        // Late results after connecting has started: do not pair a second time
        if (_pairSince != 0 || (_device != null && _device.isConnected())) {
            return;
        }
        for (var r = scanResults.next() as BluetoothLowEnergy.ScanResult?; r != null; r = scanResults.next() as BluetoothLowEnergy.ScanResult?) {
            if (!RaysidProtocol.matches(r)) {
                continue;
            }
            var name = r.getDeviceName();
            if (name == null) {
                name = "Raysid";
            }
            if (lock && pin != null && !name.equals(pin)) {
                continue;
            }
            // Selected one immediately, unless choosing by signal strength
            if (pin != null && name.equals(pin) && (lock || pref == 0)) {
                connect(r);
                return;
            }
            var old = _cands[name];
            if (old == null || r.getRssi() > old.getRssi()) {
                _cands[name] = r;
            }
            if (_firstSeen == 0) {
                _firstSeen = System.getTimer();
            }
        }
        choose();
    }

    // After CHOOSE_MS, picks from the found ones according to preference
    private function choose() as Void {
        if (_firstSeen == 0 || System.getTimer() - _firstSeen < CHOOSE_MS) {
            return;
        }
        var names = _cands.keys();
        var best = null as BluetoothLowEnergy.ScanResult?;
        var bestRank = 0;
        for (var i = 0; i < names.size(); i++) {
            var r = _cands[names[i]] as BluetoothLowEnergy.ScanResult;
            var rank = pref == 0 ? historyRank(names[i] as String) * 1000 - r.getRssi() : -r.getRssi();
            if (best == null || rank < bestRank) {
                best = r;
                bestRank = rank;
            }
        }
        if (best != null) {
            connect(best);
        }
    }

    private function connect(r as BluetoothLowEnergy.ScanResult) as Void {
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        _cands = {} as Dictionary<String, BluetoothLowEnergy.ScanResult>;
        _firstSeen = 0;
        _downSince = 0;
        _state.deviceName = r.getDeviceName();
        setStatus(:stConnecting, "");
        try {
            _device = BluetoothLowEnergy.pairDevice(r);
            _pairSince = System.getTimer();
        } catch (e) {
            setStatus(:stPairErr, "");
            startScan();
        }
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            _pairSince = 0;
            _downSince = 0;
            _lastRx = System.getTimer();
            _divSent = 0;
            _setReq = 0;
            // A new Raysid or firmware may not send the overload flag;
            // the previous Raysid's settings no longer apply
            clearLive();
            _state.devDiv = null;
            _state.devSound = null;
            _state.devDoseAl = null;
            _state.devCpsAl = null;
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            _device = device;
            remember(device.getName() != null ? device.getName() : _state.deviceName);
            setStatus(:stConnected, "");
            _parser.reset();
            subscribe();
        } else {
            // Ignore a late disconnect of the old device after connecting a new one (or after
            // a restart, when scanning is already running)
            if (_device == null || _device.isConnected()) {
                return;
            }
            setStatus(:stDisconnected, "");
            _downSince = System.getTimer();
            clearLive();
            _queue = [];
            _busy = false;
            _setReq = 0;
            // The device stays paired, Connect IQ tries to restore the connection by itself.
        }
    }

    // Enables notifications on the data characteristic and sends the init commands.
    private function subscribe() as Void {
        var ch = characteristic(RaysidProtocol.notifyCharUuid());
        if (ch == null) {
            setStatus(:stNoService, "");
            _downSince = System.getTimer();
            return;
        }
        var cccd = ch.getDescriptor(BluetoothLowEnergy.cccdUuid());
        if (cccd != null) {
            enqueue([:cccd, cccd, [0x01, 0x00]b]);
        }
        var cmds = RaysidProtocol.initCommands();
        _setReq++;
        _setReqT = System.getTimer();
        for (var i = 0; i < cmds.size(); i++) {
            enqueue([:write, :seq, cmds[i]]);
        }
    }

    private function characteristic(uuid as BluetoothLowEnergy.Uuid) as BluetoothLowEnergy.Characteristic? {
        if (_device == null) {
            return null;
        }
        var svc = _device.getService(RaysidProtocol.serviceUuid());
        if (svc == null) {
            return null;
        }
        return svc.getCharacteristic(uuid);
    }

    function onTick() as Void {
        recorder().gcStep();
        recorder().compactTick();
        // Connecting did not finish in time: release the device and scan again
        if (_pairSince != 0 && System.getTimer() - _pairSince > CONNECT_TIMEOUT_MS) {
            _pairSince = 0;
            restart();
            return;
        }
        var now = System.getTimer();
        // The connection did not recover by itself, the service is missing or no data arrives:
        // release the device and scan again (not while pairing is in progress)
        var stale = _device != null && _device.isConnected() && _downSince == 0 && now - _lastRx > RECOVER_MS;
        if (_pairSince == 0 && ((_downSince != 0 && now - _downSince > RECOVER_MS) || stale)) {
            _downSince = 0;
            restart();
            return;
        }
        choose();
        WatchUi.requestUpdate(); // redraws the clock and grays out "stale" values
        if (_device == null || !_device.isConnected()) {
            return;
        }
        // The ping keeps the connection alive (without it the Raysid disconnects after 10 s): if the queue
        // is full, it goes to the front so it is not skipped. Do not split a settings read
        // in progress, it ends with a ping itself.
        var cmd = RaysidProtocol.pollCommand();
        if (cmd != null && now - _lastPing >= RaysidProtocol.POLL_MS - 500) {
            _lastPing = now;
            var seq = false;
            for (var i = 0; i < _queue.size(); i++) {
                if ((_queue[i] as Array)[1] == :seq) {
                    seq = true;
                }
            }
            if (!seq) {
                var q = [[:write, null, cmd]] as Array;
                for (var i = 0; i < _queue.size(); i++) {
                    q.add(_queue[i] as Array);
                }
                _queue = q;
            }
        }
        // Safety net: if a write confirmation never came, the queue would get stuck
        if (_busy && now - _busySince > 3000) {
            _busy = false;
        }
        pump();
    }

    var devMenu as WatchUi.Menu2? = null;   // open Raysid settings submenu

    // Divider sync: the Raysid gets the watch divider when they differ.
    // Only one attempt per difference, so a rejection does not cause a loop.
    private var _divSent as Number = 0;

    function syncDivider() as Void {
        var d = _state.devDiv;
        if (!_state.divLink || d == null || d == _state.divider) {
            _divSent = 0;
            return;
        }
        if (_state.divider <= 255 && _divSent != _state.divider && send(RaysidProtocol.dividerCommand(_state.divider))) {
            _divSent = _state.divider;
        }
    }

    // How many requested settings have not arrived yet. A reply to an older read
    // (before a change in the menu) would otherwise briefly revert the toggle.
    private var _setReq as Number = 0;
    private var _setReqT as Number = 0;

    // Ask the Raysid to send its settings (packet 0x0a)
    function requestSettings() as Void {
        if (_device == null || !(_device as BluetoothLowEnergy.Device).isConnected()) {
            return;
        }
        // Treat older unanswered reads as lost
        if (System.getTimer() - _setReqT > 3000) {
            _setReq = 0;
        }
        _setReq++;
        _setReqT = System.getTimer();
        var cmds = RaysidProtocol.settingsCommands();
        for (var i = 0; i < cmds.size(); i++) {
            enqueue([:write, :seq, cmds[i]]);
        }
    }

    private function updateDevMenu() as Void {
        var m = devMenu;
        if (m == null) {
            return;
        }
        var i = m.findItemById(:devDiv);
        if (i >= 0 && _state.devDiv != null) {
            (m.getItem(i) as WatchUi.MenuItem).setSubLabel(devDivLabel(_state, _state.devDiv as Number));
        }
        var ids = [:devSound, :devDoseAl, :devCpsAl];
        var vals = [_state.devSound, _state.devDoseAl, _state.devCpsAl];
        for (var k = 0; k < ids.size(); k++) {
            i = m.findItemById(ids[k]);
            if (i >= 0 && vals[k] != null) {
                var it = m.getItem(i) as WatchUi.ToggleMenuItem;
                it.setEnabled(vals[k] as Boolean);
                it.setSubLabel(null);
            }
        }
    }

    // Send a command to the Raysid; false if not connected
    function send(cmd as ByteArray) as Boolean {
        if (_device == null || !(_device as BluetoothLowEnergy.Device).isConnected()
                || characteristic(RaysidProtocol.writeCharUuid()) == null) {
            return false;
        }
        enqueue([:write, null, cmd]);
        // Immediately ask for the settings back, to be sure what the Raysid accepted
        requestSettings();
        return true;
    }

    // --- request queue ---

    private function enqueue(item as Array) as Void {
        _queue.add(item);
        pump();
    }

    private function pump() as Void {
        if (_busy || _queue.size() == 0) {
            return;
        }
        var item = _queue[0] as Array;
        _queue = _queue.slice(1, null);
        try {
            if (item[0] == :cccd) {
                (item[1] as BluetoothLowEnergy.Descriptor).requestWrite(item[2] as ByteArray);
            } else {
                var ch = characteristic(RaysidProtocol.writeCharUuid());
                if (ch == null) {
                    pump();
                    return;
                }
                ch.requestWrite(item[2] as ByteArray, {:writeType => RaysidProtocol.WRITE_TYPE});
            }
            _busy = true;
            _busySince = System.getTimer();
        } catch (e) {
            // Write rejected (e.g. the previous one is still running): drop the item and
            // try the next one only from onTick, so the whole queue including the ping is not drained
            _busy = true;
            _busySince = System.getTimer() - 3000;
        }
    }

    function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
        _busy = false;
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            setStatus(:stCccd, status.toString());
        }
        pump();
    }

    function onCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
        _busy = false;
        pump();
    }

    function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, value as ByteArray) as Void {
        _state.packets++;
        _lastRx = System.getTimer();
        if (_state.showDebug) {
            _state.lastRaw = RaysidProtocol.toHex(value);
        }
        // Debug: raw data to the log (looking for the Raysid overload flag)
        _parser.dbgLog = _state.showDebug;
        var m = _parser.feed(value);
        if (m != null) {
            if (m.hasKey(:battery)) {
                _state.battery = m[:battery] as Float;
            }
            if (_setReq > 0) {
                _setReq = m.hasKey(:devDiv) ? _setReq - 1 : _setReq;
            }
            var newest = _setReq == 0 || System.getTimer() - _setReqT > 3000;
            if (m.hasKey(:devDiv) && newest) {
                _setReq = 0;
                _state.devDiv = m[:devDiv] as Number;
                _state.devSound = m[:devSound] as Boolean;
                _state.devDoseAl = m[:devDoseAl] as Boolean;
                _state.devCpsAl = m[:devCpsAl] as Boolean;
                syncDivider();
                updateDevMenu();
                WatchUi.requestUpdate();
            }
            if (m.hasKey(:btn)) {
                requestSettings();   // settings changed by the button, into the Raysid menu
            }
            if (m.hasKey(:ovl)) {
                _state.devOvl = m[:ovl] as Boolean;
            }
            if (m.hasKey(:doseRate) || m.hasKey(:cps)) {
                if (m.hasKey(:doseRate)) {
                    _state.doseRate = m[:doseRate] as Float;
                }
                if (m.hasKey(:cps)) {
                    _state.cps = m[:cps] as Float;
                }
                var now = System.getTimer();
                if (_state.lastUpdate != null) {
                    var dt = (now - (_state.lastUpdate as Number)).toFloat();
                    _state.intervalMs = _state.intervalMs == null ? dt : (_state.intervalMs as Float) * 0.8 + dt * 0.2;
                    _state.lastIntervalMs = dt.toNumber();
                }
                _state.lastUpdate = now;
                if (_state.doseRate != null && _state.cps != null) {
                    _state.updateOvl(now, _state.doseRate as Float, _state.cps as Float);
                    // During overload the Raysid may report clipped (low) values:
                    // alarms get at least the overload limits so they do not go off
                    var aDose = _state.doseRate as Float;
                    var aCps = _state.cps as Float;
                    if (_state.doseOvlOn) {
                        aDose = aDose > OVL_DOSE ? aDose : OVL_DOSE;
                    }
                    if (_state.cpsOvlOn) {
                        aCps = aCps > OVL_CPS ? aCps : OVL_CPS;
                    }
                    var alarm = _alarms.evaluate(now, aDose, aCps);
                    _state.addSample(now, _state.doseRate as Float, _state.cps as Float, alarm);
                    // With the debug screen on, write measurements to the watch log
                    // (GARMIN/APPS/LOGS/<prg name>.TXT, must exist)
                    if (_state.showDebug && now - _logT >= 2000) {
                        _logT = now;
                        System.println(now + ";" + (_state.cps as Float).format("%.1f") + ";" + (_state.doseRate as Float).format("%.2f") + ";" + (_state.cpsOvlOn ? 1 : 0) + (_state.doseOvlOn ? 1 : 0));
                    }
                }
            }
        }
        if (_state.showDebug) {
            var keys = _parser.typeCounts.keys();
            var s = "";
            for (var i = 0; i < keys.size(); i++) {
                var k = keys[i] as Number;
                s += k.format("%02X") + ":" + _parser.typeCounts[k] + " ";
            }
            _state.typeInfo = s;
        }
        WatchUi.requestUpdate();
    }

    private function setStatus(s as Symbol, arg as String) as Void {
        _state.status = s;
        _state.statusArg = arg;
        WatchUi.requestUpdate();
    }
}
