# Full Diff 사용성 보완 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full Diff의 정보 밀도, 뒤로 가기, 알고리즘 설명, 표시 불가 안내와 History 상세 diff를 승인된 설계대로 구현합니다.

**Architecture:** 기존 `FullDiffSessionController`의 파일 목록, patch, 파일 내용 캐시를 그대로 사용합니다. History 상세 선택은 이미 읽은 History 목록과 조회 문맥만 보존한 채 일반 선택 자원으로 해당 커밋의 파일 diff를 읽습니다. 화면은 작은 전용 위젯으로 나누되 기존 `DiffScreen`이 상단 조작부와 콘텐츠 전환을 계속 조정합니다.

**Tech Stack:** Flutter/Dart, Material, Flutter Shortcuts·Actions, 기존 Git 명령 계층, `flutter_test`, 기존 Full Diff 시각 검수 도구

## Global Constraints

- 커밋 제목과 파일명은 11, 보조 정보는 10, 작은 메타 정보는 9로 표시합니다.
- 상단 파일 경로는 11로 표시합니다.
- diff 코드는 10, 줄 번호와 기호는 8, Hunk 제목과 diff 안내는 10으로 표시합니다.
- 기존 행 높이, Hunk 안쪽 여백, 목록 클릭 영역과 diff 21픽셀 줄 높이는 유지합니다.
- 일반 너비의 알고리즘 버튼은 `diff 알고리즘 · <선택값>`, 480픽셀 이하에서는 `<선택값>`만 표시합니다.
- 메뉴나 팝오버가 닫힌 상태의 `Esc`와 왼쪽 위 버튼은 타임라인으로 돌아갑니다.
- History는 왼쪽 목록을 유지하고 오른쪽에 현재 Hunk·Inline·Split 방식의 선택 시점 diff를 표시합니다.
- History 목록은 760픽셀 이상에서 280픽셀, 그보다 좁을 때 전체 너비의 35%를 180~240픽셀로 제한해 사용합니다.
- 새로운 패키지 의존성을 추가하지 않습니다.
- 기존 승인 기준 이미지 13장은 변경하지 않습니다.

---

## 파일 구성

### 새 파일

- `lib/full_diff_unavailable_panel.dart`: 파일 정보와 표시 불가 사유를 한 형식으로 보여줍니다.
- `lib/full_history_workspace.dart`: History 목록과 오른쪽 상세 diff의 반응형 배치를 맡습니다.

### 수정 파일

- `lib/full_diff_model.dart`: 바이트 제한과 줄 제한을 구분해 보관합니다.
- `lib/full_diff_controller.dart`: History 조회 문맥·선택 항목 유지와 재시도 동작을 맡습니다.
- `lib/full_diff_header.dart`: 뒤로 가기 버튼, 선택 알고리즘 이름과 호버 설명을 표시합니다.
- `lib/full_diff_code_row.dart`: 코드와 줄 번호의 글자 크기를 줄입니다.
- `lib/full_diff_hunk_header.dart`: Hunk 제목 글자 크기를 줄입니다.
- `lib/full_history_view.dart`: History 행의 글자 크기와 선택 키를 정리합니다.
- `lib/diff_screen.dart`: 목록 글자 크기, 최상위 뒤로 가기, 표시 불가 패널과 History 작업공간을 연결합니다.
- `test/full_diff_model_test.dart`: 제한 사유 분류를 검증합니다.
- `test/full_diff_controller_test.dart`: History 문맥 유지, 연속 선택과 재시도를 검증합니다.
- `test/full_diff_widgets_test.dart`: diff 글자 크기와 표시 불가 패널을 검증합니다.
- `test/full_diff_header_test.dart`: 뒤로 가기, 알고리즘 이름·설명과 좁은 화면을 검증합니다.
- `test/full_diff_workspace_test.dart`: 목록 글자 크기, `Esc`, History 좌우 배치와 상세 갱신을 검증합니다.
- `test/app_test.dart`: 실제 타임라인 경로에서 버튼과 `Esc`로 돌아가는지 검증합니다.
- `test/support/full_diff_qa_harness.dart`: 표시 불가와 History 상세 검수 상태를 만듭니다.
- `test/full_diff_visual_test.dart`: 새 검수 이미지 다섯 장을 캡처합니다.
- `docs/superpowers/verification/full-diff-qa/README.md`: 새 시각 검수 결과를 기록합니다.
- `docs/superpowers/verification/full-diff-qa/followup-review.md`: 구현 전체의 독립 검토 결과를 기록합니다.

---

### Task 1: 목록과 diff 글자 크기

**Files:**
- Modify: `lib/full_diff_code_row.dart`
- Modify: `lib/full_diff_hunk_header.dart`
- Modify: `lib/full_diff_header.dart`
- Modify: `lib/full_history_view.dart`
- Modify: `lib/diff_screen.dart`
- Test: `test/full_diff_widgets_test.dart`
- Test: `test/full_diff_header_test.dart`
- Test: `test/full_diff_workspace_test.dart`

