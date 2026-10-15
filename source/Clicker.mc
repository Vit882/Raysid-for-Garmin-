// Raysid Garmin - Connect IQ app for the Raysid dosimeter
// Copyright (C) 2026 Vít Cenek and contributors (see AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 3 or (at your
// option) any later version, as published by the Free Software Foundation.
// It is distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Beeping and flashlight blinking by count rate, with a 1:N divider.
// The Raysid does not send individual pulses, only cps (about every 0.25 s), so
// pulses are beeped evenly according to the current cps. Above MAX_RATE beeps
// per second beeping is temporarily disabled, a notice is shown and a warning sounds.
// The same timer keeps the backlight on, if enabled in settings.
class Clicker {
    const TICK_MS = 100;
    // Highest beep rate the watch can handle (100 ms timer).
    // Above it the beeper is temporarily disabled and a warning sounds.
    const MAX_RATE = 10.0;
    const WARN_EVERY_TICKS = 20;  // warning every 2 s
    // The vibration motor needs tens of ms to spin up and down; gaps shorter
    // than ~250 ms merge into one buzz. Above this rate vibrations for
    // pulses are skipped (beeping and flashlight continue).
    const VIBE_MAX_RATE = 4.0;
    const SEQ_GAP_MS = 2000;      // gap between alarm bursts
    const VIBE_OVER_EVERY_MS = 10000;  // repeat of the "vibration can't keep up" signal
    private var _vibeOverNext as Number = 0;
    private var _lastBurst as Number = -10000;
    private var _state as RaysidState;
    private var _timer as Timer.Timer = new Timer.Timer();
    private var _ovlPhase as Number = 0;
    private var _ledOn as Boolean = false;
    private var _ticks as Number = 0;
    private var _acc as Float = 0.0;   // accumulated pulses for even beeping
    private var _lastTick as Number = 0;

    function initialize(state as RaysidState) {
        _state = state;
    }

    static function hasLed() as Boolean {
        return Attention has :setFlashlightMode;
    }

    function start() as Void {
        _timer.start(method(:onTick), TICK_MS, true);
    }

    function stop() as Void {
        _timer.stop();
        ledOff();
    }

    function onTick() as Void {
        _ticks++;
        if (_ledOn) {
            ledOff();
        }
        if (_state.backlight && !(_state.blMapSys && _state.page == 2) && _ticks % 10 == 0 && Attention has :backlight) {
            try {
                Attention.backlight(true);
            } catch (e) {
                // some displays do not allow a permanent backlight
            }
        }
        var now = System.getTimer();
        // Actual elapsed time: when a tick is delayed (e.g. chart drawing),
        // beeping catches up and the rate is correct on both screens
        var dt = _lastTick == 0 ? TICK_MS : now - _lastTick;
        _lastTick = now;
        if (dt > 1000) {
            dt = TICK_MS;
        }
        if (now < _state.flashUntil + TICK_MS && _state.page == 0 && !_state.showDebug) {
            WatchUi.requestUpdate();   // screen flash on alarm (main screen only)
        } else if (_state.ovl && now / 500 != _ovlPhase) {
            WatchUi.requestUpdate();   // OVL blinking
        }
        _ovlPhase = now / 500;
        if (_state.seqLeft > 0 && now >= _state.seqNext) {
            alarmBurst(_state.seqKind);
            _state.seqLeft--;
            _state.seqNext = now + SEQ_GAP_MS;
            _lastBurst = now;
        }
        // Red flashlight for the whole alarm, independent of the divider and clicking
        if (alarmLed() && _ticks % 5 == 0) {
            Attention.setFlashlightMode(Attention.FLASHLIGHT_MODE_ON,
                {:brightness => Attention.FLASHLIGHT_BRIGHTNESS_LOW, :color => Attention.FLASHLIGHT_COLOR_RED});
            _ledOn = true;
        }
        // Divider 1:1 = signalling on the watch off, only alarms remain
        if (_state.divider <= 1 || (!_state.sound && !_state.led && !_state.vibrate)) {
            _state.overload = false;
            _state.vibeOver = false;
            return;
        }
        var fresh = _state.lastUpdate != null && System.getTimer() - (_state.lastUpdate as Number) < 5000;
        if (!fresh || _state.cps == null) {
            _state.overload = false;
            _state.vibeOver = false;
            return;
        }
        var rate = (_state.cps as Float) / _state.divider;
        // Hysteresis so it does not toggle back and forth at the threshold
        if (rate > MAX_RATE) {
            _state.overload = true;
        } else if (rate < MAX_RATE * 0.8) {
            _state.overload = false;
        }
        updateVibeOver(rate, now);
        if (_state.overload) {
            // The warning does not drown out a running alarm
            if (_ticks % WARN_EVERY_TICKS == 0 && _state.seqLeft == 0 && now - _lastBurst > 2000) {
                warn();
            }
            return;
        }
        var p = rate * dt / 1000.0;
        // Evenly: beep every time another N pulses accumulate
        _acc += p;
        if (_acc >= 1.0) {
            _acc -= 1.0;
            if (_acc > 1.0) {
                _acc = 0.0;
            }
            click();
        }
    }

