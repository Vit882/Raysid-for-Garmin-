// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Vse, co je specificke pro Raysid: UUID, ping a dekodovani paketu.
// Zdroj: https://raysid.com/api/ (API.md, cps-doserate.py).
module RaysidProtocol {
    const NAME_PREFIX = "raysid";       // porovnava se bez ohledu na velikost pismen
    // Raysid se odpoji, kdyz 10 s nedostane ping; posilame ho s rezervou.
    const POLL_MS = 4000;
    const WRITE_TYPE = BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE;
    // Hodnota "DR" z paketu 0x17 je v uR/h. 1 uSv/h ~ 100 uR/h.
    // Pokud by se hodnota na hodinkach lisila od displeje Raysidu 100x, zmen na 1.0.
    const UR_PER_USV = 100.0;
    const ACTIVE_TAB = 0;               // 0 = hlavni obrazovka (telemetrie)

    function serviceUuid() as BluetoothLowEnergy.Uuid {
        return BluetoothLowEnergy.stringToUuid("49535343-fe7d-4ae5-8fa9-9fafd205e455");
    }

    // RX: zarizeni -> hodinky (notify)
    function notifyCharUuid() as BluetoothLowEnergy.Uuid {
        return BluetoothLowEnergy.stringToUuid("49535343-1e4d-4bd9-ba61-23c647249616");
    }

    // TX: hodinky -> zarizeni (write)
    function writeCharUuid() as BluetoothLowEnergy.Uuid {
        return BluetoothLowEnergy.stringToUuid("49535343-8841-43f4-a8d4-ecbe34729bb3");
    }

    function profile() as {
        :uuid as BluetoothLowEnergy.Uuid,
        :characteristics as Array<{ :uuid as BluetoothLowEnergy.Uuid, :descriptors as Array<BluetoothLowEnergy.Uuid> }>
    } {
        return {
            :uuid => serviceUuid(),
            :characteristics => [
                { :uuid => notifyCharUuid(), :descriptors => [BluetoothLowEnergy.cccdUuid()] },
                { :uuid => writeCharUuid(), :descriptors => [] as Array<BluetoothLowEnergy.Uuid> }
            ]
        };
    }

    function matches(r as BluetoothLowEnergy.ScanResult) as Boolean {
        var name = r.getDeviceName();
        if (name != null && name.toLower().find(NAME_PREFIX) != null) {
            return true;
        }
        var uuids = r.getServiceUuids();
        for (var u = uuids.next(); u != null; u = uuids.next()) {
            if (serviceUuid().equals(u)) {
                return true;
            }
        }
        return false;
    }

    // Prikazy poslane hned po zapnuti notifikaci.
    function initCommands() as Array<ByteArray> {
        return settingsCommands();
    }

    // Vyzadani nastaveni presne jako oficialni aplikace: ping s obrazovkou 9
    // (nastaveni), 0x1f 00, 0x1b 01 (Raysid odpovi paketem 0x0a), 0x1b 02
    // a zpet ping s hlavni obrazovkou.
    const SETTINGS_TAB = 9;

    function settingsCommands() as Array<ByteArray> {
        return [ping(SETTINGS_TAB), command([0x1f, 0x00]b), command([0x1b, 0x01]b),
            command([0x1b, 0x02]b), ping(ACTIVE_TAB)];
    }

    // Prikaz posilany kazdou POLL_MS.
    function pollCommand() as ByteArray? {
        return ping(ACTIVE_TAB);
    }

    // [0x12, tab, unix: 4B BE]
    function ping(tab as Number) as ByteArray {
        var t = Time.now().value();
        return command([0x12, tab,
            (t >> 24) & 0xFF, (t >> 16) & 0xFF, (t >> 8) & 0xFF, t & 0xFF]b);
    }

    // Nastaveni primo v Raysidu. Neni v API.md, odposlechnuto z oficialni
    // aplikace (btsnoop 14. 10. 2026): 0x16 N = delicka zvuku 1:N
    // (1, 5, 10, 20, 50, 100, 250; 1 neodposlechnuto), 0x03 X = zvukova signalizace.
    function dividerCommand(n as Number) as ByteArray {
        return command([0x16, n & 0xFF]b);
    }

    // Alarmy primo v Raysidu: 0x18 = alarm davkoveho prikonu, 0x17 = alarm cps
    function doseAlarmCommand(on as Boolean) as ByteArray {
        return command([0x18, on ? 0x01 : 0x00]b);
    }

    function cpsAlarmCommand(on as Boolean) as ByteArray {
        return command([0x17, on ? 0x01 : 0x00]b);
    }

    // 0x03 01 zvuk (kliky) zapne, 0x03 00 vypne
    function soundCommand(on as Boolean) as ByteArray {
        return command([0x03, on ? 0x01 : 0x00]b);
    }

