module TramData {
    var d1Line = null; var d1Time = null; var d1Dir = null; var d1Delay = null;
    var d2Line = null; var d2Time = null; var d2Dir = null; var d2Delay = null;
    var d3Line = null; var d3Time = null; var d3Dir = null; var d3Delay = null;
    var isTram           = false;
    var arrowRight       = true;
    var pageTitle        = "";
    var currentPage      = 0;
    var defaultPage      = 0;   // page set automatically on open
    var vibrateOnDelays  = false; // true = still waiting to vibrate this session
    var updatedAt        = null;
    var hasData          = false;
}
