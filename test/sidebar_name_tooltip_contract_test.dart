import 'package:flutter/gestures.dart';
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

  Finder card() => find.byKey(const Key('sidebar-name-tooltip'));

  /// 마우스를 행에 올리고, 그때 뜬 카드의 문구를 돌려준다 — 아무것도 안 뜨면 null.
  Future<String?> hoverAndRead(WidgetTester tester, String ref) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(Key('sidebar-ref-$ref'))));
    await tester.pumpAndSettle();
    if (card().evaluate().isEmpty) return null;
    return tester
        .widget<Text>(find.descendant(of: card(), matching: find.byType(Text)))
        .data;
  }

  testWidgets('a name cut short says its whole self on hover', (tester) async {
    await pumpSidebar(tester);

    expect(
      await hoverAndRead(tester, long),
      long,
      reason: '행에 보이는 조각이 아니라 폴더까지 붙은 전체 이름이다',
    );
  });

  testWidgets('the card opens to the right, clear of the next row', (
    tester,
  ) async {
    await pumpSidebar(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(Key('sidebar-ref-$long'))));
    await tester.pumpAndSettle();

    expect(card(), findsOneWidget);

    final rowRect = tester.getRect(find.byKey(Key('sidebar-ref-$long')));
    final cardRect = tester.getRect(card());
    expect(
      cardRect.left,
      greaterThanOrEqualTo(rowRect.right),
      reason: '이름 오른쪽에 선다',
    );
    expect(
      cardRect.top,
      lessThan(rowRect.bottom),
      reason: '아래 행을 덮지 않는다 — 같은 줄 높이에 머문다',
    );
  });

  testWidgets('a name that already fits gets no tooltip', (tester) async {
    await pumpSidebar(tester);

    expect(
      await hoverAndRead(tester, 'main'),
      isNull,
      reason: '다 보이는 이름 위의 툴팁은 방해다',
    );
  });
}
