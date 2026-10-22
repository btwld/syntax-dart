import 'dart:async';
import 'dart:convert';
import 'package:syntax/syntax.dart';
import 'package:syntax/langs/dart.dart';
import 'package:syntax/langs/catalog.dart';
import 'package:syntax/themes/github_dark.dart';
import 'package:syntax/themes/github_light.dart';
import 'package:test/test.dart';

void main() {
  final highlighter = Highlighter(languages: [dartLanguage]);
  const source = '/* 😀\r\ncomment\rends */\nfinal x = "héllo";\n';
  test('every UTF-8 split yields identical completed highlighting', () {
    final bytes = utf8.encode(source);
    final expected = computeHighlight(
      HighlightRequest(
        file: const SourceFile(id: 'stream', path: 'a.dart', text: source),
        languages: [dartLanguage],
        theme: githubDarkTheme,
      ),
    );
    for (var split = 0; split <= bytes.length; split++) {
      final stream = StreamingHighlighter(
        grammar: highlighter.grammar('dart'),
        theme: githubDarkTheme,
      );
      final lines = [
        ...stream.push(bytes.sublist(0, split)),
        ...stream.push(bytes.sublist(split)),
        ...stream.finish(),
      ];
      expect(
        lines.map((l) => l.text).toList(),
        expected.lines.map((l) => l.map((t) => t.text).join()).toList(),
        reason: 'split $split',
      );
      for (var i = 0; i < lines.length; i++) {
        expect(
          [
            for (final t in lines[i].tokens)
              for (final c in t.text.codeUnits) (c, t.style),
          ],
          [
            for (final t in expected.lines[i])
              for (final c in t.text.codeUnits) (c, t.style),
          ],
          reason: 'split $split line $i',
        );
      }
    }
  });
  test(
    'live highlighting reuses unaffected lines across revisions and themes',
    () {
      final document = TextDocument('final a = 1;\nfinal b = 2;\nfinal c = 3;');
      final session = LiveHighlighter(document, highlighter.grammar('dart'))
        ..pause()
        ..flush();
      final before = session.line(2);
      document.applyOffsetEdits([const OffsetEdit(10, 11, '9')]);
      session.flush();
      expect(identical(before, session.line(2)), isTrue);
      session.themedLine(2, githubLightTheme);
      expect(identical(before, session.line(2)), isTrue);
      session.dispose();
      document.dispose();
    },
  );
  test(
    'stream controller handles provisional line, completion and cancellation',
    () async {
      final controller = StreamDocumentController(
        const SourceFile(id: 's', path: 'a.dart', text: ''),
      );
      for (final byte in utf8.encode('a\r\n😀')) {
        controller.add([byte]);
      }
      controller.replaceProvisional('done');
      controller.finish();
      expect(controller.editor.document.text, 'a\r\ndone');
      expect(controller.isComplete, isTrue);
      expect(() => controller.add('late'), throwsStateError);
      controller.dispose();
      final cancelled = StreamDocumentController(
        const SourceFile(id: 'x', path: '', text: ''),
      );
      final input = StreamController<Object>();
      final bound = cancelled.bind(input.stream);
      cancelled.cancel();
      await bound;
      await input.close();
      cancelled.dispose();
    },
  );
  test('lazy dependency closure is shared and aliases resolve', () async {
    final registry = createBundledLanguageRegistry(Highlighter());
    final results = await Future.wait([
      registry.resolve('js'),
      registry.resolve('javascript'),
    ]);
    expect(identical(results.first, results.last), isTrue);
    await registry.resolve('vue');
    expect(registry.highlighter.language('vue-directives'), isNotNull);
    expect(
      registry.highlighter.grammar('vue').tokenizeLine('<template>').tokens,
      isNotEmpty,
    );
  });
  test(
    'theme loading shares pending work and stale selections are discarded',
    () async {
      var calls = 0;
      final gate = Completer<SyntaxTheme>();
      final resolver = (ThemeResolver()
        ..register('slow', () {
          calls++;
          return gate.future;
        })
        ..register('light', () async => githubLightTheme));
      final a = resolver.resolve('slow'), b = resolver.resolve('slow');
      gate.complete(githubDarkTheme);
      expect(await a, same(await b));
      expect(calls, 1);
      final imported = themeFromZed({
        'name': 'Custom',
        'appearance': 'dark',
        'style': {
          'editor.background': '#112233',
          'editor.foreground': '#eeeeee',
          'syntax': {
            'comment': {'color': '#8899aa', 'font_style': 'italic'},
          },
        },
      });
      expect(imported.background, 0xff112233);
      expect(
        imported
            .styleFor(ScopeStack.root('source.dart').push('comment.line'))
            .italic,
        isTrue,
      );
    },
  );
  test(
    'executors serialize equivalent results and pool shares requests',
    () async {
      final request = HighlightRequest(
        file: const SourceFile(
          id: 'a',
          path: 'x.dart',
          text: source,
          revision: 9,
        ),
        languages: [dartLanguage],
        theme: githubDarkTheme,
      );
      final sync = SynchronousHighlightExecutor();
      final cooperative = CooperativeHighlightExecutor(sliceLines: 1);
      final native = createNativeHighlightExecutor();
      final expected = (await sync.highlight(request)).toJson();
      expect((await cooperative.highlight(request)).toJson(), expected);
      expect((await native.highlight(request)).toJson(), expected);
      final backend = _CountingExecutor();
      final pool = HighlightPool(
        executor: backend,
        concurrency: 1,
        cacheSize: 2,
        queueSize: 2,
      );
      final results = await Future.wait([
        pool.highlight(request),
        pool.highlight(request),
      ]);
      expect(backend.calls, 1);
      expect(results.first, same(results.last));
      final cancel = CancellationToken()..cancel();
      await expectLater(
        pool.highlight(request, cancellation: cancel),
        throwsA(isA<OperationCancelled>()),
      );
      pool.dispose();
      sync.dispose();
      cooperative.dispose();
      native.dispose();
    },
  );
  test(
    'row measurements preserve indexed lookup and file sessions restore',
    () {
      final heights = RowHeightIndex(100000, estimatedHeight: 20);
      heights.measure(3, 100);
      expect(heights.offsetFor(4), 160);
      expect(heights.rowAt(150), 3);
      final files = FileListController([
        const SourceFile(id: 'a', path: 'x.dart', text: 'one', revision: 8),
      ], sessionLimit: 1);
      final editor = files.acquire('a');
      expect(editor.document.revision, 8);
      editor.insertText('two');
      files.release('a');
      expect(files.acquire('a'), same(editor));
      files.dispose();
      expect(editor.isDisposed, isTrue);
    },
  );
}

class _CountingExecutor implements HighlightExecutor {
  final backend = CooperativeHighlightExecutor(sliceLines: 1);
  @override
  void dispose() => backend.dispose();
  int calls = 0;
  @override
  Future<HighlightResult> highlight(
    HighlightRequest request, {
    CancellationToken? cancellation,
  }) {
    calls++;
    return backend.highlight(request, cancellation: cancellation);
  }
}
