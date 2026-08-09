# 사이드바 — 로컬 브랜치와 원격의 커밋 차이 표시

2026-08-09 · 시안: `docs/sidebar-divergence-mockup.html` (1안 승인) · TDD

## 무엇을 만드나

LOCAL 트리의 브랜치 행마다, 그 브랜치가 추적하는 원격과 몇 커밋 벌어졌는지를
<span>`+N`</span>(앞섬, 초록) <span>`−N`</span>(뒤처짐, 빨강)으로 이름 오른쪽에 붙인다.
원격 행이 이미 쓰는 표기 그대로다.

## 지금 상태 (확인 결과)

**데이터는 이미 있다.** `RepoRefs.aheadBehind`(lib/git.dart)는 **업스트림이 설정되어 있고 그
원격 ref가 살아 있는 모든 로컬 브랜치**에 대해 `BranchAheadBehind{ahead, behind}`를 채운다
(git.dart의 ref 적재부). 새로 잴 것이 없다.

**사이드바는 그중 거의 안 쓴다.** `_refTreeRow`(lib/timeline_sidebar.dart)는
`_refs.aheadBehind[name]`을 읽지만 조건이 `selectedLocal` — 기준 브랜치 한 줄뿐이고, 그것도
`behind`만 빨간 숫자 하나로 그린다. 앞선 수는 로컬 행에 나오지 않는다. `+N −N` 쌍은 REMOTE
행에만 있다.

**주기 갱신도 이미 있다.** `TimelineScreen`이 3분마다 `_refreshRemotes()`로 fetch하고, 실제로
갱신된 원격이 있을 때만 `_loadRefs()`를 다시 돈다. 60초 로컬 확인 타이머와 refs 디렉터리
감시도 따로 있다. **타이머를 새로 붙이지 않는다.**

**다만 fetch 대상에 구멍이 있다.** `_remotesToRefresh`는

- 기준 브랜치의 업스트림 원격, 그리고
- 같은 이름의 로컬 브랜치가 있는 원격

만 모은다. 이름이 다른 업스트림을 추적하는 브랜치(`feature/x` → `origin/topic-x`)는 그 원격이
다른 이유로 끼지 않는 한 fetch되지 않아, 배지 숫자가 낡은 채로 남는다.

## 고치는 것 두 가지

### 1. 배지 하나를 두 행이 같이 쓴다

지금 `_refTreeRow` 안에 배지가 두 벌 있다 — 로컬용 `behind`만 그리는 것과, 원격용 `+N −N`
쌍. 뒤엣것이 앞엣것을 완전히 포함한다. 원격용을 헬퍼로 빼고 둘 다 거기서 그린다.

```
_divergenceBadge({required Key key, required int ahead, required int behind,
                  required String tooltip})
  → 36pt 폭, FittedBox(scaleDown, centerRight), Text.rich(+N 초록 / −N 빨강, 11px)
```

- 로컬 행: `_refs.aheadBehind[name]`, 기준 브랜치 여부와 무관하게 **모든** 로컬 행에.
- 원격 행: `_refs.remoteAheadBehind[name]`, 지금 동작 그대로 (hover 시 ↓ 버튼에 자리를 양보).

두 값 다 **그 ref 자신의 관점**으로 저장되어 있다 — 원격 쪽은 적재할 때 이미 뒤집어 넣는다.
그래서 같은 위젯이 그대로 맞는다. 툴팁 문구만 다르다.

| 행 | 툴팁 |
|---|---|
| 로컬 | `원격보다 N개 커밋 앞서 있습니다` · `원격보다 N개 커밋 뒤처져 있습니다` |
| 원격 | `로컬보다 N개 커밋 앞서 있습니다` · `로컬보다 N개 커밋 뒤처져 있습니다` |

키: 로컬은 `sidebar-local-divergence-$name`, 원격은 지금의
`sidebar-remote-divergence-$name`. 옛 `sidebar-behind-$name`은 없어진다 — 새 배지가 그
경우를 포함한다.

무엇도 안 그리는 때: 업스트림이 없거나(맵에 항목 없음), `ahead == 0 && behind == 0`.
1안은 이 둘을 구분하지 않는다 — 시안 검토에서 알고 고른 약점이다.

### 2. fetch 대상에 모든 업스트림 원격을 넣는다

`_remotesToRefresh`가 `_refs.upstreamRemotes.values`를 통째로 넣는다. 기준 브랜치 하나만
특별 취급하던 줄이 사라진다. 같은 이름 로컬을 훑는 기존 루프는 그대로 둔다 — 업스트림
설정이 없어도 이름이 같으면 비교 대상이기 때문이다.

## 폭

사이드바 행은 좁다(기본 187pt). HEAD 행에서는 이름 · HEAD 칩 · 배지가 한 줄을 나눠 쓴다.
이름이 먼저 줄어든다(이미 `TextOverflow.ellipsis`). 배지는 36pt 고정에 `FittedBox`가
들어 있어 세 자리 수(`+120 −340`)도 잘리지 않고 작아진다.

## 계약 테스트

1. 기준 브랜치가 아닌 로컬 브랜치도 배지를 단다 — 지금은 안 단다.
2. 앞서기만 하면 `+N` 초록 하나, 뒤처지기만 하면 `−N` 빨강 하나, 갈라지면 둘 다.
3. `ahead == 0 && behind == 0`이면 배지가 없다. 업스트림이 없는 브랜치도 없다.
4. 로컬 행 툴팁이 `원격보다 …` 문구다 (원격 행의 `로컬보다 …`와 뒤바뀌지 않는다).
5. 원격 행 배지는 지금 그대로다 (회귀 방지), hover 시 ↓ 버튼에 자리를 내주는 것도 그대로.
6. 이름이 다른 업스트림을 추적하는 브랜치의 원격이 주기 fetch 대상에 든다.
7. fetch가 갱신을 보고하면 refs를 다시 읽어 배지 숫자가 바뀐다 (기존 동작, 유지 확인).
