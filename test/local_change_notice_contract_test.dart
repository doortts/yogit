import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/local_state_signature.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/timeline_palette.dart';
import 'package:yogit/timeline_theme.dart';
import 'package:yogit/window_frame.dart';
import 'package:yogit/yogit_alert.dart';

import 'app_test.dart' show FakeGitRepository, commit;
import 'package:yogit/typography.dart';

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

  Future<void> pump(
    WidgetTester tester, {
    String? startingAt,
    bool autoReload = false,
    Size size = const Size(1400, 900),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
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
          autoReloadExternalChanges: autoReload,
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
  Finder more() => find.byKey(const Key('local-change-notice-more'));

  Finder folded() => find.byKey(const Key('local-change-notice-folded'));

  /// 세기만 하던 자리가 이제 누를 자리라, 글자는 그 안에 있다.
  String? moreLabel(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: more(), matching: find.byType(Text)))
      .data;

  String? foldedLabel(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: folded(), matching: find.byType(Text)))
      .data;

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
    expect(
      find.textContaining('test: pin the origin/HEAD drop'),
      findsOneWidget,
    );
    expect(
      find.textContaining('fix: stop drawing origin/HEAD'),
      findsOneWidget,
    );
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
    expect(moreLabel(tester), '외 34개');
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
    expect(
      find.textContaining('feat: let a remote branch stand'),
      findsNothing,
    );
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
    expect(sha.style!.fontFamily, technicalFontFamily);
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
    expect((later.left + refresh.right) / 2, closeTo(title.center.dx, 1));
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

  // ── 쌓이는 카드 ─────────────────────────────────────────────────
  // docs/local-change-notice-stack-mockup.html
  testWidgets('쌓기 계약 1 — 읽는 사이에 또 바뀌면 덮지 않고 맨 위에 붙는다', (tester) async {
    await pump(tester, autoReload: true);
    await moveHead(tester, tip: 'first-tip');

    expect(headline(), findsOneWidget);
    expect(
      find.textContaining('feat: let a remote branch stand'),
      findsWidgets,
    );

    repository.operation = 'reset';
    repository.counts = (outgoing: 2, incoming: 0);
    repository.moved = const [
      (incoming: false, shortSha: 'ddd4444', subject: 'chore: the rolled back'),
    ];
    await moveHead(tester, tip: 'second-tip');

    // 앞의 읽음이 살아 있고, 새 읽음이 제 영역으로 붙었다.
    expect(headline(), findsNWidgets(2));
    expect(
      find.textContaining('feat: let a remote branch stand'),
      findsWidgets,
    );
    expect(find.textContaining('chore: the rolled back'), findsOneWidget);
    // 최근 것이 위다 — 방금 온 읽음이 앞의 것보다 높이 선다.
    expect(
      tester.getRect(find.textContaining('chore: the rolled back')).top,
      lessThan(
        tester
            .getRect(find.textContaining('feat: let a remote branch stand'))
            .top,
      ),
    );
    // 머리줄은 쌓인 건수를 센다.
    expect(
      tester
          .widget<Text>(find.byKey(const Key('local-change-notice-count')))
          .data,
      '  ·  2건',
    );
    // 나가는 문은 하나다 — 영역마다 달리지 않는다.
    expect(
      find.byKey(const Key('local-change-notice-dismiss')),
      findsOneWidget,
    );
  });

  testWidgets('쌓기 계약 3 — 다섯을 넘으면 오래된 것부터 접힌다', (tester) async {
    await pump(tester, autoReload: true);
    repository.moved = const [];
    for (var index = 0; index < 7; index++) {
      await moveHead(tester, tip: 'tip-$index');
    }

    expect(headline(), findsNWidgets(5));
    expect(foldedLabel(tester), '이전 2건 보기');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('local-change-notice-count')))
          .data,
      '  ·  7건',
    );
  });

  testWidgets('쌓기 계약 3 — 접힌 것도 눌러서 전부 볼 수 있다', (tester) async {
    await pump(tester, autoReload: true);
    repository.moved = const [];
    for (var index = 0; index < 7; index++) {
      await moveHead(tester, tip: 'tip-$index');
    }
    // 접혀 있는 동안 앞의 둘은 어디에도 서지 않는다.
    expect(headline(), findsNWidgets(5));

    await tester.tap(folded());
    await tester.pumpAndSettle();

    expect(headline(), findsNWidgets(7), reason: '처음 것까지 선다');
    expect(foldedLabel(tester), '접기');

    await tester.tap(folded());
    await tester.pumpAndSettle();
    expect(headline(), findsNWidgets(5));
    expect(foldedLabel(tester), '이전 2건 보기');
  });

  testWidgets('아래쪽을 읽고 있으면 새 읽음이 자리를 밀지 않는다', (tester) async {
    await pump(tester, autoReload: true, size: const Size(1400, 320));
    for (var index = 0; index < 5; index++) {
      await moveHead(tester, tip: 'tip-$index');
    }

    final scroll = tester.widget<Scrollable>(
      find.descendant(of: card(), matching: find.byType(Scrollable)).first,
    );
    final position = scroll.controller!.position;
    expect(position.maxScrollExtent, greaterThan(0), reason: '넘쳐야 굴러간다');
    // 맨 위가 새것이 서는 자리라, 카드는 처음부터 그 위를 보고 있다.
    expect(position.pixels, 0);

    // 위를 보고 있으면 새것은 눈이 이미 있는 자리에 선다.
    await moveHead(tester, tip: 'tip-fresh');
    expect(position.pixels, 0);

    // 아래쪽을 읽고 있으면 위로 끼어든 만큼 자리를 함께 밀어, 읽던 줄이 그대로
    // 남는다. 접힌 것을 펼쳐 두어야 새것이 붙을 때 목록이 실제로 길어진다.
    await tester.tap(folded());
    await tester.pumpAndSettle();
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    final before = position.pixels;
    final extentBefore = position.maxScrollExtent;
    await moveHead(tester, tip: 'tip-later');
    expect(position.maxScrollExtent, greaterThan(extentBefore));
    expect(
      position.pixels,
      closeTo(before + (position.maxScrollExtent - extentBefore), 0.5),
    );
  });

  testWidgets('영역마다 알아챈 뒤 얼마나 지났는지 선다', (tester) async {
    await pump(tester, autoReload: true);
    await moveHead(tester, tip: 'first-tip');

    // 시험의 시계는 가짜라 지난 시간은 늘 '방금'이다. 글자가 어떻게 바뀌는지는
    // noticedAgo가 저 혼자 시험받는다.
    Finder stamp() => find.byKey(const Key('local-change-notice-stamp'));
    expect(tester.widget<Text>(stamp()).data, '방금');

    await moveHead(tester, tip: 'second-tip');
    expect(stamp(), findsNWidgets(2), reason: '영역마다 하나씩');
  });

  testWidgets('묻는 창은 언제였는지 적지 않는다', (tester) async {
    // 답을 기다리는 물음은 방금 온 하나뿐이라 언제였는지가 물음이 되지 않는다.
    await pump(tester);
    await moveHead(tester);

    expect(ask(), findsOneWidget);
    expect(find.byKey(const Key('local-change-notice-stamp')), findsNothing);
  });

  testWidgets('쌓기 계약 5 — esc는 카드 전체를 한 번에 닫는다', (tester) async {
    await pump(tester, autoReload: true);
    await moveHead(tester, tip: 'first-tip');
    await moveHead(tester, tip: 'second-tip');
    expect(card(), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(card(), findsNothing);
  });

  testWidgets('쌓기 계약 7 — 카드는 창을 넘지 않고 제 안에서 구른다', (tester) async {
    await pump(tester, autoReload: true, size: const Size(1400, 420));
    for (var index = 0; index < 5; index++) {
      await moveHead(tester, tip: 'tip-$index');
    }

    final rect = tester.getRect(card());
    // 위아래 24씩 비워 둔 자리 안에 선다 — 창 밖으로 자라지 않는다.
    expect(rect.height, lessThanOrEqualTo(420 - 48 + 0.5));
    expect(rect.top, greaterThanOrEqualTo(23.5));
    expect(
      find.descendant(of: card(), matching: find.byType(Scrollable)),
      findsWidgets,
      reason: '넘친 영역은 카드 안에서 굴러야 한다',
    );
  });

  // ── 눌러서 펼치는 '외 N개' ──────────────────────────────────────
  testWidgets('쌓기 계약 6 — 외 N개를 누르면 전체가 펼쳐지고 접기가 된다', (tester) async {
    await pump(tester, autoReload: true);
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

    expect(find.textContaining('feat: number 8'), findsNothing);
    expect(moreLabel(tester), '외 34개');

    await tester.tap(more());
    await tester.pumpAndSettle();

    expect(find.textContaining('feat: number 8'), findsOneWidget);
    expect(find.textContaining('feat: number 11'), findsOneWidget);
    expect(moreLabel(tester), '접기');

    await tester.tap(more());
    await tester.pumpAndSettle();
    expect(find.textContaining('feat: number 8'), findsNothing);
    expect(moreLabel(tester), '외 34개');
  });

  testWidgets('펼칠 데가 없으면 세기만 한다', (tester) async {
    await pump(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: timelineThemeData(
          ThemeData.dark(),
          TimelineThemeKind.systemGraphite,
        ),
        home: const Material(
          child: LocalChangeDetailsView(
            details: LocalChangeDetails(
              headline: 'main 갱신됨',
              lines: [],
              commits: [],
              more: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(moreLabel(tester), '외 3개');
    expect(
      tester
          .widget<GestureDetector>(
            find.descendant(of: more(), matching: find.byType(GestureDetector)),
          )
          .onTap,
      isNull,
      reason: '불러올 데가 없는 글자는 누를 자리가 아니다',
    );
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
