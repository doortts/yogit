import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// docs/sidebar-and-row-branch-design.md §1 — 포커스된 커밋 행의 BRANCH / TAG
/// 칸에 그 커밋이 올라앉은 브랜치 선의 이름을 흐린 글씨로 보인다. 선의 이름은
/// 그 선에서 가장 위에 있는 행이 달고 있는 ref다 — 선은 tip에서 태어난다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  // ── 순수 함수 ─────────────────────────────────────────────────────
  group('branchLineNames', () {
    test('a line takes the ref its topmost row wears', () {
      final rows = layoutGraph([
        commit(
          'a',
          'tip',
          parents: ['b'],
          refs: const [GitRef(name: 'main')],
        ),
        commit('b', 'older', parents: ['c']),
        commit('c', 'root'),
      ]);

      final names = branchLineNames(rows);
      for (final row in rows) {
        expect(names[row.branch], 'main');
      }
    });

    test('a tag further down never renames the line', () {
      final rows = layoutGraph([
        commit(
          'a',
          'tip',
          parents: ['b'],
          refs: const [GitRef(name: 'main')],
        ),
        commit(
          'b',
          'tagged',
          parents: ['c'],
          refs: const [GitRef(name: 'v1', isTag: true)],
        ),
        commit('c', 'root'),
      ]);

      expect(branchLineNames(rows).values.toSet(), {'main'});
    });

    test('a line whose tip wears nothing stays unnamed', () {
      final rows = layoutGraph([
        commit('a', 'tip', parents: ['b']),
        commit('b', 'root'),
      ]);

      expect(branchLineNames(rows), isEmpty);
    });

    test('the working tree row does not swallow its line name', () {
      // 작업 트리 행은 체크아웃한 브랜치 줄 맨 위에 앉고 ref를 달 수 없다. 그
      // 행에서 줄 이름을 포기하면 기준 브랜치만 이름을 잃는다 — 커밋되지 않은
      // 변경이 있는 동안 내내.
      final rows = layoutGraph([
        commit('', 'working tree', parents: ['a']),
        commit(
          'a',
          'tip',
          parents: ['b'],
          refs: const [GitRef(name: 'main')],
        ),
        commit('b', 'middle', parents: ['c']),
        commit('c', 'root'),
      ]);

      final names = branchLineNames(rows);
      for (final row in rows) {
        expect(names[row.branch], 'main');
      }
    });

    test('a branch tip wins over a tag on the same commit', () {
      final rows = layoutGraph([
        commit(
          'a',
          'tip',
          parents: ['b'],
          refs: const [
            GitRef(name: 'v2', isTag: true),
            GitRef(name: 'main'),
          ],
        ),
        commit('b', 'root'),
      ]);

      expect(branchLineNames(rows)[rows.first.branch], 'main');
    });
  });

  // ── 순수 함수: 이름 없는 선의 tip ──────────────────────────────────
  group('branchLineTips', () {
    test('a line whose tip wears no ref reports that tip', () {
      final rows = layoutGraph([
        commit(
          'merge',
          'merge',
          parents: ['main-parent', 'gone-tip'],
          refs: const [GitRef(name: 'main')],
        ),
        commit('gone-tip', 'gone tip', parents: ['root']),
        commit('main-parent', 'older main', parents: ['root']),
        commit('root', 'root'),
      ]);

      final tips = branchLineTips(rows, const RepoRefs());
      final gone = rows.firstWhere((row) => row.commit.sha == 'gone-tip');
      expect(tips[gone.branch], 'gone-tip');
    });

    test('a named line is left out — its ref already speaks', () {
      final rows = layoutGraph([
        commit(
          'a',
          'tip',
          parents: ['b'],
          refs: const [GitRef(name: 'main')],
        ),
        commit('b', 'root'),
      ]);

      expect(branchLineTips(rows, const RepoRefs()), isEmpty);
    });

    test('the working tree row is never a line tip', () {
      final rows = layoutGraph([
        commit('', 'working tree', parents: ['a']),
        commit('a', 'tip', parents: ['b']),
        commit('b', 'root'),
      ]);

      expect(branchLineTips(rows, const RepoRefs()).values, ['a']);
    });
  });

  // ── 화면 ─────────────────────────────────────────────────────────
  List<GitCommit> history() => [
    commit(
      'a',
      'tip',
      parents: ['b'],
      refs: const [GitRef(name: 'main')],
    ),
    commit('b', 'middle', parents: ['c']),
    commit('c', 'root'),
  ];

  Future<void> pumpTimeline(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(FakeGitRepository((_, _) async => history()), controller),
    );
    await tester.pumpAndSettle();
  }

  Finder rowName(int index) => find.byKey(Key('row-branch-name-$index'));

  testWidgets('the focused row names the line it sits on', (tester) async {
    await pumpTimeline(tester);

    // 커서를 tip 아래 행으로 내린다.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(rowName(1), findsOneWidget);
    expect(
      find.descendant(of: rowName(1), matching: find.text('main')),
      findsOneWidget,
    );
  });

  testWidgets('it wears the same chip a tip does, only dimmed', (tester) async {
    await pumpTimeline(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    BoxDecoration decorationOf(Finder finder) =>
        tester.widget<Container>(finder).decoration! as BoxDecoration;

    final tip = decorationOf(find.byKey(const Key('ref-chip-a-main')));
    final onLine = decorationOf(rowName(1));

    expect(onLine.borderRadius, tip.borderRadius, reason: '같은 모양이어야 한다');
    expect(onLine.color!.a, lessThan(tip.color!.a), reason: '같은 색을 흐리게');
    expect(
      (onLine.border! as Border).top.color.a,
      lessThan((tip.border! as Border).top.color.a),
    );

    // 이 행을 가리키는 ref가 없으니 그래프로 향하는 연결선도 없다.
    expect(
      find.descendant(
        of: find.byKey(const Key('refs-cell-1')),
        matching: find.byKey(const Key('ref-chip-connector-b')),
      ),
      findsNothing,
    );
  });

  testWidgets('hovering a row is enough to name its line', (tester) async {
    await pumpTimeline(tester);
    expect(rowName(2), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('refs-cell-2'))));
    await tester.pumpAndSettle();

    expect(rowName(2), findsOneWidget, reason: '클릭까지 갈 필요 없다');
  });

  testWidgets('the dimmed chip leaves room for the ink it draws', (
    tester,
  ) async {
    // The same cushion a real chip keeps: a glyph inks a hair past the width
    // it reports, and a name cut to exactly its box loses that hair.
    for (var width = 90.0; width <= 200; width += 1) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(
            repository: FakeGitRepository(
              (_, _) async => [
                commit(
                  'a',
                  'tip',
                  parents: ['b'],
                  refs: const [GitRef(name: 'feature/pr-monitoring')],
                ),
                commit('b', 'middle', parents: ['c']),
                commit('c', 'root'),
              ],
            ),
            controller: controller,
            columnWidths: TimelineColumnWidths(refs: width),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final label = find.descendant(
        of: rowName(1),
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data?.isNotEmpty ?? false),
        ),
      );
      if (label.evaluate().isEmpty) continue;
      final text = tester.widget<Text>(label);
      final painter = TextPainter(
        text: TextSpan(
          text: text.data,
          // 화면이 실제로 그리는 스타일로 잰다. 칩이 들고 있는 TextStyle에는
          // 글자 간격이 없고 상속 쪽에만 있어서, 그것만 재면 글자마다 조금씩
          // 짧게 나오고 이름 끝이 테두리에 깎인다.
          style: DefaultTextStyle.of(
            tester.element(label),
          ).style.merge(text.style),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      expect(
        painter.width,
        lessThanOrEqualTo(tester.getSize(label).width - 2),
        reason: 'refs 폭 $width: 흐린 칩도 마지막 획이 깎이면 안 된다',
      );
    }
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  testWidgets('only the focused row says it', (tester) async {
    await pumpTimeline(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(rowName(2), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(rowName(1), findsNothing, reason: '떠난 행에서는 사라진다');
    expect(rowName(2), findsOneWidget);
  });

  testWidgets('a deleted line the merge remembers names itself on hover', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit(
              'merge',
              "Merge branch 'gone' into main",
              parents: ['main-parent', 'gone-tip'],
              refs: const [GitRef(name: 'main')],
            ),
            commit('gone-tip', 'finish the feature', parents: ['root']),
            commit('main-parent', 'older main', parents: ['root']),
            commit('root', 'root'),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // 지운 브랜치라 ref가 없지만, 머지 커밋 제목이 이름을 기억하고 있다.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('refs-cell-1'))));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: rowName(1), matching: find.text('gone')),
      findsOneWidget,
      reason: '메모리가 아는 이름은 hover만으로 나온다',
    );
  });

  testWidgets('hovering a nameless line asks git nothing', (tester) async {
    var reflogReads = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('a', 'tip', parents: ['b']),
            commit('b', 'root'),
          ],
          refs: const RepoRefs(),
          runner: (executable, args, {workingDirectory, environment}) async {
            if (args.contains('reflog')) reflogReads++;
            return ProcessResult(1, 0, '', '');
          },
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    final atRest = reflogReads;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final row in [0, 1, 0, 1]) {
      await mouse.moveTo(
        tester.getCenter(find.byKey(Key('refs-cell-$row'))),
      );
      await tester.pumpAndSettle();
    }

    // 마우스가 지나가는 것은 요청이 아니다.
    expect(reflogReads, atRest);
    expect(rowName(1), findsNothing);
  });

  testWidgets('the folded reflog names a line no merge remembers', (
    tester,
  ) async {
    var reflogReads = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('gone-tip', 'finish the feature', parents: ['root']),
            commit('root', 'root'),
          ],
          refs: const RepoRefs(),
          runner: (executable, args, {workingDirectory, environment}) async {
            if (!args.contains('reflog')) return ProcessResult(1, 0, '', '');
            reflogReads++;
            return ProcessResult(
              1,
              0,
              'main-tip\x00checkout: moving from gone to main\n'
                  'gone-tip\x00commit: finish the feature\n',
              '',
            );
          },
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    expect(reflogReads, 0, reason: '첫 화면은 reflog를 기다리지 않는다');
    expect(rowName(0), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(reflogReads, 1, reason: '한 번만 읽어 접어 둔다');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('refs-cell-0'))));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: rowName(0), matching: find.text('gone')),
      findsOneWidget,
    );
  });

  testWidgets('another repository folds its own reflog, not the last one', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    FakeGitRepository repositoryNaming(String branch) => FakeGitRepository(
      (_, _) async => [
        commit('gone-tip', 'finish the feature', parents: ['root']),
        commit('root', 'root'),
      ],
      refs: const RepoRefs(),
      runner: (executable, args, {workingDirectory, environment}) async =>
          args.contains('reflog')
          ? ProcessResult(
              1,
              0,
              'main-tip\x00checkout: moving from $branch to main\n'
                  'gone-tip\x00commit: finish the feature\n',
              '',
            )
          : ProcessResult(1, 0, '', ''),
    );

    Future<void> hoverTip() async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('refs-cell-0'))),
      );
      await tester.pumpAndSettle();
      await mouse.removePointer();
    }

    await tester.pumpWidget(app(repositoryNaming('first'), controller));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await hoverTip();
    expect(
      find.descendant(of: rowName(0), matching: find.text('first')),
      findsOneWidget,
    );

    // 저장소를 갈아 끼우면 앞 저장소의 이름이 남아 있어서는 안 되고, 새 저장소의
    // reflog를 다시 접어야 한다.
    await tester.pumpWidget(app(repositoryNaming('second'), controller));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await hoverTip();
    expect(find.text('first'), findsNothing);
    expect(
      find.descendant(of: rowName(0), matching: find.text('second')),
      findsOneWidget,
    );
  });

  testWidgets('a branch comparison never borrows a name by line id', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    // 비교 화면은 레이아웃을 따로 잡아 선 id가 평소 그래프와 다른 것을 가리킨다.
    // 그 id로 이름을 꺼내면 엉뚱한 브랜치 이름이 붙는다.
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit(
              'merge',
              "Merge branch 'gone' into main",
              parents: ['main-parent', 'gone-tip'],
              refs: const [GitRef(name: 'main')],
            ),
            commit('gone-tip', 'finish the feature', parents: ['root']),
            commit('main-parent', 'older main', parents: ['root']),
            commit('root', 'root'),
          ],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'merge', 'feature': 'main-parent'},
          ),
          compareBranchesCallback: (_, _) async => BranchComparisonResult(
            baseRef: 'main',
            compareRef: 'feature',
            baseTip: 'merge',
            compareTip: 'main-parent',
            baseParent: 'root',
            compareParent: 'root',
            mergeBases: const ['root'],
            commits: [
              BranchComparisonCommit(
                commit: commit('merge', 'merge', parents: const ['root']),
                side: BranchCommitSide.baseOnly,
              ),
              BranchComparisonCommit(
                commit: commit(
                  'main-parent',
                  'older main',
                  parents: const ['root'],
                ),
                side: BranchCommitSide.compareOnly,
              ),
              BranchComparisonCommit(
                commit: commit('root', 'root'),
                side: BranchCommitSide.commonBoundary,
              ),
            ],
            files: const [],
            merge: const MergeConflictCheck(status: MergeConflictStatus.clean),
          ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-menu-feature')));
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final row in [0, 1, 2]) {
      final cell = find.byKey(Key('refs-cell-$row'));
      if (cell.evaluate().isEmpty) continue;
      await mouse.moveTo(tester.getCenter(cell));
      await tester.pumpAndSettle();
    }

    expect(find.text('gone'), findsNothing);
  });

  testWidgets('a row wearing its own chip is left alone', (tester) async {
    await pumpTimeline(tester);

    // 행 0이 tip이라 이미 main 칩을 달고 있다.
    expect(find.byKey(const Key('row-branch-name-0')), findsNothing);
  });

  testWidgets('an unnamed line says nothing', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('a', 'tip', parents: ['b']),
            commit('b', 'root'),
          ],
          refs: const RepoRefs(),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(rowName(1), findsNothing);
  });
}
