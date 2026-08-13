import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// 타임라인 BRANCH / TAG 칸의 이름을 누르면 사이드바에서도 같은 ref가 골라진다.
/// 사이드바 커서를 눌러 타임라인이 따라오는 흐름의 반대 방향이다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  Future<void> pump(WidgetTester tester, FakeGitRepository repository) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(app(repository, controller));
    await tester.pumpAndSettle();
  }

  /// 사이드바 행이 커서를 달고 있는지 — 커서만 왼쪽에 2px 테두리를 그린다.
  bool cursorOn(WidgetTester tester, String name) {
    final background = find.byKey(Key('sidebar-ref-hover-background-$name'));
    if (background.evaluate().isEmpty) return false;
    final decoration =
        tester.widget<DecoratedBox>(background).decoration as BoxDecoration;
    return (decoration.border! as Border).left.width == 2;
  }

  testWidgets('a branch chip puts the sidebar cursor on that branch', (
    tester,
  ) async {
    await pump(
      tester,
      FakeGitRepository(
        (_, _) async => [
          commit(
            'a',
            'tip',
            parents: ['b'],
            refs: const [GitRef(name: 'feature')],
          ),
          commit('b', 'root', refs: const [GitRef(name: 'main', isHead: true)]),
        ],
        refs: const RepoRefs(
          local: ['main', 'feature'],
          current: 'main',
          tips: {'main': 'b', 'feature': 'a'},
        ),
      ),
    );

    expect(cursorOn(tester, 'feature'), isFalse);

    await tester.tap(find.byKey(const Key('ref-chip-a-feature')));
    await tester.pumpAndSettle();

    expect(cursorOn(tester, 'feature'), isTrue);
    // 행 자체도 눌린 대로 골라진다 — 칩이 행의 클릭을 가로채지 않는다.
    expect(find.byKey(const Key('selected-row-a')), findsOneWidget);
  });

  testWidgets('a tag past the short list is opened up to before it is picked', (
    tester,
  ) async {
    // 태그 칸은 열 개까지만 보인다. 열한 번째 태그를 누르면 나머지를 펼쳐야
    // 커서가 앉을 행이 생긴다.
    final tags = [for (var index = 0; index < 11; index++) 'v$index'];
    await pump(
      tester,
      FakeGitRepository(
        (_, _) async => [
          commit(
            'a',
            'tagged',
            parents: ['b'],
            refs: [GitRef(name: tags.first, isTag: true)],
          ),
          commit('b', 'root', refs: const [GitRef(name: 'main', isHead: true)]),
        ],
        refs: RepoRefs(
          local: const ['main'],
          current: 'main',
          tags: tags,
          tips: {for (final tag in tags) tag: 'a', 'main': 'b'},
          tagCreatorTimes: {
            for (var index = 0; index < tags.length; index++)
              tags[index]: 1700000000 + index,
          },
        ),
      ),
    );

    // 가장 오래된 태그라 짧은 목록에는 들지 못한다.
    expect(
      find.byKey(Key('sidebar-ref-hover-background-${tags.first}')),
      findsNothing,
    );

    await tester.tap(find.byKey(Key('ref-chip-a-${tags.first}')));
    await tester.pumpAndSettle();

    expect(cursorOn(tester, tags.first), isTrue);
  });
}
