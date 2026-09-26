"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const P = require("./load").load("Pending.js")

const on = { on: true, brightness: 40 }

test("a stale read during a command does not undo the optimistic value", () => {
  let map = P.begin({}, "a", { on: false })
  assert.deepEqual(P.apply(map, "a", on, 1000), { on: false, brightness: 40 })
})

test("after success the value is protected for the grace period only", () => {
  let map = P.begin({}, "a", { on: false })
  map = P.finish(map, "a", true, 1000)
  assert.equal(P.apply(map, "a", on, 1000 + P.GRACE_MS - 1).on, false)
  assert.equal(P.apply(map, "a", on, 1000 + P.GRACE_MS).on, true)
  assert.deepEqual(P.prune(map, 1000 + P.GRACE_MS), {})
})

test("overlapping commands merge and stay pending until the last one ends", () => {
  let map = P.begin({}, "a", { on: true })
  map = P.begin(map, "a", { brightness: 80 })
  map = P.finish(map, "a", true, 1000)
  assert.deepEqual(P.apply(map, "a", { on: false, brightness: 10 }, 99999), { on: true, brightness: 80 })
  map = P.finish(map, "a", true, 2000)
  assert.equal(P.apply(map, "a", { on: false }, 2000 + P.GRACE_MS).on, false)
})

test("a failed command drops the pending value so the real state shows", () => {
  let map = P.begin({}, "a", { on: false })
  map = P.finish(map, "a", false, 1000)
  assert.equal(P.apply(map, "a", on, 1000).on, true)
})

test("other devices, unknown ids and missing info are untouched", () => {
  const map = P.begin({}, "a", { on: false })
  assert.equal(P.apply(map, "b", on, 0), on)
  assert.equal(P.apply(map, "a", null, 0), null)
  assert.equal(P.finish(map, "zzz", true, 0), map)
})

test("inputs are never mutated", () => {
  const map = P.begin({}, "a", { on: false })
  const frozen = JSON.stringify(map)
  P.begin(map, "a", { on: true })
  P.finish(map, "a", true, 5)
  P.prune(map, 1e12)
  assert.equal(JSON.stringify(map), frozen)
})
