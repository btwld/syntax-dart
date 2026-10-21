# syntax_example

A live editor next to a read-only preview, with a picker for every bundled
language and theme. The editor uses `SyntaxTextEditingController` and the
preview uses `HighlightedCode`.

Every push to `main` deploys it to <https://btwld.github.io/syntax-dart/>.

```bash
flutter run -d chrome
```

It also runs on macOS with `flutter run -d macos`. Fonts load from Google
Fonts, so the first run needs network access.
