.pragma library
.import "Profiles.js" as Profiles

// Persisted configuration: paired devices (with tokens) and profiles.
// Lives in ~/.config/omarchy/nanoleaf/config.json inside a 0700 directory.

var VERSION = 1

function empty() {
  return { version: VERSION, devices: [], profiles: [] }
}

function normalizeDevice(d) {
  if (!d || typeof d !== "object") return null
  if (typeof d.id !== "string" || d.id === "") return null
  if (typeof d.host !== "string" || d.host === "") return null
  if (typeof d.token !== "string" || d.token === "") return null
  return {
    id: d.id,
    name: typeof d.name === "string" && d.name !== "" ? d.name : d.id,
    host: d.host,
    port: Number(d.port) || 16021,
    token: d.token,
    model: typeof d.model === "string" ? d.model : ""
  }
}

function parse(text) {
  var raw
  try { raw = JSON.parse(text) } catch (e) { return empty() }
  if (!raw || typeof raw !== "object") return empty()
  var out = empty()
  if (Array.isArray(raw.devices)) {
    var seen = {}
    for (var i = 0; i < raw.devices.length; i++) {
      var d = normalizeDevice(raw.devices[i])
      if (d && !seen[d.id]) { seen[d.id] = true; out.devices.push(d) }
    }
  }
  out.profiles = Profiles.normalizeList(raw.profiles)
  return out
}

function serialize(config) {
  return JSON.stringify(config, null, 2) + "\n"
}

function upsertDevice(config, device) {
  var next = { version: VERSION, devices: config.devices.slice(), profiles: config.profiles }
  var d = normalizeDevice(device)
  if (!d) return next
  for (var i = 0; i < next.devices.length; i++) {
    if (next.devices[i].id === d.id) { next.devices[i] = d; return next }
  }
  next.devices.push(d)
  return next
}

function removeDevice(config, id) {
  return {
    version: VERSION,
    devices: config.devices.filter(function(d) { return d.id !== id }),
    profiles: config.profiles
  }
}

function setProfiles(config, profiles) {
  return { version: VERSION, devices: config.devices, profiles: profiles }
}
