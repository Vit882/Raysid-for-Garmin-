// Raysid Garmin - Connect IQ app for the Raysid dosimeter
// Copyright (C) 2026 Vít Cenek and contributors (see AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 3 or (at your
// option) any later version, as published by the Free Software Foundation.
// It is distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Shared measurement state. Updated by BleManager, drawn by RaysidView.
function clamp(v as Number, lo as Number, hi as Number) as Number {
    return v < lo ? lo : (v > hi ? hi : v);
}

// Write to app storage that does not crash when storage is full
// (returns false; the caller may stop recording)
function put(key as String, value as Storage.ValueType) as Boolean {
    try {
        Storage.setValue(key, value);
        return true;
    } catch (e) {
        return false;
    }
}

class RaysidState {
    var status as Symbol = :stStart;   // translation key (Tr), translated only when drawing
    var statusArg as String = "";       // optional error code after the status
    var deviceName as String? = null;
    var doseRate as Float? = null;     // uSv/h
    var cps as Float? = null;          // counts per second
    var battery as Float? = null;      // Raysid battery in %
    // Settings in the Raysid per its last report (null = not received yet)
    var devDiv as Number? = null;
    var devSound as Boolean? = null;
    var devDoseAl as Boolean? = null;
    var devCpsAl as Boolean? = null;
    var lastUpdate as Number? = null;  // System.getTimer() ms
    var packets as Number = 0;
    var lastRaw as String = "";        // hex of the last packet (debug)
    var showDebug as Boolean = false;
    var devOvl as Boolean? = null;     // overload flag from the Raysid (null = not received)

    // Settings (persisted between launches)
    var backlight as Boolean = false;  // display stays lit the whole time the app runs
    var sound as Boolean = false;      // beeping by cps
    var led as Boolean = false;        // flashlight blink by cps
    var divider as Number = 10;        // 1 beep per N counts
    var divLink as Boolean = false;    // watch divider linked to the Raysid divider
    var overload as Boolean = false;   // beeper temporarily off due to high cps
    var vibeOver as Boolean = false;   // vibration on counts above the motor limit (4/s)
    var chartSec as Number = 30;       // chart length in seconds (10 to 60)
    var swapMain as Boolean = false;   // main screen: cps large on top, dose below it
    var vibrate as Boolean = false;    // vibration on counts (only up to VIBE_MAX_RATE per second)
    var alarmSound as Boolean = true;  // alarm tone
    var alarmVibe as Boolean = true;   // alarm vibration
    var alarmFlash as Boolean = true;  // screen flash on alarm
    var alarmRedLed as Boolean = true; // red flashlight during an alarm (when blinking is on)
    var alarmLen as Number = 1;        // alarm length: 0 short, 1 medium, 2 long
    var alarmsOn as Boolean = true;    // master switch for all alarms
    var doseOn as Boolean = false;
    var alarmDose as Float = 1.0;      // dose alarm threshold in uSv/h
    var cpsOn as Boolean = false;
    var alarmCps as Number = 1000;     // cps alarm threshold
    var softOn as Boolean = false;
    var softPct as Number = 50;        // rise detection sensitivity in % above background

    var hardAlarm as Boolean = false;
    var softAlarm as Boolean = false;
    var flashUntil as Number = 0;      // until when the screen flashes (System.getTimer)
    var flashColor as Number = 0xFF0000;

    // Alarm signaling in progress: remaining bursts, kind (1 soft, 2 hard), time of the next burst
    var seqLeft as Number = 0;
    var seqKind as Number = 0;
    var seqNext as Number = 0;

    var page as Number = 0;            // 0 = values, 1 = chart, 2 = mapping
    var intervalMs as Float? = null;   // average interval between measurements from the Raysid
    var lastIntervalMs as Number? = null;
    var ovl as Boolean = false;       // some quantity is in OVL (points are not written)
    var cpsOvlOn as Boolean = false;  // cps in OVL: holds until the dose drops below OVL_RESET_DOSE
    var doseOvlOn as Boolean = false; // dose above OVL_DOSE: holds until it drops below OVL_DOSE_RESET
    // Averaging of displayed values: 0 instant, 1 by time, 2 by number of measurements.
    // Only raw measurements are stored; the average is computed when drawing, so a change
    // of the setting applies immediately to the whole chart too. Alarms, clicks and mapping
    // points always use instant values.
    var avgMode as Number = 0;
    var avgSec as Number = 10;
    var avgN as Number = 5;
    var smDose as Array<Float> = new Array<Float>[HIST];   // averaged values for the chart
    var smCps as Array<Float> = new Array<Float>[HIST];
    var typeInfo as String = "";       // counts of received packet types (debug)

