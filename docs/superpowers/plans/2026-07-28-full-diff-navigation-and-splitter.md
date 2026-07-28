# Full Diff 탐색과 Side-by-side 분할선 개선 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full Diff의 History 선택 상태를 보존하고 헤더의 선택 관계를 분명하게 표현하며 파일·이력 목록의 키보드 탐색과 Side-by-side 폭 조절을 안정적으로 구현한다.

**Architecture:** `FullDiffSessionState`는 현재 표시 화면과 마지막 History 선택 상태를 따로 보관한다. 헤더는 주 화면 선택과 Diff 보조 옵션을 분리하고 `DiffScreen`은 목록 포커스와 분할 비율을 화면 세션 동안 관리한 뒤 기존 설정 저장 경로로 내보낸다. Side-by-side 행은 모두 같은 분할 비율을 받아 그리며 분할선은 마우스와 트랙패드 드래그만 처리한다.

**Tech Stack:** Flutter/Dart, macOS 키보드 입력, Flutter widget tests, Flutter visual QA tests

## Global Constraints

- 작업은 `/Users/doortts/repos/yogit/.worktrees/full-diff-interaction-persistence`에서 진행한다.
- 새 패키지를 추가하지 않는다.
- 모든 동작 변경은 실패하는 테스트를 먼저 확인한 뒤 구현한다.
- Diff와 Blame은 간격 없이 붙은 단일 선택 묶음이며 항상 하나만 선택한다.
- Unified와 Side-by-side도 간격 없이 붙은 단일 선택 묶음이며 항상 하나만 선택한다.
- Unified, Side-by-side, Hunk, History는 Diff를 선택한 동안에만 표시한다.
- Blame을 선택해도 마지막 History 선택 상태는 지우지 않는다.
- Diff를 다시 선택하면 마지막 History 선택 상태를 복원한다.
- `⌘1`은 Diff와 마지막 History 상태를 복원하고 `⌘2`는 History 상태를 보존한 채 Blame을 연다.
- `⌘3`은 History 상태를 바꾸고 Diff 화면으로 전환한다.
- 파일·이력 목록을 탐색하다 헤더 버튼을 눌러도 가능한 목록으로 포커스를 돌려보낸다.
- Side-by-side 분할 비율은 20~80%로 제한하고 기본값은 50%로 둔다.
- Side-by-side 분할선은 키보드 포커스를 받지 않으며 화살표 키로 조절하지 않는다.
- Command 키를 누를 때 나타나는 단축키 안내 글자는 11픽셀이다.
- 사용자에게 보이는 새 한국어 문구는 `~/.codex/prompts/korean-naturalness.md`를 읽고 교정한다.

---

### Task 1: History 선택 상태와 설정 호환성

**Files:**
- Modify: `lib/full_diff_model.dart:80-160`
- Modify: `lib/full_diff_controller.dart:50-230`
- Modify: `lib/full_diff_controller.dart:290-370`
- Modify: `lib/full_diff_controller.dart:562-570`
- Test: `test/app_test.dart:2550-2665`
- Test: `test/full_diff_controller_test.dart:1500-1550`

**Interfaces:**
- Consumes: `FullDiffView`, `FullDiffPreferences`, `FullDiffSessionState.preferences`
- Produces:
  - `FullDiffPreferences.historySelected`
  - `FullDiffSessionState.historySelected`
  - `FullDiffSessionState.primaryView`
  - `FullDiffSessionController.setPrimaryView(FullDiffView view)`
  - `FullDiffSessionController.setHistorySelected(bool selected)`

- [ ] **Step 1: 설정 왕복과 기존 설정 이전 테스트를 작성한다**

`test/app_test.dart`의 Full Diff 설정 테스트에 History 선택값을 추가한다.

```dart
test('full diff preferences preserve History behind Blame', () {
  const preferences = FullDiffPreferences(
    view: FullDiffView.blame,
    historySelected: true,
    layout: DiffLayout.sideBySide,
  );

  final json = preferences.toJson();
  final restored = FullDiffPreferences.fromJson(json);

  expect(restored, preferences);
  expect(json['view'], 'blame');
  expect(json['historySelected'], isTrue);
});

test('legacy History view migrates to selected History', () {
  final restored = FullDiffPreferences.fromJson({
    'view': 'history',
    'layout': 'unified',
  });

  expect(restored.view, FullDiffView.history);
  expect(restored.historySelected, isTrue);
});

test('legacy Diff and Blame views migrate with History off', () {
  expect(
    FullDiffPreferences.fromJson({'view': 'diff'}).historySelected,
    isFalse,
  );
  expect(
    FullDiffPreferences.fromJson({'view': 'blame'}).historySelected,
    isFalse,
  );
});
```

기존 `full diff preferences survive settings JSON`의 리터럴 기대값에는 다음 항목을 추가한다.

```dart
'historySelected': true,
```

- [ ] **Step 2: 설정 테스트가 새 필드 부재로 실패하는지 확인한다**

Run:

```bash
flutter test test/app_test.dart --plain-name "full diff preferences preserve History behind Blame"
flutter test test/app_test.dart --plain-name "legacy History view migrates to selected History"
flutter test test/app_test.dart --plain-name "legacy Diff and Blame views migrate with History off"
```

Expected: `historySelected` 생성자 인수와 getter가 없어서 FAIL

- [ ] **Step 3: 컨트롤러의 Diff·Blame·History 전환 테스트를 작성한다**

`test/full_diff_controller_test.dart`에 현재 화면과 기억한 History 상태를 따로 검증한다.

