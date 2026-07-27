# Full Diff 상호작용과 옵션 저장 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 미리보기의 파일 목록과 diff를 따로 스크롤할 수 있게 만들고 Full Diff의 마지막 화면과 표시 옵션을 저장하며 Unified / Side-by-side와 Hunk 범위, 알고리즘 설명, Blame 선택, 패널 크기 조절을 승인된 상호작용으로 구현한다.

**Architecture:** `FullDiffSessionController`는 화면 배치와 Git에 요청한 범위를 서로 다른 상태로 관리하며 성공적으로 적용된 값만 `FullDiffPreferences`로 내보낸다. `YogitApp`은 이 값을 기존 `SettingsStore`에 저장하고 새 `DiffScreen`을 만들 때 다시 전달한다. Unified와 Side-by-side는 같은 `DiffDocument`를 소비하며 Hunk 범위는 Git의 `--unified` 값과 패치 캐시 키에서 구분한다.

**Tech Stack:** Flutter/Dart, macOS 키보드 입력, Git CLI, Flutter widget/golden tests

## Global Constraints

- 구현은 별도 worktree에서 시작하며 `/Users/doortts/repos/yogit`의 기존 수정 파일을 건드리지 않는다.
- 새 패키지를 추가하지 않는다.
- 모든 동작 변경은 실패하는 테스트를 먼저 확인한 뒤 구현한다.
- Full Diff의 주 화면은 Diff, Blame, History만 제공한다. File 버튼과 원본 파일 전용 화면은 제거한다.
- Unified와 Side-by-side 중 하나는 항상 선택되어야 한다.
- Hunk는 두 배치와 함께 사용할 수 있는 별도 토글이며 새 설정의 기본값은 켬이다.
- Hunk를 끈 전체 파일 diff는 기존 10MiB, 200,000행 제한과 64MiB 원시 캐시 제한을 지킨다.
- 알고리즘, Hunk 범위, 공백 무시는 새 Git 결과를 받은 뒤에만 저장한다.
- 선택 파일, Blame 선택 줄, 집중 모드는 저장하지 않는다.
- `⌘U`는 Unified와 Side-by-side를 번갈아 선택한다.
- `⌘⇧↑/↓`는 활성 스크롤 영역을 뷰포트 높이의 50%만큼 이동한다.
- Blame 상세 카드는 선택 줄보다 두 줄 아래에 겹쳐 표시하며 다른 줄을 밀지 않는다.
- 도구 모음의 `diff 알고리즘` 문구는 선택 버튼 밖에 두고 버튼에는 현재 적용된
  알고리즘 이름만 표시한다.
- 사용자에게 보이는 새 한국어 문구는 `~/.codex/prompts/korean-naturalness.md`를 읽고 교정한다.

---

### Task 1: Full Diff 옵션과 설정 저장 모델

**Files:**
- Modify: `lib/full_diff_model.dart`
- Modify: `lib/git.dart`
- Modify: `lib/settings.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: 기존 `FullDiffView`, `DiffAlgorithm`, `AppSettings`
- Produces:
  - `enum DiffLayout { unified, sideBySide }`
  - `enum DiffScope { hunks, fullFile }`
  - `FullDiffPreferences`
  - `AppSettings.fullDiffPreferences`

- [ ] **Step 1: 설정 왕복과 손상 값 복구를 검증하는 실패 테스트를 작성한다**

`test/app_test.dart`의 설정 테스트 구역에 다음 동작을 추가한다. 기대값은 직렬화
코드에서 만들지 않고 리터럴로 적는다.

```dart
test('full diff preferences survive settings JSON', () {
  const preferences = FullDiffPreferences(
    view: FullDiffView.history,
    layout: DiffLayout.sideBySide,
    scope: DiffScope.fullFile,
    algorithm: DiffAlgorithm.patience,
    ignoreWhitespace: true,
    wrapLines: false,
  );

  final restored = AppSettings.fromJson(
    const AppSettings(fullDiffPreferences: preferences).toJson(),
  );

  expect(restored.fullDiffPreferences, preferences);
  expect(
    (const AppSettings(fullDiffPreferences: preferences).toJson()
        ['fullDiffPreferences'] as Map<String, Object>),
    const {
      'view': 'history',
      'layout': 'sideBySide',
      'scope': 'fullFile',
      'algorithm': 'patience',
      'ignoreWhitespace': true,
      'wrapLines': false,
    },
  );
});

test('removed and malformed full diff options fall back safely', () {
  final preferences = AppSettings.fromJson({
    'fullDiffPreferences': {
      'view': 'file',
      'layout': 'unknown',
      'scope': 'unknown',
      'algorithm': 'unknown',
      'ignoreWhitespace': 'yes',
      'wrapLines': 1,
    },
  }).fullDiffPreferences;

  expect(preferences, const FullDiffPreferences());
});
```

- [ ] **Step 2: 새 테스트가 예상한 이유로 실패하는지 확인한다**

Run:

```bash
flutter test test/app_test.dart --plain-name "full diff preferences survive settings JSON"
flutter test test/app_test.dart --plain-name "removed and malformed full diff options fall back safely"
```

Expected: `FullDiffPreferences`, `DiffLayout`, `DiffScope` 또는
`AppSettings.fullDiffPreferences`가 아직 없어서 FAIL

- [ ] **Step 3: 옵션 값 객체와 JSON 경계를 구현한다**

`lib/git.dart`에서 Git 호출에도 필요한 범위를 선언한다.

```dart
enum DiffScope { hunks, fullFile }
```

`lib/full_diff_model.dart`에 배치와 불변 설정 값을 추가한다. 이 단계에서는 기존
호출부를 한꺼번에 깨지 않도록 `FullDiffView.file`,
`DiffPresentation`, `FullDiffInitialView`를 아직 남겨 둔다.

```dart
enum DiffLayout { unified, sideBySide }

@immutable
class FullDiffPreferences {
  const FullDiffPreferences({
    this.view = FullDiffView.diff,
    this.layout = DiffLayout.unified,
    this.scope = DiffScope.hunks,
    this.algorithm = DiffAlgorithm.gitSetting,
    this.ignoreWhitespace = false,
    this.wrapLines = true,
  });

  final FullDiffView view;
  final DiffLayout layout;
  final DiffScope scope;
  final DiffAlgorithm algorithm;
  final bool ignoreWhitespace;
  final bool wrapLines;

  FullDiffPreferences copyWith({
    FullDiffView? view,
    DiffLayout? layout,
    DiffScope? scope,
    DiffAlgorithm? algorithm,
    bool? ignoreWhitespace,
    bool? wrapLines,
  }) => FullDiffPreferences(
    view: view ?? this.view,
    layout: layout ?? this.layout,
    scope: scope ?? this.scope,
    algorithm: algorithm ?? this.algorithm,
    ignoreWhitespace: ignoreWhitespace ?? this.ignoreWhitespace,
    wrapLines: wrapLines ?? this.wrapLines,
  );

  factory FullDiffPreferences.fromJson(Object? value) {
    final json = value is Map<String, dynamic>
        ? value
        : const <String, dynamic>{};
    return FullDiffPreferences(
      view: switch (json['view']) {
        'blame' => FullDiffView.blame,
        'history' => FullDiffView.history,
        _ => FullDiffView.diff,
      },
      layout: json['layout'] == 'sideBySide'
          ? DiffLayout.sideBySide
          : DiffLayout.unified,
      scope: json['scope'] == 'fullFile'
          ? DiffScope.fullFile
          : DiffScope.hunks,
      algorithm: DiffAlgorithm.values.firstWhere(
        (value) => value.name == json['algorithm'],
        orElse: () => DiffAlgorithm.gitSetting,
      ),
      ignoreWhitespace: json['ignoreWhitespace'] is bool
          ? json['ignoreWhitespace'] as bool
          : false,
      wrapLines:
          json['wrapLines'] is bool ? json['wrapLines'] as bool : true,
    );
  }

  Map<String, Object> toJson() => {
    'view': view.name,
    'layout': layout.name,
    'scope': scope.name,
    'algorithm': algorithm.name,
    'ignoreWhitespace': ignoreWhitespace,
    'wrapLines': wrapLines,
  };

  @override
  bool operator ==(Object other) =>
      other is FullDiffPreferences &&
      view == other.view &&
      layout == other.layout &&
      scope == other.scope &&
      algorithm == other.algorithm &&
      ignoreWhitespace == other.ignoreWhitespace &&
      wrapLines == other.wrapLines;

  @override
  int get hashCode => Object.hash(
    view,
    layout,
    scope,
    algorithm,
    ignoreWhitespace,
    wrapLines,
  );
}
```

`AppSettings`의 생성자, 필드, `copyWith`, `fromJson`, `toJson`, 동등성,
`hashCode`에 `fullDiffPreferences`를 연결한다.

```dart
this.fullDiffPreferences = const FullDiffPreferences(),

final FullDiffPreferences fullDiffPreferences;

fullDiffPreferences: FullDiffPreferences.fromJson(
  value['fullDiffPreferences'],
),

