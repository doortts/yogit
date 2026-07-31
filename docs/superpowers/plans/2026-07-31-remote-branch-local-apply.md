# 원격 브랜치 미리보기 로컬 적용 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 원격 추적 브랜치를 비교 대상으로 선택한 Merge/Rebase 미리보기 결과도 원격 ref를 바꾸지 않고 로컬 브랜치에 적용하고 원복할 수 있게 한다.

**Architecture:** `lib/git.dart`에 미리보기 방식과 현재 ref 목록으로 쓰기 가능한 로컬 변경 대상을 계산하는 작은 값 객체와 순수 함수를 추가한다. Merge는 기존 로컬 기준 브랜치만 이동하고 Rebase 비교 대상이 원격이면 같은 이름의 로컬 추적 브랜치를 만들거나 재사용한 뒤 해당 브랜치만 이동한다. `lib/timeline.dart`는 같은 계산 결과로 버튼, 확인창, 재계산 안내를 구성하므로 화면과 Git 계층이 같은 대상을 사용한다.

**Tech Stack:** Flutter, Dart, Git CLI, 기존 `GitRepository`, Flutter widget tests

## Global Constraints

- 기준 브랜치는 지금처럼 로컬 브랜치만 선택할 수 있다.
- 원격 추적 ref는 읽기 전용 입력이며 `refs/remotes/*`를 갱신하지 않는다.
- 이 흐름에서는 `git push`와 자동 `git fetch`를 실행하지 않는다.
- 같은 이름의 기존 로컬 브랜치를 원격 SHA로 초기화하지 않는다.
- 기존 로컬 브랜치의 upstream 설정을 바꾸지 않는다.
- 적용 중 만든 로컬 브랜치는 원복하거나 적용에 실패했을 때 예상 SHA가 일치하는 경우에만 삭제한다.
- Push 버튼, Push 확인창, Push 관련 Settings 항목을 추가하지 않는다.
- 새 패키지나 네트워크 연동을 추가하지 않는다.
- 설계 기준은 `docs/superpowers/specs/2026-07-31-remote-branch-local-apply-design.md`다.

## 파일 구성

- `lib/git.dart`: 로컬 변경 대상 계산, 원격 ref tip 검증, 로컬 Merge/Rebase 적용과 원복
- `lib/timeline.dart`: 적용 가능 여부, 로컬 브랜치 생성·재계산 안내, 확인창과 완료 화면 문구
- `test/git_test.dart`: 실제 임시 Git 저장소를 사용한 ref 이동·브랜치 생성·원복 검증
- `test/app_test.dart`: 원격 비교 브랜치 화면의 버튼·안내·재계산·확인창 검증
- `lib/settings.dart`: 변경하지 않음

---

### Task 1: 쓰기 가능한 로컬 변경 대상 계산

**Files:**
- Modify: `lib/git.dart:927-953`
- Test: `test/git_test.dart`

**Interfaces:**
- Consumes: `BranchApplyMode`, `BranchComparisonResult`, `RepoRefs`
- Produces: `BranchApplyTarget`, `resolveBranchApplyTarget({required BranchApplyMode mode, required BranchComparisonResult comparison, required RepoRefs refs})`

- [ ] **Step 1: 원격 Rebase 대상과 기존 로컬 충돌을 표현하는 실패 테스트 작성**

`test/git_test.dart`의 브랜치 미리보기 테스트 묶음 앞에 다음 테스트와 최소 비교 결과를 추가한다.

```dart
const remoteComparison = BranchComparisonResult(
  baseRef: 'main',
  compareRef: 'origin/feature',
  baseTip: 'main-tip',
  compareTip: 'remote-tip',
  baseParent: null,
  compareParent: null,
  mergeBases: [],
  commits: [],
  files: [],
  merge: MergeConflictCheck(
    status: MergeConflictStatus.clean,
    treeSha: 'merge-tree',
  ),
);

test('remote rebase target maps to a missing local branch', () {
  const refs = RepoRefs(
    local: ['main'],
    remote: ['origin/feature'],
    tips: {'main': 'main-tip', 'origin/feature': 'remote-tip'},
    localTips: {'main': 'main-tip'},
  );

  final target = resolveBranchApplyTarget(
    mode: BranchApplyMode.rebase,
    comparison: remoteComparison,
    refs: refs,
  );

  expect(target?.selectedRef, 'origin/feature');
  expect(target?.selectedTip, 'remote-tip');
  expect(target?.localBranch, 'feature');
  expect(target?.localTip, isNull);
  expect(target?.createsBranch, isTrue);
  expect(target?.needsRecalculation, isFalse);
});

test('different same-named local rebase target requires recalculation', () {
  const refs = RepoRefs(
    local: ['main', 'feature'],
    remote: ['origin/feature'],
    tips: {
      'main': 'main-tip',
      'feature': 'local-tip',
      'origin/feature': 'remote-tip',
    },
    localTips: {'main': 'main-tip', 'feature': 'local-tip'},
  );

  final target = resolveBranchApplyTarget(
    mode: BranchApplyMode.rebase,
    comparison: remoteComparison,
    refs: refs,
  );

  expect(target?.localBranch, 'feature');
  expect(target?.localTip, 'local-tip');
  expect(target?.createsBranch, isFalse);
  expect(target?.needsRecalculation, isTrue);
});

test('matching same-named local rebase target is reused', () {
  const refs = RepoRefs(
    local: ['main', 'feature'],
    remote: ['origin/feature'],
    tips: {
      'main': 'main-tip',
      'feature': 'remote-tip',
      'origin/feature': 'remote-tip',
    },
    localTips: {'main': 'main-tip', 'feature': 'remote-tip'},
  );

  final target = resolveBranchApplyTarget(
    mode: BranchApplyMode.rebase,
    comparison: remoteComparison,
    refs: refs,
  );

  expect(target?.localBranch, 'feature');
  expect(target?.localTip, 'remote-tip');
  expect(target?.createsBranch, isFalse);
  expect(target?.needsRecalculation, isFalse);
});
```

- [ ] **Step 2: 새 대상 계산 테스트가 실패하는지 확인**

Run:

```bash
flutter test test/git_test.dart --plain-name 'remote rebase target maps to a missing local branch'
flutter test test/git_test.dart --plain-name 'different same-named local rebase target requires recalculation'
flutter test test/git_test.dart --plain-name 'matching same-named local rebase target is reused'
```

