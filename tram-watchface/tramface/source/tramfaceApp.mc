import Toybox.Application;
import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

const GATE_URL = "https://cdt.hafas.de/gate";

// Pages (fixed order):
//   0 — Bertrange Gare  → Gare Centrale   (shows first trains after 06:40)
//   1 — Lux Gare        → Bertrange       (all westbound)
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
    var now  = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
    var clk  = System.getClockTime();
    var dateToday = Lang.format("$1$$2$$3$", [
        now.year.toString(),
        (now.month as Lang.Number).format("%02d"),
        (now.day   as Lang.Number).format("%02d")
    ]);
    var timeCurrent = Lang.format("$1$$2$$3$", [
        clk.hour.format("%02d"), clk.min.format("%02d"), clk.sec.format("%02d")
    ]);

    if (page == 0) {
        var useNextDay  = (clk.hour >= 20);
        var moment      = useNextDay ? Time.now().add(new Time.Duration(86400)) : Time.now();
        var dayInfo     = Gregorian.info(moment, Time.FORMAT_SHORT);
        var dateMorning = Lang.format("$1$$2$$3$", [
            dayInfo.year.toString(),
            (dayInfo.month as Lang.Number).format("%02d"),
            (dayInfo.day   as Lang.Number).format("%02d")
        ]);
        return { "stopId" => "200101024", "dir" => "Luxembourg",
                 "isTram" => false, "arrowRight" => false,
                 "date" => dateMorning, "time" => "064000",
                 "title" => "Bertrange > L.Gare" };
    }
    if (page == 1) {
        return { "stopId" => "200405060", "dir" => "Arlon", "lineFilter" => "RB",
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
    return { "stopId" => "200405051", "dir" => "Bonnevoie",
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

        var lineFilter = slot.get("lineFilter") as Lang.String?;
        var req = {
            "stbLoc" => {"type" => "S", "extId" => slot.get("stopId")},
            "maxJny" => 12,
            "date"   => slot.get("date"),
            "time"   => slot.get("time")
        } as Lang.Dictionary;
        if (lineFilter != null) {
            req.put("jnyFltrL", [{"type" => "LINE", "mode" => "INC", "value" => lineFilter}]);
        }

        var body = {
            "lang"    => "en",
            "svcReqL" => [{"meth" => "StationBoard", "req" => req}],
            "client"  => {"id" => "MMILUX", "type" => "IPH", "name" => "mobiliteit.iOS", "v" => ""},
            "ver"     => "1.56",
            "auth"    => {"type" => "AID", "aid" => "SkC81GuwuzL4e0"}
        };

        Communications.makeWebRequest(
            GATE_URL,
            body,
            { :method      => Communications.HTTP_REQUEST_METHOD_POST,
              :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
              :headers      => {"Content-Type" => "application/json"} },
            method(:onResponse)
        );
    }

    function onResponse(responseCode as Lang.Number, data as Lang.Dictionary?) as Void {
        if (responseCode != 200 || data == null) {
            TramData.updatedAt = "err " + responseCode.toString();
            WatchUi.requestUpdate();
            return;
        }
        var svcResL = (data as Lang.Dictionary).get("svcResL");
        if (svcResL == null || !(svcResL instanceof Lang.Array) || (svcResL as Lang.Array).size() == 0) {
            var e = (data as Lang.Dictionary).get("err");
            TramData.updatedAt = "err:" + (e != null ? e.toString() : "nodata");
            WatchUi.requestUpdate();
            return;
        }

        var slot   = getSlotDef(TramData.currentPage);
        var dirFlt = slot.get("dir") as Lang.String;
        var deps   = parseDeps((svcResL as Lang.Array)[0] as Lang.Dictionary, dirFlt);

        TramData.d1Line = null; TramData.d1Time = null; TramData.d1Dir = null; TramData.d1Delay = null;
        TramData.d2Line = null; TramData.d2Time = null; TramData.d2Dir = null; TramData.d2Delay = null;
        TramData.d3Line = null; TramData.d3Time = null; TramData.d3Dir = null; TramData.d3Delay = null;

        if (deps.size() > 0) {
            var d = deps[0] as Lang.Dictionary;
            TramData.d1Line = d.get("line"); TramData.d1Time  = d.get("time");
            TramData.d1Dir  = d.get("dir");  TramData.d1Delay = d.get("delay");
        }
        if (deps.size() > 1) {
            var d = deps[1] as Lang.Dictionary;
            TramData.d2Line = d.get("line"); TramData.d2Time  = d.get("time");
            TramData.d2Dir  = d.get("dir");  TramData.d2Delay = d.get("delay");
        }
        if (deps.size() > 2) {
            var d = deps[2] as Lang.Dictionary;
            TramData.d3Line = d.get("line"); TramData.d3Time  = d.get("time");
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

    function formatTime(raw as Lang.String) as Lang.String {
        return raw.substring(0, 2) + ":" + raw.substring(2, 4);
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

    function timeDiffMins(actual as Lang.String, scheduled as Lang.String) as Lang.Number {
        var ah = actual.substring(0, 2).toNumber();
        var am = actual.substring(2, 4).toNumber();
        var sh = scheduled.substring(0, 2).toNumber();
        var sm = scheduled.substring(2, 4).toNumber();
        var diff = (ah * 60 + am) - (sh * 60 + sm);
        if (diff < -60) { diff += 1440; }
        if (diff < 0)   { diff = 0; }
        return diff;
    }


    function parseDeps(svcRes as Lang.Dictionary, dirFilter as Lang.String) as Lang.Array {
        var result = [] as Lang.Array;
        if (svcRes == null) { return result; }
        var inner = svcRes.get("res");
        if (inner == null) { return result; }
        var jnyL = (inner as Lang.Dictionary).get("jnyL");
        if (jnyL == null || !(jnyL instanceof Lang.Array)) { return result; }
        var common = (inner as Lang.Dictionary).get("common");
        var prodL  = (common != null) ? (common as Lang.Dictionary).get("prodL") : null;
        if (prodL == null) { prodL = []; }

        for (var i = 0; i < (jnyL as Lang.Array).size(); i++) {
            var jny  = (jnyL as Lang.Array)[i] as Lang.Dictionary;
            var stop = jny.get("stbStop") as Lang.Dictionary;
            if (stop == null) { continue; }
            var dir = jny.get("dirTxt");
            if (dir == null) { dir = ""; }
            if (!dirFilter.equals("All") && (dir as Lang.String).find(dirFilter) == null) { continue; }

            var rawActual = stop.get("dTimeR");
            if (rawActual == null) { rawActual = stop.get("dTimeS"); }
            if (rawActual == null) { continue; }
            var rawSched = stop.get("dTimeS");

            var delay = 0;
            if (rawSched != null) {
                delay = timeDiffMins(rawActual as Lang.String, rawSched as Lang.String);
            }

            var lineName = "?";
            var prodX = jny.get("prodX");
            if (prodX != null && (prodL as Lang.Array).size() > 0 &&
                (prodX as Lang.Number) < (prodL as Lang.Array).size()) {
                var pName = ((prodL as Lang.Array)[prodX as Lang.Number] as Lang.Dictionary).get("name");
                if (pName != null) { lineName = shortName(pName as Lang.String); }
            }

            result.add({
                "line"  => lineName,
                "time"  => formatTime(rawActual as Lang.String),
                "dir"   => dir,
                "delay" => delay
            });
            if (result.size() >= 3) { break; }
        }
        return result;
    }
}

function getApp() as tramfaceApp {
    return Application.getApp() as tramfaceApp;
}
