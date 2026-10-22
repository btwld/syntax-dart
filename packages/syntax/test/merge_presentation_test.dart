import 'package:syntax/syntax.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:test/test.dart';

void main() {
  test('section ranges cover exact diff3 markers and CRLF source', () {
    const source =
        'before😀\r\n<<<<<<< ours\r\ncurrent\r\n'
        '||||||| ancestor\r\nbase\r\n=======\r\nincoming\r\n'
        '>>>>>>> theirs\r\nafter';
    final merge = MergeController(
      const SourceFile(id: 'a', path: 'a.dart', text: source),
    );
    final sections = merge.conflicts.single.sections;
    expect(sections.map((s) => s.kind), [
      MergeSectionKind.current,
      MergeSectionKind.base,
      MergeSectionKind.incoming,
    ]);
    expect(
      source.substring(sections[0].start, sections[0].end),
      '<<<<<<< ours\r\ncurrent\r\n',
    );
    expect(
      source.substring(sections[1].start, sections[1].end),
      '||||||| ancestor\r\nbase\r\n',
    );
    expect(
      source.substring(sections[2].start, sections[2].end),
      '=======\r\nincoming\r\n>>>>>>> theirs\r\n',
    );
    for (final section in sections) {
      expect(merge.sectionAt(section.start), same(section));
      expect(merge.sectionAt(section.end - 1), same(section));
    }
    expect(merge.sectionAt(0), isNull);
    expect(merge.sectionAt(sections.last.end), isNull);
    merge.dispose();
  });

  test('empty sections and sequential resolutions update section lookup', () {
    const conflict = '<<<<<<< ours\n=======\nb\n>>>>>>> theirs\n';
    final merge = MergeController(
      const SourceFile(id: 'a', path: 'a', text: '$conflict\n$conflict'),
    );
    expect(merge.conflicts.first.sections, hasLength(2));
    merge.resolve(0, ChangeResolution.old);
    expect(merge.file.text, '\n$conflict');
    expect(merge.sectionAt(0), isNull);
    expect(merge.sectionAt(1)!.kind, MergeSectionKind.current);
    merge.resolve(0, ChangeResolution.newer);
    expect(merge.file.text, '\nb\n');
    expect(merge.sectionAt(1), isNull);
    merge.dispose();
  });

  test('merge palettes stay distinct in light/dark and honor theme colors', () {
    for (final theme in [githubDarkTheme, githubLightTheme]) {
      final colors = MergeColors.of(theme);
      final backgrounds = MergeSectionKind.values
          .map((kind) => colors.forSection(kind).background)
          .toSet();
      expect(backgrounds, hasLength(3));
      expect(backgrounds, isNot(contains(theme.background)));
      expect(backgrounds.every((color) => color >> 24 == 255), isTrue);
    }
    final theme = SyntaxTheme.fromJson({
      'colors': {
        'editor.background': '#102030',
        'merge.currentHeaderBackground': '#ff000080',
        'merge.currentContentBackground': '#00ff0080',
        'merge.incomingContentBackground': '#0000ff80',
        'merge.commonContentBackground': '#ffffff80',
        'merge.border': '#abcdef',
      },
    });
    final colors = MergeColors.of(theme);
    expect(colors.current.header, alphaBlend(0x80ff0000, 0xff102030));
    expect(colors.current.background, alphaBlend(0x8000ff00, 0xff102030));
    expect(colors.incoming.background, alphaBlend(0x800000ff, 0xff102030));
    expect(colors.base.background, alphaBlend(0x80ffffff, 0xff102030));
    expect(colors.current.border, 0xffabcdef);
  });
}
