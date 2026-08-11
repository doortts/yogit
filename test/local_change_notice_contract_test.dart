import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/local_state_signature.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/timeline_palette.dart';
import 'package:yogit/window_frame.dart';
import 'package:yogit/yogit_alert.dart';

import 'app_test.dart' show FakeGitRepository, commit;

/// docs/local-change-summary-mockup.html — 밖에서 저장소가 바뀌면, 무엇이
/// 바뀌었는지를 먼저 보이고 그다음에 새로 읽을지 묻는다. 근거 없이 답하게 하지
/// 않는다. 묻지 않는 변화(삭제만)는 머무는 카드로 말한다.
class _ChangingRepository extends FakeGitRepository {
  _ChangingRepository(super.loader, {required super.refs});

  var signature = 'main-tip\nrefs/heads/main\nrefs/heads/main main-tip';

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
}

void main() {
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

  /// 밖에서 무언가 벌어지고, 감시자가 그것을 발견하게 둔다.
  Future<void> changeOutside(WidgetTester tester, String signature) async {
    repository.signature = signature;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
  }

  /// HEAD가 움직인 변화 — 묻는 쪽이다.
  Future<void> moveHead(WidgetTester tester, {String tip = 'new-tip'}) =>
      changeOutside(tester, '$tip\nrefs/heads/main\nrefs/heads/main $tip');

  /// 브랜치가 사라지기만 한 변화 — 묻지 않는 쪽이다.
  Future<void> deleteOutside(WidgetTester tester) => changeOutside(
    tester,
    'main-tip\nrefs/heads/main\nrefs/heads/main main-tip',
  );

  const withGone =
      'main-tip\nrefs/heads/main\n'
      'refs/heads/main main-tip\nrefs/heads/gone gone-tip';

  Finder ask() => find.text('새로 읽어올까요?');
  Finder headline() => find.byKey(const Key('local-change-notice-headline'));
  Finder card() => find.byKey(const Key('local-change-notice'));

  // ── 묻는 쪽 ──────────────────────────────────────────────────────
  testWidgets('계약 1 — 묻기 전에 무엇이 바뀌었는지 보인다', (tester) async {
    await pump(tester);
    await moveHead(tester);

    expect(find.text('저장소가 밖에서 바뀌었습니다'), findsOneWidget);
    expect(tester.widget<Text>(headline()).data, 'main · pull · 커밋 3개 들어옴');
    expect(
      find.textContaining('feat: let a remote branch stand'),
      findsOneWidget,
    );
    expect(find.textContaining('test: pin the origin/HEAD drop'), findsOneWidget);
    expect(find.textContaining('fix: stop drawing origin/HEAD'), findsOneWidget);
    expect(ask(), findsOneWidget);
  });

  testWidgets('계약 2 — 물음은 목록 아래에 온다', (tester) async {
    await pump(tester);
    await moveHead(tester);

    // 읽고 나서 답하는 순서다. 물음이 먼저 오면 근거는 뒤늦은 변명이 된다.
    expect(
      tester.getRect(ask()).top,
      greaterThan(tester.getRect(headline()).bottom),
    );
    expect(
      tester.getRect(find.byKey(const Key('local-change-refresh'))).top,
      greaterThan(tester.getRect(ask()).bottom),
    );
  });

  testWidgets('답하고 나면 같은 말을 또 하지 않는다', (tester) async {
    await pump(tester);
    await moveHead(tester);

    await tester.tap(find.byKey(const Key('local-change-refresh')));
    await tester.pumpAndSettle();

    expect(card(), findsNothing, reason: '물음이 이미 다 말했다');
  });

  testWidgets('계약 6 — 나중에를 누르면 같은 상태를 다시 묻지 않는다', (tester) async {
    await pump(tester);
    await moveHead(tester);

    await tester.tap(find.byKey(const Key('local-change-dismiss')));
    await tester.pumpAndSettle();
    expect(ask(), findsNothing);

    // 저장소는 그대로다. 같은 읽기로 다시 붙잡지 않는다.
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(ask(), findsNothing);
  });

  testWidgets('계약 3 — 여덟 줄까지, 나머지는 세어 말한다', (tester) async {
    await pump(tester);
    repository.counts = (outgoing: 0, incoming: 42);
    repository.moved = [
      for (var index = 0; index < 12; index++)
        (
          incoming: true,
          shortSha: 'c00000$index',
          subject: 'feat: number $index',
        ),
    ];
    await moveHead(tester);

    expect(find.textContaining('feat: number 7'), findsOneWidget);
    expect(find.textContaining('feat: number 8'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('local-change-notice-more')))
          .data,
      '외 34개',
    );
  });

  testWidgets('계약 4 — 브랜치가 여럿이면 브랜치마다 한 줄', (tester) async {
    await pump(tester);
    await changeOutside(
      tester,
      'moved-tip\nrefs/heads/main\n'
      'refs/heads/main moved-tip\nrefs/heads/fresh fresh-tip',
    );

    expect(tester.widget<Text>(headline()).data, 'main · pull · 커밋 3개 들어옴');
    expect(find.text('fresh 브랜치 추가됨'), findsOneWidget);
    // 커밋 목록은 접는다 — 어느 브랜치인지가 먼저다.
    expect(find.textContaining('feat: let a remote branch stand'), findsNothing);
  });

  testWidgets('계약 5 — 알아내지 못해도 묻기를 그만두지 않는다', (tester) async {
    await pump(tester);
    repository.operation = '';
    repository.counts = null;
    repository.moved = const [];
    await moveHead(tester);

    expect(
      tester.widget<Text>(headline()).data,
      'main 갱신됨 · main-tip → new-tip',
    );
    expect(ask(), findsOneWidget);
  });

  testWidgets('나간 커밋과 들어온 커밋을 갈라 보인다', (tester) async {
    await pump(tester);
    repository.operation = 'rebase';
    repository.counts = (outgoing: 1, incoming: 1);
    repository.moved = const [
      (incoming: false, shortSha: 'aaa1111', subject: 'refactor: the old one'),
      (incoming: true, shortSha: 'bbb2222', subject: 'refactor: the new one'),
    ];
    await moveHead(tester);

    expect(
      tester.widget<Text>(headline()).data,
      'main · rebase · 커밋 1개 나가고 1개 들어옴',
    );
    expect(tester.widget<Text>(find.text('+')).style!.color, mainAccent);
    expect(tester.widget<Text>(find.text('−')).style!.color, deletedPink);
    final sha = tester.widget<Text>(find.text('bbb2222'));
    expect(sha.style!.color, hashRed);
    expect(sha.style!.fontFamily, 'monospace');
    // 나간 커밋은 한 겹 물러나 보인다.
    expect(
      tester.widget<Text>(find.text('refactor: the old one')).style!.color!.a,
      lessThan(
        tester.widget<Text>(find.text('refactor: the new one')).style!.color!.a,
      ),
    );
  });

  testWidgets('묻는 상자는 넓어져도 버튼은 그대로, 그리고 가운데', (tester) async {
    await pump(tester);
    await moveHead(tester);

    final title = tester.getRect(find.text('저장소가 밖에서 바뀌었습니다'));
    final later = tester.getRect(find.byKey(const Key('local-change-dismiss')));
    final refresh = tester.getRect(
      find.byKey(const Key('local-change-refresh')),
    );

    // 상자는 목록을 담느라 넓어졌지만, 답이 그만큼 커질 이유는 없다.
    expect(title.width, greaterThan(YogitAlert.width - 32));
    expect(later.width + refresh.width, closeTo(YogitAlert.width - 32 - 7, 1));
    expect(later.width, closeTo(refresh.width, 1));
    // 답하는 자리는 물음 아래 가운데다. 한쪽으로 몰리면 상자가 기운 것처럼 읽힌다.
    expect(
      (later.left + refresh.right) / 2,
      closeTo(title.center.dx, 1),
    );
  });

  // ── 묻지 않는 쪽 ────────────────────────────────────────────────
  testWidgets('계약 7 — 삭제만 있는 변화는 머무는 카드로 말한다', (tester) async {
    await pump(tester, startingAt: withGone);
    await deleteOutside(tester);

    expect(ask(), findsNothing, reason: '잃을 것이 없어 묻지 않는다');
    expect(card(), findsOneWidget);
    expect(tester.widget<Text>(headline()).data, 'gone 브랜치 삭제됨');

    // 스낵바라면 진작 물러났을 시간이다.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(card(), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(card(), findsNothing);
  });

  testWidgets('카드 바깥 클릭은 닫되 가로채지 않는다', (tester) async {
    await pump(tester, startingAt: withGone);
    await deleteOutside(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('timeline-list')),
        matching: find.text('the beginning'),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(card(), findsNothing);
    expect(find.byKey(const Key('selected-row-root')), findsOneWidget);
  });

  testWidgets('카드는 뒤의 역사가 비치도록 선다', (tester) async {
    await pump(tester, startingAt: withGone);
    await deleteOutside(tester);

    final panel = tester.widget<Container>(card()).decoration! as BoxDecoration;
    expect(panel.color!.a, lessThan(1.0));
    expect(
      find.ancestor(of: card(), matching: find.byType(BackdropFilter)),
      findsOneWidget,
      reason: '비치되 읽히려면 뒤가 흐려져야 한다',
    );
    // 방금 답한 물음이 서 있던 자리 — 화면 한가운데다.
    final rect = tester.getRect(card());
    final screen = tester.getRect(find.byType(MaterialApp));
    expect(rect.center.dx, closeTo(screen.center.dx, 0.5));
    expect(rect.center.dy, closeTo(screen.center.dy, 0.5));
  });
}
