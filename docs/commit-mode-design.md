# 커밋 모드 — 개발 설계

승인된 시안: [commit-mode-mockup.html](commit-mode-mockup.html). 시안 하단의
'동작 정의' 9개 항목과 'git 매핑' 표가 계약이고 이 문서는 그 계약을 어느 부품으로
어떻게 지키는지를 적는다. UI 라벨의 git 동작 이름(Stage · Unstage · Hunk ·
Discard · Stage All · Unstage All · untracked …)은 영문 그대로 쓴다.

## 요약

타임라인의 `Uncommitted changes` 행을 선택하면 우측 미리보기 판이 커밋 패널이
된다. 패널은 Unstaged / Staged 두 섹션으로 파일을 나눠 보이고 파일·헝크 단위
Stage / Unstage / Discard와 커밋 폼을 담는다. diff는 기존 full diff 워크스페이스를
그대로 쓰되 축이 둘로 갈린다 — Unstaged는 작업 트리 ↔ 인덱스, Staged는 인덱스 ↔
HEAD.

레이아웃을 확인한 결과 **큰 구조 변경은 필요 없다**: full diff가 사이드바와
타임라인 자리를 대체해도 미리보기 판은 나란히 살아남는다
(timeline.dart:1832-1935의 `_workspaceLayout`이 diff와 preview를 형제로 유지한다).
커밋 패널을 미리보기 판의 내용물로 태우면 시안의 "diff가 열려도 커밋 패널 유지"가
그대로 성립한다. 미리보기 배치(right/bottom/left)는 기존 사용자 설정을 따른다 —
시안은 right 배치를 그린 것이다.

## 목표와 비목표

목표 (시안 '동작 정의' 1~9 전부):

1. WIP 행 선택 → 커밋 패널 (두 섹션, 접기, Stage All / Unstage All)
2. 파일 단위 Stage / Unstage / Discard (hover 아이콘 + filebar 버튼)
3. Hunk 단위 Stage / Unstage / Discard (diff 헝크 헤더 버튼)
4. diff 축 전환 세그먼트 (Unstaged ↔ Staged), 파일 클릭 시 소속 섹션으로 자동 전환
5. 커밋 폼: 제목(50자 카운터) + 본문 + `--amend` + 커밋 버튼
6. 키보드: Space / ⌘↵ / ↑↓ / Esc
7. Discard 확인창 (untracked는 파일 삭제임을 명시)

비목표 (v2로 미룸 — 시안 명시): **라인 단위 스테이징 · 파일 트리 뷰 토글 · 스태시 ·
AI 커밋 메시지.** 그 밖에 이번에 하지 않는 것: 커밋 메시지 초안의 디스크 저장(앱
재시작이면 사라진다), Staged 축의 Blame(버튼 비활성), 무시된(ignored) 파일 표시,
서브모듈 내용 조작.

## 이미 있는 부품

| 필요한 일 | 있는 부품 | 위치 |
|---|---|---|
| WIP 합성 커밋 행 | `loadWorkingTree()`, `isWorkingTree` = `sha.isEmpty` | git.dart:3661, :240 |
| 미리보기 판이 diff 모드에서 살아남는 구조 | `_workspaceLayout` | timeline.dart:1832 |
| 커밋 패널 머리줄 `커밋 WIP · 부모 …` | `_previewCommitLine` | timeline_preview_pane.dart:277 |
| diff 열기/닫기와 Esc 사슬 | `_openFullDiff` / `_closeFullDiff` / `_onKeyEvent`의 escape | timeline_diff_mode.dart:153, :224, timeline.dart:1426 |
| 헝크 경계와 헤더 위젯 | `DiffDocument`/`DiffHunk`, `FullDiffHunkHeader` | full_diff_model.dart:221, full_diff_hunk_header.dart |
| 세그먼트 컨트롤 | `FullDiffSegmentedControl` | full_diff_header.dart:174 사용례 |
| 충돌 파일 stage (마커 검사) | `stageResolvedFile` | git.dart:3465 |
| 확인창 | `YogitAlert` / `showYogitAlert` | yogit_alert.dart:62, :380 |
| 감시자 억제 | `_changingRepository()` | timeline.dart:757 |
| 전체 리로드 (커밋 뒤) | `_reloadTimelineAfterCherryPick` | timeline_preview_pane.dart:1707 |
| 실제 저장소 테스트 골격 | `createGitFixture`/`runGit`/`writeAndCommit` | test/full_diff_git_test.dart:34-68 |
| 위젯 테스트 골격 | `FakeGitRepository` + `app()` | test/app_test.dart:18317 |

새로 만드는 것: **순수 라이브러리 하나(`lib/working_tree_status.dart`), git 층
메서드 한 벌, 영역 어댑터 하나, 커밋 패널 part 하나.**

## 데이터 모델

새 파일 `lib/working_tree_status.dart` — `local_state_signature.dart`처럼 git.dart가
import하는 순수 라이브러리. 파서와 패치 조립이 전부 여기 살아서 프로세스 없이
테스트된다.

`GitFileChange`를 확장하지 않고 새 타입을 만든다. 근거: `GitFileChange`는 status가
한 글자짜리 단일 문자열이고 untracked 여부를 `Expando` 꼼수(git.dart:2098)로
따로 다는 구조라, 한 경로가 X(인덱스)와 Y(작업 트리) 두 축의 상태를 동시에 갖는
porcelain v2를 담을 수 없다. 대신 축을 하나 고르면 `GitFileChange`로 투영하는
함수를 두어 full diff 쪽 재사용을 살린다.

```dart
enum WorkingTreeArea { unstaged, staged }

class WorkingTreeEntry {
  final String path;
  final String? origPath;      // 2(rename/copy) 레코드만
  final String indexStatus;    // X. '.', 'M', 'T', 'A', 'D', 'R', 'C'
  final String worktreeStatus; // Y. 위와 같은 집합
  final bool untracked;        // '?' 레코드
  final bool conflicted;       // 'u' 레코드. 이때 indexStatus/worktreeStatus는 XY 원문(UU 등)
  final bool submodule;        // <sub> 필드가 'S'로 시작
  final bool symlink;          // 관련 mode 필드가 120000
  // numstat 병합 결과. untracked·binary·conflicted는 null
  final int? unstagedAdditions, unstagedDeletions;
  final int? stagedAdditions, stagedDeletions;
  final bool unstagedBinary, stagedBinary;
}

class WorkingTreeStatus {
  final List<WorkingTreeEntry> entries;
  List<WorkingTreeEntry> get unstaged; // Y != '.' 이거나 untracked 이거나 conflicted
  List<WorkingTreeEntry> get staged;   // X != '.' 이고 !conflicted
  bool get hasConflict;
}
```

