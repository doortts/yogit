import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/github_auth.dart';

/// Contract for token storage, the yonalist way:
/// - one token per API base URL, held in the macOS Keychain through the
///   `security` CLI (no plugin);
/// - read order: Keychain → GH_TOKEN → GITHUB_TOKEN; misses return null;
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

  test('a Keychain miss falls back to GH_TOKEN then GITHUB_TOKEN', () async {
    final missing = {
      'find-generic-password': (List<String> _) =>
          ProcessResult(1, 44, '', 'could not be found'),
    };

    final gh = storeWith(
      bySubcommand: missing,
      environment: const {'GH_TOKEN': 'a', 'GITHUB_TOKEN': 'b'},
    );
    expect(await gh.store.read('https://api.github.com'), 'a');

    final github = storeWith(
      bySubcommand: missing,
      environment: const {'GITHUB_TOKEN': 'b'},
    );
    expect(await github.store.read('https://api.github.com'), 'b');

    final none = storeWith(bySubcommand: missing);
    expect(await none.store.read('https://api.github.com'), isNull);
  });

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

  test('a failed save surfaces, a failed delete of a missing item does not',
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
  });
}
