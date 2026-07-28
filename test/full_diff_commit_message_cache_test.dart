import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_commit_message_cache.dart';

void main() {
  test(
    'coalesces concurrent requests and retains a successful value',
    () async {
      final cache = FullDiffCommitMessageCache();
      final completer = Completer<String>();
      var calls = 0;

      Future<String> load() {
        calls++;
        return completer.future;
      }

      final first = cache.getOrLoad(
        repositoryRoot: '/repo',
        sha: 'abc',
        loader: load,
      );
      final second = cache.getOrLoad(
        repositoryRoot: '/repo',
        sha: 'abc',
        loader: load,
      );
      expect(calls, 1);

      completer.complete('Subject\n\nBody\n');
      expect(await first, 'Subject\n\nBody');
      expect(await second, 'Subject\n\nBody');
      expect(
        await cache.getOrLoad(
          repositoryRoot: '/repo',
          sha: 'abc',
          loader: load,
        ),
        'Subject\n\nBody',
      );
      expect(calls, 1);
    },
  );

  test('separates repositories and retries failed or empty loads', () async {
    final cache = FullDiffCommitMessageCache();
    var calls = 0;

    Future<String> load() async {
      calls++;
      if (calls == 1) throw StateError('temporary');
      if (calls == 2) return '   ';
      return 'Recovered';
    }

    await expectLater(
      cache.getOrLoad(repositoryRoot: '/a', sha: 'abc', loader: load),
      throwsStateError,
    );
    await expectLater(
      cache.getOrLoad(repositoryRoot: '/a', sha: 'abc', loader: load),
      throwsFormatException,
    );
    expect(
      await cache.getOrLoad(repositoryRoot: '/a', sha: 'abc', loader: load),
      'Recovered',
    );
    expect(
      await cache.getOrLoad(
        repositoryRoot: '/b',
        sha: 'abc',
        loader: () async => 'Other repository',
      ),
      'Other repository',
    );
    expect(calls, 3);
  });
}
