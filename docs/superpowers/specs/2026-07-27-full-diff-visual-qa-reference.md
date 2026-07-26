# Full Diff 시각 검수 기준

## 기준 원본

- 저장소에 보관한 편집용 원본:
  [`assets/full-diff-qa/full-diff-redesign.html`](assets/full-diff-qa/full-diff-redesign.html)
- 브라우저에서 바로 열 수 있는 독립 원본:
  [`assets/full-diff-qa/full-diff-redesign-direct.html`](assets/full-diff-qa/full-diff-redesign-direct.html)
- 사용자가 승인한 기본 화면:
  [`assets/full-diff-qa/user-approved-default.png`](assets/full-diff-qa/user-approved-default.png)
- 기본 검수 상태: `Diff`와 `Hunk` 선택
- 기준 이미지 폴더:
  `docs/superpowers/specs/assets/full-diff-qa`

첨부 스크린샷과 대화형 원본이 다르면 첨부 스크린샷의 선택 상태를
우선합니다. 따라서 원본 HTML의 초기 `Split` 상태 대신 `Hunk` 상태를
기본 화면으로 사용합니다.

## 기능별 기준 이미지

| 파일 | 검수 대상 |
| --- | --- |
| `00-overview-hunk.png` | 전체 구성, 두 줄 머리글, 세 열 본문, `Diff`·`Hunk` 선택 |
| `01-diff-inline.png` | 문맥을 포함한 한 열 Inline 표시 |
| `02-diff-split.png` | 이전·새 내용을 나란히 보여 주는 Split 표시 |
| `03-file-view.png` | 결과 파일 전체를 보여 주는 File 화면 |
| `04-blame-view.png` | 각 행 앞에 커밋과 작성자를 붙인 Blame 화면 |
| `05-history-view.png` | 파일 경로의 변경 이력을 보여 주는 History 화면 |
| `06-focus-mode.png` | 탐색 열을 숨기고 콘텐츠만 넓히는 집중 모드 |
| `07-ignore-whitespace.png` | 공백만 바뀐 행을 제외한 상태 |
| `08-wrap-lines.png` | 긴 소스 행을 줄바꿈한 상태 |
| `09-next-change.png` | 도구·콘텐츠 상세: `3 / 7`과 실제 세 번째 Hunk가 함께 바뀐 상태 |
| `10-algorithm-histogram.png` | 도구·콘텐츠 상세: 내부 선택은 Histogram이고 닫힌 메뉴 이름은 `diff 알고리즘`인 상태 |
| `11-responsive-650.png` | 650px에서 주변 커밋 열을 숨긴 상태 |
| `12-responsive-480.png` | 480px에서 콘텐츠만 남긴 상태 |

`00-overview-hunk.png`와 `01-diff-inline.png`는 782×842px,
`02-diff-split.png`부터 `08-wrap-lines.png`까지는 1070×842px입니다.
`09-next-change.png`와 `10-algorithm-histogram.png`은 기능 상태를
분명하게 비교하기 위해 탐색 열과 첫 번째 머리글을 제외한
1280×720px 상세 이미지입니다. 반응형 기준인 `11-responsive-650.png`는
650×549px, `12-responsive-480.png`는 480×549px입니다.
`user-approved-default.png`는 1468×1098px입니다. 구현 화면은 비교할
이미지의 기록된 픽셀 크기와 같은 크기로 캡처합니다.

## 검수 규칙

- 메뉴 이름, 표시 순서, 선택 상태와 아이콘은 기준 이미지와 같아야
  합니다.
- 단색 면, 테두리, 강조색은 기준 이미지에서 읽은 색상값과 같아야
  합니다.
- 구성 요소의 위치와 크기는 CSS 논리 픽셀 기준 1px보다 크게 벗어나면
  실패로 봅니다.
- 운영체제별 글꼴 안티앨리어싱 차이는 허용하지만 글꼴 종류, 크기,
  굵기와 줄 높이는 같아야 합니다.
- 내용이 실제 저장소 데이터에 따라 달라지는 경로, SHA, 행 수와 소스
  문자열은 비교 대상에서 제외합니다. 정렬, 말줄임, 줄바꿈 방식은
  비교합니다.
- `09`와 `10`은 보이는 도구 모음과 콘텐츠만 비교합니다. 나머지 화면
  구성은 `00`부터 `08`까지의 이미지로 판정합니다.
- `10`의 Histogram 선택 여부는 이미지에 표시되지 않으므로 위젯
  테스트로 확인합니다. 이미지에서는 선택 뒤에도 닫힌 메뉴 이름이
  `diff 알고리즘`으로 유지되고 hover·tooltip 같은 일시 상태가 없는지
  확인합니다.
- 구현 결과는 각 기준 상태와 같은 화면 크기로 캡처합니다. 기준 이미지,
  구현 이미지와 차이 이미지를 함께 남깁니다. 허용 범위 밖의 차이가
  있으면 기능 완료로 처리하지 않습니다.
- 승인 없이 색상, 메뉴 이름, 구성 요소, 반응형 기준을 바꾸지 않습니다.
