# Merge·Rebase Preview Apply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Branch Diff에서 Merge·Rebase 결과를 안전한 임시 공간에서 확인하고, 승인한 결과만 로컬 브랜치에 적용하거나 적용 직전 SHA로 되돌릴 수 있게 한다.

**Architecture:** `GitRepository`와 기존 미리보기 세션이 임시 worktree, 로컬 ref 적용, SHA 원복을 맡는다. `TimelineScreen`은 기존 Branch Diff 상태와 diff 표시 위젯을 그대로 사용하고 확인창, 진행 상태, 결과 카드만 덧붙인다. 그래프는 `layoutBranchComparison()`이 만든 기존 행을 보존하고 미리보기용 가상 행과 선만 추가한다.

**Tech Stack:** Dart, Flutter, Git CLI (`merge`, `merge-tree`, `write-tree`, `commit-tree`, `update-ref`, detached worktree), 기존 `UnifiedPresentationView`와 `SideBySidePresentationView`

## Global Constraints

- 새 패키지를 추가하지 않는다.
- 원격 ref와 원격 저장소로 push하지 않는다.
- 실제 적용 전까지 기준 브랜치, 대상 브랜치, 원래 작업 트리를 변경하지 않는다.
- 실제 적용과 원복 직전에 두 로컬 브랜치 tip을 저장된 SHA와 다시 비교한다.
- 체크아웃된 브랜치는 작업 트리와 인덱스가 깨끗할 때만 적용하거나 원복한다.
- Merge·Rebase 미리보기 때문에 새로 생긴 가상 레일과 대응선만 기준 HTML과 엄격히 맞춘다.
- 기존 타임라인 레일은 `GraphRow`와 `CommitGraphPainter`의 선, 곡률, 연결 규칙을 그대로 유지한다.
- 성공과 충돌 화면 모두 Unified와 Side-by-side를 지원한다.
- 기준 화면은 `docs/superpowers/specs/assets/merge-rebase-preview/final-reference.html`이며 1440×900, 100% 배율로 비교한다.

---

### Task 1: Merge 충돌용 임시 미리보기 세션

**Files:**
- Modify: `lib/git.dart:300-690`
- Modify: `lib/git.dart:1607-1748`
- Test: `test/git_test.dart:779-1002`

**Interfaces:**
- Produces: `enum MergePreviewStatus { clean, conflict, failed }`
- Produces: `enum MergeConflictChoice { base, compare }`
- Produces: `class MergePreviewResult`
- Produces: `class MergePreviewSession`
- Produces: `GitRepository.openMergePreview({required String baseRef, required String compareRef})`
- Produces: `GitRepository.cleanupStalePreviewWorktrees()`

- [ ] **Step 1: Merge 충돌 세션의 실패 테스트 작성**

`test/git_test.dart`의 Rebase 미리보기 테스트 옆에 실제 임시 저장소를 쓰는 테스트를 추가한다.

```dart
test('merge preview resolves conflicts without moving either branch', () async {
  final root = await Directory.systemTemp.createTemp(
    'yogit_merge_preview_fixture_',
  );
  addTearDown(() => root.delete(recursive: true));
  await _initRepository(root);
  await File('${root.path}/shared.txt').writeAsString('base\n');
  await _git(root, ['add', 'shared.txt']);
  await _git(root, ['commit', '-m', 'base']);
  await _git(root, ['switch', '-c', 'feature']);
  await File('${root.path}/shared.txt').writeAsString('feature\n');
  await _git(root, ['commit', '-am', 'feature']);
  final featureBefore = (await _git(root, ['rev-parse', 'feature'])).trim();
  await _git(root, ['switch', 'main']);
  await File('${root.path}/shared.txt').writeAsString('main\n');
  await _git(root, ['commit', '-am', 'main']);
  final mainBefore = (await _git(root, ['rev-parse', 'main'])).trim();

  final session = await GitRepository(
    root.path,
  ).openMergePreview(baseRef: 'main', compareRef: 'feature');
  addTearDown(session.dispose);
  final conflict = await session.start();

  expect(conflict.status, MergePreviewStatus.conflict);
  expect(conflict.conflictFiles, ['shared.txt']);
  expect(Directory(session.worktreePath!).existsSync(), isTrue);

  await session.resolveFile('shared.txt', MergeConflictChoice.compare);
  final completed = await session.finish();

  expect(completed.status, MergePreviewStatus.clean);
  expect(completed.treeSha, isNotEmpty);
  expect(
    (await _git(root, ['show', '${completed.treeSha}:shared.txt'])).trim(),
    'feature',
  );
  expect((await _git(root, ['rev-parse', 'main'])).trim(), mainBefore);
  expect((await _git(root, ['rev-parse', 'feature'])).trim(), featureBefore);
});
```

