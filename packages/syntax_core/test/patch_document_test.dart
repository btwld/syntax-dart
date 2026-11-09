import 'package:syntax_core/syntax.dart';
import 'package:test/test.dart';

const _patch = '''diff --git a/a b/a
old mode 100644
new mode 100755
index abc123..def456
--- a/a
+++ b/a
@@ -1,3 +1,3 @@
 before
-old
+new
 after
''';

String _filePatch(String path, String before, String after) =>
    'diff --git a/$path b/$path\n'
    '--- a/$path\n+++ b/$path\n'
    '@@ -1 +1 @@\n-$before\n+$after\n';

void main() {
  group('parsePatchDocuments', () {
    // Document assertions ported from code_review/review_edit_test.dart.
    test('retains introduction, Git metadata and count diagnostics', () {
      const patch = 'commit abcdef123\nsubject\n\n$_patch';
      final parsed = parsePatchDocuments(patch, strict: true).single;
      expect(parsed.introduction, 'commit abcdef123\nsubject\n\n');
      expect(parsed.source, patch);
      expect(parsed.files.single.oldMode, '100644');
      expect(parsed.files.single.newMode, '100755');
      expect(parsed.files.single.oldObjectId, 'abc123');
      expect(parsed.files.single.newObjectId, 'def456');
      expect(parsed.diagnostics, isEmpty);
      final malformed = patch.replaceFirst('-1,3', '-1,9');
      final recovered = parsePatchDocuments(malformed).single;
      expect(recovered.files.single.hunks.single.lines, hasLength(4));
      expect(recovered.diagnostics.single.line, 10);
      expect(recovered.diagnostics.single.message, contains('counts'));
      expect(
        () => parsePatchDocuments(malformed, strict: true),
        throwsFormatException,
      );
    });

    // Document assertions extracted from review_regression_test.dart;
    // streaming is intentionally outside this API.
    test(
      'concatenated commits retain unique identities for repeated paths',
      () {
        final first = 'a' * 40, second = 'b' * 40;
        final firstPatch = _filePatch('same', 'a', 'b');
        final otherPatch = _filePatch('other', 'x', 'y');
        final secondPatch = _filePatch('same', 'b', 'c');
        final firstSource = 'commit $first\nFirst\n$firstPatch$otherPatch';
        final secondSource = 'commit $second\nSecond\n$secondPatch';
        final documents = parsePatchDocuments(
          '$firstSource$secondSource',
          strict: true,
        );
        expect(documents, hasLength(2));
        expect(documents.map((document) => document.source), [
          firstSource,
          secondSource,
        ]);
        final files = documents.expand((document) => document.files).toList();
        expect(files.map((file) => file.path), ['same', 'other', 'same']);
        expect(files.map((file) => file.id).toSet(), hasLength(3));
        expect(files.map((file) => file.id), [
          '$first:${parsePatch(firstPatch).single.id}',
          '$first:${parsePatch(otherPatch).single.id}',
          '$second:${parsePatch(secondPatch).single.id}',
        ]);
        expect(files.last.hunks.single.lines.map((line) => line.text), [
          'b',
          'c',
        ]);
      },
    );

    test(
      'mailbox documents preserve CRLF transport, introductions and footer',
      () {
        final first = '1' * 40, second = '2' * 64;
        final sources = [
          for (final hash in [first, second])
            'From $hash Mon Sep 17 00:00:00 2001\n'
                    'From: Author <author@example.com>\n'
                    'Subject: [PATCH] Change a\n\n'
                    'Message\n---\n a | 2 +-\n\n$_patch-- \n2.50.0\n'
                .replaceAll('\n', '\r\n'),
        ];
        final documents = parsePatchDocuments(sources.join(), strict: true);
        expect(documents.map((document) => document.source), sources);
        for (var i = 0; i < documents.length; i++) {
          final document = documents[i];
          expect(document.introduction, sources[i].split('diff --git').first);
          expect(document.files.single.patchLineEnding, '\r\n');
          expect(
            document.files.single.id,
            startsWith('${[first, second][i]}:'),
          );
          expect(document.files.single.hunks.single.lines.last.text, 'after');
        }
      },
    );

    test(
      'plain unified diffs keep parsePatch identities and exact transport',
      () {
        const source =
            'Introduction\r\n\r\n'
            '--- a/a\r\n+++ b/a\r\n@@ -1 +1 @@\r\n-old\r\n+new';
        final document = parsePatchDocuments(source, strict: true).single;
        expect(document.introduction, 'Introduction\r\n\r\n');
        expect(document.source, source);
        expect(document.files.single.id, parsePatch(source).single.id);
        expect(document.files.single.hunks.single.lines.last.text, 'new');
      },
    );

    test('preserves preambles, whitespace and introduction-only documents', () {
      final source = 'Cover letter\n\ncommit abcdef1\nSubject\n$_patch';
      final documents = parsePatchDocuments(source, strict: true);
      expect(documents, hasLength(2));
      expect(documents.first.introduction, 'Cover letter\n\n');
      expect(documents.first.files, isEmpty);
      expect(documents.map((document) => document.source).join(), source);
      final prefixed = parsePatchDocuments('\r\n commit note\n');
      expect(prefixed.single.introduction, '\r\n commit note\n');
      final whitespace = '\n\r\ncommit abcdef1\n$_patch';
      expect(parsePatchDocuments(whitespace).single.source, whitespace);
      for (final empty in ['', ' \r\n\t']) {
        expect(parsePatchDocuments(empty, strict: true), isEmpty);
      }
    });

    test('commit-like source content does not split documents', () {
      final source = _filePatch('a', 'commit abcdef1', 'commit abcdef2');
      final document = parsePatchDocuments(source, strict: true).single;
      expect(
        document.files.single.hunks.single.lines.first.text,
        'commit abcdef1',
      );
      expect(document.source, source);
    });

    test(
      'diagnostics refer to each original hunk, including explicit counts',
      () {
        const header = '@@ -1,1 +1,2 @@';
        const source =
            'Subject\n--- a/a\n+++ b/a\n$header\n-old\n+new\n'
            '--- a/b\n+++ b/b\n$header\n-old\n+new\n';
        final document = parsePatchDocuments(source).single;
        expect(document.files, hasLength(2));
        expect(document.diagnostics.map((diagnostic) => diagnostic.line), [
          4,
          9,
        ]);
        expect(
          document.diagnostics.map((diagnostic) => diagnostic.message),
          everyElement(contains('counts')),
        );
      },
    );

    test(
      'strict errors carry document-relative source and transport offset',
      () {
        final first = 'commit abcdef1\n$_patch';
        final broken =
            'commit abcdef2\r\n--- a/b\r\n+++ b/b\r\n'
            '@@ -1,2 +1,2 @@\r\n-old\r\n+new\r\n';
        final documents = parsePatchDocuments('$first$broken');
        expect(documents.last.diagnostics.single.line, 4);
        expect(
          () => parsePatchDocuments('$first$broken', strict: true),
          throwsA(
            isA<FormatException>()
                .having((error) => error.source, 'source', broken)
                .having(
                  (error) => error.offset,
                  'offset',
                  broken.indexOf('@@'),
                ),
          ),
        );
      },
    );

    test('malformed and oversized hunk headers are recoverable', () {
      for (final header in ['@@ broken', '@@ -1234567890 +1 @@']) {
        final source = '--- a/a\n+++ b/a\n$header\n-old\n+new\n';
        final document = parsePatchDocuments(source).single;
        expect(document.files.single.hunks, isEmpty);
        expect(document.diagnostics.single.line, 3);
        expect(document.diagnostics.single.message, 'Invalid hunk header');
        expect(
          () => parsePatchDocuments(source, strict: true),
          throwsFormatException,
        );
      }
    });

    test('reports incomplete file headers and hunks without a file', () {
      for (final source in ['Message\n--- a/a\n', 'Message\n@@ -1 +1 @@\n']) {
        final document = parsePatchDocuments(source).single;
        expect(document.files, isEmpty);
        expect(document.diagnostics.single.line, 2);
        expect(
          () => parsePatchDocuments(source, strict: true),
          throwsFormatException,
        );
      }
    });

    test('diagnoses incomplete Git and trailing unified headers', () {
      for (final suffix in ['diff --git broken\n', '--- a/incomplete\n']) {
        final source = '$_patch$suffix';
        final document = parsePatchDocuments(source).single;
        expect(document.diagnostics.single.line, 12);
        expect(document.diagnostics.single.message, 'No complete file header');
        expect(
          () => parsePatchDocuments(source, strict: true),
          throwsFormatException,
        );
      }
      // A complete unified header can recover paths from a broken Git header.
      final recovered = parsePatchDocuments(
        'diff --git broken\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n-a\n+b\n',
        strict: true,
      ).single;
      expect(recovered.files.single.path, 'a');
    });

    test('missing-newline markers and removed header-like text are content', () {
      const source =
          '--- a/a\n+++ b/a\n@@ -1,2 +1,2 @@\n'
          '--- a/not-a-header\n+++ b/not-a-header\n-old\n'
          '\\ No newline at end of file\n+new\n\\ No newline at end of file\n';
      final document = parsePatchDocuments(source, strict: true).single;
      expect(document.diagnostics, isEmpty);
      expect(document.files.single.hunks.single.lines, hasLength(4));
      expect(
        document.files.single.hunks.single.lines.last.noNewlineAtEnd,
        isTrue,
      );
    });

    test('binary, rename and mode-only files do not require hunks', () {
      const source =
          'diff --git a/a b/a\nBinary files a/a and b/a differ\n'
          'diff --git a/b b/c\nrename from b\nrename to c\n'
          'diff --git a/d b/d\nold mode 100644\nnew mode 100755\n';
      final document = parsePatchDocuments(source, strict: true).single;
      expect(document.files, hasLength(3));
      expect(document.files.first.isBinary, isTrue);
      expect(document.files[1].kind, FileDiffKind.renamed);
      expect(document.files.last.newMode, '100755');
    });

    test('returned document and parsed file collections are immutable', () {
      final documents = parsePatchDocuments(_patch);
      final document = documents.single;
      expect(() => documents.clear(), throwsUnsupportedError);
      expect(() => document.files.clear(), throwsUnsupportedError);
      expect(() => document.diagnostics.clear(), throwsUnsupportedError);
      expect(() => document.files.single.hunks.clear(), throwsUnsupportedError);
      expect(
        () => document.files.single.hunks.single.lines.clear(),
        throwsUnsupportedError,
      );
    });
  });

  test('PatchDocument snapshots caller-owned collections', () {
    final files = parsePatch(_patch);
    final diagnostics = [const PatchDiagnostic(1, 'Example')];
    final document = PatchDocument(
      introduction: 'Subject',
      source: 'Subject\n$_patch',
      files: files,
      diagnostics: diagnostics,
    );
    files.clear();
    diagnostics.clear();
    expect(document.files, hasLength(1));
    expect(document.diagnostics.single.line, 1);
    expect(document.diagnostics.single.message, 'Example');
  });
}
