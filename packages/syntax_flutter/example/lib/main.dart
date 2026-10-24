import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syntax/langs/all.dart';
import 'package:syntax/themes/all.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

import 'samples.dart';

void main() => runApp(const SyntaxDemo());

final _highlighter = Highlighter(languages: bundledLanguages.values);

/// What the pane shows.
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
  final Set<int> _collapsedDiff = {};
  final Set<DiffGapId> _expandedDiff = {};
  final Set<int> _collapsedPatch = {};
  final Set<DiffGapId> _expandedPatch = {};

  SyntaxTheme get _theme => bundledThemes[_themeName]!;

  /// A file name with the language's shortest alias as its extension:
  /// `sample.sh` rather than `sample.shellscript`.
  String get _samplePath {
    final language = bundledLanguages[_language]!;
    final names = [_language, ...language.aliases]
      ..sort((a, b) => a.length.compareTo(b.length));
    return 'sample.${names.first}';
  }

  String get _sampleText => samples[_language] ?? '';

  /// A small synthetic edit of [_sampleText] for the diff preview.
  String get _editedSample {
    final lines = _sampleText.split('\n');
    if (lines.length > 2) {
      lines[1] = '${lines[1]} // updated';
    }
    return lines.join('\n');
  }

  void _selectLanguage(String language) {
    setState(() {
      _language = language;
      _collapsedDiff.clear();
      _expandedDiff.clear();
    });
  }

  void _selectTheme(String name) {
    setState(() => _themeName = name);
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
                    child: _Pane(
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
                      child: _contentPane(theme, code),
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

  Widget _contentPane(SyntaxTheme theme, TextStyle code) => switch (_view) {
    _View.preview => HighlightedCode(
      _sampleText,
      language: _language,
      theme: theme,
      textStyle: code,
      lineNumbers: true,
    ),
    _View.diff => PatchView.fromTexts(
      oldText: _sampleText,
      newText: _editedSample,
      path: _samplePath,
      language: _language,
      theme: theme,
      mode: _mode,
      collapsed: _collapsedDiff,
      expanded: _expandedDiff,
      onToggleFile: (file) => setState(() {
        if (!_collapsedDiff.remove(file)) _collapsedDiff.add(file);
      }),
      onExpandGap: (id) => setState(() => _expandedDiff.add(id)),
      textStyle: code.copyWith(fontSize: 12.5),
    ),
    _View.patch => PatchView.fromPatch(
      samplePatch,
      theme: theme,
      mode: _mode,
      collapsed: _collapsedPatch,
      expanded: _expandedPatch,
      onToggleFile: (file) => setState(() {
        if (!_collapsedPatch.remove(file)) _collapsedPatch.add(file);
      }),
      onExpandGap: (id) => setState(() => _expandedPatch.add(id)),
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
        tooltip: 'Sample diff with PatchView.fromTexts',
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
