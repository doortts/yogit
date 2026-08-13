import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/local_state_signature.dart';
import 'package:yogit/window_frame.dart';
import 'package:yogit/working_tree_status.dart';

import 'app_test.dart' show FakeGitRepository, app, commit, workingTreeCommit;

/// 커밋 모드의 키보드와 갱신 — 승인된 시안 docs/commit-mode-mockup.html '동작
/// 정의' 9. Space가 커서 행을 축 사이로 옮기고, ⌘↵이 커밋하고, ↑↓이 두 섹션을
/// 가로질러 걷는다. 그리고 조작이 끝난 뒤 무엇이 다시 서고 무엇이 사라지는지.
class _WatchedRepository extends FakeGitRepository {
  _WatchedRepository(
    super.loader, {
    super.workingTree,
    super.workingTreeStatus,
    super.stageFilesCallback,
    super.refs,
  });

  /// 밖에서 본 저장소의 지문. 조작이 이걸 움직여도 감시자는 물어서는 안 된다 —
  /// 앱이 벌인 일이기 때문이다.
  var signature = 'tip-1\nrefs/heads/main\nrefs/heads/main tip-1';

  @override
  Future<String?> loadLocalStateSignature() async => signature;

  @override
  Future<String?> loadBranchOperation(String branch) async => 'commit';

  @override
  Future<({int outgoing, int incoming})?> countMovedCommits(
    String before,
    String after,
  ) async => (outgoing: 1, incoming: 0);

  @override
  Future<List<MovedCommit>> loadMovedCommits(
    String before,
    String after, {
    int limit = 9,
  }) async => const [];
}

