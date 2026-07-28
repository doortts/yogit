# Full Diff Git 알고리즘 설정 표시 설계

## 목적

Full Diff의 알고리즘 버튼과 선택창에서 `Git setting`이라는 추상적인
이름을 없앤다. 저장소에 실제로 적용되는 `diff.algorithm` 값을 읽어
Myers, Minimal, Patience, Histogram 가운데 하나를 표시한다.

사용자가 알고리즘을 직접 고르면 해당 알고리즘으로 diff를 다시
불러온다. Git 설정을 따르는 알고리즘과 직접 고를 수 있는 알고리즘이
목록에서 중복되지 않아야 한다.

## 범위

이번 변경은 다음 동작을 포함한다.

- 저장소에 적용되는 `diff.algorithm` 조회
- 설정값과 Git 기본값을 실제 알고리즘으로 변환
- 닫힌 버튼과 알고리즘 선택창의 표시 변경
- 현재 Git 설정인 알고리즘의 설명 표시
- 알고리즘을 선택했을 때 diff를 다시 불러오는 동작 검증
- 조회 실패와 diff 갱신 실패 처리

Git과 다른 자체 diff 알고리즘을 추가하거나 Git 설정 파일을 수정하는
기능은 포함하지 않는다. Full Diff가 열린 동안 설정 파일의 변경을
실시간으로 감시하지도 않는다. 저장소마다 Full Diff 세션을 시작할 때
설정을 새로 읽는다.

## Git 설정 해석

`GitRepository`는 저장소 경로에서 `git config --get diff.algorithm`을
실행한다. 이 명령은 저장소, 사용자, 시스템 설정의 우선순위를 Git과
같은 방식으로 반영한다.

설정값은 다음과 같이 해석한다.

| `diff.algorithm` 값 | 실제 알고리즘 | 설정 설명 |
|---|---|---|
| 값 없음 | Myers | Git 기본값 |
| `default` | Myers | Git 기본값을 명시 |
| `myers` | Myers | Git 설정 |
| `minimal` | Minimal | Git 설정 |
| `patience` | Patience | Git 설정 |
| `histogram` | Histogram | Git 설정 |

앞뒤 공백을 없애고 영문 대소문자를 구분하지 않고 해석한다. Git이
지원하지 않는 값이 들어 있거나 설정 조회 명령 자체가 실패하면 값을
짐작하지 않는다. Git 설정 오류로 다루고 기존 오류 화면에서 원인을
보여 준다.

설정 조회 결과는 다음 정보를 담는 값 객체로 표현한다.

- 실제 알고리즘
- 원래 `diff.algorithm` 값
- 설정이 없어서 Git 기본값을 쓰는지 여부

`DiffAlgorithm.gitSetting`은 사용자 선택의 출처를 나타내는 내부 값으로
유지한다. 실제 알고리즘을 나타내는 값으로 사용하지 않는다.

## 상태와 데이터 흐름

`FullDiffRepository`에 Git 알고리즘 설정을 읽는 메서드를 추가한다.
`GitRepository`는 실제 Git 명령을 실행하고 테스트용 저장소는 정해진
설정 결과를 돌려준다.

`FullDiffSessionController`는 세션을 초기화할 때 다음 순서로 처리한다.

1. 저장소에 적용되는 Git 알고리즘 설정을 읽는다.
2. 저장된 Full Diff 선택값과 Git 설정의 실제 알고리즘을 비교한다.
3. 저장된 직접 선택값이 현재 Git 설정과 같으면
   `DiffAlgorithm.gitSetting`으로 정리한다.
4. 파일 목록과 선택한 파일의 diff를 불러온다.

세 번째 단계가 있어야 목록에서 숨긴 직접 선택값이 내부에 남지 않는다.
설정 출처와 선택 표시도 같은 상태를 가리키게 된다.

상태에는 다음 두 값을 구분해 둔다.

- 선택 출처: Git 설정 또는 사용자가 직접 고른 알고리즘
- 실제 표시값: Myers, Minimal, Patience, Histogram 가운데 하나

사용자가 직접 고른 알고리즘은 그대로 실제 표시값이 된다. 선택 출처가
Git 설정이면 조회한 Git 설정의 실제 알고리즘을 표시한다.

## 화면 표시

### 닫힌 버튼

버튼에는 언제나 실제 알고리즘 이름만 표시한다.

- 설정 없음: `Myers`
- `diff.algorithm=histogram`: `Histogram`
- 사용자가 Patience를 직접 선택: `Patience`

접근성 이름도 `diff 알고리즘: Histogram`처럼 실제 알고리즘 이름을
사용한다.

### 알고리즘 선택창

목록에는 Myers, Minimal, Patience, Histogram을 각각 한 번만 표시한다.
별도의 `Git setting` 항목은 두지 않는다.

현재 Git 설정에 해당하는 항목은 내부적으로
`DiffAlgorithm.gitSetting`을 선택하는 항목이다. 나머지 항목은 해당
알고리즘을 명시적으로 선택한다. 예를 들어 Git 설정이 Histogram이면
Histogram 항목을 고를 때 Git 설정을 따르고 Myers, Minimal, Patience는
각 알고리즘을 직접 지정한다.

