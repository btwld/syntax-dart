import 'dart:async';
import 'dart:math' as math;
import '../edit/text_document.dart';
import 'theme.dart';

/// Policy selecting a light or dark theme.
enum SyntaxColorMode {
  /// Always use the light palette.
  light,

  /// Always use the dark palette.
  dark,

  /// Follow the renderer-supplied system appearance.
  system,
}

/// Lazy catalog metadata for a named theme and its collection.
final class ThemeDescriptor {
  /// Lazy catalog metadata for a named theme and its collection.
  const ThemeDescriptor({
    required this.name,
    required this.load,
    required this.isDark,
    this.collection = '',
    this.displayName,
  });

  /// Stable theme identifier and the collection it belongs to.
  final String name, collection;

  /// Optional human-readable theme label.
  final String? displayName;

  /// Whether the selected palette uses a dark background.
  final bool isDark;

  /// Asynchronous loader for this catalog entry.
  final Future<SyntaxTheme> Function() load;
}

/// Immutable catalog metadata does not load theme data until resolution.
final class ThemeCollection {
  /// Creates a deduplicated collection of lazy theme descriptors.
  ThemeCollection(Iterable<ThemeDescriptor> entries)
    : entries = List.unmodifiable(entries) {
    if (this.entries.map((e) => e.name).toSet().length != this.entries.length) {
      throw ArgumentError('Duplicate theme names');
    }
  }

  /// Theme descriptors in collection order.
  final List<ThemeDescriptor> entries;

  /// Filters descriptors by collection name and optional brightness.
  ThemeCollection where({String? collection, bool? isDark}) => ThemeCollection(
    entries.where(
      (e) =>
          (collection == null || e.collection == collection) &&
          (isDark == null || e.isDark == isDark),
    ),
  );

  /// Keeps only themes whose identifiers occur in the supplied names.
  ThemeCollection pick(Iterable<String> names) => ThemeCollection([
    for (final name in names) entries.firstWhere((e) => e.name == name),
  ]);

  /// Returns a new collection sorted by the supplied descriptor comparator.
  ThemeCollection sorted(
    int Function(ThemeDescriptor, ThemeDescriptor) compare,
  ) => ThemeCollection(entries.toList()..sort(compare));

  /// Installs every descriptor loader into the resolver.
  void registerInto(ThemeResolver resolver) {
    for (final e in entries) {
      resolver.register(e.name, e.load);
    }
  }
}

/// In-flight work is deduplicated, retries are allowed, and clearing a cache
/// prevents old asynchronous loads from repopulating it.
final class ThemeResolver {
  final Map<String, Future<SyntaxTheme> Function()> _loaders = {};
  final Map<String, SyntaxTheme> _resolved = {};
  final Map<String, Future<SyntaxTheme>> _pending = {};
  int _generation = 0;

  /// Registers a lazy loader; duplicate names throw to prevent ambiguous resolution.
  void register(String name, Future<SyntaxTheme> Function() loader) {
    if (_loaders.containsKey(name)) {
      throw ArgumentError('Duplicate theme: $name');
    }
    _loaders[name] = loader;
  }

  /// Installs an already loaded theme without invoking a loader.
  void seed(SyntaxTheme theme) => _resolved[theme.name] = theme;

  /// Returns a loaded theme, or null while it remains unloaded.
  SyntaxTheme? resolved(String name) => _resolved[name];

  /// Resolves one theme, deduplicating simultaneous calls for the same identifier.
  Future<SyntaxTheme> resolve(String name) {
    final cached = _resolved[name];
    if (cached != null) return Future.value(cached);
    final loader = _loaders[name];
    if (loader == null) {
      return Future.error(ArgumentError('Unknown theme: $name'));
    }
    final generation = _generation;
    return _pending.putIfAbsent(
      name,
      () => Future.sync(loader)
          .then((theme) {
            if (generation == _generation) _resolved[name] = theme;
            return theme;
          })
          .whenComplete(() {
            if (generation == _generation) _pending.remove(name);
          }),
    );
  }

  /// Resolves requested themes while sharing duplicate in-flight loads.
  Future<List<SyntaxTheme>> resolveAll(Iterable<String> names) =>
      Future.wait(names.map(resolve));

  /// Invalidates loaded and in-flight theme results while retaining registered loaders.
  void clear() {
    _generation++;
    _resolved.clear();
    _pending.clear();
  }
}

/// Specifies light and dark palette identifiers and a brightness policy.
final class ThemeSelection {
  /// Specifies light and dark palette identifiers and a brightness policy.
  const ThemeSelection({
    required this.light,
    required this.dark,
    this.mode = SyntaxColorMode.system,
  });

  /// Theme identifiers used in light and dark appearance respectively.
  final String light, dark;

  /// Policy selecting the light, dark or system appearance.
  final SyntaxColorMode mode;

  /// Encodes portable data for storage or transport to another executor.
  Map<String, Object?> toJson() => {
    'light': light,
    'dark': dark,
    'mode': mode.name,
  };

