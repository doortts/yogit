import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/working_tree_status.dart';

import 'full_diff_git_test.dart' show createGitFixture, runGit, writeAndCommit;
import 'support/full_diff_fixtures.dart' show commitA, fileA;

/// git derives an identity from the machine when the config has none, so the
/// identity failure is only deterministic with the outer config files cut off.
GitRepository _configIsolated(Directory root) => GitRepository(
  root.path,
  runner: (executable, arguments, {workingDirectory, environment}) =>
      Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: {
          ...?environment,
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_CONFIG_GLOBAL': '${root.path}/empty-global-gitconfig',
        },
      ),
);

Future<void> _write(Directory root, String path, String contents) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

/// `line 1` … `line [count]`, with [edits] replacing whole lines by number.
/// Two edits far enough apart give the diff two hunks at -U3.
String _numbered(
  int count, {
  Map<int, String> edits = const {},
  String ending = '\n',
  bool trailing = true,
}) {
  final body = [
    for (var line = 1; line <= count; line++) edits[line] ?? 'line $line',
  ].join(ending);
  return trailing ? '$body$ending' : body;
}

/// The index copy of [path], byte for byte.
Future<String> _indexBlob(Directory root, String path) =>
    runGit(root, ['show', ':$path']);

/// The added and removed lines of a patch, in order and signed.
List<String> _changes(List<DiffLine> lines) => [
  for (final line in lines)
    if (line.kind == DiffLineKind.add)
      '+${line.text}'
    else if (line.kind == DiffLineKind.delete)
      '-${line.text}',
];

