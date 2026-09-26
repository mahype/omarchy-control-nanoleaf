"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const C = require("./load").load("ConfigStore.js")

const device = { id: "74:20:1B:18:44:C4", name: "Shapes BC30", host: "10.0.0.43", port: 16021, token: "t0k3n", model: "NL42" }

test("parse falls back to an empty config on bad input", () => {
  assert.deepEqual(C.parse("not json"), C.empty())
  assert.deepEqual(C.parse("null"), C.empty())
})

test("parse drops devices without id, host or token and dedupes", () => {
  const cfg = C.parse(JSON.stringify({
    devices: [device, { ...device }, { id: "x", host: "1.2.3.4" }, { host: "1.2.3.4", token: "t" }],
  }))
  assert.equal(cfg.devices.length, 1)
  assert.equal(cfg.devices[0].token, "t0k3n")
})

test("round trip keeps devices and profiles", () => {
  let cfg = C.upsertDevice(C.empty(), device)
  cfg = C.setProfiles(cfg, [{ id: "abend", name: "Abend", devices: { [device.id]: { on: false } } }])
  const again = C.parse(C.serialize(cfg))
  assert.deepEqual(again, cfg)
})

test("upsertDevice replaces by id (e.g. new IP after DHCP)", () => {
  let cfg = C.upsertDevice(C.empty(), device)
  cfg = C.upsertDevice(cfg, { ...device, host: "10.0.0.99" })
  assert.equal(cfg.devices.length, 1)
  assert.equal(cfg.devices[0].host, "10.0.0.99")
})

test("removeDevice leaves profiles alone", () => {
  let cfg = C.upsertDevice(C.empty(), device)
  cfg = C.setProfiles(cfg, [{ id: "p", name: "P", devices: { [device.id]: { on: false } } }])
  cfg = C.removeDevice(cfg, device.id)
  assert.equal(cfg.devices.length, 0)
  assert.equal(cfg.profiles.length, 1)
})
