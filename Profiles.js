.pragma library

// Profiles: saved states across one or more devices. Pure helpers only.
//
// Profile shape:
//   { id, name, devices: { <deviceId>: DeviceState } }
// DeviceState:
//   { on: false }
//   { on: true, brightness, mode: "effect", effect }
//   { on: true, brightness, mode: "color", hue, sat }
//   { on: true, brightness, mode: "white", ct }
// Devices not listed in a profile are left untouched when it is applied.

function slug(name) {
  var s = String(name || "").toLowerCase()
    .replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  return s || "profil"
}

// Captures one device from parsed info (NanoleafApi.parseInfo) and its mode.
function captureDevice(info, mode) {
  if (!info) return null
  if (!info.on) return { on: false }
  var s = { on: true, brightness: info.brightness, mode: mode }
  if (mode === "effect") s.effect = info.effect
  else if (mode === "white") s.ct = info.ct
  else { s.hue = info.hue; s.sat = info.sat }
  return s
}

function normalizeDeviceState(s) {
  if (!s || typeof s !== "object") return null
  if (s.on !== true) return { on: false }
  var b = Number(s.brightness)
  var out = { on: true, brightness: isFinite(b) ? Math.max(1, Math.min(100, Math.round(b))) : 100 }
  if (s.mode === "effect" && typeof s.effect === "string" && s.effect !== "") {
    out.mode = "effect"; out.effect = s.effect
  } else if (s.mode === "white" && isFinite(Number(s.ct))) {
    out.mode = "white"; out.ct = Math.round(Number(s.ct))
  } else if (s.mode === "color" && isFinite(Number(s.hue)) && isFinite(Number(s.sat))) {
    out.mode = "color"; out.hue = Math.round(Number(s.hue)); out.sat = Math.round(Number(s.sat))
  }
  return out
}

function normalize(p) {
  if (!p || typeof p !== "object") return null
  if (typeof p.name !== "string" || p.name.trim() === "") return null
  var devices = {}
  var count = 0
  var src = p.devices && typeof p.devices === "object" ? p.devices : {}
  for (var id in src) {
    if (!Object.prototype.hasOwnProperty.call(src, id)) continue
    var s = normalizeDeviceState(src[id])
    if (s) { devices[id] = s; count++ }
  }
  if (count === 0) return null
  return { id: typeof p.id === "string" && p.id !== "" ? p.id : slug(p.name), name: p.name.trim(), devices: devices }
}

function normalizeList(list) {
  if (!Array.isArray(list)) return []
  var seen = {}
  var out = []
  for (var i = 0; i < list.length; i++) {
    var p = normalize(list[i])
    if (p && !seen[p.id]) { seen[p.id] = true; out.push(p) }
  }
  return out
}

// Same name (case-insensitive) replaces the existing profile in place.
function upsert(list, profile) {
  var p = normalize(profile)
  if (!p) return list
  var next = list.slice()
  for (var i = 0; i < next.length; i++) {
    if (next[i].name.toLowerCase() === p.name.toLowerCase()) {
      p.id = next[i].id
      next[i] = p
      return next
    }
  }
  var id = p.id, n = 2
  var taken = function(x) { return next.some(function(q) { return q.id === x }) }
  while (taken(id)) id = p.id + "-" + (n++)
  p.id = id
  next.push(p)
  return next
}

function remove(list, id) {
  return list.filter(function(p) { return p.id !== id })
}

function findByName(list, name) {
  var n = String(name || "").trim().toLowerCase()
  for (var i = 0; i < list.length; i++) if (list[i].name.toLowerCase() === n) return list[i]
  return null
}

// True when every device in the profile currently looks like the saved state.
// `current(id)` returns { info, mode } or null when the device is unreachable.
function matches(profile, current) {
  for (var id in profile.devices) {
    if (!Object.prototype.hasOwnProperty.call(profile.devices, id)) continue
    var want = profile.devices[id]
    var have = current(id)
    if (!have || !have.info) return false
    var info = have.info
    if (!want.on) { if (info.on) return false; continue }
    if (!info.on) return false
    if (Math.abs(info.brightness - want.brightness) > 2) return false
    if (!want.mode) continue
    if (have.mode !== want.mode) return false
    if (want.mode === "effect" && info.effect !== want.effect) return false
    if (want.mode === "white" && Math.abs(info.ct - want.ct) > 100) return false
    if (want.mode === "color" && (Math.abs(info.hue - want.hue) > 3 || Math.abs(info.sat - want.sat) > 3)) return false
  }
  return true
}