- **양쪽 동시 등장**: XY가 `MM`이면 같은 entry 하나가 `unstaged`와 `staged` 양쪽
  getter에 나온다. 행 글자는 섹션이 정한다 — Unstaged 행은 Y, Staged 행은 X.
- **rename**: `2` 레코드. `-z`에서는 `<path>\x00<origPath>` 두 토큰을 이어 소비해야
  한다(파서가 레코드 타입을 보고 토큰 하나를 더 읽는다). rename은 인덱스 축에서만
  나온다고 기대하되 파서는 XY 어느 쪽 R도 받아들인다.
- **삭제**: X 또는 Y가 `D`. Unstaged의 D는 "작업 트리에서 지워짐", Discard가 파일을
  되살린다.
- **untracked**: `?` 레코드. 글자 `A` + `untracked` 칩(시안 5). 통계 없음.
  `--untracked-files=all`을 줘서 디렉터리가 뭉치지 않고 파일 단위로 나온다.
- **무시된 파일**: `--ignored`를 주지 않는다. 목록에 없다.
- **서브모듈**: 행에 '서브모듈' 칩. 파일 단위 Stage / Unstage만, Discard와 헝크
  없음(포인터 되돌리기는 v1 범위 밖).
- **심볼릭 링크**: 파일 단위 전부 가능, 헝크 버튼 없음(의미가 없다).
- **바이너리**: numstat이 `-`를 주면 binary 플래그. 파일 단위 전부 가능, 헝크 없음.
- **충돌(u)**: Unstaged 섹션에 previewConflict 색 '충돌' 배지. Stage File은
  `stageResolvedFile` 경유(마커 잔재 거부). Discard·헝크 없음. 충돌 entry가 남아
  있으면 커밋 버튼 비활성('충돌 파일을 먼저 해결해야 합니다').

파서 시그니처와 porcelain v2 레코드:

```dart
/// git status --porcelain=v2 --untracked-files=all -z 원문을 파싱한다.
List<WorkingTreeEntry> parseStatusV2(String output);
```

| 레코드 | 형식 (공백 구분, -z라 레코드 사이는 NUL) |
|---|---|
| `1` | `1 XY sub mH mI mW hH hI path` |
| `2` | `2 XY sub mH mI mW hH hI R<score> path` + NUL + `origPath` |
| `u` | `u XY sub m1 m2 m3 mW h1 h2 h3 path` |
| `?` | `? path` |

투영 함수 — full diff와 미리보기 diff 재사용의 다리:

```dart
/// [area]에서 이 entry가 보일 GitFileChange. 그 축에 없으면 null.
GitFileChange? areaFileChange(WorkingTreeEntry entry, WorkingTreeArea area);
```

## git 명령 계약

모든 새 메서드는 `GitRepository`에 붙고 기존 `runner` 주입으로 테스트에서 가짜로
바뀐다. 성공 판정은 전부 exitCode 0, 실패는 stderr를 담은 `ProcessException` —
기존 `_run` 규칙 그대로.

### 목록

```
git status --porcelain=v2 --untracked-files=all -z
git diff --no-ext-diff --no-textconv --no-color --numstat -z            # unstaged 통계
git diff --no-ext-diff --no-textconv --no-color --numstat -z --cached   # staged 통계
```

`loadWorkingTreeStatus()`가 세 번을 돌려 `WorkingTreeStatus`로 병합한다. numstat
파싱은 기존 `_parseNumstat` 재사용. `--find-renames`는 status가 자체 rename 탐지를
하므로 numstat 쪽에도 `--find-renames=50%`를 같이 줘서 경로 키를 맞춘다.

### 파일 단위

| 동작 | 명령 | 비고 |
|---|---|---|
| Stage File | `git add -- :(literal)<path>` | untracked·수정·삭제 모두 이 하나로 기록된다 |
| Stage File (충돌) | 기존 `stageResolvedFile(path)` | 마커 잔재면 거부 |
| Stage All | `git add -A` | 저장소 루트에서 |
| Unstage File | `git restore --staged -- :(literal)<path>` | rename이면 `:(literal)old` `:(literal)new` 둘 다 — old가 인덱스로 돌아오고 new가 빠진다 |
| Unstage File (HEAD 없음) | `git rm --cached -r --quiet -- :(literal)<path>` | 최초 커밋 전에는 restore의 소스(HEAD)가 없다 |
| Unstage All | `git restore --staged -- :/` | HEAD 없으면 `git rm --cached -r --quiet -- :/` |
| Discard (tracked) | `git restore -- :(literal)<path>` | 소스는 기본값(인덱스) — staged 변경은 남는다. 작업 트리 삭제(D)도 이걸로 되살아난다 |
| Discard (untracked) | `resolveWorkingTreeFile(root, path)` 검증 후 Dart `File.delete()` | git 명령이 아니라 파일 삭제다. resolveWorkingTreeFile이 경로 탈출을 막는다 |
| 커밋 | 아래 별도 절 | |

HEAD 유무 판정은 WIP 행의 `parents.isEmpty`(loadWorkingTree가 이미 계산)를 쓴다 —
git을 다시 부르지 않는다.

### Hunk 단위 — 패치 재조립 알고리즘

이 기능에서 가장 틀리기 쉬운 곳이라 규칙을 못 박는다.

**원칙 1 — 패치는 항상 원문 문자열에서 자른다.** `parseUnifiedDiff`(git.dart:1668)는
`\ No newline at end of file` 줄을 header 종류로 오분류한다(git.dart:1713의 else
분기). 파싱된 `DiffLine`에서 패치를 재구성하면 이 줄과 원문 공백이 깨진다.
그래서 순수 함수는 diff 원문을 받는다:

