// Raysid Garmin - Connect IQ app for the Raysid dosimeter
// Copyright (C) 2026 Vít Cenek and contributors (see AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 3 or (at your
// option) any later version, as published by the Free Software Foundation.
// It is distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Lang;
import Toybox.System;
import Toybox.Graphics;
import Toybox.Math;
import Toybox.WatchUi;

// Alarms. Evaluated on every new measurement from the Raysid (~0.25-2 s,
// so everything is computed by time, not by number of measurements).
//  - Fixed: dose rate or cps above the set limit. Sounds only once when
//    exceeded (tone and vibration per the set length, screen flash), then a red warning stays
//    on the display. Re-armed only after dropping below 90 % of the limit.
//  - Soft: watches for a rapid rise in cps over a moving background. Sensitivity sets
//    by how many percent cps must jump; the rise must also be statistically
//    significant (3 sigma of Poisson noise) so it does not trigger on random fluctuations.
//    After a minute the background adapts to the new level and the alarm ends.
class Alarms {
    const SOFT_MAX_MS = 60000;
    const WARMUP_MS = 20000;                    // background estimate before the first alarm
    const BASE_MS = 20000;                      // time constant of the moving background
    const QUIET_MS = 4000;                      // this long below the threshold = end of alarm

    private var _state as RaysidState;
    private var _baseline as Float? = null;
    private var _startT as Number = 0;          // first measurement for the background
    private var _lastT as Number = 0;
    private var _softSince as Number = 0;
    private var _quietSince as Number = 0;      // since when cps is below the threshold (0 = not)

    function initialize(state as RaysidState) {
        _state = state;
    }

    // Returns the alarm code for the chart history: 0 none, 1 soft, 2 fixed.
    // No connection: clear alarms and forget the baseline for rapid rise
    // (after reconnecting the Raysid may be elsewhere)
    function reset() as Void {
        _baseline = null;
        _softSince = 0;
        _quietSince = 0;
        _state.hardAlarm = false;
        _state.softAlarm = false;
        _state.seqLeft = 0;   // cut off remaining alarm tones and vibrations
    }

    function evaluate(now as Number, dose as Float, cps as Float) as Number {
        evaluateHard(now, dose, cps);
        evaluateSoft(now, cps);
        return _state.hardAlarm ? 2 : (_state.softAlarm ? 1 : 0);
    }

    private function evaluateHard(now as Number, dose as Float, cps as Float) as Void {
        var dLim = _state.doseLimit();
        var cLim = _state.cpsLimit();
        // On Raysid overload every enabled dose rate or cps alarm sounds
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
        var sigma = Math.sqrt(b / 2.0 + 1.0);    // cps noise (Raysid computes it from a window of about 2 s; unverified)
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
                // The background is learned only outside an alarm (~20 s moving average)
                var a = dt.toFloat() / BASE_MS;
                a = a < 0.0 ? 0.0 : (a > 1.0 ? 1.0 : a);
                _baseline = b * (1.0 - a) + cps * a;
            }
            return;
        }
        // During a soft alarm
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
                _baseline = cps;   // new background level
            }
        }
    }
}
