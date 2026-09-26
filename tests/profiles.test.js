"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const P = require("./load").load("Profiles.js")

const effectInfo = { on: true, brightness: 60, effect: "Cyberpunk", colorMode: "effect", hue: 0, sat: 0, ct: 4000 }
const whiteInfo = { on: true, brightness: 90, effect: "*Solid*", colorMode: "ct", hue: 0, sat: 0, ct: 5000 }
const colorInfo = { on: true, brightness: 40, effect: "*Solid*", colorMode: "hs", hue: 120, sat: 80, ct: 4000 }

test("captureDevice stores only what the mode needs", () => {
  assert.deepEqual(P.captureDevice(effectInfo, "effect"), { on: true, brightness: 60, mode: "effect", effect: "Cyberpunk" })
  assert.deepEqual(P.captureDevice(whiteInfo, "white"), { on: true, brightness: 90, mode: "white", ct: 5000 })
  assert.deepEqual(P.captureDevice(colorInfo, "color"), { on: true, brightness: 40, mode: "color", hue: 120, sat: 80 })
  assert.deepEqual(P.captureDevice({ ...effectInfo, on: false }, "effect"), { on: false })
  assert.equal(P.captureDevice(null, "effect"), null)
})

test("upsert overwrites by name (case-insensitive) and keeps the id", () => {
  let list = P.upsert([], { name: "Abend", devices: { a: P.captureDevice(effectInfo, "effect") } })
  list = P.upsert(list, { name: "abend", devices: { a: { on: false } } })
  assert.equal(list.length, 1)
  assert.equal(list[0].id, "abend")
  assert.deepEqual(list[0].devices.a, { on: false })
})

test("upsert gives distinct ids to names with the same slug", () => {
  let list = P.upsert([], { name: "Abend!", devices: { a: { on: false } } })
  list = P.upsert(list, { name: "Abend?", devices: { a: { on: false } } })
  assert.deepEqual(list.map((p) => p.id), ["abend", "abend-2"])
})

test("slug transliterates umlauts", () => {
  assert.equal(P.slug("Gemütlich Grün"), "gemuetlich-gruen")
  assert.equal(P.slug("!!!"), "profil")
})

test("normalizeList drops broken profiles and clamps values", () => {
  const list = P.normalizeList([
    { name: "", devices: { a: { on: false } } },
    { name: "Leer", devices: {} },
    { name: "Hell", devices: { a: { on: true, brightness: 500, mode: "white", ct: 2700 } } },
    "nonsense",
  ])
  assert.equal(list.length, 1)
  assert.equal(list[0].devices.a.brightness, 100)
})

test("matches compares only the devices in the profile", () => {
  const profile = P.normalize({ name: "Arbeiten", devices: { a: P.captureDevice(whiteInfo, "white") } })
  const current = (id) => (id === "a" ? { info: whiteInfo, mode: "white" } : null)
  assert.equal(P.matches(profile, current), true)
  const dimmer = () => ({ info: { ...whiteInfo, brightness: 50 }, mode: "white" })
  assert.equal(P.matches(profile, dimmer), false)
  const other = () => ({ info: effectInfo, mode: "effect" })
  assert.equal(P.matches(profile, other), false)
  assert.equal(P.matches(profile, () => null), false)
})

test("matches tolerates small rounding differences", () => {
  const profile = P.normalize({ name: "Grün", devices: { a: P.captureDevice(colorInfo, "color") } })
  const close = () => ({ info: { ...colorInfo, hue: 122, brightness: 41 }, mode: "color" })
  assert.equal(P.matches(profile, close), true)
})