'fullDiffPreferences': fullDiffPreferences.toJson(),
```

- [ ] **Step 4: 설정 테스트와 정적 분석을 통과시킨다**

Run:

```bash
dart format lib/full_diff_model.dart lib/git.dart lib/settings.dart test/app_test.dart
flutter test test/app_test.dart --plain-name "full diff preferences"
flutter analyze lib/full_diff_model.dart lib/git.dart lib/settings.dart
```

Expected: 새 설정 테스트 PASS, 분석 오류 없음

- [ ] **Step 5: 옵션 저장 모델을 커밋한다**

```bash
git add lib/full_diff_model.dart lib/git.dart lib/settings.dart test/app_test.dart
git commit -m "feat: persist full diff preferences"
```

---

### Task 2: Git 범위와 컨트롤러 적용 상태

**Files:**
- Modify: `lib/git.dart`
- Modify: `lib/full_diff_controller.dart`
- Modify: `test/support/full_diff_fixtures.dart`
- Test: `test/full_diff_git_test.dart`
- Test: `test/full_diff_controller_test.dart`

**Interfaces:**
- Consumes: `DiffScope`, `FullDiffPreferences`, `fullDiffTextLineLimit`
- Produces:
  - `FullDiffRepository.loadDiff(..., DiffScope scope)`
  - `FullDiffSessionController.setLayout(DiffLayout)`
  - `FullDiffSessionController.setScope(DiffScope)`
  - `FullDiffSessionState.preferences`

- [ ] **Step 1: Git 인자와 실패 복원을 검증하는 테스트를 먼저 작성한다**

`test/full_diff_git_test.dart`에 같은 저장소와 파일을 Hunk 범위와 전체 파일
범위로 읽은 뒤 실제 Git 인자를 확인하는 테스트를 추가한다.

```dart
test('diff scope changes context without dropping algorithm options', () async {
  final root = await createGitFixture();
  addTearDown(() => root.delete(recursive: true));
  await writeAndCommit(root, 'sample.txt', 'one\ntwo\nthree\n', 'base');
  await File('${root.path}/sample.txt').writeAsString(
    'one\nchanged\nthree\n',
  );
  await runGit(root, ['commit', '-am', 'change']);

  final calls = <List<String>>[];
  final repository = GitRepository(
    root.path,
    runner: (executable, arguments, {workingDirectory}) {
      calls.add(List.unmodifiable(arguments));
      return runProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
    },
  );
  final commit = (await repository.loadHistory()).first;
  final file = (await repository.loadFiles(commit)).single;

  await repository.loadDiff(
    commit,
    file,
    scope: DiffScope.hunks,
    algorithm: DiffAlgorithm.patience,
    ignoreWhitespace: true,
  );
  await repository.loadDiff(
    commit,
    file,
    scope: DiffScope.fullFile,
    algorithm: DiffAlgorithm.patience,
    ignoreWhitespace: true,
  );

  final diffCalls = calls.where((call) => call.first == 'diff').toList();
  expect(diffCalls[0], contains('--unified=3'));
  expect(diffCalls[1], contains('--unified=$fullDiffTextLineLimit'));
  for (final call in diffCalls) {
    expect(call, contains('--diff-algorithm=patience'));
    expect(call, contains('--ignore-all-space'));
  }
});
```

`test/full_diff_controller_test.dart`에는 범위 적용에 실패하면 요청값과 저장 가능한
적용값이 이전 상태로 돌아가는 테스트를 추가한다.

```dart
test('failed full-file scope keeps the applied hunk preference', () async {
  final repository = FakeFullDiffRepository()
    ..files = ((_, _) async => const [fileA])
    ..content = ((_, _, _) async =>
        Uint8List.fromList(utf8.encode('current\n')))
    ..scopedDiff = ((_, _, _, _, _, scope) async {
      if (scope == DiffScope.fullFile) {
        throw const GitRepositoryException('/repo', 'full file failed');
      }
      return twoHunkLines;
    });
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
    initialView: FullDiffInitialView.hunk,
  );
  addTearDown(controller.dispose);
  await controller.initialize();

  await expectLater(
    controller.setScope(DiffScope.fullFile),
    throwsA(isA<GitRepositoryException>()),
  );

  expect(controller.state.requestedScope, DiffScope.hunks);
  expect(controller.state.appliedScope, DiffScope.hunks);
  expect(controller.state.preferences.scope, DiffScope.hunks);
});
```

같은 파일의 Hunk 결과와 전체 파일 결과가 서로 다른 캐시 항목을 쓰는 테스트도
추가한다. `FakeFullDiffRepository.diffRequests`에는 `scope`를 기록한다.

```dart
test('hunk and full-file patches use separate cache entries', () async {
  final repository = FakeFullDiffRepository()
    ..files = ((_, _) async => const [fileA])
    ..scopedDiff = ((_, _, _, _, _, scope) async => twoHunkLines)
    ..content = ((_, _, _) async =>
        Uint8List.fromList(utf8.encode('current\n')));
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
    initialView: FullDiffInitialView.hunk,
    initialPreferences: const FullDiffPreferences(),
  );
  addTearDown(controller.dispose);
  await controller.initialize();

  await controller.setScope(DiffScope.fullFile);
  await controller.setScope(DiffScope.hunks);

  expect(
    repository.diffRequests.map((request) => request.scope),
    [DiffScope.hunks, DiffScope.fullFile],
  );
});
```

`test/full_diff_git_test.dart`에는 반복 줄을 가진 실제 저장소를 만들어 알고리즘
선택이 결과에도 반영되는지 확인한다. 이 fixture에서는 Myers와 Histogram이
서로 다른 변경 묶음을 만든다.

```dart
test('selected git algorithm changes the parsed patch when boundaries differ',
    () async {
  final root = await createGitFixture();
  addTearDown(() => root.delete(recursive: true));
  await writeAndCommit(
    root,
    'repeated.txt',
    'A\nD\nB\nD\nD\nD\nC\nA\nD\nA\nD\nA\n',
    'base',
  );
  await File('${root.path}/repeated.txt').writeAsString(
    'A\nB\nC\nD\nC\nC\nA\nD\nD\nC\nA\nB\n',
  );
  await runGit(root, ['commit', '-am', 'reorder repeated lines']);
  final repository = GitRepository(root.path);
  final commit = (await repository.loadHistory()).first;
  final file = (await repository.loadFiles(commit)).single;

  final myers = await repository.loadDiff(
    commit,
    file,
    algorithm: DiffAlgorithm.myers,
  );
  final histogram = await repository.loadDiff(
    commit,
    file,
    algorithm: DiffAlgorithm.histogram,
  );
  List<String> signature(List<DiffLine> lines) =>
      lines.map((line) => '${line.kind.name}:${line.text}').toList();

  expect(signature(histogram), isNot(signature(myers)));
});
```

- [ ] **Step 2: 새 인자와 메서드를 다루는 테스트가 예상대로 실패하는지 확인한다**

Run:

```bash
flutter test test/full_diff_git_test.dart --plain-name "diff scope changes context"
flutter test test/full_diff_git_test.dart --plain-name "selected git algorithm changes"
flutter test test/full_diff_controller_test.dart --plain-name "failed full-file scope"
flutter test test/full_diff_controller_test.dart --plain-name "hunk and full-file patches"
```

Expected: 범위 테스트는 `scope`, `scopedDiff`, `setScope`가 없어 FAIL하고 실제
알고리즘 fixture 테스트는 현재 코드에서도 PASS한다. 후자는 기존 알고리즘 적용
상태를 고정하는 안전망이다.

- [ ] **Step 3: 저장소 요청과 패치 캐시 키에 범위를 연결한다**

`FullDiffRepository`와 `GitRepository`의 메서드에 기본 Hunk 범위를 추가한다.

```dart
Future<List<DiffLine>> loadDiff(
  GitCommit commit,
  GitFileChange file, {
  String? parent,
  DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
  bool ignoreWhitespace = false,
  DiffScope scope = DiffScope.hunks,
});
```

Git 인자에서 고정된 `--unified=3`을 다음으로 교체한다.

```dart
'--unified=${scope == DiffScope.hunks ? 3 : fullDiffTextLineLimit}',
```

`PatchCacheKey`에 `DiffScope scope`를 추가한다. `_loadPatchDocument`는
`state.requestedScope`를 저장소와 캐시 키에 함께 전달한다.

- [ ] **Step 4: 컨트롤러가 요청값과 적용값을 구분하도록 구현한다**

`FullDiffSessionState`에 `layout`, `requestedScope`, `appliedScope`를 추가하고
화면에 실제로 반영된 값을 다음 getter로 묶는다.

```dart
FullDiffPreferences get preferences => FullDiffPreferences(
  view: view == FullDiffView.file ? FullDiffView.diff : view,
  layout: layout,
  scope: appliedScope,
  algorithm: appliedAlgorithm,
  ignoreWhitespace: appliedIgnoreWhitespace,
  wrapLines: wrapLines,
);
```

컨트롤러 생성자는 기존 테스트가 단계 중간에도 컴파일되도록
`initialView`를 유지하면서 새 설정을 선택적으로 받는다.

```dart
FullDiffSessionController({
  required this.repository,
  required List<GitCommit> commits,
  required int initialIndex,
  required FullDiffInitialView initialView,
  FullDiffPreferences? initialPreferences,
  FullDiffEncodingCache? encodingCache,
}) : state = _initialState(
       commits,
       initialIndex,
       initialView,
       initialPreferences,
     );
```

범위 변경은 알고리즘과 공백 무시가 사용하는 성공 후 적용 흐름을 그대로 따른다.

```dart
void setLayout(DiffLayout layout) {
  if (_disposed || state.layout == layout) return;
  _replace(state.copyWith(layout: layout));
}

Future<void> setScope(DiffScope scope) async {
  if (_disposed || state.requestedScope == scope) return;
  final sourceLine = _anchorSourceLine(state.activeAnchor);
  _replace(
    state.copyWith(
      requestedScope: scope,
      patch: state.patch.copyWith(loading: true, error: null),
    ),
  );
  await _loadPatch(
    preserveDataOnFailure: true,
    sourceLine: sourceLine,
    propagateError: true,
  );
}
```

`_loadPatch` 성공 분기에서 `appliedScope`를 바꾸고 실패 분기에서는
`requestedScope`를 `appliedScope`로 복원한다.

- [ ] **Step 5: 테스트 저장소가 범위를 기록하도록 확장한다**

`FakeFullDiffRepository`에는 기존 다섯 인자 콜백을 보존하고 새 테스트용 콜백을
추가한다.

```dart
Future<List<DiffLine>> Function(
  GitCommit,
  GitFileChange,
  String?,
  DiffAlgorithm,
  bool,
  DiffScope,
)?
scopedDiff;

