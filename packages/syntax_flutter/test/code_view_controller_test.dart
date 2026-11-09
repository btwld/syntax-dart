import 'package:flutter_test/flutter_test.dart';
import 'package:syntax_flutter/syntax_flutter.dart';

void main() {
  test(
    'identity, revision, directed inclusive lines and source replacement',
    () {
      final c = CodeViewController(
        sourceId: 'a',
        code: 'one\r\ntwo\r\nthree\r\nfour',
        revision: 3,
      );
      addTearDown(c.dispose);
      var changes = 0;
      c.addListener(() => changes++);
      expect(c.sourceId, 'a');
      expect(c.revision, 3);
      expect(c.lineCount, 4);
      expect(c.selection, isNull);
      c.selectLines(2, 0);
      expect(c.selection, (anchor: 2, active: 0));
      expect(c.selectedText, 'one\r\ntwo\r\nthree');
      c.selectLines(2, 3);
      expect(c.selectedText, 'three\r\nfour');
      expect(changes, 2);
      c.setCode('new\n', revision: 4);
      expect(c.code, 'new\n');
      expect(c.revision, 4);
      expect(c.lineCount, 2);
      expect(c.selection, isNull);
      expect(c.selectedText, isNull);
      expect(changes, 3);
      c.selectLines(1, 1);
      expect(c.selectedText, '');
      c.setCode(c.code, revision: 5);
      expect(c.selection, isNull);
      expect(changes, 5);
      c.setCode(c.code, revision: 5);
      expect(changes, 5);
    },
  );

  test('empty source has one line and invalid commands preserve state', () {
    final c = CodeViewController(sourceId: 'empty', code: '');
    addTearDown(c.dispose);
    expect(c.lineCount, 1);
    c.selectLines(0, 0);
    expect(c.selectedText, '');
    for (final line in [-1, 1, 200]) {
      expect(() => c.selectLines(line, 0), throwsRangeError);
      expect(() => c.selectLines(0, line), throwsRangeError);
      expect(() => c.revealLine(line), throwsRangeError);
    }
    expect(c.selection, (anchor: 0, active: 0));
  });
}