    // History for the chart: ring buffer, always filled (it is cheap),
    // drawn only when the chart is on screen.
    // 600 measurements: at ~0.25 s between measurements about 2.5 min, enough for a 60 s chart
    const HIST = 600;
    var histT as Array<Number> = new Array<Number>[HIST];
    var histDose as Array<Float> = new Array<Float>[HIST];
    var histCps as Array<Float> = new Array<Float>[HIST];
    var histAlarm as Array<Number> = new Array<Number>[HIST];   // 0 none, 1 soft, 2 hard alarm
    var histHead as Number = 0;        // index of the next write
    var histCount as Number = 0;

    function initialize() {
        backlight = load("bl", backlight) as Boolean;
        sound = load("snd", sound) as Boolean;
        led = load("led", led) as Boolean;
        divider = load("div", divider) as Number;
        divLink = load("dvL", divLink) as Boolean;
        // Older custom value: the nearest from the offered list (1, 5, 10, 20, 50, 100, 250)
        var best = 1;
        for (var i = 0; i < DIVIDERS.size(); i++) {
            var d = DIVIDERS[i] as Number;
            if ((d - divider).abs() < (best - divider).abs()) {
                best = d;
            }
        }
        if (best != divider) {
            divider = best;
        }
        chartSec = load("cw", chartSec) as Number;
        swapMain = load("swap", swapMain) as Boolean;
        avgMode = load("avM", avgMode) as Number;
        avgSec = load("avS", avgSec) as Number;
        avgN = load("avN", avgN) as Number;
        // A damaged or old value would crash the menu (index out of range)
        avgMode = clamp(avgMode, 0, 2);
        avgSec = clamp(avgSec, 2, 60);
        avgN = clamp(avgN, 2, 30);
        // Older versions also had other ranges; 10 to 60 s is allowed
        if (chartSec > 60) {
            chartSec = 60;
        } else if (chartSec < 10) {
            chartSec = 10;
        }
        vibrate = load("vib", vibrate) as Boolean;
        // Older versions had 0 = off directly in the value; we convert it to switches
        var sl = load("sl", 2) as Number;
        softOn = load("slOn", sl > 0) as Boolean;
        softPct = clamp(load("sp", [50, 30, 50, 100][sl < 0 || sl > 3 ? 0 : sl] as Number) as Number, 10, 300);
        alarmSound = load("aSnd", alarmSound) as Boolean;
        alarmVibe = load("aVib", alarmVibe) as Boolean;
        alarmFlash = load("aFl", alarmFlash) as Boolean;
        alarmRedLed = load("aRed", alarmRedLed) as Boolean;
        alarmLen = clamp(load("aLen", alarmLen) as Number, 0, 2);
        // Clean up the removed log backup from build 68
        if (Storage.getValue("lgI") != null) {
            for (var i = 0; i < 20; i++) {
                Storage.deleteValue("lg" + i);
            }
            Storage.deleteValue("lgI");
        }
        var ac = load("ac", alarmCps) as Number;
        cpsOn = load("acOn", ac > 0) as Boolean;
        alarmCps = ac > 0 ? clamp(ac, 5, ALARM_CPS_MAX) : 1000;
        var ad = Storage.getValue("ad");
        var adv = ad instanceof Float ? ad : (ad instanceof Number ? ad.toFloat() : alarmDose);
        doseOn = load("adOn", ad != null && adv > 0.0) as Boolean;
        alarmDose = adv > 0.0 ? (adv > ALARM_DOSE_MAX ? ALARM_DOSE_MAX : (adv < 0.05 ? 0.05 : adv)) : 1.0;
        alarmsOn = load("aOn", alarmsOn) as Boolean;
        // Language: on first launch by the watch language (Czech, Polish, otherwise English)
        var sysLang = System.getDeviceSettings().systemLanguage;
        var defLang = sysLang == System.LANGUAGE_CES ? 0 : (sysLang == System.LANGUAGE_POL ? 2 : 1);
        Tr.lang = clamp(load("lang", defLang) as Number, 0, 2);
    }

