import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// Contract for how a branch or tag name gives way when its chip is too
/// narrow (승인된 2안).
///
/// A ref's useful half is its end, so the last segment is what survives:
/// leading namespace segments shrink to their first letter, and only when
/// that still does not fit do characters drop off the FRONT, marked by a
/// leading ellipsis. The trailing end is never cut.
void main() {
  /// A fixed-width stand-in for a real font: every character is 10 wide, so
  /// the expected strings below are arithmetic rather than font metrics.
  double measure(String text) => text.length * 10;

  group('fitRefName', () {
    test('a name that fits is untouched', () {
      expect(fitRefName('main', 100, measure), 'main');
      expect(fitRefName('codex/lane', 100, measure), 'codex/lane');
    });

    test('leading segments shrink to their first letter', () {
      // 'codex/branch-lane' is 17 chars; 'c…/branch-lane' is 14.
      expect(fitRefName('codex/branch-lane', 150, measure), 'c…/branch-lane');
      expect(
        fitRefName('release/2026.08.1-hotfix', 200, measure),
        'r…/2026.08.1-hotfix',
      );
    });

    test('every leading segment shrinks, not just the first', () {
      expect(fitRefName('feature/team/bar-baz', 150, measure), 'f…/t…/bar-baz');
    });

    test('too narrow even abbreviated: characters drop off the front', () {
      // 'c…/branch-lane' needs 140; at 100 only the tail plus '…' fits.
      final fitted = fitRefName('codex/branch-lane', 100, measure);
      expect(fitted, startsWith('…'));
      expect(measure(fitted), lessThanOrEqualTo(100));
      expect('codex/branch-lane', endsWith(fitted.substring(1)));
      // The end of the name is what survived.
      expect(fitted, endsWith('lane'));
    });

    test('a name with no namespace drops off the front directly', () {
      // 6 characters fit in 60: the ellipsis plus the last five.
      expect(fitRefName('v2026.08.1-rc2', 60, measure), '…1-rc2');
    });

    test('an impossible width still returns something drawable', () {
      expect(fitRefName('main', 5, measure), '…');
      expect(fitRefName('main', 0, measure), '…');
    });

    test('a trailing slash does not lose the name to an empty segment', () {
      expect(fitRefName('codex/', 30, measure).endsWith('/'), isTrue);
    });
  });

  group('the chip on screen', () {
    Widget timeline({double refsWidth = 110}) => MaterialApp(
      home: TimelineScreen(
        repository: FakeGitRepository(
          (_, _) async => [
            commit(
              '1',
              'first',
              refs: const [
                GitRef(name: 'codex/branch-lane-palette-assignments'),
              ],
            ),
            commit(
              '2',
              'second',
              refs: const [GitRef(name: 'v0.7.3-rc2', isTag: true)],
            ),
          ],
        ),
        controller: WindowFrameController(
          channel: const MethodChannel('test/yogit-window'),
        ),
        columnWidths: TimelineColumnWidths(refs: refsWidth),
      ),
    );

    testWidgets('the tail of a long branch name is what shows', (tester) async {
      await tester.pumpWidget(timeline());
      await tester.pumpAndSettle();

      final drawn = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .where((data) => data.contains('assignments'))
          .toList();
      expect(drawn, isNotEmpty, reason: '마지막 세그먼트는 살아남아야 한다');
      expect(
        drawn.every((data) => data != 'codex/branch-lane-palette-assignments'),
        isTrue,
        reason: '110px 안에 전체 이름이 들어갈 수 없다',
      );
    });

    testWidgets('the ✓ and ◇ glyphs survive the narrowest chip', (
      tester,
    ) async {
      await tester.pumpWidget(timeline(refsWidth: 110));
      await tester.pumpAndSettle();
      // The tag chip keeps its diamond however little room the name has.
      expect(find.text('◇'), findsWidgets);
    });
  });

  testWidgets('fitting a column never introduces a horizontal scroll', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [
              commit(
                '1',
                'a subject that would happily take the whole window if asked',
                refs: const [
                  GitRef(name: 'codex/branch-lane-palette-assignments'),
                ],
              ),
            ],
          ),
          controller: WindowFrameController(
            channel: const MethodChannel('test/yogit-window'),
          ),
          columnWidths: const TimelineColumnWidths(refs: 110),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final content = find.byKey(const Key('timeline-horizontal-content'));
    final viewport = find.byKey(const Key('timeline-list'));
    for (final column in const ['refs', 'hash', 'time', 'name', 'commit']) {
      final resizer = find.byKey(Key('$column-resizer'));
      if (resizer.evaluate().isEmpty) continue;
      await tester.tap(resizer);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(resizer);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(content).width,
        lessThanOrEqualTo(tester.getSize(viewport).width),
        reason: '$column 맞춤 후 가로 스크롤이 생겼다',
      );
    }
  });
}
