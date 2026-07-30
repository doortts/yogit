# Merge·Rebase Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Branch Diff에서 실제 저장소를 바꾸지 않고 Merge와 Rebase의 예상 타임라인, 최종 파일 차이, 충돌 진행 상태를 확인할 수 있게 한다.

**Architecture:** `GitRepository`가 merge tree와 임시 rebase worktree에서 미리보기 데이터를 만들고, `TimelineScreen`은 그 결과를 기존 Branch Diff 행과 기존 Full Diff 표시 위젯에 연결한다. 설정에는 마지막 미리보기 방식만 저장하며, 실제 브랜치와 기본 작업 트리는 어떤 단계에서도 갱신하지 않는다.

**Tech Stack:** Dart, Flutter, Git CLI (`merge-tree`, detached worktree, `rebase`), 기존 Full Diff 모델과 위젯

## Global Constraints

- 실제 브랜치, 인덱스, 기본 작업 트리는 변경하지 않는다.
- 기본 미리보기 방식은 Merge이며 마지막 선택을 `AppSettings`에 저장한다.
- 기존 Branch Diff가 아닌 일반 타임라인의 그래프 표시는 변경하지 않는다.
- 성공과 충돌 모두 Unified와 Side-by-side를 지원한다.
- 가상 연결선은 1px 점선이고 기존 브랜치 레일은 실선이다.
- Rebase 대응선은 기존 팔레트와 겹치지 않는 어두운 다섯 색을 사용한다.
- 새 패키지는 추가하지 않는다.

---

### Task 1: 미리보기 방식 설정 저장

**Files:**
- Modify: `lib/settings.dart:251-467`
- Modify: `lib/main.dart:280-354`
- Modify: `lib/timeline.dart:332-405`
- Test: `test/app_test.dart:3170-3300`

**Interfaces:**
- Produces: `enum BranchPreviewMode { merge, rebase }`
- Produces: `AppSettings.branchPreviewMode`
- Produces: `TimelineScreen.branchPreviewMode`
- Produces: `TimelineScreen.onBranchPreviewModeChanged`

- [ ] **Step 1: 저장과 복원 테스트 작성**

```dart
test('branch preview mode defaults to merge and restores rebase', () {
  expect(const AppSettings().branchPreviewMode, BranchPreviewMode.merge);
  const settings = AppSettings(branchPreviewMode: BranchPreviewMode.rebase);
  expect(AppSettings.fromJson(settings.toJson()), settings);
  expect(
    AppSettings.fromJson(const {'branchPreviewMode': 'unknown'})
        .branchPreviewMode,
    BranchPreviewMode.merge,
  );
});
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/app_test.dart --plain-name "branch preview mode defaults to merge and restores rebase"`

Expected: `BranchPreviewMode`와 `branchPreviewMode`가 없어서 컴파일 실패

- [ ] **Step 3: 최소 설정 필드 구현**

```dart
enum BranchPreviewMode { merge, rebase }

extension BranchPreviewModeStorage on BranchPreviewMode {
  static BranchPreviewMode parse(Object? value) =>
      value == 'rebase' ? BranchPreviewMode.rebase : BranchPreviewMode.merge;
}
```

`AppSettings` 생성자 기본값은 `BranchPreviewMode.merge`로 두고 `copyWith`에는 nullable 인자를 추가한다. `fromJson`은 `BranchPreviewModeStorage.parse`를 호출하고 `toJson`은 `.name`을 저장한다. 동등성 비교와 `Object.hash`에도 필드를 한 번씩 추가한다.

- [ ] **Step 4: 앱과 타임라인 연결**

```dart
TimelineScreen(
  branchPreviewMode: _settings.branchPreviewMode,
  onBranchPreviewModeChanged: _settingsLoaded
      ? (mode) => _changeSettings(_settings.copyWith(branchPreviewMode: mode))
      : null,
)
```

`TimelineScreen`은 전달받은 값을 `didUpdateWidget`에서 반영하고, 버튼 선택 시 콜백을 호출한다. 버튼 자체는 Task 5에서 표시한다.

- [ ] **Step 5: 테스트와 정적 검사**

Run: `flutter test test/app_test.dart --plain-name "branch preview mode defaults to merge and restores rebase"`

Expected: PASS

Run: `dart analyze lib/settings.dart lib/main.dart lib/timeline.dart`

