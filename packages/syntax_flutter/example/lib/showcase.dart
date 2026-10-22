import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'catalog.dart';
import 'interaction_examples.dart';
import 'showcase_samples.dart';
import 'workflows.dart';

/// A curated, interactive gallery built entirely with the public widgets.
class SyntaxShowcase extends StatefulWidget {
  const SyntaxShowcase({super.key});
  @override
  State<SyntaxShowcase> createState() => _SyntaxShowcaseState();
}

class _SyntaxShowcaseState extends State<SyntaxShowcase> {
  bool _dark = true;
  @override
  Widget build(BuildContext context) {
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff61bd8b),
          brightness: _dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          surface: _dark ? const Color(0xff11151c) : Colors.white,
          primary: _dark ? const Color(0xffa6e3b5) : const Color(0xff217a4d),
          onSurface: _dark ? const Color(0xffe7ebf0) : const Color(0xff19212b),
          onSurfaceVariant: _dark
              ? const Color(0xff939ca9)
              : const Color(0xff606c7b),
          outlineVariant: _dark
              ? const Color(0xff2a303a)
              : const Color(0xffdfe3e8),
        );
    return MaterialApp(
      title: 'Syntax — file & diff playground',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colors,
        scaffoldBackgroundColor: _dark
            ? const Color(0xff0b0e13)
            : const Color(0xfff5f6f8),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: colors.brightness).textTheme,
        ),
        dividerColor: colors.outlineVariant,
        splashFactory: NoSplash.splashFactory,
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: colors.onSurfaceVariant,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: colors.onSurfaceVariant,
            iconSize: 18,
            minimumSize: const Size(32, 32),
            padding: const EdgeInsets.all(6),
          ),
        ),
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 400),
        ),
      ),
      home: ShowcaseHome(
        dark: _dark,
        onBrightness: () => setState(() => _dark = !_dark),
        fontStyles: {
          'Roboto Mono': GoogleFonts.robotoMono(fontSize: 13.5, height: 1.72),
          'Source Code Pro': GoogleFonts.sourceCodePro(
            fontSize: 13.5,
            height: 1.72,
          ),
        },
        codeStyle: GoogleFonts.jetBrainsMono(
          fontSize: 13.5,
          height: 1.72,
          fontFeatures: const [
            FontFeature.disable('liga'),
            FontFeature.disable('calt'),
          ],
        ),
      ),
    );
  }
}

const _examples = [
  (
    Icons.difference_outlined,
    'Diff review',
    'Every change, in context.',
    'Compare real changes, expand the surrounding code, and leave a review.',
  ),
  (
    Icons.unfold_more_rounded,
    'Collapsible files',
    'A little more room to focus.',
    'Open the files you need. Fold the rest. Your drafts stay right where you left them.',
  ),
  (
    Icons.edit_note_rounded,
    'Editing',
    'Make the next change.',
    'A live editing session with history, search, diagnostics, and suggested edits.',
  ),
  (
    Icons.merge_rounded,
    'Merge conflicts',
    'Bring both sides together.',
    'Resolve a three-way conflict and see the resulting source immediately.',
  ),
  (
    Icons.stream_rounded,
    'Streaming',
    'Code, as it arrives.',
    'Watch a document build line by line with live syntax highlighting.',
  ),
  (
    Icons.speed_rounded,
    'Large files',
    'Go straight to the interesting part.',
    '100,000 lines, a small visible window. Drag the scrollbar or jump directly to a line.',
  ),
  (
    Icons.format_line_spacing,
    'Line selection',
    'Select the whole thought.',
    'Drag through the gutter, extend with Shift, and copy or annotate a range.',
  ),
  (
    Icons.functions,
    'Named sections',
    'Focus on one function.',
    'Fold patch sections by their function name. Jump to a line to reopen its section.',
  ),
  (
    Icons.tune,
    'Appearance',
    'Make the diff yours.',
    'Try markers, comparison modes, separators, line numbers, and typography.',
  ),
  (
    Icons.manage_search,
    'Token details',
    'Look inside the highlight.',
    'Inspect tokens with the pointer or keyboard and pin their details.',
  ),
  (
    Icons.dashboard_customize,
    'Custom headers',
    'Give your files context.',
    'Replace the header while keeping folding and review state connected.',
  ),
  (
    Icons.compare,
    'Compare text',
    'Bring your own changes.',
    'Paste two versions of a file and explore the resulting diff.',
  ),
];

