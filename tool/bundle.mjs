// What syntax bundles. Edit these lists, then run `npm run generate` and
// `npm run golden` from this folder.

import { grammars } from 'tm-grammars'
import { themes } from 'tm-themes'

export const LANGS = grammars.map((entry) => entry.name)
export const THEMES = themes.map((entry) => entry.name)

/// Themes the golden tests compare colors against.
export const GOLDEN_THEMES = ['github-dark', 'light-plus', 'one-dark-pro']

export const camel = (name) =>
  name.replace(/[-_](\w)/g, (_, c) => c.toUpperCase()).replace(/[^a-zA-Z0-9]/g, '').replace(/^(?=\d)/, 'language')