- [ ] **Step 2: 테스트를 실행해 새 인터페이스가 없어서 실패하는지 확인**

Run: `flutter test test/git_test.dart --plain-name "merge preview resolves conflicts without moving either branch"`

Expected: `openMergePreview`, `MergePreviewStatus`, `MergeConflictChoice`를 찾지 못해 컴파일 실패

- [ ] **Step 3: 최소 Merge 미리보기 모델과 세션 구현**

`lib/git.dart`의 Rebase 미리보기 모델 바로 앞에 다음 모델을 추가한다.

```dart
enum MergePreviewStatus { clean, conflict, failed }

enum MergeConflictChoice { base, compare }

class MergePreviewResult {
  const MergePreviewResult({
    required this.status,
    required this.baseTip,
    required this.compareTip,
    this.treeSha,
    this.resultFiles = const [],
    this.conflictFiles = const [],
    this.error,
  });

  final MergePreviewStatus status;
  final String baseTip;
  final String compareTip;
  final String? treeSha;
  final List<GitFileChange> resultFiles;
  final List<String> conflictFiles;
  final String? error;
}
```

`MergePreviewSession.start()`는 `yogit_merge_preview_` 임시 경로에
`git worktree add --detach <path> <baseTip>`을 실행한 뒤 다음 명령을
임시 경로에서 실행한다.

```dart
[
  '-c',
  'core.hooksPath=/dev/null',
  '-c',
  'commit.gpgSign=false',
  'merge',
  '--no-commit',
  '--no-ff',
  compareTip,
]
```

종료 코드가 0이면 `git write-tree`, 충돌이면
`git diff --name-only --diff-filter=U -z`를 읽는다. `resolveFile()`은
`base`를 `--ours`, `compare`를 `--theirs`에 연결하고 해당 파일을
`git add`한다. `finish()`는 충돌 파일이 없는지 확인한 뒤 `write-tree`와
`GitRepository.loadFilesBetween(baseTip, treeSha)` 결과를 반환한다.
`dispose()`는 임시 경로에서 `merge --abort`를 시도하고 앱이 만든
worktree만 강제 제거한다.

- [ ] **Step 4: 오래된 임시 worktree 정리를 Merge와 Rebase에 함께 적용**

`cleanupStaleRebaseWorktrees()`를 `cleanupStalePreviewWorktrees()`로
이름을 바꾸고 `yogit_rebase_preview_`, `yogit_merge_preview_` 두 접두사만
정리한다. `TimelineScreen`과 테스트 가짜 저장소의 재정의도 같은 이름으로
바꾼다. 다른 임시 폴더는 삭제하지 않는다.

- [ ] **Step 5: Merge와 기존 Rebase 미리보기 테스트 실행**

Run: `flutter test test/git_test.dart --plain-name "preview"`

Expected: 모든 preview 테스트 PASS

- [ ] **Step 6: 커밋**

```bash
git add lib/git.dart test/git_test.dart lib/timeline.dart test/app_test.dart
git commit -m "feat: resolve merge previews in a temporary worktree"
```

---

### Task 2: 로컬 브랜치 실제 적용과 SHA 원복

**Files:**
- Modify: `lib/git.dart:330-380`
- Modify: `lib/git.dart:1417-1980`
- Test: `test/git_test.dart:1004-1155`

**Interfaces:**
- Consumes: `BranchComparisonResult`, Task 1의 최종 `treeSha`, 기존 Rebase `virtualTip`
- Produces: `enum BranchApplyMode { merge, rebase }`
- Produces: `class BranchApplyResult`
- Produces: `GitRepository.applyMergePreview(...)`
- Produces: `GitRepository.applyRebasePreview(...)`
- Produces: `GitRepository.restoreBranchApply(BranchApplyResult result)`

