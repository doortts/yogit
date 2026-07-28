# Vim Navigation and Base Branch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 방향키를 직접 처리하는 화면에서 `h`, `j`, `k`, `l`도 이동키로 쓸 수 있게 하고, 저장소별 로컬 기준 브랜치를 골라 그 첫 번째 부모 흐름을 타임라인의 0번 레인에 배치한다.

**Architecture:** 수정키가 없는 Vim 이동키를 방향키로 바꾸는 작은 공통 함수를 만든 뒤 기존 키 처리 지점에만 적용한다. 기준 브랜치는 `AppSettings`에 저장소 절대 경로별로 보관하고 `TimelineScreen`이 refs와 저장값을 합쳐 실제 브랜치를 정한다. `layoutGraph`는 선택 사항인 tip SHA를 받아 해당 흐름이 시작될 때까지 0번 레인을 비워 둔다.

**Tech Stack:** Dart 3.11, Flutter, macOS, `flutter_test`, 기존 Git 명령 실행 계층

## Global Constraints

- 기준 브랜치 선택 목록에는 로컬 브랜치만 표시한다.
- 기준 브랜치를 골라도 체크아웃하지 않는다.
- Git 로그의 커밋 순서와 페이지 크기는 바꾸지 않는다.
- `Command`, `Control`, `Option`, `Shift` 가운데 하나라도 눌린 `h`, `j`, `k`, `l`은 변환하지 않는다.
- 텍스트 입력란과 열린 팝업 메뉴의 기본 키 처리를 바꾸지 않는다.
- 기준 브랜치를 바꿀 때 선택한 커밋, 스크롤 위치, 미리보기 상태, 이미 읽은 커밋 페이지를 유지한다.
- refs를 읽지 못하거나 설정을 저장하지 못해도 타임라인은 계속 사용할 수 있어야 한다.
- 새 외부 패키지는 추가하지 않는다.

---

### Task 1: 공통 Vim 이동키 변환

**Files:**
- Create: `lib/vim_navigation.dart`
- Create: `test/vim_navigation_test.dart`

**Interfaces:**
- Consumes: Flutter `LogicalKeyboardKey`
- Produces: `LogicalKeyboardKey normalizeNavigationKey(LogicalKeyboardKey key, {required bool hasModifier})`

- [ ] **Step 1: 변환 규칙을 고정하는 실패 테스트 작성**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/vim_navigation.dart';

void main() {
  test('maps unmodified vim keys to arrow keys', () {
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyH, hasModifier: false),
      LogicalKeyboardKey.arrowLeft,
    );
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyJ, hasModifier: false),
      LogicalKeyboardKey.arrowDown,
    );
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyK, hasModifier: false),
      LogicalKeyboardKey.arrowUp,
    );
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyL, hasModifier: false),
      LogicalKeyboardKey.arrowRight,
    );
  });

  test('leaves arrows, ordinary keys, and modified vim keys unchanged', () {
    expect(
      normalizeNavigationKey(
        LogicalKeyboardKey.arrowDown,
        hasModifier: false,
      ),
      LogicalKeyboardKey.arrowDown,
    );
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyA, hasModifier: false),
      LogicalKeyboardKey.keyA,
    );
    expect(
      normalizeNavigationKey(LogicalKeyboardKey.keyJ, hasModifier: true),
      LogicalKeyboardKey.keyJ,
    );
  });
}
```

- [ ] **Step 2: 새 테스트가 구현 부재로 실패하는지 확인**

Run: `flutter test test/vim_navigation_test.dart`

Expected: FAIL because `package:yogit/vim_navigation.dart` and `normalizeNavigationKey` do not exist.

- [ ] **Step 3: 최소 변환 함수 구현**

```dart
import 'package:flutter/services.dart';

LogicalKeyboardKey normalizeNavigationKey(
  LogicalKeyboardKey key, {
  required bool hasModifier,
}) {
  if (hasModifier) return key;
  return switch (key) {
    LogicalKeyboardKey.keyH => LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.keyJ => LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.keyK => LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.keyL => LogicalKeyboardKey.arrowRight,
    _ => key,
  };
}
```

- [ ] **Step 4: 공통 함수 테스트 통과 확인**

Run: `flutter test test/vim_navigation_test.dart`

Expected: PASS.

- [ ] **Step 5: 공통 함수 커밋**

```bash
git add lib/vim_navigation.dart test/vim_navigation_test.dart
git commit -m "feat: add vim navigation key mapping"
```

---

### Task 2: 전체 diff 화면의 직접 키 처리 지점 연결

**Files:**
- Modify: `lib/diff_screen.dart:766-790,854-929`
- Modify: `lib/full_diff_resizable_pane.dart:100-113`
- Modify: `lib/full_diff_minimap.dart:324-338`
- Modify: `lib/full_blame_view.dart:203-220`
- Modify: `lib/full_history_view.dart:55-73`
- Modify: `test/full_diff_workspace_test.dart:1674-1734,2420-2590`
- Modify: `test/full_diff_minimap_test.dart:446-470`
- Modify: `test/full_diff_content_views_test.dart:390-415`

**Interfaces:**
- Consumes: `normalizeNavigationKey(LogicalKeyboardKey, {required bool hasModifier})`
- Produces: 파일 목록 `j/k/l`, 히스토리 `h/j/k`, blame `j/k`, 미니맵 `j/k`, 크기 조절 손잡이 `h/l`

- [ ] **Step 1: 기존 방향키 테스트 옆에 Vim 키 동등성 테스트 추가**

`test/full_diff_workspace_test.dart`의 파일 탐색, 히스토리 탐색, 크기 조절 테스트에 다음 검증을 추가한다.

```dart
await sendChord(tester, LogicalKeyboardKey.keyJ);
await tester.pumpAndSettle();
expect(controller.state.selectedFile, fileB);

