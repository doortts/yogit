import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/command_log.dart';
import 'package:yogit/git.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// 콘솔은 창 아래에 붙어 있고, 툴바 버튼이나 ⌘`로 열린다. 사용자가 메뉴에서 고른
/// 일은 그 이름이 먼저 찍히고, 그 일이 부른 git이 그 아래에 놓인다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  const refs = RepoRefs(
    local: ['main', 'lane'],
    remote: [],
    remoteNames: [],
    tags: [],
    current: 'main',
    tips: {'main': '1', 'lane': '1'},
  );

  Future<CommandLog> pump(WidgetTester tester) async {
    final log = CommandLog();
    final repository = FakeGitRepository(
      (_, _) async => [commit('1', 'c')],
      refs: refs,
    );
    await tester.pumpWidget(app(repository, controller, commandLog: log));
    await tester.pumpAndSettle();
    return log;
  }

  testWidgets('the console is shut until the toolbar opens it', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('console-dock')), findsNothing);

    await tester.tap(find.byKey(const Key('toolbar-console')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('console-dock')), findsOneWidget);
    expect(find.text('콘솔'), findsOneWidget);

    await tester.tap(find.byKey(const Key('console-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('console-dock')), findsNothing);
  });

  testWidgets('⌘` opens and closes it too', (tester) async {
    await pump(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.backquote);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('console-dock')), findsOneWidget);
  });

  testWidgets('a menu choice that ran no process writes no line', (
    tester,
  ) async {
    final log = await pump(tester);
    await tester.tap(find.byKey(const Key('toolbar-console')));
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('sidebar-ref-lane'));
    await tester.tap(row);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sidebar-menu-base-lane')));
    await tester.pumpAndSettle();

    // 기준 브랜치는 화면 안의 결정이라 git을 부르지 않는다. 콘솔은 일어나지 않은
    // 일을 적지 않는다.
    expect(log.entries, isEmpty);
    expect(find.text('아직 실행한 명령이 없습니다'), findsOneWidget);
  });

  testWidgets('a command run under that name is filed beneath it', (
    tester,
  ) async {
    final log = await pump(tester);

    // 메뉴가 여는 것과 같은 자리: 이름 안에서 돈 git은 그 이름을 달고 남는다.
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 0, '', ''),
    );
    await log.action('브랜치 체크아웃 — lane', () => run('git', ['checkout', 'lane']));
    await tester.tap(find.byKey(const Key('toolbar-console')));
    await tester.pumpAndSettle();

    expect(find.text('브랜치 체크아웃 — lane'), findsOneWidget);
    expect(find.text('git checkout lane'), findsOneWidget);
    expect(log.entries.last.actionId, log.entries.first.id);
  });
}