- [ ] **Step 1: Merge 적용·원복 실패 테스트 작성**

```dart
test('merge preview applies locally and restores both exact tips', () async {
  final fixture = await _branchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  final repository = GitRepository(fixture.root.path);
  final comparison = await repository.compareBranches('main', 'feature');

  final applied = await repository.applyMergePreview(
    comparison: comparison,
    treeSha: comparison.merge.treeSha!,
  );

  expect(applied.mode, BranchApplyMode.merge);
  expect(applied.baseBefore, comparison.baseTip);
  expect(applied.baseAfter, isNot(comparison.baseTip));
  expect(
    (await _git(fixture.root, ['rev-list', '--parents', '-n', '1', 'main']))
        .trim()
        .split(' '),
    [applied.baseAfter, comparison.baseTip, comparison.compareTip],
  );
  expect(
    (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
    comparison.compareTip,
  );

  await repository.restoreBranchApply(applied);

  expect(
    (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
    comparison.baseTip,
  );
  expect(
    (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
    comparison.compareTip,
  );
});
```

테스트 파일 안의 기존 `_initRepository`, `_git` 패턴으로
`_branchPreviewFixture()`를 만들고 `main`과 `feature`가 충돌 없이 갈라진
상태를 반환한다.

- [ ] **Step 2: Rebase 적용·원복과 오래된 tip 거부 테스트 작성**

```dart
test('rebase preview applies its virtual tip and restores both tips', () async {
  final fixture = await _branchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  final repository = GitRepository(fixture.root.path);
  final comparison = await repository.compareBranches('main', 'feature');
  final session = await repository.openRebasePreview(
    baseRef: 'main',
    compareRef: 'feature',
  );
  addTearDown(session.dispose);
  final preview = await session.start();

  final applied = await repository.applyRebasePreview(
    comparison: comparison,
    virtualTip: preview.virtualTip!,
  );

  expect(
    (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
    comparison.baseTip,
  );
  expect(
    (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
    preview.virtualTip,
  );
  await repository.restoreBranchApply(applied);
  expect(
    (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
    comparison.compareTip,
  );
});

test('branch preview apply rejects changed tips and a dirty checkout', () async {
  final fixture = await _branchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  final repository = GitRepository(fixture.root.path);
  final comparison = await repository.compareBranches('main', 'feature');
  await File('${fixture.root.path}/dirty.txt').writeAsString('dirty\n');

  expect(
    () => repository.applyMergePreview(
      comparison: comparison,
      treeSha: comparison.merge.treeSha!,
    ),
    throwsA(isA<GitRepositoryException>()),
  );
});
```

원복 거부 테스트에서는 적용 뒤 대상 ref를 새 커밋으로 옮기고
`restoreBranchApply()`가 어떤 ref도 갱신하지 않는지 확인한다.

- [ ] **Step 3: 테스트를 실행해 실제 적용 API가 없어서 실패하는지 확인**

Run: `flutter test test/git_test.dart --plain-name "preview applies"`

Expected: `applyMergePreview`, `applyRebasePreview`, `restoreBranchApply`를 찾지 못해 컴파일 실패

- [ ] **Step 4: 적용 결과 모델 구현**

```dart
enum BranchApplyMode { merge, rebase }

class BranchApplyResult {
  const BranchApplyResult({
    required this.mode,
    required this.baseBranch,
    required this.compareBranch,
    required this.baseBefore,
    required this.baseAfter,
    required this.compareBefore,
    required this.compareAfter,
  });

  final BranchApplyMode mode;
  final String baseBranch;
  final String compareBranch;
  final String baseBefore;
  final String baseAfter;
  final String compareBefore;
  final String compareAfter;
}
```

- [ ] **Step 5: 공통 사전 검사와 ref 이동 구현**

`GitRepository` 안에만 쓰는 다음 도우미를 추가한다.

```dart
Future<String> _localBranchTip(String branch)
Future<void> _verifyApplyTips(BranchComparisonResult comparison)
Future<void> _moveLocalBranch({
  required String branch,
  required String expected,
  required String next,
})
```

