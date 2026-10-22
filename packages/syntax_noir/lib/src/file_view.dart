import 'package:noir/noir.dart';
import 'package:syntax/syntax.dart' as syntax;
import 'editor.dart';
import 'annotations.dart';

/// Virtualized terminal file view with keyboard selection, search and copy.
class SyntaxFileView extends StatelessWidget {
  /// Displays [controller] without allowing document edits.
  const SyntaxFileView({
    super.key,
    required this.controller,
    required this.highlighter,
    required this.theme,
    this.height,
    this.wrap = false,
    this.autofocus = false,
    this.onCopy = copyTerminalSource,
    this.headerBuilder,
    this.annotationBuilder,
    this.annotationRowBuilder,
    this.annotationRowCount,
    this.onLine,
    this.onToken,
    this.executor,
  });

  /// Shared source, selections, annotations and diagnostics.
  final syntax.EditorController controller;

  /// Registered grammars.
  final syntax.Highlighter highlighter;

  /// Current colors.
  final syntax.SyntaxTheme theme;

  /// Shared background executor; the application retains ownership.
  final syntax.HighlightExecutor? executor;

  /// Total height in terminal rows.
  final int? height;

  /// Wraps by terminal cell width.
  final bool wrap;

  /// Requests initial keyboard focus.
  final bool autofocus;

  /// Explicit source-only copy handler.
  final void Function(String) onCopy;

  /// Custom fixed file header.
  final Widget Function(BuildContext, syntax.SourceFile)? headerBuilder;

  /// Custom annotation presentation.
  final Widget Function(BuildContext, syntax.LineAnnotation<Object?>)?
  annotationBuilder;

  /// Builds each visible annotation row at the current terminal width.
  final AnnotationRowBuilder<syntax.LineAnnotation<Object?>>?
  annotationRowBuilder;

  /// Measures the custom annotation's row count; defaults to wrapped text.
  final AnnotationRowCount<syntax.LineAnnotation<Object?>>? annotationRowCount;

  /// Reports navigation to a zero-based line.
  final void Function(int)? onLine;

  /// Reports Alt+Enter token activation.
  final void Function(int, syntax.ThemedToken)? onToken;
  @override
  Widget build(BuildContext context) => SyntaxEditor(
    controller: controller,
    highlighter: highlighter,
    theme: theme,
    height: height,
    wrap: wrap,
    readOnly: true,
    autofocus: autofocus,
    onCopy: onCopy,
    headerBuilder: headerBuilder,
    annotationBuilder: annotationBuilder,
    annotationRowBuilder: annotationRowBuilder,
    annotationRowCount: annotationRowCount,
    onLine: onLine,
    onToken: onToken,
    executor: executor,
  );
}

/// A flat, keyboard-accessible file collection with retained draft sessions.
class SyntaxFileList extends StatefulWidget {
  /// Files retain their identity and session even when another file is selected.
  const SyntaxFileList({
    super.key,
    required this.controller,
    required this.highlighter,
    required this.theme,
    this.editable = false,
    this.onComplete,
    this.height,
    this.autofocus = false,
    this.wrap = false,
  });

  /// Files and bounded session storage.
  final syntax.FileListController controller;

  /// Registered grammars.
  final syntax.Highlighter highlighter;

  /// Current colors.
  final syntax.SyntaxTheme theme;

  /// Allows editing the selected file.
  final bool editable;

  /// Application decision before a draft replaces its source.
  final Future<bool> Function(syntax.SourceFile)? onComplete;

  /// Total height in terminal rows.
  final int? height;

  /// Requests initial focus in the file chooser.
  final bool autofocus;

  /// Wraps code to the available cell width.
  final bool wrap;
  @override
  State<SyntaxFileList> createState() => _SyntaxFileListState();
}

class _SyntaxFileListState extends State<SyntaxFileList> {
  String? _selected;
  syntax.EditorController? _editor;
  int _revealRequest = -1;
  void _select(String id) {
    if (_selected != id) {
      if (_selected != null) widget.controller.release(_selected!);
      _selected = id;
      _editor = widget.controller.acquire(id);
    }
    if (mounted) setState(() {});
  }

