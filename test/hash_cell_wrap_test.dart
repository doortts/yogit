import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// A hash cell never wraps. A column narrower than its content — dragged
/// there, fitted there, or squeezed there by the viewport — clips the sha to
/// one line instead of folding it onto a second one inside the row.
void main() {
  Widget timeline({required double hashWidth}) => MaterialApp(
    home: TimelineScreen(
      repository: FakeGitRepository(
        (_, _) async => [commit('abcdef0', 'first commit')],
      ),
      controller: WindowFrameController(
        channel: const MethodChannel('test/yogit-window'),
      ),
      columnWidths: TimelineColumnWidths(hash: hashWidth),
    ),
  );

  testWidgets('a sha stays on one line however narrow its column', (
    tester,
  ) async {
    // 64 is the column minimum; the Ahem test font draws the seven-character
    // sha at 84px, so without a guard it folds onto a second line.
    await tester.pumpWidget(timeline(hashWidth: 64));
    await tester.pumpAndSettle();

    final sha = tester.getSize(find.text('abcdef0'));
    expect(sha.height, lessThan(20), reason: '해시가 두 줄이 됐다 — 잘려야지 접히면 안 된다');
  });

  testWidgets('a double-click fit leaves every sha on one line', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(timeline(hashWidth: 120));
    await tester.pumpAndSettle();

    final resizer = find.byKey(const Key('hash-resizer'));
    await tester.tap(resizer);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(resizer);
    await tester.pumpAndSettle();

    expect(tester.getSize(find.text('abcdef0')).height, lessThan(20));
    expect(
      tester.getSize(find.byKey(const Key('hash-header'))).width,
      greaterThanOrEqualTo(timelineColumns['hash']!.min),
    );
  });
}
