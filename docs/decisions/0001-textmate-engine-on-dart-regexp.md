# ADR-0001: TextMate engine on Dart `RegExp`, with a pure-Dart core and a thin Flutter layer

**Status:** Accepted
**Date:** 2026-10-19
**Amended by:** [ADR-0003](0003-engine-and-readonly-rendering.md). `syntax_flutter` renders read-only code and diffs. It does not ship a text editing controller.

## Context

We want syntax highlighting that works from plain Dart (CLI, server, build
tools) and from Flutter (including web). It should also follow the de-facto
standard used by VS Code, Shiki and GitHub-style highlighters: TextMate
grammars plus VS Code JSON themes. That standard gives hundreds of
maintained grammars and themes for free, instead of hand-maintained lexers.

The drivers are:

- **Fidelity.** Output should match VS Code and Shiki for the same grammar
  and theme.
- **A pure-Dart core.** No `dart:ui`, FFI or WASM in the tokenizer.
- **Web.** Fast on Flutter web and dart2js/dart2wasm.
- **Small surface.** It should be easy to add any grammar or theme from
  JSON.
- **Maintainability.** A small codebase with a clear test oracle.

### Survey of pub.dev

Checked 2026-10-19 against the pub.dev API and source:

| Package | Approach | Problem for our goals |
|---|---|---|
| `highlight` / `flutter_highlight` | highlight.js 10 port | Last pub release was 2021. A revived master is unpublished. |
| `highlighting` (Akvelon) | highlight.js 11.8 port | No commits since 2023. |
| `re_highlight` | highlight.js 11.9 port | Pulls in Flutter. Issue #2 reports it is very slow on WASM. highlight.js grammars are less precise than TextMate ones. |
| `syntax_highlight` (Serverpod) | TextMate, home-grown engine | Flutter-only (`rootBundle`). Takes the first matching pattern rather than the leftmost. No end-backreferences, no injections, no Oniguruma translation. |
| `shiki_flutter` | vscode-textmate + Shiki port on `oniguruma_dart` | Closest in spirit, but depends on Flutter. Brand new (2026-07), with a single maintainer. |
| `val_highlight` | hand-written lexers, 55 languages, pure Dart | Not TextMate, so it can't reuse VS Code grammars. First published this month. |
| tree-sitter bindings | FFI/WASM | Native toolchain, no clean web story, immature in Dart. |

Nothing combines a pure-Dart core with a faithful TextMate engine and a
Flutter layer.

### The core technical problem

TextMate grammars are written for Oniguruma regexes. Dart `RegExp` is
ECMAScript. On the Dart VM, several Oniguruma constructs are **silently
misparsed** rather than rejected: `\h`, `\A` and `\z` are read as literal
letters, and `[[:alpha:]]` as a class plus `]`. Others throw (`(?i)`,
`(?>…)`, `a++`). Shiki's JavaScript engine shows the gap can be closed by
translation: Shiki's published compatibility table lists 237 of 238
languages as supported.

## Decision

Build a **vscode-textmate port in pure Dart** that runs on **Dart's
built-in `RegExp`** through an **Oniguruma → ECMAScript translator**. Put
it behind a small `RegexEngine` interface so that an exact Oniguruma
engine, such as `oniguruma_dart`, can be plugged in later without touching
the tokenizer.

The work is split into these packages:

- **`syntax`** (pure Dart, zero dependencies) contains:
  - the translator, scanner and tokenizer, as a port of vscode-textmate's
    algorithm;
  - VS Code theme resolution;
  - a `Highlighter` facade, with output as tokens, HTML and ANSI;
  - bundled grammars and themes as generated `const` maps, one library
    each, so they are tree-shakeable.
- **`syntax_flutter`** contains the `TextSpan` conversion and the read-only
  `HighlightedCode` and `PatchView` widgets. They reuse line state from
  `TokenizedDocument`. Editing belongs in the consuming application.

**Test oracle:** real Shiki (vscode-textmate + Oniguruma WASM), run from
`tool/` with Node. It produces golden tokens and colors for each bundled
grammar's upstream sample. Conformance is measured, not assumed.

## Options considered

1. **Adopt an existing package.** This means no engine work. But each
   candidate misses either the pure-Dart core (`shiki_flutter`,
   `syntax_highlight`) or the TextMate ecosystem (`val_highlight`,
   highlight.js ports). Adopt one instead if Flutter-only or hand-written
   lexers are acceptable.
2. **TextMate on `oniguruma_dart`.** This gives exact regex semantics with
   no translator. However:
   - it is a young, single-maintainer dependency;
   - it ships a full regex VM and Unicode tables to web bundles;
   - in a quick VM micro-benchmark it was about 2× slower than `RegExp`, and
     it is likely worse on web, where `RegExp` is the browser's native
     engine.

   It is kept as a pluggable engine rather than the default.
3. **highlight.js-style port.** This is simpler, but it is less precise,
   the theme ecosystem is weaker, and three ports already exist.
4. **Hand-written lexers.** These are fast and simple per language, but
   cost unbounded per-language maintenance. `val_highlight` already does
   this well.
5. **tree-sitter.** It has the best structure, but it is native or WASM
   only, has weak Dart tooling, and is overkill for coloring.

## Consequences

- One engine serves both CLI and Flutter. Any VS Code grammar or theme JSON
  can be loaded at runtime.
- We own a translator. Constructs ECMAScript cannot express are handled
  "forgivingly": the single offending pattern never matches and the rest of
  the grammar still works. Examples are conditionals `(?(…))` and deep
  `\g<…>` recursion.
- Correctness is pinned to Shiki output. A grammar that diverges shows up
  as a failing golden test rather than a user bug report.
- Injections are supported, both a grammar's own `injections` and other
  grammars' `injectionSelector` with `injectTo`. Shiki needs them for
  Svelte, Angular, Vue, ERB and the like.

## Outcome (2026-10-19)

- **Bundled conformance:** every token of every sample in the 18 bundled
  grammars matches Shiki, as do the colors under three themes (84 of 84
  checks).
- **All of Shiki's grammars:** 237 of 238 match exactly, which is 9,445 of
  9,447 lines. The one gap is Pug, which depends on Shiki's registration
  order.
- **Translator:** it compiles 34,684 of 34,686 patterns across all 260
  grammars. The two failures use the absent operator.
- **Throughput:** 11–12 MB/s compiled to JS, on par with Shiki's JS
  engine (10–10.5 MB/s) and about 3× its Oniguruma engine. On the Dart VM
  it is 1.9–2.0 MB/s, where `RegExp` execution is more than 90% of the
  profile.

## Reconsider when

- Golden conformance for a grammar we need stays below 100% because of a
  construct the translator cannot emulate. Use the Oniguruma engine for
  that grammar.
- `oniguruma_dart` (or `oniguruma_native` with WASM on web) reaches parity
  with `RegExp` speed and has a track record. Then we can delete the
  translator.
- `shiki_flutter` splits out a pure-Dart core with comparable fidelity. At
  that point, contributing there beats maintaining a parallel engine.
