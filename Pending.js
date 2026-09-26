.pragma library

// Optimistic state that polls must not undo.
//
// When the user flips a switch, the UI shows the new value at once. A status
// read that was already on its way (poll, panel open) can still arrive with
// the old value and would make the switch jump back. So every command records
// its fields as pending; reads merge pending fields over the device's answer
// while the command is in flight and for a short grace period afterwards.
//
// Map shape: { <deviceId>: { patch, inflight, until } }. All functions return
// a new map and never mutate their input.

var GRACE_MS = 1500

function clone(map) {
  var next = {}
  for (var k in map) if (Object.prototype.hasOwnProperty.call(map, k)) next[k] = map[k]
  return next
}

// A command for `id` starts; `patch` holds the fields it sets.
function begin(map, id, patch) {
  var next = clone(map)
  var cur = next[id]
  next[id] = {
    patch: Object.assign({}, cur ? cur.patch : {}, patch),
    inflight: (cur ? cur.inflight : 0) + 1,
    until: 0
  }
  return next
}

// A command for `id` finished. On failure the pending state is dropped so the
// next read shows the real device state.
function finish(map, id, ok, now) {
  var cur = map[id]
  if (!cur) return map
  var next = clone(map)
  if (!ok) {
    delete next[id]
    return next
  }
  var inflight = Math.max(0, cur.inflight - 1)
  next[id] = { patch: cur.patch, inflight: inflight, until: inflight === 0 ? now + GRACE_MS : 0 }
  return next
}

function isActive(entry, now) {
  return !!entry && (entry.inflight > 0 || now < entry.until)
}

// Merges pending fields over a freshly read `info`.
function apply(map, id, info, now) {
  var entry = map[id]
  if (!info || !isActive(entry, now)) return info
  return Object.assign({}, info, entry.patch)
}

// Drops entries whose grace period is over.
function prune(map, now) {
  var next = {}
  for (var k in map) {
    if (Object.prototype.hasOwnProperty.call(map, k) && isActive(map[k], now)) next[k] = map[k]
  }
  return next
}
