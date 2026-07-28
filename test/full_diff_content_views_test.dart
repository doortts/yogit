import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/full_diff_anchor_probe.dart';
import 'package:yogit/full_blame_view.dart';
import 'package:yogit/full_diff_code_row.dart';
import 'package:yogit/full_diff_commit_info_card.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_selectable_row.dart';
import 'package:yogit/full_diff_side_by_side_view.dart';
import 'package:yogit/full_diff_syntax_contract.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/full_diff_unified_view.dart';
import 'package:yogit/full_history_view.dart';
import 'package:yogit/git.dart';

import 'support/full_diff_fixtures.dart';

void main() {
  Future<BlameDocument> pumpInteractiveBlameView(
    WidgetTester tester, {
    bool emptyThirdSummary = false,
    int lineCount = 8,
    Size size = const Size(1000, 600),
    ScrollController? controller,
    FocusOnKeyEventCallback? onOuterKeyEvent,
    Key? viewKey,
    bool wrapLines = false,
    String Function(int line)? sourceForLine,
    FocusNode? focusNode,
    VoidCallback? onMoveToFiles,
    DiffAnchor? activeAnchor,
    FullDiffCommitMessageLoader? loadCommitMessage,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final file = FileDocument.fromBytes(
      revision: commitA.sha,
      path: 'interactive.dart',
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(
        utf8.encode(
          '${[for (var line = 1; line <= lineCount; line++) sourceForLine?.call(line) ?? 'source $line'].join('\n')}\n',
        ),
      ),
      gitMarkedBinary: false,
    );
    final blame = BlameDocument.fromGitLines(file, [
      for (var line = 1; line <= file.lines.length; line++)
        GitBlameLine(
          lineNumber: line,
          sha: '40aff6d123456789',
          author: 'Suwon Chae',
          authorEmail: 'suwon@example.com',
          authorTimestamp: 1704067200,
          summary: emptyThirdSummary && line == 3 ? '' : 'Commit summary $line',
          uncommitted: false,
        ),
    ]);

    Widget view = FullBlameView(
      key: viewKey,
      document: blame,
      hunks: const [],
      activeAnchor: activeAnchor,
      wrapLines: wrapLines,
      highlighter: fakeHighlighter,
      anchorKeys: {
        if (activeAnchor != null)
          activeAnchor.id: GlobalKey(debugLabel: activeAnchor.id),
      },
      controller: controller,
      focusNode: focusNode,
      onMoveToFiles: onMoveToFiles,
      loadCommitMessage: loadCommitMessage,
      showRemoteAvatars: false,
    );
    if (onOuterKeyEvent != null) {
      view = Focus(onKeyEvent: onOuterKeyEvent, child: view);
    }
    await tester.pumpWidget(qaApp(view));
    return blame;
  }

  testWidgets(
    'full-file unified renders the complete patch with its scroll controller',
    (tester) async {
      final document = DiffDocument.fromLines([
        const DiffLine(
          kind: DiffLineKind.hunk,
          text: '@@ -1,314 +1,314 @@ complete file',
        ),
        for (var line = 1; line <= 313; line++)
          DiffLine(
            kind: DiffLineKind.context,
            text: 'unchanged',
            oldNumber: line,
            newNumber: line,
          ),
        const DiffLine(
          kind: DiffLineKind.delete,
          text: 'Log(LOGINFO, OLD MODULE VERSION);',
          oldNumber: 314,
        ),
        const DiffLine(
          kind: DiffLineKind.add,
          text: 'Log(LOGINFO, BASE MODULE VERSION);',
          newNumber: 314,
        ),
      ]);
      final anchor = document.hunks.single.anchor;
      final anchorKey = GlobalKey(debugLabel: anchor.id);
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        qaApp(
          SizedBox(
            width: 640,
            height: 420,
            child: UnifiedPresentationView(
              document: document,
              path: fileA.path,
              activeAnchor: anchor,
              wrapLines: false,
              highlighter: fakeHighlighter,
              anchorKeys: {anchor.id: anchorKey},
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Log(LOGINFO, BASE MODULE VERSION);'),
        500,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('unified-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );

      expect(find.text('314'), findsWidgets);
      expect(find.byKey(const Key('unified-line-0-314')), findsOneWidget);
      expect(find.text('Log(LOGINFO, BASE MODULE VERSION);'), findsOneWidget);
      expect(
        tester
            .widget<ListView>(find.byKey(const Key('unified-list')))
            .controller,
        same(controller),
      );
    },
  );

  testWidgets(
    'unified places the hunk header after context and before changed rows',
    (tester) async {
      final document = DiffDocument.fromLines(const [
        DiffLine(
          kind: DiffLineKind.hunk,
          text: '@@ -1,3 +1,3 @@ replace value',
        ),
        DiffLine(
          kind: DiffLineKind.context,
          text: 'alpha',
          oldNumber: 1,
          newNumber: 1,
        ),
        DiffLine(kind: DiffLineKind.delete, text: 'old value', oldNumber: 2),
        DiffLine(kind: DiffLineKind.add, text: 'new value', newNumber: 2),
        DiffLine(
          kind: DiffLineKind.context,
          text: 'omega',
          oldNumber: 3,
          newNumber: 3,
        ),
      ]);
      final anchor = document.hunks.single.anchor;

      await tester.pumpWidget(
        qaApp(
          UnifiedPresentationView(
            document: document,
            path: 'result.txt',
            activeAnchor: anchor,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: {anchor.id: GlobalKey(debugLabel: anchor.id)},
          ),
        ),
      );

      final header = find.text('replace value · lines 1–3 · change 1 of 1');
      final leadingContext = find.byKey(const Key('unified-line-0-0'));
      final changedRow = find.byKey(const Key('unified-line-0-2'));
      expect(header, findsOneWidget);
      expect(
        tester.getBottomLeft(leadingContext).dy,
        lessThan(tester.getTopLeft(header).dy),
      );
      expect(
        tester.getBottomLeft(header).dy,
        lessThan(tester.getTopLeft(changedRow).dy),
      );
      final renderedLine = tester.widget<FullDiffCodeRow>(changedRow);
      expect(renderedLine.line.kind, DiffLineKind.add);
      expect(renderedLine.line.oldNumber, isNull);
      expect(renderedLine.line.newNumber, 2);
      expect(
        find.descendant(
          of: changedRow,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox && widget.color == fullDiffAddedSource,
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('unified keeps every hunk mounted when the active anchor moves', (
    tester,
  ) async {
    final firstAnchor = twoHunkDocument.hunks.first.anchor;
    final secondAnchor = twoHunkDocument.hunks.last.anchor;
    final firstKey = GlobalKey(debugLabel: firstAnchor.id);
    final secondKey = GlobalKey(debugLabel: secondAnchor.id);
    final keys = {firstAnchor.id: firstKey, secondAnchor.id: secondKey};

    Widget view(DiffAnchor activeAnchor) => qaApp(
      SizedBox(
        width: 640,
        height: 520,
        child: UnifiedPresentationView(
          document: twoHunkDocument,
          path: fileA.path,
          activeAnchor: activeAnchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: keys,
        ),
      ),
    );

    await tester.pumpWidget(view(firstAnchor));

    expect(find.byKey(const Key('unified-hunk-0')), findsOneWidget);
    expect(find.byKey(const Key('unified-hunk-1')), findsOneWidget);
    expect(firstKey.currentContext, isNotNull);
    expect(secondKey.currentContext, isNotNull);
    expect(find.text('first new'), findsOneWidget);
    expect(find.text('second new'), findsOneWidget);
    expect(
      tester
          .widget<FullDiffCodeRow>(find.byKey(const Key('unified-line-0-4')))
          .current,
      isTrue,
    );
    expect(
      tester
          .widget<FullDiffCodeRow>(find.byKey(const Key('unified-line-1-2')))
          .current,
      isFalse,
    );

    await tester.pumpWidget(view(secondAnchor));

    expect(find.byKey(const Key('unified-hunk-0')), findsOneWidget);
    expect(find.byKey(const Key('unified-hunk-1')), findsOneWidget);
    expect(firstKey.currentContext, isNotNull);
    expect(secondKey.currentContext, isNotNull);
    expect(
      tester
          .widget<FullDiffCodeRow>(find.byKey(const Key('unified-line-0-4')))
          .current,
      isFalse,
    );
    expect(
      tester
          .widget<FullDiffCodeRow>(find.byKey(const Key('unified-line-1-2')))
          .current,
      isTrue,
    );
  });

  testWidgets('unified renders deletion rows from every hunk', (tester) async {
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -2 +2 @@ replace value'),
      DiffLine(kind: DiffLineKind.delete, text: 'old value', oldNumber: 2),
      DiffLine(kind: DiffLineKind.add, text: 'new value', newNumber: 2),
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -3 +3,0 @@ delete at EOF'),
      DiffLine(kind: DiffLineKind.delete, text: 'removed value', oldNumber: 3),
    ]);
    final firstAnchor = document.hunks.first.anchor;
    final eofAnchor = document.hunks.last.anchor;

    await tester.pumpWidget(
      qaApp(
        UnifiedPresentationView(
          document: document,
          path: 'old.txt',
          activeAnchor: firstAnchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {
            firstAnchor.id: GlobalKey(debugLabel: firstAnchor.id),
            eofAnchor.id: GlobalKey(debugLabel: eofAnchor.id),
          },
        ),
      ),
    );

    final firstDeletion = tester.widget<FullDiffCodeRow>(
      find.byKey(const Key('unified-line-0-0')),
    );
    final eofDeletion = tester.widget<FullDiffCodeRow>(
      find.byKey(const Key('unified-line-1-0')),
    );
    expect(find.byKey(const Key('unified-hunk-0')), findsOneWidget);
    expect(find.byKey(const Key('unified-hunk-1')), findsOneWidget);
    expect(find.text('old value'), findsOneWidget);
    expect(find.text('removed value'), findsOneWidget);
    expect(firstDeletion.line.kind, DiffLineKind.delete);
    expect(firstDeletion.current, isTrue);
    expect(eofDeletion.line.kind, DiffLineKind.delete);
    expect(eofDeletion.current, isFalse);
  });

  testWidgets('unified skips rich rendering when explicitly disabled', (
    tester,
  ) async {
    final anchor = addedOnlyDocument.hunks.single.anchor;
    await tester.pumpWidget(
      qaApp(
        UnifiedPresentationView(
          document: addedOnlyDocument,
          path: fileA.path,
          activeAnchor: anchor,
          wrapLines: false,
          highlighter: const _ThrowingSyntaxHighlighter(),
          anchorKeys: {anchor.id: GlobalKey(debugLabel: anchor.id)},
          richRenderingEnabled: false,
        ),
      ),
    );

    expect(find.text('added line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unified source can be selected for copying', (tester) async {
    final anchor = addedOnlyDocument.hunks.single.anchor;
    await tester.pumpWidget(
      qaApp(
        UnifiedPresentationView(
          document: addedOnlyDocument,
          path: fileA.path,
          activeAnchor: anchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {anchor.id: GlobalKey(debugLabel: anchor.id)},
        ),
      ),
    );

    expect(
      find.ancestor(
        of: find.text('added line'),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );
  });

  testWidgets('history shows an explicit empty state', (tester) async {
    await tester.pumpWidget(
      qaApp(FullHistoryView(entries: const [], onSelected: (_) {})),
    );

    expect(find.text('No file history'), findsOneWidget);
    expect(find.byKey(const Key('history-list')), findsNothing);
  });

  testWidgets('history arrows immediately commit the controlled selection', (
    tester,
  ) async {
    var selected = historyEntries.first;
    await tester.pumpWidget(
      qaApp(
        StatefulBuilder(
          builder: (context, setState) => FullHistoryView(
            entries: historyEntries,
            selected: selected,
            onSelected: (entry) => setState(() => selected = entry),
          ),
        ),
      ),
    );
    tester
        .widget<Focus>(find.byKey(const Key('history-list-focus')))
        .focusNode!
        .requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(selected, same(historyEntries[1]));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(selected, same(historyEntries.first));
  });

  testWidgets(
    'history arrow navigation keeps selected rows visible in both directions',
    (tester) async {
      final entries = [
        for (var index = 0; index < 30; index++)
          FileHistoryEntry(
            commit: GitCommit(
              sha: 'history-$index',
              shortSha: 'h$index',
              parents: const [],
              author: fixtureIdentity,
              authorTimestamp: 1720573200 - index,
              committer: fixtureIdentity,
              committerTimestamp: 1720573200 - index,
              refs: const [],
              subject: 'History entry $index',
            ),
            path: fileA.path,
            oldPath: null,
            status: 'M',
          ),
      ];
      final focusNode = FocusNode();
      final scrollController = ScrollController();
      addTearDown(focusNode.dispose);
      addTearDown(scrollController.dispose);
      var selected = entries.first;
      await tester.pumpWidget(
        qaApp(
          Center(
            child: SizedBox(
              width: 360,
              height: 150,
              child: StatefulBuilder(
                builder: (context, setState) => FullHistoryView(
                  entries: entries,
                  selected: selected,
                  focusNode: focusNode,
                  controller: scrollController,
                  onSelected: (entry) => setState(() => selected = entry),
                ),
              ),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      void expectSelectedVisible() {
        final row = find.byKey(Key('history-row-${selected.commit.sha}'));
        expect(row, findsOneWidget);
        final viewport = tester.getRect(find.byKey(const Key('history-list')));
        final rowRect = tester.getRect(row);
        expect(rowRect.top, greaterThanOrEqualTo(viewport.top));
        expect(rowRect.bottom, lessThanOrEqualTo(viewport.bottom));
      }

      for (var step = 0; step < 15; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expectSelectedVisible();
      }
      for (var step = 0; step < 12; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expectSelectedVisible();
      }
    },
  );

  testWidgets(
    'history navigation mounts an externally selected offscreen row',
    (tester) async {
      final entries = [
        for (var index = 0; index < 30; index++)
          FileHistoryEntry(
            commit: GitCommit(
              sha: 'offscreen-history-$index',
              shortSha: 'o$index',
              parents: const [],
              author: fixtureIdentity,
              authorTimestamp: 1720573200 - index,
              committer: fixtureIdentity,
              committerTimestamp: 1720573200 - index,
              refs: const [],
              subject: 'Offscreen history entry $index',
            ),
            path: fileA.path,
            oldPath: null,
            status: 'M',
          ),
      ];
      final focusNode = FocusNode();
      final scrollController = ScrollController();
      addTearDown(focusNode.dispose);
      addTearDown(scrollController.dispose);
      var selected = entries.last;
      await tester.pumpWidget(
        qaApp(
          Center(
            child: SizedBox(
              width: 360,
              height: 150,
              child: StatefulBuilder(
                builder: (context, setState) => FullHistoryView(
                  entries: entries,
                  selected: selected,
                  focusNode: focusNode,
                  controller: scrollController,
                  onSelected: (entry) => setState(() => selected = entry),
                ),
              ),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      expect(
        find.byKey(Key('history-row-${entries.last.commit.sha}')),
        findsNothing,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(selected, same(entries[entries.length - 2]));
      final row = find.byKey(Key('history-row-${selected.commit.sha}'));
      expect(row, findsOneWidget);
      final viewport = tester.getRect(find.byKey(const Key('history-list')));
      final rowRect = tester.getRect(row);
      expect(rowRect.top, greaterThanOrEqualTo(viewport.top));
      expect(rowRect.bottom, lessThanOrEqualTo(viewport.bottom));
    },
  );

  testWidgets('history selection and keyboard focus use distinct surfaces', (
    tester,
  ) async {
    final filesFocus = FocusNode();
    addTearDown(filesFocus.dispose);
    var selected = historyEntries.first;
    await tester.pumpWidget(
      qaApp(
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              Focus(focusNode: filesFocus, child: const SizedBox(height: 1)),
              Expanded(
                child: FullHistoryView(
                  entries: historyEntries,
                  selected: selected,
                  onSelected: (entry) => setState(() => selected = entry),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    FullDiffSelectableRowSurface rowSurface(FileHistoryEntry entry) =>
        tester.widget<FullDiffSelectableRowSurface>(
          find.byKey(Key('history-row-${entry.commit.sha}')),
        );
    BoxDecoration rowDecoration(FileHistoryEntry entry) =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byKey(Key('history-row-${entry.commit.sha}')),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;

    expect(rowSurface(historyEntries.first).selected, isTrue);
    expect(rowSurface(historyEntries.first).focused, isFalse);
    expect(rowDecoration(historyEntries.first).color, fullDiffSelection);
    expect(rowDecoration(historyEntries[1]).color, fullDiffCanvas);
    expect(
      tester
          .widget<Text>(find.text(historyEntries.first.commit.subject))
          .style
          ?.color,
      anyOf(fullDiffAccent, Colors.white),
    );
    expect(
      tester.widget<Text>(find.text(fixtureIdentity.name).first).style?.color,
      isNot(anyOf(fullDiffMuted, fullDiffCanvas)),
    );

    tester
        .widget<Focus>(find.byKey(const Key('history-list-focus')))
        .focusNode!
        .requestFocus();
    await tester.pump();
    expect(rowSurface(historyEntries.first).focused, isTrue);
    final focusedBorder = rowDecoration(historyEntries.first).border as Border;
    expect(focusedBorder.top.width, 1);
    expect(focusedBorder.top.color, fullDiffAccent);

    await tester.tap(find.text(historyEntries[1].commit.subject));
    filesFocus.requestFocus();
    await tester.pump();
    expect(selected, same(historyEntries[1]));
    expect(rowSurface(historyEntries[1]).selected, isTrue);
    expect(rowSurface(historyEntries[1]).focused, isFalse);
    expect(rowDecoration(historyEntries[1]).color, fullDiffSelection);
    expect(rowDecoration(historyEntries[1]).border, isNull);
    expect(rowDecoration(historyEntries.first).color, fullDiffCanvas);
  });

  testWidgets('hatched cells clip their painter to the cell bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      qaApp(
        const SizedBox(
          width: 80,
          child: HatchedDiffCell(key: Key('hatched-cell')),
        ),
      ),
    );

    final cell = find.byKey(const Key('hatched-cell'));
    final clip = find.descendant(of: cell, matching: find.byType(ClipRect));
    final paint = find.descendant(of: cell, matching: find.byType(CustomPaint));
    expect(clip, findsOneWidget);
    expect(paint, findsOneWidget);
    expect(tester.getRect(paint), tester.getRect(clip));
  });

  testWidgets('history exposes the selected row as a semantic button', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    await tester.pumpWidget(
      qaApp(
        FullHistoryView(
          entries: historyEntries,
          selected: historyEntries.first,
          onSelected: (_) {},
        ),
      ),
    );

    final selectedSemantics = tester.widget<Semantics>(
      find.ancestor(
        of: find.byKey(Key('history-row-${commitA.sha}')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      ),
    );
    expect(selectedSemantics.properties.button, isTrue);
    expect(selectedSemantics.properties.onTap, isNotNull);
    semanticsHandle.dispose();
  });

  testWidgets('history uses a supplied scroll controller', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      qaApp(
        FullHistoryView(
          entries: historyEntries,
          onSelected: (_) {},
          controller: controller,
        ),
      ),
    );

    expect(
      tester.widget<ListView>(find.byKey(const Key('history-list'))).controller,
      same(controller),
    );
  });

  testWidgets('blame aligns one complete metadata row with every source line', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final file = FileDocument.fromBytes(
      revision: commitA.sha,
      path: 'two.txt',
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(
        utf8.encode('const alpha = false;\nconst beta = true;\n'),
      ),
      gitMarkedBinary: false,
    );
    final blame = BlameDocument.fromGitLines(file, const [
      GitBlameLine(
        lineNumber: 1,
        sha: '',
        author: 'Uncommitted',
        uncommitted: true,
      ),
      GitBlameLine(
        lineNumber: 99,
        sha: '40aff6d123456789',
        author: 'Suwon Chae',
        authorEmail: 'suwon@example.com',
        authorTimestamp: 1704067200,
        summary:
            'Keep this deliberately long summary on one ellipsized metadata line',
        uncommitted: false,
      ),
    ]);
    const anchor = DiffAnchor(hunkIndex: 0, oldLine: 2, newLine: 2);
    const hunk = DiffHunk(
      index: 0,
      oldStart: 2,
      oldCount: 1,
      newStart: 2,
      newCount: 1,
      context: 'replace beta',
      lines: [
        DiffLine(kind: DiffLineKind.delete, text: 'old beta', oldNumber: 2),
        DiffLine(
          kind: DiffLineKind.add,
          text: 'const beta = true;',
          newNumber: 2,
        ),
      ],
      anchor: anchor,
    );
    final anchorKey = GlobalKey(debugLabel: anchor.id);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      qaApp(
        FullBlameView(
          document: blame,
          hunks: const [hunk],
          activeAnchor: anchor,
          wrapLines: false,
          highlighter: const _TokenSyntaxHighlighter(),
          anchorKeys: {anchor.id: anchorKey},
          controller: controller,
        ),
      ),
    );

    expect(find.byKey(const Key('blame-list')), findsOneWidget);
    expect(find.byKey(Key('blame-hunk-header-${anchor.id}')), findsNothing);
    expect(find.byType(BlameSourceRow), findsNWidgets(file.lines.length));
    expect(find.byKey(const Key('blame-line-1')), findsOneWidget);
    expect(find.byKey(const Key('blame-line-2')), findsOneWidget);
    expect(find.byKey(const Key('blame-avatar-2')), findsOneWidget);
    expect(find.byKey(const Key('blame-line-number-2')), findsOneWidget);
    expect(find.byKey(const Key('blame-summary-2')), findsOneWidget);
    expect(find.byKey(const Key('blame-date-2')), findsOneWidget);
    expect(find.byKey(const Key('blame-rail-2')), findsOneWidget);
    expect(find.text('SC'), findsOneWidget);
    expect(find.text('2024-01-01'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('blame-date-1')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(anchorKey.currentContext, isNotNull);
    expect(
      tester.widget<ListView>(find.byKey(const Key('blame-list'))).controller,
      same(controller),
    );
    final avatar = tester.widget<IdentityAvatar>(
      find.byKey(const Key('blame-avatar-2')),
    );
    expect(avatar.identity.name, 'Suwon Chae');
    expect(avatar.identity.email, 'suwon@example.com');
    expect(
      tester.widget<Text>(find.byKey(const Key('blame-summary-2'))).overflow,
      TextOverflow.ellipsis,
    );
    expect(
      tester.getSize(find.byKey(const Key('blame-metadata-2'))).width,
      360,
    );
    expect(tester.getSize(find.byKey(const Key('blame-line-2'))).height, 21);
    expect(
      tester.getSize(find.byKey(const Key('blame-avatar-2'))),
      const Size(20, 20),
    );
    expect(tester.getSize(find.byKey(const Key('blame-rail-2'))).width, 1);
    final orderedColumns = [
      find.byKey(const Key('blame-avatar-2')),
      find.byKey(const Key('blame-line-number-2')),
      find.byKey(const Key('blame-summary-2')),
      find.byKey(const Key('blame-date-2')),
      find.byKey(const Key('blame-rail-2')),
      find.text('const beta = true;'),
    ];
    for (var index = 1; index < orderedColumns.length; index++) {
      expect(
        tester.getTopLeft(orderedColumns[index - 1]).dx,
        lessThan(tester.getTopLeft(orderedColumns[index]).dx),
      );
    }
    final sourceText = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const Key('blame-line-2')),
        matching: find.byKey(const Key('code-row-source-text')),
      ),
    );
    final sourceSpan = sourceText.text as TextSpan;
    expect(
      sourceSpan.children!.whereType<TextSpan>().first.style?.color,
      const Color(0xFFABCDEF),
    );
    final rail = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const Key('blame-rail-2')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(rail.color, const Color(0xFFFF2D95));
    final uncommittedRail = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const Key('blame-rail-1')),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(uncommittedRail.color, fullDiffMuted);
    expect(
      tester
          .widget<FullDiffCodeRow>(
            find.descendant(
              of: find.byKey(const Key('blame-line-2')),
              matching: find.byType(FullDiffCodeRow),
            ),
          )
          .showGutter,
      isFalse,
    );
  });

  testWidgets('wrapped blame source lines can grow beyond the base row height', (
    tester,
  ) async {
    await tester.pumpWidget(
      qaApp(
        const SizedBox(
          width: 360,
          child: BlameSourceRow(
            key: Key('wrapped-blame-row'),
            blame: BlameLine(
              lineNumber: 1,
              sha: '40aff6d1',
              author: 'Suwon Chae',
              uncommitted: false,
            ),
            lineNumber: 1,
            source:
                'const wrappedSource = '
                '"a deliberately long value that needs several visual lines";',
            path: 'wrapped.dart',
            side: FileDocumentSide.result,
            kind: DiffLineKind.context,
            wrapLines: true,
            highlighter: fakeHighlighter,
            current: false,
            viewportWidth: 360,
            showRemoteAvatars: false,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('wrapped-blame-row'))).height,
      greaterThan(21),
    );
    expect(
      tester.getSize(find.byKey(const Key('blame-metadata-1'))).height,
      21,
    );
  });

  testWidgets('blame metadata switches at the compact-width boundary', (
    tester,
  ) async {
    Widget row(double viewportWidth) => qaApp(
      Center(
        child: SizedBox(
          width: viewportWidth,
          height: 60,
          child: BlameSourceRow(
            blame: const BlameLine(
              lineNumber: 1,
              sha: '40aff6d1',
              author: 'Suwon Chae',
              uncommitted: false,
            ),
            lineNumber: 1,
            source: 'const compact = true;',
            path: 'compact.dart',
            side: FileDocumentSide.result,
            kind: DiffLineKind.context,
            wrapLines: false,
            highlighter: fakeHighlighter,
            current: false,
            viewportWidth: viewportWidth,
            showRemoteAvatars: false,
          ),
        ),
      ),
    );

    await tester.pumpWidget(row(899));
    expect(
      tester.getSize(find.byKey(const Key('blame-metadata-1'))).width,
      320,
    );

    await tester.pumpWidget(row(900));
    expect(
      tester.getSize(find.byKey(const Key('blame-metadata-1'))).width,
      360,
    );
  });

  testWidgets('zero and non-hex blame SHAs use the muted rail', (tester) async {
    for (final sha in [
      '0000000000000000000000000000000000000000',
      'not-a-sha',
    ]) {
      await tester.pumpWidget(
        qaApp(
          Center(
            child: SizedBox(
              width: 800,
              height: 60,
              child: BlameSourceRow(
                blame: BlameLine(
                  lineNumber: 1,
                  sha: sha,
                  author: 'Suwon Chae',
                  uncommitted: false,
                ),
                lineNumber: 1,
                source: 'const rail = true;',
                path: 'rail.dart',
                side: FileDocumentSide.result,
                kind: DiffLineKind.context,
                wrapLines: false,
                highlighter: fakeHighlighter,
                current: false,
                viewportWidth: 800,
                showRemoteAvatars: false,
              ),
            ),
          ),
        ),
      );

      final rail = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byKey(const Key('blame-rail-1')),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(rail.color, fullDiffMuted, reason: sha);
    }
  });

  testWidgets('enabled blame avatars display a resolved remote author', (
    tester,
  ) async {
    final requests = <List<String>>[];
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory}) async {
        requests.add(List.unmodifiable(arguments));
        return ProcessResult(
          1,
          0,
          '{"author":{"login":"ada",'
              '"avatar_url":"https://avatars.example/ada.png"},'
              '"committer":null}',
          '',
        );
      },
    );

    await tester.pumpWidget(
      qaApp(
        Center(
          child: SizedBox(
            width: 1000,
            height: 60,
            child: BlameSourceRow(
              blame: const BlameLine(
                lineNumber: 1,
                sha: '40aff6d1',
                author: 'Suwon Chae',
                authorEmail: 'suwon@example.com',
                uncommitted: false,
              ),
              lineNumber: 1,
              source: 'const avatar = true;',
              path: 'avatar.dart',
              side: FileDocumentSide.result,
              kind: DiffLineKind.context,
              wrapLines: false,
              highlighter: fakeHighlighter,
              current: false,
              viewportWidth: 1000,
              avatarService: service,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final avatar = tester.widget<IdentityAvatar>(
      find.byKey(const Key('blame-avatar-1')),
    );
    expect(avatar.remoteAvatar?.login, 'ada');
    expect(requests, hasLength(1));
  });

  testWidgets('blame avatar resolver failures fall back to initials', (
    tester,
  ) async {
    var requests = 0;
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory}) async {
        requests++;
        throw StateError('avatar lookup failed');
      },
    );

    await tester.pumpWidget(
      qaApp(
        Center(
          child: SizedBox(
            width: 1000,
            height: 60,
            child: BlameSourceRow(
              blame: const BlameLine(
                lineNumber: 1,
                sha: '40aff6d1',
                author: 'Suwon Chae',
                authorEmail: 'suwon@example.com',
                uncommitted: false,
              ),
              lineNumber: 1,
              source: 'const fallback = true;',
              path: 'fallback.dart',
              side: FileDocumentSide.result,
              kind: DiffLineKind.context,
              wrapLines: false,
              highlighter: fakeHighlighter,
              current: false,
              viewportWidth: 1000,
              avatarService: service,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final avatar = tester.widget<IdentityAvatar>(
      find.byKey(const Key('blame-avatar-1')),
    );
    expect(avatar.remoteAvatar, isNull);
    expect(find.text('SC'), findsOneWidget);
    expect(requests, 1);
  });

  testWidgets(
    'blame moves the only current row and anchor between source hunks',
    (tester) async {
      final file = FileDocument.fromBytes(
        revision: commitA.sha,
        path: 'result.txt',
        side: FileDocumentSide.result,
        bytes: Uint8List.fromList(
          utf8.encode('zero\nfirst changed\nmiddle\nsecond changed\n'),
        ),
        gitMarkedBinary: false,
      );
      final blame = BlameDocument.fromGitLines(file, const [
        GitBlameLine(
          lineNumber: 1,
          sha: '1111111',
          author: 'First',
          uncommitted: false,
        ),
        GitBlameLine(
          lineNumber: 2,
          sha: '1111111',
          author: 'First',
          uncommitted: false,
        ),
        GitBlameLine(
          lineNumber: 3,
          sha: '2222222',
          author: 'Second',
          uncommitted: false,
        ),
        GitBlameLine(
          lineNumber: 4,
          sha: '2222222',
          author: 'Second',
          uncommitted: false,
        ),
      ]);
      const firstAnchor = DiffAnchor(hunkIndex: 0, oldLine: 2, newLine: 2);
      const secondAnchor = DiffAnchor(hunkIndex: 1, oldLine: 4, newLine: 4);
      const hunks = [
        DiffHunk(
          index: 0,
          oldStart: 2,
          oldCount: 1,
          newStart: 2,
          newCount: 1,
          context: 'first change',
          lines: [
            DiffLine(
              kind: DiffLineKind.delete,
              text: 'first old',
              oldNumber: 2,
            ),
            DiffLine(
              kind: DiffLineKind.add,
              text: 'first changed',
              newNumber: 2,
            ),
          ],
          anchor: firstAnchor,
        ),
        DiffHunk(
          index: 1,
          oldStart: 4,
          oldCount: 1,
          newStart: 4,
          newCount: 1,
          context: 'second change',
          lines: [
            DiffLine(
              kind: DiffLineKind.delete,
              text: 'second old',
              oldNumber: 4,
            ),
            DiffLine(
              kind: DiffLineKind.add,
              text: 'second changed',
              newNumber: 4,
            ),
          ],
          anchor: secondAnchor,
        ),
      ];
      final firstKey = GlobalKey(debugLabel: firstAnchor.id);
      final secondKey = GlobalKey(debugLabel: secondAnchor.id);
      final attached = <String>{};

      await tester.pumpWidget(
        qaApp(
          FullBlameView(
            document: blame,
            hunks: hunks,
            activeAnchor: secondAnchor,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: {firstAnchor.id: firstKey, secondAnchor.id: secondKey},
            onAnchorProbeAttached: (anchor, _) => attached.add(anchor.id),
          ),
        ),
      );

      expect(find.byType(BlameSourceRow), findsNWidgets(file.lines.length));
      expect(
        find.byType(FullDiffAnchorProbe),
        findsNWidgets(file.lines.length),
      );
      expect(find.text('first change'), findsNothing);
      expect(find.text('second change'), findsNothing);
      expect(find.byKey(const Key('blame-current-line-4')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'blame-current-line-',
              ),
        ),
        findsOneWidget,
      );
      expect(firstKey.currentContext, isNull);
      expect(secondKey.currentContext, isNotNull);
      expect(
        tester.getRect(find.byKey(secondKey)),
        tester.getRect(find.byKey(const Key('blame-line-4'))),
      );
      expect(attached, {firstAnchor.id, secondAnchor.id});
      expect(
        tester
            .widget<FullDiffCodeRow>(
              find.descendant(
                of: find.byKey(const Key('blame-line-2')),
                matching: find.byType(FullDiffCodeRow),
              ),
            )
            .line
            .kind,
        DiffLineKind.context,
      );
      expect(
        tester
            .widget<FullDiffCodeRow>(
              find.descendant(
                of: find.byKey(const Key('blame-line-4')),
                matching: find.byType(FullDiffCodeRow),
              ),
            )
            .line
            .kind,
        DiffLineKind.add,
      );

      attached.clear();
      await tester.pumpWidget(
        qaApp(
          FullBlameView(
            document: blame,
            hunks: hunks,
            activeAnchor: firstAnchor,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: {firstAnchor.id: firstKey, secondAnchor.id: secondKey},
            onAnchorProbeAttached: (anchor, _) => attached.add(anchor.id),
          ),
        ),
      );

      expect(find.byKey(const Key('blame-current-line-2')), findsOneWidget);
      expect(firstKey.currentContext, isNotNull);
      expect(secondKey.currentContext, isNull);
      expect(
        tester.getRect(find.byKey(firstKey)),
        tester.getRect(find.byKey(const Key('blame-line-2'))),
      );
      expect(
        tester
            .widget<FullDiffCodeRow>(
              find.descendant(
                of: find.byKey(const Key('blame-line-2')),
                matching: find.byType(FullDiffCodeRow),
              ),
            )
            .line
            .kind,
        DiffLineKind.add,
      );
      expect(
        tester
            .widget<FullDiffCodeRow>(
              find.descendant(
                of: find.byKey(const Key('blame-line-4')),
                matching: find.byType(FullDiffCodeRow),
              ),
            )
            .line
            .kind,
        DiffLineKind.context,
      );
      expect(attached, {firstAnchor.id, secondAnchor.id});
    },
  );

  testWidgets('deletion-only result blame anchors its last source boundary', (
    tester,
  ) async {
    final file = FileDocument.fromBytes(
      revision: commitA.sha,
      path: 'result.txt',
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(utf8.encode('one\ntwo\n')),
      gitMarkedBinary: false,
    );
    final blame = BlameDocument.fromGitLines(file, const [
      GitBlameLine(
        lineNumber: 1,
        sha: '1111111',
        author: 'First',
        uncommitted: false,
      ),
      GitBlameLine(
        lineNumber: 2,
        sha: '2222222',
        author: 'Second',
        uncommitted: false,
      ),
    ]);
    const anchor = DiffAnchor(hunkIndex: 0, oldLine: 3, newLine: null);
    const hunk = DiffHunk(
      index: 0,
      oldStart: 3,
      oldCount: 1,
      newStart: 3,
      newCount: 0,
      context: 'delete at eof',
      lines: [
        DiffLine(kind: DiffLineKind.delete, text: 'removed', oldNumber: 3),
      ],
      anchor: anchor,
    );
    final anchorKey = GlobalKey(debugLabel: anchor.id);

    await tester.pumpWidget(
      qaApp(
        FullBlameView(
          document: blame,
          hunks: const [hunk],
          activeAnchor: anchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {anchor.id: anchorKey},
        ),
      ),
    );

    expect(find.byKey(const Key('blame-current-line-2')), findsOneWidget);
    expect(anchorKey.currentContext, isNotNull);
    expect(
      tester.getRect(find.byKey(anchorKey)),
      tester.getRect(find.byKey(const Key('blame-line-2'))),
    );
    expect(
      tester
          .widget<FullDiffCodeRow>(
            find.descendant(
              of: find.byKey(const Key('blame-line-2')),
              matching: find.byType(FullDiffCodeRow),
            ),
          )
          .line
          .kind,
      DiffLineKind.context,
    );
  });

  testWidgets('addition-only old blame anchors its last source boundary', (
    tester,
  ) async {
    final file = FileDocument.fromBytes(
      revision: commitA.parents.single,
      path: 'old.txt',
      side: FileDocumentSide.old,
      bytes: Uint8List.fromList(utf8.encode('one\ntwo\n')),
      gitMarkedBinary: false,
    );
    final blame = BlameDocument.fromGitLines(file, const [
      GitBlameLine(
        lineNumber: 1,
        sha: '1111111',
        author: 'First',
        uncommitted: false,
      ),
      GitBlameLine(
        lineNumber: 2,
        sha: '2222222',
        author: 'Second',
        uncommitted: false,
      ),
    ]);
    const anchor = DiffAnchor(hunkIndex: 0, oldLine: null, newLine: 3);
    const hunk = DiffHunk(
      index: 0,
      oldStart: 3,
      oldCount: 0,
      newStart: 3,
      newCount: 1,
      context: 'add at eof',
      lines: [DiffLine(kind: DiffLineKind.add, text: 'added', newNumber: 3)],
      anchor: anchor,
    );
    final anchorKey = GlobalKey(debugLabel: anchor.id);

    await tester.pumpWidget(
      qaApp(
        FullBlameView(
          document: blame,
          hunks: const [hunk],
          activeAnchor: anchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {anchor.id: anchorKey},
        ),
      ),
    );

    expect(find.byKey(const Key('blame-current-line-2')), findsOneWidget);
    expect(anchorKey.currentContext, isNotNull);
    expect(
      tester.getRect(find.byKey(anchorKey)),
      tester.getRect(find.byKey(const Key('blame-line-2'))),
    );
    expect(
      tester
          .widget<FullDiffCodeRow>(
            find.descendant(
              of: find.byKey(const Key('blame-line-2')),
              matching: find.byType(FullDiffCodeRow),
            ),
          )
          .line
          .kind,
      DiffLineKind.context,
    );
  });

  testWidgets('old blame marks only its active deleted source line', (
    tester,
  ) async {
    final file = FileDocument.fromBytes(
      revision: commitA.parents.single,
      path: 'old.txt',
      side: FileDocumentSide.old,
      bytes: Uint8List.fromList(utf8.encode('one\nold value\n')),
      gitMarkedBinary: false,
    );
    final blame = BlameDocument.fromGitLines(file, const [
      GitBlameLine(
        lineNumber: 1,
        sha: '1111111',
        author: 'First',
        uncommitted: false,
      ),
      GitBlameLine(
        lineNumber: 2,
        sha: '2222222',
        author: 'Second',
        uncommitted: false,
      ),
    ]);
    const anchor = DiffAnchor(hunkIndex: 0, oldLine: 2, newLine: 2);
    const hunk = DiffHunk(
      index: 0,
      oldStart: 2,
      oldCount: 1,
      newStart: 2,
      newCount: 1,
      context: 'replace value',
      lines: [
        DiffLine(kind: DiffLineKind.delete, text: 'old value', oldNumber: 2),
        DiffLine(kind: DiffLineKind.add, text: 'new value', newNumber: 2),
      ],
      anchor: anchor,
    );

    await tester.pumpWidget(
      qaApp(
        FullBlameView(
          document: blame,
          hunks: const [hunk],
          activeAnchor: anchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {anchor.id: GlobalKey(debugLabel: anchor.id)},
        ),
      ),
    );

    final firstRow = tester.widget<FullDiffCodeRow>(
      find.descendant(
        of: find.byKey(const Key('blame-line-1')),
        matching: find.byType(FullDiffCodeRow),
      ),
    );
    final secondRow = tester.widget<FullDiffCodeRow>(
      find.descendant(
        of: find.byKey(const Key('blame-line-2')),
        matching: find.byType(FullDiffCodeRow),
      ),
    );
    expect(find.byKey(const Key('blame-current-line-2')), findsOneWidget);
    expect(firstRow.line.kind, DiffLineKind.context);
    expect(secondRow.line.kind, DiffLineKind.delete);
    expect(secondRow.line.oldNumber, 2);
    expect(secondRow.line.newNumber, isNull);
    expect(find.byKey(Key('blame-hunk-header-${anchor.id}')), findsNothing);
  });

  testWidgets('empty blame keeps zero source rows without a scroll exception', (
    tester,
  ) async {
    final file = FileDocument.fromBytes(
      revision: commitA.sha,
      path: 'empty.txt',
      side: FileDocumentSide.result,
      bytes: Uint8List(0),
      gitMarkedBinary: false,
    );
    final blame = BlameDocument.fromGitLines(file, const []);
    const anchor = DiffAnchor(hunkIndex: 0, oldLine: 1, newLine: null);
    const hunk = DiffHunk(
      index: 0,
      oldStart: 1,
      oldCount: 1,
      newStart: 1,
      newCount: 0,
      context: 'empty deletion',
      lines: [
        DiffLine(kind: DiffLineKind.delete, text: 'removed', oldNumber: 1),
      ],
      anchor: anchor,
    );
    final anchorKey = GlobalKey(debugLabel: anchor.id);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      qaApp(
        FullBlameView(
          document: blame,
          hunks: const [hunk],
          activeAnchor: anchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {anchor.id: anchorKey},
          controller: controller,
        ),
      ),
    );

    expect(find.byKey(Key('blame-hunk-header-${anchor.id}')), findsNothing);
    expect(find.byKey(const Key('blame-line-1')), findsNothing);
    expect(find.byType(BlameSourceRow), findsNothing);
    expect(anchorKey.currentContext, isNull);
    controller.jumpTo(0);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('blame skips rich rendering when the file disables it', (
    tester,
  ) async {
    final file = FileDocument(
      revision: commitA.sha,
      path: fileA.path,
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(utf8.encode('alpha\n')),
      kind: FileContentKind.utf8,
      lines: const ['alpha'],
      hasTrailingNewline: true,
      disableRichRendering: true,
      fingerprint: '6:0',
    );
    final blame = BlameDocument.fromGitLines(file, const [
      GitBlameLine(
        lineNumber: 1,
        sha: '40aff6d123456789',
        author: 'Suwon Chae',
        uncommitted: false,
      ),
    ]);

    await tester.pumpWidget(
      qaApp(
        FullBlameView(
          document: blame,
          hunks: const [],
          activeAnchor: null,
          wrapLines: false,
          highlighter: const _ThrowingSyntaxHighlighter(),
          anchorKeys: const {},
        ),
      ),
    );

    expect(find.text('alpha'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blame source can be selected for copying', (tester) async {
    final file = FileDocument.fromBytes(
      revision: commitA.sha,
      path: fileA.path,
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(utf8.encode('alpha\n')),
      gitMarkedBinary: false,
    );
    final blame = BlameDocument.fromGitLines(file, const [
      GitBlameLine(
        lineNumber: 1,
        sha: '40aff6d123456789',
        author: 'Suwon Chae',
        uncommitted: false,
      ),
    ]);

    await tester.pumpWidget(
      qaApp(
        FullBlameView(
          document: blame,
          hunks: const [],
          activeAnchor: null,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: const {},
        ),
      ),
    );

    expect(
      find.ancestor(
        of: find.text('alpha'),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );
  });

  testWidgets('blame details load the full commit message', (tester) async {
    final requestedShas = <String>[];
    await pumpInteractiveBlameView(
      tester,
      loadCommitMessage: (sha) async {
        requestedShas.add(sha);
        return 'Full commit message';
      },
    );

    await tester.tap(find.byKey(const Key('blame-line-3')));
    await tester.pump();
    await tester.pump();

    final details = find.byKey(const Key('blame-commit-details-3'));
    expect(requestedShas, ['40aff6d123456789']);
    expect(
      find.descendant(of: details, matching: find.text('Full commit message')),
      findsOneWidget,
    );
  });

  testWidgets('blame hover and selection keep row geometry stable', (
    tester,
  ) async {
    await pumpInteractiveBlameView(tester);
    final row3 = find.byKey(const Key('blame-line-3'));
    final row4 = find.byKey(const Key('blame-line-4'));
    final row6 = find.byKey(const Key('blame-line-6'));
    final beforeRow4 = tester.getTopLeft(row4);

    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(row3));
    await tester.pump();
    expect(find.byKey(const Key('blame-hover-3')), findsOneWidget);

    await tester.tap(row3);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-3')), findsOneWidget);
    final card = find.byKey(const Key('blame-commit-details-3'));
    final numberColumn = find.byKey(const Key('blame-line-number-3'));
    expect(card, findsOneWidget);
    expect(
      tester.getTopLeft(card).dx,
      closeTo(tester.getTopLeft(numberColumn).dx, 0.5),
    );
    final surface = tester.widget<DecoratedBox>(
      find.descendant(
        of: card,
        matching: find.byKey(const Key('full-diff-commit-card-surface')),
      ),
    );
    final border = (surface.decoration as BoxDecoration).border as Border;
    expect(border.top.width, 1);
    expect(border.top.color, fullDiffAccent.withValues(alpha: 0.72));
    expect(tester.getTopLeft(row4), beforeRow4);
    expect(
      tester.getTopLeft(card).dy,
      closeTo(tester.getTopLeft(row3).dy + fullDiffSourceRowHeight * 2, 1),
    );
    expect(
      find.descendant(of: card, matching: find.text('40aff6d')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Suwon Chae')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Commit summary 3')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-4')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('blame-line-4')))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-4')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-4')), findsOneWidget);

    final row6Rect = tester.getRect(row6);
    await tester.tapAt(Offset(row6Rect.left + 100, row6Rect.center.dy));
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-6')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-5')), findsOneWidget);

    await tester.tap(find.byKey(const Key('blame-line-1')));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('blame-line-8')));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-8')), findsOneWidget);
  });

  testWidgets('blame focus selects, navigates, and returns to files', (
    tester,
  ) async {
    final blameFocus = FocusNode();
    addTearDown(blameFocus.dispose);
    var movedToFiles = false;
    await pumpInteractiveBlameView(
      tester,
      focusNode: blameFocus,
      onMoveToFiles: () => movedToFiles = true,
    );

    blameFocus.requestFocus();
    await tester.pump();
    expect(find.byKey(const Key('blame-list-focus')), findsOneWidget);
    expect(find.byKey(const Key('blame-selected-1')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-2')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(movedToFiles, isTrue);
  });

  testWidgets('blame focus initially selects the active anchor line', (
    tester,
  ) async {
    final blameFocus = FocusNode();
    addTearDown(blameFocus.dispose);
    const activeAnchor = DiffAnchor(hunkIndex: 0, oldLine: 4, newLine: 4);
    await pumpInteractiveBlameView(
      tester,
      focusNode: blameFocus,
      activeAnchor: activeAnchor,
    );

    blameFocus.requestFocus();
    await tester.pump();

    expect(find.byKey(const Key('blame-selected-4')), findsOneWidget);
  });

  testWidgets('blame arrow selection scrolls only the next row into view', (
    tester,
  ) async {
    await pumpInteractiveBlameView(
      tester,
      lineCount: 40,
      size: const Size(1000, 220),
    );
    final row20 = find.byKey(const Key('blame-line-20'));
    await tester.scrollUntilVisible(
      row20,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('blame-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(row20),
      alignment: 1,
      duration: Duration.zero,
    );
    await tester.pump();
    final viewport = tester.getRect(find.byKey(const Key('blame-list')));
    expect(tester.getRect(row20).bottom, closeTo(viewport.bottom, 1));

    await tester.tap(row20);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final row21 = find.byKey(const Key('blame-line-21'));
    expect(find.byKey(const Key('blame-selected-21')), findsOneWidget);
    expect(tester.getRect(row21).top, greaterThanOrEqualTo(viewport.top));
    expect(tester.getRect(row21).bottom, lessThanOrEqualTo(viewport.bottom));
  });

  testWidgets('blame ignores every modified Up and Down key', (tester) async {
    var escapedArrowEvents = 0;
    await pumpInteractiveBlameView(
      tester,
      onOuterKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.arrowDown)) {
          escapedArrowEvents++;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    await tester.tap(find.byKey(const Key('blame-line-4')));
    await tester.pump();

    for (final modifier in [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.altLeft,
    ]) {
      for (final arrow in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(arrow);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        expect(
          find.byKey(const Key('blame-selected-4')),
          findsOneWidget,
          reason: '$modifier + $arrow must not move the Blame selection',
        );
      }
    }
    expect(escapedArrowEvents, 8);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-5')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-4')), findsOneWidget);
    expect(escapedArrowEvents, 8);
  });

  testWidgets('blame semantics tap selects the row and gives it key focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpInteractiveBlameView(tester);
    final row = find.semantics.byLabel(RegExp(r'^Line 3, Commit summary 3'));

    expect(
      row.evaluate().single.getSemanticsData().hasAction(
        ui.SemanticsAction.tap,
      ),
      isTrue,
    );
    tester.semantics.tap(row);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-3')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const Key('blame-selected-4')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('blame rows expose one exact semantics label', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpInteractiveBlameView(tester);

    final summaryNode = tester.getSemantics(
      find.byKey(const Key('blame-line-3')),
    );
    expect(summaryNode.label, 'Line 3, Commit summary 3');
    expect(summaryNode.childrenCountInTraversalOrder, 0);

    await pumpInteractiveBlameView(tester, emptyThirdSummary: true);
    final fallbackNode = tester.getSemantics(
      find.byKey(const Key('blame-line-3')),
    );
    expect(fallbackNode.label, 'Line 3, 40aff6d, Suwon Chae');
    expect(fallbackNode.childrenCountInTraversalOrder, 0);
    semantics.dispose();
  });

  testWidgets(
    'blame arrows recover a selected row far outside the lazy cache',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpInteractiveBlameView(
        tester,
        lineCount: 500,
        size: const Size(1000, 220),
        controller: controller,
      );
      final row20 = find.byKey(const Key('blame-line-20'));
      await tester.scrollUntilVisible(
        row20,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('blame-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(row20),
        alignment: 0.5,
        duration: Duration.zero,
      );
      await tester.pump();
      await tester.tap(row20);
      await tester.pump();

      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(row20, findsNothing);

      for (var count = 0; count < 3; count++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pumpAndSettle();

      final row23 = find.byKey(const Key('blame-line-23'));
      final viewport = tester.getRect(find.byKey(const Key('blame-list')));
      expect(find.byKey(const Key('blame-selected-23')), findsOneWidget);
      expect(find.byKey(const Key('blame-commit-details-23')), findsOneWidget);
      expect(tester.getRect(row23).top, greaterThanOrEqualTo(viewport.top));
      expect(tester.getRect(row23).bottom, lessThanOrEqualTo(viewport.bottom));
      expect(
        tester.getTopLeft(find.byKey(const Key('blame-commit-details-23'))).dy,
        closeTo(tester.getTopLeft(row23).dy + fullDiffSourceRowHeight * 2, 1),
      );

      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(row23, findsNothing);

      for (var count = 0; count < 2; count++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      }
      await tester.pumpAndSettle();

      final row21 = find.byKey(const Key('blame-line-21'));
      expect(find.byKey(const Key('blame-selected-21')), findsOneWidget);
      expect(find.byKey(const Key('blame-commit-details-21')), findsOneWidget);
      expect(tester.getRect(row21).top, greaterThanOrEqualTo(viewport.top));
      expect(tester.getRect(row21).bottom, lessThanOrEqualTo(viewport.bottom));
    },
  );

  testWidgets('blame retains a constant number of row GlobalKeys', (
    tester,
  ) async {
    final controller = ScrollController();
    final viewKey = GlobalKey<FullBlameViewState>();
    addTearDown(controller.dispose);
    await pumpInteractiveBlameView(
      tester,
      lineCount: 500,
      size: const Size(1000, 220),
      controller: controller,
      viewKey: viewKey,
    );

    for (final fraction in [0.2, 0.4, 0.6, 0.8, 1.0, 0.0]) {
      controller.jumpTo(controller.position.maxScrollExtent * fraction);
      await tester.pump();
    }

    expect(viewKey.currentState, isNotNull);
    expect(viewKey.currentState!.debugRetainedRowGlobalKeyCount, 1);
    expect(
      tester
          .widget<ListView>(find.byKey(const Key('blame-list')))
          .childrenDelegate,
      isA<SliverChildBuilderDelegate>(),
    );
  });

  testWidgets('wrapped blame arrows use a fraction fallback off cache', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpInteractiveBlameView(
      tester,
      lineCount: 200,
      size: const Size(700, 220),
      controller: controller,
      wrapLines: true,
      sourceForLine: (line) =>
          'line $line ${List.filled(6, 'wrapped source').join(' ')}',
    );
    final row10 = find.byKey(const Key('blame-line-10'));
    final wrappedRowHeight = tester
        .getSize(find.byKey(const Key('blame-line-1')))
        .height;
    controller.jumpTo(wrappedRowHeight * 9);
    await tester.pump();
    expect(row10, findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(row10),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pump();
    expect(wrappedRowHeight, greaterThan(fullDiffSourceRowHeight));
    await tester.tap(row10);
    await tester.pump();

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(row10, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final row11 = find.byKey(const Key('blame-line-11'));
    final viewport = tester.getRect(find.byKey(const Key('blame-list')));
    expect(find.byKey(const Key('blame-selected-11')), findsOneWidget);
    expect(find.byKey(const Key('blame-commit-details-11')), findsOneWidget);
    expect(tester.getRect(row11).top, greaterThanOrEqualTo(viewport.top));
    expect(tester.getRect(row11).bottom, lessThanOrEqualTo(viewport.bottom));
  });

  testWidgets(
    'blame details preserve an empty fallback and expose fallback semantics',
    (tester) async {
      await pumpInteractiveBlameView(tester, emptyThirdSummary: true);

      await tester.tap(find.byKey(const Key('blame-line-3')));
      await tester.pump();

      final details = find.byKey(const Key('blame-commit-details-3'));
      expect(details, findsOneWidget);
      final message = tester.widget<Text>(
        find.descendant(
          of: details,
          matching: find.byKey(const Key('full-diff-commit-message')),
        ),
      );
      expect(message.data, isEmpty);
      expect(
        tester.getSemantics(find.byKey(const Key('blame-line-3'))).label,
        contains('40aff6d'),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('blame-line-3'))).label,
        contains('Suwon Chae'),
      );
    },
  );

  testWidgets(
    'blame row surface prioritizes selection then active hunk then hover',
    (tester) async {
      Future<void> pumpRow({
        required bool selected,
        required bool current,
        required bool hovered,
      }) => tester.pumpWidget(
        qaApp(
          SizedBox(
            width: 600,
            child: BlameSourceRow(
              blame: const BlameLine(
                lineNumber: 1,
                sha: '40aff6d',
                author: 'Suwon Chae',
                uncommitted: false,
              ),
              lineNumber: 1,
              source: 'changed source',
              path: 'changed.dart',
              side: FileDocumentSide.result,
              kind: DiffLineKind.add,
              wrapLines: false,
              highlighter: fakeHighlighter,
              current: current,
              hovered: hovered,
              selected: selected,
              viewportWidth: 600,
              showRemoteAvatars: false,
            ),
          ),
        ),
      );

      await pumpRow(selected: true, current: true, hovered: true);
      expect(find.byKey(const Key('blame-selected-1')), findsOneWidget);
      expect(find.byKey(const Key('blame-active-1')), findsNothing);
      expect(find.byKey(const Key('blame-hover-1')), findsNothing);
      expect(
        tester.widget<FullDiffCodeRow>(find.byType(FullDiffCodeRow)).line.kind,
        DiffLineKind.add,
      );

      await pumpRow(selected: false, current: true, hovered: true);
      expect(find.byKey(const Key('blame-active-1')), findsOneWidget);
      expect(find.byKey(const Key('blame-hover-1')), findsNothing);

      await pumpRow(selected: false, current: false, hovered: true);
      expect(find.byKey(const Key('blame-hover-1')), findsOneWidget);
    },
  );
}

class _ThrowingSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const _ThrowingSyntaxHighlighter();

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) =>
      throw StateError('rich rendering must stay disabled');

  @override
  String? languageForPath(String path) => 'test';
}

class _TokenSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const _TokenSyntaxHighlighter();

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) => const [
    CodeTokenSpan(start: 0, end: 5, style: TextStyle(color: Color(0xFFABCDEF))),
  ];

  @override
  String? languageForPath(String path) => 'test';
}
