// Downloads the upstream sample file for each bundled language into the
// golden test fixtures. Samples come from shikijs/textmate-grammars-themes.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { LANGS } from './bundle.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const dir = path.join(here, '..', 'packages', 'syntax', 'test', 'fixtures', 'samples')
const base = 'https://raw.githubusercontent.com/shikijs/textmate-grammars-themes/main/samples'

// Written for this repository instead: the upstream shell sample carries
// its author's copyright.
const OWN = new Set(['shellscript'])

fs.mkdirSync(dir, { recursive: true })
for (const lang of LANGS) {
  if (OWN.has(lang)) continue
  const res = await fetch(`${base}/${lang}.sample`)
  if (!res.ok) {
    console.warn(`No sample for ${lang} (${res.status})`)
    continue
  }
  fs.writeFileSync(path.join(dir, `${lang}.sample`), await res.text())
}
console.log(`Samples in ${path.relative(process.cwd(), dir)}`)