    // Actually effective thresholds (0 = alarm inactive)
    function doseLimit() as Float {
        return alarmsOn && doseOn ? alarmDose : 0.0;
    }

    function cpsLimit() as Number {
        return alarmsOn && cpsOn ? alarmCps : 0;
    }

    // Relative rise above background for the soft alarm, 0 = off
    function softFactor() as Float {
        return alarmsOn && softOn ? softPct / 100.0 : 0.0;
    }

    // Starts alarm signaling; number of bursts by the set length
    function startAlarm(kind as Number, now as Number) as Void {
        var bursts = [1, 3, 8];
        seqKind = kind;
        seqLeft = bursts[alarmLen < 0 || alarmLen > 2 ? 1 : alarmLen] as Number;
        seqNext = now;
    }

    function addSample(t as Number, dose as Float, cps as Float, alarm as Number) as Void {
        histAlarm[histHead] = alarm;
        histT[histHead] = t;
        histDose[histHead] = dose;
        histCps[histHead] = cps;
        histHead = (histHead + 1) % HIST;
        if (histCount < HIST) {
            histCount++;
        }
    }

    // Average dose and cps for the measurement at history index i: by time (measurements in
    // the last avgSec s) or by count (the last avgN measurements)
    // capMs limits the averaging window (in the chart by its length)
    function smoothAt(i as Number, capMs as Number) as Array<Float> {
        var t0 = histT[i] as Number;
        var sd = 0.0;
        var sc = 0.0;
        var n = 0;
        var back = (histHead - 1 - i + HIST) % HIST;   // how many measurements are newer
        for (var k = 0; back + k < histCount; k++) {
            var j = (i - k + HIST) % HIST;
            var age = t0 - (histT[j] as Number);
            if (n > 0 && (age >= capMs || (avgMode == 1 ? age >= avgSec * 1000 : n >= avgN))) {
                break;
            }
            sd += histDose[j] as Float;
            sc += histCps[j] as Float;
            n++;
        }
        return [sd / n, sc / n] as Array<Float>;
    }

    // Fills smDose/smCps for measurements newer than tMin. The sliding window
    // moves in a single pass (each measurement is added and subtracted only once),
    // so chart drawing does not exhaust the watch time limit (watchdog).
    function smooth(tMin as Number, capMs as Number) as Void {
        var lim = capMs;
        if (avgMode == 1 && avgSec * 1000 < lim) {
            lim = avgSec * 1000;
        }
        // How many measurements are needed: the chart window plus the averaging length before it
        var m = 0;
        while (m < histCount && (histT[(histHead - 1 - m + HIST) % HIST] as Number) >= tMin - lim) {
            m++;
        }
        var sd = 0.0;
        var sc = 0.0;
        var n = 0;
        var kl = m - 1;   // oldest measurement in the window
        for (var k = m - 1; k >= 0; k--) {
            var i = (histHead - 1 - k + HIST) % HIST;
            var t = histT[i] as Number;
            if (avgMode == 0) {
                if (t >= tMin) {
                    smDose[i] = histDose[i];
                    smCps[i] = histCps[i];
                }
                continue;
            }
            sd += histDose[i] as Float;
            sc += histCps[i] as Float;
            n++;
            while (n > 1) {
                var j = (histHead - 1 - kl + HIST) % HIST;
                if (t - (histT[j] as Number) < lim && (avgMode != 2 || n <= avgN)) {
                    break;
                }
                sd -= histDose[j] as Float;
                sc -= histCps[j] as Float;
                n--;
                kl--;
            }
            if (t >= tMin) {
                smDose[i] = sd / n;
                smCps[i] = sc / n;
            }
        }
    }

