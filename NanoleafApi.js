.pragma library

// Thin layer over the Nanoleaf Open API (local REST, port 16021).
// Pure helpers plus one request function; no QML state lives here.

var DEFAULT_PORT = 16021
var TIMEOUT_MS = 4000

function baseUrl(device) {
  return "http://" + device.host + ":" + (device.port || DEFAULT_PORT) + "/api/v1"
}

function authUrl(device, path) {
  return baseUrl(device) + "/" + encodeURIComponent(device.token) + (path || "/")
}

// callback(ok, status, body) — body is parsed JSON or null.
function request(method, url, payload, callback) {
  var xhr = new XMLHttpRequest()
  var done = false
  var finish = function(ok, status, body) {
    if (done) return
    done = true
    if (callback) callback(ok, status, body)
  }
  xhr.onreadystatechange = function() {
    if (xhr.readyState !== XMLHttpRequest.DONE) return
    var body = null
    if (xhr.responseText) {
      try { body = JSON.parse(xhr.responseText) } catch (e) { body = null }
    }
    finish(xhr.status >= 200 && xhr.status < 300, xhr.status, body)
  }
  xhr.timeout = TIMEOUT_MS
  xhr.ontimeout = function() { finish(false, 0, null) }
  xhr.open(method, url)
  if (payload !== undefined && payload !== null) {
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.send(JSON.stringify(payload))
  } else {
    xhr.send()
  }
}

// ---- Commands -------------------------------------------------------------

function pair(device, callback) {
  // Only succeeds while the controller is in pairing mode
  // (power button held for 5–7 s, window lasts about 30 s).
  request("POST", baseUrl(device) + "/new", null, function(ok, status, body) {
    var token = ok && body && typeof body.auth_token === "string" ? body.auth_token : ""
    callback(token !== "", status, token)
  })
}

function fetchInfo(device, callback) {
  request("GET", authUrl(device, "/"), null, callback)
}

function setState(device, state, callback) {
  request("PUT", authUrl(device, "/state"), state, callback)
}

function setOn(device, on, callback) {
  setState(device, { on: { value: !!on } }, callback)
}

function setBrightness(device, value, callback) {
  setState(device, { brightness: { value: clamp(Math.round(value), 0, 100), duration: 0 } }, callback)
}

function selectEffect(device, name, callback) {
  request("PUT", authUrl(device, "/effects"), { select: String(name) }, callback)
}

// hue 0–360, sat 0–100. Ends any running effect.
function setColor(device, hue, sat, callback) {
  setState(device, {
    hue: { value: clamp(Math.round(hue), 0, 360) },
    sat: { value: clamp(Math.round(sat), 0, 100) }
  }, callback)
}

// Color temperature in Kelvin. Ends any running effect.
function setWhite(device, ct, callback) {
  setState(device, { ct: { value: Math.round(ct) } }, callback)
}

function identify(device, callback) {
  request("PUT", authUrl(device, "/identify"), {}, callback)
}

// ---- Parsing --------------------------------------------------------------

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}

// Reduces the full info payload to the fields the UI uses.
function parseInfo(body) {
  if (!body || typeof body !== "object") return null
  var s = body.state || {}
  var fx = body.effects || {}
  var val = function(o, fallback) {
    return o && typeof o === "object" && o.value !== undefined ? o.value : fallback
  }
  var bound = function(o, key, fallback) {
    return o && typeof o === "object" && typeof o[key] === "number" ? o[key] : fallback
  }
  return {
    name: typeof body.name === "string" ? body.name : "",
    model: typeof body.model === "string" ? body.model : "",
    serialNo: typeof body.serialNo === "string" ? body.serialNo : "",
    on: val(s.on, false) === true,
    brightness: Number(val(s.brightness, 0)) || 0,
    hue: Number(val(s.hue, 0)) || 0,
    sat: Number(val(s.sat, 0)) || 0,
    ct: Number(val(s.ct, 0)) || 0,
    ctMin: bound(s.ct, "min", 1200),
    ctMax: bound(s.ct, "max", 6500),
    colorMode: typeof s.colorMode === "string" ? s.colorMode : "",
    effect: typeof fx.select === "string" ? fx.select : "",
    effects: Array.isArray(fx.effectsList) ? fx.effectsList.filter(function(e) { return typeof e === "string" }) : []
  }
}

// "effect" | "color" | "white". Nanoleaf reports colorMode "effect" while an
// effect runs, and "hs"/"ct" (with effect "*Solid*") once a plain color or
// white temperature is set.
function modeOf(info) {
  if (!info) return "effect"
  if (info.colorMode === "ct") return "white"
  if (info.colorMode === "hs") return "color"
  if (info.effect === "*Solid*" || info.effect === "") return "color"
  return "effect"
}

// Effects the user can pick; hides internal pseudo-effects like "*Solid*".
function userEffects(info) {
  if (!info) return []
  return info.effects.filter(function(e) { return e.charAt(0) !== "*" })
}

// Parses `avahi-browse -rpt _nanoleafapi._tcp` output into
// [{ id, name, host, port, model }]. IPv4 only; duplicates collapse by id.
function parseDiscovery(text) {
  var seen = {}
  var result = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split(";")
    if (f.length < 10 || f[0] !== "=" || f[2] !== "IPv4") continue
    var txt = f.slice(9).join(";")
    var idMatch = /"id=([^"]+)"/.exec(txt)
    var mdMatch = /"md=([^"]+)"/.exec(txt)
    var id = idMatch ? idMatch[1] : f[6]
    if (seen[id]) continue
    seen[id] = true
    result.push({
      id: id,
      name: unescapeAvahi(f[3]),
      host: f[7],
      port: parseInt(f[8], 10) || DEFAULT_PORT,
      model: mdMatch ? mdMatch[1] : ""
    })
  }
  return result
}

// avahi-browse -p escapes non-printables as \DDD (decimal).
function unescapeAvahi(s) {
  return String(s || "").replace(/\\(\d{3})/g, function(_, d) { return String.fromCharCode(parseInt(d, 10)) })
}