  void _changed() {
    if (_selected != null &&
        !widget.controller.files.any((f) => f.id == _selected)) {
      widget.controller.release(_selected!);
      _selected = null;
      _editor = null;
    }
    final target = widget.controller.revealTarget;
    if (target != null && widget.controller.revealRequest != _revealRequest) {
      _revealRequest = widget.controller.revealRequest;
      _select(target.$1);
      _editor!.reveal(target.$2);
    }
    if (_selected == null && widget.controller.files.isNotEmpty) {
      _select(widget.controller.files.first.id);
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    if (widget.controller.files.isNotEmpty) {
      _select(widget.controller.files.first.id);
    }
    _changed();
  }

  @override
  void didUpdateWidget(SyntaxFileList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      if (_selected != null) oldWidget.controller.release(_selected!);
      _selected = null;
      _editor = null;
      _revealRequest = -1;
      widget.controller.addListener(_changed);
      if (widget.controller.files.isNotEmpty) {
        _select(widget.controller.files.first.id);
      }
      _changed();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = widget.height ?? constraints.maxHeight ?? 24;
      final files = widget.controller.files;
      if (files.isEmpty) return const Text('No files');
      final chooserHeight = files.length.clamp(1, 4);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListView(
            itemCount: files.length,
            height: chooserHeight,
            autofocus: widget.autofocus,
            selectedIndex: files
                .indexWhere((f) => f.id == _selected)
                .clamp(0, files.length - 1),
            onSelect: (index) => _select(files[index].id),
            itemBuilder: (context, index, selected) =>
                Text('${selected ? '▸' : ' '} ${files[index].path}'),
          ),
          if (_editor != null) ...[
            if (widget.controller.hasSourceConflict(_selected!))
              Button(
                label: 'Source changed: reload latest source',
                onPressed: () => widget.controller.reload(_selected!),
              ),
            Button(
              label: widget.controller.isCollapsed(_selected!)
                  ? 'Expand file'
                  : 'Collapse file',
              onPressed: () => widget.controller.toggle(_selected!),
            ),
            if (!widget.controller.isCollapsed(_selected!))
              SyntaxEditor(
                key: ValueKey(_selected),
                controller: _editor!,
                highlighter: widget.highlighter,
                theme: widget.theme,
                height:
                    (height -
                            chooserHeight -
                            1 -
                            (widget.controller.hasSourceConflict(_selected!)
                                ? 1
                                : 0))
                        .clamp(1, height),
                wrap: widget.wrap,
                readOnly: !widget.editable,
                onComplete: widget.onComplete == null
                    ? null
                    : (_) => widget.controller.complete(
                        _selected!,
                        _editor!,
                        widget.onComplete!,
                      ),
              ),
          ],
        ],
      );
    },
  );
  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    if (_selected != null) widget.controller.release(_selected!);
    super.dispose();
  }
}

/// Streamed source rendered through the same terminal viewport as static files.
class StreamingCodeView extends StatelessWidget {
  /// Displays stable lines and the provisional final line.
  const StreamingCodeView({
    super.key,
    required this.controller,
    required this.highlighter,
    required this.theme,
    this.height,
    this.autofocus = false,
  });

  /// Stream delivery, completion and cancellation state.
  final syntax.StreamDocumentController controller;

  /// Registered grammars.
  final syntax.Highlighter highlighter;

  /// Current colors.
  final syntax.SyntaxTheme theme;

  /// Total height in rows.
  final int? height;

  /// Requests initial navigation focus.
  final bool autofocus;
  @override
  Widget build(BuildContext context) => SyntaxFileView(
    controller: controller.editor,
    highlighter: highlighter,
    theme: theme,
    height: height,
    autofocus: autofocus,
  );
}

/// Terminal conflict resolver with keyboard-accessible side choices.
class MergeConflictView extends StatefulWidget {
  /// Displays the complete file and resolves the chosen conflict in place.
  const MergeConflictView({
    super.key,
    required this.controller,
    required this.highlighter,
    required this.theme,
    this.height,
    this.autofocus = false,
  });

  /// Source and conflict resolution state.
  final syntax.MergeController controller;

  /// Registered grammars.
  final syntax.Highlighter highlighter;

  /// Current colors.
  final syntax.SyntaxTheme theme;

  /// Total height in rows.
  final int? height;

  /// Requests initial focus in the conflict chooser.
  final bool autofocus;
  @override
  State<MergeConflictView> createState() => _MergeConflictViewState();
}

class _MergeConflictViewState extends State<MergeConflictView> {
  late syntax.EditorController _editor;
  int _selected = 0;
  void _changed() {
    _editor.applyEdits([
      syntax.OffsetEdit(
        0,
        _editor.document.length,
        widget.controller.file.text,
      ),
    ]);
    _selected = _selected.clamp(0, widget.controller.conflicts.length);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _editor = syntax.EditorController(file: widget.controller.file);
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(MergeConflictView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _editor.dispose();
      _editor = syntax.EditorController(file: widget.controller.file);
      _selected = 0;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final conflicts = widget.controller.conflicts;
      final height = widget.height ?? constraints.maxHeight ?? 24;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SyntaxFileView(
            controller: _editor,
            highlighter: widget.highlighter,
            theme: widget.theme,
            height: (height - 5).clamp(1, height),
          ),
          if (conflicts.isEmpty)
            const Text('All conflicts resolved')
          else ...[
            ListView(
              itemCount: conflicts.length,
              height: 3,
              selectedIndex: _selected.clamp(0, conflicts.length - 1),
              autofocus: widget.autofocus,
              onChanged: (index) {
                setState(() => _selected = index);
                final c = conflicts[index];
                _editor.reveal(
                  syntax.DocumentRange(
                    _editor.document.positionAt(c.start),
                    _editor.document.positionAt(c.end),
                  ),
                );
              },
              itemBuilder: (context, index, selected) => Text(
                '${selected ? '▸' : ' '} Conflict ${index + 1}: ${conflicts[index].currentLabel} / ${conflicts[index].incomingLabel}',
              ),
            ),
            Row(
              children: [
                for (final (label, resolution) in [
                  ('Current', syntax.ChangeResolution.old),
                  ('Incoming', syntax.ChangeResolution.newer),
                  ('Both', syntax.ChangeResolution.both),
                ])
                  Button(
                    label: label,
                    onPressed: () => widget.controller.resolve(
                      _selected.clamp(0, conflicts.length - 1),
                      resolution,
                    ),
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );
  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _editor.dispose();
    super.dispose();
  }
}
