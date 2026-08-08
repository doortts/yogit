import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/diff_screen.dart';
import 'package:yogit/full_diff_controller.dart';
import 'package:yogit/full_diff_header.dart';
import 'package:yogit/full_diff_minimap.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/full_diff_workspace.dart';
import 'package:yogit/git.dart';

import 'support/full_diff_fixtures.dart';

/// W1 contract — the Full Diff workspace stands on its own.
///
/// docs/unified-diff-design.md §4.2: everything the full-screen route drew —
/// the two option rows, the content, the minimap, the keyboard — moves into a
/// widget that any pane can hold. The route keeps working by wrapping it; the
/// file-list pane stays with the route, never with the workspace. The header
/// also tightens to the approved mockup: 24px controls in a 4px-padded row,
/// 5px apart.
void main() {
  Future<FullDiffSessionController> session() async {
    final repository = FakeFullDiffRepository()
      ..files = ((_, _) async => const [fileA])
      ..diff = ((_, _, _, _, _) async => twoHunkLines);
    final controller = FullDiffSessionController(
      repository: repository,
      commits: const [commitA],
      initialIndex: 0,
    );
    await controller.initialize();
    return controller;
  }

  testWidgets('the workspace builds alone, without route or file pane', (
    tester,
  ) async {
    final controller = await session();
    addTearDown(controller.dispose);
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: FullDiffWorkspace(controller: controller, onBack: () => backs++),
      ),
    );
    await tester.pumpAndSettle();

    // Both option rows, in full.
    expect(find.byKey(const Key('file-info-controls')), findsOneWidget);
    expect(find.byKey(const Key('file-actions-controls')), findsOneWidget);
    expect(find.byKey(const Key('diff-algorithm-label')), findsOneWidget);
    expect(find.byKey(const Key('main-view-controls')), findsOneWidget);
    expect(find.byType(FullDiffMinimap), findsOneWidget);
    // The file list belongs to whoever embeds the workspace, not to it.
    expect(find.byKey(const Key('commit-files-pane')), findsNothing);

    await tester.tap(find.byKey(const Key('full-diff-back')));
    expect(backs, 1, reason: '← 는 임베드한 쪽의 복귀 콜백을 부른다');
  });

  testWidgets('the keyboard lives inside the workspace', (tester) async {
    final controller = await session();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: FullDiffWorkspace(controller: controller, onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.layout, DiffLayout.unified);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(
      controller.state.layout,
      DiffLayout.sideBySide,
      reason: '⌘U 는 라우트가 아니라 워크스페이스의 것이어야 임베드에서도 산다',
    );
  });

  testWidgets('the route still stands, now wrapped around the workspace', (
    tester,
  ) async {
    final controller = await session();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: DiffScreen(
          repository: controller.repository,
          commits: controller.state.nearbyCommits,
          initialIndex: 0,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullDiffWorkspace), findsOneWidget);
    // W1 changes no behaviour: the route keeps its file pane beside the
    // workspace until W2 retires the route altogether.
    expect(find.byKey(const Key('commit-files-pane')), findsOneWidget);
  });

  testWidgets('the header wears the compact measurements', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    expect(fullDiffControlHeight, 24.0, reason: '컨트롤 높이 28→24');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Column(
          children: [
            GlobalFileBar(
              file: fileA,
              path: fileA.path,
              view: FullDiffView.diff,
              encodingLabel: 'UTF-8',
              canOpenEditor: true,
              focusMode: false,
              onBack: () {},
              onOpenEditor: () {},
              onViewSelected: (_) {},
              onFocusModeChanged: (_) {},
            ),
            GlobalDiffToolbar(
              view: FullDiffView.diff,
              layout: DiffLayout.unified,
              hunkEnabled: true,
              historySelected: false,
              activeIndex: 0,
              anchorCount: 2,
              algorithm: DiffAlgorithm.histogram,
              ignoreWhitespace: false,
              wrapLines: false,
              loadingPatch: false,
              onLayoutSelected: (_) {},
              onHunkChanged: (_) {},
              onHistoryChanged: (_) {},
              onPrevious: () {},
              onNext: () {},
              onAlgorithmSelected: (_) {},
              onIgnoreWhitespaceChanged: (_) {},
              onWrapLinesChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const Key('focus-mode'))).height,
      24,
      reason: '1줄 컨트롤 높이',
    );
    expect(
      tester.getSize(find.byKey(const Key('ignore-whitespace'))).height,
      24,
      reason: '2줄 컨트롤 높이',
    );
    // 한 줄로 그려질 때 행 높이 = 컨트롤 24 + 상하 패딩 4씩.
    expect(tester.getSize(find.byType(GlobalFileBar)).height, 32);
    // 이웃한 컨트롤 사이는 5px.
    final chipRight = tester
        .getTopRight(find.byKey(const Key('file-path-chip')))
        .dx;
    final badgeLeft = tester
        .getTopLeft(find.byKey(const Key('file-summary-badge')))
        .dx;
    expect(badgeLeft - chipRight, 5, reason: '컨트롤 간격 5px');
  });
}
