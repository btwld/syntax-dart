// Each test runs test/driver/patch_app.dart as a real noir app, so the
// first launch may compile it.
@Timeout(Duration(minutes: 2))
library;

import 'package:noir_driver/noir_driver.dart';
import 'package:syntax/syntax.dart' as syntax;
import 'package:syntax/themes/github_dark.dart';
import 'package:test/test.dart';

Future<NoirDriver> launch({List<String> arguments = const []}) async {
  final driver = await NoirDriver.launch(
    'test/driver/patch_app.dart',
    width: 60,
    height: 20,
    arguments: arguments,
  );
  addTearDown(driver.quit);
  return driver;
}

DriverColor painted(int argb) =>
    DriverColor((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, 255);

Matcher containsText(String text) => DriverFrameMatchers.containsText(text);

void main() {
  const theme = githubDarkTheme;
  final colors = syntax.DiffColors.of(theme);
  final addedLine = syntax.alphaBlend(colors.insertedLine, theme.background);
  final removedLine = syntax.alphaBlend(colors.removedLine, theme.background);
  final addedWord = syntax.alphaBlend(colors.insertedText, addedLine);
  final removedWord = syntax.alphaBlend(colors.removedText, removedLine);

  test('keys show hidden lines and collapse the file', () async {
    final driver = await launch();
    expect(await driver.capture(), containsText('Show 6 unchanged lines'));

    // The file header starts selected; the hidden lines are next.
    await driver.sendKey('down');
    await driver.sendKey('enter');
    var frame = await driver.capture();
    expect(frame, containsText('final v1 = 1;'));
    expect(frame, isNot(containsText('Show 6 unchanged lines')));

    await driver.sendKey('up');
    await driver.sendKey('enter');
    frame = await driver.capture();
    expect(frame.lines.first, startsWith('▌▸ values.dart'));
    expect(frame, isNot(containsText('final v')));

    // Opening the file again keeps the lines shown before.
    await driver.sendKey('enter');
    expect(await driver.capture(), containsText('final v1 = 1;'));
  });

  test('no files shows a notice and ignores keys', () async {
    final driver = await launch(arguments: ['empty']);
    expect(await driver.capture(), containsText('No changes'));
    await driver.sendKey('down');
    await driver.sendKey('enter');
    expect(await driver.capture(), containsText('No changes'));
  });

  test('noir paints the line and word colors', () async {
    final driver = await launch();
    final frame = await driver.captureCells();
    final y = frame.lines.indexWhere((l) => l.contains('v10 = 100'));
    final line = frame.lines[y];
    expect(
      frame,
      DriverFrameMatchers.hasColorAt(
        line.indexOf('+'),
        y,
        painted(syntax.alphaBlend(colors.inserted, addedLine)),
      ),
    );
    expect(
      frame,
      DriverFrameMatchers.hasBackgroundAt(
        line.indexOf('='),
        y,
        painted(addedLine),
      ),
    );
    expect(
      frame,
      DriverFrameMatchers.hasBackgroundAt(
        line.indexOf('100'),
        y,
        painted(addedWord),
      ),
    );
    final context = frame.lines.indexWhere((l) => l.contains('v9 = 9'));
    expect(
      frame,
      DriverFrameMatchers.hasBackgroundAt(
        frame.lines[context].indexOf('='),
        context,
        painted(theme.background),
      ),
    );
  });

  test('split keeps one divider column through a resize', () async {
    final driver = await launch(arguments: ['split']);
    int dividerOf(DriverFrame frame) => {
      for (final l in frame.lines)
        if (l.contains('│')) l.indexOf('│'),
    }.single;
    expect(dividerOf(await driver.capture()), 30);

    await driver.resize(36, 20);
    final frame = await driver.captureCells();
    expect(dividerOf(frame), 18);
    // `10` and `100` are cut, and `…` takes their colors.
    expect(frame, isNot(containsText('100')));
    final y = frame.lines.indexWhere((l) => l.contains('v10 =…'));
    final line = frame.lines[y];
    expect(
      frame,
      DriverFrameMatchers.hasBackgroundAt(
        line.indexOf('…'),
        y,
        painted(removedWord),
      ),
    );
    expect(
      frame,
      DriverFrameMatchers.hasBackgroundAt(
        line.lastIndexOf('…'),
        y,
        painted(addedWord),
      ),
    );
  });

  test('sticky header updates when selection moves to another file', () async {
    final driver = await launch(arguments: ['sticky']);
    expect((await driver.capture()).lines.first.trim(), 'first.dart');
    for (var i = 0; i < 4; i++) {
      await driver.sendKey('down');
    }
    expect((await driver.capture()).lines.first.trim(), 'second.dart');
  });
}
