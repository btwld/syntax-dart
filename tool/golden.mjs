// Records what Shiki (vscode-textmate + Oniguruma WASM) produces for every
// sample: raw scopes per token, and colors per token for a few themes.
// packages/syntax_darts/test/conformance_test.dart compares syntax against these.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHighlighter } from 'shiki'
import { LANGS, GOLDEN_THEMES } from './bundle.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const fixtures = path.join(here, '..', 'packages', 'syntax', 'test', 'fixtures')
const out = path.join(fixtures, 'golden')
fs.mkdirSync(out, { recursive: true })

// Load exactly the bundled set, so embedded languages resolve identically.
const highlighter = await createHighlighter({ langs: LANGS, themes: GOLDEN_THEMES })

// `dart.sample` and `dart.modern.sample` are both Dart samples.
const samples = fs.readdirSync(path.join(fixtures, 'samples')).filter((f) => f.endsWith('.sample'))
for (const file of samples) {
  const lang = file.split('.')[0]
  if (!LANGS.includes(lang)) continue
  const code = fs.readFileSync(path.join(fixtures, 'samples', file), 'utf8')
  const lines = code.split(/\r?\n/)

  const grammar = highlighter.getLanguage(lang)
  let state = null
  const tokens = lines.map((line) => {
    const r = grammar.tokenizeLine(line, state)
    state = r.ruleStack
    return r.tokens
      .map((t) => [t.startIndex, Math.min(t.endIndex, line.length), t.scopes.join(' ')])
      .filter(([s, e]) => e > s)
  })

  // Colors come from vscode-textmate's encoded token metadata rather than
  // codeToTokensBase. Shiki skips empty lines without advancing the rule
  // stack, which VS Code does not do: after a blank line, `---` is a
  // thematic break in VS Code but a setext heading in Shiki.
  const themes = {}
  for (const theme of GOLDEN_THEMES) {
    const { colorMap } = highlighter.setTheme(theme)
    let themeState = null
    themes[theme] = lines.map((line) => {
      const r = grammar.tokenizeLine2(line, themeState)
      themeState = r.ruleStack
      const runs = []
      for (let j = 0; j < r.tokens.length; j += 2) {
        const start = r.tokens[j]
        const end = Math.min(j + 2 < r.tokens.length ? r.tokens[j + 2] : line.length, line.length)
        const metadata = r.tokens[j + 1]
        const fontStyle = (metadata & 0b111100000000000) >>> 11
        const foreground = (metadata & 0b111111111000000000000000) >>> 15
        if (end > start) runs.push([start, end, colorMap[foreground].toLowerCase(), fontStyle])
      }
      return runs
    })
  }

  const name = file.replace(/\.sample$/, '')
  fs.writeFileSync(path.join(out, `${name}.json`), JSON.stringify({ lang, sample: file, tokens, themes }))
}
console.log(`Golden files written for ${samples.length} samples.`)