`_localBranchTip()`은 `refs/heads/$branch^{commit}`만 확인한다.
`_verifyApplyTips()`은 기준과 대상이 `comparison.baseTip`,
`comparison.compareTip`과 각각 같은지 확인한 뒤 하나라도 다르면 명령을
실행하지 않는다. `_moveLocalBranch()`는 현재 체크아웃된 브랜치라면
다른 Git 작업이 없고 `status --porcelain=v1 -z`가 비어 있을 때만
`reset --hard <next>`를 실행한다. 체크아웃되지 않은 브랜치는
`update-ref refs/heads/<branch> <next> <expected>`로 원자적으로 갱신한다.

- [ ] **Step 6: Merge와 Rebase 실제 적용 구현**

```dart
Future<BranchApplyResult> applyMergePreview({
  required BranchComparisonResult comparison,
  required String treeSha,
})

Future<BranchApplyResult> applyRebasePreview({
  required BranchComparisonResult comparison,
  required String virtualTip,
})
```

Merge는 사전 검사를 마친 뒤 다음 명령으로 두 부모 Merge 커밋을 만든다.

```dart
[
  '-c',
  'commit.gpgSign=false',
  'commit-tree',
  treeSha,
  '-p',
  comparison.baseTip,
  '-p',
  comparison.compareTip,
  '-m',
  "Merge branch '${comparison.compareRef}' into ${comparison.baseRef}",
]
```

그 뒤 기준 브랜치만 새 커밋으로 옮긴다. Rebase는 `virtualTip^{commit}`을
검증한 뒤 대상 브랜치만 옮긴다. 두 메서드는 이동 뒤 두 브랜치 tip을
다시 읽어 `BranchApplyResult`에 기록한다.

- [ ] **Step 7: 원복 구현**

`restoreBranchApply()`는 두 브랜치의 현재 tip이 각각 `baseAfter`,
`compareAfter`와 같은지 먼저 확인한다. 둘 중 하나라도 다르면 아무 ref도
갱신하지 않는다. 조건이 맞으면 실제로 바뀐 브랜치만 `_moveLocalBranch()`
로 되돌리고 마지막에 두 tip이 `baseBefore`, `compareBefore`와 정확히
같은지 확인한다.

- [ ] **Step 8: Git 적용·원복 테스트 실행**

Run: `flutter test test/git_test.dart`

Expected: 모든 Git 테스트 PASS

