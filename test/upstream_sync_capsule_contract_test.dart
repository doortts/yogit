import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/upstream_sync.dart';
import 'package:yogit/upstream_sync_capsule.dart';

/// docs/upstream-sync-mockup.html의 캡슐 계약: 동기화면 점 하나, 단독 상태는
/// 동사 하나, 재는 동안은 무채색, 어긋나면 두 동사가 같은 판정을 입는다.
/// Pull은 즉시, Push는 확인으로, 빨강은 실행 없이 해결 흐름으로.
void main() {
  var pulls = 0;
  var pushes = 0;
  var resolves = 0;

  setUp(() {
    pulls = 0;
    pushes = 0;
    resolves = 0;
  });

  Future<void> pump(
    WidgetTester tester,
    UpstreamSyncState state, {
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: UpstreamSyncCapsule(
              state: state,
              enabled: enabled,
              onPull: () => pulls++,
              onPush: () => pushes++,
              onResolveConflict: () => resolves++,
            ),
          ),
        ),
      ),
    );
  }

  UpstreamSyncState state(
    UpstreamSyncKind kind, {
    int ahead = 0,
    int behind = 0,
    List<String> conflictFiles = const [],
    DateTime? measuredAt,
    DateTime? checkedAt,
  }) => UpstreamSyncState(
    kind: kind,
    branch: 'main',
    remote: 'origin',
    upstreamRef: 'origin/main',
    ahead: ahead,
    behind: behind,
    localTip: 'aaa',
    remoteTip: 'bbb',
    conflictFiles: conflictFiles,
    measuredAt: measuredAt,
    checkedAt: checkedAt,
  );

  Text textOf(WidgetTester tester, Key key) => tester.widget<Text>(
    find.descendant(of: find.byKey(key), matching: find.byType(Text)),
  );

  testWidgets('hidden leaves no trace, synced leaves one dot', (tester) async {
    await pump(tester, UpstreamSyncState.none);
    expect(find.byKey(const Key('upstream-sync-capsule')), findsNothing);

    await pump(
      tester,
      state(UpstreamSyncKind.synced, checkedAt: DateTime(2026, 8, 12, 10)),
    );
    expect(find.byKey(const Key('upstream-sync-dot')), findsOneWidget);
    expect(find.byKey(const Key('upstream-sync-pull')), findsNothing);
    expect(find.byKey(const Key('upstream-sync-push')), findsNothing);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('upstream-sync-dot')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, contains('origin/main 브랜치와 같습니다'));
    expect(tooltip.message, contains('확인'), reason: '언제 확인했는지도 말한다');
  });

  testWidgets('a lone side wears one verb, its count, and green', (
    tester,
  ) async {
    await pump(tester, state(UpstreamSyncKind.pushOnly, ahead: 3));
    expect(find.byKey(const Key('upstream-sync-pull')), findsNothing);
    final push = textOf(tester, const Key('upstream-sync-push'));
    expect(push.textSpan!.toPlainText(), '↑ 3\nPush', reason: '개수 위, 동사 아래');
    expect(push.style?.color, const Color(0xFF8AD6A1), reason: '초록 — 그대로 됨');

    await pump(tester, state(UpstreamSyncKind.pullOnly, behind: 2));
    expect(find.byKey(const Key('upstream-sync-push')), findsNothing);
    final pull = textOf(tester, const Key('upstream-sync-pull'));
    expect(pull.textSpan!.toPlainText(), '↓ 2\nPull');
  });

  testWidgets('measuring is colourless and answers no clicks', (tester) async {
    await pump(tester, state(UpstreamSyncKind.measuring, ahead: 3, behind: 2));
    final measuring = find.byKey(const Key('upstream-sync-measuring'));
    expect(measuring, findsOneWidget);
    expect(
      textOf(tester, const Key('upstream-sync-measuring')).data,
      '↓ 2 ↑ 3',
    );
    expect(
      find.descendant(
        of: measuring,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
      reason: '동사 자리에는 답 대신 도는 것이 선다',
    );

    await tester.tap(measuring, warnIfMissed: false);
    await tester.pump();
    expect(pulls + pushes + resolves, 0, reason: '아직 답이 없다');
  });

  testWidgets('a clean divergence wears amber on both verbs', (tester) async {
    await pump(
      tester,
      state(
        UpstreamSyncKind.divergedClean,
        ahead: 3,
        behind: 2,
        measuredAt: DateTime(2026, 8, 12, 10),
      ),
    );

    final pull = textOf(tester, const Key('upstream-sync-pull'));
    final push = textOf(tester, const Key('upstream-sync-push'));
    expect(pull.textSpan!.toPlainText(), '↓ 2\nPull');
    expect(push.textSpan!.toPlainText(), '↑ 3\nPush');
    expect(pull.style?.color, push.style?.color, reason: '두 동사가 같은 판정을 입는다');
    expect(push.style?.color, const Color(0xFFF0A35E), reason: '주황 — 얹으면 됨');
    final pushTip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('upstream-sync-push')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(pushTip.message, contains('받아 얹은 뒤'));
  });

  testWidgets('the verbs speak to their own callbacks', (tester) async {
    await pump(
      tester,
      state(UpstreamSyncKind.divergedClean, ahead: 3, behind: 2),
    );
    await tester.tap(find.byKey(const Key('upstream-sync-pull')));
    expect(pulls, 1);
    await tester.tap(find.byKey(const Key('upstream-sync-push')));
    expect(pushes, 1);
    expect(resolves, 0);
  });

  testWidgets('a conflict opens the resolution flow and runs nothing', (
    tester,
  ) async {
    await pump(
      tester,
      state(
        UpstreamSyncKind.divergedConflict,
        ahead: 3,
        behind: 2,
        conflictFiles: ['lib/a.dart', 'lib/b.dart'],
      ),
    );

    final pull = textOf(tester, const Key('upstream-sync-conflict'));
    expect(pull.textSpan!.toPlainText(), '↓ 2\n충돌 2');
    final resolve = textOf(tester, const Key('upstream-sync-conflict-push'));
    expect(
      resolve.textSpan!.toPlainText(),
      '↑ 3\n해결하기',
      reason: '숫자만 있던 칸도 무엇을 누르는지 말한다',
    );
    expect(
      resolve.style?.color,
      const Color(0xFF4388EE),
      reason: '판정은 빨강이지만 나가는 길은 컨트롤의 파랑이다',
    );
    expect(
      ((resolve.textSpan! as TextSpan).children!.first as TextSpan)
          .style
          ?.color,
      const Color(0xFFFF453A),
      reason: '개수는 판정에 딸린 사실이라 문을 따라 파래지지 않는다',
    );
    expect(pull.style?.color, const Color(0xFFFF453A), reason: '판정은 빨강 그대로');
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('upstream-sync-conflict')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, contains('lib/a.dart'));

    await tester.tap(find.byKey(const Key('upstream-sync-conflict')));
    expect(resolves, 1);
    expect(pulls + pushes, 0, reason: '빨강은 실행이 아니라 문이다');
  });

  testWidgets('a first push says so', (tester) async {
    await pump(
      tester,
      const UpstreamSyncState(
        kind: UpstreamSyncKind.firstPush,
        branch: 'main',
        remote: 'origin',
        localTip: 'aaa',
      ),
    );
    final push = textOf(tester, const Key('upstream-sync-push'));
    expect(push.textSpan!.toPlainText(), '처음\nPush');
    await tester.tap(find.byKey(const Key('upstream-sync-push')));
    expect(pushes, 1);
  });

  testWidgets('a disabled capsule shows the verdict but takes no clicks', (
    tester,
  ) async {
    await pump(
      tester,
      state(UpstreamSyncKind.divergedClean, ahead: 3, behind: 2),
      enabled: false,
    );
    expect(find.byKey(const Key('upstream-sync-push')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('upstream-sync-push')),
      warnIfMissed: false,
    );
    expect(pushes, 0, reason: '브랜치 diff가 도는 동안 두 worktree 흐름을 겹치지 않는다');
  });
}
