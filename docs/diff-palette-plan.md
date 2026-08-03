# GitHub Dark diff 색상 — 작업 설계

[diff-pallete-design.md](diff-pallete-design.md)의 스펙을 코드 변경 단위로 나눈 문서다. 스펙이 무엇을 바꿀지 정했다면 이 문서는 어디를 어떤 순서로 바꿀지 정한다. 색상 값과 제외 범위는 스펙을 따르며 여기서 다시 정하지 않는다.

## 현재 코드 지형

팔레트는 이미 `full_diff_theme.dart` 한 곳에 상수로 모여 있다. 스펙이 요구하는 "단일 기준"은 새로 만들 것이 아니라 값만 바꾸면 되는 상태다. 다만 세 곳이 이 기준 밖에 있다.

| 위치 | 현재 상태 | 스펙과의 차이 |
|---|---|---|
| `full_diff_theme.dart` | 팔레트 상수 21개 | 값이 GitHub Dark가 아님 |
| `full_diff_code_row.dart` | `switch (line.kind)`로 줄·줄번호 색 선택, `fullDiffWordChange` 하나를 추가·삭제가 공유 | 단어 강조가 추가·삭제 구분 없음 |
| `full_diff_side_by_side_view.dart`의 `_HatchedDiffPainter` | `Color(0xFF353535)`, `Color(0xFF4A4A4A)` 하드코딩 | 중앙 팔레트를 쓰지 않음 |
| `full_diff_minimap.dart` | 추가 표시에 `fullDiffAccent`(파랑), 삭제 표시에 `fullDiffDeletedMark`(주황) | 스펙은 초록 `#3FB950` / 빨강 `#F85149` |

`fullDiffDeletedMark`는 미니맵 외에 `full_diff_unavailable_panel.dart`도 쓴다. 미니맵 색을 스펙에 맞추면서 그 패널의 의미(오류 강조)까지 바꾸지 않도록, 미니맵 전용 상수를 따로 둔다.

## 변경 단위

각 단위는 테스트를 먼저 쓰고 통과시킨다. 단위마다 `flutter test`가 초록인 상태로 끝난다.

### 1. 팔레트 상수

`full_diff_theme.dart`의 값을 스펙 표대로 바꾼다.

- 바꾸는 상수: `fullDiffCanvas`, `fullDiffHeader`, `fullDiffDivider`, `fullDiffMuted`, `fullDiffAddedSource`, `fullDiffAddedGutter`, `fullDiffDeletedSource`, `fullDiffDeletedGutter`, `fullDiffHunkHeader`
- 새로 만드는 상수: `fullDiffAddedWord`, `fullDiffDeletedWord`(Primer 투명도 유지), `fullDiffHatchBackground`, `fullDiffHatchStroke`, `fullDiffMinimapAdded`, `fullDiffMinimapDeleted`
- 없애는 상수: `fullDiffWordChange` — 추가·삭제용 두 상수로 갈라진다

`fullDiffHeader`는 스펙의 "헤더·빈 칸 바탕 `#151B23`"에 해당한다. 툴바와 컨트롤이 함께 쓰는 상수라 값만 바뀌고 쓰임은 그대로다.

테스트: `test/full_diff_theme_palette_test.dart`(신규) — 각 상수가 승인된 값과 같은지, 단어 강조 두 상수가 서로 다른지 검사한다.

### 2. 줄과 단어 색상

`FullDiffCodeRow`가 `DiffLineKind`에 따라 줄 바탕·줄번호 바탕·기호에 더해 단어 강조 색까지 함께 고르도록 바꾼다. 지금 단어 강조는 `_sourceSpans` 안에서 상수를 직접 참조하므로, 줄 종류를 인자로 받아 색을 고르게 한다.

테스트: 추가 줄과 삭제 줄을 각각 렌더링해 단어 강조 `backgroundColor`가 서로 다르고 각각 스펙 값인지 확인한다. 기존 `full_diff_widgets_test.dart`/`full_diff_selectable_row_test.dart`의 줄 배경 검사도 새 값으로 맞춘다.

### 3. hunk 헤더와 빈 칸

`FullDiffHunkHeader`는 이미 `fullDiffHunkHeader`를 쓰므로 1단계로 끝난다. `_HatchedDiffPainter`의 하드코딩 두 색을 새 상수로 교체한다. 빗금 간격 8px과 각도는 건드리지 않는다.

테스트: 빈 칸 페인터가 중앙 팔레트 색을 쓰는지 — 페인터가 private이라 위젯을 통해 `paints` 매처로 배경 사각형 색을 검사한다.

### 4. 미니맵 표시

추가가 있는 hunk는 `fullDiffMinimapAdded`, 삭제만 있는 hunk는 `fullDiffMinimapDeleted`를 쓴다. 활성 표시와 뷰포트 링은 그대로 둔다.

테스트: 추가 hunk와 삭제 전용 hunk를 담은 문서로 `MinimapMarker.color`를 검사한다.

### 5. 시각 회귀

`full_diff_visual_test.dart`의 골든을 갱신한다. 색만 바뀌므로 레이아웃·줄 높이 차이가 없어야 하며, 갱신 전후 이미지 크기가 같은지 확인한다.

## 진행 방식

TDD로 단위마다 red → green을 밟는다. 1단계는 상수 값 검사라 테스트가 곧 스펙의 사본이 된다. 2~4단계는 위젯이 어떤 색을 그리는지 검사하므로, 테스트를 먼저 쓰면 지금 값으로 실패하고 팔레트를 연결하면 통과한다.

색상 값을 테스트와 구현 양쪽에 손으로 적으면 오타가 양쪽에 똑같이 들어가도 초록이 된다. 그래서 1단계 테스트만 값을 문자열로 직접 적고(스펙과 대조하는 유일한 지점), 2~4단계 테스트는 상수를 참조한다.

## 검증

- `flutter test`
- `flutter analyze`
- 전체 diff 시각 테스트로 레이아웃 불변 확인

## 이 문서가 정하지 않는 것

스펙의 제외 범위를 그대로 따른다. 여기에 더해 `fullDiffSelection`, `fullDiffAccent`, `fullDiffChip` 등 diff 줄 바깥의 컨트롤 색은 스펙 표에 없으므로 건드리지 않는다.
