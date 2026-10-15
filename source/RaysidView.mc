// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Oranzova a modra: dobre rozlisitelne i pro barvoslepe a na MIP displeji
const CHART_DOSE = 0xFFAA00;   // oranzova
const CHART_CPS = 0x00AAFF;    // modra
const UP_COLOR = 0xFFFF00;     // syta zluta: oblouk u UP (akce obrazovky)
const UP_TEXT = 0xFFFF00;      // stejna zluta pro text napovedy k UP
const CHART_CPS_DIM = 0x0055AA;   // tlumena modra pro rozptyl cps v grafu

class RaysidView extends WatchUi.View {
    const UP_SHIFT = 6;
    private var _state as RaysidState;

    function initialize(state as RaysidState) {
        View.initialize();
        _state = state;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        // Probliknuti pri alarmu (jen na hlavni obrazovce)
        var now = System.getTimer();
        var bg = Graphics.COLOR_BLACK;
        if (_state.page == 0 && !_state.showDebug && now < _state.flashUntil && (now / 250) % 2 == 0) {
            bg = _state.flashColor;
        }
        dc.setColor(bg, bg);
        dc.clear();

        // Stavovy radek, pri alarmu misto nej upozorneni
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var top = Tr.t(_state.status);
        if (_state.statusArg.length() > 0) {
            top += ": " + _state.statusArg;
        }
        var topY = (h * 0.12).toNumber() - (_state.page == 1 ? UP_SHIFT : 0);
        // Jmeno Raysidu jen kdyz se radek vejde do kulateho displeje
        if (_state.deviceName != null) {
            var withName = _state.deviceName + " " + top;
            if (dc.getTextWidthInPixels(withName, Graphics.FONT_XTINY) <= chordAt(h, topY, Graphics.FONT_XTINY)) {
                top = withName;
            }
        }
        if (_state.hardAlarm) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            top = Tr.t(:alarmLimit);
        } else if (_state.softAlarm) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            top = Tr.t(:rapidRise);
        }
        // Obrazovka grafu je cela o UP_SHIFT px vys, aby se graf vesel vetsi
        dc.drawText(cx, topY, Graphics.FONT_XTINY, fitText(dc, top, Graphics.FONT_XTINY, chordAt(h, topY, Graphics.FONT_XTINY)), Graphics.TEXT_JUSTIFY_CENTER);

        if (_state.showDebug) {
            drawDebug(dc, cx, h);
            return;
        }
        drawMenuHint(dc, w, h);
        if (_state.page == 2 && !recorder().enabled) {
            _state.page = 0;   // mapovani mezitim vypnute
        }
        if (_state.page == 1) {
            drawChart(dc, w, h);
            return;
        }
        if (_state.page == 2) {
            drawMapping(dc, w, h);
            return;
        }

        var stale = _state.lastUpdate == null || System.getTimer() - (_state.lastUpdate as Number) > 5000;

        // Rozlozeni pocitane z vysky pisma, aby se radky neprekryvaly.
        // Kazda velicina je cislo a hned za nim jednotka ve stejne barve.
        // Nahore velkym pismem davka, pod ni mensim cps; UP je prohodi.
        // Zobrazene hodnoty jsou okamzite nebo prumer podle nastaveni, alarmy
        // (cervena barva) ale vzdy podle okamzite hodnoty jako signalizace
        var shownDose = _state.shownDose();
        var doseText = doseOvl(_state) ? "OVL" : doseNum(shownDose);
        var doseU = doseOvl(_state) ? "uSv/h" : doseUnit(shownDose);
        var doseOver = _state.doseLimit() > 0.0 && _state.doseRate != null && (_state.doseRate as Float) >= _state.doseLimit();
        var doseColor = stale ? Graphics.COLOR_DK_GRAY : (doseOver || doseOvl(_state) ? Graphics.COLOR_RED : CHART_DOSE);
        var shownCps = _state.shownCps();
        var cpsText = cpsOvl(_state) ? "OVL" : cpsNum(shownCps);
        var cpsU = cpsOvl(_state) ? "kcps" : cpsUnit(shownCps);
        var cpsOver = _state.cpsLimit() > 0 && _state.cps != null && (_state.cps as Float) >= _state.cpsLimit();
        var cpsColor = stale ? Graphics.COLOR_DK_GRAY : (cpsOver || cpsOvl(_state) ? Graphics.COLOR_RED : CHART_CPS);
        // Radky maji pevnou polohu i velikost pisma bez ohledu na to, ktera
        // velicina je nahore. Spodni radek je co nejvetsi, pokud se pod nej
        // jeste vejdou upozorneni a baterie nad radek REC.
        var row1 = (h * 0.22).toNumber();
        var bigF = Graphics.FONT_NUMBER_HOT;
        var base1 = row1 + Graphics.getFontAscent(bigF);
        var y2 = base1 + Graphics.getFontDescent(bigF) / 2 + 6;
        var smallF = Graphics.FONT_NUMBER_MEDIUM;
        var smallU = Graphics.FONT_SMALL;
        var rest = Graphics.getFontHeight(Graphics.FONT_XTINY) * 2 + 6;
        if (y2 + Graphics.getFontAscent(smallF) + Graphics.getFontDescent(smallF) / 2 + rest > h * 0.86) {
            smallF = Graphics.FONT_NUMBER_MILD;
            smallU = Graphics.FONT_TINY;
        }
        var base2 = y2 + Graphics.getFontAscent(smallF);
        var y = base2 + Graphics.getFontDescent(smallF) / 2 + 6;
        // Pismo kazdeho radku se voli tak, aby se do nej vesla davka i cps,
        // takze se po prohozeni velikost nezmeni
        var f1 = fitFont(dc, w, bigF, Graphics.FONT_SMALL, doseText, doseU, cpsText, cpsU);
        var f2 = fitFont(dc, w, smallF, smallU, doseText, doseU, cpsText, cpsU);
        // Ciselna pisma neumi pismena: OVL se kresli textovym pismem na stejne
        // zakladni care a blika (pul sekundy sviti, pul nesviti)
        // OVL jen u veliciny, ktera do nej spadla
        var blinkOn = (System.getTimer() / 500) % 2 == 0;
        var cpsTop = _state.swapMain;
        drawMain(dc, cx, cpsTop ? base2 : base1, doseText, doseU, cpsTop ? f2 : f1, cpsTop ? smallU : Graphics.FONT_SMALL,
            cpsTop ? Graphics.FONT_MEDIUM : Graphics.FONT_LARGE, doseColor, doseOvl(_state), blinkOn);
        drawMain(dc, cx, cpsTop ? base1 : base2, cpsText, cpsU, cpsTop ? f1 : f2, cpsTop ? Graphics.FONT_SMALL : smallU,
            cpsTop ? Graphics.FONT_LARGE : Graphics.FONT_MEDIUM, cpsColor, cpsOvl(_state), blinkOn);

        if ((_state.sound || _state.led || _state.vibrate) && _state.overload) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_XTINY, Tr.t(:beeperOff), Graphics.TEXT_JUSTIFY_CENTER);
            y += Graphics.getFontHeight(Graphics.FONT_XTINY);
        } else if (_state.vibrate && _state.vibeOver) {
            dc.setColor(0xFFAA00, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_XTINY, Tr.t(:vibeMax), Graphics.TEXT_JUSTIFY_CENTER);
            y += Graphics.getFontHeight(Graphics.FONT_XTINY);
        }
        drawBatteries(dc, cx, y);
        drawRecord(dc, cx, h);
        drawClock(dc, cx, h);
    }

    // Sirka kulateho displeje v miste radku textu (s okrajem)
    private function chordAt(h as Number, y as Number, font as Graphics.FontType) as Number {
        var r = h / 2;
        var fh = Graphics.getFontHeight(font);
        // Uzsi z horniho a dolniho okraje radku
        var dy = (r - y).abs() > (r - y - fh).abs() ? (r - y).abs() : (r - y - fh).abs();
        if (dy >= r) {
            return 0;
        }
        return 2 * Math.sqrt(r * r - dy * dy).toNumber() - 12;
    }

    // Text zkraceny tak, aby se vesel do sirky (konec nahradi ..)
    private function fitText(dc as Graphics.Dc, text as String, font as Graphics.FontType, maxW as Number) as String {
        if (dc.getTextWidthInPixels(text, font) <= maxW) {
            return text;
        }
        var n = text.length();
        while (n > 1 && dc.getTextWidthInPixels((text.substring(0, n) as String) + "..", font) > maxW) {
            n--;
        }
        return (text.substring(0, n) as String) + "..";
    }

    // Male hodiny bile uplne nahore, nad stavovym radkem
    private function drawClock(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var t = System.getClockTime();
        var fh = Graphics.getFontHeight(Graphics.FONT_XTINY);
        var y = (h * 0.12).toNumber() - fh + 2;
        y = y < 2 ? 2 : y;
        var hr = t.hour;
        // 12hodinovy cas podle nastaveni hodinek
        if (!System.getDeviceSettings().is24Hour) {
            hr = hr % 12 == 0 ? 12 : hr % 12;
        }
        var clock = hr + ":" + t.min.format("%02d");
        // Pri prumerovani sede za hodinami, pres kolik se prumeruje; oboje
        // vystredene jako celek, aby nic nelezlo pres kulaty okraj
        var a = avgLabel(_state);
        var tw = dc.getTextWidthInPixels(clock, Graphics.FONT_XTINY);
        var aw = a != null ? dc.getTextWidthInPixels(" " + a, Graphics.FONT_XTINY) : 0;
        // Sirka kulateho displeje v polovine vysky textu; kdyz se nevejde,
        // zkratit na "~10 s" / "~5x"
        var r = h / 2;
        var dy = r - (y + fh / 2);
        var chord = 2 * Math.sqrt(r * r - dy * dy).toNumber() - 16;
        if (a != null && tw + aw > chord) {
            a = "~" + (_state.avgMode == 1 ? _state.avgSec + " s" : _state.avgN + "x");
            aw = dc.getTextWidthInPixels(" " + a, Graphics.FONT_XTINY);
        }
        var x = cx - (tw + aw) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, clock, Graphics.TEXT_JUSTIFY_LEFT);
        if (a != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + tw, y, Graphics.FONT_XTINY, " " + a, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // Baterie Raysidu i hodinek: popisky sede, procenta barevne podle stavu
    private function drawBatteries(dc as Graphics.Dc, cx as Number, y as Number) as Void {
        var rb = _state.battery;
        var wb = System.getSystemStats().battery;
        var parts = [
            "Raysid ", Graphics.COLOR_LT_GRAY,
            rb != null ? (rb as Float).format("%.0f") + "%" : "--", rb != null ? batColor(rb as Float) : Graphics.COLOR_LT_GRAY,
            "   " + Tr.t(:watch) + " ", Graphics.COLOR_LT_GRAY,
            wb.format("%.0f") + "%", batColor(wb)
        ];
        // Vetsim pismem, pokud se radek vejde do kulateho displeje
        var font = Graphics.FONT_TINY;
        var total = 0;
        for (var i = 0; i < parts.size(); i += 2) {
            total += dc.getTextWidthInPixels(parts[i] as String, font);
        }
        var r = cx;
        var dy = (y + Graphics.getFontHeight(font) - r).abs();
        if (total > 2 * Math.sqrt(r * r - dy * dy) - 24) {
            font = Graphics.FONT_XTINY;
            total = 0;
            for (var i = 0; i < parts.size(); i += 2) {
                total += dc.getTextWidthInPixels(parts[i] as String, font);
            }
        }
        var x = cx - total / 2;
        for (var i = 0; i < parts.size(); i += 2) {
            dc.setColor(parts[i + 1] as Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, parts[i] as String, Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(parts[i] as String, font);
        }
    }

    // Nad 30 % zelena, nad 20 % oranzova, jinak cervena
    private function batColor(p as Float) as Number {
        return p > 30.0 ? Graphics.COLOR_GREEN : (p > 20.0 ? Graphics.COLOR_ORANGE : Graphics.COLOR_RED);
    }

    // Cislo a za nim mensi jednotka na spolecne zakladni lince, cele vystredene
    // Radek s cislem a jednotkou na dane zakladni lince. Kdyby se cislo
    // neveslo na sirku, pouzije se mensi pismo, poloha radku zustane stejna.
    // Jeden radek hlavni obrazovky; pri OVL textovym pismem (ciselna neumi
    // pismena) na stejne zakladni care, blikajici
    private function drawMain(dc as Graphics.Dc, cx as Number, base as Number, num as String, unit as String,
            font as Graphics.FontType, unitFont as Graphics.FontType, ovlFont as Graphics.FontType,
            color as Number, ovl as Boolean, blinkOn as Boolean) as Void {
        if (ovl) {
            if (!blinkOn) {
                return;
            }
            font = ovlFont;
        }
        drawValue(dc, cx, base - Graphics.getFontAscent(font), num, font, unit, unitFont, color);
    }

    // Nejvetsi pismo od font dolu, do ktereho se vejde davka i cps s jednotkou
    private function fitFont(dc as Graphics.Dc, w as Number, font as Graphics.FontType, unitFont as Graphics.FontType,
            dose as String, doseU as String, cps as String, cpsU as String) as Graphics.FontType {
        var fonts = [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD] as Array<Graphics.FontType>;
        var i = fonts.indexOf(font);
        var wd = dc.getTextWidthInPixels(" " + doseU, unitFont);
        var wc = dc.getTextWidthInPixels(" " + cpsU, unitFont);
        while (i >= 0 && i < fonts.size() - 1
                && (dc.getTextWidthInPixels(dose, font) + wd > w * 0.84 || dc.getTextWidthInPixels(cps, font) + wc > w * 0.84)) {
            i++;
            font = fonts[i];
        }
        return font;
    }

    private function drawValue(dc as Graphics.Dc, cx as Number, y as Number, num as String, numFont as Graphics.FontType,
            unit as String, unitFont as Graphics.FontType, color as Number) as Void {
        var gap = 5;
        var wn = dc.getTextWidthInPixels(num, numFont);
        var wu = dc.getTextWidthInPixels(unit, unitFont);
        var x = cx - (wn + gap + wu) / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, numFont, num, Graphics.TEXT_JUSTIFY_LEFT);
        var base = y + Graphics.getFontAscent(numFont);
        dc.drawText(x + wn + gap, base - Graphics.getFontAscent(unitFont), unitFont, unit, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Stav zaznamu dole: cervena tecka, REC a pocet bodu (nebo cekani na GPS)
    private function drawRecord(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var r = recorder();
        if (!r.enabled || (!r.on && !r.full && !r.paused)) {
            return;
        }
        var text = r.full ? Tr.t(:recFull) : (r.paused ? Tr.t(:recPauseUp) + " " + r.session
            : (r.gpsOk ? (r.noData ? noDataText() : "REC " + r.session) : Tr.t(r.gpsWeak ? :gpsWeak : :waitGps)));
        var y = (h * 0.86).toNumber();
        var tw = dc.getTextWidthInPixels(text, Graphics.FONT_XTINY);
        var fh = Graphics.getFontHeight(Graphics.FONT_XTINY);
        dc.setColor(r.on && r.gpsOk && !r.noData ? Graphics.COLOR_RED : Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - tw / 2 - 7, y + fh / 2, 4);
        dc.drawText(cx + 4, y, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Obrazovka mapovani: stav zaznamu a GPS, vzdalenost, body, cas,
    // maxima od zapnuti nahravani a stav odesilani na web
    private function drawMapping(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var cx = w / 2;
        var r = recorder();
        var fh = Graphics.getFontHeight(Graphics.FONT_XTINY);
        var y = (h * 0.20).toNumber();

        // Stav: REC / pozastaveno / plno, a kvalita GPS
        // Pri pozastaveni napoveda, ze nahravani zapina UP (v barve jeho oblouku)
        var st = r.full ? Tr.t(:recFull) : (r.on ? (r.gpsOk ? (r.noData ? noDataText() : "REC") : Tr.t(r.gpsWeak ? :gpsWeak : :waitGps)) : Tr.t(r.paused ? :recPauseUp : :recPausedUp));
        dc.setColor(r.on && r.gpsOk && !r.noData ? Graphics.COLOR_RED : (!r.on && !r.full ? UP_TEXT : Graphics.COLOR_ORANGE), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, st, Graphics.TEXT_JUSTIFY_CENTER);
        y += fh;

        // Vzdalenost velkym pismem
        var km = r.meters / 1000.0;
        var distText = r.meters < 999.5 ? r.meters.format("%.0f") + " m" : km.format(km < 9.995 ? "%.2f" : "%.1f") + " km";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_MEDIUM, distText, Graphics.TEXT_JUSTIFY_CENTER);
        y += Graphics.getFontHeight(Graphics.FONT_MEDIUM);

        // Body a doba nahravani
        var mins = r.activeSec() / 60;
        var dur = (mins / 60) + ":" + (mins % 60).format("%02d");
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, r.session + " " + Tr.t(:points) + "  " + dur + " h", Graphics.TEXT_JUSTIFY_CENTER);
        y += fh + 4;

        // Maxima v ulozenych bodech od zapnuti nahravani
        dc.setColor(CHART_DOSE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_TINY, "max " + (r.session > 0 ? doseNum(r.maxDose) + " " + doseUnit(r.maxDose) : "-- uSv/h"), Graphics.TEXT_JUSTIFY_CENTER);
        y += Graphics.getFontHeight(Graphics.FONT_TINY);
        dc.setColor(CHART_CPS, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_TINY, "max " + (r.session > 0 ? cpsNum(r.maxCps) + " " + cpsUnit(r.maxCps) : "-- cps"), Graphics.TEXT_JUSTIFY_CENTER);
        y += Graphics.getFontHeight(Graphics.FONT_TINY) + 4;

        // Odesilani na web
        var u = uploader();
        var bad = u.status == :upAuth || u.status == :upErr || u.verify == :vfBad;
        var webText = u.verify == :vfBad ? Tr.t(:vfBad) : u.label();
        dc.setColor(bad ? Graphics.COLOR_RED : (u.verify == :vfOk ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, fitText(dc, Tr.t(:web) + ": " + webText, Graphics.FONT_XTINY, chordAt(h, y, Graphics.FONT_XTINY)), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Nahravani bezi, ale body se neukladaji: pretizeni nebo chybi data
    private function noDataText() as String {
        return _state.ovl ? "OVL" : Tr.t(:waitRaysid);
    }

    // Znacky u tlacitek: zvyraznene oblouky na okraji. START vpravo nahore
    // (~30 stupnu), UP vlevo (~180) a DOWN vlevo dole (~210), uhly od 3 hodin
    // proti smeru hodinovych rucicek.
    private function drawMenuHint(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var r = (w < h ? w : h) / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawArc(w / 2, h / 2, r - 2, Graphics.ARC_COUNTER_CLOCKWISE, 24, 36);
        // UP ma na kazde obrazovce vlastni akci, proto jinou barvou nez DOWN
        // a o par px tlustsi (polomer mensi, aby zustal u okraje)
        dc.setColor(UP_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(7);
        dc.drawArc(w / 2, h / 2, r - 4, Graphics.ARC_COUNTER_CLOCKWISE, 174, 186);
        dc.setPenWidth(3);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(w / 2, h / 2, r - 2, Graphics.ARC_COUNTER_CLOCKWISE, 204, 216);
        dc.setPenWidth(1);
    }

    private function drawDebug(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.25, Graphics.FONT_XTINY, Tr.t(:packets) + ": " + _state.packets, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.31, Graphics.FONT_XTINY, _state.typeInfo, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.84, Graphics.FONT_XTINY, Tr.t(:refresh) + " " + intervalText(), Graphics.TEXT_JUSTIFY_CENTER);
        // Hex po radcich, aby se vesel na kulaty displej
        var raw = _state.lastRaw;
        var y = h * 0.39;
        var line = 0;
        while (raw.length() > 0 && line < 5) {
            var n = raw.length() < 24 ? raw.length() : 24;
            dc.drawText(cx, y, Graphics.FONT_XTINY, raw.substring(0, n), Graphics.TEXT_JUSTIFY_CENTER);
            raw = raw.substring(n, raw.length());
            y += dc.getFontHeight(Graphics.FONT_XTINY);
            line++;
        }
    }

    private function intervalText() as String {
        if (_state.intervalMs == null) {
            return "--";
        }
        // Posledni interval a klouzavy prumer, oboje v ms
        return _state.lastIntervalMs + " ms (" + Tr.t(:avgShort) + " " + (_state.intervalMs as Float).toNumber() + " ms)";
    }

    // Graf davkoveho prikonu (zelene, stupnice vlevo) a cps (modre, stupnice vpravo)
    // za poslednich chartSec sekund. Kazda rada ma vlastni automatickou stupnici.
    private function drawChart(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var cx = w / 2;
        var stale = _state.lastUpdate == null || System.getTimer() - (_state.lastUpdate as Number) > 5000;

        // Aktualni hodnoty nahore
        var blinkOff = (System.getTimer() / 500) % 2 != 0;
        dc.setColor(doseOvl(_state) ? (blinkOff ? Graphics.COLOR_BLACK : Graphics.COLOR_RED) : (stale ? Graphics.COLOR_DK_GRAY : CHART_DOSE), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.17 - UP_SHIFT, Graphics.FONT_SMALL, (doseOvl(_state) ? "OVL uSv/h" : doseNum(_state.shownDose()) + " " + doseUnit(_state.shownDose())), Graphics.TEXT_JUSTIFY_CENTER);
        var shownCps = _state.shownCps();
        var cpsText = cpsOvl(_state) ? "OVL kcps" : cpsNum(shownCps) + " " + cpsUnit(shownCps);
        dc.setColor(cpsOvl(_state) ? (blinkOff ? Graphics.COLOR_BLACK : Graphics.COLOR_RED) : (stale ? Graphics.COLOR_DK_GRAY : CHART_CPS), Graphics.COLOR_TRANSPARENT);
        // O par px vys, aby ho nezakryl pruh alarmu nad grafem
        dc.drawText(cx, h * 0.17 - UP_SHIFT + Graphics.getFontHeight(Graphics.FONT_SMALL) - 7, Graphics.FONT_SMALL, cpsText, Graphics.TEXT_JUSTIFY_CENTER);

        // Spodek grafu jde nahoru min nez zbytek (graf se natahne) a diky
        // tomu se do kulateho displeje vejde i o neco sirsi
        var y0 = (h * 0.40).toNumber() - UP_SHIFT;
        var y1 = (h * 0.79).toNumber() - 17;
        // Sirka podle kulateho displeje: vsechny rohy grafu musi zustat aspon
        // 12 px od okraje, aby nekolidovaly s okrajem ani se znackami tlacitek
        var rr = (w < h ? w : h) / 2 - 12;
        var dy0 = (y0 - h / 2).abs();
        var dy1 = (y1 - h / 2).abs();
        var dy = dy0 > dy1 ? dy0 : dy1;
        var half = Math.sqrt(rr * rr - dy * dy).toNumber();
        if (half > (w * 0.415).toNumber()) {
            half = (w * 0.415).toNumber();
        }
        var x0 = cx - half;
        var x1 = cx + half;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(x0, y0, x1, y0);
        dc.drawLine(x0, (y0 + y1) / 2, x1, (y0 + y1) / 2);
        dc.drawLine(x0, y1, x1, y1);
        // Popisky casu posunute dovnitr, aby je neorizl kulaty okraj
        var now = System.getTimer();
        // Dokud nejsou data za celou zvolenou dobu (po spusteni, po vypadku),
        // roztahne se graf na to, co je, aby vyplnil celou sirku
        var spanMs = _state.chartSec * 1000;
        var wantMs = spanMs;
        var haveMs = 0;
        if (_state.histCount > 0) {
            // Zacatek souvisleho useku dat (po vypadku se graf roztahne znovu);
            // prochazi se jen viditelne okno
            var newest = (_state.histHead - 1 + _state.HIST) % _state.HIST;
            var first = _state.histT[newest] as Number;
            for (var k = 1; k < _state.histCount; k++) {
                var t = _state.histT[(_state.histHead - 1 - k + _state.HIST) % _state.HIST] as Number;
                if (first - t > 5000 || now - t > spanMs) {
                    break;
                }
                first = t;
            }
            var have = now - first;
            haveMs = have;
            if (have < spanMs) {
                var floor = spanMs < 10000 ? spanMs : 10000;
                spanMs = have < floor ? floor : have;
            }
        }
        var tMin = now - spanMs;
        // Prumer se pocita az pri kresleni ze surovych mereni, takze zmena
        // nastaveni hned plati pro cely graf i pro cisla nahore
        // V grafu je okno prumeru nejvys petina jeho delky, jinak by se
        // cara jen rozmazala (10 s graf = prumer nejvys 2 s, 60 s = 12 s)
        var capMs = _state.chartSec * 200;
        _state.smooth(tMin, capMs);
        dc.drawText(w * 0.17, y1 + 1, Graphics.FONT_XTINY, "-" + ((spanMs + 500) / 1000) + " s", Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(w * 0.83, y1 + 1, Graphics.FONT_XTINY, Tr.t(:now), Graphics.TEXT_JUSTIFY_RIGHT);
        var bms = bucketMs(spanMs);
        var buckets = spanMs > 30000 ? buildBuckets(tMin, bms) : null;
        // Rozsah hodnot ve viditelnem okne
        var dMin = null, dMax = null, cMin = null, cMax = null;
        var n = 0;
        for (var k = 0; buckets == null && k < _state.histCount; k++) {
            var i = (_state.histHead - 1 - k + _state.HIST) % _state.HIST;
            if ((_state.histT[i] as Number) < tMin) {
                break;
            }
            var d = _state.smDose[i] as Float;
            var c = _state.smCps[i] as Float;
            dMin = dMin == null || d < dMin ? d : dMin;
            dMax = dMax == null || d > dMax ? d : dMax;
            cMin = cMin == null || c < cMin ? c : cMin;
            cMax = cMax == null || c > cMax ? c : cMax;
            n++;
        }
        // Pri prumerovani stupnice podle prumeru, aby jeden vykyv nesplacl zbytek grafu
        if (buckets != null) {
            var bd = buckets[1] as Array<Float>;
            var bc = buckets[4] as Array<Float>;
            n = bd.size();
            for (var j = 0; j < n; j++) {
                dMin = dMin == null || bd[j] < dMin ? bd[j] : dMin;
                dMax = dMax == null || bd[j] > dMax ? bd[j] : dMax;
                cMin = cMin == null || bc[j] < cMin ? bc[j] : cMin;
                cMax = cMax == null || bc[j] > cMax ? bc[j] : cMax;
            }
        }
        if (n < 2) {
            drawRange(dc, cx, h, haveMs, wantMs, capMs);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            // V horni polovine grafu, at se nekryje se stredovou carou; bez
            // dat (odpojeno) stav pripojeni misto "sbiram data"
            var noData = _state.lastUpdate == null || now - (_state.lastUpdate as Number) > 5000;
            dc.drawText(cx, y0 + (y1 - y0) / 4, Graphics.FONT_XTINY, Tr.t(noData ? _state.status : :collecting), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var dr = scale(dMin as Float, dMax as Float, 0.005);
        var cr = scale(cMin as Float, cMax as Float, 0.5);

        drawAlarmBands(dc, x0, x1, y0, y1, tMin, now);
        if (buckets != null) {
            drawBuckets(dc, buckets, 3, 4, 5, cr, x0, x1, y0, y1, tMin, now, CHART_CPS, true);
            drawBuckets(dc, buckets, 0, 1, 2, dr, x0, x1, y0, y1, tMin, now, CHART_DOSE, false);
        } else {
            dc.setPenWidth(2);
            drawSeries(dc, _state.smCps, cr, x0, x1, y0, y1, tMin, now, CHART_CPS);
            drawSeries(dc, _state.smDose, dr, x0, x1, y0, y1, tMin, now, CHART_DOSE);
        }
        dc.setPenWidth(1);

        // Stupnice: davka vlevo, cps vpravo. Kresli se az nakonec s cernym
        // pozadim, aby je cary grafu nikdy neprekryly.
        var fh = Graphics.getFontHeight(Graphics.FONT_XTINY);
        dc.setColor(CHART_DOSE, Graphics.COLOR_BLACK);
        dc.drawText(x0 + 2, y0 + 1, Graphics.FONT_XTINY, formatDose(dr[1]), Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(x0 + 2, y1 - 1 - fh, Graphics.FONT_XTINY, formatDose(dr[0]), Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(CHART_CPS, Graphics.COLOR_BLACK);
        dc.drawText(x1 - 2, y0 + 1, Graphics.FONT_XTINY, formatCps(cr[1]), Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(x1 - 2, y1 - 1 - fh, Graphics.FONT_XTINY, formatCps(cr[0]), Graphics.TEXT_JUSTIFY_RIGHT);

        drawRange(dc, cx, h, haveMs, wantMs, capMs);
    }

    // Zvoleny rozsah vyrazne bile (meni se tlacitkem UP). Dokud nejsou data
    // za celou dobu, za nim oranzove, za kolik sekund uz jsou.
    private function drawRange(dc as Graphics.Dc, cx as Number, h as Number, haveMs as Number, wantMs as Number, capMs as Number) as Void {
        var fy = (h * 0.865).toNumber() - UP_SHIFT - 13;
        var rangeText = _state.chartSec + " s";
        var waitText = haveMs < wantMs - 1000 ? "  (" + Tr.t(:chartWait) + " " + (haveMs / 1000) + " s)" : "";
        var waitColor = Graphics.COLOR_ORANGE;
        // Po naplneni grafu sede, jak se v grafu skutecne prumeruje
        if (waitText.length() == 0 && _state.avgMode != 0) {
            waitText = "  " + chartAvgText(capMs);
            waitColor = Graphics.COLOR_LT_GRAY;
        }
        var rw = dc.getTextWidthInPixels(rangeText, Graphics.FONT_TINY);
        var ww = waitText.length() > 0 ? dc.getTextWidthInPixels(waitText, Graphics.FONT_XTINY) : 0;
        var fx = cx - (rw + ww) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(fx, fy, Graphics.FONT_TINY, rangeText, Graphics.TEXT_JUSTIFY_LEFT);
        if (ww > 0) {
            var fbase = fy + Graphics.getFontAscent(Graphics.FONT_TINY);
            dc.setColor(waitColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(fx + rw, fbase - Graphics.getFontAscent(Graphics.FONT_XTINY), Graphics.FONT_XTINY, waitText, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // Popisek skutecneho prumeru v grafu; kdyz ho omezila delka grafu, s "max"
    private function chartAvgText(capMs as Number) as String {
        if (_state.avgMode == 1) {
            var sec = _state.avgSec * 1000 > capMs ? capMs / 1000 : _state.avgSec;
            return Tr.t(:avgShort) + " " + sec + " s";
        }
        var iv = _state.intervalMs != null ? (_state.intervalMs as Float) : 2000.0;
        if (_state.avgN * iv > capMs) {
            return Tr.t(:avgShort) + " " + (capMs / 1000) + " s";
        }
        return Tr.t(:avgShort) + " " + _state.avgN + "x";
    }

    // Delka useku pro prumerovani: zhruba 24 useku na graf, nejmene 4 s (2 mereni)
    private function bucketMs(spanMs as Number) as Number {
        var ms = spanMs / 24;
        return ms < 4000 ? 4000 : ms;
    }

    // Mereni v okne rozdelena do useku pevne zarovnanych na cas (graf pri
    // posouvani neposkakuje). Vraci pole: [davka min, prumer, max,
    // cps min, prumer, max, cas stredu useku], od nejstarsiho.
    private function buildBuckets(tMin as Number, bms as Number) as Array<Array> {
        var out = [[], [], [], [], [], [], []] as Array<Array>;
        var count = 0;
        for (var k = 0; k < _state.histCount; k++) {
            var i = (_state.histHead - 1 - k + _state.HIST) % _state.HIST;
            if ((_state.histT[i] as Number) < tMin) {
                break;
            }
            count++;
        }
        var cur = null;
        var sd = 0.0, sc = 0.0, nn = 0;
        var dmn = 0.0, dmx = 0.0, cmn = 0.0, cmx = 0.0;
        for (var k = count - 1; k >= -1; k--) {
            var key = null;
            var i = 0;
            if (k >= 0) {
                i = (_state.histHead - 1 - k + _state.HIST) % _state.HIST;
                key = (_state.histT[i] as Number) / bms;
            }
            if (cur != null && key != cur && nn > 0) {
                out[0].add(dmn);
                out[1].add(sd / nn);
                out[2].add(dmx);
                out[3].add(cmn);
                out[4].add(sc / nn);
                out[5].add(cmx);
                out[6].add((cur as Number) * bms + bms / 2);
                nn = 0;
                sd = 0.0;
                sc = 0.0;
            }
            if (k < 0) {
                break;
            }
            cur = key;
            // Min a max ze surovych mereni (spicky zustanou videt), stred
            // z prumerovanych hodnot jako u cisel nahore
            var d = _state.histDose[i] as Float;
            var c = _state.histCps[i] as Float;
            if (nn == 0) {
                dmn = d;
                dmx = d;
                cmn = c;
                cmx = c;
            }
            dmn = d < dmn ? d : dmn;
            dmx = d > dmx ? d : dmx;
            cmn = c < cmn ? c : cmn;
            cmx = c > cmx ? c : cmx;
            sd += _state.smDose[i] as Float;
            sc += _state.smCps[i] as Float;
            nn++;
        }
        return out;
    }

    // Prumer jako silna cara; u cps navic tenka tlumena carka min-max v useku,
    // aby byly videt kratke spicky (davka jde s cps, druha carka by jen rusila)
    private function drawBuckets(dc as Graphics.Dc, b as Array<Array>, iMin as Number, iAvg as Number, iMax as Number,
            range as Array<Float>, x0 as Number, x1 as Number, y0 as Number, y1 as Number,
            tMin as Number, now as Number, color as Number, whisker as Boolean) as Void {
        var tSpan = (now - tMin).toFloat();
        var vSpan = range[1] - range[0];
        var times = b[6] as Array<Number>;
        var mins = b[iMin] as Array<Float>;
        var avgs = b[iAvg] as Array<Float>;
        var maxs = b[iMax] as Array<Float>;
        dc.setColor(CHART_CPS_DIM, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        for (var j = 0; whisker && j < times.size(); j++) {
            var x = x0 + ((times[j] - tMin) / tSpan * (x1 - x0)).toNumber();
            var ya = clampY(y1 - ((mins[j] - range[0]) / vSpan * (y1 - y0)).toNumber(), y0, y1);
            var yb = clampY(y1 - ((maxs[j] - range[0]) / vSpan * (y1 - y0)).toNumber(), y0, y1);
            if (x >= x0 && x <= x1 && ya - yb >= 2) {
                dc.drawLine(x, ya, x, yb);
            }
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var px = 0, py = 0;
        for (var j = 0; j < times.size(); j++) {
            var x = x0 + ((times[j] - tMin) / tSpan * (x1 - x0)).toNumber();
            x = x < x0 ? x0 : (x > x1 ? x1 : x);
            var y = clampY(y1 - ((avgs[j] - range[0]) / vSpan * (y1 - y0)).toNumber(), y0, y1);
            if (j > 0) {
                dc.drawLine(px, py, x, y);
            }
            px = x;
            py = y;
        }
    }

    private function clampY(y as Number, y0 as Number, y1 as Number) as Number {
        return y < y0 ? y0 : (y > y1 ? y1 : y);
    }

    // Automaticka stupnice: rozsah min..max s rezervou, ale aspon 10 % hodnoty,
    // aby stabilni signal nebyl jen sum roztazeny pres cely graf.
    private function scale(mn as Float, mx as Float, absMin as Float) as Array<Float> {
        var mid = (mn + mx) / 2.0;
        var span = mx - mn;
        var minSpan = mid * 0.2 > absMin ? mid * 0.2 : absMin;
        if (span < minSpan) {
            span = minSpan;
        }
        var lo = mid - span * 0.6;
        var hi = mid + span * 0.6;
        if (lo < 0.0) {
            hi -= lo;
            lo = 0.0;
        }
        return [lo, hi];
    }

    private function drawSeries(dc as Graphics.Dc, vals as Array<Float>, range as Array<Float>,
            x0 as Number, x1 as Number, y0 as Number, y1 as Number,
            tMin as Number, now as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var px = 0, py = 0;
        var first = true;
        var tSpan = (now - tMin).toFloat();
        var vSpan = range[1] - range[0];
        // Od nejstarsiho bodu v okne k nejnovejsimu
        var count = 0;
        for (var k = 0; k < _state.histCount; k++) {
            var i = (_state.histHead - 1 - k + _state.HIST) % _state.HIST;
            if ((_state.histT[i] as Number) < tMin) {
                break;
            }
            count++;
        }
        for (var k = count - 1; k >= 0; k--) {
            var i = (_state.histHead - 1 - k + _state.HIST) % _state.HIST;
            var x = x0 + (((_state.histT[i] as Number) - tMin) / tSpan * (x1 - x0)).toNumber();
            var y = y1 - (((vals[i] as Float) - range[0]) / vSpan * (y1 - y0)).toNumber();
            if (!first) {
                dc.drawLine(px, py, x, y);
            }
            first = false;
            px = x;
            py = y;
        }
    }

    // Useky s alarmem podbarvene tmave cervene; pevny alarm ma navic cervene pruhy
    private function drawAlarmBands(dc as Graphics.Dc, x0 as Number, x1 as Number, y0 as Number, y1 as Number,
            tMin as Number, now as Number) as Void {
        var tSpan = (now - tMin).toFloat();
        var prevX = x1;
        for (var k = 0; k < _state.histCount; k++) {
            var i = (_state.histHead - 1 - k + _state.HIST) % _state.HIST;
            var t = _state.histT[i] as Number;
            var x = x0 + ((t - tMin) / tSpan * (x1 - x0)).toNumber();
            if (x < x0) {
                x = x0;
            }
            var a = _state.histAlarm[i] as Number;
            if (a > 0) {
                // Tmave podbarveni, aby cary zustaly citelne; pevny alarm ma navic cerveny pruh nahore a dole
                dc.setColor(0x550000, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, y0 + 1, prevX - x + 1, y1 - y0 - 1);
                if (a == 2) {
                    dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                    dc.fillRectangle(x, y0 - 2, prevX - x + 1, 4);
                    dc.fillRectangle(x, y1 - 2, prevX - x + 1, 4);
                }
            }
            prevX = x;
            if (t < tMin) {
                break;
            }
        }
    }

    // Popisek stupnice: do 1000 cislo, nad tim v tisicich s "k"
    private function formatCps(v as Float) as String {
        // Meze podle zaokrouhleni, at 99.97 neukaze "100.0" a 999.6 "1000"
        if (v < 99.95) {
            return v.format("%.1f");
        }
        if (v < 999.5) {
            return v.format("%.0f");
        }
        var k = v / 1000.0;
        return k.format(k < 9.995 ? "%.2f" : (k < 99.95 ? "%.1f" : "%.0f")) + "k";
    }

    // Popisek stupnice: stejna cisla jako jinde, v mSv/h s "m" za cislem
    private function formatDose(v as Float?) as String {
        return doseNum(v) + (v != null && v >= 999.5 ? "m" : "");
    }
}
