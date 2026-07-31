# Branch / Tag 타임라인 팔레트 설계

## 목표

Branch / Tag 이름 칩과 타임라인 그래프가 하나의 팔레트를 공유한다.
Color 1은 기준 브랜치에 고정하고 Color 3–9는 자동 배정하거나 특정 레인에
고정할 수 있게 한다. 별도로 있던 `Base branch and lane fallback` 설정은
없앤다.

## 팔레트

Color 2는 사용하지 않는다. 설정 화면에서도 표시하지 않고 저장값에도
포함하지 않는다.

| 이름 | 역할 | Base | Text / line | 기본 배정 |
| --- | --- | --- | --- | --- |
| Color 1 | Base branch | `#0E8A16` | `#18E022` | Base branch 고정 |
| Color 3 | Branch / Tag | `#C5DEF5` | `#C2DDF4` | Random |
| Color 4 | Branch / Tag | `#1D76DB` | `#68A7EA` | Random |
| Color 5 | Branch / Tag | `#5319E7` | `#DACFFA` | Random |
| Color 6 | Branch / Tag | `#B51D68` | `#FF2D95` | Random |
| Color 7 | Branch / Tag | `#008FA3` | `#00E5FF` | Random |
| Color 8 | Branch / Tag | `#B89B00` | `#FFF01F` | Random |
| Color 9 | Branch / Tag | `#C94E10` | `#FF6E27` | Random |

표현 규칙은 기존 GitHub Enterprise 라벨 기준을 유지한다.

- 칩 배경: Base 색상, 불투명도 18%
- 칩 테두리: Text / line 색상, 불투명도 30%
- 칩 글자와 HEAD/Tag 기호: Text / line 색상, 불투명도 100%
- 그래프 선, 곡선, 연결선, 화살표, 노드, 링: Text / line 색상,
  불투명도 100%

## 설정 화면

`Timeline colors` 아래에는 `Branch / Tag & graph palette`만 표시한다.
기존 `Branch / Tag palette`, `Additional branch colors`,
`Base branch and lane fallback`, `Shared pool` 문구와 영역은 없앤다.

각 행에는 이름 칩 미리보기와 Base, Text / line 입력란을 둔다. Color 1에는
`Base branch`를 표시하며 배정 선택란을 두지 않는다. Color 3–9에는
`Random`, `Lane 2`, …, `Lane 9`를 고를 수 있는 선택란을 둔다.

기본값은 모두 `Random`이다. 같은 레인을 다른 색에서 고르면 기존에 그
레인을 쓰던 색은 `Random`으로 돌아간다. 한 레인에는 색 하나만 고정할 수
있다.

`Reset to defaults`는 표의 색상과 배정값을 한 번에 되돌린다. 올바른
6자리 16진수 색상을 입력하면 바로 저장하고 타임라인에 반영한다. 입력
중인 값이 완전하지 않으면 마지막으로 저장한 값을 유지한다.

## 색상 배정

Color 1은 현재 선택한 기준 브랜치와 내부 브랜치 ID 0에 항상 사용한다.
사용자에게 표시하는 `Lane 2–9`는 내부 브랜치 ID 1–8에 대응한다. 화면에서
선의 가로 위치가 바뀌더라도 브랜치 ID는 유지되므로 색상도 바뀌지 않는다.

`Lane N`으로 고정한 색은 해당 브랜치 ID에 먼저 배정하고 Random 후보에서는
제외한다. 남은 브랜치에는 `Random`으로 둔 색만 사용한다. Random은 화면을
다시 그릴 때마다 새로 고르는 뜻이 아니다. 저장소 경로에서 만든 기존
시드와 브랜치 ID 또는 ref 이름의 안정적인 해시를 사용해 같은 저장소와
같은 이름에는 실행을 다시 해도 같은 색을 배정한다.

Color 3–9를 모두 특정 레인에 고정해서 Random 후보가 없으면 전체
Color 3–9에서 안정적으로 하나를 다시 사용한다. 레인이 아홉 개를 넘거나
ref 정보가 아직 없는 경우도 같은 방식으로 색을 재사용한다.

