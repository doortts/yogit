import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/git.dart';

const _textByteLimit = 10 * 1024 * 1024;
const _largeFileLength = 32 * 1024 * 1024;

Future<String> runGit(
  Directory root,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
    environment: environment,
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
  String subject, {
  Map<String, String>? environment,
}) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
  await runGit(root, ['add', '--', path]);
  await runGit(root, ['commit', '-m', subject], environment: environment);
}

Future<void> writeSparseLargeFile(Directory root, String path) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  final handle = await file.open(mode: FileMode.write);
  try {
    await handle.setPosition(_textByteLimit);
    await handle.writeByte(0x42);
    await handle.setPosition(_largeFileLength - 1);
    await handle.writeByte(0x7A);
  } finally {
    await handle.close();
  }
}

Future<void> writeLargeTextFile(Directory root, String path) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(
    Uint8List(_textByteLimit + 2)..fillRange(0, _textByteLimit + 2, 0x61),
    flush: true,
  );
}

Future<Set<String>> blameTemporaryDirectories() async => {
  await for (final entity in Directory.systemTemp.list(followLinks: false))
    if (entity is Directory &&
        entity.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last
            .startsWith('yogit_blame_'))
      entity.path,
};

void main() {
  test(
    'diff scope changes context without dropping algorithm options',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(root, 'sample.txt', 'one\ntwo\nthree\n', 'base');
      await File(
        '${root.path}/sample.txt',
      ).writeAsString('one\nchanged\nthree\n');
      await runGit(root, ['commit', '-am', 'change']);

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

      await repository.loadDiff(
        commit,
        file,
        scope: DiffScope.hunks,
        algorithm: DiffAlgorithm.patience,
        ignoreWhitespace: true,
      );
      await repository.loadDiff(
        commit,
        file,
        scope: DiffScope.fullFile,
        algorithm: DiffAlgorithm.patience,
        ignoreWhitespace: true,
      );

      final diffCalls = calls
          .where(
            (call) =>
                call.first == 'diff' &&
                call.any((argument) => argument.startsWith('--unified=')),
          )
          .toList();
      expect(diffCalls[0], contains('--unified=3'));
      expect(diffCalls[1], contains('--unified=$fullDiffTextLineLimit'));
      for (final call in diffCalls) {
        expect(call, contains('--diff-algorithm=patience'));
        expect(call, contains('--ignore-all-space'));
      }
    },
  );

  test(
    'selected git algorithm changes the parsed patch when boundaries differ',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(
        root,
        'repeated.txt',
        'A\nD\nB\nD\nD\nD\nC\nA\nD\nA\nD\nA\n',
        'base',
      );
      await File(
        '${root.path}/repeated.txt',
      ).writeAsString('A\nB\nC\nD\nC\nC\nA\nD\nD\nC\nA\nB\n');
      await runGit(root, ['commit', '-am', 'reorder repeated lines']);
      final repository = GitRepository(root.path);
      final commit = (await repository.loadHistory()).first;
      final file = (await repository.loadFiles(commit)).single;

      final myers = await repository.loadDiff(
        commit,
        file,
        algorithm: DiffAlgorithm.myers,
      );
      final histogram = await repository.loadDiff(
        commit,
        file,
        algorithm: DiffAlgorithm.histogram,
      );
      List<String> signature(List<DiffLine> lines) =>
          lines.map((line) => '${line.kind.name}:${line.text}').toList();

      expect(signature(histogram), isNot(signature(myers)));
    },
  );

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

  test('bounds a 32 MiB untracked file snapshot', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'base.txt', 'base\n', 'base');
    await writeSparseLargeFile(root, 'large.bin');
    final repository = GitRepository(root.path);
    final working = (await repository.loadWorkingTree())!;
    final file = (await repository.loadFiles(
      working,
    )).singleWhere((entry) => entry.path == 'large.bin');

    final bytes = await repository.loadFileBytes(working, file);

    expect(bytes, hasLength(_textByteLimit + 1));
    expect(bytes.last, 0x42);
  });

  test(
    'preflights an oversized committed blob without invoking show',
    () async {
      final calls = <List<String>>[];
      var rawCalls = 0;
      final repository = GitRepository(
        '/unused',
        runner: (executable, arguments, {workingDirectory}) async {
          calls.add(List.unmodifiable(arguments));
          return ProcessResult(1, 0, '${_textByteLimit + 2}\n', '');
        },
        rawRunner: (executable, arguments, {workingDirectory}) async {
          rawCalls++;
          throw StateError('git show must not run for an oversized blob');
        },
      );

      final bytes = await repository.loadBlobBytes('deadbeef', 'large.txt');
      final document = FileDocument.fromBytes(
        revision: 'deadbeef',
        path: 'large.txt',
        side: FileDocumentSide.result,
        bytes: bytes,
        gitMarkedBinary: false,
      );

      expect(calls, [
        ['cat-file', '-s', 'deadbeef:large.txt'],
      ]);
      expect(rawCalls, 0);
      expect(bytes, hasLength(_textByteLimit + 1));
      expect(document.kind, FileContentKind.tooLarge);
      expect(document.limitReason, FileContentLimitReason.byteLimit);
    },
  );

  test('bounds a committed blob before classifying it as too large', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeLargeTextFile(root, 'large.txt');
    await runGit(root, ['add', '--all']);
    await runGit(root, ['commit', '-m', 'large text']);
    final repository = GitRepository(root.path);
    final commit = (await repository.loadHistory()).single;
    final file = (await repository.loadFiles(commit)).single;

    final bytes = await repository.loadFileBytes(commit, file);
    final document = FileDocument.fromBytes(
      revision: commit.sha,
      path: file.path,
      side: FileDocumentSide.result,
      bytes: bytes,
      gitMarkedBinary: file.isBinary,
    );

    expect(bytes, hasLength(_textByteLimit + 1));
    expect(document.kind, FileContentKind.tooLarge);
    expect(document.limitReason, FileContentLimitReason.byteLimit);
  });

  test('skips synthetic diff rows for a 32 MiB untracked file', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'base.txt', 'base\n', 'base');
    await writeSparseLargeFile(root, 'large.bin');
    final repository = GitRepository(root.path);
    final working = (await repository.loadWorkingTree())!;
    final file = (await repository.loadFiles(
      working,
    )).singleWhere((entry) => entry.path == 'large.bin');

    final diff = await repository.loadDiff(working, file);

    expect(diff, isEmpty);
  });

  test(
    'rejects untracked blame after its displayed file grows to 32 MiB',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(root, 'base.txt', 'base\n', 'base');
      await File('${root.path}/large.bin').writeAsString('displayed\n');
      final repository = GitRepository(root.path);
      final working = (await repository.loadWorkingTree())!;
      final file = (await repository.loadFiles(
        working,
      )).singleWhere((entry) => entry.path == 'large.bin');
      final displayedBytes = await repository.loadFileBytes(working, file);
      await writeSparseLargeFile(root, 'large.bin');
      final temporaryDirectoriesBefore = await blameTemporaryDirectories();

      await expectLater(
        repository.loadBlame(working, file, workingTreeBytes: displayedBytes),
        throwsA(isA<StateError>()),
      );

      expect(await blameTemporaryDirectories(), temporaryDirectoriesBefore);
    },
  );

  test(
    'rejects tracked blame after its displayed file grows to 32 MiB',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(root, 'large.bin', 'small\n', 'base');
      await File('${root.path}/large.bin').writeAsString('displayed\n');
      final fixtureRepository = GitRepository(root.path);
      final working = (await fixtureRepository.loadWorkingTree())!;
      final file = (await fixtureRepository.loadFiles(working)).single;
      final displayedBytes = await fixtureRepository.loadFileBytes(
        working,
        file,
      );
      await writeSparseLargeFile(root, 'large.bin');
      var blameCalls = 0;
      final repository = GitRepository(
        root.path,
        runner: (executable, arguments, {workingDirectory}) {
          if (arguments.first == 'blame') {
            blameCalls++;
            return Future.value(ProcessResult(1, 0, '', ''));
          }
          return runProcess(
            executable,
            arguments,
            workingDirectory: workingDirectory,
          );
        },
      );
      final temporaryDirectoriesBefore = await blameTemporaryDirectories();

      await expectLater(
        repository.loadBlame(working, file, workingTreeBytes: displayedBytes),
        throwsA(isA<StateError>()),
      );

      expect(blameCalls, 0);
      expect(await blameTemporaryDirectories(), temporaryDirectoriesBefore);
    },
  );

  test('removes tracked blame contents when its runner fails', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'tracked.txt', 'one\n', 'base');
    await File('${root.path}/tracked.txt').writeAsString('one\ntwo\n');
    final fixtureRepository = GitRepository(root.path);
    final working = (await fixtureRepository.loadWorkingTree())!;
    final file = (await fixtureRepository.loadFiles(working)).single;
    final displayedBytes = await fixtureRepository.loadFileBytes(working, file);
    String? contentsPath;
    final repository = GitRepository(
      root.path,
      runner: (executable, arguments, {workingDirectory}) {
        if (arguments.first == 'blame') {
          contentsPath = arguments[arguments.indexOf('--contents') + 1];
          return Future.value(ProcessResult(1, 1, '', 'forced blame failure'));
        }
        return runProcess(
          executable,
          arguments,
          workingDirectory: workingDirectory,
        );
      },
    );
    final temporaryDirectoriesBefore = await blameTemporaryDirectories();

    await expectLater(
      repository.loadBlame(working, file, workingTreeBytes: displayedBytes),
      throwsA(isA<ProcessException>()),
    );

    expect(contentsPath, isNotNull);
    expect(
      FileSystemEntity.typeSync(contentsPath!, followLinks: false),
      FileSystemEntityType.notFound,
    );
    expect(await blameTemporaryDirectories(), temporaryDirectoriesBefore);
  });

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

  test('preserves blame author metadata by sha', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    const firstTimestamp = '1704067200 +0000';
    await writeAndCommit(
      root,
      'fixture.txt',
      'first\nsecond\n',
      'add fixture',
      environment: {
        'GIT_AUTHOR_DATE': firstTimestamp,
        'GIT_COMMITTER_DATE': firstTimestamp,
      },
    );
    await writeAndCommit(
      root,
      'other.txt',
      'unrelated\n',
      'add unrelated',
      environment: {
        'GIT_AUTHOR_DATE': '1704067201 +0000',
        'GIT_COMMITTER_DATE': '1704067201 +0000',
      },
    );

    final repository = GitRepository(root.path);
    final commit = (await repository.loadHistory()).firstWhere(
      (entry) => entry.subject == 'add fixture',
    );
    final file = (await repository.loadFiles(
      commit,
    )).singleWhere((entry) => entry.path == 'fixture.txt');
    final lines = await repository.loadBlame(commit, file);

    expect(lines.first.authorEmail, 'test@example.com');
    expect(lines.first.authorTimestamp, 1704067200);
    expect(lines.first.summary, 'add fixture');
    expect(lines[1].authorEmail, lines.first.authorEmail);
    expect(lines[1].authorTimestamp, lines.first.authorTimestamp);
    expect(lines[1].summary, lines.first.summary);

    const sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const missingSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const uncommittedSha = '0000000000000000000000000000000000000000';
    const porcelain =
        '''$sha 1 1 2
author Test User
author-mail <test@example.com>
author-time 1704067200
summary add fixture
filename fixture.txt
\tfirst
$sha 2 2
\tsecond
$missingSha 3 3
\tmissing
$uncommittedSha 4 4
\tuncommitted
''';
    const identity = GitIdentity(name: 'Test User', email: 'test@example.com');
    const fixtureCommit = GitCommit(
      sha: 'head',
      shortSha: 'head',
      parents: ['base'],
      author: identity,
      authorTimestamp: 0,
      committer: identity,
      committerTimestamp: 0,
      refs: [],
      subject: 'head',
    );
    const fixtureFile = GitFileChange(
      path: 'fixture.txt',
      status: 'M',
      additions: 0,
      deletions: 0,
    );
    final fixtureRepository = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory}) async =>
          ProcessResult(0, 0, porcelain, ''),
    );

    final fixtureLines = await fixtureRepository.loadBlame(
      fixtureCommit,
      fixtureFile,
    );

    expect(fixtureLines[1].authorEmail, 'test@example.com');
    expect(fixtureLines[1].authorTimestamp, 1704067200);
    expect(fixtureLines[1].summary, 'add fixture');
    expect(fixtureLines[2].author, '');
    expect(fixtureLines[2].authorEmail, '');
    expect(fixtureLines[2].authorTimestamp, isNull);
    expect(fixtureLines[2].summary, '');
    expect(fixtureLines[2].uncommitted, isFalse);
    expect(fixtureLines[3].author, '');
    expect(fixtureLines[3].authorEmail, '');
    expect(fixtureLines[3].authorTimestamp, isNull);
    expect(fixtureLines[3].summary, '');
    expect(fixtureLines[3].uncommitted, isTrue);
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

  test('synthesizes blame for a staged working tree addition', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'base.txt', 'base\n', 'base');
    await File('${root.path}/staged.txt').writeAsString('one\ntwo\n');
    await runGit(root, ['add', '--', 'staged.txt']);
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
    )).singleWhere((entry) => entry.path == 'staged.txt');
    final bytes = await repository.loadFileBytes(working, file);

    final blame = await repository.loadBlame(
      working,
      file,
      workingTreeBytes: bytes,
    );

    expect(file.status, 'A');
    expect(blame, hasLength(2));
    expect(blame, everyElement(isA<GitBlameLine>()));
    expect(blame.every((line) => line.uncommitted), isTrue);
    expect(calls.where((arguments) => arguments.first == 'blame'), isEmpty);
  });

  test(
    'blames a worktree rename from its captured base and old path',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(root, 'before.txt', 'committed\n', 'base');
      await runGit(root, ['mv', 'before.txt', 'after.txt']);
      await File(
        '${root.path}/after.txt',
      ).writeAsString('committed\nworking\n');
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
      )).singleWhere((entry) => entry.path == 'after.txt');
      final bytes = await repository.loadFileBytes(working, file);

      final blame = await repository.loadBlame(
        working,
        file,
        workingTreeBytes: bytes,
      );

      expect(file.status, startsWith('R'));
      expect(file.oldPath, 'before.txt');
      expect(blame, hasLength(2));
      expect(blame.first.uncommitted, isFalse);
      expect(blame.last.uncommitted, isTrue);
      final blameCall = calls.singleWhere(
        (arguments) => arguments.first == 'blame',
      );
      expect(blameCall, contains(working.parents.single));
      expect(blameCall, contains('before.txt'));
      expect(blameCall, isNot(contains('HEAD')));
      expect(blameCall, isNot(contains('after.txt')));
    },
  );

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

  test('loads result blob sizes with one ls-tree query', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'modified.txt', 'before\n', 'base');
    await writeAndCommit(root, 'renamed.txt', 'rename before\n', 'rename base');
    await File('${root.path}/modified.txt').writeAsString('changed ✓\n');
    await File('${root.path}/added.txt').writeAsString('added 🎉\n');
    await runGit(root, ['mv', 'renamed.txt', 'renamed result.txt']);
    await runGit(root, ['add', '--all']);
    await runGit(root, ['commit', '-m', 'change files']);

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
    final files = {
      for (final file in await repository.loadFiles(commit)) file.path: file,
    };

    expect(files['modified.txt']!.sizeBytes, 12);
    expect(files['added.txt']!.sizeBytes, 11);
    expect(files['renamed result.txt']!.sizeBytes, 14);
    final sizeQuery = calls.singleWhere(
      (arguments) => arguments.first == 'ls-tree',
    );
    expect(sizeQuery.sublist(0, 4), ['ls-tree', '-rlz', commit.sha, '--']);
    expect(sizeQuery.sublist(4).toSet(), {
      ':(literal)modified.txt',
      ':(literal)added.txt',
      ':(literal)renamed result.txt',
    });
  });

  test(
    'loads deleted sizes from the selected parent with at most two queries',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(root, 'modified.txt', 'before\n', 'base');
      await writeAndCommit(root, 'deleted.txt', 'delete me ✓\n', 'delete base');
      await File('${root.path}/modified.txt').writeAsString('after 🎉\n');
      await runGit(root, ['rm', 'deleted.txt']);
      await runGit(root, ['add', '--all']);
      await runGit(root, ['commit', '-m', 'modify and delete']);

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
      final files = {
        for (final file in await repository.loadFiles(commit)) file.path: file,
      };

      expect(files['modified.txt']!.sizeBytes, 11);
      expect(files['deleted.txt']!.sizeBytes, 14);
      final sizeQueries = calls
          .where((arguments) => arguments.first == 'ls-tree')
          .toList();
      expect(sizeQueries, hasLength(2));
      expect(
        sizeQueries.map((arguments) => arguments[2]),
        contains(commit.sha),
      );
      expect(
        sizeQueries.map((arguments) => arguments[2]),
        contains(commit.parents.single),
      );
    },
  );

  test('uses the explicit merge parent for deleted size metadata', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'selected.txt', 'base\n', 'base');
    await runGit(root, ['checkout', '-b', 'side']);
    const sideContents = 'selected parent ✓\n';
    await File('${root.path}/selected.txt').writeAsString(sideContents);
    await runGit(root, ['commit', '-am', 'side modifies selected']);
    final sideSha = (await runGit(root, ['rev-parse', 'HEAD'])).trim();
    await runGit(root, ['checkout', 'main']);
    await runGit(root, ['rm', '--', 'selected.txt']);
    await runGit(root, ['commit', '-m', 'main deletes selected']);
    final merge = await Process.run('git', [
      'merge',
      '--no-ff',
      'side',
      '-m',
      'merge side',
    ], workingDirectory: root.path);
    expect(merge.exitCode, isNonZero, reason: 'fixture needs modify/delete');
    await runGit(root, ['rm', '--', 'selected.txt']);
    await runGit(root, ['commit', '-m', 'resolve merge as deletion']);

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
    expect(commit.parents, hasLength(2));
    expect(commit.parents, contains(sideSha));

    final file = (await repository.loadFiles(commit, parent: sideSha)).single;

    expect(file.status, startsWith('D'));
    expect(file.sizeBytes, utf8.encode(sideContents).length);
    final sizeQuery = calls.singleWhere(
      (arguments) => arguments.first == 'ls-tree',
    );
    expect(sizeQuery[2], sideSha);
  });

  test('isolates result and deleted size batch failures', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'modified.txt', 'before\n', 'base');
    const deletedContents = 'deleted parent ✓\n';
    await writeAndCommit(
      root,
      'deleted.txt',
      deletedContents,
      'add deleted file',
    );
    await File('${root.path}/modified.txt').writeAsString('after\n');
    await runGit(root, ['rm', '--', 'deleted.txt']);
    await runGit(root, ['commit', '-am', 'modify and delete']);

    String? resultRevision;
    final calls = <List<String>>[];
    final repository = GitRepository(
      root.path,
      runner: (executable, arguments, {workingDirectory}) {
        calls.add(List.unmodifiable(arguments));
        if (arguments.first == 'ls-tree' && arguments[2] == resultRevision) {
          return Future.value(
            ProcessResult(1, 1, '', 'forced result-size failure'),
          );
        }
        return runProcess(
          executable,
          arguments,
          workingDirectory: workingDirectory,
        );
      },
    );
    final commit = (await repository.loadHistory()).first;
    resultRevision = commit.sha;

    final files = {
      for (final file in await repository.loadFiles(commit)) file.path: file,
    };

    expect(files['modified.txt']!.sizeBytes, isNull);
    expect(
      files['deleted.txt']!.sizeBytes,
      utf8.encode(deletedContents).length,
    );
    final sizeQueries = calls
        .where((arguments) => arguments.first == 'ls-tree')
        .toList();
    expect(sizeQueries, hasLength(2));
    expect(
      sizeQueries.map((arguments) => arguments[2]),
      containsAll([commit.sha, commit.parents.single]),
    );
  });

  test('parses ls-tree sizes for paths containing spaces and tabs', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    const spacedPath = 'space name.txt';
    const tabbedPath = 'tab\tname.txt';
    await writeAndCommit(root, spacedPath, 'old\n', 'space base');
    await writeAndCommit(root, tabbedPath, 'old\n', 'tab base');
    await File('${root.path}/$spacedPath').writeAsString('spaced ✓\n');
    await File('${root.path}/$tabbedPath').writeAsString('tabbed 🎉\n');
    await runGit(root, ['add', '--all']);
    await runGit(root, ['commit', '-m', 'special paths']);

    final repository = GitRepository(root.path);
    final commit = (await repository.loadHistory()).first;
    final files = {
      for (final file in await repository.loadFiles(commit)) file.path: file,
    };

    expect(files[spacedPath]!.sizeBytes, 11);
    expect(files[tabbedPath]!.sizeBytes, 12);
  });

  test('loads sizes for a leading-colon path as a literal pathspec', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    const path = ':leading.txt';
    await File('${root.path}/$path').writeAsString('before\n');
    await runGit(root, ['add', '--all']);
    await runGit(root, ['commit', '-m', 'base']);
    await File('${root.path}/$path').writeAsString('after colon\n');
    await runGit(root, ['add', '--all']);
    await runGit(root, ['commit', '-m', 'change leading colon']);

    final repository = GitRepository(root.path);
    final commit = (await repository.loadHistory()).first;
    final file = (await repository.loadFiles(
      commit,
    )).singleWhere((entry) => entry.path == path);

    expect(file.sizeBytes, utf8.encode('after colon\n').length);
  });

  test('keeps files when size metadata lookup fails', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'tracked.txt', 'before\n', 'base');
    await File('${root.path}/tracked.txt').writeAsString('after\n');
    await runGit(root, ['commit', '-am', 'change']);

    final repository = GitRepository(
      root.path,
      runner: (executable, arguments, {workingDirectory}) {
        if (arguments.first == 'ls-tree') {
          return Future.value(
            ProcessResult(1, 1, '', 'forced ls-tree failure'),
          );
        }
        return runProcess(
          executable,
          arguments,
          workingDirectory: workingDirectory,
        );
      },
    );
    final commit = (await repository.loadHistory()).first;
    final files = await repository.loadFiles(commit);

    expect(files, hasLength(1));
    expect(files.single.path, 'tracked.txt');
    expect(files.single.sizeBytes, isNull);
  });

  test(
    'loads working tree file and symbolic link sizes without blob reads',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(root, 'regular.txt', 'before\n', 'file base');
      await Link('${root.path}/link').create('before-target');
      await runGit(root, ['add', '--', 'link']);
      await runGit(root, ['commit', '-m', 'link base']);
      await File('${root.path}/regular.txt').writeAsString('working ✓\n');
      await Link('${root.path}/link').delete();
      await Link('${root.path}/link').create('working-target ✓');

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
      final files = {
        for (final file in await repository.loadFiles(working)) file.path: file,
      };

      expect(files['regular.txt']!.sizeBytes, 12);
      expect(files['link']!.sizeBytes, 18);
      expect(calls.where((arguments) => arguments.first == 'show'), isEmpty);
      expect(calls.where((arguments) => arguments.first == 'ls-tree'), isEmpty);
    },
  );

  test('loads a worktree deletion size from its captured base', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    const contents = 'deleted from worktree ✓\n';
    await writeAndCommit(root, 'deleted.txt', contents, 'base');
    await runGit(root, ['rm', '--', 'deleted.txt']);

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
    final file = (await repository.loadFiles(working)).single;

    expect(file.status, startsWith('D'));
    expect(file.sizeBytes, utf8.encode(contents).length);
    final sizeQuery = calls.singleWhere(
      (arguments) => arguments.first == 'ls-tree',
    );
    expect(sizeQuery[2], working.parents.single);
  });

  test(
    'keeps captured worktree files when they disappear before stat',
    () async {
      final root = await createGitFixture();
      addTearDown(() => root.delete(recursive: true));
      await writeAndCommit(root, 'racing.txt', 'before\n', 'base');
      final racingFile = File('${root.path}/racing.txt');
      await racingFile.writeAsString('modified\n');
      var removedBeforeStat = false;
      final repository = GitRepository(
        root.path,
        runner: (executable, arguments, {workingDirectory}) async {
          final result = await runProcess(
            executable,
            arguments,
            workingDirectory: workingDirectory,
          );
          if (!removedBeforeStat &&
              arguments.length >= 2 &&
              arguments[0] == 'ls-files' &&
              arguments[1] == '--others') {
            await racingFile.delete();
            removedBeforeStat = true;
          }
          return result;
        },
      );
      final working = (await repository.loadWorkingTree())!;

      final file = (await repository.loadFiles(working)).single;

      expect(removedBeforeStat, isTrue);
      expect(file.path, 'racing.txt');
      expect(file.status, startsWith('M'));
      expect(file.sizeBytes, isNull);
    },
  );
}
