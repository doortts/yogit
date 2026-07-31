# No-op Remote Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 원격 추적 참조가 바뀌지 않은 3분 주기 확인이 타임라인과 브랜치 미리보기를 다시 구성하지 않게 한다.

**Architecture:** Git 계층이 `updated`와 `unchanged`를 구분하고 타임라인은 실제 변경에만 참조를 다시 읽는다. 브랜치 비교는 tip SHA가 달라질 때만 백그라운드에서 다시 계산하며 원격 확인 상태는 상태표시줄 전용 notifier로 제한한다.

**Tech Stack:** Dart, Flutter, Git CLI, flutter_test

## Global Constraints

- 새 의존성을 추가하지 않는다.
- 기존 3분 주기와 앱 생명주기·중복 요청 방지는 유지한다.
- 테스트를 먼저 실패시킨 뒤 최소 구현으로 통과시킨다.
- 변경 없는 확인은 `TimelineScreen.setState()`를 호출하지 않는다.

---

### Task 1: Git fetch 결과 구분

**Files:**
- Modify: `lib/git.dart:1676,3272-3298`
- Test: `test/git_test.dart:2497-2545`

**Interfaces:**
- Produces: `FetchOriginResult.unchanged`
- Produces: `GitRepository.fetchRemote(String)`이 porcelain 출력에 따라 결과 반환

- [ ] **Step 1: 변경 없는 fetch와 변경 있는 fetch를 구분하는 실패 테스트 작성**
- [ ] **Step 2: `flutter test test/git_test.dart --plain-name 'fetchRemote distinguishes unchanged and updated refs'`로 의도한 실패 확인**
- [ ] **Step 3: `--porcelain`을 추가하고 빈 출력을 `unchanged`로 반환하는 최소 구현**
- [ ] **Step 4: 저장소 테스트 통과 확인**
- [ ] **Step 5: 변경 커밋**

### Task 2: 불필요한 참조·비교 재계산 제거

**Files:**
- Modify: `lib/timeline.dart:877-976,1983-2039`
- Test: `test/app_test.dart:2760-3075`

**Interfaces:**
- Consumes: `FetchOriginResult.unchanged`
- Produces: tip이 바뀔 때만 실행되는 비교 갱신 경로

- [ ] **Step 1: 변경 없음이면 `loadRefs()` 호출 횟수가 늘지 않는 실패 테스트 작성**
- [ ] **Step 2: 같은 tip의 참조 재로딩이 `compareBranches()`를 다시 호출하지 않는 실패 테스트 작성**
- [ ] **Step 3: 바뀐 tip을 읽는 동안 기존 비교 행이 남고 완료 후 교체되는 실패 테스트 작성**
- [ ] **Step 4: 각 테스트가 현재 동작 때문에 실패하는지 확인**
- [ ] **Step 5: 변경 없음 건너뛰기와 tip 비교를 최소 코드로 구현**
- [ ] **Step 6: 새 비교 결과를 준비한 뒤 교체하도록 기존 선택 함수를 확장**
- [ ] **Step 7: 관련 위젯 테스트 통과 확인**
- [ ] **Step 8: 변경 커밋**

### Task 3: 원격 확인 상태의 재빌드 범위 제한

**Files:**
- Modify: `lib/timeline.dart:783-904,1089,3328-3360`
- Test: `test/app_test.dart:2760-3010`

**Interfaces:**
- Produces: 상태표시줄만 구독하는 원격 확인 진행·오류 notifier

- [ ] **Step 1: 변경 없는 확인 동안 타임라인 행이 다시 구성되지 않는 실패 테스트 작성**
- [ ] **Step 2: 테스트의 실패 원인이 상위 `setState()`인지 확인**
- [ ] **Step 3: 진행·오류 상태를 notifier로 옮기고 상태표시줄만 구독**
- [ ] **Step 4: notifier를 `dispose()`에서 정리**
- [ ] **Step 5: 관련 위젯 테스트 통과 확인**
- [ ] **Step 6: `flutter analyze`와 전체 `flutter test -r silent` 실행**
- [ ] **Step 7: 변경 커밋**