한 그래프 선에 여러 ref가 연결되면 다음 순서로 대표 ref를 고른다.

1. 현재 HEAD
2. 로컬 브랜치
3. 리모트 브랜치
4. 태그
5. 로그 장식에서만 확인한 ref

같은 우선순위에서는 이름순으로 고른다. 대표 ref의 칩은 그 브랜치에
배정된 Base와 Text / line 색상을 사용한다. 연결선과 화살표, 그래프 선도
같은 Text / line 색상을 사용한다. 같은 커밋에 함께 표시되는 나머지 ref
칩은 Random 후보에서 ref 이름의 안정적인 해시로 색을 고른다.

브랜치 비교와 rebase 미리보기에서 충돌이나 가상 커밋을 구분하는 전용
색상은 그대로 둔다. 이번 팔레트는 일반 타임라인의 Branch / Tag와 실제
브랜치 그래프에만 적용한다.

## 저장과 이전 설정 호환

`AppSettings`는 여덟 색상 쌍과 Color 3–9의 배정값을 저장한다. 저장된 행
수, 배정값, 색상값이 잘못되면 위 기본값 전체를 사용한다.

새 형식이 없는 기존 설정은 다음처럼 한 번 변환한다.

- 새 Color 1: 기존 Color 4
- 새 Color 3: 기존 Color 3
- 새 Color 4: 기존 Color 1
- 새 Color 5: 기존 Color 5
- 새 Color 6–9: 위 표의 기본값
- 기존 Color 2: 삭제
- 모든 Color 3–9 배정: Random

기존 `baseBranchColor`와 `laneColors`는 이전 설정을 읽을 때만 허용한다.
새 설정 화면과 일반 타임라인 색상 계산에서는 사용하지 않으며 새 형식으로
저장한 뒤에는 통합 팔레트가 기준이 된다.

## 구현 범위

현재 `refPalette` 저장과 `AvatarService.branchAssignments` 흐름을 재사용한다.
별도 색상 서비스를 만들지 않는다. 색상 배정 결과에는 팔레트 행 인덱스를
함께 유지해 칩의 Base와 그래프의 Text / line을 같은 행에서 읽는다.

설정이나 ref, 기준 브랜치, 커밋 페이지가 바뀌면 기존 그래프 재계산 시점에
색상을 다시 배정한다. 페이지를 더 불러와도 이미 계산한 브랜치 ID와 ref
이름의 결과는 바뀌지 않아야 한다.

## 검증

- 기본 팔레트에 Color 2가 없고 표의 여덟 색상 쌍이 정확하다.
- 기존 다섯 색상 설정은 정해진 순서로 변환되고 기존 Color 2는 사라진다.
- 팔레트와 배정값을 JSON에 저장하고 다시 읽을 수 있다.
- 잘못된 저장값은 기본 팔레트와 모두 Random인 배정으로 돌아간다.
- 설정 화면에는 통합 영역만 보이고 Color 1에는 선택란이 없다.
- Color 3–9의 기본 선택은 Random이며 같은 Lane을 고르면 이전 선택이
  Random으로 돌아간다.
- Color 1의 칩과 기준 브랜치 선이 초록색 쌍을 사용한다.
- Color 4의 칩과 배정된 브랜치 선이 파란색 쌍을 사용한다.
- 특정 Lane에 고정한 색은 해당 브랜치 ID에 배정되고 Random 후보에서
  빠진다.
- Random 배정은 저장소를 다시 열거나 페이지를 더 읽어도 바뀌지 않는다.
- 대표 ref 칩의 테두리와 연결선, 화살표, 그래프 선은 같은 Text / line
  색상을 사용한다.
- Random 후보가 없거나 레인이 아홉 개를 넘어도 그래프가 정상적으로
  표시된다.
- 브랜치 비교와 rebase 미리보기의 전용 색상은 바뀌지 않는다.

구현 뒤에는 통합 설정 화면과 여러 색의 Branch / Tag 칩, 그래프를 함께
캡처한다. 평평한 픽셀의 RGB 값을 표와 비교하며 채널별 오차는 1 이하여야
한다. 값이나 연결 관계가 다르면 고친 뒤 같은 검증을 다시 수행한다.
