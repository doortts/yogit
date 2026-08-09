# 아바타 깜박임 · 그래프 아바타 크기 · 그래프 폭 계산 — 구현 설계

2026-08-09 · TDD (계약 테스트 선행)

## 1. 미리보기 아바타가 이니셜 → 사진으로 두 번 그려진다

### 지금 무슨 일이 일어나나

`CommitAvatarStack`(lib/avatars.dart)이 `FutureBuilder(future: service.resolve(sha))`로
아바타를 얻는다. `AvatarService.resolve`는 이미 받아 둔 커밋이면 **완료된 Future**를 돌려주지만,
`FutureBuilder`는 완료된 Future라도 첫 프레임을 `snapshot.data == null`로 시작한다.
그래서 커서를 옮길 때마다 새 위젯이 만들어지고 → 한 프레임 이니셜 → 다음 프레임 사진.
42px 아바타라 그 한 프레임이 눈에 띈다.

### 고치는 방법

서비스가 **완료된 값을 동기적으로** 내주게 하고, 위젯이 그것을 `initialData`로 쓴다.

- `AvatarService`에 `final _resolved = <String, CommitAvatars>{}` — `_load`가 끝날 때 채운다.
- `CommitAvatars? cachedFor(String sha)` — 아직 모르면 null.
- `CommitAvatarStack`: `FutureBuilder(initialData: service.cachedFor(commit.sha), ...)`.

이미 아는 사람이면 첫 프레임부터 사진이 그려지고, 처음 보는 사람만 이니셜을 거친다.
같은 작성자의 다른 커밋도 사진 URL이 같아 Flutter 이미지 캐시가 즉시 답한다.

### 계약

- 한 번 resolve된 sha는 **새로 만든 위젯의 첫 pump에서 이미 사진**이다 (이니셜 프레임 없음).
- 아직 모르는 sha는 이니셜로 시작하고, 도착하면 사진으로 바뀐다 (기존 동작).

## 2. 그래프 아바타 지름 +2pt

`CommitGraphPainter.avatarDiameter` 18 → 20. 행 높이 22는 그대로라 위아래 1px씩 남는다.
`nodeExtent`·`avatarRadius`는 이 값에서 파생되므로 따라 움직인다.

### 계약

- `avatarDiameter == 20`, `avatarRadius == 10`.
- 행 안에서 잘리지 않는다: 아바타 높이 ≤ 행 높이.
- 레인 간격은 그대로 — 디스크가 이웃 레일을 덮지 않는다.

## 3. 그래프 컬럼 폭은 화면에 보이는 구조만으로 정한다

### 지금 구조

`_graphColumnWidth`(timeline.dart)는 `_graphWidth`(사용자가 끈 폭)가 없으면
`CommitGraphPainter.contentWidth(_graphLayoutDepth)`로 자동 맞춤한다.
`_graphLayoutDepth`는 일반 타임라인에서 `_ratchetLane`을 쓰고, 그 값은
`_updateRatchet`(timeline_data.dart)이 **스크롤 위치로 계산한 보이는 행 범위**에서만 깊이를 잰다.
즉 의도는 이미 "viewport만"이다. 다만:

- 래칫은 **넓어지기만** 한다. 깊은 구간을 봤다가 얕은 곳으로 돌아와도 좁아지지 않는다.
- 브랜치 diff 비교 모드(`_comparison != null`)에서는 래칫을 쓰지 않고 **비교 행 전체**의
  최대 레인을 쓴다.

### 확인할 것 (테스트가 먼저 답한다)

1. 얕은 머리(1레인) + 깊은 꼬리(5레인) 히스토리를 첫 화면에 띄우면 폭이 얕은 쪽에 맞는가.
2. 깊은 구간까지 스크롤하면 넓어지는가.
3. 다시 위로 돌아오면? — 지금은 유지(래칫). 이 동작을 유지할지 좁힐지 테스트로 고정한다.
4. 새 페이지가 붙어도 보이지 않는 깊이는 폭에 영향을 주지 않는가.
5. 사용자가 폭을 끌어 놓았으면 어떤 스크롤에도 그 폭이 유지되는가.

1·4가 깨지면 그것이 스샷의 원인이다. 깨지지 않으면 원인은 저장된 `graph` 폭이므로,
자동 맞춤이 저장 값을 무시하는지 따로 본다.

### 테스트가 답한 것 (2026-08-09)

1·2·4·5는 **이미 그렇게 동작한다** — 테스트 4건으로 고정했다. 첫 화면은 보이는 레인에만 맞고,
깊은 구간으로 내려가면 넓어지고, 사용자가 끈 폭은 어떤 스크롤에도 유지된다. 저장소를 바꾸면
`main.dart`가 저장소 root로 화면에 key를 주기 때문에 상태가 새로 서고, 앞 저장소의 깊이를
물려받지 않는다(이것도 테스트).

3(위로 돌아왔을 때)은 **유지**다. 폭이 스크롤마다 오르내리면 컬럼 경계가 흔들려 읽기 어렵다.
스샷에서 넓어 보였던 것은 한 번 내려가 본 뒤 래칫이 그 폭을 지키고 있던 것이다. 좁아지길
원하면 그때 다시 정한다.

저장소 전환 시 래칫을 0으로 되돌리는 코드는 넣었다가 **뺐다** — key 덕분에 도달하지 않는
경로였고, 오히려 옛 행이 화면에 남아 있는 동안 다시 재어 폭을 잘못 잡았다.