return scopedDiff?.call(
      commit,
      file,
      parent,
      algorithm,
      ignoreWhitespace,
      scope,
    ) ??
    diff?.call(commit, file, parent, algorithm, ignoreWhitespace) ??
    Future.value(const []);
```

`diffRequests` 기록에도 `scope`를 넣는다. `test/app_test.dart`의
`FakeGitRepository.loadDiff` override는 새 선택적 인자를 받고 기존 테스트
콜백에 전달하지 않는다.

- [ ] **Step 6: Git과 컨트롤러 테스트를 통과시킨다**

Run:

```bash
dart format lib/git.dart lib/full_diff_controller.dart test/support/full_diff_fixtures.dart test/full_diff_git_test.dart test/full_diff_controller_test.dart
flutter test test/full_diff_git_test.dart test/full_diff_controller_test.dart
```

Expected: 두 파일의 모든 테스트 PASS

- [ ] **Step 7: Git 범위와 적용 상태를 커밋한다**

```bash
git add lib/git.dart lib/full_diff_controller.dart test/support/full_diff_fixtures.dart test/full_diff_git_test.dart test/full_diff_controller_test.dart test/app_test.dart
git commit -m "feat: apply full diff scope through git"
```

---

### Task 3: Unified / Side-by-side 렌더링과 File 화면 제거

**Files:**
- Create: `lib/full_diff_unified_view.dart`
- Create: `lib/full_diff_side_by_side_view.dart`
- Modify: `lib/full_diff_model.dart`
- Modify: `lib/full_diff_controller.dart`
- Modify: `lib/diff_screen.dart`
- Modify: `lib/full_diff_header.dart`
- Modify: `lib/full_diff_minimap.dart`
- Modify: `test/full_diff_widgets_test.dart`
- Modify: `test/full_diff_workspace_test.dart`
- Modify: `test/full_diff_minimap_test.dart`
- Modify: `test/support/full_diff_qa_harness.dart`
- Delete: `lib/full_diff_hunk_view.dart`
- Delete: `lib/full_diff_inline_view.dart`
- Delete: `lib/full_diff_split_view.dart`
- Delete: `lib/full_file_view.dart`

**Interfaces:**
- Consumes: `DiffLayout`, `DiffScope`, `FullDiffSessionState`
- Produces:
  - `UnifiedPresentationView`
  - `SideBySidePresentationView`
  - `GlobalDiffToolbar.layout`
  - `GlobalDiffToolbar.hunkEnabled`

- [ ] **Step 1: 한 목록의 모든 Hunk와 제거된 File 화면을 검증하는 실패 테스트를 작성한다**

`test/full_diff_widgets_test.dart`에서 기존 “활성 Hunk 하나” 테스트를 다음 계약으로
교체한다.

```dart
testWidgets('unified hunk scope renders every hunk in source order', (
  tester,
) async {
  final anchorKeys = {
    for (final hunk in twoHunkDocument.hunks)
      hunk.anchor.id: GlobalKey(debugLabel: hunk.anchor.id),
  };
  await tester.pumpWidget(
    qaApp(
      SizedBox(
        width: 640,
        height: 420,
        child: UnifiedPresentationView(
          document: twoHunkDocument,
          activeAnchor: twoHunkDocument.hunks.last.anchor,
          path: fileA.path,
          wrapLines: false,
          highlighter: fakeHighlighter,
          anchorKeys: anchorKeys,
        ),
      ),
    ),
  );

  expect(find.text('first old'), findsOneWidget);
  expect(find.text('first new'), findsOneWidget);
  expect(find.text('second old'), findsOneWidget);
  expect(find.text('second new'), findsOneWidget);
  expect(
    tester.getTopLeft(find.text('first old')).dy,
    lessThan(tester.getTopLeft(find.text('second old')).dy),
  );
});
```

`test/full_diff_workspace_test.dart`에는 주 화면 버튼과 배치 그룹을 검증한다.

```dart
testWidgets('full diff exposes only Diff Blame History and one layout', (
  tester,
) async {
  final fixture = await initializedFixture();
  addTearDown(fixture.controller.dispose);
  await pumpWorkspace(tester, controller: fixture.controller);

  expect(find.text('File'), findsNothing);
  expect(find.text('Diff'), findsOneWidget);
  expect(find.text('Blame'), findsOneWidget);
  expect(find.text('History'), findsOneWidget);
  expect(find.text('Unified'), findsOneWidget);
  expect(find.text('Side-by-side'), findsOneWidget);
  expect(find.text('Hunk'), findsOneWidget);
});
```

같은 fixture에서 다음 Hunk 버튼과 `⌥↓`를 각각 실행한 뒤 활성 앵커만 바뀌고
첫 번째와 두 번째 Hunk의 텍스트가 계속 같은 스크롤 목록에 남는지도 확인한다.

```dart
expect(find.text('first new'), findsOneWidget);
expect(find.text('second new'), findsOneWidget);
await tester.tap(find.byKey(const Key('next-hunk')));
await tester.pumpAndSettle();
expect(fixture.controller.state.activeAnchor?.hunkIndex, 1);
expect(find.text('first new'), findsOneWidget);
expect(find.text('second new'), findsOneWidget);

await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
await tester.pumpAndSettle();
expect(fixture.controller.state.activeAnchor?.hunkIndex, 0);
```

- [ ] **Step 2: 새 이름과 제거된 화면 때문에 테스트가 실패하는지 확인한다**

Run:

```bash
flutter test test/full_diff_widgets_test.dart --plain-name "unified hunk scope"
flutter test test/full_diff_workspace_test.dart --plain-name "full diff exposes only"
```

Expected: `UnifiedPresentationView`가 없고 File 버튼이 남아 있어 FAIL

- [ ] **Step 3: 기존 Inline과 Split 렌더러를 명확한 이름으로 옮긴다**

`InlinePresentationView`의 모든 Hunk를 순서대로 만드는 `_inlineItems` 흐름을
`UnifiedPresentationView`로 옮긴다. `SplitPresentationView`는
`SideBySidePresentationView`로 옮긴다. 두 클래스의 생성자 계약은 다음과 같다.

```dart
class UnifiedPresentationView extends StatelessWidget {
  const UnifiedPresentationView({
    required this.document,
    required this.activeAnchor,
    required this.path,
    required this.wrapLines,
    required this.highlighter,
    required this.anchorKeys,
    this.richRenderingEnabled = true,
    this.onAnchorProbeAttached,
    this.onAnchorProbeDetached,
    this.controller,
    super.key,
  });
}

class SideBySidePresentationView extends StatelessWidget {
  const SideBySidePresentationView({
    required this.document,
    required this.activeAnchor,
    required this.oldPath,
    required this.newPath,
    required this.wrapLines,
    required this.showOldSide,
    required this.highlighter,
    required this.anchorKeys,
    this.richRenderingEnabled = true,
    this.onAnchorProbeAttached,
    this.onAnchorProbeDetached,
    this.controller,
    super.key,
  });
}
```

Hunk 전용 렌더러와 File 전용 렌더러를 삭제한다. Hunk 켬과 끔은 렌더러가 아니라
Git에서 받은 문맥 범위로 구분한다.

- [ ] **Step 4: 화면 상태와 도구 모음을 두 축으로 교체한다**

`FullDiffView`는 최종 세 값만 남긴다.

```dart
enum FullDiffView { diff, blame, history }
```

`DiffPresentation`과 `FullDiffInitialView`를 삭제한다.
`FullDiffSessionController` 생성자는 다음처럼 단순화한다.

```dart
FullDiffSessionController({
  required this.repository,
  required List<GitCommit> commits,
  required int initialIndex,
  FullDiffPreferences initialPreferences = const FullDiffPreferences(),
  FullDiffEncodingCache? encodingCache,
})
```

`DiffScreen`도 `initialView` 대신 `initialPreferences`를 받는다. 모든 생성
지점에서는 기본 설정이면 인자를 생략하고 특별한 테스트만 다음처럼 적는다.

```dart
initialPreferences: const FullDiffPreferences(
  view: FullDiffView.history,
  layout: DiffLayout.sideBySide,
  scope: DiffScope.fullFile,
),
```

`GlobalDiffToolbar`의 공개 계약을 바꾼다.

```dart
required DiffLayout layout,
required bool hunkEnabled,
required ValueChanged<DiffLayout> onLayoutSelected,
required ValueChanged<bool> onHunkChanged,
```

표시 문자열은 `Unified`, `Side-by-side`, `Hunk`로 고정한다.
Unified와 Side-by-side를 `Semantics(inMutuallyExclusiveGroup: true,
selected: ...)`로 묶는다. Hunk는 `Semantics(toggled: ...)`를 사용하고 상태에
따라 `Key('hunk-toggle-on')` 또는 `Key('hunk-toggle-off')`를 붙인다.

- [ ] **Step 5: DiffScreen과 미니맵을 새 렌더링 흐름에 연결한다**

`_diffContent`는 배치만으로 렌더러를 고른다.

```dart
final presentation = switch (state.layout) {
  DiffLayout.unified => UnifiedPresentationView(
    document: patch,
    activeAnchor: state.activeAnchor,
    path: selectedFile.path,
    wrapLines: state.wrapLines,
    highlighter: _highlighter,
    anchorKeys: _anchorKeys,
    richRenderingEnabled: state.richRenderingEnabled,
    onAnchorProbeAttached: _attachAnchorProbe,
    onAnchorProbeDetached: _detachAnchorProbe,
    controller: _contentScroll,
  ),
  DiffLayout.sideBySide => SideBySidePresentationView(
    document: patch,
    activeAnchor: state.activeAnchor,
    oldPath: selectedFile.oldPath ?? selectedFile.path,
    newPath: selectedFile.path,
    wrapLines: state.wrapLines,
    showOldSide: viewportWidth > 480,
    highlighter: _highlighter,
    anchorKeys: _anchorKeys,
    richRenderingEnabled: state.richRenderingEnabled,
    onAnchorProbeAttached: _attachAnchorProbe,
    onAnchorProbeDetached: _detachAnchorProbe,
    controller: _contentScroll,
  ),
};
```

`FullDiffMinimap`에서 `presentation` 인자와 Hunk 전용 앵커 드래그 분기를 제거한다.
새 Unified와 Side-by-side는 모두 실제 스크롤 위치를 가진다. 마커를 클릭하면
기존처럼 Hunk를 선택하고 뷰포트를 드래그하면 실제 스크롤 비율을 바꾼다.

- [ ] **Step 6: 이전 enum과 화면을 사용하던 테스트 fixture를 기계적으로 옮긴다**

다음 변환을 `test/` 전체와 QA harness에 적용한다.

```dart
DiffPresentation.inline  -> DiffLayout.unified
DiffPresentation.split   -> DiffLayout.sideBySide
DiffPresentation.hunk    -> DiffLayout.unified + DiffScope.hunks
FullDiffInitialView.hunk -> const FullDiffPreferences()
FullDiffInitialView.fullFile
  -> const FullDiffPreferences(scope: DiffScope.fullFile)
