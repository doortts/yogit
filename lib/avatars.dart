import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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
    this.tone,
  });

  final String login;
  final String url;
  final Map<String, String> headers;

  /// The average colour of the photo itself, once somebody has decoded it. The
  /// graph reads it to keep a lane colour off an avatar it would melt into, and
  /// it is a cache rather than a fact: null means nobody has looked yet.
  final Color? tone;
}

class CommitAvatars {
  const CommitAvatars({this.author, this.committer});

  final RemoteAvatar? author;
  final RemoteAvatar? committer;
}

/// The faces already learned, kept between runs beside the settings file.
///
/// Finding one costs a round trip per person, and a commit that has never been
/// pushed cannot buy that answer at all — so a repository whose newest commits
/// are all local opens on initials and fills in seconds later, once the rows
/// deep enough to be on the server have been asked about. Reading the answer
/// back off disk is what lets the next open draw the faces on its first frame,
/// without asking anybody.
///
/// Only the accounts that were found are written, and only the login and the
/// URL of each: an enterprise server's token is put back on by the service
/// that reads this, so it never lands on disk. "This person has no account" is
/// an answer too, but one that stops being true the day they link the address,
/// and a session is long enough to hold it.
class AvatarStore {
  AvatarStore([File? file]) : file = file ?? File(_defaultPath());

  final File file;

  static String _defaultPath() => pathForHome(Platform.environment['HOME']);

  /// Beside `settings.json`, and homeless for the same reason it is: with no
  /// HOME there is nowhere safe to write, and a face is not worth handing the
  /// opened repository a file yogit reads on every launch.
  @visibleForTesting
  static String pathForHome(String? home) => home == null || home.isEmpty
      ? '${Directory.systemTemp.createTempSync('yogit_').path}/avatars.json'
      : '$home/Library/Application Support/yogit/avatars.json';

  /// What [host] has answered before, by identity. One address can belong to
  /// different people on two servers, so each host keeps its own answers.
  Future<Map<String, RemoteAvatar>> load(String host) async {
    final entries = (await _read())[host];
    if (entries is! Map<String, dynamic>) return {};
    return {
      for (final entry in entries.entries) entry.key: ?_avatarFor(entry.value),
    };
  }

  /// Writes [known] back under [host], leaving every other host's answers
  /// where they are: two yogit windows on two servers do not erase each other.
  Future<void> save(String host, Map<String, RemoteAvatar> known) async {
    final json = await _read();
    json[host] = {
      for (final entry in known.entries)
        entry.key: {
          'login': entry.value.login,
          'url': entry.value.url,
          'tone': ?_hexOf(entry.value.tone),
        },
    };
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json), flush: true);
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, dynamic> ? json : {};
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  static RemoteAvatar? _avatarFor(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final login = value['login'];
    final url = value['url'];
    final tone = value['tone'];
    return login is String && url is String
        ? RemoteAvatar(
            login: login,
            url: url,
            // A tone that will not parse is a tone nobody has, not a face
            // nobody has: the photo is still worth drawing.
            tone: tone is String ? _toneFrom(tone) : null,
          )
        : null;
  }

  /// `#RRGGBB`, so a person opening the file sees a colour rather than an int.
  static String? _hexOf(Color? tone) {
    if (tone == null) return null;
    final rgb = tone.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
  }

  /// The same string back to a colour. `settings.dart` has this regular
  /// expression too, and reusing that one was the first thing tried: it makes
  /// this file — a leaf that talks to git and GitHub and nothing else — import
  /// the settings module, which drags the settings UI and everything behind it
  /// in, and points an import back at a file that already imports this one. A
  /// cycle is a steep price for four lines, so the four lines live here.
  static Color? _toneFrom(String value) {
    final match = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(value.trim());
    return match == null
        ? null
        : Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
  }
}

class AvatarService {
  AvatarService({required this.remote, required this.api, this.store});

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

  /// Where the faces learned this run are kept for the next one. Null in a
  /// test, and wherever an answer is not worth outliving the window.
  final AvatarStore? store;

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
  ///
  /// [restore] fills it from what earlier runs learned, which is what makes an
  /// opened repository draw faces rather than initials while it waits.
  // ponytail: unbounded identity map, add an LRU trim if a repository with
  // ten thousand authors ever turns up — the same trim would bound the file
  // [store] writes, which holds one line per person for the same reason.
  final _known = <String, RemoteAvatar?>{};

