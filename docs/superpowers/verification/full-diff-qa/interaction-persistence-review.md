# Full Diff 상호작용·저장 검수

2026-07-28에 기능 캡처 24~29를 원본 크기로 열어 확인했다. 이 여섯 장은
기존 승인 시안과 픽셀을 비교하는 이미지가 아니라, 실제 제품 위젯을
조작한 뒤 결과 상태를 기록한 기능 검수 이미지다. 자동 테스트로 조작
결과와 배치를 확인하고, 캡처를 눈으로 다시 살폈다.

## 이미지별 판정

| 이미지 | 크기 | 조작과 확인 결과 | 판정 |
| --- | ---: | --- | --- |
| [24-unified-hunks](actual/24-unified-hunks.png) | 1070×842 | Hunk를 껐다가 다시 켰다. 첫째 줄에는 연결형 Diff \| Blame 선택 묶음이 있고, 둘째 줄에는 Unified \| Side-by-side 선택 묶음과 Hunk 바로 오른쪽의 History 토글이 있다. Unified와 Hunk가 각각 선택되어 있고, `State.Init`, `SetupBase`, `LoadCurrent` 등 여러 Hunk가 한 스크롤에 소스 순서대로 이어진다. File 버튼은 없다. | PASS |
| [25-side-by-side-full-file](actual/25-side-by-side-full-file.png) | 1280×842 | Unified를 선택한 뒤 Side-by-side로 되돌렸다. Side-by-side만 선택되고 Hunk는 독립적으로 꺼져 있다. 하나로 합쳐진 `Full file` 범위 안에 이전·결과 열, 가운데 경계, 변경 사이의 연속 문맥이 함께 보인다. | PASS |
| [26-shortcut-hints](actual/26-shortcut-hints.png) | 1280×842 | Command 키를 누른 상태를 캡처했다. 첫째 줄 Diff \| Blame에는 `⌘1`·`⌘2`, 둘째 줄 Hunk 옆 History에는 `⌘3`이 표시된다. `⌘⇧F`, `⌘⇧A`, `⌘⇧Space`, `⌘⇧L`, `⌘U`, `⌘⇧H`도 각 조작부 바로 아래에 겹쳐 표시되며, 표시 전후 Unified 조작부의 위치는 바뀌지 않는다. | PASS |
| [27-algorithm-chooser](actual/27-algorithm-chooser.png) | 1280×842 | 알고리즘 선택기를 열고 Histogram을 적용했다. 왼쪽의 Git setting·Myers·Minimal·Patience·Histogram 목록과 오른쪽 설명이 모두 보이고, Histogram에만 선택 표시가 있다. 팝오버 어느 쪽도 잘리지 않는다. | PASS |
| [28-blame-selection](actual/28-blame-selection.png) | 1280×842 | Blame을 선택하면 둘째 줄의 Diff 전용 조작부인 Unified·Side-by-side·Hunk·History가 모두 숨는다. 294행을 마우스로 선택하자 커밋 카드는 선택 행에서 두 행 높이 아래인 296행 위치에서 시작한다. 295행은 가리지 않고 296행부터 아래 콘텐츠 위에 겹치며 뒤 행의 위치도 그대로다. 제목·작성자·날짜 같은 본문 정보는 UI 글꼴을 물려받고 SHA는 의도대로 기술 글꼴(`technicalFontFamily`)을 쓴다. | PASS |
| [29-history-resizers](actual/29-history-resizers.png) | 1280×842 | Files 경계를 20px, History 경계를 24px 옮겼다. Files·History·diff 사이의 1px 세로선이 끊기지 않으며, 콜백에 저장된 너비와 화면 너비가 같다. 선택된 History 행의 배경은 위·왼쪽·오른쪽 패널 가장자리에 닿는다. | PASS |

## 수동 확인 항목

1. 헤더 구조와 File 버튼 없음: 첫째 줄에는 연결형 Diff | Blame 선택
   묶음만 있다. 둘째 줄에서는 History 토글이 Hunk 바로 오른쪽에 놓인다.
   Blame에서는 Unified·Side-by-side·Hunk·History가 모두 숨으며 File
   버튼은 어느 화면에도 없다. **PASS**
2. Unified·Side-by-side 상호 배타성: 24는 Unified만, 25와 29는
   Side-by-side만 선택되어 있다. **PASS**
3. Hunk 독립 토글: 24에서는 Hunk가 켜지고 25에서는 꺼지며, 레이아웃
   선택과 섞이지 않는다. **PASS**
