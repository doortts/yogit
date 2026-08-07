import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/github_api.dart';

/// Contract for the HTTP transport that replaces the gh CLI.
///
/// - REST base URL is stored the yonalist way: the FULL API base
///   (`https://api.github.com` or `https://ghe.host/api/v3`).
/// - GraphQL endpoint derives from the REST base: github.com uses
///   `https://api.github.com/graphql`; a GHE `…/api/v3` base swaps the last
///   segment for `…/api/graphql`.
/// - Every request carries Bearer auth, a User-Agent (GitHub rejects
///   anonymous agents), and the JSON Accept header.
/// - Failures map to [GitHubApiException] with a Korean, user-facing message
///   and the HTTP status where one exists.
void main() {
  ({List<(Uri, String, Map<String, String>, String?)> calls, GitHubApi api})
  apiWith({int status = 200, String body = '{}', String? base}) {
    final responseBody = body;
    final calls = <(Uri, String, Map<String, String>, String?)>[];
    final api = GitHubApi(
      apiBaseUrl: base ?? 'https://api.github.com',
      token: 'token-1',
      send: (uri, {required method, required headers, body}) async {
        calls.add((uri, method, headers, body));
        return (status: status, body: responseBody);
      },
    );
    return (calls: calls, api: api);
  }

  group('URL layout', () {
    test('github.com REST and GraphQL endpoints', () async {
      final fixture = apiWith(body: '{"login":"sc"}');
      await fixture.api.getJson('user');
      await fixture.api.graphql('query{viewer{login}}', {});

      expect(fixture.calls[0].$1, Uri.parse('https://api.github.com/user'));
      expect(
        fixture.calls[1].$1,
        Uri.parse('https://api.github.com/graphql'),
      );
    });

    test('GHE api/v3 REST base derives the api/graphql endpoint', () async {
      final fixture = apiWith(
        base: 'https://oss.navercorp.com/api/v3',
        body: '{}',
      );
      await fixture.api.getJson('repos/team/yonalist/commits/abc');
      await fixture.api.graphql('query{viewer{login}}', {});

      expect(
        fixture.calls[0].$1,
        Uri.parse('https://oss.navercorp.com/api/v3/repos/team/yonalist/commits/abc'),
      );
      expect(
        fixture.calls[1].$1,
        Uri.parse('https://oss.navercorp.com/api/graphql'),
      );
    });

    test('a trailing slash on the base and a leading slash on the path fold',
        () async {
      final fixture = apiWith(base: 'https://oss.navercorp.com/api/v3/');
      await fixture.api.getJson('/user');
      expect(
        fixture.calls.single.$1,
        Uri.parse('https://oss.navercorp.com/api/v3/user'),
      );
    });
  });

  group('request shape', () {
    test('REST GET carries auth, accept, api-version, and a user agent',
        () async {
      final fixture = apiWith();
      await fixture.api.getJson('user');

      final (_, method, headers, body) = fixture.calls.single;
      expect(method, 'GET');
      expect(body, isNull);
      expect(headers['Authorization'], 'Bearer token-1');
      expect(headers['Accept'], 'application/vnd.github+json');
      expect(headers['X-GitHub-Api-Version'], isNotEmpty);
      expect(headers['User-Agent'], contains('yogit'));
    });

    test('GraphQL POSTs a JSON document with variables', () async {
      final fixture = apiWith(body: '{"data":{"ok":true}}');
      await fixture.api.graphql('query(\$n:Int!){x(n:\$n)}', {'n': 3});

      final (_, method, headers, body) = fixture.calls.single;
      expect(method, 'POST');
      expect(headers['Content-Type'], 'application/json');
      final document = jsonDecode(body!) as Map<String, dynamic>;
      expect(document['query'], 'query(\$n:Int!){x(n:\$n)}');
      expect(document['variables'], {'n': 3});
    });
  });

  group('responses and failures', () {
    test('REST returns decoded JSON', () async {
      final fixture = apiWith(body: '{"login":"sc"}');
      expect(await fixture.api.getJson('user'), {'login': 'sc'});
    });

    test('GraphQL returns the data map', () async {
      final fixture = apiWith(
        body: '{"data":{"repository":{"name":"yonalist"}}}',
      );
      final data = await fixture.api.graphql('query{...}', {});
      expect(data, {
        'repository': {'name': 'yonalist'},
      });
    });

    test('401 tells the user the token failed', () async {
      final fixture = apiWith(status: 401, body: '{"message":"Bad credentials"}');
      await expectLater(
        fixture.api.getJson('user'),
        throwsA(
          isA<GitHubApiException>()
              .having((error) => error.status, 'status', 401)
              .having((error) => error.message, 'message', contains('토큰')),
        ),
      );
    });

    test('404 says repository-or-permission in one breath', () async {
      final fixture = apiWith(status: 404, body: '{"message":"Not Found"}');
      await expectLater(
        fixture.api.getJson('repos/a/b'),
        throwsA(
          isA<GitHubApiException>()
              .having((error) => error.status, 'status', 404)
              .having(
                (error) => error.message,
                'message',
                allOf(contains('저장소'), contains('권한')),
              ),
        ),
      );
    });

    test('other HTTP failures carry the status and the server message',
        () async {
      final fixture = apiWith(status: 502, body: 'Bad Gateway');
      await expectLater(
        fixture.api.getJson('user'),
        throwsA(
          isA<GitHubApiException>()
              .having((error) => error.status, 'status', 502)
              .having((error) => error.message, 'message', contains('502')),
        ),
      );
    });

    test('a GraphQL errors array is a failure even with HTTP 200', () async {
      final fixture = apiWith(
        body:
            '{"data":null,"errors":[{"message":"Field snake does not exist"}]}',
      );
      await expectLater(
        fixture.api.graphql('query{snake}', {}),
        throwsA(
          isA<GitHubApiException>().having(
            (error) => error.message,
            'message',
            contains('Field snake does not exist'),
          ),
        ),
      );
    });

    test('non-JSON bodies fail as an exception, not a crash', () async {
      final fixture = apiWith(body: '<html>proxy says no</html>');
      await expectLater(
        fixture.api.getJson('user'),
        throwsA(isA<GitHubApiException>()),
      );
    });
  });
}
