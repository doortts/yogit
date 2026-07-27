# Full Diff 최종 검수

2026-07-27에 기존 승인 이미지 13장, 후속 검수 이미지 5장과 macOS 앱을
기준으로 확인했다. 최종 보완에서 제품 배치가 바뀌어 구현 이미지
00~17을 모두 새로 캡처하고 차이 이미지와 수치도 현재 이미지로 다시
계산했다. 00–04·06–12 기준 이미지는 이름만 `.png`이고 실제 내용은
JPEG라서 차이 도구는 파일 시그니처로 형식을 판별한다. 05·13–17 기준
이미지는 검토를 통과한 Flutter PNG 캡처다. JPEG 압축과 Flutter 글꼴
래스터라이징에서 생기는 픽셀 차이는 아래 수치에 포함했다.

수동 판정에서는 구성 요소의 위치·크기·줄바꿈·말줄임·색·테두리를
확인했다. 기준 HTML은 고정된 예시 행을 그리지만 구현 캡처는 검수용
데이터를 실제 위젯으로 렌더링하므로 행의 개수와 문구가 다른 구간은
픽셀 일치 판정에서 제외했다.

## 이미지 판정

좌우 비교 이미지는 왼쪽이 기준, 오른쪽이 구현이다. 캡처 크기와 카드
영역은 기준 이미지와 같다. 일반 화면의 641px 카드 높이와 상세 화면의
596px 높이는 검수용 하네스에만 적용했다. 00–08·11–12의 16px 바깥
여백도 승인 이미지와 나란히 비교하기 위한 캔버스에만 있다. 제품 셸에는
이 여백을 넣지 않았으며 782px와 480px에서 제품 셸의 왼쪽 좌표가 모두
0인지 별도 자동 테스트로 확인했다. 상세 화면인 09·10도 x=0에서
캡처한다. 실제 앱은 창에서 쓸 수 있는 높이를 모두 사용한다.