FullDiffView.file
  -> FullDiffView.diff
```

File 전용 동작을 검증하던 테스트는 삭제하지 않고 Hunk를 끈 Unified 전체 파일
동작을 검증하도록 바꾼다. File 버튼이 없어야 한다는 테스트는 유지한다.

- [ ] **Step 7: 렌더링과 작업 영역 테스트를 통과시킨다**

Run:

```bash
dart format lib test/support/full_diff_qa_harness.dart
flutter test test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart test/full_diff_minimap_test.dart test/full_diff_content_views_test.dart
```

Expected: 모든 Hunk가 한 목록에 보이고 File 화면 관련 실패가 없음

- [ ] **Step 8: 렌더링 구조 변경을 커밋한다**

```bash
git add lib test
git commit -m "feat: separate full diff layout and hunk scope"
```

---

### Task 4: 마지막 옵션 복원, 단축키와 Command 안내

**Files:**
- Create: `lib/full_diff_shortcut_hint.dart`
- Modify: `lib/main.dart`
- Modify: `lib/timeline.dart`
- Modify: `lib/diff_screen.dart`
- Modify: `lib/full_diff_header.dart`
- Modify: `lib/settings.dart`
- Test: `test/app_test.dart`
- Test: `test/full_diff_controller_test.dart`
- Test: `test/full_diff_header_test.dart`
- Test: `test/full_diff_workspace_test.dart`

**Interfaces:**
- Consumes: `FullDiffSessionState.preferences`, `AppSettings.copyWith`
- Produces:
  - `TimelineScreen.fullDiffPreferences`
  - `TimelineScreen.onFullDiffPreferencesChanged`
  - `DiffScreen.onPreferencesChanged`
  - `FullDiffShortcutHint`

- [ ] **Step 1: Full Diff를 다시 열었을 때 마지막 상태가 복원되는 실패 테스트를 작성한다**

`test/app_test.dart`에서 실제 `YogitApp`과 `MemorySettingsStore`를 사용한다.
저장소 I/O만 메모리 대역으로 바꾸고 화면과 컨트롤러는 실제 구현을 사용한다.

```dart
testWidgets('reopening full diff restores the last successful options', (
  tester,
) async {
  final store = MemorySettingsStore();
  await tester.pumpWidget(
    YogitApp(
      repository: fullDiffRepository(),
      settingsStore: store,
      discoverAvatars: false,
      windowFrameController: controller,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('toolbar-full-diff')));
  await tester.pumpAndSettle();

  await tester.tap(find.text('History'));
  await tester.tap(find.text('Side-by-side'));
  await tester.tap(find.text('Hunk'));
  await tester.tap(find.byKey(const Key('ignore-whitespace')));
  await tester.tap(find.byKey(const Key('wrap-lines')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('full-diff-back')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('toolbar-full-diff')));
  await tester.pumpAndSettle();

  expect(
    tester
        .getSemantics(find.bySemanticsLabel('History'))
        .hasFlag(SemanticsFlag.isSelected),
    isTrue,
  );
  expect(
    tester
        .getSemantics(find.bySemanticsLabel('Side-by-side'))
        .hasFlag(SemanticsFlag.isSelected),
    isTrue,
  );
  expect(store.current.fullDiffPreferences, const FullDiffPreferences(
    view: FullDiffView.history,
    layout: DiffLayout.sideBySide,
    scope: DiffScope.fullFile,
    algorithm: DiffAlgorithm.gitSetting,
    ignoreWhitespace: true,
    wrapLines: false,
  ));
});
```

같은 테스트의 끝에서 앱 위젯을 제거한 뒤 같은 `MemorySettingsStore`로
`YogitApp`을 새로 만든다. Full Diff를 열었을 때도 History, Side-by-side,
Hunk 끔, 공백 무시, 줄바꿈 끔이 복원되어야 한다.

```dart
await tester.pumpWidget(const SizedBox.shrink());
await tester.pump();
await tester.pumpWidget(
  YogitApp(
    repository: fullDiffRepository(),
    settingsStore: store,
    discoverAvatars: false,
    windowFrameController: controller,
  ),
);
await tester.pumpAndSettle();
await tester.tap(find.byKey(const Key('toolbar-full-diff')));
await tester.pumpAndSettle();

expect(
  tester
      .getSemantics(find.bySemanticsLabel('History'))
      .hasFlag(SemanticsFlag.isSelected),
  isTrue,
);
expect(
  tester
      .getSemantics(find.bySemanticsLabel('Side-by-side'))
      .hasFlag(SemanticsFlag.isSelected),
  isTrue,
);
expect(find.byKey(const Key('hunk-toggle-off')), findsOneWidget);
```

설정 파일 저장이 실패해도 현재 세션의 화면을 되돌리지 않는 테스트도 같은 파일에
추가한다. `FailingSettingsStore`는 파일 끝의 `MemorySettingsStore` 옆에 둔다.

```dart
class FailingSettingsStore extends MemorySettingsStore {
  @override
  Future<void> save(AppSettings settings) async {
    throw const FileSystemException('settings write failed');
  }
}

