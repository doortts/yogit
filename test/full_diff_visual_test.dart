import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:yogit/full_diff_controller.dart';
import 'package:yogit/full_diff_code_row.dart';
import 'package:yogit/full_diff_header.dart';
import 'package:yogit/full_diff_minimap.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_side_by_side_view.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';

import '../tool/full_diff_visual_diff.dart';
import 'support/full_diff_qa_harness.dart';

typedef QaCase = ({
  String name,
  Size size,
  FullDiffView view,
  DiffLayout layout,
  DiffScope scope,
  bool focus,
  bool whitespace,
  bool wrap,
  int hunk,
  DiffAlgorithm algorithm,
  bool detailOnly,
});

bool isFinalPolishCapture(String name) =>
    RegExp(r'^(18|19|20|21|22|23)-').hasMatch(name);

const qaCases = <QaCase>[
  (
    name: '00-overview-hunk',
    size: Size(782, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '01-diff-inline',
    size: Size(782, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '02-diff-split',
    size: Size(1070, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.sideBySide,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '04-blame-view',
    size: Size(1070, 842),
    view: FullDiffView.blame,
    layout: DiffLayout.sideBySide,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '05-history-view',
    size: Size(1070, 842),
    view: FullDiffView.history,
    layout: DiffLayout.sideBySide,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '06-focus-mode',
    size: Size(1070, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: true,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  // The approved screenshots also show Split selected for cases 07–08.
  (
    name: '07-ignore-whitespace',
    size: Size(1070, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.sideBySide,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: true,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '08-wrap-lines',
    size: Size(1070, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.sideBySide,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: true,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '09-next-change',
    size: Size(1280, 720),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 2,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: true,
  ),
  (
    name: '10-algorithm-histogram',
    size: Size(1280, 720),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.histogram,
    detailOnly: true,
  ),
  (
    name: '11-responsive-650',
    size: Size(650, 549),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '12-responsive-480',
    size: Size(480, 549),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '18-final-default',
    size: Size(1070, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '21-final-focus',
    size: Size(1070, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: true,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '22-final-responsive-650',
    size: Size(650, 549),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '23-final-responsive-480',
    size: Size(480, 549),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '24-unified-hunks',
    size: Size(1070, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 0,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '25-side-by-side-full-file',
    size: Size(1280, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.sideBySide,
    scope: DiffScope.fullFile,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 0,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '26-shortcut-hints',
    size: Size(1280, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 0,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '27-algorithm-chooser',
    size: Size(1280, 842),
    view: FullDiffView.diff,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 0,
    algorithm: DiffAlgorithm.histogram,
    detailOnly: false,
  ),
  (
    name: '28-blame-selection',
    size: Size(1280, 842),
    view: FullDiffView.blame,
    layout: DiffLayout.unified,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 0,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  (
    name: '29-history-resizers',
    size: Size(1280, 842),
    view: FullDiffView.history,
    layout: DiffLayout.sideBySide,
    scope: DiffScope.hunks,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 0,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
];

const followupCases = [
  '13-font-and-back',
  '15-unavailable-panel',
  '16-history-detail',
  '17-history-detail-split',
];

Future<void> capture(
  WidgetTester tester, {
  required String name,
  required Size size,
  required Widget child,
  Future<void> Function()? prepare,
  Finder? target,
  bool fullSurface = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: fullDiffQaTheme(),
      home: ColoredBox(color: fullDiffCanvas, child: child),
    ),
  );
  // DiffScreen deliberately keeps scroll/anchor synchronization frame-driven.
  // Pump a bounded settling window so a long File or Blame fixture cannot
  // create an unbounded golden-test wait while the viewport chooses an anchor.
  await tester.pump();
  // Let the initial proportional jump mount a lazy target, start
  // ensureVisible, and then advance its bounded 100 ms animation.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await prepare?.call();
  await expectLater(
    fullSurface
        ? _captureFullSurface(tester, size)
        : target ?? find.byKey(const Key('full-diff-comparison-canvas')),
    matchesGoldenFile(
      '../docs/superpowers/verification/full-diff-qa/actual/$name.png',
    ),
  );
}

Future<ui.Image> _captureFullSurface(WidgetTester tester, Size size) async {
  final renderView = tester.binding.renderViews.single;
  final rootLayer = renderView.debugLayer!;
  final scene = rootLayer.buildScene(ui.SceneBuilder());
  try {
    return await scene.toImage(size.width.ceil(), size.height.ceil());
  } finally {
    scene.dispose();
  }
}

Future<void> prepareFunctionalCapture(
  WidgetTester tester,
  QaCase scenario,
  FullDiffSessionController controller, {
  required FullDiffColumnWidths? Function() savedWidths,
}) async {
  switch (scenario.name) {
    case '24-unified-hunks':
      await tester.tap(find.text('Hunk'));
      await tester.pumpAndSettle();
      expect(controller.state.appliedScope, DiffScope.fullFile);
      await tester.tap(find.text('Hunk'));
      await tester.pumpAndSettle();
      expect(controller.state.appliedScope, DiffScope.hunks);
      await tester.tap(find.byKey(const Key('next-hunk')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('previous-hunk')));
      await tester.pumpAndSettle();
      expect(controller.state.activeAnchor?.hunkIndex, 0);
    case '25-side-by-side-full-file':
      final fullFilePatch = controller.state.patch.data!;
      expect(fullFilePatch.hunks, hasLength(1));
      expect(fullFilePatch.hunks.single.oldStart, 1);
      expect(fullFilePatch.hunks.single.oldCount, 442);
      expect(fullFilePatch.hunks.single.newStart, 1);
      expect(fullFilePatch.hunks.single.newCount, 450);
      expect(fullFilePatch.rows.first.newNumber, 1);
      expect(fullFilePatch.rows.last.newNumber, 450);
      expect(
        fullFilePatch.rows.any(
          (line) =>
              line.kind == DiffLineKind.context &&
              line.newNumber == 330 &&
              line.text == '  // drlua source line 330',
        ),
        isTrue,
      );
      await tester.tap(find.text('Unified'));
      await tester.pump();
      expect(controller.state.layout, DiffLayout.unified);
      await tester.tap(find.text('Side-by-side'));
      await tester.pump();
      expect(controller.state.layout, DiffLayout.sideBySide);
    case '26-shortcut-hints':
      final before = tester.getRect(find.text('Unified'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft));
      await tester.pump();
      expect(find.byKey(const Key('shortcut-hint-layout')), findsOneWidget);
      expect(find.text('⌘1'), findsOneWidget);
      expect(find.text('⌘2'), findsOneWidget);
      expect(find.text('⌘3'), findsOneWidget);
      expect(find.text('⌘U'), findsOneWidget);
      expect(tester.getRect(find.text('Unified')), before);
      final overlayRect = tester.getRect(find.byType(Overlay));
      final layoutControlRect = tester.getRect(
        find.ancestor(
          of: find.text('Unified'),
          matching: find.byWidgetPredicate(
            (widget) => widget is FullDiffSegmentedControl<DiffLayout>,
          ),
        ),
      );
      final layoutHintRect = tester.getRect(
        find.byKey(const Key('shortcut-hint-layout')),
      );
      expect(overlayRect.contains(layoutControlRect.center), isTrue);
      expect(overlayRect.contains(layoutHintRect.center), isTrue);
      expect(layoutHintRect.top, closeTo(layoutControlRect.bottom + 4, 0.5));
    case '27-algorithm-chooser':
      await tester.tap(find.byKey(const Key('diff-algorithm')));
      await tester.pump();
      expect(
        find.byKey(const Key('algorithm-details-histogram')),
        findsOneWidget,
      );
      expect(controller.state.appliedAlgorithm, DiffAlgorithm.histogram);
    case '28-blame-selection':
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final coveredRow = find.byKey(const Key('blame-line-296'));
      final coveredRowTop = tester.getTopLeft(coveredRow).dy;
      final selectedRow = find.byKey(const Key('blame-line-294'));
      final selectedRect = tester.getRect(selectedRow);
      await tester.tapAt(
        Offset(selectedRect.left + 359, selectedRect.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final card = find.byKey(const Key('blame-commit-details-294'));
      expect(card, findsOneWidget);
      expect(
        tester.getTopLeft(card).dy,
        closeTo(
          tester.getTopLeft(selectedRow).dy + fullDiffSourceRowHeight * 2,
          1,
        ),
      );
      expect(tester.getTopLeft(coveredRow).dy, coveredRowTop);
    case '29-history-resizers':
      final filesPane = find.byKey(const Key('details-files-column'));
      final historyPane = find.byKey(const Key('history-list-pane'));
      final filesBefore = tester.getSize(filesPane).width;
      final historyBefore = tester.getSize(historyPane).width;
      await tester.drag(
        find.byKey(const Key('details-files-column-resizer')),
        const Offset(20, 0),
      );
      await tester.pump();
      await tester.drag(
        find.byKey(const Key('history-list-column-resizer')),
        const Offset(24, 0),
      );
      await tester.pump();
      expect(tester.getSize(filesPane).width, filesBefore + 20);
      expect(tester.getSize(historyPane).width, historyBefore + 24);
      expect(savedWidths()?.files, filesBefore + 20);
      expect(savedWidths()?.history, historyBefore + 24);
    default:
      break;
  }
}

void main() {
  setUpAll(loadFullDiffQaFonts);

  test('macOS window allows the 480px responsive breakpoint', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    expect(
      source,
      contains('contentMinSize = NSSize(width: 480, height: 560)'),
    );
  });

  test('visual diff writes comparison images and reports pixel metrics', () {
    final root = Directory.systemTemp.createTempSync('full-diff-visual-');
    addTearDown(() => root.deleteSync(recursive: true));
    final reference = img.Image(width: 2, height: 1);
    final actual = img.Image(width: 2, height: 1)
      ..setPixelRgba(1, 0, 10, 20, 30, 255);
    final referenceFile = File('${root.path}/reference.png')
      ..writeAsBytesSync(img.encodePng(reference));
    final actualFile = File('${root.path}/actual.png')
      ..writeAsBytesSync(img.encodePng(actual));
    final differenceFile = File('${root.path}/difference.png');
    final sideBySideFile = File('${root.path}/side-by-side.png');

    final metrics = writeVisualDiff(
      referenceFile: referenceFile,
      actualFile: actualFile,
      differenceFile: differenceFile,
      sideBySideFile: sideBySideFile,
    );

    expect(metrics.totalPixels, 2);
    expect(metrics.changedPixels, 1);
    expect(metrics.changedPercent, 50);
    expect(metrics.meanAbsoluteChannelDifference, 10);
    expect(metrics.maxChannelDifference, 30);
    expect(img.decodePng(differenceFile.readAsBytesSync())?.width, 2);
    expect(img.decodePng(sideBySideFile.readAsBytesSync())?.width, 4);
  });

  test('final QA fixture covers byte-size and blame metadata states', () {
    expect(qaFiles.map((file) => file.sizeBytes), [3174, 847, 6963, null]);
    expect(qaBlameLines[312].authorEmail, 'suwon.chae@example.com');
    expect(qaBlameLines[312].authorTimestamp, 1782259200);
    expect(
      qaBlameLines[312].summary,
      'Persist Retina-aware window dimensions while restoring saved display state',
    );
  });

  testWidgets('1070px keeps both approved global headers on one line', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1070, 842);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          surfaceSize: const Size(1070, 842),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getCenter(find.byKey(const Key('file-path-chip'))).dy,
      closeTo(tester.getCenter(find.text('Diff')).dy, 0.5),
    );
    expect(
      tester.getCenter(find.text('집중 모드')).dy,
      closeTo(tester.getCenter(find.text('편집기로 열기')).dy, 0.5),
    );
    expect(
      tester.getCenter(find.text('diff 알고리즘')).dy,
      closeTo(
        tester.getCenter(find.byKey(const Key('diff-algorithm-value'))).dy,
        0.5,
      ),
    );
    expect(
      tester.getCenter(find.text('diff 알고리즘')).dy,
      closeTo(
        tester.getCenter(find.byKey(const Key('change-counter'))).dy,
        0.5,
      ),
    );
    expect(find.text('주변 커밋'), findsNothing);
    expect(find.text('변경 파일'), findsOneWidget);
    final openEditorInk = find
        .ancestor(
          of: find.byKey(const Key('open-editor')),
          matching: find.byType(InkWell),
        )
        .first;
    expect(tester.widget<InkWell>(openEditorInk).onTap, isNotNull);
  });

  testWidgets(
    'QA workspace enables the editor through a loaded worktree file',
    (tester) async {
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final controller = await qaControllerFor();
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(782, 842);
      await tester.pumpWidget(
        MaterialApp(
          theme: fullDiffQaTheme(),
          home: FullDiffQaProductShell(controller: controller),
        ),
      );
      await tester.pump();

      expect(controller.state.selectedCommit.isWorkingTree, isTrue);
      expect(controller.state.selectedCommit.shortSha, '40aff6d');
      expect(controller.state.selectedFile?.status.startsWith('D'), isFalse);
      expect(controller.state.file.data, isNotNull);
      final openEditorInk = find
          .ancestor(
            of: find.byKey(const Key('open-editor')),
            matching: find.byType(InkWell),
          )
          .first;
      expect(tester.widget<InkWell>(openEditorInk).onTap, isNotNull);
      expect(find.text('working tree'), findsNothing);
      expect(find.text('40aff6d'), findsNothing);
      expect(find.text('src/drlua.pas'), findsWidgets);
    },
  );

  testWidgets('product shell begins at x=0 without comparison canvas inset', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    for (final width in [782.0, 480.0]) {
      tester.view.physicalSize = Size(width, 842);
      await tester.pumpWidget(
        MaterialApp(
          theme: fullDiffQaTheme(),
          home: FullDiffQaProductShell(controller: controller),
        ),
      );
      await tester.pump();

      expect(
        tester.getRect(find.byKey(const Key('full-diff-product-shell'))).left,
        0,
        reason: '${width}px product shell',
      );
      expect(
        tester.getRect(find.byKey(const Key('file-path-chip'))).left,
        greaterThanOrEqualTo(fullDiffOuterPadding + 10),
      );
    }
  });

  testWidgets('comparison canvas owns the 16px workspace inset', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(782, 842);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          surfaceSize: const Size(782, 842),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getRect(find.byKey(const Key('full-diff-product-shell'))).left,
      16,
    );
  });

  testWidgets('650px keeps the changed files title to exactly two lines', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(650, 549);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          surfaceSize: const Size(650, 549),
        ),
      ),
    );
    await tester.pump();

    final title = find.text('변경 파일');
    expect(tester.getSize(title).width, greaterThanOrEqualTo(24));
    expect(tester.getSize(title).height, lessThanOrEqualTo(33));

    final selectedFile = find.byKey(const Key('selected-file-src/drlua.pas'));
    final path = find.descendant(
      of: selectedFile,
      matching: find.text('src/drlua.pas'),
    );
    final stats = find.descendant(
      of: selectedFile,
      matching: find.text('+12 −4 · 3.1 KB'),
    );
    expect(tester.getSize(path).width, greaterThan(70));
    expect(
      tester.getTopLeft(stats).dy,
      greaterThan(tester.getBottomLeft(path).dy),
    );
  });

  testWidgets('480px keeps all trailing diff controls on one line', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 549);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          surfaceSize: const Size(480, 549),
        ),
      ),
    );
    await tester.pump();

    final settingsY = tester
        .getCenter(find.byKey(const Key('diff-algorithm')))
        .dy;
    for (final key in [
      const Key('diff-algorithm'),
      const Key('ignore-whitespace'),
      const Key('wrap-lines'),
    ]) {
      expect(tester.getCenter(find.byKey(key)).dy, closeTo(settingsY, 0.5));
    }
    final navigationY = tester
        .getCenter(find.byKey(const Key('change-counter')))
        .dy;
    expect(tester.getCenter(find.text('Hunk')).dy, closeTo(navigationY, 0.5));
    expect(
      tester.getCenter(find.text('Unified')).dy,
      closeTo(navigationY, 0.5),
    );
    expect(
      tester.getCenter(find.text('Side-by-side')).dy,
      closeTo(navigationY, 0.5),
    );
  });

  testWidgets('480px initial hunk keeps the unwrapped source at x=0', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor(activeHunkIndex: 1);
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 549);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaProductShell(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final content = find.byKey(const Key('content-scrollable'));
    final horizontal = find.descendant(
      of: content,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
    );
    final horizontalScrollable = find
        .descendant(of: horizontal, matching: find.byType(Scrollable))
        .first;
    final horizontalPosition = tester
        .state<ScrollableState>(horizontalScrollable)
        .position;
    final header = find.byKey(Key('unified-hunk-1'));
    final line313 = find.byKey(const Key('unified-line-1-3'));
    final left = tester.getRect(content).left;

    expect(horizontalPosition.pixels, 0);
    expect(tester.getRect(header).left, left);
    expect(tester.getRect(line313).left, left);
    expect(
      find.descendant(of: line313, matching: find.text('313')),
      findsOneWidget,
    );
  });

  testWidgets('focus mode stretches both global headers to the content edge', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor(focusMode: true);
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1070, 842);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          surfaceSize: const Size(1070, 842),
        ),
      ),
    );
    await tester.pump();

    final back = tester.getRect(find.byKey(const Key('full-diff-back')));
    final fileIcon = tester.getRect(find.byIcon(Icons.code));
    final path = tester.getRect(find.byKey(const Key('file-path-chip')));
    expect(back.left, lessThan(80));
    expect(back.right, lessThan(fileIcon.left));
    expect(fileIcon.right, lessThan(path.left));
    final focus = tester.getRect(find.text('탐색 패널'));
    final editor = tester.getRect(find.text('편집기로 열기'));
    expect(focus.right, lessThan(editor.left));
    expect(find.byKey(const Key('commit-files-pane')), findsNothing);
    expect(find.byKey(const Key('diff-column')), findsOneWidget);
  });

  for (final layout in DiffLayout.values) {
    testWidgets('${layout.name} honors an initially selected second hunk', (
      tester,
    ) async {
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final controller = await qaControllerFor(
        layout: layout,
        activeHunkIndex: 1,
      );
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(782, 842);
      await tester.pumpWidget(
        MaterialApp(
          theme: fullDiffQaTheme(),
          home: FullDiffQaComparisonCanvas(
            controller: controller,
            surfaceSize: const Size(782, 842),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final activeAnchor = controller.state.activeAnchor!;
      expect(activeAnchor.hunkIndex, 1);
      final target = switch (layout) {
        DiffLayout.unified => find.byKey(const Key('unified-hunk-1')),
        DiffLayout.sideBySide => find.byKey(const Key('side-by-side-hunk-1')),
      };
      expect(target, findsOneWidget);
      final viewport = tester.getRect(
        find.byKey(const Key('content-scrollable')),
      );
      expect(
        tester.getTopLeft(target).dy,
        lessThanOrEqualTo(
          viewport.top + (layout == DiffLayout.unified ? 130 : 2),
        ),
      );
    });
  }

  testWidgets('full-file unified keeps one whole-file hunk', (tester) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor(
      view: FullDiffView.diff,
      scope: DiffScope.fullFile,
      activeHunkIndex: 0,
    );
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1070, 842);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          surfaceSize: const Size(1070, 842),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final patch = controller.state.patch.data!;
    expect(find.byKey(const Key('content-scrollable')), findsOneWidget);
    expect(patch.hunks, hasLength(1));
    expect(patch.rows.first.newNumber, 1);
    expect(patch.rows.last.newNumber, 450);
  });

  testWidgets('final polish canvas uses approved desktop geometry', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1070, 842);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          finalPolishGeometry: true,
          surfaceSize: const Size(1070, 842),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getRect(find.byKey(const Key('full-diff-product-shell'))),
      const Rect.fromLTWH(0, 0, 1070, 760),
    );
    final filePane = tester.getRect(find.byKey(const Key('commit-files-pane')));
    expect(filePane, const Rect.fromLTRB(0, 116, 278, 760));
  });

  testWidgets('final polish Blame rows use the approved 21px height', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor(
      view: FullDiffView.blame,
      activeHunkIndex: 1,
    );
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 842);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          finalPolishGeometry: true,
          surfaceSize: const Size(1440, 842),
          showRemoteAvatars: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.getSize(find.byKey(const Key('blame-line-313'))).height, 21);
    expect(
      tester.getSize(find.byKey(const Key('blame-avatar-313'))),
      const Size(20, 20),
    );
  });

  testWidgets('blame renders aligned metadata columns and source', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor(view: FullDiffView.blame);
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1070, 842);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          surfaceSize: const Size(1070, 842),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final metadata = find.byKey(const Key('blame-metadata-313'));
    expect(tester.getSize(metadata).width, greaterThanOrEqualTo(250));
    expect(
      find.descendant(of: metadata, matching: find.text('SC')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: metadata,
        matching: find.text(
          'Persist Retina-aware window dimensions while restoring saved display state',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: metadata, matching: find.text('2026-06-24')),
      findsOneWidget,
    );

    final row = find.byKey(const Key('blame-line-313'));
    final lineNumber = find.descendant(of: row, matching: find.text('313'));
    final summary = find.byKey(const Key('blame-summary-313'));
    final date = find.byKey(const Key('blame-date-313'));
    final rail = find.byKey(const Key('blame-rail-313'));
    final source = find.descendant(
      of: row,
      matching: find.text(
        "Log(LOGINFO, 'BASE MODULE VERSION: ' + VersionModule);",
      ),
    );
    expect(
      tester.getTopLeft(lineNumber).dx,
      lessThan(tester.getTopLeft(summary).dx),
    );
    expect(tester.getTopLeft(summary).dx, lessThan(tester.getTopLeft(date).dx));
    expect(tester.getTopLeft(date).dx, lessThan(tester.getTopLeft(rail).dx));
    expect(tester.getTopLeft(rail).dx, lessThan(tester.getTopLeft(source).dx));
    expect(tester.getSize(rail).width, 1);
    expect(find.byKey(const Key('blame-hunk-header-hunk-1')), findsNothing);
  });

  testWidgets('detail QA state maps the unified viewport from the top', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor(activeHunkIndex: 2);
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          detailOnly: true,
          surfaceSize: const Size(1280, 720),
        ),
      ),
    );
    await tester.pump();

    final minimap = find.byKey(const Key('full-diff-minimap'));
    expect(minimap, findsOneWidget);
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: minimap, matching: find.byType(CustomPaint)),
    );
    final painter = paint.painter! as FullDiffMinimapPainter;
    final height = tester.getSize(minimap).height;
    final sourceLineCount = tester
        .widget<FullDiffMinimap>(find.byType(FullDiffMinimap))
        .sourceLineCount;
    expect(sourceLineCount, 441);
    expect(painter.viewport, isNotNull);
    expect(painter.viewport!.top, 0);
    expect(painter.viewport!.height, greaterThan(18));
    expect(painter.viewport!.height, lessThan(height));
  });

  testWidgets('history rows place author and age below the title', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor(view: FullDiffView.history);
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1070, 842);
    await tester.pumpWidget(
      MaterialApp(
        theme: fullDiffQaTheme(),
        home: FullDiffQaComparisonCanvas(
          controller: controller,
          surfaceSize: const Size(1070, 842),
        ),
      ),
    );
    await tester.pump();

    final history = find.byKey(const Key('history-list'));
    expect(
      tester
          .getTopLeft(
            find
                .descendant(of: history, matching: find.text('Suwon Chae'))
                .first,
          )
          .dy,
      greaterThan(
        tester
                .getTopLeft(
                  find.descendant(
                    of: history,
                    matching: find.text('Make Retina windows pixel-aware'),
                  ),
                )
                .dy +
            14,
      ),
    );
  });

  for (final scenario in qaCases) {
    testWidgets('capture ${scenario.name}', (tester) async {
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final controller = await qaControllerFor(
        view: scenario.view,
        layout: scenario.layout,
        scope: scenario.scope,
        focusMode: scenario.focus,
        ignoreWhitespace: scenario.whitespace,
        wrapLines: scenario.wrap,
        activeHunkIndex: scenario.hunk,
        algorithm: scenario.algorithm,
      );
      addTearDown(controller.dispose);

      expect(controller.state.view, scenario.view);
      expect(controller.state.layout, scenario.layout);
      expect(controller.state.appliedScope, scenario.scope);
      expect(controller.state.focusMode, scenario.focus);
      expect(controller.state.requestedIgnoreWhitespace, scenario.whitespace);
      expect(controller.state.wrapLines, scenario.wrap);
      expect(controller.state.activeAnchor?.hunkIndex, scenario.hunk);
      expect(controller.state.requestedAlgorithm, scenario.algorithm);
      expect(
        controller.state.patch.data?.hunks,
        hasLength(scenario.scope == DiffScope.fullFile ? 1 : 7),
      );
      FullDiffColumnWidths? savedWidths;

      await capture(
        tester,
        name: scenario.name,
        size: scenario.size,
        child: FullDiffQaComparisonCanvas(
          controller: controller,
          detailOnly: scenario.detailOnly,
          finalPolishGeometry: isFinalPolishCapture(scenario.name),
          surfaceSize: scenario.size,
          onColumnWidthsChanged: (value) => savedWidths = value,
        ),
        prepare: () => prepareFunctionalCapture(
          tester,
          scenario,
          controller,
          savedWidths: () => savedWidths,
        ),
        target: scenario.name == '27-algorithm-chooser'
            ? find.byType(Overlay)
            : null,
        fullSurface: scenario.name == '26-shortcut-hints',
      );
    });
  }

  for (final name in followupCases) {
    testWidgets('capture $name', (tester) async {
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final history = name.startsWith('16-') || name.startsWith('17-');
      final unavailable = name.startsWith('15-');
      final layout = name.startsWith('17-')
          ? DiffLayout.sideBySide
          : DiffLayout.unified;
      final controller = await qaControllerFor(
        view: history ? FullDiffView.history : FullDiffView.diff,
        layout: layout,
        emptyPatch: unavailable,
        selectPastHistory: history,
        activeHunkIndex: history || unavailable ? 0 : 1,
      );
      addTearDown(controller.dispose);

      if (unavailable) {
        expect(controller.state.patch.data?.hunks, isEmpty);
        expect(controller.state.file.data?.kind, FileContentKind.utf8);
      } else if (history) {
        expect(controller.state.history.data, hasLength(4));
        expect(
          controller.state.selectedHistoryEntry?.commit.shortSha,
          '65f4c80',
        );
        expect(
          controller.state.patch.data?.rows,
          qaHistoricalPatchLines.skip(1),
        );
      } else {
        expect(controller.state.patch.data?.hunks, hasLength(7));
      }

      const size = Size(1070, 842);
      await capture(
        tester,
        name: name,
        size: size,
        child: FullDiffQaComparisonCanvas(
          controller: controller,
          surfaceSize: size,
        ),
      );
    });
  }

  testWidgets('capture 19-final-history', (tester) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor(
      view: FullDiffView.history,
      layout: DiffLayout.sideBySide,
      selectPastHistory: true,
      activeHunkIndex: 0,
    );
    addTearDown(controller.dispose);
    const size = Size(1070, 842);

    await capture(
      tester,
      name: '19-final-history',
      size: size,
      child: FullDiffQaComparisonCanvas(
        controller: controller,
        finalPolishGeometry: true,
        surfaceSize: size,
      ),
      prepare: () async {
        final historyRowFocus = focusQaHistoryRow(tester, 'c78b2ff');
        await tester.pump();
        expect(historyRowFocus.hasPrimaryFocus, isTrue);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer();
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.text('History')));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('파일의 변경 이력을 보여줍니다'), findsOneWidget);
        expect(
          controller.state.selectedHistoryEntry?.commit.shortSha,
          '65f4c80',
        );
        expect(find.byType(HatchedDiffCell), findsWidgets);
      },
      target: find.byType(Overlay),
    );
  });

  testWidgets('capture 20-final-blame', (tester) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor(
      view: FullDiffView.blame,
      activeHunkIndex: 1,
    );
    addTearDown(controller.dispose);
    const size = Size(1440, 842);

    await capture(
      tester,
      name: '20-final-blame',
      size: size,
      child: FullDiffQaComparisonCanvas(
        controller: controller,
        finalPolishGeometry: true,
        surfaceSize: size,
        showRemoteAvatars: false,
      ),
      prepare: () async {
        expect(find.byKey(const Key('blame-avatar-313')), findsOneWidget);
        expect(find.text('SC'), findsWidgets);
        expect(find.byKey(const Key('blame-summary-313')), findsOneWidget);
        expect(find.byKey(const Key('blame-date-313')), findsOneWidget);
        expect(find.byKey(const Key('blame-rail-313')), findsOneWidget);
      },
    );
  });

  testWidgets('capture 14-algorithm-tooltip', (tester) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final controller = await qaControllerFor(
      algorithm: DiffAlgorithm.histogram,
    );
    addTearDown(controller.dispose);
    const size = Size(1070, 842);

    await capture(
      tester,
      name: '14-algorithm-tooltip',
      size: size,
      child: FullDiffQaComparisonCanvas(
        controller: controller,
        surfaceSize: size,
      ),
      prepare: () async {
        await tester.tap(find.byKey(const Key('diff-algorithm')));
        await tester.pump();
        expect(
          find.byKey(const Key('algorithm-details-histogram')),
          findsOneWidget,
        );
      },
      target: find.byType(Overlay),
    );
  });
}
