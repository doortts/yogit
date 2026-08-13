# 아바타 색을 피해서 레인 색을 배정한다

2026-08-14 · 시안 없음(레이아웃 불변, 색 배정 규칙만 바뀜) · TDD

## 문제

팔레트의 연한 두 색 — `#C2DDF4`(하늘), `#DACFFA`(라벤더) — 이 밝은 아바타와 겹치면
노드의 브랜치 링이 사진에 묻힌다. 흰 바탕에 파란 낙서인 아바타에서 실제로 확인된 증상이고,
진한 레인(초록·주황·시안)은 같은 아바타에서도 잘 보인다.

구분선(1px hairline) 안은 만들었다가 되돌렸다. 이 설계는 그 자리 대신: **사용자 아바타의
대표색을 구해서, 그 색과 지각적으로 가까운 팔레트 항목을 무작위 배정 후보에서 뺀다.**
팔레트 자체는 손대지 않는다 — 바뀌는 것은 어느 브랜치가 어느 색을 받느냐뿐이다.

## 방향을 정한 근거

- **기준 아바타는 저장소의 git identity(본인) 하나.** 그래프에서 반복되는 얼굴은 대부분
  본인이다. 참가자 전원의 아바타를 다 피하려면 8색 팔레트에 남는 색이 없다.
- **배정 후보 필터링이지 팔레트 수정이 아니다.** 사용자가 설정에서 고른 팔레트와 핀 배정은
  그대로 존중한다. 자동 조정은 "무작위로 고를 때 이 색은 빼라"까지만 한다.
- **아바타가 없으면 아무것도 달라지지 않는다.** 토큰이 없어 AvatarService가 null이면
  아바타 자체가 안 그려지므로 문제도 없고 조정도 없다.

## 충돌 판정: Oklab 거리

WCAG 명도 대비만 쓰면 중간톤 사진에서 핑크(대비 1.06)·주황(1.16)까지 과잉 제외된다 —
회색 사진 위 선명한 핑크 링은 실제로는 잘 보인다(색상 차이가 명도 차이를 대신한다).
지각 균등 색공간 Oklab의 유클리드 거리는 두 경우를 모두 맞게 가른다. 실측:

| ΔE(Oklab) | 흰 낙서 `#E8EDF4` | 파란 낙서 `#C7D9EC` | 중간톤 `#8A8F96` | 어두운 사진 `#2E3138` |
|---|---|---|---|---|
| 하늘 `#C2DDF4` | **0.068** | **0.013** | 0.239 | 0.573 |
| 라벤더 `#DACFFA` | **0.085** | **0.045** | 0.235 | 0.566 |
| 시안 `#00E5FF` | 0.171 | 0.127 | 0.240 | 0.549 |
| 미드블루 `#68A7EA` | 0.254 | 0.185 | 0.125 | 0.414 |
| 초록 `#18E022` | 0.307 | 0.285 | 0.299 | 0.544 |
| 핑크 `#FF2D95` | 0.375 | 0.336 | 0.252 | 0.432 |
| 주황 `#FF6E27` | 0.311 | 0.280 | 0.212 | 0.444 |
| 노랑 `#FFF01F` | 0.204 | 0.230 | 0.355 | 0.658 |

증상이 확인된 아바타(파란 낙서)에서 문제의 두 색이 0.013·0.045로 압도적으로 가깝고,
잘 보인다고 확인된 시안·초록·주황은 0.127 이상이다. **임계값 0.10**: 문제 색만 걸러지고
경계의 시안(0.127)은 살아남는다. 값은 잠정이며 계약 테스트가 위 표의 대표 케이스를 고정한다.

- 충돌 = `ΔE(팔레트 text색, 아바타 tone) < 0.10`
- 살아남은 후보가 3개 미만이면 거리 상위 3개를 쓴다 (후보가 비는 일은 구조적으로 없다)

## 구성 요소

### 1. tone 추출 — `AvatarService.toneFor(sha, identity:)` (avatars.dart)

```dart
Future<Color?> toneFor(String sha, {required GitIdentity identity})
```

1. `restore()` (기존 lazy 경로 그대로 — avatars.dart:242. `resolve()`가 이미 먼저 태운다)
2. 얼굴은 **본인이 쓴 커밋 sha 하나로** 기존 `resolve()`를 타서 알아낸다. 주소로 거르는
   조회 경로(`commits?author=`)를 먼저 만들었다가 뺐다: tone이 필요한 순간은 본인 아바타가
   그래프에 그려질 때뿐이고, 그러려면 본인 커밋이 이미 로드된 페이지에 있어야 한다 —
   그 행을 그리며 `resolve()`가 어차피 얼굴을 알아낸다. 새 경로가 벌어 주는 것은 없었고
   대가는 셋이었다: 신원 로드마다 요청 하나, 주소가 아무것도 못 맞히면 세션 내내 반복되는
   재요청, 그리고 사용자 이메일이 URL 질의 문자열에 실리는 일 — yogit의 어디에도 없던 일이다.
   `resolve()`를 타면 캐시·디스크·'이 주소에는 계정이 없다' 기억을 전부 그대로 쓴다.
