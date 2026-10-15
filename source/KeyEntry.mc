// Raysid Garmin – Connect IQ aplikace pro dozimetr Raysid
// Copyright (C) 2026 Vít Cenek a přispěvatelé (viz AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tento program je svobodný software: můžete ho šířit a upravovat podle
// GNU General Public License verze 3 nebo (podle vaší volby) jakékoli
// pozdější, jak ji vydala Free Software Foundation. Šíří se BEZ JAKÉKOLI
// ZÁRUKY. Plné znění licence je v souboru LICENSE.

import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Zadani API klice Zhavych mist primo v hodinkach (u aplikace nahrane pres
// USB nefunguje nastaveni v Garmin Connect). UP/DOWN vybira znak, START ho
// prida, BACK smaze posledni znak (u prazdneho zrusi zadavani). Na konci
// seznamu znaku je OK, ktere klic ulozi. Nic se nedrzi (podrzeni UP/DOWN
// spousti systemove zkratky).
// Klic Zhavych mist je 48 hexadecimalnich znaku, staci tedy 0-9 a a-f
const KEY_CHARS = "0123456789abcdef";
const KEY_LEN = 48;

class KeyEntryView extends WatchUi.View {
    var text as String = "";
    var pos as Number = 0;      // index v KEY_CHARS, KEY_CHARS.length() = OK

    var orig as String = "";

    function initialize(current as String) {
        View.initialize();
        text = current;
        orig = current;
        // Klic uz je zadany: kurzor rovnou na OK (START = beze zmeny zpet)
        if (current.length() > 0) {
            pos = KEY_CHARS.length();
        }
    }

    function okIndex() as Number {
        return KEY_CHARS.length();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(0xFFAA00, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.10, Graphics.FONT_XTINY, Tr.t(:apiKey) + " " + text.length() + "/" + KEY_LEN, Graphics.TEXT_JUSTIFY_CENTER);

        // Zadany text po radcich, zobrazi se konec (posledni 3 radky)
        var per = 16;
        var lines = [] as Array<String>;
        for (var i = 0; i < text.length(); i += per) {
            var e = i + per < text.length() ? i + per : text.length();
            // Po ctvericich, aby se dal klic snadno porovnat s webem
            var line = "";
            for (var j = i; j < e; j += 4) {
                line += (j > i ? " " : "") + text.substring(j, j + 4 < e ? j + 4 : e);
            }
            lines.add(line);
        }
        var first = lines.size() > 3 ? lines.size() - 3 : 0;
        var fh = Graphics.getFontHeight(Graphics.FONT_XTINY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = first; i < lines.size(); i++) {
            dc.drawText(cx, h * 0.20 + (i - first) * fh, Graphics.FONT_XTINY, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Vybrany znak velky, sousedni mensi
        var y = h * 0.62;
        var n = okIndex() + 1;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - w * 0.22, y, Graphics.FONT_MEDIUM, label((pos - 1 + n) % n), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + w * 0.22, y, Graphics.FONT_MEDIUM, label((pos + 1) % n), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(pos == okIndex() ? Graphics.COLOR_GREEN : 0x00AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_LARGE, label(pos), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.80, Graphics.FONT_XTINY, Tr.t(:keyHelp), Graphics.TEXT_JUSTIFY_CENTER);
        // Kde klic najit: dokud se nic nezadalo, v miste pro zadany text
        if (text.length() == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.22, Graphics.FONT_XTINY, Tr.t(:keyWhere1), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, h * 0.22 + fh, Graphics.FONT_XTINY, Tr.t(:keyWhere2), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function label(i as Number) as String {
        return i == okIndex() ? "OK" : KEY_CHARS.substring(i, i + 1) as String;
    }
}

class KeyEntryDelegate extends WatchUi.BehaviorDelegate {
    private var _view as KeyEntryView;
    private var _item as WatchUi.MenuItem?;
    private var _verifyItem as WatchUi.MenuItem?;
    private var _uploadItem as WatchUi.MenuItem?;

    function initialize(view as KeyEntryView, item as WatchUi.MenuItem?, verifyItem as WatchUi.MenuItem?, uploadItem as WatchUi.MenuItem?) {
        BehaviorDelegate.initialize();
        _view = view;
        _item = item;
        _verifyItem = verifyItem;
        _uploadItem = uploadItem;
    }

    private function step(d as Number) as Boolean {
        var n = _view.okIndex() + 1;
        _view.pos = (_view.pos + d + n) % n;
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        return step(1);
    }

    function onPreviousPage() as Boolean {
        return step(-1);
    }

    function onSelect() as Boolean {
        if (_view.pos == _view.okIndex()) {
            save();
            return true;
        }
        if (_view.text.length() >= KEY_LEN) {
            _view.pos = _view.okIndex();   // klic je cely, dalsi znak uz ne
            WatchUi.requestUpdate();
            return true;
        }
        _view.text += _view.label(_view.pos);
        // Po poslednim znaku rovnou nabidnout OK
        if (_view.text.length() >= KEY_LEN) {
            _view.pos = _view.okIndex();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_ENTER) {
            return onSelect();
        }
        return false;
    }

    function onBack() as Boolean {
        var t = _view.text;
        if (t.length() == 0) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else {
            _view.text = t.substring(0, t.length() - 1) as String;
            WatchUi.requestUpdate();
        }
        return true;
    }

    // Dotyk ignorovat, aby se nic nezmenilo omylem
    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean {
        return true;
    }

    private function save() as Void {
        // Beze zmeny: jen zavrit (klic uz je v nastaveni)
        var p = null;
        try {
            p = Application.Properties.getValue("zmKey");
        } catch (e) {
        }
        if (_view.text.equals(_view.orig) && p instanceof String && p.equals(_view.text)) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return;
        }
        try {
            Application.Properties.setValue("zmKey", _view.text);
        } catch (e) {
        }
        // Zaloha v Storage, kdyby se nastaveni pri aktualizaci aplikace ztratilo
        put("zmKeyBak", _view.text);
        uploader().settingsChanged();
        // Hned overit, ze web klic prijme
        uploader().startVerify(_verifyItem);
        if (_item != null) {
            (_item as WatchUi.MenuItem).setSubLabel(keyLabel());
        }
        if (_uploadItem != null) {
            (_uploadItem as WatchUi.MenuItem).setSubLabel(uploader().label());
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// Popisek polozky API klic: nenastaven, nebo konec klice
function keyLabel() as String {
    var k = currentKey();
    if (k.length() == 0) {
        return Tr.t(:upNoKey);
    }
    return "..." + k.substring(k.length() > 4 ? k.length() - 4 : 0, k.length());
}

// Klic z nastaveni; kdyby bylo prazdne (napr. po aktualizaci), ze zalohy
function currentKey() as String {
    var k = null;
    try {
        k = Application.Properties.getValue("zmKey");
    } catch (e) {
    }
    if (k instanceof String && k.length() > 0) {
        return k;
    }
    k = Storage.getValue("zmKeyBak");
    return k instanceof String ? k : "";
}
