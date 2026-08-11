import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/local_state_signature.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/timeline_palette.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// docs/local-change-summary-mockup.html — 밖에서 바뀐 저장소를 설명하는 알림.
/// 요약 한 줄과 오간 커밋 목록을 들고, 읽을 때까지 머문다.
class _ChangingRepository extends FakeGitRepository {
  _ChangingRepository(super.loader, {required super.refs});

  var signature =
      'main-tip\nrefs/heads/main\nrefs/heads/main main-tip';

  String operation = 'pull';
  ({int outgoing, int incoming})? counts = (outgoing: 0, incoming: 3);
  List<MovedCommit> moved = const [
    (
      incoming: true,
      shortSha: '89a61cb',
      subject: 'feat: let a remote branch stand as the base to rebase onto',
    ),
    (
      incoming: true,
      shortSha: '06fdbd1',
      subject: 'test: pin the origin/HEAD drop against real git output',
    ),
    (
      incoming: true,
      shortSha: '954e6e8',
      subject: 'fix: stop drawing origin/HEAD as if it were a branch',
    ),
  ];

  @override
  Future<String?> loadLocalStateSignature() async => signature;

  @override
  Future<String?> loadBranchOperation(String branch) async => operation;

  @override
  Future<({int outgoing, int incoming})?> countMovedCommits(
    String before,
    String after,
  ) async => counts;

  @override
  Future<List<MovedCommit>> loadMovedCommits(
    String before,
    String after, {
    int limit = 9,
  }) async => moved.take(limit).toList();

  /// 밖에서 무언가 벌어진 척한다.
  void moveMain(String tip) =>
      signature = '$tip\nrefs/heads/main\nrefs/heads/main $tip';
}

