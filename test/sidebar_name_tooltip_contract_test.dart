import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// docs/sidebar-and-row-branch-design.md §3 — 이름이 줄임표로 잘린 사이드바 행에만
/// 전체 ref 이름을 툴팁으로 단다. 다 보이는 이름 위의 툴팁은 방해다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  const long = 'codex/notes-split-input-performance-with-a-very-long-tail';

  Future<void> pumpSidebar(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: FakeGitRepository(
            (_, _) async => [commit('1', 'first commit')],
            refs: const RepoRefs(local: ['main', long], current: 'main'),
          ),
          // Wide enough that 'main' and its HEAD chip both fit whole — the
          // narrow default clips even that, and then the tooltip is right.
          columnWidths: const TimelineColumnWidths(sidebar: 320),
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 행에 보이는 조각 — 폴더 아래 브랜치는 마지막 마디만 그린다.
  String segmentOf(String ref) => ref.split('/').last;

  Tooltip? tooltipOn(WidgetTester tester, String ref) {
    final candidates = find.ancestor(
      of: find.descendant(
        of: find.byKey(Key('sidebar-ref-$ref')),
        matching: find.text(segmentOf(ref)),
      ),
      matching: find.byType(Tooltip),
    );
    return candidates.evaluate().isEmpty
        ? null
        : tester.widget<Tooltip>(candidates.first);
  }

  testWidgets('a name cut short says its whole self on hover', (tester) async {
    await pumpSidebar(tester);

    final tooltip = tooltipOn(tester, long);
    expect(tooltip, isNotNull, reason: '잘린 이름에는 툴팁이 있어야 한다');
    expect(tooltip!.message, long, reason: '행에 보이는 조각이 아니라 폴더까지 붙은 전체 이름이다');
  });

  testWidgets('a name that already fits gets no tooltip', (tester) async {
    await pumpSidebar(tester);

    expect(tooltipOn(tester, 'main'), isNull, reason: '다 보이는 이름 위의 툴팁은 방해다');
  });
}
