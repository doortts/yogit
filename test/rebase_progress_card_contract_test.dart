import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/settings.dart';
import 'package:yogit/timeline.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart'
    show
        FakeGitRepository,
        FakeRebasePreviewSession,
        app,
        branchComparison,
        commit;

/// 리베이스 진행 카드는 좁은 판 안에 선다. 브랜치 이름은 사람이 짓는 것이라
/// 얼마든지 길어질 수 있고, 그 길이가 카드를 깨뜨려서는 안 된다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  testWidgets('긴 브랜치 이름이 진행 표시를 밀어내지 않는다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    const long = 'origin/codex/branch-lane-palette-assignments';
    final comparison = branchComparison(compareRef: long);
    final current = comparison.commits
        .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
        .commit;
    late FakeGitRepository repository;
    repository = FakeGitRepository(
      (_, _) async => [commit('normal', 'normal history')],
      refs: const RepoRefs(
        local: ['main'],
        remote: [long],
        current: 'main',
        tips: {'main': 'main-tip', long: 'feature-tip'},
      ),
      compareBranchesCallback: (_, _) async => comparison,
      simulateRebaseCallback: ({required baseRef, required compareRef}) =>
          Future.value(
            const RebaseCheckResult(status: RebaseCheckStatus.conflicts),
          ),
      openRebasePreviewCallback:
          ({required baseRef, required compareRef}) async =>
              FakeRebasePreviewSession(
                repository,
                RebasePreviewResult(
                  status: RebasePreviewStatus.conflict,
                  baseTip: 'main-tip',
                  compareTip: 'feature-tip',
                  currentCommit: current,
                  completed: 1,
                  total: 6,
                  conflictFiles: const ['lib/settings.dart'],
                ),
              ),
      operationInProgressCallback: () async => true,
      diffBetween: (_, _, _) async => const [],
    );
    await tester.pumpWidget(
      app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('branch-diff-menu-$long')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    // 이름이 아무리 길어도 진행 표시는 제 폭을 지킨다. 밀려나면 글자가 세로로
    // 한 자씩 쌓이고, 그러고도 모자라면 판 밖으로 넘친다.
    final progress = find.text('리베이스 진행 2/6');
    expect(progress, findsOneWidget);
    final painter = TextPainter(
      text: TextSpan(
        text: '리베이스 진행 2/6',
        style: tester.widget<Text>(progress).style,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(
      tester.getSize(progress).width,
      greaterThanOrEqualTo(painter.width - 1),
      reason: '한 줄로 다 보여야 한다',
    );
    expect(tester.takeException(), isNull, reason: '판 밖으로 넘치지 않는다');
  });
}
