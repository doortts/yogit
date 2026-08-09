import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
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
