import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/diff_screen.dart';
import 'package:yogit/external_editor.dart';
import 'package:yogit/full_diff_hunk_header.dart';
import 'package:yogit/full_diff_controller.dart';
import 'package:yogit/full_diff_minimap.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_selectable_row.dart';
import 'package:yogit/full_history_view.dart';
import 'package:yogit/full_history_workspace.dart';
import 'package:yogit/git.dart';

import 'support/full_diff_fixtures.dart';

const _sizedFile = GitFileChange(
  path: 'src/drlua.pas',
  status: 'M',
  additions: 12,
  deletions: 4,
  sizeBytes: 1536,
);

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

List<DiffLine> _distantFullFileLines() => [
  const DiffLine(
    kind: DiffLineKind.hunk,
    text: '@@ -1,240 +1,240 @@ merged full file',
  ),
  for (var line = 1; line <= 240; line++) ...[
    if (line == 120 || line == 200) ...[
      DiffLine(
        kind: DiffLineKind.delete,
        text: 'old source line $line',
        oldNumber: line,
      ),
      DiffLine(
        kind: DiffLineKind.add,
        text: 'source line $line',
        newNumber: line,
      ),
    ] else
      DiffLine(
        kind: DiffLineKind.context,
        text: 'source line $line',
        oldNumber: line,
        newNumber: line,
      ),
  ],
];

const _distantHunkLines = <DiffLine>[
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -120 +120 @@ first distant'),
  DiffLine(
    kind: DiffLineKind.delete,
    text: 'old source line 120',
    oldNumber: 120,
  ),
  DiffLine(kind: DiffLineKind.add, text: 'source line 120', newNumber: 120),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -200 +200 @@ second distant'),
  DiffLine(
    kind: DiffLineKind.delete,
    text: 'old source line 200',
    oldNumber: 200,
  ),
  DiffLine(kind: DiffLineKind.add, text: 'source line 200', newNumber: 200),
];

List<DiffLine> _nearFullFileLines() => [
  const DiffLine(
    kind: DiffLineKind.hunk,
    text: '@@ -1,24 +1,24 @@ merged full file',
  ),
  for (var line = 1; line <= 24; line++) ...[
    if (line == 1 || line == 3) ...[
      DiffLine(
        kind: DiffLineKind.delete,
        text: 'old source line $line',
        oldNumber: line,
      ),
      DiffLine(
        kind: DiffLineKind.add,
        text: 'source line $line',
        newNumber: line,
      ),
    ] else
      DiffLine(
        kind: DiffLineKind.context,
        text: 'source line $line',
        oldNumber: line,
        newNumber: line,
      ),
  ],
];

const _nearHunkLines = <DiffLine>[
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1,0 @@ nearby deletion'),
  DiffLine(kind: DiffLineKind.delete, text: 'old source line 1', oldNumber: 1),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -1,0 +1 @@ nearby addition'),
  DiffLine(kind: DiffLineKind.add, text: 'source line 1', newNumber: 1),
];

