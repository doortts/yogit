import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'git.dart';

bool _isGravatarHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'gravatar.com' || normalized.endsWith('.gravatar.com');
}

class RemoteRepository {
  const RemoteRepository({
    required this.host,
    required this.owner,
    required this.repository,
  });

  final String host;
  final String owner;
  final String repository;

  static RemoteRepository? tryParse(String value) {
    String? host;
    String? path;
    final uri = Uri.tryParse(value);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'ssh') &&
        uri.host.isNotEmpty) {
      host = uri.host;
      path = uri.path;
    } else {
      final match = RegExp(r'^[^@/]+@([^:]+):(.+)$').firstMatch(value);
      if (match != null) {
        host = match.group(1);
        path = match.group(2);
      }
    }
    if (host == null || path == null) return null;
    final normalizedHost = host.toLowerCase();
    if (_isGravatarHost(normalizedHost)) return null;
    final parts = path
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length != 2) return null;
    final repository = parts.last.endsWith('.git')
        ? parts.last.substring(0, parts.last.length - 4)
        : parts.last;
    if (parts.first.isEmpty || repository.isEmpty) return null;
    return RemoteRepository(
      host: normalizedHost,
      owner: parts.first,
      repository: repository,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteRepository &&
      host == other.host &&
      owner == other.owner &&
      repository == other.repository;

  @override
  int get hashCode => Object.hash(host, owner, repository);
}

class RemoteAvatar {
  const RemoteAvatar({
    required this.login,
    required this.url,
    this.headers = const {},
  });

  final String login;
  final String url;
  final Map<String, String> headers;
}

class CommitAvatars {
  const CommitAvatars({this.author, this.committer});

  final RemoteAvatar? author;
  final RemoteAvatar? committer;
}

class AvatarService {
  AvatarService({
    required this.remote,
    this.ghExecutable = 'gh',
    this.runner = runProcess,
  });

  /// Neon: pink, cyan, green, yellow, orange, purple, blue, red.
  static const defaultColors = [
    Color(0xFFFF2D95),
    Color(0xFF00E5FF),
    Color(0xFF39FF14),
    Color(0xFFFFF01F),
    Color(0xFFFF6E27),
    Color(0xFFB026FF),
    Color(0xFF04D9FF),
    Color(0xFFFF3131),
  ];

  /// The palette every rail, ring, chip and dot reads. Settings replace it.
  static List<Color> palette = defaultColors;

  final RemoteRepository remote;
  final String ghExecutable;
  final CommandRunner runner;
  final _cache = <String, Future<CommitAvatars>>{};
  final _permits = _PermitPool(4, maxQueued: 32);
  final _saturated = Future.value(const CommitAvatars());
  Future<String?>? _account;
  Future<String?>? _token;

  Future<CommitAvatars> resolve(String sha) {
    final cached = _cache.remove(sha);
    if (cached != null) {
      _cache[sha] = cached;
      return cached;
    }
    final pending = _permits.tryRun(() => _load(sha));
    if (pending == null) return _saturated;
    _cache[sha] = pending;
    if (_cache.length > 256) _cache.remove(_cache.keys.first);
    return pending;
  }

  @visibleForTesting
  int get debugActiveRequestCount => _permits.active;

  @visibleForTesting
  int get debugQueuedRequestCount => _permits.queued;

  @visibleForTesting
  int get debugCachedRequestCount => _cache.length;

  Future<String?> accountLogin() => _account ??= _loadAccount();

