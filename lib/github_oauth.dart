import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'git.dart';
// `show` keeps github_api's own HttpResponse record out of the way: this file
// serves dart:io's HttpResponse to the browser.
import 'github_api.dart' show HttpSend, sendOverHttps;

/// One registered OAuth App, per GitHub server.
class GithubOAuthCredentials {
  const GithubOAuthCredentials({
    required this.clientId,
    required this.clientSecret,
  });

  final String clientId;
  final String clientSecret;
}

/// The OAuth Apps registered for the built-in servers, mirrored from yonalist
/// (src/githubAuthConfig.ts).
///
/// The client secret sits in the source because a desktop app is a public
/// client: it cannot keep one, so GitHub's loopback flow does not treat it as
/// a secret either. Every native OAuth client ships this way, and yonalist
/// carries the same three pairs.
const _credentialsByBaseUrl = <String, GithubOAuthCredentials>{
  'https://oss.navercorp.com/api/v3': GithubOAuthCredentials(
    clientId: 'd7165a7a207606b3a1c7',
    clientSecret: '5129e0384f21e8be2f1030caf6298d5c62fd1cfa',
  ),
  'https://es.naverlabs.com/api/v3': GithubOAuthCredentials(
    clientId: 'ab75d9083489cf8666bf',
    clientSecret: 'e1441e9e88d994a259138c7e494872f9c1bfd590',
  ),
  'https://api.github.com': GithubOAuthCredentials(
    clientId: 'Ov23liYSh18IFNEqCz4v',
    clientSecret: '77acb5fd6a20636a5e2934180dfe89dd779541ed',
  ),
};

/// The OAuth App for [apiBaseUrl], or null when the server has none — a
/// self-hosted enterprise instance nobody registered an app on. Those servers
/// have to log in with a personal access token instead.
GithubOAuthCredentials? githubOAuthCredentialsFor(String apiBaseUrl) =>
    _credentialsByBaseUrl[_withoutTrailingSlash(apiBaseUrl)];

/// `repo` reaches private repositories, `read:org` lets the app resolve team
/// reviewers on a pull request.
const githubOAuthScopes = ['repo', 'read:org'];

/// The servers offered out of the box; the first entry is the default.
const defaultGithubApiBaseUrls = [
  'https://oss.navercorp.com/api/v3',
  'https://es.naverlabs.com/api/v3',
  'https://api.github.com',
];

/// What the UI calls each built-in server, since the API base URL is not a
/// name anyone reads.
const defaultGithubApiBaseAliases = {
  'https://oss.navercorp.com/api/v3': '네이버',
  'https://es.naverlabs.com/api/v3': '네이버 랩스',
  'https://api.github.com': 'Github',
};

/// The web host behind an API base URL — where the browser signs in, since
/// `/login/oauth/…` lives on the site and not on the API endpoint.
String webBaseUrlOf(String apiBaseUrl) {
  final uri = Uri.parse(_withoutTrailingSlash(apiBaseUrl));
  return uri.host == 'api.github.com'
      ? '${uri.scheme}://github.com'
      : uri.origin;
}

