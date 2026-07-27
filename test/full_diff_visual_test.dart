import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:yogit/full_diff_minimap.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/git.dart';

import '../tool/full_diff_visual_diff.dart';
import 'support/full_diff_qa_harness.dart';

typedef QaCase = ({
  String name,
  Size size,
  FullDiffView view,
  DiffPresentation presentation,
  bool focus,
  bool whitespace,
  bool wrap,
  int hunk,
  DiffAlgorithm algorithm,
  bool detailOnly,
});

const qaCases = <QaCase>[
  (
    name: '00-overview-hunk',
    size: Size(782, 842),
    view: FullDiffView.diff,
    presentation: DiffPresentation.hunk,
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
    presentation: DiffPresentation.inline,
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
    presentation: DiffPresentation.split,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
  // The approved screenshots show Split selected for cases 03–05 even
  // though the written case table says Hunk. Visual approval is authoritative.
  (
    name: '03-file-view',
    size: Size(1070, 842),
    view: FullDiffView.file,
    presentation: DiffPresentation.split,
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
    presentation: DiffPresentation.split,
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
    presentation: DiffPresentation.split,
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
    presentation: DiffPresentation.hunk,
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
    presentation: DiffPresentation.split,
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
    presentation: DiffPresentation.split,
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
    presentation: DiffPresentation.hunk,
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
    presentation: DiffPresentation.hunk,
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
    presentation: DiffPresentation.hunk,
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
    presentation: DiffPresentation.hunk,
    focus: false,
    whitespace: false,
    wrap: false,
    hunk: 1,
    algorithm: DiffAlgorithm.gitSetting,
    detailOnly: false,
  ),
];

Future<void> capture(
  WidgetTester tester, {
  required String name,
  required Size size,
  required Widget child,
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
  await expectLater(
    find.byKey(const Key('full-diff-qa-root')),
    matchesGoldenFile(
      '../docs/superpowers/verification/full-diff-qa/actual/$name.png',
    ),
  );
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

  testWidgets('782px keeps each global header on one line', (tester) async {
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
        home: FullDiffQaHarness(
          controller: controller,
          surfaceSize: const Size(782, 842),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getCenter(find.byKey(const Key('file-path-chip'))).dy,
      closeTo(tester.getCenter(find.text('File')).dy, 0.5),
    );
    expect(
      tester.getCenter(find.text('집중 모드')).dy,
      closeTo(tester.getCenter(find.text('diff 알고리즘')).dy, 0.5),
    );
    expect(find.text('주변 커밋'), findsOneWidget);
    expect(find.text('변경 파일'), findsOneWidget);
    final openEditorInk = find
        .ancestor(
          of: find.byKey(const Key('open-editor')),
          matching: find.byType(InkWell),
        )
        .first;
    expect(tester.widget<InkWell>(openEditorInk).onTap, isNotNull);
  });

  testWidgets('workspace card uses its 12px as inner padding', (tester) async {
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
        home: FullDiffQaHarness(controller: controller),
      ),
    );
    await tester.pump();

    final card = find
        .ancestor(
          of: find.byKey(const Key('file-path-chip')),
          matching: find.byType(ClipRRect),
        )
        .first;
    expect(tester.getRect(card).left, 0);
    expect(
      tester.getRect(find.byKey(const Key('file-path-chip'))).left,
      greaterThanOrEqualTo(fullDiffOuterPadding + 10),
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
        home: FullDiffQaHarness(
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
      matching: find.text('+12 −4'),
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
        home: FullDiffQaHarness(
          controller: controller,
          surfaceSize: const Size(480, 549),
        ),
      ),
    );
    await tester.pump();

    final controlY = tester
        .getCenter(find.byKey(const Key('change-counter')))
        .dy;
    for (final key in [
      const Key('diff-algorithm'),
      const Key('ignore-whitespace'),
      const Key('wrap-lines'),
    ]) {
      expect(tester.getCenter(find.byKey(key)).dy, closeTo(controlY, 0.5));
    }
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
        home: FullDiffQaHarness(
          controller: controller,
          surfaceSize: const Size(1070, 842),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getTopLeft(find.byKey(const Key('file-path-chip'))).dx,
      lessThan(80),
    );
    expect(tester.getTopLeft(find.text('탐색 패널')).dx, lessThan(80));
  });

  for (final presentation in DiffPresentation.values) {
    testWidgets(
      '${presentation.name} honors an initially selected second hunk',
      (tester) async {
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        final controller = await qaControllerFor(
          presentation: presentation,
          activeHunkIndex: 1,
        );
        addTearDown(controller.dispose);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(782, 842);
        await tester.pumpWidget(
          MaterialApp(
            theme: fullDiffQaTheme(),
            home: FullDiffQaHarness(
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
        final target = switch (presentation) {
          DiffPresentation.hunk => find.byKey(
            Key('hunk-card-surface-${activeAnchor.id}'),
          ),
          DiffPresentation.inline => find.byKey(const Key('inline-hunk-1')),
          DiffPresentation.split => find.byKey(const Key('split-hunk-1')),
        };
        expect(target, findsOneWidget);
        final viewport = tester.getRect(
          find.byKey(const Key('content-scrollable')),
        );
        expect(
          tester.getTopLeft(target).dy,
          lessThanOrEqualTo(
            viewport.top + (presentation == DiffPresentation.hunk ? 130 : 2),
          ),
        );
      },
    );
  }

  for (final view in [FullDiffView.file, FullDiffView.blame]) {
    testWidgets('${view.name} initially reveals the selected source anchor', (
      tester,
    ) async {
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final controller = await qaControllerFor(view: view, activeHunkIndex: 1);
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1070, 842);
      await tester.pumpWidget(
        MaterialApp(
          theme: fullDiffQaTheme(),
          home: FullDiffQaHarness(
            controller: controller,
            surfaceSize: const Size(1070, 842),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final linePrefix = view == FullDiffView.file ? 'file' : 'blame';
      final viewport = tester.getRect(
        find.byKey(const Key('content-scrollable')),
      );
      final line309 = find.byKey(Key('$linePrefix-line-309'));
      expect(line309, findsOneWidget);
      expect(
        tester.getTopLeft(line309).dy,
        inInclusiveRange(viewport.top - 27, viewport.top + 27),
      );
      expect(find.byKey(Key('$linePrefix-current-line-313')), findsOneWidget);
    });
  }

  testWidgets('blame uses one compact SHA and author-initials bundle', (
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
        home: FullDiffQaHarness(
          controller: controller,
          surfaceSize: const Size(1070, 842),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final metadata = find.byKey(const Key('blame-metadata-313'));
    expect(tester.getSize(metadata).width, 80);
    expect(
      find.descendant(of: metadata, matching: find.text('SC')),
      findsOneWidget,
    );
    expect(find.text('Suwon Chae'), findsNothing);

    final row = find.byKey(const Key('blame-line-313'));
    final lineNumber = find.descendant(of: row, matching: find.text('313'));
    final source = find.descendant(
      of: row,
      matching: find.text(
        "Log(LOGINFO, 'BASE MODULE VERSION: ' + VersionModule);",
      ),
    );
    expect(
      tester.getTopLeft(lineNumber).dx,
      lessThan(tester.getTopLeft(metadata).dx),
    );
    expect(
      tester.getTopLeft(metadata).dx,
      lessThan(tester.getTopLeft(source).dx),
    );
  });

  testWidgets('detail QA state includes the approved hunk minimap viewport', (
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
        home: FullDiffQaHarness(
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
    expect(painter.viewport.top, closeTo(height / 3, 1));
    expect(painter.viewport.height, closeTo(height * 0.24, 1));
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
        home: FullDiffQaHarness(
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
        presentation: scenario.presentation,
        focusMode: scenario.focus,
        ignoreWhitespace: scenario.whitespace,
        wrapLines: scenario.wrap,
        activeHunkIndex: scenario.hunk,
        algorithm: scenario.algorithm,
      );
      addTearDown(controller.dispose);

      expect(controller.state.view, scenario.view);
      expect(controller.state.presentation, scenario.presentation);
      expect(controller.state.focusMode, scenario.focus);
      expect(controller.state.requestedIgnoreWhitespace, scenario.whitespace);
      expect(controller.state.wrapLines, scenario.wrap);
      expect(controller.state.activeAnchor?.hunkIndex, scenario.hunk);
      expect(controller.state.requestedAlgorithm, scenario.algorithm);
      expect(controller.state.patch.data?.hunks, hasLength(7));

      await capture(
        tester,
        name: scenario.name,
        size: scenario.size,
        child: FullDiffQaHarness(
          controller: controller,
          detailOnly: scenario.detailOnly,
          surfaceSize: scenario.size,
        ),
      );
    });
  }
}
