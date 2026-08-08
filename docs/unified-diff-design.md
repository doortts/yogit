# Full Diff × 미리보기 통합 설계

2026-08-08 · 확정 시안: 1안 (이어 붙인 패널) · 시안 파일: `docs/unified-diff-mockup.html`

## 1. 배경과 목표

지금 diff 화면이 둘이다.

- **Full Diff** (`DiffScreen`, 전체화면 route): 헤더 2줄(파일 정보 + diff 옵션), 파일 목록
  pane, 미니맵, 문법 강조, blame, history, 알고리즘 선택까지 갖춘 본편.
- **미리보기 인접 diff** (`timeline.dart`의 `_adjacentPreviewDiff`): 미리보기 pane에서 파일을
  고르면 타임라인 옆에 끼어드는 간이판. Unified/Side-by-side 전환만 있고 미니맵·알고리즘·
  blame·history가 없다.

같은 일을 두 벌로 유지하는 비용을 없애고, 파일을 고르는 순간부터 본편 품질의 diff를 본창
안에서 바로 보게 한다. **미리보기 인접 diff와 전체화면 route를 둘 다 없애고, Full Diff의
기계 전체를 워크스페이스 영역(사이드바+타임라인 자리)에 임베드한다.**

파일 목록 pane은 만들지 않는다 — 그 역할은 미리보기 pane이 이미 하고 있다.

## 2. 화면 구조

### 2.1 배치 규칙 (미리보기 위치별)

diff 모드가 켜지면 사이드바와 타임라인이 사라지고 그 자리를 diff가 차지한다.
미리보기 pane과 History pane의 배치는 미리보기 위치 설정을 따른다.

| 미리보기 위치 | 배치 (왼쪽부터) |
|---|---|
| 우측 (기본) | diff+미니맵 · History · 미리보기 |
| 좌측 | 미리보기 · History · diff+미니맵 |
| 하단 | 위 = diff+미니맵 (전체 폭) / 아래 줄 = 미리보기 · History |

- 하단 배치의 아래 줄 높이는 지금 미리보기 하단 배치의 높이 조절을 그대로 쓴다.
- 미리보기가 닫혀 있을 때 ⌘D를 누르면 미리보기를 먼저 열고 진입한다.
- 세 열은 1px 구분선(`fullDiffDivider` / 본창 `border`)으로 나란히 붙는다 — 1안의 골격.

### 2.2 헤더 — Full Diff 옵션 요소 전부

`GlobalFileBar`와 `GlobalDiffToolbar`를 그대로 가져온다. diff 칼럼 폭 안에서만 그려지고,
좁아지면 지금처럼 Wrap으로 줄바꿈한다.

1줄 (GlobalFileBar): ← 복귀 · 파일 경로 칩 · `M · +15 −11 · 23 KB` 배지 · `UTF-8` 배지 ·
집중 모드(⇧F) · 편집기로 열기 · Diff|Blame(⌘1/⌘2)

2줄 (GlobalDiffToolbar): `diff 알고리즘` + 선택기(⇧A) · 공백 무시(⇧Space) · 줄바꿈(⇧L) ·
`↑ n / m ↓` hunk 이동 · Unified|Side-by-side(⌘U) · Hunk(⇧H) · History(⌘3)

헤더는 원판보다 컴팩트하게 조인다: `fullDiffControlHeight` 28→24, `_HeaderBar` 상하 패딩
7→4, 컨트롤 간격(Wrap spacing) 5. 전체화면 route가 사라지므로 토큰 자체를 바꾸면 되고,
헤더 부품 테스트의 치수 단언도 함께 갱신한다.

### 2.3 커밋 컨텍스트 라인

헤더 아래 한 줄: `6983f0f · 이전 상태 ← ff81987 · <커밋 제목>` (지금 인접 diff의 라인 유지).
머지 커밋이면 이 라인에 `Parent 1 · <sha> ▾` 선택 칩이 붙는다 — 원래 파일 pane 위에 있던
parent 선택기의 새 자리다.

### 2.4 History pane

- `FullHistoryView` 재사용. 위치만 바뀐다: diff의 반대편이 아니라 **미리보기 pane 바로 옆**
  (2.1 표). 폭은 `FullDiffColumnWidths.history` 그대로 (기본 280, 드래그 180–420, 설정 저장).
- 새 요소: 얇은 헤더 스트립 `History · <파일명> · <개수>` — 열 구조를 읽게 하는 1안 장치.
- History 항목을 고르면 그 커밋의 이 파일 diff로 이동하고, **미리보기 pane도 그 커밋으로
  전환**된다(작성자·파일 목록 포함). 타임라인 선택도 따라간다 — 복귀했을 때 미리보기와
  타임라인이 서로 다른 커밋을 가리키는 일이 없어야 한다.