Expected: `BranchApplyTarget` 또는 `resolveBranchApplyTarget`가 정의되지 않아 FAIL

- [ ] **Step 3: 최소 대상 값 객체와 순수 함수 구현**

`lib/git.dart`에서 `BranchApplyMode` 바로 뒤에 다음 코드를 추가한다.

```dart
class BranchApplyTarget {
  const BranchApplyTarget({
    required this.selectedRef,
    required this.selectedTip,
    required this.localBranch,
    required this.localTip,
  });

  final String selectedRef;
  final String selectedTip;
  final String localBranch;
  final String? localTip;

  bool get createsBranch => localTip == null;
  bool get needsRecalculation =>
      localTip != null && localTip != selectedTip;
}

BranchApplyTarget? resolveBranchApplyTarget({
  required BranchApplyMode mode,
  required BranchComparisonResult comparison,
  required RepoRefs refs,
}) {
  final selectedRef = mode == BranchApplyMode.merge
      ? comparison.baseRef
      : comparison.compareRef;
  final selectedTip = mode == BranchApplyMode.merge
      ? comparison.baseTip
      : comparison.compareTip;

  if (refs.local.contains(selectedRef)) {
    return BranchApplyTarget(
      selectedRef: selectedRef,
      selectedTip: selectedTip,
      localBranch: selectedRef,
      localTip: refs.localTips[selectedRef] ?? refs.tips[selectedRef],
    );
  }
  if (mode == BranchApplyMode.merge || !refs.remote.contains(selectedRef)) {
    return null;
  }
  final separator = selectedRef.indexOf('/');
  if (separator <= 0 || separator == selectedRef.length - 1) return null;
  final localBranch = selectedRef.substring(separator + 1);
  return BranchApplyTarget(
    selectedRef: selectedRef,
    selectedTip: selectedTip,
    localBranch: localBranch,
    localTip: refs.localTips[localBranch],
  );
}
```

Merge 변경 대상은 항상 로컬 기준 브랜치여야 하므로 원격 기준 ref는
`null`로 거부한다. Rebase일 때만 원격 이름의 첫 `/` 뒤를 로컬 후보로
사용한다.

- [ ] **Step 4: 대상 계산 테스트와 기존 Git 테스트 실행**

Run:

```bash
flutter test test/git_test.dart --plain-name 'remote rebase target maps to a missing local branch'
flutter test test/git_test.dart --plain-name 'different same-named local rebase target requires recalculation'
flutter test test/git_test.dart --plain-name 'matching same-named local rebase target is reused'
flutter test test/git_test.dart
```

Expected: 모두 PASS

