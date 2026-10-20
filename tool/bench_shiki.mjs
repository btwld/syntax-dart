// Reference numbers: Shiki on the same file, with both engines.
import fs from 'node:fs'
import { createHighlighter, createJavaScriptRegexEngine } from 'shiki'
const code = fs.readFileSync(process.argv[2], 'utf8')
for (const [label, engine] of [['oniguruma', undefined], ['javascript', createJavaScriptRegexEngine()]]) {
  let t = performance.now()
  const hl = await createHighlighter({ langs: ['dart'], themes: ['github-dark'], ...(engine ? { engine } : {}) })
  hl.codeToTokensBase(code, { lang: 'dart', theme: 'github-dark' })
  const cold = performance.now() - t
  t = performance.now()
  for (let i = 0; i < 5; i++) hl.codeToTokensBase(code, { lang: 'dart', theme: 'github-dark' })
  const warm = (performance.now() - t) / 5
  console.log(`shiki ${label}: cold ${cold.toFixed(0)}ms, warm ${warm.toFixed(1)}ms (${(code.length / 1024 / 1024 / (warm / 1000)).toFixed(2)} MB/s)`)
}
