import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_header.dart';
import 'package:yogit/full_diff_model.dart';
import 'package:yogit/full_diff_workspace.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';
import 'package:yogit/working_tree_status.dart';

import 'app_test.dart' show FakeGitRepository, app, commit, workingTreeCommit;

/// 커밋 모드의 diff 연결 — 승인된 시안 docs/commit-mode-mockup.html '동작 정의'
/// 1·2·3. 파일을 클릭하면 그 파일이 속한 축의 diff가 열리고 커밋 패널은 그대로
/// 남는다. filebar는 축 세그먼트와 파일 단위 버튼을, 헝크 헤더는 축이 정한
/// 버튼을 단다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  WorkingTreeEntry entry(
    String path, {
    String index = '.',
    String worktree = 'M',
    bool untracked = false,
    bool submodule = false,
    bool symlink = false,
    String? origPath,
    bool unstagedBinary = false,
  }) => WorkingTreeEntry(
    path: path,
    origPath: origPath,
    indexStatus: index,
    worktreeStatus: worktree,
    untracked: untracked,
    submodule: submodule,
    symlink: symlink,
    unstagedBinary: unstagedBinary,
  );

  /// lib/a.dart는 두 축 모두, lib/b.dart는 작업 트리에만, lib/c.dart는 인덱스에만.
  WorkingTreeStatus bothSections() => WorkingTreeStatus([
    entry('lib/a.dart', index: 'M', worktree: 'M'),
    entry('lib/b.dart'),
    entry('lib/c.dart', index: 'A', worktree: '.'),
  ]);

  GitFileChange change(String path) =>
      GitFileChange(path: path, status: 'M', additions: 1, deletions: 1);

  List<GitFileChange> areaFilesOf(WorkingTreeArea area) => [
    for (final entry
        in area == WorkingTreeArea.unstaged
            ? ['lib/a.dart', 'lib/b.dart']
            : ['lib/a.dart', 'lib/c.dart'])
      change(entry),
  ];

  /// 헝크 두 개짜리 diff — 헝크 헤더가 서고 버튼이 붙을 자리가 생긴다.
  const twoHunks = <DiffLine>[
    DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,3 +10,4 @@ first'),
    DiffLine(
      kind: DiffLineKind.context,
      text: 'ctx one',
      oldNumber: 10,
      newNumber: 10,
    ),
    DiffLine(kind: DiffLineKind.add, text: 'added one', newNumber: 11),
    DiffLine(
      kind: DiffLineKind.context,
      text: 'ctx two',
      oldNumber: 11,
      newNumber: 12,
    ),
    DiffLine(
      kind: DiffLineKind.context,
      text: 'ctx three',
      oldNumber: 12,
      newNumber: 13,
    ),
    DiffLine(kind: DiffLineKind.hunk, text: '@@ -40,2 +41,3 @@ second'),
    DiffLine(
      kind: DiffLineKind.context,
      text: 'ctx four',
      oldNumber: 40,
      newNumber: 41,
    ),
    DiffLine(kind: DiffLineKind.add, text: 'added two', newNumber: 42),
    DiffLine(
      kind: DiffLineKind.context,
      text: 'ctx five',
      oldNumber: 41,
      newNumber: 43,
    ),
  ];

  Future<void> pumpPanel(
    WidgetTester tester,
    FakeGitRepository repository, {
    FullDiffPreferences preferences = const FullDiffPreferences(),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(repository, controller, fullDiffPreferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('commit-panel')), findsOneWidget);
  }

  Finder row(WorkingTreeArea area, String path) =>
      find.byKey(Key('commit-row-${area.name}-$path'));

  Finder segment(String label) => find.descendant(
    of: find.byKey(const Key('commit-area-segment')),
    matching: find.text(label),
  );

  String? openPath(WidgetTester tester) => tester
      .widget<FullDiffWorkspace>(find.byType(FullDiffWorkspace))
      .controller
      .state
      .selectedFile
      ?.path;

  bool enabled(WidgetTester tester, Key key) =>
      tester.widget<InkWell>(find.byKey(key)).onTap != null;

  WorkingTreeArea segmentSelected(WidgetTester tester) => tester
      .widget<FullDiffSegmentedControl<WorkingTreeArea>>(
        find.byKey(const Key('commit-area-segment')),
      )
      .selected;

  FullDiffView view(WidgetTester tester) => tester
      .widget<FullDiffWorkspace>(find.byType(FullDiffWorkspace))
      .controller
      .state
      .view;

  FullDiffSegmentedControl<FullDiffView> mainViewControls(
    WidgetTester tester,
  ) => tester.widget<FullDiffSegmentedControl<FullDiffView>>(
    find.byKey(const Key('main-view-controls')),
  );

  bool blameEnabled(WidgetTester tester) =>
      mainViewControls(tester).isEnabled?.call(FullDiffView.blame) ?? true;

  testWidgets(
    'clicking a file opens the diff on that file\'s own area and the panel survives',
    (tester) async {
      final areas = <WorkingTreeArea>[];
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => bothSections(),
          areaFiles: (area) async {
            areas.add(area);
            return areaFilesOf(area);
          },
          areaDiff: (_, _) async => twoHunks,
        ),
      );

      await tester.tap(row(WorkingTreeArea.unstaged, 'lib/b.dart'));
      await tester.pumpAndSettle();
      expect(find.byType(FullDiffWorkspace), findsOneWidget);
      expect(
        find.byKey(const Key('commit-panel')),
        findsOneWidget,
        reason: 'diff가 열려도 커밋 패널은 그대로 유지된다 — 시안의 핵심',
      );
      expect(areas.last, WorkingTreeArea.unstaged);
      expect(openPath(tester), 'lib/b.dart');

      // Staged 섹션의 파일을 누르면 축이 따라 바뀐다.
      await tester.tap(row(WorkingTreeArea.staged, 'lib/c.dart'));
      await tester.pumpAndSettle();
      expect(areas.last, WorkingTreeArea.staged);
      expect(openPath(tester), 'lib/c.dart');
      expect(find.byKey(const Key('commit-panel')), findsOneWidget);
    },
  );

  testWidgets(
    'the file bar shows the area segment and Stage File / Unstage File per area',
    (tester) async {
      final staged = <List<String>>[];
      final unstaged = <(List<String>, bool)>[];
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => bothSections(),
          areaFiles: (area) async => areaFilesOf(area),
          areaDiff: (_, _) async => twoHunks,
          stageFilesCallback: (paths) async => staged.add(paths),
          unstageFilesCallback: (paths, hasHead) async =>
              unstaged.add((paths, hasHead)),
        ),
      );

      await tester.tap(row(WorkingTreeArea.unstaged, 'lib/b.dart'));
      await tester.pumpAndSettle();
      expect(segment('Unstaged'), findsOneWidget);
      expect(segment('Staged'), findsOneWidget);
      expect(find.text('Stage File'), findsOneWidget);
      expect(find.text('Unstage File'), findsNothing);

      await tester.tap(find.byKey(const Key('commit-file-action')));
      await tester.pumpAndSettle();
      expect(staged, [
        ['lib/b.dart'],
      ]);

      // 인덱스 축에서는 같은 자리가 Unstage File이 된다.
      await tester.tap(row(WorkingTreeArea.staged, 'lib/c.dart'));
      await tester.pumpAndSettle();
      expect(find.text('Unstage File'), findsOneWidget);
      expect(find.text('Stage File'), findsNothing);

      await tester.tap(find.byKey(const Key('commit-file-action')));
      await tester.pumpAndSettle();
      expect(unstaged.single.$1, ['lib/c.dart']);
      expect(unstaged.single.$2, isTrue);
    },
  );

  testWidgets(
    'switching the segment reopens the same path on the other axis or its first file',
    (tester) async {
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => bothSections(),
          areaFiles: (area) async => areaFilesOf(area),
          areaDiff: (_, _) async => twoHunks,
        ),
      );

      // lib/a.dart는 양쪽에 다 있다 — 축을 바꿔도 같은 파일이 열린다.
      await tester.tap(row(WorkingTreeArea.unstaged, 'lib/a.dart'));
      await tester.pumpAndSettle();
      await tester.tap(segment('Staged'));
      await tester.pumpAndSettle();
      expect(openPath(tester), 'lib/a.dart');

      // lib/c.dart는 인덱스에만 있다 — 작업 트리 축으로 가면 그 축의 첫 파일이다.
      await tester.tap(row(WorkingTreeArea.staged, 'lib/c.dart'));
      await tester.pumpAndSettle();
      expect(openPath(tester), 'lib/c.dart');
      await tester.tap(segment('Unstaged'));
      await tester.pumpAndSettle();
      expect(openPath(tester), 'lib/a.dart');
    },
  );

  testWidgets(
    'hunk headers carry Stage Hunk and Discard Hunk on unstaged, Unstage Hunk alone on staged',
    (tester) async {
      final hunks = <(String, String, int, HunkRange)>[];
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => bothSections(),
          areaFiles: (area) async => areaFilesOf(area),
          areaDiff: (_, _) async => twoHunks,
          hunkActionCallback: (action, path, index, expected) async =>
              hunks.add((action, path, index, expected)),
        ),
      );

      await tester.tap(row(WorkingTreeArea.unstaged, 'lib/a.dart'));
      await tester.pumpAndSettle();
      expect(find.text('Stage Hunk'), findsNWidgets(2));
      expect(find.text('Discard Hunk'), findsNWidgets(2));
      expect(find.text('Unstage Hunk'), findsNothing);

      // 두 번째 헝크의 @@ 네 숫자가 그대로 git 층으로 내려간다.
      await tester.tap(find.byKey(const Key('commit-stage-hunk-1')));
      await tester.pumpAndSettle();
      expect(hunks, [
        (
          'stage',
          'lib/a.dart',
          1,
          (oldStart: 40, oldCount: 2, newStart: 41, newCount: 3),
        ),
      ]);

      await tester.tap(row(WorkingTreeArea.staged, 'lib/a.dart'));
      await tester.pumpAndSettle();
      expect(find.text('Unstage Hunk'), findsNWidgets(2));
      expect(find.text('Stage Hunk'), findsNothing);
      expect(
        find.text('Discard Hunk'),
        findsNothing,
        reason: '인덱스를 되돌리는 축에는 파괴적 동작이 없다',
      );

      await tester.tap(find.byKey(const Key('commit-unstage-hunk-0')));
      await tester.pumpAndSettle();
      expect(hunks.last.$1, 'unstage');
      expect(hunks.last.$3, 0);

      // Discard Hunk는 확인창을 먼저 띄운다.
      await tester.tap(row(WorkingTreeArea.unstaged, 'lib/a.dart'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('commit-discard-hunk-0')));
      await tester.pumpAndSettle();
      expect(find.text('이 Hunk를 버릴까요?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('commit-discard-confirm')));
      await tester.pumpAndSettle();
      expect(hunks.last.$1, 'discard');
    },
  );

  testWidgets(
    'hunk buttons hide for untracked, renamed, binary, symlink and submodule files, under ignore-whitespace and outside the hunks scope',
    (tester) async {
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => WorkingTreeStatus([
            entry('lib/plain.dart'),
            entry('new.txt', worktree: 'A', untracked: true),
            entry('lib/moved.dart', worktree: 'R', origPath: 'lib/old.dart'),
            entry('assets/logo.png', unstagedBinary: true),
            entry('link.txt', symlink: true),
            entry('vendor/sub', submodule: true),
          ]),
          areaFiles: (_) async => [
            change('lib/plain.dart'),
            change('new.txt'),
            change('lib/moved.dart'),
            change('assets/logo.png'),
            change('link.txt'),
            change('vendor/sub'),
          ],
          areaDiff: (_, _) async => twoHunks,
        ),
      );

      await tester.tap(row(WorkingTreeArea.unstaged, 'lib/plain.dart'));
      await tester.pumpAndSettle();
      expect(find.text('Stage Hunk'), findsNWidgets(2));

      for (final path in [
        'new.txt',
        'lib/moved.dart',
        'assets/logo.png',
        'link.txt',
        'vendor/sub',
      ]) {
        await tester.tap(row(WorkingTreeArea.unstaged, path));
        await tester.pumpAndSettle();
        expect(
          find.text('Stage Hunk'),
          findsNothing,
          reason: '$path는 헝크 단위로 다룰 수 없다',
        );
      }

      // 공백 무시 보기에서는 버튼이 남되 눌리지 않는다 — 그 패치는 실제 바이트와
      // 다르다.
      await tester.tap(row(WorkingTreeArea.unstaged, 'lib/plain.dart'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ignore-whitespace')));
      await tester.pumpAndSettle();
      expect(enabled(tester, const Key('commit-stage-hunk-0')), isFalse);
      expect(find.byTooltip('공백 무시 보기에서는 Hunk 단위로 조작할 수 없습니다'), findsWidgets);

      // full-file 스코프에서는 버튼 자체가 없다: 거대 컨텍스트 한 덩이는
      // `--unified=3`으로 다시 뜨는 diff와 헝크 번호가 어긋난다.
      await tester.tap(find.byKey(const Key('ignore-whitespace')));
      await tester.pumpAndSettle();
      expect(find.text('Stage Hunk'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('hunk-toggle-on')));
      await tester.pumpAndSettle();
      expect(find.text('Stage Hunk'), findsNothing);
    },
  );

  testWidgets('a hunk action refreshes the open diff and the panel counts', (
    tester,
  ) async {
    var statusReads = 0;
    var diffReads = 0;
    var staged = false;
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async {
          statusReads++;
          return staged
              ? WorkingTreeStatus([entry('lib/a.dart', index: 'M')])
              : WorkingTreeStatus([entry('lib/a.dart')]);
        },
        areaFiles: (_) async => [change('lib/a.dart')],
        areaDiff: (_, _) async {
          diffReads++;
          return twoHunks;
        },
        hunkActionCallback: (_, _, _, _) async => staged = true,
      ),
    );

    await tester.tap(row(WorkingTreeArea.unstaged, 'lib/a.dart'));
    await tester.pumpAndSettle();
    final readsBefore = statusReads;
    final diffsBefore = diffReads;

    await tester.tap(find.byKey(const Key('commit-stage-hunk-0')));
    await tester.pumpAndSettle();

    expect(statusReads, greaterThan(readsBefore), reason: '패널 목록을 다시 읽는다');
    expect(diffReads, greaterThan(diffsBefore), reason: '열린 diff도 다시 뜬다');
    expect(row(WorkingTreeArea.staged, 'lib/a.dart'), findsOneWidget);
  });

  testWidgets('arrows move the open diff to the file the cursor lands on', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => bothSections(),
        areaFiles: (area) async => areaFilesOf(area),
        areaDiff: (_, _) async => twoHunks,
      ),
    );

    // 판이 닫혀 있으면 커서만 걷는다 — 화살표가 diff를 여는 키는 아니다.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(FullDiffWorkspace), findsNothing);

    await tester.tap(row(WorkingTreeArea.unstaged, 'lib/a.dart'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(openPath(tester), 'lib/a.dart');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(openPath(tester), 'lib/b.dart');

    // 섹션 경계를 넘으면 축까지 따라간다.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(segmentSelected(tester), WorkingTreeArea.staged);
    expect(openPath(tester), 'lib/a.dart');
  });

  testWidgets('the blame view is disabled on the staged axis', (tester) async {
    final blamed = <String>[];
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => bothSections(),
        areaFiles: (area) async => areaFilesOf(area),
        areaDiff: (_, _) async => twoHunks,
        blame: (_, file, _, _) async {
          blamed.add(file.path);
          return const [];
        },
      ),
      // 저장된 뷰가 Blame이어도 인덱스 축은 diff로 선다.
      preferences: const FullDiffPreferences(view: FullDiffView.blame),
    );

    await tester.tap(row(WorkingTreeArea.staged, 'lib/a.dart'));
    await tester.pumpAndSettle();
    expect(view(tester), FullDiffView.diff);
    expect(blamed, isEmpty);
    expect(blameEnabled(tester), isFalse);
    expect(
      mainViewControls(tester).tooltipFor?.call(FullDiffView.blame),
      '인덱스 blob에는 Blame이 없습니다',
    );

    // 세그먼트도 ⌘2도 그 자리를 지난다.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('main-view-controls')),
        matching: find.text('Blame'),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(view(tester), FullDiffView.diff);
    expect(blamed, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(view(tester), FullDiffView.diff);
    expect(blamed, isEmpty);

    // 작업 트리 축에는 파일이 있으니 Blame이 다시 산다.
    await tester.tap(segment('Unstaged'));
    await tester.pumpAndSettle();
    expect(blameEnabled(tester), isTrue);
  });

  testWidgets(
    'Esc closes the diff back to the timeline with the panel intact',
    (tester) async {
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => bothSections(),
          areaFiles: (area) async => areaFilesOf(area),
          areaDiff: (_, _) async => twoHunks,
        ),
      );

      await tester.tap(row(WorkingTreeArea.unstaged, 'lib/b.dart'));
      await tester.pumpAndSettle();
      expect(find.byType(FullDiffWorkspace), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(FullDiffWorkspace), findsNothing);
      expect(find.byKey(const Key('commit-panel')), findsOneWidget);
      expect(find.byKey(const Key('timeline-viewport')), findsOneWidget);
    },
  );
}