```dart
/// [patch]는 파일 하나짜리 git diff 원문. [hunkIndex]번째 헝크만 남긴
/// 적용용 패치를 돌려준다. 헝크의 @@ 헤더가 [expected]와 다르면
/// HunkMovedException — 파일이 그 사이 바뀐 것이다.
String extractHunkPatch(
  String patch,
  int hunkIndex, {
  required ({int oldStart, int oldCount, int newStart, int newCount}) expected,
});
```

조립 규칙:

1. 줄 단위로 훑어 첫 `@@` 이전 전부를 **헤더 블록**으로 잡는다. `diff --git`,
   `index`, `old mode`/`new mode`, `new file mode`, `deleted file mode`,
   `--- `/`+++ ` 줄이 원문 그대로 보존된다. 단일 경로 diff라 파일 경계는 없다.
2. 헝크는 `@@`로 시작하는 줄부터 다음 `@@` 또는 EOF 직전까지.
   `\ No newline at end of file` 줄은 앞선 +/−/컨텍스트 줄에 붙은 것이라 자연히
   자기 헝크에 포함된다.
3. `hunkIndex`번째 헝크의 `@@ -a,b +c,d @@`를 파싱해 `expected` 네 값과 비교한다.
   하나라도 다르면 던진다 — 인덱스가 밀린 낡은 화면에서 눌린 것이니 아무것도
   적용하지 않는다. (UI가 보는 `DiffHunk`는 `,1`을 생략하는 git 원문과 표기가
   다를 수 있어 문자열 비교가 아니라 숫자 4개 비교다.)
4. 결과 = 헤더 블록 + 그 헝크 하나, 마지막 개행 보장.

**원칙 2 — 매 조작마다 diff를 새로 뜬다.** 적용 절차 (git 층):

```
stageHunk(path, hunkIndex, expected, {algorithm}):
  1. git diff --no-ext-diff --no-textconv --no-color --unified=3
         [algorithm.gitArguments] -- :(literal)path            # 신선한 원문
  2. extractHunkPatch(원문, hunkIndex, expected)               # 어긋나면 여기서 중단
  3. 패치를 git dir 아래 임시 파일로 쓴다 (yogit_keep_both_ 수법,
     git.dart:4042의 createTemp 패턴 — runner에 stdin이 없어서 파일로 준다)
  4. git apply --cached --whitespace=nowarn <임시파일>
  5. 임시 파일 삭제 (finally)

unstageHunk: 1의 diff에 --cached 추가, 4가 git apply --cached -R --whitespace=nowarn
discardHunk: 1은 stageHunk와 동일, 4가 git apply -R --whitespace=nowarn
```

한 헝크만 적용해도 좌표가 맞는 이유 — 헝크 헤더의 old쪽 좌표는 그 diff의 old쪽
전체 기준이다. unstaged diff의 old쪽은 **지금 인덱스 그대로**이고 staged diff의
new쪽(-R이 찾는 쪽)은 **지금 인덱스 그대로**라, 다른 헝크를 건너뛰어도 어긋날
것이 없다. 오프셋 문제는 "한 번 적용한 뒤 낡은 헝크 목록을 계속 쓸 때"만 생기므로
원칙 2(매번 새 diff)와 3번의 expected 검사로 원천 차단한다. 같은 이유로
`--recount`는 쓰지 않는다 — 헤더를 원문 그대로 보존하므로 재계산할 것이 없고,
--recount는 손으로 고친 패치를 위한 옵션이다. `--3way`·`--unidiff-zero`도 쓰지
않는다.

경우별 처리:

| 경우 | 처리 |
|---|---|
| untracked 파일 | diff에 아예 없다(합성 diff뿐). 헝크 버튼 자체를 그리지 않는다 — Stage File만 |
| staged 새 파일(A) | `new file mode` 헤더 + 헝크 하나. Unstage Hunk가 그대로 동작(-R이 인덱스에서 항목을 제거) — 파일 단위와 동치 |
| 삭제 파일(D) | `deleted file mode` 헤더 + 헝크 하나. Stage Hunk = 삭제를 인덱스에 기록 |
| rename(R) | 헝크 버튼 비활성, 파일 단위만. rename 헤더 패치의 부분 적용은 old/new 경로가 얽혀 v1에서 배제 |
| `\ No newline at end of file` | 원문 슬라이스에 포함되어 그대로 적용된다 (P4 테스트로 못 박음) |
| CRLF | 패치와 대상이 같은 저장소의 같은 바이트라 그대로 맞는다. `git apply`는 필터 없이 바이트를 비교한다. core.autocrlf 관련 -c 오버라이드를 주지 않는다 (P4 테스트) |
| 공백 무시 보기(`--ignore-all-space`) 중 | 헝크 버튼 비활성 + tooltip '공백 무시 보기에서는 Hunk 단위로 조작할 수 없습니다' — 그 패치는 컨텍스트가 실제 바이트와 달라 적용이 깨진다 |
| full-file 스코프 | 헝크 버튼은 hunks 스코프에서만. 거대 컨텍스트 헝크의 부분 적용은 의미가 없다 |
| diff 알고리즘 | 1번 diff에 UI가 보고 있는 알고리즘 인자를 그대로 전달 — 화면의 헝크와 빌더의 헝크가 같은 모양이어야 expected 검사가 통한다 |

### 커밋

```dart
/// 인덱스를 커밋하고 새 HEAD sha를 돌려준다.
Future<String> commitIndex({required String message, bool amend = false});
```

```
git -c core.editor=true commit [-​-amend] -m <message>
env: GIT_EDITOR=true, GIT_TERMINAL_PROMPT=0        # _runCherryPickCommand과 같은 세트
성공 후: git rev-parse HEAD
```

- message = 제목 + `\n\n` + 본문(본문이 비면 제목만). `-m` 한 인자로 넘긴다 —
  runner가 argv를 셸 없이 전달하므로 개행·따옴표가 안전하고 `-m`의 cleanup은
  whitespace 모드라 `#`로 시작하는 줄도 살아남는다.
