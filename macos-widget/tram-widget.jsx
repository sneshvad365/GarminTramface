import { React } from "uebersicht";

// Internal setInterval handles refresh — no Übersicht-driven re-mount flash
export const refreshFrequency = false;

// Positioned at bottom-centre of screen
export const className = `
  position: fixed;
  bottom: 20px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  gap: 10px;
`;

// ── API config ────────────────────────────────────────────────────────────────

const API_KEY  = "041ad985-318b-44c4-a6d0-787b115a5ff8";
const BASE_URL = "https://cdt.hafas.de/opendata/apiserver/departureBoard";

// Same 5 routes as the Garmin widget (getSlotDef pages 0–4)
const ROUTES = [
  { id: 0, stopId: "200101024", dir: "Luxembourg",   isTram: false, title: "Bertrange > L.Gare",  fixedTime: "06:40" },
  { id: 1, stopId: "200405060", destId: "200101024", isTram: false, title: "L.Gare > Bertrange"  },
  { id: 2, stopId: "200405051", dir: "Gasperich",    isTram: true,  title: "Pl.Metz > Scillas"   },
  { id: 3, stopId: "200304021", dir: "Findel",       isTram: true,  title: "Scillas > Pl.Metz"   },
  { id: 4, stopId: "200405051",                      isTram: true,  title: "Pl.Metz > Lux Gare"  },
];

// ── Helpers ───────────────────────────────────────────────────────────────────

function pad2(n) { return String(n).padStart(2, "0"); }

