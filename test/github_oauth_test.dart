import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/github_oauth.dart';

/// Contract for browser-loopback OAuth, mirrored from yonalist
/// (src/githubAuthConfig.ts + src/services/oauth.ts):
/// - three built-in servers carry registered OAuth app credentials; any other
///   base URL returns null and the UI guides to a personal token instead;
/// - the flow: listen on an ephemeral localhost port, open the browser at
///   {web base}/login/oauth/authorize, receive GET /auth?code&state, verify
///   state, then exchange the code for a token at
///   {web base}/login/oauth/access_token;
/// - scopes are repo and read:org.
void main() {
  group('credentials and URLs', () {
    test('the three built-in servers resolve, others do not', () {
      for (final base in defaultGithubApiBaseUrls) {
        expect(githubOAuthCredentialsFor(base), isNotNull, reason: base);
      }
      expect(
        githubOAuthCredentialsFor('https://api.github.com/'),
        isNotNull,
        reason: 'a trailing slash is the same server',
      );
      expect(githubOAuthCredentialsFor('https://ghe.example.com/api/v3'), isNull);
    });

    test('the default list leads with 네이버 and carries aliases', () {
      expect(defaultGithubApiBaseUrls.first, 'https://oss.navercorp.com/api/v3');
      expect(
        defaultGithubApiBaseAliases['https://oss.navercorp.com/api/v3'],
        '네이버',
      );
      expect(defaultGithubApiBaseAliases['https://api.github.com'], 'Github');
      expect(githubOAuthScopes, ['repo', 'read:org']);
    });

    test('the web base strips the API suffix', () {
      expect(webBaseUrlOf('https://api.github.com'), 'https://github.com');
      expect(
        webBaseUrlOf('https://oss.navercorp.com/api/v3'),
        'https://oss.navercorp.com',
      );
    });
  });

  group('login flow', () {
    /// Drives a full loopback round trip: capture the authorize URL the
    /// browser would open, then play the part of the browser redirect.
    Future<String> runFlow({
      String? redirectState,
      String? redirectQueryOverride,
      Map<String, Object?> exchangeResponse = const {
        'access_token': 'oauth-token-1',
      },
      List<(Uri, String, Map<String, String>, String?)>? exchangeCalls,
    }) async {
      Uri? authorizeUrl;
      final login = GithubOAuthLogin(
        apiBaseUrl: 'https://oss.navercorp.com/api/v3',
        openBrowser: (uri) async => authorizeUrl = uri,
        send: (uri, {required method, required headers, body}) async {
          exchangeCalls?.add((uri, method, headers, body));
          return (status: 200, body: jsonEncode(exchangeResponse));
        },
      );

      final pending = login.login();
      // The browser opens only after the loopback server is listening.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(authorizeUrl, isNotNull, reason: 'browser never opened');

      final query = authorizeUrl!.queryParameters;
      final redirect = Uri.parse(query['redirect_uri']!);
      final callback = redirect.replace(
        query: redirectQueryOverride ??
            Uri(
              queryParameters: {
                'code': 'code-9',
                'state': redirectState ?? query['state']!,
              },
            ).query,
      );
      final client = HttpClient();
      try {
        final request = await client.getUrl(callback);
        await (await request.close()).drain<void>();
      } finally {
        client.close();
      }
      return pending;
    }

    test('a matching state exchanges the code for a token', () async {
      final exchangeCalls = <(Uri, String, Map<String, String>, String?)>[];
      final token = await runFlow(exchangeCalls: exchangeCalls);

      expect(token, 'oauth-token-1');
      final (uri, method, headers, body) = exchangeCalls.single;
      expect(
        uri,
        Uri.parse('https://oss.navercorp.com/login/oauth/access_token'),
      );
      expect(method, 'POST');
      expect(headers['Accept'], 'application/json');
      final document = jsonDecode(body!) as Map<String, dynamic>;
      expect(document['code'], 'code-9');
      expect(document['client_id'], isNotEmpty);
      expect(document['client_secret'], isNotEmpty);
      expect(document['redirect_uri'], startsWith('http://localhost:'));
    });

    test('the authorize URL carries client, scopes, state, and loopback',
        () async {
      Uri? authorizeUrl;
      final login = GithubOAuthLogin(
        apiBaseUrl: 'https://api.github.com',
        openBrowser: (uri) async => authorizeUrl = uri,
        send: (uri, {required method, required headers, body}) async =>
            (status: 200, body: '{"access_token":"t"}'),
      );
      final pending = login.login();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(authorizeUrl!.host, 'github.com');
      expect(authorizeUrl!.path, '/login/oauth/authorize');
      final query = authorizeUrl!.queryParameters;
      expect(query['client_id'], isNotEmpty);
      expect(query['response_type'], 'code');
      expect(query['scope'], 'repo read:org');
      expect(query['state'], isNotEmpty);
      expect(query['redirect_uri'], startsWith('http://localhost:'));

      // Complete the flow so the server does not leak into the next test.
      final redirect = Uri.parse(query['redirect_uri']!);
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          redirect.replace(
            query: Uri(
              queryParameters: {'code': 'c', 'state': query['state']!},
            ).query,
          ),
        );
        await (await request.close()).drain<void>();
      } finally {
        client.close();
      }
      await pending;
    });

    test('a wrong state is rejected without exchanging the code', () async {
      final exchangeCalls = <(Uri, String, Map<String, String>, String?)>[];
      await expectLater(
        runFlow(redirectState: 'forged', exchangeCalls: exchangeCalls),
        throwsA(isA<Exception>()),
      );
      expect(exchangeCalls, isEmpty);
    });

    test('an error redirect surfaces the description', () async {
      await expectLater(
        runFlow(
          redirectQueryOverride: Uri(
            queryParameters: {
              'error': 'access_denied',
              'error_description': 'The user has denied your application',
            },
          ).query,
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('denied'),
          ),
        ),
      );
    });

    test('an exchange without a token is a failure, not a null', () async {
      await expectLater(
        runFlow(
          exchangeResponse: const {
            'error': 'bad_verification_code',
            'error_description': 'The code passed is incorrect or expired.',
          },
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('expired'),
          ),
        ),
      );
    });

    test('an unregistered server refuses to start the flow', () async {
      final login = GithubOAuthLogin(
        apiBaseUrl: 'https://ghe.example.com/api/v3',
        openBrowser: (_) async {},
        send: (uri, {required method, required headers, body}) async =>
            (status: 200, body: '{}'),
      );
      await expectLater(login.login(), throwsA(isA<Exception>()));
    });
  });
}