- `--no-verify`를 주지 않는다 — 훅은 돌아야 한다.
- 이 저장소 최초의 `git commit` 호출이다(머지·리베이스는 commit-tree +
  update-ref로 만들어 왔다). WIP의 인덱스 커밋은 사용자의 훅·서명 설정을 그대로
  타야 하므로 porcelain commit이 맞다.

실패 → 사용자 문구 (stderr를 보고 분기, 못 알아보면 마지막 행 폴백):

| stderr 신호 | 폼 아래 빨간 인라인 문구 |
|---|---|
| `nothing to commit` / `no changes added` | `커밋할 Staged 파일이 없습니다.` (버튼 게이트가 있으니 경합 때만 보인다) |
| `Please tell me who you are` | `git 사용자 정보가 없습니다. git config user.name / user.email을 설정해 주세요.` |
| 훅 실패 (exit 1, 위 신호 없음) | `pre-commit 훅이 커밋을 거부했습니다.` + stderr 마지막 3줄 |
| `gpg failed` / `signing failed` | `커밋 서명에 실패했습니다.` + stderr 마지막 줄 |
| 그 외 | `커밋 실패:` + stderr 마지막 줄 |

`--amend`:

- 체크 시 제목·본문이 비어 있으면 `loadCommitMessage('HEAD')`로 채운다. 이미
  입력이 있으면 그대로 둔다(덮어쓰지 않는다). 체크 해제 시 채워 넣었던 값이면
  비운다.
- HEAD가 없으면(최초 커밋 전) 체크박스 비활성.
- 경고: 현재 브랜치에 upstream이 있고 `RepoRefs.aheadBehind[current].ahead == 0`
  이면 HEAD는 이미 원격에 있다 — 체크박스 아래 behindOrange 문구
  `이미 <upstream>에 올라간 커밋입니다. 수정하면 원격과 히스토리가 갈라집니다.`
  막지는 않는다(시안 8).
- 버튼 라벨: 평소 `Staged N개 파일 커밋`, amend 체크 시 `커밋 수정`.

### 영역 diff

`_revisionsFor`(git.dart:4904)는 건드리지 않는다 — WIP의 기존 의미(작업 트리 ↔
HEAD)를 쓰는 화면(blame 등)이 남아 있다. 대신 영역별 진입로를 추가한다:

```dart
Future<List<GitFileChange>> loadAreaFiles(WorkingTreeArea area);
Future<List<DiffLine>> loadAreaDiff(WorkingTreeArea area, GitFileChange file,
    {DiffAlgorithm algorithm, bool ignoreWhitespace, DiffScope scope});
Future<Uint8List> loadIndexBytes(String path);   // git show :0:<path>
```

| 영역 | 파일 목록 | diff | 결과쪽 바이트 |
|---|---|---|---|
| unstaged | `git diff <safeDiffArguments> --name-status -z --` (rev 없음) + `ls-files --others --exclude-standard -z` 덧붙임 (loadFiles의 기존 untracked 수법 재사용 — 합성 diff의 Expando가 같이 달린다) | `git diff … -- :(literal)path` (rev 없음: 작업 트리 ↔ 인덱스) | 작업 트리 파일 |
| staged | 같은 두 명령에 `--cached` | `git diff --cached … -- :(literal)path` (인덱스 ↔ HEAD; HEAD가 없어도 --cached는 빈 트리 기준으로 동작한다) | `:0:path` (인덱스 blob) |

full diff 컨트롤러에는 어댑터로 꽂는다 — 컨트롤러·워크스페이스의 로딩 코드를
건드리지 않는 게 목적이다:

```dart
/// FullDiffRepository 얼굴로 영역을 고정한다. loadFiles→loadAreaFiles,
/// loadDiff→loadAreaDiff, loadFileBytes→(unstaged: 위임 / staged: loadIndexBytes),
/// 나머지 다섯 멤버(root, loadDiffAlgorithmSetting, loadCommitMessage,
/// loadBlame, loadFileHistory)는 그대로 위임.
class WorkingTreeAreaRepository implements FullDiffRepository { … }
```

컨트롤러의 working tree 예외 처리(full_diff_controller.dart:1268, :1296 — WIP는
LRU 캐시를 타지 않는다)가 그대로 적용되므로 캐시 무효화 걱정이 없다. 컨트롤러에
공개 메서드 하나를 더한다:

```dart
/// stage/unstage 뒤 파일 목록과 열린 패치를 다시 읽는다. 선택 경로가
/// 살아 있으면 유지하고, 사라졌으면(헝크를 다 올렸다 등) 첫 파일로 간다.
Future<void> refreshWorkingTree();
```

구현은 `_wantedPath = state.selectedFile?.path` 세팅 후 `_loadFiles()` 재호출.

## 파괴적 동작의 안전장치

Discard만이 파괴적이다. Stage/Unstage는 인덱스만 오가고 내용은 잃지 않는다.
모든 Discard는 `showYogitAlert` 확인창을 먼저 띄운다. 확인 버튼은 기본 포커스가
아니다.

| 대상 | 제목 | 본문 | 확인 버튼 |
|---|---|---|---|
| tracked 파일 Discard | `변경 내용을 버릴까요?` | `<path>의 작업 트리 변경이 사라집니다. Staged 변경은 남습니다. 되돌릴 수 없습니다.` | `Discard` (deletedPink) |
| 작업 트리에서 삭제된 파일(D) | `삭제를 취소할까요?` | `<path>를 인덱스 내용으로 되살립니다.` | `되살리기` (파괴 아님 — 색도 기본) |
| untracked 파일 Discard | `파일을 삭제할까요?` | `추적되지 않는 파일이라 Discard는 파일 삭제입니다. <path>가 디스크에서 지워집니다. 되돌릴 수 없습니다.` | `삭제` (deletedPink) |
| Discard Hunk | `이 Hunk를 버릴까요?` | `이 Hunk의 변경이 작업 트리에서 사라집니다. 되돌릴 수 없습니다.` | `Discard Hunk` (deletedPink) |

- 이미 staged인 파일의 Discard 범위: Unstaged 행의 Discard는 **작업 트리 →
  인덱스 복원**(`git restore`, 소스 기본값)이라 staged 내용은 건드리지 않는다.
  Staged 행에는 Discard가 없다(시안 6 — Unstage 하나뿐).