```dart
test('Diff restores the History selection kept behind Blame', () async {
  final repository = FakeFullDiffRepository()
    ..files = ((_, _) async => const [fileA])
    ..diff = ((_, _, _, _, _) async => twoHunkLines)
    ..content = ((_, _, _) async => resultFile.bytes)
    ..history = ((_, _) async => const []);
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
    initialPreferences: const FullDiffPreferences(
      view: FullDiffView.blame,
      historySelected: true,
    ),
  );
  addTearDown(controller.dispose);
  await controller.initialize();

  expect(controller.state.view, FullDiffView.blame);
  expect(controller.state.primaryView, FullDiffView.blame);
  expect(controller.state.historySelected, isTrue);

  controller.setPrimaryView(FullDiffView.diff);

  expect(controller.state.view, FullDiffView.history);
  expect(controller.state.primaryView, FullDiffView.diff);
});

test('Diff stays in regular diff when remembered History is off', () async {
  final repository = FakeFullDiffRepository()
    ..files = ((_, _) async => const [fileA])
    ..diff = ((_, _, _, _, _) async => twoHunkLines)
    ..content = ((_, _, _) async => resultFile.bytes);
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
  );
  addTearDown(controller.dispose);
  await controller.initialize();

  controller.setPrimaryView(FullDiffView.blame);
  controller.setPrimaryView(FullDiffView.diff);

  expect(controller.state.view, FullDiffView.diff);
  expect(controller.state.historySelected, isFalse);
});

test('History selection persists while Blame is active', () async {
  final repository = FakeFullDiffRepository()
    ..files = ((_, _) async => const [fileA])
    ..diff = ((_, _, _, _, _) async => twoHunkLines)
    ..content = ((_, _, _) async => resultFile.bytes)
    ..history = ((_, _) async => const []);
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
  );
  addTearDown(controller.dispose);
  await controller.initialize();

  controller.setHistorySelected(true);
  controller.setPrimaryView(FullDiffView.blame);

  expect(controller.state.view, FullDiffView.blame);
  expect(controller.state.historySelected, isTrue);
  expect(controller.state.preferences.historySelected, isTrue);

  controller.setHistorySelected(false);
  expect(controller.state.view, FullDiffView.diff);
  expect(controller.state.historySelected, isFalse);
});
```

- [ ] **Step 4: 컨트롤러 테스트가 새 전환 API 부재로 실패하는지 확인한다**

Run:

```bash
flutter test test/full_diff_controller_test.dart --plain-name "Diff restores the History selection kept behind Blame"
flutter test test/full_diff_controller_test.dart --plain-name "Diff stays in regular diff when remembered History is off"
flutter test test/full_diff_controller_test.dart --plain-name "History selection persists while Blame is active"
```

Expected: `setPrimaryView`, `setHistorySelected`, `historySelected`, `primaryView`가 없어서 FAIL

- [ ] **Step 5: 설정 모델에 History 선택값을 추가한다**

`lib/full_diff_model.dart`의 `FullDiffPreferences`에 다음 필드와 이전 규칙을 넣는다.

```dart
const FullDiffPreferences({
  this.view = FullDiffView.diff,
  bool? historySelected,
  this.layout = DiffLayout.unified,
  this.scope = DiffScope.hunks,
  this.algorithm = DiffAlgorithm.gitSetting,
  this.ignoreWhitespace = false,
  this.wrapLines = true,
}) : historySelected =
         historySelected ?? view == FullDiffView.history;

final bool historySelected;
```

`copyWith`는 꺼진 값을 잃지 않도록 nullable 인수를 받은 뒤 현재 필드와 합친다.

```dart
FullDiffPreferences copyWith({
  FullDiffView? view,
  bool? historySelected,
  DiffLayout? layout,
  DiffScope? scope,
  DiffAlgorithm? algorithm,
  bool? ignoreWhitespace,
  bool? wrapLines,
}) => FullDiffPreferences(
  view: view ?? this.view,
  historySelected: historySelected ?? this.historySelected,
  layout: layout ?? this.layout,
  scope: scope ?? this.scope,
  algorithm: algorithm ?? this.algorithm,
  ignoreWhitespace: ignoreWhitespace ?? this.ignoreWhitespace,
  wrapLines: wrapLines ?? this.wrapLines,
);
```

`toJson`, 동등성, `hashCode`에도 필드를 연결한다. `fromJson`은 화면값을 먼저 읽고 기존 파일을 다음처럼 보정한다.

```dart
final view = switch (json['view']) {
  'blame' => FullDiffView.blame,
  'history' => FullDiffView.history,
  _ => FullDiffView.diff,
};
final historySelected = view == FullDiffView.history ||
    (json['historySelected'] is bool
        ? json['historySelected'] as bool
        : false);
```

저장 결과에는 다음 항목을 포함한다.

```dart
'historySelected': historySelected,
```

- [ ] **Step 6: 세션 상태와 전환 API를 구현한다**

`FullDiffSessionState`에 `historySelected`를 필수 필드로 추가하고 `copyWith`와 `preferences`에 연결한다.

```dart
final bool historySelected;

FullDiffView get primaryView =>
    view == FullDiffView.blame ? FullDiffView.blame : FullDiffView.diff;

FullDiffPreferences get preferences => FullDiffPreferences(
  view: view,
  historySelected: historySelected,
  layout: layout,
  scope: appliedScope,
  algorithm: appliedAlgorithm,
  ignoreWhitespace: appliedIgnoreWhitespace,
  wrapLines: wrapLines,
);
```

`FullDiffSessionState` 생성자에는 `required this.historySelected`를 추가한다. `copyWith`에는 `bool? historySelected`를 받고 새 상태를 만들 때 `historySelected ?? this.historySelected`를 전달한다.

초기 상태는 새 설정을 정규화하고 `historySelected: initialPreferences.historySelected`를 전달한다.

```dart
final initialView =
    initialPreferences.view == FullDiffView.diff &&
        initialPreferences.historySelected
    ? FullDiffView.history
    : initialPreferences.view;
```

`FullDiffSessionController`는 실제 화면을 바꾸는 내부 함수를 공유한다.

```dart
void setPrimaryView(FullDiffView view) {
  assert(view != FullDiffView.history);
  final nextView = view == FullDiffView.blame
      ? FullDiffView.blame
      : state.historySelected
      ? FullDiffView.history
      : FullDiffView.diff;
  _setViewState(nextView, state.historySelected);
}

void setHistorySelected(bool selected) {
  _setViewState(
    selected ? FullDiffView.history : FullDiffView.diff,
    selected,
  );
}

void setView(FullDiffView view) {
  switch (view) {
    case FullDiffView.diff:
    case FullDiffView.blame:
      setPrimaryView(view);
    case FullDiffView.history:
      setHistorySelected(true);
  }
}

void _setViewState(FullDiffView view, bool historySelected) {
  if (_disposed ||
      (state.view == view &&
          state.historySelected == historySelected)) {
    return;
  }
  _fullFileScrollGeneration++;
  _replace(
    state.copyWith(
      view: view,
      historySelected: historySelected,
      fullFileScrollTarget: null,
    ),
  );
  if (view == FullDiffView.blame) unawaited(_ensureBlame());
  if (view == FullDiffView.history) unawaited(_ensureHistory());
}
```

