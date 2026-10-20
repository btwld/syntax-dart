// What syntax bundles. Edit these lists, then run `npm run generate` and
// `npm run golden` from this folder.

export const LANGS = [
  'css',
  'dart',
  'diff',
  'go',
  'html',
  'javascript',
  'json',
  'jsonc',
  'kotlin',
  'markdown',
  'python',
  'rust',
  'shellscript',
  'sql',
  'swift',
  'typescript',
  'xml',
  'yaml',
]

export const THEMES = [
  'catppuccin-latte',
  'catppuccin-mocha',
  'dark-plus',
  'dracula',
  'github-dark',
  'github-light',
  'light-plus',
  'min-light',
  'monokai',
  'nord',
  'one-dark-pro',
  'solarized-light',
  'tokyo-night',
  'vitesse-dark',
  'vitesse-light',
]

/// Themes the golden tests compare colors against.
export const GOLDEN_THEMES = ['github-dark', 'light-plus', 'one-dark-pro']

export const camel = (name) =>
  name.replace(/[-_](\w)/g, (_, c) => c.toUpperCase())
