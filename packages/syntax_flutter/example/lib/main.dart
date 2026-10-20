import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syntax/langs/all.dart';
import 'package:syntax/themes/all.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'samples.dart';

void main() => runApp(const SyntaxDemo());

final _highlighter = Highlighter(languages: bundledLanguages.values);

/// What the right-hand pane shows.
enum _View { preview, diff, patch }

class SyntaxDemo extends StatefulWidget {
  const SyntaxDemo({super.key});

  @override
  State<SyntaxDemo> createState() => _SyntaxDemoState();
}

class _SyntaxDemoState extends State<SyntaxDemo> {
  var _language = 'dart';
  var _themeName = 'github-dark';
  var _view = _View.preview;
  var _mode = DiffMode.unified;
  late final _controller = SyntaxTextEditingController(
    highlighter: _highlighter,
    language: _language,
    theme: _theme,
    text: samples[_language],
  );

  SyntaxTheme get _theme => bundledThemes[_themeName]!;

  /// A file name with the language's shortest alias as its extension:
  /// `sample.sh` rather than `sample.shellscript`.
  String get _samplePath {
    final language = bundledLanguages[_language]!;
    final names = [_language, ...language.aliases]
      ..sort((a, b) => a.length.compareTo(b.length));
    return 'sample.${names.first}';
  }

  late String _previewText = _controller.text;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncPreview);
  }

  /// Caret moves and theme changes also notify, so only rebuild when the
  /// text itself changed.
  void _syncPreview() {
    if (_controller.text == _previewText) return;
    setState(() => _previewText = _controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectLanguage(String language) {
    setState(() => _language = language);
    _controller
      ..language = language
      ..text = samples[language] ?? '';
  }

  void _selectTheme(String name) {
    setState(() => _themeName = name);
    _controller.theme = _theme;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    // Ligatures would show `=>` as an arrow, which hides the real tokens.
    final code = GoogleFonts.jetBrainsMono(
      fontSize: 13.5,
      height: 1.55,
      fontFeatures: const [
        FontFeature.disable('calt'),
        FontFeature.disable('liga'),
      ],
    );
    final brightness = theme.isDark ? Brightness.dark : Brightness.light;
    final chrome = Color.alphaBlend(
      theme.foregroundColor.withValues(alpha: 0.05),
      theme.backgroundColor,
    );

    return MaterialApp(
      title: 'syntax',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: brightness,
        colorSchemeSeed: theme.cursorColor,
        scaffoldBackgroundColor: chrome,
        fontFamily: GoogleFonts.inter().fontFamily,
      ),
      home: HighlighterScope(
        highlighter: _highlighter,
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    language: _language,
                    themeName: _themeName,
                    onLanguage: _selectLanguage,
                    onTheme: _selectTheme,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth > 900;
                        final panes = [
                          _Pane(
                            title: 'SyntaxTextEditingController',
                            theme: theme,
                            actions: [
                              Text(
                                'Edit me',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.lineNumberColor,
                                ),
                              ),
                            ],
                            child: TextField(
                              controller: _controller,
                              maxLines: null,
                              expands: true,
                              style: code,
                              cursorColor: theme.cursorColor,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(16),
                              ),
                            ),
                          ),
                          _Pane(
                            title: switch (_view) {
                              _View.preview => 'HighlightedCode',
                              _View.diff => 'PatchView.fromTexts',
                              _View.patch => 'PatchView.fromPatch',
                            },
                            theme: theme,
                            actions: [
                              if (_view != _View.preview)
                                _ModeToggle(
                                  mode: _mode,
                                  onChanged: (m) => setState(() => _mode = m),
                                ),
                              _ViewToggle(
                                view: _view,
                                onChanged: (v) => setState(() => _view = v),
                              ),
                            ],
                            child: _rightPane(theme, code),
                          ),
                        ];
                        return Flex(
                          direction: wide ? Axis.horizontal : Axis.vertical,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 16,
                          children: [for (final p in panes) Expanded(child: p)],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rightPane(SyntaxTheme theme, TextStyle code) => switch (_view) {
    _View.preview => SingleChildScrollView(
      child: HighlightedCode(
        _previewText,
        language: _language,
        theme: theme,
        textStyle: code,
        lineNumbers: true,
      ),
    ),
    // Your edits against the original sample.
    _View.diff => PatchView.fromTexts(
      oldText: samples[_language] ?? '',
      newText: _previewText,
      path: _samplePath,
      language: _language,
      theme: theme,
      mode: _mode,
      textStyle: code.copyWith(fontSize: 12.5),
    ),
    _View.patch => PatchView.fromPatch(
      samplePatch,
      theme: theme,
      mode: _mode,
      textStyle: code.copyWith(fontSize: 12.5),
    ),
  };
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final _View view;
  final ValueChanged<_View> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<_View>(
    showSelectedIcon: false,
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    segments: const [
      ButtonSegment(
        value: _View.preview,
        label: Text('Code', softWrap: false),
        tooltip: 'HighlightedCode',
      ),
      ButtonSegment(
        value: _View.diff,
        label: Text('Diff', softWrap: false),
        tooltip: 'Your edits compared with the original sample',
      ),
      ButtonSegment(
        value: _View.patch,
        label: Text('Patch', softWrap: false),
        tooltip: 'A multi-file git patch',
      ),
    ],
    selected: {view},
    onSelectionChanged: (s) => onChanged(s.single),
  );
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final DiffMode mode;
  final ValueChanged<DiffMode> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<DiffMode>(
    showSelectedIcon: false,
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    segments: const [
      ButtonSegment(
        value: DiffMode.unified,
        label: Text('Unified', softWrap: false),
      ),
      ButtonSegment(
        value: DiffMode.split,
        label: Text('Split', softWrap: false),
      ),
    ],
    selected: {mode},
    onSelectionChanged: (s) => onChanged(s.single),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.language,
    required this.themeName,
    required this.onLanguage,
    required this.onTheme,
  });

  final String language;
  final String themeName;
  final ValueChanged<String> onLanguage;
  final ValueChanged<String> onTheme;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'syntax',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              'TextMate grammars and VS Code themes, in pure Dart',
              style: text.bodyMedium?.copyWith(
                color: text.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          children: [
            _Picker(
              label: 'Language',
              value: language,
              options: {
                for (final MapEntry(:key, :value) in bundledLanguages.entries)
                  if (samples.containsKey(key)) key: value.displayName ?? key,
              },
              onChanged: onLanguage,
            ),
            _Picker(
              label: 'Theme',
              value: themeName,
              options: {for (final name in bundledThemes.keys) name: name},
              onChanged: onTheme,
            ),
          ],
        ),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;

  /// Values and the labels to show for them.
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownMenu<String>(
    label: Text(label),
    initialSelection: value,
    width: 220,
    requestFocusOnTap: false,
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(),
    ),
    dropdownMenuEntries: [
      for (final MapEntry(:key, value: text) in options.entries)
        DropdownMenuEntry(value: key, label: text),
    ],
    onSelected: (v) {
      if (v != null) onChanged(v);
    },
  );
}

class _Pane extends StatelessWidget {
  const _Pane({
    required this.title,
    required this.theme,
    required this.actions,
    required this.child,
  });

  final String title;
  final SyntaxTheme theme;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final line = theme.foregroundColor.withValues(alpha: 0.12);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              child: Row(
                children: [
                  Text(
                    title,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.foregroundColor,
                    ),
                  ),
                  const Spacer(),
                  for (final action in actions) ...[
                    const SizedBox(width: 8),
                    action,
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: line),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
