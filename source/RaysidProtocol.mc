// Raysid Garmin - Connect IQ app for the Raysid dosimeter
// Copyright (C) 2026 Vít Cenek and contributors (see AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 3 or (at your
// option) any later version, as published by the Free Software Foundation.
// It is distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Everything specific to the Raysid: UUIDs, ping and packet decoding.
// Source: https://raysid.com/api/ (API.md, cps-doserate.py).
module RaysidProtocol {
    const NAME_PREFIX = "raysid";       // compared case-insensitively
    // The Raysid disconnects if it gets no ping for 10 s; we send it with a margin.
    const POLL_MS = 4000;
    const WRITE_TYPE = BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE;
    // The "DR" value from packet 0x17 is in uR/h. 1 uSv/h ~ 100 uR/h.
    // If the value on the watch differs from the Raysid display by 100x, change to 1.0.
    const UR_PER_USV = 100.0;
    const ACTIVE_TAB = 0;               // 0 = main screen (telemetry)

    function serviceUuid() as BluetoothLowEnergy.Uuid {
        return BluetoothLowEnergy.stringToUuid("49535343-fe7d-4ae5-8fa9-9fafd205e455");
    }

    // RX: device -> watch (notify)
    function notifyCharUuid() as BluetoothLowEnergy.Uuid {
        return BluetoothLowEnergy.stringToUuid("49535343-1e4d-4bd9-ba61-23c647249616");
    }

    // TX: watch -> device (write)
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

    // Commands sent right after enabling notifications.
    function initCommands() as Array<ByteArray> {
        return settingsCommands();
    }

    // Request settings exactly like the official app: ping with screen 9
    // (settings), 0x1f 00, 0x1b 01 (the Raysid replies with packet 0x0a), 0x1b 02
    // and back to a ping with the main screen.
    const SETTINGS_TAB = 9;

    function settingsCommands() as Array<ByteArray> {
        return [ping(SETTINGS_TAB), command([0x1f, 0x00]b), command([0x1b, 0x01]b),
            command([0x1b, 0x02]b), ping(ACTIVE_TAB)];
    }

    // Command sent every POLL_MS.
    function pollCommand() as ByteArray? {
        return ping(ACTIVE_TAB);
    }

    // [0x12, tab, unix: 4B BE]
    function ping(tab as Number) as ByteArray {
        var t = Time.now().value();
        return command([0x12, tab,
            (t >> 24) & 0xFF, (t >> 16) & 0xFF, (t >> 8) & 0xFF, t & 0xFF]b);
    }

    // Settings stored in the Raysid itself. Not in API.md, sniffed from the official
    // app (btsnoop 14. 10. 2026): 0x16 N = sound divider 1:N
    // (1, 5, 10, 20, 50, 100, 250; 1 not sniffed), 0x03 X = sound signaling.
    function dividerCommand(n as Number) as ByteArray {
        return command([0x16, n & 0xFF]b);
    }

    // Alarms in the Raysid itself: 0x18 = dose rate alarm, 0x17 = cps alarm
    function doseAlarmCommand(on as Boolean) as ByteArray {
        return command([0x18, on ? 0x01 : 0x00]b);
    }

    function cpsAlarmCommand(on as Boolean) as ByteArray {
        return command([0x17, on ? 0x01 : 0x00]b);
    }

    // 0x03 01 turns sound (clicks) on, 0x03 00 turns it off
    function soundCommand(on as Boolean) as ByteArray {
        return command([0x03, on ? 0x01 : 0x00]b);
    }

    // Command frame: [0xFF] [CRC2] [0xEE] [CRC1: 4B BE] [payload] [TotalSize]
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

    // Sum of 4-byte little-endian chunks, modulo 2^32.
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

    // XOR of 3-byte chunks. API.md describes them as little-endian, cps-doserate.py
    // as big-endian; we do not know which applies to your firmware, so we accept both.
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

