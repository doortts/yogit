import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_controller.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/git.dart';

import 'support/full_diff_fixtures.dart';

void main() {
  const mergedTwoHunkLines = <DiffLine>[
    DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,12 +10,12 @@ merged'),
    DiffLine(
      kind: DiffLineKind.context,
      text: 'before',
      oldNumber: 10,
      newNumber: 10,
    ),
    DiffLine(kind: DiffLineKind.delete, text: 'first old', oldNumber: 13),
    DiffLine(kind: DiffLineKind.add, text: 'first new', newNumber: 13),
    DiffLine(
      kind: DiffLineKind.context,
      text: 'middle',
      oldNumber: 17,
      newNumber: 17,
    ),
    DiffLine(kind: DiffLineKind.delete, text: 'second old', oldNumber: 21),
    DiffLine(kind: DiffLineKind.add, text: 'second new', newNumber: 21),
  ];

  Future<
    ({
      FullDiffSessionController controller,
      Completer<List<DiffLine>> fullFilePatch,
    })
  >
  delayedFullFileController() async {
    final fullFilePatch = Completer<List<DiffLine>>();
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('current\n')))
      ..scopedDiff = ((_, _, _, _, _, scope) => scope == DiffScope.hunks
          ? Future.value(twoHunkLines)
          : fullFilePatch.future);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    await controller.initialize();
    return (controller: controller, fullFilePatch: fullFilePatch);
  }

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
        encodingCache: FullDiffEncodingCache(),
      );

      final loading = controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.patch.loading, isTrue);
      expect(controller.state.file.loading, isTrue);
      expect(controller.state.encodingLabel, '');
      expect(controller.state.richRenderingEnabled, isFalse);
      controller
        ..setView(FullDiffView.diff)
        ..setLayout(DiffLayout.sideBySide);
      expect(controller.state.view, FullDiffView.diff);
      expect(controller.state.layout, DiffLayout.sideBySide);
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

  test('shares a committed file encoding across controllers', () async {
    final encodingCache = FullDiffEncodingCache();
    final firstRepository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('committed\n')));
    final first = FullDiffSessionController(
      repository: firstRepository,
      commits: const [commitA],
      initialIndex: 0,
      encodingCache: encodingCache,
    );
    addTearDown(first.dispose);
    await first.initialize();
    expect(first.state.encodingLabel, 'UTF-8');

    final contentStarted = Completer<void>();
    final content = Completer<Uint8List>();
    final secondRepository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) {
        contentStarted.complete();
        return content.future;
      });
    final second = FullDiffSessionController(
      repository: secondRepository,
      commits: const [commitA],
      initialIndex: 0,
      encodingCache: encodingCache,
    );
    addTearDown(second.dispose);

    final loading = second.initialize();
    await contentStarted.future;
    expect(second.state.file.loading, isTrue);
    expect(second.state.encodingLabel, 'UTF-8');

    content.complete(Uint8List.fromList(utf8.encode('committed again\n')));
    await loading;
    expect(second.state.encodingLabel, 'UTF-8');
  });

  test('refreshes a cached working-tree encoding in the background', () async {
    final encodingCache = FullDiffEncodingCache();
    final firstRepository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('working tree\n')));
    final first = FullDiffSessionController(
      repository: firstRepository,
      commits: const [_workingTreeCommit],
      initialIndex: 0,
      encodingCache: encodingCache,
    );
    addTearDown(first.dispose);
    await first.initialize();
    expect(first.state.encodingLabel, 'UTF-8');

    final contentStarted = Completer<void>();
    final content = Completer<Uint8List>();
    final secondRepository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) {
        contentStarted.complete();
        return content.future;
      });
    final second = FullDiffSessionController(
      repository: secondRepository,
      commits: const [_workingTreeCommit],
      initialIndex: 0,
      encodingCache: encodingCache,
    );
    addTearDown(second.dispose);

    final loading = second.initialize();
    await contentStarted.future;
    expect(second.state.encodingLabel, 'UTF-8');

    content.complete(Uint8List.fromList([0, 1, 2]));
    await loading;
    expect(second.state.encodingLabel, 'Binary');
  });

  test('keeps a cached working-tree encoding when refresh fails', () async {
    final encodingCache = FullDiffEncodingCache();
    final firstRepository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('working tree\n')));
    final first = FullDiffSessionController(
      repository: firstRepository,
      commits: const [_workingTreeCommit],
      initialIndex: 0,
      encodingCache: encodingCache,
    );
    addTearDown(first.dispose);
    await first.initialize();

    final secondRepository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) async => throw const GitRepositoryException(
        '/repo',
        'working tree read failed',
      ));
    final second = FullDiffSessionController(
      repository: secondRepository,
      commits: const [_workingTreeCommit],
      initialIndex: 0,
      encodingCache: encodingCache,
    );
    addTearDown(second.dispose);

    await second.initialize();
    expect(second.state.file.error, isA<GitRepositoryException>());
    expect(second.state.encodingLabel, 'UTF-8');
  });

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

  test('failed full-file scope keeps the applied hunk preference', () async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('current\n')))
      ..scopedDiff = ((_, _, _, _, _, scope) async {
        if (scope == DiffScope.fullFile) {
          throw const GitRepositoryException('/repo', 'full file failed');
        }
        return twoHunkLines;
      });
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);

    await expectLater(
      controller.setScope(DiffScope.fullFile),
      throwsA(isA<GitRepositoryException>()),
    );

    expect(controller.state.requestedScope, DiffScope.hunks);
    expect(controller.state.appliedScope, DiffScope.hunks);
    expect(controller.state.preferences.scope, DiffScope.hunks);
    expect(controller.state.fullFileScrollTarget, isNull);
  });

  test('leaving full-file scope restores the preserved later hunk', () async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('current\n')))
      ..scopedDiff = ((_, _, _, _, _, scope) async =>
          scope == DiffScope.hunks ? twoHunkLines : mergedTwoHunkLines);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);

    await controller.setScope(DiffScope.fullFile);
    expect(controller.state.fullFileScrollTarget, (oldLine: 21, newLine: 21));
    expect(controller.state.activeAnchor?.hunkIndex, 0);

    await controller.setScope(DiffScope.hunks);

    expect(controller.state.appliedScope, DiffScope.hunks);
    expect(controller.state.activeAnchor?.hunkIndex, 1);
    expect(controller.state.activeAnchor?.newLine, 21);
    expect(controller.state.fullFileScrollTarget, isNull);
  });

  test('failed hunk return restores the full-file target for retry', () async {
    var hunkLoads = 0;
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('current\n')))
      ..scopedDiff = ((_, _, _, _, _, scope) async {
        if (scope == DiffScope.fullFile) return mergedTwoHunkLines;
        if (hunkLoads++ == 1) {
          throw const GitRepositoryException('/repo', 'hunk return failed');
        }
        return twoHunkLines;
      });
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [_workingTreeCommit],
      initialIndex: 0,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);
    await controller.setScope(DiffScope.fullFile);
    final preservedTarget = controller.state.fullFileScrollTarget;

    await expectLater(
      controller.setScope(DiffScope.hunks),
      throwsA(isA<GitRepositoryException>()),
    );

    expect(controller.state.requestedScope, DiffScope.fullFile);
    expect(controller.state.appliedScope, DiffScope.fullFile);
    expect(controller.state.fullFileScrollTarget, preservedTarget);

    await controller.setScope(DiffScope.hunks);

    expect(controller.state.appliedScope, DiffScope.hunks);
    expect(controller.state.activeAnchor?.hunkIndex, 1);
    expect(controller.state.activeAnchor?.newLine, 21);
    expect(controller.state.fullFileScrollTarget, isNull);
  });

  test(
    'stale failed hunk return cannot restore its full-file target',
    () async {
      final failedHunkReturn = Completer<List<DiffLine>>();
      var hunkLoads = 0;
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('current\n')))
        ..scopedDiff = ((_, _, _, _, _, scope) {
          if (scope == DiffScope.fullFile) {
            return Future.value(mergedTwoHunkLines);
          }
          if (hunkLoads++ == 0) return Future.value(twoHunkLines);
          return failedHunkReturn.future;
        });
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [_workingTreeCommit],
        initialIndex: 0,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);
      await controller.setScope(DiffScope.fullFile);

      final loading = controller.setScope(DiffScope.hunks);
      await Future<void>.delayed(Duration.zero);
      controller.setView(FullDiffView.blame);
      failedHunkReturn.completeError(
        const GitRepositoryException('/repo', 'late hunk failure'),
      );
      await expectLater(loading, throwsA(isA<GitRepositoryException>()));

      expect(controller.state.view, FullDiffView.blame);
      expect(controller.state.requestedScope, DiffScope.fullFile);
      expect(controller.state.appliedScope, DiffScope.fullFile);
      expect(controller.state.fullFileScrollTarget, isNull);
    },
  );

  test('empty accepted full-file document never publishes a target', () async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('current\n')))
      ..scopedDiff = ((_, _, _, _, _, scope) async =>
          scope == DiffScope.hunks ? twoHunkLines : const <DiffLine>[]);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);

    await controller.setScope(DiffScope.fullFile);

    expect(controller.state.patch.data?.hunks, isEmpty);
    expect(controller.state.patch.data?.rows, isEmpty);
    expect(controller.state.fullFileScrollTarget, isNull);
    controller
      ..setView(FullDiffView.blame)
      ..setView(FullDiffView.diff);
    expect(controller.state.fullFileScrollTarget, isNull);
    await controller.setScope(DiffScope.hunks);
    expect(controller.state.fullFileScrollTarget, isNull);
  });

  test(
    'unresolvable accepted full-file document never publishes a target',
    () async {
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('current\n')))
        ..scopedDiff = ((_, _, _, _, _, scope) async => scope == DiffScope.hunks
            ? twoHunkLines
            : const [
                DiffLine(
                  kind: DiffLineKind.hunk,
                  text: '@@ -30 +30 @@ unrelated',
                ),
                DiffLine(
                  kind: DiffLineKind.delete,
                  text: 'unrelated old',
                  oldNumber: 30,
                ),
                DiffLine(
                  kind: DiffLineKind.add,
                  text: 'unrelated result',
                  newNumber: 30,
                ),
              ]);
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);

      await controller.setScope(DiffScope.fullFile);

      expect(controller.state.activeAnchor?.newLine, 30);
      expect(controller.state.fullFileScrollTarget, isNull);
      controller.setLayout(DiffLayout.sideBySide);
      expect(controller.state.fullFileScrollTarget, isNull);
      await controller.setScope(DiffScope.hunks);
      expect(controller.state.fullFileScrollTarget, isNull);
    },
  );

  test('late full-file target cannot override newer hunk navigation', () async {
    final fixture = await delayedFullFileController();
    final controller = fixture.controller;
    addTearDown(controller.dispose);
    controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);

    final loading = controller.setScope(DiffScope.fullFile);
    await Future<void>.delayed(Duration.zero);
    controller.selectAnchor(controller.state.patch.data!.hunks.first.anchor);
    fixture.fullFilePatch.complete(mergedTwoHunkLines);
    await loading;

    expect(controller.state.appliedScope, DiffScope.fullFile);
    expect(controller.state.fullFileScrollTarget, isNull);
  });

  test('late full-file target cannot survive a view change', () async {
    final fixture = await delayedFullFileController();
    final controller = fixture.controller;
    addTearDown(controller.dispose);
    controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);

    final loading = controller.setScope(DiffScope.fullFile);
    await Future<void>.delayed(Duration.zero);
    controller.setView(FullDiffView.blame);
    fixture.fullFilePatch.complete(mergedTwoHunkLines);
    await loading;

    expect(controller.state.view, FullDiffView.blame);
    expect(controller.state.appliedScope, DiffScope.fullFile);
    expect(controller.state.fullFileScrollTarget, isNull);
  });

  test('late full-file target cannot survive a return to hunk scope', () async {
    final fixture = await delayedFullFileController();
    final controller = fixture.controller;
    addTearDown(controller.dispose);
    controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);

    final staleLoading = controller.setScope(DiffScope.fullFile);
    await Future<void>.delayed(Duration.zero);
    await controller.setScope(DiffScope.hunks);
    fixture.fullFilePatch.complete(mergedTwoHunkLines);
    await staleLoading;

    expect(controller.state.requestedScope, DiffScope.hunks);
    expect(controller.state.appliedScope, DiffScope.hunks);
    expect(controller.state.fullFileScrollTarget, isNull);
  });

  for (final reload in [
    (
      name: 'algorithm reload',
      start: (FullDiffSessionController controller) =>
          controller.selectAlgorithm(DiffAlgorithm.histogram),
    ),
    (
      name: 'whitespace reload',
      start: (FullDiffSessionController controller) =>
          controller.setIgnoreWhitespace(true),
    ),
  ]) {
    test(
      '${reload.name} clears an existing full-file target at start',
      () async {
        final reloadPatch = Completer<List<DiffLine>>();
        final repository = FakeFullDiffRepository()
          ..files = ((_, _) async => const [fileA])
          ..content = ((_, _, _) async =>
              Uint8List.fromList(utf8.encode('current\n')))
          ..scopedDiff = ((_, _, _, algorithm, whitespace, scope) {
            if (scope == DiffScope.hunks) return Future.value(twoHunkLines);
            if (algorithm == DiffAlgorithm.gitSetting && !whitespace) {
              return Future.value(mergedTwoHunkLines);
            }
            return reloadPatch.future;
          });
        final controller = FullDiffSessionController(
          repository: repository,
          commits: const [commitA],
          initialIndex: 0,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);
        await controller.setScope(DiffScope.fullFile);
        expect(controller.state.fullFileScrollTarget, isNotNull);

        final loading = reload.start(controller);

        expect(controller.state.patch.loading, isTrue);
        expect(controller.state.fullFileScrollTarget, isNull);
        reloadPatch.complete(mergedTwoHunkLines);
        await loading;
        expect(controller.state.fullFileScrollTarget, isNull);
      },
    );
  }

  test('scope selection without a file does not leave patch loading', () async {
    final controller = FullDiffSessionController(
      repository: FakeFullDiffRepository(),
      commits: const [commitA],
      initialIndex: 0,
    );
    addTearDown(controller.dispose);

    await controller.setScope(DiffScope.fullFile);

    expect(controller.state.requestedScope, DiffScope.fullFile);
    expect(controller.state.appliedScope, DiffScope.hunks);
    expect(controller.state.patch.loading, isFalse);
  });

  test('hunk and full-file patches use separate cache entries', () async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..scopedDiff = ((_, _, _, _, _, scope) async => twoHunkLines)
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('current\n')));
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
      initialPreferences: const FullDiffPreferences(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.setScope(DiffScope.fullFile);
    await controller.setScope(DiffScope.hunks);

    expect(repository.diffRequests.map((request) => request.scope), [
      DiffScope.hunks,
      DiffScope.fullFile,
    ]);
  });

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
    'history selection skips unrelated files with absent old paths',
    () async {
      const unrelatedFile = GitFileChange(
        path: 'src/unrelated.pas',
        status: 'M',
        additions: 1,
        deletions: 1,
      );
      final repository = FakeFullDiffRepository()
        ..files = ((commit, _) async => commit.sha == commitA.sha
            ? const [fileA]
            : const [unrelatedFile, fileA])
        ..diff = ((_, _, _, _, _) async => twoHunkLines)
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('content\n')))
        ..history = ((_, _) async => const [
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
      );
      await controller.initialize();
      controller.setView(FullDiffView.history);
      await Future<void>.delayed(Duration.zero);

      await controller.selectHistoryEntry(
        controller.state.history.data!.single,
      );

      expect(controller.state.selectedFile, same(fileA));
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
    );
    await controller.initialize();
    controller.setView(FullDiffView.history);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.history.loading, isTrue);

    controller.setHistorySelected(false);
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

  test(
    'patch retry recovers an unmatched history row without replacing its context',
    () async {
      var patchLoads = 0;
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..diff = ((_, _, _, _, _) async {
          patchLoads++;
          if (patchLoads == 1) {
            throw const GitRepositoryException('/repo', 'patch failed');
          }
          return twoHunkLines;
        })
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('current\n')))
        ..history = ((_, _) async => const [
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
      );
      await controller.initialize();
      controller.setView(FullDiffView.history);
      await Future<void>.delayed(Duration.zero);
      final originalHistory = controller.state.history.data!;
      final originalContext = controller.state.historyContext;

      expect(controller.state.selectedHistoryEntry, isNull);
      expect(controller.state.patch.error, isA<GitRepositoryException>());

      await controller.retryPatch();

      expect(patchLoads, 2);
      expect(controller.state.patch.data, isNotNull);
      expect(controller.state.history.data, same(originalHistory));
      expect(controller.state.historyContext, originalContext);
      expect(controller.state.selectedHistoryEntry, isNull);
    },
  );

  test(
    'files retry targets the selected historical context and preserves its list',
    () async {
      var historicalFileLoads = 0;
      final repository = FakeFullDiffRepository()
        ..files = ((commit, _) async {
          if (commit.sha == commitA.sha) return const [fileA];
          historicalFileLoads++;
          if (historicalFileLoads == 1) {
            throw const GitRepositoryException(
              '/repo',
              'historical files failed',
            );
          }
          return const [fileA];
        })
        ..diff = ((_, _, _, _, _) async => twoHunkLines)
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('historical\n')))
        ..history = ((_, _) async => const [
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
      );
      await controller.initialize();
      controller.setView(FullDiffView.history);
      await Future<void>.delayed(Duration.zero);
      final originalHistory = controller.state.history.data!;
      final originalContext = controller.state.historyContext;
      final selectedEntry = originalHistory.single;

      await controller.selectHistoryEntry(selectedEntry);
      expect(
        controller.state.filesResource.error,
        isA<GitRepositoryException>(),
      );

      await controller.retryFiles();

      expect(historicalFileLoads, 2);
      expect(controller.state.selectedFile, fileA);
      expect(controller.state.patch.data, isNotNull);
      expect(controller.state.history.data, same(originalHistory));
      expect(controller.state.historyContext, originalContext);
      expect(controller.state.selectedHistoryEntry, same(selectedEntry));
    },
  );

  test('file retry reloads only the selected historical resource', () async {
    var historicalContentLoads = 0;
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((commit, _, _) async {
        if (commit.sha == commitA.sha) {
          return Uint8List.fromList(utf8.encode('current\n'));
        }
        historicalContentLoads++;
        if (historicalContentLoads == 1) {
          throw const GitRepositoryException(
            '/repo',
            'historical content failed',
          );
        }
        return Uint8List.fromList(utf8.encode('recovered\n'));
      })
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
    );
    await controller.initialize();
    controller.setView(FullDiffView.history);
    await Future<void>.delayed(Duration.zero);
    final originalHistory = controller.state.history.data!;
    final originalContext = controller.state.historyContext;
    final selectedEntry = originalHistory.last;

    await controller.selectHistoryEntry(selectedEntry);
    final patchRequests = repository.diffRequests.length;
    expect(controller.state.file.error, isA<GitRepositoryException>());

    await controller.retryFile();

    expect(historicalContentLoads, 2);
    expect(repository.diffRequests, hasLength(patchRequests));
    expect(controller.state.file.data?.lines, ['recovered']);
    expect(controller.state.history.data, same(originalHistory));
    expect(controller.state.historyContext, originalContext);
    expect(controller.state.selectedHistoryEntry, same(selectedEntry));
  });

  test('Diff restores the History selection kept behind Blame', () async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) async => resultFile.bytes)
      ..history = ((_, _) async => const []);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
      initialPreferences: const FullDiffPreferences(
        view: FullDiffView.blame,
        historySelected: true,
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(controller.state.view, FullDiffView.blame);
    expect(controller.state.primaryView, FullDiffView.blame);
    expect(controller.state.historySelected, isTrue);

    controller.setPrimaryView(FullDiffView.diff);

    expect(controller.state.view, FullDiffView.history);
    expect(controller.state.primaryView, FullDiffView.diff);
  });

  test('Diff stays in regular diff when remembered History is off', () async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) async => resultFile.bytes);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    controller.setPrimaryView(FullDiffView.blame);
    controller.setPrimaryView(FullDiffView.diff);

    expect(controller.state.view, FullDiffView.diff);
    expect(controller.state.historySelected, isFalse);
  });

  test('History selection persists while Blame is active', () async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) async => resultFile.bytes)
      ..history = ((_, _) async => const []);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    controller.setHistorySelected(true);
    controller.setPrimaryView(FullDiffView.blame);

    expect(controller.state.view, FullDiffView.blame);
    expect(controller.state.historySelected, isTrue);
    expect(controller.state.preferences.historySelected, isTrue);

    controller.setHistorySelected(false);
    expect(controller.state.view, FullDiffView.diff);
    expect(controller.state.historySelected, isFalse);
  });

  test(
    'new repository keeps display preferences but starts with its own file',
    () async {
      const newFile = GitFileChange(
        path: 'lib/new_repository.dart',
        status: 'M',
        additions: 1,
        deletions: 0,
      );
      final repository = FakeFullDiffRepository(root: '/second')
        ..files = ((_, _) async => const [newFile])
        ..scopedDiff = ((_, _, _, _, _, _) async => twoHunkLines)
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('new repository\n')));
      const preferences = FullDiffPreferences(
        view: FullDiffView.history,
        layout: DiffLayout.sideBySide,
        scope: DiffScope.hunks,
        algorithm: DiffAlgorithm.patience,
        ignoreWhitespace: true,
        wrapLines: false,
      );
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
        initialPreferences: preferences,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.state.selectedFile, newFile);
      expect(controller.state.preferences, preferences);
    },
  );
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

const _workingTreeCommit = GitCommit(
  sha: '',
  shortSha: '',
  parents: ['head'],
  author: fixtureIdentity,
  authorTimestamp: 1720573200,
  committer: fixtureIdentity,
  committerTimestamp: 1720573200,
  refs: [],
  subject: 'Working tree',
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