  /// Restores a value from its portable serialized representation.
  factory ThemeSelection.fromJson(Map<String, Object?> json) => ThemeSelection(
    light: json['light'] as String,
    dark: json['dark'] as String,
    mode: SyntaxColorMode.values.byName(json['mode'] as String),
  );
}

/// Application-owned asynchronous storage for theme preferences.
abstract interface class ThemePersistence {
  /// Loads the application-defined persisted or catalog value asynchronously.
  Future<ThemeSelection?> load();

  /// Persists the selected light/dark palettes and appearance policy.
  Future<void> save(ThemeSelection selection);
}

/// Runtime theme selection. Platforms supply their brightness and persistence;
/// the core never reads a window, operating system, or storage service.
final class SyntaxThemeController extends SyntaxObservable {
  /// Resolves appearance changes and ignores obsolete asynchronous loads.
  SyntaxThemeController({
    required this.resolver,
    required ThemeSelection selection,
    this.persistence,
    this.systemIsDark = false,
  }) : _selection = selection;

  /// Shared lazy loader and resolved-theme cache.
  final ThemeResolver resolver;

  /// Optional application-owned preference storage.
  final ThemePersistence? persistence;
  ThemeSelection _selection;

  /// Current light/dark identifiers and appearance policy.
  ThemeSelection get selection => _selection;

  /// Latest system appearance supplied by the renderer.
  bool systemIsDark;

  /// Palette used to resolve token scopes into presentation styles.
  SyntaxTheme? theme;

  /// Most recent asynchronous loading failure, or null.
  Object? error;

  /// Whether the active appearance selection is resolving.
  bool loading = false;
  int _request = 0;
  Future<void> _saving = Future.value();

  /// Effective brightness after applying the selected appearance policy.
  bool get isDark => switch (selection.mode) {
    SyntaxColorMode.light => false,
    SyntaxColorMode.dark => true,
    SyntaxColorMode.system => systemIsDark,
  };

  /// Restores persisted preferences and resolves the effective palette.
  Future<void> initialize() async {
    final initial = _request;
    final saved = await persistence?.load();
    if (isDisposed || initial != _request) return;
    if (saved != null) _selection = saved;
    await _resolve();
  }

  /// Persists the new preference and resolves its effective palette.
  Future<void> select(ThemeSelection selection) async {
    checkAlive();
    _selection = selection;
    _saving = _saving
        .catchError((Object _) {})
        .then((_) => persistence?.save(selection));
    await _resolve();
    try {
      await _saving;
    } on Object catch (e) {
      if (!isDisposed) {
        error = e;
        notifyListeners();
      }
    }
  }

  /// Updates system appearance and reloads only when system mode is selected.
  Future<void> setSystemBrightness(bool dark) async {
    systemIsDark = dark;
    if (selection.mode == SyntaxColorMode.system) await _resolve();
  }

