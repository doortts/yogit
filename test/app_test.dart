import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/diff_screen.dart';
import 'package:yogit/git.dart';
import 'package:yogit/main.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WindowFrameController controller;

  setUp(() {
    final channel = const MethodChannel('test/yogit-window');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    controller = WindowFrameController(channel: channel);
  });

  testWidgets('keyboard and pointer control selection and preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('1', 'first commit'),
            commit('2', 'second commit'),
            commit('3', 'third commit'),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(
      find.byKey(const Key('timeline-list')),
    );
    expect(list.itemExtent, 36);
    expect(list.cacheExtent, 200);

    // The preview starts hidden and only a key opens it.
    expect(find.text('Commit & Diff'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('second commit'), findsOneWidget);
    final selected = find.byKey(const Key('selected-row-2'));
    expect(selected, findsOneWidget);
    final selectedBox =
        tester.widget<GestureDetector>(selected).child! as ColoredBox;
    expect(selectedBox.color, const Color(0xFF1F4D8F));
    expect(
      selectedBox.color.computeLuminance(),
      greaterThan(const Color(0xFF15171E).computeLuminance()),
    );
    // The blue band runs the whole row, refs and graph cells included.
    for (final cell in ['refs-cell-1', 'graph-cell-1']) {
      expect(
        find.descendant(of: selected, matching: find.byKey(Key(cell))),
        findsOneWidget,
      );
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);

    // Enter toggles: a second press closes what the first opened.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);

    await tester.tap(find.text('하단'));
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.bottom);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);

    // A click selects; it no longer opens the panel.
    await tester.tap(find.text('third commit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-3')), findsOneWidget);
    expect(find.text('Commit & Diff'), findsNothing);

    // Space opens it just like Enter, on the clicked row, and closes it again.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('preview-panel')),
        matching: find.text('third commit'),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);
  });

  testWidgets('selection moves rebuild only the rows that changed', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async =>
              List.generate(8, (index) => commit('$index', 'commit $index')),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // A row that does not rebuild keeps the very same widget instances.
    Text subject(int index) => tester.widget<Text>(find.text('commit $index'));
    final before = {
      for (var index = 0; index < 8; index++) index: subject(index),
    };

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(identical(subject(0), before[0]), isFalse);
    expect(identical(subject(1), before[1]), isFalse);
    for (var index = 2; index < 8; index++) {
      expect(
        identical(subject(index), before[index]),
        isTrue,
        reason: '$index',
      );
    }
  });

  testWidgets('keyboard selection scrolls only at the viewport edges', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async =>
              List.generate(60, (index) => commit('$index', 'commit $index')),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('timeline-list')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    final viewport = position.viewportDimension;

    // Moving inside the viewport leaves the list where it is.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(position.pixels, 0);

    // The date heading leads the list, so the first commit sits at entry 1.
    var index = 2;
    while (position.pixels == 0 && index < 40) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      index++;
    }

    // Nothing moved until the selected row's bottom passed the viewport bottom,
    // and then only far enough to hold the row flush against that edge.
    expect(index * 36.0, greaterThan(viewport - 36));
    expect(position.pixels, (index + 1) * 36 - viewport);
    final anchored = position.pixels;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    index++;
    expect(position.pixels, anchored + 36);

    // Upward is symmetric: the row stays visible without a scroll until it would
    // pass the top edge, and the walk ends with the list back at the top.
    while (index > 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      index--;
      expect(position.pixels, lessThanOrEqualTo(index * 36.0));
      expect(
        position.pixels,
        greaterThanOrEqualTo((index + 1) * 36.0 - viewport),
      );
    }
    // The walk ends with the first commit flush at the top; the date heading
    // above it stays off screen until the user scrolls there.
    expect(position.pixels, 36);
    expect(find.byKey(const Key('selected-row-0')), findsOneWidget);
  });

  testWidgets('holding an arrow key keeps moving the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async =>
              List.generate(6, (index) => commit('$index', 'commit $index')),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const Key('selected-row-1')), findsOneWidget);

    // Autorepeat while the key stays held.
    for (var repeat = 2; repeat <= 4; repeat++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.byKey(Key('selected-row-$repeat')), findsOneWidget);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byKey(const Key('selected-row-2')), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);

    // Enter and Space ignore repeats, so a held key opens the panel once.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  });

  testWidgets('graph viewport resize does not scale lane coordinates', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('3', 'merge', parents: const ['2', 'branch']),
            commit('2', 'main', parents: const ['1']),
            commit('branch', 'branch', parents: const ['1']),
            commit('1', 'root'),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final beforeSize = tester.getSize(find.byKey(const Key('graph-painter-0')));
    final before =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    final beforeSpacing = before.laneX(1) - before.laneX(0);

    expect(timelineColumns.keys, [
      'refs',
      'graph',
      'hash',
      'commit',
      'time',
      'name',
    ]);
    for (final column in timelineColumns.keys) {
      expect(find.byKey(Key('$column-resizer')), findsOneWidget);
    }
    final header = tester.widget<Text>(find.text('GRAPH'));
    expect(header.style?.fontFamily, 'monospace');
    expect(header.style?.fontSize, 12);
    final commitHeader = tester.widget<Text>(find.text('COMMIT MESSAGE'));
    expect(commitHeader.style?.fontFamily, 'monospace');
    expect(commitHeader.style?.fontSize, 12);
    expect(find.text('DATE'), findsOneWidget);
    expect(find.text('NAME'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(48, 0),
    );
    await tester.pump();

    final afterSize = tester.getSize(find.byKey(const Key('graph-painter-0')));
    final after =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;

    // Two lanes auto-fit to 28 + 2 * 30, clamped up to the 96px minimum.
    expect(beforeSize.width, 96);
    expect(before.laneSpacing, 30);
    expect(afterSize.width, greaterThan(beforeSize.width));
    expect(after.laneSpacing, before.laneSpacing);
    expect(after.laneX(1) - after.laneX(0), beforeSpacing);
  });

  testWidgets('right to bottom preview animates through an intermediate size', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byKey(const Key('preview-panel')));
    await tester.tap(find.text('하단'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final intermediate = tester.getSize(find.byKey(const Key('preview-panel')));

    expect(intermediate.width, greaterThan(before.width));
    // Full width of the workspace beside the 150px sidebar.
    expect(intermediate.width, 650);
    expect(intermediate.height, lessThan(before.height));
    expect(intermediate.height, greaterThan(0));
    expect(intermediate.height, lessThan(280));
  });

  testWidgets('preview loads real files before the first file diff once', (
    tester,
  ) async {
    var fileLoads = 0;
    var diffLoads = 0;
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'first commit')],
      files: (_, _) async {
        fileLoads++;
        return const [
          GitFileChange(
            path: 'lib/first.dart',
            status: 'M',
            additions: 1,
            deletions: 0,
          ),
          GitFileChange(
            path: 'README.md',
            status: 'A',
            additions: 2,
            deletions: 0,
          ),
        ];
      },
      diff: (_, _, path, _) async {
        diffLoads++;
        return [
          DiffLine(kind: DiffLineKind.add, text: '$path changed', newNumber: 1),
        ];
      },
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // Once in the file list, once as the diff head line.
    expect(find.text('lib/first.dart'), findsNWidgets(2));
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('+lib/first.dart changed'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('preview-files'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('preview-diff'))).dy),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fileLoads, 1);
    expect(diffLoads, 1);
  });

  testWidgets('preview is a structural sibling and preserves timeline state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async =>
              List.generate(100, (index) => commit('$index', 'commit $index')),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final initialTimelineSize = tester.getSize(
      find.byKey(const Key('timeline-viewport')),
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(360);
    await tester.pump();

    tester.view.physicalSize = const Size(1088, 600);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final rightLayout = find.byKey(const Key('preview-layout-right'));
    expect(rightLayout, findsOneWidget);
    expect(tester.widget(rightLayout), isA<Row>());
    expect(
      find.descendant(
        of: rightLayout,
        matching: find.byKey(const Key('timeline-viewport')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: rightLayout,
        matching: find.byKey(const Key('preview-panel')),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('preview-panel')),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const Key('timeline-viewport'))),
      initialTimelineSize,
    );
    expect(scrollable.position.pixels, 360);

    await tester.tap(find.text('하단'));
    tester.view.physicalSize = const Size(800, 880);
    await tester.pumpAndSettle();

    final bottomLayout = find.byKey(const Key('preview-layout-bottom'));
    expect(bottomLayout, findsOneWidget);
    expect(tester.widget(bottomLayout), isA<Column>());
    expect(
      find.descendant(
        of: bottomLayout,
        matching: find.byKey(const Key('timeline-viewport')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomLayout,
        matching: find.byKey(const Key('preview-panel')),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('timeline-viewport'))),
      initialTimelineSize,
    );
    expect(scrollable.position.pixels, 360);
  });

  test('lane transitions turn on one 8px corner beside their node', () {
    GraphRow rowTo(int parentLane) => graphRow(
      commit: commit('1', 'first commit', parents: ['0']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: [parentLane],
      activeLaneShas: const {0: '1'},
      nextLaneShas: {parentLane: '0'},
      transitions: [(from: 0, to: parentLane, sha: '0')],
    );
    CommitGraphPainter painterTo(int parentLane) => CommitGraphPainter(
      row: rowTo(parentLane),
      selected: false,
      committerColor: const Color(0xFF7AD6E8),
    );

    const size = Size(168, 36);
    final painter = painterTo(1);
    expect(painter.laneX(0), 28);
    expect(painter.laneX(1), 58);
    expect(painter.laneX(2), 88);
    expect(CommitGraphPainter.railWidth, 2.0);
    expect(CommitGraphPainter.railOpacity, 1.0);
    // One corner radius for both kinds; the flat run carries the rest.
    expect(CommitGraphPainter.cornerRadius, 8);

    // Node center (y 18) down to the next row's center (y 54): one row height,
    // and no overshoot outside the two lanes.
    expect(painter.row.transitions, [(from: 0, to: 1, sha: '0')]);
    final path = painter.transitionPath(0, 1, 18, size, bendEarly: true);
    expect(path.getBounds(), const Rect.fromLTRB(28, 18, 58, 54));

    final metrics = path.computeMetrics().single;
    ui.Tangent at(double fraction) =>
        metrics.getTangentForOffset(metrics.length * fraction)!;

    // A birth leaves its node sideways and enters its new column vertically.
    expect(at(0).vector.dy.abs(), lessThan(0.01));
    expect(at(0).vector.dx, greaterThan(0.99));
    expect(at(1).vector.dx.abs(), lessThan(0.01));
    expect(at(1).vector.dy, greaterThan(0.99));

    // A birth runs flat out of its source's side, corners, and is vertical in its
    // new column well before the arrival row.
    expect(_touches(path, const Offset(28, 18)), isTrue);
    expect(_touches(path, const Offset(50, 18)), isTrue);
    final samples = _samples(path);
    expect(
      samples.where((point) => point.dy > 26.5).map((point) => point.dx),
      everyElement(58),
    );
    expect(
      samples.where((point) => point.dy > 50).map((point) => point.dx),
      everyElement(58),
    );
    // Halfway along the sweep it is neither on its old level nor on the new lane.
    final middle = at(0.5).position;
    expect(middle.dx, greaterThan(28));
    expect(middle.dx, lessThan(58));
    expect(middle.dy, greaterThan(18));
    expect(middle.dy, lessThan(54));
    // The arc cuts the corner, so the path is shorter than the two straights.
    expect(metrics.length, lessThan(30 + 36));

    // A first parent that keeps the lane records no transition at all: it is a
    // straight vertical from the node to the row edge.
    final straight = CommitGraphPainter(
      row: graphRow(
        commit: commit('1', 'first commit', parents: ['0']),
        lane: 0,
        activeLanes: const [0],
        nextLanes: const [0],
        activeLaneShas: const {0: '1'},
        nextLaneShas: const {0: '0'},
      ),
      selected: false,
      committerColor: const Color(0xFF7AD6E8),
    );
    expect(straight.row.transitions, isEmpty);
    expect(straight.laneVerticals(size)[0], (top: 18.0, bottom: 36.0));

    // The arrival row paints the same path one row height higher, so the two
    // halves meet exactly on the shared row boundary.
    expect(
      painter
          .transitionPath(0, 1, 18 - size.height, size, bendEarly: true)
          .getBounds(),
      const Rect.fromLTRB(28, -18, 58, 18),
    );

    // A join mirrors it: down its own column, then one arc onto the parent's own
    // center, arriving horizontally at the dot.
    final join = painter.transitionPath(0, 1, 18, size);
    expect(join.getBounds(), const Rect.fromLTRB(28, 18, 58, 54));
    final joinMetrics = join.computeMetrics().single;
    expect(joinMetrics.getTangentForOffset(0)!.vector.dy, greaterThan(0.99));
    expect(
      joinMetrics.getTangentForOffset(joinMetrics.length)!.vector.dx,
      greaterThan(0.99),
    );
    expect(joinMetrics.length, lessThan(30 + 36));
    final joinSamples = _samples(join);
    // It holds its lane until the corner, releases 8px along, then runs flat.
    expect(
      joinSamples.where((point) => point.dy < 45).map((point) => point.dx),
      everyElement(28),
    );
    expect(_touches(join, const Offset(36, 54)), isTrue);
    expect(
      joinSamples.where((point) => point.dx > 37).map((point) => point.dy),
      everyElement(54),
    );
    expect(_touches(join, const Offset(58, 50)), isFalse);
    expect(_touches(join, const Offset(58, 54)), isTrue);
    // No stub under the source node either: 8px down it is still on its lane.
    expect(_touches(join, const Offset(43, 26)), isFalse);

    // A distant lane cannot be spanned by one arc, so it keeps a flat run at the
    // node's own level.
    final distant = painterTo(
      2,
    ).transitionPath(0, 2, 18, size, bendEarly: true);
    expect(distant.getBounds(), const Rect.fromLTRB(28, 18, 88, 54));
    final distantRun = _samples(
      distant,
    ).where((point) => (point.dy - 18).abs() < 0.01).toList();
    expect(distantRun.first.dx, 28);
    // The run carries the lane gap the single arc cannot, handing over to it a
    // radius short of the new column.
    expect(_touches(distant, const Offset(58, 18)), isTrue);
    expect(distantRun.last.dx, greaterThanOrEqualTo(58));

    // Leftward transitions mirror, keeping the same radius.
    expect(
      painter.transitionPath(2, 0, 18, size, bendEarly: true).getBounds(),
      const Rect.fromLTRB(28, 18, 88, 54),
    );
  });

  test('a converging line holds its column, then slides in at its parent', () {
    const size = Size(168, 36);
    // Lane 1's line hands off to its first parent on lane 0: the row above the
    // parent records the convergence, and the dying branch's last node sits on
    // lane 1 right above it.
    final converging = graphRow(
      commit: commit('X', 'main commit', parents: const ['P']),
      lane: 0,
      activeLanes: const [0, 1],
      nextLanes: const [0],
      activeLaneShas: const {0: 'X', 1: 'P'},
      nextLaneShas: const {0: 'P'},
      parentLanes: const [0],
      transitions: const [(from: 1, to: 0, sha: 'P')],
      branch: 0,
      activeLaneBranches: const {0: 0, 1: 1},
      nextLaneBranches: const {0: 0},
    );
    final transition = converging.transitions.single;
    // Same discriminator as the color rule: this is not a birth.
    expect(CommitGraphPainter.isMergeEdge(converging, transition), isFalse);
    expect(CommitGraphPainter.transitionBranch(converging, transition), 1);

    final painter = CommitGraphPainter(
      row: converging,
      selected: false,
      committerColor: AvatarService.branchColor(0),
    );
    final path = painter.transitionPath(
      transition.from,
      transition.to,
      18,
      size,
      bendEarly: CommitGraphPainter.isMergeEdge(converging, transition),
    );

    // Through its own row the line stays in its column — no early horizontal.
    expect(
      _samples(path).where((point) => point.dy <= 24).map((point) => point.dx),
      everyElement(closeTo(painter.laneX(1), 0.01)),
    );
    // So no stub is left 8px under the dying branch's last node.
    expect(
      _touches(path, Offset((painter.laneX(0) + painter.laneX(1)) / 2, 18 + 8)),
      isFalse,
    );
    // One lane-wide arc onto the parent's own center, arriving horizontally at
    // the dot: no second corner, no trailing vertical on the parent's lane.
    expect(path.getBounds(), const Rect.fromLTRB(28, 18, 58, 54));
    final metrics = path.computeMetrics().single;
    expect(metrics.getTangentForOffset(0)!.vector.dy, greaterThan(0.99));
    expect(
      metrics.getTangentForOffset(metrics.length)!.vector.dx,
      lessThan(-0.99),
    );
    expect(metrics.length, lessThan(30 + 36));
    expect(_touches(path, Offset(painter.laneX(0), 54)), isTrue);
    expect(_touches(path, Offset(painter.laneX(0) + 2, 54)), isTrue);
    // Nothing descends the parent's own lane into the dot.
    expect(_touches(path, Offset(painter.laneX(0), 50)), isFalse);

    // The arrival half shows that turn inside the parent's own row.
    final arrival = painter.transitionPath(
      transition.from,
      transition.to,
      18 - size.height,
      size,
      bendEarly: CommitGraphPainter.isMergeEdge(converging, transition),
    );
    expect(_touches(arrival, Offset(painter.laneX(0), 18)), isTrue);
    expect(_touches(arrival, Offset(painter.laneX(0) + 2, 18)), isTrue);
    // Side entry into the dot, parent's lane clear above it.
    expect(_touches(arrival, Offset(painter.laneX(0), 14)), isFalse);
  });

  test('a transition lane gets no straight rail overdrawing its curve', () {
    const size = Size(168, 36);
    const color = Color(0xFF7AD6E8);

    // C is a merge: lane 0 keeps the first parent, lane 1 receives the second.
    final merge = graphRow(
      commit: commit('C', 'merge', parents: const ['A', 'B']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'C'},
      nextLaneShas: const {0: 'A', 1: 'B'},
      transitions: const [(from: 0, to: 1, sha: 'B')],
    );
    final child = CommitGraphPainter(
      row: merge,
      selected: false,
      committerColor: color,
    );
    // Lane 1 gets no vertical here: the curve reaches it in the row below.
    expect(child.laneVerticals(size).containsKey(1), isFalse);
    // C is the newest row, so its own lane only hands the first parent down.
    expect(child.laneVerticals(size)[0], (top: 18.0, bottom: 36.0));

    final main = graphRow(
      commit: commit('A', 'main', parents: const ['R']),
      lane: 0,
      activeLanes: const [0, 1],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'A', 1: 'B'},
      nextLaneShas: const {0: 'R', 1: 'B'},
    );
    final arrival = CommitGraphPainter(
      row: main,
      previous: merge,
      selected: false,
      committerColor: color,
    );
    // Lane 1 was created by the merge, so its rail resumes at the row center,
    // below the arriving curve.
    expect(arrival.continuesFromAbove(1), isFalse);
    expect(arrival.laneVerticals(size)[1], (top: 18.0, bottom: 36.0));
    // Its own lane does come from above, and hands its parent down.
    expect(arrival.laneVerticals(size)[0], (top: 0.0, bottom: 36.0));

    // B branches back into lane 0, which is already running: that lane keeps its
    // full vertical so the rail does not break where the curve joins it.
    final branch = graphRow(
      commit: commit('B', 'branch', parents: const ['R']),
      lane: 1,
      activeLanes: const [0, 1],
      nextLanes: const [0],
      activeLaneShas: const {0: 'R', 1: 'B'},
      nextLaneShas: const {0: 'R'},
      transitions: const [(from: 1, to: 0, sha: 'R')],
    );
    final joining = CommitGraphPainter(
      row: branch,
      previous: main,
      selected: false,
      committerColor: color,
    );
    expect(joining.laneVerticals(size)[0], (top: 0.0, bottom: 36.0));
    // Lane 1 runs down into the node and leaves on the curve.
    expect(joining.laneVerticals(size)[1], (top: 0.0, bottom: 18.0));

    final joined = CommitGraphPainter(
      row: graphRow(
        commit: commit('R', 'root'),
        lane: 0,
        activeLanes: const [0],
        activeLaneShas: const {0: 'R'},
      ),
      previous: branch,
      selected: false,
      committerColor: color,
    );
    expect(joined.continuesFromAbove(0), isTrue);
    expect(joined.laneVerticals(size)[0], (top: 0.0, bottom: 18.0));
  });

  test('a lane that starts at its row draws no rail above the node', () {
    const size = Size(168, 36);
    const color = Color(0xFF7AD6E8);

    // B is a branch tip: lane 1 starts on its own row, nothing above it.
    final main = graphRow(
      commit: commit('A', 'main', parents: const ['R']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0],
      activeLaneShas: const {0: 'A'},
      nextLaneShas: const {0: 'R'},
    );
    final tip = CommitGraphPainter(
      row: graphRow(
        commit: commit('B', 'branch tip', parents: const ['R']),
        lane: 1,
        activeLanes: const [0, 1],
        nextLanes: const [0],
        activeLaneShas: const {0: 'R', 1: 'B'},
        nextLaneShas: const {0: 'R'},
        transitions: const [(from: 1, to: 0, sha: 'R')],
      ),
      previous: main,
      selected: false,
      committerColor: color,
    );
    expect(tip.continuesFromAbove(1), isFalse);
    expect(tip.laneVerticals(size).containsKey(1), isFalse);

    // The working tree row leads the list, so it has no rail above it either,
    // but it does hand lane 0 to the commit underneath.
    final working = graphRow(
      commit: workingTreeCommit('1'),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0],
      activeLaneShas: const {0: ''},
      nextLaneShas: const {0: '1'},
    );
    final wip = CommitGraphPainter(
      row: working,
      selected: false,
      committerColor: color,
    );
    expect(wip.continuesFromAbove(0), isFalse);
    expect(wip.laneVerticals(size)[0], (top: 18.0, bottom: 36.0));
    final underWip = CommitGraphPainter(
      row: graphRow(
        commit: commit('1', 'head'),
        lane: 0,
        activeLanes: const [0],
        activeLaneShas: const {0: '1'},
      ),
      previous: working,
      selected: false,
      committerColor: color,
    );
    expect(underWip.continuesFromAbove(0), isTrue);
    expect(underWip.laneVerticals(size)[0], (top: 0.0, bottom: 18.0));
  });

  test('rails and curves take their branch line color', () {
    const size = Size(168, 36);
    const other = GitIdentity(name: 'Other', email: 'other@example.com');
    // Two branch ids whose colors are not this person's, so a per-committer
    // fallback anywhere would show up as a mismatch.
    final person = AvatarService.color(other);
    final ids = [
      for (var id = 0; id < AvatarService.defaultColors.length; id++)
        if (AvatarService.branchColor(id) != person) id,
    ];
    final (main, feature) = (ids.first, ids[1]);
    final merge = graphRow(
      commit: commit('C', 'merge', parents: const ['A', 'B']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'C'},
      nextLaneShas: const {0: 'A', 1: 'B'},
      transitions: [(from: 0, to: 1, sha: 'B')],
      branch: main,
      activeLaneBranches: {0: main},
      nextLaneBranches: {0: main, 1: feature},
    );
    final painter = CommitGraphPainter(
      row: merge,
      selected: false,
      committerColor: AvatarService.branchColor(merge.branch),
      committersBySha: const {'A': other, 'B': other},
    );

    // The rail, the merge curve and the merge dot all paint palette colors
    // picked by branch id, never a person's color.
    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      paints
        ..line(color: AvatarService.branchColor(main))
        ..path(color: AvatarService.branchColor(feature))
        ..circle(color: AvatarService.branchColor(main)),
    );

    // A lane without a branch id keeps the old per-committer color.
    final legacy = CommitGraphPainter(
      row: graphRow(
        commit: commit('C', 'merge', parents: const ['A', 'B']),
        lane: 0,
        activeLanes: const [0],
        nextLanes: const [0, 1],
        activeLaneShas: const {0: 'C'},
        nextLaneShas: const {0: 'A', 1: 'B'},
        transitions: const [(from: 0, to: 1, sha: 'B')],
      ),
      selected: false,
      committerColor: person,
      committersBySha: const {'A': other, 'B': other},
    );
    expect(
      (Canvas canvas) => legacy.paint(canvas, size),
      paints
        ..line(color: AvatarService.color(other))
        ..path(color: AvatarService.color(other)),
    );
  });

  test('a sweep keeps the color of the line it belongs to', () {
    const size = Size(168, 36);
    // main = 0, alpha = 1, hotfix = 2, all with distinct palette colors.
    Color line(int branch) => AvatarService.branchColor(branch);
    CommitGraphPainter painter(GraphRow row, {GraphRow? previous}) =>
        CommitGraphPainter(
          row: row,
          previous: previous,
          selected: false,
          committerColor: line(row.branch),
        );

    // A foreign column converging on its first parent: main's commit sits on
    // lane 0 while hotfix's tail sweeps in from lane 2. The sweep is hotfix's.
    final converging = graphRow(
      commit: commit('M', 'main commit', parents: const ['P']),
      lane: 0,
      activeLanes: const [0, 2],
      nextLanes: const [0],
      activeLaneShas: const {0: 'M', 2: 'P'},
      nextLaneShas: const {0: 'P'},
      parentLanes: const [0],
      transitions: const [(from: 2, to: 0, sha: 'P')],
      branch: 0,
      activeLaneBranches: const {0: 0, 2: 2},
      nextLaneBranches: const {0: 0},
    );
    expect(
      CommitGraphPainter.transitionBranch(
        converging,
        converging.transitions.single,
      ),
      2,
    );
    expect(
      (Canvas canvas) => painter(converging).paint(canvas, size),
      paints..path(color: line(2)),
    );

    // A commit's own first-parent tail moving column: alpha's line, not the
    // destination's.
    final tail = graphRow(
      commit: commit('A', 'alpha commit', parents: const ['R']),
      lane: 1,
      activeLanes: const [0, 1],
      nextLanes: const [0],
      activeLaneShas: const {0: 'R', 1: 'A'},
      nextLaneShas: const {0: 'R'},
      parentLanes: const [0],
      transitions: const [(from: 1, to: 0, sha: 'R')],
      branch: 1,
      activeLaneBranches: const {0: 0, 1: 1},
      nextLaneBranches: const {0: 0},
    );
    expect(
      CommitGraphPainter.transitionBranch(tail, tail.transitions.single),
      1,
    );
    expect(
      (Canvas canvas) => painter(tail).paint(canvas, size),
      paints..path(color: line(1)),
    );

    // A merge edge to a further parent keeps the destination line's color.
    final merge = graphRow(
      commit: commit('C', 'merge', parents: const ['A', 'B']),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'C'},
      nextLaneShas: const {0: 'A', 1: 'B'},
      parentLanes: const [0, 1],
      transitions: const [(from: 0, to: 1, sha: 'B')],
      branch: 0,
      activeLaneBranches: const {0: 0},
      nextLaneBranches: const {0: 0, 1: 2},
    );
    expect(
      CommitGraphPainter.transitionBranch(merge, merge.transitions.single),
      2,
    );
    expect(
      (Canvas canvas) => painter(merge).paint(canvas, size),
      paints..path(color: line(2)),
    );

    // Arrival halves repeat their departure half's color, so a sweep is one
    // color across the row boundary.
    for (final departure in [converging, tail, merge]) {
      final arrival = graphRow(
        commit: commit('P', 'parent', parents: const ['R']),
        lane: 0,
        activeLanes: const [0],
        nextLanes: const [0],
        activeLaneShas: const {0: 'P'},
        nextLaneShas: const {0: 'R'},
        parentLanes: const [0],
        branch: 0,
        activeLaneBranches: const {0: 0},
        nextLaneBranches: const {0: 0},
      );
      expect(
        (Canvas canvas) =>
            painter(arrival, previous: departure).paint(canvas, size),
        paints
          ..line()
          ..path(
            color: line(
              CommitGraphPainter.transitionBranch(
                departure,
                departure.transitions.single,
              )!,
            ),
          ),
      );
    }
  });

  test('a collapsing lane slides on a transition, not a straight rail', () {
    const size = Size(168, 36);
    const color = Color(0xFF7AD6E8);

    // Lane 1 empties as C hands its first parent to lane 0, so git slides the
    // pass-through lane 2 one column left into it.
    final above = graphRow(
      commit: commit('H', 'head', parents: const ['P']),
      lane: 0,
      activeLanes: const [0, 1, 2],
      nextLanes: const [0, 1, 2],
      activeLaneShas: const {0: 'H', 1: 'C', 2: 'X'},
      nextLaneShas: const {0: 'P', 1: 'C', 2: 'X'},
    );
    final collapse = graphRow(
      commit: commit('C', 'joins main', parents: const ['P']),
      lane: 1,
      activeLanes: const [0, 1, 2],
      nextLanes: const [0, 1],
      activeLaneShas: const {0: 'P', 1: 'C', 2: 'X'},
      nextLaneShas: const {0: 'P', 1: 'X'},
      transitions: const [
        (from: 1, to: 0, sha: 'P'),
        (from: 2, to: 1, sha: 'X'),
      ],
    );
    final painter = CommitGraphPainter(
      row: collapse,
      previous: above,
      selected: false,
      committerColor: color,
    );

    // The slide takes the same rounded path as a branch or merge edge.
    expect(
      painter.transitionPath(2, 1, 18, size).getBounds(),
      const Rect.fromLTRB(58, 18, 88, 54),
    );
    // Lane 2 runs down to the center and leaves on that curve.
    expect(painter.laneVerticals(size)[2], (top: 0.0, bottom: 18.0));
    // Lane 1 empties here, so nothing straight below the node either.
    expect(painter.laneVerticals(size)[1], (top: 0.0, bottom: 18.0));

    final below = CommitGraphPainter(
      row: graphRow(
        commit: commit('P', 'main', parents: const ['R']),
        lane: 0,
        activeLanes: const [0, 1],
        nextLanes: const [0, 1],
        activeLaneShas: const {0: 'P', 1: 'X'},
        nextLaneShas: const {0: 'R', 1: 'X'},
      ),
      previous: collapse,
      selected: false,
      committerColor: color,
    );
    // Lane 1's top half belongs to the arriving slide, not to a straight rail.
    expect(below.continuesFromAbove(1), isFalse);
    expect(below.laneVerticals(size)[1], (top: 18.0, bottom: 36.0));
    expect(below.laneVerticals(size)[0], (top: 0.0, bottom: 36.0));
  });

  test('the working tree ring takes its branch line color', () {
    const head = GitIdentity(name: 'Cam Committer', email: 'cam@example.com');
    final wip = graphRow(
      commit: workingTreeCommit('head'),
      lane: 0,
      activeLanes: const [0],
      nextLanes: const [0],
      activeLaneShas: const {0: ''},
      nextLaneShas: const {0: 'head'},
      branch: 3,
      activeLaneBranches: const {0: 3},
      nextLaneBranches: const {0: 3},
    );
    final painter = CommitGraphPainter(
      row: wip,
      selected: true,
      committerColor: AvatarService.branchColor(3),
      committersBySha: {'': head, 'head': head},
    );

    expect(painter.workingTreeRingColor, AvatarService.branchColor(3));
    expect(painter.workingTreeRingColor, isNot(const Color(0xFF15171E)));
    // The fill hides the rail behind the node, so it follows the row color.
    expect(painter.nodeFillColor, const Color(0xFF1F4D8F));
    expect(
      CommitGraphPainter(
        row: wip,
        selected: false,
        committerColor: AvatarService.branchColor(3),
      ).nodeFillColor,
      const Color(0xFF15171E),
    );
    // Without branch ids it degrades to the old committer color.
    expect(
      CommitGraphPainter(
        row: graphRow(
          commit: workingTreeCommit('head'),
          lane: 0,
          activeLanes: const [0],
          nextLanes: const [0],
          nextLaneShas: const {0: 'head'},
        ),
        selected: false,
        committerColor: AvatarService.color(head),
        committersBySha: {'head': head},
      ).workingTreeRingColor,
      AvatarService.color(head),
    );
  });

  testWidgets('merge rows swap the avatar stack for a filled lane dot', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('merge', 'merge commit', parents: const ['main', 'feature']),
            commit('main', 'main commit', parents: const ['base']),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    CommitGraphPainter painterAt(int index) =>
        tester
                .widget<CustomPaint>(find.byKey(Key('graph-painter-$index')))
                .painter!
            as CommitGraphPainter;

    expect(painterAt(0).showsMergeDot, isTrue);
    expect(painterAt(1).showsMergeDot, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const Key('graph-cell-0')),
        matching: find.byType(CommitAvatarStack),
      ),
      findsNothing,
    );
    final stack = tester.widget<CommitAvatarStack>(
      find.descendant(
        of: find.byKey(const Key('graph-cell-1')),
        matching: find.byType(CommitAvatarStack),
      ),
    );
    expect(stack.size, 22);
    expect(stack.discColor, AvatarService.branchColor(painterAt(1).row.branch));
    // Every stack in a row — graph cell and name cell — wears its branch line.
    expect(
      tester
          .widgetList<CommitAvatarStack>(find.byType(CommitAvatarStack))
          .map((stack) => stack.discColor),
      everyElement(isNotNull),
    );
    expect(
      painterAt(0).committerColor,
      AvatarService.branchColor(painterAt(0).row.branch),
    );
  });

  testWidgets('the commit title column flexes until it is dragged', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Default is unset, so the title column takes whatever is left over.
    expect(const TimelineColumnWidths().commit, isNull);
    double titleWidth() =>
        tester.getSize(find.byKey(const Key('commit-header'))).width;
    double nameRight() =>
        tester.getRect(find.byKey(const Key('name-header'))).right;

    // 1400 - 150 sidebar - 288 preview - (156 + 96 + 78 + 116 + 150) fixed.
    expect(titleWidth(), 366);
    expect(nameRight(), lessThanOrEqualTo(1400 - 288));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(titleWidth(), 654);
    expect(nameRight(), lessThanOrEqualTo(1400));

    // Every column stays visible at the default window size with the preview
    // open, which is the whole point of flexing.
    tester.view.physicalSize = const Size(1280, 760);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(titleWidth(), 246);
    expect(nameRight(), lessThanOrEqualTo(1280 - 288));

    // Dragging narrower pins the width: it is saved and stops following the
    // viewport. The drag starts from the width on screen (246).
    await tester.drag(
      find.byKey(const Key('commit-resizer')),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    final pinned = titleWidth();
    expect(pinned, lessThan(246));
    expect(saved?.commit, pinned);

    // A narrow window compresses even a pinned title to the 100px minimum, and
    // widening restores it up to the pinned width — never past it.
    tester.view.physicalSize = const Size(800, 760);
    await tester.pumpAndSettle();
    expect(titleWidth(), 100);
    tester.view.physicalSize = const Size(1400, 760);
    await tester.pumpAndSettle();
    expect(titleWidth(), pinned);
  });

  testWidgets('the six columns fill the timeline viewport with no dead strip', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1538, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    Widget screen(GitRepository repository) => MaterialApp(
      home: TimelineScreen(
        key: ValueKey(repository),
        repository: repository,
        controller: controller,
      ),
    );
    await tester.pumpWidget(
      screen(FakeGitRepository((_, _) async => [commit('1', 'first commit')])),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    Rect viewport() =>
        tester.getRect(find.byKey(const Key('timeline-viewport')));
    double columnWidth(String column) =>
        tester.getSize(find.byKey(Key('$column-header'))).width;

    // 1538 - 150 sidebar - 288 preview.
    expect(viewport().width, 1100);
    expect(columnWidth('graph'), 96);
    expect(columnWidth('commit'), 1100 - (156 + 96 + 78 + 116 + 150));
    expect(
      tester.getRect(find.byKey(const Key('name-header'))).right,
      viewport().right,
    );

    // A deeper graph widens its own column, and the title gives back exactly
    // that much — the right edge stays flush.
    await tester.pumpWidget(
      screen(
        FakeGitRepository(
          (_, _) async => [
            commit('M', 'octopus', parents: const ['a', 'b', 'c']),
            commit('a', 'a'),
            commit('b', 'b'),
            commit('c', 'c'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(columnWidth('graph'), 101);
    expect(columnWidth('commit'), 1100 - (156 + 101 + 78 + 116 + 150));
    expect(
      tester.getRect(find.byKey(const Key('name-header'))).right,
      viewport().right,
    );
  });

  testWidgets('the graph column fits the deepest lane until it is dragged', (
    tester,
  ) async {
    TimelineColumnWidths? saved;
    double graphWidth() =>
        tester.getSize(find.byKey(const Key('graph-header'))).width;

    // Keyed per repository so the second pump reloads instead of reusing state.
    Widget screen(GitRepository repository) => MaterialApp(
      home: TimelineScreen(
        key: ValueKey(repository),
        repository: repository,
        controller: controller,
        onColumnWidthsChanged: (value) => saved = value,
      ),
    );

    // One lane wants 28 + 30, so the 96px minimum wins.
    await tester.pumpWidget(
      screen(FakeGitRepository((_, _) async => [commit('1', 'first commit')])),
    );
    await tester.pumpAndSettle();
    expect(const TimelineColumnWidths().graph, isNull);
    expect(graphWidth(), 96);

    // Three lanes want 28 + 2 * 30 + 13 of content, which clears the minimum.
    await tester.pumpWidget(
      screen(
        FakeGitRepository(
          (_, _) async => [
            commit('M', 'octopus', parents: const ['a', 'b', 'c']),
            commit('a', 'a'),
            commit('b', 'b'),
            commit('c', 'c'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(graphWidth(), 101);

    // Dragging pins it, and the pinned width is what gets saved.
    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    final pinned = graphWidth();
    expect(pinned, greaterThan(101));
    expect(saved?.graph, pinned);
    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    expect(painter.laneX(1) - painter.laneX(0), 30);
  });

  testWidgets('the title column absorbs the window shrink down to 100px', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1250, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    Rect viewport() =>
        tester.getRect(find.byKey(const Key('timeline-viewport')));
    double titleWidth() =>
        tester.getSize(find.byKey(const Key('commit-header'))).width;
    double nameRight() =>
        tester.getRect(find.byKey(const Key('name-header'))).right;

    // 1250 - 150 sidebar, preview closed.
    expect(timelineColumns['commit']!.min, 100);
    expect(viewport().width, 1100);
    expect(titleWidth(), 1100 - 596);
    expect(nameRight(), viewport().right);

    // The title takes the whole 350px shrink; the other five hold their widths.
    tester.view.physicalSize = const Size(900, 800);
    await tester.pumpAndSettle();
    expect(viewport().width, 750);
    expect(titleWidth(), 750 - 596);
    expect(nameRight(), viewport().right);

    // Past the 100px floor the row overflows instead, so the right clips. (The
    // native window stops at 960 wide, so the toolbar never gets narrower.)
    tester.view.physicalSize = const Size(790, 800);
    await tester.pumpAndSettle();
    expect(titleWidth(), 100);
    expect(nameRight(), greaterThan(viewport().right));

    final title = tester.widget<Text>(find.text('first commit'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  test('graph lane spacing compresses in stages', () {
    // Lanes hold their coordinates while the cell still shows the last node,
    // which is all the width the content needs.
    expect(CommitGraphPainter.contentWidth(2), 101);
    expect(CommitGraphPainter.contentWidth(0), 41);
    expect(CommitGraphPainter.spacingFor(260, 2), 30);
    expect(CommitGraphPainter.spacingFor(118, 2), 30);
    expect(CommitGraphPainter.spacingFor(101, 2), 30);
    expect(CommitGraphPainter.spacingFor(58, 0), 30);
    // Below that the lanes squeeze so the last node stays just inside.
    expect(CommitGraphPainter.spacingFor(100, 2), 29.5);
    expect(CommitGraphPainter.spacingFor(70, 2), 14.5);
    expect(CommitGraphPainter.spacingFor(40, 2), 12);
    expect(CommitGraphPainter.compactWidth, 56);
    expect(timelineColumns['graph']!.min, 40);
  });

  testWidgets('a narrow graph column compresses lanes, then collapses them', (
    tester,
  ) async {
    Widget screen(double graph) => MaterialApp(
      home: TimelineScreen(
        key: ValueKey(graph),
        repository: FakeGitRepository(
          (_, _) async => [
            commit('M', 'octopus', parents: const ['a', 'b', 'c']),
            commit('a', 'a'),
            commit('b', 'b'),
            commit('c', 'c'),
          ],
        ),
        controller: controller,
        columnWidths: TimelineColumnWidths(graph: graph),
      ),
    );
    CommitGraphPainter painterAt(int index) =>
        tester
                .widget<CustomPaint>(find.byKey(Key('graph-painter-$index')))
                .painter!
            as CommitGraphPainter;
    double avatarSize(int index) => tester
        .widget<CommitAvatarStack>(
          find.descendant(
            of: find.byKey(Key('graph-cell-$index')),
            matching: find.byType(CommitAvatarStack),
          ),
        )
        .size;

    // Stage 1: 118px is wider than the 101px content, so nothing moves.
    await tester.pumpWidget(screen(118));
    await tester.pumpAndSettle();
    expect(painterAt(0).compact, isFalse);
    expect(painterAt(0).laneSpacing, 30);
    expect(painterAt(1).laneX(1) - painterAt(1).laneX(0), 30);
    expect(avatarSize(1), 22);

    // Stage 2: the lanes squeeze together and the node avatar shrinks with them.
    await tester.pumpWidget(screen(70));
    await tester.pumpAndSettle();
    expect(painterAt(0).compact, isFalse);
    expect(painterAt(0).laneSpacing, 14.5);
    expect(painterAt(1).laneX(0), CommitGraphPainter.laneInset);
    expect(painterAt(1).laneX(1) - painterAt(1).laneX(0), 14.5);
    expect(
      painterAt(0).transitionPath(0, 2, 18, const Size(70, 36)).getBounds(),
      const Rect.fromLTRB(28, 18, 57, 54),
    );
    // Nodes keep their full size at every width; the overhang just clips.
    expect(avatarSize(1), 22);

    // Stage 3: every lane collapses onto the inset and the curves are dropped.
    await tester.pumpWidget(screen(56));
    await tester.pumpAndSettle();
    final compact = painterAt(0);
    expect(compact.compact, isTrue);
    expect(compact.laneX(2), CommitGraphPainter.laneInset);
    expect(compact.laneX(2), compact.laneX(0));
    expect(compact.row.transitions, isNotEmpty);
    // The octopus row hands rails down, so its single rail runs to the edge.
    expect(compact.compactRail(const Size(56, 36)), (top: 18.0, bottom: 36.0));
    // The last row ends the history, so its rail stops at the node.
    expect(painterAt(3).compactRail(const Size(56, 36)), (
      top: 0.0,
      bottom: 18.0,
    ));
    expect(avatarSize(1), 22);
  });

  testWidgets('column resizers move by 8px on arrow keys and clamp', (
    tester,
  ) async {
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final node = tester
        .widget<Focus>(find.byKey(const Key('time-resizer-focus')))
        .focusNode!;
    node.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(saved?.time, 124);
    expect(tester.getSize(find.byKey(const Key('time-header'))).width, 124);

    for (var press = 0; press < 3; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }
    expect(saved?.time, 112);
    expect(saved?.name, 150);
  });

  testWidgets('sidebar lists refs, filters them, and moves the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('1', 'first commit'),
            commit(
              '2',
              'second commit',
              refs: const [GitRef(name: 'feature/timeline')],
            ),
          ],
          refs: const RepoRefs(
            local: ['main', 'feature/timeline'],
            remote: ['origin/main'],
            tags: ['v0.1.0'],
            current: 'main',
          ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    for (final heading in ['LOCAL', 'REMOTE', 'TAGS']) {
      expect(find.text(heading), findsOneWidget);
    }
    // The checked-out branch leads LOCAL.
    expect(
      tester.getTopLeft(find.byKey(const Key('sidebar-ref-main'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('sidebar-ref-feature/timeline')))
            .dy,
      ),
    );
    expect(find.text('origin/main'), findsOneWidget);
    expect(find.text('v0.1.0'), findsOneWidget);

    final current = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('sidebar-ref-main')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (current.decoration! as BoxDecoration).color,
      const Color(0xFF263246),
    );

    await tester.enterText(find.byKey(const Key('ref-filter')), 'feature');
    await tester.pump();
    expect(find.byKey(const Key('sidebar-ref-main')), findsNothing);
    expect(find.byKey(const Key('sidebar-ref-origin/main')), findsNothing);
    expect(
      find.byKey(const Key('sidebar-ref-feature/timeline')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('sidebar-ref-feature/timeline')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-2')), findsOneWidget);
  });

  testWidgets('selected row tints its ref chip and marks HEAD and tags', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('3', 'head commit'),
            commit(
              'tagged',
              'tagged commit',
              refs: const [GitRef(name: 'v1.0', isTag: true)],
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final chip = tester.widget<Container>(
      find.byKey(const Key('ref-chip-3-main')),
    );
    expect((chip.decoration! as BoxDecoration).color, const Color(0xFF2B4E86));
    final tag = tester.widget<Container>(
      find.byKey(const Key('ref-chip-tagged-v1.0')),
    );
    expect(
      (tag.decoration! as BoxDecoration).color,
      isNot(const Color(0xFF2B4E86)),
    );
    expect(find.text('✓'), findsOneWidget);
    expect(find.text('◇'), findsOneWidget);
  });

  testWidgets('preview describes the working tree row and counts files', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          workingTree: () async => workingTreeCommit('1'),
          files: (_, _) async => const [
            GitFileChange(
              path: 'lib/a.dart',
              status: 'M',
              additions: 3,
              deletions: 1,
            ),
            GitFileChange(
              path: 'lib/b.dart',
              status: 'A',
              additions: 5,
              deletions: 0,
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // The status bar legend carries the other 'WIP' label.
    expect(
      find.descendant(
        of: find.byKey(const Key('preview-panel')),
        matching: find.text('WIP'),
      ),
      findsOneWidget,
    );
    expect(find.text('Working tree changes'), findsOneWidget);
    expect(find.text('Not committed'), findsOneWidget);
    expect(find.text('No commit object or committer'), findsOneWidget);
    expect(find.text('2 files changed'), findsOneWidget);
    expect(find.text('+8'), findsOneWidget);
    expect(find.text('−1'), findsOneWidget);

    Color? chip(String path) =>
        (tester
                    .widget<Container>(find.byKey(Key('preview-state-$path')))
                    .decoration!
                as BoxDecoration)
            .color;
    expect(chip('lib/a.dart'), const Color(0xFF263246));
    expect(chip('lib/b.dart'), const Color(0xFF8AD6A1).withValues(alpha: 0.2));
    expect(
      fileStateChipColor('D').background,
      const Color(0xFFF29AB2).withValues(alpha: 0.2),
    );
    expect(fileStateChipColor('R100').letter, const Color(0xFFB6A0EA));
  });

  testWidgets('the preview diff starts at the hunk, not the git header', (
    tester,
  ) async {
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
          ],
          diff: (_, _, _, _) async => const [
            DiffLine(kind: DiffLineKind.header, text: 'diff --git a/x b/x'),
            DiffLine(kind: DiffLineKind.header, text: 'index 1234567..89abcde'),
            DiffLine(kind: DiffLineKind.header, text: '--- a/lib/a.dart'),
            DiffLine(kind: DiffLineKind.header, text: '+++ b/lib/a.dart'),
            DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
            DiffLine(kind: DiffLineKind.delete, text: 'old line', oldNumber: 1),
            DiffLine(kind: DiffLineKind.add, text: 'new line', newNumber: 1),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // 'N file changed' is singular for one file.
    expect(find.text('1 file changed'), findsOneWidget);
    expect(find.text('1 files changed'), findsNothing);

    final diff = find.byKey(const Key('preview-diff'));
    expect(
      find.descendant(of: diff, matching: find.text('@@ -1 +1 @@')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: diff, matching: find.text('-old line')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: diff, matching: find.text('+new line')),
      findsOneWidget,
    );
    for (final header in [
      'diff --git a/x b/x',
      'index 1234567..89abcde',
      '--- a/lib/a.dart',
      '+++ b/lib/a.dart',
    ]) {
      expect(find.textContaining(header), findsNothing);
    }
  });

  testWidgets('an open preview follows the keyboard selection', (tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('1', 'first commit'),
            commit('2', 'second commit'),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final preview = find.byKey(const Key('preview-panel'));
    expect(
      find.descendant(of: preview, matching: find.text('first commit')),
      findsOneWidget,
    );
    // The person block grew with every other avatar.
    expect(
      tester
          .widgetList<IdentityAvatar>(
            find.descendant(of: preview, matching: find.byType(IdentityAvatar)),
          )
          .map((avatar) => avatar.size),
      contains(42.0),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: preview, matching: find.text('second commit')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.text('first commit')),
      findsNothing,
    );
  });

  test('lane colors round-trip, and a damaged palette falls back', () {
    expect(AvatarService.defaultColors, hasLength(8));
    expect(AvatarService.defaultColors.first, const Color(0xFFFF2D95));
    expect(AvatarService.defaultColors.last, const Color(0xFFFF3131));
    expect(AppSettings.defaultLaneColors.first, '#FF2D95');
    expect(parseHexColor('#39C5CF'), const Color(0xFF39C5CF));
    expect(parseHexColor('39c5cf'), const Color(0xFF39C5CF));
    expect(parseHexColor('#39C5C'), isNull);
    expect(parseHexColor('teal'), isNull);

    const custom = AppSettings(laneColors: ['#112233', '#445566']);
    final decoded = AppSettings.fromJson(custom.toJson());
    expect(decoded, custom);
    expect(decoded.laneColorValues, const [
      Color(0xFF112233),
      Color(0xFF445566),
    ]);

    // One bad entry drops the whole palette back to GitHub dark.
    for (final stored in [
      <String>['#112233', 'oops'],
      <String>[],
      'red',
    ]) {
      expect(
        AppSettings.fromJson(<String, dynamic>{
          'laneColors': stored,
        }).laneColors,
        AppSettings.defaultLaneColors,
        reason: '$stored',
      );
    }
    expect(
      const AppSettings(laneColors: ['bad']).laneColorValues,
      AvatarService.defaultColors,
    );

    // A settings file still carrying the previous default never chose it, so it
    // migrates to the new one — case does not matter.
    expect(
      AppSettings.fromJson(<String, dynamic>{
        'laneColors': [
          '#f85149',
          '#db6d28',
          '#d29922',
          '#3fb950',
          '#39c5cf',
          '#58a6ff',
          '#bc8cff',
          '#f778ba',
        ],
      }).laneColors,
      AppSettings.defaultLaneColors,
    );
    // An edited palette is preserved, even when it reuses an old color.
    expect(
      AppSettings.fromJson(<String, dynamic>{
        'laneColors': ['#F85149', '#00FF00'],
      }).laneColors,
      ['#F85149', '#00FF00'],
    );
    expect(
      AppSettings.fromJson(<String, dynamic>{}).laneColors,
      AppSettings.defaultLaneColors,
    );
  });

  testWidgets('the initials avatar is a filled disc with contrasting ink', (
    tester,
  ) async {
    const ada = GitIdentity(name: 'Ada Lovelace', email: 'ada@example.com');
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: IdentityAvatar(identity: ada)),
      ),
    );

    final fill =
        tester.widget<Container>(find.byType(Container)).decoration!
            as BoxDecoration;
    // Opaque identity color, no transparent center, and no outline at all.
    expect(fill.color, AvatarService.color(ada));
    expect(fill.color!.a, 1.0);
    expect(fill.border, isNull);
    expect(tester.widget<IdentityAvatar>(find.byType(IdentityAvatar)).size, 22);

    // In a row the disc wears the branch line instead, ink following suit.
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: IdentityAvatar(
            identity: ada,
            discColor: AvatarService.branchColor(2),
          ),
        ),
      ),
    );
    final branchFill =
        tester.widget<Container>(find.byType(Container)).decoration!
            as BoxDecoration;
    expect(branchFill.color, AvatarService.branchColor(2));
    expect(
      tester.widget<Text>(find.text('AL')).style?.color,
      AvatarService.onColor(AvatarService.branchColor(2)),
    );
    expect(
      tester.widget<Text>(find.text('AL')).style?.color,
      AvatarService.onColor(AvatarService.color(ada)),
    );
    expect(AvatarService.onColor(const Color(0xFFD29922)), isNot(Colors.white));
    expect(AvatarService.onColor(const Color(0xFF1D2029)), Colors.white);
  });

  test('the committer color follows the active palette', () {
    const ada = GitIdentity(name: 'Ada', email: 'ada@example.com');
    addTearDown(() => AvatarService.palette = AvatarService.defaultColors);

    expect(AvatarService.defaultColors, contains(AvatarService.color(ada)));
    AvatarService.palette = const [Color(0xFF010203)];
    expect(AvatarService.color(ada), const Color(0xFF010203));
    // An empty palette is never painted with.
    AvatarService.palette = const [];
    expect(AvatarService.defaultColors, contains(AvatarService.color(ada)));
  });

  testWidgets('the timeline colors editor applies hex edits and resets', (
    tester,
  ) async {
    final saved = <AppSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: const AppSettings(),
          onChanged: saved.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Color swatch(int index) =>
        (tester
                    .widget<Container>(find.byKey(Key('lane-swatch-$index')))
                    .decoration!
                as BoxDecoration)
            .color!;

    expect(find.text('Timeline colors'), findsOneWidget);
    expect(find.byKey(const Key('lane-swatch-7')), findsOneWidget);
    expect(swatch(0), const Color(0xFFFF2D95));
    // The mainline swatch is the fixed green and is not editable.
    expect(
      (tester
                  .widget<Container>(find.byKey(const Key('lane-swatch-main')))
                  .decoration!
              as BoxDecoration)
          .color,
      AvatarService.mainBranchColor,
    );
    expect(find.byKey(const Key('lane-color-main')), findsNothing);
    // No row context in the preview, so those avatars stay identity-colored.
    expect(
      tester
          .widgetList<IdentityAvatar>(find.byType(IdentityAvatar))
          .map((avatar) => avatar.discColor),
      everyElement(isNull),
    );

    await tester.enterText(find.byKey(const Key('lane-color-0')), '#123456');
    await tester.pumpAndSettle();
    expect(saved.last.laneColors.first, '#123456');
    expect(swatch(0), const Color(0xFF123456));

    // A half-typed hex leaves the last good color in place.
    await tester.enterText(find.byKey(const Key('lane-color-0')), '#12');
    await tester.pumpAndSettle();
    expect(saved.last.laneColors.first, '#123456');

    await tester.ensureVisible(find.byKey(const Key('reset-lane-colors')));
    await tester.tap(find.byKey(const Key('reset-lane-colors')));
    await tester.pumpAndSettle();
    expect(saved.last.laneColors, AppSettings.defaultLaneColors);
    expect(swatch(0), const Color(0xFFFF2D95));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('lane-color-0')))
          .controller
          ?.text,
      '#FF2D95',
    );
  });

  testWidgets('a stored palette reaches the timeline rails', (tester) async {
    addTearDown(() => AvatarService.palette = AvatarService.defaultColors);
    final store = MemorySettingsStore()
      ..current = const AppSettings(laneColors: ['#0B7285']);
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
        ),
        settingsStore: store,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(AvatarService.palette, const [Color(0xFF0B7285)]);
    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    // Main is the fixed green; the stored palette is only the fallback now.
    expect(painter.row.branch, 0);
    expect(painter.committerColor, const Color(0xFF5CB270));
    expect(AvatarService.palette, const [Color(0xFF0B7285)]);
  });

  test('social time spells out the elapsed distance', () {
    expect(socialTimeLabel(const Duration(seconds: 30)), 'just now');
    expect(socialTimeLabel(const Duration(minutes: 1)), '1 minute ago');
    expect(socialTimeLabel(const Duration(minutes: 59)), '59 minutes ago');
    expect(socialTimeLabel(const Duration(hours: 1)), '1 hour ago');
    expect(socialTimeLabel(const Duration(hours: 23)), '23 hours ago');
    expect(socialTimeLabel(const Duration(days: 1)), 'yesterday');
    expect(socialTimeLabel(const Duration(days: 2)), '2 days ago');
    expect(socialTimeLabel(const Duration(days: 29)), '29 days ago');
    expect(socialTimeLabel(const Duration(days: 30)), '1 month ago');
    expect(socialTimeLabel(const Duration(days: 364)), '12 months ago');
    expect(socialTimeLabel(const Duration(days: 365)), '1 year ago');
    expect(socialTimeLabel(const Duration(days: 800)), '2 years ago');
  });

  test(
    'column widths round-trip time and name and clamp to the design range',
    () {
      const widths = TimelineColumnWidths(time: 130, name: 120, commit: 500);
      final decoded = TimelineColumnWidths.fromJson(widths.toJson());
      expect(decoded, widths);
      expect(decoded.time, 130);
      expect(decoded.name, 120);
      expect(decoded.commit, 500);
      expect(const TimelineColumnWidths().refs, 156);
      expect(const TimelineColumnWidths().hash, 78);

      // An unset graph or title width is omitted and comes back unset, so both
      // columns keep sizing themselves across restarts.
      const flexing = TimelineColumnWidths();
      expect(flexing.commit, isNull);
      expect(flexing.graph, isNull);
      expect(flexing.toJson().containsKey('commit'), isFalse);
      expect(flexing.toJson().containsKey('graph'), isFalse);
      expect(TimelineColumnWidths.fromJson(flexing.toJson()).commit, isNull);
      expect(TimelineColumnWidths.fromJson(flexing.toJson()).graph, isNull);
      expect(
        TimelineColumnWidths.fromJson(<String, dynamic>{
          'commit': 'wide',
          'graph': 'wide',
        }).graph,
        isNull,
      );
      expect(
        TimelineColumnWidths.fromJson(
          const TimelineColumnWidths(graph: 180).toJson(),
        ).graph,
        180,
      );

      final clamped = TimelineColumnWidths.fromJson(<String, dynamic>{
        'time': 400,
        'name': 10,
        'refs': 999,
        'commit': 4000,
        'graph': 10,
      });
      expect(clamped.time, 170);
      expect(clamped.name, 100);
      expect(clamped.refs, 240);
      expect(clamped.commit, 620);
      expect(clamped.graph, 40);
    },
  );

  testWidgets('uncommitted changes lead the timeline as a working tree row', (
    tester,
  ) async {
    final skips = <int>[];
    await tester.pumpWidget(
      app(
        FakeGitRepository((skip, _) async {
          skips.add(skip);
          return skip == 0 ? [commit('1', 'first commit')] : [];
        }, workingTree: () async => workingTreeCommit('1')),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Timeline row plus the opened preview title.
    expect(find.text('Uncommitted changes'), findsNWidgets(2));
    expect(find.text('working tree'), findsOneWidget);
    // No date group above the working tree row: it belongs to no day.
    expect(
      tester.getRect(find.byKey(const Key('date-row-1'))).top,
      greaterThan(tester.getRect(find.text('working tree')).top),
    );
    expect(find.text('·······'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(skips, [0]);

    final hash = tester.widget<Text>(find.text('1'));
    expect(hash.style?.color, const Color(0xFFEF6C63));

    final wipRow =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    expect(wipRow.row.commit.isWorkingTree, isTrue);
    expect(wipRow.showsMergeDot, isFalse);
    expect(CommitGraphPainter.wipNodeRadius, 8);
    expect(CommitGraphPainter.wipNodeDash, 2.5);
    expect(
      find.descendant(
        of: find.byKey(const Key('graph-cell-0')),
        matching: find.byType(CommitAvatarStack),
      ),
      findsNothing,
    );
  });

  testWidgets('left preview keeps the panel ahead of the timeline', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('좌측'));
    await tester.pumpAndSettle();

    expect(controller.previewPlacement, PreviewPlacement.left);
    final leftLayout = find.byKey(const Key('preview-layout-left'));
    expect(leftLayout, findsOneWidget);
    expect(tester.widget(leftLayout), isA<Row>());
    expect(
      tester.getTopLeft(find.byKey(const Key('preview-panel'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('timeline-viewport'))).dx,
      ),
    );
  });

  testWidgets('a multi-ref row shares its cell between chips, no avatars', (
    tester,
  ) async {
    const refs = [
      GitRef(name: 'v1.0', isTag: true),
      GitRef(name: 'origin/main'),
      GitRef(name: 'main', isHead: true),
    ];
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('multi', 'multi ref commit', refs: refs),
            commit('plain', 'plain commit', refs: const []),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // Every ref that fits gets an equal share of the cell; no badge at all.
    final cell = tester.getRect(find.byKey(const Key('refs-cell-0')));
    final chip = tester.getRect(find.byKey(const Key('ref-chip-multi-v1.0')));
    for (final ref in refs) {
      expect(find.byKey(Key('ref-chip-multi-${ref.name}')), findsOneWidget);
    }
    expect(find.byKey(const Key('ref-more-multi')), findsNothing);
    expect(chip.left, greaterThanOrEqualTo(cell.left));
    expect(
      tester.getRect(find.byKey(const Key('ref-chip-multi-main'))).right,
      lessThanOrEqualTo(cell.right),
    );

    // Chips carry no avatars at all any more, and the cell has no hairline.
    expect(
      find.descendant(
        of: find.byKey(const Key('refs-cell-0')),
        matching: find.byType(IdentityAvatar),
      ),
      findsNothing,
    );
    // Nothing in this cell paints the row hairline any more; the rules start at
    // the hash column.
    expect(
      tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(const Key('refs-cell-0')),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration).border)
          .whereType<Border>()
          .map((border) => border.bottom.color),
      everyElement(isNot(const Color(0xFF343946))),
    );
    // The remaining run to the node is the graph cell's own connector.
    expect(
      tester.getRect(find.byKey(const Key('graph-cell-0'))).left,
      cell.right,
    );
  });

  testWidgets('the selected multi-ref row lists its refs in a floating modal', (
    tester,
  ) async {
    const refs = [
      GitRef(name: 'v1.0', isTag: true),
      GitRef(name: 'origin/main'),
      GitRef(name: 'main', isHead: true),
    ];
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            for (var index = 0; index < 10; index++)
              commit(
                '$index',
                'commit $index',
                // Row 5 sits with room on both sides of it.
                refs: index == 5 ? refs : const [],
              ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    final modal = find.byKey(const Key('refs-modal'));
    expect(modal, findsNothing);

    // Arriving from above puts the box over the row, clear of it.
    for (var press = 0; press < 5; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(modal, findsOneWidget);
    for (final ref in refs) {
      expect(
        find.descendant(of: modal, matching: find.text(ref.name)),
        findsOneWidget,
      );
    }
    final row = tester.getRect(find.byKey(const Key('refs-cell-5')));
    expect(tester.getRect(modal).bottom, lessThanOrEqualTo(row.top));

    // Arriving from below flips it under the row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(modal, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(tester.getRect(modal).top, greaterThanOrEqualTo(row.bottom));

    // Leaving the row hides it again.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(modal, findsNothing);
  });

  testWidgets('avatar lookup is limited to rows in the short viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 180);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final requested = <int>[];
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory}) async {
        requested.add(int.parse(arguments.last.split('/').last));
        return ProcessResult(1, 1, '', 'offline');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => List.generate(
              100,
              (index) => commit('$index', 'commit $index'),
            ),
          ),
          controller: controller,
          avatarService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, isNotEmpty);
    expect(requested, everyElement(lessThan(12)));
  });

  testWidgets('paging keeps one request in flight and shows end state', (
    tester,
  ) async {
    final secondPage = Completer<List<GitCommit>>();
    var calls = 0;
    final repository = FakeGitRepository((skip, limit) {
      calls++;
      if (skip == 0) {
        return Future.value(
          List.generate(500, (index) => commit('$index', 'commit $index')),
        );
      }
      return secondPage.future;
    });

    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    await tester.drag(
      // Dragged by viewport: the list is wider than the visible columns.
      find.byKey(const Key('timeline-viewport')),
      const Offset(0, -20000),
    );
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(find.text('Loading more…'), findsOneWidget);

    secondPage.complete([commit('500', 'last commit')]);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('End of history'), findsOneWidget);
  });

  testWidgets('paging starts at twelve remaining rows, not thirteen', (
    tester,
  ) async {
    final nextPage = Completer<List<GitCommit>>();
    var calls = 0;
    final repository = FakeGitRepository((skip, limit) {
      calls++;
      if (skip == 0) {
        return Future.value(
          List.generate(500, (index) => commit('$index', 'commit $index')),
        );
      }
      return nextPage.future;
    });
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.byType(Scrollable),
      ),
    );

    scrollable.position.jumpTo(scrollable.position.maxScrollExtent - 13 * 36);
    await tester.pump();
    expect(calls, 1);

    scrollable.position.jumpTo(scrollable.position.maxScrollExtent - 12 * 36);
    await tester.pump();
    expect(calls, 2);

    nextPage.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('paging error retries the same page', (tester) async {
    var calls = 0;
    final repository = FakeGitRepository((skip, limit) async {
      calls++;
      if (calls == 1) throw StateError('temporary failure');
      return [commit('1', 'recovered commit')];
    });

    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    expect(find.text('Could not load history'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // Timeline row plus the opened preview title.
    expect(find.text('recovered commit'), findsNWidgets(2));
    expect(find.text('End of history'), findsOneWidget);
  });

  testWidgets('opens the full diff and preserves timeline state on escape', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final histogram = Completer<List<DiffLine>>();
    final calls =
        <
          ({String sha, String? parent, String path, DiffAlgorithm algorithm})
        >[];
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('merge', 'merge commit', parents: const ['main', 'feature']),
        commit('main', 'main commit', parents: const ['base']),
        commit('feature', 'feature commit', parents: const ['base']),
      ],
      files: (commit, parent) async => [
        const GitFileChange(
          path: 'lib/a.dart',
          status: 'M',
          additions: 2,
          deletions: 1,
        ),
        const GitFileChange(
          path: 'lib/b.dart',
          status: 'A',
          additions: 1,
          deletions: 0,
        ),
      ],
      diff: (commit, parent, path, algorithm) {
        calls.add((
          sha: commit.sha,
          parent: parent,
          path: path,
          algorithm: algorithm,
        ));
        if (algorithm == DiffAlgorithm.histogram) return histogram.future;
        return Future.value([
          const DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
          const DiffLine(
            kind: DiffLineKind.delete,
            text: 'old line',
            oldNumber: 1,
          ),
          const DiffLine(
            kind: DiffLineKind.add,
            text: 'new line',
            newNumber: 1,
          ),
        ]);
      },
    );
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open full diff'));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('nearby-column'))).width, 210);
    expect(
      tester.getSize(find.byKey(const Key('details-files-column'))).width,
      290,
    );
    expect(find.byKey(const Key('nearby-commits-list')), findsOneWidget);
    expect(find.byKey(const Key('changed-files-list')), findsOneWidget);
    expect(find.byKey(const Key('unified-diff-list')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('changed-files-list'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('unified-diff-list'))).dx,
      ),
    );
    expect(find.byKey(const Key('merge-parent-chooser')), findsOneWidget);

    await tester.tap(find.text('main commit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-nearby-main')), findsOneWidget);
    expect(find.byKey(const Key('merge-parent-chooser')), findsNothing);
    await tester.tap(find.text('merge commit'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('lib/b.dart'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-file-lib/b.dart')), findsOneWidget);
    final beforeModeSwitch = calls.length;
    await tester.tap(find.text('Side-by-side'));
    await tester.pump();
    expect(find.byKey(const Key('side-by-side-diff-list')), findsOneWidget);
    expect(calls, hasLength(beforeModeSwitch));
    expect(find.byKey(const Key('selected-file-lib/b.dart')), findsOneWidget);

    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((tooltip) => tooltip.message)
          .whereType<String>(),
      containsAll(DiffAlgorithm.values.map((algorithm) => algorithm.tooltip)),
    );
    await tester.tap(find.text('Histogram').last);
    await tester.pump();
    expect(find.text('old line'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Algorithm: Git setting (no option)'), findsOneWidget);
    expect(find.byKey(const Key('selected-file-lib/b.dart')), findsOneWidget);

    histogram.complete([
      const DiffLine(
        kind: DiffLineKind.add,
        text: 'histogram line',
        newNumber: 1,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('histogram line'), findsOneWidget);
    expect(find.text('Algorithm: --diff-algorithm=histogram'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-merge')), findsOneWidget);
    expect(find.text('Commit & Diff'), findsOneWidget);
  });

  testWidgets('failed algorithm keeps the displayed algorithm and lines', (
    tester,
  ) async {
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('1', 'commit', parents: const ['0']),
      ],
      files: (_, _) async => [
        const GitFileChange(
          path: 'file.txt',
          status: 'M',
          additions: 1,
          deletions: 1,
        ),
      ],
      diff: (_, _, _, algorithm) => algorithm == DiffAlgorithm.minimal
          ? Future.error(StateError('minimal failed'))
          : Future.value([
              const DiffLine(
                kind: DiffLineKind.context,
                text: 'displayed line',
                oldNumber: 1,
                newNumber: 1,
              ),
            ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [
            commit('1', 'commit', parents: const ['0']),
          ],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('diff-algorithm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimal').last);
    await tester.pumpAndSettle();

    expect(find.text('displayed line'), findsOneWidget);
    expect(find.text('Algorithm: Git setting (no option)'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<DiffAlgorithm>>(
            find.byKey(const Key('diff-algorithm')),
          )
          .value,
      DiffAlgorithm.gitSetting,
    );
  });

  testWidgets('algorithm tooltip opens when the control receives focus', (
    tester,
  ) async {
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester
        .widget<Focus>(find.byKey(const Key('diff-algorithm-focus')))
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();

    expect(find.text(DiffAlgorithm.gitSetting.tooltip), findsOneWidget);
  });

  testWidgets('side-by-side diff marks additions and deletions', (
    tester,
  ) async {
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'commit')],
      files: (_, _) async => [
        const GitFileChange(
          path: 'file.txt',
          status: 'M',
          additions: 1,
          deletions: 1,
        ),
      ],
      diff: (_, _, _, _) async => [
        const DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
        const DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiffScreen(
          repository: repository,
          commits: [commit('1', 'commit')],
          initialIndex: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Side-by-side'));
    await tester.pump();
    final diff = find.byKey(const Key('side-by-side-diff-list'));

    expect(find.descendant(of: diff, matching: find.text('-')), findsOneWidget);
    expect(find.descendant(of: diff, matching: find.text('+')), findsOneWidget);
  });

  test(
    'the folder picker returns the native path, or null with no plugin',
    () async {
      final calls = <String>[];
      const picker = MethodChannel('test/yogit-picker');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, (call) async {
            calls.add(call.method);
            return '/Users/ada/repo';
          });

      expect(
        await WindowFrameController(channel: picker).pickRepository(),
        '/Users/ada/repo',
      );
      expect(calls, ['pickRepository']);
      // No native side, so the timeline keeps the repository it has.
      expect(
        await WindowFrameController(
          channel: const MethodChannel('test/yogit-no-plugin'),
        ).pickRepository(),
        isNull,
      );
    },
  );

  testWidgets('the folder button opens a picked repository, or says why not', (
    tester,
  ) async {
    final picks = <String>['/Users/ada/next', '/Users/ada/plain'];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('test/yogit-window'),
          (call) async =>
              call.method == 'pickRepository' ? picks.removeAt(0) : null,
        );
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) async => arguments.contains('/Users/ada/next')
        ? ProcessResult(1, 0, '/Users/ada/next\n', '')
        : ProcessResult(1, 128, '', 'not a git repository');

    final opened = <String>[];
    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          root: '/Users/ada/first',
          runner: runner,
        ),
        settingsStore: MemorySettingsStore(),
        discoverAvatars: false,
        windowFrameController: controller,
        repositoryFactory: (root) {
          opened.add(root);
          return FakeGitRepository(
            (_, _) async => [commit('2', 'next repo commit')],
            root: root,
            runner: runner,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('/Users/ada/first'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pick-repository')));
    await tester.pumpAndSettle();

    expect(opened, ['/Users/ada/next']);
    expect(find.text('/Users/ada/next'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // Timeline row plus the preview title, and the old history is gone.
    expect(find.text('next repo commit'), findsNWidgets(2));
    expect(find.text('first commit'), findsNothing);

    // A plain directory is reported inline and changes nothing.
    await tester.tap(find.byKey(const Key('pick-repository')));
    await tester.pumpAndSettle();
    expect(find.text('Git 저장소가 아닙니다: /Users/ada/plain'), findsOneWidget);
    expect(opened, ['/Users/ada/next']);
    expect(find.text('/Users/ada/next'), findsOneWidget);
    expect(find.text('next repo commit'), findsNWidgets(2));

    // Let the notice expire so its timer does not outlive the test.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  test('native close clamps the saved frame to a current visible screen', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    // The folder picker rides the same channel as the frame calls.
    for (final line in [
      'case "pickRepository":',
      'panel.canChooseDirectories = true',
      'panel.canChooseFiles = false',
      'panel.allowsMultipleSelection = false',
      'panel.prompt = "Open"',
      'return panel.runModal() == .OK ? panel.url?.path : nil',
    ]) {
      expect(source, contains(line));
    }
    expect(
      source,
      contains(
        'setFrame(clamped(baseFrame, to: visibleFrame), display: true, animate: true)',
      ),
    );
    expect(
      source,
      contains(
        'private func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect',
      ),
    );
    expect(source, isNot(contains('baseFrame.intersection(visibleFrame)')));
  });

  test('settings persist only the supported fields', () async {
    final directory = await Directory.systemTemp.createTemp('yogit_settings_');
    addTearDown(() => directory.delete(recursive: true));
    final store = SettingsStore(File('${directory.path}/nested/settings.json'));

    expect(await store.load(), const AppSettings());
    const saved = AppSettings(
      showAvatars: false,
      previewPlacement: PreviewPlacement.bottom,
      columnWidths: TimelineColumnWidths(graph: 220),
    );
    await store.save(saved);

    expect(await store.load(), saved);
    final json = await store.file.readAsString();
    expect(json, contains('"showAvatars":false'));
    expect(json, isNot(contains('token')));

    await store.save(
      const AppSettings(previewPlacement: PreviewPlacement.left),
    );
    expect((await store.load()).previewPlacement, PreviewPlacement.left);
  });

  test('repository argument and executable lookup avoid a shell', () async {
    final directory = await Directory.systemTemp.createTemp('yogit_exec_');
    addTearDown(() => directory.delete(recursive: true));
    final executable = File('${directory.path}/git');
    await executable.writeAsString('');

    expect(repositoryPathFromArgs(['--repo', '/tmp/project']), '/tmp/project');
    expect(
      () => repositoryPathFromArgs(['--repo']),
      throwsA(isA<FormatException>()),
    );
    expect(
      resolveExecutable(
        'git',
        environment: {'PATH': directory.path},
        exists: (path) => path == executable.path,
      ),
      executable.path,
    );
    final launch = launchOptionsFromArgs([
      '--repo',
      '/tmp/project',
      '--git',
      '/usr/bin/git',
      '--gh',
      '/usr/bin/true',
    ]);
    expect(launch.repositoryPath, '/tmp/project');
    expect(launch.gitExecutable, '/usr/bin/git');
    expect(launch.ghExecutable, '/usr/bin/true');
    expect(
      () => launchOptionsFromArgs(['--git', 'git']),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => launchOptionsFromArgs(['--git', '/does/not/exist/git']),
      throwsA(isA<FormatException>()),
    );

    final calls = <List<String>>[];
    final root = await resolveRepositoryRoot(
      '/tmp/project',
      gitExecutable: executable.path,
      runner: (command, arguments, {workingDirectory}) async {
        calls.add(arguments);
        return ProcessResult(1, 0, '/tmp/project\n', '');
      },
    );
    expect(root, '/tmp/project');
    expect(calls.single, [
      '-C',
      '/tmp/project',
      'rev-parse',
      '--show-toplevel',
    ]);

    await expectLater(
      resolveRepositoryRoot(
        '/tmp/not-a-repository',
        runner: (command, arguments, {workingDirectory}) async =>
            ProcessResult(1, 128, '', 'not a git repository'),
      ),
      throwsA(isA<GitRepositoryException>()),
    );
  });

  test('yo launcher builds once and passes the resolved repository path', () {
    final file = File('bin/yo');
    final source = file.readAsStringSync();

    expect(FileStat.statSync(file.path).mode & 0x40, isNot(0));
    expect(source, contains(r'git_bin=$(command -v git)'));
    expect(source, contains('flutter build macos'));
    expect(source, contains(r'set -- --repo "$root" --git "$git_bin"'));
    expect(source, contains(r'set -- "$@" --gh "$gh_bin"'));
    expect(source, contains('/usr/bin/open'));
    expect(source, contains(r'-n "$app" --args "$@"'));
    expect(File('README.md').readAsStringSync(), contains('Flutter 3.41.8'));
  });

  test('parses GitHub and GHE remotes without accepting non-network URLs', () {
    expect(
      RemoteRepository.tryParse('git@github.com:example/project.git'),
      const RemoteRepository(
        host: 'github.com',
        owner: 'example',
        repository: 'project',
      ),
    );
    expect(
      RemoteRepository.tryParse('https://git.example.com/team/yogit.git'),
      const RemoteRepository(
        host: 'git.example.com',
        owner: 'team',
        repository: 'yogit',
      ),
    );
    expect(RemoteRepository.tryParse('/tmp/local.git'), isNull);
  });

  test('avatar lookup uses gh once per SHA and never requests Gravatar', () async {
    final requests = <List<String>>[];
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      ghExecutable: '/usr/bin/gh',
      runner: (executable, arguments, {workingDirectory}) async {
        requests.add(arguments);
        return ProcessResult(
          1,
          0,
          '{"author":{"login":"ada","avatar_url":"https://avatars.example/ada"},'
              '"committer":{"login":"cam","avatar_url":"https://avatars.example/cam"}}',
          '',
        );
      },
    );

    final first = service.resolve('abc1234');
    final second = service.resolve('abc1234');
    final avatars = await first;

    expect(identical(first, second), isTrue);
    expect(avatars.author?.login, 'ada');
    expect(avatars.committer?.login, 'cam');
    expect(requests, hasLength(1));
    expect(requests.single, [
      'api',
      '--hostname',
      'github.com',
      'repos/team/yogit/commits/abc1234',
    ]);
    expect(
      requests
          .expand((request) => request)
          .any((argument) => argument.toLowerCase().contains('gravatar')),
      isFalse,
    );
  });

  test('drops Gravatar avatar URLs returned by GitHub and GHE', () async {
    for (final entry in {
      'github.com': 'https://gravatar.com/avatar/ada',
      'git.example.com': 'https://cdn.gravatar.com/avatar/ada',
    }.entries) {
      final service = AvatarService(
        remote: RemoteRepository(
          host: entry.key,
          owner: 'team',
          repository: 'yogit',
        ),
        runner: (executable, arguments, {workingDirectory}) async => ProcessResult(
          1,
          0,
          '{"author":{"login":"ada","avatar_url":"${entry.value}"},'
              '"committer":{"login":"cam","avatar_url":"https://notgravatar.com/cam"}}',
          '',
        ),
      );

      final avatars = await service.resolve(entry.key);

      expect(avatars.author, isNull, reason: entry.key);
      expect(avatars.committer?.login, 'cam', reason: entry.key);
    }
  });

  test('GHE token headers stay on the selected remote host', () async {
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'git.example.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory}) async {
        if (arguments.take(2).join(' ') == 'auth token') {
          return ProcessResult(1, 0, 'secret-token\n', '');
        }
        return ProcessResult(
          1,
          0,
          '{"author":{"login":"ada","avatar_url":"https://cdn.example/ada"},'
              '"committer":{"login":"cam","avatar_url":"https://git.example.com/cam"}}',
          '',
        );
      },
    );

    final avatars = await service.resolve('abc1234');

    expect(avatars.author?.headers, isEmpty);
    expect(avatars.committer?.headers['Authorization'], 'Bearer secret-token');
  });

  test('avatar lookup runs at most four gh requests concurrently', () async {
    final gates = List.generate(5, (_) => Completer<ProcessResult>());
    var active = 0;
    var peak = 0;
    var started = 0;
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory}) {
        final gate = gates[started++];
        active++;
        peak = active > peak ? active : peak;
        return gate.future.whenComplete(() => active--);
      },
    );

    final futures = List.generate(5, (index) => service.resolve('$index'));
    await Future<void>.delayed(Duration.zero);
    expect(started, 4);
    expect(peak, 4);

    gates.first.complete(ProcessResult(1, 1, '', 'offline'));
    await Future<void>.delayed(Duration.zero);
    expect(started, 5);
    for (final gate in gates.skip(1)) {
      gate.complete(ProcessResult(1, 1, '', 'offline'));
    }
    await Future.wait(futures);
  });

  test(
    'avatar queue and SHA cache stay bounded under heavy scrolling',
    () async {
      final gates = List.generate(36, (_) => Completer<ProcessResult>());
      var started = 0;
      final service = AvatarService(
        remote: const RemoteRepository(
          host: 'github.com',
          owner: 'team',
          repository: 'yogit',
        ),
        runner: (executable, arguments, {workingDirectory}) =>
            gates[started++].future,
      );

      final futures = List.generate(400, (index) => service.resolve('$index'));
      await Future<void>.delayed(Duration.zero);

      expect(started, 4);
      expect(service.debugActiveRequestCount, 4);
      expect(service.debugQueuedRequestCount, 32);
      expect(service.debugCachedRequestCount, lessThanOrEqualTo(256));
      expect(
        identical(service.resolve('saturated'), service.resolve('saturated')),
        isTrue,
      );

      for (var index = 0; index < gates.length; index++) {
        gates[index].complete(ProcessResult(1, 1, '', 'offline'));
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(futures);
      expect(started, 36);
      expect(service.debugActiveRequestCount, 0);
      expect(service.debugQueuedRequestCount, 0);

      var sequentialStarts = 0;
      final lru = AvatarService(
        remote: const RemoteRepository(
          host: 'github.com',
          owner: 'team',
          repository: 'yogit',
        ),
        runner: (executable, arguments, {workingDirectory}) async {
          sequentialStarts++;
          return ProcessResult(1, 1, '', 'offline');
        },
      );
      for (var index = 0; index < 300; index++) {
        await lru.resolve('$index');
      }
      expect(sequentialStarts, 300);
      expect(lru.debugCachedRequestCount, 256);
      expect(identical(lru.resolve('299'), lru.resolve('299')), isTrue);
    },
  );

  testWidgets('settings toggle preserves timeline state and graph geometry', (
    tester,
  ) async {
    final store = MemorySettingsStore();
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory}) async =>
          ProcessResult(1, 1, '', 'offline'),
    );
    final repository = FakeGitRepository(
      (_, _) async => [
        commit('1', 'first commit'),
        commit('2', 'second commit'),
      ],
    );

    await tester.pumpWidget(
      YogitApp(
        repository: repository,
        settingsStore: store,
        avatarService: service,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final graphSize = tester.getSize(find.byKey(const Key('graph-painter-0')));

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Git integrations'), findsWidgets);
    await tester.tap(find.byKey(const Key('show-avatars-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selected-row-2')), findsOneWidget);
    expect(
      tester
          .widgetList<CommitAvatarStack>(find.byType(CommitAvatarStack))
          .every((avatar) => !avatar.showRemoteAvatars),
      isTrue,
    );
    expect(tester.getSize(find.byKey(const Key('graph-painter-0'))), graphSize);
    expect(store.current.showAvatars, isFalse);
  });

  testWidgets('persisted avatar opt-out wins before remote lookup starts', (
    tester,
  ) async {
    final loaded = Completer<AppSettings>();
    final store = DelayedSettingsStore(loaded.future);
    var requests = 0;
    final service = AvatarService(
      remote: const RemoteRepository(
        host: 'github.com',
        owner: 'team',
        repository: 'yogit',
      ),
      runner: (executable, arguments, {workingDirectory}) async {
        requests++;
        return ProcessResult(1, 1, '', 'offline');
      },
    );

    await tester.pumpWidget(
      YogitApp(
        repository: FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
        ),
        settingsStore: store,
        avatarService: service,
        discoverAvatars: false,
        windowFrameController: controller,
      ),
    );
    await tester.pump();
    expect(requests, 0);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('open-settings')))
          .onPressed,
      isNull,
    );

    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(30, 0),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.right);
    expect(store.saveCount, 0);

    loaded.complete(
      const AppSettings(
        showAvatars: false,
        previewPlacement: PreviewPlacement.bottom,
        columnWidths: TimelineColumnWidths(graph: 220),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.getSize(find.byKey(const Key('graph-painter-0'))).width, 220);
    expect(store.saveCount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.bottom);
  });

  testWidgets('preferred preview placement and column widths are applied', (
    tester,
  ) async {
    TimelineColumnWidths? savedWidths;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
          ),
          controller: controller,
          preferredPreviewPlacement: PreviewPlacement.bottom,
          columnWidths: const TimelineColumnWidths(graph: 210),
          onColumnWidthsChanged: (value) => savedWidths = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('graph-painter-0'))).width, 210);

    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(30, 0),
    );
    await tester.pump();
    expect(savedWidths?.graph, greaterThan(210));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.bottom);
  });
  // ------------------------------------------------------------------ §17.1
  test('date group labels read Today, Yesterday, then dates', () {
    final now = DateTime(2026, 7, 26, 10);
    String label(DateTime day) => dateGroupLabel(day, now);

    expect(label(DateTime(2026, 7, 26)), 'Today');
    expect(label(DateTime(2026, 7, 25)), 'Yesterday');
    expect(label(DateTime(2026, 7, 24)), '07.24 Fri');
    expect(label(DateTime(2026, 1, 1)), '01.01 Thu');
    expect(label(DateTime(2025, 12, 31)), '25.12.31 Wed');
    expect(label(DateTime(2024, 2, 29)), '24.02.29 Thu');
  });

  test('date separators head every day and the working tree leads them', () {
    final now = DateTime(2026, 7, 26, 12);
    int at(int day, int hour) =>
        DateTime(2026, 7, day, hour).millisecondsSinceEpoch ~/ 1000;
    final rows = layoutGraph([
      workingTreeCommit('a'),
      commit('a', 'today late', timestamp: at(26, 9)),
      commit('a2', 'today early', parents: const ['b'], timestamp: at(26, 1)),
      commit('b', 'yesterday', timestamp: at(25, 23)),
    ]);

    final entries = timelineEntries(rows, now);

    expect(entries.map((entry) => entry.label).toList(), [
      null,
      'Today',
      null,
      null,
      'Yesterday',
      null,
    ]);
    // The working tree row belongs to no day, so it leads the list.
    expect(entries.first.row.commit.isWorkingTree, isTrue);
    expect(entries.first.rowIndex, 0);
    expect(entries[2].rowIndex, 1);
    // A separator is a pass-through row carrying the lanes of the row above it.
    final separator = entries[4];
    expect(separator.rowIndex, -1);
    expect(separator.row.activeLanes, rows[2].nextLanes);
    expect(separator.row.nextLanes, rows[2].nextLanes);
    expect(separator.row.activeLaneShas, rows[2].nextLaneShas);
    expect(separator.row.activeLaneBranches, rows[2].nextLaneBranches);
    expect(separator.row.nextLaneBranches, rows[2].nextLaneBranches);
    expect(separator.row.transitions, isEmpty);
  });

  test('a date separator carries the rails and the sweep across itself', () {
    const size = Size(168, 36);
    final now = DateTime(2026, 7, 26, 12);
    int at(int day) =>
        DateTime(2026, 7, day, 12).millisecondsSinceEpoch ~/ 1000;
    // A merge on the older day: its second-parent sweep must finish over the
    // separator, and the merge must not stamp a node on the separator row.
    final rows = layoutGraph([
      commit('M', 'merge', parents: const ['P', 'F'], timestamp: at(26)),
      commit('P', 'parent', parents: const ['R'], timestamp: at(25)),
      commit('F', 'feature', parents: const ['R'], timestamp: at(25)),
      commit('R', 'root', timestamp: at(25)),
    ]);
    final entries = timelineEntries(rows, now);
    final separator = entries[2];
    expect(separator.label, 'Yesterday');

    final painter = CommitGraphPainter(
      row: separator.row,
      previous: rows[0],
      selected: true,
      committerColor: const Color(0xFF5CB270),
      passThrough: true,
    );

    // Lane 0 runs the full height and the arriving sweep completes here.
    expect(painter.laneVerticals(size)[0], (top: 0.0, bottom: 36.0));
    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      paints
        ..line(p1: const Offset(28, 0), p2: const Offset(28, 18))
        ..line(p1: const Offset(28, 18), p2: const Offset(28, 36))
        ..path(),
    );
    // No node, no selected band, no ref connector on a pass-through row.
    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      isNot(paints..circle()),
    );
    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      isNot(paints..rect()),
    );
  });

  testWidgets('date rows head their group, boxed at the hash column', (
    tester,
  ) async {
    final now = DateTime.now();
    int stamp(Duration ago) => now.subtract(ago).millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit(
              'a',
              'today commit',
              timestamp: stamp(const Duration(hours: 2)),
            ),
            commit(
              'b',
              'older commit',
              timestamp: stamp(const Duration(days: 2)),
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.byKey(const Key('date-row-0')), findsOneWidget);
    expect(find.byKey(const Key('date-row-2')), findsOneWidget);
    // Rounded, transparent, blue-bordered box with blue 12px w600 text.
    final box =
        tester
                .widget<Container>(find.byKey(const Key('date-box-0')))
                .decoration!
            as BoxDecoration;
    expect(box.color, isNull);
    expect((box.border! as Border).top.color, const Color(0xFF5AB0FF));
    expect((box.border! as Border).top.width, 1);
    expect(box.borderRadius, BorderRadius.circular(7));
    final label = tester.widget<Text>(find.text('Today'));
    expect(label.style?.color, const Color(0xFF5AB0FF));
    expect(label.style?.fontSize, 12);
    expect(label.style?.fontWeight, FontWeight.w600);
    // The box sits 5px left of the hash text it heads.
    expect(
      tester.getRect(find.byKey(const Key('date-box-0'))).left,
      tester.getRect(find.text('a')).left - 5,
    );
    // The date row is a row of the list, 36px like the rest.
    expect(tester.getSize(find.byKey(const Key('date-row-0'))).height, 36);

    // Underlines are gone from commit rows too.
    expect(
      tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(const Key('selected-row-a')),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration).border)
          .whereType<Border>()
          .map((border) => border.bottom.color),
      everyElement(isNot(const Color(0xFF343946))),
    );
  });

  testWidgets('date headings select like any other row', (tester) async {
    final now = DateTime.now();
    int stamp(Duration ago) => now.subtract(ago).millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit(
              'a',
              'today commit',
              timestamp: stamp(const Duration(hours: 2)),
            ),
            commit(
              'b',
              'older commit',
              timestamp: stamp(const Duration(days: 2)),
            ),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // Selection starts on the first commit, and the walk stops on the heading
    // between the two days on its way down.
    expect(find.byKey(const Key('selected-row-a')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-a')), findsNothing);
    expect(find.byKey(const Key('selected-row-b')), findsNothing);
    // The heading carries the full-width band while it holds the selection.
    final band = tester.widget<ColoredBox>(
      find
          .ancestor(
            of: find.byKey(const Key('date-row-2')),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(band.color, const Color(0xFF1F4D8F));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-b')), findsOneWidget);

    // A heading has no commit, so the preview falls back to its empty state.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('No commit selected'), findsOneWidget);
    expect(find.byKey(const Key('refs-modal')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);

    // Clicking a commit selects it, and clicking a heading selects that.
    await tester.tap(find.text('older commit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-b')), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-b')), findsNothing);
    expect(find.byKey(const Key('selected-row-a')), findsNothing);
  });

  // ------------------------------------------------------------------ §17.2
  test('branch colors take fixed roles, then a non-colliding pool', () {
    GraphRow born(int id, Map<int, int> active) => graphRow(
      commit: commit('$id', 'line $id'),
      lane: 0,
      activeLanes: active.keys.toList(),
      nextLanes: active.keys.toList(),
      branch: id,
      activeLaneBranches: active,
      nextLaneBranches: active,
    );
    // main, then a second line, then three lines each born while the earlier
    // ones are still running, then one more with the pool exhausted.
    final rows = [
      born(0, const {0: 0}),
      born(1, const {0: 0, 1: 1}),
      born(2, const {0: 0, 1: 1, 2: 2}),
      born(3, const {0: 0, 2: 2, 3: 3}),
      born(4, const {0: 0, 2: 2, 3: 3, 4: 4}),
      born(5, const {2: 2, 3: 3, 4: 4, 5: 5}),
    ];

    final colors = assignBranchColors(rows, 7);

    expect(colors[0], const Color(0xFF5CB270));
    expect(colors[1], anyOf(const Color(0xFF00E5FF), const Color(0xFFFF3131)));
    // Pool order, skipping colors already on screen at birth.
    expect(colors[2], const Color(0xFF3B82F6));
    expect(colors[3], const Color(0xFFFFF01F));
    expect(colors[4], const Color(0xFFB026FF));
    // Pool exhausted: a seeded pick from the rest of the palette.
    expect(colors[5], isNot(const Color(0xFF3B82F6)));
    expect(colors[5], isNot(const Color(0xFFFFF01F)));
    expect(colors[5], isNot(const Color(0xFFB026FF)));
    expect(colors[5], isNot(const Color(0xFF5CB270)));
    expect(colors[5], isNotNull);

    // Deterministic per seed, and stable as rows are appended.
    expect(assignBranchColors(rows, 7), colors);
    expect(assignBranchColors(rows, 8)[0], colors[0]);
    for (var length = 1; length <= rows.length; length++) {
      final prefix = assignBranchColors(rows.sublist(0, length), 7);
      for (final entry in prefix.entries) {
        expect(entry.value, colors[entry.key], reason: 'id ${entry.key}');
      }
    }
    // Both second-line colors are reachable across seeds.
    expect(
      {for (var seed = 0; seed < 8; seed++) assignBranchColors(rows, seed)[1]},
      {const Color(0xFF00E5FF), const Color(0xFFFF3131)},
    );
  });

  test('assigned branch colors win over the fallback palette', () {
    addTearDown(() {
      AvatarService.branchAssignments = const {};
      AvatarService.palette = AvatarService.defaultColors;
    });

    AvatarService.branchAssignments = const {0: Color(0xFF010203)};
    expect(AvatarService.branchColor(0), const Color(0xFF010203));
    // An id the map does not carry keeps the palette fallback; main stays green.
    AvatarService.branchAssignments = const {};
    expect(AvatarService.branchColor(0), const Color(0xFF5CB270));
    expect(AvatarService.branchColor(1), AvatarService.defaultColors.first);
  });

  testWidgets('the timeline colors the graph with its assigned lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [
            commit('merge', 'merge commit', parents: const ['main', 'feature']),
            commit('main', 'main commit', parents: const ['base']),
            commit('feature', 'feature commit', parents: const ['base']),
          ],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    expect(painter.row.branch, 0);
    expect(painter.committerColor, const Color(0xFF5CB270));
    expect(AvatarService.branchAssignments[0], const Color(0xFF5CB270));
    expect(
      AvatarService.branchAssignments[1],
      anyOf(const Color(0xFF00E5FF), const Color(0xFFFF3131)),
    );
  });

  // ------------------------------------------------------------------ §17.3
  testWidgets('ref chips split the cell width and drop what will not fit', (
    tester,
  ) async {
    const many = [
      GitRef(name: 'main', isHead: true),
      GitRef(name: 'v1.0', isTag: true),
      GitRef(name: 'origin/main'),
      GitRef(name: 'feature/one'),
      GitRef(name: 'feature/two'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit('three', 'three refs', refs: many.take(3).toList()),
              commit('five', 'five refs', refs: many),
            ],
          ),
          controller: controller,
          // 150px of chips: floor(150 / 40) = 3 chips at 50px each.
          columnWidths: const TimelineColumnWidths(refs: 150),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Rect chip(String sha, String name) =>
        tester.getRect(find.byKey(Key('ref-chip-$sha-$name')));
    for (final ref in many.take(3)) {
      expect(chip('three', ref.name).width, greaterThanOrEqualTo(40));
    }
    // Equal shares, in order, inside the cell.
    expect(chip('three', 'main').left, lessThan(chip('three', 'v1.0').left));
    expect(
      chip('three', 'v1.0').left,
      lessThan(chip('three', 'origin/main').left),
    );
    expect(
      chip('three', 'main').width,
      closeTo(chip('three', 'origin/main').width, 0.5),
    );

    // Five refs in the same cell: three chips, the rest silently dropped, and
    // no badge anywhere.
    for (final ref in many.take(3)) {
      expect(find.byKey(Key('ref-chip-five-${ref.name}')), findsOneWidget);
    }
    for (final ref in many.skip(3)) {
      expect(find.byKey(Key('ref-chip-five-${ref.name}')), findsNothing);
    }
    expect(find.byKey(const Key('ref-more-five')), findsNothing);
    expect(find.textContaining('+'), findsNothing);

    // The modal still lists every ref, each behind a square 2px accent bar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final modal = find.byKey(const Key('refs-modal'));
    for (final ref in many) {
      expect(
        find.descendant(of: modal, matching: find.text(ref.name)),
        findsOneWidget,
      );
    }
    final accent = find.byKey(const Key('modal-accent-main'));
    expect(tester.getSize(accent).width, 2);
    expect(tester.getSize(accent).height, 20);
    expect(tester.widget<Container>(accent).decoration, isNull);
  });

  // ------------------------------------------------------------------ §17.4
  testWidgets('the graph column ratchets to the lanes it has shown', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    // A straight run on lane 0, then an octopus far below the fold opening
    // lanes 1..3.
    final repository = FakeGitRepository(
      (_, _) async => [
        for (var index = 0; index < 20; index++)
          commit('$index', 'commit $index', parents: ['${index + 1}']),
        commit('20', 'octopus', parents: const ['a', 'b', 'c', 'd']),
        commit('a', 'a'),
        commit('b', 'b'),
        commit('c', 'c'),
        commit('d', 'd'),
      ],
    );
    Widget screen(GitRepository repository, Key key) => MaterialApp(
      home: TimelineScreen(
        key: key,
        repository: repository,
        controller: controller,
      ),
    );
    await tester.pumpWidget(screen(repository, const Key('first')));
    await tester.pumpAndSettle();
    double graphWidth() =>
        tester.getSize(find.byKey(const Key('graph-header'))).width;

    // Only lane 0 is on screen, so the column stays at its floor.
    expect(graphWidth(), 96);

    // Scrolling the octopus into view widens it once: 28 + 3 * 30 + 13.
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(graphWidth(), 131);

    // Scrolling back never shrinks it inside a session.
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(graphWidth(), 131);

    // A different repository starts over.
    await tester.pumpWidget(
      screen(
        FakeGitRepository((_, _) async => [commit('1', 'first commit')]),
        const Key('second'),
      ),
    );
    await tester.pumpAndSettle();
    expect(graphWidth(), 96);
  });
  // ------------------------------------------------------------------ §18.1
  test('a date heading carries a non-main lane through, not just lane 0', () {
    const size = Size(168, 36);
    final now = DateTime(2026, 7, 26, 12);
    int at(int day) =>
        DateTime(2026, 7, day, 12).millisecondsSinceEpoch ~/ 1000;
    // A lane-1 chain straddling a day change, with lane 0 running beside it.
    final rows = layoutGraph([
      commit('M', 'merge', parents: const ['P', 'F1'], timestamp: at(26)),
      commit('F1', 'feature today', parents: const ['F2'], timestamp: at(26)),
      commit(
        'F2',
        'feature yesterday',
        parents: const ['P'],
        timestamp: at(25),
      ),
      commit('P', 'parent', timestamp: at(25)),
    ]);
    final entries = timelineEntries(rows, now);
    final heading = entries.firstWhere((entry) => entry.label == 'Yesterday');
    final above = entries[entries.indexOf(heading) - 1];
    expect(above.row.commit.sha, 'F1');
    expect(above.row.lane, 1);

    final painter = CommitGraphPainter(
      row: heading.row,
      previous: above.row,
      selected: false,
      committerColor: AvatarService.branchColor(0),
      passThrough: true,
    );

    // Both lanes hand their rail straight through the heading row.
    expect(painter.laneVerticals(size)[0], (top: 0.0, bottom: 36.0));
    expect(painter.laneVerticals(size)[1], (top: 0.0, bottom: 36.0));
    expect(
      (Canvas canvas) => painter.paint(canvas, size),
      paints
        ..line(p1: const Offset(28, 0), p2: const Offset(28, 18))
        ..line(p1: const Offset(28, 18), p2: const Offset(28, 36))
        ..line(p1: const Offset(58, 0), p2: const Offset(58, 18))
        ..line(p1: const Offset(58, 18), p2: const Offset(58, 36)),
    );

    // The commit below the heading resumes lane 1 from the top of its row.
    final below = entries[entries.indexOf(heading) + 1];
    expect(below.row.commit.sha, 'F2');
    final resumed = CommitGraphPainter(
      row: below.row,
      previous: heading.row,
      selected: false,
      committerColor: AvatarService.branchColor(0),
    );
    expect(resumed.continuesFromAbove(1), isTrue);
    expect(resumed.laneVerticals(size)[1]?.top, 0.0);
  });

  testWidgets('the date heading row paints its rails at full row size', (
    tester,
  ) async {
    final now = DateTime.now();
    int stamp(Duration ago) => now.subtract(ago).millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit(
                'M',
                'merge',
                parents: const ['P', 'F'],
                timestamp: stamp(const Duration(hours: 1)),
              ),
              commit(
                'F',
                'feature today',
                parents: const ['P'],
                timestamp: stamp(const Duration(hours: 2)),
              ),
              commit('P', 'parent', timestamp: stamp(const Duration(days: 2))),
            ],
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(graph: 120),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The heading's graph cell is a full row, so its rails actually paint.
    final painter = find.byKey(const Key('date-painter-3'));
    expect(painter, findsOneWidget);
    expect(tester.getSize(painter), const Size(120, 36));
    expect(
      tester.getRect(painter).left,
      tester.getRect(find.byKey(const Key('graph-cell-0'))).left,
    );
  });

  // ------------------------------------------------------------------ §18.2
  testWidgets('nodes sit above every rail and inside their own lane', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit('o', 'octopus', parents: const ['a', 'b', 'c', 'd', 'e']),
              commit('a', 'a', parents: const ['z']),
              commit('b', 'b', parents: const ['z']),
              commit('c', 'c', parents: const ['z']),
              commit('d', 'd', parents: const ['z']),
              commit('e', 'e', parents: const ['z']),
              commit('z', 'root'),
            ],
          ),
          controller: controller,
          // Five lanes squeezed into a cell far below their content width.
          columnWidths: const TimelineColumnWidths(graph: 110),
        ),
      ),
    );
    await tester.pumpAndSettle();

    CommitGraphPainter painterAt(int index) =>
        tester
                .widget<CustomPaint>(find.byKey(Key('graph-painter-$index')))
                .painter!
            as CommitGraphPainter;
    expect(painterAt(0).laneSpacing, lessThan(30));

    for (var index = 1; index <= 5; index++) {
      final painter = painterAt(index);
      final cell = tester.getRect(find.byKey(Key('graph-cell-$index')));
      final stack = find.descendant(
        of: find.byKey(Key('graph-cell-$index')),
        matching: find.byType(CommitAvatarStack),
      );
      final avatar = tester.widget<CommitAvatarStack>(stack);
      final rect = tester.getRect(stack);

      // The node sits on its lane's effective x, centred on it.
      expect(
        rect.left - cell.left,
        closeTo(painter.laneX(painter.row.lane) - avatar.size / 2, 0.01),
      );
      // And it stops short of the next lane's rail.
      expect(
        rect.right - cell.left,
        lessThanOrEqualTo(
          painter.laneX(painter.row.lane) +
              painter.laneSpacing -
              CommitGraphPainter.railWidth,
        ),
      );

      // Rails paint below the node: the painter comes first in the row's stack.
      final children = tester
          .widget<Stack>(
            find
                .descendant(
                  of: find.byKey(Key('graph-cell-$index')),
                  matching: find.byType(Stack),
                )
                .first,
          )
          .children;
      expect(children.length, 2);
      expect(
        find
            .descendant(
              of: find.byWidget(children.first),
              matching: find.byType(CustomPaint),
            )
            .evaluate(),
        isNotEmpty,
      );
      expect(
        find
            .descendant(
              of: find.byWidget(children.last),
              matching: find.byType(CommitAvatarStack),
            )
            .evaluate(),
        isNotEmpty,
      );
    }
  });
  // ------------------------------------------------------------------ §18.3
  testWidgets('the toolbar reads half again bigger', (tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          root: '/Users/ada/project',
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('/Users/ada/project')).style?.fontSize,
      18,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.account_tree_outlined)).size,
      24,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.folder_open_outlined)).size,
      24,
    );
    expect(tester.getSize(find.byKey(const Key('toolbar'))).height, 56);
  });

  // ------------------------------------------------------------------ §18.4
  testWidgets('the sidebar resizes, persists, and clamps', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
            refs: const RepoRefs(local: ['main'], current: 'main'),
          ),
          controller: controller,
          onColumnWidthsChanged: (value) => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    double sidebarWidth() =>
        tester.getSize(find.byKey(const Key('sidebar'))).width;
    double titleWidth() =>
        tester.getSize(find.byKey(const Key('commit-header'))).width;
    double nameRight() =>
        tester.getRect(find.byKey(const Key('name-header'))).right;

    expect(const TimelineColumnWidths().sidebar, 150);
    expect(sidebarWidth(), 150);
    final title = titleWidth();

    // Dragging the right edge widens it, and the timeline gives up exactly that
    // much so no dead strip opens.
    await tester.drag(
      find.byKey(const Key('sidebar-resizer')),
      const Offset(70, 0),
    );
    await tester.pumpAndSettle();
    expect(sidebarWidth(), 220);
    expect(saved?.sidebar, 220);
    expect(titleWidth(), title - 70);
    expect(nameRight(), 1400);

    // It clamps at both ends of the design range.
    await tester.drag(
      find.byKey(const Key('sidebar-resizer')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();
    expect(sidebarWidth(), 320);
    await tester.drag(
      find.byKey(const Key('sidebar-resizer')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(sidebarWidth(), 120);
    expect(saved?.sidebar, 120);

    // Round-trips like every other width, clamped on the way in.
    expect(
      TimelineColumnWidths.fromJson(
        const TimelineColumnWidths(sidebar: 240).toJson(),
      ).sidebar,
      240,
    );
    expect(
      TimelineColumnWidths.fromJson(<String, dynamic>{'sidebar': 40}).sidebar,
      120,
    );
    expect(
      TimelineColumnWidths.fromJson(<String, dynamic>{'sidebar': 900}).sidebar,
      320,
    );
  });

  testWidgets('the sidebar reads a size up', (tester) async {
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('1', 'first commit')],
          refs: const RepoRefs(
            local: ['main'],
            tags: ['v1.0'],
            current: 'main',
          ),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text('main')).style?.fontSize, 13);
    expect(tester.widget<Text>(find.text('LOCAL')).style?.fontSize, 11);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ref-filter')))
          .style
          ?.fontSize,
      13,
    );
  });
  // ------------------------------------------------------------------ §18.2b
  testWidgets('a newborn branch line leaves the source node center', (
    tester,
  ) async {
    final now = DateTime.now();
    int stamp(Duration ago) => now.subtract(ago).millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            // A merge whose second parent opens a new column, with the day
            // change landing right under it.
            (_, _) async => [
              commit(
                'M',
                'merge',
                parents: const ['P', 'F'],
                timestamp: stamp(const Duration(hours: 1)),
              ),
              commit(
                'P',
                'parent',
                parents: const ['R'],
                timestamp: stamp(const Duration(days: 2)),
              ),
              commit(
                'F',
                'feature',
                parents: const ['R'],
                timestamp: stamp(const Duration(days: 2)),
              ),
              commit('R', 'root', timestamp: stamp(const Duration(days: 3))),
            ],
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(graph: 120),
        ),
      ),
    );
    await tester.pumpAndSettle();

    CommitGraphPainter painterAt(Key key) =>
        tester.widget<CustomPaint>(find.byKey(key)).painter!
            as CommitGraphPainter;
    const size = Size(120, 36);
    final merge = painterAt(const Key('graph-painter-0'));
    final edge = merge.row.transitions.single;
    expect(edge.from, merge.row.lane);
    expect(edge.to, 1);

    // A birth: the same discriminator the color rule uses puts its bend beside
    // the departure node.
    expect(CommitGraphPainter.isMergeEdge(merge.row, edge), isTrue);
    Path departure() => merge.transitionPath(
      edge.from,
      edge.to,
      18,
      size,
      bendEarly: CommitGraphPainter.isMergeEdge(merge.row, edge),
    );

    // The birth leaves the node sideways on one arc into its own column, instead
    // of running down the parent's rail into the next row.
    expect(_touches(departure(), const Offset(28, 18)), isTrue);
    expect(departure().getBounds(), Rect.fromLTRB(28, 18, merge.laneX(1), 54));
    final sweep = _samples(departure());
    // Everything past the sweep sits in the new column, still inside this row.
    expect(
      sweep.where((point) => point.dy > 50).map((point) => point.dx),
      everyElement(closeTo(merge.laneX(1), 0.01)),
    );
    expect(
      sweep
          .where((point) => point.dx > 29)
          .map((point) => point.dy)
          .reduce((a, b) => a < b ? a : b),
      lessThan(36),
    );

    // The date heading right below completes the sweep into the new column.
    final heading = painterAt(const Key('date-painter-2'));
    expect(heading.passThrough, isTrue);
    final arrival = heading.transitionPath(
      edge.from,
      edge.to,
      18 - 36,
      size,
      // Classified against the row that started it, so the halves match.
      bendEarly: CommitGraphPainter.isMergeEdge(merge.row, edge),
    );
    expect(_touches(arrival, Offset(heading.laneX(1), 18)), isTrue);
    // The sweep finishes inside the heading row and runs straight from there.
    expect(
      _samples(
        arrival,
      ).where((point) => point.dy >= 12).map((point) => point.dx),
      everyElement(closeTo(heading.laneX(1), 0.01)),
    );
  });
  // ------------------------------------------------------------------ §18.4b
  testWidgets('the ref modal shows long names in full', (tester) async {
    const long = 'feature/very-long-branch-name-for-testing-full-width';
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit('first', 'first commit'),
              commit(
                'many',
                'many refs',
                refs: const [
                  GitRef(name: 'main', isHead: true),
                  GitRef(name: long),
                ],
              ),
            ],
          ),
          controller: controller,
          columnWidths: const TimelineColumnWidths(refs: 120),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final modal = find.byKey(const Key('refs-modal'));
    expect(modal, findsOneWidget);
    // The full name renders, and nothing inside the modal ellipsizes.
    final name = find.descendant(of: modal, matching: find.text(long));
    expect(name, findsOneWidget);
    expect(tester.widget<Text>(name).overflow, TextOverflow.visible);
    expect(tester.getSize(name).width, greaterThan(120));
    // The box grew past the refs column to fit it, and stays in the viewport.
    final width = tester.getSize(modal).width;
    expect(width, greaterThan(120));
    expect(
      width,
      lessThanOrEqualTo(
        tester.getSize(find.byKey(const Key('timeline-viewport'))).width,
      ),
    );
  });
}