Expected: `No issues found!`

- [ ] **Step 6: 커밋**

```bash
git add lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart
git commit -m "feat: remember branch preview mode"
```

### Task 2: Merge 결과 tree와 충돌 데이터 수집

**Files:**
- Modify: `lib/git.dart:250-330`
- Modify: `lib/git.dart:1162-1318`
- Test: `test/git_test.dart:612-699`

**Interfaces:**
- Replaces: `MergeConflictCheck` with `MergePreviewResult`
- Produces:

```dart
enum MergePreviewStatus { clean, conflicts, failed }

class MergePreviewResult {
  const MergePreviewResult({
    required this.status,
    this.treeSha,
    this.files = const [],
    this.conflictFiles = const [],
    this.error,
  });

  final MergePreviewStatus status;
  final String? treeSha;
  final List<GitFileChange> files;
  final List<String> conflictFiles;
  final String? error;
}
```

- Produces: `GitRepository.loadDiffBetween(String from, String to, GitFileChange file)` for tree SHA input as already supported

- [ ] **Step 1: 성공한 가상 Merge tree 테스트 작성**

기존 branch comparison fixture에 서로 다른 파일을 수정하는 clean merge를 추가하고 다음을 검증한다.

```dart
final result = await repository.compareBranches('main', 'feature');
expect(result.merge.status, MergePreviewStatus.clean);
expect(result.merge.treeSha, isNotEmpty);
expect(result.merge.files.map((file) => file.path), contains('feature.txt'));
expect((await _git(root, ['status', '--porcelain'])).trim(), isEmpty);
expect((await _git(root, ['rev-parse', 'main'])).trim(), result.baseTip);
```

- [ ] **Step 2: 충돌 결과 테스트 갱신**

```dart
expect(result.merge.status, MergePreviewStatus.conflicts);
expect(result.merge.treeSha, isNull);
expect(result.merge.conflictFiles, contains('shared.txt'));
```

- [ ] **Step 3: 실패 확인**

Run: `flutter test test/git_test.dart --plain-name "branch comparison returns virtual merge tree"`

Expected: `treeSha`와 `MergePreviewStatus`가 없어서 컴파일 실패

- [ ] **Step 4: `merge-tree` 출력에서 tree SHA 보존**

성공 시 `stdout`의 첫 NUL 구분 필드를 tree SHA로 읽고 `_loadFilesBetween(baseTip, treeSha)`를 호출한다. 충돌 시 현재 로직대로 `CONFLICT` 항목만 모은다.

```dart
if (result.exitCode == 0) {
  final treeSha = result.stdout.toString().split('\x00').first.trim();
  return MergePreviewResult(
    status: MergePreviewStatus.clean,
    treeSha: treeSha,
    files: await _loadFilesBetween(baseTip, treeSha),
  );
}
```

- [ ] **Step 5: 기존 호출부 이름 갱신**

`BranchComparisonResult.merge`와 타임라인 상태 문구가 새 enum과 `conflictFiles`를 사용하게 바꾼다. 화면 구조는 아직 바꾸지 않는다.

- [ ] **Step 6: Git 테스트 실행**

Run: `flutter test test/git_test.dart --plain-name "branch comparison"`

Expected: PASS

- [ ] **Step 7: 커밋**

```bash
git add lib/git.dart lib/timeline.dart test/git_test.dart
git commit -m "feat: expose virtual merge results"
```

### Task 3: Rebase 미리보기 세션

**Files:**
- Modify: `lib/git.dart:280-320`
- Modify: `lib/git.dart:1320-1435`
- Test: `test/git_test.dart:700-820`

**Interfaces:**
- Produces:

```dart
enum RebasePreviewStatus { clean, conflict, failed }

typedef RewrittenCommit = ({
  String originalSha,
  String rewrittenSha,
  String subject,
});

class RebasePreviewResult {
  const RebasePreviewResult({
    required this.status,
    required this.baseTip,
    required this.compareTip,
    this.rewritten = const [],
    this.currentCommit,
    this.completed = 0,
    this.total = 0,
    this.conflictFiles = const [],
    this.virtualTip,
    this.error,
  });

  final RebasePreviewStatus status;
  final String baseTip;
  final String compareTip;
  final List<RewrittenCommit> rewritten;
  final GitCommit? currentCommit;
  final int completed;
  final int total;
  final List<String> conflictFiles;
  final String? virtualTip;
  final String? error;
}
```

