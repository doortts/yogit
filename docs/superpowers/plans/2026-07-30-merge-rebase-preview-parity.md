# Merge·Rebase 미리보기 시안 일치 작업 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 승인된 최종 기준 페이지와 실제 앱의 Merge·Rebase 성공·충돌 화면을 같은 시각 언어와 정보 구조로 맞춘다.

**Architecture:** Git 미리보기 결과와 기존 타임라인 배치는 그대로 두고 `TimelineScreen`의 상태별 표시 규칙만 보강한다. 가상 행·노드·라벨은 `PreviewGraphNodeKind`에서 파생하고, 새로 생긴 가상 구간만 `CommitGraphPainter`의 1px 점선 규칙을 사용한다.

**Tech Stack:** Dart, Flutter, Flutter widget tests, 기존 `GraphRow`와 `CommitGraphPainter`

## Global Constraints

- 기준 페이지는 `docs/superpowers/specs/assets/merge-rebase-preview/final-reference.html`이다.
- 기존 타임라인 레일의 선, 곡률, 연결 규칙은 바꾸지 않는다.
- Merge·Rebase 미리보기로 새로 생긴 연결선만 1px 점선으로 그린다.
- 가상 성공 요소는 보라색, 충돌 중인 요소는 붉은색과 문구를 함께 사용한다.
- 새 패키지나 새 상태 관리 계층은 추가하지 않는다.

---

### Task 1: 가상 타임라인의 색과 연결선

**Files:**
- Modify: `lib/timeline.dart:99-230`
- Modify: `lib/timeline.dart:4160-4865`
- Modify: `lib/timeline.dart:7233-7685`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `PreviewGraphNodeKind`, `BranchPreviewGraph.dashedLanes`
- Produces: `CommitGraphPainter.isDashedAbove(int lane)`
- Produces: 상태별 가상 행 배경, 라벨 색, Merge 충돌 노드

- [ ] **Step 1: 아래쪽 절반까지 점선이 이어지는 실패 테스트 작성**

```dart
test('preview rail inherits the previous row dash above its node', () {
  final painter = CommitGraphPainter(
    row: baseRow,
    previous: virtualRow,
    selected: false,
    committerColor: Colors.green,
    previousDashedLanes: const {0},
  );
  expect(painter.isDashedAbove(0), isTrue);
});
```

- [ ] **Step 2: 가상 성공·충돌 행의 실패 테스트 작성**

```dart
expect(find.byKey(const Key('virtual-preview-row')), findsOneWidget);
expect(find.byKey(const Key('virtual-preview-chip')), findsOneWidget);
expect(find.byKey(const Key('virtual-merge-conflict-node')), findsOneWidget);
expect(find.text('! 병합 충돌'), findsOneWidget);
```

- [ ] **Step 3: 실패 확인**

Run: `flutter test test/app_test.dart --plain-name "preview rail inherits"`

Expected: `isDashedAbove`가 없어 실패

Run: `flutter test test/app_test.dart --plain-name "branch preview"`

Expected: 가상 행 키와 충돌 노드가 없어 실패

- [ ] **Step 4: 점선 상속과 상태별 표시를 최소 구현**

```dart
bool isDashedAbove(int lane) =>
    dashedLanes.contains(lane) || previousDashedLanes.contains(lane);
```

직선 레일의 위쪽 절반만 `isDashedAbove()`를 사용한다. 아래쪽 절반과 기존
전환선 규칙은 그대로 둔다. `virtualMerge`, `virtualRebase` 행은 보라색
배경과 테두리를 사용하고 Merge 충돌일 때만 붉은 행, `!` 노드,
`! 병합 충돌` 라벨로 바꾼다.

- [ ] **Step 5: 관련 테스트 실행**

