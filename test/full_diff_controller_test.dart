import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_controller.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/git.dart';

import 'support/full_diff_fixtures.dart';

void main() {
  test(
    'loads patch and content together and keeps views independent',
    () async {
      final patch = Completer<List<DiffLine>>();
      final content = Completer<Uint8List>();
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..diff = ((_, _, _, _, _) => patch.future)
        ..content = ((_, _, _) => content.future);
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );

      final loading = controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.patch.loading, isTrue);
      expect(controller.state.file.loading, isTrue);
      expect(controller.state.encodingLabel, 'Loading');
      controller
        ..setView(FullDiffView.file)
        ..setPresentation(DiffPresentation.split);
      expect(controller.state.view, FullDiffView.file);
      expect(controller.state.presentation, DiffPresentation.split);
      expect(repository.diffRequests, hasLength(1));

      patch.complete(twoHunkLines);
      content.complete(Uint8List.fromList(utf8.encode('one\ntwo\n')));
      await loading;

      expect(controller.state.patch.data?.hunks, hasLength(2));
      expect(controller.state.file.data?.kind, FileContentKind.utf8);
      expect(controller.state.activeAnchor?.hunkIndex, 0);
    },
  );

  test('a late file cannot replace the current four resources', () async {
    const fileB = GitFileChange(
      path: 'src/window.pas',
      status: 'M',
      additions: 1,
      deletions: 1,
    );
    final patchA = Completer<List<DiffLine>>();
    final patchB = Completer<List<DiffLine>>();
    final contentA = Completer<Uint8List>();
    final contentB = Completer<Uint8List>();
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA, fileB])
      ..diff = ((_, file, _, _, _) =>
          file.path == fileA.path ? patchA.future : patchB.future)
      ..content = ((_, file, _) =>
          file.path == fileA.path ? contentA.future : contentB.future)
      ..blame = ((_, file, _, _) async => [
        GitBlameLine(
          lineNumber: 1,
          sha: commitA.sha,
          author: file.path,
          uncommitted: false,
        ),
      ])
      ..history = ((_, file) async => [
        GitFileHistoryRecord(
          commit: commitA,
          path: file.path,
          oldPath: null,
          status: 'M',
        ),
      ]);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
      initialView: FullDiffInitialView.hunk,
    );
    final firstLoad = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    final secondLoad = controller.selectFile(fileB);
    expect(controller.state.patch.data, isNull);
    expect(controller.state.file.data, isNull);
    expect(controller.state.blame.data, isNull);
    expect(controller.state.history.data, isNull);

    patchB.complete(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
      DiffLine(kind: DiffLineKind.add, text: 'current', newNumber: 1),
    ]);
    contentB.complete(Uint8List.fromList(utf8.encode('current\n')));
    await secondLoad;
    controller.setView(FullDiffView.blame);
    await Future<void>.delayed(Duration.zero);
    controller.setView(FullDiffView.history);
    await Future<void>.delayed(Duration.zero);

    patchA.complete(twoHunkLines);
    contentA.complete(Uint8List.fromList(utf8.encode('stale\n')));
    await firstLoad;

    expect(controller.state.selectedFile, fileB);
    expect(controller.state.patch.data?.rows.last.text, 'current');
    expect(controller.state.file.data?.lines.single, 'current');
    expect(controller.state.blame.data?.lines.single.author, fileB.path);
    expect(controller.state.history.data?.single.path, fileB.path);
  });

  test(
    'history follows a file selection without waiting for patch or content',
    () async {
      const fileB = GitFileChange(
        path: 'src/window.pas',
        status: 'M',
        additions: 1,
        deletions: 1,
      );
      final patchB = Completer<List<DiffLine>>();
      final contentB = Completer<Uint8List>();
      final historyB = Completer<List<GitFileHistoryRecord>>();
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA, fileB])
        ..diff = ((_, file, _, _, _) => file.path == fileB.path
            ? patchB.future
            : Future.value(twoHunkLines))
        ..content = ((_, file, _) => file.path == fileB.path
            ? contentB.future
            : Future.value(Uint8List.fromList(utf8.encode('initial\n'))))
        ..history = ((_, file) => file.path == fileB.path
            ? historyB.future
            : Future.value(const <GitFileHistoryRecord>[]));
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );
      await controller.initialize();
      controller.setView(FullDiffView.history);
      await Future<void>.delayed(Duration.zero);

      final selection = controller.selectFile(fileB);
      await Future<void>.delayed(Duration.zero);

      expect(repository.historyRequests.last.path, fileB.path);
      expect(controller.state.history.loading, isTrue);
      historyB.complete([
        GitFileHistoryRecord(
          commit: commitA,
          path: fileB.path,
          oldPath: null,
          status: 'M',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.history.data?.single.path, fileB.path);

      patchB.complete(twoHunkLines);
      contentB.complete(Uint8List.fromList(utf8.encode('current\n')));
      await selection;
    },
  );

  test(
    'failed options restore the last successful patch and controls',
    () async {
      var calls = 0;
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('current\n')))
        ..diff = ((_, _, _, algorithm, whitespace) async {
          calls++;
          if (algorithm == DiffAlgorithm.histogram || whitespace) {
            throw const GitRepositoryException('/repo', 'diff failed');
          }
          return twoHunkLines;
        });
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );
      await controller.initialize();
      final successful = controller.state.patch.data;

      await expectLater(
        controller.selectAlgorithm(DiffAlgorithm.histogram),
        throwsA(isA<GitRepositoryException>()),
      );
      expect(controller.state.patch.data, same(successful));
      expect(controller.state.requestedAlgorithm, DiffAlgorithm.gitSetting);
      expect(controller.state.appliedAlgorithm, DiffAlgorithm.gitSetting);
      expect(calls, 2);
    },
  );

  test('file failure settles blame after leaving the blame view', () async {
    final patch = Completer<List<DiffLine>>();
    final content = Completer<Uint8List>();
    const failure = GitRepositoryException('/repo', 'content failed');
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) => patch.future)
      ..content = ((_, _, _) => content.future);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
      initialView: FullDiffInitialView.hunk,
    );

    final loading = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    controller
      ..setView(FullDiffView.blame)
      ..setView(FullDiffView.diff);
    expect(controller.state.blame.loading, isTrue);

    patch.complete(twoHunkLines);
    content.completeError(failure);
    await loading;

    expect(controller.state.file.error, same(failure));
    expect(controller.state.blame.loading, isFalse);
    expect(controller.state.blame.error, same(failure));
  });

  test('committed caches stay within count and byte limits', () async {
    final commits = List.generate(
      40,
      (index) => GitCommit(
        sha: 'sha-$index',
        shortSha: '$index'.padLeft(7, '0'),
        parents: index == 39 ? const [] : ['sha-${index + 1}'],
        author: fixtureIdentity,
        authorTimestamp: 1720573200 - index,
        committer: fixtureIdentity,
        committerTimestamp: 1720573200 - index,
        refs: const [],
        subject: 'commit $index',
      ),
    );
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) async => Uint8List(2 * 1024 * 1024));
    final controller = FullDiffSessionController(
      repository: repository,
      commits: commits,
      initialIndex: 0,
      initialView: FullDiffInitialView.hunk,
    );
    await controller.initialize();
    for (final commit in commits.skip(1)) {
      await controller.selectCommit(commit);
    }

    expect(controller.debugPatchCacheLength, lessThanOrEqualTo(32));
    expect(controller.debugFileCacheLength, lessThanOrEqualTo(32));
    expect(controller.debugRawCacheBytes, lessThanOrEqualTo(64 * 1024 * 1024));
  });

  test(
    'replaces a history-only commit with the canonical nearby object',
    () async {
      final historyCommit = GitCommit(
        sha: 'history-sha',
        shortSha: 'history',
        parents: const ['40aff6d'],
        author: fixtureIdentity,
        authorTimestamp: 1720573100,
        committer: fixtureIdentity,
        committerTimestamp: 1720573100,
        refs: const [],
        subject: 'history copy',
      );
      final canonical = GitCommit(
        sha: historyCommit.sha,
        shortSha: historyCommit.shortSha,
        parents: historyCommit.parents,
        author: historyCommit.author,
        authorTimestamp: historyCommit.authorTimestamp,
        committer: historyCommit.committer,
        committerTimestamp: historyCommit.committerTimestamp,
        refs: const [GitRef(name: 'main', isHead: true)],
        subject: 'canonical row',
      );
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..diff = ((_, _, _, _, _) async => twoHunkLines)
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('current\n')));
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );
      await controller.initialize();
      await controller.selectHistoryEntry(
        FileHistoryEntry(
          commit: historyCommit,
          path: fileA.path,
          oldPath: null,
          status: 'M',
        ),
      );
      controller.replaceNearbyCommits([canonical, commitA]);

      expect(controller.state.selectedCommit, same(canonical));
      expect(controller.state.nearbyCommits.first, same(canonical));
    },
  );
}