await sendChord(tester, LogicalKeyboardKey.keyK);
await tester.pumpAndSettle();
expect(controller.state.selectedFile, fileA);

Focus.of(tester.element(filesResizer)).requestFocus();
await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
await tester.pump();
expect(
  tester.getSize(find.byKey(const Key('details-files-column'))).width,
  326,
);
await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
await tester.pump();
expect(
  tester.getSize(find.byKey(const Key('details-files-column'))).width,
  318,
);
```

`test/full_diff_minimap_test.dart`와 `test/full_diff_content_views_test.dart`에는 기존 방향키 기대값을 그대로 쓰는 `keyJ`, `keyK` 검증을 넣는다.

```dart
await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
await tester.pump();
expect(selected.last, same(twoHunkDocument.hunks.last.anchor));

await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
await tester.pump();
expect(selected.last, same(twoHunkDocument.hunks.first.anchor));
```

알고리즘 선택 메뉴에는 Vim 별칭을 추가하지 않는다. 메뉴가 열린 상태에서 `j`가 알고리즘 선택과 파일 선택을 모두 바꾸지 않는지 검증한다.

```dart
final selectedFile = fixture.controller.state.selectedFile;
await sendChord(tester, LogicalKeyboardKey.keyA, meta: true, shift: true);
expect(find.byKey(const Key('algorithm-details-gitSetting')), findsOneWidget);
await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
await tester.pump();
expect(find.byKey(const Key('algorithm-details-gitSetting')), findsOneWidget);
expect(fixture.controller.state.selectedFile, selectedFile);
```

- [ ] **Step 2: 전체 diff 관련 테스트가 Vim 키에서 실패하는지 확인**

Run: `flutter test test/full_diff_workspace_test.dart test/full_diff_minimap_test.dart test/full_diff_content_views_test.dart`

Expected: FAIL because `h`, `j`, `k`, `l` are not handled by the focused lists, minimap, or resize handles.

- [ ] **Step 3: 모든 직접 처리 지점에서 수정키 상태를 한 번 계산한 뒤 키 변환**

각 파일에 `package:yogit/vim_navigation.dart`를 가져온다. 직접 키를 비교하기 전에 다음 형태로 변환한다.

```dart
final keyboard = HardwareKeyboard.instance;
final key = normalizeNavigationKey(
  event.logicalKey,
  hasModifier:
      keyboard.isMetaPressed ||
      keyboard.isAltPressed ||
      keyboard.isShiftPressed ||
      keyboard.isControlPressed,
);
```

`diff_screen.dart`의 `_handleFileListKey`, `full_diff_minimap.dart`, `full_blame_view.dart`, `full_history_view.dart`, `full_diff_resizable_pane.dart`는 이후 비교 대상을 `event.logicalKey`에서 `key`로 바꾼다. 기존 수정키 검사는 그대로 둔다. 따라서 `Shift+방향키`처럼 이미 처리하던 조합은 유지되고 수정키가 있는 Vim 문자만 변환 대상에서 빠진다.

`diff_screen.dart`의 최상위 `Shortcuts`에는 수정키 없는 기본 파일 이동만 추가한다.

```dart
if (state.view != FullDiffView.history)
  const SingleActivator(LogicalKeyboardKey.keyK):
      _StepPrimaryFileIntent(-1),
if (state.view != FullDiffView.history)
  const SingleActivator(LogicalKeyboardKey.keyJ):
      _StepPrimaryFileIntent(1),
```

수정키가 있는 기존 방향키 조합과 `full_diff_algorithm_chooser.dart`의 메뉴 단축키는 건드리지 않는다.

- [ ] **Step 4: 전체 diff 관련 테스트 통과 확인**

Run: `flutter test test/full_diff_workspace_test.dart test/full_diff_minimap_test.dart test/full_diff_content_views_test.dart`

Expected: PASS, including the unchanged algorithm chooser arrow behavior.

- [ ] **Step 5: 전체 diff Vim 탐색 커밋**

```bash
git add lib/diff_screen.dart lib/full_diff_resizable_pane.dart lib/full_diff_minimap.dart lib/full_blame_view.dart lib/full_history_view.dart test/full_diff_workspace_test.dart test/full_diff_minimap_test.dart test/full_diff_content_views_test.dart
git commit -m "feat: support vim keys in diff navigation"
```

---

### Task 3: 타임라인 Vim 이동과 텍스트 입력 보호

**Files:**
- Modify: `lib/timeline.dart:655-701,1674-1701`
- Modify: `test/app_test.dart:220-265,1567-1670,6170-6230,7510-7605`

**Interfaces:**
- Consumes: `normalizeNavigationKey(LogicalKeyboardKey, {required bool hasModifier})`
- Produces: 타임라인 `j/k` 선택 이동과 반복 입력, 타임라인 열 크기 조절 `h/l`

- [ ] **Step 1: 타임라인 이동, 반복 입력, 수정키, 텍스트 입력 테스트 작성**

기존 타임라인 방향키 테스트에 Vim 키를 추가한다.

```dart
await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
expect(find.byKey(const Key('selected-row-1')), findsOneWidget);
await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
expect(find.byKey(const Key('selected-row-0')), findsOneWidget);

