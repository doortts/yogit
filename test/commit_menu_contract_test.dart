import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// ↵는 커서가 선 커밋의 메뉴를 연다. ⇧+화살표는 붙어 있는 구간을 잡고, ⌘+클릭은
/// 떨어진 커밋도 집는다 — 무엇을 잡았는지에 따라 메뉴의 어느 줄이 살아 있는지가
/// 갈린다. 고쳐 쓰기가 실제로 무엇을 하는지는 history_rewrite_git_test가 본다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  const refs = RepoRefs(
    local: ['main'],
    current: 'main',
    tips: {'main': '3'},
    localTips: {'main': '3'},
  );

  /// 3 ← 2 ← 1 ← 0, 모두 main 위에 있고 업스트림은 없다. 뿌리 커밋은 다시 쓸 수
  /// 없으니 0을 하나 더 깔아 둔다.
  List<GitCommit> history() => [
    commit('3', 'third', parents: ['2']),
    commit('2', 'second', parents: ['1']),
    commit('1', 'first', parents: ['0']),
    commit('0', 'root'),
  ];

  /// 돌아간 git 명령들과, rebase가 받아 든 todo 파일의 내용.
  Future<(List<List<String>>, List<String>)> pump(WidgetTester tester) async {
    final calls = <List<String>>[];
    final todos = <String>[];
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => history(),
          refs: refs,
          commitMessage: (sha) async => 'commit $sha\n\nbody line\n',
          runner: (executable, arguments, {workingDirectory, environment}) async {
            if (arguments.contains('commit') ||
                arguments.contains('reset') ||
                arguments.contains('rebase')) {
              calls.add(arguments);
            }
            // todo 파일은 rebase가 끝나면 지워지니, 명령이 도는 이 순간에 읽는다.
            final editor = environment?['GIT_SEQUENCE_EDITOR'] ?? '';
            if (editor.startsWith("cp '")) {
              todos.add(
                File(editor.substring(4, editor.length - 1)).readAsStringSync(),
              );
            }
            return ProcessResult(1, 0, '', '');
          },
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    return (calls, todos);
  }

  Future<void> pressEnter(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  Future<void> shiftDown(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<PopupMenuItem<String>>(find.byKey(Key(key))).enabled;

  testWidgets('Enter opens the cursor commit menu instead of the preview', (
    tester,
  ) async {
    await pump(tester);
    await pressEnter(tester);

    expect(find.byKey(const Key('preview-surface')), findsNothing);
    // 커서는 HEAD 위에 있다 — 제 브랜치로 체리픽할 수는 없고, 메시지는 고칠 수 있다.
    expect(enabled(tester, 'commit-menu-cherry-pick'), isFalse);
    expect(enabled(tester, 'commit-menu-reword'), isTrue);
  });

  testWidgets('the preview toggle moved to ⌘]', (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('preview-surface')), findsOneWidget);
  });

  testWidgets('rewording HEAD amends the message only', (tester) async {
    final (calls, todos) = await pump(tester);
    await pressEnter(tester);
    await tester.tap(find.byKey(const Key('commit-menu-reword')));
    await tester.pumpAndSettle();

    // 대화창은 지금 메시지를 그대로 들고 열린다.
    expect(
      tester.widget<TextField>(find.byKey(const Key('commit-message-field'))).controller?.text,
      'commit 3\n\nbody line',
    );
    await tester.enterText(
      find.byKey(const Key('commit-message-field')),
      'third, said better',
    );
    await tester.tap(find.byKey(const Key('commit-message-confirm')));
    await tester.pumpAndSettle();

    expect(calls, [
      [
        '-c',
        'core.editor=true',
        'commit',
        '--amend',
        '--only',
        '-m',
        'third, said better\n',
      ],
    ]);
  });

  testWidgets('⇧+arrow marks a run and the menu offers the squash', (
    tester,
  ) async {
    await pump(tester);
    await shiftDown(tester);
    await pressEnter(tester);

    expect(find.text('커밋 2개 합치기'), findsOneWidget);
    expect(enabled(tester, 'commit-menu-squash'), isTrue);
    expect(enabled(tester, 'commit-menu-reorder'), isTrue);
    // 여러 개를 잡으면 한 커밋만의 항목은 메뉴에서 빠진다.
    expect(find.byKey(const Key('commit-menu-reword')), findsNothing);

    await tester.tap(find.byKey(const Key('commit-menu-squash')));
    await tester.pumpAndSettle();

    // 이어 붙인 메시지가 대화창에 오래된 것부터 들어온다.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('commit-message-field')))
          .controller
          ?.text,
      'commit 2\n\nbody line\n\ncommit 3\n\nbody line',
    );
  });

  testWidgets('⌘-click picks commits apart and only the squash goes quiet', (
    tester,
  ) async {
    await pump(tester);
    // 커서는 3에 있다. ⌘로 1을 집으면 2를 건너뛴 선택이 된다.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.tap(find.text('first'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();
    await pressEnter(tester);

    expect(find.text('커밋 2개 버리기'), findsOneWidget);
    // 끊긴 선택은 합칠 수도, 뒤집을 수도 없다 — 사이에 남을 커밋을 어디로 보낼지
    // 정해 줄 사람이 없다.
    expect(enabled(tester, 'commit-menu-squash'), isFalse);
    expect(enabled(tester, 'commit-menu-reorder'), isFalse);
    // 버리기와 되돌리기는 떨어져 있어도 된다.
    expect(enabled(tester, 'commit-menu-drop'), isTrue);
    expect(enabled(tester, 'commit-menu-revert'), isTrue);
  });

  testWidgets('a single commit menu carries the whole set of one-commit items', (
    tester,
  ) async {
    await pump(tester);
    await pressEnter(tester);

    for (final key in [
      'commit-menu-reword',
      'commit-menu-identity',
      'commit-menu-branch',
      'commit-menu-copy-sha',
      'commit-menu-revert',
      'commit-menu-drop',
    ]) {
      expect(enabled(tester, key), isTrue, reason: key);
    }
    // 옮길 다른 브랜치가 없으면 그 항목만 흐려진다.
    expect(enabled(tester, 'commit-menu-rebase-onto'), isFalse);
  });

  testWidgets('the branch dialog names the commit it will point at', (
    tester,
  ) async {
    await pump(tester);
    await pressEnter(tester);
    await tester.tap(find.byKey(const Key('commit-menu-branch')));
    await tester.pumpAndSettle();

    expect(find.text('3 third'), findsOneWidget);
    expect(find.byKey(const Key('commit-branch-field')), findsOneWidget);
  });
}
