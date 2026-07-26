import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';

Future<String> runGit(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return result.stdout.toString();
}

Future<Directory> createGitFixture() async {
  final root = await Directory.systemTemp.createTemp('yogit_full_diff_');
  await runGit(root, ['init', '-b', 'main']);
  await runGit(root, ['config', 'user.name', 'Test User']);
  await runGit(root, ['config', 'user.email', 'test@example.com']);
  return root;
}

Future<void> writeAndCommit(
  Directory root,
  String path,
  String contents,
  String subject,
) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
  await runGit(root, ['add', '--', path]);
  await runGit(root, ['commit', '-m', subject]);
}

void main() {
  test('finds renames and passes both paths when loading its patch', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(
      root,
      'old name.pas',
      'begin\n  Setup;\n  Run;\n  Teardown;\nend.\n',
      'base',
    );
    await runGit(root, ['mv', 'old name.pas', 'new name.pas']);
    await File('${root.path}/new name.pas').writeAsString(
      'begin\n  Setup;\n  Writeln("renamed");\n  Run;\n  Teardown;\nend.\n',
    );
    await runGit(root, ['commit', '-am', 'rename']);

    final calls = <List<String>>[];
    final repository = GitRepository(
      root.path,
      runner: (executable, arguments, {workingDirectory}) {
        calls.add(List.unmodifiable(arguments));
        return runProcess(
          executable,
          arguments,
          workingDirectory: workingDirectory,
        );
      },
    );
    final commit = (await repository.loadHistory()).first;
    final file = (await repository.loadFiles(commit)).single;
    await repository.loadDiff(commit, file);

    expect(file.status, startsWith('R'));
    expect(file.oldPath, 'old name.pas');
    expect(file.path, 'new name.pas');
    final patchArguments = calls.lastWhere(
      (arguments) =>
          arguments.first == 'diff' && arguments.contains('--unified=3'),
    );
    expect(
      patchArguments,
      containsAll(['--find-renames=50%', 'old name.pas', 'new name.pas']),
    );
  });

  test(
    'synthesizes an add document for an untracked working tree file',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(root, 'tracked.txt', 'tracked\n', 'base');
      await File('${root.path}/new file.txt').writeAsString('one\ntwo\n');
      final repository = GitRepository(root.path);
      final working = (await repository.loadWorkingTree())!;
      final file = (await repository.loadFiles(
        working,
      )).singleWhere((entry) => entry.path == 'new file.txt');

      final lines = await repository.loadDiff(working, file);

      expect(file.status, 'A');
      expect(
        lines.where((line) => line.kind == DiffLineKind.add),
        hasLength(2),
      );
      expect(lines.last.newNumber, 2);
    },
  );

  test(
    'loads the correct side for deleted files and follows renames',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(root, 'first.txt', 'old content\n', 'first');
      await runGit(root, ['mv', 'first.txt', 'second.txt']);
      await runGit(root, ['commit', '-m', 'rename once']);
      await runGit(root, ['mv', 'second.txt', 'final.txt']);
      await runGit(root, ['commit', '-m', 'rename twice']);
      await runGit(root, ['rm', 'final.txt']);
      await runGit(root, ['commit', '-m', 'delete']);

      final repository = GitRepository(root.path);
      final deletion = (await repository.loadHistory()).first;
      final file = (await repository.loadFiles(deletion)).single;
      final bytes = await repository.loadFileBytes(deletion, file);
      final history = await repository.loadFileHistory(deletion, file);

      expect(utf8.decode(bytes), 'old content\n');
      expect(
        history.map((entry) => entry.commit.subject),
        containsAll(['delete', 'rename twice', 'rename once', 'first']),
      );
      expect(history.map((entry) => entry.path), contains('first.txt'));
    },
  );

  test('blames tracked and untracked working tree contents', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'tracked.txt', 'one\n', 'base');
    await File('${root.path}/tracked.txt').writeAsString('one\ntwo\n');
    await File('${root.path}/new.txt').writeAsString('new\n');

    final repository = GitRepository(root.path);
    final working = (await repository.loadWorkingTree())!;
    final files = await repository.loadFiles(working);
    final tracked = files.singleWhere((file) => file.path == 'tracked.txt');
    final untracked = files.singleWhere((file) => file.path == 'new.txt');
    final trackedBytes = await repository.loadFileBytes(working, tracked);
    final untrackedBytes = await repository.loadFileBytes(working, untracked);

    final trackedBlame = await repository.loadBlame(
      working,
      tracked,
      workingTreeBytes: trackedBytes,
    );
    final untrackedBlame = await repository.loadBlame(
      working,
      untracked,
      workingTreeBytes: untrackedBytes,
    );

    expect(trackedBlame, hasLength(2));
    expect(trackedBlame.last.uncommitted, isTrue);
    expect(untrackedBlame, hasLength(1));
    expect(untrackedBlame.single.author, 'Uncommitted');
  });

  test(
    'requires displayed bytes before blaming a tracked working file',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(root, 'tracked.txt', 'one\n', 'base');
      await File('${root.path}/tracked.txt').writeAsString('one\ntwo\n');

      final repository = GitRepository(root.path);
      final working = (await repository.loadWorkingTree())!;
      final tracked = (await repository.loadFiles(
        working,
      )).singleWhere((file) => file.path == 'tracked.txt');

      await expectLater(
        repository.loadBlame(working, tracked),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('keeps special-character paths intact in blame and history', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    const oldPath = 'odd\tname.txt';
    const newPath = 'renamed\nname.txt';
    await writeAndCommit(root, oldPath, 'first\n', 'first');
    await runGit(root, ['mv', oldPath, newPath]);
    await runGit(root, ['commit', '-m', 'rename']);

    final repository = GitRepository(root.path);
    final commit = (await repository.loadHistory()).first;
    final file = (await repository.loadFiles(commit)).single;
    final blame = await repository.loadBlame(commit, file);
    final history = await repository.loadFileHistory(commit, file);

    expect(file.path, newPath);
    expect(blame.single.lineNumber, 1);
    expect(history.map((entry) => entry.path), containsAll([oldPath, newPath]));
  });
}
