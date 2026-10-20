# ADR-0002: The core owns everything but painting

**Status:** Accepted
**Date:** 2026-10-19

## Context

`syntax_flutter` is the first renderer, and `syntax_noir` is planned for
[noir](https://github.com/btwld/noir), a terminal UI framework on OpenTUI.
`syntax` itself already renders HTML and ANSI.

Noir's `CodeView` and `DiffView` take a `CodeHighlighter`, an interface with
one method. It returns non-overlapping UTF-16 `StyledTextRange`s over the
whole source, styled with noir's own `TextStyle` (see
`packages/noir/lib/src/widgets/code_view.dart` in that repository).

Until now, several pieces that have nothing to do with Flutter lived
privately in `syntax_flutter`:

- incremental re-tokenizing, in the text controller;
- the fallbacks for line number, selection and cursor colors;
- the patch layout: gaps, split pairing and line numbering;
- splitting tokens where changed words start and end.

A second renderer would have copied them. The patch layout alone had two
line-numbering bugs found in review, so copies would have copied
bugs too.

## Decision

`syntax` provides everything a renderer needs, in neutral types: colors as
ARGB `int`s, offsets in UTF-16 code units, and no `dart:ui`. A renderer only
paints and handles interaction.

| Need | Core API |
|---|---|
| Tokens and incremental state | `Grammar.tokenizeLine`, `StateStack` |
| Styles | `TokenStyle` (colors and bold, italic, underline, strikethrough), `SyntaxTheme` |
| Editor colors | `SyntaxTheme.foreground`, `background`, `lineNumberForeground`, `selectionBackground`, `cursorForeground`, `editorColor` |
| One styled string | `Highlighter.highlightRanges` returning `StyledRange`s |
| A document being edited | `TokenizedDocument`; unchanged `DocumentLine`s keep their identity, so renderers can cache per line |
| Diffs | `parsePatch`, `diffTexts`, `FileDiff` |
| Diff presentation | `layoutDiff` returning `DiffRow`s, `HighlightedDiff.segmentsFor` returning `DiffSegment`s, `DiffColors`, `FileDiff.maxLineNumber` |

Renderers own:

- widgets, layout, fonts and spacing;
- interaction state, such as collapsed files, expanded gaps and selection;
- every user-facing string. The core reports *why* a file has no lines as
  a `DiffNotice` value, and renderers choose the wording, so they can
  localize it.

`syntax_flutter` now follows this. `PatchView` paints `layoutDiff` rows,
`SyntaxTextEditingController` keeps a `TokenizedDocument`, and the
`SyntaxThemeColors` getters wrap the core colors.

### What `syntax_noir` needs

The core of the package is an adapter for noir's `CodeHighlighter`. A sketch
follows. `_style` maps a `TokenStyle`'s ARGB colors and flags to noir's
`TextStyle`; it is left out because noir's API may still change.

```dart
import 'package:noir/noir.dart';
import 'package:syntax/syntax.dart' as syntax;

final class SyntaxCodeHighlighter implements CodeHighlighter {
  SyntaxCodeHighlighter(this.highlighter, this.theme);

  final syntax.Highlighter highlighter;
  final syntax.SyntaxTheme theme;
  final _documents = <String, syntax.TokenizedDocument>{};

  @override
  List<StyledTextRange> highlight(String source, {String? language}) {
    final lang = language == null ? null : highlighter.language(language);
    if (lang == null) return const [];
    final grammar = highlighter.grammar(lang.scopeName);
    final document = _documents[lang.scopeName] ??=
        syntax.TokenizedDocument(grammar);
    document
      ..grammar = grammar
      ..update(source); // re-tokenizes only the edited lines
    return [
      for (final r in document.ranges(theme))
        StyledTextRange(start: r.start, end: r.end, style: _style(r.style)),
    ];
  }
}
```

`StyledRange`s already meet noir's validation: they are sorted,
non-overlapping and non-empty, within bounds, and never cross a line break.

Noir also exports `DiffLine`, `DiffHunk` and `DiffLineKind`, so the adapter
imports `syntax` with a prefix, as above.

Noir's `DiffView` has its own diff model. `syntax_noir` can either pass our
highlighter to it, or paint `layoutDiff` rows for the same features as
`PatchView`: word-level highlights and expandable unchanged lines. That
choice belongs to `syntax_noir`. The core supports both.

## Options considered

- **Keep the logic in each renderer.** This means less public API in core,
  but every renderer re-implements the patch layout and the incremental
  tokenizer, and their bugs.
- **Core owns all non-painting logic (chosen).** Renderers stay thin, and
  the logic is tested once, in plain Dart, without widget tests. The cost is
  that `DiffRow`, `TokenizedDocument` and friends are now public contracts.
- **A full renderer interface in core**, such as `abstract class
  SyntaxRenderer`. Flutter and a terminal framework share too little at the
  painting level for one interface to help, so data types are the
  contract instead.

## Consequences

- A new renderer maps rows and segments to its own widgets. It never
  computes line numbers, gaps or word ranges.
- The core's public surface is larger, and changes to the row types or
  `TokenizedDocument` affect every renderer.
- Layout behavior is tested in `packages/syntax/test`. That includes a
  property test that expanding every gap rebuilds both files.

## Reconsider when

- A renderer needs something the core can't express neutrally, such as
  measured text widths for wrapping or bidirectional text.
- Noir's `CodeHighlighter` gains incremental or streaming semantics that
  `TokenizedDocument.update` with the whole source doesn't fit.
- Very large patches need the layout to be lazy, producing rows on demand
  instead of as one list.
