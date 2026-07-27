import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_blame_view.dart';
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
    await tester.pumpWidget(
      qaApp(
        FullFileView(
          document: empty,
          hunks: const [],
          path: empty.path,
          activeAnchor: null,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: const {},
        ),
      ),
    );
    expect(find.text('Empty file'), findsOneWidget);

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

  testWidgets('history click selects and selected row uses a square fill', (
    tester,
  ) async {
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
    expect(selectedSurface.color, fullDiffSelection);

    await tester.tap(find.text(historyEntries[1].commit.subject));
    expect(selected, same(historyEntries[1]));
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
