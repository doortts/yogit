import 'dart:io';

import 'git.dart';

/// One token per GitHub server, kept in the macOS Keychain through
/// `/usr/bin/security` so no plugin and no gh CLI is involved.
///
/// Reads fall back to `GH_TOKEN` then `GITHUB_TOKEN`, which is what a terminal
/// already exports on a machine that used gh, so the app works before anyone
/// logs in through it.
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
    for (final name in const ['GH_TOKEN', 'GITHUB_TOKEN']) {
      final value = _environment[name]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// `-U` updates the existing item, so saving twice is not a duplicate error.
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
