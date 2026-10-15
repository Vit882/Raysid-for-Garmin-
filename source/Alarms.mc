// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.Lang;
import Toybox.System;
import Toybox.Graphics;
import Toybox.Math;
import Toybox.WatchUi;

// Alarmy. Vyhodnocuji se pri kazdem novem mereni z Raysidu (~0,25-2 s,
// proto se vse pocita podle casu, ne podle poctu mereni).
//  - Pevny: davka nebo cps nad nastavenou mez. Ozve se jen jednou pri
//    prekroceni (ton a vibrace podle nastavene delky, probliknuti), pak zustane cervene upozorneni
//    na displeji. Znovu se aktivuje az po poklesu pod 90 % meze.
//  - Mekky: hlida prudky narust cps proti klouzavemu pozadi. Citlivost urcuje,
//    o kolik procent musi cps vyskocit; navic musi byt narust statisticky
//    vyznamny (3 sigma Poissonova sumu), aby nespoustel na nahodnych vykyvech.
//    Po minute trvani se pozadi prizpusobi nove urovni a alarm skonci.
class Alarms {
    const SOFT_MAX_MS = 60000;
    const WARMUP_MS = 20000;                    // odhad pozadi pred prvnim alarmem
    const BASE_MS = 20000;                      // casova konstanta klouzaveho pozadi
    const QUIET_MS = 4000;                      // tak dlouho pod hranici = konec alarmu

    private var _state as RaysidState;
    private var _baseline as Float? = null;
    private var _startT as Number = 0;          // prvni mereni pro pozadi
    private var _lastT as Number = 0;
    private var _softSince as Number = 0;
    private var _quietSince as Number = 0;      // od kdy je cps pod hranici (0 = neni)

    function initialize(state as RaysidState) {
        _state = state;
    }

    // Vraci kod alarmu pro historii grafu: 0 zadny, 1 mekky, 2 pevny.
    // Bez spojeni: alarmy zhasnout a zapomenout zaklad pro prudky narust
    // (po navratu muze byt Raysid jinde)
    function reset() as Void {
        _baseline = null;
        _softSince = 0;
        _quietSince = 0;
        _state.hardAlarm = false;
        _state.softAlarm = false;
        _state.seqLeft = 0;   // dobihajici tony a vibrace alarmu utnout
    }

    function evaluate(now as Number, dose as Float, cps as Float) as Number {
        evaluateHard(now, dose, cps);
        evaluateSoft(now, cps);
        return _state.hardAlarm ? 2 : (_state.softAlarm ? 1 : 0);
    }

    private function evaluateHard(now as Number, dose as Float, cps as Float) as Void {
        var dLim = _state.doseLimit();
        var cLim = _state.cpsLimit();
        // Pri pretizeni Raysidu se ozve kazdy zapnuty alarm davky nebo cps
        var ovl = _state.ovl && (dLim > 0.0 || cLim > 0);
        var over = ovl || (dLim > 0.0 && dose >= dLim) || (cLim > 0 && cps >= cLim);
        var clear = !ovl && (dLim <= 0.0 || dose < dLim * 0.9) && (cLim <= 0 || cps < cLim * 0.9);
        if (!_state.hardAlarm && over) {
            _state.hardAlarm = true;
            _state.flashUntil = _state.alarmFlash ? now + 1500 : 0;
            _state.flashColor = Graphics.COLOR_RED;
            _state.startAlarm(2, now);
        } else if (_state.hardAlarm && clear) {
            _state.hardAlarm = false;
        }
    }

    private function evaluateSoft(now as Number, cps as Float) as Void {
        var f = _state.softFactor();
        if (f <= 0.0) {
            _state.softAlarm = false;
            _baseline = null;
            return;
        }
        if (_baseline == null) {
            _baseline = cps;
            _startT = now;
            _lastT = now;
            return;
        }
        var dt = now - _lastT;
        _lastT = now;
        var b = _baseline as Float;
        var rise = cps - b;
        var sigma = Math.sqrt(b / 2.0 + 1.0);    // sum cps (Raysid je pocita z okna asi 2 s; neovereno)
        var significant = rise > b * f && rise > 3.0 * sigma;

        if (!_state.softAlarm) {
            if (now - _startT > WARMUP_MS && significant) {
                _state.softAlarm = true;
                _softSince = now;
                _quietSince = 0;
                if (!_state.hardAlarm) {
                    _state.flashUntil = _state.alarmFlash ? now + 600 : 0;
                    _state.flashColor = 0xAA0000;
                }
                if (!_state.hardAlarm) {
                    _state.startAlarm(1, now);
                }
            } else {
                // Pozadi se uci jen mimo alarm (~20 s klouzavy prumer)
                var a = dt.toFloat() / BASE_MS;
                a = a < 0.0 ? 0.0 : (a > 1.0 ? 1.0 : a);
                _baseline = b * (1.0 - a) + cps * a;
            }
            return;
        }
        // Behem mekkeho alarmu
        if (cps < b * (1.0 + f / 2.0)) {
            if (_quietSince == 0) {
                _quietSince = now;
            }
        } else {
            _quietSince = 0;
        }
        var quiet = _quietSince != 0 && now - _quietSince >= QUIET_MS;
        if (quiet || now - _softSince > SOFT_MAX_MS) {
            _state.softAlarm = false;
            _quietSince = 0;
            if (!quiet) {
                _baseline = cps;   // nova uroven pozadi
            }
        }
    }
}