testWidgets('settings write failure keeps the applied full diff session', (
  tester,
) async {
  final store = FailingSettingsStore();
  await tester.pumpWidget(
    YogitApp(
      repository: fullDiffRepository(),
      settingsStore: store,
      discoverAvatars: false,
      windowFrameController: controller,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('toolbar-full-diff')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Side-by-side'));
  await tester.pump();

  expect(
    tester
        .getSemantics(find.bySemanticsLabel('Side-by-side'))
        .hasFlag(SemanticsFlag.isSelected),
    isTrue,
  );
  expect(tester.takeException(), isNull);
});
```

`test/full_diff_workspace_test.dart`에는 범위 적용 실패 시 저장 콜백이 호출되지
않는 테스트를 추가한다.

```dart
testWidgets('failed scope change does not report a new preference', (
  tester,
) async {
  final repository = FakeFullDiffRepository()
    ..files = ((_, _) async => const [fileA])
    ..scopedDiff = ((_, _, _, _, _, scope) async {
      if (scope == DiffScope.fullFile) {
        throw const GitRepositoryException('/repo', 'full file failed');
      }
      return twoHunkLines;
    })
    ..content = ((_, _, _) async =>
        Uint8List.fromList(utf8.encode('current\n')));
  final reported = <FullDiffPreferences>[];
  await pumpDiffScreen(
    tester,
    repository: repository,
    onPreferencesChanged: reported.add,
  );

  await tester.tap(find.text('Hunk'));
  await tester.pumpAndSettle();

  expect(reported.where((value) => value.scope == DiffScope.fullFile), isEmpty);
  expect(find.byKey(const Key('hunk-toggle-on')), findsOneWidget);
});
```

`test/full_diff_controller_test.dart`에는 다른 저장소를 나타내는 새 컨트롤러가
표시 옵션은 이어받되 파일 선택은 새 목록의 첫 파일로 시작하는 테스트를
추가한다.

```dart
test('new repository keeps display preferences but starts with its own file',
    () async {
  const newFile = GitFileChange(
    path: 'lib/new_repository.dart',
    status: 'M',
    additions: 1,
    deletions: 0,
  );
  final repository = FakeFullDiffRepository(root: '/second')
    ..files = ((_, _) async => const [newFile])
    ..scopedDiff = ((_, _, _, _, _, _) async => twoHunkLines)
    ..content = ((_, _, _) async =>
        Uint8List.fromList(utf8.encode('new repository\n')));
  const preferences = FullDiffPreferences(
    view: FullDiffView.history,
    layout: DiffLayout.sideBySide,
    scope: DiffScope.hunks,
    algorithm: DiffAlgorithm.patience,
    ignoreWhitespace: true,
    wrapLines: false,
  );
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
    initialPreferences: preferences,
  );
  addTearDown(controller.dispose);
  await controller.initialize();

  expect(controller.state.selectedFile, newFile);
  expect(controller.state.preferences, preferences);
});
```

- [ ] **Step 2: 설정 전달 경로가 없어 테스트가 실패하는지 확인한다**

Run:

```bash
flutter test test/app_test.dart --plain-name "reopening full diff restores"
```

Expected: 다시 연 화면이 기본값으로 돌아가 FAIL

- [ ] **Step 3: 설정을 Main → Timeline → DiffScreen으로 전달한다**

`YogitApp.build`에서 다음 값을 전달한다.

```dart
fullDiffPreferences: _settings.fullDiffPreferences,
onFullDiffPreferencesChanged: _settingsLoaded
    ? (preferences) => _changeSettings(
        _settings.copyWith(fullDiffPreferences: preferences),
      )
    : null,
```

`TimelineScreen`은 이 값을 보관하지 않고 `_openFullDiff`에서 그대로 넘긴다.

```dart
DiffScreen(
  repository: widget.repository,
  commits: List.unmodifiable(_commits),
  initialIndex: _commits.indexOf(commit),
  initialPreferences: widget.fullDiffPreferences,
  onPreferencesChanged: widget.onFullDiffPreferencesChanged,
  // 기존 편집기, 아바타, 폭 인자는 유지
)
```

`DiffScreen`은 컨트롤러를 붙일 때 초기 `state.preferences`를 기억한다.
`_handleControllerChanged`에서 적용된 설정이 달라졌을 때만 콜백을 한 번 부른다.

```dart
void _reportPreferences(FullDiffSessionState state) {
  final next = state.preferences;
  if (next == _lastReportedPreferences) return;
  _lastReportedPreferences = next;
  widget.onPreferencesChanged?.call(next);
}
```

요청 중인 `requestedAlgorithm`, `requestedScope`,
`requestedIgnoreWhitespace`는 이 getter에 들어가지 않으므로 실패한 선택은
저장되지 않는다.

Settings 화면의 이전 `Full Diff` 초기 화면 라디오와
`AppSettings.fullDiffInitialView`를 제거한다. 예전 JSON 키는 무시한다.

- [ ] **Step 4: 단축키 동작을 검증하는 실패 테스트를 작성한다**

`test/full_diff_workspace_test.dart`에 다음 입력을 차례로 보내 실제 상태를
확인한다.

```dart
await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
expect(controller.state.view, FullDiffView.blame);

await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
expect(controller.state.layout, DiffLayout.sideBySide);

await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
await tester.pumpAndSettle();
expect(controller.state.appliedScope, DiffScope.fullFile);
```

같은 테스트에서 `⌘1` Diff, `⌘3` History, `⌘⇧Space` 공백 무시,
`⌘⇧L` 줄바꿈을 확인한다. `⌘4`를 누른 뒤에도 현재 화면이 바뀌지 않는지
검증해 제거된 File 단축키가 남아 있지 않도록 고정한다.

```dart
final beforeCommand4 = controller.state.view;
await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
expect(controller.state.view, beforeCommand4);
```

- [ ] **Step 5: Full Diff 단축키 Intent와 Action을 구현한다**

`diff_screen.dart`에 값이 있는 Intent를 둔다.

```dart
class _SelectViewIntent extends Intent {
  const _SelectViewIntent(this.view);
  final FullDiffView view;
}

class _ToggleLayoutIntent extends Intent {
  const _ToggleLayoutIntent();
}

class _ToggleScopeIntent extends Intent {
  const _ToggleScopeIntent();
}
```

`Shortcuts`에는 다음 조합을 등록한다.

```dart
SingleActivator(LogicalKeyboardKey.digit1, meta: true):
    const _SelectViewIntent(FullDiffView.diff),
SingleActivator(LogicalKeyboardKey.digit2, meta: true):
    const _SelectViewIntent(FullDiffView.blame),
SingleActivator(LogicalKeyboardKey.digit3, meta: true):
    const _SelectViewIntent(FullDiffView.history),
SingleActivator(LogicalKeyboardKey.keyU, meta: true):
    const _ToggleLayoutIntent(),
SingleActivator(LogicalKeyboardKey.keyH, meta: true, shift: true):
    const _ToggleScopeIntent(),
SingleActivator(LogicalKeyboardKey.space, meta: true, shift: true):
    const _ToggleWhitespaceIntent(),
SingleActivator(LogicalKeyboardKey.keyL, meta: true, shift: true):
    const _ToggleWrapIntent(),
```

`⌘U`는 현재 배치의 반대 값을 설정한다. 비동기 토글은 기존 diff를 유지하고
완료될 때까지 중복 요청을 만들지 않는다.

Full Diff의 `Shortcuts`는 코드 선택을 감싸되 선택에 쓰는 기본 키 입력을
재정의하지 않는다. 알고리즘 선택창이 열려 있을 때는 Task 5의 내부 `Focus`와
`Shortcuts`가 `↑/↓`, Enter, Esc를 먼저 처리하게 한다.

- [ ] **Step 6: Command 안내 배지의 실패 테스트와 구현을 완료한다**

`test/full_diff_header_test.dart`는 Command를 누르기 전과 누른 뒤의 배지를
비교한다. 버튼 좌표가 바뀌지 않는 것도 함께 확인한다.

```dart
final before = tester.getRect(find.text('Unified'));
expect(find.byKey(const Key('shortcut-hint-layout')), findsNothing);

await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
await tester.pump();

expect(find.text('⌘1'), findsOneWidget);
expect(find.text('⌘2'), findsOneWidget);
expect(find.text('⌘3'), findsOneWidget);
expect(find.text('⌘U'), findsOneWidget);
expect(tester.getRect(find.text('Unified')), before);

await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
await tester.pump();
expect(find.byKey(const Key('shortcut-hint-layout')), findsNothing);
```

`FullDiffShortcutHint`는 `OverlayPortal`과
`CompositedTransformTarget/Follower`로 버튼 아래에 그린다.

```dart
class FullDiffShortcutHint extends StatefulWidget {
  const FullDiffShortcutHint({
    required this.visible,
    required this.label,
    required this.child,
    this.hintKey,
    super.key,
  });

  final bool visible;
  final String label;
  final Widget child;
  final Key? hintKey;
}
```

`DiffScreen`은 `HardwareKeyboard.instance.addHandler`로 Meta 키의 눌림 상태만
추적하고 dispose에서 handler를 제거한다. 배지는 `IgnorePointer`로 그려 버튼
입력을 막지 않는다. Unified / Side-by-side 그룹은 그룹 전체를 한 anchor로
감싸 `⌘U`를 한 번만 표시한다.

배지 자체는 `ExcludeSemantics`로 중복 읽기를 막는다. 각 버튼과 토글의 기존
Semantics hint에는 눈으로 보는 배지와 같은 단축키를 넣는다. 예를 들어 Hunk는
`Hunk 켜기 또는 끄기, 단축키 Command Shift H`, 배치 그룹은
`Unified와 Side-by-side 전환, 단축키 Command U`를 사용한다.

- [ ] **Step 7: 저장, 단축키, 안내 테스트를 통과시킨다**

Run:

```bash
dart format lib test/app_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
flutter test test/app_test.dart --name "full diff preferences|reopening full diff"
flutter test test/full_diff_controller_test.dart --plain-name "new repository keeps display preferences"
flutter test test/full_diff_header_test.dart test/full_diff_workspace_test.dart
```

Expected: 마지막 옵션 복원, 숫자 단축키, `⌘U`, 안내 배지 모두 PASS

- [ ] **Step 8: 설정 복원과 단축키를 커밋한다**

```bash
git add lib/main.dart lib/timeline.dart lib/diff_screen.dart lib/full_diff_header.dart lib/full_diff_shortcut_hint.dart lib/settings.dart test/app_test.dart test/full_diff_controller_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
git commit -m "feat: restore full diff options and shortcuts"
```

---

### Task 5: 즉시 반응하는 diff 알고리즘 설명창

**Files:**
- Create: `lib/full_diff_algorithm_chooser.dart`
- Modify: `lib/full_diff_header.dart`
- Modify: `lib/diff_screen.dart`
- Test: `test/full_diff_header_test.dart`
- Test: `test/full_diff_workspace_test.dart`

**Interfaces:**
- Consumes: `DiffAlgorithm`, `diffAlgorithmDescription`
- Produces:
  - `DiffAlgorithmDetails`
  - `FullDiffAlgorithmChooser`
  - `FullDiffAlgorithmChooserState.show()`

- [ ] **Step 1: 호버, 키보드 미리보기, 적용을 구분하는 실패 테스트를 작성한다**

`test/full_diff_header_test.dart`에서 선택값을 Histogram으로 두고 설명창을 연다.

```dart
testWidgets('algorithm chooser previews immediately and applies on enter', (
  tester,
) async {
  DiffAlgorithm? selected;
  await pumpHeaders(
    tester,
    algorithm: DiffAlgorithm.histogram,
    onAlgorithmSelected: (value) => selected = value,
  );

  expect(find.text('diff 알고리즘'), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const Key('diff-algorithm')),
      matching: find.text('Histogram'),
    ),
    findsOneWidget,
  );
  await tester.tap(find.byKey(const Key('diff-algorithm')));
  await tester.pump();
  expect(find.byKey(const Key('algorithm-details-histogram')), findsOneWidget);

  final patience = find.byKey(const Key('algorithm-option-patience'));
  final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
  await mouse.addPointer();
  await mouse.moveTo(tester.getCenter(patience));
  await tester.pump();

  expect(find.byKey(const Key('algorithm-details-patience')), findsOneWidget);
  expect(selected, isNull);

  await tester.tap(patience);
  await tester.pumpAndSettle();
  expect(selected, DiffAlgorithm.patience);
});
```

키보드 테스트는 `⌘⇧A`로 열고 `↓`, Enter, Esc를 보내 적용과 취소를 각각
확인한다.

- [ ] **Step 2: 기존 PopupMenuButton의 지연 설명 때문에 테스트가 실패하는지 확인한다**

Run:

```bash
flutter test test/full_diff_header_test.dart --plain-name "algorithm chooser previews immediately"
```

Expected: 오른쪽 설명 패널과 알고리즘 옵션 key가 없어 FAIL

- [ ] **Step 3: 정적 설명 자료와 좌우 패널을 구현한다**

`lib/full_diff_algorithm_chooser.dart`에 설명 자료를 둔다.

```dart
@immutable
class DiffAlgorithmDetails {
  const DiffAlgorithmDetails({
    required this.description,
    required this.bestFor,
    required this.example,
  });

  final String description;
  final String bestFor;
  final List<String> example;
}