void main() {
  late WindowFrameController controller;
  TestGesture? mouse;

  setUp(() {
    mouse = null;
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  WorkingTreeEntry entry(
    String path, {
    String index = '.',
    String worktree = 'M',
    bool untracked = false,
  }) => WorkingTreeEntry(
    path: path,
    indexStatus: index,
    worktreeStatus: worktree,
    untracked: untracked,
  );

  /// lib/a.dart는 두 축 모두, lib/b.dart는 작업 트리에만, lib/c.dart는 인덱스에만.
  /// 커서가 걷는 평평한 줄은 넷이다: (Unstaged a, b) 다음 (Staged a, c).
  WorkingTreeStatus bothSections() => WorkingTreeStatus([
    entry('lib/a.dart', index: 'M', worktree: 'M'),
    entry('lib/b.dart'),
    entry('lib/c.dart', index: 'A', worktree: '.'),
  ]);

  /// 경로마다 XY 두 글자를 든 아주 작은 저장소 모델. 스테이징이 목록을 실제로
  /// 움직여야 같은 파일에 두 번 누르는 진짜 토글을 볼 수 있다.
  WorkingTreeStatus statusOf(Map<String, String> axes) => WorkingTreeStatus([
    for (final axis in axes.entries)
      entry(axis.key, index: axis.value[0], worktree: axis.value[1]),
  ]);

  /// 작업 트리 쪽 글자가 인덱스로 넘어간다. 되돌리면 그 반대다.
  String afterStage(String axes) => '${axes[1] == '.' ? axes[0] : axes[1]}.';
  String afterUnstage(String axes) => '.${axes[0] == '.' ? axes[1] : axes[0]}';

  /// 위 모델을 stage/unstage 콜백에 물린 저장소. [log]에 무엇이 불렸는지 남는다.
  FakeGitRepository movingRepository(
    Map<String, String> axes,
    List<String> log,
  ) => FakeGitRepository(
    (_, _) async => [commit('1', 'first commit')],
    workingTree: () async => workingTreeCommit('1'),
    workingTreeStatus: () async => statusOf(axes),
    stageFilesCallback: (paths) async {
      log.add('stage ${paths.single}');
      axes[paths.single] = afterStage(axes[paths.single]!);
    },
    unstageFilesCallback: (paths, hasHead) async {
      log.add('unstage ${paths.single}');
      axes[paths.single] = afterUnstage(axes[paths.single]!);
    },
  );

  GitFileChange change(String path) =>
      GitFileChange(path: path, status: 'M', additions: 1, deletions: 1);

  const oneHunk = <DiffLine>[
    DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,2 +10,3 @@ first'),
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
  ];

  Future<void> pumpPanel(
    WidgetTester tester,
    FakeGitRepository repository,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('commit-panel')), findsOneWidget);
  }

  Future<void> hoverOver(WidgetTester tester, Finder target) async {
    if (mouse == null) {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      mouse = gesture;
    }
    await mouse!.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
  }

  Finder row(WorkingTreeArea area, String path) =>
      find.byKey(Key('commit-row-${area.name}-$path'));

  /// 커서가 앉은 행만 배경을 얻는다 — 시안의 `.frow.selected`.
  bool cursorOn(WidgetTester tester, WorkingTreeArea area, String path) =>
      tester
          .widget<Container>(
            find
                .descendant(
                  of: row(area, path),
                  matching: find.byType(Container),
                )
                .first,
          )
          .color !=
      null;

  Future<void> metaKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  /// 타임라인이 키보드를 도로 가져간다 — 입력칸을 떠나야 평범한 Enter가 판을
  /// 여닫는 쪽으로 간다.
  Future<void> focusTimeline(WidgetTester tester) async {
    await tester.tap(find.text('Uncommitted changes'));
    await tester.pumpAndSettle();
  }

  testWidgets('Space toggles the cursor row between the sections', (
    tester,
  ) async {
    final log = <String>[];
    // 커서가 걷는 줄은 넷이다: (Unstaged a, b) 다음 (Staged a, c).
    final axes = {'lib/a.dart': 'MM', 'lib/b.dart': '.M', 'lib/c.dart': 'A.'};
    await pumpPanel(tester, movingRepository(axes, log));

    // 커서가 없으면 Space는 아무것도 하지 않는다.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(log, isEmpty);

    await metaKey(tester, LogicalKeyboardKey.arrowDown);
    await metaKey(tester, LogicalKeyboardKey.arrowDown);
    expect(cursorOn(tester, WorkingTreeArea.unstaged, 'lib/b.dart'), isTrue);

    // Unstaged 행의 Space는 Stage다. 파일이 인덱스로 넘어갔으니 커서도 따라간다.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(log, ['stage lib/b.dart']);
    expect(row(WorkingTreeArea.unstaged, 'lib/b.dart'), findsNothing);
    expect(cursorOn(tester, WorkingTreeArea.staged, 'lib/b.dart'), isTrue);

    // Staged 행의 Space는 그 반대다.
    await metaKey(tester, LogicalKeyboardKey.arrowUp);
    expect(cursorOn(tester, WorkingTreeArea.staged, 'lib/a.dart'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(log, ['stage lib/b.dart', 'unstage lib/a.dart']);
    expect(cursorOn(tester, WorkingTreeArea.unstaged, 'lib/a.dart'), isTrue);
  });

  testWidgets('Space twice returns the file to where it started', (
    tester,
  ) async {
    final log = <String>[];
    final axes = {'lib/a.dart': '.M'};
    await pumpPanel(tester, movingRepository(axes, log));

    await metaKey(tester, LogicalKeyboardKey.arrowDown);
    expect(cursorOn(tester, WorkingTreeArea.unstaged, 'lib/a.dart'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(log, ['stage lib/a.dart']);
    expect(cursorOn(tester, WorkingTreeArea.staged, 'lib/a.dart'), isTrue);

    // 같은 파일에 한 번 더 누르면 되돌아온다 — Stage가 두 번 되는 것이 아니다.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(log, ['stage lib/a.dart', 'unstage lib/a.dart']);
    expect(cursorOn(tester, WorkingTreeArea.unstaged, 'lib/a.dart'), isTrue);
  });

  testWidgets('Space typed into the title field stays a space', (tester) async {
    final staged = <List<String>>[];
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => bothSections(),
        stageFilesCallback: (paths) async => staged.add(paths),
      ),
    );

    await metaKey(tester, LogicalKeyboardKey.arrowDown);
    expect(cursorOn(tester, WorkingTreeArea.unstaged, 'lib/a.dart'), isTrue);

    await tester.enterText(find.byKey(const Key('commit-title')), 'fix the');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(staged, isEmpty, reason: '제목을 치는 중의 스페이스가 커서 행을 Stage 해서는 안 된다');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('commit-title')))
          .controller
          ?.text,
      'fix the',
    );
  });

  testWidgets('Cmd+Enter commits from the list and from the title field, '
      'plain Enter still toggles the preview', (tester) async {
    final commits = <(String, bool)>[];
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => bothSections(),
        commitIndexCallback: (message, amend) async {
          commits.add((message, amend));
          return 'new-head';
        },
      ),
    );

    // 제목이 비면 ⌘↵은 커밋 버튼과 같은 이유로 아무것도 하지 않는다.
    await metaKey(tester, LogicalKeyboardKey.enter);
    expect(commits, isEmpty);
    expect(
      find.byKey(const Key('commit-panel')),
      findsOneWidget,
      reason: '막힌 ⌘↵이 평범한 Enter로 새어 판을 닫아서는 안 된다',
    );

    await tester.enterText(find.byKey(const Key('commit-title')), 'from list');
    await tester.pumpAndSettle();
    await focusTimeline(tester);
    await metaKey(tester, LogicalKeyboardKey.enter);
    expect(commits, [('from list', false)]);

    // 제목칸에 포커스가 있어도 같다 — 치고 바로 커밋하는 흐름.
    await tester.enterText(find.byKey(const Key('commit-title')), 'from field');
    await tester.pumpAndSettle();
    await metaKey(tester, LogicalKeyboardKey.enter);
    expect(commits.last, ('from field', false));

    // 수식키가 없는 Enter는 여전히 판을 여닫는다.
    await focusTimeline(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('commit-panel')), findsNothing);
    expect(commits, hasLength(2));
  });

  testWidgets('arrows walk the cursor across the section boundary', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => bothSections(),
        areaFiles: (area) async => [
          for (final path
              in area == WorkingTreeArea.unstaged
                  ? ['lib/a.dart', 'lib/b.dart']
                  : ['lib/a.dart', 'lib/c.dart'])
            change(path),
        ],
        areaDiff: (_, _) async => oneHunk,
      ),
    );

    // 타임라인이 키보드를 든 채로도 ⌘↑↓이 파일을 걷는다.
    await metaKey(tester, LogicalKeyboardKey.arrowDown);
    await metaKey(tester, LogicalKeyboardKey.arrowDown);
    expect(cursorOn(tester, WorkingTreeArea.unstaged, 'lib/b.dart'), isTrue);

    // Unstaged의 끝에서 한 칸 더 가면 Staged의 첫 행이다.
    await metaKey(tester, LogicalKeyboardKey.arrowDown);
    expect(cursorOn(tester, WorkingTreeArea.unstaged, 'lib/b.dart'), isFalse);
    expect(cursorOn(tester, WorkingTreeArea.staged, 'lib/a.dart'), isTrue);

    // →는 커서가 앉은 파일의 diff를 그 축으로 연다.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('commit-panel')), findsOneWidget);

    // 미리보기가 키보드를 든 뒤에는 맨 화살표가 같은 커서를 움직인다.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(cursorOn(tester, WorkingTreeArea.unstaged, 'lib/b.dart'), isTrue);
  });

  testWidgets(
    'a commit reloads the timeline and keeps the WIP row while the tree is dirty',
    (tester) async {
      var committed = false;
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [
            if (committed) commit('2', 'the new commit'),
            commit('1', 'first commit'),
          ],
          workingTree: () async => workingTreeCommit(committed ? '2' : '1'),
          workingTreeStatus: () async => bothSections(),
          commitIndexCallback: (message, amend) async {
            committed = true;
            return '2';
          },
        ),
      );

      expect(find.text('the new commit'), findsNothing);
      await tester.enterText(find.byKey(const Key('commit-title')), 'a title');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('commit-submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('the new commit'),
        findsOneWidget,
        reason: '타임라인이 다시 선다',
      );
      expect(find.text('Uncommitted changes'), findsOneWidget);
      expect(
        find.byKey(const Key('commit-panel')),
        findsOneWidget,
        reason: '트리가 아직 더러우면 WIP 행이 0행에 남아 선택이 유지된다',
      );
      // 폼은 비고 다음 커밋을 기다린다.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('commit-title')))
            .controller
            ?.text,
        isEmpty,
      );
    },
  );

  testWidgets('discarding the last change removes the WIP row', (tester) async {
    var discarded = false;
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => discarded ? null : workingTreeCommit('1'),
        workingTreeStatus: () async => discarded
            ? const WorkingTreeStatus(<WorkingTreeEntry>[])
            : WorkingTreeStatus([entry('lib/only.dart')]),
        discardWorktreeFileCallback: (path, untracked) async =>
            discarded = true,
      ),
    );

    await hoverOver(tester, row(WorkingTreeArea.unstaged, 'lib/only.dart'));
    await tester.tap(find.byKey(const Key('commit-discard-lib/only.dart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('commit-discard-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Uncommitted changes'), findsNothing);
    expect(find.byKey(const Key('commit-panel')), findsNothing);
    expect(find.text('first commit'), findsWidgets);
  });

  testWidgets('a stage refreshes the open diff and the panel list', (
    tester,
  ) async {
    var staged = false;
    var areaReads = 0;
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => staged
            ? WorkingTreeStatus([
                entry('lib/a.dart', index: 'M', worktree: '.'),
              ])
            : WorkingTreeStatus([entry('lib/a.dart'), entry('lib/b.dart')]),
        areaFiles: (area) async {
          areaReads++;
          return [
            if (!staged || area == WorkingTreeArea.staged) change('lib/a.dart'),
            if (!staged && area == WorkingTreeArea.unstaged)
              change('lib/b.dart'),
          ];
        },
        areaDiff: (_, _) async => oneHunk,
        stageFilesCallback: (paths) async => staged = true,
      ),
    );

    await tester.tap(row(WorkingTreeArea.unstaged, 'lib/a.dart'));
    await tester.pumpAndSettle();
    expect(find.text('lib/b.dart'), findsWidgets);
    final readsBefore = areaReads;

    await hoverOver(tester, row(WorkingTreeArea.unstaged, 'lib/a.dart'));
    await tester.tap(find.byKey(const Key('commit-stage-lib/a.dart')));
    await tester.pumpAndSettle();

    expect(
      areaReads,
      greaterThan(readsBefore),
      reason: '열린 diff의 파일 목록을 다시 읽는다',
    );
    expect(
      find.text('lib/b.dart'),
      findsNothing,
      reason: 'Stage 뒤에는 그 축에 남은 파일이 없다',
    );
  });

  testWidgets(
    'a failed status reload surfaces instead of leaving a stale list',
    (tester) async {
      var reads = 0;
      final log = <String>[];
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          // 조작은 통하고 그 뒤의 목록 읽기만 실패한다.
          workingTreeStatus: () async {
            if (++reads > 1) {
              throw const GitRepositoryException('.', 'git status가 실패했습니다');
            }
            return WorkingTreeStatus([entry('lib/a.dart')]);
          },
          stageFilesCallback: (paths) async => log.add('stage ${paths.single}'),
        ),
      );

      await metaKey(tester, LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(log, ['stage lib/a.dart']);
      expect(find.byKey(const Key('commit-error')), findsOneWidget);
      expect(find.text('git status가 실패했습니다'), findsOneWidget);
    },
  );

  testWidgets('reselecting the working tree row reads the status again', (
    tester,
  ) async {
    var reads = 0;
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        // 밖(터미널)에서 저장소가 바뀐 것을 흉내낸다 — 두 번째 읽기부터 다른 목록.
        workingTreeStatus: () async {
          reads++;
          return WorkingTreeStatus([
            entry(reads == 1 ? 'lib/a.dart' : 'lib/z.dart'),
          ]);
        },
      ),
    );

    expect(reads, 1);
    expect(row(WorkingTreeArea.unstaged, 'lib/a.dart'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('commit-panel')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(reads, 2);
    expect(row(WorkingTreeArea.unstaged, 'lib/z.dart'), findsOneWidget);
    expect(row(WorkingTreeArea.unstaged, 'lib/a.dart'), findsNothing);
  });

  testWidgets(
    'mutations run inside _changingRepository so no external-change prompt appears',
    (tester) async {
      late _WatchedRepository repository;
      repository = _WatchedRepository(
        (_, _) async => [commit('tip-1', 'first commit')],
        workingTree: () async => workingTreeCommit('tip-1'),
        workingTreeStatus: () async => bothSections(),
        stageFilesCallback: (paths) async => repository.signature =
            'tip-2\nrefs/heads/main\nrefs/heads/main tip-2',
        refs: const RepoRefs(
          local: ['main'],
          current: 'main',
          tips: {'main': 'tip-1'},
        ),
      );
      await pumpPanel(tester, repository);

      await hoverOver(tester, row(WorkingTreeArea.unstaged, 'lib/b.dart'));
      await tester.tap(find.byKey(const Key('commit-stage-lib/b.dart')));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(
        find.text('새로 읽어올까요?'),
        findsNothing,
        reason: '앱이 벌인 일을 두고 밖에서 바뀌었다고 묻지 않는다',
      );

      // 감시자 자체는 살아 있다 — 앱을 지나지 않은 변화는 그대로 묻는다.
      repository.signature = 'tip-3\nrefs/heads/main\nrefs/heads/main tip-3';
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('새로 읽어올까요?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('local-change-dismiss')));
      await tester.pumpAndSettle();
    },
  );
}
