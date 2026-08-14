import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/command_log.dart';
import 'package:yogit/git.dart';
import 'package:yogit/timeline_palette.dart';
import 'package:yogit/timeline_theme.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// 콘솔은 창 아래에 붙어 있고, 상태바 버튼이나 ⌘`로 열린다. 사용자가 메뉴에서 고른
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

  testWidgets('the console is shut until the status bar opens it', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byKey(const Key('console-dock')), findsNothing);

    await tester.tap(find.byKey(const Key('console-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('console-dock')), findsOneWidget);
    expect(find.text('콘솔'), findsOneWidget);

    await tester.tap(find.byKey(const Key('console-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('console-dock')), findsNothing);
  });

  testWidgets('the door stands in the status bar, left of the profile chip', (
    tester,
  ) async {
    await pump(tester);

    final toggle = find.byKey(const Key('console-toggle'));
    // 로그를 보는 일은 상태 확인이라 문은 툴바를 떠났다.
    expect(
      find.descendant(of: find.byKey(const Key('toolbar')), matching: toggle),
      findsNothing,
    );
    final door = tester.getRect(toggle);
    final chip = tester.getRect(find.byKey(const Key('commit-profile-chip')));
    expect(chip.left - door.right, moreOrLessEquals(8, epsilon: 0.5));
    expect(door.center.dy, moreOrLessEquals(chip.center.dy, epsilon: 0.5));
    // 그림 하나로 선 문이라, 눌리는 것이라고 스스로 말해야 한다 — 툴바의 버튼은
    // 말해 주고 있었다.
    expect(
      tester.getSemantics(toggle),
      matchesSemantics(isButton: true, hasTapAction: true, tooltip: '콘솔 (⌘`)'),
    );
  });

  testWidgets('the glyph goes orange while a command is out there', (
    tester,
  ) async {
    final log = await pump(tester);
    // 시험이 세우는 앱에는 팔레트 확장이 없으니 기본 팔레트가 쓰인다.
    final idle = TimelineThemePalette.systemGraphite.muted;
    Color? glyph() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('console-toggle')),
            matching: find.text('>_'),
          ),
        )
        .style
        ?.color;

    expect(glyph(), idle);

    // 문이 닫혀 있는 동안에는 이 색이 명령이 돌고 있다는 유일한 신호다.
    final finished = Completer<ProcessResult>();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) =>
          finished.future,
    );
    final running = run('git', ['fetch']);
    await tester.pump();

    expect(glyph(), behindOrange);

    finished.complete(ProcessResult(1, 0, '', ''));
    await running;
    await tester.pump();

    expect(glyph(), idle);
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
    await tester.tap(find.byKey(const Key('console-toggle')));
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
    await tester.tap(find.byKey(const Key('console-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('브랜치 체크아웃 — lane'), findsOneWidget);
    expect(find.text('git checkout lane'), findsOneWidget);
    expect(log.entries.last.actionId, log.entries.first.id);
  });
}