    // Peak cps (and dose at it) before saturation; the recovery is compared to it
    private var _ovlPeak as Float = 0.0;
    private var _ovlPeakDose as Float = 0.0;
    private var _ovlOk as Number = 0;     // how many consecutive measurements look like a recovery
    private var _ovlPrevDose as Float = 0.0;
    private var _ovlPrevCps as Float = 0.0;
    private var _ovlSame as Number = 0;
    private var _pk as Float = 0.0;       // peak from the last cpsDropped
    private var _pkD as Float = 0.0;

    // Turns OVL on when a threshold is exceeded or on a steep cps drop that
    // the dose does not follow. Turned off by recovery through the peak (cps climbed back
    // close to the peak and the dose fell to its level at the peak, OVL_EXIT_N
    // measurements in a row), or by dose below OVL_RESET_DOSE. Called before storing
    // a new measurement in the history.
    function updateOvl(now as Number, dose as Float, cps as Float) as Void {
        // cps: ceiling or steep drop; the dose is still shown (the Raysid
        // computes it even with saturated cps)
        // The Raysid reports overload itself (same as its red LED); our own
        // estimate from the cps and dose trend only when it does not send the flag
        if (devOvl != null) {
            cpsOvlOn = devOvl as Boolean;
            if (dose > OVL_DOSE) {
                doseOvlOn = true;
            } else if (doseOvlOn && dose < OVL_DOSE_RESET) {
                doseOvlOn = false;
            }
            ovl = cpsOvlOn || doseOvlOn;
            return;
        }
        var hit = cpsDropped(now, dose, cps) || (OVL_CPS_ON && cps > OVL_CPS);
        if (hit && !cpsOvlOn) {
            cpsOvlOn = true;
            _ovlPeak = _pk;
            _ovlPeakDose = _pkD;
            _ovlOk = 0;
            _ovlSame = 0;
            _ovlPrevCps = cps;
            _ovlPrevDose = dose;
        } else if (cpsOvlOn && !hit) {
            // During saturation cps falls and dose rises; when leaving saturation
            // cps rises and dose falls. Recovery = cps back near the peak with
            // dose at most as at the peak; confirmed by the next measurement where the dose
            // stayed low (cps may then fall together with it)
            // The Raysid dose lags (on ramp-up it stays low at the peak,
            // on exit it stays high for a while), hence only the loose limit OVL_EXIT_DOSE and
            // confirmation by the next measurement that the dose is no longer rising
            var lowDose = dose <= _ovlPeakDose * OVL_EXIT_DOSE;
            var nearPeak = cps >= _ovlPeak * OVL_EXIT_CPS;
            var notRising = _ovlOk == 0 || dose <= _ovlPrevDose * 1.05;
            // On a fast exit cps skips past the peak at once and falls together with
            // the dose: so a second measurement with a falling dose is enough
            var back = _ovlPeak > 0.0 && lowDose && notRising
                && (nearPeak || (_ovlOk > 0 && dose < _ovlPrevDose));
            _ovlOk = back ? _ovlOk + 1 : 0;
            // Second way: cps and dose move in the same direction (both fall
            // or both rise) OVL_SAME_N measurements in a row. During saturation they always
            // go against each other, so this happens only outside it.
            var same = _ovlPrevCps > 0.0 && ((cps < _ovlPrevCps * (1.0 - OVL_SAME_STEP) && dose < _ovlPrevDose)
                || (cps > _ovlPrevCps * (1.0 + OVL_SAME_STEP) && dose > _ovlPrevDose));
            _ovlSame = same ? _ovlSame + 1 : 0;
            _ovlPrevDose = dose;
            _ovlPrevCps = cps;
            if (_ovlOk >= OVL_EXIT_N || _ovlSame >= OVL_SAME_N || dose < OVL_RESET_DOSE) {
                cpsOvlOn = false;
            }
        }
        // dose: above 999 uSv/h a number is never shown
        if (dose > OVL_DOSE) {
            doseOvlOn = true;
        } else if (doseOvlOn && dose < OVL_DOSE_RESET) {
            doseOvlOn = false;
        }
        ovl = cpsOvlOn || doseOvlOn;
    }