- [ ] **Step 9: 커밋**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: apply and restore branch preview results"
```

---

### Task 3: 기존 레일을 보존하는 미리보기 그래프

**Files:**
- Modify: `lib/timeline.dart:46-197`
- Modify: `lib/timeline.dart:3464-3825`
- Modify: `lib/timeline.dart:6088-6182`
- Test: `test/app_test.dart:3846-3898`

**Interfaces:**
- Consumes: 기존 `layoutBranchComparison()`, `GraphRow`, `CommitGraphPainter`
- Produces: 기존 비교 행을 그대로 담는 `BranchPreviewGraph.rows`
- Produces: Merge·Rebase 가상 행, 1px 점선, Rebase 대응선

- [ ] **Step 1: 기존 행이 바뀌지 않는 그래프 테스트 작성**

```dart
test('preview graphs preserve every existing comparison row', () {
  final comparison = branchComparison();
  final existing = layoutBranchComparison(comparison.commits);
  final merge = layoutMergePreviewGraph(comparison);
  expect(merge.rows.skip(1).toList(), orderedEquals(existing));

  final feature = comparison.commits
      .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
      .commit;
  final rebase = layoutRebasePreviewGraph(
    comparison,
    RebasePreviewResult(
      status: RebasePreviewStatus.clean,
      baseTip: comparison.baseTip,
      compareTip: comparison.compareTip,
      rewritten: [(original: feature, rewrittenSha: 'rewritten-feature')],
      completed: 1,
      total: 1,
      virtualTip: 'rewritten-feature',
    ),
    rebaseMappingColors(AvatarService.defaultColors),
  );
  expect(rebase.rows.skip(1).toList(), orderedEquals(existing));
});
```

Rebase 커밋이 세 개인 경우 가상 행이 기준 브랜치 HEAD 위 같은 lane에
놓이고 원본 행의 lane, transitions, branch 값이 모두 그대로인지도
확인한다.

- [ ] **Step 2: 테스트를 실행해 현재 전체 재배치 때문에 실패하는지 확인**

Run: `flutter test test/app_test.dart --plain-name "preview graphs preserve every existing comparison row"`

Expected: 현재 `layoutGraph([...virtual, ...existing])`가 기존 행을 다시 만들어 비교 실패

- [ ] **Step 3: 기존 비교 행을 재사용하도록 두 레이아웃 함수 수정**

두 함수는 먼저 다음 값을 만든다.

```dart
final existing = layoutBranchComparison(comparison.commits);
final baseRow = existing.firstWhere(
  (row) => row.commit.sha == comparison.baseTip,
);
```

가상 행은 `baseRow.lane`과 `baseRow.branch`를 쓰며 기존 행 앞에만 붙인다.
기존 행은 다시 `layoutGraph()`에 넣지 않는다. 가상 행의
`activeLanes`, `nextLanes`, `activeLaneShas`, `nextLaneShas`만 채워
추가된 구간을 연결한다. `dashedLanes`에는 가상 행 구간만 넣어 기존
행의 실선이 점선으로 바뀌지 않게 한다.

- [ ] **Step 4: 새 미리보기 선의 표시 규칙 유지**

Merge의 두 부모 연결과 Rebase 가상 커밋 사이는
`CommitGraphPainter.previewRailWidth == 1`인 점선으로 그린다. 원본과
재작성 커밋 대응선은 기존 `RebaseMappingPainter`를 재사용한다.
대응선은 어두운 다섯 색, 1px 실선, 둥근 직교 경로, 가상 커밋 쪽 화살표,
양쪽 노드의 같은 색 테두리를 유지한다. route lane은 그래프 오른쪽에
순서대로 배치해 서로 교차하거나 아바타를 통과하지 않게 한다.

- [ ] **Step 5: 그래프 단위 및 위젯 테스트 실행**

Run: `flutter test test/app_test.dart --plain-name "preview graph"`

Expected: 모든 preview graph 테스트 PASS

- [ ] **Step 6: 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: preserve existing rails in branch previews"
```

---

### Task 4: 적용 확인, 진행 상태, 완료와 원복 UI

**Files:**
- Modify: `lib/timeline.dart:562-680`
- Modify: `lib/timeline.dart:1985-2165`
- Modify: `lib/timeline.dart:2987-3085`
- Modify: `lib/timeline.dart:4210-4768`
- Modify: `test/app_test.dart:2606-3210`
- Modify: `test/app_test.dart:11869-12175`

**Interfaces:**
- Consumes: Task 2의 `applyMergePreview`, `applyRebasePreview`, `restoreBranchApply`
- Produces: `enum BranchApplyStatus`
- Produces: `_confirmBranchPreviewApply()`, `_runBranchPreviewApply()`
- Produces: `_confirmBranchPreviewRollback()`, `_runBranchPreviewRollback()`
- Produces: 적용 상태 카드와 Rebase 커밋 포커스 애니메이션

- [ ] **Step 1: Merge 적용 확인과 원복 위젯 테스트 작성**

`FakeGitRepository`에 다음 선택 콜백을 추가하고 같은 이름의 메서드를
재정의한다.

```dart
final Future<BranchApplyResult> Function({
  required BranchComparisonResult comparison,
  required String treeSha,
})? applyMergePreviewCallback;
final Future<BranchApplyResult> Function({
  required BranchComparisonResult comparison,
  required String virtualTip,
})? applyRebasePreviewCallback;
final Future<void> Function(BranchApplyResult result)?
restoreBranchApplyCallback;
```

Merge 성공 위젯 테스트는 다음을 검증한다.

```dart
expect(find.text('fix/docs를 main에 Merge 실제 적용'), findsOneWidget);
await tester.tap(find.byKey(const Key('branch-preview-apply')));
await tester.pumpAndSettle();
expect(find.text('Merge 실제 적용'), findsOneWidget);
expect(find.textContaining('원격 저장소로 push하지 않습니다'), findsOneWidget);
expect(find.textContaining('이전 시점으로 되돌릴 수'), findsOneWidget);
expect(find.textContaining('main-tip'), findsWidgets);
expect(find.textContaining('feature-tip'), findsWidgets);
```

