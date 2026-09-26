"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const Api = require("./load").load("NanoleafApi.js")

const AVAHI = [
  '+;wlp8s0;IPv4;Shapes\\032BC30;_nanoleafapi._tcp;local',
  '=;wlp8s0;IPv6;Shapes\\032BC30;_nanoleafapi._tcp;local;Shapes-BC30.local;2a00::1;16021;"id=74:20:1B:18:44:C4" "md=NL42"',
  '=;wlp8s0;IPv4;Shapes\\032BC30;_nanoleafapi._tcp;local;Shapes-BC30.local;10.0.0.43;16021;"id=74:20:1B:18:44:C4" "md=NL42" "srcvers=12.3.2"',
  '=;docker0;IPv4;Shapes\\032BC30;_nanoleafapi._tcp;local;Shapes-BC30.local;172.17.0.1;16021;"id=74:20:1B:18:44:C4" "md=NL42"',
  '=;wlp8s0;IPv4;B\\252ro\\032Lines;_nanoleafapi._tcp;local;Lines.local;10.0.0.44;16021;"id=AA:BB:CC:DD:EE:FF" "md=NL59"',
].join("\n")

test("parseDiscovery keeps IPv4 entries, one per device id", () => {
  const found = Api.parseDiscovery(AVAHI)
  assert.equal(found.length, 2)
  assert.deepEqual(found[0], { id: "74:20:1B:18:44:C4", name: "Shapes BC30", host: "10.0.0.43", port: 16021, model: "NL42" })
  assert.equal(found[1].name, "Büro Lines")
})

test("parseDiscovery tolerates junk", () => {
  assert.deepEqual(Api.parseDiscovery(""), [])
  assert.deepEqual(Api.parseDiscovery("garbage;;;\n=;x"), [])
})

const INFO = {
  name: "Shapes BC30",
  model: "NL42",
  state: {
    on: { value: true },
    brightness: { value: 38, max: 100, min: 0 },
    hue: { value: 120, max: 360, min: 0 },
    sat: { value: 80, max: 100, min: 0 },
    ct: { value: 2700, max: 6500, min: 1200 },
    colorMode: "effect",
  },
  effects: { select: "Cyberpunk", effectsList: ["Cyberpunk", "Forest", 42] },
}

test("parseInfo extracts the fields the UI needs", () => {
  const info = Api.parseInfo(INFO)
  assert.equal(info.on, true)
  assert.equal(info.brightness, 38)
  assert.equal(info.ct, 2700)
  assert.equal(info.ctMin, 1200)
  assert.equal(info.ctMax, 6500)
  assert.equal(info.effect, "Cyberpunk")
  assert.deepEqual(info.effects, ["Cyberpunk", "Forest"])
})

test("parseInfo rejects non-objects and survives missing fields", () => {
  assert.equal(Api.parseInfo(null), null)
  const info = Api.parseInfo({})
  assert.equal(info.on, false)
  assert.equal(info.ctMin, 1200)
  assert.deepEqual(info.effects, [])
})

test("modeOf maps Nanoleaf colorMode to Szene / Farbe / Weiß", () => {
  assert.equal(Api.modeOf({ colorMode: "effect", effect: "Cyberpunk" }), "effect")
  assert.equal(Api.modeOf({ colorMode: "hs", effect: "*Solid*" }), "color")
  assert.equal(Api.modeOf({ colorMode: "ct", effect: "*Solid*" }), "white")
  assert.equal(Api.modeOf({ colorMode: "", effect: "*Solid*" }), "color")
  assert.equal(Api.modeOf(null), "effect")
})

test("userEffects hides internal pseudo effects", () => {
  assert.deepEqual(Api.userEffects({ effects: ["*Solid*", "Forest", "*Dynamic*"] }), ["Forest"])
})

test("URLs encode the token and default the port", () => {
  const d = { host: "10.0.0.43", token: "a/b" }
  assert.equal(Api.baseUrl(d), "http://10.0.0.43:16021/api/v1")
  assert.equal(Api.authUrl(d, "/state"), "http://10.0.0.43:16021/api/v1/a%2Fb/state")
})
