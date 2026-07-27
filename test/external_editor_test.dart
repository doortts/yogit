import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/external_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses quoted and escaped editor arguments without a shell', () {
    expect(
      parsePosixWords(
        r'''code --reuse-window "profile name" 'literal $value' escaped\ value''',
      ),
      [
        'code',
        '--reuse-window',
        'profile name',
        r'literal $value',
        'escaped value',
      ],
    );
  });

  test('preserves an explicitly empty editor argument', () {
    expect(parsePosixWords('code "" tail'), ['code', '', 'tail']);
  });

  for (final unsafe in [
    r'code $(touch bad)',
    r'code `touch bad`',
    'code file | cat',
    'code > output',
    'code < input',
    'code; other',
    'code & other',
    'code && other',
    'code "unterminated',
    r'code trailing\',
  ]) {
    test('rejects unsafe editor setting: $unsafe', () {
      expect(() => parsePosixWords(unsafe), throwsFormatException);
    });
  }

  test('rejects an empty editor setting', () {
    expect(() => parsePosixWords(' \t\n '), throwsFormatException);
  });

  test('passes a difficult file path as one final VS Code argument', () async {
    final root = await Directory.systemTemp.createTemp('yogit_editor_');
    addTearDown(() => root.delete(recursive: true));
    final binDirectory = Directory('${root.path}/bin folder');
    await binDirectory.create();
    final bin = await _createExecutable(binDirectory, 'code');
    const relativePath = '-leading space;name.txt';
    final target = File('${root.path}/$relativePath');
    await target.writeAsString('one\n');
    final launches = <({String executable, List<String> arguments})>[];
    final service = ExternalEditorService(
      repositoryRoot: root.path,
      environment: {'VISUAL': '"${bin.path}" --reuse-window'},
      processStarter: (executable, arguments) async {
        launches.add((
          executable: executable,
          arguments: List.unmodifiable(arguments),
        ));
      },
    );

    await service.open(relativePath: relativePath, line: 7);

    final canonical = await target.resolveSymbolicLinks();
    expect(launches.single.executable, bin.path);
    expect(launches.single.arguments, [
      '--reuse-window',
      '--goto',
      '$canonical:7',
    ]);
  });

  for (final name in ['code', 'code-insiders', 'cursor']) {
    test('$name uses the VS Code goto contract and defaults to line 1', () {
      expect(
        editorArguments(
          '/usr/local/bin/$name',
          const ['--wait'],
          '/tmp/a b',
          null,
        ),
        ['--wait', '--goto', '/tmp/a b:1'],
      );
    });
  }

  test('adds line arguments only for editors that support them', () {
    expect(editorArguments('/usr/bin/subl', const [], '/tmp/file', 9), [
      '/tmp/file:9',
    ]);
    expect(editorArguments('/usr/bin/nvim', const ['-f'], '/tmp/-file', 9), [
      '-f',
      '+9',
      '--',
      '/tmp/-file',
    ]);
    expect(editorArguments('/usr/bin/emacsclient', const [], '/tmp/file', 9), [
      '+9',
      '/tmp/file',
    ]);
    expect(
      editorArguments(
        '/usr/bin/custom-editor',
        const ['--wait'],
        '/tmp/file',
        9,
      ),
      ['--wait', '/tmp/file'],
    );
  });

  test('normalizes the repository root and working tree path', () async {
    final root = await Directory.systemTemp.createTemp('yogit_root_');
    addTearDown(() => root.delete(recursive: true));
    final nested = Directory('${root.path}/nested');
    await nested.create();
    final target = File('${root.path}/target.txt');
    await target.writeAsString('working tree\n');
    final rootLink = Link('${root.path}_link');
    await rootLink.create(root.path);
    addTearDown(() async {
      if (await rootLink.exists()) await rootLink.delete();
    });
    final opened = <String>[];
    final service = ExternalEditorService(
      repositoryRoot: rootLink.path,
      environment: const {},
      nativeFileOpener: (path) async {
        opened.add(path);
        return true;
      },
    );

    await service.open(relativePath: 'nested/../target.txt');

    expect(opened, [await target.resolveSymbolicLinks()]);
  });

  test('rejects a parent path that escapes the repository', () async {
    final parent = await Directory.systemTemp.createTemp('yogit_parent_');
    addTearDown(() => parent.delete(recursive: true));
    final root = Directory('${parent.path}/root');
    await root.create();
    final outside = File('${parent.path}/outside.txt');
    await outside.writeAsString('outside\n');
    var opened = false;
    final service = ExternalEditorService(
      repositoryRoot: root.path,
      environment: const {},
      nativeFileOpener: (_) async {
        opened = true;
        return true;
      },
    );

    await expectLater(
      service.open(relativePath: '../outside.txt'),
      throwsA(isA<FileSystemException>()),
    );
    expect(opened, isFalse);
  });

  test('rejects a symbolic link that escapes the repository', () async {
    final root = await Directory.systemTemp.createTemp('yogit_root_');
    final outside = await Directory.systemTemp.createTemp('yogit_outside_');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));
    await File('${outside.path}/secret.txt').writeAsString('secret\n');
    await Link('${root.path}/escape').create(outside.path);
    final service = ExternalEditorService(
      repositoryRoot: root.path,
      environment: const {},
      nativeFileOpener: (_) async => true,
    );

    await expectLater(
      service.open(relativePath: 'escape/secret.txt'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'rejects a deleted working tree file without launching anything',
    () async {
      final root = await Directory.systemTemp.createTemp('yogit_root_');
      addTearDown(() => root.delete(recursive: true));
      final deleted = File('${root.path}/deleted.txt');
      await deleted.writeAsString('old\n');
      await deleted.delete();
      var launched = false;
      var opened = false;
      final service = ExternalEditorService(
        repositoryRoot: root.path,
        environment: const {},
        processStarter: (_, _) async => launched = true,
        nativeFileOpener: (_) async {
          opened = true;
          return true;
        },
      );

      await expectLater(
        service.open(relativePath: 'deleted.txt'),
        throwsA(isA<FileSystemException>()),
      );
      expect(launched, isFalse);
      expect(opened, isFalse);
    },
  );

  test('rejects a directory instead of opening it as a working file', () async {
    final root = await Directory.systemTemp.createTemp('yogit_root_');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/folder').create();
    final service = ExternalEditorService(
      repositoryRoot: root.path,
      environment: const {},
      nativeFileOpener: (_) async => true,
    );

    await expectLater(
      service.open(relativePath: 'folder'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('uses EDITOR when VISUAL does not resolve to an executable', () async {
    final root = await Directory.systemTemp.createTemp('yogit_editor_');
    addTearDown(() => root.delete(recursive: true));
    final target = File('${root.path}/working.txt');
    await target.writeAsString('modified\n');
    final editor = await _createExecutable(root, 'code-insiders');
    final launches = <({String executable, List<String> arguments})>[];
    final service = ExternalEditorService(
      repositoryRoot: root.path,
      environment: {
        'VISUAL': 'missing-editor --wait',
        'EDITOR': 'code-insiders --reuse-window',
        'PATH': root.path,
      },
      processStarter: (executable, arguments) async {
        launches.add((
          executable: executable,
          arguments: List.unmodifiable(arguments),
        ));
      },
    );

    await service.open(relativePath: 'working.txt', line: 3);

    expect(launches.single.executable, editor.path);
    expect(launches.single.arguments, [
      '--reuse-window',
      '--goto',
      '${await target.resolveSymbolicLinks()}:3',
    ]);
  });

  test('an unsafe VISUAL setting is rejected rather than executed', () async {
    final root = await Directory.systemTemp.createTemp('yogit_editor_');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/working.txt').writeAsString('modified\n');
    await _createExecutable(root, 'code');
    var launched = false;
    var opened = false;
    final service = ExternalEditorService(
      repositoryRoot: root.path,
      environment: {
        'VISUAL': r'code $(touch injected)',
        'EDITOR': 'code',
        'PATH': root.path,
      },
      processStarter: (_, _) async => launched = true,
      nativeFileOpener: (_) async {
        opened = true;
        return true;
      },
    );

    await expectLater(
      service.open(relativePath: 'working.txt'),
      throwsFormatException,
    );
    expect(launched, isFalse);
    expect(opened, isFalse);
    expect(File('${root.path}/injected').existsSync(), isFalse);
  });

  test('reports a false native open result', () async {
    const channel = MethodChannel('yogit/window');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final root = await Directory.systemTemp.createTemp('yogit_root_');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/working.txt').writeAsString('working tree\n');
    final service = ExternalEditorService(
      repositoryRoot: root.path,
      environment: const {},
    );

    await expectLater(
      service.open(relativePath: 'working.txt'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Native file opener failed'),
        ),
      ),
    );
  });

  test('preserves a native openFile platform error', () async {
    const channel = MethodChannel('yogit/window');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(
            code: 'open_failed',
            message: 'workspace rejected file',
          ),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final root = await Directory.systemTemp.createTemp('yogit_root_');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/working.txt').writeAsString('working tree\n');
    final service = ExternalEditorService(
      repositoryRoot: root.path,
      environment: const {},
    );

    await expectLater(
      service.open(relativePath: 'working.txt'),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'open_failed')
            .having(
              (error) => error.message,
              'message',
              'workspace rejected file',
            ),
      ),
    );
  });

  test(
    'falls back to the native openFile channel with a canonical path',
    () async {
      const channel = MethodChannel('yogit/window');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final root = await Directory.systemTemp.createTemp('yogit_root_');
      addTearDown(() => root.delete(recursive: true));
      final target = File('${root.path}/a b;name.txt');
      await target.writeAsString('working tree\n');
      final service = ExternalEditorService(
        repositoryRoot: root.path,
        environment: const {},
      );

      await service.open(relativePath: 'a b;name.txt');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'openFile');
      expect(calls.single.arguments, {
        'path': await target.resolveSymbolicLinks(),
      });
    },
  );
}

Future<File> _createExecutable(Directory directory, String name) async {
  final file = File('${directory.path}/$name');
  await file.writeAsString('#!/bin/sh\nexit 0\n');
  final result = await Process.run('chmod', ['+x', file.path]);
  expect(result.exitCode, 0);
  return file;
}
