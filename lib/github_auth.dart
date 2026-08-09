import 'dart:io';

import 'git.dart';

/// One token per GitHub server, kept in the macOS Keychain through
/// `/usr/bin/security`: no plugin, and no other tool to install.
///
/// Reads fall back to the `GH_TOKEN` family a developer machine usually
/// exports already, so the app works before anyone logs in through it — and it
/// follows the same split by host, since a github.com token on an enterprise
/// server buys nothing but a 401.
class GithubTokenStore {
  GithubTokenStore({this.runner = runProcess, Map<String, String>? environment})
    : _environment = environment ?? Platform.environment;

  final CommandRunner runner;
  final Map<String, String> _environment;

  static const _security = '/usr/bin/security';
  static const _account = 'yogit';

  /// The Keychain service holding [apiBaseUrl]'s token. Stable across a
  /// trailing slash, distinct per server, and readable in Keychain Access.
  static String serviceName(String apiBaseUrl) {
    var base = apiBaseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final host = base.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z\d+.-]*://'), '');
    return 'yogit-github-${host.replaceAll('/', '-')}';
  }

  Future<String?> read(String apiBaseUrl) async {
    final found = await runner(_security, [
      'find-generic-password',
      '-a',
      _account,
      '-s',
      serviceName(apiBaseUrl),
      '-w',
    ]);
    if (found.exitCode == 0) {
      final token = found.stdout.toString().trim();
      if (token.isNotEmpty) return token;
    }
    for (final name in _envTokenNames(apiBaseUrl)) {
      final value = _environment[name]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// The conventional split: the `GH_TOKEN` pair is github.com's, the enterprise pair
  /// belongs to every other host. Reading across that line would send a token
  /// the server has never heard of.
  static List<String> _envTokenNames(String apiBaseUrl) {
    final host = Uri.tryParse(apiBaseUrl)?.host.toLowerCase();
    return host == 'api.github.com' || host == 'github.com'
        ? const ['GH_TOKEN', 'GITHUB_TOKEN']
        : const ['GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN'];
  }

  /// `-U` updates the existing item, so saving twice is not a duplicate error.
  ///
  /// The token rides in argv, so it is visible in `ps` for the length of the
  /// call. Accepted: the alternative is `security`'s interactive prompt, which
  /// cannot be driven from a GUI app.
  Future<void> save(String apiBaseUrl, String token) async {
    final result = await runner(_security, [
      'add-generic-password',
      '-U',
      '-a',
      _account,
      '-s',
      serviceName(apiBaseUrl),
      '-w',
      token,
    ]);
    if (result.exitCode != 0) {
      final detail = result.stderr.toString().trim();
      throw Exception(
        '키체인에 토큰을 저장하지 못했습니다${detail.isEmpty ? '' : ': $detail'}',
      );
    }
  }

  /// Failures are ignored: an item that is already gone is the wanted result,
  /// and `security` reports that as an error like any other.
  Future<void> delete(String apiBaseUrl) async {
    await runner(_security, [
      'delete-generic-password',
      '-a',
      _account,
      '-s',
      serviceName(apiBaseUrl),
    ]);
  }
}
