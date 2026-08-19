# Pull과 Push — 개발 설계

승인된 시안: [upstream-sync-mockup.html](upstream-sync-mockup.html). 시안의 계약이 곧
테스트 목록이고, 이 문서는 그 계약을 어느 부품으로 어떻게 지키는지를 적는다.

## 요약

기준 브랜치와 upstream의 어긋남을 미리 재어 두고, 툴바의 캡슐 두 동사(Pull / Push)가
판정 색을 입는다. 어긋났을 때의 판정 — 로컬 커밋이 원격 끝 위에 깨끗이 얹히는가 — 은
숨은 worktree 재연 한 번으로 나오고, 그 답이 두 버튼을 동시에 칠한다.

## 이미 있는 부품

| 필요한 일 | 있는 부품 | 위치 |
|---|---|---|
| ahead/behind | `RepoRefs.aheadBehind`, `upstreams`, `upstreamRemotes` — refs 로드에 포함 | git.dart:1932 |
| fetch | `fetchRemote`, `_refreshRemotes`, 상태바 실패·재시도 | git.dart:4608, timeline.dart |
| 재연 dry-run | `RebasePreviewSession(baseTip:, compareTip:, originalCommits:)` → `start()` → `RebasePreviewResult{clean·conflict·failed, virtualTip, conflictFiles}` | git.dart:836 |
| ref만 이동 (체크아웃 불가침) | `_moveLocalBranch(branch:, expected:, next:)` — `update-ref`에 expected를 걸어 경합 안전 | git.dart:3406 부근 |
| 빨리감기 Pull 양 경로 | `pullRemoteBranch(remote, branch, checkedOut:)` — 체크아웃이면 `pull --ff-only`, 아니면 `fetch remote branch:branch` | git.dart:4643 |
| 오간 커밋 목록 | `loadMovedCommits(before, after)` — `--left-right` 한 번이 들어올 커밋(<)과 올라갈 커밋(>)을 같이 준다 | git.dart:2226 |
| 확인창 뼈대 | `YogitAlert` + `LocalChangeNotice`의 블록(요약줄·커밋 목록) 시각 언어 | yogit_alert.dart, timeline_widgets.dart:968 |
| 충돌 해결 흐름 | 브랜치 diff의 rebase 미리보기 충돌 화면 전체 | timeline_branch_preview.dart |

새로 만드는 것: **git push 메서드 하나, 판정 컨트롤러 하나, 캡슐 위젯 하나,
Push 확인창 내용물 하나.**

## 상태 모델

새 파일 `lib/upstream_sync.dart`.

```dart
enum UpstreamSyncKind {
  hidden,            // 기준이 원격 ref이거나 refs가 아직 없음 — 캡슐 자체가 없다
  firstPush,         // upstream 미설정 또는 원격 ref 소멸 — push -u
  synced,            // ahead 0 · behind 0 — 점 하나
  pushOnly,          // ahead>0 · behind 0 — 초록 Push
  pullOnly,          // ahead 0 · behind>0 — 초록 Pull
  measuring,         // 어긋남, 재연 진행 중 — 무채색 숫자
  divergedClean,     // 재연 성공 — 주황 Pull·Push
  divergedConflict,  // 재연 충돌 — 빨강, conflictFiles
}

class UpstreamSyncState {
  final UpstreamSyncKind kind;
  final int ahead, behind;
  final String? localTip, remoteTip;   // 판정이 잰 두 끝
  final List<String> conflictFiles;
  final String? virtualTip;            // divergedClean일 때 재연이 만든 새 tip
  final DateTime? measuredAt;          // tooltip의 'N분 전'
}
```

### 판정 파이프라인

```
refs 로드/fetch 완료 ──> ahead·behind 읽기 (공짜)
        │
        ├─ 어긋남 아님 ──> kind 확정, 끝
        │
        └─ ahead>0 ∧ behind>0 ──> (localTip, remoteTip) 쌍이 지난 판정과 같으면 재사용
                                   다르면 RebasePreviewSession(
                                     baseTip: remoteTip,      // upstream 끝
                                     compareTip: localTip,    // 로컬 끝
                                     originalCommits: 로컬 전용 커밋,
                                   ).start() ──> clean → divergedClean(virtualTip 보관)
                                                 conflict → divergedConflict(files)
                                                 failed → measuring 유지 + 상태바 오류
```

- 재연은 **기준 브랜치 하나만, 한 번에 하나만**. 진행 중 tip이 또 움직이면 결과를
  버리고 다시 잰다 (serial 번호 패턴 — `_requestSerial`류, avatars.dart와 동일 수법).
- clean 판정의 worktree는 **바로 버리지 않는다**: virtualTip은 커밋 객체로 저장소에
  남으므로 세션은 dispose하고 virtualTip 해시만 보관한다. '받아 얹고 Push' 실행은
  그 tip으로 `_moveLocalBranch(expected: localTip)` — 그 사이 로컬이 움직였으면
  update-ref가 거절하고 재판정한다.