/// Points along [path], for probing where a rail actually runs.
List<Offset> _samples(Path path) => path
    .computeMetrics()
    .expand(
      (metric) => [
        for (var step = 0; step <= 400; step++)
          metric.getTangentForOffset(metric.length * step / 400)!.position,
      ],
    )
    .toList();

/// Whether [path] passes within a hair of [point].
bool _touches(Path path, Offset point) =>
    _samples(path).any((sample) => (sample - point).distance < 0.5);

Widget app(GitRepository repository, WindowFrameController controller) =>
    MaterialApp(
      home: TimelineScreen(repository: repository, controller: controller),
    );

class FakeGitRepository extends GitRepository {
  FakeGitRepository(
    this.loader, {
    this.files,
    this.diff,
    this.workingTree,
    this.refs = const RepoRefs(local: ['main'], current: 'main'),
    String root = '.',
    CommandRunner runner = runProcess,
  }) : super(root, runner: runner);

  final RepoRefs refs;
  final Future<List<GitCommit>> Function(int skip, int limit) loader;
  final Future<GitCommit?> Function()? workingTree;
  final Future<List<GitFileChange>> Function(GitCommit commit, String? parent)?
  files;
  final Future<List<DiffLine>> Function(
    GitCommit commit,
    String? parent,
    String path,
    DiffAlgorithm algorithm,
  )?
  diff;

