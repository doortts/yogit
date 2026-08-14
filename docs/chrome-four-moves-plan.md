# 크롬 정리 네 가지 — 개발 계획

2026-08-14 · 시안: `docs/chrome-four-moves-design.md` (확정) ·
목업: `docs/chrome-four-moves-mockup.html`

확정 시 변경: 4번의 텍스트 세그먼트는 만들지 않는다 — 미리보기 머리줄에는 글리프
세그먼트만 선다.

## 진행 방식

단계마다 **구현(Opus 서브에이전트) → 적대적 리뷰(내가) → 필요하면 xHigh 재작업 → 커밋**.
리뷰가 보는 것: 시안과의 일치, 코드 품질, 결과물의 간결함(더 짧게 되는가), 책임과 권한의
분리(어느 위젯이 무엇을 알아야 하는가), 테스트가 진짜 계약을 지키는가.

단계 순서는 의존성이 정한다. A와 B가 툴바 우측 무리를 비우고 나야 C의 중앙·접힘 규칙을
확정된 좌우 폭 위에서 잴 수 있다. D는 독립이지만 `timeline.dart`를 C와 함께 건드리므로
뒤에 세운다.

| 단계 | 내용 | 주로 건드리는 파일 |
|---|---|---|
| A | 콘솔 버튼 → 상태바, `>_` 글리프 | `timeline_chrome.dart` |
| B | 배치 세그먼트 → 미리보기 머리줄, 글리프화 | `timeline_chrome.dart`, `timeline_preview_pane.dart` |
| C | 워드마크 창-중앙 + 접힘 사다리 | `timeline.dart`, `timeline_chrome.dart` |
| D | ⌘, + 마지막 설정 섹션 기억 | `settings.dart`, `main.dart`, `timeline.dart` |

## A. 콘솔 버튼을 상태바로