void main() {
  Future<
    ({FullDiffSessionController controller, FakeFullDiffRepository repository})
  >
  workspaceFixture() async {
    final repository = FakeFullDiffRepository();
    repository.files = (_, _) async => const [_sizedFile];
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
    );
    await controller.initialize();
    return (controller: controller, repository: repository);
  }

  Future<
    ({FullDiffSessionController controller, FakeFullDiffRepository repository})
  >
  distantChangeFixture(
    FullDiffPreferences initialPreferences, {
    Future<List<DiffLine>>? delayedFullFilePatch,
  }) async {
    final repository = FakeFullDiffRepository();
    final source = [
      for (var line = 1; line <= 240; line++) 'source line $line',
    ].join('\n');
    repository.files = (_, _) async => const [fileA];
    repository.scopedDiff = (_, _, _, _, _, scope) async {
      if (scope == DiffScope.hunks) return _distantHunkLines;
      if (delayedFullFilePatch != null) return delayedFullFilePatch;
      return _distantFullFileLines();
    };
    repository.content = (_, _, _) async =>
        Uint8List.fromList(utf8.encode('$source\n'));
    repository.blame = (_, _, _, _) async => [
      for (var line = 1; line <= 240; line++)
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
      initialPreferences: initialPreferences,
    );
    await controller.initialize();
    return (controller: controller, repository: repository);
  }

  Future<
    ({FullDiffSessionController controller, FakeFullDiffRepository repository})
  >
  nearbyChangeFixture() async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..scopedDiff = ((_, _, _, _, _, scope) async =>
          scope == DiffScope.hunks ? _nearHunkLines : _nearFullFileLines())
      ..content = ((_, _, _) async => Uint8List.fromList(
        utf8.encode(
          '${[for (var line = 1; line <= 24; line++) 'source line $line'].join('\n')}\n',
        ),
      ));
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    await controller.initialize();
    return (controller: controller, repository: repository);
  }

  Future<
    ({FullDiffSessionController controller, FakeFullDiffRepository repository})
  >
  historyWorkspaceFixture({
    Future<List<GitFileChange>> Function(GitCommit, String?)? files,
    Future<List<DiffLine>> Function(
      GitCommit,
      GitFileChange,
      String?,
      DiffAlgorithm,
      bool,
    )?
    diff,
  }) async {
    final repository = FakeFullDiffRepository()
      ..files = files ?? ((_, _) async => const [fileA])
      ..diff =
          diff ??
          ((commit, _, _, _, _) async => commit.sha == commitA.sha
              ? twoHunkLines
              : const [
                  DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
                  DiffLine(
                    kind: DiffLineKind.add,
                    text: 'historical change',
                    newNumber: 1,
                  ),
                ])
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('current\n')))
      ..history = ((_, _) async => [
        for (final entry in historyEntries)
          GitFileHistoryRecord(
            commit: entry.commit,
            path: entry.path,
            oldPath: entry.oldPath,
            status: entry.status,
          ),
      ]);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    await controller.initialize();
    controller.setView(FullDiffView.history);
    return (controller: controller, repository: repository);
  }

  Future<FullDiffSessionController> longHistoryController({
    List<GitCommit> commits = const [commitA],
  }) async {
    const secondaryFile = GitFileChange(
      path: 'src/secondary.pas',
      status: 'M',
      additions: 2,
      deletions: 1,
    );
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA, secondaryFile])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) async => resultFile.bytes)
      ..history = ((commit, file) async => [
        GitFileHistoryRecord(
          commit: commit,
          path: file.path,
          oldPath: file.oldPath,
          status: file.status,
        ),
        for (var index = 1; index < 40; index++)
          GitFileHistoryRecord(
            commit: GitCommit(
              sha: '${commit.sha}-history-$index',
              shortSha: 'h$index',
              parents: ['parent-$index'],
              author: fixtureIdentity,
              authorTimestamp: commit.authorTimestamp - index * 3600,
              committer: fixtureIdentity,
              committerTimestamp: commit.committerTimestamp - index * 3600,
              refs: const [],
              subject: 'Historical revision $index',
            ),
            path: file.path,
            oldPath: file.oldPath,
            status: file.status,
          ),
      ]);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: commits,
      initialIndex: 0,
    );
    await controller.initialize();
    controller.setView(FullDiffView.history);
    return controller;
  }

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    required FullDiffSessionController controller,
    required Size size,
    ExternalEditorService? editorService,
    ValueChanged<FullDiffPreferences>? onPreferencesChanged,
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
      controller: controller,
      editorService: editorService,
      onPreferencesChanged: onPreferencesChanged,
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

  Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: 'condition did not become true');
  }

  InkWell editorButton(WidgetTester tester) => tester.widget<InkWell>(
    find.ancestor(
      of: find.byKey(const Key('open-editor')),
      matching: find.byType(InkWell),
    ),
  );

  ScrollPosition historyPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('history-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  Future<double> scrollHistoryDeep(WidgetTester tester) async {
    final position = historyPosition(tester);
    expect(position.maxScrollExtent, greaterThan(300));
    position.jumpTo(300);
    await tester.pump();
    return position.pixels;
  }

  ScrollableState contentScrollableState(WidgetTester tester) =>
      tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('content-scrollable')),
              matching: find.byType(Scrollable),
            )
            .first,
      );

  testWidgets('full diff exposes only Diff Blame History and one layout', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );

    expect(find.text('File'), findsNothing);
    expect(find.text('Diff'), findsOneWidget);
    expect(find.text('Blame'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Unified'), findsOneWidget);
    expect(find.text('Side-by-side'), findsOneWidget);
    expect(find.text('Hunk'), findsOneWidget);

    expect(find.text('first new'), findsOneWidget);
    expect(find.text('second new'), findsOneWidget);
    await tester.tap(find.byKey(const Key('next-hunk')));
    await tester.pumpAndSettle();
    expect(fixture.controller.state.activeAnchor?.hunkIndex, 1);
    expect(find.text('first new'), findsOneWidget);
    expect(find.text('second new'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(fixture.controller.state.activeAnchor?.hunkIndex, 0);
  });

  testWidgets('keeps layout and anchor while switching main views', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    final controller = fixture.controller
      ..setView(FullDiffView.diff)
      ..setLayout(DiffLayout.unified)
      ..selectAnchor(twoHunkDocument.hunks[1].anchor);
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 842),
    );

    await tester.tap(find.text('Side-by-side'));
    await tester.tap(find.text('Blame'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diff'));
    await tester.pumpAndSettle();

    expect(controller.state.layout, DiffLayout.sideBySide);
    expect(controller.state.activeAnchor?.hunkIndex, 1);
    expect(fixture.repository.diffRequests, hasLength(1));
  });

  testWidgets('initial Full File aligns the first change in the viewport', (
    tester,
  ) async {
    final fixture = await distantChangeFixture(
      const FullDiffPreferences(scope: DiffScope.fullFile),
    );
    addTearDown(fixture.controller.dispose);

    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 520),
    );

    final target = find.byKey(const Key('unified-line-0-119'));
    expect(target, findsOneWidget);
    final viewport = tester.getRect(find.byKey(const Key('unified-list')));
    final targetRect = tester.getRect(target);
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('content-scrollable')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(position.pixels, greaterThan(0));
    expect(targetRect.top, greaterThanOrEqualTo(viewport.top));
    expect(targetRect.bottom, lessThanOrEqualTo(viewport.bottom));
  });

  testWidgets('turning Hunk off aligns the active change in full file scope', (
    tester,
  ) async {
    final fixture = await distantChangeFixture(const FullDiffPreferences());
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 520),
    );

    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('content-scrollable')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(position.pixels, 0);
    expect(find.byKey(const Key('unified-line-0-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hunk-toggle-on')));
    await tester.pumpAndSettle();

    final target = find.byKey(const Key('unified-line-0-120'));
    expect(fixture.controller.state.appliedScope, DiffScope.fullFile);
    expect(position.pixels, greaterThan(0));
    expect(target, findsOneWidget);
    final viewport = tester.getRect(find.byKey(const Key('unified-list')));
    final targetRect = tester.getRect(target);
    expect(targetRect.top, greaterThanOrEqualTo(viewport.top));
    expect(targetRect.bottom, lessThanOrEqualTo(viewport.bottom));
  });

  for (final layout in DiffLayout.values) {
    testWidgets('turning Hunk off preserves a later change in ${layout.name}', (
      tester,
    ) async {
      final fixture = await distantChangeFixture(
        FullDiffPreferences(layout: layout),
      );
      addTearDown(fixture.controller.dispose);
      fixture.controller.selectAnchor(
        fixture.controller.state.patch.data!.hunks.last.anchor,
      );
      await pumpWorkspace(
        tester,
        controller: fixture.controller,
        size: const Size(1070, 520),
      );

      await tester.tap(find.byKey(const Key('hunk-toggle-on')));
      await tester.pumpAndSettle();

      expect(fixture.controller.state.patch.data!.hunks, hasLength(1));
      expect(fixture.controller.state.activeAnchor?.hunkIndex, 0);
      expect(fixture.controller.state.activeAnchor?.newLine, 120);
      expect(fixture.controller.state.fullFileScrollTarget, (
        oldLine: 200,
        newLine: 200,
      ));
      final laterChange = find.text('source line 200');
      expect(laterChange, findsOneWidget);
      final viewport = tester.getRect(
        find.byKey(const Key('content-scrollable')),
      );
      final laterRect = tester.getRect(laterChange);
      expect(laterRect.top, greaterThanOrEqualTo(viewport.top));
      expect(laterRect.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(
        find.text('old source line 200'),
        layout == DiffLayout.unified ? findsNothing : findsOneWidget,
      );
      expect(find.text('old source line 120'), findsNothing);

      await tester.tap(find.byKey(const Key('hunk-toggle-off')));
      await tester.pumpAndSettle();

      expect(fixture.controller.state.appliedScope, DiffScope.hunks);
      expect(fixture.controller.state.patch.data!.hunks, hasLength(2));
      expect(fixture.controller.state.activeAnchor?.hunkIndex, 1);
      expect(fixture.controller.state.activeAnchor?.newLine, 200);
      expect(fixture.controller.state.fullFileScrollTarget, isNull);
    });
  }

  testWidgets(
    'full-file target survives a frame with an attached row but no scroll client',
    (tester) async {
      final initialFixture = await nearbyChangeFixture();
      final replacementFixture = await nearbyChangeFixture();
      final initialController = initialFixture.controller;
      final replacementController = replacementFixture.controller;
      addTearDown(initialController.dispose);
      addTearDown(replacementController.dispose);
      initialController.selectAnchor(
        initialController.state.patch.data!.hunks.last.anchor,
      );
      replacementController.selectAnchor(
        replacementController.state.patch.data!.hunks.last.anchor,
      );
      await initialController.setScope(DiffScope.fullFile);
      await replacementController.setScope(DiffScope.fullFile);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1070, 220);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Stack(
            children: [
              DiffScreen(
                repository: initialController.repository,
                commits: initialController.state.nearbyCommits,
                initialIndex: 0,
                controller: initialController,
              ),
              const SizedBox.shrink(),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('source line 1'), findsOneWidget);
      final scrollable = contentScrollableState(tester);
      final scrollController =
          scrollable.widget.controller! as FullDiffScrollController;
      final position = scrollable.position;
      position.jumpTo(position.minScrollExtent);
      scrollController.debugClientsAvailable = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Stack(
            children: [
              DiffScreen(
                repository: replacementController.repository,
                commits: replacementController.state.nearbyCommits,
                initialIndex: 0,
                controller: replacementController,
              ),
              const SizedBox.shrink(),
            ],
          ),
        ),
      );

      expect(scrollController.hasClients, isTrue);
      expect(scrollController.clientsReady, isFalse);
      expect(replacementController.state.fullFileScrollTarget, (
        oldLine: null,
        newLine: 1,
      ));
      expect(find.text('source line 1'), findsOneWidget);

      scrollController.debugClientsAvailable = true;
      scrollController.detach(position);
      scrollController.attach(position);
      await tester.pumpAndSettle();

      expect(position.pixels, greaterThan(0));
      final viewport = tester.getRect(
        find.byKey(const Key('content-scrollable')),
      );
      final target = tester.getRect(find.text('source line 1'));
      expect(target.top, greaterThanOrEqualTo(viewport.top));
      expect(target.bottom, lessThanOrEqualTo(viewport.bottom));
    },
  );

  testWidgets(
    'lazy full-file target resumes paging when the scroll client reattaches',
    (tester) async {
      final fixture = await distantChangeFixture(const FullDiffPreferences());
      final controller = fixture.controller;
      addTearDown(controller.dispose);
      controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1070, 220),
      );
      final scrollable = contentScrollableState(tester);
      final scrollController = scrollable.widget.controller!;
      final position = scrollable.position;
      position.jumpTo(position.minScrollExtent);
      scrollController.detach(position);
      var reattached = false;
      addTearDown(() {
        if (!reattached && !scrollController.positions.contains(position)) {
          scrollController.attach(position);
        }
      });

      await controller.setScope(DiffScope.fullFile);
      await tester.pump();

      expect(scrollController.hasClients, isFalse);
      expect(controller.state.fullFileScrollTarget, (
        oldLine: 200,
        newLine: 200,
      ));
      expect(find.text('source line 200'), findsNothing);

      scrollController.attach(position);
      reattached = true;
      await tester.pumpAndSettle();

      expect(position.pixels, greaterThan(0));
      expect(find.text('source line 200'), findsOneWidget);
      final viewport = tester.getRect(
        find.byKey(const Key('content-scrollable')),
      );
      final target = tester.getRect(find.text('source line 200'));
      expect(target.top, greaterThanOrEqualTo(viewport.top));
      expect(target.bottom, lessThanOrEqualTo(viewport.bottom));
    },
  );

  testWidgets(
    'late full-file load cannot override newer navigation or scroll',
    (tester) async {
      final fullFilePatch = Completer<List<DiffLine>>();
      final fixture = await distantChangeFixture(
        const FullDiffPreferences(),
        delayedFullFilePatch: fullFilePatch.future,
      );
      final controller = fixture.controller;
      addTearDown(controller.dispose);
      controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1070, 220),
      );

      final loading = controller.setScope(DiffScope.fullFile);
      await tester.pump();
      controller.selectAnchor(controller.state.patch.data!.hunks.first.anchor);
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('content-scrollable')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final navigationOffset = position.pixels;
      expect(navigationOffset, closeTo(0, 0.5));

      fullFilePatch.complete(_distantFullFileLines());
      await loading;
      await tester.pumpAndSettle();

      expect(controller.state.fullFileScrollTarget, isNull);
      expect(position.pixels, closeTo(navigationOffset, 0.5));
    },
  );

  testWidgets('stale queued full-file target cannot jump after scope return', (
    tester,
  ) async {
    final fullFilePatch = Completer<List<DiffLine>>();
    final fixture = await distantChangeFixture(
      const FullDiffPreferences(),
      delayedFullFilePatch: fullFilePatch.future,
    );
    final controller = fixture.controller;
    addTearDown(controller.dispose);
    controller.selectAnchor(controller.state.patch.data!.hunks.last.anchor);
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 220),
    );
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('content-scrollable')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    final laterHunkOffset = position.pixels;
    expect(laterHunkOffset, greaterThan(0));

    final fullFileLoading = controller.setScope(DiffScope.fullFile);
    fullFilePatch.complete(_distantFullFileLines());
    await fullFileLoading;
    await controller.setScope(DiffScope.hunks);
    await tester.pump();

    expect(controller.state.appliedScope, DiffScope.hunks);
    expect(controller.state.fullFileScrollTarget, isNull);
    expect(position.pixels, closeTo(laterHunkOffset, 0.5));
  });

  for (final view in [FullDiffView.blame]) {
    testWidgets('switching into ${view.name} aligns the active change', (
      tester,
    ) async {
      final fixture = await distantChangeFixture(const FullDiffPreferences());
      addTearDown(fixture.controller.dispose);
      await pumpWorkspace(
        tester,
        controller: fixture.controller,
        size: const Size(1070, 520),
      );

      await tester.tap(find.text('Blame'));
      await tester.pumpAndSettle();

      final list = find.byKey(const Key('blame-list'));
      final target = find.byKey(const Key('blame-current-line-120'));
      expect(target, findsOneWidget);
      final viewport = tester.getRect(list);
      final targetRect = tester.getRect(target);
      expect(targetRect.top, greaterThanOrEqualTo(viewport.top));
      expect(targetRect.bottom, lessThanOrEqualTo(viewport.bottom));
    });
  }

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
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..setView(FullDiffView.diff)
        ..setLayout(DiffLayout.sideBySide);

      await controller.selectParent('parent-2');

      expect(repository.fileRequests.last.parent, 'parent-2');
      expect(repository.diffRequests.last.parent, 'parent-2');
      expect(repository.contentRequests.last.parent, 'parent-2');
      expect(controller.state.view, FullDiffView.diff);
      expect(controller.state.layout, DiffLayout.sideBySide);
    },
  );

  for (final scenario in [
    (width: 1070.0, files: true),
    (width: 650.0, files: true),
    (width: 481.0, files: true),
    (width: 480.0, files: false),
  ]) {
    testWidgets('responsive width ${scenario.width}', (tester) async {
      final fixture = await workspaceFixture();
      addTearDown(fixture.controller.dispose);
      fixture.controller.setLayout(DiffLayout.sideBySide);
      await pumpWorkspace(
        tester,
        controller: fixture.controller,
        size: Size(scenario.width, 549),
      );
      expect(find.byKey(const Key('nearby-commits-pane')), findsNothing);
      expect(find.byKey(const Key('nearby-commits-list')), findsNothing);
      expect(find.byKey(const Key('nearby-column-resizer')), findsNothing);
      expect(
        find.byKey(const Key('commit-files-pane')),
        scenario.files ? findsOneWidget : findsNothing,
      );
      expect(find.byKey(const Key('diff-column')), findsOneWidget);
    });
  }

  testWidgets('regular commits start the file pane with its section header', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );

    final filesPane = find.byKey(const Key('commit-files-pane'));
    expect(
      find.descendant(of: filesPane, matching: find.text(commitA.subject)),
      findsNothing,
    );
    expect(
      find.descendant(of: filesPane, matching: find.text(fixtureIdentity.name)),
      findsNothing,
    );
    expect(
      tester
          .getTopLeft(
            find.descendant(of: filesPane, matching: find.text('변경 파일')),
          )
          .dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('changed-files-list'))).dy,
      ),
    );
  });

  testWidgets('encoding appears without moving file details or actions', (
    tester,
  ) async {
    final contentStarted = Completer<void>();
    final content = Completer<Uint8List>();
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [_sizedFile])
      ..diff = ((_, _, _, _, _) async => twoHunkLines)
      ..content = ((_, _, _) {
        contentStarted.complete();
        return content.future;
      });
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
      encodingCache: FullDiffEncodingCache(),
    );
    addTearDown(controller.dispose);
    final loading = controller.initialize();
    await contentStarted.future;
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1400, 842),
    );

    const stableKeys = [
      Key('file-path-chip'),
      Key('file-summary-badge'),
      Key('focus-mode'),
      Key('main-view-controls'),
    ];
    final before = {
      for (final key in stableKeys) key: tester.getTopLeft(find.byKey(key)),
    };
    expect(find.byKey(const Key('encoding-badge')), findsNothing);

    content.complete(Uint8List.fromList(utf8.encode('source\n')));
    await loading;
    await tester.pumpAndSettle();

    for (final key in stableKeys) {
      expect(tester.getTopLeft(find.byKey(key)), before[key]);
    }
    expect(find.byKey(const Key('encoding-badge')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('encoding-badge'))).dx,
      greaterThan(
        tester.getTopRight(find.byKey(const Key('file-summary-badge'))).dx,
      ),
    );
  });

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

  testWidgets('the 480px algorithm chooser stays inside the viewport', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(480, 560),
    );

    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pump();

    final details = find.byKey(const Key('algorithm-details-gitSetting'));
    expect(details, findsOneWidget);
    expect(tester.getTopLeft(details).dx, greaterThanOrEqualTo(0));
    expect(tester.getTopRight(details).dx, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a diff refresh error uses the compact guide type size', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );
    fixture.repository.diff = (_, _, _, algorithm, _) async {
      if (algorithm == DiffAlgorithm.histogram) {
        throw const GitRepositoryException('/repo', 'diff failed');
      }
      return twoHunkLines;
    };

    await expectLater(
      fixture.controller.selectAlgorithm(DiffAlgorithm.histogram),
      throwsA(isA<GitRepositoryException>()),
    );
    await tester.pump();

    final banner = find.byKey(const Key('diff-refresh-error'));
    expect(banner, findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(of: banner, matching: find.byType(Text)),
          )
          .style
          ?.fontSize,
      10,
    );
  });

  testWidgets(
    'an empty preserved patch keeps refresh errors visible and can recover',
    (tester) async {
      var histogramLoads = 0;
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..diff = ((_, _, _, algorithm, _) async {
          if (algorithm == DiffAlgorithm.gitSetting) return const [];
          histogramLoads++;
          if (histogramLoads == 1) {
            throw const GitRepositoryException('/repo', 'refresh failed');
          }
          return twoHunkLines;
        })
        ..content = ((_, _, _) async => resultFile.bytes);
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1070, 842),
      );
      expect(find.text('현재 옵션으로 표시할 변경이 없습니다.'), findsOneWidget);

      await expectLater(
        controller.selectAlgorithm(DiffAlgorithm.histogram),
        throwsA(isA<GitRepositoryException>()),
      );
      await tester.pump();

      expect(find.byKey(const Key('diff-refresh-error')), findsOneWidget);
      expect(find.textContaining('refresh failed'), findsOneWidget);
      expect(find.text('현재 옵션으로 표시할 변경이 없습니다.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('diff-algorithm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('algorithm-option-histogram')));
      await tester.pumpAndSettle();

      expect(histogramLoads, 2);
      expect(find.byKey(const Key('diff-refresh-error')), findsNothing);
      expect(find.byKey(const Key('full-diff-unavailable')), findsNothing);
      expect(find.text('first new'), findsOneWidget);
    },
  );

  testWidgets('focus mode restores pane widths and selection', (tester) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );
    final fileWidth = tester
        .getSize(find.byKey(const Key('commit-files-pane')))
        .width;
    final commit = fixture.controller.state.selectedCommit;
    final file = fixture.controller.state.selectedFile;

    await tester.tap(find.text('집중 모드'));
    await tester.pump();
    expect(find.byKey(const Key('nearby-commits-pane')), findsNothing);
    expect(find.byKey(const Key('nearby-commits-list')), findsNothing);
    expect(find.byKey(const Key('nearby-column-resizer')), findsNothing);
    expect(find.byKey(const Key('commit-files-pane')), findsNothing);
    expect(find.byKey(const Key('diff-column')), findsOneWidget);
    expect(find.text('탐색 패널'), findsOneWidget);

    await tester.tap(find.text('탐색 패널'));
    await tester.pump();
    expect(find.byKey(const Key('nearby-commits-pane')), findsNothing);
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
    final selectedRow = find.byKey(Key('selected-file-${fileA.path}'));
    final surface = tester.widget<FullDiffSelectableRowSurface>(selectedRow);
    expect(surface.selected, isTrue);
    expect(surface.focused, isTrue);
    expect(find.text('+'), findsWidgets);
    expect(find.text('−'), findsWidgets);
    expect(find.byKey(const Key('code-row-current-marker')), findsNWidgets(2));
  });

  testWidgets(
    'history highlights the current row and keeps it semantically selected',
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

      final surface = tester.widget<FullDiffSelectableRowSurface>(row);
      expect(surface.selected, isTrue);
      expect(surface.focused, isFalse);
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

  testWidgets('history keeps a responsive list beside its detail pane', (
    tester,
  ) async {
    const scenarios = [
      (workspaceWidth: 760.0, listWidth: 280.0),
      (workspaceWidth: 600.0, listWidth: 210.0),
      (workspaceWidth: 480.0, listWidth: 180.0),
    ];
    for (final scenario in scenarios) {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: scenario.workspaceWidth,
              height: 400,
              child: const FullHistoryWorkspace(
                history: SizedBox(),
                detail: SizedBox(),
              ),
            ),
          ),
        ),
      );

      final listPane = find.byKey(const Key('history-list-pane'));
      final detailPane = find.byKey(const Key('history-detail-pane'));
      expect(tester.getSize(listPane).width, scenario.listWidth);
      expect(
        tester.getTopLeft(listPane).dx,
        lessThan(tester.getTopLeft(detailPane).dx),
      );
      expect(find.byKey(const Key('history-detail-divider')), findsOneWidget);
    }
  });

  testWidgets(
    'history split uses the local detail width after real navigation panes',
    (tester) async {
      for (final scenario in [
        (windowWidth: 782.0, showsOldSide: false),
        (windowWidth: 1440.0, showsOldSide: true),
      ]) {
        final fixture = await historyWorkspaceFixture();
        addTearDown(fixture.controller.dispose);
        fixture.controller.setLayout(DiffLayout.sideBySide);
        await pumpWorkspace(
          tester,
          controller: fixture.controller,
          size: Size(scenario.windowWidth, 842),
        );

        final detailWidth = tester
            .getSize(find.byKey(const Key('history-detail-pane')))
            .width;
        if (scenario.showsOldSide) {
          expect(detailWidth, greaterThan(480));
          expect(
            find.byKey(const Key('side-by-side-old-pane')),
            findsOneWidget,
          );
        } else {
          expect(detailWidth, lessThan(480));
          expect(find.byKey(const Key('side-by-side-old-pane')), findsNothing);
        }
      }
    },
  );

  testWidgets(
    'history scroll stays for row selection and resets for a different file',
    (tester) async {
      final controller = await longHistoryController();
      addTearDown(controller.dispose);
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1070, 650),
      );
      final originalContext = controller.state.historyContext;
      final beforeSelection = await scrollHistoryDeep(tester);

      await controller.selectHistoryEntry(controller.state.history.data![5]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.state.historyContext, originalContext);
      expect(historyPosition(tester).pixels, closeTo(beforeSelection, 0.5));

      await controller.selectFile(controller.state.files.last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.state.historyContext?.path, 'src/secondary.pas');
      expect(historyPosition(tester).pixels, 0);
    },
  );

  testWidgets('history scroll resets for commit and parent context changes', (
    tester,
  ) async {
    final controller = await longHistoryController(
      commits: [commitA, historyEntries.last.commit],
    );
    addTearDown(controller.dispose);
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 650),
    );

    await scrollHistoryDeep(tester);
    await controller.selectCommit(historyEntries.last.commit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      controller.state.historyContext?.startRevision,
      historyEntries.last.commit.sha,
    );
    expect(historyPosition(tester).pixels, 0);

    await scrollHistoryDeep(tester);
    await controller.selectParent('alternate-parent');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.state.parent, 'alternate-parent');
    expect(historyPosition(tester).pixels, 0);
  });

  testWidgets('history scroll resets when the session controller is replaced', (
    tester,
  ) async {
    final first = await longHistoryController();
    final second = await longHistoryController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await pumpWorkspace(tester, controller: first, size: const Size(1070, 650));
    await scrollHistoryDeep(tester);
    expect(first.state.historyContext, second.state.historyContext);

    await pumpWorkspace(
      tester,
      controller: second,
      size: const Size(1070, 650),
    );

    expect(historyPosition(tester).pixels, 0);
  });

  testWidgets('history row metadata shrinks inside the narrow list pane', (
    tester,
  ) async {
    const author = 'A deliberately long author name for narrow history rows';
    const entry = FileHistoryEntry(
      commit: GitCommit(
        sha: 'narrow-history',
        shortSha: 'narrow',
        parents: ['parent'],
        author: GitIdentity(name: author, email: 'author@example.com'),
        authorTimestamp: -3000000000000,
        committer: GitIdentity(name: author, email: 'author@example.com'),
        committerTimestamp: -3000000000000,
        refs: [],
        subject: 'Narrow history metadata',
      ),
      path: 'lib/narrow.dart',
      oldPath: null,
      status: 'M',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: Material(
            child: SizedBox(
              width: 180,
              height: 160,
              child: FullHistoryView(
                entries: const [entry],
                selected: entry,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final authorText = tester.widget<Text>(find.text(author));
    final timeText = tester.widget<Text>(find.textContaining('ago'));
    expect(authorText.overflow, TextOverflow.ellipsis);
    expect(timeText.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicking history keeps the list and shows its patch', (
    tester,
  ) async {
    final fixture = await historyWorkspaceFixture();
    addTearDown(fixture.controller.dispose);
    fixture.controller.setFocusMode(true);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );
    final historicalEntry = historyEntries.last;

    await tester.tap(
      find.byKey(Key('history-row-${historicalEntry.commit.sha}')),
    );
    await pumpUntil(
      tester,
      () =>
          fixture.controller.state.selectedCommit.sha ==
              historicalEntry.commit.sha &&
          fixture.controller.state.patch.data != null &&
          fixture.controller.state.file.data != null,
    );
    await tester.pump();

    expect(find.byKey(const Key('history-list')), findsOneWidget);
    expect(find.byKey(const Key('history-detail-pane')), findsOneWidget);
    expect(find.text('historical change'), findsOneWidget);
  });

  testWidgets('history focus alone does not change the detail patch', (
    tester,
  ) async {
    final fixture = await historyWorkspaceFixture();
    addTearDown(fixture.controller.dispose);
    fixture.controller.setFocusMode(true);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );
    final historicalRow = find.byKey(
      Key('history-row-${historyEntries.last.commit.sha}'),
    );

    Focus.of(tester.element(historicalRow)).requestFocus();
    await tester.pump();

    expect(Focus.of(tester.element(historicalRow)).hasPrimaryFocus, isTrue);
    expect(fixture.controller.state.selectedCommit.sha, commitA.sha);
    expect(find.text('first new'), findsOneWidget);
    expect(find.text('historical change'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpUntil(
      tester,
      () =>
          fixture.controller.state.selectedCommit.sha ==
              historyEntries.last.commit.sha &&
          fixture.controller.state.patch.data != null &&
          fixture.controller.state.file.data != null,
    );
    await tester.pump();

    expect(
      fixture.controller.state.selectedCommit.sha,
      historyEntries.last.commit.sha,
    );
    expect(find.text('historical change'), findsOneWidget);
  });

  testWidgets('history detail supports unified and side-by-side layouts', (
    tester,
  ) async {
    final fixture = await historyWorkspaceFixture();
    addTearDown(fixture.controller.dispose);
    fixture.controller.setFocusMode(true);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );

    await tester.tap(find.text('Unified'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unified-hunk-0')), findsOneWidget);

    await tester.tap(find.text('Side-by-side'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('side-by-side-old-pane')), findsOneWidget);
  });

  testWidgets('history keeps its list while detail loading fails and retries', (
    tester,
  ) async {
    final historicalPatch = Completer<List<DiffLine>>();
    var historicalAttempts = 0;
    final fixture = await historyWorkspaceFixture(
      diff: (commit, _, _, _, _) {
        if (commit.sha == commitA.sha) return Future.value(twoHunkLines);
        historicalAttempts++;
        if (historicalAttempts == 1) return historicalPatch.future;
        return Future.value(const [
          DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
          DiffLine(
            kind: DiffLineKind.add,
            text: 'historical change',
            newNumber: 1,
          ),
        ]);
      },
    );
    addTearDown(fixture.controller.dispose);
    fixture.controller.setFocusMode(true);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );

    await tester.tap(
      find.byKey(Key('history-row-${historyEntries.last.commit.sha}')),
    );
    await tester.pump();
    await tester.pump();

    expect(historicalAttempts, 1);
    expect(find.byKey(const Key('history-list')), findsOneWidget);
    expect(find.byKey(const Key('history-detail-pane')), findsOneWidget);
    expect(find.byKey(const Key('diff-pending-first-diff')), findsOneWidget);

    historicalPatch.completeError(
      const GitRepositoryException('/repo', 'historical failed'),
    );
    await pumpUntil(tester, () => fixture.controller.state.patch.error != null);
    await tester.pump();

    expect(find.byKey(const Key('history-list')), findsOneWidget);
    expect(find.byKey(const Key('full-diff-unavailable')), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await pumpUntil(
      tester,
      () =>
          historicalAttempts == 2 &&
          fixture.controller.state.patch.data != null &&
          fixture.controller.state.file.data != null,
    );
    await tester.pump();

    expect(historicalAttempts, 2);
    expect(find.byKey(const Key('history-list')), findsOneWidget);
    expect(find.text('historical change'), findsOneWidget);
  });

  testWidgets(
    'unmatched history detail retries the failed current patch in place',
    (tester) async {
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
        ..content = ((_, _, _) async => resultFile.bytes)
        ..history = ((_, _) async => [
          GitFileHistoryRecord(
            commit: historyEntries.last.commit,
            path: fileA.path,
            oldPath: null,
            status: 'M',
          ),
        ]);
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setView(FullDiffView.history);
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1070, 842),
      );
      final originalHistory = controller.state.history.data;
      final originalContext = controller.state.historyContext;

      expect(controller.state.selectedHistoryEntry, isNull);
      expect(find.byKey(const Key('full-diff-unavailable')), findsOneWidget);

      await tester.tap(find.text('다시 시도'));
      await pumpUntil(
        tester,
        () => patchLoads == 2 && controller.state.patch.data != null,
      );
      await tester.pump();

      expect(patchLoads, 2);
      expect(controller.state.history.data, same(originalHistory));
      expect(controller.state.historyContext, originalContext);
      expect(controller.state.selectedHistoryEntry, isNull);
      expect(find.text('first new'), findsOneWidget);
    },
  );

  testWidgets(
    'changed files retry preserves the selected historical list and context',
    (tester) async {
      var historicalFileLoads = 0;
      final fixture = await historyWorkspaceFixture(
        files: (commit, _) async {
          if (commit.sha == commitA.sha) return const [fileA];
          historicalFileLoads++;
          if (historicalFileLoads == 1) {
            throw const GitRepositoryException(
              '/repo',
              'historical files failed',
            );
          }
          return const [fileA];
        },
      );
      addTearDown(fixture.controller.dispose);
      await pumpWorkspace(
        tester,
        controller: fixture.controller,
        size: const Size(1070, 842),
      );
      final originalHistory = fixture.controller.state.history.data;
      final originalContext = fixture.controller.state.historyContext;
      final selectedEntry = originalHistory!.last;

      await tester.tap(
        find.byKey(Key('history-row-${selectedEntry.commit.sha}')),
      );
      await pumpUntil(
        tester,
        () => fixture.controller.state.filesResource.error != null,
      );
      await tester.pump();
      expect(find.byKey(const Key('files-error')), findsOneWidget);

      await tester.tap(find.byKey(const Key('files-retry')));
      await pumpUntil(
        tester,
        () =>
            historicalFileLoads == 2 &&
            fixture.controller.state.patch.data != null,
      );
      await tester.pump();

      expect(fixture.controller.state.history.data, same(originalHistory));
      expect(fixture.controller.state.historyContext, originalContext);
      expect(
        fixture.controller.state.selectedHistoryEntry,
        same(selectedEntry),
      );
      expect(find.text('historical change'), findsOneWidget);
    },
  );

  testWidgets(
    'history keeps its list and shows loading while revision files load',
    (tester) async {
      final historicalFiles = Completer<List<GitFileChange>>();
      final fixture = await historyWorkspaceFixture(
        files: (commit, _) => commit.sha == commitA.sha
            ? Future.value(const [fileA])
            : historicalFiles.future,
      );
      addTearDown(fixture.controller.dispose);
      fixture.controller.setFocusMode(true);
      await pumpWorkspace(
        tester,
        controller: fixture.controller,
        size: const Size(1070, 842),
      );

      await tester.tap(
        find.byKey(Key('history-row-${historyEntries.last.commit.sha}')),
      );
      await tester.pump();

      expect(fixture.controller.state.filesResource.loading, isTrue);
      expect(find.byKey(const Key('history-list')), findsOneWidget);
      expect(find.byKey(const Key('history-detail-pane')), findsOneWidget);
      expect(find.text('파일을 읽는 중입니다'), findsOneWidget);
      expect(tester.widget<Text>(find.text('파일을 읽는 중입니다')).style?.fontSize, 10);
      expect(find.text('표시할 데이터가 없습니다'), findsNothing);

      historicalFiles.complete(const [fileA]);
      await pumpUntil(
        tester,
        () =>
            fixture.controller.state.patch.data != null &&
            fixture.controller.state.file.data != null,
      );
    },
  );

  testWidgets('uses approved typography in the file list', (tester) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(600, 842),
    );

    final fileList = find.byKey(const Key('changed-files-list'));
    expect(
      tester
          .widget<Text>(
            find.descendant(of: fileList, matching: find.text(fileA.path)),
          )
          .style
          ?.fontSize,
      13,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: fileList,
              matching: find.text('+12 −4 · 1.5 KB'),
            ),
          )
          .style
          ?.fontSize,
      12,
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
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 842),
    );

    final filesFocus = tester.widget<Focus>(
      find.byKey(const Key('changed-files-focus')),
    );
    filesFocus.focusNode!.requestFocus();
    await tester.pump();
    expect(filesFocus.focusNode!.hasFocus, isTrue);

    await sendChord(tester, LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.state.selectedFile, fileB);
    await controller.selectFile(fileA);
    await tester.pumpAndSettle();

    Focus.of(
      tester.element(find.byKey(const Key('content-scrollable'))),
    ).requestFocus();
    await tester.pump();
    await sendChord(tester, LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.state.selectedFile, fileB);
    await controller.selectFile(fileA);
    await tester.pumpAndSettle();

    await sendChord(tester, LogicalKeyboardKey.arrowDown, meta: true);
    await tester.pumpAndSettle();
    expect(controller.state.selectedFile, fileB);

    await sendChord(tester, LogicalKeyboardKey.arrowDown, alt: true);
    await tester.pumpAndSettle();
    expect(controller.state.activeAnchor?.hunkIndex, 1);
    await sendChord(tester, LogicalKeyboardKey.keyF, meta: true, shift: true);
    expect(controller.state.focusMode, isTrue);
  });

  testWidgets(
    'algorithm shortcut previews with arrows and applies with enter',
    (tester) async {
      final fixture = await workspaceFixture();
      addTearDown(fixture.controller.dispose);
      await pumpWorkspace(
        tester,
        controller: fixture.controller,
        size: const Size(1070, 842),
      );
      final requestsBefore = fixture.repository.diffRequests.length;

      await sendChord(tester, LogicalKeyboardKey.keyA, meta: true, shift: true);
      expect(
        find.byKey(const Key('algorithm-details-gitSetting')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.byKey(const Key('algorithm-details-myers')), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const Key('algorithm-option-myers')))
            .getSemanticsData()
            .flagsCollection
            .isFocused,
        ui.Tristate.isTrue,
      );
      expect(
        fixture.controller.state.appliedAlgorithm,
        DiffAlgorithm.gitSetting,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(fixture.repository.diffRequests, hasLength(requestsBefore + 1));
      expect(
        fixture.repository.diffRequests.last.algorithm,
        DiffAlgorithm.myers,
      );
      expect(fixture.controller.state.appliedAlgorithm, DiffAlgorithm.myers);
    },
  );

  testWidgets('escape cancels algorithm preview and restores toolbar focus', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );
    final requestsBefore = fixture.repository.diffRequests.length;

    await sendChord(tester, LogicalKeyboardKey.keyA, meta: true, shift: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const Key('algorithm-details-myers')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('algorithm-details-myers')), findsNothing);
    expect(fixture.repository.diffRequests, hasLength(requestsBefore));
    expect(fixture.controller.state.appliedAlgorithm, DiffAlgorithm.gitSetting);
    final algorithmButton = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('diff-algorithm')),
        matching: find.byType(InkWell),
      ),
    );
    expect(algorithmButton.focusNode?.hasFocus, isTrue);
  });

  testWidgets('file and History lists move selection and focus explicitly', (
    tester,
  ) async {
    const fileB = GitFileChange(
      path: 'src/window.pas',
      status: 'M',
      additions: 1,
      deletions: 1,
    );
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA, fileB])
      ..diff = ((commit, _, _, _, _) async => commit.sha == commitA.sha
          ? twoHunkLines
          : const [
              DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
              DiffLine(
                kind: DiffLineKind.add,
                text: 'historical detail',
                newNumber: 1,
              ),
            ])
      ..content = ((_, _, _) async => resultFile.bytes)
      ..history = ((_, file) async => [
        for (final entry in historyEntries)
          GitFileHistoryRecord(
            commit: entry.commit,
            path: file.path,
            oldPath: file.oldPath,
            status: file.status,
          ),
      ]);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setView(FullDiffView.history);
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 842),
    );

    final filesFocus = tester.widget<Focus>(
      find.byKey(const Key('changed-files-focus')),
    );
    filesFocus.focusNode!.requestFocus();
    await tester.pump();
    expect(filesFocus.focusNode!.hasFocus, isTrue);
    expect(
      tester
          .widget<FullDiffSelectableRowSurface>(
            find.byKey(Key('selected-file-${fileA.path}')),
          )
          .focused,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final historyFocus = tester.widget<Focus>(
      find.byKey(const Key('history-list-focus')),
    );
    expect(historyFocus.focusNode!.hasFocus, isTrue);
    expect(controller.state.selectedHistoryEntry, isNotNull);
    expect(
      tester
          .widget<FullDiffSelectableRowSurface>(
            find.byKey(Key('selected-file-${fileA.path}')),
          )
          .focused,
      isFalse,
    );

    await sendChord(tester, LogicalKeyboardKey.arrowDown, meta: true);
    await tester.pumpAndSettle();
    expect(controller.state.selectedFile, fileB);
    await controller.selectFile(fileA);
    await tester.pumpAndSettle();
    historyFocus.focusNode!.requestFocus();
    await tester.pump();

    final selectedFilePath = controller.state.selectedFile!.path;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      controller.state.selectedHistoryEntry?.commit.sha,
      historyEntries[1].commit.sha,
    );
    expect(controller.state.selectedFile!.path, selectedFilePath);
    expect(find.text('historical detail'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(filesFocus.focusNode!.hasFocus, isTrue);
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
    fixture.controller.setView(FullDiffView.diff);
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
    expect(
      position.pixels,
      closeTo(
        (before + 48).clamp(position.minScrollExtent, position.maxScrollExtent),
        0.5,
      ),
    );

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

  testWidgets('minimap uses the active diff scroll position', (tester) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    fixture.controller.setLayout(DiffLayout.sideBySide);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1070, 842),
    );

    expect(
      tester
          .widget<FullDiffMinimap>(find.byType(FullDiffMinimap))
          .scrollController
          .positions,
      hasLength(1),
    );
  });

  Future<FullDiffSessionController> unavailableController({
    required Uint8List bytes,
    Future<List<DiffLine>> Function(
      GitCommit,
      GitFileChange,
      String?,
      DiffAlgorithm,
      bool,
    )?
    diff,
    FullDiffPreferences initialPreferences = const FullDiffPreferences(),
  }) async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = diff ?? ((_, _, _, _, _) async => const [])
      ..content = ((_, _, _) async => bytes);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
      initialPreferences: initialPreferences,
    );
    await controller.initialize();
    return controller;
  }

  final lineLimitedBytes = Uint8List((fullDiffTextLineLimit + 1) * 2);
  for (var index = 0; index < lineLimitedBytes.length; index += 2) {
    lineLimitedBytes[index] = 0x78;
    lineLimitedBytes[index + 1] = 0x0A;
  }
  final byteLimitedBytes = Uint8List(fullDiffTextByteLimit + 1)
    ..fillRange(0, fullDiffTextByteLimit + 1, 0x78);
  final unavailableCases = [
    (
      label: 'empty patch',
      bytes: Uint8List.fromList(utf8.encode('unchanged\n')),
      attribute: 'UTF-8',
      message: '현재 옵션으로 표시할 변경이 없습니다.',
      patch: <DiffLine>[],
    ),
    (
      label: 'binary content',
      bytes: Uint8List.fromList([0x78, 0x00]),
      attribute: 'Binary',
      message: '바이너리 파일이라 텍스트 diff를 표시할 수 없습니다.',
      patch: twoHunkLines,
    ),
    (
      label: 'unsupported encoding',
      bytes: Uint8List.fromList([0x80, 0x81]),
      attribute: 'Unsupported encoding',
      message: 'UTF-8로 해석할 수 없는 파일이라 텍스트 diff를 표시할 수 없습니다.',
      patch: twoHunkLines,
    ),
    (
      label: 'byte-limited content',
      bytes: byteLimitedBytes,
      attribute: '10 MiB 초과',
      message: '파일이 10 MiB 제한을 초과해 내용을 표시하지 않습니다.',
      patch: twoHunkLines,
    ),
    (
      label: 'line-limited content',
      bytes: lineLimitedBytes,
      attribute: '200,000줄 초과',
      message: '파일이 200,000줄 제한을 초과해 내용을 표시하지 않습니다.',
      patch: twoHunkLines,
    ),
  ];
  for (final scenario in unavailableCases) {
    testWidgets('${scenario.label} explains why diff content is unavailable', (
      tester,
    ) async {
      final controller = await unavailableController(
        bytes: scenario.bytes,
        diff: (_, _, _, _, _) async => scenario.patch,
      );
      addTearDown(controller.dispose);
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1070, 650),
      );

      expect(find.byKey(const Key('full-diff-unavailable')), findsOneWidget);
      expect(find.text(fileA.path), findsWidgets);
      expect(find.text(scenario.attribute), findsWidgets);
      expect(find.text(scenario.message), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);
    });
  }

  testWidgets('full-file scope keeps unsupported content in the panel', (
    tester,
  ) async {
    final controller = await unavailableController(
      bytes: Uint8List.fromList([0x80, 0x81]),
      diff: (_, _, _, _, _) async => twoHunkLines,
      initialPreferences: const FullDiffPreferences(scope: DiffScope.fullFile),
    );
    addTearDown(controller.dispose);
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 650),
    );

    expect(find.byKey(const Key('full-diff-unavailable')), findsOneWidget);
    expect(find.text('Unsupported encoding'), findsWidgets);
    expect(
      find.text('UTF-8로 해석할 수 없는 파일이라 텍스트 diff를 표시할 수 없습니다.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed first patch request can retry into a diff', (
    tester,
  ) async {
    var attempts = 0;
    final controller = await unavailableController(
      bytes: Uint8List.fromList(utf8.encode('current\n')),
      diff: (_, _, _, _, _) async {
        if (attempts++ == 0) throw const FormatException('bad patch');
        return twoHunkLines;
      },
    );
    addTearDown(controller.dispose);
    final repository = controller.repository as FakeFullDiffRepository;
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1070, 650),
    );

    expect(find.byKey(const Key('full-diff-unavailable')), findsOneWidget);
    expect(find.text('Git에서 이 파일의 변경 내용을 읽지 못했습니다.'), findsOneWidget);
    expect(find.textContaining('bad patch'), findsOneWidget);
    expect(repository.diffRequests, hasLength(1));

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repository.diffRequests, hasLength(2));
    expect(find.byKey(const Key('full-diff-unavailable')), findsNothing);
    expect(find.text('first new'), findsOneWidget);
  });

  for (final scope in DiffScope.values) {
    testWidgets(
      '${scope.name} scope byte failures use the structured panel and retry only content',
      (tester) async {
        var contentLoads = 0;
        final repository = FakeFullDiffRepository()
          ..files = ((_, _) async => const [fileA])
          ..diff = ((_, _, _, _, _) async => twoHunkLines)
          ..content = ((_, _, _) async {
            contentLoads++;
            if (contentLoads == 1) {
              throw const GitRepositoryException('/repo', 'content failed');
            }
            return resultFile.bytes;
          });
        final controller = FullDiffSessionController(
          repository: repository,
          commits: const [commitA],
          initialIndex: 0,
          initialPreferences: FullDiffPreferences(scope: scope),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await pumpWorkspace(
          tester,
          controller: controller,
          size: const Size(1070, 650),
        );

        expect(find.byKey(const Key('full-diff-unavailable')), findsOneWidget);
        expect(find.text(fileA.path), findsWidgets);
        expect(find.text('M · +12 −4 · —'), findsWidgets);
        expect(find.text('Git error'), findsOneWidget);
        expect(find.text('Git에서 이 파일의 변경 내용을 읽지 못했습니다.'), findsOneWidget);
        expect(find.textContaining('content failed'), findsOneWidget);
        expect(repository.contentRequests, hasLength(1));
        expect(repository.diffRequests, hasLength(1));

        await tester.tap(find.text('다시 시도'));
        await tester.pumpAndSettle();

        expect(repository.contentRequests, hasLength(2));
        expect(repository.diffRequests, hasLength(1));
        expect(find.byKey(const Key('full-diff-unavailable')), findsNothing);
        expect(find.byKey(const Key('unified-list')), findsOneWidget);
      },
    );
  }

  testWidgets('failed scope change does not report a new preference', (
    tester,
  ) async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..scopedDiff = ((_, _, _, _, _, scope) async {
        if (scope == DiffScope.fullFile) {
          throw const GitRepositoryException('/repo', 'full file failed');
        }
        return twoHunkLines;
      })
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('current\n')));
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final reported = <FullDiffPreferences>[];
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1200, 800),
      onPreferencesChanged: reported.add,
    );

    await tester.tap(find.text('Hunk'));
    await tester.pumpAndSettle();

    expect(
      reported.where((value) => value.scope == DiffScope.fullFile),
      isEmpty,
    );
    expect(find.byKey(const Key('hunk-toggle-on')), findsOneWidget);
  });

  testWidgets(
    'failed algorithm choice keeps its applied label and preference',
    (tester) async {
      final pending = Completer<List<DiffLine>>();
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..diff = ((_, _, _, algorithm, _) {
          if (algorithm == DiffAlgorithm.myers) return pending.future;
          return Future.value(twoHunkLines);
        })
        ..content = ((_, _, _) async => resultFile.bytes);
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final reported = <FullDiffPreferences>[];
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1200, 800),
        onPreferencesChanged: reported.add,
      );

      await tester.tap(find.byKey(const Key('diff-algorithm')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('algorithm-option-myers')));
      await tester.pump();

      expect(controller.state.requestedAlgorithm, DiffAlgorithm.myers);
      expect(controller.state.appliedAlgorithm, DiffAlgorithm.gitSetting);
      expect(
        find.descendant(
          of: find.byKey(const Key('diff-algorithm')),
          matching: find.text('Git setting'),
        ),
        findsOneWidget,
      );
      expect(
        reported.where(
          (preference) => preference.algorithm == DiffAlgorithm.myers,
        ),
        isEmpty,
      );

      pending.completeError(
        const GitRepositoryException('/repo', 'algorithm failed'),
      );
      await tester.pumpAndSettle();

      expect(controller.state.requestedAlgorithm, DiffAlgorithm.gitSetting);
      expect(controller.state.appliedAlgorithm, DiffAlgorithm.gitSetting);
      expect(
        reported.where(
          (preference) => preference.algorithm == DiffAlgorithm.myers,
        ),
        isEmpty,
      );
    },
  );

  testWidgets('full diff command shortcuts change only their owned options', (
    tester,
  ) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1200, 800),
    );

    expect(find.byKey(const Key('shortcut-hint-layout')), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    for (final label in ['⌘1', '⌘2', '⌘3', '⌘U']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(find.byKey(const Key('shortcut-hint-layout')), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(fixture.controller.state.view, FullDiffView.blame);
    expect(find.byKey(const Key('shortcut-hint-layout')), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(fixture.controller.state.layout, DiffLayout.sideBySide);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(fixture.controller.state.appliedScope, DiffScope.fullFile);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(fixture.controller.state.view, FullDiffView.diff);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(fixture.controller.state.view, FullDiffView.history);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(fixture.controller.state.appliedIgnoreWhitespace, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(fixture.controller.state.wrapLines, isFalse);

    final beforeCommand4 = fixture.controller.state.view;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(fixture.controller.state.view, beforeCommand4);
  });

  testWidgets('scope shortcut ignores repeats while its patch is loading', (
    tester,
  ) async {
    final pending = Completer<List<DiffLine>>();
    var fullFileRequests = 0;
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..scopedDiff = ((_, _, _, _, _, scope) {
        if (scope == DiffScope.fullFile) {
          fullFileRequests++;
          return pending.future;
        }
        return Future.value(twoHunkLines);
      })
      ..content = ((_, _, _) async =>
          Uint8List.fromList(utf8.encode('current\n')));
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1200, 800),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyH);
    expect(fullFileRequests, 1);
    expect(controller.state.requestedScope, DiffScope.fullFile);
    pending.complete(twoHunkLines);
    await tester.pumpAndSettle();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyH);
    expect(controller.state.appliedScope, DiffScope.fullFile);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });

  testWidgets(
    'whitespace shortcut ignores repeats while its patch is loading',
    (tester) async {
      final pending = Completer<List<DiffLine>>();
      var whitespaceRequests = 0;
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [fileA])
        ..scopedDiff = ((_, _, _, _, ignoreWhitespace, _) {
          if (ignoreWhitespace) {
            whitespaceRequests++;
            return pending.future;
          }
          return Future.value(twoHunkLines);
        })
        ..content = ((_, _, _) async =>
            Uint8List.fromList(utf8.encode('current\n')));
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1200, 800),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      expect(whitespaceRequests, 1);
      expect(controller.state.requestedIgnoreWhitespace, isTrue);
      pending.complete(twoHunkLines);
      await tester.pumpAndSettle();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      expect(controller.state.appliedIgnoreWhitespace, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    },
  );

  testWidgets('layout and wrap shortcuts ignore key repeats', (tester) async {
    final fixture = await workspaceFixture();
    addTearDown(fixture.controller.dispose);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: const Size(1200, 800),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyU);
    expect(fixture.controller.state.layout, DiffLayout.sideBySide);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyL);
    expect(fixture.controller.state.wrapLines, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });

  testWidgets(
    'deleted Diff content failure retries the old-side file resource',
    (tester) async {
      const deletedFile = GitFileChange(
        path: 'src/deleted-result.pas',
        oldPath: 'src/deleted-original.pas',
        status: 'D',
        additions: 0,
        deletions: 2,
      );
      var contentLoads = 0;
      final requestedPaths = <String>[];
      final repository = FakeFullDiffRepository()
        ..files = ((_, _) async => const [deletedFile])
        ..diff = ((_, _, _, _, _) async => twoHunkLines)
        ..content = ((_, file, _) async {
          requestedPaths.add(file.oldPath ?? file.path);
          contentLoads++;
          if (contentLoads == 1) {
            throw const GitRepositoryException('/repo', 'content failed');
          }
          return resultFile.bytes;
        });
      final controller = FullDiffSessionController(
        repository: repository,
        commits: const [commitA],
        initialIndex: 0,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1070, 650),
      );

      expect(find.byKey(const Key('full-diff-unavailable')), findsOneWidget);
      expect(find.text('src/deleted-original.pas'), findsOneWidget);
      expect(requestedPaths, ['src/deleted-original.pas']);
      expect(repository.contentRequests, hasLength(1));
      expect(repository.diffRequests, hasLength(1));

      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(requestedPaths, [
        'src/deleted-original.pas',
        'src/deleted-original.pas',
      ]);
      expect(repository.contentRequests, hasLength(2));
      expect(repository.diffRequests, hasLength(1));
      expect(controller.state.file.data?.path, 'src/deleted-original.pas');
      expect(find.byKey(const Key('full-diff-unavailable')), findsNothing);
      expect(find.byKey(const Key('unified-list')), findsOneWidget);
    },
  );

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

  for (final view in [FullDiffView.blame]) {
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
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setView(view);
      await pumpWorkspace(
        tester,
        controller: controller,
        size: const Size(1070, 650),
      );
      final listKey = view == FullDiffView.diff
          ? const Key('unified-list')
          : const Key('blame-list');
      final scrollable = find
          .descendant(
            of: find.byKey(listKey),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      if (view == FullDiffView.blame) {
        final list = tester.widget<ListView>(find.byKey(listKey));
        expect(
          (list.childrenDelegate as SliverChildBuilderDelegate).childCount,
          130,
        );
        expect(find.byType(FullDiffHunkHeader), findsNothing);
      }

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

  for (final presentation in [DiffLayout.unified, DiffLayout.sideBySide]) {
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
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        controller.setLayout(presentation);
        await pumpWorkspace(
          tester,
          controller: controller,
          size: const Size(1070, 650),
        );
        final target = controller.state.patch.data!.hunks.last.anchor;
        final targetFinder = find.byKey(
          Key(
            presentation == DiffLayout.unified
                ? 'unified-hunk-1'
                : 'side-by-side-hunk-1',
          ),
        );
        final viewportRect = tester.getRect(
          find.byKey(const Key('content-scrollable')),
        );
        final firstRow = find.byKey(
          Key(
            presentation == DiffLayout.unified
                ? 'unified-line-0-0'
                : 'side-by-side-row-0-0',
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

  testWidgets('a false native editor result is exposed on the editor control', (
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
    final repository = FakeFullDiffRepository();
    repository.files = (_, _) async => const [fileA];
    repository.diff = (_, _, _, _, _) async => twoHunkLines;
    repository.content = (_, _, _) async => resultFile.bytes;
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [workingTree],
      initialIndex: 0,
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
    editorCompleter.completeError(StateError('Native file opener failed'));
    await tester.pump();
    await tester.pump();

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('open-editor')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, contains('Native file opener failed'));
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
