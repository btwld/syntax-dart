import 'dart:io';

/// Large combined scanners can crash the Dart 3.9 native RegExp JIT.
/// Individual scanners have equivalent precedence and avoid this compiler path.
final bool supportsCombinedRegex = !Platform.version.startsWith('3.9.');