  /// The lookups on their way, so two rows by the same person scrolling in
  /// together share one request rather than racing.
  final _identities = <String, Future<RemoteAvatar?>>{};

  /// Commits GitHub has never heard of. A sha that has not been pushed yet is
  /// no commit at all to the server, and asking a second time only earns the
  /// same 404: the row is answered from what its people are already known by
  /// instead, so the face still arrives once another row of theirs finds it.
  final _missing = <String>{};
  final _permits = _PermitPool(4, maxQueued: 32);
  final _saturated = Future.value(const CommitAvatars());
  Future<String?>? _account;

  /// One write at a time, so two answers landing together cannot interleave
  /// halfway through the file.
  Future<void> _writing = Future.value();

  Future<void>? _restoring;
  var _restored = false;

  /// Reads back what earlier runs learned about this server's people, once.
  /// Every answer waits on it, so a row asked before the disk has been read
  /// waits for the disk rather than paying the network for something already
  /// written down. What this run heard for itself wins: the file fills gaps.
  Future<void> restore() =>
      _restored ? Future.value() : (_restoring ??= _readStore());

  Future<void> _readStore() async {
    final store = this.store;
    if (store != null) {
      for (final entry in (await store.load(remote.host)).entries) {
        _known.putIfAbsent(entry.key, () => _headed(entry.value));
      }
    }
    _restored = true;
  }

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
    // Nobody is asked about until the file has been read: the answer is very
    // often already in it, and a request sent before that is one the app knew
    // the answer to.
    // The wait itself is not filed under the sha: the answer behind it is, by
    // the call on the other side, and a future that finds itself in the cache
    // would be waiting for its own result.
    if (!_restored && store != null) {
      return restore().then(
        (_) => resolve(sha, author: author, committer: committer),
      );
    }
    // A commit the server does not have is answered from its people, and the
    // answer is not kept: the next rebuild reads the map again, so a face that
    // landed meanwhile reaches a row whose own sha will never find one.
    if (_missing.contains(sha)) return _knownFor(author, committer);
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
      return _remember(sha, _shared(sha, author, committer, keys));
    }
    final pending = _ask(sha, author, committer, keys);
    if (pending == null) return _saturated;
    return _remember(sha, pending);
  }

  /// Asks about [sha] and files the answer under everyone it names. Null when
  /// the queue is full. While it is in flight every other row by these people
  /// waits on it rather than asking again.
  Future<CommitAvatars>? _ask(
    String sha,
    GitIdentity author,
    GitIdentity? committer,
    Set<String> keys,
  ) {
    final pending = _permits.tryRun(() {
      // A lookup that landed while this one sat in the queue has already
      // answered for these people, so the turn is spent on nothing.
      if (keys.every(_known.containsKey)) return _knownFor(author, committer);
      return _load(sha, author, committer);
    });
    if (pending == null) return null;
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
    return pending;
  }

  /// The answer a lookup already on its way is about to give. That lookup
  /// asked about somebody else's commit, and a commit that has not been pushed
  /// yet is one GitHub answers nothing about — nothing about the sha, and so
  /// nothing about the person who wrote it. A person still unknown when it
  /// lands is asked about again, with this row's own commit, rather than
  /// wearing initials for the rest of the session over a sha that never left
  /// the machine.
  Future<CommitAvatars> _shared(
    String sha,
    GitIdentity author,
    GitIdentity? committer,
    Set<String> keys,
  ) async {
    final answer = await _fromIdentities(author, committer);
    if (keys.every(_known.containsKey)) return answer;
    return await _ask(sha, author, committer, keys) ?? answer;
  }

  /// What the map holds for these two right now, without asking anybody.
  Future<CommitAvatars> _knownFor(GitIdentity author, GitIdentity? committer) =>
      Future.value(
        CommitAvatars(
          author: _known[_identityKey(author)],
          committer: committer == null ? null : _known[_identityKey(committer)],
        ),
      );

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

  @visibleForTesting
  Future<void> get debugWritten => _writing;

  /// The pixel arithmetic on its own, so a test can hand it an image it built
  /// rather than one it had to talk a network out of.
  @visibleForTesting
  static Future<Color?> debugToneOf(ui.Image image) => _averageColor(image);

  Future<String?> accountLogin() => _account ??= _loadAccount();

  /// The average colour of the face this repository commits under, which the
  /// graph keeps its lane colours away from. [sha] is a commit [identity]
  /// themselves wrote, and it is what the face is looked up by: a tone is only
  /// ever wanted while that person's photo is on the graph, which means a row
  /// of theirs is loaded, which means [resolve] is the path — the same cache,
  /// the same file on disk, the same memory of an address GitHub has no account
  /// for. A lookup filtered by the address instead was written first and taken
  /// back out: it bought nothing the drawn row does not already buy, and cost a
  /// request on every identity load, a request repeated for the rest of the
  /// session whenever the address matched nothing, and the user's own email
  /// address in a URL query string, which nothing else here puts there.
  ///
  /// Null where there is nothing to avoid — no identity, no account, no photo
  /// that would decode — and in that case the graph is assigned exactly as it
  /// always was.
  ///
  /// A tone read off disk comes back immediately, because the first graph is
  /// drawn long before an image arrives, and the live photo is decoded behind
  /// it: a GitHub avatar URL does not change when the picture behind it does,
  /// so the stored value is a fast first frame and the decode is the truth. A
  /// live tone that turns out different is written down for the next run.
  Future<Color?> toneFor(String sha, {required GitIdentity identity}) async {
    if (_identityKey(identity).isEmpty) return null;
    final avatar = (await resolve(sha, author: identity)).author;
    if (avatar == null) return null;
    final stored = avatar.tone;
    if (stored == null) return _learnTone(identity, avatar);
    unawaited(_learnTone(identity, avatar));
    return stored;
  }

  /// Decodes the photo, writes the tone down beside the face, and answers with
  /// it. Null wherever the photo does not arrive or does not decode: a tone is
  /// a nicety, and nothing about it is worth an error reaching a row.
  Future<Color?> _learnTone(GitIdentity identity, RemoteAvatar avatar) async {
    final tone = await _decodeTone(avatar);
    if (tone == null || tone == avatar.tone) return tone;
    _known[_identityKey(identity)] = RemoteAvatar(
      login: avatar.login,
      url: avatar.url,
      headers: avatar.headers,
      tone: tone,
    );
    _persist();
    return tone;
  }

  /// The photo's average colour. [NetworkImage] is what the rows draw with, so
  /// this reads the same Flutter image cache rather than fetching anything of
  /// its own — and the enterprise token rides along on the avatar's headers the
  /// same way it does there.
  Future<Color?> _decodeTone(RemoteAvatar avatar) {
    final tone = Completer<Color?>();
    final stream = NetworkImage(
      avatar.url,
      headers: avatar.headers.isEmpty ? null : avatar.headers,
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void answer(Color? color) {
      stream.removeListener(listener);
      if (!tone.isCompleted) tone.complete(color);
    }

    listener = ImageStreamListener((image, _) async {
      try {
        answer(await _averageColor(image.image));
      } catch (_) {
        // Nothing in here may leave the completer standing: [toneFor] awaits
        // it, so a throw on the way to the pixels would stall the tone for the
        // rest of the session instead of costing one avatar its ring. The read
        // that can actually fail is answered inside [_averageColor], where a
        // test can reach it; this is the net under everything else.
        answer(null);
      } finally {
        image.dispose();
      }
    }, onError: (Object _, StackTrace? _) => answer(null));
    stream.addListener(listener);
    return tone.future;
  }

  /// The mean of the pixels that are actually there. An arithmetic mean rather
  /// than a dominant-colour cluster: what the ring has to stand out against is
  /// the whole face at a glance, not its largest patch.
  static Future<Color?> _averageColor(ui.Image image) async {
    ByteData? data;
    try {
      // The straight variant rather than `rawRgba`, which hands back
      // premultiplied bytes: a pixel drawn at 78% alpha comes out of that one
      // multiplied down towards black, so a photo with a soft edge or a
      // translucent logo would read as a darker face than it is. Straight RGBA
      // is the colour the pixel was drawn in, which is what the ring is
      // actually seen against.
      data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    } catch (_) {
      // A texture the engine will not read back — one already disposed, one
      // whose bytes never made it to the GPU — is a face with no tone, not an
      // error worth having: the caller is a completer's listener, and throwing
      // past it would leave the tone pending forever.
      return null;
    }
    final pixels = (data?.lengthInBytes ?? 0) ~/ 4;
    if (data == null || pixels == 0) return null;
    // A 460px GitHub avatar is a fifth of a megapixel, and every fourth or
    // fortieth pixel of a face is the same answer to within a shade.
    final step = math.max(1, pixels ~/ 4096);
    var red = 0;
    var green = 0;
    var blue = 0;
    var counted = 0;
    for (var pixel = 0; pixel < pixels; pixel += step) {
      final at = pixel * 4;
      // A transparent corner is whatever sits behind the photo, not the photo.
      if (data.getUint8(at + 3) < 128) continue;
      red += data.getUint8(at);
      green += data.getUint8(at + 1);
      blue += data.getUint8(at + 2);
      counted++;
    }
    return counted == 0
        ? null
        : Color.fromARGB(
            255,
            red ~/ counted,
            green ~/ counted,
            blue ~/ counted,
          );
  }

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
  /// lookup that failed is not an answer: nobody is remembered, so the next
  /// commit by the same person asks again rather than wearing initials for the
  /// rest of the session over one dropped request. The sha itself is retired
  /// only when the server says it has no such commit.
  Future<CommitAvatars> _load(
    String sha,
    GitIdentity author,
    GitIdentity? committer,
  ) async {
    Object? json;
    try {
      json = await api.getJson(
        'repos/${remote.owner}/${remote.repository}/commits/$sha',
      );
    } on GitHubApiException catch (error) {
      // 404 for a repository the server has, 422 for a sha it does not: either
      // way this commit is local-only and will answer nothing until it is
      // pushed. Every other failure — a rate limit, a dropped connection — is
      // worth asking about again, so only these two retire the sha.
      if (error.status == 404 || error.status == 422) {
        _missing.add(sha);
        _cache.remove(sha);
      }
    }
    if (json is! Map<String, dynamic>) {
      _forget(author, committer);
      return const CommitAvatars();
    }
    final avatars = CommitAvatars(
      author: _headed(_parseAvatar(json['author'])),
      committer: _headed(_parseAvatar(json['committer'])),
    );
    final authorKey = _identityKey(author);
    // Blame knows who wrote a line but not who committed it. Without an
    // identity to file it under, the committer's account is dropped rather
    // than remembered as somebody.
    final committerKey = committer == null ? null : _identityKey(committer);
    _known[authorKey] = _keepingTone(authorKey, avatars.author);
    if (committerKey != null) {
      _known[committerKey] = _keepingTone(committerKey, avatars.committer);
    }
    if (avatars.author != null || avatars.committer != null) _persist();
    return CommitAvatars(
      author: _known[authorKey],
      committer: committerKey == null ? null : _known[committerKey],
    );
  }

  /// [fresh] wearing the tone already known for [key]. The server never
  /// mentions a tone, so every parsed avatar arrives without one — and a row
  /// with a known author and an unheard-of committer still reaches the lookup,
  /// which every squash merge through the GitHub UI is (`noreply@github.com`
  /// committed it). Without this the answer would put a
  /// tone-less face back over the one restored from disk, and [_persist] would
  /// then write the loss down. Only for the same photo: a tone read off another
  /// URL is not this one's, and is dropped so the next decode reads it again.
  RemoteAvatar? _keepingTone(String key, RemoteAvatar? fresh) {
    final tone = _known[key]?.tone;
    if (fresh == null ||
        fresh.tone != null ||
        tone == null ||
        _known[key]?.url != fresh.url) {
      return fresh;
    }
    return RemoteAvatar(
      login: fresh.login,
      url: fresh.url,
      headers: fresh.headers,
      tone: tone,
    );
  }

  /// Hands the faces found so far to the next run. The whole map goes rather
  /// than a diff: it holds one line per person, and this happens once per
  /// person met, not once per commit.
  void _persist() {
    final store = this.store;
    if (store == null) return;
    final found = {for (final entry in _known.entries) entry.key: ?entry.value};
    // A write that fails is a face relearned next time, which is what the app
    // did before there was a file at all.
    _writing = _writing
        .then((_) => store.save(remote.host, found))
        .catchError((Object _) {});
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
    return RemoteAvatar(
      login: avatar.login,
      url: avatar.url,
      headers: headers,
      tone: avatar.tone,
    );
  }

  /// A dot parts a name the way a space does: plenty of people commit as
  /// `jung.min`, and that reads as JM, not J. Empty pieces — a trailing dot,
  /// two in a row — drop out rather than count as a name.
  static String initials(GitIdentity identity) {
    final parts = identity.name
        .split(RegExp(r'[\s.]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
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
