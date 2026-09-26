"use strict"

// Exercises the HTTP layer of NanoleafApi.js against a scripted
// XMLHttpRequest, checking method, URL and payload of every command.

const test = require("node:test")
const assert = require("node:assert/strict")

const sent = []
let respond = () => ({ status: 204, body: "" })

class MockXHR {
  static DONE = 4
  constructor() { this.headers = {}; this.readyState = 0 }
  open(method, url) { this.method = method; this.url = url }
  setRequestHeader(k, v) { this.headers[k] = v }
  send(body) {
    this.body = body === undefined ? undefined : JSON.parse(body)
    sent.push(this)
    const r = respond(this)
    if (r === "timeout") { this.ontimeout(); return }
    this.status = r.status
    this.responseText = r.body
    this.readyState = MockXHR.DONE
    this.onreadystatechange()
    // A late second DONE must not call back twice.
    this.onreadystatechange()
  }
}
globalThis.XMLHttpRequest = MockXHR

const Api = require("./load").load("NanoleafApi.js")
const device = { host: "10.0.0.43", port: 16021, token: "tok" }
const base = "http://10.0.0.43:16021/api/v1"

function last() { return sent[sent.length - 1] }

function call(fn, ...args) {
  return new Promise((resolve) => fn(device, ...args, (...res) => resolve(res)))
}

test("setOn / setBrightness / setColor / setWhite send the right state", async () => {
  respond = () => ({ status: 204, body: "" })
  const cases = [
    [Api.setOn, [true], { on: { value: true } }],
    [Api.setBrightness, [150.4], { brightness: { value: 100, duration: 0 } }],
    [Api.setColor, [400, -5], { hue: { value: 360 }, sat: { value: 0 } }],
    [Api.setWhite, [2712.6], { ct: { value: 2713 } }],
  ]
  for (const [fn, args, body] of cases) {
    const [ok, status] = await call(fn, ...args)
    assert.equal(ok, true)
    assert.equal(status, 204)
    assert.equal(last().method, "PUT")
    assert.equal(last().url, base + "/tok/state")
    assert.equal(last().headers["Content-Type"], "application/json")
    assert.deepEqual(last().body, body)
  }
})

test("selectEffect and identify hit their endpoints", async () => {
  respond = () => ({ status: 204, body: "" })
  await call(Api.selectEffect, "Forest")
  assert.equal(last().url, base + "/tok/effects")
  assert.deepEqual(last().body, { select: "Forest" })
  await call(Api.identify)
  assert.equal(last().url, base + "/tok/identify")
})

test("fetchInfo parses JSON bodies and tolerates garbage", async () => {
  respond = () => ({ status: 200, body: JSON.stringify({ name: "Shapes" }) })
  let [ok, status, body] = await call(Api.fetchInfo)
  assert.equal(last().method, "GET")
  assert.equal(last().url, base + "/tok/")
  assert.equal(last().body, undefined)
  assert.deepEqual([ok, status, body], [true, 200, { name: "Shapes" }])

  respond = () => ({ status: 200, body: "<html>" })
  ;[ok, status, body] = await call(Api.fetchInfo)
  assert.equal(body, null)
})

test("errors and timeouts report failure", async () => {
  respond = () => ({ status: 401, body: "" })
  let [ok, status] = await call(Api.fetchInfo)
  assert.deepEqual([ok, status], [false, 401])

  respond = () => "timeout"
  ;[ok, status] = await call(Api.fetchInfo)
  assert.deepEqual([ok, status], [false, 0])
})

test("pair returns the token, or the status on refusal", async () => {
  respond = () => ({ status: 200, body: JSON.stringify({ auth_token: "new-token" }) })
  let [ok, status, token] = await new Promise((r) => Api.pair(device, (...a) => r(a)))
  assert.equal(last().method, "POST")
  assert.equal(last().url, base + "/new")
  assert.deepEqual([ok, status, token], [true, 200, "new-token"])

  respond = () => ({ status: 403, body: "" })
  ;[ok, status, token] = await new Promise((r) => Api.pair(device, (...a) => r(a)))
  assert.deepEqual([ok, status, token], [false, 403, ""])
})

test("a missing callback is fine", () => {
  respond = () => ({ status: 204, body: "" })
  assert.doesNotThrow(() => Api.identify(device, null))
})