- Produces:

```dart
class RebasePreviewSession {
  Future<RebasePreviewResult> start();
  Future<void> markResolved(String relativePath);
  Future<RebasePreviewResult> continueAfterResolving();
  Future<void> dispose();
  String filePath(String relativePath);
}
```

- Produces: `GitRepository.openRebasePreview({required String baseRef, required String compareRef})`
- Produces: `GitRepository.operationInProgress()`

- [ ] **Step 1: 성공 시 SHA 대응 테스트 작성**

```dart
final session = await repository.openRebasePreview(
  baseRef: 'main',
  compareRef: 'feature',
);
addTearDown(session.dispose);
final result = await session.start();
expect(result.status, RebasePreviewStatus.clean);
expect(result.rewritten, hasLength(2));
expect(result.rewritten.map((entry) => entry.originalSha), originalShas);
expect(result.rewritten.every(
  (entry) => entry.originalSha != entry.rewrittenSha,
), isTrue);
expect(result.virtualTip, result.rewritten.last.rewrittenSha);
```

- [ ] **Step 2: 최초 충돌과 정리 테스트 작성**

```dart
final result = await session.start();
expect(result.status, RebasePreviewStatus.conflict);
expect(result.currentCommit?.subject, 'feature conflict');
expect(result.completed, 1);
expect(result.total, 3);
expect(result.conflictFiles, contains('shared.txt'));
await session.dispose();
expect(Directory(session.worktreePath).existsSync(), isFalse);
```

테스트 접근용으로 `@visibleForTesting String get worktreePath`를 제공한다.

- [ ] **Step 3: 실패 확인**

Run: `flutter test test/git_test.dart --plain-name "rebase preview"`

Expected: `openRebasePreview`와 새 결과 형식이 없어서 컴파일 실패

- [ ] **Step 4: 임시 worktree 생명주기 구현**

`Directory.systemTemp.createTemp('yogit_rebase_preview_')`로 경로를 만들고 `git worktree add --detach`를 실행한다. 시작 전 원본 커밋은 `git rev-list --reverse <base>..<compare>`와 기존 커밋 파서로 읽는다. Rebase 명령에는 기존 `simulateRebase()`의 hook, rerere, autostash, updateRefs, gpg 비활성화 옵션을 그대로 사용한다.

- [ ] **Step 5: 재작성 SHA 대응 수집**

세션 폴더 안에 앱 전용 `post-rewrite` hook과 매핑 파일을 만들고 해당 임시 worktree의 Rebase 명령에만 `-c core.hooksPath=<session-hooks>`를 건다. hook은 Git이 표준 입력으로 보내는 `<old-sha> <new-sha>` 쌍을 매핑 파일에 추가한다. 진행 중에는 worktree의 Git 디렉터리에 있는 `rebase-merge/rewritten-list`도 읽어 이미 끝난 커밋을 표시한다. 사용자의 hook은 실행하지 않는다.

충돌이면 `rebase-merge/stopped-sha`를 읽어 `currentCommit`을 정한다. `markResolved(path)`는 path가 세션 worktree 안에 있는지 확인하고 `git add -- <path>`를 실행한다. `continueAfterResolving()`은 `git diff --name-only --diff-filter=U`가 비어 있을 때만 `git rebase --continue`를 실행한 뒤 같은 결과 파서를 호출한다.

- [ ] **Step 6: 정리 보장**

`dispose()`는 진행 중인 Rebase를 중단하고 기본 저장소에서 `git worktree remove --force <path>`와 `git worktree prune`을 차례대로 시도한다. 두 번째 호출은 아무 일도 하지 않는다. 시작 중 오류가 나도 `dispose()`를 호출한다.

- [ ] **Step 7: 이전 실행에서 남은 임시 경로 정리**

첫 미리보기 세션을 열기 전에 `git worktree prune`을 한 번 실행한다. 시스템 임시 폴더에서 `yogit_rebase_preview_`로 시작하는 디렉터리만 찾고, 현재 `git worktree list --porcelain`에 없는 경로만 재귀 삭제한다. 다른 이름의 임시 폴더와 등록된 worktree는 건드리지 않는다.