- 충돌 판정의 세션도 dispose. 해결 흐름은 P4에서 브랜치 diff 모드가 자기 세션을
  새로 연다 (이미 그렇게 동작하는 화면이라 세션 공유가 오히려 복잡도).

### 컨트롤러

```dart
class UpstreamSyncController extends ChangeNotifier {
  UpstreamSyncState get state;
  void updateRefs(RepoRefs refs, String? baseBranch);  // 타임라인이 refs 로드마다 호출
  Future<void> pull();                                  // pullOnly에서만
  Future<void> push();                                  // pushOnly·firstPush에서만
  Future<void> rebaseThenPush();                        // divergedClean에서만
}
```

재연 실행 함수는 생성자 주입 (`Future<RebasePreviewResult> Function(...)`) — 상태
판정 테스트가 가짜 재연으로 돌 수 있어야 한다. 타임라인의 기존 ref watcher가 tip
이동을 이미 감지하므로 컨트롤러는 스스로 감시하지 않는다.

## git 층 추가

```dart
/// 로컬 브랜치를 upstream으로 올린다. force 없음 — 그 사이 원격이 움직였으면
/// git이 거절하고, 거절은 재판정으로 이어진다.
Future<void> pushBranch(String remote, String branch, {bool setUpstream = false}) =>
    _runWithoutPrompts([
      '-c', 'credential.interactive=never',
      'push', if (setUpstream) '-u', remote, '$branch:$branch',
    ]);
```

- Pull(빨리감기): `pullRemoteBranch` 그대로 재사용. 변경 없음.
- 받아 얹기 실현: `RebasePreviewSession` + `_moveLocalBranch` 재사용. 단
  `applyRebasePreview`는 `BranchComparisonResult`에 묶여 있으므로, 얇은 진입로
  `applyUpstreamRebase({branch, expectedTip, virtualTip})`를 추가해 같은
  `_moveLocalBranch`를 부른다. 체크아웃된 브랜치의 작업 트리 갱신 규칙(더러우면
  거절)은 `_moveLocalBranch`의 기존 약속을 그대로 상속 — **P1에서 그 약속을 실제
  git 테스트로 못 박는다.**

## UI 층

### 캡슐 — `UpstreamSyncCapsule` (새 파일 lib/upstream_sync_capsule.dart)

- 순수 위젯: `state` + 콜백 셋(`onPull`, `onPush`, `onResolveConflict`)만 받는다.
- 시안 규칙 그대로: synced → 6px 점, 단독 상태 → 동사 하나, measuring → 무채색
  숫자, diverged → 두 동사 같은 판정 색, conflict → `↓ N 충돌 M파일`.
- 자리: `RepositoryBranchSelector`에 `Widget? trailing` 슬롯을 하나 열고 기준
  브랜치 선택기 다음에 끼운다. 선택기 내부 로직은 건드리지 않는다.
- tooltip: 판정 문장 + `measuredAt` 상대 시각. 기존 `_tooltip`/`SideTooltip` 재사용.

### Push 확인창 — 오갈 커밋 목록

- `YogitAlert` 골격에 내용물 `PushSummary` 위젯: `LocalChangeNotice`의
  블록(요약줄 + `MovedCommit` 행) 렌더링을 공용 위젯 `MovedCommitBlock`으로
  추출해 둘이 같이 쓴다 — 형식이 한 곳에서 관리된다.
- 초록 Push: 블록 하나(`main · push · 커밋 N개 올라감`, ↑ 표식) + "원격 main이
  A에서 B로 움직입니다" + [그만두기 | Push].
- 주황: 제목 "받아 얹은 뒤 Push할까요? (Pull Rebase and Push)", 블록 둘
  (pull --rebase 들어옴 / push 올라감) + "충돌 없음은 방금 재연으로 확인했습니다.
  얹힌 커밋은 해시가 달라집니다." + [그만두기 | Pull Rebase and Push].
- 커밋 목록은 `loadMovedCommits(remoteTip, localTip)` 한 번 — `<`가 들어올 커밋,
  `>`가 올라갈 커밋. 9개 초과는 기존 규칙대로 '외 N개'.

### 실행과 그 뒤

- Pull(초록): 확인 없이 `pullRemoteBranch` → refs 재로드 → 타임라인이 말한다.
- Push(초록/처음): 확인창 → `pushBranch` → refs 재로드.
- 받아 얹고 Push(주황): 확인창 → `applyUpstreamRebase`(ref 이동) →
  `pushBranch` → refs 재로드. 첫걸음이 expected 불일치로 거절되면 중단·재판정.
  push가 거절되면(그 사이 원격 이동) 로컬 rebase는 유지된 채 재판정 —
  다음 판정은 대개 pushOnly거나 다시 diverged다.
- 충돌(빨강): 기준을 upstream ref로, 비교를 로컬 브랜치로 하는 브랜치 diff에
  rebase 모드로 진입 — 기존 충돌 해결 화면 그대로. 진입 전 기준 브랜치를 기억해
  두었다가 흐름이 끝나면(적용이든 포기든) 복원한다.