await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyJ);
await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
expect(find.byKey(const Key('selected-row-2')), findsOneWidget);
```

수정키가 있는 Vim 키는 선택을 바꾸지 않는지 검증한다.

```dart
await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
expect(find.byKey(const Key('selected-row-0')), findsOneWidget);
```

`ref-filter`를 눌러 포커스를 옮긴 뒤 네 문자가 그대로 입력되는지 검증한다.

```dart
await tester.tap(find.byKey(const Key('ref-filter')));
await tester.enterText(find.byKey(const Key('ref-filter')), 'hjkl');
await tester.pump();
expect(
  tester.widget<TextField>(find.byKey(const Key('ref-filter'))).controller!.text,
  'hjkl',
);
```

타임라인 열 크기 조절 테스트에는 `keyL`로 8px 늘리고 `keyH`로 되돌리는 검증을 추가한다.

- [ ] **Step 2: 타임라인 Vim 키 테스트가 실패하는지 확인**

Run: `flutter test test/app_test.dart`

Expected: FAIL on Vim selection and resize assertions while existing text field behavior remains intact.

- [ ] **Step 3: 타임라인 키 처리에 공통 변환 적용**

`_onKeyEvent`에서 페이지 이동 조합을 먼저 처리한 뒤 키를 정규화한다.

```dart
final keyboard = HardwareKeyboard.instance;
final key = normalizeNavigationKey(
  event.logicalKey,
  hasModifier:
      keyboard.isMetaPressed ||
      keyboard.isAltPressed ||
      keyboard.isShiftPressed ||
      keyboard.isControlPressed,
);
final step = switch (key) {
  LogicalKeyboardKey.arrowDown => 1,
  LogicalKeyboardKey.arrowUp => -1,
  _ => 0,
};
```

기존 `Meta+↑/↓` 미리보기 파일 이동은 `event.logicalKey`와 기존 수정키 검사로 계속 처리한다. 열 크기 조절 손잡이도 같은 변환 함수를 쓴다. 변환은 타임라인의 `Focus`와 손잡이의 `Focus` 안에서만 일어나므로 `TextField`가 받은 문자는 그대로 남는다.

- [ ] **Step 4: 타임라인 테스트 통과 확인**

Run: `flutter test test/app_test.dart`

Expected: PASS.

- [ ] **Step 5: 타임라인 Vim 탐색 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: support vim keys in timeline navigation"
```

---

### Task 4: 저장소별 기준 브랜치 설정

**Files:**
- Modify: `lib/settings.dart:201-340`
- Modify: `test/app_test.dart:2150-2230,4740-4770`

**Interfaces:**
- Consumes: JSON object whose `baseBranches` member may be absent or malformed
- Produces: `AppSettings.baseBranches`, `AppSettings.copyWith({Map<String, String>? baseBranches})`

- [ ] **Step 1: 설정 JSON 왕복과 이전 형식 호환 테스트 작성**

```dart
test('base branches round-trip per repository', () {
  const settings = AppSettings(
    baseBranches: {
      '/repos/one': 'main',
      '/repos/two': 'release',
    },
  );
  expect(AppSettings.fromJson(settings.toJson()), settings);
  expect(AppSettings.fromJson(const {}).baseBranches, isEmpty);
  expect(
    AppSettings.fromJson({
      'baseBranches': {
        '/repos/one': 'main',
        '/repos/bad': 42,
      },
    }).baseBranches,
    {'/repos/one': 'main'},
  );
});

test('copyWith replaces the base branch map without losing other settings', () {
  const settings = AppSettings(showAvatars: false);
  final changed = settings.copyWith(baseBranches: {'/repos/one': 'develop'});
  expect(changed.showAvatars, isFalse);
  expect(changed.baseBranches, {'/repos/one': 'develop'});
});
```

`settings persist only the supported fields` 테스트의 저장값에도 두 저장소 맵을 넣고 파일을 다시 읽었을 때 그대로인지 확인한다.

- [ ] **Step 2: 설정 테스트가 새 필드 부재로 실패하는지 확인**

Run: `flutter test test/app_test.dart --plain-name "base branch"`

Expected: FAIL because `AppSettings.baseBranches` and its constructor argument do not exist.

- [ ] **Step 3: `AppSettings`에 맵 직렬화와 값 의미론 추가**

생성자와 필드, `copyWith`에 다음 값을 추가한다.

```dart
this.baseBranches = const {},

final Map<String, String> baseBranches;

Map<String, String>? baseBranches,

baseBranches: baseBranches ?? this.baseBranches,
```

`fromJson` 앞부분에서 문자열 키와 문자열 값만 읽는다.

