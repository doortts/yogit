# Merge·Rebase 미리보기 세부 시안 일치 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 승인된 `rebase-preview-refinement-v34.html`과 사용자 스크린샷을 기준으로 미리보기 문구, diff 전환 버튼, Rebase 대응 관계, Branch/Tag 라벨을 실제 앱에 일치시킨다.

**Architecture:** 기존 `TimelineScreen`과 `CommitGraphPainter`를 재사용하며, 미리보기 상태에서 파생되는 표시 값만 바꾼다. 일반 타임라인의 레일과 ref 연결 규칙은 보존하고, Branch/Tag 연결선 억제는 `_comparison`이 활성화된 경우에만 적용한다.

**Tech Stack:** Dart, Flutter, Flutter widget tests

## Global Constraints

- 기준 시안은 `docs/superpowers/specs/assets/merge-rebase-preview/rebase-preview-refinement-v34.html`이다.
- Merge·Rebase 미리보기의 Branch/Tag 라벨에는 그래프 방향 연결선을 그리지 않는다.
- 일반 타임라인의 ref 연결선, 레일 곡률, 연결 규칙은 바꾸지 않는다.
- 새 패키지, 새 상태 객체, 새 그래프 추상화는 추가하지 않는다.

---

### Task 1: 표시 규칙을 테스트로 고정

**Files:**
- Modify: `test/app_test.dart:3080-3229`
- Modify: `test/app_test.dart:3493-3676`
- Modify: `test/app_test.dart:4070-4140`
- Modify: `test/app_test.dart:5013-5028`

**Interfaces:**
- Consumes: `CommitGraphPainter.refConnector`, `rebaseMappingColors`, 미리보기 위젯 키
- Produces: 회귀를 막는 문구·색·크기·연결선 검증

- [ ] **Step 1: diff 선택 버튼의 회색 배경 테스트 작성**

```dart
expect(
  (unifiedButton.decoration! as BoxDecoration).color,
  const Color(0xFF2C2C2E),
);
```

- [ ] **Step 2: Branch/Tag 라벨과 연결선 테스트 작성**

```dart
expect(find.text('feature · 가상'), findsNWidgets(3));
expect(find.text('feature · 원본'), findsNWidgets(3));
expect(
  previewPainters.every((painter) => !painter.refConnector),
  isTrue,
);
```

- [ ] **Step 3: Rebase 대응 아바타와 색상 테스트 작성**

```dart
expect(tester.getSize(mappedRing), const Size.square(22));
expect(
  colors.map((color) => HSLColor.fromColor(color).lightness),
  everyElement(inInclusiveRange(0.48, 0.52)),
);
```

- [ ] **Step 4: 충돌 문구 테스트를 변경**

```dart
expect(find.text('충돌 해결 중'), findsOneWidget);
expect(find.text('현재 적용 중'), findsNothing);
```

- [ ] **Step 5: 실패 확인**

Run: `flutter test test/app_test.dart --plain-name "branch preview diff switches between both full diff layouts"`

Expected: 선택 배경이 파란색이라 실패

Run: `flutter test test/app_test.dart --plain-name "rebase preview adds rewritten commits to the timeline"`

Expected: Branch/Tag 연결선과 아바타 크기가 시안과 달라 실패

Run: `flutter test test/app_test.dart --plain-name "rebase conflict focuses the actual commit row"`

Expected: `충돌 해결 중` 문구가 없어 실패

Run: `flutter test test/app_test.dart --plain-name "rebase mapping colors"`

Expected: 대응 색상이 너무 어두워 실패

---

### Task 2: 시안 표시 규칙 구현

**Files:**
- Modify: `lib/timeline.dart:52-68`
- Modify: `lib/timeline.dart:4445-4503`
- Modify: `lib/timeline.dart:4729-4792`
- Modify: `lib/timeline.dart:5147-5170`
- Modify: `lib/timeline.dart:7285-7310`

**Interfaces:**
- Consumes: `_comparison`, `_palette.neutralChip`, `_rebaseMappingAvatarBorderWidth`
- Produces: 시안과 같은 미리보기 라벨, 문구, 대응선 색, 아바타 테두리

- [ ] **Step 1: 대응선 색상을 조금 밝게 조정**

```dart
final color = HSLColor.fromAHSL(
  1,
  (18 + index * 67) % 360,
  0.34,
  0.50,
).toColor();
```

- [ ] **Step 2: 미리보기의 Branch/Tag 연결선을 억제**

```dart
refs.isNotEmpty && _comparison == null,
```

- [ ] **Step 3: 시안 문구와 라벨 유지**

```dart
? '충돌 해결 중'
```

가상 Rebase는 `${comparison.compareRef} · 가상`, 원본은
`${comparison.compareRef} · 원본`, 기준 브랜치는 `comparison.baseRef`,
공통 부모는 `공통`을 사용한다. 가상 tip과 기준 branch tip에만 기존
`GitRef.isHead` 체크 표시를 재사용한다.

- [ ] **Step 4: 대응 아바타 테두리가 원에 밀착되도록 수정**

```dart
Container(
  width: size,
  height: size,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    border: Border.all(
      color: mappingColor,
      width: _rebaseMappingAvatarBorderWidth,
    ),
  ),
  child: CommitAvatarStack(
    size: size - _rebaseMappingAvatarBorderWidth * 2,
  ),
)
```

- [ ] **Step 5: diff 선택 버튼에 테마 중립색 사용**

```dart
color: _branchPreviewLayout == layout
    ? _palette.neutralChip
    : Colors.transparent,
```

- [ ] **Step 6: 관련 테스트 실행**

Run: `flutter test test/app_test.dart --plain-name "branch preview diff switches between both full diff layouts"`

Run: `flutter test test/app_test.dart --plain-name "rebase preview adds rewritten commits to the timeline"`

Run: `flutter test test/app_test.dart --plain-name "rebase preview focuses the first conflicting commit"`

Run: `flutter test test/app_test.dart --plain-name "rebase mapping colors"`

Expected: 모두 PASS

---

### Task 3: 전체 검증과 시안 비교

**Files:**
- Verify: `lib/timeline.dart`
- Verify: `test/app_test.dart`
- Verify: `docs/superpowers/specs/assets/merge-rebase-preview/rebase-preview-refinement-v34.html`

**Interfaces:**
- Consumes: Task 1과 Task 2의 구현
- Produces: 정적 분석, 전체 테스트, 실제 앱 시각 확인 결과

- [ ] **Step 1: 형식과 정적 분석 확인**

Run: `dart format lib/timeline.dart test/app_test.dart`

Run: `flutter analyze`

Expected: 오류 없음

- [ ] **Step 2: 전체 테스트 실행**

Run: `flutter test`

Expected: 모두 PASS

- [ ] **Step 3: 앱을 다시 실행해 시안과 비교**

Merge와 Rebase 미리보기를 각각 열어 다음을 확인한다.

- Branch/Tag 칩에서 그래프 방향 연결선이 보이지 않는다.
- 가상, 기준, 원본, 공통 라벨의 문구가 시안과 같다.
- Rebase 원본·가상 대응 테두리가 아바타에 밀착된다.
- Unified·Side-by-side 선택 배경이 회색이다.
- 충돌 행에 `충돌 해결 중`이 표시된다.

- [ ] **Step 4: 커밋**

```bash
git add lib/timeline.dart test/app_test.dart \
  docs/superpowers/plans/2026-07-31-branch-preview-detail-parity.md \
  docs/superpowers/specs/assets/merge-rebase-preview/rebase-preview-refinement-v34.html
git commit -m "style: refine branch preview timeline details"
```