## 구현 단계 — 각 단계가 TDD 한 바퀴

### P1 · git 층 (실제 git 테스트, test/git_test.dart)

이 저장소의 기존 수법대로 실제 저장소를 만들어 검증한다 (`_initRepository` +
bare 원격 + clone).

1. `pushBranch`가 bare 원격의 ref를 전진시킨다 / 원격이 먼저 움직였으면 거절한다
2. `pushBranch(setUpstream: true)`가 upstream을 연결한다
3. `applyUpstreamRebase`: 체크아웃 밖 브랜치 — ref만 이동, 작업 트리 불변
4. `applyUpstreamRebase`: expectedTip 불일치 — 아무것도 움직이지 않고 거절
5. 체크아웃된 브랜치 + 더러운 트리 — 거절하고 이유를 말한다 (`_moveLocalBranch`
   기존 약속의 계약화)
6. `loadMovedCommits(remoteTip, localTip)`가 들어올/올라갈 커밋을 가른다 (기존
   테스트 보강)

### P2 · 판정 (test/upstream_sync_state_test.dart — 순수, 가짜 재연 주입)

1. refs → kind 매핑 전부 (hidden/firstPush/synced/pushOnly/pullOnly)
2. 어긋나면 measuring을 거쳐 재연 결과대로 divergedClean/Conflict
3. (localTip, remoteTip) 쌍이 같으면 재연을 다시 돌리지 않는다
4. 재연 중 tip이 움직이면 낡은 결과를 버린다 (serial)
5. 재연 failed — 판정 보류, 마지막 판정 유지
6. 기준이 원격 ref면 hidden

### P3 · 캡슐 + 확인창 (test/upstream_sync_capsule_contract_test.dart)

시안 '계약' 절을 한 줄씩 옮긴다:

1. synced에서 동사가 없다 — 점 하나
2. 단독 상태는 동사 하나, 개수는 판정 색과 함께
3. measuring은 무채색, 끝나면 두 동사가 같은 판정을 입는다
4. Push는 확인창 — 올라갈 커밋 목록과 ref 이동 해시
5. 주황 확인창은 블록 둘, 제목은 "받아 얹은 뒤 Push할까요? (Pull Rebase and Push)"
6. Pull은 확인 없이 콜백 즉시
7. 빨강은 실행 없이 충돌 진입 콜백만
8. tooltip에 잰 시각

앱 통합 (test/upstream_sync_flow_contract_test.dart): 툴바에 캡슐이 서고, fetch
완료가 재판정을 부르고, 주황 확인 한 번에 두 걸음이 이어지고, 완료 후 타임라인
행이 갱신된다.

### P4 · 충돌 흐름 연결

1. 빨강 클릭 → 브랜치 diff(기준 upstream, 비교 로컬) rebase 모드 진입
2. 해결 완료 후 캡슐이 주황(남은 걸음 Push)으로 돌아온다
3. 포기 → 로컬 브랜치 무변, 기준 브랜치 복원

## 엣지와 리스크

| 경우 | 처리 |
|---|---|
| 기준 브랜치가 원격 ref | 캡슐 hidden — 올릴 로컬이 없다 |
| upstream 미설정 / 원격 ref 소멸 | firstPush — `push -u` |
| fetch 실패 | 마지막 판정 유지, tooltip에 'N분 전 기준'. 재시도는 상태바 기존 담당 |
| 체크아웃 + 더러운 트리 | pull·rebase 실현 모두 git/기존 약속이 거절 — 이유를 알림으로 |
| 다른 worktree가 체크아웃한 브랜치 | `_moveLocalBranch`가 이미 거절한다 — 그 문구 그대로 알림으로 |
| push 사이 원격 이동 | force 없음 → git 거절 → 재판정. 로컬 rebase 결과는 유지 |
| 재연 중 로컬 커밋 추가 | ref watcher → tip 변화 → 낡은 판정 폐기, 재판정 |
| 큰 어긋남 (behind 수백) | 재연 비용 = rebase 1회. worktree는 기존 정리 규칙(df9618c)이 청소 |
| 브랜치 diff 사용 중 | 캡슐은 표시만, 실행 버튼 비활성 — 두 worktree 흐름을 겹치지 않는다 |

리스크 하나를 명시해 둔다: P4의 '기준 브랜치 전환 후 복원'은 브랜치 diff 상태
기계와 얽힌다. P1–P3만으로도 기능이 완결되므로(빨강 = 충돌 파일 tooltip + 진입
버튼 비활성으로 임시 처리) P4는 별도 커밋 열차로 간다.

## 완료 정의

- `flutter analyze lib test` 무결
- 새 테스트 전부 + 기존 스위트 전체 green
- 시안 '계약' 절의 각 항목이 테스트 이름으로 존재한다
- 커밋은 P1~P4 단계별로, 각 단계가 홀로 되돌릴 수 있게