- untracked Discard는 git이 아니라 파일 삭제다. `resolveWorkingTreeFile`이 경로가
  저장소 밖으로 새는 것을 막은 뒤 지운다. 디렉터리 단위 삭제는 없다 —
  `--untracked-files=all`이라 목록이 파일 단위다.
- 서브모듈·충돌 파일에는 Discard를 그리지 않는다.
- 커밋 실패 처리는 위 커밋 절의 표. 실패해도 인덱스와 폼 입력은 그대로 남는다.
- 연타 경합: 패널 전체가 `_commitModeBusy` 플래그 하나로 직렬화된다. busy 동안
  모든 버튼 비활성 — index.lock 충돌을 UI에서 막는다.

## UI 구성

### 새 part — `lib/timeline_commit_panel.dart`

`part of 'timeline.dart';` + `extension _TimelineCommitPanel on
_TimelineScreenState`. 범위: 커밋 패널 본문(두 섹션·파일 행·hover 액션·접기),
커밋 폼(제목·카운터·본문·amend·버튼·인라인 오류), Discard 확인창들, 상태 로딩과
`_runCommitAction` 오케스트레이션, 패널 키보드 커서.

상태 필드(모두 `_TimelineScreenState`에, 기존 캐시 필드 timeline.dart:450-453 옆):

```dart
WorkingTreeStatus? _commitStatus;            // null = 아직 안 읽음
Object? _commitStatusError;
var _commitModeBusy = false;
WorkingTreeArea _commitDiffArea = WorkingTreeArea.unstaged;
({WorkingTreeArea area, String path})? _commitCursor;   // Space·↑↓의 대상
var _commitUnstagedCollapsed = false, _commitStagedCollapsed = false;
final _commitTitle = TextEditingController();           // dispose에서 해제
final _commitBody = TextEditingController();
var _commitAmend = false;
String? _commitAmendPrefill;                 // amend가 채워 넣은 값 — 해제 시 지울 근거
String? _commitError;
```

### 기존 파일 변경점

| 파일:줄 | 변경 |
|---|---|
| timeline.dart:58-66 | `part 'timeline_commit_panel.dart';` 추가 |
| timeline.dart:1323 `_onKeyEvent` | ⌘↵ 분기 추가(아래 키보드 절), Space 분기 추가 |
| timeline.dart:1422 | 기존 Enter 토글에 `!shortcutModifierHeld` 가드 — 지금은 ⌘↵도 미리보기를 토글해 버린다 |
| timeline_preview_pane.dart:185-199 | `_previewBody(commit)` 자리에서 `commit.isWorkingTree && _cherryPickState == null`이면 `_commitPanel(commit)` |
| timeline_preview_pane.dart:167-184 | WIP 선택 중 힌트 줄 문구를 `Space Stage/Unstage · ⌘↵ 커밋 · ↑↓ 파일 이동 · Esc diff 닫기`로 |
| timeline_diff_mode.dart:153 `_openFullDiff` | WIP + 커밋 모드면 `repository: WorkingTreeAreaRepository(widget.repository, _commitDiffArea)`, `commits: [wip]`로 세션 생성. `_enterPreview`(:9)의 WIP 분기도 커밋 커서 파일로 |
| timeline_diff_mode.dart:388 `_embeddedFullDiff` | 세션이 커밋 모드면 워크스페이스에 영역·콜백 묶음 전달 |
| full_diff_workspace.dart:1118 부근 | `GlobalFileBar`에 커밋 모드 파라미터 전달, 헝크 액션을 unified/side-by-side 뷰로 내려보냄 |
| full_diff_header.dart:35 `GlobalFileBar` | 옵션 파라미터: `commitArea`, `onCommitAreaSelected`, `onStageFile`(라벨은 영역이 정한다 — Stage File / Unstage File). null이면 오늘 모습 그대로 |
| full_diff_hunk_header.dart:8 | `actions: List<Widget>` 옵션 슬롯 — 비면 오늘 모습 그대로. Stage Hunk/Unstage Hunk(mainAccent 테두리), Discard Hunk(deletedPink 테두리, unstaged 축만) |
| full_diff_unified_view.dart:128, full_diff_side_by_side_view.dart:138 | 헝크 액션 전달 |
| full_diff_controller.dart | `refreshWorkingTree()` 추가 |
| timeline_chrome.dart:257 `_normalStatusBarContent` | WIP 행 선택 중 legend 행 오른쪽에 시안 statusbar의 키 힌트 4개(`Space` `⌘↵` `↑↓` `Esc`, raised 배경 kbd 칩) |
| git.dart | `loadWorkingTreeStatus`, `stageFiles`, `unstageFiles`, `discardWorktreeFile`, `commitIndex`, `stageHunk`/`unstageHunk`/`discardHunk`, `loadAreaFiles`/`loadAreaDiff`/`loadIndexBytes`, `WorkingTreeAreaRepository` |
| test/app_test.dart `FakeGitRepository` | 위 메서드들의 콜백 슬롯 추가 (기존 `stageResolvedFileCallback` 방식 그대로) |

### 패널 시각 언어 (시안 CSS ↔ 코드 토큰)

| 시안 | 토큰 |
|---|---|
| `--panel` 패널 배경 / `--border` | `_palette.surface` / `_palette.border` (미리보기 판이 이미 쓰는 값) |
| `.frow.selected` `--sel` | `_palette.selectedRow` |
| hover `--raised`, 칩 배경 | `_palette.raised` |
| 글자 M 초록 / D 핑크 / R 보라 | `mainAccent` / `deletedPink` / `renamedPurple` (미리보기 행 규칙 그대로, timeline_preview_pane.dart:1059) |
| +N / −N | `mainAccent` / `hashRed` |
| `.act` Stage All 텍스트 버튼 | `_palette.interactive` — 시안의 #7AB8FF는 팔레트에 없어 가장 가까운 의미 토큰으로 정한다 |
| ↺ Discard 아이콘 / − Unstage 아이콘 | `deletedPink` / `behindOrange` |
| 50자 초과 카운터 | `behindOrange` |
| 커밋 버튼 배경 | `mainAccent`, 전경은 시안 값 `#0F1A13`을 이 part의 지역 상수로(팔레트에 어두운 전경 토큰이 없다) |
| diff 쪽 filebar·헝크 버튼 | full_diff_theme 토큰 (`fullDiffHeader`, `fullDiffDivider`, `fullDiffAccent`) + 의미색 |
| 글꼴 | 경로·카운터·헝크는 `technicalFontFamily`(Menlo) |

