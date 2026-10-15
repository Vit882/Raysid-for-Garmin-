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
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Entering the Zhava mista API key directly on the watch (for an app loaded via
// USB, settings in Garmin Connect do not work). UP/DOWN selects a character, START
// adds it, BACK deletes the last character (on empty input cancels entry). At the
// end of the character list is OK, which saves the key. Nothing is held (holding
// UP/DOWN triggers system shortcuts).
// The Zhava mista key is 48 hexadecimal characters, so 0-9 and a-f are enough
const KEY_CHARS = "0123456789abcdef";
const KEY_LEN = 48;

class KeyEntryView extends WatchUi.View {
    var text as String = "";
    var pos as Number = 0;      // index into KEY_CHARS, KEY_CHARS.length() = OK

    var orig as String = "";

    function initialize(current as String) {
        View.initialize();
        text = current;
        orig = current;
        // Key already entered: cursor straight on OK (START = back without change)
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

        // Entered text in lines, the end is shown (last 3 lines)
        var per = 16;
        var lines = [] as Array<String>;
        for (var i = 0; i < text.length(); i += per) {
            var e = i + per < text.length() ? i + per : text.length();
            // In groups of four so the key is easy to compare with the website
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

        // Selected character large, neighbors smaller
        var y = h * 0.62;
        var n = okIndex() + 1;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - w * 0.22, y, Graphics.FONT_MEDIUM, label((pos - 1 + n) % n), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + w * 0.22, y, Graphics.FONT_MEDIUM, label((pos + 1) % n), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(pos == okIndex() ? Graphics.COLOR_GREEN : 0x00AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_LARGE, label(pos), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.80, Graphics.FONT_XTINY, Tr.t(:keyHelp), Graphics.TEXT_JUSTIFY_CENTER);
        // Where to find the key: until something is entered, in the place for the entered text
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
            _view.pos = _view.okIndex();   // the key is complete, no more characters
            WatchUi.requestUpdate();
            return true;
        }
        _view.text += _view.label(_view.pos);
        // After the last character offer OK right away
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

    // Ignore touch so nothing changes by accident
    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean {
        return true;
    }

    private function save() as Void {
        // No change: just close (the key is already in settings)
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
        // Backup in Storage, in case settings are lost on an app update
        put("zmKeyBak", _view.text);
        uploader().settingsChanged();
        // Verify right away that the website accepts the key
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

// Label of the API key item: not set, or the end of the key
function keyLabel() as String {
    var k = currentKey();
    if (k.length() == 0) {
        return Tr.t(:upNoKey);
    }
    return "..." + k.substring(k.length() > 4 ? k.length() - 4 : 0, k.length());
}

// Key from settings; if empty (e.g. after an update), from the backup
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
