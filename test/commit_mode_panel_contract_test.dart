import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/timeline_palette.dart';
import 'package:yogit/window_frame.dart';
import 'package:yogit/working_tree_status.dart';

import 'app_test.dart' show FakeGitRepository, app, commit, workingTreeCommit;

/// 커밋 패널 — 승인된 시안 docs/commit-mode-mockup.html '동작 정의' 1·4·5·6·7·8을
/// 한 줄씩 계약으로 못 박는다. 두 섹션과 그 hover 동작, Discard 확인창, 커밋 폼의
/// 게이트가 여기서 정해진다. diff 연결(2·3)과 키보드(9)는 다음 단계다.
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
    bool conflicted = false,
    bool submodule = false,
    String? origPath,
    int? unstagedAdditions,
    int? unstagedDeletions,
    int? stagedAdditions,
    int? stagedDeletions,
  }) => WorkingTreeEntry(
    path: path,
    origPath: origPath,
    indexStatus: index,
    worktreeStatus: worktree,
    untracked: untracked,
    conflicted: conflicted,
    submodule: submodule,
    unstagedAdditions: unstagedAdditions,
    unstagedDeletions: unstagedDeletions,
    stagedAdditions: stagedAdditions,
    stagedDeletions: stagedDeletions,
  );

  /// 한 파일은 두 축 모두(MM), 하나는 작업 트리에만, 하나는 인덱스에만.
  WorkingTreeStatus bothSections() => WorkingTreeStatus([
    entry(
      'lib/a.dart',
      index: 'M',
      worktree: 'M',
      unstagedAdditions: 9,
      unstagedDeletions: 1,
      stagedAdditions: 3,
      stagedDeletions: 5,
    ),
    entry('lib/b.dart', unstagedAdditions: 4, unstagedDeletions: 0),
    entry(
      'lib/c.dart',
      index: 'A',
      worktree: '.',
      stagedAdditions: 48,
      stagedDeletions: 0,
    ),
  ]);

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
    // 판이 이미 열려 있으면(같은 시험에서 두 번째 저장소를 태우는 경우) Enter는
    // 도로 닫는 쪽이다.
    if (find.byKey(const Key('commit-panel')).evaluate().isEmpty) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
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

  bool enabled(WidgetTester tester, Key key) =>
      tester.widget<InkWell>(find.byKey(key)).onTap != null;

  testWidgets('selecting the WIP row turns the preview into the commit panel', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => bothSections(),
      ),
    );

    expect(find.byKey(const Key('commit-panel')), findsOneWidget);
    // 머리줄은 그대로 미리보기 판의 것이다 — 시안의 `커밋 WIP · 부모 …`.
    expect(find.byKey(const Key('preview-working-tree')), findsOneWidget);

    // 커밋 행으로 내려가면 평범한 미리보기가 돌아온다.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('commit-panel')), findsNothing);
  });

  testWidgets(
    'two sections show counts, collapse, and Stage All / Unstage All',
    (tester) async {
      final staged = <List<String>>[];
      final unstaged = <(List<String>, bool)>[];
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => bothSections(),
          stageFilesCallback: (paths) async => staged.add(paths),
          unstageFilesCallback: (paths, hasHead) async =>
              unstaged.add((paths, hasHead)),
        ),
      );

      final unstagedHeader = find.byKey(const Key('commit-section-unstaged'));
      final stagedHeader = find.byKey(const Key('commit-section-staged'));
      expect(
        find.descendant(of: unstagedHeader, matching: find.text('2')),
        findsOneWidget,
        reason: 'MM 파일과 작업 트리에만 있는 파일',
      );
      expect(
        find.descendant(of: stagedHeader, matching: find.text('2')),
        findsOneWidget,
        reason: 'MM 파일과 인덱스에만 있는 파일',
      );
      expect(row(WorkingTreeArea.unstaged, 'lib/a.dart'), findsOneWidget);
      expect(row(WorkingTreeArea.staged, 'lib/a.dart'), findsOneWidget);

      // ▾를 누르면 그 섹션의 행만 접힌다.
      await tester.tap(unstagedHeader);
      await tester.pumpAndSettle();
      expect(row(WorkingTreeArea.unstaged, 'lib/a.dart'), findsNothing);
      expect(row(WorkingTreeArea.staged, 'lib/a.dart'), findsOneWidget);
      await tester.tap(unstagedHeader);
      await tester.pumpAndSettle();
      expect(row(WorkingTreeArea.unstaged, 'lib/a.dart'), findsOneWidget);

      // All 버튼은 경로 목록이 빈 채로 내려간다 — git add -A / restore --staged :/.
      await tester.tap(find.byKey(const Key('commit-stage-all')));
      await tester.pumpAndSettle();
      expect(staged, [<String>[]]);
      await tester.tap(find.byKey(const Key('commit-unstage-all')));
      await tester.pumpAndSettle();
      expect(unstaged.single.$1, isEmpty);
      expect(unstaged.single.$2, isTrue, reason: 'HEAD가 있으면 restore --staged');
    },
  );

  testWidgets(
    'an unstaged row hover offers Stage File and Discard, a staged row only Unstage File',
    (tester) async {
      final staged = <List<String>>[];
      final unstaged = <(List<String>, bool)>[];
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => bothSections(),
          stageFilesCallback: (paths) async => staged.add(paths),
          unstageFilesCallback: (paths, hasHead) async =>
              unstaged.add((paths, hasHead)),
        ),
      );

      expect(find.byKey(const Key('commit-stage-lib/a.dart')), findsNothing);
      await hoverOver(tester, row(WorkingTreeArea.unstaged, 'lib/a.dart'));
      expect(find.byKey(const Key('commit-stage-lib/a.dart')), findsOneWidget);
      expect(
        find.byKey(const Key('commit-discard-lib/a.dart')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('commit-unstage-lib/a.dart')), findsNothing);
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: find.byKey(const Key('commit-stage-lib/a.dart')),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        'Stage File',
      );

      await tester.tap(find.byKey(const Key('commit-stage-lib/a.dart')));
      await tester.pumpAndSettle();
      expect(staged, [
        ['lib/a.dart'],
      ]);

      // Staged 행에는 Unstage 하나뿐 — 인덱스만 되돌리니 Discard가 없다.
      await hoverOver(tester, row(WorkingTreeArea.staged, 'lib/c.dart'));
      expect(
        find.byKey(const Key('commit-unstage-lib/c.dart')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('commit-discard-lib/c.dart')), findsNothing);
      expect(find.byKey(const Key('commit-stage-lib/c.dart')), findsNothing);

      await tester.tap(find.byKey(const Key('commit-unstage-lib/c.dart')));
      await tester.pumpAndSettle();
      expect(unstaged.single.$1, ['lib/c.dart']);
      expect(unstaged.single.$2, isTrue);
    },
  );

  testWidgets(
    'an untracked row carries the untracked chip and its discard dialog names deletion',
    (tester) async {
      final discarded = <(String, bool)>[];
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => WorkingTreeStatus([
            entry('.DS_Store', worktree: 'A', untracked: true),
          ]),
          discardWorktreeFileCallback: (path, untracked) async =>
              discarded.add((path, untracked)),
        ),
      );

      final untracked = row(WorkingTreeArea.unstaged, '.DS_Store');
      expect(
        find.descendant(of: untracked, matching: find.text('untracked')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: untracked, matching: find.text('A')),
        findsOneWidget,
        reason: '새 파일은 추가로 읽힌다',
      );

      await hoverOver(tester, untracked);
      await tester.tap(find.byKey(const Key('commit-discard-.DS_Store')));
      await tester.pumpAndSettle();
      expect(find.text('파일을 삭제할까요?'), findsOneWidget);
      expect(
        find.textContaining('디스크에서 지워집니다'),
        findsOneWidget,
        reason: 'git이 아니라 파일 삭제라는 것을 확인창이 말한다',
      );

      await tester.tap(find.byKey(const Key('commit-discard-confirm')));
      await tester.pumpAndSettle();
      expect(discarded, [('.DS_Store', true)]);
    },
  );

  testWidgets(
    'a tracked discard dialog says staged changes survive, and confirming calls git',
    (tester) async {
      final discarded = <(String, bool)>[];
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => bothSections(),
          discardWorktreeFileCallback: (path, untracked) async =>
              discarded.add((path, untracked)),
        ),
      );

      await hoverOver(tester, row(WorkingTreeArea.unstaged, 'lib/a.dart'));
      await tester.tap(find.byKey(const Key('commit-discard-lib/a.dart')));
      await tester.pumpAndSettle();
      expect(find.text('변경 내용을 버릴까요?'), findsOneWidget);
      expect(find.textContaining('Staged 변경은 남습니다'), findsOneWidget);

      // 취소하면 아무 일도 없다.
      await tester.tap(find.byKey(const Key('commit-discard-cancel')));
      await tester.pumpAndSettle();
      expect(discarded, isEmpty);

      await hoverOver(tester, row(WorkingTreeArea.unstaged, 'lib/a.dart'));
      await tester.tap(find.byKey(const Key('commit-discard-lib/a.dart')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('commit-discard-confirm')));
      await tester.pumpAndSettle();
      expect(discarded, [('lib/a.dart', false)]);
    },
  );

  testWidgets(
    'a conflicted row blocks commit and routes Stage File through the marker check',
    (tester) async {
      final resolved = <String>[];
      final staged = <List<String>>[];
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => WorkingTreeStatus([
            entry('lib/x.dart', index: 'U', worktree: 'U', conflicted: true),
            entry('lib/c.dart', index: 'A', worktree: '.', stagedAdditions: 4),
          ]),
          stageResolvedFileCallback: (path) async => resolved.add(path),
          stageFilesCallback: (paths) async => staged.add(paths),
        ),
      );

      final conflict = row(WorkingTreeArea.unstaged, 'lib/x.dart');
      expect(
        find.descendant(of: conflict, matching: find.text('충돌')),
        findsOneWidget,
      );
      expect(
        row(WorkingTreeArea.staged, 'lib/x.dart'),
        findsNothing,
        reason: '충돌은 인덱스가 들고 있는 것이 아니다',
      );

      await tester.enterText(find.byKey(const Key('commit-title')), '제목');
      await tester.pumpAndSettle();
      expect(enabled(tester, const Key('commit-submit')), isFalse);
      expect(find.text('충돌 파일을 먼저 해결해야 합니다'), findsOneWidget);

      // Discard도 헝크도 없다. Stage만이 마커 검사를 지나 인덱스로 간다.
      await hoverOver(tester, conflict);
      expect(find.byKey(const Key('commit-discard-lib/x.dart')), findsNothing);
      await tester.tap(find.byKey(const Key('commit-stage-lib/x.dart')));
      await tester.pumpAndSettle();
      expect(resolved, ['lib/x.dart']);
      expect(staged, isEmpty);
    },
  );

  testWidgets("a row's letter comes from its own section's axis", (
    tester,
  ) async {
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => WorkingTreeStatus([
          entry('both.dart', index: 'M', worktree: 'M'),
          entry('added.dart', index: 'A', worktree: 'M'),
          entry('gone.dart', worktree: 'D'),
        ]),
      ),
    );

    Finder letter(WorkingTreeArea area, String path, String glyph) =>
        find.descendant(of: row(area, path), matching: find.text(glyph));

    expect(letter(WorkingTreeArea.unstaged, 'both.dart', 'M'), findsOneWidget);
    expect(letter(WorkingTreeArea.staged, 'both.dart', 'M'), findsOneWidget);

    // 같은 파일이 축마다 다른 글자를 든다 — 인덱스에는 새 파일, 작업 트리에는 수정.
    expect(letter(WorkingTreeArea.unstaged, 'added.dart', 'M'), findsOneWidget);
    expect(letter(WorkingTreeArea.staged, 'added.dart', 'A'), findsOneWidget);

    expect(letter(WorkingTreeArea.unstaged, 'gone.dart', 'D'), findsOneWidget);
    expect(row(WorkingTreeArea.staged, 'gone.dart'), findsNothing);
  });

  testWidgets('Stage All is disabled while a conflict is unresolved', (
    tester,
  ) async {
    final staged = <List<String>>[];
    final plain = entry('lib/b.dart');
    // 충돌을 해결해 인덱스로 올린 다음의 목록.
    var status = WorkingTreeStatus([
      entry('lib/x.dart', index: 'U', worktree: 'U', conflicted: true),
      plain,
    ]);
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => status,
        stageFilesCallback: (paths) async => staged.add(paths),
        stageResolvedFileCallback: (_) async =>
            status = WorkingTreeStatus([plain]),
      ),
    );

    expect(enabled(tester, const Key('commit-stage-all')), isFalse);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.byKey(const Key('commit-stage-all')),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      '충돌 파일을 먼저 해결해야 합니다',
      reason: '커밋 버튼이 쓰는 문구와 같아야 한다',
    );
    await tester.tap(
      find.byKey(const Key('commit-stage-all')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(staged, isEmpty);
    // 죽은 버튼을 지난 탭은 머리줄에 닿아 섹션을 접는다. 도로 편다.
    await tester.tap(find.byKey(const Key('commit-section-unstaged')));
    await tester.pumpAndSettle();

    // 충돌이 해결되면 게이트도 풀린다 — 상시 잠김이 아니다.
    await hoverOver(tester, row(WorkingTreeArea.unstaged, 'lib/x.dart'));
    await tester.tap(find.byKey(const Key('commit-stage-lib/x.dart')));
    await tester.pumpAndSettle();

    expect(enabled(tester, const Key('commit-stage-all')), isTrue);
    await tester.tap(find.byKey(const Key('commit-stage-all')));
    await tester.pumpAndSettle();
    expect(staged, [<String>[]]);
  });

  testWidgets('Unstage All is disabled while a conflict is unresolved', (
    tester,
  ) async {
    final unstaged = <(List<String>, bool)>[];
    final staged = entry(
      'lib/c.dart',
      index: 'A',
      worktree: '.',
      stagedAdditions: 4,
    );
    var status = WorkingTreeStatus([
      entry('lib/x.dart', index: 'U', worktree: 'U', conflicted: true),
      staged,
    ]);
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => status,
        unstageFilesCallback: (paths, hasHead) async =>
            unstaged.add((paths, hasHead)),
        stageResolvedFileCallback: (_) async =>
            status = WorkingTreeStatus([staged]),
      ),
    );

    expect(
      row(WorkingTreeArea.staged, 'lib/x.dart'),
      findsNothing,
      reason: '충돌은 Staged 목록에 서지 않는다 — 섹션 목록만 보는 가드는 이것을 놓친다',
    );
    expect(enabled(tester, const Key('commit-unstage-all')), isFalse);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.byKey(const Key('commit-unstage-all')),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      '충돌 파일을 먼저 해결해야 합니다',
      reason: 'Stage All과 같은 문구로 막힌다',
    );

    await tester.tap(
      find.byKey(const Key('commit-unstage-all')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      unstaged,
      isEmpty,
      reason: 'restore --staged :/는 충돌 경로의 stage 1/2/3까지 지운다',
    );

    // 충돌이 해결되면 게이트가 풀린다 — 상시 잠김이 아니다.
    await hoverOver(tester, row(WorkingTreeArea.unstaged, 'lib/x.dart'));
    await tester.tap(find.byKey(const Key('commit-stage-lib/x.dart')));
    await tester.pumpAndSettle();

    expect(enabled(tester, const Key('commit-unstage-all')), isTrue);
    await tester.tap(find.byKey(const Key('commit-unstage-all')));
    await tester.pumpAndSettle();
    expect(unstaged.single.$1, isEmpty);
  });

  testWidgets('the title counter turns orange past 50 without blocking', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => bothSections(),
      ),
    );

    Color? counterColor() => tester
        .widget<Text>(find.byKey(const Key('commit-title-counter')))
        .style
        ?.color;

    await tester.enterText(find.byKey(const Key('commit-title')), 'a' * 50);
    await tester.pumpAndSettle();
    expect(find.text('50/50'), findsOneWidget);
    expect(counterColor(), isNot(behindOrange));

    await tester.enterText(find.byKey(const Key('commit-title')), 'a' * 51);
    await tester.pumpAndSettle();
    expect(find.text('51/50'), findsOneWidget);
    expect(counterColor(), behindOrange);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('commit-title')))
          .controller!
          .text
          .length,
      51,
      reason: '넘어도 막지 않는다',
    );
  });

  testWidgets(
    'the commit button is disabled while staged is empty or the title is blank',
    (tester) async {
      final commits = <(String, bool)>[];
      // 커밋이 지나가면 인덱스가 빈다 — 두 번째 판정은 그 뒤의 목록이다.
      var status = bothSections();
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => status,
          commitIndexCallback: (message, amend) async {
            commits.add((message, amend));
            status = WorkingTreeStatus([
              entry('lib/b.dart', unstagedAdditions: 4),
            ]);
            return 'new-head';
          },
        ),
      );

      // Staged가 있어도 제목이 비면 누를 수 없다.
      expect(enabled(tester, const Key('commit-submit')), isFalse);
      expect(find.text('Staged 2개 파일 커밋'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('commit-title')),
        'feat(desktop): stage hunks from the diff view',
      );
      await tester.enterText(find.byKey(const Key('commit-body')), '왜 바꿨는지');
      await tester.pumpAndSettle();
      expect(enabled(tester, const Key('commit-submit')), isTrue);

      await tester.tap(find.byKey(const Key('commit-submit')));
      await tester.pumpAndSettle();
      expect(commits, [
        ('feat(desktop): stage hunks from the diff view\n\n왜 바꿨는지', false),
      ]);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('commit-title')))
            .controller!
            .text,
        isEmpty,
        reason: '성공하면 폼이 비워진다',
      );

      // 이제 Staged가 비었다. 제목을 채워도 누를 수 없다.
      await tester.enterText(find.byKey(const Key('commit-title')), '제목');
      await tester.pumpAndSettle();
      expect(find.text('Staged 0개 파일 커밋'), findsOneWidget);
      expect(enabled(tester, const Key('commit-submit')), isFalse);
    },
  );

  testWidgets(
    '--amend prefills the HEAD message, relabels the button, and warns on a pushed HEAD',
    (tester) async {
      await pumpPanel(
        tester,
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          workingTreeStatus: () async => bothSections(),
          commitMessage: (sha) async => 'feat(app): 앞선 커밋\n\n무엇을 왜 바꿨는지',
          refs: const RepoRefs(
            local: ['main'],
            current: 'main',
            upstreams: {'main': 'origin/main'},
            aheadBehind: {'main': BranchAheadBehind(ahead: 0, behind: 0)},
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('commit-amend')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('commit-title')))
            .controller!
            .text,
        'feat(app): 앞선 커밋',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('commit-body')))
            .controller!
            .text,
        '무엇을 왜 바꿨는지',
      );
      expect(find.text('커밋 수정'), findsOneWidget);
      expect(
        find.text('이미 origin/main에 올라간 커밋입니다. 수정하면 원격과 히스토리가 갈라집니다.'),
        findsOneWidget,
      );

      // 체크를 풀면 채워 넣었던 값이 물러난다.
      await tester.tap(find.byKey(const Key('commit-amend')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('commit-title')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byKey(const Key('commit-amend-warning')), findsNothing);
      expect(find.text('Staged 2개 파일 커밋'), findsOneWidget);
    },
  );

  testWidgets('a failed amend prefill unchecks the box and says so', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => bothSections(),
        commitMessage: (sha) async =>
            throw const GitRepositoryException('.', 'HEAD 메시지를 읽지 못했습니다'),
      ),
    );

    await tester.tap(find.byKey(const Key('commit-amend')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('commit-error')), findsOneWidget);
    expect(find.text('HEAD 메시지를 읽지 못했습니다'), findsOneWidget);
    expect(
      find.text('커밋 수정'),
      findsNothing,
      reason: '읽지 못한 메시지로 amend 체크만 켜진 빈 폼을 남기지 않는다',
    );
    expect(find.text('Staged 2개 파일 커밋'), findsOneWidget);
  });

  testWidgets('commit failure shows the inline message and keeps the form', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => bothSections(),
        commitIndexCallback: (message, amend) async =>
            throw const GitRepositoryException(
              '.',
              'pre-commit 훅이 커밋을 거부했습니다.',
            ),
      ),
    );

    await tester.enterText(find.byKey(const Key('commit-title')), '제목');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('commit-submit')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('commit-error'))).data,
      'pre-commit 훅이 커밋을 거부했습니다.',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('commit-title')))
          .controller!
          .text,
      '제목',
      reason: '실패해도 입력은 그대로 남는다',
    );
  });

  testWidgets('busy disables every action until the running one lands', (
    tester,
  ) async {
    final gate = Completer<void>();
    final staged = <List<String>>[];
    await pumpPanel(
      tester,
      FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
        workingTree: () async => workingTreeCommit('1'),
        workingTreeStatus: () async => bothSections(),
        stageFilesCallback: (paths) async {
          staged.add(paths);
          await gate.future;
        },
      ),
    );

    await tester.enterText(find.byKey(const Key('commit-title')), '제목');
    await tester.pumpAndSettle();
    expect(enabled(tester, const Key('commit-submit')), isTrue);

    await tester.tap(find.byKey(const Key('commit-stage-all')));
    await tester.pump();
    expect(staged, [<String>[]]);
    expect(enabled(tester, const Key('commit-submit')), isFalse);
    expect(enabled(tester, const Key('commit-stage-all')), isFalse);

    // 연타는 두 번째 조작을 만들지 않는다 — index.lock 경합을 UI에서 막는다.
    await tester.tap(find.byKey(const Key('commit-stage-all')));
    await tester.pump();
    expect(staged, [<String>[]]);

    gate.complete();
    await tester.pumpAndSettle();
    expect(enabled(tester, const Key('commit-stage-all')), isTrue);
    expect(enabled(tester, const Key('commit-submit')), isTrue);
  });
}
