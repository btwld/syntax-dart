# syntax_example

A read-only preview of `HighlightedCode` and `PatchView`, with a picker for
every bundled language and theme.

Every push to `main` deploys it to <https://btwld.github.io/syntax-dart/>.

```bash
flutter pub get
flutter run -d chrome
```

`pubspec_overrides.yaml` points `syntax` at the sibling package in this
repo. That file is not part of the published package. After `syntax` is on
pub.dev, the example resolves it from there.

It also runs on macOS with `flutter run -d macos`. Fonts load from Google
Fonts, so the first run needs network access.

## Plain WidgetsApp demo

```bash
flutter run -t lib/widgets_app.dart -d chrome
```

This target uses only the widgets layer: no Material theme, localizations or
icon font. It demonstrates selectable code, keyboard folding, the default
selection menu and an injected missing-newline marker. The main demo retains
its Material application controls; the syntax surfaces support either host.

Touch selection handles show a widgets-only magnifier on Android and iOS.
`SyntaxSelectionChrome.magnifierConfiguration` lets the host replace it with
its own controls or disable it with `TextMagnifierConfiguration.disabled`.
