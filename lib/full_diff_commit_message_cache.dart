import 'package:flutter/foundation.dart';

typedef FullDiffCommitMessageCacheKey = ({String repositoryRoot, String sha});

class FullDiffCommitMessageCache {
  FullDiffCommitMessageCache();

  static final FullDiffCommitMessageCache shared = FullDiffCommitMessageCache();

  final _values = <FullDiffCommitMessageCacheKey, String>{};
  final _inFlight = <FullDiffCommitMessageCacheKey, Future<String>>{};

  Future<String> getOrLoad({
    required String repositoryRoot,
    required String sha,
    required Future<String> Function() loader,
  }) {
    final key = (repositoryRoot: repositoryRoot, sha: sha);
    final value = _values[key];
    if (value != null) return SynchronousFuture(value);
    final pending = _inFlight[key];
    if (pending != null) return pending;

    late final Future<String> request;
    request = Future<String>.sync(loader)
        .then((raw) {
          final message = raw.trimRight();
          if (message.trim().isEmpty) {
            throw const FormatException('Empty commit message');
          }
          _values[key] = message;
          return message;
        })
        .whenComplete(() {
          if (identical(_inFlight[key], request)) _inFlight.remove(key);
        });
    _inFlight[key] = request;
    return request;
  }
}