```dart
final storedBaseBranches = value['baseBranches'];
final baseBranches = <String, String>{
  if (storedBaseBranches is Map)
    for (final entry in storedBaseBranches.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
};
```

`AppSettings(...)`에 `baseBranches: baseBranches`를 넘기고 `toJson()`에는 다음 항목을 추가한다.

```dart
'baseBranches': baseBranches,
```

동등성에는 `mapEquals(baseBranches, other.baseBranches)`를 넣고 해시에는 키와 값을 함께 반영한다.

```dart
Object.hashAllUnordered(
  baseBranches.entries.map((entry) => Object.hash(entry.key, entry.value)),
),
```

- [ ] **Step 4: 설정 관련 테스트 통과 확인**

Run: `flutter test test/app_test.dart --plain-name "base branch"`

Expected: PASS.

Run: `flutter test test/app_test.dart --plain-name "settings persist only the supported fields"`

Expected: PASS.

- [ ] **Step 5: 설정 저장 커밋**

```bash
git add lib/settings.dart test/app_test.dart
git commit -m "feat: persist base branch per repository"
```

---

### Task 5: 기준 브랜치 결정과 0번 레인 예약

**Files:**
- Modify: `lib/git.dart:318-430,647-670`
- Modify: `test/git_test.dart:30-250`

**Interfaces:**
- Produces: `String? resolveBaseBranch(RepoRefs refs, String? savedBranch)`
- Produces: `List<GraphRow> layoutGraph(List<GitCommit> commits, {String? preferredTip})`

- [ ] **Step 1: 기준 브랜치 결정 순서 테스트 작성**

```dart
test('resolves a saved local branch before current and first local', () {
  const refs = RepoRefs(
    local: ['main', 'release'],
    current: 'main',
  );
  expect(resolveBaseBranch(refs, 'release'), 'release');
  expect(resolveBaseBranch(refs, 'deleted'), 'main');
  expect(
    resolveBaseBranch(
      const RepoRefs(local: ['release'], current: null),
      null,
    ),
    'release',
  );
  expect(resolveBaseBranch(const RepoRefs(), null), isNull);
});
```

- [ ] **Step 2: 기준 tip과 첫 번째 부모 흐름의 레인 테스트 작성**

```dart
test('preferred tip reserves lane zero across newer branch commits', () {
  final rows = layoutGraph(
    [
      _commit('feature-tip', ['base']),
      _commit('main-tip', ['main-parent']),
      _commit('main-parent', ['base']),
      _commit('base', const []),
    ],
    preferredTip: 'main-tip',
  );
  expect([for (final row in rows) row.lane], [1, 0, 0, 0]);
});

test('working tree uses lane zero only when its parent is preferred', () {
  final current = layoutGraph(
    [
      _commit('', ['main-tip']),
      _commit('main-tip', ['root']),
      _commit('root', const []),
    ],
    preferredTip: 'main-tip',
  );
  expect([for (final row in current) row.lane], [0, 0, 0]);

  final other = layoutGraph(
    [
      _commit('', ['feature-tip']),
      _commit('feature-tip', ['root']),
      _commit('main-tip', ['root']),
      _commit('root', const []),
    ],
    preferredTip: 'main-tip',
  );
  expect(other.first.lane, greaterThan(0));
  expect(other[2].lane, 0);
});

test('first-parent edge to unloaded preferred tip uses lane zero', () {
  final row = layoutGraph(
    [_commit('child', ['preferred'])],
    preferredTip: 'preferred',
  ).single;
  expect(row.parentLanes, [0]);
  expect(row.transitions, [(from: 1, to: 0, sha: 'preferred')]);
});

test('merge-parent edge to unloaded preferred tip uses lane zero', () {
  final row = layoutGraph(
    [_commit('merge', ['main', 'preferred'])],
    preferredTip: 'preferred',
  ).single;
  expect(row.parentLanes, [1, 0]);
  expect(row.transitions, [(from: 1, to: 0, sha: 'preferred')]);
});
```

기존 페이지 안정성 테스트를 `preferredTip`을 넘긴 경우에도 반복한다. 짧은 페이지에서 먼저 읽은 자식이 아직 읽지 않은 `preferredTip`을 첫 번째 부모나 머지 부모로 가리키면, 전체 페이지를 읽은 뒤에도 앞부분의 레인, 브랜치 식별자, 전이선이 같아야 한다.

```dart
final page = layoutGraph(commits.take(4).toList(), preferredTip: 'P');
final full = layoutGraph(commits, preferredTip: 'P');
expect(
  [for (final row in page) (row.lane, row.branch, row.transitions)],
  [
    for (final row in full.take(page.length))
      (row.lane, row.branch, row.transitions),
  ],
);
```

마지막으로 `preferredTip`을 생략한 결과를 현재 기대 배열과 비교해 기존 동작을 고정한다.

- [ ] **Step 3: 그래프와 기준 브랜치 테스트가 실패하는지 확인**

Run: `flutter test test/git_test.dart`

Expected: FAIL because the new named argument and `resolveBaseBranch` do not exist.

- [ ] **Step 4: 기준 브랜치 결정 함수 구현**

`RepoRefs` 선언 뒤에 다음 함수를 둔다.