function dateStr(d) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function timeStr(d) {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

// Mirror of Garmin timeDiffMins: handles midnight wrap, clamps negative to 0
function timeDiffMins(actualHHMM, schedHHMM) {
  const ah = parseInt(actualHHMM.slice(0, 2)), am = parseInt(actualHHMM.slice(2, 4));
  const sh = parseInt(schedHHMM.slice(0, 2)), sm = parseInt(schedHHMM.slice(2, 4));
  let diff = (ah * 60 + am) - (sh * 60 + sm);
  if (diff < -60) diff += 1440;
  return Math.max(0, diff);
}

// Mirror of Garmin shortName: "T 1" → "T1", "RE 2" → "RE2", "Bus 295" → "Bus"
function shortName(name) {
  if (!name) return "?";
  const idx = name.indexOf(" ");
  if (idx <= 0) return name.length > 5 ? name.slice(0, 5) : name;
  const prefix = name.slice(0, idx);
  const rest   = name.slice(idx + 1);
  if (prefix.length === 1 && !isNaN(Number(rest))) return prefix + rest;
  return prefix;
}

// Mirror of Garmin parseDeps: direction text filter + extract time/rtTime/delay/lineName
function parseDeps(depArr, route) {
  const result = [];
  for (let i = 0; i < depArr.length && result.length < 3; i++) {
    const dep       = depArr[i];
    const direction = dep.direction || "";

    if (route.dir && !direction.includes(route.dir)) continue;

    const sched = dep.time;
    if (!sched) continue;

    const schedHHMM  = sched.slice(0, 2) + sched.slice(3, 5);
    let   displayTime = sched.slice(0, 5);
    let   delay       = 0;

    const rt = dep.rtTime;
    if (rt && rt.length >= 5) {
      const rtHHMM = rt.slice(0, 2) + rt.slice(3, 5);
      delay       = timeDiffMins(rtHHMM, schedHHMM);
      displayTime = rt.slice(0, 5);
    }

    const lineName = dep.ProductAtStop?.name ? shortName(dep.ProductAtStop.name) : "?";
    result.push({ line: lineName, time: displayTime, dir: direction, delay });
  }
  return result;
}

// Mirror of Garmin fetchDepartures logic for a single route
async function fetchRoute(route) {
  const now = new Date();

  // Route 0: fixed 06:40; if it's evening (≥20h) show tomorrow's board
  let date = dateStr(now);
  if (route.fixedTime && now.getHours() >= 20) {
    date = dateStr(new Date(now.getTime() + 86400000));
  }

  const params = new URLSearchParams({
    accessId:    API_KEY,
    extId:       route.stopId,
    format:      "json",
    maxJourneys: route.destId ? 5 : 10,
    duration:    route.destId ? 120 : 60,
    date,
    time:        (route.fixedTime ?? timeStr(now)) + ":00",
  });

  if (route.destId) params.set("direction", route.destId);

  const res = await fetch(`${BASE_URL}?${params}`);
  if (!res.ok) throw new Error(`err ${res.status}`);
  const data = await res.json();
  return parseDeps(data.Departure ?? [], route);
}

// ── Design tokens ─────────────────────────────────────────────────────────────

const C = {
  tram:    "#1D9E75",
  train:   "#378ADD",
  amber:   "#F59E0B",
  red:     "#EF4444",
  bg:      "#0d0d11",
  surface: "#111116",
  border:  "#1e1e28",
  text:    "#e8e8f0",
  muted:   "#55556a",
};

const CARD_W = 205;

// ── Sub-components ────────────────────────────────────────────────────────────

function LineBadge({ line, isTram }) {
  return (
    <span style={{
      display:      "inline-block",
      background:   isTram ? C.tram : C.train,
      color:        "#000",
      fontFamily:   "'DM Mono', 'Courier New', monospace",
      fontSize:     "11px",
      fontWeight:   "700",
      padding:      "1px 5px",
      borderRadius: "4px",
      minWidth:     "26px",
      textAlign:    "center",
      flexShrink:   0,
    }}>{line}</span>
  );
}

function DepRow({ dep, isTram }) {
  const delayed = dep.delay > 0;
  return (
    <div style={{ display: "flex", alignItems: "center", gap: "5px", marginBottom: "5px", minWidth: 0 }}>
      <LineBadge line={dep.line} isTram={isTram} />
      <span style={{
        fontFamily: "'DM Mono', 'Courier New', monospace",
        fontSize:   "14px",
        fontWeight: "500",
        color:      delayed ? C.amber : C.text,
        flexShrink: 0,
      }}>{dep.time}</span>
      {delayed && (
        <span style={{
          fontFamily: "'DM Mono', monospace",
          fontSize:   "10px",
          color:      C.red,
          flexShrink: 0,
        }}>+{dep.delay}m</span>
      )}
      <span style={{
        fontFamily:   "'-apple-system', 'DM Sans', sans-serif",
        fontSize:     "10px",
        color:        C.muted,
        overflow:     "hidden",
        whiteSpace:   "nowrap",
        textOverflow: "ellipsis",
        minWidth:     0,
      }}>{dep.dir}</span>
    </div>
  );
}

function RouteCard({ route, deps, loading, error, updatedAt }) {
  const accent = route.isTram ? C.tram : C.train;
  return (
    <div style={{
      background:    C.surface,
      border:        `1px solid ${C.border}`,
      borderRadius:  "12px",
      padding:       "11px 12px 9px",
      width:         `${CARD_W}px`,
      boxSizing:     "border-box",
      boxShadow:     "0 4px 24px rgba(0,0,0,0.6)",
    }}>
      {/* Route title */}
      <div style={{
        fontFamily:   "-apple-system, 'DM Sans', sans-serif",
        fontSize:     "11px",
        fontWeight:   "600",
        color:        accent,
        marginBottom: "7px",
        whiteSpace:   "nowrap",
        overflow:     "hidden",
        textOverflow: "ellipsis",
        letterSpacing: "0.2px",
      }}>{route.title}</div>

      {/* Divider */}
      <div style={{ height: "1px", background: C.border, marginBottom: "7px" }} />

      {/* Departure rows */}
      {loading && (
        <div style={{ fontFamily: "sans-serif", fontSize: "11px", color: C.muted, paddingBottom: "4px" }}>
          fetching…
        </div>
      )}
      {!loading && error && (
        <div style={{ fontFamily: "'DM Mono', monospace", fontSize: "11px", color: C.red, paddingBottom: "4px" }}>
          {error}
        </div>
      )}
      {!loading && !error && deps.length === 0 && (
        <div style={{ fontFamily: "sans-serif", fontSize: "11px", color: C.muted, paddingBottom: "4px" }}>
          no departures
        </div>
      )}
      {!loading && !error && deps.map((dep, i) => (
        <DepRow key={i} dep={dep} isTram={route.isTram} />
      ))}

      {/* Updated timestamp */}
      <div style={{ height: "1px", background: C.border, margin: "6px 0 5px" }} />
      <div style={{
        fontFamily: "'DM Mono', 'Courier New', monospace",
        fontSize:   "9px",
        color:      C.muted,
      }}>{updatedAt ? `upd ${updatedAt}` : "—"}</div>
    </div>
  );
}

// ── Root widget ───────────────────────────────────────────────────────────────

const initialCards = ROUTES.map(r => ({ route: r, deps: [], loading: true, error: null, updatedAt: null }));

export default function Widget() {
  const [cards, setCards] = React.useState(initialCards);

  // Load Google Fonts once into the document head
  React.useEffect(() => {
    if (!document.getElementById("tram-gf")) {
      const link  = document.createElement("link");
      link.id     = "tram-gf";
      link.rel    = "stylesheet";
      link.href   = "https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600&family=DM+Mono:wght@400;500&display=swap";
      document.head.appendChild(link);
    }
  }, []);

  // Fetch all 5 routes in parallel, update each card independently
  const refresh = React.useCallback(() => {
    setCards(ROUTES.map(r => ({ route: r, deps: [], loading: true, error: null, updatedAt: null })));

    ROUTES.forEach((route, i) => {
      fetchRoute(route)
        .then(deps => {
          const now = new Date();
          const upd = `${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
          setCards(prev => {
            const next = [...prev];
            next[i] = { route, deps, loading: false, error: null, updatedAt: upd };
            return next;
          });
        })
        .catch(err => {
          setCards(prev => {
            const next = [...prev];
            next[i] = { ...prev[i], loading: false, error: err.message };
            return next;
          });
        });
    });
  }, []);

  // Fetch on mount, then every 60 seconds
  React.useEffect(() => {
    refresh();
    const timer = setInterval(refresh, 60_000);
    return () => clearInterval(timer);
  }, [refresh]);

  return (
    <div style={{ display: "flex", gap: "10px" }}>
      {cards.map((card, i) => <RouteCard key={i} {...card} />)}
    </div>
  );
}
