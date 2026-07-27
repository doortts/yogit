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
      expect(controller.state.richRenderingEnabled, isFalse);
      controller
        ..setView(FullDiffView.file)
        ..setPresentation(DiffPresentation.split);
      expect(controller.state.view, FullDiffView.file);
      expect(controller.state.presentation, DiffPresentation.split);
      expect(repository.diffRequests, hasLength(1));

      patch.complete(twoHunkLines);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.patch.data?.hunks, hasLength(2));
      expect(controller.state.file.data, isNull);
      expect(controller.state.richRenderingEnabled, isFalse);

      content.complete(Uint8List.fromList(utf8.encode('one\ntwo\n')));
      await loading;

      expect(controller.state.patch.data?.hunks, hasLength(2));
      expect(controller.state.file.data?.kind, FileContentKind.utf8);
      expect(controller.state.richRenderingEnabled, isTrue);
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

  test(
    'successful file load resumes blame after leaving the blame view',
    () async {
      final patch = Completer<List<DiffLine>>();
      final content = Completer<Uint8List>();
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..diff = ((_, _, _, _, _) => patch.future)
        ..content = ((_, _, _) => content.future)
        ..blame = ((_, _, _, _) async => const [
          GitBlameLine(
            lineNumber: 1,
            sha: '40aff6d',
            author: 'First',
            uncommitted: false,
          ),
          GitBlameLine(
            lineNumber: 2,
            sha: '40aff6d',
            author: 'Second',
            uncommitted: false,
          ),
        ]);
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
      content.complete(Uint8List.fromList(utf8.encode('one\ntwo\n')));
      await loading;

      expect(controller.state.file.data?.kind, FileContentKind.utf8);
      expect(controller.state.blame.loading, isFalse);
      expect(controller.state.blame.data?.lines, hasLength(2));
      expect(repository.blameRequests, hasLength(1));
    },
  );

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

  test(
    'keeps the history context while selecting a historical revision',
    () async {
      const fileB = GitFileChange(
        path: 'src/window.pas',
        status: 'M',
        additions: 1,
        deletions: 1,
      );
      final repository = FakeFullDiffRepository()
        ..files = ((commit, _) async =>
            commit.sha == commitA.sha ? const [fileA] : const [fileA, fileB])
        ..diff = ((commit, _, _, _, _) async => [
          const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
          DiffLine(
            kind: DiffLineKind.add,
            text: commit.sha == commitA.sha
                ? 'current change'
                : 'historical change',
            newNumber: 1,
          ),
        ])
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('content\n')))
        ..history = ((_, _) async => [
          const GitFileHistoryRecord(
            commit: commitA,
            path: 'src/drlua.pas',
            oldPath: null,
            status: 'M',
          ),
          const GitFileHistoryRecord(
            commit: historyCommitB,
            path: 'src/drlua.pas',
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

      expect(controller.state.selectedHistoryEntry, isNull);
      expect(controller.state.historyContext, isNull);
      await controller.initialize();
      controller.setView(FullDiffView.history);
      await Future<void>.delayed(Duration.zero);
      final originalHistory = controller.state.history.data!;
      final historyEntry = originalHistory.last;

      expect(controller.state.selectedHistoryEntry?.commit.sha, commitA.sha);
      expect(controller.state.historyContext, (
        startRevision: commitA.sha,
        path: fileA.path,
      ));

      await controller.selectHistoryEntry(historyEntry);

      expect(controller.state.history.data, same(originalHistory));
      expect(controller.state.selectedHistoryEntry, same(historyEntry));
      expect(controller.state.historyContext, (
        startRevision: commitA.sha,
        path: fileA.path,
      ));
      expect(controller.state.patch.data?.rows.last.text, 'historical change');

      controller.setView(FullDiffView.diff);
      expect(controller.state.history.data, same(originalHistory));
      final fileSelection = controller.selectFile(fileB);
      expect(controller.state.history.data, isNull);
      expect(controller.state.selectedHistoryEntry, isNull);
      expect(controller.state.historyContext, isNull);
      await fileSelection;
    },
  );

  test(
    'keeps the selected history entry through loading and resource errors',
    () async {
      final historicalFiles = Completer<List<GitFileChange>>();
      const failure = GitRepositoryException('/repo', 'historical failed');
      final repository = FakeFullDiffRepository()
        ..files = ((commit, _) => commit.sha == commitA.sha
            ? Future.value(const [fileA])
            : historicalFiles.future)
        ..diff = ((commit, _, _, _, _) => commit.sha == commitA.sha
            ? Future.value(twoHunkLines)
            : Future.error(failure))
        ..content = ((commit, _, _) => commit.sha == commitA.sha
            ? Future.value(Uint8List.fromList(utf8.encode('current\n')))
            : Future.error(failure))
        ..history = ((_, _) async => const [
          GitFileHistoryRecord(
            commit: commitA,
            path: 'src/drlua.pas',
            oldPath: null,
            status: 'M',
          ),
          GitFileHistoryRecord(
            commit: historyCommitB,
            path: 'src/drlua.pas',
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
      await controller.initialize();
      controller.setView(FullDiffView.history);
      await Future<void>.delayed(Duration.zero);
      final originalHistory = controller.state.history.data!;
      final historyEntry = originalHistory.last;

      final selection = controller.selectHistoryEntry(historyEntry);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.filesResource.loading, isTrue);
      expect(controller.state.history.data, same(originalHistory));
      expect(controller.state.selectedHistoryEntry, same(historyEntry));
      expect(controller.state.historyContext, (
        startRevision: commitA.sha,
        path: fileA.path,
      ));

      historicalFiles.complete(const [fileA]);
      await selection;

      expect(controller.state.patch.error, same(failure));
      expect(controller.state.file.error, same(failure));
      expect(controller.state.history.data, same(originalHistory));
      expect(controller.state.selectedHistoryEntry, same(historyEntry));
    },
  );

  test(
    'a late historical file list cannot replace a newer selection',
    () async {
      final firstFiles = Completer<List<GitFileChange>>();
      final secondFiles = Completer<List<GitFileChange>>();
      final repository = FakeFullDiffRepository()
        ..files = ((commit, _) => switch (commit.sha) {
          'history-b' => firstFiles.future,
          'history-c' => secondFiles.future,
          _ => Future.value(const [fileA]),
        })
        ..diff = ((commit, _, _, _, _) async => [
          const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
          DiffLine(
            kind: DiffLineKind.add,
            text: commit.sha == historyCommitC.sha ? 'second' : 'first',
            newNumber: 1,
          ),
        ])
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('content\n')))
        ..history = ((_, _) async => const [
          GitFileHistoryRecord(
            commit: historyCommitB,
            path: 'src/drlua.pas',
            oldPath: null,
            status: 'M',
          ),
          GitFileHistoryRecord(
            commit: historyCommitC,
            path: 'src/drlua.pas',
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
      await controller.initialize();
      controller.setView(FullDiffView.history);
      await Future<void>.delayed(Duration.zero);
      final originalHistory = controller.state.history.data!;
      final firstEntry = originalHistory.first;
      final secondEntry = originalHistory.last;

      final firstSelection = controller.selectHistoryEntry(firstEntry);
      final secondSelection = controller.selectHistoryEntry(secondEntry);
      secondFiles.complete(const [fileA]);
      await secondSelection;
      firstFiles.complete(const [fileA]);
      await firstSelection;

      expect(controller.state.selectedHistoryEntry, same(secondEntry));
      expect(controller.state.selectedCommit.sha, historyCommitC.sha);
      expect(controller.state.patch.data?.rows.last.text, 'second');
      expect(controller.state.history.data, same(originalHistory));
    },
  );

  test('a late historical patch cannot replace a newer selection', () async {
    final firstPatch = Completer<List<DiffLine>>();
    final secondPatch = Completer<List<DiffLine>>();
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((commit, _, _, _, _) => switch (commit.sha) {
        'history-b' => firstPatch.future,
        'history-c' => secondPatch.future,
        _ => Future.value(twoHunkLines),
      })
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('content\n')))
      ..history = ((_, _) async => const [
        GitFileHistoryRecord(
          commit: historyCommitB,
          path: 'src/drlua.pas',
          oldPath: null,
          status: 'M',
        ),
        GitFileHistoryRecord(
          commit: historyCommitC,
          path: 'src/drlua.pas',
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
    await controller.initialize();
    controller.setView(FullDiffView.history);
    await Future<void>.delayed(Duration.zero);
    final originalHistory = controller.state.history.data!;
    final firstEntry = originalHistory.first;
    final secondEntry = originalHistory.last;

    final firstSelection = controller.selectHistoryEntry(firstEntry);
    await Future<void>.delayed(Duration.zero);
    final secondSelection = controller.selectHistoryEntry(secondEntry);
    await Future<void>.delayed(Duration.zero);
    secondPatch.complete(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
      DiffLine(kind: DiffLineKind.add, text: 'second', newNumber: 1),
    ]);
    await secondSelection;
    firstPatch.complete(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
      DiffLine(kind: DiffLineKind.add, text: 'first', newNumber: 1),
    ]);
    await firstSelection;

    expect(controller.state.selectedHistoryEntry, same(secondEntry));
    expect(controller.state.selectedCommit.sha, historyCommitC.sha);
    expect(controller.state.patch.data?.rows.last.text, 'second');
    expect(controller.state.history.data, same(originalHistory));
  });

  test(
    'retries a failed historical selection and matches the previous path',
    () async {
      const renamedFile = GitFileChange(
        path: 'src/new-name.pas',
        oldPath: 'src/old-name.pas',
        status: 'R',
        additions: 1,
        deletions: 1,
      );
      var historicalFileLoads = 0;
      final repository = FakeFullDiffRepository()
        ..files = ((commit, _) async {
          if (commit.sha == commitA.sha) return const [renamedFile];
          historicalFileLoads++;
          if (historicalFileLoads == 1) {
            throw const GitRepositoryException('/repo', 'files failed');
          }
          return const [renamedFile];
        })
        ..diff = ((_, _, _, _, _) async => const [
          DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
          DiffLine(kind: DiffLineKind.add, text: 'retried', newNumber: 1),
        ])
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('retried\n')))
        ..history = ((_, _) async => const [
          GitFileHistoryRecord(
            commit: historyCommitB,
            path: 'src/old-name.pas',
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
      await controller.initialize();
      controller.setView(FullDiffView.history);
      await Future<void>.delayed(Duration.zero);
      final originalHistory = controller.state.history.data!;
      final historyEntry = originalHistory.single;

      await controller.selectHistoryEntry(historyEntry);

      expect(
        controller.state.filesResource.error,
        isA<GitRepositoryException>(),
      );
      expect(controller.state.selectedHistoryEntry, same(historyEntry));
      expect(controller.state.history.data, same(originalHistory));

      await controller.retryHistorySelection();

      expect(historicalFileLoads, 2);
      expect(controller.state.selectedFile, renamedFile);
      expect(controller.state.patch.data?.rows.last.text, 'retried');
      expect(controller.state.selectedHistoryEntry, same(historyEntry));
      expect(controller.state.history.data, same(originalHistory));
    },
  );

  test(
    'commit and parent selections clear the history selection context',
    () async {
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..diff = ((_, _, _, _, _) async => twoHunkLines)
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('content\n')))
        ..history = ((_, _) async => const [
          GitFileHistoryRecord(
            commit: commitA,
            path: 'src/drlua.pas',
            oldPath: null,
            status: 'M',
          ),
        ]);
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA, historyCommitB],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );
      await controller.initialize();
      controller.setView(FullDiffView.history);
      await Future<void>.delayed(Duration.zero);

      final commitSelection = controller.selectCommit(historyCommitB);
      expect(controller.state.history.data, isNull);
      expect(controller.state.selectedHistoryEntry, isNull);
      expect(controller.state.historyContext, isNull);
      await commitSelection;

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.historyContext, (
        startRevision: historyCommitB.sha,
        path: fileA.path,
      ));

      final parentSelection = controller.selectParent(null);
      expect(controller.state.history.data, isNull);
      expect(controller.state.selectedHistoryEntry, isNull);
      expect(controller.state.historyContext, isNull);
      await parentSelection;
    },
  );

  test('retrying files rejects an earlier history completion', () async {
    final history = Completer<List<GitFileHistoryRecord>>();
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('content\n')))
      ..history = ((_, _) => history.future);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
      initialView: FullDiffInitialView.hunk,
    );
    await controller.initialize();
    controller.setView(FullDiffView.history);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.history.loading, isTrue);

    controller.setView(FullDiffView.diff);
    await controller.retryFiles();
    expect(controller.state.history.data, isNull);
    expect(controller.state.selectedHistoryEntry, isNull);
    expect(controller.state.historyContext, isNull);

    history.complete(const [
      GitFileHistoryRecord(
        commit: commitA,
        path: 'src/drlua.pas',
        oldPath: null,
        status: 'M',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.history.data, isNull);
    expect(controller.state.selectedHistoryEntry, isNull);
    expect(controller.state.historyContext, isNull);
  });
}

const historyCommitB = GitCommit(
  sha: 'history-b',
  shortSha: 'history',
  parents: ['parent-b'],
  author: fixtureIdentity,
  authorTimestamp: 1720486800,
  committer: fixtureIdentity,
  committerTimestamp: 1720486800,
  refs: [],
  subject: 'Historical revision B',
);

const historyCommitC = GitCommit(
  sha: 'history-c',
  shortSha: 'history',
  parents: ['parent-c'],
  author: fixtureIdentity,
  authorTimestamp: 1720400400,
  committer: fixtureIdentity,
  committerTimestamp: 1720400400,
  refs: [],
  subject: 'Historical revision C',
);