- [ ] **Step 5: 대상 계산 변경 커밋**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: resolve local targets for remote previews"
```

---

### Task 2: 원격 비교 브랜치를 로컬 기준 브랜치에 Merge

**Files:**
- Modify: `lib/git.dart:927-953,2005-2140`
- Test: `test/git_test.dart:1120-1270,2260-2290`

**Interfaces:**
- Consumes: `resolveBranchApplyTarget(...)`
- Produces: 원격 비교 ref를 허용하는 기존 `applyMergePreview(...)`, 한 브랜치만 되돌리는 `restoreBranchApply(...)`

- [ ] **Step 1: 원격 비교 ref Merge와 원복 실패 테스트 작성**

`test/git_test.dart`의 `_branchPreviewFixture()` 아래에 원격 전용 비교
fixture를 추가한다.

```dart
Future<({Directory root, BranchComparisonResult comparison, String remoteTip})>
_remoteBranchPreviewFixture() async {
  final fixture = await _branchPreviewFixture();
  final remoteTip = fixture.comparison.compareTip;
  await _git(fixture.root, [
    'update-ref',
    'refs/remotes/origin/feature',
    remoteTip,
  ]);
  await _git(fixture.root, ['branch', '-D', 'feature']);
  final repository = GitRepository(fixture.root.path);
  return (
    root: fixture.root,
    comparison: await repository.compareBranches('main', 'origin/feature'),
    remoteTip: remoteTip,
  );
}
```

같은 테스트 묶음에 다음 테스트를 추가한다.

```dart
test('remote merge preview updates only the local base', () async {
  final fixture = await _remoteBranchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  final commands = <List<String>>[];
  final repository = GitRepository(
    fixture.root.path,
    runner: (executable, arguments, {workingDirectory, environment}) async {
      commands.add(List<String>.of(arguments));
      return runProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    },
  );

  final applied = await repository.applyMergePreview(
    comparison: fixture.comparison,
    treeSha: fixture.comparison.merge.treeSha!,
  );

  expect(applied.mode, BranchApplyMode.merge);
  expect(applied.baseBranch, 'main');
  expect(applied.compareBranch, 'origin/feature');
  expect(
    (await _git(fixture.root, ['rev-parse', 'origin/feature'])).trim(),
    fixture.remoteTip,
  );
  final localFeature = await Process.run(
    'git',
    ['show-ref', '--verify', 'refs/heads/feature'],
    workingDirectory: fixture.root.path,
  );
  expect(localFeature.exitCode, 1);

  await repository.restoreBranchApply(applied);

  expect(
    (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
    fixture.comparison.baseTip,
  );
  expect(
    (await _git(fixture.root, ['rev-parse', 'origin/feature'])).trim(),
    fixture.remoteTip,
  );
  expect(
    commands.where(
      (arguments) =>
          arguments.isNotEmpty &&
          (arguments.first == 'push' || arguments.first == 'fetch'),
    ),
    isEmpty,
  );
});

test('remote merge apply rejects a changed remote tip', () async {
  final fixture = await _remoteBranchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  final repository = GitRepository(fixture.root.path);
  await _git(fixture.root, [
    'update-ref',
    'refs/remotes/origin/feature',
    fixture.comparison.baseTip,
  ]);

  await expectLater(
    repository.applyMergePreview(
      comparison: fixture.comparison,
      treeSha: fixture.comparison.merge.treeSha!,
    ),
    throwsA(
      isA<GitRepositoryException>().having(
        (error) => error.message,
        'message',
        contains('브랜치가 바뀌어 미리보기를 다시 계산'),
      ),
    ),
  );
  expect(
    (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
    fixture.comparison.baseTip,
  );
});
```

기존 `branch preview restore rejects changed tips without partial moves`
테스트는 Merge가 비교 브랜치를 원복 대상으로 삼지 않는 새 규칙과
맞지 않는다. 다음 테스트로 교체한다.

```dart
test('merge restore ignores changes to its read-only comparison ref', () async {
  final fixture = await _branchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  final repository = GitRepository(fixture.root.path);
  final applied = await repository.applyMergePreview(
    comparison: fixture.comparison,
    treeSha: fixture.comparison.merge.treeSha!,
  );
  await _git(fixture.root, [
    'branch',
    '-f',
    'feature',
    fixture.comparison.baseTip,
  ]);

  await repository.restoreBranchApply(applied);

  expect(
    (await _git(fixture.root, ['rev-parse', 'main'])).trim(),
    fixture.comparison.baseTip,
  );
  expect(
    (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
    fixture.comparison.baseTip,
  );
});
```

- [ ] **Step 2: 원격 Merge 테스트가 현재 로컬 ref 검증에서 실패하는지 확인**

Run:

```bash
flutter test test/git_test.dart --plain-name 'remote merge preview updates only the local base'
flutter test test/git_test.dart --plain-name 'remote merge apply rejects a changed remote tip'
flutter test test/git_test.dart --plain-name 'merge restore ignores changes to its read-only comparison ref'
```

Expected: 세 테스트 모두 현재 로컬 전용 검증·원복 규칙과 달라 FAIL

- [ ] **Step 3: 실제 ref tip 검증과 Merge 전용 원복 구현**

`BranchApplyResult`에 Rebase 작업에서만 사용할 기본값 필드를 추가해
기존 생성 코드를 깨뜨리지 않는다.

```dart
class BranchApplyResult {
  const BranchApplyResult({
    required this.mode,
    required this.baseBranch,
    required this.compareBranch,
    required this.baseBefore,
    required this.baseAfter,
    required this.compareBefore,
    required this.compareAfter,
    this.compareBranchCreated = false,
  });

  final BranchApplyMode mode;
  final String baseBranch;
  final String compareBranch;
  final String baseBefore;
  final String baseAfter;
  final String compareBefore;
  final String compareAfter;
  final bool compareBranchCreated;
}
```

`_verifyApplyTips`는 두 입력을 모두 로컬 브랜치로 가정하지 않고
`RepoRefs`에서 실제 전체 ref 경로를 정해 확인한다. 확인에 사용한
목록을 반환해서 변경 대상 계산에도 그대로 쓴다.

```dart
Future<String> _refTip(String ref, RepoRefs refs) async {
  final fullRef = refs.local.contains(ref)
      ? 'refs/heads/$ref'
      : refs.remote.contains(ref)
      ? 'refs/remotes/$ref'
      : null;
  if (fullRef == null) {
    throw GitRepositoryException(ref, '브랜치를 찾을 수 없습니다.');
  }
  return (await _run([
    'rev-parse',
    '--verify',
    '$fullRef^{commit}',
  ])).trim();
}

Future<RepoRefs> _verifyApplyTips(
  BranchComparisonResult comparison,
) async {
  final refs = await loadRefs();
  if (await _refTip(comparison.baseRef, refs) != comparison.baseTip ||
      await _refTip(comparison.compareRef, refs) != comparison.compareTip) {
    throw GitRepositoryException(root, '브랜치가 바뀌어 미리보기를 다시 계산해야 합니다.');
  }
  return refs;
}
```

`applyMergePreview`에서는 검증한 목록으로 로컬 기준 브랜치를 다시
정한다. `compareAfter`는 로컬 브랜치에서 읽지 않고 검증한 원격 비교
tip을 그대로 기록한다.

```dart
Future<BranchApplyResult> applyMergePreview({
  required BranchComparisonResult comparison,
  required String treeSha,
}) async {
  final refs = await _verifyApplyTips(comparison);
  final target = resolveBranchApplyTarget(
    mode: BranchApplyMode.merge,
    comparison: comparison,
    refs: refs,
  );
  if (target == null || target.needsRecalculation) {
    throw GitRepositoryException(
      root,
      '로컬 기준 브랜치로 미리보기를 다시 계산해야 합니다.',
    );
  }
  final tree = (await _run([
    'rev-parse',
    '--verify',
    '$treeSha^{tree}',
  ])).trim();
  final mergeCommit = (await _run([
    '-c',
    'commit.gpgSign=false',
    'commit-tree',
    tree,
    '-p',
    comparison.baseTip,
    '-p',
    comparison.compareTip,
    '-m',
    "Merge branch '${comparison.compareRef}' into ${comparison.baseRef}",
  ])).trim();
  await _moveLocalBranch(
    branch: target.localBranch,
    expected: target.selectedTip,
    next: mergeCommit,
  );
  return BranchApplyResult(
    mode: BranchApplyMode.merge,
    baseBranch: target.localBranch,
    compareBranch: comparison.compareRef,
    baseBefore: comparison.baseTip,
    baseAfter: await _localBranchTip(target.localBranch),
    compareBefore: comparison.compareTip,
    compareAfter: comparison.compareTip,
  );
}
```

`restoreBranchApply`는 적용 방식에 따라 실제로 변경된 로컬 브랜치
하나만 검증하고 이동한다.

```dart
Future<void> restoreBranchApply(BranchApplyResult result) async {
  if (result.mode == BranchApplyMode.merge) {
    if (await _localBranchTip(result.baseBranch) != result.baseAfter) {
      throw GitRepositoryException(root, '적용 뒤 브랜치가 바뀌어 이전 시점으로 되돌릴 수 없습니다.');
    }
    await _moveLocalBranch(
      branch: result.baseBranch,
      expected: result.baseAfter,
      next: result.baseBefore,
    );
    return;
  }
  if (await _localBranchTip(result.compareBranch) != result.compareAfter) {
    throw GitRepositoryException(root, '적용 뒤 브랜치가 바뀌어 이전 시점으로 되돌릴 수 없습니다.');
  }
  await _moveLocalBranch(
    branch: result.compareBranch,
    expected: result.compareAfter,
    next: result.compareBefore,
  );
}
```

- [ ] **Step 4: 원격 Merge와 기존 적용·원복 테스트 실행**

Run:

```bash
flutter test test/git_test.dart --plain-name 'remote merge preview updates only the local base'
flutter test test/git_test.dart --plain-name 'remote merge apply rejects a changed remote tip'
flutter test test/git_test.dart --plain-name 'merge restore ignores changes to its read-only comparison ref'
flutter test test/git_test.dart --plain-name 'merge preview applies locally and restores both exact tips'
flutter test test/git_test.dart --plain-name 'rebase preview applies its virtual tip and restores both tips'
```

Expected: 모두 PASS

- [ ] **Step 5: 원격 Merge 적용 변경 커밋**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: apply remote merge previews locally"
```

---

### Task 3: 원격 Rebase 대상을 로컬 추적 브랜치로 적용하고 원복

**Files:**
- Modify: `lib/git.dart:2043-2140`
- Test: `test/git_test.dart:1120-1270,2260-2320`

**Interfaces:**
- Consumes: `BranchApplyTarget`, `resolveBranchApplyTarget(...)`, Task 2의 `compareBranchCreated`
- Produces: 원격 비교 ref를 지원하는 기존 `applyRebasePreview(...)`, 생성한 로컬 브랜치를 삭제하는 `restoreBranchApply(...)`

- [ ] **Step 1: 원격 Rebase 적용·upstream·원복 실패 테스트 작성**

```dart
test('remote rebase preview creates a local tracking branch and undo removes it',
    () async {
  final fixture = await _remoteBranchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  final commands = <List<String>>[];
  final repository = GitRepository(
    fixture.root.path,
    runner: (executable, arguments, {workingDirectory, environment}) async {
      commands.add(List<String>.of(arguments));
      return runProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    },
  );
  final session = await repository.openRebasePreview(
    baseRef: 'main',
    compareRef: 'origin/feature',
  );
  addTearDown(session.dispose);
  final preview = await session.start();

  final applied = await repository.applyRebasePreview(
    comparison: fixture.comparison,
    virtualTip: preview.virtualTip!,
  );

  expect(applied.compareBranch, 'feature');
  expect(applied.compareBranchCreated, isTrue);
  expect(
    (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
    preview.virtualTip,
  );
  expect(
    (await _git(fixture.root, [
      'rev-parse',
      '--abbrev-ref',
      'feature@{upstream}',
    ])).trim(),
    'origin/feature',
  );
  expect(
    (await _git(fixture.root, ['rev-parse', 'origin/feature'])).trim(),
    fixture.remoteTip,
  );

  await repository.restoreBranchApply(applied);

  final localFeature = await Process.run(
    'git',
    ['show-ref', '--verify', 'refs/heads/feature'],
    workingDirectory: fixture.root.path,
  );
  expect(localFeature.exitCode, 1);
  expect(
    (await _git(fixture.root, ['rev-parse', 'origin/feature'])).trim(),
    fixture.remoteTip,
  );
  expect(
    commands.where(
      (arguments) =>
          arguments.isNotEmpty &&
          (arguments.first == 'push' || arguments.first == 'fetch'),
    ),
    isEmpty,
  );
});
```

같은 이름의 로컬 브랜치가 다른 SHA에 있으면 적용을 거부하는 테스트도
추가한다.

```dart
test('remote rebase apply rejects a divergent same-named local branch',
    () async {
  final fixture = await _remoteBranchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  await _git(fixture.root, ['branch', 'feature', 'main']);
  final repository = GitRepository(fixture.root.path);

  await expectLater(
    repository.applyRebasePreview(
      comparison: fixture.comparison,
      virtualTip: fixture.comparison.baseTip,
    ),
    throwsA(
      isA<GitRepositoryException>().having(
        (error) => error.message,
        'message',
        contains('기존 로컬 브랜치 기준으로 미리보기를 다시 계산'),
      ),
    ),
  );
  expect(
    (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
    fixture.comparison.baseTip,
  );
});

test('remote rebase reuses a matching local branch and undo keeps it',
    () async {
  final fixture = await _remoteBranchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  await _git(fixture.root, [
    'branch',
    '--no-track',
    'feature',
    'origin/feature',
  ]);
  final repository = GitRepository(fixture.root.path);
  final session = await repository.openRebasePreview(
    baseRef: 'main',
    compareRef: 'origin/feature',
  );
  addTearDown(session.dispose);
  final preview = await session.start();

  final applied = await repository.applyRebasePreview(
    comparison: fixture.comparison,
    virtualTip: preview.virtualTip!,
  );
  expect(applied.compareBranchCreated, isFalse);

  await repository.restoreBranchApply(applied);

  expect(
    (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
    fixture.remoteTip,
  );
  final upstream = await Process.run(
    'git',
    ['rev-parse', '--abbrev-ref', 'feature@{upstream}'],
    workingDirectory: fixture.root.path,
  );
  expect(upstream.exitCode, isNot(0));
});

test('rebase apply rejects a target checked out in another worktree', () async {
  final fixture = await _remoteBranchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  await _git(fixture.root, [
    'branch',
    '--no-track',
    'feature',
    'origin/feature',
  ]);
  final temporary = await Directory.systemTemp.createTemp(
    'yogit_apply_worktree_',
  );
  final worktreePath = temporary.path;
  await temporary.delete();
  await _git(fixture.root, ['worktree', 'add', worktreePath, 'feature']);
  addTearDown(() async {
    await Process.run(
      'git',
      ['worktree', 'remove', '--force', worktreePath],
      workingDirectory: fixture.root.path,
    );
    final directory = Directory(worktreePath);
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  final repository = GitRepository(fixture.root.path);

  await expectLater(
    repository.applyRebasePreview(
      comparison: fixture.comparison,
      virtualTip: fixture.comparison.baseTip,
    ),
    throwsA(
      isA<GitRepositoryException>().having(
        (error) => error.message,
        'message',
        contains('다른 worktree에서 체크아웃한 브랜치'),
      ),
    ),
  );
  expect(
    (await _git(fixture.root, ['rev-parse', 'feature'])).trim(),
    fixture.remoteTip,
  );
});
```

- [ ] **Step 2: 원격 Rebase 테스트가 로컬 브랜치를 찾지 못해 실패하는지 확인**

Run:

```bash
flutter test test/git_test.dart --plain-name 'remote rebase preview creates a local tracking branch and undo removes it'
flutter test test/git_test.dart --plain-name 'remote rebase apply rejects a divergent same-named local branch'
flutter test test/git_test.dart --plain-name 'remote rebase reuses a matching local branch and undo keeps it'
flutter test test/git_test.dart --plain-name 'rebase apply rejects a target checked out in another worktree'
```

Expected: 원격 비교 ref를 로컬 브랜치로 처리하는 현재 구현과 오류
문구가 달라 네 테스트 모두 FAIL

- [ ] **Step 3: 로컬 추적 브랜치 생성과 예상 SHA 삭제 구현**

새로 만든 브랜치를 안전하게 지우는 도우미를 추가한다.

```dart
Future<void> _deleteLocalBranch({
  required String branch,
  required String expected,
}) async {
  if (await _localBranchTip(branch) != expected) {
    throw GitRepositoryException(branch, '브랜치가 바뀌어 삭제하지 않았습니다.');
  }
  await _run(['branch', '-D', branch]);
}
```

다른 worktree에서 체크아웃한 브랜치를 `update-ref`로 우회해 움직이지
않도록 `worktree list --porcelain` 결과를 확인한다.

```dart
Future<String?> _branchWorktreePath(String branch) async {
  final output = await _run(['worktree', 'list', '--porcelain']);
  String? path;
  for (final line in output.split('\n')) {
    if (line.startsWith('worktree ')) {
      path = line.substring('worktree '.length);
    } else if (line == 'branch refs/heads/$branch') {
      return path;
    } else if (line.isEmpty) {
      path = null;
    }
  }
  return null;
}
```

기존 `_moveLocalBranch`에서 현재 브랜치를 처리한 분기 뒤와
`update-ref` 호출 사이에 다음 검사를 넣는다.

```dart
final worktreePath = await _branchWorktreePath(branch);
if (worktreePath != null) {
  throw GitRepositoryException(
    branch,
    '다른 worktree에서 체크아웃한 브랜치라 적용할 수 없습니다.',
  );
}
```

`applyRebasePreview`에서 최신 ref 목록으로 변경 대상을 다시 계산하고
다른 로컬 SHA가 있으면 중단한다. 새 브랜치를 만든 뒤 적용에 실패하면
생성 당시 SHA가 유지된 경우에만 정리한다.

```dart
Future<BranchApplyResult> applyRebasePreview({
  required BranchComparisonResult comparison,
  required String virtualTip,
}) async {
  final refs = await _verifyApplyTips(comparison);
  final rewrittenTip = (await _run([
    'rev-parse',
    '--verify',
    '$virtualTip^{commit}',
  ])).trim();
  final target = resolveBranchApplyTarget(
    mode: BranchApplyMode.rebase,
    comparison: comparison,
    refs: refs,
  );
  if (target == null || target.needsRecalculation) {
    throw GitRepositoryException(
      root,
      '기존 로컬 브랜치 기준으로 미리보기를 다시 계산해야 합니다.',
    );
  }

  var created = false;
  try {
    if (target.createsBranch) {
      await _run([
        'branch',
        '--no-track',
        target.localBranch,
        target.selectedTip,
      ]);
      created = true;
      await _run([
        'branch',
        '--set-upstream-to=${target.selectedRef}',
        target.localBranch,
      ]);
      final refreshedRefs = await loadRefs();
      if (await _refTip(target.selectedRef, refreshedRefs) !=
              target.selectedTip ||
          await _localBranchTip(target.localBranch) != target.selectedTip) {
        throw GitRepositoryException(
          target.localBranch,
          '원격 브랜치가 바뀌어 미리보기를 다시 계산해야 합니다.',
        );
      }
    }
    await _moveLocalBranch(
      branch: target.localBranch,
      expected: target.selectedTip,
      next: rewrittenTip,
    );
    return BranchApplyResult(
      mode: BranchApplyMode.rebase,
      baseBranch: comparison.baseRef,
      compareBranch: target.localBranch,
      baseBefore: comparison.baseTip,
      baseAfter: comparison.baseTip,
      compareBefore: comparison.compareTip,
      compareAfter: await _localBranchTip(target.localBranch),
      compareBranchCreated: created,
    );
  } catch (_) {
    if (created) {
      try {
        await _deleteLocalBranch(
          branch: target.localBranch,
          expected: target.selectedTip,
        );
      } on Object {
        // 예상 SHA가 아니면 사용자 작업일 수 있으므로 남긴다.
      }
    }
    rethrow;
  }
}
```

`restoreBranchApply`의 Rebase 분기에서 생성 여부에 따라 삭제하거나
기존 SHA로 이동한다.

```dart
if (result.compareBranchCreated) {
  await _deleteLocalBranch(
    branch: result.compareBranch,
    expected: result.compareAfter,
  );
} else {
  await _moveLocalBranch(
    branch: result.compareBranch,
    expected: result.compareAfter,
    next: result.compareBefore,
  );
}
```

- [ ] **Step 4: 적용 실패 뒤 생성 브랜치 정리 테스트 작성**

`update-ref refs/heads/feature`만 실패시키는 runner로 저장소를 만들고,
적용 뒤 로컬 `feature`가 남지 않는지 확인한다.

```dart
test('failed remote rebase apply removes its unchanged created branch',
    () async {
  final fixture = await _remoteBranchPreviewFixture();
  addTearDown(() => fixture.root.delete(recursive: true));
  final repository = GitRepository(
    fixture.root.path,
    runner: (executable, arguments, {workingDirectory, environment}) async {
      if (arguments case [
        'update-ref',
        'refs/heads/feature',
        _,
        _,
      ]) {
        return ProcessResult(1, 1, '', 'forced update failure');
      }
      return runProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    },
  );

  await expectLater(
    repository.applyRebasePreview(
      comparison: fixture.comparison,
      virtualTip: fixture.comparison.baseTip,
    ),
    throwsA(isA<ProcessException>()),
  );

  final localFeature = await Process.run(
    'git',
    ['show-ref', '--verify', 'refs/heads/feature'],
    workingDirectory: fixture.root.path,
  );
  expect(localFeature.exitCode, 1);
  expect(
    (await _git(fixture.root, ['rev-parse', 'origin/feature'])).trim(),
    fixture.remoteTip,
  );
});
```

- [ ] **Step 5: 원격 Rebase, 실패 정리, 전체 Git 테스트 실행**

Run:

```bash
flutter test test/git_test.dart --plain-name 'remote rebase preview creates a local tracking branch and undo removes it'
flutter test test/git_test.dart --plain-name 'remote rebase apply rejects a divergent same-named local branch'
flutter test test/git_test.dart --plain-name 'remote rebase reuses a matching local branch and undo keeps it'
flutter test test/git_test.dart --plain-name 'rebase apply rejects a target checked out in another worktree'
flutter test test/git_test.dart --plain-name 'failed remote rebase apply removes its unchanged created branch'
flutter test test/git_test.dart
```

Expected: 모두 PASS

- [ ] **Step 6: 원격 Rebase 적용 변경 커밋**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: apply remote rebase previews to local branches"
```

---

### Task 4: 원격 비교 미리보기의 적용 화면과 재계산 흐름

**Files:**
- Modify: `lib/timeline.dart:720-750,1927-1985,3585-3785,3820-3970`
- Modify: `test/app_test.dart:3980-4370,13920-14170`

**Interfaces:**
- Consumes: `resolveBranchApplyTarget(...)`, 기존 `applyMergePreview(...)`, `applyRebasePreview(...)`
- Produces: `_branchPreviewTarget`, `_prepareBranchPreviewApply()`, 원격 비교 브랜치용 적용 안내와 확인창

- [ ] **Step 1: 원격 Merge 적용 버튼과 안내 실패 테스트 작성**

기존 `remote branch preview cannot be applied directly` 테스트를 다음
기대로 교체한다.

```dart
testWidgets('remote merge preview applies to the local base only', (
  tester,
) async {
  final comparison = branchComparison(
    compareRef: 'origin/feature',
    merge: const MergeConflictCheck(
      status: MergeConflictStatus.clean,
      treeSha: 'merge-tree',
    ),
  );
  var applied = false;
  var restored = false;
  await tester.pumpWidget(
    app(
      FakeGitRepository(
        (_, _) async => [commit('normal', 'normal history')],
        refs: const RepoRefs(
          local: ['main'],
          remote: ['origin/feature'],
          current: 'main',
          tips: {'main': 'main-tip', 'origin/feature': 'feature-tip'},
          localTips: {'main': 'main-tip'},
        ),
        compareBranchesCallback: (_, _) async => comparison,
        applyMergePreviewCallback:
            ({required comparison, required treeSha}) async {
              applied = true;
              return const BranchApplyResult(
                mode: BranchApplyMode.merge,
                baseBranch: 'main',
                compareBranch: 'origin/feature',
                baseBefore: 'main-tip',
                baseAfter: 'merge-tip',
                compareBefore: 'feature-tip',
                compareAfter: 'feature-tip',
              );
            },
        restoreBranchApplyCallback: (_) async => restored = true,
      ),
      controller,
    ),
  );

  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('branch-diff-selector')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('branch-diff-menu-origin/feature')),
  );
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();

  expect(
    find.text('origin/feature는 입력으로만 사용합니다. 실제 변경은 로컬 main에 적용됩니다.'),
    findsOneWidget,
  );
  final button = tester.widget<FilledButton>(
    find.byKey(const Key('branch-preview-apply')),
  );
  expect(button.onPressed, isNotNull);
  expect(
    find.text('origin/feature를 main에 Merge 실제 적용'),
    findsOneWidget,
  );

  await tester.tap(find.byKey(const Key('branch-preview-apply')));
  await tester.pumpAndSettle();
  expect(
    find.textContaining('로컬 main 브랜치만 변경합니다'),
    findsOneWidget,
  );
  expect(
    find.textContaining('원격 추적 브랜치와 원격 저장소는 변경하지 않습니다'),
    findsOneWidget,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Merge 실제 적용'));
  await tester.pumpAndSettle();

  expect(applied, isTrue);
  expect(find.textContaining('main: main-tip → merge-tip'), findsOneWidget);
  expect(find.textContaining('origin/feature: 변경 없음'), findsOneWidget);

  await tester.tap(find.byKey(const Key('branch-preview-rollback')));
  await tester.pumpAndSettle();
  expect(
    find.textContaining('로컬 main을 main-tip으로 되돌립니다'),
    findsOneWidget,
  );
  expect(
    find.textContaining('origin/feature는 변경하지 않습니다'),
    findsOneWidget,
  );
  await tester.tap(find.widgetWithText(FilledButton, '되돌리기'));
  await tester.pumpAndSettle();
  expect(restored, isTrue);
});
```

- [ ] **Step 2: 원격 Rebase 로컬 생성과 재계산 실패 테스트 작성**

로컬 브랜치가 없을 때 생성 안내와 활성화된 적용 버튼을 확인한다.

```dart
testWidgets('remote rebase preview creates a local branch before apply', (
  tester,
) async {
  final comparison = branchComparison(compareRef: 'origin/feature');
  final original = comparison.commits
      .singleWhere((entry) => entry.side == BranchCommitSide.compareOnly)
      .commit;
  final preview = RebasePreviewResult(
    status: RebasePreviewStatus.clean,
    baseTip: comparison.baseTip,
    compareTip: comparison.compareTip,
    rewritten: [(original: original, rewrittenSha: 'rewritten-feature')],
    completed: 1,
    total: 1,
    virtualTip: 'rewritten-feature',
  );
  var applied = false;
  var restored = false;
  late FakeGitRepository repository;
  repository = FakeGitRepository(
    (_, _) async => [commit('normal', 'normal history')],
    refs: const RepoRefs(
      local: ['main'],
      remote: ['origin/feature'],
      current: 'main',
      tips: {'main': 'main-tip', 'origin/feature': 'feature-tip'},
      localTips: {'main': 'main-tip'},
    ),
    compareBranchesCallback: (_, _) async => comparison,
    openRebasePreviewCallback:
        ({required baseRef, required compareRef}) async =>
            FakeRebasePreviewSession(repository, preview),
    applyRebasePreviewCallback:
        ({required comparison, required virtualTip}) async {
          applied = true;
          return const BranchApplyResult(
            mode: BranchApplyMode.rebase,
            baseBranch: 'main',
            compareBranch: 'feature',
            baseBefore: 'main-tip',
            baseAfter: 'main-tip',
            compareBefore: 'feature-tip',
            compareAfter: 'rewritten-feature',
            compareBranchCreated: true,
          );
        },
    restoreBranchApplyCallback: (_) async => restored = true,
    filesBetween: (_, _) async => const [],
  );
  await tester.pumpWidget(
    app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('branch-diff-selector')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('branch-diff-menu-origin/feature')),
  );
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();

  expect(
    find.text('로컬 feature를 origin/feature에서 만든 뒤 결과를 적용합니다.'),
    findsOneWidget,
  );
  expect(
    find.text('main 위로 feature Rebase 실제 적용'),
    findsOneWidget,
  );
  expect(
    tester
        .widget<FilledButton>(find.byKey(const Key('branch-preview-apply')))
        .onPressed,
    isNotNull,
  );

  await tester.tap(find.byKey(const Key('branch-preview-apply')));
  await tester.pumpAndSettle();
  expect(
    find.textContaining('로컬 feature 브랜치만 변경합니다'),
    findsOneWidget,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Rebase 실제 적용'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 220));
  await tester.pumpAndSettle();
  expect(applied, isTrue);
  expect(
    find.textContaining('feature: 새 브랜치 → rewritten-feature'),
    findsOneWidget,
  );
  expect(find.textContaining('origin/feature: 변경 없음'), findsOneWidget);

  await tester.tap(find.byKey(const Key('branch-preview-rollback')));
  await tester.pumpAndSettle();
  expect(
    find.textContaining('적용 과정에서 만든 로컬 feature를 삭제합니다'),
    findsOneWidget,
  );
  await tester.tap(find.widgetWithText(FilledButton, '되돌리기'));
  await tester.pumpAndSettle();
  expect(restored, isTrue);
});
```

같은 이름의 로컬 브랜치가 다른 SHA에 있는 경우에는 첫 버튼이 재계산
동작으로 바뀌는 테스트를 추가한다.

```dart
testWidgets('divergent local rebase target recalculates before apply', (
  tester,
) async {
  final comparisons = <String>[];
  late FakeGitRepository repository;
  repository = FakeGitRepository(
    (_, _) async => [commit('normal', 'normal history')],
    refs: const RepoRefs(
      local: ['main', 'feature'],
      remote: ['origin/feature'],
      current: 'main',
      tips: {
        'main': 'main-tip',
        'feature': 'local-tip',
        'origin/feature': 'feature-tip',
      },
      localTips: {'main': 'main-tip', 'feature': 'local-tip'},
    ),
    compareBranchesCallback: (base, compare) async {
      comparisons.add(compare);
      return branchComparison(
        compareRef: compare,
        compareTip: compare == 'feature' ? 'local-tip' : 'feature-tip',
      );
    },
    openRebasePreviewCallback:
        ({required baseRef, required compareRef}) async {
          final compareTip = compareRef == 'feature'
              ? 'local-tip'
              : 'feature-tip';
          final original = commit(
            compareTip,
            'feature only',
            parents: const ['root'],
          );
          return FakeRebasePreviewSession(
            repository,
            RebasePreviewResult(
              status: RebasePreviewStatus.clean,
              baseTip: 'main-tip',
              compareTip: compareTip,
              rewritten: [
                (original: original, rewrittenSha: 'rewritten-$compareTip'),
              ],
              completed: 1,
              total: 1,
              virtualTip: 'rewritten-$compareTip',
            ),
          );
        },
    filesBetween: (_, _) async => const [],
  );
  await tester.pumpWidget(
    app(repository, controller, branchPreviewMode: BranchPreviewMode.rebase),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('branch-diff-selector')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('branch-diff-menu-origin/feature')),
  );
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();

  expect(
    find.text('로컬 feature 기준으로 다시 계산'),
    findsOneWidget,
  );
  await tester.tap(find.byKey(const Key('branch-preview-apply')));
  await tester.pumpAndSettle();

  expect(comparisons, ['origin/feature', 'feature']);
  expect(
    find.text('기존 로컬 feature 기준으로 미리보기를 다시 계산했습니다.'),
    findsOneWidget,
  );
});
```

- [ ] **Step 3: 화면 테스트가 기존 비활성 조건 때문에 실패하는지 확인**

Run:

```bash
flutter test test/app_test.dart --plain-name 'remote merge preview applies to the local base only'
flutter test test/app_test.dart --plain-name 'remote rebase preview creates a local branch before apply'
flutter test test/app_test.dart --plain-name 'divergent local rebase target recalculates before apply'
```

Expected: 원격 ref가 포함되면 `_branchPreviewCanApply`가 false라 FAIL

- [ ] **Step 4: 변경 대상 getter와 준비 동작 구현**

`_TimelineScreenState`에 현재 모드와 ref 목록을 사용하는 getter를
추가한다.

```dart
BranchApplyTarget? get _branchPreviewTarget {
  final comparison = _comparison;
  if (comparison == null) return null;
  return resolveBranchApplyTarget(
    mode: _branchPreviewMode == BranchPreviewMode.merge
        ? BranchApplyMode.merge
        : BranchApplyMode.rebase,
    comparison: comparison,
    refs: _refs,
  );
}

bool get _branchPreviewCanPrepare =>
    _branchPreviewReady && _branchPreviewTarget != null;

bool get _branchPreviewCanApply =>
    _branchPreviewCanPrepare &&
    !_branchPreviewTarget!.needsRecalculation;
```

적용 버튼을 누르면 기존 로컬 브랜치와 SHA가 다른 경우 먼저 해당
브랜치로 비교를 다시 계산한다.

```dart
Future<void> _prepareBranchPreviewApply() async {
  final target = _branchPreviewTarget;
  if (target == null || !_branchPreviewReady || _branchApplyBusy) return;
  if (target.needsRecalculation) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '기존 로컬 ${target.localBranch} 기준으로 미리보기를 다시 계산했습니다.',
        ),
      ),
    );
    await _selectComparison(target.localBranch);
    return;
  }
  await _confirmBranchPreviewApply();
}
```

버튼은 준비 가능한 경우 활성화하고 재계산이 필요하면 실제 적용 대신
재계산 문구를 표시한다.

```dart
onPressed: _branchApplyBusy || !_branchPreviewCanPrepare
    ? null
    : () => unawaited(_prepareBranchPreviewApply()),