```dart
String? resolveBaseBranch(RepoRefs refs, String? savedBranch) {
  if (savedBranch != null && refs.local.contains(savedBranch)) {
    return savedBranch;
  }
  final current = refs.current;
  if (current != null && refs.local.contains(current)) return current;
  return refs.local.isEmpty ? null : refs.local.first;
}
```

- [ ] **Step 5: `layoutGraph`가 선호 tip을 만날 때까지 0번 레인을 예약하도록 구현**

함수 서명과 초기 상태를 다음처럼 바꾼다.

```dart
List<GraphRow> layoutGraph(
  List<GitCommit> commits, {
  String? preferredTip,
}) {
  final columns = <_Column>[
    if (preferredTip != null) (sha: null, row: -1, line: -1),
  ];
  var preferredNodePlaced = false;
  var preferredTipLoaded = false;
```

각 커밋의 일반 레인 탐색 전에 강제 배치 여부와 탐색 시작 열을 계산한다.

```dart
final workingTreeStartsPreferred =
    !preferredNodePlaced &&
    index == 0 &&
    commit.sha.isEmpty &&
    commit.parents.isNotEmpty &&
    commit.parents.first == preferredTip;
final startsPreferred =
    !preferredNodePlaced &&
    (commit.sha == preferredTip || workingTreeStartsPreferred);
final firstCandidate =
    preferredTip != null && !preferredNodePlaced && !startsPreferred ? 1 : 0;

var lane = startsPreferred ? 0 : -1;
if (startsPreferred) preferredNodePlaced = true;
for (
  var column = firstCandidate;
  column < columns.length && lane < 0;
  column++
) {
  if (columns[column].sha == commit.sha && clear(column)) lane = column;
}
for (
  var column = firstCandidate;
  column < columns.length && lane < 0;
  column++
) {
  if (columns[column].sha == null && clear(column)) lane = column;
}
```

열 추가와 수렴 계산 뒤에는 아직 읽지 않은 `preferredTip`을 현재 커밋이 부모로 가리키는지 확인한다. 첫 번째 부모와 머지 부모를 구분하지 않고 해당 부모 레인을 0으로 정하며, 현재 레인에서 0번 레인으로 향하는 전이선을 즉시 만든다. 0번 레인에는 같은 브랜치 식별자로 `preferredTip`을 기다리는 선을 두고, 나중에 tip을 읽으면 그 선을 이어받게 한다. 따라서 페이지를 추가해도 앞부분의 레인, 브랜치 식별자, 전이선이 바뀌지 않는다. `preferredTip == null`이면 `columns`가 빈 목록에서 시작하고 `firstCandidate`가 0이므로 기존 결과가 유지된다.

- [ ] **Step 6: 전체 Git 그래프 테스트 통과 확인**

Run: `flutter test test/git_test.dart`

Expected: PASS, including every pre-existing graph topology test.

- [ ] **Step 7: 그래프 계산 커밋**

```bash
git add lib/git.dart test/git_test.dart
git commit -m "feat: reserve graph lane for base branch"
```

---

### Task 6: 저장소와 기준 브랜치 선택 위젯

**Files:**
- Create: `lib/repository_branch_selector.dart`
- Create: `test/repository_branch_selector_test.dart`

**Interfaces:**
- Produces: `RepositoryBranchSelector`
- Produces internally: `_SelectorField`
- Constructor:

```dart
const RepositoryBranchSelector({
  required String repositoryName,
  required String repositoryPath,
  required List<String> localBranches,
  required String? selectedBranch,
  required bool refsLoading,
  required bool refsLoadFailed,
  required VoidCallback onRepositoryPressed,
  required ValueChanged<String> onBranchSelected,
  Key? key,
})
```

- [ ] **Step 1: 표시 상태와 로컬 브랜치 메뉴 테스트 작성**

```dart
testWidgets('shows repository and only supplied local branches', (tester) async {
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
  await tester.tap(find.byKey(const Key('base-branch-menu-release')));
  expect(selected, 'release');
});
```

로딩, 빈 목록, 실패 상태를 표 형식의 매개변수 테스트로 추가한다.

```dart
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
  });
}
```

- [ ] **Step 2: 위젯 테스트가 구현 부재로 실패하는지 확인**

Run: `flutter test test/repository_branch_selector_test.dart`

Expected: FAIL because `RepositoryBranchSelector` does not exist.

- [ ] **Step 3: 두 선택 영역과 브랜치 팝업 구현**

`RepositoryBranchSelector`는 `Row(mainAxisSize: MainAxisSize.min)` 안에 두 영역을 둔다. 저장소 영역은 `InkWell`로 기존 폴더 선택 콜백을 호출하고 브랜치 영역은 `PopupMenuButton<String>`을 사용한다.

```dart
final branchLabel = refsLoadFailed
    ? '불러오기 실패'
    : refsLoading
    ? '불러오는 중'
    : localBranches.isEmpty
    ? '브랜치 없음'
    : selectedBranch ?? localBranches.first;
final branchEnabled =
    !refsLoading && !refsLoadFailed && localBranches.isNotEmpty;
```