**Interfaces:**
- Consumes: 기존 `FullDiffCodeRow`, `FullDiffHunkHeader`, `GlobalFileBar`, `FullHistoryView`, `DiffScreen`
- Produces: 설계에 고정된 글자 크기. 새 공개 형식이나 상태는 만들지 않습니다.

- [ ] **Step 1: diff 코드와 Hunk 제목의 실패 테스트를 작성합니다**

`test/full_diff_widgets_test.dart`의 코드 행 테스트에 다음 검사를
추가합니다.

```dart
final richText = tester.widget<RichText>(
  find.byKey(const Key('code-row-source-text')),
);
expect((richText.text as TextSpan).style?.fontSize, 10);
expect((richText.text as TextSpan).style?.height, 21 / 10);
expect(tester.widget<Text>(find.text('314')).style?.fontSize, 8);
expect(tester.widget<Text>(find.text('+')).style?.fontSize, 8);
```

같은 파일에 Hunk 제목을 단독으로 띄우고 `fontSize == 10`을 검사하는
테스트를 추가합니다.

- [ ] **Step 2: 목록과 파일 경로의 실패 테스트를 작성합니다**

`test/full_diff_header_test.dart`의 파일 경로 검사를 `14`가 아니라
`11`로 기대하게 바꿉니다.

`test/full_diff_workspace_test.dart`에 다음 항목을 검사하는 테스트를
추가합니다.

```dart
expect(tester.widget<Text>(find.text(commitA.subject)).style?.fontSize, 11);
expect(
  tester
      .widget<Text>(find.textContaining(commitA.shortSha).first)
      .style
      ?.fontSize,
  10,
);
final fileList = find.byKey(const Key('changed-files-list'));
expect(
  tester
      .widget<Text>(
        find.descendant(of: fileList, matching: find.text(fileA.path)),
      )
      .style
      ?.fontSize,
  11,
);
expect(
  tester
      .widget<Text>(
        find.descendant(of: fileList, matching: find.text('+12 −4')),
      )
      .style
      ?.fontSize,
  10,
);
```

History 행은 제목 11, SHA·작성자·상대 시간 10을 각각 검사합니다.

- [ ] **Step 3: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_widgets_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart --reporter expanded
```

Expected: 기존 14·12·11 크기 때문에 새 기대값만 실패합니다.

- [ ] **Step 4: 승인된 정수 글자 크기를 적용합니다**

`lib/full_diff_code_row.dart`:

```dart
const _sourceStyle = TextStyle(
  color: Colors.white,
  fontFamily: technicalFontFamily,
  fontFamilyFallback: technicalFontFallback,
  fontSize: 10,
  height: 21 / 10,
);

const _gutterStyle = TextStyle(
  color: fullDiffMuted,
  fontFamily: technicalFontFamily,
  fontFamilyFallback: technicalFontFallback,
  fontSize: 8,
  height: 21 / 8,
);
```

`lib/full_diff_hunk_header.dart`의 제목은 `fontSize: 10`,
`height: 21 / 10`으로 바꿉니다. `DiffScreen`의 커밋·파일 목록과
`FullHistoryView`, `GlobalFileBar`에는 Global Constraints 표의 값을
그대로 적용합니다. 패딩과 최소 높이는 바꾸지 않습니다.

- [ ] **Step 5: 관련 테스트와 포맷을 확인합니다**

Run:

```bash
dart format lib/full_diff_code_row.dart lib/full_diff_hunk_header.dart lib/full_diff_header.dart lib/full_history_view.dart lib/diff_screen.dart test/full_diff_widgets_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
flutter test test/full_diff_widgets_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart --reporter expanded
```

Expected: 모두 통과

- [ ] **Step 6: 작업을 커밋합니다**

```bash
git add lib/full_diff_code_row.dart lib/full_diff_hunk_header.dart lib/full_diff_header.dart lib/full_history_view.dart lib/diff_screen.dart test/full_diff_widgets_test.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
git commit -m "style: tighten full diff typography"
```

---

### Task 2: 뒤로 가기 버튼과 `Esc`

**Files:**
- Modify: `lib/full_diff_header.dart`
- Modify: `lib/diff_screen.dart`
- Test: `test/full_diff_header_test.dart`
- Test: `test/full_diff_workspace_test.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `Navigator.maybePop`, 기존 `_ReturnToTimelineIntent`
- Produces: `GlobalFileBar.onBack`, `DiffScreen._returnToTimeline()`

- [ ] **Step 1: 상단 뒤로 가기 버튼의 실패 테스트를 작성합니다**

`pumpHeaders()`에 `VoidCallback? onBack`을 추가하고
`GlobalFileBar(onBack: onBack ?? () {})`로 전달합니다.

