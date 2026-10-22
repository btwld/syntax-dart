import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syntax/syntax.dart';

/// Immutable file selection passed to application-owned review actions.
///
/// Check [file]'s identity and revision before applying an asynchronous result.
final class FileSelectionDetails {
  /// Captures a source snapshot and its directed UTF-16 selection.
  const FileSelectionDetails({
    required this.file,
    required this.selection,
    required this.anchorLine,
    required this.activeLine,
  });

  /// Source identity, revision and contents when the action was built.
  final SourceFile file;

  /// Directed, half-open UTF-16 offsets into [file].
  final DocumentSelection selection;

  /// Zero-based fixed endpoint line.
  final int anchorLine;

  /// Zero-based moving endpoint line, where the action is displayed.
  final int activeLine;

  /// First selected zero-based line, inclusive.
  int get startLine => anchorLine < activeLine ? anchorLine : activeLine;

  /// Last selected zero-based line, inclusive.
  int get endLine => anchorLine > activeLine ? anchorLine : activeLine;

  /// Selected source without line numbers, annotations or other decorations.
  String get selectedText =>
      file.text.substring(selection.start, selection.end);
}

/// Immutable diff selection passed to application-owned review actions.
///
/// [selection] preserves both sides and direction. Check [file]'s identity and
/// revision before applying an asynchronous result.
final class DiffSelectionDetails {
  /// Captures the file revision and its directed, one-based line selection.
  const DiffSelectionDetails({required this.file, required this.selection});

  /// Source snapshot when the action was built; it may be a partial patch.
  final FileDiff file;

  /// Inclusive one-based endpoints, including the active endpoint's side.
  final DiffSelection selection;
}

/// Presentation and keyboard bindings for a selection's comment action.
///
/// A view's `selectionActionBuilder` can replace the entire action or return
/// null to hide it. Applications own comment forms, persistence and permissions.
@immutable
class SelectionActionStyle {
  /// Creates a compact gutter action, with Ctrl/Cmd+Shift+M as its shortcut.
  const SelectionActionStyle({
    this.icon = const Icon(Icons.add_comment_outlined, size: 14),
    this.tooltip = 'Comment on selected lines',
    this.buttonStyle,
    this.alignment = Alignment.topLeft,
    this.size = 20,
    this.gutterWidth = 24,
    this.shortcuts = const [
      SingleActivator(LogicalKeyboardKey.keyM, control: true, shift: true),
      SingleActivator(LogicalKeyboardKey.keyM, meta: true, shift: true),
    ],
  }) : assert(size > 0),
       assert(gutterWidth >= 0);

  /// Icon for the built-in button.
  final Widget icon;

  /// Localizable tooltip and accessible name for the built-in button.
  final String tooltip;

  /// Optional Material button colors, border, shape and other style overrides.
  final ButtonStyle? buttonStyle;

  /// Placement within the active source row (within its pane in split diffs).
  final Alignment alignment;

  /// Preferred button extent, constrained to the row's height.
  final double size;

  /// Reserved space before line numbers, keeping the action clear of source.
  /// Increase for wider custom actions, or use zero with trailing alignment.
  final double gutterWidth;

  /// Comment shortcuts while the view has focus. Pass an empty list to disable.
  /// These invoke `onComment`, independently of a custom action builder.
  final List<ShortcutActivator> shortcuts;
}
