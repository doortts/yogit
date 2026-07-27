# Full Diff 최종 보완 검토

## 검토 범위

- 기준 커밋: `71f4759`
- 승인 설계:
  `docs/superpowers/specs/2026-07-27-full-diff-final-polish-design.md`
- 승인 시안:
  `docs/superpowers/specs/assets/full-diff-final-polish-mockup.svg`
- 최종 캡처: `actual/18-final-default.png`부터
  `actual/23-final-responsive-480.png`까지

## 완료 기준과 자동 검증

| 완료 기준 | 구현 파일 | 대표 테스트와 캡처 | 결과 |
| --- | --- | --- | --- |
| 집중 모드가 편집기로 열기 바로 왼쪽에 표시됨 | `lib/full_diff_header.dart` | `global bars keep the approved labels in exact order`, 21 | 통과 |
| 알고리즘 라벨과 현재 선택값이 분리됨 | `lib/full_diff_header.dart` | `algorithm label and selected value remain separate and ordered`, 18·22·23 | 통과 |
| 파일 이름 배경을 없애고 크기를 함께 표시함 | `lib/diff_screen.dart`, `lib/full_diff_header.dart` | `formats file sizes with compact binary units`, 18 | 통과 |
| History 도움말, 선택 반전과 키보드 이동이 동작함 | `lib/full_diff_header.dart`, `lib/full_history_view.dart`, `lib/diff_screen.dart` | `history view explains its purpose after the hover delay`, `history selection and keyboard focus use distinct surfaces`, `file and History lists move selection and focus explicitly`, 19 | 통과 |
| Blame이 줄별 정보와 전체 소스를 나란히 표시함 | `lib/full_blame_view.dart`, `lib/full_source_hunk_map.dart`, `lib/full_diff_code_row.dart` | `blame aligns one complete metadata row with every source line`, 20 | 통과 |
| 주변 커밋 없이 파일과 콘텐츠만 표시함 | `lib/diff_screen.dart` | `responsive width 1070.0`, `responsive width 650.0`, `responsive width 480.0`, 18·22·23 | 통과 |
| 전체 테스트, 분석, benchmark와 릴리스 빌드가 통과함 | 저장소 전체 | 아래 최종 검증 표 | 통과 |

## 파일 크기 조회

`GitRepository.loadFiles()`는 결과 revision의 경로를 묶어
`git ls-tree -rlz`를 한 번 호출합니다. 삭제 파일의 이전 경로가
필요할 때만 선택한 부모를 한 번 더 조회하므로 호출 수는 최대
두 번입니다.

- `loads result blob sizes with one ls-tree query`: 일반 커밋 한 번
- `loads deleted sizes from the selected parent with at most two queries`:
  삭제 파일이 있어도 두 번 이하
- `parses ls-tree sizes for paths containing spaces and tabs`: NUL 구분
  경로 보존
- `keeps files when size metadata lookup fails`: 크기를 읽지 못해도
  파일 목록 유지
- `loads working tree file and symbolic link sizes without blob reads`:
  일반 파일과 심볼릭 링크를 파일 시스템 메타데이터로 계산

최종 fixture는 `3174`, `847`, `6963`, `null` 바이트를 사용합니다.
캡처에서 각각 `3.1 KB`, `847 B`, `6.8 KB`, `—`로 표시되는지
확인했습니다.

## History

History 선택은 controller가 맡고 파일 목록과 History 목록의 포커스는
각각 별도 `FocusNode`가 맡습니다. 19번 캡처에서는 `65f4c80`을 확정
선택하고 다른 행인 `c78b2ff`에 키보드 포커스를 두었습니다. 확정
선택이 바뀌지 않은 상태에서 선택 배경과 1px 목록 포커스 테두리가
함께 보이는지 확인했습니다.

- `Right`: 파일 목록에서 History 목록으로 포커스 이동
- `Left`: History 목록에서 파일 목록으로 포커스 이동
- `Up`·`Down`: 포커스된 목록의 선택 이동
- `Cmd+Up`·`Cmd+Down`: 포커스 위치와 관계없이 변경 파일 이동
- `Option+Up`·`Option+Down`: Hunk 이동
- `Cmd+Shift+Up`·`Cmd+Shift+Down`: 콘텐츠를 48px씩 이동
- `Cmd+Shift+F`: 집중 모드 전환
- `Esc`: 열린 메뉴나 도움말을 먼저 닫고, 그 밖에는 타임라인으로 이동

빗금 셀은 `ClipRect` 안에서 그리며
`hatched cells clip their painter to the cell bounds`가 경계를 고정합니다.

## Blame

20번 캡처는 1440×842에서 원격 아바타를 끄고 이니셜 대체 표시를
사용했습니다. 소스 한 줄마다 Blame 행 하나가 있으며 Hunk 머리글은
소스 사이에 넣지 않습니다.

열 순서는 작성자 아바타, 줄 번호, 제목, 날짜, 4px 색상선, 구문 강조
소스입니다. 긴 제목은 제목 열에서만 말줄임하고 줄 번호, 날짜와
색상선은 계속 표시합니다. fixture의 작성자 메일, 시각과 제목은
`BlameDocument`까지 보존되며 `SC`와 `E` 이니셜, `yyyy-MM-dd` 날짜,
SHA별 색상선을 캡처에서 확인했습니다.