```dart
testWidgets('file bar leads with an accessible return button', (tester) async {
  var calls = 0;
  await pumpHeaders(tester, onBack: () => calls++);

  expect(find.byKey(const Key('full-diff-back')), findsOneWidget);
  expect(
    find.semantics.byLabel('타임라인으로 돌아가기'),
    findsOneWidget,
  );
  await tester.tap(find.byKey(const Key('full-diff-back')));
  expect(calls, 1);
});
```

- [ ] **Step 2: 실제 경로와 포커스 상태의 실패 테스트를 작성합니다**

`test/app_test.dart`의 타임라인 → Full Diff 통합 테스트에 버튼으로
돌아가는 경우를 추가합니다. 별도 테스트에서는 Full Diff를 다시 열고
코드 행을 클릭해 포커스를 옮긴 뒤 `Esc`를 보냅니다.

```dart
await tester.tap(find.byKey(const Key('preview-full-diff')));
await tester.pumpAndSettle();
await tester.tap(find.byKey(const Key('code-row-source-text')).first);
await tester.sendKeyEvent(LogicalKeyboardKey.escape);
await tester.pumpAndSettle();
expect(find.text('Commit & Diff'), findsOneWidget);
```

`test/full_diff_workspace_test.dart`에는 집중 모드 상태에서도 한 번의
`Esc`가 경로를 닫는 테스트를 추가합니다. 메뉴가 열려 있을 때 첫
`Esc`는 메뉴만 닫고 두 번째 `Esc`가 경로를 닫는 경우도 검사합니다.

- [ ] **Step 3: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_header_test.dart test/full_diff_workspace_test.dart test/app_test.dart --reporter expanded
```

Expected: 뒤로 가기 버튼이 없고 집중 모드에서 첫 `Esc`가 모드만
해제하므로 실패

- [ ] **Step 4: 버튼과 하나의 뒤로 가기 경로를 구현합니다**

`GlobalFileBar`에 다음 필드를 추가합니다.

```dart
final VoidCallback onBack;
```

파일 아이콘 앞에 다음 버튼을 둡니다.

```dart
IconButton(
  key: const Key('full-diff-back'),
  tooltip: '타임라인으로 돌아가기 (Esc)',
  onPressed: onBack,
  icon: const Icon(Icons.arrow_back, size: 18),
  color: fullDiffMuted,
  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
  padding: EdgeInsets.zero,
)
```

`DiffScreen`에서는 기존 `_handleEscape()`를 다음 동작으로 바꾸고 버튼과
Action이 모두 호출하게 합니다.

```dart
void _returnToTimeline() {
  Navigator.of(context).maybePop();
}
```

집중 모드를 먼저 끄는 분기를 제거합니다. `Shortcuts`와 `Actions`는
Full Diff 경로의 최상위 `Focus(autofocus: true)` 안에 유지해 자식의
키 이벤트가 위로 전달되게 합니다. 메뉴 자체가 처리한 `Esc`는
`_ReturnToTimelineIntent`에 도달하지 않아야 합니다.

- [ ] **Step 5: 관련 테스트를 다시 실행합니다**

Run:

```bash
dart format lib/full_diff_header.dart lib/diff_screen.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart test/app_test.dart
flutter test test/full_diff_header_test.dart test/full_diff_workspace_test.dart test/app_test.dart --reporter expanded
```

Expected: 모두 통과

- [ ] **Step 6: 작업을 커밋합니다**

```bash
git add lib/full_diff_header.dart lib/diff_screen.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart test/app_test.dart
git commit -m "fix: restore full diff navigation"
```

---

### Task 3: 현재 알고리즘 이름과 호버 설명

**Files:**
- Modify: `lib/full_diff_header.dart`
- Test: `test/full_diff_header_test.dart`
- Test: `test/full_diff_workspace_test.dart`

**Interfaces:**
- Consumes: `DiffAlgorithm.label`
- Produces: `diffAlgorithmDescription(DiffAlgorithm) -> String`

- [ ] **Step 1: 닫힌 버튼과 좁은 화면의 실패 테스트를 작성합니다**

기존에 닫힌 버튼 이름을 `diff 알고리즘`으로만 기대하는 검사를
다음처럼 바꿉니다.

```dart
expect(find.text('diff 알고리즘 · Histogram'), findsOneWidget);
expect(find.byKey(const Key('diff-algorithm-value')), findsNothing);
```

480픽셀 테스트에서는 다음을 검사합니다.

```dart
tester.view.physicalSize = const Size(480, 560);
expect(find.text('Histogram'), findsOneWidget);
expect(find.textContaining('diff 알고리즘 ·'), findsNothing);
expect(
  find.semantics.byLabel('diff 알고리즘: Histogram'),
  findsOneWidget,
);
```

- [ ] **Step 2: 다섯 설명과 호버 팝오버의 실패 테스트를 작성합니다**

각 `DiffAlgorithm`에 대해 `diffAlgorithmDescription()`이 설계 문서의
문구를 정확히 돌려주는 단위 검사를 추가합니다.

마우스 호버는 다음 방식으로 검사합니다.

```dart
final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
await mouse.addPointer();
await mouse.moveTo(tester.getCenter(find.byKey(const Key('diff-algorithm'))));
await tester.pump(const Duration(milliseconds: 600));
expect(find.text('Diff 알고리즘 · Histogram'), findsOneWidget);
expect(
  find.textContaining('반복이 많은 코드의 변경 경계를 찾습니다'),
  findsOneWidget,
);
```

- [ ] **Step 3: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_header_test.dart test/full_diff_workspace_test.dart --reporter expanded
```

