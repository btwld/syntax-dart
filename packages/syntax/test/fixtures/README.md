# Test fixtures

- `samples/`: selected conformance sources for bundled languages. Each `<language>.sample`
  comes from the `samples` folder of
  [shikijs/textmate-grammars-themes](https://github.com/shikijs/textmate-grammars-themes)
  (MIT), fetched by `tool/samples.mjs`. The exception is
  `shellscript.sample`, which was written here because the upstream one
  carries its author's copyright. `dart.modern.sample`,
  `markdown.fences.sample` and `yaml.pubspec.sample` were written here too. The `*.catalog.sample` files are project-owned cases covering additional languages, dependency embeddings and injections.
- `golden/`: Shiki's tokens and colors for each sample, recorded by
  `tool/golden.mjs`.
- `diff/`: patches and before/after files made with git in a scratch
  repository.
