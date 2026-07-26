import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/diff_screen.dart';
import 'package:yogit/external_editor.dart';
import 'package:yogit/full_diff_controller.dart';
import 'package:yogit/full_diff_minimap.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/git.dart';

import 'support/full_diff_fixtures.dart';

class _RecordingEditorService extends ExternalEditorService {
  _RecordingEditorService() : super(repositoryRoot: '/unused');

  String? relativePath;
  int? line;

  @override
  Future<void> open({required String relativePath, int? line}) async {
    this.relativePath = relativePath;
    this.line = line;
  }
}

void main() {
  Future<
    ({FullDiffSessionController controller, FakeFullDiffRepository repository})
  >
  workspaceFixture() async {
    final repository = FakeFullDiffRepository();
    repository.files = (_, _) async => const [fileA];
    repository.diff = (_, _, _, _, _) async => twoHunkLines;
    repository.content = (_, _, _) async => resultFile.bytes;
    repository.blame = (_, _, _, _) async => [
      for (var index = 0; index < resultFile.lines.length; index++)
        GitBlameLine(
          lineNumber: index + 1,
          sha: commitA.sha,
          author: fixtureIdentity.name,
          uncommitted: false,
        ),
    ];
    repository.history = (_, _) async => [
      for (final entry in historyEntries)
        GitFileHistoryRecord(
          commit: entry.commit,
          path: entry.path,
          oldPath: entry.oldPath,
          status: entry.status,
        ),
    ];
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
      initialView: FullDiffInitialView.hunk,
    );
    await controller.initialize();
    return (controller: controller, repository: repository);
  }

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    required FullDiffSessionController controller,
    required Size size,
    ExternalEditorService? editorService,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: DiffScreen(
          repository: controller.repository,
          commits: controller.state.nearbyCommits,
          initialIndex: 0,
          initialView: FullDiffInitialView.hunk,
          controller: controller,
          editorService: editorService,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> sendChord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool meta = false,
    bool alt = false,
    bool shift = false,
  }) async {
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }

  TextButton editorButton(WidgetTester tester) => tester.widget<TextButton>(
    find.descendant(
      of: find.byKey(const Key('open-editor')),
      matching: find.byType(TextButton),
    ),
  );

  testWidgets('keeps presentation and anchor while switching main views', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    final controller = fixture.controller
      ..setView(FullDiffView.diff)
      ..setPresentation(DiffPresentation.hunk)
      ..selectAnchor(twoHunkDocument.hunks[1].anchor);
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 842),
    );

    await tester.tap(find.text('Split'));
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blame'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diff'));
    await tester.pumpAndSettle();

    expect(controller.state.presentation, DiffPresentation.split);
    expect(controller.state.activeAnchor?.hunkIndex, 1);
    expect(fixture.repository.diffRequests, hasLength(1));
  });

  test(
    'navigation boundaries and scroll synchronization do not bounce',
    () async {
      final fixture = await workspaceFixture();
      addTearDown(fixture.controller.dispose);
      final controller = fixture.controller;
      controller.selectAnchor(twoHunkDocument.hunks.last.anchor);
      final lastSerial = controller.state.navigationSerial;
      controller.stepAnchor(1);
      expect(
        controller.state.activeAnchor?.id,
        twoHunkDocument.hunks.last.anchor.id,
      );
      expect(controller.state.navigationSerial, lastSerial);

      controller.syncAnchorFromScroll(twoHunkDocument.hunks.first.anchor);
      expect(
        controller.state.activeAnchor?.id,
        twoHunkDocument.hunks.first.anchor.id,
      );
      expect(controller.state.navigationSerial, lastSerial);
      controller.stepAnchor(1);
      expect(
        controller.state.activeAnchor?.id,
        twoHunkDocument.hunks.last.anchor.id,
      );
      expect(controller.state.navigationSerial, lastSerial + 1);
    },
  );

  test(
    'parent 2 reaches files patch and content without resetting views',
    () async {
      const merge = GitCommit(
        sha: 'merge-sha',
        shortSha: 'merge12',
        parents: ['parent-1', 'parent-2'],
        author: fixtureIdentity,
        authorTimestamp: 1720573300,
        committer: fixtureIdentity,
        committerTimestamp: 1720573300,
        refs: [],
        subject: 'merge',
      );
      final repository = FakeFullDiffRepository();
      repository.files = (_, _) async => const [fileA];
      repository.diff = (_, _, _, _, _) async => twoHunkLines;
      repository.content = (_, _, _) async =>
          Uint8List.fromList(utf8.encode('current\n'));
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [merge],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..setView(FullDiffView.file)
        ..setPresentation(DiffPresentation.split);

      await controller.selectParent('parent-2');

      expect(repository.fileRequests.last.parent, 'parent-2');
      expect(repository.diffRequests.last.parent, 'parent-2');
      expect(repository.contentRequests.last.parent, 'parent-2');
      expect(controller.state.view, FullDiffView.file);
      expect(controller.state.presentation, DiffPresentation.split);
    },
  );

  for (final scenario in [
    (width: 651.0, commits: true, files: true, oldSplit: true),
    (width: 650.0, commits: false, files: true, oldSplit: true),
    (width: 481.0, commits: false, files: true, oldSplit: true),
    (width: 480.0, commits: false, files: false, oldSplit: false),
  ]) {
    testWidgets('responsive width ${scenario.width}', (tester) async {
      final fixture = await workspaceFixture();
      addTearDown(fixture.controller.dispose);
      fixture.controller.setPresentation(DiffPresentation.split);
      await pumpWorkspace(
        tester,
        controller: fixture.controller,
        size: Size(scenario.width, 549),
      );
      expect(
        find.byKey(const Key('nearby-commits-pane')),
        scenario.commits ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('commit-files-pane')),
        scenario.files ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('split-old-pane')),
        scenario.oldSplit ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('focus mode restores pane widths and selection', (tester) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );
    final commitWidth = tester
        .getSize(find.byKey(const Key('nearby-commits-pane')))
        .width;
    final fileWidth = tester
        .getSize(find.byKey(const Key('commit-files-pane')))
        .width;
    final commit = fixture.controller.state.selectedCommit;
    final file = fixture.controller.state.selectedFile;

    await tester.tap(find.text('집중 모드'));
    await tester.pump();
    expect(find.byKey(const Key('nearby-commits-pane')), findsNothing);
    expect(find.byKey(const Key('commit-files-pane')), findsNothing);
    expect(find.text('탐색 패널'), findsOneWidget);

    await tester.tap(find.text('탐색 패널'));
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('nearby-commits-pane'))).width,
      commitWidth,
    );
    expect(
      tester.getSize(find.byKey(const Key('commit-files-pane'))).width,
      fileWidth,
    );
    expect(fixture.controller.state.selectedCommit, same(commit));
    expect(fixture.controller.state.selectedFile, same(file));
  });

  testWidgets('selected rows and source state are not color-only', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.byKey(Key('selected-file-${fileA.path}')))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    semantics.dispose();
    expect(find.text('+'), findsWidgets);
    expect(find.text('−'), findsWidgets);
    expect(find.byKey(const Key('code-row-current-marker')), findsOneWidget);
  });

  testWidgets('parent chooser changes all selected resources', (tester) async {
    const merge = GitCommit(
      sha: 'merge-sha',
      shortSha: 'merge12',
      parents: ['parent-1', 'parent-2'],
      author: fixtureIdentity,
      authorTimestamp: 1720573300,
      committer: fixtureIdentity,
      committerTimestamp: 1720573300,
      refs: [],
      subject: 'merge',
    );
    final repository = FakeFullDiffRepository();
    repository.files = (_, _) async => const [fileA];
    repository.diff = (_, _, _, _, _) async => twoHunkLines;
    repository.content = (_, _, _) async => resultFile.bytes;
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [merge],
      initialIndex: 0,
      initialView: FullDiffInitialView.hunk,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 842),
    );

    await tester.tap(find.byKey(const Key('merge-parent-chooser')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parent 2 · parent-').last);
    await tester.pumpAndSettle();

    expect(controller.state.parent, 'parent-2');
    expect(repository.fileRequests.last.parent, 'parent-2');
    expect(repository.diffRequests.last.parent, 'parent-2');
    expect(repository.contentRequests.last.parent, 'parent-2');
  });

  testWidgets('navigation and focus shortcuts update only their target', (
    tester,
  ) async {
    const fileB = GitFileChange(
      path: 'src/window.pas',
      status: 'M',
      additions: 1,
      deletions: 1,
    );
    final repository = FakeFullDiffRepository();
    repository.files = (_, _) async => const [fileA, fileB];
    repository.diff = (_, _, _, _, _) async => twoHunkLines;
    repository.content = (_, _, _) async => resultFile.bytes;
    final controller = FullDiffSessionController(
      repository: repository,
      commits: [commitA, historyEntries[1].commit],
      initialIndex: 0,
      initialView: FullDiffInitialView.hunk,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 842),
    );

    await sendChord(tester, LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.state.selectedFile, fileB);
    await sendChord(tester, LogicalKeyboardKey.arrowDown, meta: true);
    await tester.pumpAndSettle();
    expect(controller.state.selectedCommit, historyEntries[1].commit);
    await sendChord(tester, LogicalKeyboardKey.arrowDown, alt: true);
    await tester.pumpAndSettle();
    expect(controller.state.activeAnchor?.hunkIndex, 1);
    await sendChord(tester, LogicalKeyboardKey.keyF, meta: true, shift: true);
    expect(controller.state.focusMode, isTrue);
    await sendChord(tester, LogicalKeyboardKey.escape);
    expect(controller.state.focusMode, isFalse);
  });

  testWidgets('page scroll moves 48px and an open menu consumes its keys', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    fixture.controller.setView(FullDiffView.file);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 549),
    );
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('content-scrollable')),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final before = position.pixels;
    await sendChord(
      tester,
      LogicalKeyboardKey.arrowDown,
      meta: true,
      shift: true,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(position.pixels, closeTo(before + 48, 0.5));

    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pumpAndSettle();
    final menuPosition = position.pixels;
    await sendChord(
      tester,
      LogicalKeyboardKey.arrowDown,
      meta: true,
      shift: true,
    );
    expect(position.pixels, menuPosition);
  });

  testWidgets('minimap receives the active diff presentation', (tester) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    fixture.controller.setPresentation(DiffPresentation.split);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );

    expect(
      tester.widget<FullDiffMinimap>(find.byType(FullDiffMinimap)).presentation,
      DiffPresentation.split,
    );
  });

  testWidgets(
    'external editor stays blocked outside an existing worktree file',
    (tester) async {
      final committed = await workspaceFixture();
      addTearDown(committed.controller.dispose);
      await pumpWorkspace(
        tester,
        controller: committed.controller,
        size: const Size(1070, 842),
      );
      expect(editorButton(tester).onPressed, isNull);

      const workingTree = GitCommit(
        sha: '',
        shortSha: '',
        parents: ['HEAD'],
        author: fixtureIdentity,
        authorTimestamp: 1720573300,
        committer: fixtureIdentity,
        committerTimestamp: 1720573300,
        refs: [],
        subject: 'working tree',
      );
      final workingRepository = FakeFullDiffRepository();
      workingRepository.files = (_, _) async => const [fileA];
      workingRepository.diff = (_, _, _, _, _) async => twoHunkLines;
      workingRepository.content = (_, _, _) async => resultFile.bytes;
      final workingController = FullDiffSessionController(
        repository: workingRepository,
        commits: const [workingTree],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );
      addTearDown(workingController.dispose);
      await workingController.initialize();
      final editorService = _RecordingEditorService();
      await pumpWorkspace(
        tester,
        controller: workingController,
        size: const Size(1070, 842),
        editorService: editorService,
      );
      expect(editorButton(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('open-editor')));
      await tester.pump();
      expect(editorService.relativePath, fileA.path);
      expect(editorService.line, twoHunkDocument.hunks.first.anchor.newLine);

      final deletedRepository = FakeFullDiffRepository();
      deletedRepository.files = (_, _) async => const [
        GitFileChange(
          path: 'src/deleted.pas',
          status: 'D',
          additions: 0,
          deletions: 2,
        ),
      ];
      deletedRepository.diff = (_, _, _, _, _) async => twoHunkLines;
      deletedRepository.content = (_, _, _) async => resultFile.bytes;
      final deletedController = FullDiffSessionController(
        repository: deletedRepository,
        commits: const [workingTree],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );
      addTearDown(deletedController.dispose);
      await deletedController.initialize();
      await pumpWorkspace(
        tester,
        controller: deletedController,
        size: const Size(1070, 842),
      );
      expect(editorButton(tester).onPressed, isNull);
    },
  );
}