Expected: 버튼이 고정 이름만 표시하고 설명 함수와 팝오버가 없어 실패

- [ ] **Step 4: 설명 함수와 반응형 버튼을 구현합니다**

`lib/full_diff_header.dart`에 다음 함수를 추가합니다.

```dart
String diffAlgorithmDescription(DiffAlgorithm value) => switch (value) {
  DiffAlgorithm.gitSetting =>
    'Git 설정에 지정된 알고리즘을 사용합니다. '
    '설정이 없으면 Git의 기본 동작을 따릅니다.',
  DiffAlgorithm.myers =>
    '일반적인 소스 변경을 빠르게 비교하는 Git의 기본 알고리즘입니다.',
  DiffAlgorithm.minimal =>
    '계산을 더 수행해 가능한 한 작은 변경 결과를 찾습니다. '
    '큰 파일에서는 느릴 수 있습니다.',
  DiffAlgorithm.patience =>
    '고유한 줄을 기준으로 삼아 이동하거나 재구성한 코드의 경계를 '
    '읽기 쉽게 만듭니다.',
  DiffAlgorithm.histogram =>
    '빈도가 낮은 줄을 기준으로 삼아 반복이 많은 코드의 변경 경계를 '
    '찾습니다.',
};
```

`_AlgorithmMenu`의 접근성 이름은
`diff 알고리즘: ${algorithm.label}`로 바꿉니다. 버튼 안 텍스트는
`compact ? algorithm.label : 'diff 알고리즘 · ${algorithm.label}'`을
사용합니다.

기존 Material `Tooltip`의 `richMessage`를 사용해 제목과 설명을 두 줄로
표시합니다. `waitDuration`은 500밀리초로 고정하고 메뉴의 체크 항목과
선택 동작은 바꾸지 않습니다.

- [ ] **Step 5: 테스트와 480픽셀 한 줄 배치를 확인합니다**

Run:

```bash
dart format lib/full_diff_header.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
flutter test test/full_diff_header_test.dart test/full_diff_workspace_test.dart --reporter expanded
```

Expected: 모두 통과하며 480픽셀 도구 모음에 세로 줄바꿈이 생기지 않음

- [ ] **Step 6: 작업을 커밋합니다**

```bash
git add lib/full_diff_header.dart test/full_diff_header_test.dart test/full_diff_workspace_test.dart
git commit -m "feat: explain the selected diff algorithm"
```

---

### Task 4: 파일 정보가 있는 표시 불가 안내

**Files:**
- Create: `lib/full_diff_unavailable_panel.dart`
- Modify: `lib/full_diff_model.dart`
- Modify: `lib/diff_screen.dart`
- Modify: `lib/full_diff_controller.dart`
- Test: `test/full_diff_model_test.dart`
- Test: `test/full_diff_widgets_test.dart`
- Test: `test/full_diff_workspace_test.dart`

**Interfaces:**
- Produces: `enum FileContentLimitReason { byteLimit, lineLimit }`
- Produces: `enum FullDiffUnavailableReason { noChanges, binary, unsupportedEncoding, byteLimit, lineLimit, gitError }`
- Produces: `FullDiffUnavailablePanel`
- Produces: `FullDiffSessionController.retryPatch()`

- [ ] **Step 1: 정확한 제한 사유의 실패 테스트를 작성합니다**

`test/full_diff_model_test.dart`에서 기존 두 제한 입력을 나눠 검사합니다.

```dart
expect(bytesFile.kind, FileContentKind.tooLarge);
expect(bytesFile.limitReason, FileContentLimitReason.byteLimit);
expect(linesFile.kind, FileContentKind.tooLarge);
expect(linesFile.limitReason, FileContentLimitReason.lineLimit);
expect(utf8File.limitReason, isNull);
```

- [ ] **Step 2: 패널의 정보 순서와 문구 실패 테스트를 작성합니다**

`test/full_diff_widgets_test.dart`에 `FullDiffUnavailablePanel`을 직접
띄우는 표 기반 테스트를 추가합니다.

```dart
const scenarios = [
  (
    reason: FullDiffUnavailableReason.binary,
    attribute: 'Binary',
    message: '바이너리 파일이라 텍스트 diff를 표시할 수 없습니다.',
  ),
  (
    reason: FullDiffUnavailableReason.byteLimit,
    attribute: '10 MiB 초과',
    message: '파일이 10 MiB 제한을 초과해 내용을 표시하지 않습니다.',
  ),
];
```

