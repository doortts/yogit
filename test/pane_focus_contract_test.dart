import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_workspace.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// One keyboard, three panes.
///
/// 시안(pane-focus-mockup) 1안: 키보드를 쥔 pane의 선택만 색을 갖고, 나머지는
/// 같은 명도의 무채색으로 물러난다. 미리보기는 한 번도 들어가 본 적이 없으면
/// 아무것도 고르지 않는다. ←/→ 와 h/l 이 사이드바·타임라인·미리보기를 오가고,
/// 미리보기로 들어가면 그 파일의 diff가 곧바로 열린다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  FakeGitRepository repository() => FakeGitRepository(
    (_, _) async => [commit('1', 'first commit'), commit('2', 'second commit')],
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
      DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
    ],
  );

  Future<void> pumpPreview(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(app(repository(), controller));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  BoxDecoration? fileRow(WidgetTester tester, String path) {
    final row = find.ancestor(
      of: find.byKey(Key('preview-state-$path')),
      matching: find.byType(DecoratedBox),
    );
    if (row.evaluate().isEmpty) return null;
    return tester.widget<DecoratedBox>(row.first).decoration as BoxDecoration;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('an unvisited preview marks no file at all', (tester) async {
    await pumpPreview(tester);

    expect(find.byKey(const Key('preview-state-lib/a.dart')), findsOneWidget);
    expect(
      fileRow(tester, 'lib/a.dart')?.color,
      isNull,
      reason: '들어가 본 적이 없으면 고른 파일도 없다',
    );
  });

  testWidgets('right opens the diff in the preview, left puts it away', (
    tester,
  ) async {
    await pumpPreview(tester);
    expect(find.byType(FullDiffWorkspace), findsNothing);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(
      find.byType(FullDiffWorkspace),
      findsOneWidget,
      reason: '미리보기로 들어가면 diff가 곧바로 열린다',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('file-path-chip')),
        matching: find.text('lib/a.dart'),
      ),
      findsOneWidget,
    );

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byType(FullDiffWorkspace), findsNothing);
    expect(find.byKey(const Key('timeline-viewport')), findsOneWidget);
    expect(
      find.byKey(const Key('preview-panel')),
      findsOneWidget,
      reason: 'diff만 접히고 미리보기는 남는다',
    );
  });

  testWidgets('the vim keys walk the same three panes', (tester) async {
    await pumpPreview(tester);

    await press(tester, LogicalKeyboardKey.keyL);
    expect(find.byType(FullDiffWorkspace), findsOneWidget);

    await press(tester, LogicalKeyboardKey.keyH);
    expect(find.byType(FullDiffWorkspace), findsNothing);

    // 타임라인에서 왼쪽은 사이드바, 오른쪽은 다시 타임라인.
    await press(tester, LogicalKeyboardKey.keyH);
    expect(find.byKey(const Key('sidebar-action-strip')), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyL);
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(
      find.byKey(const Key('selected-row-2')),
      findsOneWidget,
      reason: '타임라인으로 돌아오면 j 는 다시 커밋을 걷는다',
    );
  });

  testWidgets('only the pane holding the keyboard keeps its colour', (
    tester,
  ) async {
    await pumpPreview(tester);

    await press(tester, LogicalKeyboardKey.arrowRight);
    final focused = fileRow(tester, 'lib/a.dart')!.color!;
    expect(
      focused.g,
      isNot(closeTo(focused.r, 0.001)),
      reason: '키보드가 미리보기에 있으면 그 선택은 색을 가진다',
    );

    await press(tester, LogicalKeyboardKey.arrowLeft);
    final resting = fileRow(tester, 'lib/a.dart')!.color!;
    expect(resting, isNot(focused));
    expect(resting.a, lessThan(1), reason: '돌아 나오면 hover 정도의 자국만 남는다');
  });

  testWidgets('re-entering the preview goes straight to the last file', (
    tester,
  ) async {
    final asked = <String>[];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
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
          diff: (_, _, path, _, _) async {
            asked.add(path);
            return const [
              DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
              DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
            ];
          },
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    asked.clear();

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(asked, ['lib/b.dart'], reason: '첫 파일을 거쳐 가면 그 한 프레임이 깜박임으로 보인다');
  });

  testWidgets('the preview walks its files while it holds the keyboard', (
    tester,
  ) async {
    await pumpPreview(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(
      find.descendant(
        of: find.byKey(const Key('file-path-chip')),
        matching: find.text('lib/b.dart'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('preview-sha'))).data,
      '1',
      reason: '커밋은 그대로 — 아래로 걷는 건 파일이다',
    );
  });
}
