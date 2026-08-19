import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_workspace.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit, togglePreview;

/// W2 contract — the preview's file list opens the real Full Diff in place.
///
/// docs/unified-diff-design.md §2.1/§3: picking a file swaps the sidebar and
/// timeline for the embedded workspace; the preview pane stays and remains the
/// file navigation. The adjacent simplified diff and the full-screen route are
/// both gone. esc, the header's ←, and → out of the preview all come back
/// to the timeline.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  FakeGitRepository repository() => FakeGitRepository(
    (_, _) async => [commit('1', 'first commit')],
    files: (_, _) async => const [
      GitFileChange(
        path: 'lib/a.dart',
        status: 'M',
        additions: 1,
        deletions: 1,
      ),
      GitFileChange(
        path: 'lib/b.dart',
        status: 'M',
        additions: 2,
        deletions: 0,
      ),
    ],
    diff: (_, _, _, _, _) async => const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
      DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
      DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
    ],
    content: (_, _, _) async => Uint8List.fromList('new\n'.codeUnits),
  );

  Future<void> pumpTimeline(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(app(repository(), controller));
    await tester.pumpAndSettle();
    // 첫 커밋 선택 + 미리보기 열기.
    await togglePreview(tester);
    await tester.pumpAndSettle();
  }

  Future<void> enterByFile(
    WidgetTester tester, [
    String path = 'lib/a.dart',
  ]) async {
    await tester.tap(find.byKey(Key('preview-state-$path')));
    await tester.pumpAndSettle();
  }

  Future<void> pressArrow(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('a file click swaps the workspace in for the timeline', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await enterByFile(tester);

    expect(find.byType(FullDiffWorkspace), findsOneWidget);
    expect(
      find.byKey(const Key('timeline-viewport')),
      findsNothing,
      reason: '타임라인 자리가 diff의 것이 된다',
    );
    expect(
      find.byKey(const Key('sidebar-action-strip')),
      findsNothing,
      reason: '사이드바도 함께 물러난다',
    );
    expect(find.byKey(const Key('preview-panel')), findsOneWidget);
    // 간이 인접 diff와 route의 파일 pane은 더 이상 존재하지 않는다.
    expect(find.byKey(const Key('preview-diff')), findsNothing);
    expect(find.byKey(const Key('commit-files-pane')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('file-path-chip')),
        matching: find.text('lib/a.dart'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the workspace follows the preview placement', (tester) async {
    await pumpTimeline(tester);
    await enterByFile(tester);

    final workspace = find.byType(FullDiffWorkspace);
    final preview = find.byKey(const Key('preview-panel'));
    expect(
      tester.getRect(workspace).right,
      lessThanOrEqualTo(tester.getRect(preview).left),
      reason: '우측 배치: diff가 미리보기 왼쪽을 다 차지한다',
    );

    await tester.tap(find.byKey(const Key('placement-PreviewPlacement.left')));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(preview).right,
      lessThanOrEqualTo(tester.getRect(workspace).left),
      reason: '좌측 배치: 거울로 뒤집힌다',
    );

    await tester.tap(
      find.byKey(const Key('placement-PreviewPlacement.bottom')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(workspace).bottom,
      lessThanOrEqualTo(tester.getRect(preview).top),
      reason: '하단 배치: diff가 위 전체, 미리보기가 아래',
    );
  });

  testWidgets('esc and the header arrow both restore the timeline', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await enterByFile(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(FullDiffWorkspace), findsNothing);
    expect(find.byKey(const Key('timeline-viewport')), findsOneWidget);
    expect(find.byKey(const Key('sidebar-action-strip')), findsOneWidget);
    expect(
      find.byKey(const Key('preview-panel')),
      findsOneWidget,
      reason: '복귀해도 미리보기는 남는다',
    );

    await enterByFile(tester);
    await tester.tap(find.byKey(const Key('full-diff-back')));
    await tester.pumpAndSettle();
    expect(find.byType(FullDiffWorkspace), findsNothing);
    expect(find.byKey(const Key('timeline-viewport')), findsOneWidget);
  });

  testWidgets('the arrows toggle the embedded diff without a route', (
    tester,
  ) async {
    await pumpTimeline(tester);

    await pressArrow(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byType(FullDiffWorkspace), findsOneWidget);
    // 전체화면 route가 아니라 제자리 교체다: 본창 툴바가 그대로 보인다.
    expect(
      find.byKey(const Key('preview-placement')),
      findsOneWidget,
      reason: '전체화면 route는 은퇴했다',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('file-path-chip')),
        matching: find.text('lib/a.dart'),
      ),
      findsOneWidget,
      reason: '선택된 파일이 없으면 첫 파일로 연다',
    );

    await pressArrow(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byType(FullDiffWorkspace), findsNothing);
    expect(find.byKey(const Key('timeline-viewport')), findsOneWidget);
  });

  testWidgets('picking another file in the preview retargets the diff', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await enterByFile(tester);

    await enterByFile(tester, 'lib/b.dart');
    expect(find.byType(FullDiffWorkspace), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('file-path-chip')),
        matching: find.text('lib/b.dart'),
      ),
      findsOneWidget,
      reason: '미리보기 목록이 곧 파일 내비게이션이다',
    );
  });
}