- [ ] **Step 7: 상태·설정 테스트와 정적 검사를 통과시킨다**

Run:

```bash
dart format lib/full_diff_model.dart lib/full_diff_controller.dart test/app_test.dart test/full_diff_controller_test.dart
flutter test test/app_test.dart --plain-name "full diff preferences"
flutter test test/app_test.dart --plain-name "legacy History"
flutter test test/full_diff_controller_test.dart --plain-name "History"
flutter analyze lib/full_diff_model.dart lib/full_diff_controller.dart
```

Expected: 대상 테스트 PASS, 분석 오류 없음

- [ ] **Step 8: History 상태 모델을 커밋한다**

```bash
git add lib/full_diff_model.dart lib/full_diff_controller.dart test/app_test.dart test/full_diff_controller_test.dart
git commit -m "feat: preserve full diff history selection"
```

---

### Task 2: 붙어 있는 선택 버튼과 History 배치

**Files:**
- Modify: `lib/full_diff_header.dart:40-190`
- Modify: `lib/full_diff_header.dart:193-465`
- Modify: `lib/full_diff_header.dart:480-730`
- Modify: `lib/full_diff_shortcut_hint.dart:50-75`
- Modify: `lib/diff_screen.dart:930-1010`
- Test: `test/full_diff_header_test.dart:20-540`

**Interfaces:**
- Consumes: `FullDiffSessionState.primaryView`, `historySelected`
- Produces:
  - `GlobalDiffToolbar.historySelected`
  - `GlobalDiffToolbar.onHistoryChanged`
  - 간격 없이 붙는 `FullDiffSegmentedControl<T>`

- [ ] **Step 1: 헤더의 버튼 관계와 표시 조건 테스트를 작성한다**

`test/full_diff_header_test.dart`에서 기존 순서 테스트를 다음 조건으로 바꾼다.

```dart
testWidgets('Diff controls use two exclusive connected groups', (tester) async {
  await pumpHeaders(tester);

  expect(
    find.descendant(
      of: find.byKey(const Key('main-view-controls')),
      matching: find.text('History'),
    ),
    findsNothing,
  );
  final diff = tester.getRect(find.text('Diff'));
  final blame = tester.getRect(find.text('Blame'));
  expect((diff.right - blame.left).abs(), lessThanOrEqualTo(1));

  final unified = tester.getRect(find.text('Unified'));
  final sideBySide = tester.getRect(find.text('Side-by-side'));
  expect((unified.right - sideBySide.left).abs(), lessThanOrEqualTo(1));
});

testWidgets('History follows Hunk and only Diff tools hide in Blame', (
  tester,
) async {
  await pumpHeaders(tester, historySelected: true);

  expect(
    tester.getCenter(find.text('Hunk')).dx,
    lessThan(tester.getCenter(find.text('History')).dx),
  );

  await pumpHeaders(
    tester,
    view: FullDiffView.blame,
    historySelected: true,
  );

  for (final label in ['Unified', 'Side-by-side', 'Hunk', 'History']) {
    expect(find.text(label), findsNothing);
  }
  for (final label in ['diff 알고리즘', 'Histogram', '공백 무시', '줄바꿈']) {
    expect(find.text(label), findsOneWidget);
  }
});

testWidgets('History view selects Diff and its own toggle', (tester) async {
  final semantics = tester.ensureSemantics();
  await pumpHeaders(
    tester,
    view: FullDiffView.history,
    historySelected: true,
  );

  expect(
    find.semantics
        .byLabel('Diff')
        .evaluate()
        .single
        .getSemanticsData()
        .flagsCollection
        .isSelected,
    ui.Tristate.isTrue,
  );
  expect(
    find.semantics
        .byLabel('History')
        .evaluate()
        .single
        .getSemanticsData()
        .flagsCollection
        .isToggled,
    ui.Tristate.isTrue,
  );
  semantics.dispose();
});
```

`pumpHeaders`의 선택 인수에는 `bool? historySelected`를 추가한다. `GlobalDiffToolbar`에는 `historySelected: historySelected ?? view == FullDiffView.history`와 `onHistoryChanged: (_) {}`를 전달한다.

- [ ] **Step 2: 헤더 테스트가 현재 세 버튼과 분리된 배치 때문에 실패하는지 확인한다**

Run:

```bash
flutter test test/full_diff_header_test.dart --plain-name "Diff controls use two exclusive connected groups"
flutter test test/full_diff_header_test.dart --plain-name "History follows Hunk and only Diff tools hide in Blame"
flutter test test/full_diff_header_test.dart --plain-name "History view selects Diff and its own toggle"
```

Expected: History가 첫 번째 줄에 있고 버튼 사이에 6픽셀 간격이 있으며 Blame에서도 Diff 도구가 보여 FAIL

- [ ] **Step 3: 주 화면 묶음을 Diff와 Blame만 표시하도록 바꾼다**

`GlobalFileBar`의 주 화면 묶음은 다음 값만 사용한다.

```dart
FullDiffSegmentedControl<FullDiffView>(
  key: const Key('main-view-controls'),
  groupLabel: '주 화면',
  values: const [FullDiffView.diff, FullDiffView.blame],
  selected: view == FullDiffView.blame
      ? FullDiffView.blame
      : FullDiffView.diff,
  labelFor: _viewLabel,
  onSelected: onViewSelected,
  showShortcutHints: showShortcutHints,
  shortcutLabelFor: (value) => switch (value) {
    FullDiffView.diff => '⌘1',
    FullDiffView.blame => '⌘2',
    FullDiffView.history => null,
  },
)
```

- [ ] **Step 4: History를 Hunk 오른쪽의 독립 토글로 옮긴다**

`GlobalDiffToolbar`에 다음 인수를 추가한다.

```dart
required this.historySelected,
required this.onHistoryChanged,

final bool historySelected;
final ValueChanged<bool> onHistoryChanged;
```

Hunk 다음에 History 토글을 만든다.

