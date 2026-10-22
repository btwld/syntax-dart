import 'dart:async';
import 'dart:convert';

import 'package:syntax/syntax.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/catalog.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:test/test.dart';

void main() {
  test('line identities follow insertions and undo restores them', () {
    final doc = TextDocument('one\r\ntwo\rthree\nfour');
    final identity = doc.lineIdentity(2);
    doc.applyOffsetEdits([const OffsetEdit(0, 0, 'new\n')]);
    expect(doc.lineForIdentity(identity), 3);
    expect(doc.lineIdentity(3), same(identity));
    doc.undo();
    expect(doc.lineForIdentity(identity), 2);
    doc.applyOffsetEdits([
      OffsetEdit(doc.lineStart(2), doc.lineStart(2) + 1, 'T'),
    ]);
    expect(doc.lineForIdentity(identity), isNull);
    doc.dispose();
  });
  test('incremental index handles every CRLF edit boundary', () {
    const initial = 'a\r\nb\rc\n😀\r\n';
    for (var start = 0; start <= initial.length; start++) {
      for (var end = start; end <= initial.length; end++) {
        for (final replacement in ['', '\r', '\n', '\r\n', 'x\r\ny']) {
          final doc = TextDocument(initial);
          doc.lineCount;
          doc.applyOffsetEdits([OffsetEdit(start, end, replacement)]);
          final expected = TextDocument(
            initial.replaceRange(start, end, replacement),
          );
          expect(doc.lineCount, expected.lineCount);
          for (var line = 0; line < doc.lineCount; line++) {
            expect(doc.lineStart(line), expected.lineStart(line));
            expect(
              doc.lineText(line, includeTerminator: true),
              expected.lineText(line, includeTerminator: true),
            );
          }
          doc.dispose();
          expected.dispose();
        }
      }
    }
  });
  test(
    'retained review drafts are bounded and reject stale completions',
    () async {
      final controller = PatchController([
        for (var i = 0; i < 3; i++) diffTexts('a\n', 'b\n', id: '$i'),
      ], sessionLimit: 1);
      final first = controller.beginEdit('0');
      controller.releaseEdit('0');
      final active = controller.beginEdit('1');
      controller.beginEdit('2');
      controller.releaseEdit('2');
      expect(first.isDisposed, isTrue);
      expect(active.isDisposed, isFalse);
      controller.updateFile(diffTexts('other\n', 'new\n', id: '1'));
      await expectLater(controller.completeEdit('1'), throwsStateError);
      controller.dispose();
      expect(active.isDisposed, isTrue);
    },
  );
  test('individual block actions leave the neighboring change intact', () {
    final controller = PatchController([
      diffTexts(
        'a\nold\ncontext\nold2\nz\n',
        'a\nnew\ncontext\nnew2\nz\n',
        id: 'f',
        contextLines: 3,
      ),
    ]);
    final block = controller.changeAt('f', 4)!;
    expect(block.change, 1);
    controller.resolve(
      'f',
      block.hunk,
      ChangeResolution.old,
      changeIndex: block.change,
    );
    expect(controller.files.single.newText, 'a\nnew\ncontext\nold2\nz\n');
    expect(controller.files.single.additions, 1);
    controller.dispose();
  });
  test(
    'decoding failures complete the bound stream with an observable error',
    () async {
      final controller = StreamDocumentController(
        const SourceFile(id: 's', path: '', text: ''),
      );
      await expectLater(
        controller.bind(
          Stream<Object>.fromIterable([
            [255],
          ]),
        ),
        throwsFormatException,
      );
      expect(controller.error, isA<FormatException>());
      expect(controller.isCancelled, isTrue);
      controller.dispose();
    },
  );
  test('theme changes reuse diff presentation and preserve raw boundaries', () {
    final highlighter = Highlighter(languages: [dartLanguage]);
    final diff = diffTexts('final n = 1;\n', 'final n = 2;\n', path: 'a.dart');
    final cache = DiffHighlightCache(
      highlighter: highlighter,
      theme: githubDarkTheme,
    );
    final presentation = cache.highlighted(diff);
    final before = presentation.newLine(1);
    cache.theme = githubLightTheme;
    expect(cache.highlighted(diff), same(presentation));
    final after = presentation.newLine(1);
    expect(after.map((token) => token.text), before.map((token) => token.text));
    expect(
      after.map((token) => token.scopes),
      before.map((token) => token.scopes),
    );
    expect(
      after.map((token) => token.style),
      isNot(before.map((token) => token.style)),
    );
  });
  test(
    'catalog metadata is lazy and accessible variants retain contrast',
    () async {
      expect(bundledThemeCollection.entries, hasLength(65));
      expect(bundledThemeCollection.where(isDark: false).entries, isNotEmpty);
      final resolver = ThemeResolver();
      bundledThemeCollection.pick(['github-dark']).registerInto(resolver);
      expect((await resolver.resolve('github-dark')).isDark, isTrue);
      for (final dark in [false, true]) {
        for (final variant in SyntaxPaletteVariant.values) {
          final theme = createSyntaxTheme(dark: dark, variant: variant);
          expect(
            contrastRatio(theme.foreground, theme.background),
            greaterThanOrEqualTo(7),
          );
          for (final scope in ['keyword', 'string', 'comment']) {
            expect(
              contrastRatio(
                theme.styleFor(ScopeStack.root(scope)).foreground,
                theme.background,
              ),
              greaterThanOrEqualTo(4.5),
            );
          }
          final colors = DiffColors.of(theme);
          expect(colors.inserted, isNot(colors.removed));
        }
      }
    },
  );
  test(
    'compound extension overrides and filename aliases are deterministic',
    () {
      final highlighter = Highlighter(languages: [dartLanguage]);
      highlighter.setLanguageForPath('.config.custom', 'dart');
      expect(
        highlighter.languageForPath('src/app.config.custom'),
        dartLanguage,
      );
      highlighter.setLanguageForPath('BUILD', 'dart');
      expect(highlighter.languageForPath('src/BUILD'), dartLanguage);
    },
  );
  test('untyped decoded recursive grammars preserve rule identity', () {
    Object? untyped(Object? value) => value is Map
        ? <Object?, Object?>{
            for (final entry in value.entries) entry.key: untyped(entry.value),
          }
        : value is List
        ? value.map(untyped).toList()
        : value;
    final decoded = Map<String, Object?>.from(
      untyped(jsonDecode(jsonEncode(dartLanguage.grammar))) as Map,
    );
    final highlighter = Highlighter(
      languages: [Language.fromJson(decoded, name: 'dart')],
    );
    expect(
      highlighter
          .highlight('final n = 1;', language: 'dart', theme: githubDarkTheme)
          .single
          .map((t) => t.text)
          .join(),
      'final n = 1;',
    );
  });
  test('separate selected line groups move and duplicate atomically', () {
    final editor = EditorController(
      file: const SourceFile(id: 'lines', path: '', text: 'a\r\nb\nc\rd'),
    );
    editor.setSelections([
      DocumentSelection.collapsed(editor.document.lineStart(1)),
      DocumentSelection.collapsed(editor.document.lineStart(3)),
    ]);
    editor.execute(EditorCommand.moveLineUp);
    expect(editor.document.text, 'b\r\na\nd\rc');
    editor.undo();
    expect(editor.document.text, 'a\r\nb\nc\rd');
    editor.execute(EditorCommand.copyLineDown);
    expect(editor.document.text, 'a\r\nb\nb\nc\rd\r\nd');
    editor.dispose();
  });
  test(
    'mailbox commits give repeated file paths distinct review identities',
    () {
      final first = renderPatch(diffTexts('a\n', 'b\n', path: 'same.dart'));
      final second = renderPatch(diffTexts('b\n', 'c\n', path: 'same.dart'));
      final commits = parsePatchDocuments(
        'commit aaaaaaa\nFirst change\n$first'
        'commit bbbbbbb\nSecond change\n$second',
      );
      final controller = PatchController(
        commits.expand((commit) => commit.files),
      );
      expect(commits, hasLength(2));
      expect(commits.first.introduction, contains('First change'));
      expect(controller.files.map((file) => file.id).toSet(), hasLength(2));
      expect(controller.files.map((file) => file.path), [
        'same.dart',
        'same.dart',
      ]);
      controller.dispose();
    },
  );
}
