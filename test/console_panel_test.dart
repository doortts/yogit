import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/command_log.dart';
import 'package:yogit/console_panel.dart';
import 'package:yogit/timeline_theme.dart';

/// 콘솔 패널은 로그를 읽어 보여 주기만 한다. 실패한 줄은 묻지 않아도 펼쳐지고,
/// 사용자가 시킨 일의 이름은 그 아래 명령보다 먼저 놓이며, 가려진 출력은 어떤
/// 조작으로도 열리지 않는다.
void main() {
  ProcessResult ok([String stdout = '', String stderr = '']) =>
      ProcessResult(1, 0, stdout, stderr);

  Future<void> pump(WidgetTester tester, CommandLog log) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [TimelineThemePalette.systemGraphite],
        ),
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ConsolePanel(log: log, onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an empty console says so', (tester) async {
    await pump(tester, CommandLog());
    expect(find.text('아직 실행한 명령이 없습니다'), findsOneWidget);
  });

  testWidgets('a command shows its line and opens on a tap', (tester) async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ok('7508f23\n'),
    );
    await run('git', ['rev-parse', 'HEAD']);
    await pump(tester, log);

    final id = log.entries.single.id;
    expect(find.text('git rev-parse HEAD'), findsOneWidget);
    expect(find.byKey(Key('console-detail-$id')), findsNothing);

    await tester.tap(find.byKey(Key('console-command-$id')));
    await tester.pump();

    expect(find.byKey(Key('console-detail-$id')), findsOneWidget);
    expect(find.textContaining('7508f23'), findsOneWidget);
  });

  testWidgets('a failure opens itself and shows what went wrong', (
    tester,
  ) async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 1, '', '! [rejected] main -> main\n'),
    );
    await run('git', ['push']);
    await pump(tester, log);

    // 실패는 눌러야 보이면 놓친다.
    expect(find.textContaining('rejected'), findsOneWidget);
  });

  testWidgets('the action stands above the commands it asked for', (
    tester,
  ) async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async => ok(),
    );
    await log.action('브랜치 체크아웃 — lane', () => run('git', ['checkout', 'lane']));
    await pump(tester, log);

    final action = log.entries.first;
    expect(find.byKey(Key('console-action-${action.id}')), findsOneWidget);
    expect(find.text('브랜치 체크아웃 — lane'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(Key('console-action-${action.id}'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(Key('console-command-${log.entries[1].id}')))
            .dy,
      ),
    );
  });

  testWidgets('a failure that opened itself can still be closed', (
    tester,
  ) async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 1, '', '! [rejected] main -> main\n'),
    );
    await run('git', ['push']);
    await pump(tester, log);

    final id = log.entries.single.id;
    expect(find.byKey(Key('console-detail-$id')), findsOneWidget);

    await tester.tap(find.byKey(Key('console-command-$id')));
    await tester.pump();

    expect(
      find.byKey(Key('console-detail-$id')),
      findsNothing,
      reason: '앱이 연 것을 읽는 사람이 닫을 수 있어야 한다',
    );
  });

  testWidgets('the keychain line can be read but never opened', (tester) async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ok('ghp_realsecrettoken'),
    );
    await run('/usr/bin/security', ['find-generic-password', '-w']);
    await pump(tester, log);

    final id = log.entries.single.id;
    await tester.tap(find.byKey(Key('console-command-$id')));
    await tester.pump();

    expect(find.byKey(Key('console-detail-$id')), findsNothing);
    expect(find.textContaining('ghp_'), findsNothing);
    // 열리지 않는 줄이라면, 무엇이 없는지는 줄 자체가 말해야 한다.
    expect(find.text('출력 감춤 (자격 증명)'), findsOneWidget);
  });

  testWidgets('실패만 leaves the failures and their action names', (tester) async {
    final log = CommandLog();
    var code = 0;
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, code, '', ''),
    );
    await run('git', ['status']);
    await log.action('Push', () async {
      code = 1;
      await run('git', ['push']);
    });
    await pump(tester, log);

    await tester.tap(find.byKey(const Key('console-filter-실패만')));
    await tester.pump();

    expect(find.text('git push'), findsOneWidget);
    expect(find.text('git status'), findsNothing);
    expect(find.text('Push'), findsOneWidget, reason: '무엇을 하다 실패했는지가 남는다');
  });

  testWidgets('a search that matches nothing says which emptiness it is', (
    tester,
  ) async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async => ok(),
    );
    await run('git', ['status']);
    await pump(tester, log);

    await tester.enterText(find.byKey(const Key('console-search')), 'rebase');
    await tester.pump();

    expect(find.text('이 조건에 맞는 줄이 없습니다'), findsOneWidget);
  });

  testWidgets('clearing empties the console', (tester) async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async => ok(),
    );
    await run('git', ['status']);
    await pump(tester, log);

    await tester.tap(find.byKey(const Key('console-clear')));
    await tester.pump();

    expect(log.entries, isEmpty);
    expect(find.text('아직 실행한 명령이 없습니다'), findsOneWidget);
  });

  testWidgets('a big answer says how much of it is not here', (tester) async {
    final log = CommandLog(outputLimit: 16);
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ok('x' * 4096),
    );
    await run('git', ['diff']);
    await pump(tester, log);

    // 접힌 채로도 무엇이 빠졌는지 보인다.
    expect(find.textContaining('앞 16바이트만 보관'), findsOneWidget);
  });
}