저장소 값은 최대 180px, 브랜치 값은 최대 160px로 제한한다. 두 값의 `Text`에는 `maxLines: 1`과 `overflow: TextOverflow.ellipsis`를 주고 `Tooltip`에는 전체 경로 또는 전체 브랜치 이름을 넣는다. 메뉴 항목은 전달받은 `localBranches`만 순회하며 선택한 항목에는 `Icons.check`를 표시한다.

```dart
PopupMenuButton<String>(
  key: const Key('base-branch-selector'),
  enabled: branchEnabled,
  initialValue: selectedBranch,
  onSelected: onBranchSelected,
  itemBuilder: (context) => [
    for (final branch in localBranches)
      PopupMenuItem<String>(
        key: Key('base-branch-menu-$branch'),
        value: branch,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: branch == selectedBranch
                  ? const Icon(Icons.check, size: 16)
                  : null,
            ),
            Flexible(
              child: Text(
                branch,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
  ],
  child: _SelectorField(
    caption: '기준 브랜치',
    value: branchLabel,
    tooltip: selectedBranch ?? branchLabel,
    maxWidth: 160,
  ),
)
```

저장소 `InkWell`에는 기존 테스트와 호출부가 쓰는 `Key('pick-repository')`를 유지한다. 값 영역은 다음 전용 위젯으로 만들어 두 선택기에서 함께 쓴다.

```dart
class _SelectorField extends StatelessWidget {
  const _SelectorField({
    required this.caption,
    required this.value,
    required this.tooltip,
    required this.maxWidth,
  });

  final String caption;
  final String value;
  final String tooltip;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Tooltip(
            message: tooltip,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 4: 선택기 위젯 테스트 통과 확인**

Run: `flutter test test/repository_branch_selector_test.dart`

Expected: PASS.

- [ ] **Step 5: 선택기 위젯 커밋**

```bash
git add lib/repository_branch_selector.dart test/repository_branch_selector_test.dart
git commit -m "feat: add repository base branch selector"
```

---

### Task 7: 타임라인 refs 상태와 그래프 다시 계산

**Files:**
- Modify: `lib/timeline.dart:302-485,581-630,1008-1078`
- Modify: `test/app_test.dart:6060-6250,7100-7350,8588-8660`

**Interfaces:**
- Consumes: `TimelineScreen.preferredBranch`, `RepositoryBranchSelector`, `resolveBaseBranch`, `layoutGraph(..., preferredTip:)`
- Produces: `TimelineScreen.onPreferredBranchChanged`

```dart
final String? preferredBranch;
final ValueChanged<String>? onPreferredBranchChanged;
```

- [ ] **Step 1: fake 저장소가 refs 성공과 실패를 모두 만들 수 있게 확장**

`FakeGitRepository` 생성자에 다음 선택 인자를 추가한다.

```dart
Future<RepoRefs> Function()? refsLoader,
```

필드와 재정의는 다음처럼 바꾼다.

```dart
final Future<RepoRefs> Function()? refsLoader;

@override
Future<RepoRefs> loadRefs() =>
    refsLoader?.call() ?? Future<RepoRefs>.value(refs);
```

- [ ] **Step 2: 초기 선택, fallback, 실패 상태 테스트 작성**

```dart
testWidgets('restores a valid base branch and falls back to current', (
  tester,
) async {
  final changes = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: TimelineScreen(
        repository: FakeGitRepository(
          (_, _) async => [
            commit('feature-tip', 'feature'),
            commit('main-tip', 'main'),
          ],
          refs: const RepoRefs(
            local: ['main', 'feature'],
            current: 'main',
            tips: {'main': 'main-tip', 'feature': 'feature-tip'},
          ),
        ),
        preferredBranch: 'deleted',
        onPreferredBranchChanged: changes.add,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('main'), findsWidgets);
  expect(changes, ['main']);
});
```

refs 실패 저장소로 `불러오기 실패`가 보이는지, 타임라인 커밋은 계속 보이는지 검증한다.

```dart
refsLoader: () => Future<RepoRefs>.error(StateError('refs failed')),
```

- [ ] **Step 3: 설정이 늦게 도착해도 저장 브랜치를 적용하는 테스트 작성**

`TimelineScreen`을 감싼 `StatefulBuilder`에서 `preferredBranch`를 처음에는 `null`로 주고 refs를 읽은 뒤 `feature`로 바꾼다.

```dart
final repository = FakeGitRepository(
  (_, _) async => [
    commit('feature-tip', 'feature'),
    commit('main-tip', 'main'),
  ],
  refs: const RepoRefs(
    local: ['main', 'feature'],
    current: 'main',
    tips: {'main': 'main-tip', 'feature': 'feature-tip'},
  ),
);
String? preferredBranch;
late StateSetter updateHarness;
await tester.pumpWidget(
  MaterialApp(
    home: StatefulBuilder(
      builder: (context, setState) {
        updateHarness = setState;
        return TimelineScreen(
          repository: repository,
          preferredBranch: preferredBranch,
        );
      },
    ),
  ),
);
await tester.pumpAndSettle();
await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
expect(find.byKey(const Key('selected-row-1')), findsOneWidget);
final before = tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;
updateHarness(() => preferredBranch = 'feature');
await tester.pump();
expect(find.byKey(const Key('selected-row-1')), findsOneWidget);
expect(
  tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels,
  before,
);
expect(find.text('feature'), findsWidgets);
```

- [ ] **Step 4: 새 타임라인 테스트가 실패하는지 확인**

Run: `flutter test test/app_test.dart --plain-name "base branch"`

Expected: FAIL because `TimelineScreen` has no base branch inputs or selector state.

- [ ] **Step 5: refs 상태와 실제 기준 브랜치 상태 구현**

`TimelineScreen` 생성자와 필드에 `preferredBranch`, `onPreferredBranchChanged`를 추가한다. 상태에는 다음 값을 둔다.

```dart
var _refs = const RepoRefs();
var _refsLoading = true;
var _refsLoadFailed = false;
var _refsLoaded = false;
String? _baseBranch;

