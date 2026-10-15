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
import Toybox.WatchUi;

// Jedna stranka napovedy. Text se zalamuje po slovech, UP/DOWN (a START) posouvaji text.
class HelpView extends WatchUi.View {
    private var _title as String;
    private var _text as String;
    var offset as Number = 0;       // prvni zobrazeny radek
    var lineCount as Number = 0;
    private var _lines as Array<String>? = null;

    function initialize(title as String, text as String) {
        View.initialize();
        _title = title;
        _text = text;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var r = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(0xFFAA00, Graphics.COLOR_TRANSPARENT);
        dc.drawText(r, h * 0.11, Graphics.FONT_TINY, _title, Graphics.TEXT_JUSTIFY_CENTER);

        // Textove okno drzime v prostredni casti kulateho displeje, kde je dost siroko
        var font = Graphics.FONT_XTINY;
        var lh = dc.getFontHeight(font);
        var top = (h * 0.22).toNumber();
        var bottom = (h * 0.80).toNumber();
        var dy = r - top;
        var maxW = (2 * Math.sqrt(r * r - dy * dy) - 16).toFloat();
        // Zalomit jen jednou, ne pri kazdem posunu (dlouhe texty)
        if (_lines == null) {
            _lines = wrap(dc, font, maxW);
        }
        var lines = _lines as Array<String>;
        lineCount = lines.size();
        var visible = (bottom - top) / lh;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var y = top;
        for (var i = offset; i < lines.size() && i < offset + visible; i++) {
            dc.drawText(r, y, font, lines[i] as String, Graphics.TEXT_JUSTIFY_CENTER);
            y += lh;
        }
        // Sipky, kdyz je text nad nebo pod oknem
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (offset > 0) {
            dc.fillPolygon([[r - 7, top - 3], [r + 7, top - 3], [r, top - 10]]);
        }
        if (offset + visible < lines.size()) {
            dc.fillPolygon([[r - 7, bottom + 3], [r + 7, bottom + 3], [r, bottom + 10]]);
        }
        _visible = visible;
    }

    private var _visible as Number = 1;

    private function wrap(dc as Graphics.Dc, font as Graphics.FontType, maxW as Float) as Array<String> {
        var words = split(_text);
        var lines = [] as Array<String>;
        var line = "";
        for (var i = 0; i < words.size(); i++) {
            // Samostatne "\n" v textu = novy radek (prazdny radek mezi odstavci)
            if ((words[i] as String).equals("\n")) {
                lines.add(line);
                line = "";
                continue;
            }
            var cand = line.length() == 0 ? words[i] as String : line + " " + words[i];
            if (line.length() > 0 && dc.getTextWidthInPixels(cand, font) > maxW) {
                lines.add(line);
                line = words[i] as String;
            } else {
                line = cand;
            }
        }
        if (line.length() > 0) {
            lines.add(line);
        }
        return lines;
    }

    private function split(s as String) as Array<String> {
        var out = [] as Array<String>;
        var rest = s;
        var idx = rest.find(" ");
        while (idx != null) {
            if (idx > 0) {
                out.add(rest.substring(0, idx) as String);
            }
            rest = rest.substring(idx + 1, rest.length()) as String;
            idx = rest.find(" ");
        }
        if (rest.length() > 0) {
            out.add(rest);
        }
        return out;
    }

    function scroll(delta as Number) as Void {
        var n = offset + delta;
        if (n < 0) {
            n = 0;
        }
        if (n > lineCount - _visible) {
            n = lineCount - _visible;
        }
        offset = n < 0 ? 0 : n;
        WatchUi.requestUpdate();
    }
}

class HelpDelegate extends WatchUi.BehaviorDelegate {
    private var _view as HelpView;

    function initialize(view as HelpView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.scroll(3);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.scroll(-3);
        return true;
    }

    function onSelect() as Boolean {
        _view.scroll(3);
        return true;
    }
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