| 상태 | 기준 | 구현 | 차이 | 메뉴·순서 | 색·테두리 | 크기·배치 | 판정 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 00 Hunk | [기준](../../specs/assets/full-diff-qa/00-overview-hunk.png) | [구현](actual/00-overview-hunk.png) | [차이](diff/00-overview-hunk.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: 탐색 2열과 두 번째 Hunk 배치 확인 |
| 01 Inline | [기준](../../specs/assets/full-diff-qa/01-diff-inline.png) | [구현](actual/01-diff-inline.png) | [차이](diff/01-diff-inline.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: 선행 문맥, Hunk 제목, 활성 구간 순서 확인 |
| 02 Split | [기준](../../specs/assets/full-diff-qa/02-diff-split.png) | [구현](actual/02-diff-split.png) | [차이](diff/02-diff-split.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: 이전·이후 행 두 열과 가운데 경계 확인 |
| 03 File | [기준](../../specs/assets/full-diff-qa/03-file-view.png) | [구현](actual/03-file-view.png) | [차이](diff/03-file-view.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: 선택한 Hunk 하나의 제목과 결과 쪽 추가 행만 표시되는지 확인 |
| 04 Blame | [기준](../../specs/assets/full-diff-qa/04-blame-view.png) | [구현](actual/04-blame-view.png) | [차이](diff/04-blame-view.png) | 전체 소스와 6개 열 | SHA별 색상선 적용 | Hunk 머리글 없이 줄별 정렬 | 통과: 아바타·줄 번호·제목·날짜·4px 색상선·소스 순서 확인 |
| 05 History | [기준](../../specs/assets/full-diff-qa/05-history-view.png) | [구현](actual/05-history-view.png) | [차이](diff/05-history-view.png) | History 목록과 565px Split 상세의 양쪽 결과 표시 | 기준 상수 적용 | History 작업 영역 약 846px, 목록 280px, 상세 565px와 1px 경계 | 통과: 목록과 양쪽 결과를 유지하면서 현재 시점의 여러 Hunk를 함께 표시 |
| 06 집중 모드 | [기준](../../specs/assets/full-diff-qa/06-focus-mode.png) | [구현](actual/06-focus-mode.png) | [차이](diff/06-focus-mode.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: 탐색 열 제거, 머리글 정렬, 본문 확장 확인 |
| 07 공백 무시 | [기준](../../specs/assets/full-diff-qa/07-ignore-whitespace.png) | [구현](actual/07-ignore-whitespace.png) | [차이](diff/07-ignore-whitespace.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: 선택 상태와 공백 행 제거 확인 |
| 08 줄바꿈 | [기준](../../specs/assets/full-diff-qa/08-wrap-lines.png) | [구현](actual/08-wrap-lines.png) | [차이](diff/08-wrap-lines.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: 선택 상태, 한 개의 줄 번호, 긴 소스 줄바꿈 확인 |
| 09 다음 변경 | [기준](../../specs/assets/full-diff-qa/09-next-change.png) | [구현](actual/09-next-change.png) | [차이](diff/09-next-change.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: 상세 화면 `3 / 7`, 한 줄 조작부, 미니맵 확인 |
| 10 Histogram | [기준](../../specs/assets/full-diff-qa/10-algorithm-histogram.png) | [구현](actual/10-algorithm-histogram.png) | [차이](diff/10-algorithm-histogram.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: Histogram 상태, 두 번째 Hunk, 미니맵 확인 |
| 11 650px | [기준](../../specs/assets/full-diff-qa/11-responsive-650.png) | [구현](actual/11-responsive-650.png) | [차이](diff/11-responsive-650.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: 파일 경로와 통계를 두 줄로 배치하고 파일 열 유지 |
| 12 480px | [기준](../../specs/assets/full-diff-qa/12-responsive-480.png) | [구현](actual/12-responsive-480.png) | [차이](diff/12-responsive-480.png) | 일치 | 기준 상수 적용 | 핵심 배치 일치 | 통과: 두 탐색 열 제거, 한 줄 조작부, 초기 가로 이동값 0, Hunk 제목과 313행의 왼쪽 정렬 확인 |
| 13 글자와 뒤로 가기 | [기준](../../specs/assets/full-diff-qa/13-font-and-back.png) | [구현](actual/13-font-and-back.png) | [차이](diff/13-font-and-back.png) | 뒤로 가기→파일 아이콘→경로 순서 | 기존 상단 색 유지 | 파일 이름 13px, 통계·코드·Hunk 12px, 줄 번호 10px | 통과: 최신 글자 크기가 행 안에서 잘리지 않고 32px 뒤로 가기 버튼이 가장 왼쪽에 있음 |
| 14 알고리즘 설명 | [기준](../../specs/assets/full-diff-qa/14-algorithm-tooltip.png) | [구현](actual/14-algorithm-tooltip.png) | [차이](diff/14-algorithm-tooltip.png) | 닫힌 버튼에 Histogram 표시 | 어두운 화면 위에 뜨는 밝은 임시 팝오버의 대비 분명 | diff 머리글과 첫 소스 행 위에 잠시 겹치며 내용은 선명하게 읽힘 | 통과: 선택값, 설정 목적과 반복 코드용 Histogram 설명을 한눈에 읽을 수 있음 |
| 15 표시 불가 | [기준](../../specs/assets/full-diff-qa/15-unavailable-panel.png) | [구현](actual/15-unavailable-panel.png) | [차이](diff/15-unavailable-panel.png) | 경로→통계→UTF-8→사유→옵션 순서 | 속성 칩과 사유의 대비 분명 | 빈 본문 중앙에서 한 줄 정보 흐름 유지 | 통과: `src/drlua.pas`, `M · +12 −4`, `UTF-8`, 변경이 없다는 사유와 현재 옵션을 순서대로 확인 |
| 16 History 상세 | [기준](../../specs/assets/full-diff-qa/16-history-detail.png) | [구현](actual/16-history-detail.png) | [차이](diff/16-history-detail.png) | 선택한 65f4c80과 과거 Hunk 표시 | 선택 행과 변경 행 색 구분 | History 작업 영역 약 846px, 목록 280px, 상세 565px와 1px 경계 | 통과: 목록을 유지한 채 과거 커밋의 파일 목록·통계와 1개 Hunk가 오른쪽에서 함께 바뀜 |
| 17 History Split | [기준](../../specs/assets/full-diff-qa/17-history-detail-split.png) | [구현](actual/17-history-detail-split.png) | [차이](diff/17-history-detail-split.png) | 선택한 65f4c80과 과거 Split 설정 | 추가 배경과 결과 쪽 경계 분명 | History 작업 영역 약 846px, 목록 280px, 상세 565px | 통과: Split의 이전·결과 쪽을 함께 표시하면서 검수용 소스 줄과 빗금 셀 경계를 유지 |

승인 이미지가 작업 표보다 우선한다. 승인 이미지에서 Split이 선택된
03·04·05·07·08은 Split 상태로 캡처했다. 검수 하네스는 Flutter SDK의
Material Icons와 Roboto, macOS의 Menlo와 Apple SD Gothic Neo를
불러오며 Menlo에 없는 글자는 앱에 포함된 D2Coding으로 표시한다.
File은 선택한 Hunk의 제목과 변경 표시를 투영한다. Blame은 Hunk
머리글 없이 전체 소스와 줄별 메타데이터를 나란히 표시한다. 미니맵은
선택한 이전·결과 쪽 소스 범위로 뷰포트를 계산하며 아래 수치는 이
계산을 적용한 현재 캡처 기준이다.

## 픽셀 차이

`changed`는 RGB 가운데 한 채널이라도 다른 픽셀 수다. `mean RGB`는
전체 픽셀과 세 채널을 합친 평균 절대 차이다. 기준 이미지가 손실 압축된
JPEG라서 넓고 단색인 배경도 미세한 차이로 집계된다.

| 이미지 | 크기 | changed | changed % | mean RGB | max RGB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 00-overview-hunk | 782×842 | 293,272 | 44.5402 | 12.1579 | 251 |
| 01-diff-inline | 782×842 | 389,339 | 59.1302 | 18.1361 | 255 |
| 02-diff-split | 1070×842 | 471,138 | 52.2940 | 16.4181 | 255 |
| 03-file-view | 1070×842 | 374,459 | 41.5631 | 12.2910 | 255 |
| 04-blame-view | 1070×842 | 398,103 | 44.1875 | 14.3329 | 255 |
| 05-history-view | 1070×842 | 277,582 | 30.8103 | 13.6445 | 255 |
| 06-focus-mode | 1070×842 | 207,269 | 23.0059 | 5.3399 | 255 |
| 07-ignore-whitespace | 1070×842 | 477,264 | 52.9740 | 16.9156 | 255 |
| 08-wrap-lines | 1070×842 | 504,262 | 55.9707 | 18.0182 | 255 |
| 09-next-change | 1280×720 | 665,347 | 72.1948 | 9.1519 | 239 |
| 10-algorithm-histogram | 1280×720 | 664,894 | 72.1456 | 9.1538 | 248 |
| 11-responsive-650 | 650×549 | 182,010 | 51.0046 | 17.1530 | 253 |
| 12-responsive-480 | 480×549 | 124,727 | 47.3311 | 16.2315 | 253 |
| 13-font-and-back | 1070×842 | 199,609 | 22.1556 | 7.9408 | 255 |
| 14-algorithm-tooltip | 1070×842 | 220,498 | 24.4742 | 15.7527 | 255 |
| 15-unavailable-panel | 1070×842 | 146,040 | 16.2097 | 6.3041 | 255 |
| 16-history-detail | 1070×842 | 178,935 | 19.8609 | 7.6851 | 255 |
| 17-history-detail-split | 1070×842 | 191,471 | 21.2524 | 8.2384 | 255 |

## 구문 강조 성능과 앱 크기

성능 테스트는 기본 테스트 검색 경로 밖인 `benchmark/`에 둬
`flutter test`에 포함되지 않게 했다. 성능 기준은 다음과 같이 한 파일만
동시 실행 수 1로 검사한다.

```sh
flutter test
flutter test --concurrency=1 \
  benchmark/full_diff_syntax_benchmark_test.dart --reporter expanded
```

DRL 첫 Hunk의 12줄을 30번 강조했다. 격리 실행의 첫 실행은 17,098µs,
p95는 1,468µs로 50ms 기준을 통과했다.

| 빌드 | 압축 크기 |
| --- | ---: |
| `YOGIT_EXTENDED_SYNTAX=false` | 23,174,843 bytes |
| `YOGIT_EXTENDED_SYNTAX=true` | 23,349,322 bytes |
| 증가량 | 174,479 bytes |

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
| History 키보드 이동 | 통과 | `file and History lists move selection and focus explicitly`에서 목록 포커스 이동, 화살표 확정 선택과 상세 diff 변경 확인 |
| Settings 초기값 두 가지 | 통과 | Hunk와 `Full file focused on first change`로 새 Full Diff를 각각 열어 초기 화면 확인. 검수 뒤 Hunk로 복원 |
| 작업 트리 편집기로 열기 | 통과 | `scripts/package-macos-release.sh`를 눌러 TextEdit가 같은 절대 경로와 파일 내용을 연 것을 확인 |
| 651·650·481·480px | 통과 | 651은 두 탐색 열, 650은 파일 열만, 481은 파일 열, 480은 콘텐츠만 표시. 실제 캡처 너비도 각각 확인 |

반응형 수동 검수 중 macOS 창의 최소 너비가 960px라서 경계에 도달하지
못하는 문제를 찾았다. 최소 너비를 480px로 낮추고 자동 테스트로
고정한 뒤 네 경계를 다시 확인했다.

## 최종 보완 캡처 18~23

00~17의 기준 이미지는 이전 승인 단계의 시안이고 구현 이미지와
`diff/`는 현재 제품 배치로 다시 생성했다. 2026-07-27 최종 보완에서는
아래 여섯 장을 최신 승인 시안의 최종 판정 기준으로 추가했다. 자세한
근거는 [최종 보완 검토](final-polish-review.md)에 기록했다.

| 상태 | 캡처 | 크기 | 판정 |
| --- | --- | ---: | --- |
| 기본 Diff | [18-final-default](actual/18-final-default.png) | 1070×842 | 통과: 파일+콘텐츠 두 열, 크기, 머리글과 버튼 순서 확인 |
| History | [19-final-history](actual/19-final-history.png) | 1070×842 | 통과: 도움말, 선택 반전, 포커스 테두리, 상세 Split과 잘린 셀의 빗금 확인 |
| Blame | [20-final-blame](actual/20-final-blame.png) | 1440×842 | 통과: 44px 행, 이니셜, 줄 번호, 제목, 날짜, 4px 색상선과 소스 정렬 확인 |
| 집중 모드 | [21-final-focus](actual/21-final-focus.png) | 1070×842 | 통과: 파일 열 제거와 탐색 패널·편집기 버튼 순서 확인 |
| 650px | [22-final-responsive-650](actual/22-final-responsive-650.png) | 650×549 | 통과: 파일+콘텐츠와 조작부 그룹 줄바꿈 확인 |
| 480px | [23-final-responsive-480](actual/23-final-responsive-480.png) | 480×549 | 통과: 콘텐츠 단독 표시와 Hunk 행 정렬 확인 |

승인 시안과 나란히 비교해 버튼 위치, 알고리즘 라벨 분리, 파일 이름
배경, 글자 크기, Blame 열 경계와 반응형 전환을 확인했다. 저장소
데이터에 따라 달라지는 문자열을 제외하면 1px보다 큰 설계 차이는
찾지 못했다. 데스크톱 캡처는 승인 시안의 작업 영역 높이 760px과
파일 열 너비 278px을 사용하며 자동 테스트로 두 값을 고정했다.

최종 시각 테스트는 44개가 통과했다. 기본·축소 syntax 전체 테스트는
각각 452개가 통과했고, 정적 분석은 문제 0, benchmark는 첫 실행
17,098µs와 p95 1,468µs로 기준을 통과했다. macOS 릴리스 앱은 제품
변경을 반영한 커밋 `d264010`에서 다시 빌드했으며 Flutter가 55.3MB로
보고했다.