```dart
final historyControl = FullDiffShortcutHint(
  visible: showShortcutHints,
  label: '⌘3',
  child: Tooltip(
    message: '파일의 변경 이력을 보여줍니다',
    waitDuration: const Duration(milliseconds: 500),
    child: _HeaderToggle(
      controlKey: const Key('history-toggle'),
      label: 'History',
      value: historySelected,
      icon: Icons.history,
      onChanged: onHistoryChanged,
      semanticsHint: 'History 켜기 또는 끄기, 단축키 Command 3',
    ),
  ),
);
```

Diff 도구 묶음은 다음 조건과 순서로 렌더링한다.

```dart
if (showLeadingControls && view != FullDiffView.blame)
  Wrap(
    spacing: 6,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [layoutHint, hunkControl, historyControl],
  ),
```

- [ ] **Step 5: 공통 선택 묶음의 경계와 모서리를 합친다**

`FullDiffSegmentedControl<T>`는 `Wrap(spacing: 6)` 대신 `Row(mainAxisSize: MainAxisSize.min)`을 사용한다. 각 `_SegmentButton`에 첫 번째와 마지막 여부를 전달한다.

```dart
for (var index = 0; index < values.length; index++)
  _SegmentButton(
    label: labelFor(values[index]),
    selected: values[index] == selected,
    enabled: isEnabled?.call(values[index]) ?? true,
    first: index == 0,
    last: index == values.length - 1,
    onPressed: () => onSelected(values[index]),
  ),
```

`_SegmentButton`은 바깥쪽 모서리만 둥글게 만든다.

```dart
final radius = BorderRadius.horizontal(
  left: first
      ? const Radius.circular(fullDiffControlRadius)
      : Radius.zero,
  right: last
      ? const Radius.circular(fullDiffControlRadius)
      : Radius.zero,
);
```

`DiffScreen`은 새 필수 인수에 현재 상태와 컨트롤러 동작을 연결해 이 Task가 끝났을 때 전체 코드가 컴파일되게 한다.

```dart
view: state.view,
onViewSelected: _controller.setPrimaryView,

view: state.view,
historySelected: state.historySelected,
onHistoryChanged: _controller.setHistorySelected,
```

Task 3에서 이 두 콜백을 포커스 복원 함수로 교체한다.

`_HeaderButton`에 선택 묶음에서 넘긴 `borderRadius`와 `border`를 적용할 수 있는 선택 인수를 추가한다. 인접한 버튼은 앞 버튼의 오른쪽 테두리 하나만 공유해 가운데 테두리가 2픽셀이 되지 않게 한다.

```dart
final side = const BorderSide(color: _fullDiffInputBorder);
final segmentBorder = Border(
  left: first ? side : BorderSide.none,
  top: side,
  right: side,
  bottom: side,
);

_HeaderButton(
  label: label,
  selected: selected,
  enabled: enabled,
  onPressed: onPressed,
  borderRadius: radius,
  border: segmentBorder,
)
```

`_HeaderButton`은 선택 인수가 없을 때 기존 단독 버튼 모양을 그대로 사용한다.

```dart
final effectiveRadius =
    borderRadius ?? BorderRadius.circular(fullDiffControlRadius);
final effectiveBorder =
    border ?? (selected ? null : Border.all(color: _fullDiffInputBorder));
```

- [ ] **Step 6: 단축키 안내 글자를 11픽셀로 바꾼다**

`lib/full_diff_shortcut_hint.dart`의 글자 크기만 바꾼다.

```dart
style: technicalTextStyle.copyWith(
  color: Colors.white,
  fontSize: 11,
  height: 1,
),
```

`test/full_diff_header_test.dart`의 단축키 안내 테스트에는 다음 검증을 추가한다.

```dart
expect(tester.widget<Text>(find.text('⌘1')).style?.fontSize, 11);
expect(tester.widget<Text>(find.text('⌘U')).style?.fontSize, 11);
```

- [ ] **Step 7: 헤더 테스트와 정적 검사를 통과시킨다**

Run:

```bash
dart format lib/full_diff_header.dart lib/full_diff_shortcut_hint.dart lib/diff_screen.dart test/full_diff_header_test.dart
flutter test test/full_diff_header_test.dart
flutter analyze lib/full_diff_header.dart lib/full_diff_shortcut_hint.dart lib/diff_screen.dart
```

Expected: 헤더 테스트 PASS, 분석 오류 없음

- [ ] **Step 8: 헤더 변경을 커밋한다**

```bash
git add lib/full_diff_header.dart lib/full_diff_shortcut_hint.dart lib/diff_screen.dart test/full_diff_header_test.dart
git commit -m "feat: regroup full diff header controls"
```

---

### Task 3: 파일·History 목록 포커스와 화살표 키 이동

**Files:**
- Modify: `lib/diff_screen.dart:120-180`
- Modify: `lib/diff_screen.dart:650-910`
- Modify: `lib/diff_screen.dart:910-1210`
- Modify: `lib/diff_screen.dart:1500-1530`
- Modify: `lib/full_history_view.dart:35-175`
- Test: `test/full_diff_workspace_test.dart:2690-2890`
- Test: `test/full_diff_workspace_test.dart:3160-3270`

**Interfaces:**
- Consumes: `FullDiffSessionController.setPrimaryView`, `setHistorySelected`
- Produces:
  - `_FullDiffNavigationPane.files`
  - `_FullDiffNavigationPane.history`
  - `_restoreNavigationFocus()`

- [ ] **Step 1: 헤더를 누른 뒤에도 목록 탐색이 이어지는 실패 테스트를 작성한다**

`test/full_diff_workspace_test.dart`의 목록 포커스 테스트를 다음 시나리오로 확장한다.

```dart
testWidgets('History arrow navigation survives header actions', (
  tester,
) async {
  const fileB = GitFileChange(
    path: 'src/window.pas',
    status: 'M',
    additions: 1,
    deletions: 1,
  );
  final fixture = await historyWorkspaceFixture(
    files: (_, _) async => const [fileA, fileB],
  );
  addTearDown(fixture.controller.dispose);
  await pumpWorkspace(
    tester,
    controller: fixture.controller,
    size: const Size(1200, 842),
  );

  await tester.tap(
    find.byKey(Key('history-row-${historyEntries.first.commit.sha}')),
  );
  await tester.pumpAndSettle();
  final selectedBefore =
      fixture.controller.state.selectedHistoryEntry!.commit.sha;

  await tester.tap(find.text('Side-by-side'));
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pumpAndSettle();

  expect(
    fixture.controller.state.selectedHistoryEntry!.commit.sha,
    isNot(selectedBefore),
  );

  await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pumpAndSettle();
  expect(
    fixture.controller.state.selectedFile,
    fixture.controller.state.files[1],
  );
});
```