`blame aligns one complete metadata row with every source line`는 행 수,
열 순서, 4px 색상선, 말줄임, 작성자 메일, 날짜, 이니셜 대체 표시와
구문 강조를 함께 검사합니다.

## 18~23 수동 판정

최종 캡처 전용 하네스는 승인 시안의 데스크톱 작업 영역 높이 760px과
파일 열 너비 278px을 사용합니다. 650px과 480px에서는 캡처 높이
549px을 모두 사용합니다.
`final polish canvas uses approved desktop geometry`가 1070px 화면에서
제품 셸의 위치와 크기 `0, 0, 1070, 760`, 파일 열 너비 278px을
고정합니다.

| 이미지 | 크기 | 확인 내용 | 판정 |
| --- | ---: | --- | --- |
| [18 기본 Diff](actual/18-final-default.png) | 1070×842 | 파일+콘텐츠 두 열, 파일 크기, 머리글 두 줄, 버튼 순서, 분리된 알고리즘 라벨 | 통과 |
| [19 History](actual/19-final-history.png) | 1070×842 | 도움말, 선택 반전, 별도 행의 키보드 포커스, 상세 diff | 통과 |
| [20 Blame](actual/20-final-blame.png) | 1440×842 | 이니셜, 줄 번호, 말줄임 제목, 날짜, 4px 색상선, 전체 소스 정렬 | 통과 |
| [21 집중 모드](actual/21-final-focus.png) | 1070×842 | 파일 열 제거, 콘텐츠 확장, 탐색 패널 버튼과 편집기 버튼 순서 | 통과 |
| [22 650px](actual/22-final-responsive-650.png) | 650×549 | 파일+콘텐츠 유지, 조작부 그룹별 줄바꿈 | 통과 |
| [23 480px](actual/23-final-responsive-480.png) | 480×549 | 콘텐츠만 표시, 조작부와 Hunk 행 정렬 | 통과 |

버튼 위치, 색, 글자 크기, 테두리와 간격을 승인 시안과 나란히
확인했습니다. 저장소 데이터에 따라 달라지는 경로, 제목, 날짜와 크기는
판정에서 제외했습니다. 초기 독립 검토에서 발견한 작업 영역 높이와 파일
열 너비 차이를 고치고 다시 캡처했습니다. 재검수에서는 1px보다 큰 설계
차이를 찾지 못했습니다.

## 최종 검증

| 검사 | 결과 |
| --- | --- |
| Dart 포맷 | 50개 파일 검사, 변경 0 |
| 정적 분석 | 문제 0 |
| Full Diff 시각 테스트 | 43개 통과 |
| 기본 전체 테스트 | 451개 통과 |
| `YOGIT_EXTENDED_SYNTAX=false` | 451개 통과 |
| syntax benchmark | 첫 실행 15,018µs, p95 2,272µs, 기준 통과 |
| macOS 릴리스 빌드 | 성공, `yogit.app` 55.3MB |
| 미완성 표식 검색 | 새 표식 없음 |
| 생성자 호환성 검사 | 선택 필드의 기본값 또는 실제 fixture 값 사용 |
| 공백 오류 | 없음 |

처음 전체 분석에서는 이전 Blame 파서 변경에 남아 있던 불필요한
null 단언 연산자 여덟 개가 경고로 잡혔습니다. 분석 결과를 RED로
확인하고 해당 연산자만 제거했습니다. Blame 메타데이터 보존 테스트
두 개와 전체 분석을 다시 실행해 각각 통과와 문제 0을 확인했습니다.

## 독립 검토

독립 검토자가 기준 커밋과 현재 변경을 읽기 전용으로 비교했습니다.
첫 검토에서는 다음 내용을 지적했습니다.

- 중요: 최종 캡처가 이전 하네스의 641px 작업 영역과 좁은 파일 열을
  사용함
- 중요: History fixture가 선택 행과 키보드 포커스 행을 분리하지 않음
- 중요: README의 Blame 설명과 차이 수치가 갱신된 이미지와 맞지 않음
- 중요: 19번 캡처에 없는 빗금 셀을 수동 확인 항목으로 기록함
- 경미: 미완성 표식 검색이 검토 문서 자체의 표현과 일치함
- 경미: File 단일 항목 반복문과 도달할 수 없는 Blame 분기가 남음

최종 캡처 전용 기하를 추가하고 18~23을 다시 생성했습니다. History는
`65f4c80` 선택을 유지하면서 `c78b2ff` 행에 실제 기본 포커스를
요청하고 두 상태를 각각 검사합니다. README의 00~17 차이 이미지와
수치를 현재 구현 이미지로 다시 계산했으며 Blame, History와 검증
설명을 고쳤습니다. 단일 항목 반복문과 검색에 걸리던 표현도
제거했습니다.

재검토에서는 00~17 표의 History 너비와 13번 글자 크기 설명 네 곳이
이전 값으로 남아 있다는 중요 지적 한 건이 있었습니다. 현재 캡처의
History 작업 영역 약 846px, 목록 280px, 상세 565px과 최신
13·12·10px 글자 크기로 표를 고쳤습니다. 재검토의 나머지 확인 항목에는
추가 지적이 없었습니다. 마지막 확인 결과는 남은 지적 사항 없음,
병합 가능입니다.

## 남은 지적 사항

- P0: 없음
- P1: 없음
- P2: 없음
- P3: 없음
