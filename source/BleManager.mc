// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Skenovani, pripojeni k Raysidu, zapnuti notifikaci a prijem dat.
// Connect IQ dovoli jen jeden rozpracovany BLE pozadavek najednou,
// proto jsou zapisy (CCCD, prikazy) ve fronte _queue.
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
    private var _pairSince as Number = 0;   // kdy zacalo pripojovani (0 = neprobiha)
    private var _logT as Number = 0;        // posledni radek mereni v ladicim logu
    const CONNECT_TIMEOUT_MS = 15000;
    const RECOVER_MS = 30000;   // bez spojeni nebo bez dat tak dlouho: pripojit znovu
    private var _downSince as Number = 0;   // kdy spojeni spadlo / chybi sluzba (0 = v poradku)
    private var _lastRx as Number = 0;      // posledni prijata data
    private var _lastPing as Number = 0;
    const CHOOSE_MS = 3000;     // jak dlouho sbirat nalezene Raysidy, nez se vybere
    const HISTORY_MAX = 6;

    // Nastaveni pripojeni (ukladaji se)
    var pin as String? = null;     // vybrany Raysid (jmeno)
    var lock as Boolean = false;   // pripojovat jen vybrany
    var pref as Number = 0;        // pri vice kusech: 0 vybrany/znamy, 1 nejsilnejsi signal
    var history as Array<Array> = [] as Array<Array>;   // [[jmeno, unix cas], ...], nejnovejsi prvni

    // Raysidy nalezene v probihajicim hledani: jmeno -> ScanResult (nejsilnejsi)
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
            // "Jen vybrany" bez vybraneho nema smysl
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

    // "Jen vybrany" a pripojeny je jiny Raysid: pripojit vybrany
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

    // Pripojeny Raysid na zacatek historie; prvni pripojeny se stane vybranym
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
        // Vybranym se sam stane jen uplne prvni pripojeny Raysid; kdyz uzivatel
        // pozdeji zvoli "kterykoli", zustane to tak
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
        // Periodicky dotaz na data, pokud ho protokol vyzaduje
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
            register();   // registrace profilu se nepovedla: zkusit znovu
            return;
        }
        startScan();
    }

    // Po ztrate spojeni: alarmy a pretizeni zhasnout, nastaveni Raysidu neznama
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

    // Po aktualizaci aplikace (nahrani pres USB) muze Raysid zustat spojeny
    // s hodinkami z predchozi instance. Pak nevysila a skenovani ho nenajde,
    // dokud se hodinky nerestartuji. Takove spojeni prevezmeme, a kdyz uz
    // neni aktivni, zarizeni odparujeme, aby slo znovu najit.
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

    // Nalezene Raysidy se chvili sbiraji, aby se pri vice kusech dalo vybrat.
    // Vybrany Raysid se pripoji hned; s "jen vybrany" se ostatni ignoruji.
    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        // Opozdene vysledky po zahajeni pripojovani: neparovat podruhe
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
            // Vybrany hned, pokud se nema volit podle sily signalu
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

    // Po CHOOSE_MS vybere z nalezenych podle preference
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
            // Novy Raysid nebo firmware nemusi priznak pretizeni posilat;
            // nastaveni predchoziho Raysidu uz neplati
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
            // Opozdene odpojeni stareho zarizeni po pripojeni noveho (nebo po
            // restartu, kdy uz se hleda) ignorovat
            if (_device == null || _device.isConnected()) {
                return;
            }
            setStatus(:stDisconnected, "");
            _downSince = System.getTimer();
            clearLive();
            _queue = [];
            _busy = false;
            _setReq = 0;
            // Zarizeni zustava sparovane, Connect IQ se pokusi spojeni obnovit samo.
        }
    }

    // Zapne notifikace na datove charakteristice a posle inicializacni prikazy.
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
        // Pripojeni se nepovedlo vcas: zarizeni pustit a hledat znovu
        if (_pairSince != 0 && System.getTimer() - _pairSince > CONNECT_TIMEOUT_MS) {
            _pairSince = 0;
            restart();
            return;
        }
        var now = System.getTimer();
        // Spojeni se samo neobnovilo, chybi sluzba nebo neprichazeji data:
        // zarizeni pustit a hledat znovu (ne behem rozbehnuteho parovani)
        var stale = _device != null && _device.isConnected() && _downSince == 0 && now - _lastRx > RECOVER_MS;
        if (_pairSince == 0 && ((_downSince != 0 && now - _downSince > RECOVER_MS) || stale)) {
            _downSince = 0;
            restart();
            return;
        }
        choose();
        WatchUi.requestUpdate(); // prekresli hodiny a "zastarale" hodnoty sede
        if (_device == null || !_device.isConnected()) {
            return;
        }
        // Ping drzi spojeni (bez nej Raysid po 10 s odpoji): kdyz je fronta
        // plna, zaradi se na jeji zacatek, aby nevynechal. Rozpracovane cteni
        // nastaveni nerozdelit, samo konci pingem.
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
        // Pojistka: kdyby potvrzeni zapisu neprislo, fronta by se zasekla
        if (_busy && now - _busySince > 3000) {
            _busy = false;
        }
        pump();
    }

    var devMenu as WatchUi.Menu2? = null;   // otevrene podmenu nastaveni Raysidu

    // Slouceni delicky: Raysid dostane delicku hodinek, kdyz se lisi.
    // Jen jeden pokus na rozdil, at se pri odmitnuti nezacykli.
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

    // Kolik vyzadanych nastaveni jeste neprislo. Odpoved na starsi cteni
    // (pred zmenou v menu) by jinak prepinac na chvili vratila.
    private var _setReq as Number = 0;
    private var _setReqT as Number = 0;

    // Nechat si od Raysidu poslat nastaveni (paket 0x0a)
    function requestSettings() as Void {
        if (_device == null || !(_device as BluetoothLowEnergy.Device).isConnected()) {
            return;
        }
        // Starsi nevyrizena cteni povazovat za ztracena
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

    // Poslat prikaz do Raysidu; false, kdyz neni pripojeny
    function send(cmd as ByteArray) as Boolean {
        if (_device == null || !(_device as BluetoothLowEnergy.Device).isConnected()
                || characteristic(RaysidProtocol.writeCharUuid()) == null) {
            return false;
        }
        enqueue([:write, null, cmd]);
        // Hned si nechat poslat nastaveni zpet, at je jiste, co Raysid prijal
        requestSettings();
        return true;
    }

    // --- fronta pozadavku ---

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
            // Zapis odmitnut (napr. jeste bezi predchozi): polozku zahodit a
            // dalsi zkusit az z onTick, at se nevyprazdni cela fronta i s pingem
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
        // Ladeni: surova data do logu (hledame priznak pretizeni Raysidu)
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
                requestSettings();   // tlacitkem zmenene nastaveni do menu Raysid
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
                    // Pri pretizeni muze Raysid hlasit useknute (nizke) hodnoty:
                    // alarmy dostanou aspon meze pretizeni, aby nezhasly
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
                    // Pri zapnute ladici obrazovce zapis mereni do logu hodinek
                    // (GARMIN/APPS/LOGS/<jmeno prg>.TXT, musi existovat)
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
