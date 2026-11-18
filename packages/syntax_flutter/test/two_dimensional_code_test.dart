import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_core/themes/github_dark.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

void main() {
  testWidgets('reveal stays inside a shared two-dimensional viewport', (
    tester,
  ) async {
    final lines = List.generate(150, (i) => 'line $i ${'long ' * 100}');
    final source = CodeViewController(sourceId: 'a', code: lines.join('\n'));
    final vertical = ScrollController();
    final horizontal = ScrollController(initialScrollOffset: 30);
    addTearDown(source.dispose);
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);
    final delegate = TwoDimensionalChildBuilderDelegate(
      maxXIndex: 0,
      maxYIndex: 0,
      builder: (context, vicinity) => HighlightedCode.controlled(
        controller: source,
        language: 'text',
        theme: githubDarkTheme,
        highlighter: Highlighter(),
        lineNumbers: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TwoDimensionalScrollable(
          horizontalDetails: ScrollableDetails.horizontal(
            controller: horizontal,
          ),
          verticalDetails: ScrollableDetails.vertical(controller: vertical),
          viewportBuilder: (context, verticalOffset, horizontalOffset) =>
              _SourceViewport(
                verticalOffset: verticalOffset,
                horizontalOffset: horizontalOffset,
                delegate: delegate,
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(vertical.offset, 0);
    source.revealLine(100);
    await tester.pumpAndSettle();
    expect(vertical.offset, greaterThan(0));
    final viewport = tester.getRect(find.byType(_SourceViewport));
    final line = tester.getRect(find.text(lines[100], findRichText: true));
    expect(line.top, greaterThanOrEqualTo(viewport.top));
    expect(line.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(horizontal.offset, 30);
    final horizontalPositions =
        tester
            .stateList<ScrollableState>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.right,
              ),
            )
            .map((state) => state.position.pixels)
            .toList()
          ..sort();
    expect(horizontalPositions, [0, 30]);
    expect(tester.takeException(), isNull);
  });
}

// One unbounded-height source cell in a real shared render viewport. Both
// ScrollPositions belong to this viewport, rather than nested 1D viewports.
class _SourceViewport extends TwoDimensionalViewport {
  const _SourceViewport({
    required super.verticalOffset,
    required super.horizontalOffset,
    required super.delegate,
  }) : super(
         verticalAxisDirection: AxisDirection.down,
         horizontalAxisDirection: AxisDirection.right,
         mainAxis: Axis.vertical,
       );

  @override
  RenderTwoDimensionalViewport createRenderObject(BuildContext context) =>
      _RenderSourceViewport(
        verticalOffset: verticalOffset,
        horizontalOffset: horizontalOffset,
        delegate: delegate,
        childManager: context as TwoDimensionalChildManager,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTwoDimensionalViewport renderObject,
  ) {
    renderObject
      ..verticalOffset = verticalOffset
      ..horizontalOffset = horizontalOffset
      ..delegate = delegate;
  }
}

class _RenderSourceViewport extends RenderTwoDimensionalViewport {
  _RenderSourceViewport({
    required super.verticalOffset,
    required super.horizontalOffset,
    required super.delegate,
    required super.childManager,
  }) : super(
         verticalAxisDirection: AxisDirection.down,
         horizontalAxisDirection: AxisDirection.right,
         mainAxis: Axis.vertical,
       );

  @override
  void layoutChildSequence() {
    final child = buildOrObtainChildFor(
      const ChildVicinity(xIndex: 0, yIndex: 0),
    )!;
    child.layout(
      const BoxConstraints.tightFor(width: 1000),
      parentUsesSize: true,
    );
    parentDataOf(child).layoutOffset = Offset(
      -horizontalOffset.pixels,
      -verticalOffset.pixels,
    );
    horizontalOffset.applyContentDimensions(
      0,
      math.max(0, child.size.width - size.width),
    );
    verticalOffset.applyContentDimensions(
      0,
      math.max(0, child.size.height - size.height),
    );
  }
}
