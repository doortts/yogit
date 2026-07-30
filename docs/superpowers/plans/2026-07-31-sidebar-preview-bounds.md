# Sidebar And Bottom Preview Bounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 왼쪽 패널의 최소 폭을 150픽셀로 고정하고 하단 미리보기가 컬럼 헤더 바로 아래까지 늘어나게 한다.

**Architecture:** 기존 크기 저장 방식과 드래그 핸들을 그대로 사용한다. 왼쪽 패널은 두 최소값만 맞추고 하단 미리보기는 작업 영역 높이에서 타임라인 상단 영역을 뺀 동적 상한을 사용한다.

**Tech Stack:** Flutter, Dart, flutter_test

## Global Constraints

- 새 의존성을 추가하지 않는다.
- 하단 미리보기의 최소 높이 200픽셀은 유지한다.
- `BRANCH / TAG`를 포함한 컬럼 헤더는 가리지 않는다.

---

### Task 1: 왼쪽 패널의 최소 폭

**Files:**
- Modify: `lib/timeline.dart`
- Modify: `lib/settings.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `TimelineColumnWidths.fromJson`, `_sidebarRange`
- Produces: 드래그와 설정 복원에서 같은 150픽셀 최소 폭

- [ ] **Step 1: 실패하는 테스트 작성**

`the sidebar resizes, persists, and clamps` 테스트에서 최소 폭과 저장값을 150으로 기대하고 40픽셀 저장값도 150으로 보정되는지 검사한다.

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/app_test.dart --plain-name 'the sidebar resizes, persists, and clamps'`

Expected: 현재 구현이 120을 반환하므로 실패한다.

- [ ] **Step 3: 최소 구현**

`_sidebarRange.min`과 `TimelineColumnWidths.fromJson`의 `sidebar` 최소값을 150으로 바꾼다.

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/app_test.dart --plain-name 'the sidebar resizes, persists, and clamps'`

Expected: PASS

### Task 2: 하단 미리보기의 동적 최대 높이

**Files:**
- Modify: `lib/timeline.dart`
- Modify: `lib/settings.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Consumes: `_workspaceLayout`, `_previewResizer`, `AppSettings.fromJson`
- Produces: 현재 작업 영역에 맞춘 하단 미리보기 최대 높이

- [ ] **Step 1: 실패하는 테스트 작성**

미리보기를 하단으로 옮긴 뒤 분할선을 위로 충분히 끌어 컬럼 헤더가 보이는 상태에서 기존 480픽셀보다 커지는지 검사한다. 설정의 `previewHeight`가 480보다 큰 값도 그대로 읽는지 검사한다.

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/app_test.dart --plain-name 'the preview panel resizes, persists, and clamps'`

Expected: 높이가 480에서 멈추거나 저장값이 480으로 줄어 실패한다.

- [ ] **Step 3: 최소 구현**

작업 영역 높이에서 컬럼 헤더 높이와 선택적인 브랜치 비교 요약 높이를 뺀 값을 하단 미리보기 상한으로 계산한다. 드래그와 표시 크기에 같은 상한을 적용하고 설정 복원의 고정 상한을 없앤다.

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/app_test.dart --plain-name 'the preview panel resizes, persists, and clamps'`

Expected: PASS

### Task 3: 전체 검증

**Files:**
- Verify: `lib/timeline.dart`
- Verify: `lib/settings.dart`
- Verify: `test/app_test.dart`

**Interfaces:**
- Consumes: Task 1과 Task 2의 변경
- Produces: 분석과 전체 테스트를 통과한 작업 브랜치

- [ ] **Step 1: 코드 형식 정리**

Run: `dart format lib/timeline.dart lib/settings.dart test/app_test.dart`

- [ ] **Step 2: 정적 분석**

Run: `flutter analyze`

Expected: No issues found

- [ ] **Step 3: 전체 테스트**

Run: `flutter test`

Expected: All tests passed

- [ ] **Step 4: 변경 검토**

Run: `git diff --check && git diff --stat && git status --short`

Expected: 공백 오류가 없고 요청한 파일과 문서만 변경되어 있다.
