import 'dart:math' as math;

import 'package:noir/noir.dart';

/// Measures a custom annotation in terminal rows at the supplied cell width.
typedef AnnotationRowCount<T> = int Function(T annotation, int width);

/// Builds one visible row of a custom annotation without building hidden rows.
typedef AnnotationRowBuilder<T> =
    Widget Function(BuildContext context, T annotation, int row, int width);

/// Wraps plain annotation text at grapheme boundaries, preserving explicit lines.
List<String> annotationLines(Object? data, int width) {
  width = math.max(1, width);
  final result = <String>[];
  for (final line in '$data'.split(RegExp(r'\r\n|\r|\n'))) {
    final safe = line
        .replaceAll('\t', '    ')
        .replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), '�');
    final map = TextIndexMap(safe);
    var text = StringBuffer(), cells = 0;
    for (var i = 0; i < map.graphemeCount; i++) {
      final grapheme = safe.substring(
        map.graphemeToUtf16(i),
        map.graphemeToUtf16(i + 1),
      );
      final size = terminalStringWidth(grapheme);
      if (cells + size > width && text.isNotEmpty) {
        result.add(text.toString());
        text = StringBuffer();
        cells = 0;
      }
      text.write(size > width ? '�' : grapheme);
      cells += math.min(size, width);
    }
    result.add(text.toString());
  }
  return result;
}

/// Measures custom rows or the default wrapped text without creating widgets.
int annotationHeight<T>(
  T annotation,
  Object? data,
  int width,
  AnnotationRowCount<T>? count,
  bool legacyBuilder,
) => math.max(
  1,
  count?.call(annotation, width) ??
      (legacyBuilder ? 1 : annotationLines(data, width).length),
);

/// Builds the requested annotation row using its configured presentation.
Widget annotationRow<T>(
  BuildContext context,
  T annotation,
  Object? data,
  int row,
  int width,
  AnnotationRowBuilder<T>? builder,
  Widget Function(BuildContext, T)? legacyBuilder,
) =>
    builder?.call(context, annotation, row, width) ??
    legacyBuilder?.call(context, annotation) ??
    Text(
      annotationLines(data, width).elementAtOrNull(row) ?? '',
      softWrap: false,
      maxLines: 1,
    );
