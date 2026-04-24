command: "date +%H:%M"
refreshFrequency: 600000

style: """
  position: fixed
  top: 20px
  right: 20px
"""

render: (output) -> """
  <div style="display:flex;flex-direction:column;gap:8px;font-family:system-ui,sans-serif">
    <div style="display:flex;gap:10px">
      #{("""
        <div id="card-#{i}" style="background:#111116;border:1px solid #1e1e28;border-radius:12px;padding:11px 12px 9px;width:200px;box-shadow:0 4px 24px rgba(0,0,0,0.5);color:#e8e8f0;font-size:11px;box-sizing:border-box">
          <div style="color:#9090a8">fetching...</div>
        </div>
      """ for i in [0..4]).join('')}
    </div>
    <div style="display:flex;justify-content:flex-end">
      <button id="tram-refresh" style="background:#1e1e28;border:1px solid #2a2a3a;color:#888;font-size:11px;font-family:system-ui,sans-serif;padding:4px 12px;border-radius:6px;cursor:pointer">&#8635; Refresh</button>
    </div>
  </div>
"""

afterRender: (domEl) ->

  API_KEY  = "041ad985-318b-44c4-a6d0-787b115a5ff8"
  BASE_URL = "https://cdt.hafas.de/opendata/apiserver/departureBoard"

  ROUTES = [
    {id: 0, stopId: "200101024", dir: "Luxembourg",   isTram: false, title: "Bertrange > L.Gare",  fixedTime: "06:40"}
    {id: 1, stopId: "200405060", destId: "200101024", isTram: false, title: "L.Gare > Bertrange"}
    {id: 2, stopId: "200405051", dir: "Gasperich",    isTram: true,  title: "Pl.Metz > Scillas"}
    {id: 3, stopId: "200304021", dir: "Findel",       isTram: true,  title: "Scillas > Pl.Metz"}
    {id: 4, stopId: "200405051", dirs: ["Gasperich", "Bonnevoie"], isTram: true, title: "Pl.Metz > Lux Gare"}
  ]

  pad2 = (n) -> String(n).padStart(2, "0")

  dateStr = (d) ->
    d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())

  timeStr = (d) ->
    pad2(d.getHours()) + ":" + pad2(d.getMinutes())

  timeDiff = (a, s) ->
    diff = (parseInt(a[0..1]) * 60 + parseInt(a[2..3])) - (parseInt(s[0..1]) * 60 + parseInt(s[2..3]))
    diff += 1440 if diff < -60
    Math.max(0, diff)

  shortName = (name) ->
    return "?" unless name
    idx = name.indexOf(" ")
    return (if name.length > 5 then name[0...5] else name) if idx <= 0
    prefix = name[0...idx]
    rest   = name[idx + 1..]
    return prefix + rest if prefix.length is 1 and not isNaN(Number(rest))
    prefix

  parseDeps = (depArr, route) ->
    result = []
    for dep in depArr
      break if result.length >= 3
      dir = dep.direction or ""
      if route.dirs
        continue unless route.dirs.some((d) -> dir.indexOf(d) isnt -1)
      else
        continue if route.dir and dir.indexOf(route.dir) is -1
      sched = dep.time
      continue unless sched
      schedHHMM = sched[0..1] + sched[3..4]
      displayTime = sched[0..4]
      delay = 0
      rt = dep.rtTime
      if rt and rt.length >= 5
        rtHHMM = rt[0..1] + rt[3..4]
        delay = timeDiff(rtHHMM, schedHHMM)
        displayTime = rt[0..4]
      prod = dep.ProductAtStop
      line = if prod and prod.name then shortName(prod.name) else "?"
      result.push {line, time: displayTime, dir, delay}
    result

  renderCard = (el, route, deps, updatedAt) ->
    accent = if route.isTram then "#1D9E75" else "#378ADD"

    rows = (for dep in deps
      delayed    = dep.delay > 0
      timeColor  = if delayed then "#F59E0B" else "#e8e8f0"
      delayBadge = if delayed then "<span style='color:#EF4444;font-size:10px;margin-left:2px'>+#{dep.delay}m</span>" else ""
      dirText    = dep.dir.replace(/Luxembourg/g, "Lux")
      dirText    = if dirText.length > 20 then dirText[0...20] + "\u2026" else dirText
      "<div style='display:flex;align-items:center;gap:5px;margin-bottom:5px'><span style='background:#{accent};color:#000;font-family:monospace;font-size:11px;font-weight:700;padding:1px 5px;border-radius:4px;min-width:26px;text-align:center;flex-shrink:0'>#{dep.line}</span><span style='font-family:monospace;font-size:14px;color:#{timeColor};flex-shrink:0'>#{dep.time}</span>#{delayBadge}<span style='font-size:10px;color:#9090a8;overflow:hidden;white-space:nowrap;text-overflow:ellipsis'>#{dirText}</span></div>"
    ).join("")

    noData = if deps.length is 0 then "<div style='color:#9090a8;font-size:11px'>no departures</div>" else ""
    upd    = if updatedAt then "<div style='color:#9090a8;font-family:monospace;font-size:9px;margin-top:3px'>upd #{updatedAt}</div>" else ""

    el.innerHTML = "<div style='font-size:11px;font-weight:600;color:#{accent};margin-bottom:6px'>#{route.title}</div><div style='height:1px;background:#1e1e28;margin-bottom:7px'></div>#{rows}#{noData}<div style='height:1px;background:#1e1e28;margin:5px 0 4px'></div>#{upd}"

  fetchRoute = (route, idx) ->
    now  = new Date()
    date = dateStr(now)
    date = dateStr(new Date(now.getTime() + 86400000)) if route.fixedTime and now.getHours() >= 20
    t    = (if route.fixedTime then route.fixedTime else timeStr(now)) + ":00"

    url  = BASE_URL + "?accessId=#{API_KEY}&extId=#{route.stopId}&format=json&maxJourneys=#{if route.destId then 5 else 10}&duration=#{if route.destId then 120 else 60}&date=#{date}&time=#{encodeURIComponent(t)}"
    url += "&direction=#{route.destId}" if route.destId

    el = domEl.querySelector("#card-#{idx}")

    fetch(url)
      .then (r)    -> r.json()
      .then (data) ->
        now2 = new Date()
        upd  = pad2(now2.getHours()) + ":" + pad2(now2.getMinutes())
        deps = parseDeps(data.Departure or [], route)
        renderCard(el, route, deps, upd)
      .catch (err) ->
        el.innerHTML = "<div style='color:#EF4444;font-size:11px'>#{err.message}</div>" if el

  fetchAll = ->
    btn = domEl.querySelector("#tram-refresh")
    btn.textContent = "refreshing..." if btn
    ROUTES.forEach (route, i) -> fetchRoute(route, i)
    setTimeout (-> btn.innerHTML = "&#8635; Refresh" if btn), 2000

  # Wire up the refresh button
  btn = domEl.querySelector("#tram-refresh")
  btn.addEventListener("click", fetchAll) if btn

  # Initial fetch
  fetchAll()