모든 경우 파일 경로, `M · +12 −4`, 속성 칩과 사유를 검사합니다.
`noChanges`에서는 `Git setting`과 `공백 포함`을, `gitError`에서는 오류
세부 정보와 `다시 시도` 버튼을 검사합니다.

- [ ] **Step 3: 실제 화면 연결의 실패 테스트를 작성합니다**

`test/full_diff_workspace_test.dart`에 다음 저장소 상태를 각각 만듭니다.

- 빈 patch + UTF-8 파일 → 현재 옵션에서 변경 없음
- NUL 바이트 → Binary
- 잘못된 UTF-8 → Unsupported encoding
- 바이트 제한 초과
- 줄 제한 초과
- 첫 patch 실패, 재시도 성공

각 테스트는 `Key('full-diff-unavailable')`, 파일명, 속성과 사유를
검사합니다. 재시도 테스트는 `repository.diffRequests`가 2개가 되고
diff 행이 나타나는지 검사합니다.

- [ ] **Step 4: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_model_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart --reporter expanded
```

Expected: 제한 사유와 패널, patch 재시도 API가 없어 실패

- [ ] **Step 5: 모델과 패널을 최소 구현합니다**

`FileDocument`에 기본값이 `null`인 다음 필드를 추가해 기존 직접
생성자를 깨뜨리지 않습니다.

```dart
enum FileContentLimitReason { byteLimit, lineLimit }

final FileContentLimitReason? limitReason;
```

`FileDocument.fromBytes()`는 바이트 제한을 먼저 검사하고 줄 제한을
따로 검사해 해당 값을 넣습니다.

`lib/full_diff_unavailable_panel.dart`의 공개 생성자는 다음 값을
받습니다.

```dart
const FullDiffUnavailablePanel({
  required this.file,
  required this.path,
  required this.reason,
  required this.algorithm,
  required this.ignoreWhitespace,
  this.error,
  this.onRetry,
  super.key,
});
```

패널은 `Key('full-diff-unavailable')`를 사용하고 설계 문서의 순서와
문구를 그대로 출력합니다. 기술 정보에는 `technicalTextStyle`을
사용합니다.

- [ ] **Step 6: 화면 상태와 재시도를 연결합니다**

`FullDiffSessionController`에 다음 메서드를 추가합니다.

```dart
Future<void> retryPatch() => _loadPatch();
```

`DiffScreen._diffContent()`는 다음 우선순위로 상태를 고릅니다.

1. patch 오류이고 성공한 문서가 없음 → `gitError`
2. 파일을 읽는 중 → 기존 로딩
3. `FileContentKind.binary` → `binary`
4. `unsupportedEncoding` → `unsupportedEncoding`
5. `tooLarge`와 `limitReason` → `byteLimit` 또는 `lineLimit`
6. `patch.hunks.isEmpty` → `noChanges`
7. 그 밖의 경우 기존 Hunk·Inline·Split

`DiffScreen._fileContent()`도 UTF-8이 아닌 문서는 `FullFileView`에
넘기지 않고 같은 패널을 반환합니다. 파일 정보와 옵션은 현재
`FullDiffSessionState`에서 전달합니다.

- [ ] **Step 7: 테스트와 포맷을 확인합니다**

Run:

```bash
dart format lib/full_diff_model.dart lib/full_diff_unavailable_panel.dart lib/full_diff_controller.dart lib/diff_screen.dart test/full_diff_model_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart
flutter test test/full_diff_model_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart --reporter expanded
```

Expected: 모두 통과

- [ ] **Step 8: 작업을 커밋합니다**

```bash
git add lib/full_diff_model.dart lib/full_diff_unavailable_panel.dart lib/full_diff_controller.dart lib/diff_screen.dart test/full_diff_model_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart
git commit -m "feat: explain unavailable full diff content"
```

---

### Task 5: History 목록 문맥과 상세 선택 상태

**Files:**
- Modify: `lib/full_diff_controller.dart`
- Test: `test/full_diff_controller_test.dart`

**Interfaces:**
- Produces: `FullDiffSessionState.selectedHistoryEntry`
- Produces: `FullDiffSessionState.historyContext`
- Produces: `FullDiffSessionController.retryHistorySelection()`
- Consumes: 기존 `HistoryCacheKey`, `selectionGeneration`, patch·파일 캐시

- [ ] **Step 1: History 목록 유지의 실패 테스트를 작성합니다**

현재 커밋과 과거 커밋의 파일·patch·내용을 구분해 반환하는
`FakeFullDiffRepository`를 만듭니다.

```dart
controller.setView(FullDiffView.history);
await Future<void>.delayed(Duration.zero);
final originalHistory = controller.state.history.data;

await controller.selectHistoryEntry(historyEntry);

