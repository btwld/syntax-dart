# syntax

Syntax highlighting for Dart and Flutter that uses the same TextMate
grammars and VS Code themes as VS Code, Shiki and GitHub. These packages
are the highlighting engine and read-only views of code, diffs and
patches; editing belongs in the application. On every bundled
sample, its tokens and colors match Shiki's exactly; see
[Verified against Shiki](#verified-against-shiki).

Try it in the browser: the [live demo](https://btwld.github.io/syntax-dart/)
has a code view, a diff view and a patch view for every bundled language and
theme.

| Package | What it is |
|---|---|
| [`packages/syntax_core`](packages/syntax_core) | Pure Dart, zero dependencies. Contains the tokenizer, themes, HTML/ANSI rendering, diff tools (patch parsing, line diffs, word-level changes), and the renderer-neutral pieces other renderers build on. It runs on the VM, AOT, the web and inside Flutter. |
| [`packages/syntax_flutter`](packages/syntax_flutter) | Contains `HighlightedCode` (read-only highlighted code), `PatchView` (a highlighted diff or patch, unified or split) and `HighlighterScope`. |
| [`packages/syntax_flutter/example`](packages/syntax_flutter/example) | A read-only code, diff and patch preview with a picker for every bundled language and theme. |
| [`packages/syntax_noir`](packages/syntax_noir) | Terminal widgets on [noir](https://github.com/btwld/noir): a `CodeHighlighter` for noir's `CodeView` and a `PatchView`. Needs Dart 3.10. It is a workspace member and resolves `syntax_core` from this repo. |

Install [`syntax_core`](https://pub.dev/packages/syntax_core),
[`syntax_flutter`](https://pub.dev/packages/syntax_flutter), and
[`syntax_noir`](https://pub.dev/packages/syntax_noir) from pub.dev
(`syntax_core` 0.0.2, `syntax_flutter` 0.0.4, `syntax_noir` 0.0.2).
Renderers paint what the core lays out.

## Why another highlighter

Highlighters on pub.dev were either highlight.js ports, hand-written
lexers or Flutter-only. None ran VS Code's TextMate grammars in pure Dart
with output that matches VS Code.

## How it works

```
grammar.json ──► RuleFactory ──► Grammar.tokenizeLine(line, state) ──► Token(start, end, scopes)
                                        │                                   │
              Oniguruma regex ──► translator ──► Dart RegExp      SyntaxTheme.styleFor(scopes)
```

1. **Tokenizer:** a line-by-line port of vscode-textmate. It covers
   begin/end and begin/while rules, captures (including captures with
   their own patterns), `$self`/`$base`/external includes, end
   backreferences, injections and the endless-loop guards. The state is
   immutable, so editors can resume from any line.
2. **Regex translation.** Grammars are written for Oniguruma, and Dart's
   `RegExp` is ECMAScript. A real parser converts each pattern into an
   equivalent ECMAScript pattern:
   - `\G`, `\A`, `\z` and `\h`;
   - possessive quantifiers and atomic groups;
   - `(?i)`/`(?x)` scoping;
   - POSIX classes and class intersections;
   - `\g<name>` recursion;
   - Unicode `\w`/`\b`;
   - a `^` that does not match after the trailing newline.

   Dart's `RegExpMatch` has no group offsets, so capture positions are
   recovered with a lookbehind probe. All of a rule's patterns are
   searched with one alternation regex. The engine sits behind a
   `RegexEngine` interface, so an exact Oniguruma engine can be plugged in.
3. **Themes:** a port of vscode-textmate's theme trie. It handles dotted
   prefix matching, parent-scope selectors and specificity.

## Verified against Shiki

Shiki, with its Oniguruma WASM engine, is the oracle.

- **Bundled grammars:** `packages/syntax_core/test/conformance_test.dart` checks
  18 bundled grammars on 21 samples. Every token's scopes match Shiki
  exactly, as does every character's color and font style under three
  themes: 84 of 84 checks pass.
- **All of Shiki's grammars:** a stress run over all 238 grammars in Shiki
  that have samples matches 237 exactly. That is 9,445 of 9,447 lines.
  The remaining one is Pug. There, Shiki only applies Vue injections when
  Vue loads first, and this package applies them regardless of load order.
- **Translator:** it compiles 34,684 of the 34,686 patterns across all 260
  of Shiki's grammars. The two failures are C# patterns that use
  Oniguruma's absent operator, which ECMAScript cannot express.

Shiki's own `codeToTokensBase` skips blank lines without advancing the
grammar state. VS Code does advance it, so in Shiki a `---` after a blank
line becomes a setext heading. This package follows VS Code, and the color
goldens come from vscode-textmate's token metadata.

## Performance

Throughput when tokenizing and theming Flutter's `framework.dart` (301 KB,
7,469 lines) on an M-series Mac:

| Runtime | syntax | Shiki (JS engine) | Shiki (Oniguruma) |
|---|---|---|---|
| JavaScript (dart2js on Node) | 11–12 MB/s | 10–10.5 MB/s | 3.6–3.8 MB/s |
| Dart VM (JIT) | 1.9–2.0 MB/s | – | – |

Ranges cover three runs. On the web, `syntax` is on par with Shiki's
JavaScript engine and about 3× faster than its Oniguruma WASM engine.

On the VM, more than 90% of the time is spent inside `RegExp` itself, and
the same patterns run about 10× faster in V8. A 1,000-line file still
tokenizes in about 20 ms, and `TokenizedDocument` only re-tokenizes the
lines an edit can affect.

Capture offsets are measured from the start of each match, so the
tokenizer's own cost does not depend on where in a line a match is.
Minified JSON on one line takes about 0.3 µs per character at any length
up to 100,000. Grammars with lookaheads that scan to the end of the line
still slow down as minified lines grow, and so does Shiki on the same
lines. A minified JavaScript line of 20,000 characters takes about 170 ms
on the VM. Lines longer than 20,000 characters are left untokenized by
default, as in VS Code; set `Highlighter.maxLineLength` to change it.

Reproduce with the same input for each:

```bash
dart run packages/syntax_core/benchmark/tokenize.dart path/to/file.dart
```

```bash
dart compile js -O4 packages/syntax_core/benchmark/web_bench.dart -o /tmp/syntax_bench.js && node /tmp/syntax_bench.js path/to/file.dart
```

```bash
cd tool && npm run bench -- path/to/file.dart
```

The long-line numbers come from:

```bash
dart run packages/syntax_core/benchmark/long_line.dart
```

## Development

```bash
flutter pub get
```

The workspace is `syntax_core`, `syntax_flutter`, and `syntax_noir`, so it
resolves with the Flutter SDK.

```bash
cd packages/syntax_core && dart test
```

```bash
cd packages/syntax_flutter && flutter test
```

The example is not a workspace member. Resolve it, then run it:

```bash
cd packages/syntax_flutter/example && flutter pub get && flutter run -d chrome
```

`syntax_noir` is in the workspace, so `syntax_core` resolves to
`packages/syntax_core`. The published package depends on hosted `syntax_core`.

```bash
cd packages/syntax_noir && dart pub get && dart test
```

The bundled grammars, themes and goldens are generated from npm. To add a
language or theme, edit `tool/bundle.mjs`, then run:

```bash
cd tool && npm ci && npm run generate && npm run samples && npm run golden
```

These tools are for checking regex and tokenizer changes against every
Shiki grammar:

- `packages/syntax_core/tool/coverage.dart` translates and compiles every
  pattern in a directory of grammars.
- `packages/syntax_core/tool/stress.dart`, with `tool/stress.mjs`, compares
  tokens with Shiki for every grammar that has an upstream sample.
- `packages/syntax_core/tool/git_compare.dart` checks `parsePatch` and
  `diffTexts` against `git diff` on random edits.

## Not done yet

- **Background tokenizing:** an isolate helper for very large documents.
  Today tokenizing is synchronous.
- **Optional Oniguruma engine:** a `RegexEngine` adapter over
  `oniguruma_dart`, for grammars that need exact Oniguruma semantics.

## License

BSD 3-Clause, see [LICENSE](LICENSE). The bundled grammars and themes keep
their own licenses, listed in [packages/syntax_core/NOTICE](packages/syntax_core/NOTICE).