    // Ramec prikazu: [0xFF] [CRC2] [0xEE] [CRC1: 4B BE] [payload] [TotalSize]
    function command(payload as ByteArray) as ByteArray {
        var c1 = crc1(payload);
        var inner = [0xEE,
            ((c1 >> 24) & 0xFF).toNumber(), ((c1 >> 16) & 0xFF).toNumber(),
            ((c1 >> 8) & 0xFF).toNumber(), (c1 & 0xFF).toNumber()]b;
        inner.addAll(payload);
        var crc2 = 0;
        for (var i = 0; i < inner.size(); i++) {
            crc2 ^= inner[i];
        }
        var out = [0xFF, crc2]b;
        out.addAll(inner);
        out.add(out.size() + 1);
        return out;
    }

    // Soucet 4bajtovych little-endian bloku, modulo 2^32.
    function crc1(data as ByteArray) as Long {
        var crc = 0l;
        for (var i = 0; i < data.size(); i += 4) {
            var v = 0l;
            for (var k = 0; k < 4 && i + k < data.size(); k++) {
                v |= (data[i + k].toLong() << (8 * k));
            }
            crc += v;
        }
        return crc & 0xFFFFFFFFl;
    }

    // XOR 3bajtovych bloku. API.md je popisuje little-endian, cps-doserate.py
    // big-endian; nevime, ktere plati pro tvuj firmware, tak prijimame obe.
    function checksumOk(buf as ByteArray, start as Number, len as Number) as Boolean {
        var le = 0;
        var be = 0;
        var n = len - 3;
        for (var i = 0; i < n; i += 3) {
            var b0 = buf[start + i];
            var b1 = i + 1 < n ? buf[start + i + 1] : 0;
            var b2 = i + 2 < n ? buf[start + i + 2] : 0;
            le ^= b0 | (b1 << 8) | (b2 << 16);
            be ^= (b0 << 16) | (b1 << 8) | b2;
        }
        var e = start + len;
        var rx = buf[e - 3] | (buf[e - 2] << 8) | (buf[e - 1] << 16);
        return rx != 0 && (rx == le || rx == be);
    }

    // Komprese 16bitovych hodnot: v / 6000 je pocet nasobeni deseti.
    function unpackValue(v as Number) as Float {
        var res = (v % 6000).toFloat();
        for (var i = 0; i < v / 6000; i++) {
            res *= 10.0;
        }
        return res;
    }

    function toHex(b as ByteArray) as String {
        var s = "";
        for (var i = 0; i < b.size(); i++) {
            s += b[i].format("%02X");
        }
        return s;
    }
}

// Sklada pakety z notifikaci (jeden paket muze prijit ve vice kusech)
// a dekoduje je: [Size] [Type] [Payload] [Checksum3: 3B]
// Typy paketu videne z Raysidu (pro rozpoznani oddelovace)
const KNOWN_TYPES = [0x02, 0x03, 0x06, 0x0a, 0x17, 0x18, 0x21, 0x22, 0x23];

class RaysidParser {
    private var _buf as ByteArray = []b;
    private var _delim as Number? = null;     // oddelovac mezi pakety (videno 0x84, 0x10)
    private var _candidates as Dictionary = {};
    private var _afterPacket as Boolean = false;
    // Pozice v bufferu je zacatek paketu (po paketu nebo oddelovaci). Po smeti
    // ne: pak se se znamym oddelovacem preskoci rovnou na dalsi oddelovac.
    private var _sync as Boolean = true;
    private var _noPkt as Number = 0;          // notifikaci bez platneho paketu
    const JUNK_MAX = 120;      // bajtu se zkouskou souctu za notifikaci (watchdog)
    const RELEARN_AFTER = 10;  // tolik notifikaci bez paketu: oddelovac se uci znovu
    var typeCounts as Dictionary<Number, Number> = {};   // pocty paketu podle typu (debug)
    var dbgLog as Boolean = false;   // ladici log vybranych paketu (println)
    private var _dbgLast as Dictionary = {};   // posledni zapsany obsah podle typu

    function initialize() {}

    function reset() as Void {
        _buf = []b;
        _afterPacket = false;
        _sync = true;
        _noPkt = 0;
        // Po restartu Raysidu se oddelovac muze zmenit (videno 0x84 -> 0x10)
        _delim = null;
        _candidates = {};
    }