파일 목록의 현재 행을 다시 눌러도 포커스를 가져오는 테스트를 추가한다.

```dart
testWidgets('selected file row can reclaim keyboard focus', (tester) async {
  const fileB = GitFileChange(
    path: 'src/window.pas',
    status: 'M',
    additions: 1,
    deletions: 1,
  );
  final fixture = await historyWorkspaceFixture(
    files: (_, _) async => const [fileA, fileB],
  );
  addTearDown(fixture.controller.dispose);
  fixture.controller.setHistorySelected(false);
  await pumpWorkspace(
    tester,
    controller: fixture.controller,
    size: const Size(1070, 842),
  );

  await tester.tap(
    find.byKey(Key('selected-file-${fixture.controller.state.selectedFile!.path}')),
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pumpAndSettle();

  expect(
    fixture.controller.state.selectedFile,
    fixture.controller.state.files[1],
  );
});
```

- [ ] **Step 2: 포커스 테스트가 현재 버튼·행 동작에서 실패하는지 확인한다**

Run:

```bash
flutter test test/full_diff_workspace_test.dart --plain-name "History arrow navigation survives header actions"
flutter test test/full_diff_workspace_test.dart --plain-name "selected file row can reclaim keyboard focus"
```

Expected: 헤더 버튼 또는 선택된 파일 행이 목록 포커스를 복원하지 않아 FAIL

- [ ] **Step 3: 마지막 탐색 목록을 기억하고 화면 갱신 뒤 복원한다**

`lib/diff_screen.dart`에 탐색 위치를 둔다.

```dart
enum _FullDiffNavigationPane { files, history }

_FullDiffNavigationPane _lastNavigationPane =
    _FullDiffNavigationPane.files;
```

두 `FocusNode`에 listener를 연결해 실제로 포커스를 얻었을 때만 마지막 목록을 갱신한다.

```dart
void _handleFileListFocusChanged() {
  if (_fileListFocus.hasFocus) {
    _lastNavigationPane = _FullDiffNavigationPane.files;
  }
}

void _handleHistoryListFocusChanged() {
  if (_historyListFocus.hasFocus) {
    _lastNavigationPane = _FullDiffNavigationPane.history;
  }
}
```

`initState`에서 두 listener를 등록하고 첫 프레임 뒤 `_restoreNavigationFocus()`를 호출한다. `dispose`에서는 listener를 먼저 제거한 뒤 `FocusNode`를 해제한다.

```dart
_fileListFocus.addListener(_handleFileListFocusChanged);
_historyListFocus.addListener(_handleHistoryListFocusChanged);
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) _restoreNavigationFocus();
});
```

상단 버튼 동작이 끝난 다음 연결된 목록만 선택한다.

```dart
void _restoreNavigationFocus() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || _controller.state.focusMode) return;
    if (_controller.state.view == FullDiffView.history &&
        _lastNavigationPane == _FullDiffNavigationPane.history &&
        _historyListFocus.context != null) {
      _historyListFocus.requestFocus();
      return;
    }
    if (_fileListFocus.context != null) {
      _lastNavigationPane = _FullDiffNavigationPane.files;
      _fileListFocus.requestFocus();
    }
  });
}
```

Blame이나 일반 Diff로 전환해 이력 목록이 사라지면 `_lastNavigationPane`을 `files`로 바꾼 뒤 복원한다.

- [ ] **Step 4: 화면·배치·Hunk·History 콜백을 포커스 복원 함수로 감싼다**

`GlobalFileBar`와 `GlobalDiffToolbar`에 넘기는 콜백은 컨트롤러를 직접 참조하지 않는다.

```dart
void _selectPrimaryView(FullDiffView view) {
  _controller.setPrimaryView(view);
  if (_controller.state.view != FullDiffView.history) {
    _lastNavigationPane = _FullDiffNavigationPane.files;
  }
  _restoreNavigationFocus();
}

void _selectLayout(DiffLayout layout) {
  _controller.setLayout(layout);
  _restoreNavigationFocus();
}

void _selectHistory(bool selected) {
  _controller.setHistorySelected(selected);
  if (!selected) {
    _lastNavigationPane = _FullDiffNavigationPane.files;
  }
  _restoreNavigationFocus();
}
```

`_SelectViewIntent`도 같은 전환 함수를 사용한다. `⌘3`은 현재 History 상태를 반대로 바꾸며 Diff로 이동한다.

```dart
_SelectViewIntent: CallbackAction<_SelectViewIntent>(
  onInvoke: (intent) {
    if (intent.view == FullDiffView.history) {
      _selectHistory(!_controller.state.historySelected);
    } else {
      _selectPrimaryView(intent.view);
    }
    return null;
  },
),
```

Hunk 변경은 비동기 요청을 시작한 직후 `_restoreNavigationFocus()`를 호출한다. 알고리즘 선택기는 자체 메뉴 키보드 이동이 필요하므로 메뉴가 열려 있는 동안 포커스를 빼앗지 않는다.

- [ ] **Step 5: 행을 눌렀을 때 해당 목록이 포커스를 가져오게 한다**

파일 행은 선택 여부와 관계없이 눌릴 수 있게 한다.

```dart
onTap: () {
  _fileListFocus.requestFocus();
  if (!selected) unawaited(_controller.selectFile(file));
},
```

History 행 선택 콜백도 먼저 이력 목록 포커스를 요청한다.

```dart
onSelected: (entry) {
  _historyListFocus.requestFocus();
  unawaited(_controller.selectHistoryEntry(entry));
},
```

`FullHistoryView`의 포인터와 접근성 활성화 경로는 같은 `activate` 함수를 사용한다.

```dart
void activate() {
  _focusNode.requestFocus();
  widget.onSelected(entry);
}
```

- [ ] **Step 6: History에서는 상위 위·아래 단축키가 목록 입력을 가로채지 않게 한다**