String? get _preferredTip =>
    _baseBranch == null ? null : _refs.tips[_baseBranch!];
```

refs 읽기 성공과 실패를 분리한다.

```dart
Future<void> _loadRefs() async {
  try {
    final refs = await widget.repository.loadRefs();
    if (!mounted) return;
    final branch = resolveBaseBranch(refs, widget.preferredBranch);
    setState(() {
      _refs = refs;
      _refsLoading = false;
      _refsLoadFailed = false;
      _refsLoaded = true;
      _baseBranch = branch;
      _rebuildGraph();
    });
    if (branch != null && branch != widget.preferredBranch) {
      widget.onPreferredBranchChanged?.call(branch);
    }
  } catch (_) {
    if (!mounted) return;
    setState(() {
      _refsLoading = false;
      _refsLoadFailed = true;
      _refsLoaded = false;
    });
  }
}
```

그래프 다시 계산을 한 함수로 모은다.

```dart
void _rebuildGraph() {
  _rows = layoutGraph(_commits, preferredTip: _preferredTip);
  _entries = timelineEntries(_rows, DateTime.now());
  AvatarService.branchAssignments = assignBranchColors(
    _rows,
    widget.repository.root.hashCode,
  );
}
```

`_fetchNextPage`의 세 줄짜리 그래프·엔트리·색상 갱신은 `_rebuildGraph()` 호출로 바꾼다.

- [ ] **Step 6: 사용자 선택과 늦게 들어온 설정값 처리**

선택 콜백은 로그를 다시 읽지 않고 현재 목록만 다시 배치한다.

```dart
void _selectBaseBranch(String branch) {
  if (!_refs.local.contains(branch) || branch == _baseBranch) return;
  setState(() {
    _baseBranch = branch;
    _rebuildGraph();
  });
  widget.onPreferredBranchChanged?.call(branch);
  _focusNode.requestFocus();
}
```

`didUpdateWidget`에는 refs를 이미 읽은 뒤 `preferredBranch`가 바뀌는 경우를 추가한다.

```dart
if (_refsLoaded && widget.preferredBranch != oldWidget.preferredBranch) {
  final branch = resolveBaseBranch(_refs, widget.preferredBranch);
  if (branch != _baseBranch) {
    setState(() {
      _baseBranch = branch;
      _rebuildGraph();
    });
  }
  if (branch != null && branch != widget.preferredBranch) {
    widget.onPreferredBranchChanged?.call(branch);
  }
}
```

- [ ] **Step 7: 툴바에 선택기 연결**

`_toolbarLeft`의 기존 폴더 아이콘과 저장소 이름을 `RepositoryBranchSelector`로 바꾼다.

```dart
RepositoryBranchSelector(
  repositoryName: _repositoryName,
  repositoryPath: widget.repository.root,
  localBranches: _refs.local,
  selectedBranch: _baseBranch,
  refsLoading: _refsLoading,
  refsLoadFailed: _refsLoadFailed,
  onRepositoryPressed: () => unawaited(_pickRepository()),
  onBranchSelected: _selectBaseBranch,
),
```

남은 `Expanded` 영역은 기존 `toolbar-drag` 동작과 wordmark를 유지한다. 너비 960px인 기존 툴바 테스트와 최소 지원 너비 테스트에서 `FlutterError`가 발생하지 않고 오른쪽 도구 모음이 창 안에 남는지 확인한다.

- [ ] **Step 8: 타임라인 기준 브랜치 테스트와 전체 앱 테스트 통과 확인**

Run: `flutter test test/app_test.dart --plain-name "base branch"`

Expected: PASS.

Run: `flutter test test/app_test.dart`

Expected: PASS.

- [ ] **Step 9: 타임라인 기준 브랜치 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "feat: apply base branch to timeline"
```

---

### Task 8: 앱 설정 연결과 저장소별 값 보존

**Files:**
- Modify: `lib/main.dart:191-324`
- Modify: `test/app_test.dart:2270-2350,5100-5205`

**Interfaces:**
- Consumes: `AppSettings.baseBranches`, `TimelineScreen.preferredBranch`, `TimelineScreen.onPreferredBranchChanged`
- Produces: 저장소별 기준 브랜치 자동 저장

- [ ] **Step 1: 앱이 현재 저장소 값만 읽고 다른 저장소 값을 지우지 않는 테스트 작성**

