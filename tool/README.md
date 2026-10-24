# tool

Node scripts that build and check the bundled grammars and themes in
`packages/syntax_core`. Install the pinned versions first:

```bash
npm ci
```

| Command | What it does |
|---|---|
| `npm run generate` | Writes `lib/langs`, `lib/themes` and `NOTICE` from `tm-grammars` and `tm-themes`. The languages and themes are listed in `bundle.mjs`. |
| `npm run samples` | Downloads the upstream sample for each bundled language into `test/fixtures/samples`, except the ones written for this repository. |
| `npm run golden` | Records Shiki's tokens and colors for each sample into `test/fixtures/golden`. |
| `npm run bench -- <file>` | Measures Shiki on a file, for comparison with `packages/syntax_core/benchmark`. |
| `node stress.mjs <dir>` | Records Shiki's tokens for every grammar that has a sample, for `packages/syntax_core/tool/stress.dart`. |

The versions of `shiki`, `tm-grammars` and `tm-themes` are exact in
`package.json`, so regenerating gives the same files. CI checks this.
