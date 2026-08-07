import 'dart:convert';
import 'dart:io';

/// What one HTTP exchange gives back. Bodies stay text because every GitHub
/// failure carries a message the user should read, JSON or not.
typedef HttpResponse = ({int status, String body});

typedef HttpSend =
    Future<HttpResponse> Function(
      Uri uri, {
      required String method,
      required Map<String, String> headers,
      String? body,
    });

/// Every GitHub failure the app shows, with the HTTP status where one exists.
/// [message] is user-facing Korean, so it goes into a banner unchanged.
class GitHubApiException implements Exception {
  const GitHubApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => 'GitHubApiException: $message';
}

/// One GitHub server, reached over HTTPS instead of through the gh CLI.
///
/// [apiBaseUrl] is the full REST base — `https://api.github.com` for
/// github.com, `https://ghe.host/api/v3` for an enterprise server — and the
/// GraphQL endpoint derives from it rather than being stored separately.
class GitHubApi {
  GitHubApi({required String apiBaseUrl, required this.token, HttpSend? send})
    : _base = _withoutTrailingSlash(apiBaseUrl),
      _send = send ?? sendOverHttps;

  final String _base;
  final String token;
  final HttpSend _send;

  static const _apiVersion = '2022-11-28';

  /// REST GET, decoded. [path] may lead with a slash or not.
  Future<Object?> getJson(String path) async {
    final uri = Uri.parse('$_base/${_withoutLeadingSlash(path)}');
    return _decode(await _send(uri, method: 'GET', headers: _headers));
  }

  /// POSTs one GraphQL document and returns its `data` map.
  ///
  /// GitHub answers a rejected query with HTTP 200 and an `errors` array, so
  /// the status alone never says whether the query ran.
  Future<Map<String, dynamic>> graphql(
    String query,
    Map<String, Object?> variables,
  ) async {
    final response = await _send(
      _graphqlEndpoint,
      method: 'POST',
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'query': query, 'variables': variables}),
    );
    final json = _decode(response);
    if (json is! Map<String, dynamic>) {
      throw GitHubApiException(
        'GitHub GraphQL 응답을 읽을 수 없습니다',
        status: response.status,
      );
    }
    final errors = json['errors'];
    if (errors is List && errors.isNotEmpty) {
      throw GitHubApiException(_firstErrorMessage(errors));
    }
    final data = json['data'];
    return data is Map<String, dynamic> ? data : const {};
  }

  /// github.com hangs GraphQL off the API host; an enterprise server hangs it
  /// beside `v3` under the same `/api` prefix.
  Uri get _graphqlEndpoint {
    final segments = _base.split('/');
    if (segments.last == 'v3') {
      return Uri.parse(
        [...segments.take(segments.length - 1), 'graphql'].join('/'),
      );
    }
    return Uri.parse('$_base/graphql');
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': _apiVersion,
    'User-Agent': 'yogit',
  };

  Object? _decode(HttpResponse response) {
    if (response.status < 200 || response.status >= 300) {
      throw _failure(response);
    }
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw GitHubApiException(
        'GitHub가 JSON이 아닌 응답을 돌려줬습니다: ${_excerpt(response.body)}',
        status: response.status,
      );
    }
  }

  GitHubApiException _failure(HttpResponse response) =>
      switch (response.status) {
        401 => GitHubApiException(
          '토큰 인증에 실패했습니다. 토큰이 만료됐거나 이 서버에서 쓸 수 없습니다.',
          status: 401,
        ),
        404 => const GitHubApiException(
          '저장소를 찾을 수 없거나 접근 권한이 없습니다.',
          status: 404,
        ),
        final status => GitHubApiException(
          'GitHub 요청이 실패했습니다 (HTTP $status): ${_detail(response.body)}',
          status: status,
        ),
      };

  /// The server's own explanation: GitHub sends `{"message":…}`, a proxy in
  /// front of it sends whatever it likes.
  static String _detail(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic> && json['message'] is String) {
        return json['message'] as String;
      }
    } on FormatException {
      // Not JSON, so the raw body is the best explanation available.
    }
    return _excerpt(body);
  }

  static String _excerpt(String body) {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }

  static String _firstErrorMessage(List<Object?> errors) {
    final first = errors.first;
    final message = first is Map<String, dynamic> ? first['message'] : null;
    return message is String && message.isNotEmpty
        ? message
        : 'GitHub가 이 조회를 거절했습니다';
  }

  static String _withoutTrailingSlash(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String _withoutLeadingSlash(String path) {
    var trimmed = path.trim();
    while (trimmed.startsWith('/')) {
      trimmed = trimmed.substring(1);
    }
    return trimmed;
  }
}

const _requestTimeout = Duration(seconds: 20);

/// The default transport. Honours `HTTPS_PROXY`/`https_proxy` because an
/// enterprise server usually sits behind one, and `NO_PROXY`/`no_proxy`
/// alongside it because the same shells exempt the internal host that way.
///
/// Headers and body each get their own [_requestTimeout]: a proxy that sends
/// headers and then stalls the body would otherwise hang the request forever.
/// Transport failures come back as [GitHubApiException] so callers only ever
/// catch the one type.
Future<HttpResponse> sendOverHttps(
  Uri uri, {
  required String method,
  required Map<String, String> headers,
  String? body,
}) async {
  final proxy =
      Platform.environment['HTTPS_PROXY'] ??
      Platform.environment['https_proxy'];
  final noProxy =
      Platform.environment['NO_PROXY'] ?? Platform.environment['no_proxy'];
  final client = HttpClient()..connectionTimeout = _requestTimeout;
  if (proxy != null && proxy.trim().isNotEmpty) {
    final proxyEnvironment = {
      'https_proxy': proxy,
      if (noProxy != null && noProxy.trim().isNotEmpty) 'no_proxy': noProxy,
    };
    client.findProxy = (target) => HttpClient.findProxyFromEnvironment(
      target,
      environment: proxyEnvironment,
    );
  }
  try {
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close().timeout(_requestTimeout);
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_requestTimeout);
    return (status: response.statusCode, body: text);
  } on Exception catch (error) {
    throw GitHubApiException('GitHub($uri)에 연결할 수 없습니다: $error');
  } finally {
    client.close();
  }
}