오른쪽 설명 영역은 가리키거나 키보드로 선택한 알고리즘의 기존 설명을
유지한다. 현재 Git 설정에 해당하는 알고리즘에는 설명 위에 다음 문구를
추가한다.

- 설정 없음: `현재 Git 설정 · Git 기본값`
- `diff.algorithm=default`: `현재 Git 설정 · Git 기본값`
- `diff.algorithm=histogram`: `현재 Git 설정`

설정값 자체도 보조 문구로 보여 준다.

- 설정 없음: `diff.algorithm 미설정`
- 설정 있음: `diff.algorithm=histogram`

Git 설정과 다른 알고리즘의 설명에는 이 표시를 붙이지 않는다. 현재
적용 중인 알고리즘의 체크 표시와 현재 Git 설정 표시는 서로 독립적이다.
사용자가 Patience를 직접 적용한 동안에도 Histogram 설명에는
`현재 Git 설정`이 남고 Patience에 체크 표시가 나타난다.

## 알고리즘 선택과 diff 갱신

현재 Git 설정에 해당하는 항목을 선택하면
`DiffAlgorithm.gitSetting`으로 diff를 요청한다. Git 명령에는
`--diff-algorithm` 인자를 붙이지 않으므로 Git이 설정을 그대로 적용한다.

다른 항목을 선택하면 기존처럼 다음 인자 가운데 하나를 붙인다.

- `--diff-algorithm=myers`
- `--diff-algorithm=minimal`
- `--diff-algorithm=patience`
- `--diff-algorithm=histogram`

선택 직후에는 기존 diff를 유지한 채 불러오는 상태를 표시한다. 새 Git
요청이 성공하면 patch 문서, hunk 위치, 선택값을 함께 바꾼다. patch
캐시 키에는 선택 출처와 알고리즘이 이미 포함되므로 서로 다른 요청의
결과가 섞이지 않는다.

요청이 실패하면 마지막으로 성공한 diff와 알고리즘 선택을 복원한다.
오류를 숨기지 않고 현재 오류 처리 흐름으로 전달한다.

## 예외 처리

- 설정이 없으면 오류가 아니라 Myers를 쓰는 정상 상태다.
- `default`는 Myers로 표시하되 `diff.algorithm=default`를 보조 문구로
  보여 준다.
- 지원하지 않는 설정값은 임의의 알고리즘으로 바꾸지 않는다.
- 설정 조회가 실패하면 diff를 잘못된 이름으로 표시하지 않는다.
- 알고리즘을 바꾸는 도중 다른 파일을 선택하면 기존 요청 취소 규칙을
  그대로 따른다.
- 추적하지 않는 새 파일은 알고리즘에 따라 patch가 달라지지 않더라도
  선택 상태와 화면 갱신 흐름은 동일하게 유지한다.

## 테스트

### Git 저장소 테스트

- `diff.algorithm`이 없으면 Myers와 Git 기본값 상태를 돌려주는지 확인
- `default`를 Myers로 해석하는지 확인
- `myers`, `minimal`, `patience`, `histogram`을 각각 올바르게 해석하는지
  확인
- 지원하지 않는 값과 명령 실패를 오류로 돌려주는지 확인
- 직접 선택한 알고리즘이 Git 명령의 `--diff-algorithm` 인자로
  전달되는지 확인
- Git 설정 선택은 해당 인자를 생략하는지 확인

### 컨트롤러 테스트

- 초기화할 때 Git 설정을 상태에 저장하는지 확인
- 저장된 직접 선택값이 현재 Git 설정과 같으면 Git 설정 선택으로
  정리하는지 확인
- 직접 고른 알고리즘으로 patch 문서를 다시 불러오는지 확인
- Git 설정 항목으로 돌아가면 인자 없는 새 요청을 보내는지 확인
- 갱신 성공 후 새 문서와 선택값을 함께 적용하는지 확인
- 갱신 실패 후 마지막으로 성공한 문서와 선택값을 복원하는지 확인

### 화면 테스트

- 닫힌 버튼에 실제 알고리즘 이름이 표시되는지 확인
- 선택창에 네 알고리즘이 한 번씩만 나타나는지 확인
- Git 설정에 해당하는 설명에만 `현재 Git 설정`이 나타나는지 확인
- 설정이 없으면 Myers 설명에 `현재 Git 설정 · Git 기본값`이 나타나는지
  확인
- 현재 선택 체크와 Git 설정 표시가 서로 다른 알고리즘에 함께 나타날 수
  있는지 확인
- 마우스, 키보드, 접근성 동작이 기존 선택창과 동일한지 확인

## 완료 조건

1. Full Diff 어디에도 `Git setting`이 현재 알고리즘 이름으로 표시되지
   않는다.
2. 닫힌 버튼은 실제 적용 중인 알고리즘 이름을 보여 준다.
3. 선택창에는 네 알고리즘이 각각 한 번만 나타난다.
4. Git 설정에 해당하는 알고리즘 설명에는 `현재 Git 설정`이 나타난다.
5. Git 설정이 없으면 Myers가 Git 기본값임을 함께 알린다.
6. 알고리즘을 선택하면 해당 Git 방식으로 patch를 다시 읽고 화면을
   갱신한다.
7. 갱신에 실패하면 기존 diff와 선택값을 유지한다.
