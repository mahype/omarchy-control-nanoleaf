import QtQuick
import Quickshell
import Quickshell.Io
import "NanoleafApi.js" as Api
import "ConfigStore.js" as ConfigStore
import "Profiles.js" as Profiles
import "Pending.js" as Pending

// Owner of all Nanoleaf state.
//
// A `service` is mounted once per session, a `bar-widget` once per monitor, so
// config, device state and all HTTP traffic live here. The panel reaches it
// through `bar.shell.serviceFor("io.github.mahype.omarchy-control-nanoleaf")` and only
// calls the action functions below.
QtObject {
  id: root

  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy-control-nanoleaf"
  readonly property string configPath: configDir + "/config.json"

  property var config: ConfigStore.empty()
  property bool configLoaded: false

  // Paired devices from config (tokens included — never render or log them).
  readonly property var devices: config.devices

  // id -> { reachable, info } ; bump `revision` on every change so bindings
  // that read nested fields re-evaluate.
  property var states: ({})
  property int revision: 0

  // Optimistic values of commands in flight; see Pending.js. Not bound by
  // the UI, only merged into `states`.
  property var pending: ({})

  // Discovery results that are not paired yet: [{ id, name, host, port, model }]
  property var discovered: []
  property bool discovering: false

  // Pairing: id of the device being paired, and the last error as a code
  // ("not-pairing" | "unreachable" | ""). The panel turns codes into text.
  property string pairingId: ""
  property string pairingError: ""

  readonly property var profiles: config.profiles
  // Id of the profile the devices currently match, or "".
  readonly property string activeProfileId: {
    revision
    for (var i = 0; i < profiles.length; i++) {
      if (Profiles.matches(profiles[i], _currentFor)) return profiles[i].id
    }
    return ""
  }
  // Scenes a profile referred to that no longer exist on the device (e.g.
  // deleted in the Nanoleaf app), from the last applyProfile().
  property var missingScenes: []

  readonly property bool hasDevices: devices.length > 0
  readonly property bool anyOn: {
    revision
    for (var i = 0; i < devices.length; i++) {
      var s = states[devices[i].id]
      if (s && s.reachable && s.info && s.info.on) return true
    }
    return false
  }
  readonly property int averageBrightness: {
    revision
    var sum = 0, n = 0
    for (var i = 0; i < devices.length; i++) {
      var s = states[devices[i].id]
      if (s && s.reachable && s.info && s.info.on) { sum += s.info.brightness; n++ }
    }
    return n > 0 ? Math.round(sum / n) : 0
  }

  // ---- Queries ------------------------------------------------------------

  function stateFor(id) {
    revision
    return states[id] || { reachable: false, info: null }
  }

  function deviceById(id) {
    for (var i = 0; i < devices.length; i++) if (devices[i].id === id) return devices[i]
    return null
  }

  // ---- Actions ------------------------------------------------------------

  function refresh() {
    for (var i = 0; i < devices.length; i++) refreshDevice(devices[i].id)
  }

  function refreshDevice(id) {
    var d = deviceById(id)
    if (!d) return
    Api.fetchInfo(d, function(ok, status, body) {
      var now = Date.now()
      root.pending = Pending.prune(root.pending, now)
      var info = Pending.apply(root.pending, id, ok ? Api.parseInfo(body) : null, now)
      root._putState(id, { reachable: !!info, info: info })
    })
  }

  function setOn(id, on) {
    var d = deviceById(id)
    if (!d) return
    _patchInfo(id, { on: !!on })
    Api.setOn(d, on, _done(id))
  }

  function toggle(id) {
    var s = stateFor(id)
    setOn(id, !(s.info && s.info.on))
  }

  function setBrightness(id, value) {
    var d = deviceById(id)
    if (!d) return
    var v = Api.clamp(Math.round(value), 0, 100)
    _patchInfo(id, { brightness: v, on: v > 0 })
    Api.setBrightness(d, v, _done(id))
  }

  // Effect, color and white are mutually exclusive on the device; each call
  // switches the device into that mode. Setting any of them also turns it on.
  function selectEffect(id, name) {
    var d = deviceById(id)
    if (!d) return
    _patchInfo(id, { effect: name, colorMode: "effect", on: true })
    Api.selectEffect(d, name, _done(id))
  }

  function setColor(id, hue, sat) {
    var d = deviceById(id)
    if (!d) return
    _patchInfo(id, { hue: hue, sat: sat, colorMode: "hs", effect: "*Solid*", on: true })
    Api.setColor(d, hue, sat, _done(id))
  }

  function setWhite(id, ct) {
    var d = deviceById(id)
    if (!d) return
    _patchInfo(id, { ct: ct, colorMode: "ct", effect: "*Solid*", on: true })
    Api.setWhite(d, ct, _done(id))
  }

  function modeFor(id) {
    return Api.modeOf(stateFor(id).info)
  }

  function effectsFor(id) {
    return Api.userEffects(stateFor(id).info)
  }

  // ---- Profiles -----------------------------------------------------------

  function profileByName(name) {
    return Profiles.findByName(profiles, name)
  }

  // Saves the current state of the given devices (default: all) under
  // `name`. Unreachable devices are skipped. An existing profile with the
  // same name is overwritten.
  function saveProfile(name, deviceIds) {
    var clean = String(name || "").trim()
    if (clean === "") return false
    var ids = Array.isArray(deviceIds) ? deviceIds : devices.map(function(d) { return d.id })
    var devs = {}
    var count = 0
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      var s = states[id]
      if (!s || !s.reachable || !s.info) continue
      var captured = Profiles.captureDevice(s.info, Api.modeOf(s.info))
      if (captured) { devs[id] = captured; count++ }
    }
    if (count === 0) return false
    _saveConfig(ConfigStore.setProfiles(config, Profiles.upsert(profiles, { name: clean, devices: devs })))
    return true
  }

  function deleteProfile(id) {
    _saveConfig(ConfigStore.setProfiles(config, Profiles.remove(profiles, id)))
  }

  function applyProfile(id) {
    var p = null
    for (var i = 0; i < profiles.length; i++) if (profiles[i].id === id) p = profiles[i]
    if (!p) return
    missingScenes = []
    var missing = []
    for (var devId in p.devices) {
      if (!Object.prototype.hasOwnProperty.call(p.devices, devId)) continue
      var d = deviceById(devId)
      if (!d) continue
      var want = p.devices[devId]
      if (!want.on) { setOn(devId, false); continue }
      if (want.mode === "effect") {
        var known = effectsFor(devId)
        if (known.length > 0 && known.indexOf(want.effect) < 0) {
          missing.push(want.effect)
          setBrightness(devId, want.brightness)
          continue
        }
        _applyEffectState(d, devId, want)
      } else {
        // Color and white go out as one state request together with on and
        // brightness.
        var body = { on: { value: true }, brightness: { value: want.brightness, duration: 0 } }
        var patch = { on: true, brightness: want.brightness }
        if (want.mode === "white") {
          body.ct = { value: want.ct }
          Object.assign(patch, { ct: want.ct, colorMode: "ct", effect: "*Solid*" })
        } else if (want.mode === "color") {
          body.hue = { value: want.hue }
          body.sat = { value: want.sat }
          Object.assign(patch, { hue: want.hue, sat: want.sat, colorMode: "hs", effect: "*Solid*" })
        }
        _patchInfo(devId, patch)
        _sendState(d, devId, body)
      }
    }
    missingScenes = missing
  }

  function _applyEffectState(d, devId, want) {
    _patchInfo(devId, { on: true, brightness: want.brightness, effect: want.effect, colorMode: "effect" })
    // One pending entry covers both requests; only the last one finishes it.
    Api.selectEffect(d, want.effect, function(ok) {
      if (!ok) { root._done(devId)(false); return }
      Api.setState(d, { brightness: { value: want.brightness, duration: 0 } }, root._done(devId))
    })
  }

  function _sendState(d, devId, body) {
    Api.setState(d, body, _done(devId))
  }

  // Completion callback for a command started via _patchInfo.
  function _done(id) {
    return function(ok) {
      root.pending = Pending.finish(root.pending, id, ok, Date.now())
      if (!ok) root.refreshDevice(id)
    }
  }

  function _currentFor(id) {
    var s = root.states[id]
    if (!s || !s.reachable || !s.info) return null
    return { info: s.info, mode: Api.modeOf(s.info) }
  }

  function setAllOn(on) {
    for (var i = 0; i < devices.length; i++) setOn(devices[i].id, on)
  }

  function toggleAll() {
    setAllOn(!anyOn)
  }

  // Applies to devices that are on; if everything is off, turns all on.
  function setAllBrightness(value) {
    var targets = []
    for (var i = 0; i < devices.length; i++) {
      var s = states[devices[i].id]
      if (s && s.reachable && s.info && s.info.on) targets.push(devices[i].id)
    }
    if (targets.length === 0) targets = devices.map(function(d) { return d.id })
    for (var j = 0; j < targets.length; j++) setBrightness(targets[j], value)
  }

  function stepAllBrightness(delta) {
    if (!anyOn) return
    setAllBrightness(averageBrightness + delta)
  }

  function identify(id) {
    var d = deviceById(id)
    if (d) Api.identify(d, null)
  }

  function discover() {
    if (discoverProc.running) return
    discovering = true
    discoverProc.running = true
  }

  // Requires the controller's power button held for 5–7 s beforehand.
  function pair(id) {
    var found = null
    for (var i = 0; i < discovered.length; i++) if (discovered[i].id === id) found = discovered[i]
    if (!found || pairingId !== "") return
    pairingId = id
    pairingError = ""
    Api.pair(found, function(ok, status, token) {
      root.pairingId = ""
      if (!ok) {
        root.pairingError = status === 403 ? "not-pairing" : "unreachable"
        return
      }
      root._saveConfig(ConfigStore.upsertDevice(root.config, {
        id: found.id, name: found.name, host: found.host, port: found.port,
        model: found.model, token: token
      }))
      root.discovered = root.discovered.filter(function(x) { return x.id !== id })
      root.refreshDevice(id)
    })
  }

  function forget(id) {
    _saveConfig(ConfigStore.removeDevice(config, id))
    var next = Object.assign({}, states)
    delete next[id]
    states = next
    revision++
  }

  // ---- Internals ----------------------------------------------------------

  function _putState(id, s) {
    var next = Object.assign({}, states)
    next[id] = s
    states = next
    revision++
  }

  function _patchInfo(id, patch) {
    pending = Pending.begin(pending, id, patch)
    var s = states[id]
    if (!s || !s.info) return
    _putState(id, { reachable: s.reachable, info: Object.assign({}, s.info, patch) })
  }

  // The file is read at startup and again after the directory exists, and the
  // watcher reports our own writes; identical text is not re-applied, so a
  // single change triggers a single refresh.
  property string appliedConfigText: ""

  function _applyConfigText(text) {
    configLoaded = true
    if (text === appliedConfigText) return
    appliedConfigText = text
    config = ConfigStore.parse(text)
    refresh()
  }

  function _saveConfig(next) {
    config = next
    appliedConfigText = ConfigStore.serialize(next)
    configFile.setText(appliedConfigText)
  }

  function _applyDiscovery(text) {
    discovering = false
    var found = Api.parseDiscovery(text)
    var fresh = []
    var cfg = config
    var changed = false
    for (var i = 0; i < found.length; i++) {
      var known = deviceById(found[i].id)
      if (!known) { fresh.push(found[i]); continue }
      // DHCP may have moved a paired device; follow it.
      if (known.host !== found[i].host || known.port !== found[i].port) {
        cfg = ConfigStore.upsertDevice(cfg, Object.assign({}, known, { host: found[i].host, port: found[i].port }))
        changed = true
      }
    }
    discovered = fresh
    if (changed) { _saveConfig(cfg); refresh() }
  }

  // ---- Plumbing -----------------------------------------------------------

  // FileView does not create parent directories; the directory is 0700 because
  // the config holds device tokens.
  property Process configDirProc: Process {
    command: ["install", "-d", "-m", "700", root.configDir]
    running: true
    onExited: configFile.reload()
  }

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root._applyConfigText(text())
    onLoadFailed: { root.configLoaded = true; root.discover() }
    onFileChanged: reload()
  }

  property Process discoverProc: Process {
    command: ["timeout", "4", "avahi-browse", "-rpt", "_nanoleafapi._tcp"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._applyDiscovery(text) }
    onExited: root.discovering = false
  }

  // Cheap polling until the event stream lands; keeps state in sync with
  // changes from the Nanoleaf app or the power button.
  property Timer pollTimer: Timer {
    interval: 15000
    running: root.hasDevices
    repeat: true
    onTriggered: root.refresh()
  }

  // Re-discover occasionally so IP changes of paired devices are picked up.
  property Timer rediscoverTimer: Timer {
    interval: 10 * 60 * 1000
    running: root.hasDevices
    repeat: true
    onTriggered: root.discover()
  }
}
