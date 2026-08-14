# Diff 가로 스크롤 — 줄 단위에서 pane 단위로

2026-08-14 · 시안 파일: `docs/diff-horizontal-scroll-mockup.html`

## 1. 지금 무슨 일이 벌어지나

`FullDiffCodeRow`가 줄마다 자기 스크롤 뷰를 하나씩 달고 있다
([full_diff_code_row.dart:335](../lib/full_diff_code_row.dart#L335)).

```dart
final source = wrapLines || !horizontalScroll
    ? richText
    : SingleChildScrollView(
        key: const Key('code-row-horizontal-scroll'),
        scrollDirection: Axis.horizontal,
        ...
```

그래서 긴 줄 위에서 트랙패드를 옆으로 밀면 그 줄 하나만 움직인다. 옆 줄은 제자리에 남고,
side-by-side에서는 반대편도 따라오지 않는다. 줄마다 스크롤 위치가 따로 놀아서 코드가
계단처럼 어긋나 보인다.

## 2. 다른 diff 뷰어는 어떻게 하나

| 뷰어 | 가로 스크롤 단위 | 줄 번호(거터) | side-by-side |
|---|---|---|---|
| VS Code diff editor | 편집기 pane 하나 | 고정 | 양쪽 오프셋 동기화, 구분선 제자리 |
| IntelliJ diff | pane 하나 | 고정 | 동기화 |
| Sublime Merge · Fork · GitKraken | pane 하나 | 고정 | 동기화 |
| GitHub split diff | 표 하나 | 좌측 고정 | 표가 통째로 움직이니 양쪽이 같이 감 |

세부는 갈려도 공통 규칙은 셋이다.

1. 가로 스크롤은 **줄이 아니라 pane**이 갖는다.
2. **거터는 따라가지 않는다** — 줄 번호와 +/− 부호는 항상 왼쪽에 남는다.
3. side-by-side는 **한 오프셋을 양쪽이 공유**하고, 분할 구분선은 움직이지 않는다.

yogit은 데스크톱 git 클라이언트니 VS Code/GitKraken 쪽 관례를 따른다.

## 3. 확정 규칙

- **한 pane에 가로 오프셋 하나.** 줄마다 있던 스크롤 뷰는 없앤다.
- **거터·부호·hunk 헤더·커밋 정보 카드는 고정.** 움직이는 건 소스 텍스트 칼럼뿐이다.
  hunk 헤더에는 스테이징 버튼이 붙으니 가로로 밀려나면 안 된다.
- **side-by-side는 양쪽이 같은 오프셋으로 함께 움직인다.** 구분선과 분할 비율은 그대로다.
  양쪽 칼럼은 각자의 폭 안에서 잘린다.
- **스크롤 범위는 문서 전체 기준.** 화면에 보이는 줄이 아니라 파일에서 가장 긴 줄이 끝까지
  들어오는 만큼을 최대 오프셋으로 잡는다. 세로로 움직여도 가로 막대 길이가 흔들리지 않는다.
  side-by-side에서는 양쪽 중 더 긴 쪽을 쓴다.
- **줄바꿈(⇧L)이 켜지면 가로 스크롤은 사라진다.** 지금과 같다.
- **가로 막대는 pane 아래쪽에 얇게 뜨고 멈추면 사라진다.** 미니맵이 세로를 맡고 있으니
  세로 막대는 계속 없다. 가로는 대신할 안내가 없어서 막대를 둔다.
- **오프셋을 0으로 되돌리는 때**: 파일이 바뀔 때, 줄바꿈을 켤 때, unified↔side-by-side를
  바꿀 때. 세로 이동이나 hunk 이동, 공백 무시 토글은 오프셋을 건드리지 않는다.

## 4. 구현 설계

### 4.1 어디에 넣나

두 표현 뷰(`UnifiedPresentationView`, `SideBySidePresentationView`) 안에 넣는다. Full Diff
워크스페이스와 타임라인 미리보기가 이 뷰를 각각 호스팅하고 있어서
([full_diff_workspace.dart:1417](../lib/full_diff_workspace.dart#L1417),
[timeline_preview_pane.dart:1362](../lib/timeline_preview_pane.dart#L1362)), 뷰가 스크롤
면을 직접 가지면 호스트 쪽은 고칠 게 없다.

### 4.2 위젯 구조

세로 `ListView.builder`의 가상화를 그대로 두려면 리스트가 가로 스크롤 뷰의 자식이어야
한다. 그래야 트랙패드 가로 제스처가 리스트를 지나 위쪽 가로 스크롤로 넘어간다(Flutter는
축이 다른 중첩 스크롤에서 델타가 0인 축을 조상에게 넘긴다).

```
Scrollbar(controller: hScroll)
  SingleChildScrollView(horizontal, controller: hScroll)   // 스크롤 면
    SizedBox(width: viewportWidth + overflow)              // 스크롤 범위만 정한다
      AnimatedBuilder(hScroll)
        Transform.translate(+offset)                       // 리스트는 화면에 붙여 둔다
          ListView.builder( ... 기존 그대로 ... )
```

리스트를 다시 제자리로 밀어 두는 게 핵심이다. 스크롤 면은 폭만 제공하고, 실제로 움직이는
건 각 행의 소스 칼럼이다. 행 쪽은 지금의 `SingleChildScrollView`를 이렇게 바꾼다.

```dart
ClipRect(
  child: AnimatedBuilder(
    animation: horizontalOffset,          // InheritedNotifier로 내려받는다
    builder: (_, child) => Transform.translate(
      offset: Offset(-horizontalOffset.value, 0),
      child: child,
    ),
    child: OverflowBox(                   // 폭 제약을 풀어 자연 폭으로 눕힌다
      alignment: Alignment.topLeft,
      maxWidth: double.infinity,
      child: richText,
    ),
  ),
)
```

`Transform.translate`는 페인트 단계만 건드려서 보이는 행만 다시 그린다. 거터는 지금도
행 `Stack`의 `Positioned(left: 0)`이라 손대지 않아도 제자리에 남는다. side-by-side의 두
칼럼은 각자 `ClipRect`를 가지므로 같은 오프셋을 받고도 자기 폭 안에서만 잘린다.

### 4.3 스크롤 범위 계산

가장 긴 줄의 실제 폭이 필요한데, 파일 전체를 `TextPainter`로 재면 큰 파일에서 느리다.
두 단계로 나눈다.

1. 문서를 한 번 훑어 줄마다 **셀 수**를 센다(한글·한자·가나는 2셀, 나머지 1셀). 문자열
   연산이라 1만 줄도 몇 ms다.
2. 셀 수 상위 5줄만 `TextPainter`로 정확히 재고 그중 최댓값을 쓴다.

`overflow = max(0, 가장 긴 줄 폭 − 소스 칼럼 폭)`. side-by-side는 양쪽을 각각 계산해서 큰
쪽을 쓴다(소스 칼럼 폭이 분할 비율에 따라 다르므로). 결과는 문서 단위로 캐시한다 —
side-by-side는 `_SideBySideDocumentIndexCache`가 이미 문서 바뀔 때만 다시 만드는 자리를
갖고 있다.

### 4.4 Blame

`FullBlameView`도 같은 `FullDiffCodeRow`를 쓴다([full_blame_view.dart:460](../lib/full_blame_view.dart#L460)).
같은 래퍼를 blame 리스트에도 씌우면 같은 동작을 얻는다. 래퍼가 없는 곳에서는 행이 오프셋
0으로 동작하니 중간 상태도 깨지지 않는다.

### 4.5 테스트

- 행 하나에는 더 이상 가로 스크롤 뷰가 없다 — `code-row-horizontal-scroll` 키를 보던
  [full_diff_widgets_test.dart:1374](../test/full_diff_widgets_test.dart#L1374)를 pane 쪽
  스크롤 면을 보도록 바꾼다.
- pane을 200px 밀면 서로 다른 두 행의 텍스트가 같은 거리만큼 움직인다.
- side-by-side에서 pane을 밀면 왼쪽·오른쪽 소스가 같이 움직이고, 구분선과 줄 번호는
  제자리다.
- 줄바꿈을 켜면 스크롤 범위가 0이다.
- 파일을 바꾸면 오프셋이 0으로 돌아간다.
- [full_diff_visual_test.dart:820](../test/full_diff_visual_test.dart#L820)의 가로 스크롤
  위치 단언은 pane 스크롤 면 기준으로 옮긴다.

## 5. 구현하면서 정해진 것

- **스크롤 면은 밀 곳이 없어도 트리에 남는다.** 넣었다 뺐다 하면 그 아래 리스트가 다시
  붙으면서 세로 위치를 잃는다. 밀 곳이 없을 때는 범위가 0인 채로 가만히 있는다.
- **마우스로 소스를 끌면 텍스트가 선택된다.** 가로 이동은 트랙패드·휠·스크롤 막대가 맡는다.
  VS Code를 비롯한 다른 뷰어도 같다.
- **미니맵이 한 프레임 늦게 따라오던 문제를 같이 고쳤다.** 리스트가 이제 가로 스크롤의
  레이아웃 안에서 만들어져서, 미니맵이 그릴 때는 스크롤 위치가 아직 없다. 가만히 있는
  리스트는 알림을 보내지 않으니 미니맵이 다음 프레임에 한 번 더 확인한다.

## 6. 하지 않는 것

- 좌우 독립 스크롤(한쪽만 미는 모드). 요청은 동기화다.
- 선택 드래그로 화면 끝에 닿았을 때 자동 가로 이동.
- 검색·라인 이동이 화면 밖 열에 있을 때 가로로 따라가 보여주기. 필요해지면 그때 붙인다.