루트 `Shortcuts`의 일반 `↑/↓` 등록은 Diff와 Blame에서만 만든다.

```dart
shortcuts: <ShortcutActivator, Intent>{
  const SingleActivator(LogicalKeyboardKey.escape):
      _ReturnToTimelineIntent(),
  const SingleActivator(
    LogicalKeyboardKey.keyF,
    meta: true,
    shift: true,
    includeRepeats: false,
  ): _ToggleFocusModeIntent(),
  const SingleActivator(
    LogicalKeyboardKey.digit1,
    meta: true,
    includeRepeats: false,
  ): _SelectViewIntent(FullDiffView.diff),
  const SingleActivator(
    LogicalKeyboardKey.digit2,
    meta: true,
    includeRepeats: false,
  ): _SelectViewIntent(FullDiffView.blame),
  const SingleActivator(
    LogicalKeyboardKey.digit3,
    meta: true,
    includeRepeats: false,
  ): _SelectViewIntent(FullDiffView.history),
  const SingleActivator(
    LogicalKeyboardKey.keyU,
    meta: true,
    includeRepeats: false,
  ): _ToggleLayoutIntent(),
  const SingleActivator(
    LogicalKeyboardKey.keyH,
    meta: true,
    shift: true,
    includeRepeats: false,
  ): _ToggleScopeIntent(),
  const SingleActivator(
    LogicalKeyboardKey.space,
    meta: true,
    shift: true,
    includeRepeats: false,
  ): _ToggleWhitespaceIntent(),
  const SingleActivator(
    LogicalKeyboardKey.keyL,
    meta: true,
    shift: true,
    includeRepeats: false,
  ): _ToggleWrapIntent(),
  const SingleActivator(
    LogicalKeyboardKey.keyA,
    meta: true,
    shift: true,
    includeRepeats: false,
  ): _OpenAlgorithmChooserIntent(),
  const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
      _StepHunkIntent(-1),
  const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
      _StepHunkIntent(1),
  const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
      _StepFileIntent(-1),
  const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
      _StepFileIntent(1),
  if (state.view != FullDiffView.history)
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        _StepPrimaryFileIntent(-1),
  if (state.view != FullDiffView.history)
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        _StepPrimaryFileIntent(1),
},
```

기존 `shortcuts: const <ShortcutActivator, Intent>{...}`의 `const`는 제거한다. 화면 상태를 읽는 두 조건 외의 단축키 표는 그대로 유지한다.

History에서는 파일 목록의 `_handleFileListKey`와 `FullHistoryView._handleKey`가 일반 화살표를 직접 처리한다. 이 구조를 유지하면 이력 선택을 옮길 때 `FullHistoryView._revealSelection`도 함께 실행되어 화면 밖의 선택 행이 자동으로 보인다.

`←`와 `→`도 기존 목록 `Focus.onKeyEvent`에서 처리한다. 파일 목록의 `→`는 첫 이력을 선택하고 이력 목록으로 이동하며 이력 목록의 `←`는 파일 목록으로 돌아간다.

- [ ] **Step 7: 단축키의 전환 의미와 포커스 복원을 검증한다**

기존 `full diff command shortcuts change only their owned options` 테스트에 다음 흐름을 추가한다.

```dart
fixture.controller.setHistorySelected(true);
await sendChord(tester, LogicalKeyboardKey.digit2, meta: true);
expect(fixture.controller.state.view, FullDiffView.blame);
expect(fixture.controller.state.historySelected, isTrue);

await sendChord(tester, LogicalKeyboardKey.digit1, meta: true);
expect(fixture.controller.state.view, FullDiffView.history);

await sendChord(tester, LogicalKeyboardKey.digit3, meta: true);
expect(fixture.controller.state.view, FullDiffView.diff);
expect(fixture.controller.state.historySelected, isFalse);
```

Blame 상태에서 저장된 설정으로 새 Full Diff를 만들었을 때도 History 선택값이 되살아나는 테스트를 추가한다.

```dart
testWidgets('History preference survives closing Full Diff on Blame', (
  tester,
) async {
  final first = await workspaceFixture();
  addTearDown(first.controller.dispose);
  FullDiffPreferences? saved;
  await pumpWorkspace(
    tester,
    controller: first.controller,
    size: const Size(1070, 842),
    onPreferencesChanged: (value) => saved = value,
  );

  first.controller.setHistorySelected(true);
  first.controller.setPrimaryView(FullDiffView.blame);
  await tester.pump();

  expect(saved?.view, FullDiffView.blame);
  expect(saved?.historySelected, isTrue);

  final second = await distantChangeFixture(saved!);
  addTearDown(second.controller.dispose);
  expect(second.controller.state.view, FullDiffView.blame);

  second.controller.setPrimaryView(FullDiffView.diff);
  expect(second.controller.state.view, FullDiffView.history);
});
```

- [ ] **Step 8: 목록 탐색과 단축키 테스트를 통과시킨다**

Run:

```bash
dart format lib/diff_screen.dart lib/full_history_view.dart test/full_diff_workspace_test.dart
flutter test test/full_diff_workspace_test.dart --plain-name "History arrow navigation"
flutter test test/full_diff_workspace_test.dart --plain-name "selected file row can reclaim keyboard focus"
flutter test test/full_diff_workspace_test.dart --plain-name "full diff command shortcuts"
flutter test test/full_diff_workspace_test.dart --plain-name "History preference survives closing Full Diff on Blame"
flutter analyze lib/diff_screen.dart lib/full_history_view.dart
```

Expected: 대상 테스트 PASS, 분석 오류 없음

- [ ] **Step 9: 키보드 탐색 변경을 커밋한다**

```bash
git add lib/diff_screen.dart lib/full_history_view.dart test/full_diff_workspace_test.dart
git commit -m "fix: retain full diff list navigation focus"
```

---

### Task 4: Side-by-side 분할선과 비율 저장

**Files:**
- Modify: `lib/settings.dart:126-166`
- Modify: `lib/diff_screen.dart:120-180`
- Modify: `lib/diff_screen.dart:1380-1430`
- Modify: `lib/diff_screen.dart:1580-1620`
- Modify: `lib/full_diff_side_by_side_view.dart:12-130`
- Modify: `lib/full_diff_side_by_side_view.dart:484-570`
- Test: `test/app_test.dart:2510-2550`
- Test: `test/full_diff_widgets_test.dart:640-900`
- Test: `test/full_diff_workspace_test.dart:1500-1660`

