# Full Diff Shortcut Hint Position Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full Diff 단축키 배지를 버튼 하단에 붙여 다른 아이콘이나 본문과 겹치지 않게 한다.

**Architecture:** 공통 오버레이 컴포넌트인 `FullDiffShortcutHint`에서 배지의 세로 오프셋만 바꾼다. 각 버튼은 같은 배치 규칙을 계속 공유하며, 도구막대 레이아웃과 단축키 동작은 그대로 둔다.

**Tech Stack:** Flutter, Dart, Flutter widget tests, Flutter screenshot QA

## Global Constraints

- 승인된 A안처럼 배지 윗부분이 버튼 하단 테두리에 4픽셀 겹쳐야 한다.
- 배지의 글자 크기, 안쪽 여백, 색상, 테두리와 둥근 모서리는 바꾸지 않는다.
- 버튼 위치와 도구막대 높이는 배지 표시 전후에 같아야 한다.
- 모든 Full Diff 단축키 배지에 같은 위치 규칙을 적용한다.
- 구현이 끝나면 전체 테스트를 통과한 뒤 로컬 `main`에 머지한다.

---

### Task 1: 단축키 배지 위치 회귀 테스트와 공통 위치 수정

**Files:**
- Modify: `test/full_diff_header_test.dart:642-661`
- Modify: `test/full_diff_visual_test.dart:442-468`
- Modify: `lib/full_diff_shortcut_hint.dart:34-82`
- Verify: `docs/superpowers/verification/full-diff-qa/actual/26-shortcut-hints.png`

**Interfaces:**
- Consumes: `FullDiffShortcutHint({required bool visible, required String label, required Widget child, Key? hintKey})`
- Produces: 모든 Full Diff 단축키 배지가 버튼 하단보다 4픽셀 위에서 시작하는 공통 배치 규칙

- [ ] **Step 1: 버튼과 배지의 상대 위치를 고정하는 실패 테스트 작성**

`test/full_diff_header_test.dart`의 `shortcut hints overlay controls without moving them` 테스트에 다음 검증을 추가한다.

```dart
final layoutControlRect = tester.getRect(
  find.ancestor(
    of: find.text('Unified'),
    matching: find.byWidgetPredicate(
      (widget) => widget is FullDiffSegmentedControl<DiffLayout>,
    ),
  ),
);
final layoutHintRect = tester.getRect(
  find.byKey(const Key('shortcut-hint-layout')),
);
expect(layoutHintRect.top, closeTo(layoutControlRect.bottom - 4, 0.5));
```

`test/full_diff_visual_test.dart`의 `26-shortcut-hints` 검증도 같은 기대값으로 바꾼다.

```dart
expect(layoutHintRect.top, closeTo(layoutControlRect.bottom - 4, 0.5));
```

- [ ] **Step 2: 위치 테스트가 기존 구현에서 실패하는지 확인**

Run:

```bash
flutter test test/full_diff_header_test.dart test/full_diff_visual_test.dart \
  --plain-name "shortcut hints"
```

Expected: 현재 배지는 버튼 하단보다 4픽셀 아래에서 시작하므로 `bottom - 4` 기대값에서 실패한다.

- [ ] **Step 3: 공통 배지 오프셋을 승인된 위치로 변경**

`lib/full_diff_shortcut_hint.dart`에서 오프셋을 한 곳만 수정한다.

```dart
offset: const Offset(0, -4),
```

다른 배지 스타일이나 각 호출부는 수정하지 않는다.

- [ ] **Step 4: 위치 테스트와 Full Diff 관련 테스트 실행**

Run:

```bash
flutter test test/full_diff_header_test.dart
flutter test test/full_diff_visual_test.dart \
  --plain-name "capture 26-shortcut-hints"
flutter test test/full_diff_workspace_test.dart
```

Expected: 모든 테스트가 통과하고, `26-shortcut-hints.png`에서 배지가 버튼 하단에 붙어 있으며 다음 아이콘이나 본문을 가리지 않는다.

- [ ] **Step 5: 포맷과 전체 테스트 확인**

Run:

```bash
dart format lib/full_diff_shortcut_hint.dart \
  test/full_diff_header_test.dart \
  test/full_diff_visual_test.dart
git diff --check
flutter analyze
flutter test
```

Expected: 분석 오류가 없고 전체 테스트 649개 이상이 모두 통과한다.

- [ ] **Step 6: 구현 커밋**

```bash
git add \
  lib/full_diff_shortcut_hint.dart \
  test/full_diff_header_test.dart \
  test/full_diff_visual_test.dart \
  docs/superpowers/verification/full-diff-qa/actual/26-shortcut-hints.png
git commit -m "fix: raise full diff shortcut hints"
```

캡처 파일에 실제 픽셀 차이가 생기지 않았으면 해당 파일은 `git add` 대상에서 빠져도 된다.

### Task 2: 최종 검수와 로컬 main 통합

**Files:**
- Verify: `lib/full_diff_shortcut_hint.dart`
- Verify: `test/full_diff_header_test.dart`
- Verify: `docs/superpowers/verification/full-diff-qa/actual/26-shortcut-hints.png`

**Interfaces:**
- Consumes: Task 1의 공통 배치 규칙과 통과한 전체 테스트
- Produces: 검수와 로컬 `main` 통합을 마친 변경

- [ ] **Step 1: 변경 범위 검토**

Run:

```bash
git diff main...HEAD --check
git diff --stat main...HEAD
git diff main...HEAD -- \
  lib/full_diff_shortcut_hint.dart \
  test/full_diff_header_test.dart \
  test/full_diff_visual_test.dart
```

Expected: 배지 위치와 그 회귀 검증만 달라지고 관련 없는 코드 변경은 없다.

- [ ] **Step 2: 최신 main과 합친 상태에서 전체 검증**

최신 `main`을 기능 브랜치에 합친 다음 아래 명령을 실행한다.

```bash
flutter analyze
flutter test
```

Expected: 분석 오류가 없고 전체 테스트가 모두 통과한다.

- [ ] **Step 3: 로컬 main에 머지**

`main` 전용 격리 작업공간에서 기능 브랜치를 머지한다.

```bash
git merge --no-ff codex/full-diff-shortcut-hint-position
```

- [ ] **Step 4: 머지된 main 최종 확인**

Run:

```bash
flutter analyze
flutter test
git status --short --branch
```

Expected: 분석 오류가 없고 전체 테스트가 모두 통과하며 작업공간이 깨끗하다.
