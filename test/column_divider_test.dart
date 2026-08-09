import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// Contract for what a column divider does under the mouse.
///
/// A divider goes where it is dragged. That is the whole contract, and it is
/// what the layout made impossible for the columns right of the flexing title
/// column: growing Date stole its width from the title column on its LEFT, so
/// Date's own right edge — the line under the cursor — never moved and Author
/// kept every pixel. A divider drag now moves width between the two columns
/// the divider separates, so the line follows the cursor and the total never
/// changes.
void main() {
  Widget timeline({
    ValueChanged<TimelineColumnWidths>? onColumnWidthsChanged,
    TimelineColumnWidths widths = const TimelineColumnWidths(
      time: 100,
      name: 120,
    ),
  }) => MaterialApp(
    home: TimelineScreen(
      repository: FakeGitRepository(
        (_, _) async => [commit('1', 'first commit')],
      ),
      controller: WindowFrameController(
        channel: const MethodChannel('test/yogit-window'),
      ),
      columnWidths: widths,
      onColumnWidthsChanged: onColumnWidthsChanged,
    ),
  );

  double widthOf(WidgetTester tester, String column) =>
      tester.getSize(find.byKey(Key('$column-header'))).width;

  /// The x of the line the column's resizer sits on.
  double dividerX(WidgetTester tester, String column) =>
      tester.getRect(find.byKey(Key('$column-header'))).right;

  Future<void> dragDivider(
    WidgetTester tester,
    String column,
    double dx,
  ) async {
    await tester.drag(find.byKey(Key('$column-resizer')), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  group('a divider follows the cursor', () {
    testWidgets("Date's divider moves and Author gives up the width", (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(timeline());
      await tester.pumpAndSettle();

      final commitBefore = widthOf(tester, 'commit');
      final lineBefore = dividerX(tester, 'time');

      await dragDivider(tester, 'time', 40);

      expect(dividerX(tester, 'time'), closeTo(lineBefore + 40, 1));
      expect(widthOf(tester, 'time'), closeTo(140, 1));
      expect(widthOf(tester, 'name'), closeTo(80, 1));
      expect(
        widthOf(tester, 'commit'),
        closeTo(commitBefore, 1),
        reason: '제목 컬럼은 이 드래그와 무관하다',
      );

      // And back the other way: the divider goes left, Author takes it back.
      await dragDivider(tester, 'time', -40);
      expect(dividerX(tester, 'time'), closeTo(lineBefore, 1));
      expect(widthOf(tester, 'time'), closeTo(100, 1));
      expect(widthOf(tester, 'name'), closeTo(120, 1));
    });

    testWidgets("the title column's divider takes from Date, not from Author", (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(timeline());
      await tester.pumpAndSettle();

      final lineBefore = dividerX(tester, 'commit');
      await dragDivider(tester, 'commit', 30);

      expect(dividerX(tester, 'commit'), closeTo(lineBefore + 30, 1));
      expect(widthOf(tester, 'time'), closeTo(70, 1));
      expect(widthOf(tester, 'name'), closeTo(120, 1));
    });

    testWidgets('a divider left of the title column still follows', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(timeline());
      await tester.pumpAndSettle();

      final lineBefore = dividerX(tester, 'refs');
      final refsBefore = widthOf(tester, 'refs');
      await dragDivider(tester, 'refs', 20);

      expect(dividerX(tester, 'refs'), closeTo(lineBefore + 20, 1));
      expect(widthOf(tester, 'refs'), closeTo(refsBefore + 20, 1));
      // Date and Author are nowhere near this divider.
      expect(widthOf(tester, 'time'), closeTo(100, 1));
      expect(widthOf(tester, 'name'), closeTo(120, 1));
    });

    testWidgets('dragging Date right far enough collapses Author', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      TimelineColumnWidths? saved;
      // Date starts at its minimum so it has room to take all of Author's.
      await tester.pumpWidget(
        timeline(
          widths: TimelineColumnWidths(
            time: timelineColumns['time']!.min,
            name: 120,
          ),
          onColumnWidthsChanged: (value) => saved = value,
        ),
      );
      await tester.pumpAndSettle();

      // Author bottoms out at its minimum first, then goes.
      await dragDivider(tester, 'time', 100);
      expect(widthOf(tester, 'name'), timelineColumns['name']!.min);
      await dragDivider(tester, 'time', 30);
      expect(find.byKey(const Key('name-header')), findsNothing);
      expect(saved?.showName, isFalse);
    });

    testWidgets('a column at its own limit stops the divider instead of '
        'quietly eating its neighbour', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      // Date starts at its maximum, so it cannot take another pixel.
      await tester.pumpWidget(
        timeline(
          widths: TimelineColumnWidths(
            time: timelineColumns['time']!.max,
            name: 120,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lineBefore = dividerX(tester, 'time');
      await dragDivider(tester, 'time', 40);
      expect(dividerX(tester, 'time'), closeTo(lineBefore, 1));
      expect(
        widthOf(tester, 'name'),
        closeTo(120, 1),
        reason: '선이 못 움직이면 Author도 빼앗기지 않아야 한다',
      );

      // The mirror case: Author at its maximum cannot take what Date gives up.
      await tester.pumpWidget(
        timeline(
          widths: TimelineColumnWidths(
            time: 100,
            name: timelineColumns['name']!.max,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mirrorBefore = dividerX(tester, 'time');
      await dragDivider(tester, 'time', -40);
      expect(dividerX(tester, 'time'), closeTo(mirrorBefore, 1));
      expect(widthOf(tester, 'time'), closeTo(100, 1));
    });

    testWidgets("the title column's divider transfers leftward too: Date "
        'takes what the title gives up', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(timeline());
      await tester.pumpAndSettle();

      final lineBefore = dividerX(tester, 'commit');
      final commitBefore = widthOf(tester, 'commit');

      await dragDivider(tester, 'commit', -40);

      expect(dividerX(tester, 'commit'), closeTo(lineBefore - 40, 1));
      expect(widthOf(tester, 'commit'), closeTo(commitBefore - 40, 1));
      expect(widthOf(tester, 'time'), closeTo(140, 1));
      expect(widthOf(tester, 'name'), closeTo(120, 1));
    });

    testWidgets('leftward transfer cascades to Author and stops at the caps', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(timeline());
      await tester.pumpAndSettle();

      final commitBefore = widthOf(tester, 'commit');
      final lineBefore = dividerX(tester, 'commit');
      // Date can take 70 (100→170), Author 120 (120→240): 190 in total.
      await dragDivider(tester, 'commit', -400);

      expect(widthOf(tester, 'time'), timelineColumns['time']!.max);
      expect(widthOf(tester, 'name'), timelineColumns['name']!.max);
      expect(widthOf(tester, 'commit'), closeTo(commitBefore - 190, 1));
      expect(dividerX(tester, 'commit'), closeTo(lineBefore - 190, 1));
    });

    testWidgets('double-clicking the title divider fits it to the longest '
        'subject on screen', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(timeline());
      await tester.pumpAndSettle();

      final pane = tester.getSize(find.byKey(const Key('timeline-viewport')));
      final before = widthOf(tester, 'commit');

      final resizer = find.byKey(const Key('commit-resizer'));
      await tester.tap(resizer);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(resizer);
      await tester.pumpAndSettle();

      // 'first commit' is short: the column compacts, the neighbours take
      // the difference, and the row still fills the pane exactly.
      final after = widthOf(tester, 'commit');
      expect(after, lessThan(before));
      expect(after, greaterThanOrEqualTo(timelineColumns['commit']!.min));
      final subject = tester.getSize(find.text('first commit'));
      expect(after, greaterThanOrEqualTo(subject.width));
      expect(
        tester
            .getSize(find.byKey(const Key('timeline-horizontal-content')))
            .width,
        lessThanOrEqualTo(pane.width),
      );
    });

    testWidgets('the total never grows, so no horizontal scroll appears', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(timeline());
      await tester.pumpAndSettle();

      final content = find.byKey(const Key('timeline-horizontal-content'));
      final pane = find.byKey(const Key('timeline-viewport'));
      for (final drag in const [
        ('refs', 60.0),
        ('commit', 80.0),
        ('time', 90.0),
        ('name', 40.0),
        ('time', -70.0),
      ]) {
        await dragDivider(tester, drag.$1, drag.$2);
        expect(
          tester.getSize(content).width,
          lessThanOrEqualTo(tester.getSize(pane).width),
          reason: '${drag.$1} 드래그 후 가로 스크롤이 생겼다',
        );
      }
    });

    testWidgets('several moves inside one frame count in full', (tester) async {
      // A fast mouse delivers more than one move between frames. Each move has
      // to build on the width the one before it left, or the divider crawls
      // behind the cursor at a fraction of its speed.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 800);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(timeline());
      await tester.pumpAndSettle();

      for (final column in const ['refs', 'graph', 'hash', 'time']) {
        final before = widthOf(tester, column);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(Key('$column-resizer'))),
          kind: PointerDeviceKind.mouse,
        );
        for (var move = 0; move < 4; move++) {
          await gesture.moveBy(const Offset(6, 0));
        }
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          widthOf(tester, column),
          closeTo(before + 24, 1),
          reason: '$column: 네 번 움직인 만큼 다 따라와야 한다',
        );
      }
    });
  });
}
