import 'dart:async';
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
import 'package:yogit/full_diff_theme.dart';
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

class _CompletingEditorService extends ExternalEditorService {
  _CompletingEditorService(this.completer) : super(repositoryRoot: '/unused');

  final Completer<void> completer;

  @override
  Future<void> open({required String relativePath, int? line}) =>
      completer.future;
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
    bool routeBacked = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    Widget diffScreen() => DiffScreen(
      repository: controller.repository,
      commits: controller.state.nearbyCommits,
      initialIndex: 0,
      initialView: FullDiffInitialView.hunk,
      controller: controller,
      editorService: editorService,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: routeBacked
            ? Builder(
                builder: (context) => Center(
                  child: TextButton(
                    key: const Key('launch-full-diff'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => diffScreen()),
                    ),
                    child: const Text('Timeline'),
                  ),
                ),
              )
            : diffScreen(),
      ),
    );
    if (routeBacked) {
      await tester.tap(find.byKey(const Key('launch-full-diff')));
    }
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

  InkWell editorButton(WidgetTester tester) => tester.widget<InkWell>(
    find.ancestor(
      of: find.byKey(const Key('open-editor')),
      matching: find.byType(InkWell),
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

  testWidgets('the 480px toolbar uses the compact algorithm label', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await fixture.controller.selectAlgorithm(DiffAlgorithm.histogram);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(480, 560),
    );

    expect(find.text('Histogram'), findsOneWidget);
    expect(find.textContaining('diff 알고리즘 ·'), findsNothing);
    expect(find.semantics.byLabel('diff 알고리즘: Histogram'), findsOneWidget);
  });

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

  testWidgets(
    'history keeps the current row neutral and semantically selected',
    (tester) async {
      final fixture = await workspaceFixture();
      addTearDown(fixture.controller.dispose);
      fixture.controller.setView(FullDiffView.history);
      await pumpWorkspace(
        tester,
        controller: fixture.controller,
        size: const Size(1070, 842),
      );
      final semantics = tester.ensureSemantics();
      final row = find.byKey(Key('history-row-${commitA.sha}'));

      expect(tester.widget<ColoredBox>(row).color, fullDiffCanvas);
      final selectedSemantics = find.ancestor(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      );
      expect(selectedSemantics, findsOneWidget);
      expect(
        tester.getSemantics(selectedSemantics).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(of: row, matching: find.text(commitA.subject)),
            )
            .style
            ?.fontSize,
        11,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: row,
                matching: find.textContaining(commitA.shortSha),
              ),
            )
            .style
            ?.fontSize,
        10,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: row,
                matching: find.text(fixtureIdentity.name),
              ),
            )
            .style
            ?.fontSize,
        10,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(of: row, matching: find.textContaining('ago')),
            )
            .style
            ?.fontSize,
        10,
      );

      semantics.dispose();
    },
  );

  testWidgets('uses compact typography in commit and file lists', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(600, 842),
    );

    expect(tester.widget<Text>(find.text(commitA.subject)).style?.fontSize, 11);
    expect(
      tester
          .widget<Text>(find.textContaining(commitA.shortSha).first)
          .style
          ?.fontSize,
      10,
    );
    final fileList = find.byKey(const Key('changed-files-list'));
    expect(
      tester
          .widget<Text>(
            find.descendant(of: fileList, matching: find.text(fileA.path)),
          )
          .style
          ?.fontSize,
      11,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: fileList, matching: find.text('+12 −4')),
          )
          .style
          ?.fontSize,
      10,
    );
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
  });

  testWidgets(
    'escape returns from focus mode and lets an open menu close first',
    (tester) async {
      final fixture = await workspaceFixture();
      addTearDown(fixture.controller.dispose);
      fixture.controller.setFocusMode(true);
      await pumpWorkspace(
        tester,
        controller: fixture.controller,
        size: const Size(1070, 842),
        routeBacked: true,
      );

      await sendChord(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('launch-full-diff')), findsOneWidget);
      expect(fixture.controller.state.focusMode, isTrue);

      await tester.tap(find.byKey(const Key('launch-full-diff')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('diff-algorithm')));
      await tester.pumpAndSettle();
      expect(find.text('Histogram'), findsOneWidget);

      await sendChord(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Histogram'), findsNothing);
      expect(find.byKey(const Key('content-scrollable')), findsOneWidget);

      await sendChord(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('launch-full-diff')), findsOneWidget);
    },
  );

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

  final tooManyLines = Uint8List((fullDiffTextLineLimit + 1) * 2);
  for (var index = 0; index < tooManyLines.length; index += 2) {
    tooManyLines[index] = 0x78;
    tooManyLines[index + 1] = 0x0A;
  }
  for (final scenario in [
    (label: 'binary', bytes: Uint8List.fromList([0x00, 0x01])),
    (label: 'too-large', bytes: tooManyLines),
  ]) {
    testWidgets(
      '${scenario.label} file minimap falls back to patch-side coordinates',
      (tester) async {
        final repository = FakeFullDiffRepository()
          ..files = ((_, _) async => const [fileA])
          ..diff = ((_, _, _, _, _) async => const [
            DiffLine(
              kind: DiffLineKind.hunk,
              text: '@@ -10,2 +300,5 @@ fallback',
            ),
            DiffLine(
              kind: DiffLineKind.context,
              text: 'line',
              oldNumber: 10,
              newNumber: 300,
            ),
          ])
          ..content = ((_, _, _) async => scenario.bytes);
        final controller = FullDiffSessionController(
          repository: repository,
          commits: const [commitA],
          initialIndex: 0,
          initialView: FullDiffInitialView.hunk,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await pumpWorkspace(
          tester,
          controller: controller,
          size: const Size(1070, 650),
        );

        final minimap = tester.widget<FullDiffMinimap>(
          find.byType(FullDiffMinimap),
        );
        expect(controller.state.file.data?.lines, isEmpty);
        expect(minimap.sourceSide, FileDocumentSide.result);
        expect(minimap.sourceLineCount, 304);
      },
    );
  }

  testWidgets('file load errors stay distinct from an empty successful load', (
    tester,
  ) async {
    var attempt = 0;
    final repository = FakeFullDiffRepository();
    repository.files = (_, _) async {
      if (attempt++ == 0) throw StateError('files failed');
      return const [];
    };
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
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

    expect(find.byKey(const Key('files-error')), findsOneWidget);
    expect(find.textContaining('files failed'), findsOneWidget);
    expect(find.byKey(const Key('files-empty')), findsNothing);

    await tester.tap(find.byKey(const Key('files-retry')));
    await tester.pumpAndSettle();

    expect(repository.fileRequests, hasLength(2));
    expect(find.byKey(const Key('files-error')), findsNothing);
    expect(find.byKey(const Key('files-empty')), findsOneWidget);
  });

  for (final view in [FullDiffView.file, FullDiffView.blame]) {
    testWidgets('manual ${view.name} scroll synchronizes the active hunk', (
      tester,
    ) async {
      final lines = <DiffLine>[
        const DiffLine(kind: DiffLineKind.hunk, text: '@@ -5 +5 @@ first'),
        const DiffLine(
          kind: DiffLineKind.delete,
          text: 'old first',
          oldNumber: 5,
        ),
        const DiffLine(kind: DiffLineKind.add, text: 'new first', newNumber: 5),
        const DiffLine(kind: DiffLineKind.hunk, text: '@@ -100 +100 @@ second'),
        const DiffLine(
          kind: DiffLineKind.delete,
          text: 'old second',
          oldNumber: 100,
        ),
        const DiffLine(
          kind: DiffLineKind.add,
          text: 'new second',
          newNumber: 100,
        ),
      ];
      final bytes = Uint8List.fromList(
        utf8.encode(
          '${[for (var line = 1; line <= 130; line++) 'line $line'].join('\n')}\n',
        ),
      );
      final repository = FakeFullDiffRepository();
      repository.files = (_, _) async => const [fileA];
      repository.diff = (_, _, _, _, _) async => lines;
      repository.content = (_, _, _) async => bytes;
      repository.blame = (_, _, _, _) async => [
        for (var line = 1; line <= 130; line++)
          GitBlameLine(
            lineNumber: line,
            sha: commitA.sha,
            author: fixtureIdentity.name,
            uncommitted: false,
          ),
      ];
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setView(view);
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1070, 650),
      );
      final listKey = view == FullDiffView.file
          ? const Key('file-list')
          : const Key('blame-list');
      final scrollable = find
          .descendant(
            of: find.byKey(listKey),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;

      while (position.pixels < position.maxScrollExtent - 0.5) {
        await tester.drag(scrollable, const Offset(0, -240));
        await tester.pump();
      }

      expect(controller.state.activeAnchor?.hunkIndex, 1);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(
        tester
            .widget<FullDiffMinimap>(find.byType(FullDiffMinimap))
            .activeAnchor
            ?.hunkIndex,
        1,
      );
    });
  }

  testWidgets('a deletion-only hunk opens its result-side boundary line', (
    tester,
  ) async {
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
    final lines = <DiffLine>[
      const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@ first'),
      const DiffLine(
        kind: DiffLineKind.delete,
        text: 'old first',
        oldNumber: 1,
      ),
      const DiffLine(kind: DiffLineKind.add, text: 'new first', newNumber: 1),
      const DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,2 +10 @@ middle'),
      const DiffLine(
        kind: DiffLineKind.context,
        text: 'kept',
        oldNumber: 10,
        newNumber: 10,
      ),
      const DiffLine(kind: DiffLineKind.delete, text: 'removed', oldNumber: 11),
      const DiffLine(kind: DiffLineKind.hunk, text: '@@ -20 +19 @@ last'),
      const DiffLine(
        kind: DiffLineKind.delete,
        text: 'old last',
        oldNumber: 20,
      ),
      const DiffLine(kind: DiffLineKind.add, text: 'new last', newNumber: 19),
    ];
    final repository = FakeFullDiffRepository();
    repository.files = (_, _) async => const [fileA];
    repository.diff = (_, _, _, _, _) async => lines;
    repository.content = (_, _, _) async => resultFile.bytes;
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [workingTree],
      initialIndex: 0,
      initialView: FullDiffInitialView.hunk,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.selectAnchor(controller.state.patch.data!.hunks[1].anchor);
    final editorService = _RecordingEditorService();
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 842),
      editorService: editorService,
    );

    await tester.tap(find.byKey(const Key('open-editor')));
    await tester.pump();

    expect(editorService.line, 10);
  });

  testWidgets('a late editor failure cannot alter a replacement session', (
    tester,
  ) async {
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
    Future<FullDiffSessionController> controllerFor(String path) async {
      final file = GitFileChange(
        path: path,
        status: 'M',
        additions: 1,
        deletions: 1,
      );
      final repository = FakeFullDiffRepository();
      repository.files = (_, _) async => [file];
      repository.diff = (_, _, _, _, _) async => twoHunkLines;
      repository.content = (_, _, _) async => resultFile.bytes;
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [workingTree],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );
      await controller.initialize();
      return controller;
    }

    final first = await controllerFor('src/first.pas');
    final second = await controllerFor('src/second.pas');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final editorCompleter = Completer<void>();
    final editorService = _CompletingEditorService(editorCompleter);
    await pumpWorkspace(
      tester,
      controller: first,
      size: const Size(1070, 842),
      editorService: editorService,
    );
    await tester.tap(find.byKey(const Key('open-editor')));
    await tester.pump();
    expect(editorButton(tester).onTap, isNull);

    await pumpWorkspace(
      tester,
      controller: second,
      size: const Size(1070, 842),
      editorService: editorService,
    );
    expect(find.text('src/second.pas'), findsWidgets);
    expect(editorButton(tester).onTap, isNotNull);

    editorCompleter.completeError(StateError('late editor failed'));
    await tester.pump();
    await tester.pump();

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('open-editor')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, isNot(contains('late editor failed')));
    expect(editorButton(tester).onTap, isNotNull);
  });

  testWidgets(
    'a late editor failure cannot alter a new selection on the same controller',
    (tester) async {
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
      const secondFile = GitFileChange(
        path: 'src/second.pas',
        status: 'M',
        additions: 1,
        deletions: 1,
      );
      final secondPatch = Completer<List<DiffLine>>();
      final secondContent = Completer<Uint8List>();
      final repository = FakeFullDiffRepository();
      repository.files = (_, _) async => const [fileA, secondFile];
      repository.diff = (_, file, _, _, _) => file.path == fileA.path
          ? Future.value(twoHunkLines)
          : secondPatch.future;
      repository.content = (_, file, _) => file.path == fileA.path
          ? Future.value(resultFile.bytes)
          : secondContent.future;
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [workingTree],
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final editorCompleter = Completer<void>();
      final editorService = _CompletingEditorService(editorCompleter);
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1070, 842),
        editorService: editorService,
      );

      await tester.tap(find.byKey(const Key('open-editor')));
      await tester.pump();
      expect(editorButton(tester).onTap, isNull);

      unawaited(controller.selectFile(secondFile));
      await tester.pump();
      expect(controller.state.selectedFile, secondFile);
      expect(controller.state.patch.loading, isTrue);
      expect(controller.state.file.loading, isTrue);
      expect(find.byKey(const Key('diff-pending-first-diff')), findsOneWidget);

      editorCompleter.completeError(StateError('late editor failed'));
      await tester.pump();
      await tester.pump();

      expect(controller.state.patch.error, isNull);
      expect(controller.state.file.error, isNull);
      expect(controller.state.patch.loading, isTrue);
      expect(controller.state.file.loading, isTrue);
      expect(find.byKey(const Key('diff-pending-first-diff')), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const Key('open-editor')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, isNot(contains('late editor failed')));
      expect(editorButton(tester).onTap, isNull);

      secondPatch.complete(twoHunkLines);
      secondContent.complete(resultFile.bytes);
      await tester.pumpAndSettle();
    },
  );

  for (final presentation in [
    DiffPresentation.inline,
    DiffPresentation.split,
  ]) {
    testWidgets(
      '${presentation.name} keeps viewport anchors stable across long wrapped hunks',
      (tester) async {
        final lines = <DiffLine>[
          const DiffLine(
            kind: DiffLineKind.hunk,
            text: '@@ -1,161 +1,161 @@ long first hunk',
          ),
          for (var row = 0; row < 160; row++)
            DiffLine(
              kind: DiffLineKind.context,
              text:
                  'long first hunk context $row '
                  '${row.isEven ? 'wrapped segment ' * 12 : ''}',
              oldNumber: row + 1,
              newNumber: row + 1,
            ),
          const DiffLine(
            kind: DiffLineKind.add,
            text: 'long first hunk changed',
            newNumber: 161,
          ),
          const DiffLine(
            kind: DiffLineKind.hunk,
            text: '@@ -200,161 +200,161 @@ distant target',
          ),
          for (var row = 0; row < 160; row++)
            DiffLine(
              kind: DiffLineKind.context,
              text:
                  'distant context $row '
                  '${row.isOdd ? 'wrapped segment ' * 12 : ''}',
              oldNumber: 200 + row,
              newNumber: 200 + row,
            ),
          const DiffLine(
            kind: DiffLineKind.delete,
            text: 'distant old',
            oldNumber: 360,
          ),
          const DiffLine(
            kind: DiffLineKind.add,
            text: 'distant new',
            newNumber: 360,
          ),
        ];
        final repository = FakeFullDiffRepository();
        repository.files = (_, _) async => const [fileA];
        repository.diff = (_, _, _, _, _) async => lines;
        repository.content = (_, _, _) async => resultFile.bytes;
        final controller = FullDiffSessionController(
          repository: repository,
          commits: const [commitA],
          initialIndex: 0,
          initialView: FullDiffInitialView.hunk,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        controller.setPresentation(presentation);
        await pumpWorkspace(
          tester,
          controller: controller,
          size: const Size(1070, 650),
        );
        final target = controller.state.patch.data!.hunks.last.anchor;
        final targetFinder = find.byKey(
          Key(
            presentation == DiffPresentation.inline
                ? 'inline-hunk-1'
                : 'split-hunk-1',
          ),
        );
        final viewportRect = tester.getRect(
          find.byKey(const Key('content-scrollable')),
        );
        final firstRow = find.byKey(
          Key(
            presentation == DiffPresentation.inline
                ? 'inline-line-0-0'
                : 'split-row-0-0',
          ),
        );
        expect(tester.getRect(firstRow).height, greaterThan(27));
        expect(targetFinder, findsNothing);
        final scrollable = find
            .descendant(
              of: find.byKey(const Key('content-scrollable')),
              matching: find.byType(Scrollable),
            )
            .first;
        for (var viewport = 0; viewport < 3; viewport++) {
          await tester.drag(scrollable, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(controller.state.activeAnchor?.hunkIndex, 0);
        }

        controller.selectAnchor(target);
        await tester.pumpAndSettle();

        expect(controller.state.activeAnchor?.hunkIndex, 1);
        expect(targetFinder, findsOneWidget);
        final targetRect = tester.getRect(targetFinder);
        expect(targetRect.top, greaterThanOrEqualTo(viewportRect.top));
        expect(targetRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
        for (var viewport = 0; viewport < 2; viewport++) {
          await tester.drag(scrollable, const Offset(0, -240));
          await tester.pumpAndSettle();
          expect(controller.state.activeAnchor?.hunkIndex, 1);
        }
      },
    );
  }

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
      expect(editorButton(tester).onTap, isNull);

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
      const loadingFile = GitFileChange(
        path: 'src/loading.pas',
        status: 'M',
        additions: 1,
        deletions: 1,
      );
      final loadingPatch = Completer<List<DiffLine>>();
      final loadingContent = Completer<Uint8List>();
      final workingRepository = FakeFullDiffRepository();
      workingRepository.files = (_, _) async => const [fileA, loadingFile];
      workingRepository.diff = (_, file, _, _, _) =>
          file == fileA ? Future.value(twoHunkLines) : loadingPatch.future;
      workingRepository.content = (_, file, _) => file == fileA
          ? Future.value(resultFile.bytes)
          : loadingContent.future;
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
      expect(editorButton(tester).onTap, isNotNull);
      await tester.tap(find.byKey(const Key('open-editor')));
      await tester.pump();
      expect(editorService.relativePath, fileA.path);
      expect(editorService.line, twoHunkDocument.hunks.first.anchor.newLine);

      unawaited(workingController.selectFile(loadingFile));
      await tester.pump();
      expect(workingController.state.selectedFile, loadingFile);
      expect(workingController.state.file.loading, isTrue);
      expect(editorButton(tester).onTap, isNull);
      loadingPatch.complete(twoHunkLines);
      loadingContent.complete(resultFile.bytes);
      await tester.pumpAndSettle();

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
      expect(editorButton(tester).onTap, isNull);
    },
  );
}
