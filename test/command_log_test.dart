import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/command_log.dart';

/// 콘솔은 앱이 밖으로 내보내는 모든 프로세스를 지나는 자리 하나를 감싸서 만든다.
/// 사용자가 시킨 일에는 이름이 붙고 그 아래에 명령이 놓이며, 자격 증명을 쥔
/// 명령의 출력은 성공이든 실패든 콘솔에 들어오지 않는다.
void main() {
  ProcessResult ok([Object stdout = '', Object stderr = '']) =>
      ProcessResult(1, 0, stdout, stderr);

  test('a wrapped call is written down with what it answered', () async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ok('7508f23\n'),
    );

    final result = await run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: '/repo');

    expect(result.exitCode, 0, reason: '감싸도 답은 그대로 지나간다');
    final entry = log.entries.single;
    expect(entry.kind, CommandLogKind.command);
    expect(entry.commandLine, 'git rev-parse HEAD');
    expect(entry.workingDirectory, '/repo');
    expect(entry.stdout, '7508f23\n');
    expect(entry.state, CommandLogState.ok);
    expect(entry.duration, isNotNull);
  });

  test('a failing command keeps its code and what it said', () async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 1, '', '! [rejected] main -> main\n'),
    );

    await run('git', ['push']);

    expect(log.entries.single.state, CommandLogState.failed);
    expect(log.entries.single.stderr, contains('rejected'));
    expect(log.failedCount, 1);
  });

  test('a runner that throws leaves the line and the error both', () async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          throw const ProcessException('git', ['status'], 'not found'),
    );

    await expectLater(run('git', ['status']), throwsA(isA<ProcessException>()));

    final entry = log.entries.single;
    expect(entry.state, CommandLogState.failed, reason: '답이 없는 것도 실패다');
    expect(entry.failure, contains('not found'));
    expect(entry.duration, isNotNull, reason: '멈춘 채로 남지 않는다');
  });

  test('a command in flight is running until it answers', () async {
    final log = CommandLog();
    final gate = Completer<ProcessResult>();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) => gate.future,
    );

    final pending = run('git', ['fetch']);
    await Future<void>.delayed(Duration.zero);

    expect(log.entries.single.state, CommandLogState.running);
    expect(log.runningCount, 1);

    gate.complete(ok());
    await pending;

    expect(log.entries.single.state, CommandLogState.ok);
    expect(log.runningCount, 0);
  });

  test('an action names itself first and adopts what it runs', () async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async => ok(),
    );

    await log.action('브랜치 체크아웃 — lane', () async {
      await run('git', ['checkout', 'lane']);
      await run('git', ['status']);
    });
    // 아무도 시키지 않은 일 — 감시자의 폴링은 이름 아래로 들어가지 않는다.
    await run('git', ['rev-parse', 'HEAD']);

    final action = log.entries.first;
    expect(action.kind, CommandLogKind.action);
    expect(action.label, '브랜치 체크아웃 — lane');
    expect(log.entries.skip(1).map((entry) => entry.actionId).toList(), [
      action.id,
      action.id,
      null,
    ]);
  });

  test('two actions at once keep their own commands', () async {
    final log = CommandLog();
    final gates = <String, Completer<ProcessResult>>{};
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) =>
          (gates[arguments.first] = Completer<ProcessResult>()).future,
    );

    final first = log.action('Pull', () => run('git', ['pull']));
    final second = log.action('Fetch', () => run('git', ['fetch']));
    await Future<void>.delayed(Duration.zero);
    gates['pull']!.complete(ok());
    gates['fetch']!.complete(ok());
    await Future.wait([first, second]);

    final actions = {
      for (final entry in log.entries)
        if (entry.kind == CommandLogKind.action) entry.label: entry.id,
    };
    final commands = {
      for (final entry in log.entries)
        if (entry.kind == CommandLogKind.command)
          entry.arguments.first: entry.actionId,
    };
    expect(commands['pull'], actions['Pull']);
    expect(commands['fetch'], actions['Fetch'], reason: '동시에 돌아도 섞이지 않는다');
  });

  test('the keychain never gives the console its answer', () async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ok('ghp_realsecrettoken\n', 'ghp_realsecrettoken\n'),
    );

    await run('/usr/bin/security', [
      'add-generic-password',
      '-s',
      'yogit',
      '-w',
      'ghp_realsecrettoken',
    ]);

    final entry = log.entries.single;
    expect(entry.redacted, isTrue);
    expect(entry.stdout, isEmpty, reason: '표준출력이 곧 토큰이다');
    expect(entry.stderr, isEmpty);
    expect(entry.commandLine, isNot(contains('ghp_realsecrettoken')));
    expect(entry.commandLine, contains('••••••'));
    expect(entry.exitCode, 0, reason: '무엇이 돌았는지는 남는다');
  });

  test('a keychain command that fails hides its output too', () async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 44, 'ghp_realsecrettoken', 'ghp_realsecrettoken'),
    );

    await run('/usr/bin/security', ['find-generic-password', '-w']);

    expect(log.entries.single.state, CommandLogState.failed);
    expect(log.entries.single.stdout, isEmpty);
    expect(log.entries.single.stderr, isEmpty);
  });

  test(
    'a diff bigger than the console keeps its head and its weight',
    () async {
      final log = CommandLog(outputLimit: 16);
      final patch = utf8.encode('x' * 100);
      final run = log.wrapRaw(
        (executable, arguments, {workingDirectory}) async => ok(patch),
      );

      await run('git', ['diff']);

      final entry = log.entries.single;
      expect(entry.stdout, 'x' * 16);
      expect(entry.droppedStdoutBytes, 84);
    },
  );

  test('a long text answer is measured in bytes as well', () async {
    final log = CommandLog(outputLimit: 4);
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          ok('가나다라마'),
    );

    await run('git', ['log']);

    expect(log.entries.single.stdout, '가나다라');
    expect(log.entries.single.droppedStdoutBytes, 3, reason: '한 글자는 세 바이트다');
  });

  test('a thrown keychain command tells nothing it was hiding', () async {
    final log = CommandLog();
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async =>
          throw const ProcessException('/usr/bin/security', [
            'add-generic-password',
            '-w',
            'ghp_realsecrettoken',
          ], 'No such file or directory'),
    );

    await expectLater(
      run('/usr/bin/security', [
        'add-generic-password',
        '-w',
        'ghp_realsecrettoken',
      ]),
      throwsA(isA<ProcessException>()),
    );

    // ProcessException은 자기 명령줄을 통째로 인쇄한다 — 가린 인자가 그리로
    // 돌아오면 가린 의미가 없다.
    final entry = log.entries.single;
    expect(entry.failure, isNot(contains('ghp_realsecrettoken')));
    expect(entry.failure, 'No such file or directory');
  });

  test('an action is done when its work is done', () async {
    final log = CommandLog();

    await log.action('Pull', () async {});

    final entry = log.entries.single;
    expect(entry.state, CommandLogState.ok);
    expect(log.runningCount, 0, reason: '끝난 액션이 실행 중으로 남으면 개수가 계속 는다');
  });

  test('an action that threw is a failed line, and still throws', () async {
    final log = CommandLog();

    await expectLater(
      log.action('Push', () async => throw Exception('rejected')),
      throwsException,
    );

    expect(log.entries.single.state, CommandLogState.failed);
    expect(log.entries.single.failure, contains('rejected'));
  });

  test('a command outliving its action name is set loose', () async {
    final log = CommandLog(limit: 2);
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async => ok(),
    );

    await log.action('Rebase', () async {
      await run('git', ['rebase']);
      await run('git', ['status']);
    });

    // 이름이 먼저 밀려났다. 남은 명령이 없는 줄을 가리키고 있으면 안 된다.
    expect(log.entries.map((entry) => entry.kind), [
      CommandLogKind.command,
      CommandLogKind.command,
    ]);
    expect(log.entries.map((entry) => entry.actionId), [null, null]);
  });

  test('the console forgets its oldest line to keep the newest', () async {
    final log = CommandLog(limit: 3);
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async => ok(),
    );

    for (var index = 0; index < 5; index++) {
      await run('git', ['status', '$index']);
    }

    expect(log.entries, hasLength(3));
    expect(log.entries.first.arguments.last, '2');
    expect(log.entries.last.arguments.last, '4');
  });

  test('a listener hears the line arrive and the line settle', () async {
    final log = CommandLog();
    var beats = 0;
    log.addListener(() => beats++);
    final run = log.wrap(
      (executable, arguments, {workingDirectory, environment}) async => ok(),
    );

    await run('git', ['status']);

    expect(beats, 2, reason: '시작할 때 한 번, 끝날 때 한 번');
  });
}