**옮긴다**: [timeline_chrome.dart:151](../lib/timeline_chrome.dart#L151)의
`ListenableBuilder` + `IconButton`을 상태바 우측
([timeline_chrome.dart:462](../lib/timeline_chrome.dart#L462)) 프로필 칩 **왼쪽**으로.

**모양**: `Icons.terminal` 대신 `>_` 텍스트 글리프 (모노 폰트, 11px, letterSpacing 0.5).
상태바 글자 크기(10–11px)에 맞춘다. 호버에 `_palette.raised` 배경.

**색 규칙은 그대로**: 열림 `_palette.text` · 실행 중 `behindOrange` · 평소 `_palette.muted`.
툴팁 `콘솔 (⌘\`)`도 그대로. ⌘\` 핸들러는 손대지 않는다.

**키**: `toolbar-console` → `console-toggle`. 툴바를 떠났으니 이름도 떠난다.
`test/console_dock_test.dart`의 세 군데를 함께 고친다.

**완료 조건**: 툴바 우측은 `모니터링 · 미리보기 컨트롤 · 설정`만. 상태바에서 콘솔이
열리고 닫힌다. 실행 중 색이 상태바에서도 산다.

## B. 배치 세그먼트를 미리보기 머리줄로

**옮긴다**: `preview-placement` 컨테이너와 세 개의 `_placementButton`을
미리보기 헤더([timeline_preview_pane.dart:236](../lib/timeline_preview_pane.dart#L236))
우측으로. `미리보기` 캡션 텍스트와 `showPreviewLabel` 분기는 은퇴한다.

**글리프**: 라벨 텍스트 대신 pane 위치를 그리는 14×11 `CustomPaint` — 바깥 사각형
(테두리)과 채워진 판 하나. 좌측 = 왼쪽 세로 판, 우측 = 오른쪽 세로 판, 하단 = 아래
가로 판. 현재 배치는 `_palette.selectedRow` 위에 흰색, 나머지는 muted.
툴팁으로 `좌측`/`우측`/`하단`을 남긴다 — 글리프만으로는 처음 보는 사람이 못 읽는다.

**닫기**: 세그먼트 오른쪽에 `✕` (`preview-close`). 지금 `_togglePreview()`를 부른다.

**툴바에 남는 것**: 여닫기 토글(`preview-toggle`) 하나. 미리보기가 닫히면 머리줄도
사라지니 다시 여는 문은 툴바에 있어야 한다.

**키 유지**: `preview-placement`, `placement-$placement`, `placement-hover-$placement`는
그대로 — 자리만 옮기고 계약은 지킨다. 테스트는 캡션·순서 단언만 고친다
(`app_test.dart` 14965 근처, 15313 근처, 243 근처).

**책임 경계**: 헤더는 배치를 *고르는 UI*만 그린다. 무엇이 선택됐는지와 무엇을 할지는
지금처럼 `_activePlacement` / `widget.onPreviewPlacementChanged` /
`_previewController.setPreview`가 답한다 — 상태를 헤더로 내리지 않는다.

## C. 워드마크를 창 중앙으로

**구조**: `_toolbar()`의 `Padding` 안을 `Stack`으로 바꾼다.

```
Stack(
  children: [
    _toolbarRow(...),                       // 지금 그대로, 워드마크만 빠진 채
    Positioned.fill(child: IgnorePointer(child: Align(center, wordmark))),
  ],
)
```

`_dragAndWordmark()`는 워드마크를 내려놓고 드래그 영역만 남는다 (`toolbar-drag` 유지).

**접힘 사다리** — 창 폭이 아니라 **중앙에 남은 자리**로 잰다. 툴바 `LayoutBuilder`가 아는
전체 폭과, 좌측 무리의 실제 끝·우측 무리의 실제 시작이 필요하다. 측정 대신 계산으로:
좌측 끝은 선택기 폭 계산([timeline_chrome.dart:38](../lib/timeline_chrome.dart#L38))이
이미 내놓는 값이고, 우측 무리는 A·B 뒤 고정 폭에 가깝다 — 폭을 상수로 두지 말고
`_toolbarRight`가 자기 폭을 셈해 돌려주게 한다. 26px가 서면 26, 아니면 20, 그것도
안 서면 숨긴다. 여유는 양쪽 24px.

**하지 않을 것**: 렌더 후 `GlobalKey` 측정 → `setState` (프레임이 한 번 늦고 흔들린다).
폭을 하드코딩한 상수 (버튼이 하나 늘면 조용히 틀어진다).

**테스트**: `app_test.dart` J3(18618)을 창-중앙 기준으로 다시 쓴다 — 워드마크 중심이
툴바 중심과 ±1px, 좌우 무리와 24px 이상 떨어짐, 좁히면 20px → 사라짐, 드래그 폭 200 유지.

## D. 설정: ⌘, + 마지막 섹션

**⌘,**: [timeline.dart:1518](../lib/timeline.dart#L1518)의 ⌘\` 옆에
`LogicalKeyboardKey.comma` + `shortcutModifierHeld` → `widget.onOpenSettings?.call()`.
텍스트 편집 중에도 열리는지는 ⌘\`와 같은 규칙을 따른다.

**마지막 섹션**: `AppSettings`에 `settingsSection` (문자열 저장, enum 복원) 추가 —
`copyWith` · `fromMap` · `toMap` · `==` · `hashCode` 다섯 자리를 모두 채운다.
`SettingsScreen`은 `settings.settingsSection`으로 시작하고, 탭을 누를 때
`onChanged`로 기록한다. 모르는 이름이면 기본값(`gitIntegrations`).

**경계**: `_SettingsSection`은 지금 private이다. 저장을 위해 public으로 열되, 저장값은
`name` 문자열이고 파싱은 `AppSettings`가 맡는다 — 화면이 저장 포맷을 알 필요는 없다.

**테스트**: ⌘,로 설정이 열린다. 섹션을 바꾸면 설정이 저장된다. 저장된 섹션으로 다시
열린다. 모르는 값은 기본값으로 떨어진다.

## 공통

- 매 단계 `flutter analyze` + `flutter test` 전체 통과. 골든은 full-diff QA뿐이라
  이 네 가지와 무관하지만, 깨지면 원인을 보고 판단한다.
- 커밋은 단계마다 하나. 메시지는 저장소 관례(왜 → 무엇).
- 새 설정 키는 D의 `settingsSection` 하나뿐. 나머지는 자리 이동이라 저장값이 늘지 않는다.
