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
import Toybox.WatchUi;

// Entering a custom value digit by digit with the watch system Picker:
// UP/DOWN changes the digit, START moves to the next digit (saves on the last one),
// BACK goes back one digit or cancels. Nothing is held, because
// holding UP/DOWN on the fenix triggers system shortcuts.

class DigitFactory extends WatchUi.PickerFactory {
    function initialize() {
        PickerFactory.initialize();
    }

    function getSize() as Number {
        return 10;
    }

    function getValue(index as Number) as Object? {
        return index;
    }

    function getIndex(value as Number) as Number {
        return value;
    }

    function getDrawable(index as Number, isSelected as Boolean) as Drawable? {
        return new WatchUi.Text({
            :text => index.toString(),
            :color => isSelected ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY,
            :font => Graphics.FONT_NUMBER_MILD,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER
        });
    }
}

class DigitPicker extends WatchUi.Picker {
    // intDigits digits before the decimal point, decDigits after it
    function initialize(title as String, intDigits as Number, decDigits as Number, current as Float) {
        var pattern = [] as Array<PickerFactory or Drawable>;
        var defaults = [] as Array<Number>;
        var scaled = (current * pow10(decDigits) + 0.5).toNumber();
        var total = intDigits + decDigits;
        var digits = [] as Array<Number>;
        for (var i = 0; i < total; i++) {
            digits.add(0);
        }
        for (var i = total - 1; i >= 0; i--) {
            digits[i] = scaled % 10;
            scaled /= 10;
        }
        for (var i = 0; i < total; i++) {
            if (decDigits > 0 && i == intDigits) {
                pattern.add(new WatchUi.Text({
                    :text => ".",
                    :color => Graphics.COLOR_WHITE,
                    :font => Graphics.FONT_NUMBER_MILD,
                    :locX => WatchUi.LAYOUT_HALIGN_CENTER,
                    :locY => WatchUi.LAYOUT_VALIGN_CENTER
                }));
                defaults.add(0);
            }
            pattern.add(new DigitFactory());
            defaults.add(digits[i]);
        }
        var titleText = new WatchUi.Text({
            :text => title,
            :color => 0xFFAA00,
            :font => Graphics.FONT_TINY,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_BOTTOM
        });
        Picker.initialize({:title => titleText, :pattern => pattern, :defaults => defaults});
    }

    static function pow10(n as Number) as Float {
        var f = 1.0;
        for (var i = 0; i < n; i++) {
            f *= 10.0;
        }
        return f;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        Picker.onUpdate(dc);
    }
}

class DigitPickerDelegate extends WatchUi.PickerDelegate {
    private var _decDigits as Number;
    private var _min as Float;
    private var _max as Float;
    private var _onDone as Method(value as Float) as Void;

    function initialize(decDigits as Number, minV as Float, maxV as Float, onDone as Method(value as Float) as Void) {
        PickerDelegate.initialize();
        _decDigits = decDigits;
        _min = minV;
        _max = maxV;
        _onDone = onDone;
    }

    // The value is built from the digits; outside the allowed range it is clamped to its edge
    function onAccept(values as Array) as Boolean {
        var n = 0;
        for (var i = 0; i < values.size(); i++) {
            var v = values[i];
            if (v instanceof Number) {
                n = n * 10 + v;
            }
        }
        var value = n.toFloat() / DigitPicker.pow10(_decDigits);
        if (value < _min) {
            value = _min;
        } else if (value > _max) {
            value = _max;
        }
        _onDone.invoke(value);
        return true;
    }

    function onCancel() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
