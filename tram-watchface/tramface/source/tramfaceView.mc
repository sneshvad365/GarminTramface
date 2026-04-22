import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class tramfaceView extends WatchUi.View {

    private const BG    = 0x000000;
    private const FG    = 0xFFFFFF;
    private const MUTED = 0x888888;
    private const TRAM  = 0xF97316;
    private const TRAIN = 0x378ADD;
    private const AMB   = 0xF59E0B;
    private const RED   = 0xEF4444;

    private const NUM_PAGES = 5;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
    }

    function onShow() as Void {
        TramData.defaultPage     = getPageForTime();
        TramData.currentPage     = TramData.defaultPage;
        TramData.vibrateOnDelays = true;
        getApp().fetchDepartures();
    }

    function onHide() as Void {
        TramData.vibrateOnDelays = false;
    }


    function drawDep(dc as Dc, w as Lang.Number, h as Lang.Number,
                     yRow  as Lang.Number,
                     line  as Lang.String?,
                     time  as Lang.String?,
                     dir   as Lang.String?,
                     delay as Lang.Number?) as Void {

        var cx  = w / 2;
        var bw  = (w * 0.14).toNumber();
        var bh  = (h * 0.065).toNumber();
        var br  = 4;
        var bx  = cx - (w * 0.38).toNumber();
        var col = TramData.isTram ? TRAM : TRAIN;
        var yDir = yRow + (h * 0.075).toNumber();

        // Direction arrow (red triangle) just after the badge
        var ax = bx + bw + 4;
        var ay = yRow;
        dc.setColor(RED, Graphics.COLOR_TRANSPARENT);
        if (TramData.arrowRight) {
            dc.fillPolygon([[ax, ay - 5], [ax + 10, ay], [ax, ay + 5]]);
        } else {
            dc.fillPolygon([[ax + 10, ay - 5], [ax, ay], [ax + 10, ay + 5]]);
        }

        // Badge
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx, yRow - bh / 2, bw, bh, br);
        dc.setColor(BG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bx + bw / 2, yRow, Graphics.FONT_XTINY,
            line != null ? line : "?",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Departure time
        var tx = ax + 13;
        var timeStr = time != null ? time : "--:--";
        var delayed = delay != null && (delay as Lang.Number) > 0;
        dc.setColor(delayed ? AMB : FG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx, yRow, Graphics.FONT_MEDIUM, timeStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Delay badge
        if (delayed) {
            dc.setColor(RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - bx, yRow, Graphics.FONT_XTINY,
                "+" + (delay as Lang.Number).toString() + "m",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Direction text
        if (dir != null && !(dir as Lang.String).equals("")) {
            var dirStr = dir as Lang.String;
            if (dirStr.length() > 24) { dirStr = dirStr.substring(0, 24); }
            dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(bx, yDir, Graphics.FONT_XTINY, dirStr,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function drawPageDots(dc as Dc, w as Lang.Number, yDots as Lang.Number) as Void {
        var col = TramData.isTram ? TRAM : TRAIN;
        var spacing = 14;
        var totalW  = (NUM_PAGES - 1) * spacing;
        var startX  = w / 2 - totalW / 2;
        for (var i = 0; i < NUM_PAGES; i++) {
            var x = startX + i * spacing;
            if (i == TramData.currentPage) {
                dc.setColor(col, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, yDots, 4);
            } else {
                dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, yDots, 2);
            }
        }
    }

    function onUpdate(dc as Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(BG, BG);
        dc.clear();

        var clk = System.getClockTime();

        // Layout
        var yTime  = (h * 0.11).toNumber();
        var yTitle = (h * 0.21).toNumber();
        var yDiv   = (h * 0.28).toNumber();
        var yD1    = (h * 0.37).toNumber();
        var yD2    = (h * 0.57).toNumber();
        var yD3    = (h * 0.77).toNumber();
        var yDots  = (h * 0.90).toNumber();
        var yUpd   = (h * 0.96).toNumber();
        var pad    = (w * 0.14).toNumber();

        // ── Logo (two small badges: orange tram | blue train) ────────────
        var logoY  = (h * 0.05).toNumber();
        var bh     = 10;
        var bw     = 22;
        var gap    = 4;
        var lx     = cx - bw - gap / 2;
        var rx     = cx + gap / 2;
        dc.setColor(TRAM, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(lx, logoY - bh / 2, bw, bh, 3);
        dc.setColor(TRAIN, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(rx, logoY - bh / 2, bw, bh, 3);

        // ── Time ─────────────────────────────────────────────────────────
        var timeStr = Lang.format("$1$:$2$", [clk.hour, clk.min.format("%02d")]);
        dc.setColor(FG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yTime, Graphics.FONT_LARGE, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Page title ────────────────────────────────────────────────────
        var col = TramData.isTram ? TRAM : TRAIN;
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, yTitle, Graphics.FONT_SMALL,
            TramData.pageTitle != null ? TramData.pageTitle : "",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ── Divider ───────────────────────────────────────────────────────
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(pad, yDiv, w - pad, yDiv);

        // ── Departures ────────────────────────────────────────────────────
        if (!TramData.hasData) {
            dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
            var msg = (TramData.updatedAt != null) ? TramData.updatedAt : "Tap to fetch";
            dc.drawText(cx, (h * 0.55).toNumber(), Graphics.FONT_XTINY, msg,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            if (TramData.d1Time != null) {
                drawDep(dc, w, h, yD1,
                    TramData.d1Line as Lang.String?, TramData.d1Time as Lang.String?,
                    TramData.d1Dir  as Lang.String?, TramData.d1Delay as Lang.Number?);
            }
            if (TramData.d2Time != null) {
                drawDep(dc, w, h, yD2,
                    TramData.d2Line as Lang.String?, TramData.d2Time as Lang.String?,
                    TramData.d2Dir  as Lang.String?, TramData.d2Delay as Lang.Number?);
            }
            if (TramData.d3Time != null) {
                drawDep(dc, w, h, yD3,
                    TramData.d3Line as Lang.String?, TramData.d3Time as Lang.String?,
                    TramData.d3Dir  as Lang.String?, TramData.d3Delay as Lang.Number?);
            }
        }

        // ── Page dots ─────────────────────────────────────────────────────
        drawPageDots(dc, w, yDots);

        // ── Updated timestamp ─────────────────────────────────────────────
        if (TramData.updatedAt != null) {
            dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, yUpd, Graphics.FONT_XTINY,
                "upd " + TramData.updatedAt,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}

class TramDelegate extends WatchUi.BehaviorDelegate {

    private const NUM_PAGES = 5;

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Lang.Boolean {
        TramData.currentPage = (TramData.currentPage + 1) % NUM_PAGES;
        getApp().fetchDepartures();
        return true;
    }
}