  Future<void> _resolve() async {
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final next = await resolver.resolve(
        isDark ? selection.dark : selection.light,
      );
      if (isDisposed || request != _request) return;
      theme = next;
    } on Object catch (e) {
      if (!isDisposed && request == _request) error = e;
    } finally {
      if (!isDisposed && request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }
}

/// Converts semantic syntax categories and editor colors to TextMate selectors.
SyntaxTheme themeFromZed(Map<String, Object?> json, {String? name}) {
  final family = json['themes'];
  if (family is List && family.isNotEmpty) {
    return themeFromZed(
      Map<String, Object?>.from(family.first as Map),
      name: name,
    );
  }
  final style = Map<String, Object?>.from(json['style'] as Map? ?? const {});
  final syntax = Map<String, Object?>.from(style['syntax'] as Map? ?? const {});
  const scopes = <String, String>{
    'attribute': 'entity.other.attribute-name',
    'boolean': 'constant.language.boolean',
    'comment': 'comment',
    'comment.doc': 'comment.documentation',
    'constant': 'constant',
    'constructor': 'entity.name.type',
    'embedded': 'meta.embedded',
    'enum': 'entity.name.type.enum',
    'function': 'entity.name.function',
    'function.method': 'entity.name.function.member',
    'keyword': 'keyword',
    'label': 'entity.name.label',
    'number': 'constant.numeric',
    'operator': 'keyword.operator',
    'property': 'variable.other.property',
    'punctuation': 'punctuation',
    'string': 'string',
    'string.escape': 'constant.character.escape',
    'string.regex': 'string.regexp',
    'tag': 'entity.name.tag',
    'type': 'entity.name.type',
    'variable': 'variable',
    'variable.special': 'variable.language',
  };
  return SyntaxTheme.fromJson({
    'name': name ?? json['name'] ?? 'custom',
    'type': json['appearance'],
    'colors': <String, Object?>{
      for (final entry in style.entries)
        if (entry.key != 'syntax') entry.key: entry.value,
      'editor.background': style['editor.background'] ?? style['background'],
      'editor.foreground':
          style['editor.foreground'] ?? style['text'] ?? style['foreground'],
      'editor.lineHighlightBackground': style['editor.active_line.background'],
      'editorError.foreground': style['error'],
      'editorWarning.foreground': style['warning'],
    },
    'tokenColors': [
      for (final entry in syntax.entries)
        {
          'scope': scopes[entry.key] ?? entry.key,
          'settings': entry.value is String
              ? {'foreground': entry.value}
              : {
                  'foreground': (entry.value as Map)['color'],
                  'fontStyle': [
                    if ((entry.value as Map)['font_style'] == 'italic')
                      'italic',
                    if (((entry.value as Map)['font_weight'] as num? ?? 400) >=
                        600)
                      'bold',
                  ].join(' '),
                },
        },
    ],
  });
}

/// Computes linearized sRGB relative luminance for an ARGB color.
double relativeLuminance(int argb) {
  double channel(int shift) {
    final c = ((argb >> shift) & 255) / 255;
    return c <= .04045
        ? c / 12.92
        : math.pow((c + .055) / 1.055, 2.4).toDouble();
  }

  return .2126 * channel(16) + .7152 * channel(8) + .0722 * channel(0);
}

/// Computes the WCAG contrast ratio of two opaque sRGB colors.
double contrastRatio(int a, int b) {
  final x = relativeLuminance(a), y = relativeLuminance(b);
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

/// Chooses the candidate with the highest contrast against the background.
int readableForeground(int background, Iterable<int> candidates) {
  final sorted = candidates.toList()
    ..sort(
      (a, b) =>
          contrastRatio(b, background).compareTo(contrastRatio(a, background)),
    );
  if (sorted.isEmpty) {
    throw ArgumentError('At least one foreground is required');
  }
  return sorted.first;
}

/// Project-owned palette families available in both appearances.
enum SyntaxPaletteVariant {
  /// Balanced default syntax and review colors.
  standard,

  /// Lower-saturation syntax accents.
  soft,

  /// More saturated syntax accents.
  vibrant,

  /// Blue/orange review accents for red/green differentiation.
  redGreen,

  /// Magenta/green review accents for blue/yellow differentiation.
  blueYellow,
}

/// Project-owned palettes use hue as a supplement to diff markers and labels.
SyntaxTheme createSyntaxTheme({
  bool dark = true,
  SyntaxPaletteVariant variant = SyntaxPaletteVariant.standard,
}) {
  final bg = dark ? 0xff171b24 : 0xfffafbfe;
  final fg = dark ? 0xffe7eaf2 : 0xff202636;
  final accent = switch (variant) {
    SyntaxPaletteVariant.redGreen => dark ? 0xff70bcff : 0xff00569a,
    SyntaxPaletteVariant.blueYellow => dark ? 0xffff92cb : 0xff8d245c,
    SyntaxPaletteVariant.soft => dark ? 0xffb3c4df : 0xff435d83,
    SyntaxPaletteVariant.vibrant => dark ? 0xffc79cff : 0xff7734a4,
    SyntaxPaletteVariant.standard => dark ? 0xff92afff : 0xff3559a3,
  };
  final string = variant == SyntaxPaletteVariant.redGreen
      ? (dark ? 0xffffce82 : 0xff805300)
      : (dark ? 0xff8fdbb2 : 0xff226142);
  return SyntaxTheme.fromJson({
    'name': 'syntax-${dark ? 'dark' : 'light'}-${variant.name}',
    'type': dark ? 'dark' : 'light',
    'colors': {
      'editor.background': colorToHex(bg),
      'editor.foreground': colorToHex(fg),
      'editorLineNumber.foreground': colorToHex(dark ? 0xff9aa7bf : 0xff626f87),
      'editorGutter.addedBackground': colorToHex(
        variant == SyntaxPaletteVariant.redGreen ? accent : string,
      ),
      'editorGutter.deletedBackground': colorToHex(
        variant == SyntaxPaletteVariant.blueYellow
            ? accent
            : (dark ? 0xffe9a275 : 0xff985122),
      ),
      'diffEditor.insertedTextBackground': colorToHex(
        ((variant == SyntaxPaletteVariant.redGreen ? accent : string) &
                0xffffff) |
            0x55000000,
      ),
      'diffEditor.removedTextBackground': colorToHex(
        ((variant == SyntaxPaletteVariant.blueYellow
                    ? accent
                    : (dark ? 0xffe9a275 : 0xff985122)) &
                0xffffff) |
            0x55000000,
      ),
    },
    'tokenColors': [
      {
        'scope': 'keyword, storage, entity.name.function',
        'settings': {'foreground': colorToHex(accent)},
      },
      {
        'scope': 'string, constant.numeric',
        'settings': {'foreground': colorToHex(string)},
      },
      {
        'scope': 'comment',
        'settings': {
          'foreground': dark ? '#a1adbf' : '#5c697b',
          'fontStyle': 'italic',
        },
      },
    ],
  });
}
