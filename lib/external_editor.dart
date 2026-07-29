import 'dart:io';

import 'package:flutter/services.dart';

import 'git.dart';

typedef EditorProcessStarter =
    Future<void> Function(String executable, List<String> arguments);
typedef NativeFileOpener = Future<bool> Function(String absolutePath);

List<String> parsePosixWords(String source) {
  final words = <String>[];
  final current = StringBuffer();
  String? quote;
  var escaping = false;
  var wordStarted = false;

  void finish() {
    if (!wordStarted) return;
    words.add(current.toString());
    current.clear();
    wordStarted = false;
  }

  for (var index = 0; index < source.length; index++) {
    final character = source[index];
    if (escaping) {
      current.write(character);
      wordStarted = true;
      escaping = false;
      continue;
    }
    if (character == r'\' && quote != "'") {
      escaping = true;
      wordStarted = true;
      continue;
    }
    if (character == "'" || character == '"') {
      if (quote == null) {
        quote = character;
        wordStarted = true;
      } else if (quote == character) {
        quote = null;
      } else {
        current.write(character);
      }
      continue;
    }
    if (quote == null && r'`$|><;&'.contains(character)) {
      throw const FormatException('Unsafe editor setting');
    }
    if (quote == null && character.trim().isEmpty) {
      finish();
      continue;
    }
    current.write(character);
    wordStarted = true;
  }

  if (quote != null || escaping) {
    throw const FormatException('Unterminated editor setting');
  }
  finish();
  if (words.isEmpty) {
    throw const FormatException('Empty editor setting');
  }
  return List.unmodifiable(words);
}

class ExternalEditorService {
  ExternalEditorService({
    required this.repositoryRoot,
    Map<String, String>? environment,
    EditorProcessStarter? processStarter,
    NativeFileOpener? nativeFileOpener,
  }) : environment = environment ?? Platform.environment,
       processStarter =
           processStarter ??
           ((executable, arguments) async {
             await Process.start(executable, arguments);
           }),
       nativeFileOpener =
           nativeFileOpener ??
           ((path) async =>
               await const MethodChannel(
                 'yogit/window',
               ).invokeMethod<bool>('openFile', {'path': path}) ==
               true);

  final String repositoryRoot;
  final Map<String, String> environment;
  final EditorProcessStarter processStarter;
  final NativeFileOpener nativeFileOpener;

  Future<void> open({required String relativePath, int? line}) async {
    final file = (await resolveWorkingTreeFile(
      repositoryRoot,
      relativePath,
    )).path;

    for (final key in const ['VISUAL', 'EDITOR']) {
      final configured = environment[key];
      if (configured == null || configured.trim().isEmpty) continue;
      final words = parsePosixWords(configured);
      final command = words.first;
      final executable = command.contains(Platform.pathSeparator)
          ? isExecutableFile(command)
                ? command
                : null
          : resolveOptionalExecutable(command, environment: environment);
      if (executable == null) continue;
      final arguments = editorArguments(
        executable,
        words.skip(1).toList(growable: false),
        file,
        line,
      );
      await processStarter(executable, arguments);
      return;
    }

    if (!await nativeFileOpener(file)) {
      throw StateError('Native file opener failed');
    }
  }
}

List<String> editorArguments(
  String executable,
  List<String> configured,
  String path,
  int? line,
) {
  final name = executable.split(Platform.pathSeparator).last.toLowerCase();
  final location = line ?? 1;
  return switch (name) {
    'code' ||
    'code-insiders' ||
    'cursor' => [...configured, '--goto', '$path:$location'],
    'subl' || 'sublime_text' => [...configured, '$path:$location'],
    'vim' || 'nvim' || 'mvim' => [...configured, '+$location', '--', path],
    'emacs' || 'emacsclient' => [...configured, '+$location', path],
    _ => [...configured, path],
  };
}