- [ ] **Step 8: 진행 중인 Git 작업 조회 공개**

기존 `_gitOperationInProgress()`를 호출하는 공개 메서드만 추가한다.

```dart
Future<bool> operationInProgress() => _gitOperationInProgress();
```

- [ ] **Step 9: 기존 `simulateRebase()` 호환**

`simulateRebase()`는 새 세션을 열고 `start()` 결과를 기존 `RebaseCheckResult`로 변환한 뒤 `finally`에서 정리한다. 기존 호출부와 테스트를 깨지 않는다.

- [ ] **Step 10: 테스트 실행**

Run: `flutter test test/git_test.dart --plain-name "rebase"`

Expected: PASS

- [ ] **Step 11: 커밋**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: add isolated rebase preview sessions"
```

### Task 4: 가상 타임라인 투영과 선 그리기

**Files:**
- Modify: `lib/git.dart:320-405`
- Modify: `lib/timeline.dart:50-145`
- Modify: `lib/timeline.dart:4930-5240`
- Test: `test/git_test.dart:960-1080`

**Interfaces:**
- Produces:

```dart
enum PreviewGraphNodeKind { actual, virtualMerge, virtualRebase, conflictTarget }

typedef RebaseMapping = ({
  int originalRow,
  int virtualRow,
  int routeLane,
  Color color,
});
```

- Produces: `layoutMergePreview(...)` and `layoutRebasePreview(...)`
- Produces: `rebaseMappingColors(Iterable<Color> reserved)`
- Extends: `CommitGraphPainter` with `dashedRails`, `virtualNodeKind`, `mappingSegments`, and `nodeOutline`

- [ ] **Step 1: Merge 가상 노드 레이아웃 테스트 작성**

```dart
final preview = layoutMergePreview(comparison, comparison.merge);
expect(preview.rows.first.kind, PreviewGraphNodeKind.virtualMerge);
expect(preview.rows.first.dashedParentLanes, [0, 1]);
expect(preview.rows.skip(1).every((row) => row.dashedParentLanes.isEmpty), isTrue);
```

- [ ] **Step 2: Rebase 대응선 경로 테스트 작성**

다섯 커밋 fixture로 다음을 검증한다.

```dart
final preview = layoutRebasePreview(comparison, result, palette);
expect(preview.mappings.map((entry) => entry.color).toSet(), hasLength(5));
expect(preview.mappings.every((entry) => entry.width == 1), isTrue);
expect(preview.mappings.every((entry) => entry.hasArrow), isTrue);
expect(mappingPathsIntersectNodes(preview), isFalse);
expect(mappingPathsCross(preview), isFalse);
```

- [ ] **Step 3: 실패 확인**

Run: `flutter test test/git_test.dart --plain-name "preview graph"`

Expected: 레이아웃 함수와 가상 그래프 속성이 없어서 컴파일 실패

- [ ] **Step 4: 최소 투영 모델 구현**

기존 `GraphRow`는 일반 타임라인과 Branch Diff 실선 레일에 그대로 쓴다. 가상 노드, 점선 연결, 대응선은 별도 `PreviewGraphOverlay` 값으로 계산해 painter에 전달한다. Git 모델에는 색이나 좌표를 넣지 않는다.

- [ ] **Step 5: 어두운 전용 팔레트 선택**

현재 타임라인 팔레트와 테마 강조색을 `reserved`로 넘긴다. 채도 0.26, 명도 0.42에서 시작해 색상환을 67도씩 이동하며 다섯 색을 고른다. 이미 쓰는 색과 정확히 겹치면 11도씩 더 이동한다. 설계 문서에서 특정 색상값을 고정하지 않았으므로 현재 설정이 바뀌어도 겹치지 않게 계산한다.

```dart
List<Color> rebaseMappingColors(Iterable<Color> reserved) {
  final used = reserved.map((color) => color.toARGB32()).toSet();
  final result = <Color>[];
  var hue = 18.0;
  while (result.length < 5) {
    var color = HSLColor.fromAHSL(1, hue, 0.26, 0.42).toColor();
    while (used.contains(color.toARGB32())) {
      hue = (hue + 11) % 360;
      color = HSLColor.fromAHSL(1, hue, 0.26, 0.42).toColor();
    }
    result.add(color);
    used.add(color.toARGB32());
    hue = (hue + 67) % 360;
  }
  return result;
}
```

- [ ] **Step 6: 선과 노드 그리기**

실제 레일은 기존 `railWidth`를 유지한다. 가상 Merge/Rebase 연결은 `strokeWidth = 1`과 dash 길이 3, 간격 3을 사용한다. Rebase 대응선은 1px 실선 직교 경로와 `cornerRadius = 6`, 끝 화살표를 사용한다. 원본과 가상 노드에는 같은 색의 1px 테두리를 그린다.

- [ ] **Step 7: painter 테스트 실행**

Run: `flutter test test/git_test.dart --plain-name "preview graph"`

Expected: PASS

Run: `flutter test test/git_test.dart --plain-name "CommitGraphPainter"`

Expected: 기존 painter 테스트도 PASS

- [ ] **Step 8: 커밋**

```bash
git add lib/git.dart lib/timeline.dart test/git_test.dart
git commit -m "feat: draw merge and rebase preview graphs"
```

### Task 5: 상단 버튼과 결과 요약 영역

**Files:**
- Modify: `lib/timeline.dart:1500-1840`
- Modify: `lib/timeline.dart:2290-2435`
- Test: `test/app_test.dart:2480-2660`

**Interfaces:**
- Consumes: `BranchPreviewMode`, `MergePreviewResult`, `RebasePreviewResult`
- Produces widget keys:
  - `branch-preview-merge`
  - `branch-preview-rebase`
  - `branch-preview-summary`
  - `branch-preview-success-icon`

- [ ] **Step 1: 버튼과 저장 콜백 위젯 테스트 작성**

```dart
expect(find.byKey(const Key('branch-preview-merge')), findsOneWidget);
expect(find.byKey(const Key('branch-preview-rebase')), findsOneWidget);
await tester.tap(find.byKey(const Key('branch-preview-rebase')));
await tester.pump();
expect(changedMode, BranchPreviewMode.rebase);
```

- [ ] **Step 2: 성공 문구 테스트 작성**

```dart
expect(find.text('Merge 미리보기'), findsOneWidget);
expect(find.text('Merge 성공'), findsOneWidget);
expect(find.byKey(const Key('branch-preview-success-icon')), findsOneWidget);
expect(find.text('가상 병합'), findsNothing);
```

Rebase 모드에서는 `find.text('Rebase 미리보기')`, `find.text('Rebase 성공')`, `find.byKey(const Key('branch-preview-success-icon'))`가 각각 하나인지 검증한다.

- [ ] **Step 3: 실패 확인**

Run: `flutter test test/app_test.dart --plain-name "branch preview controls"`

Expected: 버튼 key를 찾지 못해 실패

- [ ] **Step 4: 선택기 오른쪽에 버튼 추가**

Branch Diff 대상 선택기가 보일 때만 두 버튼을 표시한다. 현재 모드는 채운 배경과 테두리로 구분한다. 성공 아이콘은 녹색 원형 체크를 쓰고 문구만으로도 상태를 알 수 있게 한다.

- [ ] **Step 5: 상태 표시줄 이동**

`_comparisonStatusBar()`를 하단 조립부에서 제거하고 타임라인 열 제목 바로 위에 `_branchPreviewSummary()`로 넣는다. 공통 조상, 양쪽 고유 커밋 수, 충돌 상태를 유지하되 현재 모드 결과가 가장 먼저 보이게 한다.

- [ ] **Step 6: 위젯 테스트 실행**

Run: `flutter test test/app_test.dart --plain-name "branch preview"`

Expected: PASS

- [ ] **Step 7: 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: add branch preview controls and summary"
```

