import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_blame_view.dart';
import 'package:yogit/full_diff_code_row.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_syntax_contract.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/full_file_view.dart';
import 'package:yogit/full_history_view.dart';
import 'package:yogit/git.dart';

import 'support/full_diff_fixtures.dart';

void main() {
  testWidgets('file view shows the selected side and current source line', (
    tester,
  ) async {
    const anchor = DiffAnchor(hunkIndex: 0, oldLine: 313, newLine: 314);
    final anchorKey = GlobalKey(debugLabel: anchor.id);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      qaApp(
        FullFileView(
          document: resultFile,
          hunks: const [
            DiffHunk(
              index: 0,
              oldStart: 313,
              oldCount: 1,
              newStart: 314,
              newCount: 1,
              context: '',
              lines: [],
              anchor: anchor,
            ),
          ],
          path: 'src/drlua.pas',
          activeAnchor: anchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {anchor.id: anchorKey},
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Log(LOGINFO, BASE MODULE VERSION);'),
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('file-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(find.text('314'), findsOneWidget);
    expect(find.byKey(const Key('file-current-line-314')), findsOneWidget);
    expect(find.text('Log(LOGINFO, BASE MODULE VERSION);'), findsOneWidget);
    expect(anchorKey.currentContext, isNotNull);
    expect(
      tester.widget<ListView>(find.byKey(const Key('file-list'))).controller,
      same(controller),
    );
  });

  testWidgets(
    'file result shows the selected hunk header before its added source row',
    (tester) async {
      final file = FileDocument.fromBytes(
        revision: commitA.sha,
        path: 'result.txt',
        side: FileDocumentSide.result,
        bytes: Uint8List.fromList(utf8.encode('alpha\nnew value\nomega\n')),
        gitMarkedBinary: false,
      );
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
          FullFileView(
            document: file,
            hunks: const [hunk],
            path: file.path,
            activeAnchor: anchor,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: {anchor.id: GlobalKey(debugLabel: anchor.id)},
          ),
        ),
      );

      final header = find.byKey(Key('file-hunk-header-${anchor.id}'));
      final changedRow = find.byKey(const Key('file-line-2'));
      expect(header, findsOneWidget);
      expect(tester.getBottomLeft(header).dy, tester.getTopLeft(changedRow).dy);
      final renderedLine = tester.widget<FullDiffCodeRow>(
        find.descendant(of: changedRow, matching: find.byType(FullDiffCodeRow)),
      );
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

  testWidgets('file moves header anchor and decoration to the active hunk', (
    tester,
  ) async {
    final file = FileDocument.fromBytes(
      revision: commitA.sha,
      path: 'result.txt',
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(
        utf8.encode('zero\nfirst changed\nmiddle\nsecond changed\n'),
      ),
      gitMarkedBinary: false,
    );
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
          DiffLine(kind: DiffLineKind.delete, text: 'first old', oldNumber: 2),
          DiffLine(kind: DiffLineKind.add, text: 'first changed', newNumber: 2),
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
          DiffLine(kind: DiffLineKind.delete, text: 'second old', oldNumber: 4),
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
    final keys = {firstAnchor.id: firstKey, secondAnchor.id: secondKey};

    Widget view(DiffAnchor activeAnchor) => qaApp(
      FullFileView(
        document: file,
        hunks: hunks,
        path: file.path,
        activeAnchor: activeAnchor,
        wrapLines: false,
        highlighter: fakeHighlighter,
        anchorKeys: keys,
      ),
    );

    await tester.pumpWidget(view(firstAnchor));

    expect(
      find.byKey(Key('file-hunk-header-${firstAnchor.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('file-hunk-header-${secondAnchor.id}')),
      findsNothing,
    );
    expect(firstKey.currentContext, isNotNull);
    expect(secondKey.currentContext, isNull);
    expect(
      tester
          .widget<FullDiffCodeRow>(
            find.descendant(
              of: find.byKey(const Key('file-line-2')),
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
              of: find.byKey(const Key('file-line-4')),
              matching: find.byType(FullDiffCodeRow),
            ),
          )
          .line
          .kind,
      DiffLineKind.context,
    );

    await tester.pumpWidget(view(secondAnchor));

    expect(find.byKey(Key('file-hunk-header-${firstAnchor.id}')), findsNothing);
    expect(
      find.byKey(Key('file-hunk-header-${secondAnchor.id}')),
      findsOneWidget,
    );
    expect(firstKey.currentContext, isNull);
    expect(secondKey.currentContext, isNotNull);
    expect(
      tester
          .widget<FullDiffCodeRow>(
            find.descendant(
              of: find.byKey(const Key('file-line-2')),
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
              of: find.byKey(const Key('file-line-4')),
              matching: find.byType(FullDiffCodeRow),
            ),
          )
          .line
          .kind,
      DiffLineKind.add,
    );
  });

  testWidgets('file old side decorates only the active deletion hunk', (
    tester,
  ) async {
    final file = FileDocument.fromBytes(
      revision: commitA.parents.single,
      path: 'old.txt',
      side: FileDocumentSide.old,
      bytes: Uint8List.fromList(utf8.encode('alpha\nold value\n')),
      gitMarkedBinary: false,
    );
    const firstAnchor = DiffAnchor(hunkIndex: 0, oldLine: 2, newLine: 2);
    const eofAnchor = DiffAnchor(hunkIndex: 1, oldLine: 3, newLine: 3);
    const hunks = [
      DiffHunk(
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
        anchor: firstAnchor,
      ),
      DiffHunk(
        index: 1,
        oldStart: 3,
        oldCount: 1,
        newStart: 3,
        newCount: 0,
        context: 'delete at EOF',
        lines: [
          DiffLine(
            kind: DiffLineKind.delete,
            text: 'removed value',
            oldNumber: 3,
          ),
        ],
        anchor: eofAnchor,
      ),
    ];
    final firstKey = GlobalKey(debugLabel: firstAnchor.id);
    final eofKey = GlobalKey(debugLabel: eofAnchor.id);

    await tester.pumpWidget(
      qaApp(
        FullFileView(
          document: file,
          hunks: hunks,
          path: file.path,
          activeAnchor: firstAnchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {firstAnchor.id: firstKey, eofAnchor.id: eofKey},
        ),
      ),
    );

    final firstHeader = find.byKey(Key('file-hunk-header-${firstAnchor.id}'));
    final deletedRow = find.byKey(const Key('file-line-2'));
    final eofHeader = find.byKey(Key('file-hunk-header-${eofAnchor.id}'));
    expect(firstHeader, findsOneWidget);
    expect(eofHeader, findsNothing);
    expect(
      tester.getBottomLeft(firstHeader).dy,
      tester.getTopLeft(deletedRow).dy,
    );
    expect(firstKey.currentContext, isNotNull);
    expect(eofKey.currentContext, isNull);
    final renderedLine = tester.widget<FullDiffCodeRow>(
      find.descendant(of: deletedRow, matching: find.byType(FullDiffCodeRow)),
    );
    expect(renderedLine.line.kind, DiffLineKind.delete);
    expect(renderedLine.line.oldNumber, 2);
    expect(renderedLine.line.newNumber, isNull);
    expect(
      find.descendant(
        of: deletedRow,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == fullDiffDeletedSource,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('file keeps only the active deletion-only result header at EOF', (
    tester,
  ) async {
    final file = FileDocument.fromBytes(
      revision: commitA.sha,
      path: 'result.txt',
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(utf8.encode('alpha\nomega\n')),
      gitMarkedBinary: false,
    );
    const firstAnchor = DiffAnchor(hunkIndex: 0, oldLine: 3, newLine: null);
    const secondAnchor = DiffAnchor(hunkIndex: 1, oldLine: 4, newLine: null);
    const hunks = [
      DiffHunk(
        index: 0,
        oldStart: 3,
        oldCount: 1,
        newStart: 3,
        newCount: 0,
        context: 'first EOF deletion',
        lines: [
          DiffLine(
            kind: DiffLineKind.delete,
            text: 'removed first',
            oldNumber: 3,
          ),
        ],
        anchor: firstAnchor,
      ),
      DiffHunk(
        index: 1,
        oldStart: 4,
        oldCount: 1,
        newStart: 3,
        newCount: 0,
        context: 'second EOF deletion',
        lines: [
          DiffLine(
            kind: DiffLineKind.delete,
            text: 'removed second',
            oldNumber: 4,
          ),
        ],
        anchor: secondAnchor,
      ),
    ];
    final firstKey = GlobalKey(debugLabel: firstAnchor.id);
    final secondKey = GlobalKey(debugLabel: secondAnchor.id);

    await tester.pumpWidget(
      qaApp(
        FullFileView(
          document: file,
          hunks: hunks,
          path: file.path,
          activeAnchor: firstAnchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {firstAnchor.id: firstKey, secondAnchor.id: secondKey},
        ),
      ),
    );

    final lastSourceRow = find.byKey(const Key('file-line-2'));
    final firstHeader = find.byKey(Key('file-hunk-header-${firstAnchor.id}'));
    final secondHeader = find.byKey(Key('file-hunk-header-${secondAnchor.id}'));
    expect(
      tester.getTopLeft(firstHeader).dy,
      tester.getBottomLeft(lastSourceRow).dy,
    );
    expect(secondHeader, findsNothing);
    expect(firstKey.currentContext, isNotNull);
    expect(secondKey.currentContext, isNull);
    for (final lineNumber in [1, 2]) {
      final renderedLine = tester.widget<FullDiffCodeRow>(
        find.descendant(
          of: find.byKey(Key('file-line-$lineNumber')),
          matching: find.byType(FullDiffCodeRow),
        ),
      );
      expect(renderedLine.line.kind, DiffLineKind.context);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('file view distinguishes every non-source state', (tester) async {
    final cases = <(FileContentKind, String)>[
      (FileContentKind.binary, 'Binary file'),
      (FileContentKind.unsupportedEncoding, 'Unsupported encoding'),
      (FileContentKind.tooLarge, 'File too large'),
    ];
    for (final (kind, label) in cases) {
      await tester.pumpWidget(
        qaApp(
          FullFileView(
            document: FileDocument(
              revision: commitA.sha,
              path: fileA.path,
              side: FileDocumentSide.result,
              bytes: Uint8List(0),
              kind: kind,
              lines: const [],
              hasTrailingNewline: false,
              disableRichRendering: true,
              fingerprint: '0:0',
            ),
            hunks: const [],
            path: fileA.path,
            activeAnchor: null,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: const {},
          ),
        ),
      );
      expect(find.text(label), findsOneWidget, reason: '$kind');
    }

    final empty = FileDocument.fromBytes(
      revision: commitA.sha,
      path: 'empty.txt',
      side: FileDocumentSide.result,
      bytes: Uint8List(0),
      gitMarkedBinary: false,
    );
    const emptyAnchor = DiffAnchor(hunkIndex: 0, oldLine: 1, newLine: null);
    final emptyAnchorKey = GlobalKey(debugLabel: emptyAnchor.id);
    await tester.pumpWidget(
      qaApp(
        FullFileView(
          document: empty,
          hunks: const [
            DiffHunk(
              index: 0,
              oldStart: 1,
              oldCount: 1,
              newStart: 1,
              newCount: 0,
              context: 'empty deletion',
              lines: [
                DiffLine(
                  kind: DiffLineKind.delete,
                  text: 'removed',
                  oldNumber: 1,
                ),
              ],
              anchor: emptyAnchor,
            ),
          ],
          path: empty.path,
          activeAnchor: emptyAnchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {emptyAnchor.id: emptyAnchorKey},
        ),
      ),
    );
    expect(find.text('Empty file'), findsOneWidget);
    expect(find.textContaining('empty deletion'), findsOneWidget);
    expect(
      find.byKey(Key('file-hunk-header-${emptyAnchor.id}')),
      findsOneWidget,
    );
    expect(emptyAnchorKey.currentContext, isNotNull);

    final deleted = FileDocument.fromBytes(
      revision: commitA.parents.single,
      path: 'deleted.txt',
      side: FileDocumentSide.old,
      bytes: Uint8List.fromList(utf8.encode('old content\n')),
      gitMarkedBinary: false,
    );
    await tester.pumpWidget(
      qaApp(
        FullFileView(
          document: deleted,
          hunks: const [],
          path: deleted.path,
          activeAnchor: null,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: const {},
        ),
      ),
    );
    expect(
      find.text('Deleted file · showing previous version'),
      findsOneWidget,
    );
    expect(find.text('old content'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('deleted file keeps its banner with every source state', (
    tester,
  ) async {
    final cases = <(FileContentKind, String)>[
      (FileContentKind.binary, 'Binary file'),
      (FileContentKind.unsupportedEncoding, 'Unsupported encoding'),
      (FileContentKind.tooLarge, 'File too large'),
      (FileContentKind.utf8, 'Empty file'),
    ];

    for (final (kind, label) in cases) {
      await tester.pumpWidget(
        qaApp(
          FullFileView(
            document: FileDocument(
              revision: commitA.parents.single,
              path: 'deleted.txt',
              side: FileDocumentSide.old,
              bytes: Uint8List(0),
              kind: kind,
              lines: const [],
              hasTrailingNewline: false,
              disableRichRendering: true,
              fingerprint: '0:0',
            ),
            hunks: const [],
            path: 'deleted.txt',
            activeAnchor: null,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: const {},
          ),
        ),
      );

      expect(
        find.text('Deleted file · showing previous version'),
        findsOneWidget,
        reason: '$kind',
      );
      expect(find.text(label), findsOneWidget, reason: '$kind');
    }
  });

  testWidgets('file view skips rich rendering when the document disables it', (
    tester,
  ) async {
    final document = FileDocument(
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

    await tester.pumpWidget(
      qaApp(
        FullFileView(
          document: document,
          hunks: const [],
          path: document.path,
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

  testWidgets('file source can be selected for copying', (tester) async {
    final document = FileDocument.fromBytes(
      revision: commitA.sha,
      path: fileA.path,
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(utf8.encode('alpha\n')),
      gitMarkedBinary: false,
    );

    await tester.pumpWidget(
      qaApp(
        FullFileView(
          document: document,
          hunks: const [],
          path: document.path,
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

  testWidgets('history shows an explicit empty state', (tester) async {
    await tester.pumpWidget(
      qaApp(FullHistoryView(entries: const [], onSelected: (_) {})),
    );

    expect(find.text('No file history'), findsOneWidget);
    expect(find.byKey(const Key('history-list')), findsNothing);
  });

  testWidgets('history focus does not select until enter', (tester) async {
    FileHistoryEntry? selected;
    await tester.pumpWidget(
      qaApp(
        FullHistoryView(
          entries: historyEntries,
          onSelected: (entry) => selected = entry,
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(selected, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, same(historyEntries[1]));
  });

  testWidgets(
    'history click selects while the selected row keeps a neutral background',
    (tester) async {
      FileHistoryEntry? selected;
      await tester.pumpWidget(
        qaApp(
          FullHistoryView(
            entries: historyEntries,
            selected: historyEntries.first,
            onSelected: (entry) => selected = entry,
          ),
        ),
      );

      expect(find.text(commitA.shortSha), findsOneWidget);
      expect(find.text(commitA.subject), findsOneWidget);
      expect(find.text(fixtureIdentity.name), findsNWidgets(2));
      expect(find.textContaining('ago'), findsNWidgets(2));
      final selectedSurface = tester.widget<ColoredBox>(
        find.byKey(Key('history-row-${commitA.sha}')),
      );
      expect(selectedSurface.color, fullDiffCanvas);

      await tester.tap(find.text(historyEntries[1].commit.subject));
      expect(selected, same(historyEntries[1]));
    },
  );

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

  testWidgets('blame keeps metadata and source rows aligned', (tester) async {
    final file = FileDocument.fromBytes(
      revision: commitA.sha,
      path: 'two.txt',
      side: FileDocumentSide.result,
      bytes: Uint8List.fromList(utf8.encode('alpha\nbeta\n')),
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
        lineNumber: 2,
        sha: '40aff6d123456789',
        author: 'Suwon Chae',
        uncommitted: false,
      ),
    ]);
    const anchor = DiffAnchor(hunkIndex: 0, oldLine: 1, newLine: 1);
    final anchorKey = GlobalKey(debugLabel: anchor.id);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      qaApp(
        FullBlameView(
          document: blame,
          hunks: const [
            DiffHunk(
              index: 0,
              oldStart: 1,
              oldCount: 1,
              newStart: 1,
              newCount: 1,
              context: '',
              lines: [],
              anchor: anchor,
            ),
          ],
          activeAnchor: anchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {anchor.id: anchorKey},
          controller: controller,
        ),
      ),
    );

    expect(find.byKey(const Key('blame-list')), findsOneWidget);
    expect(find.text('·······'), findsOneWidget);
    expect(find.text('U'), findsOneWidget);
    expect(find.text('40aff6d'), findsOneWidget);
    expect(find.text('SC'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(anchorKey.currentContext, isNotNull);
    expect(
      tester.widget<ListView>(find.byKey(const Key('blame-list'))).controller,
      same(controller),
    );
  });

  testWidgets(
    'blame old side orders hunk header metadata gutter and deleted source',
    (tester) async {
      final file = FileDocument.fromBytes(
        revision: commitA.parents.single,
        path: 'old.txt',
        side: FileDocumentSide.old,
        bytes: Uint8List.fromList(utf8.encode('alpha\nold value\n')),
        gitMarkedBinary: false,
      );
      final blame = BlameDocument.fromGitLines(file, const [
        GitBlameLine(
          lineNumber: 1,
          sha: '1111111',
          author: 'Alpha Author',
          uncommitted: false,
        ),
        GitBlameLine(
          lineNumber: 2,
          sha: '2222222',
          author: 'Beta Author',
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

      final header = find.byKey(Key('blame-hunk-header-${anchor.id}'));
      final changedRow = find.byKey(const Key('blame-line-2'));
      final metadata = find.byKey(const Key('blame-metadata-2'));
      final lineNumber = find.descendant(
        of: changedRow,
        matching: find.text('2'),
      );
      expect(header, findsOneWidget);
      expect(tester.getBottomLeft(header).dy, tester.getTopLeft(changedRow).dy);
      final renderedLine = tester.widget<FullDiffCodeRow>(
        find.descendant(of: changedRow, matching: find.byType(FullDiffCodeRow)),
      );
      expect(renderedLine.line.kind, DiffLineKind.delete);
      expect(renderedLine.line.oldNumber, 2);
      expect(renderedLine.line.newNumber, isNull);
      expect(
        tester.getTopLeft(lineNumber).dx,
        lessThan(tester.getTopLeft(metadata).dx),
      );
      expect(
        tester.getTopLeft(metadata).dx,
        lessThan(tester.getTopLeft(find.text('old value')).dx),
      );
      expect(
        find.descendant(
          of: changedRow,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox && widget.color == fullDiffDeletedSource,
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('blame projects only the active hunk header and decoration', (
    tester,
  ) async {
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
          DiffLine(kind: DiffLineKind.delete, text: 'first old', oldNumber: 2),
          DiffLine(kind: DiffLineKind.add, text: 'first changed', newNumber: 2),
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
          DiffLine(kind: DiffLineKind.delete, text: 'second old', oldNumber: 4),
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

    await tester.pumpWidget(
      qaApp(
        FullBlameView(
          document: blame,
          hunks: hunks,
          activeAnchor: secondAnchor,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {firstAnchor.id: firstKey, secondAnchor.id: secondKey},
        ),
      ),
    );

    expect(
      find.byKey(Key('blame-hunk-header-${firstAnchor.id}')),
      findsNothing,
    );
    expect(
      find.byKey(Key('blame-hunk-header-${secondAnchor.id}')),
      findsOneWidget,
    );
    expect(firstKey.currentContext, isNull);
    expect(secondKey.currentContext, isNotNull);
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
  });

  testWidgets('blame keeps the selected hunk header for an empty file', (
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

    expect(find.byKey(Key('blame-hunk-header-${anchor.id}')), findsOneWidget);
    expect(find.textContaining('empty deletion'), findsOneWidget);
    expect(find.byKey(const Key('blame-line-1')), findsNothing);
    expect(anchorKey.currentContext, isNotNull);
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
}

class _ThrowingSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const _ThrowingSyntaxHighlighter();

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) =>
      throw StateError('rich rendering must stay disabled');

  @override
  String? languageForPath(String path) => 'test';
}
