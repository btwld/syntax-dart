import 'dart:async';
import 'package:syntax/syntax.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:test/test.dart';

void main() {
  final highlighter = Highlighter(languages: [dartLanguage]);
  test('static file HTML escapes source and decorations in every palette', () {
    final html = renderFileHtml(
      const SourceFile(
        id: 'a"',
        path: '<x>.dart',
        text: 'final x = "<script>";\r\n',
      ),
      highlighter: highlighter,
      themes: {'light': githubLightTheme, 'dark': githubDarkTheme},
      decorate: (_, _) =>
          const HtmlDecoration(title: '"><script>', before: '<b>'),
    );
    expect(html, contains('--syntax-background:'));
    expect(html, contains('data-theme="dark"'));
    expect(html, isNot(contains('<script>')));
    expect(html, contains('&lt;b&gt;'));
    expect(html, contains('data-file="a&quot;"'));
    final diff = renderDiffHtml(
      [diffTexts('old\n', 'new\n', path: 'a.dart')],
      highlighter: highlighter,
      themes: {'dark': githubDarkTheme},
      mode: DiffMode.split,
    );
    expect(diff, contains('class="removed '));
    expect(diff, contains('class="added '));
  });
  test('ANSI styling strips executable controls and resolves SGR resets', () {
    final tokens = parseAnsi(
      '\x1b[31mred\x1b[0m normal\x1b]52;c;YWJj\x07\x1b[2J\n\x1b[38;2;1;2;3mtruecolor',
      theme: githubDarkTheme,
    );
    expect(tokens.first.map((t) => t.text).join(), 'red normal');
    expect(tokens.first.first.style.foreground, 0xffcd3131);
    expect(tokens.first.last.style.foreground, githubDarkTheme.foreground);
    expect(tokens.last.single.style.foreground, 0xff010203);
    expect(
      tokens.expand((l) => l).map((t) => t.text).join(),
      isNot(contains('\x1b')),
    );
  });
  test(
    'viewport requests retain grammar state without offscreen tokens',
    () async {
      final request = HighlightRequest(
        file: const SourceFile(
          id: 'f',
          path: 'a.dart',
          text: '/*\ninside\n*/\nfinal a = 1;',
        ),
        languages: [dartLanguage],
        theme: githubDarkTheme,
        startLine: 1,
        endLine: 2,
      );
      final result = computeHighlight(request);
      expect(result.startLine, 1);
      expect(result.lines, hasLength(1));
      expect(
        result.lines.single.first.scopes.scopes.any(
          (s) => s.startsWith('comment'),
        ),
        isTrue,
      );
      final json = result.toJson();
      expect(HighlightResult.fromJson(json).toJson(), json);
    },
  );
  test('presentation rejects stale revision and grammar results', () async {
    final editor = EditorController(
      file: const SourceFile(id: 'a', path: 'a.dart', text: 'old'),
    );
    final executor = _Delayed();
    final presentation = PresentationController(
      editor: editor,
      highlighter: highlighter,
      theme: githubDarkTheme,
      executor: executor,
    );
    final first = presentation.flush();
    editor.insertText('new');
    final second = presentation.flush();
    executor.requests[0].$2.complete(computeHighlight(executor.requests[0].$1));
    await first;
    expect(presentation.snapshot, isNull);
    executor.requests[1].$2.complete(computeHighlight(executor.requests[1].$1));
    await second;
    expect(presentation.snapshot?.revision, editor.document.revision);
    final count = executor.requests.length;
    presentation.theme = githubLightTheme;
    expect(executor.requests.length, count);
    expect(
      presentation.snapshot?.lines.single.map((t) => t.text).join(),
      'newold',
    );
    presentation.dispose();
    editor.dispose();
  });
  for (final ending in ['\n', '\r\n', '\r']) {
    test(
      'stream retains completed line colors with ${ending.codeUnits}',
      () async {
        final stream = StreamDocumentController(
          SourceFile(
            id: 'stream',
            path: 'stream.dart',
            text: 'final stable = 1;$ending/*$ending',
          ),
        );
        final executor = _Delayed();
        final presentation = PresentationController(
          editor: stream.editor,
          highlighter: highlighter,
          theme: githubDarkTheme,
          executor: executor,
          overscan: 0,
        );
        addTearDown(() {
          presentation.dispose();
          stream.dispose();
        });
        presentation.setViewport(0, 3);
        final initial = presentation.flush();
        executor.complete(0);
        await initial;
        final stable = presentation.line(0)!.first;
        stream.add('comment 🙂');
        expect(presentation.line(0)!.first, same(stable));
        expect(presentation.line(1), isNotNull);
        expect(presentation.line(2), isNull);
        final pending = presentation.flush();
        stream.add('$ending*/');
        expect(presentation.line(0)!.first, same(stable));
        expect(
          presentation.snapshot!.revision,
          stream.editor.document.revision,
        );
        presentation.setViewport(0, stream.editor.document.lineCount);
        final latest = presentation.flush();
        executor.complete(1);
        await pending;
        expect(presentation.line(0)!.first, same(stable));
        expect(presentation.line(2), isNull);
        executor.complete(2);
        await latest;
        expect(
          presentation.snapshot!.toJson(),
          computeHighlight(executor.requests.last.$1).toJson(),
        );
        stream.replaceProvisional('*/ // done');
        expect(presentation.line(0), isNotNull);
        expect(presentation.line(2), isNotNull);
        expect(presentation.line(3), isNull);
        final complete = presentation.flush();
        executor.complete(3);
        await complete;
        stream.finish();
        expect(
          presentation.snapshot!.toJson(),
          computeHighlight(executor.requests.last.$1).toJson(),
        );
      },
    );
  }
  test(
    'editing grammar state invalidates the suffix of a retained window',
    () async {
      final editor = EditorController(
        file: const SourceFile(
          id: 'edit',
          path: 'edit.dart',
          text: '// before\nfinal stable = 1;\n/* comment\nstill comment\n*/',
        ),
      );
      final executor = _Delayed();
      final presentation = PresentationController(
        editor: editor,
        highlighter: highlighter,
        theme: githubDarkTheme,
        executor: executor,
        overscan: 0,
      );
      addTearDown(() {
        presentation.dispose();
        editor.dispose();
      });
      presentation.setViewport(1, 5);
      final initial = presentation.flush();
      executor.complete(0);
      await initial;
      editor.document.applyEdits([
        const DocumentEdit(
          DocumentRange(DocumentPosition(2, 0), DocumentPosition(2, 2)),
          '//',
        ),
      ]);
      expect(presentation.snapshot!.startLine, 1);
      expect(presentation.line(1), isNotNull);
      expect(presentation.line(2), isNull);
      expect(presentation.line(3), isNull);
      final changed = presentation.flush();
      executor.complete(1);
      await changed;
      expect(
        presentation.snapshot!.toJson(),
        computeHighlight(executor.requests.last.$1).toJson(),
      );
      editor.document.applyOffsetEdits([const OffsetEdit(0, 0, '/*')]);
      expect(presentation.snapshot, isNull);
    },
  );
  test(
    'consumer cancellation is immediate and cache clearing rejects inflight results',
    () async {
      final executor = _Delayed();
      final pool = HighlightPool(executor: executor);
      final request = HighlightRequest(
        file: const SourceFile(id: 'a', path: 'a.dart', text: 'a'),
        languages: [dartLanguage],
        theme: githubDarkTheme,
      );
      final cancellation = CancellationToken();
      final a = pool.highlight(request, cancellation: cancellation);
      final b = pool.highlight(request);
      cancellation.cancel();
      await expectLater(a, throwsA(isA<OperationCancelled>()));
      pool.clearCache();
      executor.requests.single.$2.complete(computeHighlight(request));
      await b;
      expect(pool.stats.cached, 0);
      pool.dispose();
    },
  );
}

class _Delayed implements HighlightExecutor {
  final requests = <(HighlightRequest, Completer<HighlightResult>)>[];
  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) {
    final completer = Completer<HighlightResult>();
    requests.add((request, completer));
    return completer.future;
  }

  void complete(int index) =>
      requests[index].$2.complete(computeHighlight(requests[index].$1));

  @override
  void dispose() {}
}