### Task 6: 성공·충돌 결과 파일과 Unified·Side-by-side diff

**Files:**
- Modify: `lib/timeline.dart:3900-4420`
- Reuse: `lib/full_diff_unified_view.dart`
- Reuse: `lib/full_diff_side_by_side_view.dart`
- Test: `test/app_test.dart:2660-2820`

**Interfaces:**
- Consumes: Merge virtual tree SHA and Rebase virtual tip
- Produces: timeline-local `_branchPreviewLayout: DiffLayout`
- Produces widget keys:
  - `branch-preview-layout-unified`
  - `branch-preview-layout-side-by-side`
  - `branch-preview-file-list`

- [ ] **Step 1: 성공 결과 파일 테스트 작성**

```dart
expect(find.byKey(const Key('branch-preview-file-list')), findsOneWidget);
expect(find.text('feature.txt'), findsOneWidget);
expect(find.text('Merge 미리보기'), findsOneWidget);
```

- [ ] **Step 2: Merge 충돌 파일과 선택지 테스트 작성**

```dart
expect(find.text('Merge 충돌'), findsOneWidget);
expect(find.text('shared.txt'), findsOneWidget);
expect(find.text('main · main change'), findsOneWidget);
expect(find.text('feature · feature change'), findsOneWidget);
expect(find.textContaining(RegExp(r'^[0-9a-f]{7} 사용$')), findsNothing);
```

