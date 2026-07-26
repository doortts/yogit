# Task 8 작업 보고서

## 커밋

- 기준 커밋: `82312d1e91dc081a8dea1d3cfed3f30bcd9bef88`
- 최종 구현 커밋: `58025d639cd6bf4c8ed4283d5d0ac7307e6c09bf`

## 변경 파일

- `lib/full_diff_header.dart`
  - `GlobalFileBar`, `GlobalDiffToolbar`,
    `FullDiffSegmentedControl<T>`를 추가했습니다.
  - 승인된 이름과 순서, 선택·사용 가능 상태, 접근성 이름을
    구현했습니다.
  - 조립 전인 현재 브랜치와 기존 테스트가 계속 동작하도록
    `DiffFileHeader`와 `DiffToolbar`는 유지했습니다.
- `test/full_diff_header_test.dart`
  - 메뉴 순서, 알고리즘 메뉴, History 상태, 접근성, 크기·반지름·글꼴,
    선택 색을 검증하는 위젯 테스트 6개를 추가했습니다.

## RED 확인

1. 새 머리글 테스트를 처음 실행했을 때 `GlobalFileBar`와
   `GlobalDiffToolbar`가 없어서 컴파일에 실패했습니다.
2. 기준 이미지를 다시 대조한 뒤 켜진 토글의 색을 검증하는 테스트를
   추가했습니다. 이 테스트는 흰색을 기대했지만 기존 구현이
   `fullDiffControl`을 사용해서 실패했습니다.
3. 켜진 토글도 선택한 화면 버튼과 같은 흰 배경·검은 글자를 쓰도록
   고친 뒤 전용 테스트를 다시 통과시켰습니다.

## 통과한 검사

- `dart format lib/full_diff_header.dart test/full_diff_header_test.dart`
- `flutter test test/full_diff_header_test.dart`
  - 6개 통과
- `flutter test test/full_diff_header_test.dart test/full_diff_widgets_test.dart`
  - 29개 통과
- `flutter test`
  - 241개 통과
- `flutter analyze`
  - 문제 없음
- `flutter build macos --debug`
  - `yogit.app` 빌드 성공
- `git diff --check`
  - 문제 없음

## 시안 대조

다음 승인 이미지를 직접 확인했습니다.

- `00-overview-hunk.png`
- `06-focus-mode.png`
- `07-ignore-whitespace.png`
- `10-algorithm-histogram.png`
- `user-approved-default.png`

확인한 항목은 다음과 같습니다.

- 첫 번째 머리글은 파일 경로와 상태 뒤에 `편집기로 열기`, `File`,
  `Diff`, `Blame`, `History`, `UTF-8`을 같은 순서로 배치했습니다.
- 두 번째 머리글은 `집중 모드`, 세 가지 표시 방식, 이전·현재·다음
  변경, 알고리즘, `공백 무시`, `줄바꿈` 순서를 지켰습니다.
- 선택한 화면·표시 방식·토글은 흰 배경과 검은 글자, 나머지 조작
  요소는 `fullDiffControl`과 흰 글자를 사용합니다.
- 조작 요소 높이는 28px, 반지름은 12.5px입니다. 파일 경로 칩의
  반지름은 7.5px이며 Menlo 14px과 한 줄 말줄임을 적용했습니다.
- 집중 모드를 켜면 이름을 `탐색 패널`로 바꾸고
  `Icons.view_sidebar_outlined`를 사용합니다.
- 알고리즘의 닫힌 메뉴 이름은 선택값과 관계없이
  `diff 알고리즘`으로 유지합니다. 열린 메뉴에서만 다섯 선택지와
  현재 선택 상태를 보여 줍니다.

## 범위 이탈

브리프에 적힌 구현 파일, 새 테스트 파일과 이 보고서만 바꿨습니다.
Task 11이 새 머리글을 `DiffScreen`에 조립하기 전에도 전체 브랜치가
빌드되고 테스트되도록 기존 머리글 두 클래스는 삭제하지 않았습니다.

## 남은 위험

- 이번 작업은 머리글 위젯만 구현했으므로 완성 화면 캡처와 픽셀 차이
  비교는 아직 실행할 수 없습니다. Task 11에서 `DiffScreen`에 조립한
  뒤 Task 12의 13개 기준 이미지 검수로 최종 위치를 확인해야 합니다.
- Material 아이콘은 웹 시안의 Lucide 아이콘과 윤곽이 조금 다를 수
  있습니다. 기능별 이미지 대조에서 허용 범위를 넘으면 같은 모양의
  벡터 자산으로 교체해야 합니다.