String get _branchPreviewApplyLabel {
  final comparison = _comparison!;
  final target = _branchPreviewTarget;
  if (target?.needsRecalculation == true) {
    return '로컬 ${target!.localBranch} 기준으로 다시 계산';
  }
  return _branchPreviewMode == BranchPreviewMode.merge
      ? '${comparison.compareRef}를 ${target!.localBranch}에 Merge 실제 적용'
      : '${comparison.baseRef} 위로 ${target!.localBranch} Rebase 실제 적용';
}
```

- [ ] **Step 5: 적용 카드, 확인창, 원복 문구를 로컬 변경 하나에 맞춤**

적용 전 안내는 `BranchApplyTarget` 상태에 따라 한 문장만 고른다.

```dart
String get _branchPreviewApplyHelp {
  final comparison = _comparison!;
  final target = _branchPreviewTarget;
  if (target == null) return '적용할 로컬 브랜치를 찾을 수 없습니다.';
  if (target.needsRecalculation) {
    return '기존 로컬 ${target.localBranch} 기준으로 다시 계산해야 합니다.';
  }
  if (target.createsBranch) {
    return '로컬 ${target.localBranch}를 ${target.selectedRef}에서 만든 뒤 결과를 적용합니다.';
  }
  if (_branchPreviewMode == BranchPreviewMode.merge &&
      _refs.remote.contains(comparison.compareRef)) {
    return '${comparison.compareRef}는 입력으로만 사용합니다. 실제 변경은 로컬 ${target.localBranch}에 적용됩니다.';
  }
  return '가상 결과를 로컬 ${target.localBranch}에 적용할 수 있습니다.';
}
```

적용 카드의 기존 조건부 안내를 다음 코드로 교체해서 Merge와
Rebase 모두 항상 계산된 안내를 표시한다.

```dart
Text(
  _branchPreviewApplyHelp,
  style: TextStyle(color: _palette.muted, fontSize: 10),
),
const SizedBox(height: 7),
```

`_confirmBranchPreviewApply`는 계산한 대상이 실제 적용 가능한지 다시
확인하고 다음 문구를 사용한다.

```dart
final target = _branchPreviewTarget;
if (comparison == null ||
    target == null ||
    !_branchPreviewCanApply ||
    _branchApplyBusy) {
  return;
}

