import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/github_auth.dart';
import 'package:yogit/github_oauth.dart';
import 'package:yogit/settings.dart';

/// Contract for the settings "GitHub 서버" section (approved mockup):
/// - the three built-in servers plus user-added ones, each row wearing its
///   login state; the selected server is what the monitor and avatars use;
/// - the login card: browser login only for registered servers, a token
///   field for every server, the scope hint (repo · read:org), a 연결 확인
///   button that calls GET /user, and logout deleting the Keychain entry;
/// - tokens never live in settings.json — only in the Keychain.
void main() {
  group('AppSettings github fields', () {
    test('selected server and custom servers round-trip, 네이버 is default', () {
      const settings = AppSettings();
      expect(settings.githubApiBaseUrl, defaultGithubApiBaseUrls.first);
      expect(settings.customGithubApiBaseUrls, isEmpty);

      const custom = AppSettings(
        githubApiBaseUrl: 'https://ghe.internal.io/api/v3',
        customGithubApiBaseUrls: ['https://ghe.internal.io/api/v3'],
      );
      expect(AppSettings.fromJson(custom.toJson()), custom);
      // No token field exists in the JSON, by construction.
      expect(jsonEncode(custom.toJson()).contains('token'), isFalse);
    });
  });

  group('GitHub 서버 section', () {
    ({
      List<List<String>> security,
      List<Uri> requests,
      List<AppSettings> changed,
      Widget widget,
    })
    build({
      AppSettings settings = const AppSettings(),
      String? keychainToken,
      String userLogin = 'sw.chae',
      int userStatus = 200,
      Future<String> Function(String apiBaseUrl)? oauthLogin,
    }) {
      final security = <List<String>>[];
      final requests = <Uri>[];
      final changed = <AppSettings>[];
      final store = GithubTokenStore(
        environment: const {},
        runner: (executable, arguments, {workingDirectory, environment}) async {
          security.add(arguments);
          if (arguments.first == 'find-generic-password') {
            return keychainToken == null
                ? ProcessResult(1, 44, '', 'not found')
                : ProcessResult(1, 0, '$keychainToken\n', '');
          }
          return ProcessResult(1, 0, '', '');
        },
      );
      final widget = MaterialApp(
        home: SettingsScreen(
          settings: settings,
          onChanged: changed.add,
          tokenStore: store,
          githubSend: (uri, {required method, required headers, body}) async {
            requests.add(uri);
            return (status: userStatus, body: jsonEncode({'login': userLogin}));
          },
          oauthLogin: oauthLogin,
        ),
      );
      return (
        security: security,
        requests: requests,
        changed: changed,
        widget: widget,
      );
    }

    testWidgets('lists built-in servers with aliases and login state', (
      tester,
    ) async {
      final fixture = build(keychainToken: null);
      await tester.pumpWidget(fixture.widget);
      await tester.pumpAndSettle();

      expect(find.text('GitHub 서버'), findsOneWidget);
      expect(find.text('네이버'), findsOneWidget);
      expect(find.text('네이버 랩스'), findsOneWidget);
      expect(find.text('Github'), findsOneWidget);
      // No tokens anywhere: every row says not logged in.
      expect(find.text('로그인 안 함'), findsNWidgets(3));
    });

    testWidgets('a saved token marks the row and 연결 확인 names the login', (
      tester,
    ) async {
      final fixture = build(keychainToken: 'kc-token');
      await tester.pumpWidget(fixture.widget);
      await tester.pumpAndSettle();

      expect(find.text('토큰 저장됨'), findsWidgets);

      await tester.tap(find.byKey(const Key('github-verify')));
      await tester.pumpAndSettle();

      expect(fixture.requests.single.path, endsWith('/user'));
      expect(find.textContaining('sw.chae'), findsWidgets);
    });

    testWidgets('saving a token writes the Keychain, never settings.json', (
      tester,
    ) async {
      final fixture = build(keychainToken: null);
      await tester.pumpWidget(fixture.widget);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('github-token-field')),
        'ghp_new',
      );
      await tester.tap(find.byKey(const Key('github-token-save')));
      await tester.pumpAndSettle();

      final save = fixture.security.firstWhere(
        (arguments) => arguments.first == 'add-generic-password',
      );
      expect(save, contains('ghp_new'));
      // Settings may change (selection etc.) but no token rides along.
      for (final settings in fixture.changed) {
        expect(jsonEncode(settings.toJson()).contains('ghp_new'), isFalse);
      }
    });

    testWidgets('browser login shows only for registered servers and saves '
        'the token it wins', (tester) async {
      final logins = <String>[];
      final fixture = build(
        keychainToken: null,
        oauthLogin: (apiBaseUrl) async {
          logins.add(apiBaseUrl);
          return 'oauth-token-9';
        },
      );
      await tester.pumpWidget(fixture.widget);
      await tester.pumpAndSettle();

      // 네이버 (registered) is selected by default → button present.
      await tester.tap(find.byKey(const Key('github-browser-login')));
      await tester.pumpAndSettle();

      expect(logins, [defaultGithubApiBaseUrls.first]);
      final save = fixture.security.firstWhere(
        (arguments) => arguments.first == 'add-generic-password',
      );
      expect(save, contains('oauth-token-9'));
    });

    testWidgets('a custom server offers no browser login, only the token '
        'field', (tester) async {
      final fixture = build(
        settings: const AppSettings(
          githubApiBaseUrl: 'https://ghe.internal.io/api/v3',
          customGithubApiBaseUrls: ['https://ghe.internal.io/api/v3'],
        ),
        keychainToken: null,
      );
      await tester.pumpWidget(fixture.widget);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('github-browser-login')), findsNothing);
      expect(find.byKey(const Key('github-token-field')), findsOneWidget);
      expect(find.textContaining('브라우저 로그인이 등록돼 있지 않습니다'), findsOneWidget);
    });

    testWidgets('selecting another server persists the choice', (tester) async {
      final fixture = build(keychainToken: null);
      await tester.pumpWidget(fixture.widget);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('github-server-select-2')));
      await tester.pumpAndSettle();

      expect(
        fixture.changed.last.githubApiBaseUrl,
        defaultGithubApiBaseUrls[2],
      );
    });

    testWidgets('logout deletes the Keychain entry for the selected server', (
      tester,
    ) async {
      final fixture = build(keychainToken: 'kc-token');
      await tester.pumpWidget(fixture.widget);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('github-logout')));
      await tester.pumpAndSettle();

      expect(
        fixture.security.any(
          (arguments) =>
              arguments.first == 'delete-generic-password' &&
              arguments.contains(
                GithubTokenStore.serviceName(defaultGithubApiBaseUrls.first),
              ),
        ),
        isTrue,
      );
    });

    testWidgets('the scope hint names repo and read:org', (tester) async {
      final fixture = build(keychainToken: null);
      await tester.pumpWidget(fixture.widget);
      await tester.pumpAndSettle();

      expect(find.textContaining('repo'), findsWidgets);
      expect(find.textContaining('read:org'), findsWidgets);
    });
  });
}