### 상호작용 흐름

- 파일 행 클릭 → `_commitCursor` 이동, `_commitDiffArea = 행의 섹션`,
  `_openFullDiff`(커밋 모드 세션) 또는 열린 세션이면 어댑터 교체가 필요한지 보고
  같은 축이면 `selectFile`, 다른 축이면 세션 재생성(시안 1 — 자동 전환).
- filebar 세그먼트 전환 → 같은 경로가 반대 축 목록에 있으면 그 파일로, 없으면 그
  축의 첫 파일로 세션 재생성. 반대 축이 비어 있으면 세그먼트 비활성.
- Stage/Unstage/Discard 어느 것이든:

```
_runCommitAction(action, {reloadTimeline = false}):
  _commitModeBusy = true
  _changingRepository(() async {
    await action()                                  # git 층 호출
  })
  _reloadCommitMode(timelineToo: reloadTimeline)
  실패(ProcessException·HunkMovedException) → SnackBar + _reloadCommitMode
  finally busy 해제
```

- 커밋: `_runCommitAction(commitIndex…, reloadTimeline: true)` 성공 시 폼 비우기.
  타임라인 리로드는 `_reloadTimelineAfterCherryPick(null)` 재사용 — 트리가 아직
  더러우면 WIP 행(0행)이 남아 선택이 유지되고, 깨끗해지면 새 HEAD가 0행이라
  자연스럽게 그리로 간다.

## 상태 갱신과 캐시

**작업 트리 감시자는 새로 달지 않는다.** 근거: (1) ref 감시는 `refWatchPaths`가
gitDir을 이미 보고 있어 `git add`가 고쳐 쓰는 `.git/index`의 변경 이벤트는
지금도 온다 — 다만 fingerprint(`loadLocalStateSignature`)가 HEAD·브랜치 끝만
읽어서 아무 일도 일어나지 않는다. 이 무해한 동작을 유지한다. (2) 작업 트리
파일 감시는 저장소 크기에 비례해 비싸고 기존 설계가 일부러 뺀 것이다
(timeline.dart:705-730). 커밋 패널은 **앱이 벌인 조작 뒤 명시적 리로드**만
한다. 밖(터미널)에서 바뀐 것은 다음 선택/조작 때 새 status 읽기로 따라잡고,
헝크 조작은 expected 검사가 낡음을 걸러 준다.

조작 뒤 무엇을 다시 읽고 무엇을 버리나:

| 시점 | 하는 일 |
|---|---|
| 모든 조작 공통 (`_reloadCommitMode`) | `loadWorkingTreeStatus()` 다시 읽어 `_commitStatus` 교체 · `_previewFiles.remove('')` / `_previewFileLists.remove('')` / `_previewDiffs.removeWhere(key.sha == '')` — 빈 sha 키가 무효화되지 않는 기존 함정(timeline_preview_pane.dart:1804)을 여기서 끊는다 · full diff가 WIP에 열려 있으면 `session.refreshWorkingTree()` |
| stage / unstage (파일·헝크·All) | 위가 전부. WIP 행은 남아 있으므로 타임라인은 그대로 |
| discard | 위 + status가 비면(마지막 변경을 버렸으면) `_reloadTimelineAfterCherryPick(null)` — WIP 행이 사라져야 한다 |
| 커밋 (amend 포함) | 위 + `_reloadTimelineAfterCherryPick(null)` — HEAD가 움직였고 행 전체가 다시 서야 한다. refs 재로드와 `_syncLocalSignature`까지 그 함수가 이미 한다 |

`_changingRepository()`는 **git을 부르는 조작 전부**를 감싼다 — 커밋이 HEAD를
움직일 때 감시자가 "밖에서 바뀌었어요" 알림을 띄우지 않게 하는 기존 규칙이다.
untracked 파일 삭제(Dart delete)는 ref를 안 건드리지만 같은 헬퍼로 감싸 규칙을
하나로 유지한다.

## 키보드와 포커스

충돌 점검 결과 (page_scroll_shortcuts.dart, timeline.dart:1323 `_onKeyEvent`,
timeline_diff_mode.dart:73 `_onPreviewKeyEvent`, full_diff_workspace.dart:975):

| 시안 키 | 기존 사용자 | 판정과 해법 |
|---|---|---|
| Space | 없음 (⌘⇧Space만 diff의 공백 토글) | 루트 `_onKeyEvent`에 추가. 단 `_editableDescendantHasFocus`면 무시 — 제목·본문 TextField의 스페이스 입력은 IME로 들어가고 키 이벤트는 ignored로 버블되므로 이 가드가 없으면 타자 중에 stage가 토글된다 |
| ⌘↵ | 없음. 단 기존 Enter 분기(timeline.dart:1422)가 modifier를 안 보고 미리보기를 토글한다 | ⌘↵ 분기를 Enter 분기보다 앞에, Enter 분기에 `!shortcutModifierHeld` 가드 추가 |
| ↑↓ | 타임라인 포커스 = 커밋 이동, 미리보기 포커스 = 파일 이동 | 유지. WIP 선택 중 미리보기 포커스의 ↑↓(`_onPreviewKeyEvent`:103)가 커밋 커서를 Unstaged→Staged를 가로질러 평평하게 움직인다(섹션 끝에서 다음 섹션 첫 행). ⌘↑↓(타임라인 포커스에서 파일 걷기)도 같은 경로를 탄다 |
| Esc | 알림 → full diff → 인접 diff → 패널 닫기 사슬(timeline.dart:1426) | 그대로 — 시안의 'Esc = diff 닫기'가 이미 성립한다 |

- Space·⌘↵는 **WIP 행이 선택되어 있고 패널이 열려 있을 때만** 동작한다.
  루트 Focus(timeline.dart:1800)가 모든 키를 버블로 받으므로 한 곳에서 처리된다.
