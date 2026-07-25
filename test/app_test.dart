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
    expect(list.cacheExtent, 0);

    // The preview opens with the app, so the subject shows in both panes.
    expect(find.text('Commit & Diff'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('second commit'), findsNWidgets(2));
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

    await tester.tap(find.text('하단'));
    await tester.pumpAndSettle();
    expect(controller.previewPlacement, PreviewPlacement.bottom);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Commit & Diff'), findsNothing);

    await tester.tap(find.text('third commit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-3')), findsOneWidget);
    expect(find.text('Commit & Diff'), findsOneWidget);
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
    expect(header.style?.fontSize, 11);
    final commitHeader = tester.widget<Text>(find.text('COMMIT TITLE'));
    expect(commitHeader.style?.fontFamily, 'monospace');
    expect(commitHeader.style?.fontSize, 11);
    expect(find.text('SOCIAL TIME'), findsOneWidget);
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

  test('lane transitions are rounded right angles spanning a full row', () {
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
    expect(CommitGraphPainter.jogInset, 8);
    expect(CommitGraphPainter.departureRadius, 5);
    expect(CommitGraphPainter.arrivalRadius, 8);

    // Node center (y 18) down to the next row's center (y 54): one row height,
    // and no overshoot outside the two lanes.
    expect(painter.row.transitions, [(from: 0, to: 1, sha: '0')]);
    final path = painter.transitionPath(0, 1, 18, size);
    expect(path.getBounds(), const Rect.fromLTRB(28, 18, 58, 54));

    final metrics = path.computeMetrics().single;
    ui.Tangent at(double fraction) =>
        metrics.getTangentForOffset(metrics.length * fraction)!;

    // Leaves the node and enters the arrival lane vertically.
    expect(at(0).vector.dx.abs(), lessThan(0.01));
    expect(at(0).vector.dy, greaterThan(0.99));
    expect(at(1).vector.dx.abs(), lessThan(0.01));
    expect(at(1).vector.dy, greaterThan(0.99));

    // A flat jog line 8px above the arrival center carries the sideways move:
    // 5px arc out, a full 8px arc in that lands exactly on the arrival center,
    // so the straight run spans x 33 to 50.
    const jogY = 54.0 - CommitGraphPainter.jogInset;
    expect(jogY + CommitGraphPainter.arrivalRadius, 54);
    final jog = <Offset>[];
    for (var step = 0; step <= 400; step++) {
      final point = at(step / 400).position;
      if ((point.dy - jogY).abs() < 0.01) jog.add(point);
    }
    expect(jog, hasLength(greaterThan(1)));
    expect(jog.first.dx, closeTo(33, 0.5));
    expect(jog.last.dx, closeTo(50, 0.5));
    expect(jog.map((point) => point.dy), everyElement(closeTo(jogY, 0.01)));

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
      painter.transitionPath(0, 1, 18 - size.height, size).getBounds(),
      const Rect.fromLTRB(28, -18, 58, 18),
    );

    // A distant lane only lengthens the horizontal run on the same jog line.
    final distant = painterTo(2).transitionPath(0, 2, 18, size);
    expect(distant.getBounds(), const Rect.fromLTRB(28, 18, 88, 54));
    final distantMetrics = distant.computeMetrics().single;
    final distantJog = <Offset>[];
    for (var step = 0; step <= 400; step++) {
      final point = distantMetrics
          .getTangentForOffset(distantMetrics.length * step / 400)!
          .position;
      if ((point.dy - jogY).abs() < 0.01) distantJog.add(point);
    }
    expect(distantJog.last.dx - distantJog.first.dx, greaterThan(40));
    expect(distantJog.first.dx, closeTo(33, 0.5));

    // Leftward transitions mirror, keeping the same radii.
    expect(
      painter.transitionPath(2, 0, 18, size).getBounds(),
      const Rect.fromLTRB(28, 18, 88, 54),
    );
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

  test('the working tree ring takes the HEAD committer lane color', () {
    const head = GitIdentity(name: 'Cam Committer', email: 'cam@example.com');
    final rows = layoutGraph([
      workingTreeCommit('head'),
      commit('head', 'head commit', committer: head),
    ]);
    final painter = CommitGraphPainter(
      row: rows[0],
      selected: true,
      committerColor: AvatarService.color(head),
      committersBySha: {'': head, 'head': head},
    );

    expect(painter.workingTreeRingColor, AvatarService.color(head));
    expect(painter.workingTreeRingColor, isNot(const Color(0xFF15171E)));
    // The fill hides the rail behind the node, so it follows the row color.
    expect(painter.nodeFillColor, const Color(0xFF1F4D8F));
    expect(
      CommitGraphPainter(
        row: rows[0],
        selected: false,
        committerColor: AvatarService.color(head),
        committersBySha: {'': head, 'head': head},
      ).nodeFillColor,
      const Color(0xFF15171E),
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
    expect(stack.size, 18);
    expect(stack.ringWidth, 2.0);
    expect(
      stack.ringColor,
      AvatarService.color(painterAt(1).row.commit.committer),
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

    // Default is unset, so the title column takes whatever is left over.
    expect(const TimelineColumnWidths().commit, isNull);
    double titleWidth() =>
        tester.getSize(find.byKey(const Key('commit-header'))).width;
    double nameRight() =>
        tester.getRect(find.byKey(const Key('name-header'))).right;

    // 1400 - 150 sidebar - 288 preview - (156 + 96 + 78 + 116 + 100) fixed.
    expect(titleWidth(), 416);
    expect(nameRight(), lessThanOrEqualTo(1400 - 288));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(titleWidth(), 704);
    expect(nameRight(), lessThanOrEqualTo(1400));

    // Every column stays visible at the default window size with the preview
    // open, which is the whole point of flexing.
    tester.view.physicalSize = const Size(1280, 760);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(titleWidth(), 296);
    expect(nameRight(), lessThanOrEqualTo(1280 - 288));

    // Dragging pins it: the stored width is saved and stops following the
    // viewport. The drag starts from the width on screen (296).
    await tester.drag(
      find.byKey(const Key('commit-resizer')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    final pinned = titleWidth();
    expect(pinned, greaterThan(296));
    expect(saved?.commit, pinned);
    // A wider window still fills the slack: the drag is a floor, not a cap, so
    // no dead strip ever opens on the right.
    tester.view.physicalSize = const Size(1400, 760);
    await tester.pumpAndSettle();
    expect(titleWidth(), 416);
    expect(nameRight(), 1400 - 288);
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
    final page = Completer<List<GitCommit>>();
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository((_, _) => page.future),
          controller: controller,
          // A width dragged narrower than the viewport must not strand slack.
          columnWidths: const TimelineColumnWidths(commit: 330),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Rect viewport() =>
        tester.getRect(find.byKey(const Key('timeline-viewport')));
    double columnWidth(String column) =>
        tester.getSize(find.byKey(Key('$column-header'))).width;

    // 1538 - 150 sidebar - 288 preview.
    expect(viewport().width, 1100);
    expect(columnWidth('graph'), 96);
    expect(columnWidth('commit'), 1100 - (156 + 96 + 78 + 116 + 100));
    expect(
      tester.getRect(find.byKey(const Key('name-header'))).right,
      viewport().right,
    );

    // A deeper graph widens its own column, and the title gives back exactly
    // that much — the right edge stays flush.
    page.complete([
      commit('M', 'octopus', parents: const ['a', 'b', 'c']),
      commit('a', 'a'),
      commit('b', 'b'),
      commit('c', 'c'),
    ]);
    await tester.pumpAndSettle();
    expect(columnWidth('graph'), 118);
    expect(columnWidth('commit'), 1100 - (156 + 118 + 78 + 116 + 100));
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

    // Three lanes want 28 + 3 * 30, which clears the minimum.
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
    expect(graphWidth(), 118);

    // Dragging pins it, and the pinned width is what gets saved.
    await tester.drag(
      find.byKey(const Key('graph-resizer')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    final pinned = graphWidth();
    expect(pinned, greaterThan(118));
    expect(saved?.graph, pinned);
    final painter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('graph-painter-0')))
                .painter!
            as CommitGraphPainter;
    expect(painter.laneX(1) - painter.laneX(0), 30);
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
    expect(saved?.name, 100);
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
      expect(clamped.name, 88);
      expect(clamped.refs, 240);
      expect(clamped.commit, 620);
      expect(clamped.graph, 96);
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

    // Timeline row plus the open preview title.
    expect(find.text('Uncommitted changes'), findsNWidgets(2));
    expect(find.text('working tree'), findsOneWidget);
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

  testWidgets('renders every ref and later HEAD committer avatar', (
    tester,
  ) async {
    final refs = const [
      GitRef(name: 'v1.0', isTag: true),
      GitRef(name: 'origin/main'),
      GitRef(name: 'feature'),
      GitRef(name: 'main', isHead: true),
    ];
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [commit('multi', 'multi ref commit', refs: refs)],
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();

    // Scoped to the row: the sidebar lists branch names of its own.
    for (final ref in refs) {
      expect(
        find.descendant(
          of: find.byKey(const Key('refs-cell-0')),
          matching: find.text(ref.name),
        ),
        findsOneWidget,
      );
    }
    // Every branch chip carries the tip committer; the tag chip carries none.
    for (final ref in refs.where((ref) => !ref.isTag)) {
      expect(find.byKey(Key('ref-avatar-multi-${ref.name}')), findsOneWidget);
    }
    expect(find.byKey(const Key('ref-avatar-multi-v1.0')), findsNothing);

    // Chips pack to the right: the last one ends on the graph boundary, and the
    // stagger keeps every earlier chip inside the cell.
    final cell = tester.getRect(find.byKey(const Key('refs-cell-0')));
    Rect chip(GitRef ref) =>
        tester.getRect(find.byKey(Key('ref-chip-multi-${ref.name}')));
    expect(chip(refs.last).right, cell.right);
    expect(chip(refs.first).left, greaterThanOrEqualTo(cell.left));
    for (var index = 1; index < refs.length; index++) {
      expect(chip(refs[index]).left, greaterThan(chip(refs[index - 1]).left));
    }
    // The remaining run to the node is the graph cell's own connector.
    expect(
      tester.getRect(find.byKey(const Key('graph-cell-0'))).left,
      cell.right,
    );
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
    // Timeline row plus the open preview title.
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
    // Timeline row plus the reopened preview title, and the old history is gone.
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
}

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
}) => GraphRow(
  commit: commit,
  lane: lane,
  parentLanes: const [],
  activeLanes: activeLanes,
  nextLanes: nextLanes,
  activeLaneShas: activeLaneShas,
  nextLaneShas: nextLaneShas,
  transitions: transitions,
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
  committerTimestamp: 1700000120,
  refs:
      refs ??
      (sha == '3' ? const [GitRef(name: 'main', isHead: true)] : const []),
  subject: subject,
);