**Interfaces:**
- Consumes: `FullDiffColumnWidths`, `SideBySidePresentationView`
- Produces:
  - `FullDiffColumnWidths.sideBySideRatio`
  - `SideBySidePresentationView.splitRatio`
  - `SideBySidePresentationView.onSplitRatioChanged`
  - `SideBySidePresentationView.onSplitRatioChangeEnd`

- [ ] **Step 1: 분할 비율의 저장·복원·제한 테스트를 작성한다**

`test/app_test.dart`의 Full Diff 폭 테스트를 확장한다.

```dart
test('side-by-side ratio round-trips and clamps damaged settings', () {
  const widths = FullDiffColumnWidths(
    history: 240,
    files: 330,
    sideBySideRatio: 0.65,
  );
  expect(FullDiffColumnWidths.fromJson(widths.toJson()), widths);

  expect(
    FullDiffColumnWidths.fromJson({'sideBySideRatio': 0.05})
        .sideBySideRatio,
    0.2,
  );
  expect(
    FullDiffColumnWidths.fromJson({'sideBySideRatio': 1.5})
        .sideBySideRatio,
    0.8,
  );
  expect(
    FullDiffColumnWidths.fromJson(const {}).sideBySideRatio,
    0.5,
  );
});
```

- [ ] **Step 2: 분할선의 포인터 동작 테스트를 작성한다**

`test/full_diff_widgets_test.dart`에 두 열의 실제 폭과 드래그 콜백을 검증한다.

```dart
testWidgets('side-by-side divider resizes every row without keyboard focus', (
  tester,
) async {
  var ratio = 0.5;
  var ended = 0;

  Future<void> pump() => tester.pumpWidget(
    qaApp(
      StatefulBuilder(
        builder: (context, setState) => SizedBox(
          width: 800,
          height: 300,
          child: SideBySidePresentationView(
            document: twoHunkDocument,
            activeAnchor: twoHunkDocument.hunks.first.anchor,
            oldPath: 'old.pas',
            newPath: 'new.pas',
            wrapLines: false,
            showOldSide: true,
            highlighter: fakeHighlighter,
            anchorKeys: {
              for (final hunk in twoHunkDocument.hunks)
                hunk.anchor.id: GlobalKey(
                  debugLabel: hunk.anchor.id,
                ),
            },
            splitRatio: ratio,
            onSplitRatioChanged: (value) {
              setState(() => ratio = value);
            },
            onSplitRatioChangeEnd: () => ended++,
          ),
        ),
      ),
    ),
  );

  await pump();
  expect(
    tester.getSize(find.byKey(const Key('side-by-side-divider'))).width,
    1,
  );
  expect(
    tester.getSize(find.byKey(const Key('side-by-side-resizer'))).width,
    8,
  );
  expect(
    find.descendant(
      of: find.byKey(const Key('side-by-side-resizer')),
      matching: find.byType(Focus),
    ),
    findsNothing,
  );

  await tester.drag(
    find.byKey(const Key('side-by-side-resizer')),
    const Offset(80, 0),
  );
  await tester.pump();

  expect(ratio, closeTo(0.6, 0.01));
  expect(ended, 1);
});
```

좁은 화면에서 `showOldSide: false`이면 분할선과 드래그 영역이 모두 사라지는 테스트도 추가한다.

- [ ] **Step 3: 새 설정과 위젯 테스트가 필드·인수 부재로 실패하는지 확인한다**

Run:

```bash
flutter test test/app_test.dart --plain-name "side-by-side ratio round-trips and clamps damaged settings"
flutter test test/full_diff_widgets_test.dart --plain-name "side-by-side divider resizes every row without keyboard focus"
```

Expected: `sideBySideRatio`, `splitRatio`, 분할선 key가 없어서 FAIL

- [ ] **Step 4: 분할 비율을 기존 폭 설정에 저장한다**

`FullDiffColumnWidths`에 비율과 제한값을 추가한다.

```dart
const FullDiffColumnWidths({
  this.history = 280,
  this.files = 290,
  this.sideBySideRatio = 0.5,
});

static const minSideBySideRatio = 0.2;
static const maxSideBySideRatio = 0.8;

final double sideBySideRatio;
```

`fromJson`에서 `0.2`와 `0.8` 사이로 제한하고 `toJson`, 동등성, `hashCode`에 포함한다.

```dart
'sideBySideRatio': sideBySideRatio,
```

기존 `legacy full diff commits width migrates to history width` 테스트의 JSON 기대값에도 기본 비율을 명시한다.

```dart
expect(widths.toJson(), {
  'history': 244.0,
  'files': 318.0,
  'sideBySideRatio': 0.5,
});
```

- [ ] **Step 5: Side-by-side 위젯에 공통 분할 비율을 적용한다**

`SideBySidePresentationView`에 다음 인수를 추가한다.

```dart
this.splitRatio = 0.5,
this.onSplitRatioChanged,
this.onSplitRatioChangeEnd,

final double splitRatio;
final ValueChanged<double>? onSplitRatioChanged;
final VoidCallback? onSplitRatioChangeEnd;
```

`showOldSide`일 때 `LayoutBuilder`와 `Stack`으로 목록 위에 분할선을 둔다. 보이는 선은 1픽셀이고 드래그 영역은 8픽셀이다.

```dart
final ratio = splitRatio.clamp(0.2, 0.8).toDouble();
return LayoutBuilder(
  builder: (context, constraints) {
    final splitX = constraints.maxWidth * ratio;
    return Stack(
      children: [
        Positioned.fill(child: list),
        Positioned(
          key: const Key('side-by-side-divider'),
          left: splitX,
          top: 0,
          bottom: 0,
          width: 1,
          child: const ColoredBox(color: fullDiffDivider),
        ),
        Positioned(
          left: splitX - 4,
          top: 0,
          bottom: 0,
          width: 8,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              key: const Key('side-by-side-resizer'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                onSplitRatioChanged?.call(
                  (ratio + details.delta.dx / constraints.maxWidth)
                      .clamp(0.2, 0.8)
                      .toDouble(),
                );
              },
              onHorizontalDragEnd: (_) =>
                  onSplitRatioChangeEnd?.call(),
              onHorizontalDragCancel: onSplitRatioChangeEnd,
            ),
          ),
        ),
      ],
    );
  },
);
```

