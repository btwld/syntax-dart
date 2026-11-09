import 'package:flutter/widgets.dart';
import 'package:syntax_core/syntax.dart';

import 'chrome.dart';
import 'chrome_action.dart';
import 'selection_chrome.dart';
import 'styles.dart';

/// Owns the focus node used by a code surface's selection region.
class SyntaxSelectableRegion extends StatefulWidget {
  /// Makes [child] selectable with optional injected controls.
  const SyntaxSelectableRegion({
    super.key,
    required this.theme,
    required this.chrome,
    required this.child,
  });

  /// Palette for selection overlays.
  final SyntaxTheme theme;

  /// Caller controls or null for plain defaults.
  final SyntaxSelectionChrome? chrome;

  /// Selectable content.
  final Widget child;

  @override
  State<SyntaxSelectableRegion> createState() => _SyntaxSelectableRegionState();
}

class _SyntaxSelectableRegionState extends State<SyntaxSelectableRegion> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = widget.chrome ?? SyntaxSelectionChrome.plain;
    return SelectableRegion(
      focusNode: _focus,
      selectionControls: chrome.selectionControls,
      contextMenuBuilder: (context, state) =>
          chrome.contextMenuBuilder?.call(context, state) ??
          _plainMenu(context, state, chrome, widget.theme),
      child: widget.child,
    );
  }
}

Widget _plainMenu(
  BuildContext context,
  SelectableRegionState state,
  SyntaxSelectionChrome chrome,
  SyntaxTheme theme,
) {
  final localizations = WidgetsLocalizations.of(context);
  return CustomSingleChildLayout(
    delegate: TextSelectionToolbarLayoutDelegate(
      anchorAbove: state.contextMenuAnchors.primaryAnchor,
      anchorBelow:
          state.contextMenuAnchors.secondaryAnchor ??
          state.contextMenuAnchors.primaryAnchor,
    ),
    child: SyntaxChrome(
      theme: theme,
      selectionChrome: chrome,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.foregroundColor),
        ),
        child: FocusScope(
          child: DefaultTextStyle(
            // Overlay text must not inherit an application's fallback style.
            style: TextStyle(
              inherit: false,
              color: theme.foregroundColor,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.25,
              decoration: TextDecoration.none,
            ),
            child: Builder(
              builder: (context) => Wrap(
                children: [
                  for (final item in state.contextMenuButtonItems)
                    if (item.type == ContextMenuButtonType.copy ||
                        item.type == ContextMenuButtonType.selectAll)
                      buildSyntaxAction(
                        context,
                        chrome,
                        SyntaxChromeAction(
                          kind: item.type == ContextMenuButtonType.copy
                              ? SyntaxChromeActionKind.copy
                              : SyntaxChromeActionKind.selectAll,
                          label: item.type == ContextMenuButtonType.copy
                              ? localizations.copyButtonLabel
                              : localizations.selectAllButtonLabel,
                          onInvoke: item.onPressed,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            item.type == ContextMenuButtonType.copy
                                ? localizations.copyButtonLabel
                                : localizations.selectAllButtonLabel,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