  Future<String?> _loadAccount() async {
    final result = await runner(ghExecutable, [
      'api',
      '--hostname',
      remote.host,
      'user',
    ]);
    if (result.exitCode != 0) return null;
    try {
      final json = jsonDecode(result.stdout.toString());
      return json is Map<String, dynamic> && json['login'] is String
          ? json['login'] as String
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<CommitAvatars> _load(String sha) async {
    final result = await runner(ghExecutable, [
      'api',
      '--hostname',
      remote.host,
      'repos/${remote.owner}/${remote.repository}/commits/$sha',
    ]);
    if (result.exitCode != 0) return const CommitAvatars();
    try {
      final json = jsonDecode(result.stdout.toString());
      if (json is! Map<String, dynamic>) return const CommitAvatars();
      final author = _parseAvatar(json['author']);
      final committer = _parseAvatar(json['committer']);
      if (remote.host == 'github.com' ||
          !_needsRemoteHeader(author, committer)) {
        return CommitAvatars(author: author, committer: committer);
      }
      final token = await (_token ??= _loadToken());
      if (token == null) {
        return CommitAvatars(author: author, committer: committer);
      }
      final headers = {'Authorization': 'Bearer $token'};
      return CommitAvatars(
        author: _withSafeHeaders(author, headers),
        committer: _withSafeHeaders(committer, headers),
      );
    } on FormatException {
      return const CommitAvatars();
    }
  }

  RemoteAvatar? _parseAvatar(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final login = value['login'];
    final url = value['avatar_url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (login is! String ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        _isGravatarHost(uri.host)) {
      return null;
    }
    return RemoteAvatar(login: login, url: uri.toString());
  }

  bool _needsRemoteHeader(RemoteAvatar? author, RemoteAvatar? committer) =>
      [author, committer].whereType<RemoteAvatar>().any(
        (avatar) => Uri.parse(avatar.url).host.toLowerCase() == remote.host,
      );

  RemoteAvatar? _withSafeHeaders(
    RemoteAvatar? avatar,
    Map<String, String> headers,
  ) {
    if (avatar == null ||
        Uri.parse(avatar.url).host.toLowerCase() != remote.host) {
      return avatar;
    }
    return RemoteAvatar(login: avatar.login, url: avatar.url, headers: headers);
  }

  Future<String?> _loadToken() async {
    final result = await runner(ghExecutable, [
      'auth',
      'token',
      '--hostname',
      remote.host,
    ]);
    final token = result.stdout.toString().trim();
    return result.exitCode == 0 && token.isNotEmpty ? token : null;
  }

  static String initials(GitIdentity identity) {
    final parts = identity.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return [
      parts.first[0],
      if (parts.length > 1) parts.last[0],
    ].join().toUpperCase();
  }

  /// A branch line's color. Every rail, curve, chip and dot on one line shares
  /// it, so the graph reads by branch rather than by person.
  static Color branchColor(int branch) {
    final colors = palette.isEmpty ? defaultColors : palette;
    return colors[branch.abs() % colors.length];
  }

  /// Person color, for avatars only: the graph is colored by branch.
  static Color color(GitIdentity identity) {
    var hash = 0;
    for (final codeUnit in identity.email.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return branchColor(hash);
  }

  /// Ink that stays readable on a filled [background] disc. The crossover sits
  /// where white and near-black swap contrast, not at mid grey, so the brighter
  /// palette colors get dark letters.
  static Color onColor(Color background) =>
      background.computeLuminance() > 0.179
      ? const Color(0xFF15171E)
      : const Color(0xFFFFFFFF);
}

class _PermitPool {
  _PermitPool(this.limit, {required this.maxQueued});

  final int limit;
  final int maxQueued;
  var _active = 0;
  final _waiting = Queue<Future<void> Function()>();

  int get active => _active;
  int get queued => _waiting.length;

  Future<T>? tryRun<T>(Future<T> Function() action) {
    if (_active < limit) return _start(action);
    if (_waiting.length >= maxQueued) return null;
    final result = Completer<T>();
    _waiting.add(() async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<T> _start<T>(Future<T> Function() action) async {
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      _startNext();
    }
  }

  void _startNext() {
    if (_active >= limit || _waiting.isEmpty) return;
    final action = _waiting.removeFirst();
    _active++;
    unawaited(
      action().whenComplete(() {
        _active--;
        _startNext();
      }),
    );
  }
}

class IdentityAvatar extends StatelessWidget {
  const IdentityAvatar({
    required this.identity,
    this.remoteAvatar,
    this.size = 22,
    super.key,
  });

  final GitIdentity identity;
  final RemoteAvatar? remoteAvatar;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = AvatarService.color(identity);
    final avatar = _safeAvatar(remoteAvatar);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // A filled identity-colored disc, no outline: a photo covers it,
        // initials sit on it.
        color: color,
      ),
      clipBehavior: Clip.antiAlias,
      child: avatar == null
          ? _initials(color)
          : Image.network(
              avatar.url,
              headers: avatar.headers.isEmpty ? null : avatar.headers,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _initials(color),
            ),
    );
  }

  RemoteAvatar? _safeAvatar(RemoteAvatar? avatar) {
    if (avatar == null) return null;
    final uri = Uri.tryParse(avatar.url);
    return uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            _isGravatarHost(uri.host)
        ? null
        : avatar;
  }

  Widget _initials(Color background) => Text(
    AvatarService.initials(identity),
    maxLines: 1,
    style: TextStyle(
      color: AvatarService.onColor(background),
      fontSize: size * 0.42,
      fontWeight: FontWeight.w700,
      height: 1,
    ),
  );
}

class CommitAvatarStack extends StatelessWidget {
  const CommitAvatarStack({
    required this.commit,
    this.avatarService,
    this.showRemoteAvatars = true,
    this.size = 22,
    super.key,
  });

  final GitCommit commit;
  final AvatarService? avatarService;
  final bool showRemoteAvatars;
  final double size;

  bool get _hasSeparateCommitter =>
      commit.author.name != commit.committer.name ||
      commit.author.email != commit.committer.email;

  @override
  Widget build(BuildContext context) {
    final service = showRemoteAvatars ? avatarService : null;
    if (service == null) return _stack(null);
    return FutureBuilder<CommitAvatars>(
      future: service.resolve(commit.sha),
      builder: (context, snapshot) => _stack(snapshot.data),
    );
  }

  Widget _stack(CommitAvatars? avatars) {
    final offset = _hasSeparateCommitter ? size * 0.45 : 0.0;
    return SizedBox(
      width: size + offset,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_hasSeparateCommitter)
            Positioned(
              left: offset,
              child: IdentityAvatar(
                key: ValueKey('committer-avatar-${commit.sha}'),
                identity: commit.committer,
                remoteAvatar: avatars?.committer,
                size: size,
              ),
            ),
          Positioned(
            left: 0,
            child: IdentityAvatar(
              key: ValueKey('author-avatar-${commit.sha}'),
              identity: commit.author,
              remoteAvatar: avatars?.author,
              size: size,
            ),
          ),
        ],
      ),
    );
  }
}