3. 저장된 tone이 있으면 **즉시 반환**하고, 백그라운드에서 라이브 재계산 후 다르면 갱신한다.
   GitHub 아바타 URL은 사진을 바꿔도 안 바뀌므로(`?v=4`) 저장값은 첫 프레임용 fast path,
   라이브 디코드가 진실이다.
4. 없으면 이미지에서 계산: `NetworkImage(url, headers:).resolve()` + `ImageStreamListener`
   — 행이 이미 그리는 이미지와 같은 Flutter 이미지 캐시를 타므로 추가 요청이 없고,
   enterprise 토큰 헤더도 그대로 따라간다. `ui.Image.toByteData(rawStraightRgba)` → 픽셀
   산술평균 (큰 이미지는 stride로 4096픽셀 이하만 샘플링) → persist → 반환. `rawRgba`는
   알파가 곱해진 바이트를 주므로 반투명 픽셀이 검정 쪽으로 어두워진다 — 링이 마주하는 색은
   그려진 색이라 straight 쪽을 쓴다.
5. 조회 실패·디코드 실패·계정 없음·본인 커밋이 로드된 페이지에 없음 → null. 예외는 밖으로
   새지 않는다 — 픽셀을 못 읽어도 completer는 null로 닫힌다.

### 2. 지속화 — avatars.json에 `tone` 한 필드 (avatars.dart)

`RemoteAvatar`에 `tone`(Color?, 직렬화는 `#RRGGBB`) 추가. `AvatarStore.save()`(:134)와
`_avatarFor()`(:155) 두 곳만 손댄다. settings.json이 아닌 이유: 이 값은 원격 이미지의
파생 캐시라 생명주기가 avatars.json과 같고(잃어도 다시 계산, 실패 무시 — `_persist()`
정책 그대로), settings.json은 사용자가 직접 정한 취향이 사는 곳인 데다 `AppSettings`의
all-or-nothing 검증(settings.dart:753)에 새 필드를 끼우면 리셋 폭발 위험이 있다.

적어 둔 tone은 평범한 행 조회에도 살아남는다. 저자는 아는 얼굴이고 커미터는 처음 보는
사람인 행 — GitHub UI squash 머지가 남기는 `GitHub <noreply@github.com>`이 그 커미터다 —
은 `resolve()`의 캐시 경로를 못 타고 `_load()`까지 내려간다. 서버 응답에는 tone이 없으니
그대로 덮어쓰면 복원한 값이 메모리에서 사라지고 `_persist()`가 그 상태를 파일에 적는다.
그래서 `_load()`는 같은 URL인 얼굴에 한해 알고 있던 tone을 새 응답에 얹어 둔다 — 위 흐름
표의 '재실행' 줄이 사실이기 위한 조건이다. 사진이 바뀌면(URL이 달라지면) tone은 버리고
다시 읽는다.

### 3. 배정 필터 — `assignBranchPaletteIndexes()` 확장 (timeline_model.dart:720)

```dart
Map<int, int> assignBranchPaletteIndexes(
  List<GraphRow> rows,
  int seed, {
  List<int> refPaletteAssignments = ...,
  List<RefPaletteEntry>? refPalette,  // 팔레트 그대로. 레인 색은 안에서 읽는다
  Color? avoidTone,                   // 아바타 tone, null이면 오늘과 동일
})
```

`randomRefPaletteIndexes()`가 돌려준 무작위 후보에서 충돌 인덱스를 뺀다. **base
브랜치(항상 인덱스 0)와 핀 배정은 건드리지 않는다** — 사용자가 명시한 선택은 자동 조정보다
세다. 해시(`stableRefPaletteIndex`)는 줄어든 후보 목록 위에서 그대로 돌므로 같은
저장소·같은 tone이면 배정은 결정적이다.

Oklab 변환(~20줄, 순수 Dart)은 색 수학이 이미 사는 timeline_palette.dart에 둔다.

### 4. 배선 — TimelineScreen (timeline.dart, timeline_data.dart)

- `_TimelineScreenState`에 `Color? _avatarTone` 필드 하나.
- `_loadCommitIdentity()`(timeline_data.dart:320)가 identity를 확정한 직후:
  로드된 커밋에서 그 주소가 쓴 가장 최근 sha를 찾아 `toneFor(sha, identity:)` → 완료 시
  값이 다르면 `_rebuild(() { _avatarTone = tone; _rebuildGraph(); })`.
  identity 로드는 이미 initState·저장소 전환·프로필 적용 세 곳에서 다시 돌고(:693, :1030,
  :1304), 페이지가 도착할 때도 tone이 아직 없으면 한 번 더 시도한다 — 신원이 로그보다 먼저
  확정되는 순서가 흔해서 찾을 커밋이 아직 메모리에 없을 수 있다.
- sha는 저자 주소(소문자)로만 맞춘다. 커미터로 맞히지 않는 이유: `resolve()`는 넘겨받은
  identity 아래에 **그 커밋의 저자** 얼굴을 적어 두므로 커미터로 고른 sha는 남의 얼굴을
  본인 것으로 기억하게 된다.