Run: `flutter test test/app_test.dart --plain-name "branch preview"`

Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "style: distinguish virtual preview timeline states"
```

---

### Task 2: 상태별 요약과 오른쪽 패널

**Files:**
- Modify: `lib/timeline.dart:3294-3925`
- Modify: `lib/timeline.dart:5170-6136`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `_effectiveMergeStatus`, `_rebasePreview`, `_branchPreviewReady`
- Produces: `_branchPreviewSummaryChip(...)`
- Produces: `_branchPreviewPanelTitle`
- Produces: `_branchPreviewPanelStatus`

- [ ] **Step 1: 네 상태의 요약 문구 실패 테스트 작성**

```dart
expect(find.text('가상 커밋 1'), findsOneWidget);
expect(find.text('두 부모'), findsOneWidget);
expect(find.text('충돌 없음'), findsOneWidget);
expect(find.text('점선 이동 경로'), findsOneWidget);
expect(find.text('실제 브랜치 변경 없음'), findsOneWidget);
expect(find.text('임시 공간 사용 중'), findsOneWidget);
```

- [ ] **Step 2: 충돌 패널과 안전 안내 실패 테스트 작성**

```dart
expect(find.text('Merge 충돌 해결'), findsOneWidget);
expect(find.text('Rebase 상태 및 결정'), findsOneWidget);
expect(find.text('임시 공간에서 해결 중'), findsOneWidget);
expect(find.text('자동 준비됨'), findsOneWidget);
expect(find.text('적용 완료'), findsOneWidget);
expect(find.text('현재 충돌'), findsOneWidget);
expect(find.text('적용 대기'), findsOneWidget);
```

- [ ] **Step 3: 좁은 미리보기에서 적용 버튼이 잘리지 않는 실패 테스트 작성**

```dart
await tester.binding.setSurfaceSize(const Size(1280, 720));
expect(tester.takeException(), isNull);
expect(
  find.text('main 위로 fix/docs Rebase 실제 적용'),
  findsOneWidget,
);
```

- [ ] **Step 4: 실패 확인**

Run: `flutter test test/app_test.dart --plain-name "branch preview summary"`

Expected: 시안 문구를 찾지 못해 실패

- [ ] **Step 5: 상태별 표시 규칙 구현**

성공 상태는 제목 옆 녹색 체크와 보라색 의미 칩을 사용한다. Merge 충돌은
충돌 파일 수·두 부모·임시 공간을, Rebase 충돌은 최초 충돌·진행
순서·임시 공간을 표시한다. 오른쪽 패널은 상태에 따라 다음 제목을
사용한다.

```dart
final title = switch ((mode, hasConflict)) {
  (BranchPreviewMode.merge, false) => '가상 병합 커밋',
  (BranchPreviewMode.merge, true) => 'Merge 충돌 해결',
  (BranchPreviewMode.rebase, false) => '가상 리베이스 결과',
  (BranchPreviewMode.rebase, true) => 'Rebase 상태 및 결정',
};
```

안전 안내 카드에는 `임시 공간에서 해결 중`, `자동 준비됨` 머리글을
추가한다. 적용 카드는 폭이 좁으면 안내문과 버튼을 세로로 배치하고 버튼
문구는 줄바꿈할 수 있게 한다.

- [ ] **Step 6: 충돌 해결 완료 카드 정리**

충돌 해결을 마치면 한 카드 안에서 최종 diff 안내, `Drop`, 실제 적용
버튼을 함께 보여준다. 기존 `_branchPreviewApplyCard()`의 실제 적용
동작을 재사용하고 별도 상태나 콜백은 만들지 않는다.

- [ ] **Step 7: 관련 테스트 실행**

Run: `flutter test test/app_test.dart --plain-name "branch preview"`

Expected: PASS

- [ ] **Step 8: 커밋**

```bash
git add lib/timeline.dart test/app_test.dart
git commit -m "style: match branch preview summaries and conflict panels"
```

---

### Task 3: 고정 시나리오와 시각 검증

**Files:**
- Modify: `test/app_test.dart`
- Modify: `docs/superpowers/verification/merge-rebase-preview/actual/merge-success.png`
- Modify: `docs/superpowers/verification/merge-rebase-preview/actual/rebase-success.png`
- Modify: `docs/superpowers/verification/merge-rebase-preview/actual/merge-conflict.png`
- Modify: `docs/superpowers/verification/merge-rebase-preview/actual/rebase-conflict.png`
- Modify: `docs/superpowers/verification/merge-rebase-preview/review.md`

**Interfaces:**
- Consumes: 기존 `FakeGitRepository`, `BranchComparisonResult`
- Produces: 원본 커밋 세 개와 충돌 단계 세 개를 가진 고정 Rebase 화면
- Produces: 사실과 일치하는 시각 검토 기록

- [ ] **Step 1: 커밋 세 개 Rebase 화면 테스트 작성**

```dart
expect(find.byKey(const Key('virtual-rebase-node-rewrite-1')), findsOneWidget);
expect(find.byKey(const Key('virtual-rebase-node-rewrite-2')), findsOneWidget);
expect(find.byKey(const Key('virtual-rebase-node-rewrite-3')), findsOneWidget);
expect(find.text('가상 커밋 3개'), findsOneWidget);
```

- [ ] **Step 2: Rebase 진행 수치 테스트 작성**

```dart
expect(find.text('리베이스 진행 2/3'), findsOneWidget);
expect(find.text('1 적용 완료'), findsOneWidget);
expect(find.text('1 현재 충돌'), findsOneWidget);
expect(find.text('1 적용 대기'), findsOneWidget);
```

- [ ] **Step 3: 관련 테스트와 전체 테스트 실행**

Run: `flutter test test/app_test.dart --plain-name "branch preview"`

Expected: PASS

Run: `flutter test`

Expected: 모든 테스트 PASS

- [ ] **Step 4: 네 상태와 적용 흐름 다시 캡처**

1280×720, 100% 배율에서 고정 저장소를 사용해 성공·충돌 네 상태를 다시
캡처한다. Rebase 성공은 커밋 세 개를 사용한다. 적용 확인, 적용 중,
완료, 되돌리기 화면도 직접 확인하고 `review.md`에 결과를 기록한다.

- [ ] **Step 5: 최종 검사**

Run: `dart format --output=none --set-exit-if-changed lib/timeline.dart test/app_test.dart`

Expected: exit 0

Run: `flutter analyze`

Expected: `No issues found!`

Run: `git diff --check`

Expected: 출력 없음

- [ ] **Step 6: 검증 자료 커밋**

```bash
git add test/app_test.dart docs/superpowers/verification/merge-rebase-preview
git commit -m "test: verify branch preview visual parity"
```
