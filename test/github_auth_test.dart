import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/github_auth.dart';

/// Contract for token storage, the yonalist way:
/// - one token per API base URL, held in the macOS Keychain through the
///   `security` CLI (no plugin);
/// - read order: Keychain first, then the env pair for the right host —
///   github.com reads GH_TOKEN → GITHUB_TOKEN, an enterprise host reads
///   GH_ENTERPRISE_TOKEN → GITHUB_ENTERPRISE_TOKEN; misses return null;
/// - the gh CLI is never consulted.
void main() {
  ({List<List<String>> calls, GithubTokenStore store}) storeWith({
    Map<String, ProcessResult Function(List<String>)>? bySubcommand,
    Map<String, String> environment = const {},
  }) {
    final calls = <List<String>>[];
    final store = GithubTokenStore(
      environment: environment,
      runner: (executable, arguments, {workingDirectory, environment}) async {
        expect(executable, '/usr/bin/security');
        calls.add(arguments);
        final responder = bySubcommand?[arguments.first];
        return responder?.call(arguments) ?? ProcessResult(1, 0, '', '');
      },
    );
    return (calls: calls, store: store);
  }

  test('the service name is stable per API base URL', () {
    expect(
      GithubTokenStore.serviceName('https://oss.navercorp.com/api/v3'),
      GithubTokenStore.serviceName('https://oss.navercorp.com/api/v3/'),
    );
    expect(
      GithubTokenStore.serviceName('https://api.github.com'),
      isNot(GithubTokenStore.serviceName('https://oss.navercorp.com/api/v3')),
    );
  });

  test('read prefers the Keychain entry', () async {
    final fixture = storeWith(
      bySubcommand: {
        'find-generic-password': (_) => ProcessResult(1, 0, 'kc-token\n', ''),
      },
      environment: const {'GH_TOKEN': 'env-token'},
    );

    expect(await fixture.store.read('https://api.github.com'), 'kc-token');
    final arguments = fixture.calls.single;
    expect(arguments.first, 'find-generic-password');
    expect(arguments, contains('-w'));
    expect(
      arguments,
      contains(GithubTokenStore.serviceName('https://api.github.com')),
    );
  });

  test(
    'a Keychain miss falls back to the env token for the right host',
    () async {
      // gh semantics: GH_TOKEN belongs to github.com, GH_ENTERPRISE_TOKEN to
      // enterprise hosts. Handing a github.com token to a GHE server would just
      // manufacture a 401 banner.
      final missing = {
        'find-generic-password': (List<String> _) =>
            ProcessResult(1, 44, '', 'could not be found'),
      };
      const env = {
        'GH_TOKEN': 'dotcom-a',
        'GITHUB_TOKEN': 'dotcom-b',
        'GH_ENTERPRISE_TOKEN': 'ghe-a',
        'GITHUB_ENTERPRISE_TOKEN': 'ghe-b',
      };

      final dotcom = storeWith(bySubcommand: missing, environment: env);
      expect(await dotcom.store.read('https://api.github.com'), 'dotcom-a');

      final ghe = storeWith(bySubcommand: missing, environment: env);
      expect(await ghe.store.read('https://oss.navercorp.com/api/v3'), 'ghe-a');

      final gheSecondChoice = storeWith(
        bySubcommand: missing,
        environment: const {
          'GH_TOKEN': 'dotcom-a',
          'GITHUB_ENTERPRISE_TOKEN': 'ghe-b',
        },
      );
      expect(
        await gheSecondChoice.store.read('https://oss.navercorp.com/api/v3'),
        'ghe-b',
      );

      // A github.com-only env never leaks onto an enterprise server.
      final wrongHost = storeWith(
        bySubcommand: missing,
        environment: const {'GH_TOKEN': 'dotcom-a', 'GITHUB_TOKEN': 'dotcom-b'},
      );
      expect(
        await wrongHost.store.read('https://oss.navercorp.com/api/v3'),
        isNull,
      );

      final none = storeWith(bySubcommand: missing);
      expect(await none.store.read('https://api.github.com'), isNull);
    },
  );

  test('save upserts and delete removes, both scoped to the service', () async {
    final fixture = storeWith();
    await fixture.store.save('https://api.github.com', 'new-token');
    await fixture.store.delete('https://api.github.com');

    final save = fixture.calls[0];
    expect(save.first, 'add-generic-password');
    // -U updates in place: saving twice must not fail on a duplicate item.
    expect(save, contains('-U'));
    expect(save, contains('new-token'));
    expect(
      save,
      contains(GithubTokenStore.serviceName('https://api.github.com')),
    );

    final remove = fixture.calls[1];
    expect(remove.first, 'delete-generic-password');
    expect(
      remove,
      contains(GithubTokenStore.serviceName('https://api.github.com')),
    );
  });

  test(
    'a failed save surfaces, a failed delete of a missing item does not',
    () async {
      final fixture = storeWith(
        bySubcommand: {
          'add-generic-password': (_) => ProcessResult(1, 36, '', 'denied'),
          'delete-generic-password': (_) =>
              ProcessResult(1, 44, '', 'could not be found'),
        },
      );

      await expectLater(
        fixture.store.save('https://api.github.com', 'x'),
        throwsA(isA<Exception>()),
      );
      // Deleting what is already gone is the desired end state.
      await fixture.store.delete('https://api.github.com');
    },
  );
}
