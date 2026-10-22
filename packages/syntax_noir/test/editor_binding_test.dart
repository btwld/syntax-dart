import 'package:noir/noir.dart';
import 'package:syntax/syntax.dart' as syntax;
import 'package:syntax_noir/syntax_noir.dart';
import 'package:test/test.dart';

void main() {
  test('backspace deletes a complete grapheme at every caret', () {
    final editor = syntax.EditorController(
      file: const syntax.SourceFile(
        id: 'emoji',
        path: '',
        text: '😀 👨‍👩‍👧‍👦',
      ),
    );
    editor.setSelections([
      const syntax.DocumentSelection.collapsed(2),
      syntax.DocumentSelection.collapsed(editor.document.length),
    ]);
    final input = DocumentTextEditingController(editor);
    input.value = const TextEditingValue(
      text: ' 👨‍👩‍👧‍👦',
      selection: TextSelection.collapsed(offset: 0),
    );
    expect(editor.document.text, ' ');
    editor.undo();
    expect(editor.document.text, '😀 👨‍👩‍👧‍👦');
    input.dispose();
    editor.dispose();
  });
  test(
    'native replacements and deletion apply to every selection atomically',
    () {
      final editor = syntax.EditorController(
        file: const syntax.SourceFile(id: 'multi', path: '', text: 'one two'),
      );
      editor.setSelections(const [
        syntax.DocumentSelection(0, 3),
        syntax.DocumentSelection(4, 7),
      ]);
      final input = DocumentTextEditingController(editor);
      input.value = const TextEditingValue(
        text: 'x two',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(input.text, 'x x');
      editor.undo();
      expect(input.text, 'one two');
      input.value = const TextEditingValue(
        text: ' two',
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(input.text, ' ');
      expect(editor.document.text, ' ');
      editor.undo();
      expect(input.text, 'one two');
      input.dispose();
      expect(editor.isDisposed, isFalse);
      editor.dispose();
    },
  );
}