확인 뒤 가짜 적용 결과를 반환하고 `Merge 이전 시점으로 되돌리기`를
누르면 별도 확인창을 거쳐 `restoreBranchApplyCallback`이 같은 결과를
받는지 확인한다.

- [ ] **Step 2: Rebase 적용 진행과 원복 위젯 테스트 작성**

Rebase 성공 상태에서 `main 위로 fix/docs Rebase 실제 적용` 버튼과 같은
안내 문구를 확인한다. 적용을 확인한 뒤 `rebase-apply-current-row` 키가
oldest-first 순서로 이동하는지 220ms씩 `pump()`해서 검증한다. 완료 뒤
`Rebase 이전 시점으로 되돌리기` 버튼과 적용 전/후 SHA가 표시되는지도
검증한다.

- [ ] **Step 3: 테스트를 실행해 적용 UI가 없어서 실패하는지 확인**

Run: `flutter test test/app_test.dart --plain-name "branch preview applies"`

Expected: `branch-preview-apply` 버튼과 적용 콜백을 찾지 못해 실패

- [ ] **Step 4: 최소 적용 상태 추가**

```dart
enum BranchApplyStatus {
  idle,
  applying,
  applied,
  reverting,
  reverted,
  failed,
}
```

`_TimelineScreenState`에는 다음 값만 추가한다.

```dart
BranchApplyStatus _branchApplyStatus = BranchApplyStatus.idle;
BranchApplyResult? _branchApplyResult;
Object? _branchApplyError;
String? _rebaseApplyingSha;
```

브랜치, 저장소, 미리보기 방식이 바뀌면 이 상태를 초기화한다.

- [ ] **Step 5: 적용 확인창과 실행 구현**

성공 카드의 버튼 문구는 모드에 따라 정확히 다음 값을 쓴다.

```dart
final applyLabel = _branchPreviewMode == BranchPreviewMode.merge
    ? '${comparison.compareRef}를 ${comparison.baseRef}에 Merge 실제 적용'
    : '${comparison.baseRef} 위로 ${comparison.compareRef} Rebase 실제 적용';
```

확인창은 `autofocus: true`인 취소 버튼을 먼저 배치하고 다음 내용을
표시한다.

- 기준 브랜치 이름과 시작 SHA
- 대상 브랜치 이름과 시작 SHA
- 실제로 바뀌는 로컬 브랜치
- 원격 저장소로 push하지 않는다는 안내
- 완료 뒤 두 브랜치를 시작 SHA로 되돌릴 수 있다는 안내

Merge는 현재 `treeSha`, Rebase는 현재 `virtualTip`으로 Task 2의 메서드를
호출한다. 오류는 결과 카드에 표시하고 기존 미리보기는 유지한다.

- [ ] **Step 6: Rebase 진행 포커스 애니메이션 구현**

사용자가 확인한 뒤 `preview.rewritten`을 oldest-first로 순회한다.
각 단계에서 `_rebaseApplyingSha`와 선택 행을 갱신하고
`Scrollable.ensureVisible()`을 호출한다. 기본 지속 시간은 220ms
`Curves.easeOut`이며 `MediaQuery.disableAnimationsOf(context)`가 참이면
즉시 이동한다. 마지막 단계에서만 `applyRebasePreview()`를 호출해 대상
ref를 한 번 옮긴다.

- [ ] **Step 7: 완료 카드와 원복 구현**

적용 성공 카드에는 두 브랜치의 적용 전/후 SHA와 다음 버튼을 표시한다.

- `Merge 이전 시점으로 되돌리기`
- `Rebase 이전 시점으로 되돌리기`

원복 확인창은 취소에 기본 포커스를 두고 두 복원 SHA와 원격 저장소가
바뀌지 않는다는 안내를 표시한다. 확인 뒤 `restoreBranchApply()`를
호출하고 성공하면 `SHA 일치 확인` 상태를 표시한다.

- [ ] **Step 8: 적용 UI 테스트 실행**

Run: `flutter test test/app_test.dart --plain-name "branch preview"`

Expected: 모든 branch preview 위젯 테스트 PASS