    // 16-bit value compression: v / 6000 is the number of multiplications by ten.
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

// Assembles packets from notifications (one packet may arrive in several pieces)
// and decodes them: [Size] [Type] [Payload] [Checksum3: 3B]
// Packet types seen from the Raysid (for detecting the delimiter)
const KNOWN_TYPES = [0x02, 0x03, 0x06, 0x0a, 0x17, 0x18, 0x21, 0x22, 0x23];

class RaysidParser {
    private var _buf as ByteArray = []b;
    private var _delim as Number? = null;     // delimiter between packets (seen 0x84, 0x10)
    private var _candidates as Dictionary = {};
    private var _afterPacket as Boolean = false;
    // Buffer position is the start of a packet (after a packet or delimiter). Not after
    // junk: then, with a known delimiter, we skip straight to the next delimiter.
    private var _sync as Boolean = true;
    private var _noPkt as Number = 0;          // notifications without a valid packet
    const JUNK_MAX = 120;      // bytes tried with a checksum per notification (watchdog)
    const RELEARN_AFTER = 10;  // this many notifications without a packet: relearn the delimiter
    var typeCounts as Dictionary<Number, Number> = {};   // packet counts by type (debug)
    var dbgLog as Boolean = false;   // debug log of selected packets (println)
    private var _dbgLast as Dictionary = {};   // last logged content by type

    function initialize() {}

    function reset() as Void {
        _buf = []b;
        _afterPacket = false;
        _sync = true;
        _noPkt = 0;
        // After a Raysid restart the delimiter may change (seen 0x84 -> 0x10)
        _delim = null;
        _candidates = {};
    }

    // Returns {:cps, :doseRate (uSv/h), :battery, :temp}, only the keys present in the data; or null.
    function feed(value as ByteArray) as Dictionary? {
        _buf.addAll(value);
        if (_buf.size() > 1024) {
            _buf = _buf.slice(_buf.size() - 512, null);
            _sync = false;
        }
        var out = {};
        var pos = 0;
        var junk = 0;   // bytes skipped while trying the checksum
        var found = false;
        while (pos < _buf.size()) {
            // Junk (bad length/checksum): do not keep trying every byte forever,
            // otherwise the watchdog may fire; drop it and wait for more data
            if (junk > JUNK_MAX) {
                pos = _buf.size();
                _sync = false;
                break;
            }
            var b = _buf[pos];
            // Delimiter before the next packet
            if (_delim != null && b == _delim && (_afterPacket || !_sync)) {
                pos++;
                _afterPacket = false;
                _sync = true;
                continue;
            }
            // After junk with a known delimiter: skip up to it (no checksum)
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
            // Is the byte a delimiter? A valid packet starts right after it.
            if (pos + 1 < _buf.size()) {
                var l2 = _buf[pos + 1];
                // Checksum only for a known packet type (saves time on junk)
                if (l2 >= 4 && pos + 1 + l2 <= _buf.size() && KNOWN_TYPES.indexOf(_buf[pos + 2]) >= 0
                        && RaysidProtocol.checksumOk(_buf, pos + 1, l2)) {
                    learnDelimiter(b);
                    pos++;
                    _sync = true;
                    continue;
                }
            }
            if (_sync && len >= 4 && pos + len > _buf.size()) {
                break; // waiting for the rest of the packet
            }
            pos++;
            junk++;
            _sync = false;
        }
        _buf = pos >= _buf.size() ? []b : _buf.slice(pos, null);
        // The delimiter changed (Raysid restart without disconnecting): relearn it
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

    // Log only events and changes: 0x17 when the overload flag changes,
    // 0x22/0x18/0x23 always, others except spectrum and periodic status on change
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
            // Chunks [RangeType] [LSB] [MSB]; 0 = CPS, 1 = dose rate (uR/h)
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
            // The byte before the checksum = Raysid overload flag (01 when the
            // red LED is blinking, sniffed 14. 10. 2026)
            if ((size - 5) % 3 == 1) {
                out[:ovl] = p[size - 4] != 0;
            }
        } else if (type == 0x18) {
            // Raysid button action: [function, new state]; 02 = clicks,
            // 03 = alarms (sniffed 14. 10. 2026)
            out[:btn] = true;
        } else if (type == 0x0a && size >= 14) {
            // Raysid settings (sniffed 14. 10. 2026): [4] divider 1:N,
            // [6] click sound, [10] alarms: bit 0x10 dose rate, 0x01 cps
            out[:devDiv] = p[4];
            out[:devSound] = p[6] != 0;
            out[:devDoseAl] = (p[10] & 0x10) != 0;
            out[:devCpsAl] = (p[10] & 0x01) != 0;
        } else if (type == 0x02 && size >= 9) {
            out[:temp] = (p[2] | (p[3] << 8)) / 10.0 - 100.0;
            // API.md says divide by 10, but the real Raysid sends the percentage directly
            out[:battery] = (p[4] | (p[5] << 8)).toFloat();
        }
    }
}