- History 토글을 끄면 pane이 접히고 diff가 그 폭을 흡수한다.

### 2.5 집중 모드

집중 모드는 History pane과 미리보기 pane을 함께 숨겨 diff만 남긴다. 다시 누르면(또는 ⇧F)
원래 배치로 돌아온다. 원판의 "탐색 패널 숨김" 의미를 새 구조에 맞게 옮긴 것.

## 3. 동작

- **진입**: ① 미리보기 파일 목록에서 파일 클릭 ② 툴바 Full Diff 버튼 / ⌘D (선택된 파일이
  없으면 첫 파일 선택) ③ 미리보기 pane 안의 Full Diff 버튼(`preview-full-diff`) — 셋 다 같은
  모드로 들어간다.
- **복귀**: esc · 헤더의 ← · ⌘D 재입력. 타임라인+사이드바가 돌아오고 미리보기 pane은 그대로
  남는다. 스크롤·선택 상태 복원은 지금 인접 diff 닫기와 같다.
- **파일 이동**: ⌘↑/↓가 미리보기 목록의 선택을 옮기고 diff가 따라온다 (기존 동작 유지).
  diff 내용 스크롤은 ⇧⌘↑/↓.
- **키보드**: Full Diff의 단축키 전부 유지 — ⌘1 Diff · ⌘2 Blame · ⌘3 History · ⌘U 레이아웃 ·
  ⇧A 알고리즘 · ⇧Space 공백 무시 · ⇧L 줄바꿈 · ⇧H Hunk · ⇧F 집중 모드. ⌘ 누르고 있으면
  단축키 힌트 표시도 그대로.

## 4. 구현 구조

### 4.1 재사용 매핑

| 부품 | 재사용 방식 |
|---|---|
| `FullDiffSessionController` / `FullDiffSessionState` | 그대로. 소유자만 route → 타임라인 상태로 이동 |
| `GlobalFileBar` · `GlobalDiffToolbar` | 그대로. `onBack` = diff 모드 닫기 |
| unified/side-by-side/blame 뷰, `FullDiffMinimap`, 문법 강조 | 그대로 |
| `FullHistoryView` | 그대로. 배치만 2.1 규칙, 헤더 스트립 추가 |
| `FullDiffResizablePane` | History pane 폭 조절에 그대로 |
| `ExternalEditorService`, 커밋 메시지 캐시 | 그대로 |
| 미리보기 pane (`_preview()`) | 변경 없음 — 파일 목록이 곧 내비게이션 |

### 4.2 새로 만드는 것

`DiffScreen`(2058줄)에서 **`FullDiffWorkspace` 위젯을 추출**한다: 헤더 2줄 + 커밋 라인 +
콘텐츠(diff/blame) + 미니맵 + History pane. route도, 파일 목록 pane도, Scaffold도 없이 어떤
칸에든 끼울 수 있는 순수 위젯. 타임라인의 `_workspaceLayout`이 diff 모드일 때 타임라인 대신
이 위젯을 배치한다. 컨트롤러 수명은 타임라인이 쥔다(파일이 바뀌어도 세션 유지, 커밋이 바뀌면
재생성 — 지금 route 진입과 같은 규칙).

### 4.3 삭제 대상

- `_openFullDiff`의 `MaterialPageRoute` 경로와 `_FullDiffRouteSession`
- `DiffScreen`의 파일 목록 pane (`_commitFiles`, `_ResponsiveDiffBody`의 files 부분,
  `FullDiffColumnWidths.files` 사용처) — 추출 후 남는 껍데기 전부
- `timeline.dart`의 인접 미리보기 diff: `_adjacentPreviewDiff`, `_previewDiffOpen`,
  `_previewDiff*` 폭/높이 필드와 리사이저, `preview-diff-*` 키의 위젯들
- 설정 `previewDiffLeftWidth` / `previewDiffRightWidth` / `previewDiffBottomHeight` —
  읽기는 무시, 쓰지 않음 (파싱 호환만 유지). `FullDiffColumnWidths.files`도 같은 취급

### 4.4 설정

- `FullDiffPreferences`(뷰·레이아웃·scope·알고리즘·공백·줄바꿈·집중 모드) 그대로 저장.
- History pane 폭은 `FullDiffColumnWidths.history` 그대로.
- 새 키 없음.

## 5. 시각 충실도 — 검수 기준

