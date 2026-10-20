// Internal: not exported from package:syntax.
// ignore_for_file: public_member_api_docs

// Compiled grammar rules, a port of vscode-textmate's `rule.ts`.
//
// Raw grammar JSON is compiled lazily into numbered rules. Scanners are
// built per rule the first time the rule is on top of the stack.

import '../regex/engine.dart';

/// Pseudo rule id the scanner reports when a rule's `end` pattern matched.
const int endRuleId = -1;

/// Pseudo rule id the scanner reports when a rule's `while` pattern matched.
const int whileRuleId = -2;

final RegExp _captureReference = RegExp(
  r'\$(\d+)|\$\{(\d+):/(downcase|upcase)\}',
);
final RegExp _backReference = RegExp(r'\\(\d+)');
final RegExp _regexSpecial = RegExp(r'[\-\\{}*+?|^$.,\[\]()#\s]');

/// Substitutes `$1` and `${1:/downcase}` in a scope name with capture text.
String _replaceCaptures(String source, ScanMatch match) =>
    source.replaceAllMapped(_captureReference, (m) {
      final index = int.parse(m.group(1) ?? m.group(2)!);
      if (index > match.groupCount) return m.group(0)!;
      var text = match.captureText(index) ?? '';
      // Leading dots would produce an invalid scope selector.
      while (text.startsWith('.')) {
        text = text.substring(1);
      }
      return switch (m.group(3)) {
        'downcase' => text.toLowerCase(),
        'upcase' => text.toUpperCase(),
        _ => text,
      };
    });

/// Resolves `\1`-style references in an `end` or `while` pattern to the
/// escaped text captured by `begin`, as vscode-textmate does.
String _resolveBackReferences(String source, ScanMatch match) =>
    source.replaceAllMapped(_backReference, (m) {
      final index = int.parse(m.group(1)!);
      final text = index <= match.groupCount ? match.captureText(index) : null;
      return (text ?? '').replaceAllMapped(
        _regexSpecial,
        (c) => '\\${c.group(0)}',
      );
    });

sealed class Rule {
  Rule(this.id, this.name, this.contentName)
    : _nameHasCaptures = name != null && _captureReference.hasMatch(name),
      _contentNameHasCaptures =
          contentName != null && _captureReference.hasMatch(contentName);

  final int id;
  final String? name;
  final String? contentName;
  final bool _nameHasCaptures;
  final bool _contentNameHasCaptures;

  String? nameFor(ScanMatch? match) =>
      _nameHasCaptures && match != null ? _replaceCaptures(name!, match) : name;

  String? contentNameFor(ScanMatch match) => _contentNameHasCaptures
      ? _replaceCaptures(contentName!, match)
      : contentName;
}

final class CaptureRule extends Rule {
  CaptureRule(
    super.id,
    super.name,
    super.contentName,
    this.retokenizeCapturedWithRuleId,
  );

  /// When the capture has its own `patterns`, the rule used to tokenize the
  /// captured text. Otherwise 0.
  final int retokenizeCapturedWithRuleId;
}

final class MatchRule extends Rule {
  MatchRule(int id, String? name, this.match, this.captures)
    : super(id, name, null);

  final String match;
  final List<CaptureRule?> captures;
}

/// A rule that has patterns but no regex of its own, such as the grammar
/// root or a repository entry with only `patterns`.
final class IncludeOnlyRule extends Rule {
  IncludeOnlyRule(super.id, super.name, super.contentName);

  late final List<int> patterns;
  late final bool hasMissingPatterns;
}

final class BeginEndRule extends Rule {
  BeginEndRule(
    super.id,
    super.name,
    super.contentName,
    this.begin,
    this.end,
    this.applyEndPatternLast,
  ) : endHasBackReferences = _backReference.hasMatch(end);

  final String begin;
  final String end;
  final bool endHasBackReferences;
  final bool applyEndPatternLast;
  late final List<CaptureRule?> beginCaptures;
  late final List<CaptureRule?> endCaptures;
  late final List<int> patterns;
  late final bool hasMissingPatterns;

  String resolveEnd(ScanMatch beginMatch) =>
      _resolveBackReferences(end, beginMatch);
}

final class BeginWhileRule extends Rule {
  BeginWhileRule(
    super.id,
    super.name,
    super.contentName,
    this.begin,
    this.whilePattern,
  ) : whileHasBackReferences = _backReference.hasMatch(whilePattern);

  final String begin;
  final String whilePattern;
  final bool whileHasBackReferences;
  late final List<CaptureRule?> beginCaptures;
  late final List<CaptureRule?> whileCaptures;
  late final List<int> patterns;
  late final bool hasMissingPatterns;

  String resolveWhile(ScanMatch beginMatch) =>
      _resolveBackReferences(whilePattern, beginMatch);
}

/// A scanner together with the rule id behind each of its patterns.
final class CompiledRule {
  CompiledRule(this.scanner, this.ruleIds);

  final Scanner scanner;
  final List<int> ruleIds;
}

/// Callbacks the rule factory needs from the grammar.
abstract interface class RuleRegistry {
  int registerRule(Rule Function(int id) factory);
  Rule? ruleOrNull(int id);

  /// The initialized raw grammar for [scopeName], used for external
  /// `include`s. Returns `null` if no such grammar is registered.
  Map<String, Object?>? externalGrammar(
    String scopeName,
    Map<String, Object?>? repository,
  );
}

/// Compiles raw grammar rules. A port of vscode-textmate's `RuleFactory`.
final class RuleFactory {
  RuleFactory(this._registry);

  final RuleRegistry _registry;

  /// Ids are tracked by object identity, like vscode-textmate stores
  /// `desc.id` on the raw rule. A repository entry included from many
  /// places compiles once.
  final Map<Object, int> _ids = Map.identity();