4. 모든 Hunk의 순차 표시: 24에서 여러 변경 머리글이 소스 순서대로 한
   스크롤에 이어진다. 25에서는 Hunk가 꺼져 하나의 연속된 `Full file`
   범위로 바뀐다. **PASS**
5. 알고리즘 선택기 비절단: 27에서 왼쪽 목록과 오른쪽 상세 설명을 모두
   읽을 수 있다. **PASS**
6. 단축키 배지 배치: 26에서 배지가 조작부 바로 아래에 놓이고 상단 바는
   움직이지 않는다. **PASS**
7. Blame 카드 배치: 28에서 카드는 294행보다 두 행 아래인 296행부터
   겹친다. 295행을 가리지 않고 기존 행도 밀어내지 않는다. **PASS**
8. 열 경계: 29에서 Files·History·diff 사이의 1px 세로 경계가 모두
   보인다. **PASS**
9. History 선택면: 29에서 선택 배경이 목록 패널의 위·왼쪽·오른쪽
   가장자리에 닿는다. **PASS**

## 설계 완료 기준

1. Preview의 파일 목록과 diff를 따로 스크롤할 수 있다. `preview file and
   diff panes scroll independently` 테스트에서 두 스크롤 위치를 따로
   움직여 확인했다. **PASS**
2. Full Diff의 첫째 줄에는 Diff | Blame 선택 묶음만 있고 File 화면은 없다.
   History는 둘째 줄 Hunk 옆의 독립 토글이다. Blame에서는 Diff 전용
   조작부인 Unified·Side-by-side·Hunk·History가 모두 숨는다. 24~29와
   헤더 위젯 테스트에서 확인했다. **PASS**
3. Full Diff를 다시 열면 마지막 화면과 옵션이 복원된다. `reopening full
   diff restores the last successful options`와 설정 JSON 왕복 테스트가
   화면·레이아웃·범위·알고리즘·공백·줄바꿈 값을 확인한다. **PASS**
4. Unified와 Side-by-side 중 하나가 항상 선택되고 `⌘U`로 전환된다.
   24·25와 `full diff command shortcuts change only their owned options`
   테스트에서 확인했다. **PASS**
5. Hunk는 레이아웃과 별개이며 기본값은 켜짐이다. 24·25와 기본 환경설정
   테스트에서 확인했다. **PASS**
6. Hunk가 켜지면 모든 Hunk가 소스 순서대로 한 스크롤에 표시된다.
   24와 `unified hunk scope renders every hunk in source order` 테스트에서
   확인했다. **PASS**
7. Hunk가 꺼지면 Unified와 Side-by-side 모두 전체 문맥을 표시한다.
   25와 두 레이아웃의 `turning Hunk off preserves a later change` 테스트로
   확인했다. **PASS**
8. 알고리즘과 공백 무시 옵션이 실제 git diff 요청에 반영된다. 저장소
   요청 인수를 검사하는 controller·workspace 테스트에서 적용값과 실패
   시 복구까지 확인했다. **PASS**
9. 알고리즘 선택기는 왼쪽 목록과 오른쪽 설명을 함께 표시하고,
   마우스·키보드 미리보기를 즉시 갱신한다. 27과 chooser의 hover·화살표·
   Enter 테스트에서 확인했다. **PASS**
10. Command 키를 누르면 배지가 상단 배치를 움직이지 않고 나타난다.
    26에서 배지의 위치와 Unified 조작부의 전후 좌표를 함께 검사했다.
    **PASS**
11. Blame의 hover·클릭·키보드 선택은 행을 밀지 않는다. 커밋 카드는
    선택 행에서 두 행 높이 아래부터 겹치므로 바로 다음 행은 가리지
    않는다. 28과 Blame 선택·화살표 테스트에서 행 좌표를 확인했다.
    **PASS**
12. `⌘⇧↑`·`⌘⇧↓`는 활성 콘텐츠를 뷰포트의 50%만큼 스크롤한다.
    Preview·Full Diff·History 상세의 페이지 스크롤 테스트에서 이동
    거리와 끝점 제한을 확인했다. **PASS**
13. Files·History·diff 사이에 1px 세로선이 있고, 두 열 너비를 조절해
    복원할 수 있다. 29, 리사이저 테스트, 설정 저장·복원 테스트에서
    화면 너비와 저장값을 함께 확인했다. **PASS**
14. History 목록에는 바깥 여백이 없고 선택면이 패널 가장자리에 닿는다.
    29와 `selected History row reaches all three list edges` 테스트에서
    확인했다. **PASS**

완료 기준 14개와 수동 확인 항목 9개는 모두 **PASS**다.
