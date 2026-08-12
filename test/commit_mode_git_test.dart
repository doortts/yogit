import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';

import 'full_diff_git_test.dart' show createGitFixture, runGit, writeAndCommit;

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

    await expectLater(
      repository.discardWorktreeFile('escape.txt', untracked: true),
      throwsA(isA<FileSystemException>()),
    );

    expect(await secret.readAsString(), 'keep\n');
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
}