  int compiledRuleId(
    Map<String, Object?> desc,
    Map<String, Object?> repository,
  ) {
    final existing = _ids[desc];
    if (existing != null) return existing;
    return _registry.registerRule((id) {
      _ids[desc] = id;
      final repo = desc['repository'] is Map
          ? {...repository, ..._asMap(desc['repository'])}
          : repository;
      final name = desc['name'] as String?;
      final contentName = desc['contentName'] as String?;

      // Like vscode-textmate, empty strings count as absent.
      final match = desc['match'];
      if (match is String && match.isNotEmpty) {
        return MatchRule(id, name, match, _captures(desc['captures'], repo));
      }

      final begin = desc['begin'];
      if (begin is! String) {
        var patterns = desc['patterns'];
        if (patterns == null && desc['include'] is String) {
          patterns = [
            {'include': desc['include']},
          ];
        }
        final rule = IncludeOnlyRule(id, name, contentName);
        final (ids, missing) = _patterns(patterns, repo);
        rule
          ..patterns = ids
          ..hasMissingPatterns = missing;
        return rule;
      }

      final whilePattern = desc['while'];
      if (whilePattern is String && whilePattern.isNotEmpty) {
        final rule = BeginWhileRule(id, name, contentName, begin, whilePattern);
        rule
          ..beginCaptures = _captures(
            desc['beginCaptures'] ?? desc['captures'],
            repo,
          )
          ..whileCaptures = _captures(
            desc['whileCaptures'] ?? desc['captures'],
            repo,
          );
        final (ids, missing) = _patterns(desc['patterns'], repo);
        rule
          ..patterns = ids
          ..hasMissingPatterns = missing;
        return rule;
      }

      final end = desc['end'];
      final rule = BeginEndRule(
        id,
        name,
        contentName,
        begin,
        end is String && end.isNotEmpty ? end : '\uFFFF',
        desc['applyEndPatternLast'] == true || desc['applyEndPatternLast'] == 1,
      );
      rule
        ..beginCaptures = _captures(
          desc['beginCaptures'] ?? desc['captures'],
          repo,
        )
        ..endCaptures = _captures(
          desc['endCaptures'] ?? desc['captures'],
          repo,
        );
      final (ids, missing) = _patterns(desc['patterns'], repo);
      rule
        ..patterns = ids
        ..hasMissingPatterns = missing;
      return rule;
    });
  }

  List<CaptureRule?> _captures(Object? raw, Map<String, Object?> repository) {
    // Captures are usually a map keyed by group number. Some grammars use
    // a list, which JavaScript's `for...in` also iterates by index.
    final Map<String, Object?> captures;
    if (raw is List) {
      captures = {for (var i = 0; i < raw.length; i++) '$i': raw[i]};
    } else if (raw is Map) {
      captures = _asMap(raw);
    } else {
      return const [];
    }
    var max = -1;
    for (final key in captures.keys) {
      final n = int.tryParse(key);
      if (n != null && n > max) max = n;
    }
    final result = List<CaptureRule?>.filled(max + 1, null);
    for (final MapEntry(:key, :value) in captures.entries) {
      final n = int.tryParse(key);
      if (n == null || value is! Map) continue;
      final capture = _asMap(value);
      final retokenize = capture['patterns'] != null
          ? compiledRuleId(capture, repository)
          : 0;
      final id = _registry.registerRule(
        (id) => CaptureRule(
          id,
          capture['name'] as String?,
          capture['contentName'] as String?,
          retokenize,
        ),
      );
      result[n] = _registry.ruleOrNull(id) as CaptureRule?;
    }
    return result;
  }

  (List<int>, bool) _patterns(Object? raw, Map<String, Object?> repository) {
    if (raw is! List) return (const [], false);
    final result = <int>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final pattern = _asMap(item);
      final ruleId = _patternRuleId(pattern, repository);
      if (ruleId == -1) continue;
      final rule = _registry.ruleOrNull(ruleId);
      final empty = switch (rule) {
        IncludeOnlyRule(:final hasMissingPatterns, :final patterns) =>
          hasMissingPatterns && patterns.isEmpty,
        BeginEndRule(:final hasMissingPatterns, :final patterns) =>
          hasMissingPatterns && patterns.isEmpty,
        BeginWhileRule(:final hasMissingPatterns, :final patterns) =>
          hasMissingPatterns && patterns.isEmpty,
        _ => false,
      };
      if (!empty) result.add(ruleId);
    }
    return (result, raw.length != result.length);
  }

  int _patternRuleId(
    Map<String, Object?> pattern,
    Map<String, Object?> repository,
  ) {
    final include = pattern['include'];
    if (include is! String) return compiledRuleId(pattern, repository);

    if (include == r'$base' || include == r'$self') {
      final target = repository[include];
      return target is Map ? compiledRuleId(_asMap(target), repository) : -1;
    }
    if (include.startsWith('#')) {
      final target = repository[include.substring(1)];
      return target is Map ? compiledRuleId(_asMap(target), repository) : -1;
    }
    // `source.lang` or `source.lang#rule`.
    final hash = include.indexOf('#');
    final scopeName = hash < 0 ? include : include.substring(0, hash);
    final ruleName = hash < 0 ? null : include.substring(hash + 1);
    final external = _registry.externalGrammar(scopeName, repository);
    if (external == null) return -1;
    final externalRepository = _asMap(external['repository']);
    final target = externalRepository[ruleName ?? r'$self'];
    return target is Map
        ? compiledRuleId(_asMap(target), externalRepository)
        : -1;
  }
}

Map<String, Object?> _asMap(Object? value) => value is Map<String, Object?>
    ? value
    : value is Map
    ? value.cast<String, Object?>()
    : const {};