SyntaxTheme _codeTheme(bool dark) {
  final base = dark ? githubDarkTheme : githubLightTheme;
  final json = base.json;
  return SyntaxTheme.fromJson({
    ...json,
    'name': dark ? 'Syntax night' : 'Syntax day',
    'colors': {
      ...json['colors'] as Map<String, Object?>,
      'editor.background': dark ? '#11151c' : '#ffffff',
      'editor.foreground': dark ? '#dce3ed' : '#24292f',
      'editorLineNumber.foreground': dark ? '#636f80' : '#8b949e',
      'diffEditor.insertedTextBackground': dark ? '#39b77430' : '#2da44e20',
      'diffEditor.removedTextBackground': dark ? '#f3697030' : '#fa454920',
    },
  });
}

/// Kept separate from font loading so interaction tests can use system fonts.
class ShowcaseHome extends StatefulWidget {
  const ShowcaseHome({
    super.key,
    required this.dark,
    required this.onBrightness,
    this.fontStyles = const {},
    this.codeStyle = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      height: 1.72,
    ),
  });
  final bool dark;
  final VoidCallback onBrightness;
  final TextStyle codeStyle;
  final Map<String, TextStyle> fontStyles;
  @override
  State<ShowcaseHome> createState() => _ShowcaseHomeState();
}

class _ShowcaseHomeState extends State<ShowcaseHome> {
  final _highlighter = Highlighter(languages: [dartLanguage]);
  final _night = _codeTheme(true), _day = _codeTheme(false);
  late PatchController _review = _newReview();
  final _commentInput = TextEditingController();
  final _commentFocus = FocusNode();
  DiffSelectionDetails? _commentSelection;
  late final _files = FileListController(showcaseFiles);
  late final _editor = EditorController(
    file: const SourceFile(
      id: 'edit',
      path: 'lib/client/retry_policy.dart',
      text: retryAfter,
    ),
    proposalProvider: (request) async {
      final start = request.file.text.indexOf('maxAttempts = 3');
      return start < 0 ? [] : [OffsetEdit(start + 14, start + 15, '5')];
    },
  );
  late MergeController _merge = _newMerge();
  StreamDocumentController _stream = _newStream();
  EditorController? _large;
  final _largeScroll = ScrollController();
  final _largeVisible = ValueNotifier<(int, int)>((0, 0));
  bool _largeWrap = false;
  HighlightPool? _pool;
  Timer? _timer;
  int _tab = 0, _streamLine = 0;
  int? _diagnosticRevision;
  bool _wrap = true, _backgrounds = true, _indicators = true;
  bool _contextExpanded = false;
  bool get _activeWrap => _tab == 5 ? _largeWrap : _wrap;
  InlineDiffMode _comparison = InlineDiffMode.mergedWords;
  final _resolved = <String>{};
  String _status = 'Click a line to select it. Shift-click to select a range.';
  ColorScheme get colors => Theme.of(context).colorScheme;
  SyntaxTheme get codeTheme => widget.dark ? _night : _day;

  static MergeController _newMerge() => MergeController(
    const SourceFile(
      id: 'merge',
      path: 'lib/client/options.dart',
      text: conflictSource,
    ),
  );
  static StreamDocumentController _newStream() => StreamDocumentController(
    const SourceFile(
      id: 'stream',
      path: 'lib/client/retry_policy.dart',
      text: '',
    ),
  );
  PatchController _newReview() {
    final controller = PatchController(
      showcaseDiffs(),
      contextThreshold: 0,
      expansionLineCount: 8,
    );
    controller.toggleFile('options');
    controller.toggleFile('tests');
    controller.setAnnotations([
      const ReviewAnnotation(
        id: 'initial',
        fileId: 'retry',
        side: DiffSide.newer,
        line: 7,
        data:
            'Keeping this configurable is a nice touch. Callers with tighter timeouts can opt into fewer attempts.',
      ),
    ]);
    return controller;
  }

