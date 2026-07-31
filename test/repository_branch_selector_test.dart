import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/repository_branch_selector.dart';

void main() {
  testWidgets('shows repository and only supplied local branches', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryBranchSelector(
            repositoryName: 'yogit',
            repositoryPath: '/repos/yogit',
            localBranches: const ['main', 'release'],
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

    expect(
      find.descendant(
        of: find.byKey(const Key('base-branch-menu-main')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('base-branch-menu-release')));
    expect(selected, 'release');
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
      final selector = tester.widget<PopupMenuButton<String>>(
        find.byKey(const Key('base-branch-selector')),
      );
      expect(selector.enabled, isFalse);
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

    await tester.tap(find.byKey(const Key('pick-repository')));
    expect(repositoryPressed, isTrue);
    expect(find.byTooltip(repositoryPath), findsOneWidget);
    expect(find.byTooltip(branch), findsOneWidget);

    for (final value in ['a-very-long-repository-name', branch]) {
      final text = tester.widget<Text>(find.text(value));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    }
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