expect(controller.state.history.data, same(originalHistory));
expect(controller.state.selectedHistoryEntry, same(historyEntry));
expect(controller.state.historyContext, (
  startRevision: commitA.sha,
  path: fileA.path,
));
expect(controller.state.patch.data?.rows.last.text, 'historical change');
```

일반 파일 선택을 하면 `history`, `selectedHistoryEntry`,
`historyContext`가 모두 비워지는 경우도 검사합니다.

- [ ] **Step 2: 연속 선택과 오래된 결과 차단의 실패 테스트를 작성합니다**

두 History 항목의 파일 목록과 patch를 각각 `Completer`로 제어합니다.
두 번째 요청을 먼저 끝내고 첫 번째 요청을 나중에 끝낸 뒤 다음을
검사합니다.

```dart
expect(controller.state.selectedHistoryEntry, same(secondEntry));
expect(controller.state.selectedCommit.sha, secondEntry.commit.sha);
expect(controller.state.patch.data?.rows.last.text, 'second');
expect(controller.state.history.data, same(originalHistory));
```

- [ ] **Step 3: 이름 변경과 재시도의 실패 테스트를 작성합니다**

History 항목의 `path`가 현재 파일의 `oldPath`와 일치하는 경우 해당
파일을 선택하는지 검사합니다. 첫 파일 목록 요청이 실패한 뒤
`retryHistorySelection()`을 호출하면 같은 항목을 다시 읽고 성공하는지
검사합니다.

- [ ] **Step 4: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_controller_test.dart --reporter expanded
```

Expected: `selectHistoryEntry()`가 History 자원을 비우며 새 상태 필드와
재시도 메서드가 없어 실패

- [ ] **Step 5: History 문맥 필드를 추가합니다**

`FullDiffSessionState`에 다음 필드를 추가하고 초기값은 `null`로
둡니다.

```dart
final FileHistoryEntry? selectedHistoryEntry;
final HistoryCacheKey? historyContext;
```

`copyWith()`는 `_unset` 표식을 사용해 값 유지와 `null`로 지우기를
구분합니다.

`_ensureHistory()`가 성공하면 다음 문맥과 현재 커밋에 해당하는 항목을
함께 저장합니다.

```dart
final context = (
  startRevision: commit.sha,
  path: file.path,
);
```

- [ ] **Step 6: 일반 선택과 History 상세 선택을 구분합니다**

`_beginSelection()`에 다음 선택 인자를 추가합니다.

```dart
bool preserveHistory = false,
FileHistoryEntry? selectedHistoryEntry,
```

일반 커밋·부모·파일 선택은 기존처럼 History 상태를 비웁니다.
`selectHistoryEntry()`만 `preserveHistory: true`와 선택 항목을
전달합니다. 기존 후보 경로 조건에 중복된
`candidate.oldPath == entry.path` 한 줄은 제거하고 다음 네 조합만
남깁니다.

```dart
candidate.path == entry.path ||
candidate.oldPath == entry.path ||
candidate.path == entry.oldPath ||
candidate.oldPath == entry.oldPath
```

`retryHistorySelection()`은 현재 선택 항목이 있을 때
`selectHistoryEntry()`를 다시 호출합니다.

- [ ] **Step 7: 테스트와 포맷을 확인합니다**

Run:

```bash
dart format lib/full_diff_controller.dart test/full_diff_controller_test.dart
flutter test test/full_diff_controller_test.dart --reporter expanded
```

Expected: 목록이 같은 객체로 유지되고 마지막 선택만 화면에 반영되며
모든 테스트 통과

- [ ] **Step 8: 작업을 커밋합니다**

```bash
git add lib/full_diff_controller.dart test/full_diff_controller_test.dart
git commit -m "feat: preserve history while selecting file revisions"
```

---

### Task 6: History 목록 오른쪽의 상세 diff

**Files:**
- Create: `lib/full_history_workspace.dart`
- Modify: `lib/full_history_view.dart`
- Modify: `lib/diff_screen.dart`
- Test: `test/full_diff_workspace_test.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Produces: `FullHistoryWorkspace`
- Consumes: `FullHistoryView`, `FullDiffSessionState.selectedHistoryEntry`, 기존 `_diffContent()`

- [ ] **Step 1: 반응형 좌우 배치의 실패 테스트를 작성합니다**

`test/full_diff_workspace_test.dart`에서 History를 연 뒤 다음을
검사합니다.

```dart
final listPane = find.byKey(const Key('history-list-pane'));
final detailPane = find.byKey(const Key('history-detail-pane'));
expect(tester.getSize(listPane).width, 280);
expect(tester.getTopLeft(listPane).dx, lessThan(tester.getTopLeft(detailPane).dx));
expect(find.byKey(const Key('history-detail-divider')), findsOneWidget);
```

작업공간 자체를 600픽셀과 480픽셀로 띄워 목록 너비가 각각 210픽셀과
180픽셀인지 검사합니다.

- [ ] **Step 2: 항목 클릭과 `Enter`의 실패 테스트를 작성합니다**

History 항목을 클릭한 뒤 목록이 남고 오른쪽에 과거 patch가
표시되는지 검사합니다.

```dart
await tester.tap(find.byKey(Key('history-row-${historyCommit.sha}')));
await tester.pumpAndSettle();

