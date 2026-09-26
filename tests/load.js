// Loads a QML JavaScript library (".pragma library" + ".import") into Node so
// the pure helpers can be tested without a QML engine.
"use strict"

const fs = require("fs")
const path = require("path")
const vm = require("vm")

const cache = {}

function load(file) {
  const full = path.resolve(__dirname, "..", file)
  if (cache[full]) return cache[full]
  let src = fs.readFileSync(full, "utf8")
  const imports = {}
  src = src.replace(/^\.pragma library\s*$/m, "")
  src = src.replace(/^\.import "([^"]+)" as (\w+)\s*$/gm, (_, dep, name) => {
    imports[name] = load(path.join(path.dirname(file), dep))
    return ""
  })
  const names = []
  for (const m of src.matchAll(/^(?:function|var)\s+(\w+)/gm)) names.push(m[1])
  // Wrap in a function and compile with the real filename so stack traces
  // and coverage point at the library file. The wrapper stays on the first
  // line to keep line numbers intact.
  const params = Object.keys(imports).join(",")
  const wrapped = "(function(" + params + ") {" + src + "\nreturn {" + names.join(",") + "}\n})"
  const fn = vm.runInThisContext(wrapped, { filename: full })
  cache[full] = fn(...Object.values(imports))
  return cache[full]
}

module.exports = { load }
