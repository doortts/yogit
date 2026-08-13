import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/git.dart';
import 'package:yogit/github_api.dart';

import 'app_test.dart' show commit;

/// 아바타는 커밋이 아니라 **사람**에 붙는다. 한 사람이 500개를 커밋했어도
/// GitHub에 물을 것은 한 번뿐이고, 그 사람의 다음 행은 기다림 없이 첫 프레임부터
/// 사진으로 그려진다. 계정이 없다는 답도 답이라 다시 묻지 않지만, 답을 못 받은
/// 것(끊긴 요청)은 아직 답이 아니라 다시 물을 수 있어야 한다.
void main() {
  const ada = GitIdentity(name: 'Ada Author', email: 'ada@example.com');
  const cam = GitIdentity(name: 'Cam Committer', email: 'cam@example.com');
  const dana = GitIdentity(name: 'Dana Dev', email: 'dana@example.com');

  const bothAccounts =
      '{"author":{"login":"ada","avatar_url":"https://avatars.example/ada"},'
      '"committer":{"login":"cam","avatar_url":"https://avatars.example/cam"}}';

  ({AvatarService service, List<Uri> requests}) serviceOn(
    Future<HttpResponse> Function(Uri uri) answer, {
    RemoteRepository remote = const RemoteRepository(
      host: 'github.com',
      owner: 'team',
      repository: 'yogit',
    ),
    String token = 'token-1',
  }) {
    final requests = <Uri>[];
    return (
      service: AvatarService(
        remote: remote,
        api: GitHubApi(
          apiBaseUrl: remote.host == 'github.com'
              ? 'https://api.github.com'
              : 'https://${remote.host}/api/v3',
          token: token,
          send: (uri, {required method, required headers, body}) {
            requests.add(uri);
            return answer(uri);
          },
        ),
      ),
      requests: requests,
    );
  }

  Future<HttpResponse> answering(String body) async =>
      (status: 200, body: body);

  test('a second commit by the same author asks the network nothing', () async {
    final fake = serviceOn((_) => answering(bothAccounts));

    await fake.service.resolve('aaa1111', author: ada, committer: cam);
    final second = await fake.service.resolve(
      'bbb2222',
      author: ada,
      committer: cam,
    );

    expect(fake.requests, hasLength(1), reason: '사람은 그대로다');
    expect(second.author?.login, 'ada');
    expect(second.committer?.login, 'cam');
  });

  test(
    'a seen author already answers for a commit never asked about',
    () async {
      final fake = serviceOn((_) => answering(bothAccounts));
      await fake.service.resolve('aaa1111', author: ada, committer: cam);

      final known = fake.service.cachedFor(author: ada, committer: cam);

      expect(known?.author?.login, 'ada', reason: '프레임을 기다리지 않고 답한다');
      expect(known?.committer?.login, 'cam');
    },
  );

  test('two rows of one author scrolling in together ask once', () async {
    final gate = Completer<HttpResponse>();
    final fake = serviceOn((_) => gate.future);

    final first = fake.service.resolve('aaa1111', author: ada, committer: cam);
    final second = fake.service.resolve('bbb2222', author: ada, committer: cam);
    gate.complete((status: 200, body: bothAccounts));

    expect((await first).author?.login, 'ada');
    expect((await second).author?.login, 'ada');
    expect(fake.requests, hasLength(1), reason: '한 사람의 답을 둘이 나눠 쓴다');
  });

  test('another author still costs one request', () async {
    final fake = serviceOn((_) => answering(bothAccounts));

    await fake.service.resolve('aaa1111', author: ada, committer: cam);
    await fake.service.resolve('ccc3333', author: dana, committer: dana);

    expect(fake.requests, hasLength(2));
  });

  test('an author GitHub cannot match is not asked about twice', () async {
    final fake = serviceOn(
      (_) => answering('{"author":null,"committer":null}'),
    );

    await fake.service.resolve('aaa1111', author: ada, committer: cam);
    await fake.service.resolve('bbb2222', author: ada, committer: cam);

    expect(fake.requests, hasLength(1), reason: '계정이 없다는 것도 받은 답이다');
    final known = fake.service.cachedFor(author: ada, committer: cam);
    expect(known, isNotNull, reason: '모르는 것과 없는 것은 다르다');
    expect(known?.author, isNull);
  });

  test('a lookup that never answered can be asked again', () async {
    var attempt = 0;
    final fake = serviceOn(
      (_) async => attempt++ == 0
          ? (status: 500, body: 'offline')
          : (status: 200, body: bothAccounts),
    );

    await fake.service.resolve('aaa1111', author: ada, committer: cam);
    final second = await fake.service.resolve(
      'bbb2222',
      author: ada,
      committer: cam,
    );

    expect(fake.requests, hasLength(2), reason: '끊긴 요청은 아직 답이 아니다');
    expect(second.author?.login, 'ada');
  });

  Future<HttpResponse> noSuchCommit() async =>
      (status: 422, body: '{"message":"No commit found for SHA"}');

  test(
    'an unpushed commit does not answer for the people who wrote it',
    () async {
      final fake = serviceOn(
        (uri) => uri.path.endsWith('local11')
            ? noSuchCommit()
            : answering(bothAccounts),
      );

      // 한 프레임에 들어온 두 행: 맨 위는 아직 푸시하지 않은 커밋, 그 아래는 서버에
      // 있는 커밋이다. 아래 행은 위 행의 요청에 얹혀 기다린다.
      final top = fake.service.resolve('local11', author: ada, committer: cam);
      final below = fake.service.resolve(
        'bbb2222',
        author: ada,
        committer: cam,
      );

      expect((await top).author, isNull, reason: '서버에 없는 커밋은 답이 없다');
      expect(
        (await below).author?.login,
        'ada',
        reason: '푸시 안 한 sha 하나가 사람을 지우지 않는다',
      );
    },
  );

  test('the unpushed row takes the face the next row found', () async {
    final fake = serviceOn(
      (uri) => uri.path.endsWith('local11')
          ? noSuchCommit()
          : answering(bothAccounts),
    );
    final top = fake.service.resolve('local11', author: ada, committer: cam);
    await fake.service.resolve('bbb2222', author: ada, committer: cam);
    await top;

    final again = await fake.service.resolve(
      'local11',
      author: ada,
      committer: cam,
    );

    expect(again.author?.login, 'ada', reason: '얼굴은 커밋이 아니라 사람의 것이다');
    expect(fake.requests, hasLength(2), reason: '없는 커밋을 다시 묻지는 않는다');
  });

  test('a known author with a new committer still fetches the commit', () async {
    final fake = serviceOn(
      (_) => answering(
        '{"author":{"login":"ada","avatar_url":"https://avatars.example/ada"},'
        '"committer":{"login":"dana","avatar_url":"https://avatars.example/dana"}}',
      ),
    );
    await fake.service.resolve('aaa1111', author: ada, committer: ada);

    final second = await fake.service.resolve(
      'bbb2222',
      author: ada,
      committer: dana,
    );

    expect(fake.requests, hasLength(2), reason: '모르는 사람이 하나라도 있으면 묻는다');
    expect(second.committer?.login, 'dana');
  });

  test('a known author is answered while the queue is full', () async {
    final gates = <Completer<HttpResponse>>[];
    var seeded = false;
    final fake = serviceOn((_) {
      if (!seeded) return answering(bothAccounts);
      final gate = Completer<HttpResponse>();
      gates.add(gate);
      return gate.future;
    });
    await fake.service.resolve('aaa1111', author: ada, committer: cam);
    seeded = true;

    // 스크롤이 큐를 가득 채운다 — 저마다 다른 사람이라 모두 물어야 하는 행들이다.
    for (var index = 0; index < 400; index++) {
      unawaited(
        fake.service.resolve(
          'flood$index',
          author: GitIdentity(name: 'User $index', email: 'user$index@x.com'),
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);

    final known = await fake.service.resolve(
      'zzz9999',
      author: ada,
      committer: cam,
    );

    expect(known.author?.login, 'ada', reason: '아는 얼굴은 줄을 서지 않는다');
    expect(fake.service.debugActiveRequestCount, 4);
    for (final gate in gates) {
      gate.complete((status: 500, body: 'offline'));
    }
  });

  test('an enterprise token rides along to the next commit', () async {
    final fake = serviceOn(
      (_) => answering(
        '{"author":{"login":"ada","avatar_url":"https://cdn.example/ada"},'
        '"committer":{"login":"cam","avatar_url":"https://git.example.com/cam"}}',
      ),
      remote: const RemoteRepository(
        host: 'git.example.com',
        owner: 'team',
        repository: 'yogit',
      ),
      token: 'secret-token',
    );

    await fake.service.resolve('aaa1111', author: ada, committer: cam);
    final second = await fake.service.resolve(
      'bbb2222',
      author: ada,
      committer: cam,
    );

    expect(fake.requests, hasLength(1));
    expect(second.author?.headers, isEmpty);
    expect(
      second.committer?.headers['Authorization'],
      'Bearer secret-token',
      reason: '사람으로 기억해도 그 사람의 사진을 받을 열쇠는 함께 간다',
    );
  });

  testWidgets('the next row of a seen author is a photo on its first frame', (
    tester,
  ) async {
    final fake = serviceOn((_) => answering(bothAccounts));
    final seen = commit('aaa1111', 'first commit');
    await fake.service.resolve(
      seen.sha,
      author: seen.author,
      committer: seen.committer,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: CommitAvatarStack(
            // 스크롤로 막 들어온, 한 번도 물어본 적 없는 커밋이다.
            commit: commit('bbb2222', 'a commit never asked about'),
            avatarService: fake.service,
            size: 42,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsWidgets);
    expect(find.text('AA'), findsNothing, reason: '이니셜을 거치지 않는다');
    expect(fake.requests, hasLength(1));
  });
}