final content =
    '기준 브랜치 ${comparison.baseRef}\n'
    '${comparison.baseTip}\n\n'
    '대상 브랜치 ${comparison.compareRef}\n'
    '${comparison.compareTip}\n\n'
    '로컬 ${target.localBranch} 브랜치만 변경합니다. '
    '원격 추적 브랜치와 원격 저장소는 변경하지 않습니다.\n'
    '완료 뒤 적용 전 SHA로 되돌릴 수 있습니다.';
```

완료 카드에는 실제 변경한 로컬 브랜치와 읽기 전용 원격 ref만
표시한다.

```dart
String get _branchPreviewAppliedSummary {
  final result = _branchApplyResult!;
  final local = result.mode == BranchApplyMode.merge
      ? '${result.baseBranch}: ${result.baseBefore} → ${result.baseAfter}'
      : result.compareBranchCreated
      ? '${result.compareBranch}: 새 브랜치 → ${result.compareAfter}'
      : '${result.compareBranch}: ${result.compareBefore} → ${result.compareAfter}';
  final compareRef = _comparison?.compareRef;
  return compareRef != null && _refs.remote.contains(compareRef)
      ? '$local\n$compareRef: 변경 없음'
      : local;
}
```

기존 두 SHA 줄을 출력하던 `Text`에는
`_branchPreviewAppliedSummary`를 전달한다. 원복 확인창도 실제 변경한
로컬 브랜치 하나만 설명한다.

```dart
String _branchPreviewRollbackMessage(BranchApplyResult result) {
  final local = result.mode == BranchApplyMode.merge
      ? '로컬 ${result.baseBranch}을 ${result.baseBefore}으로 되돌립니다.'
      : result.compareBranchCreated
      ? '적용 과정에서 만든 로컬 ${result.compareBranch}를 삭제합니다.'
      : '로컬 ${result.compareBranch}를 ${result.compareBefore}으로 되돌립니다.';
  final compareRef = _comparison?.compareRef;
  final remote = compareRef != null && _refs.remote.contains(compareRef)
      ? '\n$compareRef는 변경하지 않습니다.'
      : '';
  return '$local$remote\n원격 저장소는 변경하지 않습니다.';
}
```

`_confirmBranchPreviewRollback`의 기존 두 브랜치 안내를
`_branchPreviewRollbackMessage(result)`로 교체한다.

- [ ] **Step 6: 원격 화면 테스트와 기존 로컬 적용 테스트 실행**

Run:

```bash
flutter test test/app_test.dart --plain-name 'remote merge preview applies to the local base only'
flutter test test/app_test.dart --plain-name 'remote rebase preview creates a local branch before apply'
flutter test test/app_test.dart --plain-name 'divergent local rebase target recalculates before apply'
flutter test test/app_test.dart --plain-name 'branch preview applies merge and restores its exact tips'
flutter test test/app_test.dart --plain-name 'branch preview applies rebase with a focused commit'
```

Expected: 모두 PASS

- [ ] **Step 7: 화면 적용 변경 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: enable local apply for remote branch previews"
```

