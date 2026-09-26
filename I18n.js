.pragma library

// UI strings. Terms follow the Nanoleaf app in each language (Scene/Szene,
// Color/Farbe, White/Weiß). "%1" is replaced by the argument.

var STRINGS = {
  en: {
    serviceUnavailable: "Nanoleaf: service unavailable",
    noDevice: "Nanoleaf: no device paired",
    tooltipOn: "Nanoleaf: on, %1 %",
    tooltipOff: "Nanoleaf: off",
    searchDevices: "Search for devices",
    deleteProfileQuestion: "Delete profile “%1”?",
    delete: "Delete",
    cancel: "Cancel",
    sceneMissing: "Scene no longer available: %1",
    saveAsProfile: "Save as profile",
    profileName: "Profile name",
    save: "Save",
    overwritesProfile: "Overwrites the existing profile.",
    newDevices: "NEW DEVICES",
    searching: "Searching the network …",
    noNewDevices: "No new devices found.",
    pairHint: "To pair, hold the power button on the controller for 5–7 s until the LEDs flash, then click “Pair”.",
    pair: "Pair",
    pairing: "Pairing …",
    pairNotReady: "Device is not in pairing mode. Hold the power button for 5–7 s and try again.",
    pairUnreachable: "Device not reachable.",
    unreachable: "unreachable",
    off: "off",
    color: "Color",
    identify: "Flash device",
    tabScene: "Scene",
    tabColor: "Color",
    tabWhite: "White",
    chooseScene: "Choose scene",
    noScenes: "No scenes stored on the device.",
    warm: "warm",
    cool: "cool"
  },
  de: {
    serviceUnavailable: "Nanoleaf: Dienst nicht verfügbar",
    noDevice: "Nanoleaf: kein Gerät gekoppelt",
    tooltipOn: "Nanoleaf: an, %1 %",
    tooltipOff: "Nanoleaf: aus",
    searchDevices: "Geräte suchen",
    deleteProfileQuestion: "Profil „%1“ löschen?",
    delete: "Löschen",
    cancel: "Abbrechen",
    sceneMissing: "Szene nicht mehr vorhanden: %1",
    saveAsProfile: "Als Profil speichern",
    profileName: "Name des Profils",
    save: "Speichern",
    overwritesProfile: "Überschreibt das bestehende Profil.",
    newDevices: "NEUE GERÄTE",
    searching: "Suche im Netzwerk …",
    noNewDevices: "Keine neuen Geräte gefunden.",
    pairHint: "Zum Koppeln die Power-Taste am Controller 5–7 s halten, bis die LEDs blinken, dann „Koppeln“ klicken.",
    pair: "Koppeln",
    pairing: "Koppeln …",
    pairNotReady: "Gerät nicht im Kopplungsmodus. Power-Taste 5–7 s halten und erneut versuchen.",
    pairUnreachable: "Gerät nicht erreichbar.",
    unreachable: "nicht erreichbar",
    off: "aus",
    color: "Farbe",
    identify: "Gerät blinken lassen",
    tabScene: "Szene",
    tabColor: "Farbe",
    tabWhite: "Weiß",
    chooseScene: "Szene wählen",
    noScenes: "Keine Szenen auf dem Gerät gespeichert.",
    warm: "warm",
    cool: "kalt"
  }
}

// setting: "Auto" | "English" | "Deutsch" (widget option); localeName: e.g. "de_DE".
function resolve(setting, localeName) {
  if (setting === "English") return "en"
  if (setting === "Deutsch") return "de"
  return String(localeName || "").toLowerCase().indexOf("de") === 0 ? "de" : "en"
}

function t(lang, key, arg) {
  var table = STRINGS[lang] || STRINGS.en
  var s = table[key]
  if (s === undefined) s = STRINGS.en[key]
  if (s === undefined) return key
  return arg === undefined ? s : s.replace("%1", String(arg))
}
