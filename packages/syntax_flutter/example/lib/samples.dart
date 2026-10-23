// Starting text for each language in the demo.

const samples = <String, String>{
  'dart': r'''
import 'package:flutter/material.dart';

/// A counter that knows its [label].
sealed class Event {}

final class Tapped extends Event {
  Tapped(this.count);
  final int count;
}

class Counter extends StatefulWidget {
  const Counter({super.key, this.label = 'Taps'});
  final String label;

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  var _count = 0;

  String describe(Event event) => switch (event) {
        Tapped(:final count) when count > 9 => 'many ($count)',
        Tapped(:final count) => '${widget.label}: $count',
      };

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => _count++),
        child: Text(describe(Tapped(_count))),
      );
}
''',
  'yaml': r'''
name: syntax_example
description: >-
  Live editor and preview for syntax_flutter.
publish_to: none
version: 1.0.0+1

environment:
  sdk: ^3.9.0

dependencies:
  flutter:
    sdk: flutter
  syntax_flutter: ^0.1.0 # TextMate grammars
  google_fonts: &fonts ^9.0.0

flutter:
  uses-material-design: true
''',
  'json': r'''
{
  "name": "syntax",
  "version": "0.1.0",
  "grammars": ["dart", "json", "yaml", "markdown"],
  "conformance": { "samples": 21, "matchesShiki": true },
  "speedMBps": 11.3,
  "license": null
}
''',
  'markdown': r'''
# syntax

Syntax highlighting for **Dart** and _Flutter_, using the same
TextMate grammars as [VS Code](https://code.visualstudio.com).

- Pure Dart core
- `HighlightedCode` and `PatchView`

```dart
final highlighter = Highlighter(languages: [dartLanguage]);
print(highlighter.toAnsi(code, language: 'dart', theme: githubDarkTheme));
```

> Embedded code blocks use their own grammar.
''',
  'shellscript': r'''
#!/usr/bin/env bash
set -euo pipefail

for pkg in packages/*/; do
  echo "Testing ${pkg%/}"
  (cd "$pkg" && dart test --reporter=compact) || exit 1
done
''',
  'typescript': r'''
type Token = { start: number; end: number; scopes: string[] };

export async function highlight(code: string, lang = 'ts'): Promise<Token[]> {
  const lines = code.split(/\r?\n/);
  return lines.flatMap((line, i) => tokenize(line, i));
}
''',
  'kotlin': r'''
data class Token(val start: Int, val end: Int, val scope: String)

fun main() {
    val tokens = listOf(Token(0, 5, "keyword"))
    println("Found ${tokens.size} tokens")
}
''',
  'swift': r'''
struct Token: Hashable {
    let range: Range<Int>
    var scope: String
}

let tokens = [Token(range: 0..<5, scope: "keyword")]
print("Found \(tokens.count) tokens")
''',
  'python': r'''
from dataclasses import dataclass

@dataclass
class Token:
    start: int
    end: int
    scope: str = "source"

print(f"{Token(0, 5)!r}")
''',
  'rust': r'''
#[derive(Debug, Clone)]
struct Token<'a> { range: std::ops::Range<usize>, scope: &'a str }

fn main() {
    let t = Token { range: 0..5, scope: "keyword" };
    println!("{:?}", t);
}
''',
  'go': r'''
package main

import "fmt"

type Token struct {
	Start, End int
	Scope      string
}

func main() {
	fmt.Println(Token{0, 5, "keyword"})
}
''',
  'sql': r'''
SELECT name, COUNT(*) AS uses
FROM grammars g
JOIN packages p ON p.id = g.package_id
WHERE p.platform IN ('web', 'ios') -- Flutter targets
GROUP BY name
ORDER BY uses DESC;
''',
  'html': r'''
<!doctype html>
<html lang="en">
  <body>
    <pre class="syntax"><code>final x = 1;</code></pre>
    <script>console.log("highlighted")</script>
  </body>
</html>
''',
  'css': r'''
.syntax {
  font-family: "JetBrains Mono", monospace;
  background: #0d1117;
  padding: 16px;
}
.syntax .line:hover { background: rgb(255 255 255 / 4%); }
''',
};

/// An illustrative `git diff -M` of a small app: a modified widget and
/// pubspec, an added README, a deleted script and a renamed file.
const samplePatch = r'''
diff --git a/README.md b/README.md
new file mode 100644
index 0000000..367117d
--- /dev/null
+++ b/README.md
@@ -0,0 +1,7 @@
+# counter_app
+
+Tap to count, long-press to reset.
+
+```bash
+flutter run -d chrome
+```
diff --git a/lib/theme.dart b/lib/app_theme.dart
similarity index 100%
rename from lib/theme.dart
rename to lib/app_theme.dart
diff --git a/lib/counter.dart b/lib/counter.dart
index 58ad70c..16a9f09 100644
--- a/lib/counter.dart
+++ b/lib/counter.dart
@@ -1,22 +1,28 @@
 import 'package:flutter/material.dart';
 
 class Counter extends StatefulWidget {
-  const Counter({super.key});
+  const Counter({super.key, this.step = 1});
+
+  /// How much each tap adds.
+  final int step;
 
   @override
   State<Counter> createState() => _CounterState();
 }
 
 class _CounterState extends State<Counter> {
-  int count = 0;
+  int total = 0;
+
+  void increment() => setState(() => total += widget.step);
 
-  void increment() => setState(() => count++);
+  void reset() => setState(() => total = 0);
 
   @override
   Widget build(BuildContext context) {
     return TextButton(
       onPressed: increment,
-      child: Text('Count: $count'),
+      onLongPress: reset,
+      child: Text('Total: $total'),
     );
   }
 }
diff --git a/pubspec.yaml b/pubspec.yaml
index 8b5f2d2..09ab0df 100644
--- a/pubspec.yaml
+++ b/pubspec.yaml
@@ -1,9 +1,10 @@
 name: counter_app
-version: 1.0.0
+version: 1.1.0
 
 environment:
-  sdk: ^3.8.0
+  sdk: ^3.9.0
 
 dependencies:
   flutter:
     sdk: flutter
+  syntax_flutter: ^0.1.0
diff --git a/tool/release.sh b/tool/release.sh
deleted file mode 100644
index 1873297..0000000
--- a/tool/release.sh
+++ /dev/null
@@ -1,3 +0,0 @@
-#!/usr/bin/env bash
-set -e
-flutter build web --release
''';
