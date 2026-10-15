// Raysid Garmin - Connect IQ app for the Raysid dosimeter
// Copyright (C) 2026 Vít Cenek and contributors (see AUTHORS.md)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 3 or (at your
// option) any later version, as published by the Free Software Foundation.
// It is distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// One help page. Text wraps at words, UP/DOWN (and START) scroll the text.
class HelpView extends WatchUi.View {
    private var _title as String;
    private var _text as String;
    var offset as Number = 0;       // first visible line
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
        var titleY = (h * 0.11).toNumber();
        dc.drawText(r, titleY, Graphics.FONT_TINY, _title, Graphics.TEXT_JUSTIFY_CENTER);

        // Keep the text window in the middle of the round display, where it is wide enough
        var font = Graphics.FONT_XTINY;
        var lh = dc.getFontHeight(font);
        var top = (h * 0.22).toNumber();
        // The up arrow sits centered in the gap between the title and the text;
        // its size scales with the display (7 px half-width at 280 px)
        var titleBottom = titleY + dc.getFontHeight(Graphics.FONT_TINY);
        var ah = h / 40;
        if (top < titleBottom + ah + 8) {
            top = titleBottom + ah + 8;
        }
        var bottom = (h * 0.80).toNumber();
        var dy = r - top;
        var maxW = (2 * Math.sqrt(r * r - dy * dy) - 16).toFloat();
        // Wrap only once, not on every scroll (long texts)
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
        // Arrows when there is text above or below the window
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (offset > 0) {
            var yc = (titleBottom + top) / 2;
            dc.fillPolygon([[r - ah, yc + ah / 2], [r + ah, yc + ah / 2], [r, yc - ah / 2]]);
        }
        if (offset + visible < lines.size()) {
            dc.fillPolygon([[r - ah, bottom + 3], [r + ah, bottom + 3], [r, bottom + 3 + ah]]);
        }
        _visible = visible;
    }

    private var _visible as Number = 1;

    private function wrap(dc as Graphics.Dc, font as Graphics.FontType, maxW as Float) as Array<String> {
        var words = split(_text);
        var lines = [] as Array<String>;
        var line = "";
        for (var i = 0; i < words.size(); i++) {
            // A standalone "\n" in the text = new line (blank line between paragraphs)
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