    // Peak cps in the last OVL_DROP_MS and the dose at it vs the current measurement
    private function cpsDropped(now as Number, dose as Float, cps as Float) as Boolean {
        var peak = 0.0;
        var peakDose = 0.0;
        for (var k = 0; k < histCount; k++) {
            var i = (histHead - 1 - k + HIST) % HIST;
            if (now - (histT[i] as Number) > OVL_DROP_MS) {
                break;
            }
            if ((histCps[i] as Float) > peak) {
                peak = histCps[i] as Float;
                peakDose = histDose[i] as Float;
            }
        }
        _pk = peak;
        _pkD = peakDose;
        // Below OVL_RESET_DOSE saturation cannot happen (false OVL after moving away from a source,
        // when cps falls faster than the lagging dose)
        if (peak < OVL_DROP_MIN_CPS || peakDose <= 0.0 || dose < OVL_RESET_DOSE) {
            return false;
        }
        var rc = cps / peak;
        var rd = dose / peakDose;
        return (rc <= OVL_FAST_CPS && rd >= OVL_FAST_DOSE) || (rc <= OVL_DROP_CPS && rd >= rc * OVL_DROP_GAP && rd >= 1.0);
    }

    // Average dose and cps over measurements newer than tFrom (system timer ms),
    // always at least from the last measurement; for mapping points, independent of settings
    function avgSince(tFrom as Number) as Array<Float>? {
        var sd = 0.0;
        var sc = 0.0;
        var n = 0;
        for (var k = 0; k < histCount; k++) {
            var i = (histHead - 1 - k + HIST) % HIST;
            if (n > 0 && (histT[i] as Number) <= tFrom) {
                break;
            }
            sd += histDose[i] as Float;
            sc += histCps[i] as Float;
            n++;
        }
        return n == 0 ? null : [sd / n, sc / n] as Array<Float>;
    }

    // Displayed values: instant, or averaged per settings
    function shownDose() as Float? {
        if (avgMode == 0 || histCount == 0 || doseRate == null) {
            return doseRate;
        }
        return smoothAt((histHead - 1 + HIST) % HIST, 60000)[0];
    }

    function shownCps() as Float? {
        if (avgMode == 0 || histCount == 0 || cps == null) {
            return cps;
        }
        return smoothAt((histHead - 1 + HIST) % HIST, 60000)[1];
    }

    // Stored value of the same type as the default; otherwise (missing, damaged) the default
    private function load(key as String, def as Boolean or Number) as Boolean or Number {
        var v = Storage.getValue(key);
        if (def instanceof Boolean) {
            return v instanceof Boolean ? v : def;
        }
        return v instanceof Number ? v : def;
    }

    function save() as Void {
        put("bl", backlight);
        put("snd", sound);
        put("led", led);
        put("div", divider);
        put("dvL", divLink);
        put("cw", chartSec);
        put("swap", swapMain);
        put("avM", avgMode);
        put("avS", avgSec);
        put("avN", avgN);
        put("vib", vibrate);
        put("sp", softPct);
        put("aSnd", alarmSound);
        put("aVib", alarmVibe);
        put("aFl", alarmFlash);
        put("aRed", alarmRedLed);
        put("aLen", alarmLen);
        put("ac", alarmCps);
        put("ad", alarmDose);
        put("aOn", alarmsOn);
        put("adOn", doseOn);
        put("acOn", cpsOn);
        put("slOn", softOn);
        put("lang", Tr.lang);
    }
}

class RaysidApp extends Application.AppBase {
    var state as RaysidState;
    var ble as BleManager;
    var clicker as Clicker;
    var recorder as Recorder;
    var uploader as Uploader;

    function initialize() {
        AppBase.initialize();
        state = new RaysidState();
        ble = new BleManager(state);
        clicker = new Clicker(state);
        uploader = new Uploader();
        recorder = new Recorder(state);
    }

    function onStart(params as Dictionary?) as Void {
        BluetoothLowEnergy.setDelegate(ble);
        ble.start();
        clicker.start();
        recorder.resume();
        uploader.start();
    }

    function onStop(params as Dictionary?) as Void {
        clicker.stop();
        uploader.stop();
        recorder.suspend();
        ble.stop();
    }

    // Key or upload toggle changed in Garmin Connect
    function onSettingsChanged() as Void {
        uploader.settingsChanged();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new RaysidView(state), new RaysidDelegate(state, ble)];
    }
}