```dart
testWidgets('YogitApp persists base branches independently by repository', (
  tester,
) async {
  final store = MemorySettingsStore()
    ..current = const AppSettings(
      baseBranches: {
        '/repos/one': 'release',
        '/repos/two': 'main',
      },
    );
  await tester.pumpWidget(
    YogitApp(
      repository: FakeGitRepository(
        (_, _) async => [commit('tip', 'tip')],
        root: '/repos/one',
        refs: const RepoRefs(
          local: ['main', 'release'],
          current: 'main',
          tips: {'main': 'tip', 'release': 'tip'},
        ),
      ),
      settingsStore: store,
      discoverAvatars: false,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('base-branch-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('base-branch-menu-main')));
  await tester.pumpAndSettle();
  expect(store.current.baseBranches, {
    '/repos/one': 'main',
    '/repos/two': 'main',
  });
});
```

설정 저장소가 실패하는 경우에도 메뉴의 현재 값이 바뀐 채 유지되는지 검증한다.

```dart
testWidgets('a failed settings write keeps the selected base branch', (
  tester,
) async {
  final store = FailingSettingsStore()
    ..current = const AppSettings(
      baseBranches: {'/repos/one': 'main'},
    );
  await tester.pumpWidget(
    YogitApp(
      repository: FakeGitRepository(
        (_, _) async => [commit('tip', 'tip')],
        root: '/repos/one',
        refs: const RepoRefs(
          local: ['main', 'release'],
          current: 'main',
          tips: {'main': 'tip', 'release': 'tip'},
        ),
      ),
      settingsStore: store,
      discoverAvatars: false,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('base-branch-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('base-branch-menu-release')));
  await tester.pumpAndSettle();
  expect(find.text('release'), findsWidgets);
  expect(find.byType(TimelineScreen), findsOneWidget);
});
```

- [ ] **Step 2: 앱 설정 연결 테스트가 실패하는지 확인**

Run: `flutter test test/app_test.dart --plain-name "persists base branches independently"`

Expected: FAIL because `YogitApp` does not pass or save the base branch.

- [ ] **Step 3: 현재 저장소의 값을 타임라인에 전달하고 변경된 한 항목만 저장**

`TimelineScreen` 생성부에 다음 인자를 추가한다.

```dart
preferredBranch:
    _settingsLoaded ? _settings.baseBranches[_repository.root] : null,
onPreferredBranchChanged: _settingsLoaded
    ? (branch) {
        final baseBranches = Map<String, String>.of(_settings.baseBranches)
          ..[_repository.root] = branch;
        _changeSettings(_settings.copyWith(baseBranches: baseBranches));
      }
    : null,
```

설정을 읽기 전에는 콜백을 넘기지 않는다. 설정을 읽고 위젯이 다시 만들어지면 Task 7의 `didUpdateWidget`이 저장된 브랜치를 적용한다. 저장소를 바꾸면 기존 `Key('timeline-screen-${_repository.root}')`가 새 상태를 만들고 새 절대 경로로 값을 찾는다.

- [ ] **Step 4: 앱 설정 연결과 전체 앱 테스트 통과 확인**

Run: `flutter test test/app_test.dart --plain-name "base branch"`

Expected: PASS.

Run: `flutter test test/app_test.dart`

Expected: PASS.

- [ ] **Step 5: 앱 설정 연결 커밋**

```bash
git add lib/main.dart test/app_test.dart
git commit -m "feat: save selected base branch"
```

---

### Task 9: 전체 검증과 문서 정리

**Files:**
- Modify if needed: files changed in Tasks 1-8
- Verify: `docs/superpowers/specs/2026-07-28-vim-navigation-base-branch-design.md`

**Interfaces:**
- Consumes: 모든 앞선 작업의 공개 인터페이스
- Produces: 분석과 macOS 디버그 빌드를 통과하는 최종 기능

- [ ] **Step 1: Dart 형식 정리**

Run:

```bash
dart format lib test
```

Expected: command exits 0.

- [ ] **Step 2: 전체 테스트 실행**

Run:

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 3: 정적 분석 실행**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: macOS 개발 빌드 확인**

Run:

```bash
flutter build macos --debug
```

Expected: command exits 0 and reports the built `.app` path.

- [ ] **Step 5: 변경 범위와 사용자 작업 보존 확인**

Run:

```bash
git status --short
git diff --check
git log --oneline --decorate main..HEAD
```

Expected: `git diff --check` exits 0, only this feature's intended files are changed, and the feature commits are listed above `main`.

- [ ] **Step 6: 형식 정리에서 생긴 변경이 있으면 커밋**

```bash
git add lib test docs/superpowers/specs/2026-07-28-vim-navigation-base-branch-design.md
git diff --cached --quiet || git commit -m "chore: finalize vim navigation and base branch"
```

- [ ] **Step 7: 완료 전 검증 절차로 결과를 다시 확인한 뒤 `main`에 병합**

`superpowers:verification-before-completion`을 적용해 Step 2-5의 최신 출력을 확인한다. 이어서 `superpowers:finishing-a-development-branch`를 적용한다. 사용자가 요청한 대로 기본 작업 트리의 사용자 변경을 그대로 둔 채 `codex/vim-navigation-base-branch`를 `main`에 병합하고 충돌이 있으면 중단해 충돌 파일을 보고한다.
