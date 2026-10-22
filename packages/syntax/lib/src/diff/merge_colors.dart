import '../theme/theme.dart';
import 'review.dart';

/// Opaque presentation colors for one side of a merge conflict.
final class MergeSectionColors {
  /// Colors resolved against the editor background.
  const MergeSectionColors({
    required this.background,
    required this.header,
    required this.border,
  });

  /// Subtle background behind source lines.
  final int background;

  /// Stronger background behind the section's label and actions.
  final int header;

  /// Visible side indicator.
  final int border;
}

/// Theme-aware current, incoming and common-ancestor section colors.
final class MergeColors {
  /// Reads standard `merge.*` editor colors, with light/dark fallbacks.
  factory MergeColors.of(SyntaxTheme theme) {
    MergeSectionColors section(String name, int accent) {
      final header =
          theme.editorColor('merge.${name}HeaderBackground') ??
          (0x44000000 | accent & 0xffffff);
      final content =
          theme.editorColor('merge.${name}ContentBackground') ??
          (0x22000000 | accent & 0xffffff);
      return MergeSectionColors(
        background: alphaBlend(content, theme.background),
        header: alphaBlend(header, theme.background),
        border: alphaBlend(
          theme.editorColor('merge.border') ?? accent,
          theme.background,
        ),
      );
    }

    return MergeColors._(
      section('current', theme.isDark ? 0xff3fb59b : 0xff10795f),
      section('incoming', theme.isDark ? 0xff599cf5 : 0xff205fb1),
      section('common', theme.isDark ? 0xffa3a0b2 : 0xff636074),
    );
  }

  const MergeColors._(this.current, this.incoming, this.base);

  /// Current branch colors.
  final MergeSectionColors current;

  /// Incoming branch colors.
  final MergeSectionColors incoming;

  /// Common ancestor colors.
  final MergeSectionColors base;

  /// Selects the palette for a parsed source section.
  MergeSectionColors forSection(MergeSectionKind kind) => switch (kind) {
    MergeSectionKind.current => current,
    MergeSectionKind.incoming => incoming,
    MergeSectionKind.base => base,
  };
}