- [ ] **Step 9: 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: apply and restore branch previews from the timeline"
```

---

### Task 5: 충돌 안전 안내, 해결 완료 diff, Drop

**Files:**
- Modify: `lib/timeline.dart:562-680`
- Modify: `lib/timeline.dart:1740-1975`
- Modify: `lib/timeline.dart:4524-5454`
- Modify: `test/app_test.dart:2784-3150`
- Modify: `test/app_test.dart:11869-12175`

**Interfaces:**
- Consumes: Task 1의 `MergePreviewSession`, 기존 `RebasePreviewSession`
- Consumes: Task 4의 실제 적용 버튼과 상태 카드
- Produces: 자동 준비되는 임시 공간 안내
- Produces: Merge 충돌 해결, 최종 diff, `Drop`

- [ ] **Step 1: 임시 공간 안내와 Merge 충돌 해결 테스트 작성**

Merge 충돌 비교를 연 뒤 다음 문구와 태그를 검증한다.

```dart
expect(
  find.text(
    '충돌 해결 과정은 임시 공간에서만 진행합니다. '
    '기준 브랜치 main과 대상 브랜치 fix/docs를 직접 변경하지 않습니다.',
  ),
  findsOneWidget,
);
expect(find.text('두 브랜치 변경 없음'), findsOneWidget);
expect(find.text('현재 작업 트리 변경 없음'), findsOneWidget);
expect(find.text('종료 시 자동 삭제'), findsOneWidget);
expect(find.text('임시 작업 공간 시작'), findsNothing);
```

`FakeMergePreviewSession`을 추가해 `resolveFile()` 호출과 `finish()` 결과를
기록한다. Merge 충돌에서 기준/대상 선택과 `해결 후 계속`을 누르면
세션이 받은 값과 최종 파일 목록이 맞는지 확인한다.

- [ ] **Step 2: 충돌 해결 완료 뒤 최종 diff와 Drop 테스트 작성**

Merge와 Rebase 각각 마지막 충돌을 해결한 뒤 다음 요소를 검증한다.

```dart
expect(find.text('충돌 해결과 테스트를 마쳤습니다'), findsOneWidget);
expect(find.text('Drop'), findsOneWidget);
expect(find.byType(UnifiedPresentationView), findsOneWidget);
await tester.tap(
  find.byKey(const Key('branch-preview-layout-side-by-side')),
);
await tester.pump();
expect(find.byType(SideBySidePresentationView), findsOneWidget);
```

`Drop`을 누르면 세션의 `dispose()`가 호출되고 실제 적용 콜백은 호출되지
않으며 두 브랜치가 변경되지 않았다는 완료 문구가 보이는지 확인한다.

- [ ] **Step 3: 테스트를 실행해 Merge 세션과 안전 카드가 없어서 실패하는지 확인**

Run: `flutter test test/app_test.dart --plain-name "temporary preview"`

Expected: 안전 안내 문구와 Merge 해결 동작을 찾지 못해 실패

- [ ] **Step 4: Merge 충돌 세션 자동 시작**

Merge 모드에서 `comparison.merge.status == conflicts`이면 별도 시작 버튼
없이 `openMergePreview()`와 `session.start()`를 차례대로 호출한다.
Rebase와 같은 serial 검사를 사용해 브랜치나 모드가 바뀐 뒤 도착한
결과는 폐기한다. 화면 종료, 비교 해제, 저장소 변경 때 세션을 정리한다.

- [ ] **Step 5: 공통 안전 안내 카드 구현**

두 충돌 모드에서 `branch-preview-safe-workspace` 키를 가진 카드를
표시한다. 본문은 다음 문장을 그대로 쓴다.

> 충돌 해결 과정은 임시 공간에서만 진행합니다. 기준 브랜치 main과 대상 브랜치 fix/docs를 직접 변경하지 않습니다.

브랜치 이름은 현재 비교 값으로 바꾸고 `두 브랜치 변경 없음`,
`현재 작업 트리 변경 없음`, `종료 시 자동 삭제` 태그는 시안의 밝은
청록 계열로 표시한다.

- [ ] **Step 6: Merge 충돌 선택과 최종 결과 구현**

Merge 충돌 선택 버튼은 `MergePreviewSession.resolveFile()`을 호출한다.
모든 파일이 해결되면 `finish()`를 실행하고 반환된 `treeSha`,
`resultFiles`를 `_branchPreviewRange`, 파일 목록, diff에 사용한다.
Rebase는 기존 `continueAfterResolving()`이 clean을 반환한 시점부터 같은
최종 검토 상태를 사용한다.

최종 카드에는 `충돌 해결과 테스트를 마쳤습니다`, `Merge 가능` 또는
`Rebase 가능`, `Drop`, Task 4의 실제 적용 버튼을 표시한다. `Drop`은
소유한 임시 세션을 정리하고 `임시 결과를 Drop했습니다`, `변경 없음`을
표시한다.

- [ ] **Step 7: 충돌 안전 흐름 테스트 실행**

Run: `flutter test test/app_test.dart --plain-name "conflict"`

Expected: 모든 Branch Diff 및 Cherry-pick 충돌 테스트 PASS

- [ ] **Step 8: 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: finish conflicted previews in temporary worktrees"
```

