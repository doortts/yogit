import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/repository_branch_selector.dart';

void main() {
  /// 이름은 고르라고 있는 것이 아니라 지금 어디에 서 있는지 말하려고 있다.
  /// docs/toolbar-selectors-mockup.html의 몫: 저장소 4, 기준 브랜치 4,
  /// 브랜치 diff 3 — 대개 '선택' 두 글자인 칸이 이름의 자리를 가져가지 않는다.
  testWidgets('the names take the width, the comparison gives it up', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 620,
            child: RepositoryBranchSelector(
              repositoryName: 'yogit-desktop-workspace',
              repositoryPath: '/repos/yogit',
              localBranches: const ['feature/search-pill'],
              branchTimes: const {},
              selectedBranch: 'feature/search-pill',
              refsLoading: false,
              refsLoadFailed: false,
              onRepositoryPressed: () {},
              onBranchSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    double widthOf(String key) => tester.getSize(find.byKey(Key(key))).width;

    expect(widthOf('repository-selector'), widthOf('base-branch-selector'));
    expect(
      widthOf('repository-selector'),
      greaterThan(widthOf('branch-diff-selector')),
      reason: '이름 두 칸이 비교 칸보다 넓다',
    );
    // 이 폭이면 이름이 잘리지 않는다 — 잘리던 'yona…'가 시안의 출발점이었다.
    expect(
      tester.getSize(find.text('yogit-desktop-workspace')).width,
      lessThan(widthOf('repository-selector')),
    );
  });

  testWidgets('shows repository and only supplied local branches', (
    tester,
  ) async {
    String? selected;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryBranchSelector(
            repositoryName: 'yogit',
            repositoryPath: '/repos/yogit',
            localBranches: const ['main', 'release'],
            branchTimes: {'main': now - 2 * 60 * 60},
            selectedBranch: 'main',
            refsLoading: false,
            refsLoadFailed: false,
            onRepositoryPressed: () {},
            onBranchSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('저장소'), findsOneWidget);
    expect(find.text('기준 브랜치'), findsOneWidget);
    expect(find.text('yogit'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);

    await tester.tap(find.byKey(const Key('base-branch-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('base-branch-menu-main')), findsOneWidget);
    expect(find.byKey(const Key('base-branch-menu-release')), findsOneWidget);
    expect(find.byKey(const Key('base-branch-menu-remote/main')), findsNothing);
    expect(find.text('브랜치 2개 · 최근 커밋순'), findsOneWidget);

    expect(
      find.descendant(
        of: find.byKey(const Key('base-branch-menu-main')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    // Only the branch with a known tip time carries the second line.
    expect(
      find.descendant(
        of: find.byKey(const Key('base-branch-menu-main')),
        matching: find.text('2시간 전 커밋'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('base-branch-search')), 'rele');
    await tester.pump();
    expect(find.byKey(const Key('base-branch-menu-main')), findsNothing);
    expect(find.byKey(const Key('base-branch-menu-release')), findsOneWidget);

    // Gapped letters find the branch too, without typing it in full.
    await tester.enterText(find.byKey(const Key('base-branch-search')), 'rls');
    await tester.pump();
    expect(find.byKey(const Key('base-branch-menu-main')), findsNothing);
    expect(find.byKey(const Key('base-branch-menu-release')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('base-branch-search')), 'rele');
    await tester.pump();

    await tester.tap(find.byKey(const Key('base-branch-menu-release')));
    await tester.pumpAndSettle();
    expect(selected, 'release');
  });

  test('relative commit labels', () {
    final now = DateTime(2026, 8, 3, 12);
    int at(Duration ago) => now.subtract(ago).millisecondsSinceEpoch ~/ 1000;
    expect(relativeCommitLabel(at(Duration.zero), now), '방금 전 커밋');
    expect(
      relativeCommitLabel(at(const Duration(minutes: 10)), now),
      '10분 전 커밋',
    );
    expect(relativeCommitLabel(at(const Duration(hours: 3)), now), '3시간 전 커밋');
    expect(relativeCommitLabel(at(const Duration(hours: 30)), now), '어제 커밋');
    expect(relativeCommitLabel(at(const Duration(days: 4)), now), '4일 전 커밋');
    expect(relativeCommitLabel(at(const Duration(days: 21)), now), '3주 전 커밋');
    expect(relativeCommitLabel(at(const Duration(days: 90)), now), '3개월 전 커밋');
    expect(relativeCommitLabel(at(const Duration(days: 800)), now), '2년 전 커밋');
  });

  for (final state in [
    (loading: true, failed: false, branches: <String>[], label: '불러오는 중'),
    (loading: false, failed: false, branches: <String>[], label: '브랜치 없음'),
    (loading: false, failed: true, branches: <String>[], label: '불러오기 실패'),
  ]) {
    testWidgets('shows ${state.label}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RepositoryBranchSelector(
            repositoryName: 'yogit',
            repositoryPath: '/repos/yogit',
            localBranches: state.branches,
            selectedBranch: null,
            refsLoading: state.loading,
            refsLoadFailed: state.failed,
            onRepositoryPressed: () {},
            onBranchSelected: (_) {},
          ),
        ),
      );

      expect(find.text(state.label), findsOneWidget);
      await tester.tap(find.byKey(const Key('base-branch-selector')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('base-branch-search')), findsNothing);
    });
  }

  testWidgets('preserves repository action and full-value tooltips', (
    tester,
  ) async {
    var repositoryPressed = false;
    const repositoryPath = '/a/very/long/repository/path/to/yogit';
    const branch = 'feature/a-very-long-local-branch-name';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryBranchSelector(
            repositoryName: 'a-very-long-repository-name',
            repositoryPath: repositoryPath,
            localBranches: const [branch],
            selectedBranch: branch,
            refsLoading: false,
            refsLoadFailed: false,
            onRepositoryPressed: () => repositoryPressed = true,
            onBranchSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('repository-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-repository')));
    await tester.pumpAndSettle();
    expect(repositoryPressed, isTrue);
    expect(find.byTooltip(repositoryPath), findsOneWidget);
    expect(find.byTooltip(branch), findsOneWidget);

    for (final value in ['a-very-long-repository-name', branch]) {
      final text = tester.widget<Text>(find.text(value));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    }
  });

  testWidgets('searches, opens, and forgets recent repositories', (
    tester,
  ) async {
    String? opened;
    String? forgotten;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryBranchSelector(
            repositoryName: 'yogit',
            repositoryPath: '/repos/yogit',
            localBranches: const ['main'],
            selectedBranch: 'main',
            refsLoading: false,
            refsLoadFailed: false,
            onRepositoryPressed: () {},
            recentRepositories: const [
              '/repos/yogit',
              '/work/payments-api',
              '/work/design-tokens',
            ],
            onRecentRepositorySelected: (value) => opened = value,
            onRecentRepositoryRemoved: (value) => forgotten = value,
            onBranchSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('repository-selector')));
    await tester.pumpAndSettle();
    expect(find.text('/work/payments-api'), findsOneWidget);
    // The open repository is marked and cannot be forgotten out from under us.
    expect(
      find.descendant(
        of: find.byKey(const Key('recent-repository-/repos/yogit')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('repository-search')),
      'payments',
    );
    await tester.pump();
    expect(
      find.byKey(const Key('recent-repository-/work/payments-api')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('recent-repository-/work/design-tokens')),
      findsNothing,
    );

    // The remove button appears once the row is under the pointer.
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(
        tester.getCenter(
          find.byKey(const Key('recent-repository-/work/payments-api')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('forget-repository-/work/payments-api')),
    );
    await tester.pumpAndSettle();
    expect(forgotten, '/work/payments-api');

    await tester.tap(
      find.byKey(const Key('recent-repository-/work/payments-api')),
    );
    await tester.pumpAndSettle();
    expect(opened, '/work/payments-api');
  });

  testWidgets('says when there is nothing to remember', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryBranchSelector(
            repositoryName: 'yogit',
            repositoryPath: '/repos/yogit',
            localBranches: const ['main'],
            selectedBranch: 'main',
            refsLoading: false,
            refsLoadFailed: false,
            onRepositoryPressed: () {},
            onBranchSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('repository-selector')));
    await tester.pumpAndSettle();
    expect(find.text('최근 저장소 없음'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('repository-search')), 'x');
    await tester.pump();
    expect(find.text('최근 저장소 없음'), findsOneWidget);
  });

  testWidgets('searches local and remote comparison branches', (tester) async {
    String? compared;
    var cleared = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryBranchSelector(
            repositoryName: 'yogit',
            repositoryPath: '/repos/yogit',
            localBranches: const ['main', 'feature/a'],
            remoteBranches: const ['origin/main'],
            tags: const ['v2.0.0', 'v1.0.0'],
            selectedBranch: 'main',
            comparedBranch: 'feature/a',
            refsLoading: false,
            refsLoadFailed: false,
            onRepositoryPressed: () {},
            onBranchSelected: (_) {},
            onComparisonSelected: (value) => compared = value,
            onComparisonCleared: () => cleared = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    expect(find.text('LOCAL'), findsOneWidget);
    expect(find.text('REMOTE'), findsOneWidget);
    expect(find.text('TAG'), findsOneWidget);
    expect(find.byKey(const Key('branch-diff-menu-v2.0.0')), findsOneWidget);
    expect(find.byKey(const Key('branch-diff-menu-main')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('branch-diff-menu-feature/a')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('branch-diff-search')),
      'origin',
    );
    await tester.pump();
    expect(
      find.byKey(const Key('branch-diff-menu-origin/main')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('branch-diff-menu-feature/a')), findsNothing);
    await tester.tap(find.byKey(const Key('branch-diff-menu-origin/main')));
    await tester.pumpAndSettle();
    expect(compared, 'origin/main');

    await tester.tap(find.byKey(const Key('branch-diff-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('branch-diff-clear')));
    await tester.pump();
    expect(cleared, isTrue);
  });
}
