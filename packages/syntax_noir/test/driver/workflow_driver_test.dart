@Timeout(Duration(minutes: 2))
library;

import 'package:noir_driver/noir_driver.dart';
import 'package:test/test.dart';

Future<NoirDriver> launch([String mode = 'editor']) async {
  final driver = await NoirDriver.launch(
    'test/driver/workflow_app.dart',
    width: 75,
    height: 20,
    arguments: [mode],
  );
  addTearDown(driver.quit);
  return driver;
}

Matcher containsText(String text) => DriverFrameMatchers.containsText(text);
void main() {
  test('keyboard folds a section and reveal restores its lines', () async {
    final driver = await launch('fold');
    expect(await driver.capture(), containsText('new'));
    await driver.sendKey('down');
    await driver.sendKey('enter');
    expect(await driver.capture(), isNot(containsText('new')));
    await driver.clickLocator(DriverLocator.byText('Reveal selected line'));
    expect(await driver.capture(), containsText('new'));
  });

  test(
    'custom annotation heights update when terminal width changes',
    () async {
      final driver = await launch('custom-annotations');
      expect(await driver.capture(), containsText('Custom annotation row 1'));
      expect(
        await driver.capture(),
        isNot(containsText('Custom annotation row 3')),
      );
      await driver.resize(30, 20);
      expect(await driver.capture(), containsText('Custom annotation row 3'));
    },
  );

  test('long review notes can be scrolled with the keyboard', () async {
    final driver = await launch('long-review');
    await driver.sendKey('down');
    await driver.sendKey('down');
    expect(await driver.capture(), containsText('Review note row 0'));
    await driver.sendKey('tab');
    await driver.sendKey('end');
    expect(await driver.capture(), containsText('Review note row 29'));
  });
  test(
    'multiline annotations remain visible across terminal resizing',
    () async {
      final driver = await launch('annotations');
      expect(await driver.capture(), containsText('Annotation final row'));
      await driver.resize(30, 20);
      expect(await driver.capture(), containsText('Annotation final row'));
      expect(await driver.capture(), containsText('second line'));
    },
  );

  test('review annotations use multiple terminal rows', () async {
    final driver = await launch('patch');
    await driver.sendKey('down');
    await driver.sendKey('down');
    expect(await driver.capture(), containsText('Review first row'));
    expect(await driver.capture(), containsText('Review second row'));
    expect(await driver.capture(), containsText('Review final row'));
  });
  test(
    'file collections refresh controller ownership and repeat navigation',
    () async {
      final driver = await launch('files');
      expect(await driver.capture(), containsText('first row 0'));
      await driver.clickLocator(DriverLocator.byText('Reveal distant row'));
      expect(await driver.capture(), containsText('first row 80'));
      await driver.clickLocator(DriverLocator.byText('Reveal first row'));
      expect(await driver.capture(), containsText('first row 0'));
      await driver.clickLocator(DriverLocator.byText('Reveal distant row'));
      expect(await driver.capture(), containsText('first row 80'));
      await driver.clickLocator(DriverLocator.byText('Swap collection'));
      expect(await driver.capture(), containsText('replacement source'));
      expect(await driver.capture(), isNot(containsText('first row 80')));
    },
  );
  test('native terminal edits, undo, annotations and completion', () async {
    final driver = await launch();
    expect(await driver.capture(), containsText('Review annotation'));
    await driver.typeText('hello');
    expect(await driver.capture(), containsText('hellofinal answer'));
    await driver.sendKey('ctrl-z');
    expect(await driver.capture(), containsText('hellfinal answer'));
    await driver.sendKey('ctrl-y');
    expect(await driver.capture(), containsText('hellofinal answer'));
    await driver.clickLocator(DriverLocator.byText('Done'));
    expect(
      await driver.capture(),
      containsText('Completed: hellofinal answer'),
    );
  });
  test('directed selection copies only source and survives resize', () async {
    final driver = await launch();
    for (var i = 0; i < 5; i++) {
      await driver.typeText('\x1b[1;2C');
    }
    await driver.sendKey('ctrl-c');
    expect(await driver.capture(), containsText('Copied: final'));
    await driver.resize(40, 20);
    expect(await driver.capture(), containsText('Copied: final'));
  });
  test('search navigates source matches', () async {
    final driver = await launch();
    await driver.sendKey('ctrl-f');
    await driver.clickLocator(DriverLocator.byType('TextInput').at(0));
    await driver.typeText('second');
    await driver.sendKey('enter');
    expect(await driver.capture(), containsText('1 matches'));
  });
  test('patch selection copy excludes gutters', () async {
    final driver = await launch('patch');
    await driver.sendKey('down');
    await driver.sendKey('down');
    await driver.sendKey('enter');
    await driver.sendKey('ctrl-c');
    expect(await driver.capture(), containsText('Copied: one'));
  });
  test('conflict side action updates the full source', () async {
    final driver = await launch('conflict');
    await driver.clickLocator(DriverLocator.byText('Both'));
    expect(await driver.capture(), containsText('All conflicts resolved'));
    expect(await driver.capture(), isNot(containsText('<<<<<<<')));
  });
  test(
    'proposals preview and accept through keyboard-accessible controls',
    () async {
      final driver = await launch('proposal');
      await driver.typeText('a');
      expect(
        await driver.waitForText('Suggestion: suggested'),
        containsText('Suggestion: suggested'),
      );
      await driver.clickLocator(DriverLocator.byText('Accept suggestion'));
      expect(await driver.capture(), containsText('suggestedfinal answer'));
    },
  );
  test('unmounting restores the draft and its undo history', () async {
    final driver = await launch('restore');
    expect(await driver.capture(), containsText('Review the answer'));
    await driver.typeText('draft');
    await driver.clickLocator(DriverLocator.byText('Hide editor'));
    expect(await driver.capture(), containsText('Draft retained'));
    await driver.clickLocator(DriverLocator.byText('Show editor'));
    expect(await driver.capture(), containsText('draftfinal answer'));
    await driver.sendKey('ctrl-z');
    expect(await driver.capture(), containsText('draffinal answer'));
  });
}
