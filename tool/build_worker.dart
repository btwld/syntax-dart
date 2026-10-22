import 'dart:io';

/// Compiles the worker into an application-controlled public asset directory.
Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent;
  final output = arguments.isEmpty
      ? '${root.path}/packages/syntax/test/fixtures/highlight_worker.js'
      : arguments.single;
  await File(output).parent.create(recursive: true);
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'js',
    '-O2',
    '${root.path}/packages/syntax/lib/highlight_worker.dart',
    '-o',
    output,
  ], workingDirectory: root.path);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exitCode = result.exitCode;
  if (arguments.isEmpty && result.exitCode == 0) {
    final fixture = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'js',
      '-O2',
      '${root.path}/packages/syntax/test/fixtures/failing_worker.dart',
      '-o',
      '${root.path}/packages/syntax/test/fixtures/failing_worker.js',
    ], workingDirectory: root.path);
    stdout.write(fixture.stdout);
    stderr.write(fixture.stderr);
    exitCode = fixture.exitCode;
  }
}