const diffAlgorithmDetails = <DiffAlgorithm, DiffAlgorithmDetails>{
  DiffAlgorithm.gitSetting: DiffAlgorithmDetails(
    description: '저장소의 Git 설정을 따릅니다. 설정이 없으면 Git 기본값을 사용합니다.',
    bestFor: '팀에서 diff.algorithm 설정을 공유하는 저장소',
    example: ['설정: diff.algorithm=histogram', '결과: Histogram 방식 사용'],
  ),
  DiffAlgorithm.myers: DiffAlgorithmDetails(
    description: '일반적인 소스 변경을 빠르게 비교하는 Git 기본 알고리즘입니다.',
    bestFor: '대부분의 작은 코드 수정',
    example: ['old: setup(); run();', 'new: setup(); log(); run();'],
  ),
  DiffAlgorithm.minimal: DiffAlgorithmDetails(
    description: '계산을 더 수행해 가능한 한 작은 변경 묶음을 찾습니다.',
    bestFor: '작은 diff가 중요하고 계산 시간이 허용되는 파일',
    example: ['반복 줄 사이의 변경', '가장 짧은 삭제·추가 묶음 선택'],
  ),
  DiffAlgorithm.patience: DiffAlgorithmDetails(
    description: '고유한 줄을 기준으로 이동한 코드의 경계를 찾습니다.',
    bestFor: '함수 이동과 큰 코드 재배치',
    example: ['고유 함수 선언을 기준점으로 사용', '이동한 블록의 경계 보존'],
  ),
  DiffAlgorithm.histogram: DiffAlgorithmDetails(
    description: '빈도가 낮은 줄을 기준으로 반복 코드의 경계를 찾습니다.',
    bestFor: '비슷한 줄이 많이 반복되는 소스',
    example: ['반복되는 end 사이의 변경', '희소한 선언 줄을 기준점으로 사용'],
  ),
};
```

`FullDiffAlgorithmChooser`는 공개 상태 타입을 가진 `StatefulWidget`으로 만든다.
상태 타입은 `Future<void> show()`를 공개한다. 버튼의 `onPressed`와
`⌘⇧A` Action은 모두 이 메서드를 호출한다. `show()`는 현재 적용값으로
`previewAlgorithm`을 초기화하고 해당 목록 행에 포커스를 둔 뒤 아래
`showMenu`를 연다.

`showMenu`에는 하나의 사용자 정의 `PopupMenuEntry`를 넣고 내부를 왼쪽
알고리즘 목록과 오른쪽 설명 패널로 나눈다. 호버와 포커스는
`previewAlgorithm`만 바꾸며 선택 콜백은 클릭 또는 Enter에서만 호출한다.
각 목록 행의 Semantics는 현재 적용된 값에 `selected: true`를 주고 키보드로
가리키는 값에는 `focused: true`를 준다. 체크 표시는 적용값에만 남긴다.

- [ ] **Step 4: 도구 모음과 `⌘⇧A`를 설명창에 연결한다**

`GlobalDiffToolbar`은 `diff 알고리즘` 고정 문구와
`FullDiffAlgorithmChooser` 버튼을 나란히 둔다. 버튼의 닫힌 상태에는
`algorithm.label`과 화살표만 표시한다.
`DiffScreen`은 `GlobalKey<FullDiffAlgorithmChooserState>`를 도구 모음에
전달한다. `_OpenAlgorithmChooserIntent`를 `⌘⇧A`에 매핑하고
`_algorithmChooserKey.currentState?.show()`를 호출한다. 설명창을 닫을 때
포커스를 원래 도구 모음으로 돌린다.

- [ ] **Step 5: 알고리즘 UI와 실제 적용 테스트를 통과시킨다**

Run:

```bash
dart format lib/full_diff_algorithm_chooser.dart lib/full_diff_header.dart lib/diff_screen.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
flutter test test/full_diff_header_test.dart test/full_diff_workspace_test.dart --name "algorithm|알고리즘"
```

Expected: 호버 즉시 설명, 키보드 적용과 취소, 실제 repository 호출 모두 PASS

- [ ] **Step 6: 알고리즘 설명창을 커밋한다**

```bash
git add lib/full_diff_algorithm_chooser.dart lib/full_diff_header.dart lib/diff_screen.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
git commit -m "feat: explain diff algorithms in chooser"
```

---

### Task 6: Blame 줄 선택과 커밋 상세 카드

**Files:**
- Modify: `lib/full_blame_view.dart`
- Modify: `lib/diff_screen.dart`
- Test: `test/full_diff_content_views_test.dart`
- Test: `test/full_diff_workspace_test.dart`

**Interfaces:**
- Consumes: `BlameLine.summary`, `fullDiffSourceRowHeight`
- Produces:
  - 선택 가능한 `FullBlameView`
  - `BlameCommitDetailsCard`

- [ ] **Step 1: 호버, 선택, 키보드 이동, 비확장 오버레이 테스트를 작성한다**

`test/full_diff_content_views_test.dart`에 실제 `BlameDocument`와 뷰를 띄운다.

```dart
testWidgets('blame hover and selection keep row geometry stable', (
  tester,
) async {
  await pumpBlameView(tester);
  final row3 = find.byKey(const Key('blame-line-3'));
  final row4 = find.byKey(const Key('blame-line-4'));
  final beforeRow4 = tester.getTopLeft(row4);

  final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
  await mouse.addPointer();
  await mouse.moveTo(tester.getCenter(row3));
  await tester.pump();
  expect(find.byKey(const Key('blame-hover-3')), findsOneWidget);

  await tester.tap(row3);
  await tester.pump();
  expect(find.byKey(const Key('blame-selected-3')), findsOneWidget);
  expect(find.byKey(const Key('blame-commit-details-3')), findsOneWidget);
  expect(tester.getTopLeft(row4), beforeRow4);

  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pump();
  expect(find.byKey(const Key('blame-selected-4')), findsOneWidget);
});
```

카드 y 좌표는 선택 행 상단에 `fullDiffSourceRowHeight * 2`를 더한 값과 1px
오차 안에서 같아야 한다. 카드에는 fixture의 해시, 작성자, 날짜, summary가
보여야 한다.

- [ ] **Step 2: 현재 Stateless Blame 뷰에서 테스트가 실패하는지 확인한다**

Run:

```bash
flutter test test/full_diff_content_views_test.dart --plain-name "blame hover and selection"
```

Expected: 선택과 상세 카드 key가 없어 FAIL

- [ ] **Step 3: FullBlameView를 선택 상태를 가진 StatefulWidget으로 바꾼다**

상태는 화면 안에서만 유지한다.

```dart
final _focusNode = FocusNode(debugLabel: 'full blame lines');
final _selectedLink = LayerLink();
int? _selectedLine;
int? _hoveredLine;
```

각 줄을 `MouseRegion`과 `InkWell`로 감싼다. 클릭하면 줄 번호를 저장하고
`_focusNode.requestFocus()`를 호출한다. `Focus.onKeyEvent`는 Meta와 Alt가 없는
`↑/↓`만 처리하며 범위를 1부터 마지막 줄로 제한한다. 키보드로 이동했을 때는
선택 행의 `BuildContext`에 `Scrollable.ensureVisible`을 호출하되 상세 카드
전체를 맞추려고 추가로 스크롤하지 않는다.

선택 줄의 행에는 `CompositedTransformTarget`을 놓는다. Blame 뷰포트의 Stack
마지막 자식에 `CompositedTransformFollower`를 두고 다음 offset을 사용한다.

```dart
offset: const Offset(12, fullDiffSourceRowHeight * 2),
```

카드는 `IgnorePointer`와 `ClipRect` 안에 두어 뒤의 줄 클릭을 막지 않고
뷰포트 밖에서는 잘리게 한다.

- [ ] **Step 4: 호버와 선택 배경의 우선순위를 구현한다**

`BlameSourceRow`에 `hovered`, `selected`를 전달한다. 색 우선순위는 선택,
활성 Hunk, 호버, 기본 순서다. 추가·삭제 배경은 유지하고 현재 3px인 색상선은
2px로 줄인다.

상세 카드는 다음 정보를 표시한다. `summary`가 비어 있으면 제목용 `Text`를
만들지 않아 해시, 작성자, 날짜만 남긴다.

```dart
Text(blame.sha.length <= 7 ? blame.sha : blame.sha.substring(0, 7))
Text(blame.author)
Text(_formatDate(blame.authorTimestamp))
if (blame.summary.isNotEmpty) Text(blame.summary)
```

각 Blame 행의 Semantics에는 줄 번호와 커밋 제목을 넣고 `selected` 상태를
노출한다. 제목이 없으면 줄 번호, 짧은 해시, 작성자만 label에 넣는다.

- [ ] **Step 5: Blame 상호작용 테스트를 통과시킨다**

Run:

```bash
dart format lib/full_blame_view.dart lib/diff_screen.dart test/full_diff_content_views_test.dart test/full_diff_workspace_test.dart
flutter test test/full_diff_content_views_test.dart test/full_diff_workspace_test.dart --name "blame|Blame"
```

Expected: 호버, 클릭, `↑/↓`, 카드 위치, 행 좌표 보존 모두 PASS

- [ ] **Step 6: Blame 선택 기능을 커밋한다**

```bash
git add lib/full_blame_view.dart lib/diff_screen.dart test/full_diff_content_views_test.dart test/full_diff_workspace_test.dart
git commit -m "feat: select blame lines with commit details"
```

---

### Task 7: 패널 구분선, History 폭과 가장자리 정렬

**Files:**
- Create: `lib/full_diff_resizable_pane.dart`
- Modify: `lib/settings.dart`
- Modify: `lib/diff_screen.dart`
- Modify: `lib/full_history_workspace.dart`
- Modify: `lib/full_history_view.dart`
- Test: `test/app_test.dart`
- Test: `test/full_diff_workspace_test.dart`

**Interfaces:**
- Consumes: `FullDiffColumnWidths`
- Produces:
  - `FullDiffColumnWidths.history`
  - `FullDiffResizablePane`
  - 조절 가능한 `FullHistoryWorkspace`

- [ ] **Step 1: 이전 폭 설정과 두 리사이저를 검증하는 실패 테스트를 작성한다**

`test/app_test.dart`에서 기존 `commits` 값이 History 폭으로 옮겨지는지 확인한다.

```dart
test('legacy full diff commits width migrates to history width', () {
  final widths = FullDiffColumnWidths.fromJson({
    'commits': 244,
    'files': 318,
  });
  expect(widths.history, 244);
  expect(widths.files, 318);
  expect(widths.toJson(), {'history': 244.0, 'files': 318.0});
});
```

`test/full_diff_workspace_test.dart`에서는 History 화면을 열고 두 선을 드래그한다.

```dart
expect(find.byKey(const Key('files-detail-divider')), findsOneWidget);
expect(find.byKey(const Key('history-detail-divider')), findsOneWidget);