---

### Task 6: 전체 검증과 기준 시안 비교

**Files:**
- Create: `docs/superpowers/verification/merge-rebase-preview/reference/merge-success.png`
- Create: `docs/superpowers/verification/merge-rebase-preview/reference/rebase-success.png`
- Create: `docs/superpowers/verification/merge-rebase-preview/reference/merge-conflict.png`
- Create: `docs/superpowers/verification/merge-rebase-preview/reference/rebase-conflict.png`
- Create: `docs/superpowers/verification/merge-rebase-preview/actual/merge-success.png`
- Create: `docs/superpowers/verification/merge-rebase-preview/actual/rebase-success.png`
- Create: `docs/superpowers/verification/merge-rebase-preview/actual/merge-conflict.png`
- Create: `docs/superpowers/verification/merge-rebase-preview/actual/rebase-conflict.png`
- Create: `docs/superpowers/verification/merge-rebase-preview/review.md`

**Interfaces:**
- Consumes: Tasks 1-5의 완성 화면
- Produces: 네 상태의 기준/실제 캡처와 차이 0개 검토 기록

- [ ] **Step 1: 정적 분석과 전체 테스트 실행**

Run: `dart format --output=none --set-exit-if-changed lib/git.dart lib/timeline.dart test/git_test.dart test/app_test.dart`

Expected: exit 0

Run: `flutter analyze`

Expected: `No issues found!`

Run: `flutter test`

Expected: 모든 테스트 PASS

- [ ] **Step 2: 기준 페이지 네 상태 캡처**

`docs/superpowers/specs/assets/merge-rebase-preview/final-reference.html`을
1440×900, 100% 배율로 열고 Merge 성공, Rebase 성공, Merge 충돌,
Rebase 충돌을 `reference/`의 네 파일로 저장한다.

- [ ] **Step 3: 구현 앱 네 상태 캡처**

같은 저장소, 브랜치 이름, 창 크기, 배율로 앱의 네 상태를 열고
`actual/`의 네 파일로 저장한다. 성공 화면은 적용 전 카드까지, 충돌
화면은 임시 공간 안내와 선택한 diff까지 보이게 한다.

- [ ] **Step 4: 시각 차이 검토와 재작업**

`review.md`에 상태별로 문구, 색, 간격, 버튼 위치, 보라색 가상 요소,
새 1px 점선, 대응선, 행 강조, Unified/Side-by-side를 비교해 기록한다.
기존 타임라인 레일의 위치와 곡률은 기준 HTML과 달라도 허용하지만 기존
앱의 `CommitGraphPainter` 결과와 연결 규칙이 바뀌면 결함으로 기록한다.
차이가 남아 있으면 해당 Task의 테스트를 먼저 보강한 뒤 구현과 캡처를
반복한다.

- [ ] **Step 5: 차이 0개와 깨끗한 작업 트리 확인**

Run: `rg -n \"남은 차이: 0|Remaining differences: 0\" docs/superpowers/verification/merge-rebase-preview/review.md`

Expected: 한 줄 이상 출력

Run: `git diff --check`

Expected: 출력 없음, exit 0

- [ ] **Step 6: 검증 자료 커밋**

```bash
git add docs/superpowers/verification/merge-rebase-preview
git commit -m "test: verify merge and rebase preview designs"
```
