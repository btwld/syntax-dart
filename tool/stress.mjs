// Stress test: records Shiki's scopes for every grammar in tm-grammars,
// using the upstream sample for each. Usage: node stress.mjs <outDir>
// Then, from packages/syntax:
//   dart run tool/stress.dart <outDir> ../../tool/node_modules/tm-grammars/grammars
import fs from 'node:fs'
import path from 'node:path'
import { createHighlighter } from 'shiki'
import { grammars } from 'tm-grammars'

const out = process.argv[2]
const base = 'https://raw.githubusercontent.com/shikijs/textmate-grammars-themes/main/samples'
fs.mkdirSync(path.join(out, 'samples'), { recursive: true })
fs.mkdirSync(path.join(out, 'golden'), { recursive: true })

const names = grammars.map((g) => g.name)
await Promise.all(names.map(async (name) => {
  const file = path.join(out, 'samples', `${name}.sample`)
  if (fs.existsSync(file)) return
  const res = await fetch(`${base}/${name}.sample`)
  if (res.ok) fs.writeFileSync(file, await res.text())
}))

const highlighter = await createHighlighter({ langs: names, themes: [] })

// Shiki keeps `injectTo` in its language registrations, not in tm-grammars.
const { bundledLanguages } = await import('shiki')
const injectTo = {}
for (const [name, load] of Object.entries(bundledLanguages)) {
  for (const reg of (await load()).default) {
    if (reg.injectTo) injectTo[reg.name] = reg.injectTo
  }
}
fs.writeFileSync(path.join(out, 'inject_to.json'), JSON.stringify(injectTo))
let count = 0
for (const name of names) {
  const file = path.join(out, 'samples', `${name}.sample`)
  if (!fs.existsSync(file)) continue
  const code = fs.readFileSync(file, 'utf8')
  const grammar = highlighter.getLanguage(name)
  let state = null
  const tokens = code.split(/\r?\n/).map((line) => {
    const r = grammar.tokenizeLine(line, state)
    state = r.ruleStack
    return r.tokens.map((t) => [t.startIndex, Math.min(t.endIndex, line.length), t.scopes.join(' ')]).filter(([s, e]) => e > s)
  })
  const meta = grammars.find((g) => g.name === name)
  fs.writeFileSync(path.join(out, 'golden', `${name}.json`), JSON.stringify({ lang: name, scopeName: meta.scopeName, tokens }))
  count++
}
console.log(`Recorded ${count} grammars`)
