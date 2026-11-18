import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'patch_composition_test.dart' show app;

void main() {
  testWidgets('cancelled source reveal stops frames and ancestor navigation', (
    tester,
  ) async {
    final controller = CodeViewController(
      sourceId: 'source',
      code: List.generate(3000, (i) => 'line $i').join('\n'),
    );
    final outer = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(outer.dispose);
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          controller: outer,
          child: Column(
            children: [
              const SizedBox(height: 600),
              SizedBox(
                height: 200,
                child: HighlightedCode.controlled(
                  controller: controller,
                  highlighter: Highlighter(),
                  language: 'text',
                  theme: githubDarkTheme,
                  padding: EdgeInsets.zero,
                  selectable: false,
                ),
              ),
              const SizedBox(height: 600),
            ],
          ),
        ),
        height: 600,
      ),
    );
    await tester.pumpAndSettle();
    final viewport = tester.widget<IndexedCodeViewport>(
      find.byType(IndexedCodeViewport),
    );
    controller.revealLine(2000);
    await tester.pump(); // Run the indexed jump, before the target lays out.
    final destination = viewport.controller.offset;
    expect(destination, greaterThan(0));
    expect(find.text('line 2000', findRichText: true), findsNothing);
    expect(outer.offset, 0);
    viewport.controller.jumpTo(0); // Cancel the active indexed reveal.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final idle = !SchedulerBinding.instance.hasScheduledFrame;
    // Later ordinary navigation mounts the former target. The retired reveal
    // must not take this opportunity to scroll the enclosing view.
    viewport.controller.jumpTo(destination);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('line 2000', findRichText: true), findsOneWidget);
    final outerOffset = outer.offset;
    debugPrint('cancelled source reveal: idle=$idle outer=$outerOffset');
    controller.revealLine(
      2000,
    ); // A fresh successful request still reveals once.
    await tester.pumpAndSettle();
    final successfulOffset = outer.offset;
    await tester.pumpWidget(const SizedBox());
    expect(
      (idle, outerOffset),
      (true, 0.0),
      reason: 'Cancellation must retire frames and ancestor navigation',
    );
    expect(successfulOffset, greaterThan(0));
  });
}