expect(find.byKey(const Key('history-list')), findsOneWidget);
expect(find.byKey(const Key('history-detail-pane')), findsOneWidget);
expect(find.text('historical change'), findsOneWidget);
```

포커스만 옮겼을 때는 patch가 바뀌지 않고 `Enter`를 누른 뒤에만
바뀌는 경우도 추가합니다.

- [ ] **Step 3: 표시 방식과 오류 유지의 실패 테스트를 작성합니다**

History 상세에서 `Inline`, `Split`을 차례로 선택해 해당 키가 보이는지
검사합니다. History 상세 로딩이 실패한 경우 목록은 남고 오른쪽에
표시 불가 패널과 `다시 시도` 버튼이 나타나는지 검사합니다.

- [ ] **Step 4: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_workspace_test.dart test/app_test.dart --reporter expanded
```

Expected: History가 목록만 전체 너비로 표시하므로 실패

- [ ] **Step 5: History 작업공간 위젯을 구현합니다**

`lib/full_history_workspace.dart`:

```dart
class FullHistoryWorkspace extends StatelessWidget {
  const FullHistoryWorkspace({
    required this.history,
    required this.detail,
    super.key,
  });

  final Widget history;
  final Widget detail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 760
          ? 280.0
          : (constraints.maxWidth * 0.35).clamp(180.0, 240.0);
      return Row(
        children: [
          SizedBox(
            key: const Key('history-list-pane'),
            width: width,
            child: history,
          ),
          const SizedBox(
            key: Key('history-detail-divider'),
            width: 1,
            child: ColoredBox(color: fullDiffDivider),
          ),
          Expanded(
            key: const Key('history-detail-pane'),
            child: detail,
          ),
        ],
      );
    },
  );
}
```

- [ ] **Step 6: 별도 목록 스크롤과 오른쪽 diff를 연결합니다**

`_DiffScreenState`에 `_historyScroll`을 추가하고 `dispose()`에서
정리합니다. 기존 `_contentScroll`은 오른쪽 diff와 페이지 이동
단축키만 담당합니다.

`_historyContent()`는 다음 구조를 반환합니다.

```dart
return FullHistoryWorkspace(
  history: FullHistoryView(
    entries: history,
    selected: state.selectedHistoryEntry,
    onSelected: (entry) =>
        unawaited(_controller.selectHistoryEntry(entry)),
    controller: _historyScroll,
  ),
  detail: _diffContent(state, viewportWidth),
);
```

`_contentFor()`가 History에도 `viewportWidth`를 전달하게 바꿉니다.
History 상세 실패의 `다시 시도`는
`_controller.retryHistorySelection()`을 호출합니다. History에서는
기존 규칙대로 바깥 미니맵을 표시하지 않습니다.

- [ ] **Step 7: 관련 테스트와 전체 Full Diff 테스트를 실행합니다**

Run:

```bash
dart format lib/full_history_workspace.dart lib/full_history_view.dart lib/diff_screen.dart test/full_diff_workspace_test.dart test/app_test.dart
flutter test test/full_diff_workspace_test.dart test/app_test.dart test/full_diff_controller_test.dart --reporter expanded
```

Expected: 모두 통과

- [ ] **Step 8: 작업을 커밋합니다**

```bash
git add lib/full_history_workspace.dart lib/full_history_view.dart lib/diff_screen.dart test/full_diff_workspace_test.dart test/app_test.dart
git commit -m "feat: show file history beside its diff"
```

---

### Task 7: 시각 검수와 전체 검증

**Files:**
- Modify: `test/support/full_diff_qa_harness.dart`
- Modify: `test/full_diff_visual_test.dart`
- Modify: `docs/superpowers/verification/full-diff-qa/README.md`
- Create: `docs/superpowers/specs/assets/full-diff-qa/13-font-and-back.png`
- Create: `docs/superpowers/specs/assets/full-diff-qa/14-algorithm-tooltip.png`
- Create: `docs/superpowers/specs/assets/full-diff-qa/15-unavailable-panel.png`
- Create: `docs/superpowers/specs/assets/full-diff-qa/16-history-detail.png`
- Create: `docs/superpowers/specs/assets/full-diff-qa/17-history-detail-split.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/13-font-and-back.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/14-algorithm-tooltip.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/15-unavailable-panel.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/16-history-detail.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/17-history-detail-split.png`
- Create: `docs/superpowers/verification/full-diff-qa/diff/13-font-and-back.png`
- Create: `docs/superpowers/verification/full-diff-qa/diff/14-algorithm-tooltip.png`
- Create: `docs/superpowers/verification/full-diff-qa/diff/15-unavailable-panel.png`
- Create: `docs/superpowers/verification/full-diff-qa/diff/16-history-detail.png`
- Create: `docs/superpowers/verification/full-diff-qa/diff/17-history-detail-split.png`
- Create: `docs/superpowers/verification/full-diff-qa/followup-review.md`