시안(`docs/unified-diff-mockup.html`)과 앱이 같은 토큰을 써야 한다. 시안 하단 충실도 표가
검수 기준표다: diff 팔레트(`full_diff_theme.dart` 전 토큰), 소스 폰트 Menlo 12/행높이 21/
거터 10/줄번호 폭 74, 컨트롤 높이 24·행 상하 패딩 4·컨트롤 간격 5·라운드 12.5·선택=흰 배경,
배지 필 Menlo 11, 경로 칩 #3A3A3A 라운드 7.5, History 카드 11px/Menlo 10px, 미니맵 폭 18과 5색.

검증 루프 (사용자 요구사항): 구현 후 실행 화면을 시안과 대조 → 다른 항목을 표로 정리 →
재작업 지시 → 같아질 때까지 반복. 토큰 수준은 위젯 테스트로 고정하고, 배치·비례는 스크린샷
대조로 본다.

## 6. 테스트 설계 (TDD 계약 — Fable 작성, 구현자는 단언 수정 금지)

1. **진입**: 미리보기에서 파일을 고르면 워크스페이스에 `FullDiffWorkspace`가 나타나고
   타임라인·사이드바가 사라진다. 미리보기 pane은 남는다.
2. **헤더 완전성**: `file-path-chip` · `file-summary-badge` · `encoding-badge` · `focus-mode` ·
   `open-editor` · `main-view-controls`(Diff|Blame) · `diff-algorithm-label`+선택기 ·
   `ignore-whitespace` · `wrap-lines` · `change-counter` · 레이아웃 세그먼트 · `hunk-toggle` ·
   `history-toggle` · 미니맵이 모두 존재한다.
3. **배치 — 우측**: diff.left < history.left < preview.left (History 켠 상태).
4. **배치 — 좌측**: preview.left < history.left < diff.left.
5. **배치 — 하단**: diff.bottom ≤ history.top, 아래 줄에서 preview.left < history.left.
6. **History 토글**: 끄면 pane이 사라지고 diff 폭이 그만큼 늘어난다.
7. **집중 모드**: History·미리보기가 숨고 diff만 남는다. 해제하면 복원.
8. **복귀**: esc/←/⌘D 로 타임라인+사이드바 복귀, 미리보기 유지.
9. **파일 이동**: ⌘↓가 미리보기 선택을 다음 파일로 옮기고 diff 경로 칩이 따라온다.
10. **History 선택**: 항목을 고르면 diff와 미리보기 pane이 그 커밋으로 전환되고,
    복귀 시 타임라인 선택도 그 커밋이다.
11. **머지 커밋**: parent 선택 칩이 커밋 라인에 나타나고 전환이 동작한다.
12. **route 부재**: Full Diff 버튼이 더 이상 Navigator push를 하지 않는다.
13. **토큰 고정**: diff 소스 스타일(Menlo 12/21), History 카드 스타일, 팔레트 토큰 사용을
    단언 (기존 `full_diff_theme_palette_test` 계열 확장).
- 기존 `full_diff_workspace_test.dart`(DiffScreen 레벨)는 임베드 워크스페이스 대상으로
  이전한다. 부품 테스트(헤더·미니맵·컨트롤러·문법 등)는 그대로 남는다.

## 7. 작업 분할 (Opus 지시 단위)

- **W1 — 추출**: `DiffScreen` → `FullDiffWorkspace` 분리. 파일 pane 제거, route 껍데기 제거,
  기존 full diff 테스트 이전. 이 단계에서는 아직 타임라인에 연결하지 않는다 (기존 route가
  새 위젯을 감싸 그대로 동작).
- **W2 — 임베드**: 타임라인 `_workspaceLayout`에 diff 모드 추가 (placement 3종 배치),
  진입·복귀 배선, 인접 미리보기 diff 삭제, route 삭제.
- **W3 — 결합 동작**: History 위치·헤더 스트립, 미리보기/타임라인 커밋 동기화, 집중 모드
  새 의미, parent 칩 이동, 설정 정리.
- **W4 — 충실도 검수**: 실행 화면 vs 시안 대조, 차이 재작업, 전체 스위트·analyze·빌드.

순서는 W1 → W2 → W3 → W4. 각 단계 계약 테스트 선행(red), 구현(green), 적대적 리뷰 후 통과.

## 8. 리스크

- `DiffScreen` 추출은 2천 줄 이동이다 — W1에서 기능 변화 없이 옮기기만 하고, 기존 테스트가
  그대로 도는 것을 완료 조건으로 삼는다.
- 인접 diff 삭제는 `preview-diff-*`를 참조하는 기존 테스트를 깨뜨린다 — 계약 테스트로
  대체하는 목록을 W2 지시에 명시한다.
- 하단 배치는 세로 공간이 좁다 — 헤더 2줄 Wrap이 3줄로 접히는 폭에서도 diff 본문이 남는지
  좁은 창 테스트로 고정한다.