String _withoutTrailingSlash(String url) {
  var trimmed = url.trim();
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

/// How long the loopback server waits for the browser: long enough for the
/// user to type a password and clear a 2FA prompt.
const _callbackTimeout = Duration(minutes: 5);

/// Browser login through a loopback redirect, mirrored from yonalist
/// (src/services/oauth.ts).
///
/// The app owns no public redirect URL, so it becomes the redirect target
/// itself: bind an ephemeral localhost port, send the browser to GitHub, and
/// take the authorization code off the one request that comes back.
class GithubOAuthLogin {
  GithubOAuthLogin({
    required this.apiBaseUrl,
    HttpSend? send,
    Future<void> Function(Uri)? openBrowser,
    String Function()? stateFactory,
  }) : _send = send ?? sendOverHttps,
       _openBrowser = openBrowser ?? _openInDefaultBrowser,
       _stateFactory = stateFactory ?? _randomState;

  final String apiBaseUrl;
  final HttpSend _send;
  final Future<void> Function(Uri) _openBrowser;
  final String Function() _stateFactory;

  /// Runs the whole round trip and returns the access token. The loopback
  /// server closes on every path out, including a timeout, so a second login
  /// attempt never trips over the first one's port.
  Future<String> login() async {
    final credentials = githubOAuthCredentialsFor(apiBaseUrl);
    if (credentials == null) {
      throw Exception(
        '이 서버는 브라우저 로그인이 등록돼 있지 않습니다. Personal Access Token으로 로그인하세요.',
      );
    }
    final webBase = webBaseUrlOf(apiBaseUrl);
    final state = _stateFactory();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final String code;
    final String redirectUri;
    try {
      redirectUri = 'http://localhost:${server.port}/auth';
      await _openBrowser(
        Uri.parse('$webBase/login/oauth/authorize').replace(
          queryParameters: {
            'client_id': credentials.clientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'scope': githubOAuthScopes.join(' '),
            'state': state,
          },
        ),
      );
      code = await _awaitCode(server, state).timeout(
        _callbackTimeout,
        onTimeout: () => throw Exception('브라우저 로그인을 기다리다 시간이 지났습니다'),
      );
    } finally {
      await server.close(force: true);
    }
    return _exchange(credentials, webBase, code, redirectUri);
  }

  /// Waits for the one redirect the browser makes, answers it with a page the
  /// user can read, and hands back the authorization code.
  ///
  /// The page goes out before the failure is thrown, so a user staring at the
  /// browser learns why the login stopped instead of seeing a dead tab.
  Future<String> _awaitCode(HttpServer server, String state) async {
    await for (final request in server) {
      if (request.uri.path != '/auth') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final parameters = request.uri.queryParameters;
      final failure = _failureIn(parameters, state);
      await _reply(request.response, failure);
      if (failure != null) throw Exception(failure);
      return parameters['code']!;
    }
    throw Exception('브라우저가 로그인을 끝내지 못했습니다');
  }

  /// Why this redirect cannot be trusted, or null when it can. A mismatched
  /// `state` means the redirect did not come from the request this app made,
  /// so the code never leaves the machine.
  static String? _failureIn(Map<String, String> parameters, String state) {
    final error = parameters['error'];
    if (error != null && error.isNotEmpty) {
      final description = parameters['error_description'];
      return description == null || description.isEmpty ? error : description;
    }
    if (parameters['state'] != state) {
      return 'state 값이 달라서 로그인을 중단했습니다. 다시 시도해 주세요.';
    }
    final code = parameters['code'];
    if (code == null || code.isEmpty) {
      return '브라우저가 인증 코드를 돌려주지 않았습니다';
    }
    return null;
  }

  /// `Connection: close` keeps the socket from lingering, so closing the
  /// server right after this does not have to wait out a keep-alive.
  static Future<void> _reply(HttpResponse response, String? failure) async {
    response.statusCode = failure == null
        ? HttpStatus.ok
        : HttpStatus.badRequest;
    response.persistentConnection = false;
    response.headers.contentType = ContentType.html;
    final message = failure == null
        ? '로그인 완료 — 창을 닫아도 됩니다.'
        : '로그인 실패: $failure';
    response.write(
      '<!doctype html><html lang="ko"><head><meta charset="utf-8">'
      '<title>yogit</title></head>'
      '<body style="font: 16px -apple-system, sans-serif; padding: 3rem">'
      '<p>${const HtmlEscape().convert(message)}</p></body></html>',
    );
    await response.close();
  }

  Future<String> _exchange(
    GithubOAuthCredentials credentials,
    String webBase,
    String code,
    String redirectUri,
  ) async {
    final response = await _send(
      Uri.parse('$webBase/login/oauth/access_token'),
      method: 'POST',
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'client_id': credentials.clientId,
        'client_secret': credentials.clientSecret,
        'code': code,
        'redirect_uri': redirectUri,
      }),
    );
    Object? document;
    try {
      document = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'GitHub가 토큰 대신 읽을 수 없는 응답을 돌려줬습니다 (HTTP ${response.status})',
      );
    }
    final fields = document is Map<String, dynamic> ? document : const {};
    final token = fields['access_token'];
    if (token is String && token.isNotEmpty) return token;
    throw Exception(
      _firstNonEmpty(fields['error_description'], fields['error']) ??
          '토큰을 받지 못했습니다 (HTTP ${response.status})',
    );
  }

  static String? _firstNonEmpty(Object? first, Object? second) {
    for (final value in [first, second]) {
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}

/// macOS hands the URL to whatever browser the user already uses.
Future<void> _openInDefaultBrowser(Uri url) async {
  final result = await runProcess('/usr/bin/open', [url.toString()]);
  if (result.exitCode != 0) {
    throw Exception('브라우저를 열지 못했습니다: ${result.stderr.toString().trim()}');
  }
}

/// 32 hex characters from the platform's secure source — enough that a forged
/// redirect cannot guess it.
String _randomState() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