**Interfaces:**
- Consumes: 기존 `FullDiffQaComparisonCanvas`, `capture()`, `tool/full_diff_visual_diff.dart`
- Produces: 새 상태 다섯 장의 기준·실제·차이 이미지와 검수 기록

- [ ] **Step 1: 검수 상태와 캡처 테스트를 먼저 추가합니다**

QA 저장소가 History 과거 커밋을 선택했을 때 해당 커밋의 파일 목록과
다른 patch를 반환하게 합니다. 표시 불가 상태는 빈 patch와 UTF-8 파일
조합으로 만듭니다.

다음 캡처를 추가합니다.

```dart
const followupCases = [
  '13-font-and-back',
  '15-unavailable-panel',
  '16-history-detail',
  '17-history-detail-split',
];
```

`14-algorithm-tooltip`은 `Histogram` 상태로 화면을 띄운 뒤 마우스를
알고리즘 버튼 위로 옮기고 600밀리초 진행한 다음 `capture()`를
호출합니다.

- [ ] **Step 2: 새 기준 이미지가 없어서 검사가 실패하는지 확인합니다**

Run:

```bash
flutter test test/full_diff_visual_test.dart --reporter expanded
```

Expected: 새 캡처 파일 또는 비교 기준이 없어 새 다섯 경우만 실패

- [ ] **Step 3: 실제 앱 이미지를 만들고 눈으로 검토합니다**

Run:

```bash
flutter test --update-goldens test/full_diff_visual_test.dart --reporter expanded
```

생성된 실제 이미지를 다음 항목에 따라 원본 참고 이미지와 설계 문서에
맞춰 확인합니다.

- 뒤로 가기 버튼이 파일 아이콘보다 왼쪽에 있는지
- 목록 11/10/9와 diff 10/8 글자가 지나치게 붙거나 잘리지 않는지
- 알고리즘 선택값과 설명 팝오버가 한눈에 읽히는지
- 표시 불가 패널의 정보 순서가 파일 경로 → 변경 통계 → 속성 → 사유인지
- History 목록과 오른쪽 diff의 너비, 경계선과 선택 항목이 분명한지
- Split의 두 쪽이 History 상세 너비 안에서 잘리지 않는지

문제가 있으면 제품 코드와 테스트를 고친 뒤 다시 캡처합니다. 검토를
통과한 실제 앱 이미지에 한해 새 기준 이미지로 복사합니다. 기존
00~12 기준 이미지는 건드리지 않습니다.

- [ ] **Step 4: 픽셀 차이 이미지와 README를 갱신합니다**

Run:

```bash
flutter test test/full_diff_visual_test.dart --reporter expanded
dart run tool/full_diff_visual_diff.dart
```

Expected: 00~17 캡처 테스트가 모두 통과하고 새 다섯 차이 이미지가
생성됨

README 표에 13~17 행을 추가하고 각 이미지에서 확인한 결과를
구체적으로 적습니다.

- [ ] **Step 5: 포맷, 정적 분석과 전체 테스트를 실행합니다**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test tool benchmark
flutter analyze
flutter test --reporter compact
flutter test --dart-define=YOGIT_EXTENDED_SYNTAX=false --reporter compact
```

Expected: 포맷 변경 없음, 분석 문제 0개, 두 구성의 전체 테스트 통과

- [ ] **Step 6: macOS 릴리스 빌드와 저장소 상태를 확인합니다**

Run:

```bash
flutter build macos --release --dart-define=YOGIT_EXTENDED_SYNTAX=true
git diff --check
git status --short
```

Expected: 릴리스 빌드 성공, 공백 오류 없음, 계획에 든 파일만 변경

- [ ] **Step 7: 시각 검수 자료와 최종 코드를 커밋합니다**

```bash
git add test/support/full_diff_qa_harness.dart test/full_diff_visual_test.dart docs/superpowers/specs/assets/full-diff-qa docs/superpowers/verification/full-diff-qa
git commit -m "test: verify full diff usability follow-up"
```

- [ ] **Step 8: 구현 전체를 독립적으로 검토합니다**

기준 커밋 `c2219a8`부터 현재 HEAD까지 설계 문서의 모든 완료 기준을
확인합니다. P0~P3 지적 사항, 테스트 결과와 병합 가능 여부를
`docs/superpowers/verification/full-diff-qa/followup-review.md`에
기록합니다. 지적 사항이 있으면 해당 작업의 실패 테스트부터 추가한 뒤
수정하고 전체 검증을 다시 실행합니다.

- [ ] **Step 9: 독립 검토 결과를 커밋합니다**

```bash
git add lib test docs/superpowers/specs/assets/full-diff-qa docs/superpowers/verification/full-diff-qa
git commit -m "chore: close full diff follow-up review"
```
