"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const I18n = require("./load").load("I18n.js")

test("resolve follows the setting, then the system locale", () => {
  assert.equal(I18n.resolve("English", "de_DE"), "en")
  assert.equal(I18n.resolve("Deutsch", "en_US"), "de")
  assert.equal(I18n.resolve("Auto", "de_AT"), "de")
  assert.equal(I18n.resolve("Auto", "en_GB"), "en")
  assert.equal(I18n.resolve(undefined, "fr_FR"), "en")
})

test("both languages define the same keys", () => {
  assert.deepEqual(Object.keys(I18n.STRINGS.de).sort(), Object.keys(I18n.STRINGS.en).sort())
})

test("t substitutes the argument and falls back to English", () => {
  assert.equal(I18n.t("en", "tooltipOn", 40), "Nanoleaf: on, 40 %")
  assert.equal(I18n.t("de", "tooltipOn", 40), "Nanoleaf: an, 40 %")
  assert.equal(I18n.t("xx", "tabWhite"), "White")
  assert.equal(I18n.t("en", "no-such-key"), "no-such-key")
})

test("tabs use the Nanoleaf app terms", () => {
  assert.deepEqual(["tabScene", "tabColor", "tabWhite"].map((k) => I18n.t("en", k)), ["Scene", "Color", "White"])
  assert.deepEqual(["tabScene", "tabColor", "tabWhite"].map((k) => I18n.t("de", k)), ["Szene", "Farbe", "Weiß"])
})