void main() {
  _mockupParity();
  late _ChangingRepository repository;

  Future<void> pump(WidgetTester tester, {String? startingAt}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    repository = _ChangingRepository(
      (_, _) async => [
        commit('main-tip', 'tip', parents: ['root']),
        commit('root', 'the beginning'),
      ],
      refs: const RepoRefs(
        local: ['main'],
        current: 'main',
        tips: {'main': 'main-tip'},
      ),
    );
    if (startingAt != null) repository.signature = startingAt;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository,
          controller: WindowFrameController(
            channel: const MethodChannel('test/yogit-window'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 감시자가 다음 차례에 발견하도록 둔다.
  Future<void> changeOutside(WidgetTester tester, {String tip = 'new-tip'}) async {
    repository.moveMain(tip);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    // HEAD가 움직인 변화는 먼저 물어본다 — 새로 읽겠다고 답해야 알림이 선다.
    final refresh = find.byKey(const Key('local-change-refresh'));
    if (refresh.evaluate().isNotEmpty) {
      await tester.tap(refresh);
      await tester.pumpAndSettle();
    }
  }

  Finder notice() => find.byKey(const Key('local-change-notice'));
  Finder headline() => find.byKey(const Key('local-change-notice-headline'));

  testWidgets('요약과 오간 커밋을 함께 말한다', (tester) async {
    await pump(tester);
    await changeOutside(tester);

    expect(notice(), findsOneWidget);
    expect(
      tester.widget<Text>(headline()).data,
      'main · pull · 커밋 3개 들어옴',
    );
    expect(find.textContaining('feat: let a remote branch stand'), findsOneWidget);
    expect(find.textContaining('test: pin the origin/HEAD drop'), findsOneWidget);
    expect(find.textContaining('fix: stop drawing origin/HEAD'), findsOneWidget);
  });

  testWidgets('계약 1 — 스스로 사라지지 않는다', (tester) async {
    await pump(tester);
    await changeOutside(tester);
    expect(notice(), findsOneWidget);

    // 스낵바라면 진작 물러났을 시간이다.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(notice(), findsOneWidget);
  });

  testWidgets('계약 1 — esc로 닫힌다', (tester) async {
    await pump(tester);
    await changeOutside(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(notice(), findsNothing);
  });

  testWidgets('계약 2 — 바깥 클릭은 닫되 가로채지 않는다', (tester) async {
    await pump(tester);
    await changeOutside(tester);

    // 아래 행을 누른다. 알림은 닫히고, 그 행은 선택된다.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.text('the beginning'),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(notice(), findsNothing);
    expect(find.byKey(const Key('selected-row-root')), findsOneWidget);
  });

  testWidgets('계약 3 — esc는 알림부터 닫는다', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-panel')), findsOneWidget);

    await changeOutside(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(notice(), findsNothing, reason: '알림이 먼저 닫힌다');
    expect(
      find.byKey(const Key('preview-panel')),
      findsOneWidget,
      reason: '미리보기는 그다음 차례다',
    );
  });

  testWidgets('계약 4 — 새 변화가 오면 갈린다', (tester) async {
    await pump(tester);
    await changeOutside(tester);

    repository.operation = 'reset';
    repository.counts = (outgoing: 2, incoming: 0);
    repository.moved = const [
      (incoming: false, shortSha: 'aaa1111', subject: 'refactor: gone'),
    ];
    await changeOutside(tester, tip: 'newer-tip');

    expect(notice(), findsOneWidget, reason: '쌓이지 않는다');
    expect(
      tester.widget<Text>(headline()).data,
      'main · reset · 커밋 2개 물러남',
    );
  });

  testWidgets('계약 5 — 여덟 줄까지, 나머지는 세어 말한다', (tester) async {
    await pump(tester);
    // 시안의 '많이 오갔을 때' 카드를 그대로 세워 본다.
    repository.counts = (outgoing: 0, incoming: 42);
    repository.moved = [
      for (var index = 0; index < 12; index++)
        (
          incoming: true,
          shortSha: 'c00000$index',
          subject: 'feat: number $index',
        ),
    ];
    await changeOutside(tester);

    expect(find.textContaining('feat: number 7'), findsOneWidget);
    expect(find.textContaining('feat: number 8'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('local-change-notice-more'))).data,
      '외 34개',
    );
  });

  testWidgets('계약 6 — 알아내지 못하면 sha 두 개로 물러난다', (tester) async {
    await pump(tester);
    repository.operation = '';
    repository.counts = null;
    repository.moved = const [];
    await changeOutside(tester);

    expect(
      tester.widget<Text>(headline()).data,
      'main 갱신됨 · main-tip → new-tip',
    );
  });

  testWidgets('브랜치가 여럿 움직이면 브랜치마다 한 줄씩', (tester) async {
    await pump(tester);
    // main은 움직이고, 다른 브랜치는 생기고 사라졌다.
    repository.signature =
        'moved-tip\nrefs/heads/main\n'
        'refs/heads/main moved-tip\nrefs/heads/fresh fresh-tip';
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    final refresh = find.byKey(const Key('local-change-refresh'));
    if (refresh.evaluate().isNotEmpty) {
      await tester.tap(refresh);
      await tester.pumpAndSettle();
    }

    expect(
      tester.widget<Text>(headline()).data,
      'main · pull · 커밋 3개 들어옴',
      reason: '첫 줄은 움직인 브랜치가 무엇을 했는지 말한다',
    );
    expect(find.text('fresh 브랜치 추가됨'), findsOneWidget);
    // 여럿이 움직였으면 커밋 목록은 접는다 — 어느 브랜치인지가 먼저다.
    expect(find.textContaining('feat: let a remote branch stand'), findsNothing);
  });

  testWidgets('한 번에 여럿을 지우면 세어서 말한다', (tester) async {
    // 넷이 있는 상태에서 시작해, 한 번에 사라지게 한다.
    await pump(
      tester,
      startingAt:
          'main-tip\nrefs/heads/main\nrefs/heads/main main-tip'
          '\nrefs/heads/a a\nrefs/heads/b b\nrefs/heads/c c\nrefs/heads/d d',
    );
    repository.signature =
        'main-tip\nrefs/heads/main\nrefs/heads/main main-tip';
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    // 네 줄이 아니라 한 줄로 센다 — 이름을 나열하는 한계와 같은 선이다.
    expect(tester.widget<Text>(headline()).data, '브랜치 4개 삭제됨');
  });

  testWidgets('나간 커밋과 들어온 커밋을 갈라 보인다', (tester) async {
    await pump(tester);
    repository.operation = 'rebase';
    repository.counts = (outgoing: 1, incoming: 1);
    repository.moved = const [
      (incoming: false, shortSha: 'aaa1111', subject: 'refactor: the old one'),
      (incoming: true, shortSha: 'bbb2222', subject: 'refactor: the new one'),
    ];
    await changeOutside(tester);

    expect(
      tester.widget<Text>(headline()).data,
      'main · rebase · 커밋 1개 나가고 1개 들어옴',
    );
    expect(find.text('−'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
  });
}

/// 시안(docs/local-change-summary-mockup.html)이 그린 값들을 하나씩 대조한다.
/// 문구가 맞아도 색과 자리가 다르면 다른 물건이다.
void _mockupParity() {
  testWidgets('시안과 같은 자리, 같은 치수', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final repository = _ChangingRepository(
      (_, _) async => [
        commit('main-tip', 'tip', parents: ['root']),
        commit('root', 'the beginning'),
      ],
      refs: const RepoRefs(
        local: ['main'],
        current: 'main',
        tips: {'main': 'main-tip'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository,
          controller: WindowFrameController(
            channel: const MethodChannel('test/yogit-window'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repository.moveMain('new-tip');
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    final refresh = find.byKey(const Key('local-change-refresh'));
    if (refresh.evaluate().isNotEmpty) {
      await tester.tap(refresh);
      await tester.pumpAndSettle();
    }

    final card = tester.getRect(find.byKey(const Key('local-change-notice')));
    final screen = tester.getRect(find.byType(MaterialApp));

    // 왼쪽 아래, 상태 표시줄 위 — 시안의 마지막 그림 그대로.
    expect(card.left, 16);
    expect(screen.bottom - card.bottom, 29 + 16);
    // 시안이 잡은 너비: 최소 380, 최대 640.
    expect(card.width, greaterThanOrEqualTo(420));
    expect(card.width, lessThanOrEqualTo(640));

    // 나가는 길을 보여 준다.
    expect(find.text('esc'), findsOneWidget);
    expect(find.text('닫기'), findsOneWidget);
    // 눌러도 닫힌다 — 키보드만의 길이 아니다.
    await tester.tap(find.byKey(const Key('local-change-notice-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-change-notice')), findsNothing);
  });

  testWidgets('시안과 같은 색', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final repository = _ChangingRepository(
      (_, _) async => [
        commit('main-tip', 'tip', parents: ['root']),
        commit('root', 'the beginning'),
      ],
      refs: const RepoRefs(
        local: ['main'],
        current: 'main',
        tips: {'main': 'main-tip'},
      ),
    )
      ..operation = 'rebase'
      ..counts = (outgoing: 1, incoming: 1)
      ..moved = const [
        (incoming: false, shortSha: 'aaa1111', subject: 'refactor: the old one'),
        (incoming: true, shortSha: 'bbb2222', subject: 'refactor: the new one'),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          repository: repository,
          controller: WindowFrameController(
            channel: const MethodChannel('test/yogit-window'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repository.moveMain('new-tip');
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    final refresh = find.byKey(const Key('local-change-refresh'));
    if (refresh.evaluate().isNotEmpty) {
      await tester.tap(refresh);
      await tester.pumpAndSettle();
    }

    // 들어온 것은 초록, 나간 것은 붉게 — 시안의 두 색 그대로.
    expect(tester.widget<Text>(find.text('+')).style!.color, mainAccent);
    expect(tester.widget<Text>(find.text('−')).style!.color, deletedPink);
    // 짧은 sha는 타임라인이 해시에 쓰는 그 색, 그 고정폭 글자다.
    final sha = tester.widget<Text>(find.text('bbb2222'));
    expect(sha.style!.color, hashRed);
    expect(sha.style!.fontFamily, 'monospace');
    // 나간 커밋은 한 겹 물러나 보인다.
    final outgoing = tester.widget<Text>(
      find.text('refactor: the old one'),
    );
    final incoming = tester.widget<Text>(
      find.text('refactor: the new one'),
    );
    expect(outgoing.style!.color!.a, lessThan(incoming.style!.color!.a));
  });
}