final filesBefore = tester.getSize(
  find.byKey(const Key('details-files-column')),
).width;
await tester.drag(
  find.byKey(const Key('details-files-column-resizer')),
  const Offset(24, 0),
);
expect(
  tester.getSize(find.byKey(const Key('details-files-column'))).width,
  filesBefore + 24,
);

final historyBefore = tester.getSize(
  find.byKey(const Key('history-list-pane')),
).width;
await tester.drag(
  find.byKey(const Key('history-list-column-resizer')),
  const Offset(20, 0),
);
expect(
  tester.getSize(find.byKey(const Key('history-list-pane'))).width,
  historyBefore + 20,
);
```

History 첫 행의 선택면 rect가 목록 rect의 top, left, right와 닿는지도 확인한다.

드래그가 끝날 때만 폭 저장 콜백이 호출되고 새 `DiffScreen`이 저장한 두 폭으로
시작하는 테스트도 추가한다.

```dart
FullDiffColumnWidths? saved;
await pumpDiffScreen(
  tester,
  initialPreferences: const FullDiffPreferences(view: FullDiffView.history),
  columnWidths: const FullDiffColumnWidths(history: 244, files: 318),
  onColumnWidthsChanged: (value) => saved = value,
);
final gesture = await tester.startGesture(
  tester.getCenter(find.byKey(const Key('history-list-column-resizer'))),
);
await gesture.moveBy(const Offset(16, 0));
await tester.pump();
expect(saved, isNull);
await gesture.up();
await tester.pump();
expect(saved, const FullDiffColumnWidths(history: 260, files: 318));

await tester.pumpWidget(const SizedBox.shrink());
await pumpDiffScreen(
  tester,
  initialPreferences: const FullDiffPreferences(view: FullDiffView.history),
  columnWidths: saved!,
);
expect(
  tester.getSize(find.byKey(const Key('history-list-pane'))).width,
  260,
);
expect(
  tester.getSize(find.byKey(const Key('details-files-column'))).width,
  318,
);
```

리사이저에 포커스를 둔 뒤 `→`를 누르면 8px 넓어지고 `←`를 누르면 8px
줄어드는지 확인한다. 폭을 바꾼 다음 집중 모드를 켰다가 끄면 변경한 폭으로
돌아와야 한다. 700px 폭의 fixture에서는 `full-diff-detail-pane`이 320px보다
좁아지지 않도록 파일과 History 폭이 먼저 제한되는지도 검증한다.

- [ ] **Step 2: History 폭과 두 번째 리사이저가 없어 테스트가 실패하는지 확인한다**

Run:

```bash
flutter test test/app_test.dart --plain-name "legacy full diff commits width"
flutter test test/full_diff_workspace_test.dart --name "divider|resizer|History"
```

Expected: `history` 필드와 History 리사이저가 없어 FAIL

- [ ] **Step 3: 폭 모델을 파일과 History 이름으로 정리한다**

`FullDiffColumnWidths`를 다음 계약으로 바꾼다.

```dart
class FullDiffColumnWidths {
  const FullDiffColumnWidths({this.history = 280, this.files = 290});

  static const minHistory = 180.0;
  static const maxHistory = 420.0;
  static const minFiles = 158.0;
  static const maxFiles = 520.0;

  final double history;
  final double files;
}
```

`fromJson`은 `history`를 먼저 읽고 없으면 `commits`를 읽는다. `toJson`은
`history`, `files`만 쓴다.

- [ ] **Step 4: 공통 1px 선과 8px 입력 영역을 구현한다**

새 컴포넌트는 자식의 오른쪽에 보이는 선과 넓은 입력 영역을 겹친다.

```dart
class FullDiffResizablePane extends StatelessWidget {
  const FullDiffResizablePane({
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.label,
    required this.resizerKey,
    required this.dividerKey,
    required this.onChanged,
    required this.onChangeEnd,
    required this.child,
    super.key,
  });
}
```

선은 `width: 1`, 드래그와 키보드 입력 영역은 `width: 8`이다. `←/→`는 8px씩
움직이며 Semantics에는 대상 이름과 현재 폭을 넣는다.

`_ResponsiveDiffBody`는 파일 패널에 이 컴포넌트를 사용한다.
`FullHistoryWorkspace`는 `historyWidth`, `onHistoryResized`,
`onHistoryResizeEnd`를 받고 같은 컴포넌트를 사용한다.

- [ ] **Step 5: History 바깥 여백을 없애고 행 내부 여백만 남긴다**

`FullHistoryView`의 `ListView.builder.padding`을 `EdgeInsets.zero`로 바꾼다.
`HistoryRow`의 `FullDiffSelectableRowSurface`가 패널 전체 폭을 차지하게 두고
그 child에만 다음 여백을 둔다.

```dart
child: Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  child: Row(...),
),
```

`DiffScreen`은 `_filesWidth`와 `_historyWidth`를 각각 보관하고 어느 선의
드래그가 끝나도 두 값을 함께 저장한다.

좁은 화면에서는 상세 패널의 최소 폭 320px을 먼저 빼고 남은 폭 안에서 파일과
History 폭을 각 최소·최대 범위로 제한한다. 집중 모드에 들어갈 때는 저장 폭을
바꾸지 않고 목록만 숨기며 해제할 때 메모리에 남은 두 폭을 다시 사용한다.

- [ ] **Step 6: 패널 테스트를 통과시킨다**

Run:

```bash
dart format lib/full_diff_resizable_pane.dart lib/settings.dart lib/diff_screen.dart lib/full_history_workspace.dart lib/full_history_view.dart test/app_test.dart test/full_diff_workspace_test.dart
flutter test test/app_test.dart --name "full diff.*width|legacy full diff"
flutter test test/full_diff_workspace_test.dart --name "History|divider|resizer|column"
```

Expected: 폭 이전, 1px 선, 두 드래그, 가장자리 선택면 모두 PASS

- [ ] **Step 7: 패널 배치 변경을 커밋한다**

```bash
git add lib/full_diff_resizable_pane.dart lib/settings.dart lib/diff_screen.dart lib/full_history_workspace.dart lib/full_history_view.dart test/app_test.dart test/full_diff_workspace_test.dart
git commit -m "feat: resize full diff file and history panes"
```

---

### Task 8: 미리보기 독립 스크롤과 50% 페이지 이동

**Files:**
- Modify: `lib/page_scroll_shortcuts.dart`
- Modify: `lib/timeline.dart`
- Test: `test/page_scroll_shortcuts_test.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `PageScrollIntent`, 미리보기 배치
- Produces:
  - `applyPageScroll`의 50% 뷰포트 이동
  - `preview-files-scroll`
  - `preview-diff-scroll`

- [ ] **Step 1: 페이지 이동 거리를 뷰포트에서 계산하는 실패 테스트를 작성한다**

`test/page_scroll_shortcuts_test.dart`의 48px 기대를 다음 계약으로 바꾼다.

```dart
testWidgets('scrolls half a viewport and clamps at both ends', (
  tester,
) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        height: 120,
        child: SingleChildScrollView(
          controller: controller,
          child: const SizedBox(height: 600),
        ),
      ),
    ),
  );
  await tester.pump();

  applyPageScroll(controller, direction: 1, animate: false);
  expect(controller.position.pixels, 60);
  applyPageScroll(controller, direction: -1, animate: false);
  expect(controller.position.pixels, 0);

  controller.jumpTo(controller.position.maxScrollExtent - 20);
  applyPageScroll(controller, direction: 1, animate: false);
  expect(controller.position.pixels, controller.position.maxScrollExtent);
});
```

- [ ] **Step 2: 미리보기의 두 스크롤 위치가 독립적인 실패 테스트를 작성한다**

`test/app_test.dart`에서 변경 파일과 긴 diff를 가진 미리보기를 연다.

```dart
final filesScrollable = find.byKey(const Key('preview-files-scroll'));
final diffScrollable = find.byKey(const Key('preview-diff-scroll'));
expect(filesScrollable, findsOneWidget);
expect(diffScrollable, findsOneWidget);

final filesPosition = tester
    .state<ScrollableState>(filesScrollable)
    .position;
final diffPosition = tester
    .state<ScrollableState>(diffScrollable)
    .position;

await tester.drag(filesScrollable, const Offset(0, -120));
await tester.pump();
expect(filesPosition.pixels, greaterThan(0));
expect(diffPosition.pixels, 0);

await tester.drag(diffScrollable, const Offset(0, -120));
await tester.pump();
expect(filesPosition.pixels, greaterThan(0));
expect(diffPosition.pixels, greaterThan(0));
```

마지막으로 파일 영역을 클릭한 뒤 `⌘⇧↓`를 보내 파일 위치만 뷰포트의 50%만큼
옮기고, diff 영역을 클릭한 뒤 같은 키로 diff 위치만 옮기는 검증을 추가한다.

- [ ] **Step 3: 두 실패를 확인한다**

Run:

```bash
flutter test test/page_scroll_shortcuts_test.dart
flutter test test/app_test.dart --plain-name "preview file and diff panes scroll independently"
```

Expected: 첫 테스트는 48px 이동 때문에 FAIL, 두 번째는 단일
`preview-scroll`만 있어 FAIL

- [ ] **Step 4: 페이지 이동을 뷰포트 높이의 절반으로 바꾼다**

`pageScrollStep` 상수를 삭제하고 다음 계산을 사용한다.

```dart
final distance = position.viewportDimension * 0.5;
final target = (position.pixels + direction * distance)
    .clamp(position.minScrollExtent, position.maxScrollExtent)
    .toDouble();
```

첫 KeyDown은 기존 100ms 애니메이션을 사용하고 KeyRepeat은 `jumpTo`를
사용한다.

- [ ] **Step 5: 미리보기 몸체를 두 스크롤 영역으로 나눈다**

`_previewScrollController`를 다음 두 컨트롤러로 교체한다.

```dart
final _previewFilesScrollController = ScrollController();
final _previewDiffScrollController = ScrollController();
ScrollController? _activePreviewScrollController;
```

좌측·우측 배치는 위아래로 나눈다.

```dart
Column(
  children: [
    Expanded(child: _previewScrollableInfo(info)),
    const Divider(height: 1, color: _border),
    Expanded(child: _previewScrollableDiff(diff)),
  ],
)
```

하단 배치는 좌우로 나눈다.

```dart
Row(
  children: [
    SizedBox(width: 240, child: _previewScrollableInfo(info)),
    const VerticalDivider(width: 1, color: _border),
    Expanded(child: _previewScrollableDiff(diff)),
  ],
)
```

각 영역은 `Listener(onPointerDown:)`와
`NotificationListener<ScrollNotification>`로 활성 컨트롤러를 기록한다.
`⌘⇧↑/↓`는 활성 컨트롤러를 사용하고 아직 없으면 diff 컨트롤러를 사용한다.

파일 행 선택은 공통 메서드로 모은다.

```dart
void _selectPreviewFile(GitCommit commit, String path) {
  setState(() => _previewPaths[commit.sha] = path);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_previewDiffScrollController.hasClients) {
      _previewDiffScrollController.jumpTo(0);
    }
  });
}
```

파일 목록의 스크롤 위치는 바꾸지 않는다.

- [ ] **Step 6: 스크롤 테스트를 통과시킨다**

Run:

```bash
dart format lib/page_scroll_shortcuts.dart lib/timeline.dart test/page_scroll_shortcuts_test.dart test/app_test.dart
flutter test test/page_scroll_shortcuts_test.dart
flutter test test/app_test.dart --name "preview.*scroll|page scroll|meta arrows"
```

Expected: 두 영역 독립 스크롤과 50% 이동 모두 PASS

- [ ] **Step 7: 미리보기와 페이지 이동을 커밋한다**

```bash
git add lib/page_scroll_shortcuts.dart lib/timeline.dart test/page_scroll_shortcuts_test.dart test/app_test.dart
git commit -m "feat: separate preview scrolling"
```

---

### Task 9: 통합 검증과 기능별 이미지

**Files:**
- Modify: `test/support/full_diff_qa_harness.dart`
- Modify: `test/full_diff_visual_test.dart`
- Modify: `docs/superpowers/verification/full-diff-qa/README.md`
- Create: `docs/superpowers/verification/full-diff-qa/interaction-persistence-review.md`
- Create: `docs/superpowers/verification/full-diff-qa/actual/24-unified-hunks.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/25-side-by-side-full-file.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/26-shortcut-hints.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/27-algorithm-chooser.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/28-blame-selection.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/29-history-resizers.png`
- Delete: `docs/superpowers/verification/full-diff-qa/actual/03-file-view.png`
- Delete: `docs/superpowers/verification/full-diff-qa/diff/03-file-view.png`
- Delete: `docs/superpowers/verification/full-diff-qa/diff/03-file-view-side-by-side.png`

**Interfaces:**
- Consumes: 모든 앞선 작업의 공개 위젯과 QA fixture
- Produces: 기능별 검수 이미지, 최종 검수 기록

- [ ] **Step 1: 새 상태를 캡처하는 golden 테스트를 먼저 추가한다**

`QaCase`를 최종 모델에 맞춘다.

```dart
typedef QaCase = ({
  String name,
  Size size,
  FullDiffView view,
  DiffLayout layout,
  DiffScope scope,
  bool focus,
  bool whitespace,
  bool wrap,
  int hunk,
  DiffAlgorithm algorithm,
  bool detailOnly,
});
```

기존 `03-file-view`는 제거한다. 24~29는 다음 상태를 캡처한다.

```dart
(
  name: '24-unified-hunks',
  size: Size(1070, 842),
  view: FullDiffView.diff,
  layout: DiffLayout.unified,
  scope: DiffScope.hunks,
  focus: false,
  whitespace: false,
  wrap: false,
  hunk: 0,
  algorithm: DiffAlgorithm.gitSetting,
  detailOnly: false,
),
(
  name: '25-side-by-side-full-file',
  size: Size(1280, 842),
  view: FullDiffView.diff,
  layout: DiffLayout.sideBySide,
  scope: DiffScope.fullFile,
  focus: false,
  whitespace: false,
  wrap: false,
  hunk: 0,
  algorithm: DiffAlgorithm.gitSetting,
  detailOnly: false,
),
(
  name: '26-shortcut-hints',
  size: Size(1280, 842),
  view: FullDiffView.diff,
  layout: DiffLayout.unified,
  scope: DiffScope.hunks,
  focus: false,
  whitespace: false,
  wrap: false,
  hunk: 0,
  algorithm: DiffAlgorithm.gitSetting,
  detailOnly: false,
),
(
  name: '27-algorithm-chooser',
  size: Size(1280, 842),
  view: FullDiffView.diff,
  layout: DiffLayout.unified,
  scope: DiffScope.hunks,
  focus: false,
  whitespace: false,
  wrap: false,
  hunk: 0,
  algorithm: DiffAlgorithm.histogram,
  detailOnly: false,
),
(
  name: '28-blame-selection',
  size: Size(1280, 842),
  view: FullDiffView.blame,
  layout: DiffLayout.unified,
  scope: DiffScope.hunks,
  focus: false,
  whitespace: false,
  wrap: false,
  hunk: 0,
  algorithm: DiffAlgorithm.gitSetting,
  detailOnly: false,
),
(
  name: '29-history-resizers',
  size: Size(1280, 842),
  view: FullDiffView.history,
  layout: DiffLayout.sideBySide,
  scope: DiffScope.hunks,
  focus: false,
  whitespace: false,
  wrap: false,
  hunk: 0,
  algorithm: DiffAlgorithm.gitSetting,
  detailOnly: false,
),
```

각 캡처의 `prepare`는 Command key down, 알고리즘 선택창 열기, Blame 줄 클릭,
History 폭 드래그처럼 실제 입력을 보낸다.

- [ ] **Step 2: 새 golden 파일이 없어서 실패하는지 확인한다**

Run:

```bash
flutter test test/full_diff_visual_test.dart --reporter expanded
```

Expected: 24~29 golden이 없거나 기존 이미지와 달라 FAIL

- [ ] **Step 3: 정해진 상태를 캡처하고 시각 검수 자료를 갱신한다**

Run:

```bash
flutter test --update-goldens test/full_diff_visual_test.dart --reporter expanded
dart run tool/full_diff_visual_diff.dart
```

새 디자인은 기존 기준 이미지가 없으므로 actual 이미지를 reference로 복사하지
않는다. `README.md`에는 24~29의 목적과 육안 검수 결과를 적고
`interaction-persistence-review.md`에는 다음 항목을 이미지별로 기록한다.

- File 버튼이 남아 있지 않은가
- Unified / Side-by-side가 배타적으로 보이는가
- Hunk가 독립 토글로 보이는가
- 모든 Hunk가 위치 순서대로 이어지는가
- 설명창의 좌우 정보가 잘리지 않는가
- 단축키 배지가 컨트롤 아래에 있고 도구 모음이 움직이지 않는가
- Blame 카드가 선택 줄보다 두 줄 아래에 겹쳐 있는가
- 파일·History·diff 사이의 1px 선이 이어지는가
- History 선택면이 패널 가장자리까지 닿는가

- [ ] **Step 4: 전체 자동 검증을 실행한다**

Run:

```bash
flutter test
flutter analyze
flutter build macos --release
```

Expected:

- `flutter test`: 모든 테스트 PASS
- `flutter analyze`: `No issues found!`
- `flutter build macos --release`: 종료 코드 0과 release 앱 생성

- [ ] **Step 5: 설계 문서와 구현을 대조한다**

`docs/superpowers/specs/2026-07-28-full-diff-interaction-persistence-design.md`
완료 기준 14개를 `interaction-persistence-review.md`에서 하나씩 PASS 또는 FAIL로
기록한다. FAIL이 하나라도 있으면 커밋 전에 해당 작업의 실패 테스트로 돌아가
수정한다.

다음 검색 결과에는 제품 코드의 미완성 표시가 없어야 한다.

```bash
rg -n "UnimplementedError|구현 예정|미구현 상태" lib test
```

- [ ] **Step 6: 최종 검수 자료를 커밋한다**

```bash
git add test/support/full_diff_qa_harness.dart test/full_diff_visual_test.dart docs/superpowers/verification/full-diff-qa
git commit -m "test: verify full diff interaction persistence"
```

- [ ] **Step 7: 완료 전 검증 절차로 전환한다**

`superpowers:verification-before-completion`을 읽고 깨끗한 상태에서 전체 테스트,
분석, macOS release 빌드를 다시 실행한다. 구현 브랜치를 정리하기 전에는
`superpowers:requesting-code-review`로 설계 일치와 코드 품질 검토를 받는다.