- Space의 대상은 `_commitCursor` 행: Unstaged 행이면 Stage, Staged 행이면 Unstage.
  커서가 없으면 무시.
- ⌘↵는 커밋 버튼과 같은 게이트(Staged 비면·제목 비면·충돌 남으면·busy면 무시).
  TextField에 포커스가 있어도 동작한다 — 제목 치고 바로 커밋하는 흐름.
- vim 키(j/k)는 `normalizeNavigationKey`가 이미 화살표로 접어 주므로 공짜다.

## TDD 구현 계획

각 단계는 그 단계의 테스트가 전부 초록이고 기존 스위트와 `flutter analyze lib
test`가 무결한 지점이다. 순수 로직을 앞에 놓는다. 실제 저장소 통합 테스트가
필요한 곳(P3·P4·P5 — git apply·commit의 실제 동작이 관건)과 가짜 주입으로
충분한 곳(P1·P2·P6·P7·P8)을 가른다.

### P1 · porcelain v2 파서 (순수)

(a) `test/working_tree_status_test.dart`:
- `parses an ordinary modified entry into both axes` (XY `MM` — unstaged와 staged 양쪽 getter에 같은 entry)
- `parses a staged-only and an unstaged-only entry into one section each` (`M.` / `.M`)
- `parses a -z rename record consuming the second NUL token` (`2` + `R100` + origPath)
- `parses untracked, conflict, submodule and symlink records` (`?` / `u` UU / sub `S...` / mode 120000)
- `merges numstat pairs onto the right axis and flags binary`
- `derives section letters from the section's own axis` (MM → Unstaged 행 M, Staged 행 M / `.D` → D는 Unstaged만)
- `keeps conflicted entries out of the staged section`

(b) `lib/working_tree_status.dart`의 `WorkingTreeEntry`/`WorkingTreeStatus`/
`parseStatusV2`/`areaFileChange` + numstat 병합 함수.
(c) 완료: 위 테스트 초록, git 프로세스 0회.

### P2 · 헝크 패치 조립 (순수)

(a) 같은 파일에 추가:
- `extracts the middle hunk with the file header block intact`
- `keeps a trailing no-newline marker inside its hunk`
- `keeps new-file and deleted-file headers verbatim`
- `throws HunkMovedException when the expected header numbers differ`
- `accepts a header that omits ,1 counts` (`@@ -3 +3 @@`)
- `returns a patch ending with a newline`

(b) `extractHunkPatch` + `HunkMovedException`.
(c) 완료: P1·P2 초록.

### P3 · git 층 — 목록·파일 단위·커밋 (실제 저장소)

(a) `test/commit_mode_git_test.dart` — full_diff_git_test.dart의
`createGitFixture`/`runGit`/`writeAndCommit` 수법 복사:
- `loadWorkingTreeStatus reads both sections from a real repository` (MM 파일 하나로)
- `stageFiles records an untracked file and a worktree deletion`
- `unstageFiles restores the index entry and leaves the worktree alone`
- `unstaging a staged rename brings back the old path and drops the new one`
- `unstage falls back to rm --cached before the first commit`
- `discard restores a tracked file from the index and keeps staged changes`
- `discard of an untracked file deletes it and refuses a path outside the repository`
- `commitIndex creates the commit with title and body and returns HEAD`
- `commitIndex --amend rewrites HEAD`
- `commitIndex surfaces identity-missing and pre-commit-hook failures` (fixture에 `user.name` 제거 / `.git/hooks/pre-commit` exit 1 스크립트)

(b) `loadWorkingTreeStatus`, `stageFiles`, `unstageFiles`, `discardWorktreeFile`,
`commitIndex`.
(c) 완료: 실제 저장소에서 `git status`로 검산하는 expect가 전부 초록.

### P4 · git 층 — 헝크 (실제 저장소, 이 기능의 심장)

(a) 같은 테스트 파일에 추가:
- `stageHunk stages exactly one of two hunks` (뒤에 `git diff --cached` 검산)
- `staging the second hunk first leaves the first hunk unstaged and intact`
- `two consecutive stageHunk calls survive because each re-reads the diff` (오프셋 재현 시나리오)
- `stageHunk refuses a moved hunk and stages nothing` (조작 사이에 파일을 바꿔 expected 불일치)
- `unstageHunk returns one hunk to the worktree-only side`
- `unstageHunk on a staged new file empties its index entry`
- `discardHunk removes the hunk from the worktree only`
- `hunk operations keep a file without trailing newline byte-identical`
- `hunk operations keep CRLF line endings byte-identical`
- `stageHunk builds the patch with the algorithm the caller passes`

(b) `stageHunk`/`unstageHunk`/`discardHunk` (임시 파일 + `git apply`).
(c) 완료: 각 테스트가 조작 후 저장소 상태를 `git diff`/`git diff --cached`
원문으로 검산해 초록.

### P5 · 영역 diff 어댑터 (실제 저장소 + 위임 확인)

(a) 같은 파일 또는 `test/commit_mode_area_test.dart`:
- `loadAreaDiff(unstaged) compares worktree to index and (staged) index to HEAD` (MM 파일이 축마다 다른 헝크)
- `loadAreaFiles(unstaged) appends untracked files with a synthetic all-add diff`
- `loadAreaFiles(staged) lists a rename with both paths`
- `loadIndexBytes reads the :0 blob`
- `staged area diff works before the first commit`
- `WorkingTreeAreaRepository delegates the remaining members` (가짜 runner로 인자만 확인)

(b) `loadAreaFiles`/`loadAreaDiff`/`loadIndexBytes` + `WorkingTreeAreaRepository`
+ `FullDiffSessionController.refreshWorkingTree()` (컨트롤러 테스트는
`test/full_diff_controller_test.dart`에 `refreshWorkingTree keeps the selected
path and reloads files` 한 줄 추가).
(c) 완료: 위 초록 + 기존 full diff 스위트 무결.

### P6 · 커밋 패널 위젯 (FakeGitRepository)

