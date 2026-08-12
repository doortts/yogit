import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'git.dart';
import 'github_api.dart';

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
  AvatarService({required this.remote, required this.api});

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

  /// A branch line's weight. It lives here, beside the colour, because the
  /// avatar ring is that same line drawn around a disc — and the graph painter
  /// that draws the rails already reads its colours from this class, so the
  /// number stays in one place instead of once per drawer.
  /// `CommitGraphPainter.railWidth` forwards to it.
  static const railWidth = 2.0;

  final RemoteRepository remote;
  final GitHubApi api;

  /// The answer already given for a sha, so a row that rebuilds hands
  /// `FutureBuilder` the same object instead of a new one every frame.
  final _cache = <String, Future<CommitAvatars>>{};

  /// What GitHub said about a person, which is what an avatar actually belongs
  /// to. A repository whose whole history is one author asks once rather than
  /// once per commit, and the next row that person wrote is answered without
  /// waiting — or asking — at all.
  ///
  /// A key that is present with a null value is an answer too: GitHub has no
  /// account for that identity. It is only ever written from an answer that
  /// arrived, so a lookup that failed leaves nothing behind and can be asked
  /// again.
  // ponytail: unbounded identity map, add an LRU trim if a repository with
  // ten thousand authors ever turns up.
  final _known = <String, RemoteAvatar?>{};

  /// The lookups on their way, so two rows by the same person scrolling in
  /// together share one request rather than racing.
  final _identities = <String, Future<RemoteAvatar?>>{};
  final _permits = _PermitPool(4, maxQueued: 32);
  final _saturated = Future.value(const CommitAvatars());
  Future<String?>? _account;

  /// An identity's key: the email, lowercased, because that is what GitHub
  /// matches a commit to an account by. A commit written without one falls
  /// back to the name, which is all it left to be known by.
  static String _identityKey(GitIdentity identity) {
    final email = identity.email.trim();
    return (email.isEmpty ? identity.name.trim() : email).toLowerCase();
  }

  /// What is already known about these people, without waiting a frame. Null
  /// when neither of them has been heard about yet; otherwise as much as has
  /// arrived, so a face already known is drawn while the other is still coming.
  CommitAvatars? cachedFor({
    required GitIdentity author,
    GitIdentity? committer,
  }) {
    final authorKey = _identityKey(author);
    final committerKey = committer == null ? null : _identityKey(committer);
    if (!_known.containsKey(authorKey) &&
        (committerKey == null || !_known.containsKey(committerKey))) {
      return null;
    }
    return CommitAvatars(
      author: _known[authorKey],
      committer: committerKey == null ? null : _known[committerKey],
    );
  }

  /// The avatars for the commit at [sha], written by [author] and committed by
  /// [committer]. The sha is what GitHub is asked about; the identities are who
  /// the answer is remembered under, and the reason the same answer serves
  /// every other commit those people wrote.
  Future<CommitAvatars> resolve(
    String sha, {
    required GitIdentity author,
    GitIdentity? committer,
  }) {
    final cached = _cache.remove(sha);
    if (cached != null) {
      _cache[sha] = cached;
      return cached;
    }
    final keys = {
      _identityKey(author),
      if (committer != null) _identityKey(committer),
    };
    // Everyone on this row is known, or is already being asked about: the row
    // is answered from what the app has, and the queue never hears about it.
    if (keys.every(
      (key) => _known.containsKey(key) || _identities.containsKey(key),
    )) {
      return _remember(sha, _fromIdentities(author, committer));
    }
    final pending = _permits.tryRun(() => _load(sha, author, committer));
    if (pending == null) return _saturated;
    for (final key in keys) {
      // A lookup that threw is nobody's answer: the person goes back to being
      // unknown so the next commit of theirs asks again. The error itself is
      // the row's to show, and it is already on the future the row holds.
      _identities[key] = pending.then<RemoteAvatar?>(
        (_) => _known[key],
        onError: (Object _, StackTrace _) {
          _identities.remove(key);
          return null;
        },
      );
    }
    return _remember(sha, pending);
  }

  Future<CommitAvatars> _remember(String sha, Future<CommitAvatars> answer) {
    _cache[sha] = answer;
    if (_cache.length > 256) _cache.remove(_cache.keys.first);
    return answer;
  }

  Future<CommitAvatars> _fromIdentities(
    GitIdentity author,
    GitIdentity? committer,
  ) async => CommitAvatars(
    author: await _identityAvatar(author),
    committer: committer == null ? null : await _identityAvatar(committer),
  );

  Future<RemoteAvatar?> _identityAvatar(GitIdentity identity) {
    final key = _identityKey(identity);
    return _identities[key] ?? Future.value(_known[key]);
  }

  @visibleForTesting
  int get debugActiveRequestCount => _permits.active;

  @visibleForTesting
  int get debugQueuedRequestCount => _permits.queued;

  @visibleForTesting
  int get debugCachedRequestCount => _cache.length;

  Future<String?> accountLogin() => _account ??= _loadAccount();

  Future<String?> resolveMergedBranchName(String tipSha) async {
    final json = await _getJsonOrNull(
      'repos/${remote.owner}/${remote.repository}/commits/$tipSha/pulls',
    );
    if (json is! List) return null;
    final candidates = <({String ref, String sha, DateTime mergedAt})>[];
    for (final entry in json) {
      if (entry is! Map<String, dynamic>) continue;
      final head = entry['head'];
      final mergedAt = DateTime.tryParse('${entry['merged_at'] ?? ''}');
      if (head is! Map<String, dynamic> || mergedAt == null) continue;
      final sha = head['sha'];
      final ref = head['ref'];
      if (sha is! String || sha.isEmpty || ref is! String || ref.isEmpty) {
        continue;
      }
      candidates.add((ref: ref, sha: sha, mergedAt: mergedAt));
    }
    candidates.sort((left, right) {
      final leftExact = left.sha == tipSha;
      final rightExact = right.sha == tipSha;
      if (leftExact != rightExact) return leftExact ? -1 : 1;
      return right.mergedAt.compareTo(left.mergedAt);
    });
    return candidates.firstOrNull?.ref;
  }

  Future<String?> _loadAccount() async {
    final json = await _getJsonOrNull('user');
    return json is Map<String, dynamic> && json['login'] is String
        ? json['login'] as String
        : null;
  }

  /// Asks about one commit and files the answer under the people it names. A
  /// lookup that failed is not an answer: nothing is remembered, so the next
  /// commit by the same person asks again rather than wearing initials for the
  /// rest of the session over one dropped request.
  Future<CommitAvatars> _load(
    String sha,
    GitIdentity author,
    GitIdentity? committer,
  ) async {
    final json = await _getJsonOrNull(
      'repos/${remote.owner}/${remote.repository}/commits/$sha',
    );
    if (json is! Map<String, dynamic>) {
      _forget(author, committer);
      return const CommitAvatars();
    }
    final avatars = CommitAvatars(
      author: _headed(_parseAvatar(json['author'])),
      committer: _headed(_parseAvatar(json['committer'])),
    );
    _known[_identityKey(author)] = avatars.author;
    // Blame knows who wrote a line but not who committed it. Without an
    // identity to file it under, the committer's account is dropped rather
    // than remembered as somebody.
    if (committer != null) {
      _known[_identityKey(committer)] = avatars.committer;
    }
    return CommitAvatars(
      author: avatars.author,
      committer: committer == null ? null : avatars.committer,
    );
  }

  void _forget(GitIdentity author, GitIdentity? committer) {
    _identities.remove(_identityKey(author));
    if (committer != null) _identities.remove(_identityKey(committer));
  }

  /// An enterprise server wants the token before it hands over a face. The
  /// header rides on the avatar itself, so it goes wherever that avatar is
  /// reused — including onto a row whose own commit was never fetched.
  RemoteAvatar? _headed(RemoteAvatar? avatar) {
    if (avatar == null || remote.host == 'github.com' || api.token.isEmpty) {
      return avatar;
    }
    return _withSafeHeaders(avatar, {'Authorization': 'Bearer ${api.token}'});
  }

  /// A failed avatar lookup stays quiet — the row keeps its initials — so every
  /// GitHub failure comes back as a missing answer instead of an error.
  Future<Object?> _getJsonOrNull(String path) async {
    try {
      return await api.getJson(path);
    } on GitHubApiException {
      return null;
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

  static String initials(GitIdentity identity) {
    final parts = identity.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return [
      parts.first[0],
      if (parts.length > 1) parts.last[0],
    ].join().toUpperCase();
  }

  /// Branch 0 is the selected base branch.
  static const defaultBaseBranchColor = Color(0xFF5CB270);
  static Color baseBranchColor = defaultBaseBranchColor;

  /// Branch id → color for the repository on screen, assigned once per layout.
  /// Empty until the timeline assigns them, and [branchColor] falls back to the
  /// editable palette for anything the map does not carry.
  static Map<int, Color> branchAssignments = const {};

  /// A branch line's color. Every rail, curve, chip and dot on one line shares
  /// it, so the graph reads by branch rather than by person.
  static Color branchColor(int branch) {
    final assigned = branchAssignments[branch];
    if (assigned != null) return assigned;
    if (branch == 0) return baseBranchColor;
    final colors = palette.isEmpty ? defaultColors : palette;
    return colors[(branch.abs() - 1) % colors.length];
  }

  /// Person color, for avatars only: the graph is colored by branch.
  static Color color(GitIdentity identity) {
    var hash = 0;
    for (final codeUnit in identity.email.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return branchColor(hash);
  }

  static const _lightInk = Color(0xFFFFFFFF);
  static const _darkInk = Color(0xFF15171E);

  /// Ink that stays readable on a filled [background] disc: whichever of the
  /// two actually contrasts more. A luminance threshold would be the same
  /// answer only against pure black, and the dark ink is not pure — near the
  /// crossover, a mid-bright fill like the dimmed orange reads better in white
  /// than the threshold would have guessed.
  static Color onColor(Color background) =>
      _contrast(_lightInk, background) >= _contrast(_darkInk, background)
      ? _lightInk
      : _darkInk;

  /// WCAG relative contrast, the lighter of the pair over the darker.
  static double _contrast(Color ink, Color background) {
    final a = ink.computeLuminance() + 0.05;
    final b = background.computeLuminance() + 0.05;
    return a > b ? a / b : b / a;
  }
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
    this.discColor,
    this.fontFamily,
    this.fontScale = 1,
    super.key,
  });

  final GitIdentity identity;
  final RemoteAvatar? remoteAvatar;
  final double size;

  /// The face and scale the initials take when no photo covers them. The
  /// timeline hands over its own font so the disc matches the row it sits in;
  /// everywhere else the disc keeps its 0.42-of-the-diameter default.
  final String? fontFamily;
  final double fontScale;

  /// The branch line this avatar sits on, drawn as a ring around a disc of the
  /// same color. Null off the graph — the settings preview, the blame gutter —
  /// where there is no branch to name and the disc goes unringed.
  final Color? discColor;

  /// How far the branch color is dimmed inside the ring. The initials sit on
  /// this fill in the undimmed branch color, so the two share a hue and the
  /// alpha barely moves their contrast — over the row background (`#1C1C1E`) and
  /// the selected row (`#234D72`) the worst palette color reads 1.87 at 0.18 and
  /// 1.70 at 0.40. What the alpha does decide is whether the disc reads as
  /// filled, which is why it is the mockup's 0.22 and not lower.
  /// How far under its line a disc sits. Small on purpose: darker than the
  /// rail so the two read apart where the line meets the disc, and nowhere
  /// near black, which would cost the disc its branch.
  static const fillLightnessScale = 0.72;

  /// The disc's interior for a commit on [branch]: the same hue and
  /// saturation, a little darker, and opaque — a translucent fill would let
  /// the lane's rail run through the face.
  static Color fillFor(Color branch) {
    final line = HSLColor.fromColor(branch);
    return line.withLightness(line.lightness * fillLightnessScale).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final branch = discColor;
    // A row's disc is its branch line: a ring at the rail's own weight and the
    // same colour a little darker inside it. Off the graph — the settings
    // preview, the blame gutter — there is no branch to name, so the disc
    // keeps the identity fill. Either way the ink is whichever of white or
    // black reads better on what it sits on.
    final ring = branch == null ? 0.0 : AvatarService.railWidth;
    final fill = branch == null
        ? AvatarService.color(identity)
        : fillFor(branch);
    final ink = AvatarService.onColor(fill);
    final inner = size - ring * 2;
    final avatar = _safeAvatar(remoteAvatar);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: branch == null ? null : Border.all(color: branch, width: ring),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatar == null
          ? _initials(ink, inner)
          // The border insets the child, and clipping the photo to its own
          // circle keeps its corners off the ring: the branch stays visible
          // around a face that used to hide it completely.
          : ClipOval(
              child: Image.network(
                avatar.url,
                headers: avatar.headers.isEmpty ? null : avatar.headers,
                width: inner,
                height: inner,
                fit: BoxFit.cover,
                // A photo that never arrives leaves the initials, ring and all:
                // a 404 avatar must not cost the row who wrote the commit.
                errorBuilder: (_, _, _) => _initials(ink, inner),
              ),
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

  Widget _initials(Color ink, double inner) => Text(
    AvatarService.initials(identity),
    maxLines: 1,
    style: TextStyle(
      color: ink,
      fontFamily: fontFamily,
      // Two glyphs still have to sit inside the circle, so the scale stops at
      // half the room the ring leaves however large the timeline's font grows.
      fontSize: math.min(inner / 2, size * 0.42 * fontScale),
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
    this.stacked = true,
    this.committerOnly = false,
    this.discColor,
    this.fontFamily,
    this.fontScale = 1,
    super.key,
  });

  final GitCommit commit;
  final AvatarService? avatarService;
  final bool showRemoteAvatars;
  final double size;

  /// Whether a separate committer may sit behind the author. A graph node in a
  /// squeezed lane says no, so the pair never reaches the next lane's rail.
  final bool stacked;
  final bool committerOnly;

  /// Passed straight through to both discs: a row's avatars wear its branch.
  final Color? discColor;

  /// The initials' face and size, passed through to both discs.
  final String? fontFamily;
  final double fontScale;

  bool get _hasSeparateCommitter =>
      !committerOnly &&
      stacked &&
      (commit.author.name != commit.committer.name ||
          commit.author.email != commit.committer.email);

  @override
  Widget build(BuildContext context) {
    final service = showRemoteAvatars ? avatarService : null;
    if (service == null) return _stack(null);
    return FutureBuilder<CommitAvatars>(
      future: service.resolve(
        commit.sha,
        author: commit.author,
        committer: commit.committer,
      ),
      initialData: service.cachedFor(
        author: commit.author,
        committer: commit.committer,
      ),
      builder: (context, snapshot) => _stack(snapshot.data),
    );
  }

  Widget _stack(CommitAvatars? avatars) {
    if (committerOnly) {
      return IdentityAvatar(
        key: ValueKey('committer-avatar-${commit.sha}'),
        identity: commit.committer,
        remoteAvatar: avatars?.committer,
        size: size,
        discColor: discColor,
        fontFamily: fontFamily,
        fontScale: fontScale,
      );
    }
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
                discColor: discColor,
                fontFamily: fontFamily,
                fontScale: fontScale,
              ),
            ),
          Positioned(
            left: 0,
            child: IdentityAvatar(
              key: ValueKey('author-avatar-${commit.sha}'),
              identity: commit.author,
              remoteAvatar: avatars?.author,
              size: size,
              discColor: discColor,
              fontFamily: fontFamily,
              fontScale: fontScale,
            ),
          ),
        ],
      ),
    );
  }
}