- [ ] **Step 3: diff 방식 전환 유지 테스트 작성**

```dart
await tester.tap(
  find.byKey(const Key('branch-preview-layout-side-by-side')),
);
await tester.pump();
  expect(find.byType(SideBySidePresentationView), findsOneWidget);
await tester.tap(find.text('other.txt'));
await tester.pump();
expect(find.byType(SideBySidePresentationView), findsOneWidget);
```

- [ ] **Step 4: 실패 확인**

Run: `flutter test test/app_test.dart --plain-name "branch preview diff"`

Expected: 레이아웃 버튼과 Full Diff 표시 위젯을 찾지 못해 실패

- [ ] **Step 5: 가상 결과와 충돌 범위 연결**

Merge 성공은 `baseTip..merge.treeSha`, Rebase 성공은 `baseTip..rebase.virtualTip`을 파일 및 diff 범위로 사용한다. Merge 충돌은 `merge.conflictFiles`를 목록으로 쓰고 `baseTip..compareTip`을 diff 범위로 쓴다. Rebase 충돌은 현재 커밋의 첫 부모와 현재 커밋을 diff 범위로 쓴다. 기존 `_previewFilesFor`와 `_previewDiff`에 선택적 `fromSha`, `toSha`를 전달해 같은 캐시와 파일 선택 흐름을 유지한다.

- [ ] **Step 6: 기존 Full Diff 표시 위젯 재사용**

현재 단순 `_previewDiffLine` 목록을 Branch Diff 미리보기에서만 `UnifiedPresentationView` 또는 `SideBySidePresentationView`로 교체한다. `DiffDocument.fromLines(lines)`로 기존 `DiffLine` 목록을 문서로 바꾸고 기존 `FullDiffSyntaxHighlighter`를 전달한다. 새 diff 파서는 만들지 않는다.

- [ ] **Step 7: 테스트 실행**

Run: `flutter test test/app_test.dart --plain-name "branch preview diff"`

Expected: PASS

Run: `flutter test test/full_diff_content_views_test.dart`

Expected: PASS