---

### Task 5: 전체 검증

**Files:**
- Verify: `lib/git.dart`
- Verify: `lib/timeline.dart`
- Verify: `test/git_test.dart`
- Verify: `test/app_test.dart`

**Interfaces:**
- Consumes: Task 1~4의 모든 변경
- Produces: 분석·테스트·macOS 디버그 빌드를 통과한 작업 브랜치

- [ ] **Step 1: 변경 파일 서식 정리**

```bash
dart format lib/git.dart lib/timeline.dart test/git_test.dart test/app_test.dart
```

Expected: 네 파일이 Dart 표준 형식과 일치

- [ ] **Step 2: 정적 분석**

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Git 계층과 화면 테스트**

```bash
flutter test test/git_test.dart
flutter test test/app_test.dart
```

Expected: 모두 PASS

- [ ] **Step 4: 전체 테스트**

```bash
flutter test
```

Expected: 모든 테스트 PASS

- [ ] **Step 5: macOS 디버그 빌드**

```bash
flutter build macos --debug --no-pub
```

Expected: `✓ Built build/macos/Build/Products/Debug/yogit.app`

- [ ] **Step 6: 변경 범위와 금지 동작 확인**

```bash
git diff --check
git diff --name-only main...HEAD
git diff main...HEAD -- lib/git.dart | rg -n "['\"](push|fetch)['\"]|update-ref.*refs/remotes"
```

Expected:

- `git diff --check` 출력 없음
- 구현 파일과 테스트, 승인된 설계·계획 문서만 변경
- 마지막 검색 명령 출력 없음
