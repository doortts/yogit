import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_code_row.dart';
import 'package:yogit/full_diff_header.dart';
import 'package:yogit/full_diff_hunk_header.dart';
import 'package:yogit/full_diff_unified_view.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_side_by_side_view.dart';
import 'package:yogit/full_diff_syntax.dart';
import 'package:yogit/full_diff_syntax_contract.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/full_diff_unavailable_panel.dart';
import 'package:yogit/git.dart';
import 'package:yogit/typography.dart';

import 'support/full_diff_fixtures.dart';

const _sizedFile = GitFileChange(
  path: 'src/drlua.pas',
  status: 'M',
  additions: 12,
  deletions: 4,
  sizeBytes: 1536,
);

void main() {
  final unavailableScenarios = [
    (
      reason: FullDiffUnavailableReason.noChanges,
      attribute: 'UTF-8',
      message: '현재 옵션으로 표시할 변경이 없습니다.',
    ),
    (
      reason: FullDiffUnavailableReason.binary,
      attribute: 'Binary',
      message: '바이너리 파일이라 텍스트 diff를 표시할 수 없습니다.',
    ),
    (
      reason: FullDiffUnavailableReason.unsupportedEncoding,
      attribute: 'Unsupported encoding',
      message: 'UTF-8로 해석할 수 없는 파일이라 텍스트 diff를 표시할 수 없습니다.',
    ),
    (
      reason: FullDiffUnavailableReason.byteLimit,
      attribute: '10 MiB 초과',
      message: '파일이 10 MiB 제한을 초과해 내용을 표시하지 않습니다.',
    ),
    (
      reason: FullDiffUnavailableReason.lineLimit,
      attribute: '200,000줄 초과',
      message: '파일이 200,000줄 제한을 초과해 내용을 표시하지 않습니다.',
    ),
    (
      reason: FullDiffUnavailableReason.gitError,
      attribute: 'Git error',
      message: 'Git에서 이 파일의 변경 내용을 읽지 못했습니다.',
    ),
  ];

  for (final scenario in unavailableScenarios) {
    testWidgets(
      'unavailable panel explains ${scenario.reason.name} in information order',
      (tester) async {
        var retries = 0;
        await tester.pumpWidget(
          qaApp(
            FullDiffUnavailablePanel(
              file: _sizedFile,
              path: _sizedFile.path,
              reason: scenario.reason,
              algorithm: DiffAlgorithm.gitSetting,
              ignoreWhitespace: false,
              error: const FormatException('fixture failure'),
              onRetry: () => retries++,
            ),
          ),
        );

        final path = find.text(_sizedFile.path);
        final summary = find.text('M · +12 −4 · 1.5 KB');
        final attribute = find.text(scenario.attribute);
        final message = find.text(scenario.message);
        expect(find.byKey(const Key('full-diff-unavailable')), findsOneWidget);
        expect(path, findsOneWidget);
        expect(summary, findsOneWidget);
        expect(attribute, findsOneWidget);
        expect(message, findsOneWidget);
        expect(tester.widget<Text>(message).style?.fontSize, 10);
        expect(
          tester.getTopLeft(path).dy,
          lessThan(tester.getTopLeft(summary).dy),
        );
        expect(
          tester.getTopLeft(summary).dy,
          lessThan(tester.getTopLeft(attribute).dy),
        );
        expect(
          tester.getTopLeft(attribute).dy,
          lessThan(tester.getTopLeft(message).dy),
        );
        expect(
          tester.widget<Text>(path).style?.fontFamily,
          technicalTextStyle.fontFamily,
        );
        expect(
          tester.widget<Text>(summary).style?.fontFamily,
          technicalTextStyle.fontFamily,
        );

        if (scenario.reason == FullDiffUnavailableReason.noChanges) {
          expect(find.textContaining('Git setting'), findsOneWidget);
          expect(find.textContaining('공백 포함'), findsOneWidget);
        } else {
          expect(find.textContaining('공백 포함'), findsNothing);
        }

        if (scenario.reason == FullDiffUnavailableReason.gitError) {
          expect(find.textContaining('fixture failure'), findsOneWidget);
          expect(find.text('다시 시도'), findsOneWidget);
          await tester.tap(find.text('다시 시도'));
          expect(retries, 1);
        } else {
          expect(find.textContaining('fixture failure'), findsNothing);
          expect(find.text('다시 시도'), findsNothing);
        }
      },
    );
  }

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

  testWidgets('unified hunk scope renders every hunk in source order', (
    tester,
  ) async {
    final anchorKeys = {
      for (final hunk in twoHunkDocument.hunks)
        hunk.anchor.id: GlobalKey(debugLabel: hunk.anchor.id),
    };
    await tester.pumpWidget(
      qaApp(
        SizedBox(
          width: 640,
          height: 420,
          child: UnifiedPresentationView(
            document: twoHunkDocument,
            activeAnchor: twoHunkDocument.hunks.last.anchor,
            path: fileA.path,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: anchorKeys,
          ),
        ),
      ),
    );

    expect(find.text('first old'), findsOneWidget);
    expect(find.text('first new'), findsOneWidget);
    expect(find.text('second old'), findsOneWidget);
    expect(find.text('second new'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('first old')).dy,
      lessThan(tester.getTopLeft(find.text('second old')).dy),
    );
  });

  final scrollTargetCases = [
    (
      name: 'separated mixed edit',
      document: DiffDocument.fromLines(const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -5,3 +9,3 @@ mixed'),
        DiffLine(
          kind: DiffLineKind.delete,
          text: 'mixed old target',
          oldNumber: 5,
        ),
        DiffLine(
          kind: DiffLineKind.context,
          text: 'separator',
          oldNumber: 6,
          newNumber: 9,
        ),
        DiffLine(
          kind: DiffLineKind.add,
          text: 'mixed result target',
          newNumber: 10,
        ),
      ]),
      target: (oldLine: 5, newLine: 10),
      expectedText: 'mixed result target',
    ),
    (
      name: 'addition-only edit',
      document: DiffDocument.fromLines(const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -0,0 +11 @@ added'),
        DiffLine(
          kind: DiffLineKind.add,
          text: 'addition target',
          newNumber: 11,
        ),
      ]),
      target: (oldLine: null, newLine: 11),
      expectedText: 'addition target',
    ),
    (
      name: 'deletion-only edit',
      document: DiffDocument.fromLines(const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -12 +11,0 @@ deleted'),
        DiffLine(
          kind: DiffLineKind.delete,
          text: 'deletion target',
          oldNumber: 12,
        ),
      ]),
      target: (oldLine: 12, newLine: null),
      expectedText: 'deletion target',
    ),
    (
      name: 'context fallback',
      document: DiffDocument.fromLines(const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -30,2 +31,2 @@ context'),
        DiffLine(
          kind: DiffLineKind.context,
          text: 'context target',
          oldNumber: 30,
          newNumber: 31,
        ),
        DiffLine(kind: DiffLineKind.add, text: 'other change', newNumber: 32),
      ]),
      target: (oldLine: 30, newLine: 31),
      expectedText: 'context target',
    ),
    (
      name: 'paired replacement',
      document: DiffDocument.fromLines(const [
        DiffLine(kind: DiffLineKind.hunk, text: '@@ -40 +40 @@ paired'),
        DiffLine(
          kind: DiffLineKind.delete,
          text: 'paired old target',
          oldNumber: 40,
        ),
        DiffLine(
          kind: DiffLineKind.add,
          text: 'paired result target',
          newNumber: 40,
        ),
      ]),
      target: (oldLine: 40, newLine: 40),
      expectedText: 'paired result target',
    ),
  ];

  for (final layout in DiffLayout.values) {
    for (final scenario in scrollTargetCases) {
      testWidgets(
        '${layout.name} resolves ${scenario.name} to the shared source target',
        (tester) async {
          final scrollTargetKey = GlobalKey(
            debugLabel: '${layout.name}-${scenario.name}',
          );
          await pumpPresentation(
            tester,
            layout: layout,
            document: scenario.document,
            scrollTarget: scenario.target,
            scrollTargetKey: scrollTargetKey,
          );

          final keyedTarget = find.byKey(scrollTargetKey);
          expect(keyedTarget, findsOneWidget);
          expect(
            find.descendant(
              of: keyedTarget,
              matching: find.text(scenario.expectedText),
            ),
            findsWidgets,
          );
        },
      );
    }
  }

  testWidgets('unwrapped unified rows keep their source horizontally movable', (
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
          child: UnifiedPresentationView(
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
    expect(horizontal, findsNWidgets(2));
    final position = tester.state<ScrollableState>(horizontal.last).position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.drag(horizontal.last, const Offset(-160, 0));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    final lastSource = find.descendant(
      of: find.byKey(const Key('unified-line-0-1')),
      matching: find.byKey(const Key('code-row-source-text')),
    );
    expect(lastSource, findsOneWidget);
    expect(
      tester.getRect(lastSource).right,
      lessThanOrEqualTo(tester.getRect(horizontal.last).right),
    );
  });

  testWidgets('unified shows every hunk with three context lines', (
    tester,
  ) async {
    await pumpPresentation(
      tester,
      layout: DiffLayout.unified,
      document: twoHunkDocument,
    );

    expect(find.byKey(const Key('unified-hunk-0')), findsOneWidget);
    expect(find.byKey(const Key('unified-hunk-1')), findsOneWidget);
    expect(find.text('context before 3'), findsOneWidget);
    expect(find.text('context after 3'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('unified-line-0-0')),
        matching: find.text('10'),
      ),
      findsOneWidget,
    );
    final header = find.text('Configure · lines 10–16 · change 1 of 2');
    expect(
      tester.getTopLeft(find.text('context before 1')).dy,
      lessThan(tester.getTopLeft(header).dy),
    );
    expect(
      tester.getTopLeft(find.text('first old')).dy,
      greaterThan(tester.getTopLeft(header).dy),
    );
  });

  testWidgets('unified mounts supplied anchor keys for ensureVisible', (
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
          child: UnifiedPresentationView(
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

  testWidgets('side-by-side pairs replacements and hatches a missing side', (
    tester,
  ) async {
    final anchorKey = GlobalKey(debugLabel: 'added-only-anchor');
    await pumpPresentation(
      tester,
      layout: DiffLayout.sideBySide,
      document: addedOnlyDocument,
      anchorKeys: {addedOnlyDocument.hunks.single.anchor.id: anchorKey},
    );

    expect(find.byKey(const Key('side-by-side-missing-old-0')), findsOneWidget);
    expect(find.text('added line'), findsOneWidget);
    expect(anchorKey.currentContext, isNotNull);
  });

  testWidgets('side-by-side divider resizes every row without keyboard focus', (
    tester,
  ) async {
    var ratio = 0.5;
    var ended = 0;

    Future<void> pump() => tester.pumpWidget(
      qaApp(
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 800,
            height: 300,
            child: SideBySidePresentationView(
              document: twoHunkDocument,
              activeAnchor: twoHunkDocument.hunks.first.anchor,
              oldPath: 'old.pas',
              newPath: 'new.pas',
              wrapLines: false,
              showOldSide: true,
              highlighter: fakeHighlighter,
              anchorKeys: {
                for (final hunk in twoHunkDocument.hunks)
                  hunk.anchor.id: GlobalKey(debugLabel: hunk.anchor.id),
              },
              splitRatio: ratio,
              onSplitRatioChanged: (value) {
                setState(() => ratio = value);
              },
              onSplitRatioChangeEnd: () => ended++,
            ),
          ),
        ),
      ),
    );

    await pump();
    expect(
      tester.getSize(find.byKey(const Key('side-by-side-divider'))).width,
      1,
    );
    expect(
      tester.getSize(find.byKey(const Key('side-by-side-resizer'))).width,
      8,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('side-by-side-resizer')),
        matching: find.byType(Focus),
      ),
      findsNothing,
    );

    Finder cellFor(String text) => find
        .ancestor(of: find.text(text), matching: find.byType(FullDiffCodeRow))
        .first;
    expect(tester.getSize(cellFor('first old')).width, 400);
    expect(tester.getSize(cellFor('first new')).width, 400);

    await tester.drag(
      find.byKey(const Key('side-by-side-resizer')),
      const Offset(80, 0),
    );
    await tester.pump();

    expect(ratio, closeTo(0.6, 0.01));
    expect(ended, 1);
    expect(tester.getSize(cellFor('first old')).width, closeTo(480, 0.01));
    expect(tester.getSize(cellFor('first new')).width, closeTo(320, 0.01));
  });

  testWidgets('side-by-side divider is hidden with the old side', (
    tester,
  ) async {
    await tester.pumpWidget(
      qaApp(
        SizedBox(
          width: 400,
          height: 300,
          child: SideBySidePresentationView(
            document: twoHunkDocument,
            activeAnchor: twoHunkDocument.hunks.first.anchor,
            oldPath: 'old.pas',
            newPath: 'new.pas',
            wrapLines: false,
            showOldSide: false,
            highlighter: fakeHighlighter,
            anchorKeys: {
              for (final hunk in twoHunkDocument.hunks)
                hunk.anchor.id: GlobalKey(debugLabel: hunk.anchor.id),
            },
            splitRatio: 0.65,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('side-by-side-divider')), findsNothing);
    expect(find.byKey(const Key('side-by-side-resizer')), findsNothing);
  });

  testWidgets('side-by-side places leading context before its hunk header', (
    tester,
  ) async {
    await pumpPresentation(
      tester,
      layout: DiffLayout.sideBySide,
      document: twoHunkDocument,
    );

    final header = find.text('Configure · lines 10–16 · change 1 of 2');
    expect(
      find.descendant(
        of: find.byKey(const Key('side-by-side-row-0-0')),
        matching: find.text('10'),
      ),
      findsNWidgets(2),
    );
    expect(
      tester.getTopLeft(find.text('context before 1').first).dy,
      lessThan(tester.getTopLeft(header).dy),
    );
    expect(
      tester.getTopLeft(find.text('first old')).dy,
      greaterThan(tester.getTopLeft(header).dy),
    );
  });

  testWidgets('side-by-side copies paired sources as tab-separated text', (
    tester,
  ) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final document = DiffDocument.fromLines(const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -7 +7 @@ paired'),
      DiffLine(kind: DiffLineKind.delete, text: 'old source', oldNumber: 7),
      DiffLine(kind: DiffLineKind.add, text: 'new source', newNumber: 7),
    ]);
    await pumpPresentation(
      tester,
      layout: DiffLayout.sideBySide,
      document: document,
    );

    final oldParagraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('old source'),
        matching: find.byType(RichText),
      ),
    );
    final newParagraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('new source'),
        matching: find.byType(RichText),
      ),
    );
    await _dragSelection(
      tester,
      oldParagraph,
      0,
      newParagraph,
      'new source'.length,
    );

    Actions.invoke(
      tester.element(find.text('old source')),
      CopySelectionTextIntent.copy,
    );
    await tester.pump();

    expect(copied, ['old source\tnew source']);
    expect(copied.single, isNot(contains('7')));
    expect(copied.single, isNot(contains('−')));
    expect(copied.single, isNot(contains('+')));
  });

  for (final layout in DiffLayout.values) {
    testWidgets('${layout.name} lazily mounts a 600-line unwrapped hunk', (
      tester,
    ) async {
      final document = DiffDocument.fromLines([
        const DiffLine(
          kind: DiffLineKind.hunk,
          text: '@@ -1,300 +1,300 @@ large',
        ),
        for (var index = 1; index <= 300; index++) ...[
          DiffLine(
            kind: DiffLineKind.delete,
            text: 'old $index ${'segment ' * 20}',
            oldNumber: index,
          ),
          DiffLine(
            kind: DiffLineKind.add,
            text: 'new $index ${'segment ' * 20}',
            newNumber: index,
          ),
        ],
      ]);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final highlighter = _CountingSyntaxHighlighter();
      var wordDiffCalls = 0;
      WordChangeRanges wordDiffer(String oldText, String newText) {
        wordDiffCalls++;
        return WordChangeRanges.empty;
      }

      final lastKey = switch (layout) {
        DiffLayout.unified => const Key('unified-line-0-599'),
        DiffLayout.sideBySide => const Key('side-by-side-row-0-299'),
      };
      final view = switch (layout) {
        DiffLayout.unified => UnifiedPresentationView(
          document: document,
          activeAnchor: document.hunks.single.anchor,
          path: fileA.path,
          wrapLines: false,
          highlighter: highlighter,
          wordDiffer: wordDiffer,
          anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
          controller: controller,
        ),
        DiffLayout.sideBySide => SideBySidePresentationView(
          document: document,
          activeAnchor: document.hunks.single.anchor,
          oldPath: fileA.path,
          newPath: fileA.path,
          wrapLines: false,
          showOldSide: true,
          highlighter: highlighter,
          wordDiffer: wordDiffer,
          anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
          controller: controller,
        ),
      };

      await tester.pumpWidget(
        qaApp(SizedBox(width: 800, height: 200, child: view)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FullDiffCodeRow).evaluate().length, lessThan(80));
      expect(highlighter.calls, lessThan(80));
      expect(wordDiffCalls, lessThan(80));
      expect(find.byKey(lastKey), findsNothing);
      expect(find.byType(IntrinsicHeight), findsNothing);

      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(find.byKey(lastKey), findsOneWidget);
    });
  }

  for (final layout in DiffLayout.values) {
    testWidgets('lazy ${layout.name} select all copies every source row', (
      tester,
    ) async {
      final copied = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add(
                (call.arguments as Map<Object?, Object?>)['text']! as String,
              );
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final document = DiffDocument.fromLines([
        const DiffLine(
          kind: DiffLineKind.hunk,
          text: '@@ -0,0 +1,600 @@ copy all',
        ),
        for (var index = 1; index <= 600; index++)
          DiffLine(
            kind: DiffLineKind.add,
            text: 'copy line $index',
            newNumber: index,
          ),
      ]);
      final view = switch (layout) {
        DiffLayout.unified => UnifiedPresentationView(
          document: document,
          activeAnchor: document.hunks.single.anchor,
          path: fileA.path,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
        ),
        DiffLayout.sideBySide => SideBySidePresentationView(
          document: document,
          activeAnchor: document.hunks.single.anchor,
          oldPath: fileA.path,
          newPath: fileA.path,
          wrapLines: false,
          showOldSide: true,
          highlighter: fakeHighlighter,
          anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
        ),
      };

      await tester.pumpWidget(
        qaApp(SizedBox(width: 800, height: 200, child: view)),
      );
      await tester.pumpAndSettle();
      final firstSource = tester.element(find.text('copy line 1'));

      Actions.invoke(
        firstSource,
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();
      Actions.invoke(firstSource, CopySelectionTextIntent.copy);
      await tester.pump();

      expect(copied, hasLength(1));
      expect(copied.single.split('\n'), hasLength(600));
      expect(copied.single, startsWith('copy line 1\n'));
      expect(copied.single, endsWith('\ncopy line 600'));
    });
  }

  for (final layout in DiffLayout.values) {
    testWidgets(
      '${layout.name} first frame lazily materializes a near-limit document',
      (tester) async {
        const lineCount = fullDiffTextLineLimit - 1;
        const changedLine = lineCount ~/ 2;
        final document = DiffDocument.fromLines([
          const DiffLine(
            kind: DiffLineKind.hunk,
            text: '@@ -1,199999 +1,199999 @@ near limit',
          ),
          for (var line = 1; line < changedLine; line++)
            DiffLine(
              kind: DiffLineKind.context,
              text: 'context $line',
              oldNumber: line,
              newNumber: line,
            ),
          const DiffLine(
            kind: DiffLineKind.delete,
            text: 'old',
            oldNumber: changedLine,
          ),
          const DiffLine(
            kind: DiffLineKind.add,
            text: 'new',
            newNumber: changedLine,
          ),
          for (var line = changedLine + 1; line <= lineCount; line++)
            DiffLine(
              kind: DiffLineKind.context,
              text: 'context $line',
              oldNumber: line,
              newNumber: line,
            ),
        ]);
        final metrics = FullDiffLazyBuildMetrics();
        final view = switch (layout) {
          DiffLayout.unified => UnifiedPresentationView(
            document: document,
            activeAnchor: document.hunks.single.anchor,
            path: fileA.path,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
            richRenderingEnabled: false,
            debugMetrics: metrics,
          ),
          DiffLayout.sideBySide => SideBySidePresentationView(
            document: document,
            activeAnchor: document.hunks.single.anchor,
            oldPath: fileA.path,
            newPath: fileA.path,
            wrapLines: false,
            showOldSide: true,
            highlighter: fakeHighlighter,
            anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
            richRenderingEnabled: false,
            debugMetrics: metrics,
          ),
        };

        await tester.pumpWidget(
          qaApp(SizedBox(width: 800, height: 200, child: view)),
        );
        await tester.pump();

        expect(metrics.materializedItemCount, lessThan(100));
        expect(metrics.materializedPairCount, lessThan(100));
        expect(metrics.selectionTextBuildCount, 0);
      },
    );

    testWidgets(
      '${layout.name} disables syntax and word diff for a large patch',
      (tester) async {
        final document = DiffDocument.fromLines([
          const DiffLine(
            kind: DiffLineKind.hunk,
            text: '@@ -1,300 +1,300 @@ large',
          ),
          for (var index = 1; index <= 300; index++) ...[
            DiffLine(
              kind: DiffLineKind.delete,
              text: 'old $index ${'segment ' * 20}',
              oldNumber: index,
            ),
            DiffLine(
              kind: DiffLineKind.add,
              text: 'new $index ${'segment ' * 20}',
              newNumber: index,
            ),
          ],
        ]);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final highlighter = _CountingSyntaxHighlighter();
        var wordDiffCalls = 0;
        WordChangeRanges wordDiffer(String oldText, String newText) {
          wordDiffCalls++;
          return WordChangeRanges.empty;
        }

        final view = switch (layout) {
          DiffLayout.unified => UnifiedPresentationView(
            document: document,
            activeAnchor: document.hunks.single.anchor,
            path: fileA.path,
            wrapLines: false,
            richRenderingEnabled: false,
            highlighter: highlighter,
            wordDiffer: wordDiffer,
            anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
            controller: controller,
          ),
          DiffLayout.sideBySide => SideBySidePresentationView(
            document: document,
            activeAnchor: document.hunks.single.anchor,
            oldPath: fileA.path,
            newPath: fileA.path,
            wrapLines: false,
            showOldSide: true,
            richRenderingEnabled: false,
            highlighter: highlighter,
            wordDiffer: wordDiffer,
            anchorKeys: {document.hunks.single.anchor.id: GlobalKey()},
            controller: controller,
          ),
        };

        await tester.pumpWidget(
          qaApp(SizedBox(width: 800, height: 200, child: view)),
        );
        await tester.pumpAndSettle();
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();

        expect(highlighter.calls, 0);
        expect(wordDiffCalls, 0);
      },
    );
  }

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
          child: SideBySidePresentationView(
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

    expect(find.byKey(const Key('side-by-side-missing-new-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hunk empty state and one lazy selection boundary are explicit', (
    tester,
  ) async {
    for (final layout in DiffLayout.values) {
      await pumpPresentation(
        tester,
        layout: layout,
        document: DiffDocument.fromLines(const []),
      );
      expect(find.text('현재 옵션으로 표시할 변경이 없습니다'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('현재 옵션으로 표시할 변경이 없습니다')).style?.fontSize,
        10,
      );
    }

    await pumpPresentation(
      tester,
      layout: DiffLayout.unified,
      document: twoHunkDocument,
    );
    expect(find.byType(SelectionArea), findsOneWidget);
  });

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
    expect((richText.text as TextSpan).style?.fontSize, 12);
    expect((richText.text as TextSpan).style?.height, 21 / 12);
    expect(tester.widget<Text>(find.text('314')).style?.fontSize, 10);
    expect(tester.widget<Text>(find.text('+')).style?.fontSize, 10);
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

  testWidgets('hunk headers use the approved compact type size', (
    tester,
  ) async {
    await tester.pumpWidget(
      qaApp(
        FullDiffHunkHeader(
          hunk: twoHunkDocument.hunks.first,
          path: fileA.path,
          hunkCount: twoHunkDocument.hunks.length,
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.textContaining('lines')).style?.fontSize,
      12,
    );
  });

  testWidgets('resolves source order once per large copy and per area', (
    tester,
  ) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    var firstAreaResolutions = 0;
    var secondAreaResolutions = 0;
    await tester.pumpWidget(
      qaApp(
        SingleChildScrollView(
          child: Column(
            children: [
              FullDiffSelectionArea(
                debugOnSelectionOrderResolved: () => firstAreaResolutions++,
                child: Column(
                  children: [
                    for (var index = 0; index < 400; index++)
                      FullDiffCodeRow(
                        line: DiffLine(
                          kind: DiffLineKind.add,
                          text: 'bulk source $index',
                          newNumber: index + 1,
                        ),
                        path: fileA.path,
                        wrapLines: false,
                        highlighter: fakeHighlighter,
                      ),
                  ],
                ),
              ),
              FullDiffSelectionArea(
                debugOnSelectionOrderResolved: () => secondAreaResolutions++,
                child: FullDiffCodeRow(
                  line: const DiffLine(
                    kind: DiffLineKind.add,
                    text: 'other area',
                    newNumber: 1,
                  ),
                  path: fileA.path,
                  wrapLines: false,
                  highlighter: fakeHighlighter,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final firstSource = tester.element(find.text('bulk source 0'));

    Actions.invoke(
      firstSource,
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    Actions.invoke(firstSource, CopySelectionTextIntent.copy);

    expect(firstAreaResolutions, 1);
    expect(secondAreaResolutions, 0);
    Actions.invoke(firstSource, CopySelectionTextIntent.copy);

    expect(firstAreaResolutions, 2);
    expect(secondAreaResolutions, 0);
    await tester.pump();

    expect(copied, hasLength(2));
    for (final content in copied) {
      expect(content.split('\n'), hasLength(400));
      expect(content, startsWith('bulk source 0\nbulk source 1\n'));
      expect(content, endsWith('\nbulk source 399'));
      expect(content, isNot(contains('+')));
    }
  });

  testWidgets('refreshes source order after rows move and unregister', (
    tester,
  ) async {
    final copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final rows = ValueNotifier(const ['alpha source', 'beta source']);
    addTearDown(rows.dispose);
    await tester.pumpWidget(
      qaApp(
        ValueListenableBuilder<List<String>>(
          valueListenable: rows,
          builder: (context, values, child) => FullDiffSelectionArea(
            child: Column(
              children: [
                for (final (index, value) in values.indexed)
                  FullDiffCodeRow(
                    key: ValueKey(value),
                    line: DiffLine(
                      kind: DiffLineKind.add,
                      text: value,
                      newNumber: index + 1,
                    ),
                    path: fileA.path,
                    wrapLines: false,
                    highlighter: fakeHighlighter,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final alphaSource = tester.element(find.text('alpha source'));

    Actions.invoke(
      alphaSource,
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    Actions.invoke(alphaSource, CopySelectionTextIntent.copy);
    await tester.pump();
    expect(copied, ['alpha source\nbeta source']);

    final selectionArea = find.ancestor(
      of: find.text('alpha source'),
      matching: find.byType(SelectionArea),
    );
    tester
        .state<SelectionAreaState>(selectionArea)
        .selectableRegion
        .clearSelection();
    rows.value = const ['gamma source', 'beta source'];
    await tester.pumpAndSettle();
    final gammaSource = tester.element(find.text('gamma source'));

    Actions.invoke(
      gammaSource,
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    Actions.invoke(gammaSource, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(copied, ['alpha source\nbeta source', 'gamma source\nbeta source']);
    expect(find.text('alpha source'), findsNothing);
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

Future<void> _dragSelection(
  WidgetTester tester,
  RenderParagraph startParagraph,
  int startOffset,
  RenderParagraph endParagraph,
  int endOffset,
) async {
  final start = startParagraph.localToGlobal(
    startParagraph.getOffsetForCaret(
          TextPosition(offset: startOffset),
          Rect.zero,
        ) +
        const Offset(1, 6),
  );
  final end = endParagraph.localToGlobal(
    endParagraph.getOffsetForCaret(TextPosition(offset: endOffset), Rect.zero) +
        const Offset(-1, 6),
  );
  final gesture = await tester.startGesture(
    start,
    kind: ui.PointerDeviceKind.mouse,
  );
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> pumpPresentation(
  WidgetTester tester, {
  required DiffLayout layout,
  required DiffDocument document,
  DiffAnchor? activeAnchor,
  Map<String, GlobalKey>? anchorKeys,
  DiffSourceTarget? scrollTarget,
  GlobalKey? scrollTargetKey,
}) async {
  final resolvedAnchorKeys =
      anchorKeys ??
      {for (final hunk in document.hunks) hunk.anchor.id: GlobalKey()};
  final child = switch (layout) {
    DiffLayout.unified => UnifiedPresentationView(
      document: document,
      activeAnchor:
          activeAnchor ??
          (document.hunks.isEmpty ? null : document.hunks.first.anchor),
      path: fileA.path,
      wrapLines: false,
      highlighter: fakeHighlighter,
      anchorKeys: resolvedAnchorKeys,
      scrollTarget: scrollTarget,
      scrollTargetKey: scrollTargetKey,
    ),
    DiffLayout.sideBySide => SideBySidePresentationView(
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
      scrollTarget: scrollTarget,
      scrollTargetKey: scrollTargetKey,
    ),
  };
  await tester.pumpWidget(qaApp(SizedBox(width: 800, child: child)));
  await tester.pumpAndSettle();
}

class _CountingSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  int calls = 0;

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) {
    calls++;
    return const [];
  }

  @override
  String? languageForPath(String path) => null;
}