  @override
  void initState() {
    super.initState();
    _review.addListener(_changed);
    _files.addListener(_changed);
    _merge.addListener(_changed);
    _editor.addListener(_updateDiagnostic);
    _updateDiagnostic();
  }

  void _updateDiagnostic() {
    if (_diagnosticRevision == _editor.document.revision) return;
    _diagnosticRevision = _editor.document.revision;
    final start = _editor.document.text.indexOf('maxAttempts = 3');
    _editor.setDiagnostics([
      if (start >= 0)
        Diagnostic(
          start: start + 14,
          end: start + 15,
          message:
              'Demo suggestion: try five attempts. Use Preview suggestion to compare.',
          severity: DiagnosticSeverity.information,
        ),
    ]);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _message(String text) {
    if (mounted) setState(() => _status = text);
  }

  void _select(int tab) {
    if (tab == 5 && _large == null) {
      _large = EditorController(
        file: SourceFile(
          id: 'large',
          path: 'generated/events.dart',
          text: List.generate(
            100000,
            (i) =>
                'final event${i + 1} = Event(id: ${i + 1}, status: "ready");',
          ).join('\n'),
        ),
      );
      _pool = HighlightPool(
        executor: kIsWeb
            ? createBrowserHighlightExecutor(
                workerUri: const bool.fromEnvironment('SYNTAX_WORKER')
                    ? Uri.base.resolve('highlight_worker.js')
                    : null,
              )
            : createNativeHighlightExecutor(),
        cacheSize: 4,
      );
    }
    setState(() {
      _tab = tab;
      _status = 'Examples run locally. Changes stay in this session.';
    });
  }

  void _reset() {
    switch (_tab) {
      case 0:
        _commentSelection = null;
        _commentInput.clear();
        final previous = _review..removeListener(_changed);
        _review = _newReview()..addListener(_changed);
        _resolved.clear();
        _contextExpanded = false;
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      case 1:
        _files.setFiles(showcaseFiles);
        for (final file in showcaseFiles) {
          _files.reload(file.id);
        }
      case 2:
        _diagnosticRevision = null;
        _editor.replaceSource(
          const SourceFile(
            id: 'edit',
            path: 'lib/client/retry_policy.dart',
            text: retryAfter,
          ),
        );
      case 3:
        final previous = _merge..removeListener(_changed);
        _merge = _newMerge()..addListener(_changed);
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      case 4:
        _timer?.cancel();
        _timer = null;
        final previous = _stream;
        _stream = _newStream();
        _streamLine = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      case 5:
        _largeWrap = false;
        _large?.reveal(
          const DocumentRange(DocumentPosition(0, 0), DocumentPosition(0, 0)),
        );
    }
    setState(() => _status = 'Example reset. Ready for another review.');
  }

  void _toggleAll() {
    if (_tab == 1) {
      final collapse = _files.files.any((file) => !_files.isCollapsed(file.id));
      for (final file in _files.files) {
        if (_files.isCollapsed(file.id) != collapse) _files.toggle(file.id);
      }
    } else {
      final collapse = _review.files.any(
        (file) => !_review.isCollapsed(file.id),
      );
      for (final file in _review.files) {
        if (_review.isCollapsed(file.id) != collapse) {
          _review.toggleFile(file.id);
        }
      }
    }
  }

  Future<void> _copy() async {
    final value = _review.selectedText();
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    _message(
      'Selected source copied. Line numbers and review notes are excluded.',
    );
  }

  void _comment([DiffSelectionDetails? details]) {
    final selection = details?.selection ?? _review.selection;
    if (selection == null) return;
    if (_commentSelection != null &&
        _review.files.any(_commentSelection!.matches)) {
      _commentFocus.requestFocus();
      final pending = _commentSelection!;
      final endpoint = pending.endIn(_review.mode);
      _review.revealLine(pending.file.id, endpoint.line, side: endpoint.side);
      return;
    }
    final snapshot =
        details ??
        DiffSelectionDetails(
          file: _review.file(selection.fileId),
          selection: selection,
        );
    _commentInput.clear();
    setState(() => _commentSelection = snapshot);
    if (details == null) {
      final endpoint = snapshot.endIn(_review.mode);
      _review.revealLine(selection.fileId, endpoint.line, side: endpoint.side);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            identical(_commentSelection, snapshot) &&
            _commentFocus.context == null) {
          _comment(snapshot);
        }
      });
    }
  }

  void _cancelComment() {
    _commentInput.clear();
    setState(() => _commentSelection = null);
  }

  void _submitComment(String text) {
    final details = _commentSelection;
    if (details == null || !_review.files.any(details.matches)) return;
    final endpoint = details.endIn(_review.mode);
    _review.setAnnotations([
      ..._review.annotations,
      ReviewAnnotation(
        id: 'note-${DateTime.now().microsecondsSinceEpoch}',
        fileId: details.file.id,
        side: endpoint.side,
        line: endpoint.line,
        data: text,
      ),
    ]);
    _cancelComment();
    _message('Comment added to the selected lines. Only visible in this demo.');
  }

  Future<void> _editFile(FileDiff file) async {
    final owner = _review;
    final session = owner.beginEdit(file.id);
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 900,
          height: 620,
          child: SyntaxEditor(
            controller: session,
            highlighter: _highlighter,
            theme: codeTheme,
            textStyle: widget.codeStyle,
            onDismiss: () => Navigator.pop(context),
            onComplete: (_) async {
              final accepted = await owner.completeEdit(
                file.id,
                accept: (_) async => true,
              );
              if (context.mounted) Navigator.pop(context);
              _message('Edits applied to ${file.path}.');
              return accepted;
            },
          ),
        ),
      ),
    );
    if (!owner.isDisposed) owner.releaseEdit(file.id);
  }

  Future<void> _editCollectionFile(SourceFile file) async {
    final session = _files.acquire(file.id);
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 900,
          height: 620,
          child: SyntaxEditor(
            controller: session,
            highlighter: _highlighter,
            theme: codeTheme,
            textStyle: widget.codeStyle,
            onDismiss: () => Navigator.pop(context),
            onComplete: (_) async {
              final accepted = await _files.complete(
                file.id,
                session,
                (_) async => true,
              );
              if (context.mounted) Navigator.pop(context);
              _message('Edits applied to ${file.path}.');
              return accepted;
            },
          ),
        ),
      ),
    );
    if (!_files.isDisposed) _files.release(file.id);
  }

  void _startStream() {
    if (_timer?.isActive == true || _stream.isComplete) return;
    final lines = RegExp(
      r'[^\n]*\n|[^\n]+$',
    ).allMatches(retryAfter).map((match) => match.group(0)!).toList();
    _timer = Timer.periodic(const Duration(milliseconds: 160), (timer) {
      if (_streamLine == lines.length) {
        timer.cancel();
        _stream.finish();
        _message('Stream complete. All lines received.');
        return;
      }
      _stream.add(lines[_streamLine++]);
      _message('Receiving source · $_streamLine / ${lines.length} lines');
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          _topBar(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1050;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide) _sidebar(),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 36 : 16,
                          26,
                          wide ? 36 : 16,
                          18,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!wide)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (var i = 0; i < _examples.length; i++)
                                        _nav(i, compact: true),
                                    ],
                                  ),
                                ),
                              ),
                            _intro(constraints.maxWidth < 620),
                            const SizedBox(height: 22),
                            Expanded(
                              child: Container(
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    if (_tab < 6) _toolbar(),
                                    if (_tab == 0 &&
                                        _review.mode == DiffMode.split)
                                      _splitLabels(),
                                    Expanded(child: _surface()),
                                    _footer(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _topBar() => Container(
    height: 68,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    decoration: BoxDecoration(
      color: colors.surface,
      border: Border(bottom: BorderSide(color: colors.outlineVariant)),
    ),
    child: Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.code_rounded,
            size: 20,
            color: widget.dark ? const Color(0xff14231a) : Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'syntax',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(width: 16),
        Text('/', style: TextStyle(color: colors.outlineVariant, fontSize: 22)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            'Playground',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
          ),
        ),
        if (MediaQuery.sizeOf(context).width > 540)
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const CatalogPlayground(),
              ),
            ),
            icon: const Icon(Icons.palette_outlined, size: 16),
            label: const Text('Languages & themes'),
          ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: widget.dark
              ? 'Switch to light theme'
              : 'Switch to dark theme',
          onPressed: widget.onBrightness,
          icon: Icon(
            widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
        ),
      ],
    ),
  );

  Widget _sidebar() => Container(
    width: 218,
    padding: const EdgeInsets.fromLTRB(16, 30, 16, 20),
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: colors.outlineVariant)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 14),
          child: Text(
            'EXPLORE',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (var i = 0; i < _examples.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: _nav(i),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.tips_and_updates_outlined, size: 18),
              const SizedBox(height: 10),
              const Text(
                'Made to be explored',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              Text(
                'Every example is live. Fold a file, edit a line, or resolve a change.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.7,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => WorkflowsDemo(textStyle: widget.codeStyle),
            ),
          ),
          icon: const Icon(Icons.science_outlined, size: 15),
          label: const Text('Stress-test workflows'),
        ),
      ],
    ),
  );

  Widget _nav(int index, {bool compact = false}) {
    final selected = _tab == index;
    return Padding(
      padding: EdgeInsets.only(right: compact ? 6 : 0),
      child: TextButton(
        key: ValueKey('example-$index'),
        onPressed: () => _select(index),
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? colors.primary.withValues(alpha: .10)
              : Colors.transparent,
          foregroundColor: selected ? colors.primary : colors.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          alignment: Alignment.centerLeft,
        ),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(_examples[index].$1, size: 17),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _examples[index].$2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intro(bool narrow) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${(_tab + 1).toString().padLeft(2, '0')} / ${_examples[_tab].$2.toUpperCase()}',
        style: TextStyle(
          color: colors.primary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.6,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        _examples[_tab].$3,
        style: TextStyle(
          fontSize: narrow ? 24 : 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -.9,
          height: 1.25,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _examples[_tab].$4,
        style: TextStyle(
          fontSize: 12,
          height: 1.6,
          color: colors.onSurfaceVariant,
        ),
      ),
    ],
  );

  void _shortcuts() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: const SingleChildScrollView(
        child: Text(
          'Ctrl / Cmd + Z — Undo\n'
          'Ctrl / Cmd + Shift + Z — Redo\n'
          'Ctrl / Cmd + F — Find and replace\n'
          'Ctrl / Cmd + / — Toggle comment\n'
          'Tab / Shift + Tab — Indent / outdent\n'
          'Alt + ↑ / ↓ — Move line\n'
          'Alt + Shift + ↑ / ↓ — Duplicate line\n'
          'Ctrl / Cmd + C — Copy selected source\n\n'
          'Editing shortcuts apply while the code field is focused. '
          'Search fields keep their normal text editing and Tab navigation.',
          style: TextStyle(height: 1.8),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _toolbar() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: colors.outlineVariant)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_tab == 0) ...[
            _modeToggle(),
            _tool(
              _contextExpanded ? 'Collapse context' : 'Expand context',
              _contextExpanded ? Icons.unfold_less : Icons.unfold_more,
              () {
                _contextExpanded = !_contextExpanded;
                if (_contextExpanded) {
                  _review.expandAll();
                } else {
                  _review.collapseContext();
                }
                _message(
                  _contextExpanded
                      ? 'All unchanged context is visible.'
                      : 'Unchanged context collapsed. Review decisions are preserved.',
                );
              },
            ),
          ],
          if (_tab == 2) ...[
            _tool(
              'Preview suggestion',
              Icons.auto_fix_high_outlined,
              _editor.requestProposal,
            ),
            _tool('Keyboard shortcuts', Icons.keyboard_outlined, _shortcuts),
          ],
          if (_tab == 0 || _tab == 1)
            _tool(
              (_tab == 1
                      ? _files.files.every((f) => _files.isCollapsed(f.id))
                      : _review.files.every((f) => _review.isCollapsed(f.id)))
                  ? 'Expand files'
                  : 'Collapse files',
              Icons.unfold_less_rounded,
              _toggleAll,
            ),
          if (_tab == 0) ...[
            _tool(
              'Comment',
              Icons.add_comment_outlined,
              _review.selection == null ? null : _comment,
            ),
            IconButton(
              tooltip: 'Copy selected source',
              onPressed: _review.selection == null ? null : _copy,
              icon: const Icon(Icons.content_copy_rounded),
            ),
          ],
          if (_tab == 4) ...[
            _tool(
              _stream.isComplete
                  ? 'Complete'
                  : _timer?.isActive == true
                  ? 'Receiving…'
                  : 'Start stream',
              Icons.play_arrow_rounded,
              _stream.isComplete || _timer?.isActive == true
                  ? null
                  : _startStream,
            ),
            _tool(
              'Pause',
              Icons.pause_rounded,
              _timer?.isActive != true
                  ? null
                  : () {
                      _timer?.cancel();
                      setState(() {});
                    },
            ),
          ],
          if (_tab == 5) ...[
            _tool(
              'Line 90,001',
              Icons.south_rounded,
              () => _large!.reveal(
                const DocumentRange(
                  DocumentPosition(90000, 0),
                  DocumentPosition(90000, 0),
                ),
              ),
            ),
            _tool(
              'Back to top',
              Icons.vertical_align_top_rounded,
              () => _large!.reveal(
                const DocumentRange(
                  DocumentPosition(0, 0),
                  DocumentPosition(0, 0),
                ),
              ),
            ),
          ],
          if (_tab != 4)
            _tool(
              _activeWrap ? 'Wrap on' : 'Wrap off',
              Icons.wrap_text_rounded,
              () => setState(() {
                if (_tab == 5) {
                  _largeWrap = !_largeWrap;
                } else {
                  _wrap = !_wrap;
                }
              }),
            ),
          if (_tab == 0)
            PopupMenuButton<String>(
              tooltip: 'Display options',
              icon: const Icon(Icons.tune_rounded, size: 18),
              onSelected: (value) => setState(() {
                if (value == 'backgrounds') {
                  _backgrounds = !_backgrounds;
                } else if (value == 'indicators') {
                  _indicators = !_indicators;
                } else {
                  _comparison = InlineDiffMode.values.firstWhere(
                    (mode) => mode.name == value,
                  );
                }
              }),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: 'backgrounds',
                  checked: _backgrounds,
                  child: const Text('Line backgrounds'),
                ),
                CheckedPopupMenuItem(
                  value: 'indicators',
                  checked: _indicators,
                  child: const Text('Change indicators'),
                ),
                const PopupMenuDivider(),
                for (final mode in InlineDiffMode.values)
                  CheckedPopupMenuItem(
                    value: mode.name,
                    checked: _comparison == mode,
                    child: Text(switch (mode) {
                      InlineDiffMode.word => 'Words',
                      InlineDiffMode.mergedWords => 'Merged words',
                      InlineDiffMode.character => 'Characters',
                      InlineDiffMode.changedSpan => 'Changed span',
                      InlineDiffMode.none => 'No inline highlighting',
                    }),
                  ),
              ],
            ),
          _tool('Reset', Icons.restart_alt_rounded, _reset),
        ],
      ),
    ),
  );

  Widget _tool(String label, IconData icon, VoidCallback? onPressed) =>
      TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label),
      );
  Widget _modeToggle() => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor,
      border: Border.all(color: colors.outlineVariant),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mode in DiffMode.values)
          TextButton(
            key: ValueKey('mode-${mode.name}'),
            onPressed: () => _review.setMode(mode),
            style: TextButton.styleFrom(
              minimumSize: const Size(65, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: _review.mode == mode
                  ? colors.surface
                  : Colors.transparent,
              foregroundColor: _review.mode == mode
                  ? colors.onSurface
                  : colors.onSurfaceVariant,
            ),
            child: Text(mode == DiffMode.unified ? 'Unified' : 'Split'),
          ),
      ],
    ),
  );
  Widget _splitLabels() => Container(
    height: 30,
    color: colors.onSurface.withValues(alpha: .025),
    child: Row(
      children: [
        for (final label in ['BEFORE', 'AFTER'])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _surface() => switch (_tab) {
    0 => PatchView.controlled(
      key: const ValueKey('review'),
      controller: _review,
      highlighter: _highlighter,
      theme: codeTheme,
      padding: EdgeInsets.zero,
      textStyle: widget.codeStyle,
      wrap: _wrap,
      showBackgrounds: _backgrounds,
      showChangeIndicators: _indicators,
      inlineDiffMode: _comparison,
      headerBuilder: (context, file, collapsed, toggle) => _fileHeader(
        file.path,
        collapsed,
        toggle,
        stats: '+${file.additions}  −${file.deletions}',
        onEdit: () => _editFile(file),
      ),
      hunkBuilder: _hunkHeader,
      annotationBuilder: _reviewNote,
      onComment: _comment,
      commentSelection: _commentSelection,
      commentBuilder: (context, selection) => SyntaxCommentComposer(
        controller: _commentInput,
        focusNode: _commentFocus,
        onSubmit: _submitComment,
        onCancel: _cancelComment,
      ),
      onLineTap: (file, side, line) => _message(
        '${file.path} · ${side == DiffSide.old ? 'before' : 'after'} · line $line selected',
      ),
    ),
    1 => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final file in _files.files)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _fileHeader(
                    file.path,
                    _files.isCollapsed(file.id),
                    () => _files.toggle(file.id),
                    onEdit: () => _editCollectionFile(file),
                  ),
                  if (!_files.isCollapsed(file.id))
                    SizedBox(
                      height: 300,
                      child: _RetainedFile(
                        key: ValueKey(file.id),
                        owner: _files,
                        id: file.id,
                        highlighter: _highlighter,
                        theme: codeTheme,
                        codeStyle: widget.codeStyle,
                        wrap: _wrap,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
    2 => SyntaxEditor(
      key: const ValueKey('editor'),
      controller: _editor,
      highlighter: _highlighter,
      theme: codeTheme,
      textStyle: widget.codeStyle,
      wrap: _wrap,
      onComplete: (_) async {
        _message('Draft accepted. Changes are kept in this demo session.');
        return true;
      },
    ),
    3 => MergeConflictView(
      key: ValueKey(_merge),
      controller: _merge,
      highlighter: _highlighter,
      theme: codeTheme,
      textStyle: widget.codeStyle,
      wrap: _wrap,
    ),
    4 =>
      _stream.editor.document.length == 0
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stream_rounded, size: 34, color: colors.primary),
                  const SizedBox(height: 14),
                  const Text(
                    'Ready when you are.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start the stream to watch the file take shape.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : SyntaxFileView(
              key: ValueKey(_stream),
              controller: _stream.editor,
              highlighter: _highlighter,
              theme: codeTheme,
              textStyle: widget.codeStyle,
            ),
    5 => ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _largeScroll,
        thumbVisibility: true,
        interactive: true,
        child: SyntaxFileView(
          key: const ValueKey('large'),
          controller: _large!,
          highlighter: _highlighter,
          theme: codeTheme,
          textStyle: widget.codeStyle,
          executor: _pool,
          scrollController: _largeScroll,
          onVisibleLinesChanged: (start, end) =>
              _largeVisible.value = (start, end),
          wrap: _largeWrap,
        ),
      ),
    ),
    _ => InteractionExamples(
      kind: _tab - 6,
      fontStyles: widget.fontStyles,
      theme: codeTheme,
      textStyle: widget.codeStyle,
    ),
  };

  Widget _fileHeader(
    String path,
    bool collapsed,
    VoidCallback toggle, {
    String? stats,
    VoidCallback? onEdit,
  }) => Container(
    decoration: BoxDecoration(
      color: colors.onSurface.withValues(alpha: .035),
      border: Border(bottom: BorderSide(color: colors.outlineVariant)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: '${collapsed ? 'Expand' : 'Collapse'} $path',
            onTap: toggle,
            excludeSemantics: true,
            child: InkWell(
              onTap: toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Icon(
                      collapsed
                          ? Icons.chevron_right_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.code_rounded, size: 16, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        path,
                        overflow: TextOverflow.ellipsis,
                        style: widget.codeStyle.copyWith(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (stats != null)
          Text(
            stats,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.primary,
            ),
          ),
        if (onEdit != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              tooltip: 'Edit $path',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
            ),
          ),
        const SizedBox(width: 10),
      ],
    ),
  );

  Widget _hunkHeader(BuildContext context, FileDiff file, DiffHunk hunk) =>
      Container(
        padding: const EdgeInsets.only(left: 18, right: 8, top: 3, bottom: 3),
        color: colors.primary.withValues(alpha: .045),
        child: Row(
          children: [
            Icon(
              Icons.commit_rounded,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hunk.header,
                overflow: TextOverflow.ellipsis,
                style: widget.codeStyle.copyWith(
                  fontSize: 10,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            _tool('Reject', Icons.close_rounded, () {
              _review.resolve(
                file.id,
                file.hunks.indexOf(hunk),
                ChangeResolution.old,
              );
              _message('Change rejected in ${file.path}.');
            }),
            _tool('Accept', Icons.check_rounded, () {
              _review.resolve(
                file.id,
                file.hunks.indexOf(hunk),
                ChangeResolution.newer,
              );
              _message('Change accepted in ${file.path}.');
            }),
          ],
        ),
      );

  Widget _reviewNote(BuildContext context, ReviewAnnotation<Object?> note) {
    final resolved = _resolved.contains(note.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 12, 20, 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: colors.primary.withValues(alpha: .15),
                  child: Text(
                    note.id == 'initial' ? 'AM' : 'YO',
                    style: TextStyle(
                      fontSize: 8,
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    note.id == 'initial' ? 'Alex Morgan' : 'You',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    if (resolved) {
                      _resolved.remove(note.id);
                    } else {
                      _resolved.add(note.id);
                    }
                  }),
                  child: Text(resolved ? 'Reopen' : 'Resolve'),
                ),
              ],
            ),
            if (!resolved)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${note.data}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: colors.onSurface,
                  ),
                ),
              ),
            if (resolved)
              Text(
                'Resolved',
                style: TextStyle(fontSize: 11, color: colors.primary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    final additions = _review.files.fold(
      0,
      (sum, file) => sum + file.additions,
    );
    final deletions = _review.files.fold(
      0,
      (sum, file) => sum + file.deletions,
    );
    return Container(
      height: 37,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _tab == 5
                ? ValueListenableBuilder<(int, int)>(
                    valueListenable: _largeVisible,
                    builder: (context, range, _) => Text(
                      'Visible lines ${range.$1 + 1}–${range.$2} of 100,000 · virtualized',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                : Text(
                    _status,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          if (_tab == 0)
            Text(
              '3 files   +$additions  −$deletions',
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _commentInput.dispose();
    _commentFocus.dispose();
    _review.dispose();
    _files.dispose();
    _editor.dispose();
    _merge.dispose();
    _stream.dispose();
    _large?.dispose();
    _largeScroll.dispose();
    _largeVisible.dispose();
    _pool?.dispose();
    super.dispose();
  }
}

class _RetainedFile extends StatefulWidget {
  const _RetainedFile({
    super.key,
    required this.owner,
    required this.id,
    required this.highlighter,
    required this.theme,
    required this.codeStyle,
    required this.wrap,
  });
  final FileListController owner;
  final String id;
  final Highlighter highlighter;
  final SyntaxTheme theme;
  final TextStyle codeStyle;
  final bool wrap;
  @override
  State<_RetainedFile> createState() => _RetainedFileState();
}

class _RetainedFileState extends State<_RetainedFile> {
  late final editor = widget.owner.acquire(widget.id);
  @override
  Widget build(BuildContext context) => SyntaxFileView(
    controller: editor,
    highlighter: widget.highlighter,
    theme: widget.theme,
    showHeader: false,
    textStyle: widget.codeStyle,
    wrap: widget.wrap,
  );
  @override
  void dispose() {
    widget.owner.release(widget.id);
    super.dispose();
  }
}