- [ ] **Step 8: 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: preview virtual branch diff results"
```

### Task 7: Rebase 충돌 포커스와 임시 해결 흐름

**Files:**
- Modify: `lib/timeline.dart:500-900`
- Modify: `lib/timeline.dart:3500-3900`
- Modify: `lib/timeline.dart:3900-4420`
- Test: `test/app_test.dart:2820-3020`

**Interfaces:**
- Consumes: `RebasePreviewSession.start()`
- Consumes: `RebasePreviewSession.continueAfterResolving()`
- Produces widget keys:
  - `rebase-conflict-current-row`
  - `rebase-conflict-files`
  - `rebase-conflict-continue`
  - `rebase-conflict-abort`

- [ ] **Step 1: 최초 충돌 행 포커스 테스트 작성**

```dart
expect(find.byKey(const Key('rebase-conflict-current-row')), findsOneWidget);
expect(find.text('Rebase 충돌'), findsOneWidget);
expect(find.text('2/3'), findsOneWidget);
expect(find.text('docs: update API examples'), findsOneWidget);
```

- [ ] **Step 2: 다음 충돌 이동 테스트 작성**

가짜 repository/session이 두 충돌 결과를 차례대로 반환하게 한다.

```dart
await tester.tap(find.byKey(const Key('rebase-conflict-continue')));
await tester.pump(const Duration(milliseconds: 240));
expect(find.text('3/3'), findsOneWidget);
expect(find.text('docs: publish API guide'), findsOneWidget);
expect(scrollController.offset, greaterThan(previousOffset));
```

- [ ] **Step 3: 동작 줄이기 테스트 작성**

`MediaQueryData(disableAnimations: true)`에서 계속을 누른 뒤 한 번의 `pump()`만으로 다음 행이 선택되고 진행 중 애니메이션이 남지 않는지 검증한다.

- [ ] **Step 4: 오래된 결과와 진행 중인 Git 작업 테스트 작성**

두 비교 요청을 반대 순서로 완료해 마지막 요청만 보이는지 검증한다. 기본 저장소에 `CHERRY_PICK_HEAD`가 있으면 충돌 해결 버튼이 비활성화되고 `현재 Git 작업을 마친 뒤 해결할 수 있습니다`가 보이는지도 검증한다.

- [ ] **Step 5: 실패 확인**

Run: `flutter test test/app_test.dart --plain-name "rebase conflict preview"`

Expected: 충돌 행 및 버튼 key가 없어서 실패

- [ ] **Step 6: 세션 상태와 화면 생명주기 연결**

Rebase 모드 선택 시 세션을 시작한다. 비교 브랜치, 저장소, 모드가 바뀌거나 widget이 dispose되면 이전 세션을 정리한다. 요청 serial과 시작 당시 base/compare tip이 현재 결과와 일치할 때만 `setState`한다.

- [ ] **Step 7: 충돌 행과 가상 위치 표시**

현재 `currentCommit.sha`와 같은 실제 비교 브랜치 행에 붉은 반전 배경을 적용한다. 기준 브랜치 HEAD 위에는 빈 가상 원과 1px 점선만 표시하고 별도 충돌 커밋 행은 추가하지 않는다.

- [ ] **Step 8: 충돌 미리보기 조작 연결**

충돌 파일 선택과 내장/외부 편집기 메뉴는 Cherry-pick 패널의 위젯을 재사용한다. 편집 경로는 `session.filePath(file)`을 사용한다. 파일을 저장한 뒤 `session.markResolved(file)`을 호출하고 Git이 보고한 미해결 파일이 없을 때만 계속 버튼을 활성화한다. 기본 저장소에서 다른 Git 작업이 진행 중이면 편집, 해결 표시, 계속을 비활성화한다. 중단은 세션을 폐기하고 일반 Branch Diff로 돌아간다.

- [ ] **Step 9: 포커스 이동**

`Scrollable.ensureVisible`에 `Duration(milliseconds: 220)`과 `Curves.easeOut`을 사용한다. `MediaQuery.disableAnimations`가 true면 `Duration.zero`를 사용한다.

- [ ] **Step 10: 테스트 실행**

Run: `flutter test test/app_test.dart --plain-name "rebase conflict preview"`

Expected: PASS

- [ ] **Step 11: 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: walk through rebase preview conflicts"
```

### Task 8: 전체 검증과 정리

**Files:**
- Modify: `test/git_test.dart`
- Modify: `test/app_test.dart`
- Test: `test/git_test.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Verifies all interfaces from Tasks 1-7

- [ ] **Step 1: 형식과 정적 검사**

Run: `dart format --output=none --set-exit-if-changed lib test`

Expected: exit code 0

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 2: 관련 테스트 전체 실행**

Run: `flutter test test/git_test.dart test/full_diff_content_views_test.dart`

Expected: PASS

Run: `flutter test test/app_test.dart`

Expected: PASS

- [ ] **Step 3: 전체 테스트 실행**

Run: `flutter test`

Expected: PASS

- [ ] **Step 4: 실제 저장소 불변 확인**

`test/git_test.dart`에 테스트용 저장소에서 Merge 성공, Merge 충돌, Rebase 성공, Rebase 충돌 미리보기를 각각 실행하는 회귀 테스트를 추가한다. 모든 경우에 다음을 검증한다.

```dart
expect(await git('rev-parse', 'main'), originalMain);
expect(await git('rev-parse', 'feature'), originalFeature);
expect(await git('status', '--porcelain'), '');
expect(await git('worktree', 'list', '--porcelain'), originalWorktrees);
```

- [ ] **Step 5: 남은 변경 확인과 최종 커밋**

Run: `git diff --check`

Expected: 출력 없음

```bash
git add test/git_test.dart test/app_test.dart
git commit -m "test: verify branch preview workflows"
```
