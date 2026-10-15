// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Pipani a blikani svitilnou podle count rate, s delickou 1:N.
// Raysid neposila jednotlive impulzy, jen cps (asi kazdych 0,25 s), takze impulzy
// pipame rovnomerne podle aktualniho cps. Nad MAX_RATE pipnuti za
// sekundu se pipani docasne vypne, na displeji je upozorneni a zni varovani.
// Stejny casovac drzi zapnute podsviceni, je-li to v nastaveni.
class Clicker {
    const TICK_MS = 100;
    // Nejvyssi frekvence pipani, kterou hodinky zvladnou (casovac 100 ms).
    // Nad ni se pipak docasne vypne a zni varovani.
    const MAX_RATE = 10.0;
    const WARN_EVERY_TICKS = 20;  // varovani kazde 2 s
    // Vibracni motor potrebuje na rozbeh a dobeh desitky ms; kratsi rozestupy
    // nez ~250 ms uz splyvaji v jedno bzuceni. Nad touto frekvenci se
    // vibrace k impulzum vynechavaji (pipani a svitilna jedou dal).
    const VIBE_MAX_RATE = 4.0;
    const SEQ_GAP_MS = 2000;      // rozestup davek alarmu
    const VIBE_OVER_EVERY_MS = 10000;  // opakovani hlaseni "vibrace nestaci"
    private var _vibeOverNext as Number = 0;
    private var _lastBurst as Number = -10000;
    private var _state as RaysidState;
    private var _timer as Timer.Timer = new Timer.Timer();
    private var _ovlPhase as Number = 0;
    private var _ledOn as Boolean = false;
    private var _ticks as Number = 0;
    private var _acc as Float = 0.0;   // nasbirane impulzy pro rovnomerne pipani
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
        if (_state.backlight && _ticks % 10 == 0 && Attention has :backlight) {
            try {
                Attention.backlight(true);
            } catch (e) {
                // nektere displeje nedovoli sviceni trvale
            }
        }
        var now = System.getTimer();
        // Skutecne uplynuly cas: kdyz se tik zpozdi (napr. kresleni grafu),
        // pipani se dorovna a frekvence sedi na obou obrazovkach
        var dt = _lastTick == 0 ? TICK_MS : now - _lastTick;
        _lastTick = now;
        if (dt > 1000) {
            dt = TICK_MS;
        }
        if (now < _state.flashUntil + TICK_MS && _state.page == 0 && !_state.showDebug) {
            WatchUi.requestUpdate();   // probliknuti obrazovky pri alarmu (jen hlavni obrazovka)
        } else if (_state.ovl && now / 500 != _ovlPhase) {
            WatchUi.requestUpdate();   // blikani OVL
        }
        _ovlPhase = now / 500;
        if (_state.seqLeft > 0 && now >= _state.seqNext) {
            alarmBurst(_state.seqKind);
            _state.seqLeft--;
            _state.seqNext = now + SEQ_GAP_MS;
            _lastBurst = now;
        }
        // Cervena svitilna po celou dobu alarmu, nezavisle na delicce a cvakani
        if (alarmLed() && _ticks % 5 == 0) {
            Attention.setFlashlightMode(Attention.FLASHLIGHT_MODE_ON,
                {:brightness => Attention.FLASHLIGHT_BRIGHTNESS_LOW, :color => Attention.FLASHLIGHT_COLOR_RED});
            _ledOn = true;
        }
        // Delicka 1:1 = signalizace v hodinkach vypnuta, zustavaji jen alarmy
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
        // Hystereze, aby to na hranici neprepinalo sem a tam
        if (rate > MAX_RATE) {
            _state.overload = true;
        } else if (rate < MAX_RATE * 0.8) {
            _state.overload = false;
        }
        updateVibeOver(rate, now);
        if (_state.overload) {
            // Varovani neprehlusi probihajici alarm
            if (_ticks % WARN_EVERY_TICKS == 0 && _state.seqLeft == 0 && now - _lastBurst > 2000) {
                warn();
            }
            return;
        }
        var p = rate * dt / 1000.0;
        // Rovnomerne: pipne pokazde, kdyz se nasbira dalsich N impulzu
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
        // Tesne po davce alarmu necvakat, at cvaknuti neutne jeho ton
        if (_state.sound && Attention has :playTone && System.getTimer() - _lastBurst > 1000) {
            Attention.playTone({:toneProfile => [new Attention.ToneProfile(3000, 25)]});
        }
        // Vibrace jen pri nizsi frekvenci a ne pres probihajici alarm
        if (_state.vibrate && !_state.vibeOver && System.getTimer() - _lastBurst > 1200
                && Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, 40)]);
        }
        // Pri alarmu s cervenou svitilnou blika svitilna jen cervene (viz onTick)
        if (_state.led && hasLed() && !alarmLed()) {
            Attention.setFlashlightMode(Attention.FLASHLIGHT_MODE_ON,
                {:brightness => Attention.FLASHLIGHT_BRIGHTNESS_LOW, :color => Attention.FLASHLIGHT_COLOR_WHITE});
            _ledOn = true;
        }
    }

    // Nad VIBE_MAX_RATE se vibrace k impulzum vynechavaji. Aby to bylo poznat,
    // ozve se silici vibrace slaba-stredni-silna (alarmy maji stejnou silu
    // a delsi pulzy, takze se neplete). Hystereze 4 -> 3 za sekundu.
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
        // Pri pretizeni pipaku uz vibruje varovani, pri alarmu jeho davky
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

    // Jedna davka alarmu: pevny = vyrazny ton a dvojita vibrace, mekky = stoupajici ton a kratka vibrace
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

    // 3x kratce pipne (a 3x zavibruje), pak mezera do dalsiho varovani
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
