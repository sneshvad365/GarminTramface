import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

const REST_URL = "https://cdt.hafas.de/opendata/apiserver/departureBoard";
const REST_KEY = "041ad985-318b-44c4-a6d0-787b115a5ff8";

// Pages (fixed order):
//   0 — Bertrange Gare  → Gare Centrale   (shows first trains after 06:40)
//   1 — Lux Gare        → Bertrange       (direction filter by stop ID)
//   2 — Place de Metz   → Scillas         (toward Gasperich)
//   3 — Scillas         → Place de Metz   (toward Findel / city)
//   4 — Place de Metz   → Lux Gare        (never default)

function getPageForTime() as Lang.Number {
    var h = System.getClockTime().hour;
    if (h >= 20 || h < 8)  { return 0; }
    if (h < 12)             { return 2; }
    if (h < 14)             { return 3; }
    return 1;
}

function getSlotDef(page as Lang.Number) as Lang.Dictionary {
    var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
    var clk = System.getClockTime();
    var dateToday = Lang.format("$1$-$2$-$3$", [
        now.year.toString(),
        (now.month as Lang.Number).format("%02d"),
        (now.day   as Lang.Number).format("%02d")
    ]);
    var timeCurrent = Lang.format("$1$:$2$", [
        clk.hour.format("%02d"), clk.min.format("%02d")
    ]);

    if (page == 0) {
        var useNextDay = (clk.hour >= 20);
        var moment     = useNextDay ? Time.now().add(new Time.Duration(86400)) : Time.now();
        var dayInfo    = Gregorian.info(moment, Time.FORMAT_SHORT);
        var dateMorning = Lang.format("$1$-$2$-$3$", [
            dayInfo.year.toString(),
            (dayInfo.month as Lang.Number).format("%02d"),
            (dayInfo.day   as Lang.Number).format("%02d")
        ]);
        return { "stopId" => "200101024", "dir" => "Luxembourg",
                 "isTram" => false, "arrowRight" => false,
                 "date" => dateMorning, "time" => "06:40",
                 "title" => "Bertrange > L.Gare" };
    }
    if (page == 1) {
        return { "stopId" => "200405060", "destId" => "200101024",
                 "isTram" => false, "arrowRight" => true,
                 "date" => dateToday, "time" => timeCurrent,
                 "title" => "L.Gare > Bertrange" };
    }
    if (page == 2) {
        return { "stopId" => "200405051", "dir" => "Gasperich",
                 "isTram" => true, "arrowRight" => false,
                 "date" => dateToday, "time" => timeCurrent,
                 "title" => "Pl.Metz > Scillas" };
    }
    if (page == 3) {
        return { "stopId" => "200304021", "dir" => "Findel",
                 "isTram" => true, "arrowRight" => true,
                 "date" => dateToday, "time" => timeCurrent,
                 "title" => "Scillas > Pl.Metz" };
    }
    // Page 4 — never the default, manually navigated to
    // No dir filter: all departures from this platform are southbound and pass through Lux Gare
    return { "stopId" => "200405051",
             "isTram" => true, "arrowRight" => false,
             "date" => dateToday, "time" => timeCurrent,
             "title" => "Pl.Metz > Lux Gare" };
}

class tramfaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new tramfaceView(), new TramDelegate() ];
    }

    function fetchDepartures() as Void {
        var slot = getSlotDef(TramData.currentPage);
        TramData.isTram     = slot.get("isTram")     as Lang.Boolean;
        TramData.arrowRight = slot.get("arrowRight") as Lang.Boolean;
        TramData.pageTitle  = slot.get("title")      as Lang.String;
        TramData.updatedAt  = "fetching...";
        TramData.hasData    = false;
        WatchUi.requestUpdate();

        var destId = slot.get("destId") as Lang.String?;
        var params = {
            "accessId"    => REST_KEY,
            "extId"       => slot.get("stopId"),
            "date"        => slot.get("date"),
            "time"        => slot.get("time"),
            "format"      => "json",
            "maxJourneys" => (destId != null ? 5 : 10),
            "duration"    => (destId != null ? 120 : 45)
        } as Lang.Dictionary;

        if (destId != null) {
            params.put("direction", destId);
        }

        Communications.makeWebRequest(
            REST_URL,
            params,
            { :method      => Communications.HTTP_REQUEST_METHOD_GET,
              :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
            method(:onResponse)
        );
    }

    function onResponse(responseCode as Lang.Number, data as Lang.Dictionary?) as Void {
        if (responseCode != 200 || data == null) {
            TramData.updatedAt = "err " + responseCode.toString();
            WatchUi.requestUpdate();
            return;
        }
        var depArr = (data as Lang.Dictionary).get("Departure");
        if (depArr == null || !(depArr instanceof Lang.Array)) {
            TramData.updatedAt = "err:nodata";
            WatchUi.requestUpdate();
            return;
        }

        var slot   = getSlotDef(TramData.currentPage);
        var dirFlt = slot.get("dir") as Lang.String?;
        var deps   = parseDeps(depArr as Lang.Array, dirFlt);

        TramData.d1Line = null; TramData.d1Time = null; TramData.d1Dir = null; TramData.d1Delay = null;
        TramData.d2Line = null; TramData.d2Time = null; TramData.d2Dir = null; TramData.d2Delay = null;
        TramData.d3Line = null; TramData.d3Time = null; TramData.d3Dir = null; TramData.d3Delay = null;

        if (deps.size() > 0) {
            var d = deps[0] as Lang.Dictionary;
            TramData.d1Line = d.get("line"); TramData.d1Time = d.get("time");
            TramData.d1Dir  = d.get("dir");  TramData.d1Delay = d.get("delay");
        }
        if (deps.size() > 1) {
            var d = deps[1] as Lang.Dictionary;
            TramData.d2Line = d.get("line"); TramData.d2Time = d.get("time");
            TramData.d2Dir  = d.get("dir");  TramData.d2Delay = d.get("delay");
        }
        if (deps.size() > 2) {
            var d = deps[2] as Lang.Dictionary;
            TramData.d3Line = d.get("line"); TramData.d3Time = d.get("time");
            TramData.d3Dir  = d.get("dir");  TramData.d3Delay = d.get("delay");
        }

        var clk = System.getClockTime();
        TramData.updatedAt = Lang.format("$1$:$2$", [clk.hour, clk.min.format("%02d")]);
        TramData.hasData   = true;

        // Vibrate once if this was the default-page fetch and any departure is delayed
        if (TramData.vibrateOnDelays && TramData.currentPage == TramData.defaultPage) {
            TramData.vibrateOnDelays = false;
            var delayed = (TramData.d1Delay != null && (TramData.d1Delay as Lang.Number) > 0)
                       || (TramData.d2Delay != null && (TramData.d2Delay as Lang.Number) > 0)
                       || (TramData.d3Delay != null && (TramData.d3Delay as Lang.Number) > 0);
            if (delayed && (Attention has :vibrate)) {
                Attention.vibrate([new Attention.VibeProfile(100, 300)]);
            }
        }

        WatchUi.requestUpdate();
    }

    function shortName(name as Lang.String?) as Lang.String {
        if (name == null) { return "?"; }
        var idx = name.find(" ");
        if (idx == null || idx <= 0) {
            return name.length() > 4 ? name.substring(0, 4) : name;
        }
        var prefix = name.substring(0, idx);
        var rest   = name.substring(idx + 1, name.length());
        if (prefix.length() == 1 && rest.toNumber() != null) { return prefix + rest; }
        return prefix;
    }

    function timeDiffMins(actualHHMM as Lang.String, schedHHMM as Lang.String) as Lang.Number {
        var ah = actualHHMM.substring(0, 2).toNumber();
        var am = actualHHMM.substring(2, 4).toNumber();
        var sh = schedHHMM.substring(0, 2).toNumber();
        var sm = schedHHMM.substring(2, 4).toNumber();
        var diff = (ah * 60 + am) - (sh * 60 + sm);
        if (diff < -60) { diff += 1440; }
        if (diff < 0)   { diff = 0; }
        return diff;
    }

    function parseDeps(depArr as Lang.Array, dirFilter as Lang.String?) as Lang.Array {
        var result = [] as Lang.Array;
        for (var i = 0; i < depArr.size() && result.size() < 3; i++) {
            var dep = depArr[i] as Lang.Dictionary;

            var direction = dep.get("direction") as Lang.String?;
            if (direction == null) { direction = ""; }
            if (dirFilter != null && (direction as Lang.String).find(dirFilter) == null) { continue; }

            var sched = dep.get("time") as Lang.String?;
            if (sched == null) { continue; }
            // REST time format is "HH:MM:SS"
            var schedHHMM = (sched as Lang.String).substring(0, 2) + (sched as Lang.String).substring(3, 5);
            var timeStr   = (sched as Lang.String).substring(0, 5);

            var delay = 0;
            var rt = dep.get("rtTime") as Lang.String?;
            if (rt != null && (rt as Lang.String).length() >= 5) {
                var rtHHMM = (rt as Lang.String).substring(0, 2) + (rt as Lang.String).substring(3, 5);
                delay   = timeDiffMins(rtHHMM, schedHHMM);
                timeStr = (rt as Lang.String).substring(0, 5);
            }

            var prod = dep.get("ProductAtStop") as Lang.Dictionary?;
            var lineName = "?";
            if (prod != null) {
                var pName = (prod as Lang.Dictionary).get("name") as Lang.String?;
                if (pName != null) { lineName = shortName(pName); }
            }

            result.add({
                "line"  => lineName,
                "time"  => timeStr,
                "dir"   => direction,
                "delay" => delay
            });
        }
        return result;
    }
}

function getApp() as tramfaceApp {
    return Application.getApp() as tramfaceApp;
}