- 왕복이 끝나면 서비스와 저장소가 그대로인지 확인한 뒤에 반영한다 — 저장소를 갈아탄 창에
  앞 저장소의 tone이 내려앉지 않도록.
- `_rebuildGraph()`(timeline.dart:1257)에서 `widget.refPalette`와 `_avatarTone`을 그대로
  넘긴다. 레인 색은 `refPaletteColorsAt`이 팔레트에서 읽어 주므로 호출부가 색 목록을 따로
  뽑지 않는다. `AvatarService.branchAssignments` 갱신은 지금 코드 그대로.

repaint는 확인됐다: `_rebuildGraph`가 `layoutGraph`로 GraphRow를 새로 만들고, GraphRow는
`operator ==`가 없어서(git.dart:1292) `CommitGraphPainter.shouldRepaint`(:842)의
`oldDelegate.row != row`가 참이 된다 — tone 도착으로 배정이 바뀌면 레일까지 전부 다시
그려진다. 별도 epoch는 필요 없다.

## 흐름

| 상황 | 보이는 일 |
|---|---|
| 첫 실행 (캐시 없음) | 기본 배정으로 뜸 → 몇 초 안에 tone 계산 → 충돌 레인만 색이 한 번 바뀜 |
| 재실행 | restore가 저장된 tone을 요청 없이 바로 준다 → 첫 페이지가 도착한 직후 조정된 배정이 붙고 색이 두 번 바뀌는 점멸은 없다 |
| 사진 교체 (URL 동일) | 저장값으로 뜬다. 라이브 재계산이 다르면 **새 tone을 적어 두고 다음 실행부터 반영** — 세션 중 배정을 갈아입히는 통보 경로는 만들지 않았다 |
| 신원 미설정 / 계정 없음 / 토큰 없음 / 본인 커밋이 로드된 페이지에 없음 | tone null → 오늘과 완전히 동일 |

## 계약 테스트

1. Oklab 거리 고정: 위 표의 대표 케이스 — 하늘·라벤더 vs `#C7D9EC` < 0.10,
   핑크 vs `#8A8F96` ≥ 0.10, 시안 vs `#C7D9EC` ≥ 0.10.
2. 밝은 tone + 기본 팔레트 → 무작위 배정 결과에 연한 두 인덱스가 나타나지 않는다.
3. tone과 충돌하는 색이라도 **핀 배정은 유지**된다.
4. base 브랜치는 tone과 무관하게 팔레트 0을 받는다.
5. 전 항목이 충돌하는 팔레트 → 거리 상위 3개로 배정된다 (후보 공집합 없음).
6. tone이 null이면 배정이 오늘과 완전히 같다 (기존 배정 테스트가 무수정 통과).
7. `tone` 필드가 avatars.json을 왕복한다 (save → load, 없던 파일·없던 필드 하위호환).
8. tone 도착이 레인 색을 갈아입힌다: fake `HttpSend` + 1×1 픽셀 PNG로 위젯 테스트,
   pump 전후 `AvatarService.branchAssignments` 변화 확인.
9. 같은 저장소·같은 tone이면 rebuild를 반복해도 배정이 같다.
10. 이미지 fetch 실패·깨진 바이트 → tone null, 예외 전파 없음, 배정 무변화.
11. 얼굴은 본인 커밋 sha로 `resolve()`를 타서 찾는다 — 요청 경로에 주소가 실리지 않고 같은
    사람의 다음 커밋은 요청 없이 답한다. 로드된 커밋에 본인 것이 없으면 tone은 null.

## 구현 단계 (단계마다 계약 테스트 먼저)

1. **순수 색 수학**: timeline_palette.dart에 Oklab 변환 + 충돌 필터. 테스트 1·5.
2. **배정 확장**: assignBranchPaletteIndexes 시그니처 확장. 테스트 2·3·4·6·9.
3. **지속화**: RemoteAvatar.tone + AvatarStore 왕복. 테스트 7.
4. **toneFor + 배선**: AvatarService.toneFor, TimelineScreen 연결. 테스트 8·10·11.
   기존 테스트 관례를 따른다 — AvatarService는 fake `HttpSend` 주입(app_test.dart:18783
   `avatarServiceOn`), AvatarStore는 임시 디렉터리 File 주입, 쓰기 대기는 `debugWritten`.

## 열린 결정

- **임계값 0.10은 잠정.** 4단계까지 넣고 실제 앱에서 본인 아바타로 확인한 뒤 조정한다.
  조정 지점은 상수 하나다.
- **설정 토글은 만들지 않는다.** 자동 조정이 싫으면 핀 배정이 탈출구다 — 핀은 항상 이긴다.
  실사용에서 불만이 나오면 그때 토글을 단다.
- **다른 참가자의 아바타는 범위 밖.** 팀원 아바타까지 피하는 배정은 후보를 다 태운다.
  필요해지면 "화면에 가장 자주 나오는 얼굴" 가중 방식을 그때 설계한다.
