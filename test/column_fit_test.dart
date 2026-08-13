import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// Contract for two column mechanics:
/// - the hash column's left rule is a 1px hairline, not a 2px strip;
/// - double-clicking a column's resizer fits that column to the widest content
///   currently on screen, clamped to the column's own max and the viewport.
void main() {
  Widget timeline({
    required WindowFrameController controller,
    ValueChanged<TimelineColumnWidths>? onColumnWidthsChanged,
    TimelineColumnWidths widths = const TimelineColumnWidths(),
  }) => MaterialApp(
    home: TimelineScreen(
      repository: FakeGitRepository(
        (_, _) async => [
          commit(
            '1',
            'a subject long enough that the title column has to grow for it',
            refs: const [GitRef(name: 'codex/branch-lane-palette-assignments')],
          ),
          commit('2', 'short one'),
        ],
      ),
      controller: controller,
      columnWidths: widths,
      onColumnWidthsChanged: onColumnWidthsChanged,
    ),
  );

  /// 열 사이를 가르는 선은 마지막 열의 오른쪽에서 그친다. 목록의 끝은 창이
  /// 이미 그어 두었으니, 거기 한 줄을 더 그으면 두 줄로 보인다.
  testWidgets('the rightmost column heading draws no rule of its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      timeline(
        controller: WindowFrameController(
          channel: const MethodChannel('test/yogit-window'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    BorderSide rightRule(String column) {
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(Key('$column-header')),
              matching: find.byType(Container),
            )
            .first,
      );
      return ((box.decoration! as BoxDecoration).border! as Border).right;
    }

    expect(rightRule('name'), BorderSide.none, reason: '맨 오른쪽 열');
    expect(rightRule('commit').color, isNot(BorderSide.none.color));
  });

  testWidgets('the hash rule is a one pixel hairline', (tester) async {
    await tester.pumpWidget(
      timeline(
        controller: WindowFrameController(
          channel: const MethodChannel('test/yogit-window'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('hash-rule-0'))).width, 1);
  });

  testWidgets('double-clicking a resizer fits the column to its content', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      timeline(
        controller: WindowFrameController(
          channel: const MethodChannel('test/yogit-window'),
        ),
        onColumnWidthsChanged: (value) => saved = value,
        // Start the refs column at its minimum so a fit has room to grow.
        widths: const TimelineColumnWidths(refs: 110),
      ),
    );
    await tester.pumpAndSettle();

    double refsWidth() =>
        tester.getSize(find.byKey(const Key('refs-header'))).width;
    expect(refsWidth(), 110);

    final resizer = find.byKey(const Key('refs-resizer'));
    await tester.tap(resizer);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(resizer);
    await tester.pumpAndSettle();

    // The long branch name no longer has to ellipsize, and the fit is saved.
    expect(refsWidth(), greaterThan(110));
    expect(refsWidth(), lessThanOrEqualTo(timelineColumns['refs']!.max));
    expect(saved?.refs, refsWidth());

    // Fitting twice is idempotent: the content did not change.
    final fitted = refsWidth();
    await tester.tap(resizer);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(resizer);
    await tester.pumpAndSettle();
    expect(refsWidth(), fitted);
  });

  testWidgets('a single click on the resizer still resizes nothing', (
    tester,
  ) async {
    TimelineColumnWidths? saved;
    await tester.pumpWidget(
      timeline(
        controller: WindowFrameController(
          channel: const MethodChannel('test/yogit-window'),
        ),
        onColumnWidthsChanged: (value) => saved = value,
        widths: const TimelineColumnWidths(refs: 110),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('refs-resizer')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('refs-header'))).width, 110);
    expect(saved, isNull);
  });
}
