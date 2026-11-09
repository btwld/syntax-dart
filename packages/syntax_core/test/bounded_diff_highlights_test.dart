import 'package:syntax_core/langs/dart.dart';
import 'package:syntax_core/syntax.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:test/test.dart';

// Generic retention cases transferred from code_review_flutter's bounded cache.
void main() {
  DiffHighlightCache cache({int entries = 8, int units = 1024 * 1024}) =>
      DiffHighlightCache(
        highlighter: Highlighter(languages: [dartLanguage]),
        theme: githubDarkTheme,
        maxEntries: entries,
        maxCodeUnits: units,
      );
  FileDiff file(String id, [int revision = 0]) => diffTexts(
    'final value = 0;',
    'final value = $revision;',
    path: '$id.dart',
    id: id,
    revision: revision,
  );

  test('a filtered file reuses syntax and word changes on revisit', () {
    final a = file('a'), b = file('b');
    final highlights = cache();
    final syntax = highlights.highlighted(b);
    final words = highlights.words(b);
    highlights.highlighted(a);
    expect(highlights.highlighted(b), same(syntax));
    expect(highlights.words(b), same(words));
  });

  test('replacement content and revision never reuse a stale entry', () {
    final a = file('a'), replacement = file('a', 1);
    final highlights = cache();
    final old = highlights.highlighted(a);
    expect(highlights.highlighted(replacement), isNot(same(old)));
    final changed = replacement.hunks.single.lines.last;
    expect(
      highlights.segmentsFor(replacement, changed).map((s) => s.text).join(),
      changed.text,
    );
  });

  test('LRU evicts syntax and words together', () {
    final a = file('a'), b = file('b'), c = file('c');
    final highlights = cache(entries: 2);
    final first = highlights.highlighted(a);
    final second = highlights.highlighted(b);
    final words = highlights.words(b);
    expect(highlights.highlighted(a), same(first));
    highlights.highlighted(c);
    expect(highlights.entryCount, 2);
    expect(highlights.highlighted(a), same(first));
    expect(highlights.highlighted(b), isNot(same(second)));
    expect(highlights.words(b), isNot(same(words)));
  });

  test(
    'one oversize file is allowed alone and words alone obey the limits',
    () {
      final highlights = cache(units: 4);
      highlights.words(file('a'));
      highlights.words(file('b'));
      expect(highlights.entryCount, 1);
      expect(highlights.retainedCodeUnits, greaterThan(4));
    },
  );
  test('full source texts are charged once and fit the exact input budget', () {
    const before = 'a🙂\r\nb';
    const after = 'a🙂\r\nc';
    final a = diffTexts(before, after, id: 'a');
    final b = diffTexts(before, after, id: 'b');
    const unitsPerFile = before.length + after.length;
    final highlights = cache(units: unitsPerFile * 2);
    final first = highlights.highlighted(a);
    final words = highlights.words(a);
    expect(highlights.retainedCodeUnits, unitsPerFile);
    highlights.highlighted(b);
    expect(highlights.entryCount, 2);
    expect(highlights.retainedCodeUnits, unitsPerFile * 2);
    expect(highlights.highlighted(a), same(first));
    expect(highlights.words(a), same(words));
    highlights.highlighted(diffTexts(before, after, id: 'c'));
    expect(highlights.entryCount, 2);
    expect(highlights.retainedCodeUnits, unitsPerFile * 2);
    expect(highlights.highlighted(a), same(first));
  });
}
