import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';

import 'full_diff_git_test.dart' show createGitFixture, runGit, writeAndCommit;

/// 히스토리 고쳐 쓰기는 진짜 git 위에서만 확인이 된다 — todo 파일을 `cp`로
/// 덮어쓰는 걸음도, `exec git commit --amend`도 git이 실행해 줘야 도는 것이다.
void main() {
  late Directory root;
  late GitRepository repository;

  setUp(() async {
    root = await createGitFixture();
    repository = GitRepository(root.path);
    await writeAndCommit(root, 'a.txt', 'a\n', 'first');
    await writeAndCommit(root, 'b.txt', 'b\n', 'second');
    await writeAndCommit(root, 'c.txt', 'c\n', 'third');
  });

  tearDown(() => root.delete(recursive: true));

  Future<List<String>> subjects() async =>
      (await runGit(root, ['log', '--format=%s']))
          .trim()
          .split('\n')
          .where((line) => line.isNotEmpty)
          .toList();

  Future<String> shaOf(String subject) async => (await runGit(root, [
    'log',
    '--format=%H %s',
  ])).trim().split('\n').firstWhere((line) => line.endsWith(' $subject')).split(' ').first;

  test('a middle commit takes a new message and keeps the ones after it', () async {
    await repository.rewriteHistory(
      base: await shaOf('first'),
      steps: [
        RewriteStep(await shaOf('second'), message: 'second, reworded\n'),
        RewriteStep(await shaOf('third')),
      ],
    );

    expect(await subjects(), ['third', 'second, reworded', 'first']);
    // 커밋 내용은 그대로다 — 메시지만 갈렸다.
    expect(await runGit(root, ['show', '--format=', '--name-only', 'HEAD~1']),
        contains('b.txt'));
  });

  test('fixup folds the newer commit into the older one', () async {
    await repository.rewriteHistory(
      base: await shaOf('first'),
      steps: [
        RewriteStep(await shaOf('second'), message: 'second and third\n'),
        RewriteStep(await shaOf('third'), action: RewriteAction.fixup),
      ],
    );

    expect(await subjects(), ['second and third', 'first']);
    final files = await runGit(root, ['show', '--format=', '--name-only', 'HEAD']);
    expect(files, contains('b.txt'));
    expect(files, contains('c.txt'));
  });

  test('drop removes one commit and its files', () async {
    await repository.rewriteHistory(
      base: await shaOf('first'),
      steps: [
        RewriteStep(await shaOf('second'), action: RewriteAction.drop),
        RewriteStep(await shaOf('third')),
      ],
    );

    expect(await subjects(), ['third', 'first']);
    expect(File('${root.path}/b.txt').existsSync(), isFalse);
  });

  test('steps out of order reorder the commits', () async {
    await repository.rewriteHistory(
      base: await shaOf('first'),
      steps: [
        RewriteStep(await shaOf('third')),
        RewriteStep(await shaOf('second')),
      ],
    );

    expect(await subjects(), ['second', 'third', 'first']);
  });

  test('an amended author and date ride along with the pick', () async {
    await repository.rewriteHistory(
      base: await shaOf('second'),
      steps: [
        RewriteStep(
          await shaOf('third'),
          author: "Sam O'Hara <sam@example.com>",
          date: '2024-03-04T05:06:07+09:00',
        ),
      ],
    );

    expect(
      (await runGit(root, ['log', '-1', '--format=%an <%ae>%n%aI'])).trim(),
      "Sam O'Hara <sam@example.com>\n2024-03-04T05:06:07+09:00",
    );
    expect(await subjects(), ['third', 'second', 'first']);
  });

  test('a conflicting rewrite leaves no rebase behind', () async {
    // 같은 파일의 같은 줄을 두 커밋이 건드리면, 앞 커밋을 버리는 순간 뒤 커밋이
    // 충돌한다.
    await writeAndCommit(root, 'a.txt', 'a\nsecond touch\n', 'touch a');
    await writeAndCommit(root, 'a.txt', 'a\nthird touch\n', 'touch a again');

    await expectLater(
      repository.rewriteHistory(
        base: await shaOf('third'),
        steps: [
          RewriteStep(await shaOf('touch a'), action: RewriteAction.drop),
          RewriteStep(await shaOf('touch a again')),
        ],
      ),
      throwsA(isA<GitRepositoryException>()),
    );
    expect(
      Directory('${root.path}/.git/rebase-merge').existsSync(),
      isFalse,
      reason: '되돌린 rebase는 흔적을 남기지 않는다',
    );
    expect(await subjects(), ['touch a again', 'touch a', 'third', 'second', 'first']);
  });

  test('revert undoes the newest commits and a new branch points where told', () async {
    await repository.revertCommits([await shaOf('third')]);
    expect(await subjects(), [
      'Revert "third"',
      'third',
      'second',
      'first',
    ]);
    expect(File('${root.path}/c.txt').existsSync(), isFalse);

    await repository.createBranchAt('keep/second', await shaOf('second'));
    expect(
      (await runGit(root, ['rev-parse', 'keep/second'])).trim(),
      await shaOf('second'),
    );
  });
}