(a) `test/commit_mode_panel_contract_test.dart` — 시안 '동작 정의'를 한 줄씩:
- `selecting the WIP row turns the preview into the commit panel` (Key `commit-panel`)
- `two sections show counts, collapse, and Stage All / Unstage All`
- `an unstaged row hover offers Stage File and Discard, a staged row only Unstage File`
- `an untracked row carries the untracked chip and its discard dialog names deletion`
- `a tracked discard dialog says staged changes survive, and confirming calls git`
- `a conflicted row blocks commit and routes Stage File through the marker check`
- `the title counter turns orange past 50 without blocking`
- `the commit button is disabled while staged is empty or the title is blank`
- `--amend prefills the HEAD message, relabels the button, and warns on a pushed HEAD`
- `commit failure shows the inline message and keeps the form`
- `busy disables every action until the running one lands`

(b) `lib/timeline_commit_panel.dart` + `_previewBody` 분기 + FakeGitRepository
콜백 슬롯.
(c) 완료: 시안 1·4·5·6·7·8이 테스트 이름으로 존재하고 초록.

### P7 · diff 연결 (FakeGitRepository)

(a) `test/commit_mode_diff_contract_test.dart`:
- `clicking a file opens the diff on that file's own area and the panel survives` (diff 모드에서 `commit-panel`이 그대로 있다 — 시안 핵심)
- `the file bar shows the area segment and Stage File / Unstage File per area`
- `switching the segment reopens the same path on the other axis or its first file`
- `hunk headers carry Stage Hunk and Discard Hunk on unstaged, Unstage Hunk alone on staged`
- `hunk buttons hide for untracked, renamed and binary files and under ignore-whitespace`
- `a hunk action refreshes the open diff and the panel counts`
- `Esc closes the diff back to the timeline with the panel intact`

(b) GlobalFileBar·FullDiffHunkHeader·workspace·`_openFullDiff` 연결.
(c) 완료: 시안 1·2·3이 테스트 이름으로 존재하고 초록.

### P8 · 키보드와 갱신 오케스트레이션 (FakeGitRepository)

(a) `test/commit_mode_keys_contract_test.dart`:
- `Space toggles the cursor row between the sections`
- `Space typed into the title field stays a space` (`_editableDescendantHasFocus` 가드)
- `Cmd+Enter commits from the list and from the title field, plain Enter still toggles the preview`
- `arrows walk the cursor across the section boundary`
- `a commit reloads the timeline and keeps the WIP row while the tree is dirty`
- `discarding the last change removes the WIP row`
- `a stage invalidates the empty-sha preview caches` (기존 함정의 계약화)
- `mutations run inside _changingRepository so no external-change prompt appears`

(b) `_onKeyEvent`/`_onPreviewKeyEvent` 분기, `_runCommitAction`/`_reloadCommitMode`,
상태바 힌트.
(c) 완료: 전체 스위트 + `flutter analyze lib test` 무결. 시안 9까지 테스트
이름으로 존재.

커밋은 P1~P8 단계별로, 각 단계가 홀로 되돌릴 수 있게.

## 위험 목록

| 위험 | 완화 |
|---|---|
| 낡은 헝크에 대고 apply — 엉뚱한 내용이 스테이징 | 매 조작마다 diff를 새로 뜨고 expected 숫자 4개 검사. 불일치는 아무것도 적용하지 않고 리로드 (P4 테스트) |
| `\ No newline` 줄을 파싱 결과로 재조립하다 유실 | 패치는 원문 문자열 슬라이스만. `parseUnifiedDiff` 산출물로 패치를 만들지 않는다는 것을 P2가 못 박는다 |
| 공백 무시·다른 알고리즘 화면과 빌더 diff 불일치 | ignore-whitespace 중 헝크 버튼 비활성, 알고리즘 인자는 빌더에 그대로 전달 |
| index.lock 경합 (연타·동시 조작) | `_commitModeBusy` 직렬화 — 패널 전체가 한 번에 한 조작 |
| 커밋·amend가 감시자 알림을 유발 | 전 조작 `_changingRepository()` 래핑 (P8 테스트) |
| 빈 sha 캐시가 조작 후에도 낡은 목록을 보여줌 | `_reloadCommitMode`가 세 캐시의 '' 키를 지운다 — 알려진 함정의 봉인 (P8 테스트) |
| rename 헝크 부분 적용의 경로 얽힘 | v1은 rename 파일 헝크 버튼 비활성, 파일 단위만 |
| 최초 커밋 전(HEAD 없음) restore/amend 실패 | `parents.isEmpty` 판정으로 `rm --cached` 폴백, amend 비활성 (P3 테스트) |
| 훅·서명·identity로 커밋이 조용히 실패 | GIT_TERMINAL_PROMPT=0으로 멈춤 방지, stderr 분기 문구 (P3 테스트) |
| Space가 제목 입력을 가로챔 | editable 포커스 가드 (P8 테스트) |
| ⌘↵이 기존 Enter 토글에 먹힘 | Enter 분기에 modifier 가드 추가 (P8 테스트) |
| status와 diff --find-renames의 rename 판정이 어긋남 | numstat·영역 diff에 `--find-renames=50%`를 일관 전달. 그래도 어긋나면 행 통계만 빠질 뿐 동작은 깨지지 않는다 |
| untracked 삭제가 심볼릭 링크를 타고 저장소 밖을 지움 | `resolveWorkingTreeFile` 검증 후에만 삭제 (P3 테스트) |

추측임을 밝혀 두는 것 하나: porcelain v2에서 rename이 작업 트리 축(`.R`)으로
나오는 경우는 없다고 보고 설계했다(작업 트리 rename은 삭제+untracked로 갈라진다).
파서는 방어적으로 어느 축의 R도 받아들이므로 이 추측이 틀려도 목록이 깨지지는
않고 헝크 버튼 비활성 규칙이 R 상태 전체에 걸려 있어 조작도 안전하다.

## 완료 정의

- `flutter analyze lib test` 무결
- 새 테스트 전부 + 기존 스위트 전체 green
- 시안 '동작 정의' 9개 항목 각각이 P6~P8의 테스트 이름으로 존재한다
- 시안이 정하지 않은 결정(색 토큰 매핑, 감시자 미도입, rename 헝크 비활성)이 이
  문서에 근거와 함께 남아 있다
