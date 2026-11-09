import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'material_free_test.dart' show expectPlainTree;
import 'patch_composition_test.dart' show app;

bool addresses(DiffRow row, int lineNumber) => switch (row) {
  DiffLineRow(:final line) => line.newNumber == lineNumber,
  DiffPairRow(:final right) => right?.newNumber == lineNumber,
  _ => false,
};

void main() {
  for (final mode in DiffMode.values) {
    testWidgets(
      'source shrink rows retain a draft across gap expansion $mode',
      (tester) async {
        final before = List.generate(18, (i) => 'line ${i + 1}').join('\n');
        final file = diffTexts(
          before,
          before.replaceFirst('line 8', 'changed 8'),
          path: 'gap.txt',
          contextLines: 1,
        );
        final expanded = <DiffGapId>{};
        final highlighter = Highlighter();
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (_, update) {
                return PatchView<void>(
                  files: [file],
                  mode: mode,
                  theme: githubDarkTheme,
                  highlighter: highlighter,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  leading: const SizedBox(height: 20),
                  expanded: expanded,
                  onExpandGap: (id) => update(() => expanded.add(id)),
                  rowBelowBuilder: (_, row) =>
                      addresses(row.row, 9) ? const _Draft() : null,
                );
              },
            ),
            height: 600,
          ),
        );
        await tester.pumpAndSettle();
        final draft = tester.state<_DraftState>(find.byType(_Draft));
        await tester.enterText(find.byType(EditableText), 'unfinished comment');
        await tester.tap(find.text('Show 6 unchanged lines'));
        await tester.pumpAndSettle();
        expect(expanded, contains((file: 0, hunk: 0)));
        expect(tester.state<_DraftState>(find.byType(_Draft)), same(draft));
        expect(draft.text.text, 'unfinished comment');
        expectPlainTree(tester);
      },
    );

    testWidgets(
      'source shrink rows retain a later draft when an earlier file folds $mode',
      (tester) async {
        final first = diffTexts(
          '',
          'early one\nearly two\n',
          path: 'first.txt',
        );
        final later = diffTexts('', 'later\n', path: 'later.txt');
        final collapsed = <int>{};
        final highlighter = Highlighter();
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (_, update) {
                return PatchView<void>(
                  files: [first, later],
                  mode: mode,
                  theme: githubDarkTheme,
                  highlighter: highlighter,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  collapsed: collapsed,
                  onToggleFile: (index) => update(() => collapsed.add(index)),
                  headerBuilder: (_, file, _, toggle) => GestureDetector(
                    onTap: toggle,
                    child: SizedBox(
                      height: 32,
                      child: Text('Fold ${file.path}'),
                    ),
                  ),
                  rowBelowBuilder: (_, row) =>
                      row.file.id == later.id && addresses(row.row, 1)
                      ? const _Draft()
                      : null,
                );
              },
            ),
            height: 600,
          ),
        );
        await tester.pumpAndSettle();
        final draft = tester.state<_DraftState>(find.byType(_Draft));
        await tester.enterText(find.byType(EditableText), 'unfinished comment');
        await tester.tap(find.text('Fold first.txt'));
        await tester.pumpAndSettle();
        expect(collapsed, contains(0));
        expect(tester.state<_DraftState>(find.byType(_Draft)), same(draft));
        expect(draft.text.text, 'unfinished comment');
        expectPlainTree(tester);
      },
    );

    testWidgets(
      'LayoutBuilder gutter has finite row constraints and a full-height hit target $mode',
      (tester) async {
        final code = List.filled(12, 'wrapped words').join(' ');
        final file = diffTexts('', '$code\n', path: 'wrapped.txt');
        final constraints = <BoxConstraints>[];
        DiffSelection? selected;
        await tester.pumpWidget(
          app(
            PatchView<void>(
              files: [file],
              mode: mode,
              theme: githubDarkTheme,
              highlighter: Highlighter(),
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              onSelectionChanged: (value) => selected = value,
              gutterBuilder: (_, line) => LayoutBuilder(
                builder: (_, size) {
                  constraints.add(size);
                  return SizedBox.expand(
                    key: ValueKey('slot-${line.side.name}-${line.line}'),
                    child: const ColoredBox(color: Color(0xff445566)),
                  );
                },
              ),
            ),
            height: 600,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(constraints, isNotEmpty);
        expect(
          constraints.every(
            (size) => size.maxWidth == 24 && size.hasBoundedHeight,
          ),
          isTrue,
        );
        final marker = tester.getRect(
          find.byKey(const ValueKey('slot-newer-1')),
        );
        final text = tester.getRect(find.text(code, findRichText: true));
        expect(text.height, greaterThan(21));
        expect(marker.height, closeTo(text.height, .1));
        await tester.tapAt(Offset(marker.center.dx, marker.bottom - 2));
        await tester.pumpAndSettle();
        expect(selected?.fileId, file.id);
        expect(selected?.side, DiffSide.newer);
        expect(selected?.active, 1);
        expectPlainTree(tester);
      },
    );

    testWidgets(
      'caller gutter semantics survive for context and changed lines $mode',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final file = diffTexts(
            'context\nbefore\nlast\n',
            'context\nchanged\nlast\n',
            path: 'semantics.txt',
          );
          await tester.pumpWidget(
            app(
              PatchView<void>(
                files: [file],
                mode: mode,
                theme: githubDarkTheme,
                highlighter: Highlighter(),
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                gutterBuilder: (_, line) => Semantics(
                  container: true,
                  label: 'status ${line.side.name} ${line.line}',
                  button: true,
                  onTap: () {},
                  child: const SizedBox(width: 12, height: 12),
                ),
              ),
              height: 600,
            ),
          );
          await tester.pumpAndSettle();
          final coordinates = [
            if (mode == DiffMode.split) (DiffSide.old, 1),
            (DiffSide.newer, 1),
            (DiffSide.old, 2),
            (DiffSide.newer, 2),
            if (mode == DiffMode.split) (DiffSide.old, 3),
            (DiffSide.newer, 3),
          ];
          for (final (side, line) in coordinates) {
            final marker = find.bySemanticsLabel('status ${side.name} $line');
            expect(marker, findsOneWidget);
            final data = tester.getSemantics(marker).getSemanticsData();
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          }
          expectPlainTree(tester);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}

class _Draft extends StatefulWidget {
  const _Draft();
  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  final text = TextEditingController();
  final focus = FocusNode();
  @override
  Widget build(BuildContext context) => EditableText(
    controller: text,
    focusNode: focus,
    style: const TextStyle(fontSize: 14, color: Color(0xffffffff)),
    cursorColor: const Color(0xffffffff),
    backgroundCursorColor: const Color(0xff000000),
  );
  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }
}