`_SideBySideRow`에 `splitRatio`를 전달하고 왼쪽 `Expanded`를 다음 폭으로 바꾼다.

```dart
LayoutBuilder(
  builder: (context, constraints) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: constraints.maxWidth * splitRatio,
        child: oldSide,
      ),
      Expanded(child: newSide),
    ],
  ),
)
```

가운데 선은 상위 `Stack`에서 한 번만 그리므로 행의 `VerticalDivider`는 제거한다.

- [ ] **Step 6: DiffScreen에서 비율을 관리하고 저장한다**

`DiffScreen` 상태에 `_sideBySideRatio`를 추가하고 `widget.columnWidths.sideBySideRatio`로 초기화한다. `didUpdateWidget`에서도 바깥 설정값이 바뀌면 갱신한다.

```dart
void _resizeSideBySide(double ratio) {
  setState(() {
    _sideBySideRatio = ratio.clamp(
      FullDiffColumnWidths.minSideBySideRatio,
      FullDiffColumnWidths.maxSideBySideRatio,
    );
  });
}
```

Side-by-side 위젯에 다음 값을 전달한다.

```dart
splitRatio: _sideBySideRatio,
onSplitRatioChanged: _resizeSideBySide,
onSplitRatioChangeEnd: _saveColumnWidths,
```

기존 저장 함수는 세 값을 모두 보낸다.

```dart
FullDiffColumnWidths(
  history: _historyWidth,
  files: _filesWidth,
  sideBySideRatio: _sideBySideRatio,
)
```

- [ ] **Step 7: 화면 통합 테스트에서 저장과 복원을 검증한다**

`test/full_diff_workspace_test.dart`에 1200픽셀 화면에서 분할선을 10% 옮긴 뒤 `onColumnWidthsChanged`로 받은 값이 다음 `pumpWorkspace`에서 같은 폭을 만드는지 검증한다. 파일 전환과 Unified 왕복 뒤에도 `sideBySideRatio`가 그대로인지 확인한다.

```dart
expect(saved?.sideBySideRatio, closeTo(0.6, 0.01));
expect(
  fixture.controller.state.layout,
  DiffLayout.sideBySide,
);
```

- [ ] **Step 8: 설정·위젯·화면 통합 테스트를 통과시킨다**

Run:

```bash
dart format lib/settings.dart lib/diff_screen.dart lib/full_diff_side_by_side_view.dart test/app_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart
flutter test test/app_test.dart --plain-name "side-by-side ratio"
flutter test test/full_diff_widgets_test.dart --plain-name "side-by-side divider"
flutter test test/full_diff_workspace_test.dart --plain-name "side-by-side divider"
flutter analyze lib/settings.dart lib/diff_screen.dart lib/full_diff_side_by_side_view.dart
```

Expected: 대상 테스트 PASS, 분석 오류 없음

- [ ] **Step 9: Side-by-side 분할선 변경을 커밋한다**

```bash
git add lib/settings.dart lib/diff_screen.dart lib/full_diff_side_by_side_view.dart test/app_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart
git commit -m "feat: resize side-by-side diff panes"
```

---

### Task 5: 시각 검수와 전체 확인

**Files:**
- Modify: `test/full_diff_visual_test.dart`
- Verify: `docs/superpowers/specs/assets/full-diff-qa/`

**Interfaces:**
- Consumes: 완성된 헤더, 포커스, 분할선 동작
- Produces: Diff·History·Blame·Side-by-side 상태별 시각 검수 결과

- [ ] **Step 1: 시각 검수 테스트를 새 헤더 구조에 맞춘다**

`test/full_diff_visual_test.dart`에서 첫 번째 줄의 History 탐색을 `history-toggle`로 바꾸고 다음 상태를 각각 캡처하거나 픽셀 검증한다.

```dart
await tester.tap(find.byKey(const Key('history-toggle')));
await tester.pumpAndSettle();
expect(controller.state.view, FullDiffView.history);

await tester.tap(find.text('Blame'));
await tester.pumpAndSettle();
for (final label in ['Unified', 'Side-by-side', 'Hunk', 'History']) {
  expect(find.text(label), findsNothing);
}

await tester.tap(find.text('Diff'));
await tester.pumpAndSettle();
expect(controller.state.view, FullDiffView.history);
```

Side-by-side 캡처 전에는 `side-by-side-resizer`를 오른쪽으로 드래그해 60:40 배치가 실제 이미지에 반영되는지 확인한다.

- [ ] **Step 2: 영향 범위 테스트를 한 번에 실행한다**

Run:

```bash
flutter test test/app_test.dart test/full_diff_controller_test.dart test/full_diff_header_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart test/full_diff_visual_test.dart
```

Expected: 대상 테스트 전부 PASS

- [ ] **Step 3: 전체 테스트와 정적 검사를 실행한다**

Run:

```bash
flutter test
flutter analyze
```

Expected: 전체 테스트 PASS, 분석 오류 없음

- [ ] **Step 4: macOS 릴리스 빌드를 확인한다**

Run:

```bash
flutter build macos --release
```

Expected: `build/macos/Build/Products/Release/yogit.app` 생성

- [ ] **Step 5: 최종 diff에서 설계 조건을 다시 확인한다**

Run:

```bash
git diff --check
git status --short
```

확인 항목:

- Diff 복귀 시 이전 History 선택 상태가 되살아난다.
- Blame에서는 Unified, Side-by-side, Hunk, History가 보이지 않는다.
- 파일·이력 목록에서 `↑`, `↓`, `←`, `→` 이동이 이어진다.
- 헤더 버튼을 누른 뒤에도 목록 화살표 이동이 동작한다.
- Side-by-side 분할선은 포인터로만 움직이고 20~80% 범위를 지킨다.
- 단축키 안내 글자는 11픽셀이다.

- [ ] **Step 6: 시각 검수와 전체 확인을 커밋한다**

```bash
git add test/full_diff_visual_test.dart docs/superpowers/specs/assets/full-diff-qa
git commit -m "test: verify full diff navigation redesign"
```