  @override
  Future<List<GitCommit>> loadHistory({int limit = 500, int skip = 0}) =>
      loader(skip, limit);

  @override
  Future<RepoRefs> loadRefs() async => refs;

  @override
  Future<GitCommit?> loadWorkingTree() =>
      workingTree?.call() ?? Future.value(null);

  @override
  Future<List<GitFileChange>> loadFiles(GitCommit commit, {String? parent}) =>
      files?.call(commit, parent) ?? Future.value(const []);

  @override
  Future<List<DiffLine>> loadDiff(
    GitCommit commit,
    String path, {
    String? parent,
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
  }) => diff?.call(commit, parent, path, algorithm) ?? Future.value(const []);
}

class DelayedSettingsStore extends SettingsStore {
  DelayedSettingsStore(this.settings) : super(File('/tmp/yogit-unused.json'));

  final Future<AppSettings> settings;
  var saveCount = 0;

  @override
  Future<AppSettings> load() => settings;

  @override
  Future<void> save(AppSettings settings) async => saveCount++;
}

class MemorySettingsStore extends SettingsStore {
  MemorySettingsStore() : super(File('/tmp/yogit-unused.json'));

  AppSettings current = const AppSettings();

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<void> save(AppSettings settings) async => current = settings;
}

/// A row built for the painter directly: it reads lanes and [transitions], so
/// these tests stay independent of how layoutGraph assigns them.
GraphRow graphRow({
  required GitCommit commit,
  required int lane,
  List<int> activeLanes = const [],
  List<int> nextLanes = const [],
  Map<int, String> activeLaneShas = const {},
  Map<int, String> nextLaneShas = const {},
  List<LaneTransition> transitions = const [],
  List<int> parentLanes = const [],
  int branch = 0,
  Map<int, int> activeLaneBranches = const {},
  Map<int, int> nextLaneBranches = const {},
}) => GraphRow(
  commit: commit,
  lane: lane,
  parentLanes: parentLanes,
  activeLanes: activeLanes,
  nextLanes: nextLanes,
  activeLaneShas: activeLaneShas,
  nextLaneShas: nextLaneShas,
  transitions: transitions,
  branch: branch,
  activeLaneBranches: activeLaneBranches,
  nextLaneBranches: nextLaneBranches,
);

GitCommit workingTreeCommit(String head) => GitCommit(
  sha: '',
  shortSha: '',
  parents: [head],
  author: const GitIdentity(name: '', email: ''),
  authorTimestamp: 0,
  committer: const GitIdentity(name: '', email: ''),
  committerTimestamp: 0,
  refs: const [],
  subject: 'Uncommitted changes',
);

GitCommit commit(
  String sha,
  String subject, {
  List<String> parents = const [],
  List<GitRef>? refs,
  int timestamp = 1700000120,
  GitIdentity committer = const GitIdentity(
    name: 'Cam Committer',
    email: 'cam@example.com',
  ),
}) => GitCommit(
  sha: sha,
  shortSha: sha,
  parents: parents,
  author: GitIdentity(name: 'Ada Author', email: 'ada@example.com'),
  authorTimestamp: 1700000000,
  committer: committer,
  committerTimestamp: timestamp,
  refs:
      refs ??
      (sha == '3' ? const [GitRef(name: 'main', isHead: true)] : const []),
  subject: subject,
);