    // Vrati {:cps, :doseRate (uSv/h), :battery, :temp}, jen klice, ktere v datech byly; nebo null.
    function feed(value as ByteArray) as Dictionary? {
        _buf.addAll(value);
        if (_buf.size() > 1024) {
            _buf = _buf.slice(_buf.size() - 512, null);
            _sync = false;
        }
        var out = {};
        var pos = 0;
        var junk = 0;   // bajtu preskocenych se zkouskou souctu
        var found = false;
        while (pos < _buf.size()) {
            // Smeti (spatna delka/soucet): nezkouset donekonecna kazdy bajt,
            // jinak hrozi watchdog; zahodit a cekat na dalsi data
            if (junk > JUNK_MAX) {
                pos = _buf.size();
                _sync = false;
                break;
            }
            var b = _buf[pos];
            // Oddelovac pred dalsim paketem
            if (_delim != null && b == _delim && (_afterPacket || !_sync)) {
                pos++;
                _afterPacket = false;
                _sync = true;
                continue;
            }
            // Po smeti se znamym oddelovacem: preskocit az k nemu (bez souctu)
            if (_delim != null && !_sync) {
                pos++;
                continue;
            }
            _afterPacket = false;
            var len = b;
            if (len >= 4 && pos + len <= _buf.size() && RaysidProtocol.checksumOk(_buf, pos, len)) {
                decode(_buf.slice(pos, pos + len), out);
                pos += len;
                _afterPacket = true;
                _sync = true;
                found = true;
                continue;
            }
            // Je bajt oddelovac? Hned za nim zacina platny paket.
            if (pos + 1 < _buf.size()) {
                var l2 = _buf[pos + 1];
                // Soucet jen u znameho typu paketu (setri cas na smeti)
                if (l2 >= 4 && pos + 1 + l2 <= _buf.size() && KNOWN_TYPES.indexOf(_buf[pos + 2]) >= 0
                        && RaysidProtocol.checksumOk(_buf, pos + 1, l2)) {
                    learnDelimiter(b);
                    pos++;
                    _sync = true;
                    continue;
                }
            }
            if (_sync && len >= 4 && pos + len > _buf.size()) {
                break; // cekame na zbytek paketu
            }
            pos++;
            junk++;
            _sync = false;
        }
        _buf = pos >= _buf.size() ? []b : _buf.slice(pos, null);
        // Oddelovac se zmenil (restart Raysidu bez odpojeni): naucit znovu
        _noPkt = found ? 0 : _noPkt + 1;
        if (_noPkt > RELEARN_AFTER && _delim != null) {
            _delim = null;
            _candidates = {};
            _sync = true;
            _noPkt = 0;
        }
        return out.size() > 0 ? out : null;
    }

    private function learnDelimiter(b as Number) as Void {
        if (_delim != null) {
            return;
        }
        var c = _candidates.hasKey(b) ? (_candidates[b] as Number) + 1 : 1;
        _candidates[b] = c;
        if (c >= 3) {
            _delim = b;
        }
    }

    // Do logu jen udalosti a zmeny: 0x17 pri zmene priznaku pretizeni,
    // 0x22/0x18/0x23 vzdy, ostatni krome spektra a periodickych stavu pri zmene
    private function logPacket(type as Number, p as ByteArray) as Void {
        if (type == 0x21 || type == 0x02 || type == 0x06) {
            return;
        }
        var size = p.size();
        var key = type == 0x17 ? (p[size - 4] != 0 ? "1" : "0") : RaysidProtocol.toHex(p);
        var always = type == 0x22 || type == 0x18 || type == 0x23;
        if (!always && _dbgLast.hasKey(type) && (_dbgLast[type] as String).equals(key)) {
            return;
        }
        _dbgLast[type] = key;
        System.println(System.getTimer() + ";P;" + RaysidProtocol.toHex(p));
    }

    private function decode(p as ByteArray, out as Dictionary) as Void {
        var size = p.size();
        var type = p[1];
        typeCounts[type] = typeCounts.hasKey(type) ? (typeCounts[type] as Number) + 1 : 1;
        if (dbgLog) {
            logPacket(type, p);
        }
        if (type == 0x17) {
            // Bloky [RangeType] [LSB] [MSB]; 0 = CPS, 1 = davkovy prikon (uR/h)
            var off = 2;
            while (off + 2 < size - 3) {
                var range = p[off];
                var v = RaysidProtocol.unpackValue(p[off + 1] | (p[off + 2] << 8)) / 600.0;
                if (range == 0) {
                    out[:cps] = v;
                } else if (range == 1) {
                    out[:doseRate] = v / RaysidProtocol.UR_PER_USV;
                }
                off += 3;
            }
            // Bajt pred kontrolnim souctem = priznak pretizeni Raysidu (01 pri
            // cervene blikajici LED, odposlechnuto 14. 10. 2026)
            if ((size - 5) % 3 == 1) {
                out[:ovl] = p[size - 4] != 0;
            }
        } else if (type == 0x18) {
            // Akce tlacitka na Raysidu: [funkce, novy stav]; 02 = cvakani,
            // 03 = alarmy (odposlechnuto 14. 10. 2026)
            out[:btn] = true;
        } else if (type == 0x0a && size >= 14) {
            // Nastaveni Raysidu (odposlechnuto 14. 10. 2026): [4] delicka 1:N,
            // [6] zvuk kliku, [10] alarmy: bit 0x10 davkovy prikon, 0x01 cps
            out[:devDiv] = p[4];
            out[:devSound] = p[6] != 0;
            out[:devDoseAl] = (p[10] & 0x10) != 0;
            out[:devCpsAl] = (p[10] & 0x01) != 0;
        } else if (type == 0x02 && size >= 9) {
            out[:temp] = (p[2] | (p[3] << 8)) / 10.0 - 100.0;
            // API.md uvadi deleni 10, skutecny Raysid ale posila primo procenta
            out[:battery] = (p[4] | (p[5] << 8)).toFloat();
        }
    }
}