void main() {
  test('loadWorkingTreeStatus reads both sections from a real repository', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', 'one\ntwo\nthree\n', 'base');
    await _write(root, 'a.txt', 'one\ntwo\nthree\nfour\n');
    await runGit(root, ['add', '--', 'a.txt']);
    await _write(root, 'a.txt', 'one\ntwo\nthree\nfour\nfive\nsix\n');
    await _write(root, 'nested/fresh.txt', 'new\n');

    final status = await GitRepository(root.path).loadWorkingTreeStatus();

    final modified = status.entries.firstWhere((entry) => entry.path == 'a.txt');
    expect(modified.indexStatus, 'M');
    expect(modified.worktreeStatus, 'M');
    expect(status.staged.map((entry) => entry.path), ['a.txt']);
    expect(status.unstaged.map((entry) => entry.path), [
      'a.txt',
      'nested/fresh.txt',
    ]);
    expect(modified.stagedAdditions, 1);
    expect(modified.stagedDeletions, 0);
    expect(modified.unstagedAdditions, 2);
    expect(modified.unstagedDeletions, 0);
    expect(status.hasConflict, isFalse);
  });

  test('stageFiles records an untracked file and a worktree deletion', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'gone.txt', 'bye\n', 'base');
    await File('${root.path}/gone.txt').delete();
    await _write(root, 'fresh.txt', 'new\n');
    final repository = GitRepository(root.path);

    await repository.stageFiles(['gone.txt', 'fresh.txt']);

    expect(
      await runGit(root, ['status', '--porcelain']),
      'A  fresh.txt\nD  gone.txt\n',
    );

    await _write(root, 'later.txt', 'later\n');
    await repository.stageFiles(const []);

    expect(
      await runGit(root, ['status', '--porcelain']),
      'A  fresh.txt\nD  gone.txt\nA  later.txt\n',
    );
  });

  test('unstageFiles restores the index entry and leaves the worktree alone', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', 'one\n', 'base a');
    await writeAndCommit(root, 'b.txt', 'one\n', 'base b');
    await _write(root, 'a.txt', 'one\ntwo\n');
    await _write(root, 'b.txt', 'one\ntwo\n');
    await runGit(root, ['add', '--', 'a.txt', 'b.txt']);
    await _write(root, 'a.txt', 'one\ntwo\nthree\n');
    final repository = GitRepository(root.path);

    await repository.unstageFiles(['a.txt'], hasHead: true);

    expect(await runGit(root, ['status', '--porcelain']), ' M a.txt\nM  b.txt\n');
    expect(await File('${root.path}/a.txt').readAsString(), 'one\ntwo\nthree\n');

    await repository.unstageFiles(const [], hasHead: true);

    expect(await runGit(root, ['status', '--porcelain']), ' M a.txt\n M b.txt\n');
    expect(await File('${root.path}/a.txt').readAsString(), 'one\ntwo\nthree\n');
  });

  test('unstaging a staged rename brings back the old path and drops the new one', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'old.txt', 'one\ntwo\nthree\n', 'base');
    await runGit(root, ['mv', 'old.txt', 'new.txt']);

    await GitRepository(
      root.path,
    ).unstageFiles(['old.txt', 'new.txt'], hasHead: true);

    expect(
      await runGit(root, ['status', '--porcelain']),
      ' D old.txt\n?? new.txt\n',
    );
    expect(File('${root.path}/new.txt').existsSync(), isTrue);
  });

  test('unstage falls back to rm --cached before the first commit', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'a.txt', 'one\n');
    await runGit(root, ['add', '--', 'a.txt']);

    await GitRepository(root.path).unstageFiles(['a.txt'], hasHead: false);

    expect(await runGit(root, ['status', '--porcelain']), '?? a.txt\n');
    expect(await File('${root.path}/a.txt').readAsString(), 'one\n');
  });

  test('discard restores a tracked file from the index and keeps staged changes', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', 'one\n', 'base a');
    await writeAndCommit(root, 'b.txt', 'keep\n', 'base b');
    await _write(root, 'a.txt', 'one\ntwo\n');
    await runGit(root, ['add', '--', 'a.txt']);
    await _write(root, 'a.txt', 'one\ntwo\nthree\n');
    await File('${root.path}/b.txt').delete();
    final repository = GitRepository(root.path);

    await repository.discardWorktreeFile('a.txt');
    await repository.discardWorktreeFile('b.txt');

    expect(await File('${root.path}/a.txt').readAsString(), 'one\ntwo\n');
    expect(await File('${root.path}/b.txt').readAsString(), 'keep\n');
    expect(await runGit(root, ['diff', '--cached', '--name-only']), 'a.txt\n');
  });

  test('discard of an untracked file deletes it and refuses a path outside the repository', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    final outside = await Directory.systemTemp.createTemp('yogit_commit_out_');
    addTearDown(() => outside.delete(recursive: true));
    final secret = File('${outside.path}/secret.txt');
    await secret.writeAsString('keep\n');
    await _write(root, 'fresh.txt', 'new\n');
    await Link('${root.path}/escape.txt').create(secret.path);
    final repository = GitRepository(root.path);

    await repository.discardWorktreeFile('fresh.txt', untracked: true);

    expect(File('${root.path}/fresh.txt').existsSync(), isFalse);

    // 링크를 discard하면 링크만 사라진다 — 저장소 밖의 대상은 그대로다.
    await repository.discardWorktreeFile('escape.txt', untracked: true);

    expect(Link('${root.path}/escape.txt').existsSync(), isFalse);
    expect(await secret.readAsString(), 'keep\n');

    // 부모 디렉터리가 저장소 밖으로 새는 경로는 거부한다.
    await Link('${root.path}/outdir').create(outside.path);

    await expectLater(
      repository.discardWorktreeFile('outdir/secret.txt', untracked: true),
      throwsA(isA<FileSystemException>()),
    );

    expect(await secret.readAsString(), 'keep\n');
  });

  test('discarding an untracked symlink deletes the link, not its target', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'precious.txt', 'keep\n', 'base');
    await Link('${root.path}/link.txt').create('precious.txt');

    await GitRepository(
      root.path,
    ).discardWorktreeFile('link.txt', untracked: true);

    expect(File('${root.path}/precious.txt').existsSync(), isTrue);
    expect(await File('${root.path}/precious.txt').readAsString(), 'keep\n');
    expect(
      await runGit(root, ['status', '--porcelain']),
      isNot(contains(' D precious.txt')),
    );
    expect(Link('${root.path}/link.txt').existsSync(), isFalse);
  });

  test('commitIndex creates the commit with title and body and returns HEAD', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', 'one\n', 'base');
    await _write(root, 'a.txt', 'one\ntwo\n');
    await runGit(root, ['add', '--', 'a.txt']);

    final sha = await GitRepository(root.path).commitIndex(
      message: 'add the second line\n\n#1234 asked for it\nand it was easy',
    );

    expect(sha, (await runGit(root, ['rev-parse', 'HEAD'])).trim());
    expect(
      (await runGit(root, ['log', '-1', '--format=%s'])).trim(),
      'add the second line',
    );
    expect(
      await runGit(root, ['log', '-1', '--format=%B']),
      startsWith('add the second line\n\n#1234 asked for it\nand it was easy\n'),
    );
  });

  test('commitIndex --amend rewrites HEAD', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', 'one\n', 'base');
    await _write(root, 'a.txt', 'one\ntwo\n');
    await runGit(root, ['add', '--', 'a.txt']);
    final repository = GitRepository(root.path);
    final first = await repository.commitIndex(message: 'first message');
    await _write(root, 'a.txt', 'one\ntwo\nthree\n');
    await runGit(root, ['add', '--', 'a.txt']);

    final amended = await repository.commitIndex(
      message: 'amended message',
      amend: true,
    );

    expect(amended, isNot(first));
    expect(amended, (await runGit(root, ['rev-parse', 'HEAD'])).trim());
    expect(
      (await runGit(root, ['log', '-1', '--format=%s'])).trim(),
      'amended message',
    );
    expect((await runGit(root, ['rev-list', '--count', 'HEAD'])).trim(), '2');
  });

  test('commitIndex surfaces identity-missing and pre-commit-hook failures', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', 'one\n', 'base');
    await _write(root, 'a.txt', 'one\ntwo\n');
    await runGit(root, ['add', '--', 'a.txt']);
    await runGit(root, ['config', '--unset', 'user.name']);
    await runGit(root, ['config', '--unset', 'user.email']);
    await runGit(root, ['config', 'user.useConfigOnly', 'true']);

    await expectLater(
      _configIsolated(root).commitIndex(message: 'no identity'),
      throwsA(
        isA<GitRepositoryException>().having(
          (error) => error.message,
          'message',
          'git 사용자 정보가 없습니다. git config user.name / user.email을 설정해 주세요.',
        ),
      ),
    );

    await runGit(root, ['config', 'user.name', 'Test User']);
    await runGit(root, ['config', 'user.email', 'test@example.com']);
    final hook = File('${root.path}/.git/hooks/pre-commit');
    await hook.writeAsString('#!/bin/sh\necho "lint: bad thing" >&2\nexit 1\n');
    await Process.run('chmod', ['+x', hook.path]);

    await expectLater(
      GitRepository(root.path).commitIndex(message: 'hooked'),
      throwsA(
        isA<GitRepositoryException>().having(
          (error) => error.message,
          'message',
          allOf(
            startsWith('pre-commit 훅이 커밋을 거부했습니다.'),
            contains('lint: bad thing'),
          ),
        ),
      ),
    );

    expect((await runGit(root, ['log', '-1', '--format=%s'])).trim(), 'base');
  });

  test('stageHunk stages exactly one of two hunks', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', _numbered(20), 'base');
    final both = _numbered(
      20,
      edits: {3: 'line 3 changed', 17: 'line 17 changed'},
    );
    await _write(root, 'a.txt', both);

    await GitRepository(root.path).stageHunk(
      'a.txt',
      0,
      expected: (oldStart: 1, oldCount: 6, newStart: 1, newCount: 6),
    );

    expect(
      await _indexBlob(root, 'a.txt'),
      _numbered(20, edits: {3: 'line 3 changed'}),
    );
    expect(await File('${root.path}/a.txt').readAsString(), both);
    final staged = await runGit(root, ['diff', '--cached']);
    expect(staged, contains('+line 3 changed'));
    expect(staged, isNot(contains('line 17 changed')));
  });

  test('staging the second hunk first leaves the first hunk unstaged and intact', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', _numbered(20), 'base');
    final both = _numbered(
      20,
      edits: {3: 'line 3 changed', 17: 'line 17 changed'},
    );
    await _write(root, 'a.txt', both);

    await GitRepository(root.path).stageHunk(
      'a.txt',
      1,
      expected: (oldStart: 14, oldCount: 7, newStart: 14, newCount: 7),
    );

    expect(
      await _indexBlob(root, 'a.txt'),
      _numbered(20, edits: {17: 'line 17 changed'}),
    );
    expect(await File('${root.path}/a.txt').readAsString(), both);
    final unstaged = await runGit(root, ['diff']);
    expect(unstaged, contains('+line 3 changed'));
    expect(unstaged, isNot(contains('line 17 changed')));
  });

  test('two consecutive stageHunk calls survive because each re-reads the diff', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', _numbered(20), 'base');
    final both = _numbered(
      20,
      edits: {3: 'line 3 changed', 17: 'line 17 changed'},
    );
    await _write(root, 'a.txt', both);
    final repository = GitRepository(root.path);

    await repository.stageHunk(
      'a.txt',
      1,
      expected: (oldStart: 14, oldCount: 7, newStart: 14, newCount: 7),
    );
    // 남은 헝크는 목록에서 0번으로 밀렸다. 새로 뜬 diff의 0번이라 좌표가 맞는다.
    await repository.stageHunk(
      'a.txt',
      0,
      expected: (oldStart: 1, oldCount: 6, newStart: 1, newCount: 6),
    );

    expect(await _indexBlob(root, 'a.txt'), both);
    expect(await runGit(root, ['diff']), isEmpty);
  });

  test('stageHunk refuses a moved hunk and stages nothing', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', _numbered(20), 'base');
    await _write(
      root,
      'a.txt',
      'line 0\n${_numbered(20, edits: {3: 'line 3 changed', 17: 'line 17 changed'})}',
    );

    await expectLater(
      GitRepository(root.path).stageHunk(
        'a.txt',
        0,
        expected: (oldStart: 1, oldCount: 6, newStart: 1, newCount: 6),
      ),
      throwsA(isA<HunkMovedException>()),
    );

    expect(await runGit(root, ['diff', '--cached']), isEmpty);
  });

  test('discardHunk refuses a hunk the file rewrote at the same line count', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', _numbered(20), 'base');
    await _write(root, 'a.txt', _numbered(20, edits: {3: 'line 3 first'}));
    // 화면이 그린 diff — 헝크 범위와 그 위의 index 줄.
    const expected = (oldStart: 1, oldCount: 6, newStart: 1, newCount: 6);
    final drawn = await runGit(root, ['diff', '--', 'a.txt']);
    final indexLine = drawn
        .split('\n')
        .firstWhere((line) => line.startsWith('index '));

    // 같은 줄을 같은 줄 수로 다시 고친다. 가장 흔한 재편집이고, @@ 숫자 넷은
    // 하나도 움직이지 않아 그것만 보는 검사는 이것을 통과시킨다.
    final second = _numbered(20, edits: {3: 'line 3 second'});
    await _write(root, 'a.txt', second);
    expect(await runGit(root, ['diff', '--', 'a.txt']), contains('@@ -1,6 +1,6 @@'));

    await expectLater(
      GitRepository(root.path).discardHunk(
        'a.txt',
        0,
        expected: expected,
        expectedIndexLine: indexLine,
      ),
      throwsA(isA<HunkMovedException>()),
    );

    expect(
      await File('${root.path}/a.txt').readAsString(),
      second,
      reason: '사용자가 본 적 없는 두 번째 편집을 되돌리지 않는다',
    );
  });

  test('unstageHunk returns one hunk to the worktree-only side', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', _numbered(20), 'base');
    final both = _numbered(
      20,
      edits: {3: 'line 3 changed', 17: 'line 17 changed'},
    );
    await _write(root, 'a.txt', both);
    await runGit(root, ['add', '--', 'a.txt']);

    await GitRepository(root.path).unstageHunk(
      'a.txt',
      0,
      expected: (oldStart: 1, oldCount: 6, newStart: 1, newCount: 6),
    );

    expect(
      await _indexBlob(root, 'a.txt'),
      _numbered(20, edits: {17: 'line 17 changed'}),
    );
    expect(await File('${root.path}/a.txt').readAsString(), both);
    expect(await runGit(root, ['diff']), contains('+line 3 changed'));
  });

  test('unstageHunk on a staged new file empties its index entry', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'seed.txt', 'seed\n', 'base');
    await _write(root, 'fresh.txt', 'fresh one\nfresh two\n');
    await runGit(root, ['add', '--', 'fresh.txt']);

    await GitRepository(root.path).unstageHunk(
      'fresh.txt',
      0,
      expected: (oldStart: 0, oldCount: 0, newStart: 1, newCount: 2),
    );

    expect(await runGit(root, ['status', '--porcelain']), '?? fresh.txt\n');
    expect(
      await File('${root.path}/fresh.txt').readAsString(),
      'fresh one\nfresh two\n',
    );
  });

  test('discardHunk removes the hunk from the worktree only', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', _numbered(20), 'base');
    await _write(root, 'a.txt', _numbered(20, edits: {10: 'line 10 staged'}));
    await runGit(root, ['add', '--', 'a.txt']);
    await _write(
      root,
      'a.txt',
      _numbered(
        20,
        edits: {
          3: 'line 3 changed',
          10: 'line 10 staged',
          17: 'line 17 changed',
        },
      ),
    );

    await GitRepository(root.path).discardHunk(
      'a.txt',
      0,
      expected: (oldStart: 1, oldCount: 6, newStart: 1, newCount: 6),
    );

    expect(
      await File('${root.path}/a.txt').readAsString(),
      _numbered(
        20,
        edits: {10: 'line 10 staged', 17: 'line 17 changed'},
      ),
    );
    expect(
      await _indexBlob(root, 'a.txt'),
      _numbered(20, edits: {10: 'line 10 staged'}),
    );
    expect(
      await runGit(root, ['diff', '--cached']),
      contains('+line 10 staged'),
    );
  });

  test('hunk operations keep a file without trailing newline byte-identical', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', _numbered(20, trailing: false), 'base');
    await _write(
      root,
      'a.txt',
      _numbered(
        20,
        edits: {3: 'line 3 changed', 20: 'line 20 changed'},
        trailing: false,
      ),
    );
    final repository = GitRepository(root.path);

    await repository.stageHunk(
      'a.txt',
      1,
      expected: (oldStart: 17, oldCount: 4, newStart: 17, newCount: 4),
    );

    final tail = _numbered(
      20,
      edits: {20: 'line 20 changed'},
      trailing: false,
    );
    expect(await _indexBlob(root, 'a.txt'), tail);

    await repository.discardHunk(
      'a.txt',
      0,
      expected: (oldStart: 1, oldCount: 6, newStart: 1, newCount: 6),
    );

    expect(await File('${root.path}/a.txt').readAsString(), tail);
    expect(await runGit(root, ['diff']), isEmpty);
  });

  test('hunk operations keep CRLF line endings byte-identical', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await runGit(root, ['config', 'core.autocrlf', 'false']);
    await writeAndCommit(root, 'a.txt', _numbered(20, ending: '\r\n'), 'base');
    final both = _numbered(
      20,
      edits: {3: 'line 3 changed', 17: 'line 17 changed'},
      ending: '\r\n',
    );
    await _write(root, 'a.txt', both);
    final repository = GitRepository(root.path);

    await repository.stageHunk(
      'a.txt',
      0,
      expected: (oldStart: 1, oldCount: 6, newStart: 1, newCount: 6),
    );

    final head = _numbered(20, edits: {3: 'line 3 changed'}, ending: '\r\n');
    expect(await _indexBlob(root, 'a.txt'), head);
    expect(await File('${root.path}/a.txt').readAsString(), both);

    await repository.discardHunk(
      'a.txt',
      0,
      expected: (oldStart: 14, oldCount: 7, newStart: 14, newCount: 7),
    );

    expect(await File('${root.path}/a.txt').readAsString(), head);
    expect(await runGit(root, ['diff']), isEmpty);
  });

  test('stageHunk builds the patch with the algorithm the caller passes', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', _numbered(20), 'base');
    await _write(
      root,
      'a.txt',
      _numbered(20, edits: {3: 'line 3 changed', 17: 'line 17 changed'}),
    );
    final commands = <List<String>>[];
    final repository = GitRepository(
      root.path,
      runner: (executable, arguments, {workingDirectory, environment}) {
        commands.add(arguments);
        return Process.run(
          executable,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
        );
      },
    );

    await repository.stageHunk(
      'a.txt',
      0,
      expected: (oldStart: 1, oldCount: 6, newStart: 1, newCount: 6),
      algorithm: DiffAlgorithm.patience,
    );

    expect(
      commands.firstWhere((arguments) => arguments.first == 'diff'),
      containsAllInOrder(['--diff-algorithm=patience', '--', ':(literal)a.txt']),
    );
    expect(
      await _indexBlob(root, 'a.txt'),
      _numbered(20, edits: {3: 'line 3 changed'}),
    );
  });

  test('loadAreaDiff(unstaged) compares worktree to index and (staged) index to HEAD', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', 'one\ntwo\nthree\n', 'base');
    await _write(root, 'a.txt', 'one\nstaged\nthree\n');
    await runGit(root, ['add', '--', 'a.txt']);
    await _write(root, 'a.txt', 'one\nstaged\nworktree\n');
    final repository = GitRepository(root.path);
    const file = GitFileChange(
      path: 'a.txt',
      status: 'M',
      additions: null,
      deletions: null,
    );

    expect(
      _changes(await repository.loadAreaDiff(WorkingTreeArea.unstaged, file)),
      ['-three', '+worktree'],
    );
    expect(
      _changes(await repository.loadAreaDiff(WorkingTreeArea.staged, file)),
      ['-two', '+staged'],
    );
  });

  test('a file whose name holds glob characters diffs only itself', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'a1.txt', 'one\ntwo\nthree\n');
    await _write(root, 'a[1].txt', 'one\ntwo\nthree\n');
    await runGit(root, ['add', '-A']);
    await runGit(root, ['commit', '-m', 'base']);
    // 이름이 pathspec 와일드카드로 읽히면 `a[1].txt`가 `a1.txt`까지 함께 문다.
    await _write(root, 'a1.txt', 'one\nOTHER-CHANGED\nthree\n');
    await _write(root, 'a[1].txt', 'one\nONE-CHANGED\nthree\n');
    const file = GitFileChange(
      path: 'a[1].txt',
      status: 'M',
      additions: null,
      deletions: null,
    );

    expect(
      _changes(
        await GitRepository(
          root.path,
        ).loadAreaDiff(WorkingTreeArea.unstaged, file),
      ),
      ['-two', '+ONE-CHANGED'],
      reason: '남의 헝크가 섞이면 화면의 헝크 번호가 어긋나 Discard Hunk가 엉뚱한 파일을 지운다',
    );
  });

  test('loadAreaFiles(unstaged) appends untracked files with a synthetic all-add diff', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', 'one\n', 'base');
    await _write(root, 'a.txt', 'one\ntwo\n');
    await _write(root, 'nested/fresh.txt', 'fresh one\nfresh two\n');
    final repository = GitRepository(root.path);

    final files = await repository.loadAreaFiles(WorkingTreeArea.unstaged);

    expect(files.map((file) => file.path), ['a.txt', 'nested/fresh.txt']);
    expect(files.last.status, 'A');
    expect(
      _changes(
        await repository.loadAreaDiff(WorkingTreeArea.unstaged, files.last),
      ),
      ['+fresh one', '+fresh two'],
    );
    expect(await repository.loadAreaFiles(WorkingTreeArea.staged), isEmpty);
  });

  test('loadAreaFiles(staged) lists a rename with both paths', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'old.txt', _numbered(20), 'base');
    await runGit(root, ['mv', 'old.txt', 'new.txt']);

    final files = await GitRepository(
      root.path,
    ).loadAreaFiles(WorkingTreeArea.staged);

    expect(files, hasLength(1));
    expect(files.single.path, 'new.txt');
    expect(files.single.oldPath, 'old.txt');
    expect(files.single.status, startsWith('R'));
  });

  test('loadIndexBytes reads the :0 blob', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await writeAndCommit(root, 'a.txt', 'committed\n', 'base');
    await _write(root, 'a.txt', 'staged\n');
    await runGit(root, ['add', '--', 'a.txt']);
    await _write(root, 'a.txt', 'worktree\n');
    final repository = GitRepository(root.path);
    final wip = (await repository.loadWorkingTree())!;
    const file = GitFileChange(
      path: 'a.txt',
      status: 'M',
      additions: null,
      deletions: null,
    );

    expect(utf8.decode(await repository.loadIndexBytes('a.txt')), 'staged\n');
    expect(
      utf8.decode(
        await WorkingTreeAreaRepository(
          repository,
          WorkingTreeArea.staged,
        ).loadFileBytes(wip, file),
      ),
      'staged\n',
    );
    expect(
      utf8.decode(
        await WorkingTreeAreaRepository(
          repository,
          WorkingTreeArea.unstaged,
        ).loadFileBytes(wip, file),
      ),
      'worktree\n',
    );
  });

  test('staged area diff works before the first commit', () async {
    final root = await createGitFixture();
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'a.txt', 'one\ntwo\n');
    await runGit(root, ['add', '--', 'a.txt']);
    final repository = GitRepository(root.path);

    final files = await repository.loadAreaFiles(WorkingTreeArea.staged);

    expect(files.single.path, 'a.txt');
    expect(files.single.status, 'A');
    expect(files.single.additions, 2);
    expect(
      _changes(
        await repository.loadAreaDiff(WorkingTreeArea.staged, files.single),
      ),
      ['+one', '+two'],
    );
  });

  test('WorkingTreeAreaRepository delegates the remaining members', () async {
    final commands = <List<String>>[];
    final repository = GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        commands.add(arguments);
        return ProcessResult(0, 0, arguments.first == 'config' ? 'myers' : '', '');
      },
    );
    final area = WorkingTreeAreaRepository(
      repository,
      WorkingTreeArea.staged,
    );

    expect(area.root, '/repo');
    expect(
      (await area.loadDiffAlgorithmSetting()).algorithm,
      DiffAlgorithm.myers,
    );
    await area.loadCommitMessage(commitA.sha);
    await area.loadBlame(commitA, fileA);
    await area.loadFileHistory(commitA, fileA);

    expect(commands.map((arguments) => arguments.first), [
      'config',
      'show',
      'blame',
      'log',
    ]);
    expect(commands[1], ['show', '-s', '--format=%B', commitA.sha]);
    expect(commands[2], [
      'blame',
      '--line-porcelain',
      commitA.sha,
      '--',
      fileA.path,
    ]);
    expect(commands[3], containsAllInOrder(['log', '--follow', commitA.sha]));
  });
}
