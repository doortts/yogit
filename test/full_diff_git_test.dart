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

  test('worktree rename history starts from the path at HEAD', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'old.txt', 'committed\n', 'base');
    await runGit(root, ['mv', 'old.txt', 'new.txt']);

    final repository = GitRepository(root.path);
    final working = (await repository.loadWorkingTree())!;
    final file = (await repository.loadFiles(working)).single;
    final history = await repository.loadFileHistory(working, file);

    expect(file.status, startsWith('R'));
    expect(file.oldPath, 'old.txt');
    expect(file.path, 'new.txt');
    expect(history.map((entry) => entry.commit.subject), contains('base'));
    expect(history.single.path, 'old.txt');
  });

  test('history uses old path only for worktree renames', () async {
    final calls = <List<String>>[];
    final repository = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory}) async {
        calls.add(List.unmodifiable(arguments));
        return ProcessResult(0, 0, '', '');
      },
    );
    const identity = GitIdentity(name: 'Test', email: 'test@example.com');
    const working = GitCommit(
      sha: '',
      shortSha: '',
      parents: ['head'],
      author: identity,
      authorTimestamp: 0,
      committer: identity,
      committerTimestamp: 0,
      refs: [],
      subject: 'working',
    );
    const committed = GitCommit(
      sha: 'commit',
      shortSha: 'commit',
      parents: ['parent'],
      author: identity,
      authorTimestamp: 0,
      committer: identity,
      committerTimestamp: 0,
      refs: [],
      subject: 'committed',
    );
    const cases = <({GitCommit commit, String status, String expected})>[
      (commit: working, status: 'R100', expected: 'old.txt'),
      (commit: working, status: 'D', expected: 'selected.txt'),
      (commit: working, status: 'M', expected: 'selected.txt'),
      (commit: working, status: 'T', expected: 'selected.txt'),
      (commit: working, status: 'A', expected: 'selected.txt'),
      (commit: working, status: 'C100', expected: 'selected.txt'),
      (commit: committed, status: 'R100', expected: 'selected.txt'),
      (commit: committed, status: 'D', expected: 'selected.txt'),
    ];

    for (final value in cases) {
      await repository.loadFileHistory(
        value.commit,
        GitFileChange(
          path: 'selected.txt',
          oldPath: 'old.txt',
          status: value.status,
          additions: 0,
          deletions: 0,
        ),
      );
    }

    expect(calls.map((arguments) => arguments.last), [
      for (final value in cases) value.expected,
    ]);
  });

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
    'untracked worktree symlink uses link text for diff file and blame',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      final external = await Directory.systemTemp.createTemp('yogit_external_');
      addTearDown(() => external.delete(recursive: true));
      final sentinel = File('${external.path}/sentinel.txt');
      await sentinel.writeAsString('EXTERNAL_SENTINEL\nDO_NOT_READ\n');
      await writeAndCommit(root, 'base.txt', 'base\n', 'base');
      await Link('${root.path}/untracked-link').create(sentinel.path);

      final repository = GitRepository(root.path);
      final working = (await repository.loadWorkingTree())!;
      final link = (await repository.loadFiles(
        working,
      )).singleWhere((file) => file.path == 'untracked-link');

      final diff = await repository.loadDiff(working, link);
      final bytes = await repository.loadFileBytes(working, link);
      final blame = await repository.loadBlame(working, link);

      expect(
        diff
            .where((line) => line.kind == DiffLineKind.add)
            .map((line) => line.text),
        [sentinel.path],
      );
      expect(utf8.decode(bytes), sentinel.path);
      expect(blame, hasLength(1));
      expect(blame.single.author, 'Uncommitted');
    },
  );

  test('worktree symlink reader preserves every link target form', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    final external = await Directory.systemTemp.createTemp('yogit_external_');
    addTearDown(() => external.delete(recursive: true));
    await writeAndCommit(root, 'base.txt', 'base\n', 'base');
    final sentinel = File('${external.path}/sentinel.txt');
    await sentinel.writeAsString('EXTERNAL_SENTINEL\n');
    final relativeTarget =
        '../${external.uri.pathSegments.where((part) => part.isNotEmpty).last}'
        '/sentinel.txt';
    final targets = <String, String>{
      'relative-link': relativeTarget,
      'absolute-link': sentinel.path,
      'broken-link': 'missing/target',
      'directory-link': external.path,
    };
    for (final entry in targets.entries) {
      await Link('${root.path}/${entry.key}').create(entry.value);
    }

    final repository = GitRepository(root.path);
    final working = (await repository.loadWorkingTree())!;
    final files = {
      for (final file in await repository.loadFiles(working)) file.path: file,
    };

    for (final entry in targets.entries) {
      final bytes = await repository.loadFileBytes(working, files[entry.key]!);
      expect(utf8.decode(bytes), entry.value, reason: entry.key);
    }
  });

  test(
    'tracked worktree symlink blame uses link text through safe contents',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      final external = await Directory.systemTemp.createTemp('yogit_external_');
      addTearDown(() => external.delete(recursive: true));
      final sentinel = File('${external.path}/sentinel.txt');
      await sentinel.writeAsString('EXTERNAL_SENTINEL\nDO_NOT_READ\n');
      final link = Link('${root.path}/tracked-link');
      await link.create('initial-target');
      await runGit(root, ['add', '--', 'tracked-link']);
      await runGit(root, ['commit', '-m', 'base link']);
      await link.delete();
      await link.create(sentinel.path);

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
      final working = (await repository.loadWorkingTree())!;
      final file = (await repository.loadFiles(
        working,
      )).singleWhere((entry) => entry.path == 'tracked-link');

      final diff = await repository.loadDiff(working, file);
      final bytes = await repository.loadFileBytes(working, file);
      final blame = await repository.loadBlame(
        working,
        file,
        workingTreeBytes: bytes,
      );

      expect(
        diff
            .where((line) => line.kind == DiffLineKind.add)
            .map((line) => line.text),
        [sentinel.path],
      );
      expect(utf8.decode(bytes), sentinel.path);
      expect(blame, hasLength(1));
      final blameCall = calls.singleWhere(
        (arguments) => arguments.first == 'blame',
      );
      final contentsPath = blameCall[blameCall.indexOf('--contents') + 1];
      expect(contentsPath, isNot(link.path));
      expect(contentsPath, isNot(sentinel.path));
      expect(contentsPath, startsWith(Directory.systemTemp.path));
      expect(
        FileSystemEntity.typeSync(contentsPath, followLinks: false),
        FileSystemEntityType.notFound,
      );
    },
  );

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
