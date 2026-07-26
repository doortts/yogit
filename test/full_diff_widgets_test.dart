import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_code_row.dart';
import 'package:yogit/full_diff_header.dart';
import 'package:yogit/full_diff_hunk_view.dart';
import 'package:yogit/full_diff_inline_view.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_split_view.dart';
import 'package:yogit/full_diff_syntax.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/git.dart';

import 'support/full_diff_fixtures.dart';

void main() {
  testWidgets('keeps the algorithm name fixed beside its selected value', (
    tester,
  ) async {
    DiffAlgorithm? selected;
    await _pumpToolbar(
      tester,
      activeHunkIndex: 1,
      hunkCount: 7,
      algorithm: DiffAlgorithm.histogram,
      onAlgorithmSelected: (value) => selected = value,
    );

    expect(find.text('diff 알고리즘'), findsOneWidget);
    expect(find.text('Histogram'), findsOneWidget);
    expect(find.text('2 / 7'), findsOneWidget);
    expect(find.text('Unified'), findsNothing);
    expect(find.text('Side-by-side'), findsNothing);

    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Patience').last);
    await tester.pumpAndSettle();

    expect(selected, DiffAlgorithm.patience);
  });

  testWidgets('shows only resolved file information and active hunk mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DiffFileHeader(
            file: GitFileChange(
              path: 'lib/full_diff_header.dart',
              status: 'R100',
              additions: 9,
              deletions: 2,
            ),
            path: 'lib/full_diff_header.dart',
            hunkSelected: true,
          ),
        ),
      ),
    );

    expect(find.text('lib/full_diff_header.dart'), findsOneWidget);
    expect(find.text('R100'), findsOneWidget);
    expect(find.text('+9'), findsOneWidget);
    expect(find.text('−2'), findsOneWidget);
    expect(find.text('Hunk'), findsOneWidget);
    for (final absentLabel in const [
      'File',
      'Blame',
      'History',
      'UTF-8',
      'Open in editor',
    ]) {
      expect(find.text(absentLabel), findsNothing);
    }
  });

  testWidgets('distinguishes unknown counts from zero and omits null fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DiffFileHeader(
            file: GitFileChange(
              path: 'assets/logo.bin',
              status: 'M',
              additions: null,
              deletions: null,
            ),
            path: 'assets/logo.bin',
            hunkSelected: false,
          ),
        ),
      ),
    );

    expect(find.text('+—'), findsOneWidget);
    expect(find.text('−—'), findsOneWidget);
    expect(find.text('+0'), findsNothing);
    expect(find.text('−0'), findsNothing);
    expect(find.textContaining('null'), findsNothing);
    expect(find.text('Hunk'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DiffFileHeader(file: null, path: null, hunkSelected: false),
        ),
      ),
    );

    expect(find.text('assets/logo.bin'), findsNothing);
    expect(find.text('M'), findsNothing);
    expect(find.text('+—'), findsNothing);
    expect(find.text('−—'), findsNothing);
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets(
    'uses hunk boundaries while retaining navigation during loading',
    (tester) async {
      var previousCalls = 0;
      var nextCalls = 0;

      await _pumpToolbar(
        tester,
        activeHunkIndex: 0,
        hunkCount: 3,
        loading: true,
        onPreviousHunk: () => previousCalls++,
        onNextHunk: () => nextCalls++,
      );

      expect(_navigationButton(tester, 'Previous hunk').onPressed, isNull);
      expect(_navigationButton(tester, 'Next hunk').onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byTooltip('Next hunk'));
      expect(nextCalls, 1);

      await _pumpToolbar(
        tester,
        activeHunkIndex: 2,
        hunkCount: 3,
        onPreviousHunk: () => previousCalls++,
        onNextHunk: () => nextCalls++,
      );

      expect(_navigationButton(tester, 'Previous hunk').onPressed, isNotNull);
      expect(_navigationButton(tester, 'Next hunk').onPressed, isNull);
      await tester.tap(find.byTooltip('Previous hunk'));
      expect(previousCalls, 1);

      await _pumpToolbar(
        tester,
        activeHunkIndex: 0,
        hunkCount: 0,
        onPreviousHunk: () => previousCalls++,
        onNextHunk: () => nextCalls++,
      );

      expect(_navigationButton(tester, 'Previous hunk').onPressed, isNull);
      expect(_navigationButton(tester, 'Next hunk').onPressed, isNull);
      expect(find.text('0 / 0'), findsOneWidget);
      expect(previousCalls, 1);
      expect(nextCalls, 1);
    },
  );

  testWidgets('clamps direct hunk positions before displaying them', (
    tester,
  ) async {
    await _pumpToolbar(tester, activeHunkIndex: 99, hunkCount: 7);
    expect(find.text('7 / 7'), findsOneWidget);

    await _pumpToolbar(tester, activeHunkIndex: -4, hunkCount: 7);
    expect(find.text('1 / 7'), findsOneWidget);
  });

  testWidgets(
    'exposes one algorithm button and one semantic toggle per option',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      bool? ignoreWhitespace;
      DiffAlgorithm? selectedAlgorithm;
      await _pumpToolbar(
        tester,
        activeHunkIndex: 1,
        hunkCount: 7,
        algorithm: DiffAlgorithm.histogram,
        ignoreWhitespace: false,
        wrapLines: true,
        focusMode: false,
        onAlgorithmSelected: (value) => selectedAlgorithm = value,
        onIgnoreWhitespaceChanged: (value) => ignoreWhitespace = value,
      );

      final algorithmFinder = find.semantics.byLabel('diff 알고리즘: Histogram');
      expect(algorithmFinder, findsOne);
      final algorithmNode = algorithmFinder.evaluate().single;
      expect(algorithmNode.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(
        algorithmNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      tester.semantics.tap(algorithmFinder);
      await tester.pumpAndSettle();
      expect(find.text('Minimal'), findsOneWidget);
      await tester.tap(find.text('Minimal'));
      await tester.pumpAndSettle();
      expect(selectedAlgorithm, DiffAlgorithm.minimal);

      final ignoreFinder = find.semantics.byLabel('Ignore whitespace');
      final wrapFinder = find.semantics.byLabel('Wrap lines');
      final focusFinder = find.semantics.byLabel('Focus mode');
      expect(ignoreFinder, findsOne);
      expect(wrapFinder, findsOne);
      expect(focusFinder, findsOne);
      final ignoreNode = ignoreFinder.evaluate().single;
      final wrapNode = wrapFinder.evaluate().single;
      final focusNode = focusFinder.evaluate().single;
      for (final node in [ignoreNode, wrapNode, focusNode]) {
        expect(
          node.getSemanticsData().flagsCollection.isToggled,
          isNot(ui.Tristate.none),
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
      expect(
        ignoreNode.getSemanticsData().flagsCollection.isToggled,
        ui.Tristate.isFalse,
      );
      expect(
        wrapNode.getSemanticsData().flagsCollection.isToggled,
        ui.Tristate.isTrue,
      );
      expect(
        focusNode.getSemanticsData().flagsCollection.isToggled,
        ui.Tristate.isFalse,
      );

      tester.semantics.tap(ignoreFinder);
      await tester.pump();

      expect(ignoreWhitespace, isTrue);
      semanticsHandle.dispose();
    },
  );

  testWidgets('hunk shows only changed rows for the active block', (
    tester,
  ) async {
    final anchorKeys = {
      for (final hunk in twoHunkDocument.hunks)
        hunk.anchor.id: GlobalKey(debugLabel: hunk.anchor.id),
    };
    await pumpPresentation(
      tester,
      presentation: DiffPresentation.hunk,
      document: twoHunkDocument,
      activeAnchor: twoHunkDocument.hunks.last.anchor,
      anchorKeys: anchorKeys,
    );

    expect(find.text('second old'), findsOneWidget);
    expect(find.text('second new'), findsOneWidget);
    expect(find.text('second context'), findsNothing);
    expect(find.text('first old'), findsNothing);
    expect(
      find.text('SetupBase · lines 20–21 · change 2 of 2'),
      findsOneWidget,
    );
    expect(
      anchorKeys[twoHunkDocument.hunks.last.anchor.id]!.currentContext,
      isNotNull,
    );
  });

  testWidgets('an unwrapped hunk shares one movable horizontal scroll', (
    tester,
  ) async {
    final document = DiffDocument.fromLines([
      const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@ long'),
      DiffLine(
        kind: DiffLineKind.delete,
        text: 'old ${'segment ' * 80}',
        oldNumber: 1,
      ),
      DiffLine(
        kind: DiffLineKind.add,
        text: 'new ${'segment ' * 80}',
        newNumber: 1,
      ),
    ]);
    await tester.pumpWidget(
      qaApp(
        SizedBox(
          width: 320,
          height: 180,
          child: HunkPresentationView(
            document: document,
            activeAnchor: document.hunks.single.anchor,
            path: fileA.path,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final horizontal = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right,
    );
    expect(horizontal, findsOneWidget);
    final position = tester.state<ScrollableState>(horizontal).position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.drag(horizontal, const Offset(-160, 0));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
  });

  testWidgets('inline shows every hunk with three context lines', (
    tester,
  ) async {
    await pumpPresentation(
      tester,
      presentation: DiffPresentation.inline,
      document: twoHunkDocument,
    );

    expect(find.byKey(const Key('inline-hunk-0')), findsOneWidget);
    expect(find.byKey(const Key('inline-hunk-1')), findsOneWidget);
    expect(find.text('context before 3'), findsOneWidget);
    expect(find.text('context after 3'), findsOneWidget);
  });

  testWidgets('inline mounts supplied anchor keys for ensureVisible', (
    tester,
  ) async {
    final anchorKeys = {
      for (final hunk in twoHunkDocument.hunks)
        hunk.anchor.id: GlobalKey(debugLabel: hunk.anchor.id),
    };
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      qaApp(
        SizedBox(
          width: 800,
          height: 200,
          child: InlinePresentationView(
            document: twoHunkDocument,
            activeAnchor: twoHunkDocument.hunks.first.anchor,
            path: fileA.path,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: anchorKeys,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final targetKey = anchorKeys[twoHunkDocument.hunks.last.anchor.id]!;
    expect(targetKey.currentContext, isNotNull);
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller,
      same(controller),
    );

    await Scrollable.ensureVisible(
      targetKey.currentContext!,
      duration: Duration.zero,
      alignment: 0.1,
    );
    await tester.pump();

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('split pairs replacements and hatches a missing side', (
    tester,
  ) async {
    final anchorKey = GlobalKey(debugLabel: 'added-only-anchor');
    await pumpPresentation(
      tester,
      presentation: DiffPresentation.split,
      document: addedOnlyDocument,
      anchorKeys: {addedOnlyDocument.hunks.single.anchor.id: anchorKey},
    );

    expect(find.byKey(const Key('split-missing-old-0')), findsOneWidget);
    expect(find.text('added line'), findsOneWidget);
    expect(anchorKey.currentContext, isNotNull);
  });

  testWidgets('split avoids intrinsic layout for a large unwrapped hunk', (
    tester,
  ) async {
    final document = DiffDocument.fromLines([
      const DiffLine(kind: DiffLineKind.hunk, text: '@@ -0,0 +1,600 @@ large'),
      for (var index = 1; index <= 600; index++)
        DiffLine(
          kind: DiffLineKind.add,
          text: 'added line $index',
          newNumber: index,
        ),
    ]);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      qaApp(
        SizedBox(
          width: 800,
          height: 200,
          child: SplitPresentationView(
            document: document,
            activeAnchor: document.hunks.single.anchor,
            oldPath: fileA.path,
            newPath: fileA.path,
            wrapLines: false,
            showOldSide: true,
            highlighter: fakeHighlighter,
            anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullDiffCodeRow), findsNWidgets(600));
    expect(find.byType(IntrinsicHeight), findsNothing);
  });

  testWidgets('split keeps a deletion hatch when the old side is hidden', (
    tester,
  ) async {
    final deletedOnlyDocument = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +0,0 @@'),
      DiffLine(kind: DiffLineKind.delete, text: 'deleted line', oldNumber: 1),
    ]);

    await tester.pumpWidget(
      qaApp(
        SizedBox(
          width: 400,
          child: SplitPresentationView(
            document: deletedOnlyDocument,
            activeAnchor: deletedOnlyDocument.hunks.single.anchor,
            oldPath: fileA.path,
            newPath: fileA.path,
            wrapLines: false,
            showOldSide: false,
            highlighter: fakeHighlighter,
            anchorKeys: {
              deletedOnlyDocument.hunks.single.anchor.id: GlobalKey(),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('split-missing-new-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hunk empty state and each hunk selection boundary are explicit',
    (tester) async {
      await pumpPresentation(
        tester,
        presentation: DiffPresentation.hunk,
        document: DiffDocument.fromLines(const []),
      );
      expect(find.text('현재 옵션으로 표시할 변경이 없습니다'), findsOneWidget);

      await pumpPresentation(
        tester,
        presentation: DiffPresentation.inline,
        document: twoHunkDocument,
      );
      expect(find.byType(SelectionArea), findsNWidgets(2));
    },
  );

  testWidgets('code rows expose sign current line and word emphasis', (
    tester,
  ) async {
    await tester.pumpWidget(
      qaApp(
        FullDiffCodeRow(
          line: const DiffLine(
            kind: DiffLineKind.add,
            text: 'Scale := WindowPixelRatio;',
            newNumber: 314,
          ),
          path: fileA.path,
          wrapLines: false,
          highlighter: fakeHighlighter,
          current: true,
          wordRanges: const [
            WordRange(text: 'WindowPixelRatio', start: 9, end: 25),
          ],
        ),
      ),
    );

    expect(find.text('+'), findsOneWidget);
    expect(find.text('314'), findsOneWidget);
    expect(find.byKey(const Key('code-row-current-marker')), findsOneWidget);
    expect(find.byKey(const Key('code-row-horizontal-scroll')), findsOneWidget);
    final richText = tester.widget<RichText>(
      find.byKey(const Key('code-row-source-text')),
    );
    final spans = (richText.text as TextSpan).children!.cast<TextSpan>();
    expect(
      spans.any(
        (span) =>
            span.style?.backgroundColor == fullDiffWordChange &&
            span.style?.decoration == TextDecoration.underline,
      ),
      isTrue,
    );
  });
}

Future<void> _pumpToolbar(
  WidgetTester tester, {
  int activeHunkIndex = 0,
  int hunkCount = 1,
  DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
  bool ignoreWhitespace = false,
  bool wrapLines = true,
  bool focusMode = false,
  bool loading = false,
  VoidCallback? onPreviousHunk,
  VoidCallback? onNextHunk,
  ValueChanged<DiffAlgorithm>? onAlgorithmSelected,
  ValueChanged<bool>? onIgnoreWhitespaceChanged,
  ValueChanged<bool>? onWrapLinesChanged,
  ValueChanged<bool>? onFocusModeChanged,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: DiffToolbar(
        activeHunkIndex: activeHunkIndex,
        hunkCount: hunkCount,
        algorithm: algorithm,
        ignoreWhitespace: ignoreWhitespace,
        wrapLines: wrapLines,
        focusMode: focusMode,
        loading: loading,
        onPreviousHunk: onPreviousHunk ?? () {},
        onNextHunk: onNextHunk ?? () {},
        onAlgorithmSelected: onAlgorithmSelected ?? (_) {},
        onIgnoreWhitespaceChanged: onIgnoreWhitespaceChanged ?? (_) {},
        onWrapLinesChanged: onWrapLinesChanged ?? (_) {},
        onFocusModeChanged: onFocusModeChanged ?? (_) {},
      ),
    ),
  ),
);

IconButton _navigationButton(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

Future<void> pumpPresentation(
  WidgetTester tester, {
  required DiffPresentation presentation,
  required DiffDocument document,
  DiffAnchor? activeAnchor,
  Map<String, GlobalKey>? anchorKeys,
}) async {
  final resolvedAnchorKeys =
      anchorKeys ??
      {for (final hunk in document.hunks) hunk.anchor.id: GlobalKey()};
  final child = switch (presentation) {
    DiffPresentation.hunk => HunkPresentationView(
      document: document,
      activeAnchor:
          activeAnchor ??
          (document.hunks.isEmpty ? null : document.hunks.first.anchor),
      path: fileA.path,
      wrapLines: false,
      highlighter: fakeHighlighter,
      anchorKeys: resolvedAnchorKeys,
    ),
    DiffPresentation.inline => InlinePresentationView(
      document: document,
      activeAnchor:
          activeAnchor ??
          (document.hunks.isEmpty ? null : document.hunks.first.anchor),
      path: fileA.path,
      wrapLines: false,
      highlighter: fakeHighlighter,
      anchorKeys: resolvedAnchorKeys,
    ),
    DiffPresentation.split => SplitPresentationView(
      document: document,
      activeAnchor:
          activeAnchor ??
          (document.hunks.isEmpty ? null : document.hunks.first.anchor),
      oldPath: fileA.oldPath ?? fileA.path,
      newPath: fileA.path,
      wrapLines: false,
      showOldSide: true,
      highlighter: fakeHighlighter,
      anchorKeys: resolvedAnchorKeys,
    ),
  };
  await tester.pumpWidget(qaApp(SizedBox(width: 800, child: child)));
  await tester.pumpAndSettle();
}
