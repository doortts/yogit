import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_commit_info_card.dart';
import 'package:yogit/full_diff_minimap.dart';
import 'package:yogit/full_diff_theme.dart';
import 'package:yogit/full_diff_workspace.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit, togglePreview;

/// W3 contract — the History pane, the commit line, and the couplings.
///
/// docs/unified-diff-design.md §2.1–§2.5, §3: History는 diff의 오른쪽이 아니라
/// 미리보기 곁에 산다(우측: diff·History·미리보기 / 좌측: 그 거울 / 하단: 아래
/// 줄에서 미리보기·History). 항목을 고르면 diff·미리보기·타임라인이 같은
/// 커밋을 가리킨다. 집중 모드는 diff만 남긴다. 커밋 컨텍스트 라인이 헤더
/// 아래 놓이고, 머지 커밋의 parent 선택기가 그 라인에 붙는다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  final newer = commit('1', 'first commit', parents: ['2']);
  final older = commit('2', 'second commit');

  FakeGitRepository repository({List<GitCommit>? commits}) => FakeGitRepository(
    (_, _) async => commits ?? [newer, older],
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
    history: (_, file) async => [
      GitFileHistoryRecord(
        commit: newer,
        path: file.path,
        oldPath: null,
        status: 'M',
      ),
      GitFileHistoryRecord(
        commit: older,
        path: file.path,
        oldPath: null,
        status: 'M',
      ),
    ],
  );

  Future<void> pumpDiffMode(
    WidgetTester tester, {
    List<GitCommit>? commits,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(app(repository(commits: commits), controller));
    await tester.pumpAndSettle();
    await togglePreview(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-state-lib/a.dart')));
    await tester.pumpAndSettle();
  }

  Future<void> toggleHistory(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('history-toggle')));
    await tester.pumpAndSettle();
  }

  testWidgets('the history pane lives beside the preview, under its header', (
    tester,
  ) async {
    await pumpDiffMode(tester);
    expect(find.byKey(const Key('history-pane')), findsNothing);

    final workspace = find.byType(FullDiffWorkspace);
    final widthAlone = tester.getSize(workspace).width;

    await toggleHistory(tester);
    final pane = find.byKey(const Key('history-pane'));
    expect(pane, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('history-pane-header')),
        matching: find.textContaining('History'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('history-pane-header')),
        matching: find.textContaining('a.dart'),
      ),
      findsOneWidget,
      reason: '헤더가 어느 파일의 이력인지 말한다',
    );
    final preview = find.byKey(const Key('preview-panel'));
    expect(
      tester.getRect(workspace).right,
      lessThanOrEqualTo(tester.getRect(pane).left),
      reason: '우측 배치: diff · History · 미리보기',
    );
    expect(
      tester.getRect(pane).right,
      lessThanOrEqualTo(tester.getRect(preview).left),
    );

    await toggleHistory(tester);
    expect(find.byKey(const Key('history-pane')), findsNothing);
    expect(
      tester.getSize(workspace).width,
      widthAlone,
      reason: '끄면 diff가 그 폭을 되찾는다',
    );
  });

  testWidgets('the history pane follows the placement mirrors', (tester) async {
    await pumpDiffMode(tester);
    await toggleHistory(tester);

    final workspace = find.byType(FullDiffWorkspace);
    final pane = find.byKey(const Key('history-pane'));
    final preview = find.byKey(const Key('preview-panel'));

    await tester.tap(find.byKey(const Key('placement-PreviewPlacement.left')));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(preview).right,
      lessThanOrEqualTo(tester.getRect(pane).left),
      reason: '좌측 배치: 미리보기 · History · diff',
    );
    expect(
      tester.getRect(pane).right,
      lessThanOrEqualTo(tester.getRect(workspace).left),
    );

    await tester.tap(
      find.byKey(const Key('placement-PreviewPlacement.bottom')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(workspace).bottom,
      lessThanOrEqualTo(tester.getRect(pane).top),
      reason: '하단 배치: diff가 위 전체',
    );
    expect(
      tester.getRect(preview).right,
      lessThanOrEqualTo(tester.getRect(pane).left),
      reason: '하단 배치: 아래 줄은 미리보기 · History 순',
    );
  });

  testWidgets('the minimap stays while the history pane is open', (
    tester,
  ) async {
    await pumpDiffMode(tester);
    expect(find.byType(FullDiffMinimap), findsOneWidget);

    await toggleHistory(tester);
    expect(
      find.byType(FullDiffMinimap),
      findsOneWidget,
      reason: 'History가 열려도 diff는 여전히 한 파일의 diff다',
    );
    final workspace = tester.getRect(find.byType(FullDiffWorkspace));
    final minimap = tester.getRect(find.byType(FullDiffMinimap));
    expect(minimap.right, closeTo(workspace.right, 1));
    expect(
      minimap.width,
      fullDiffMinimapWidth,
      reason: '자리만 잡고 폭이 0이면 사라진 것과 같다',
    );
  });

  testWidgets('the history pane widens towards the diff', (tester) async {
    await pumpDiffMode(tester);
    await toggleHistory(tester);

    final pane = find.byKey(const Key('history-pane'));
    final before = tester.getSize(pane).width;
    // 핸들은 diff와 맞닿은 쪽에 있다 — 미리보기의 손잡이와 같은 자리에 겹치면
    // 위에 놓인 쪽만 잡히고 History는 영영 못 잡는다.
    await tester.drag(
      find.byKey(const Key('history-pane-resizer')),
      const Offset(-40, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(pane).width, before + 40);
  });

  testWidgets('a focused history row keeps its message to itself', (
    tester,
  ) async {
    await pumpDiffMode(tester);
    await toggleHistory(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('history-pane')),
        matching: find.text('second commit'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(FullDiffCommitInfoCard),
      findsNothing,
      reason: '선택 행 아래 뜨던 커밋 메시지 팝오버는 은퇴했다',
    );
  });

  testWidgets('focus mode leaves only the diff standing', (tester) async {
    await pumpDiffMode(tester);
    await toggleHistory(tester);

    await tester.tap(find.byKey(const Key('focus-mode')));
    await tester.pumpAndSettle();
    expect(find.byType(FullDiffWorkspace), findsOneWidget);
    expect(find.byKey(const Key('history-pane')), findsNothing);
    expect(
      find.byKey(const Key('preview-panel')),
      findsNothing,
      reason: '집중 모드는 History와 미리보기를 함께 물린다',
    );

    await tester.tap(find.byKey(const Key('focus-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-pane')), findsOneWidget);
    expect(find.byKey(const Key('preview-panel')), findsOneWidget);
  });

  testWidgets(
    'a history entry points diff, preview and timeline at its commit',
    (tester) async {
      await pumpDiffMode(tester);
      await toggleHistory(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('history-pane')),
          matching: find.text('second commit'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('full-diff-commit-line')),
          matching: find.textContaining('second commit'),
        ),
        findsOneWidget,
        reason: 'diff가 그 커밋의 이 파일을 보여준다',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('preview-panel')),
          matching: find.textContaining('second commit'),
        ),
        findsWidgets,
        reason: '미리보기도 그 커밋으로 넘어간다',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('timeline-viewport')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('preview-panel')),
          matching: find.textContaining('second commit'),
        ),
        findsWidgets,
        reason: '복귀한 타임라인의 선택도 그 커밋이다',
      );
    },
  );

  testWidgets('command-arrow file steps drive the preview highlight', (
    tester,
  ) async {
    await pumpDiffMode(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('file-path-chip')),
        matching: find.text('lib/b.dart'),
      ),
      findsOneWidget,
      reason: '⌘↓ 는 워크스페이스의 파일을 옮기고',
    );
  });

  testWidgets('the commit line sits under the header rows', (tester) async {
    await pumpDiffMode(tester);

    final line = find.byKey(const Key('full-diff-commit-line'));
    expect(line, findsOneWidget);
    expect(
      find.descendant(of: line, matching: find.textContaining('이전 상태')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: line, matching: find.textContaining('first commit')),
      findsOneWidget,
      reason: '어느 커밋을 보고 있는지 라인이 말한다',
    );
    expect(
      find.byKey(const Key('merge-parent-chooser')),
      findsNothing,
      reason: '부모가 하나면 선택기는 없다',
    );
  });

  testWidgets('a merge commit hangs its parent chooser on the commit line', (
    tester,
  ) async {
    final merge = commit('1', 'merge branch', parents: ['2', '3']);
    await pumpDiffMode(
      tester,
      commits: [merge, older, commit('3', 'side commit')],
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('full-diff-commit-line')),
        matching: find.byKey(const Key('merge-parent-chooser')),
      ),
      findsOneWidget,
      reason: '머지 커밋의 parent 선택은 커밋 라인의 것',
    );
  });
}
