# Full Diff 최종 검수

2026-07-27에 승인 이미지 13장과 macOS 앱을 기준으로 확인했다.
기준 이미지 파일은 이름만 `.png`이고 실제 내용은 JPEG라서 차이 도구는
파일 시그니처로 형식을 판별한다. JPEG 압축과 Flutter 글꼴
래스터라이징에서 생기는 픽셀 차이는 아래 수치에 포함했다. 수동 판정에서는
구성 요소의 위치·크기·줄바꿈·말줄임·색·테두리를 각각 확인했다. 기준
HTML은 고정된 예시 행을 그리지만 구현 캡처는 검수용 데이터를 실제
위젯으로 렌더링하므로 행의 개수와 문구가 다른 구간은 픽셀 일치 판정에서
제외했다.

## 이미지 판정

좌우 비교 이미지는 왼쪽이 기준, 오른쪽이 구현이다. 캡처 크기와 카드
영역은 기준 이미지와 같다. 일반 화면의 641px 카드 높이와 상세 화면의
596px 높이는 검수용 하네스에만 적용했다. 실제 앱은 창에서 쓸 수 있는
높이를 모두 사용한다.

| 상태 | 기준 | 구현 | 차이 | 메뉴·순서 | 색·테두리 | 크기·배치 | 판정 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 00 Hunk | [기준](../../specs/assets/full-diff-qa/00-overview-hunk.png) | [구현](actual/00-overview-hunk.png) | [차이](diff/00-overview-hunk.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 탐색 2열과 두 번째 Hunk 배치 확인 |
| 01 Inline | [기준](../../specs/assets/full-diff-qa/01-diff-inline.png) | [구현](actual/01-diff-inline.png) | [차이](diff/01-diff-inline.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 선행 문맥, Hunk 제목, 활성 구간 순서 확인 |
| 02 Split | [기준](../../specs/assets/full-diff-qa/02-diff-split.png) | [구현](actual/02-diff-split.png) | [차이](diff/02-diff-split.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 이전·이후 행 두 열과 가운데 경계 확인 |
| 03 File | [기준](../../specs/assets/full-diff-qa/03-file-view.png) | [구현](actual/03-file-view.png) | [차이](diff/03-file-view.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 전체 파일과 활성 변경 위치 확인 |
| 04 Blame | [기준](../../specs/assets/full-diff-qa/04-blame-view.png) | [구현](actual/04-blame-view.png) | [차이](diff/04-blame-view.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 줄 번호, 80px 메타데이터, 소스 순서 확인 |
| 05 History | [기준](../../specs/assets/full-diff-qa/05-history-view.png) | [구현](actual/05-history-view.png) | [차이](diff/05-history-view.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 제목 아래 작성자·경과 시간 배치 확인 |
| 06 집중 모드 | [기준](../../specs/assets/full-diff-qa/06-focus-mode.png) | [구현](actual/06-focus-mode.png) | [차이](diff/06-focus-mode.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 탐색 열 제거, 머리글 정렬, 본문 확장 확인 |
| 07 공백 무시 | [기준](../../specs/assets/full-diff-qa/07-ignore-whitespace.png) | [구현](actual/07-ignore-whitespace.png) | [차이](diff/07-ignore-whitespace.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 선택 상태와 공백 행 제거 확인 |
| 08 줄바꿈 | [기준](../../specs/assets/full-diff-qa/08-wrap-lines.png) | [구현](actual/08-wrap-lines.png) | [차이](diff/08-wrap-lines.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 선택 상태, 한 개의 줄 번호, 긴 소스 줄바꿈 확인 |
| 09 다음 변경 | [기준](../../specs/assets/full-diff-qa/09-next-change.png) | [구현](actual/09-next-change.png) | [차이](diff/09-next-change.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 상세 화면 `3 / 7`, 한 줄 조작부, 미니맵 확인 |
| 10 Histogram | [기준](../../specs/assets/full-diff-qa/10-algorithm-histogram.png) | [구현](actual/10-algorithm-histogram.png) | [차이](diff/10-algorithm-histogram.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — Histogram 상태, 두 번째 Hunk, 미니맵 확인 |
| 11 650px | [기준](../../specs/assets/full-diff-qa/11-responsive-650.png) | [구현](actual/11-responsive-650.png) | [차이](diff/11-responsive-650.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 파일 경로와 통계를 두 줄로 배치하고 파일 열 유지 |
| 12 480px | [기준](../../specs/assets/full-diff-qa/12-responsive-480.png) | [구현](actual/12-responsive-480.png) | [차이](diff/12-responsive-480.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과 — 두 탐색 열 제거, 한 줄 조작부, 본문 전폭 사용 확인 |

승인 이미지가 작업 표보다 우선한다. 승인 이미지에서 Split이 선택된
03·04·05·07·08은 Split 상태로 캡처했다. 검수 하네스는 Flutter SDK의
Material Icons와 Roboto, macOS의 Menlo와 Apple SD Gothic Neo를
불러오며 Menlo에 없는 글자는 앱에 포함된 D2Coding으로 표시한다.

## 픽셀 차이

`changed`는 RGB 가운데 한 채널이라도 다른 픽셀 수다. `mean RGB`는
전체 픽셀과 세 채널을 합친 평균 절대 차이다. 기준 이미지가 손실 압축된
JPEG라서 넓고 단색인 배경도 미세한 차이로 집계된다.

| 이미지 | 크기 | changed | changed % | mean RGB | max RGB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 00-overview-hunk | 782×842 | 253,788 | 38.5436 | 9.0307 | 255 |
| 01-diff-inline | 782×842 | 339,916 | 51.6241 | 15.8542 | 255 |
| 02-diff-split | 1070×842 | 442,279 | 49.0908 | 15.0808 | 255 |
| 03-file-view | 1070×842 | 329,664 | 36.5911 | 11.1614 | 255 |
| 04-blame-view | 1070×842 | 350,900 | 38.9482 | 12.5168 | 255 |
| 05-history-view | 1070×842 | 273,172 | 30.3208 | 7.4224 | 255 |
| 06-focus-mode | 1070×842 | 183,644 | 20.3836 | 3.3508 | 255 |
| 07-ignore-whitespace | 1070×842 | 447,836 | 49.7076 | 15.5643 | 255 |
| 08-wrap-lines | 1070×842 | 475,223 | 52.7475 | 16.3073 | 255 |
| 09-next-change | 1280×720 | 654,846 | 71.0553 | 8.9486 | 240 |
| 10-algorithm-histogram | 1280×720 | 654,612 | 71.0299 | 8.8465 | 248 |
| 11-responsive-650 | 650×549 | 158,025 | 44.2833 | 11.4639 | 255 |
| 12-responsive-480 | 480×549 | 105,341 | 39.9746 | 9.8100 | 255 |

## 구문 강조 성능과 앱 크기

DRL 첫 Hunk의 12줄을 30번 강조했다. 첫 실행은 16,136µs, p95는
2,706µs로 50ms 기준을 통과했다.

| 빌드 | 압축 크기 |
| --- | ---: |
| `YOGIT_EXTENDED_SYNTAX=false` | 23,138,651 bytes |
| `YOGIT_EXTENDED_SYNTAX=true` | 23,315,244 bytes |
| 증가량 | 176,593 bytes |

증가량은 1,048,576바이트 기준보다 작다. 두 기준을 모두 통과했으므로
`extendedSyntaxEnabled`의 기본값은 `true`로 유지했다. 포함한 확장
문법은 `perl`, `r`, `julia`, `scala`, `elixir`, `erlang`, `haskell`,
`ocaml`, `fsharp`, `clojure`, `lisp`, `scheme`, `verilog`, `vhdl`,
`x86asm`, `armasm`, `fortran`, `matlab`, `qml`, `latex`다.

## DRL 실제 앱 확인

계획에 적힌 `40aff6d/src/drlua.pas` 조합은 실제 저장소에 없다.
`40aff6d`가 바꾼 파일은 `src/drlgfxio.pas`, `src/drlwindow.pas`,
`tests/test_drlwindow.pas`다. 따라서 같은 커밋의
`src/drlgfxio.pas`를 주 검증 파일로 사용했다.

계획의 `flutter run -d macos -- /Users/doortts/repos/drl` 명령은 현재
Flutter에서 저장소 경로를 Dart 진입점으로 해석해 실패했다. 같은
인수를 앱에 전달하도록 빌드 바이너리를 `--repo
/Users/doortts/repos/drl`로 실행했다.

| 항목 | 결과 | 확인 내용 |
| --- | --- | --- |
| 40aff6d 파일 열기 | 조건부 통과 | 계획에 적힌 파일이 없어 실제 변경 파일인 `src/drlgfxio.pas`로 확인 |
| File·Diff·Blame·History | 통과 | 네 화면을 차례로 열고 머리글과 콘텐츠가 같은 커밋·파일을 가리키는지 확인 |
| Hunk·Inline·Split | 통과 | 세 표시 방식을 차례로 선택하고 내용과 미니맵을 확인 |
| 이전·다음 | 통과 | 카운터와 미니맵이 `1 / 9`와 `2 / 9` 사이에서 함께 이동 |
| Histogram | 통과 | 메뉴에서 Histogram의 선택 표시 확인 |
| 공백 무시·줄바꿈·집중 모드 | 통과 | 각 기능을 켰다가 끄고 행 구성과 탐색 패널 복원을 확인 |
| History 포커스 후 Enter | 수동 미검증 | Computer Use에서 Flutter 행 포커스를 안정적으로 지정하지 못함. `history focus does not select until enter` 자동 테스트는 통과 |
| Settings 초기값 두 가지 | 통과 | Hunk와 `Full file focused on first change`로 새 Full Diff를 각각 열어 초기 화면 확인. 검수 뒤 Hunk로 복원 |
| 작업 트리 편집기로 열기 | 통과 | `scripts/package-macos-release.sh`를 눌러 TextEdit가 같은 절대 경로와 파일 내용을 연 것을 확인 |
| 651·650·481·480px | 통과 | 651은 두 탐색 열, 650은 파일 열만, 481은 파일 열, 480은 콘텐츠만 표시. 실제 캡처 너비도 각각 확인 |

반응형 수동 검수 중 macOS 창의 최소 너비가 960px라서 경계에 도달하지
못하는 문제를 찾았다. 최소 너비를 480px로 낮추고 자동 테스트로
고정한 뒤 네 경계를 다시 확인했다.