    private function alarmLed() as Boolean {
        return _state.alarmRedLed && (_state.softAlarm || _state.hardAlarm) && hasLed()
            && Attention.hasFlashlightColor(Attention.FLASHLIGHT_COLOR_RED);
    }

    private function click() as Void {
        // Right after an alarm burst do not click, so the click does not cut its tone
        if (_state.sound && Attention has :playTone && System.getTimer() - _lastBurst > 1000) {
            Attention.playTone({:toneProfile => [new Attention.ToneProfile(3000, 25)]});
        }
        // Vibrate only at lower rates and not over a running alarm
        if (_state.vibrate && !_state.vibeOver && System.getTimer() - _lastBurst > 1200
                && Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, 40)]);
        }
        // During an alarm with red flashlight the flashlight blinks only red (see onTick)
        if (_state.led && hasLed() && !alarmLed()) {
            Attention.setFlashlightMode(Attention.FLASHLIGHT_MODE_ON,
                {:brightness => Attention.FLASHLIGHT_BRIGHTNESS_LOW, :color => Attention.FLASHLIGHT_COLOR_WHITE});
            _ledOn = true;
        }
    }

    // Above VIBE_MAX_RATE vibrations for pulses are skipped. To make this noticeable,
    // an escalating weak-medium-strong vibration plays (alarms have the same strength
    // and longer pulses, so they are not confused). Hysteresis 4 -> 3 per second.
    private function updateVibeOver(rate as Float, now as Number) as Void {
        if (!_state.vibrate) {
            _state.vibeOver = false;
            return;
        }
        if (rate > VIBE_MAX_RATE) {
            if (!_state.vibeOver) {
                _state.vibeOver = true;
                _vibeOverNext = now;
            }
        } else if (rate < VIBE_MAX_RATE * 0.75) {
            _state.vibeOver = false;
        }
        // On beeper overload the warning already vibrates, during an alarm its bursts
        if (_state.vibeOver && !_state.overload && now >= _vibeOverNext
                && now - _lastBurst > 1500 && _state.seqLeft == 0) {
            _vibeOverNext = now + VIBE_OVER_EVERY_MS;
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(25, 120), new Attention.VibeProfile(0, 90),
                    new Attention.VibeProfile(55, 120), new Attention.VibeProfile(0, 90),
                    new Attention.VibeProfile(100, 160)]);
            }
        }
    }

    // One alarm burst: fixed = distinct tone and double vibration, soft = rising tone and short vibration
    private function alarmBurst(kind as Number) as Void {
        if (_state.alarmSound && Attention has :playTone) {
            if (kind == 2) {
                Attention.playTone(Attention.TONE_ALERT_HI);
            } else {
                Attention.playTone({:toneProfile => [
                    new Attention.ToneProfile(1500, 60), new Attention.ToneProfile(0, 40),
                    new Attention.ToneProfile(2500, 80)
                ]});
            }
        }
        if (_state.alarmVibe && Attention has :vibrate) {
            if (kind == 2) {
                Attention.vibrate([new Attention.VibeProfile(100, 300), new Attention.VibeProfile(0, 150),
                    new Attention.VibeProfile(100, 300)]);
            } else {
                Attention.vibrate([new Attention.VibeProfile(70, 200)]);
            }
        }
    }

    // Beeps 3x briefly (and vibrates 3x), then a gap until the next warning
    private function warn() as Void {
        if (_state.vibrate && Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, 80), new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 80), new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(100, 80)]);
        }
        if (_state.sound && Attention has :playTone) {
            Attention.playTone({:toneProfile => [
                new Attention.ToneProfile(2000, 100), new Attention.ToneProfile(0, 80),
                new Attention.ToneProfile(2000, 100), new Attention.ToneProfile(0, 80),
                new Attention.ToneProfile(2000, 100)
            ]});
        }
    }

    private function ledOff() as Void {
        if (hasLed()) {
            Attention.setFlashlightMode(Attention.FLASHLIGHT_MODE_OFF, null);
        }
        _ledOn = false;
    }
}
