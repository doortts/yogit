# Full Diff Hunk 작업 화면 1차 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full Diff를 Hunk 블록 중심의 코드 리뷰 화면으로 바꾸고, 데이터
요청과 화면 상태를 전용 컨트롤러로 분리합니다.

**Architecture:** `GitRepository`는 원본 patch 행과 파일 목록만 읽고,
`DiffDocument`가 행을 Hunk와 앵커로 묶습니다. `FullDiffSessionController`는
커밋·부모·파일·옵션·로딩·캐시를 관리하며, `DiffScreen`과 하위 위젯은
상태를 받아 화면만 그립니다.

**Tech Stack:** Flutter, Dart, Git CLI, `ChangeNotifier`, `flutter_test`

## Global Constraints

- 구현 기준 문서:
  `docs/superpowers/specs/2026-07-27-full-diff-workspace-design.md`
- 1차의 유일한 콘텐츠 모드는 Hunk입니다. File, Blame, History,
  `View in full file`, Split, 구문 강조, 단어 단위 강조, 미니맵,
  `Open in editor`, Full Diff 초기 보기 설정은 2·3차에서 추가합니다.
- 현재의 `Unified`·`Side-by-side` 조작은 화면에서 제거합니다. Split은
  2차에서 Hunk 표시 옵션으로 다시 추가합니다.
- Git patch는 `--unified=3`으로 읽습니다. 공백 변경 무시는
  `--ignore-all-space`를 사용합니다.
- Hunk와 전체 행은 필요한 만큼만 만듭니다. Hunk 목록을 하나의 큰
  `Column`으로 만들지 않습니다.
- 화면 전체에 D2Coding을 적용하지 않습니다. 기술 정보와 소스는 Menlo,
  D2Coding, Monaco 순서의 글꼴 묶음을 사용합니다. 일반 설명과 조작
  기능은 시스템 UI 글꼴을 사용합니다.
- D2Coding은 한국어와 고정폭 정렬이 함께 필요할 때만 대체 글꼴로
  사용합니다.
- 페이지 스크롤은 미리보기와 Full Diff 모두
  `Command-Shift-Up/Down`, 48px, 첫 입력 100ms 애니메이션을 사용합니다.
- 옵션을 바꾸는 동안 마지막으로 성공한 Hunk 문서를 유지합니다. 새
  요청이 실패하면 마지막으로 성공한 알고리즘과 공백 설정으로
  돌아갑니다.
- 작업 트리 diff는 오래 유지하는 캐시에 넣지 않습니다.
- 기존 머지 부모 선택, 열 너비 저장, 텍스트 선택, 파일·커밋 키보드
  이동, Escape 복귀 동작을 유지합니다.
- 새 런타임 패키지는 추가하지 않습니다.

## 파일 구성

- Create: `lib/full_diff_model.dart`
  - `DiffDocument`, `DiffHunk`, `DiffAnchor`와 Hunk 해석을 담당합니다.
- Create: `lib/full_diff_controller.dart`
  - Full Diff 세션 상태, 요청 순서, 캐시, 선택 명령을 담당합니다.
- Create: `lib/full_diff_hunk_view.dart`
  - 필요한 Hunk 카드만 만들고 소스 행과 선택 상태를 그립니다.
- Create: `lib/full_diff_header.dart`
  - 파일 머리글과 두 번째 줄의 도구 모음을 그립니다.
- Create: `lib/page_scroll_shortcuts.dart`
  - 미리보기와 Full Diff가 공유할 키 판별, intent, 이동량을 제공합니다.
- Create: `lib/typography.dart`
  - UI 글꼴과 기술 정보용 고정폭 글꼴을 한곳에서 정의합니다.
- Modify: `lib/git.dart`
  - 공백 무시 옵션, 고정 문맥 수, 원본 바이트 읽기 경계를 추가합니다.
- Modify: `lib/diff_screen.dart`
  - 세 열 배치와 하위 위젯 조합만 남기고 전용 컨트롤러를 구독합니다.
- Modify: `lib/timeline.dart`
  - 공통 페이지 스크롤과 글꼴 정의를 사용합니다.
- Modify: `test/app_test.dart`
  - 기존 Full Diff 통합 테스트를 새 화면 구조에 맞춥니다.
- Create: `test/full_diff_model_test.dart`
  - Hunk, 줄 범위, 함수 문맥, 앵커를 검증합니다.
- Create: `test/full_diff_controller_test.dart`
  - 요청 순서, 캐시, 옵션 복원, 선택 상태를 검증합니다.
- Create: `test/full_diff_widgets_test.dart`
  - 머리글, 도구 모음, Hunk 카드, 글꼴, 접근성을 검증합니다.
- Create: `test/page_scroll_shortcuts_test.dart`
  - 공통 키 판별과 48px 이동을 검증합니다.

---

### Task 0: 날짜 경계에 의존하는 기존 테스트 안정화

2026-07-27 01:17 KST에 전체 테스트를 실행했을 때 제품 코드와 무관한 날짜
제목 테스트 3개가 실패했습니다. 테스트 데이터가 `현재 시각 - 2시간`을
Today로 가정해서 자정 직후에는 전날이 되기 때문입니다. 제품 코드는
바꾸지 않고 테스트 날짜만 같은 달력 날짜로 고정합니다.

**Files:**

- Modify: `test/app_test.dart:4068-4225`
- Modify: `test/app_test.dart:4507-4555`

**Interfaces:**

- Consumes: `dateGroupLabel`이 시각 차이가 아니라 현지 달력 날짜를
  기준으로 묶는 현재 동작
- Produces: 하루 중 어느 시각에 실행해도 같은 결과를 내는 날짜 제목
  위젯 테스트

- [ ] **Step 1: 세 테스트의 오늘 timestamp를 달력 날짜로 만듭니다**

세 테스트 안의 `stamp(Duration ago)`를 다음 지역 함수로 바꿉니다.

```dart
final now = DateTime.now();
final today = DateTime(now.year, now.month, now.day);
int stampOn(DateTime day, {int minute = 0}) =>
    day.add(Duration(minutes: minute)).millisecondsSinceEpoch ~/ 1000;
```

두 커밋 테스트에서는 오늘 커밋을 `stampOn(today)`로, 이틀 전 커밋을
`stampOn(today.subtract(const Duration(days: 2)))`로 만듭니다. 머지
테스트에서는 `M`을 `stampOn(today, minute: 2)`, `F`를
`stampOn(today, minute: 1)`, `P`를 이틀 전으로 만듭니다.

- [ ] **Step 2: 오전 2시 이전에 실패했던 테스트만 실행합니다**

Run:

```bash
flutter test test/app_test.dart --plain-name 'date rows head their group, boxed at the hash column'
flutter test test/app_test.dart --plain-name 'only the first date heading takes the selection'
flutter test test/app_test.dart --plain-name 'the date heading row paints its rails at full row size'
```

Expected: 세 명령 모두 `All tests passed!`

- [ ] **Step 3: 전체 기준선을 다시 확인합니다**

Run: `flutter test`

Expected: `All tests passed!`

- [ ] **Step 4: 테스트 수정만 커밋합니다**

```bash
git add test/app_test.dart
git commit -m "test: stabilize date heading fixtures"
```

### Task 1: Hunk 문서 모델과 해석기

**Files:**

- Create: `lib/full_diff_model.dart`
- Create: `test/full_diff_model_test.dart`

**Interfaces:**

- Consumes: `List<DiffLine>` from `GitRepository.loadDiff`
- Produces:
  - `DiffDocument.fromLines(List<DiffLine>)`
  - `DiffDocument.headers`
  - `DiffDocument.hunks`
  - `DiffDocument.rows`
  - `DiffHunk.anchor`
  - `DiffHunk.rangeLabel`

- [ ] **Step 1: 두 Hunk와 함수 문맥을 담은 실패 테스트를 작성합니다**

```dart
test('groups patch rows into hunks with readable ranges and anchors', () {
  final document = DiffDocument.fromLines(const [
    DiffLine(kind: DiffLineKind.header, text: 'diff --git a/a.pas b/a.pas'),
    DiffLine(
      kind: DiffLineKind.hunk,
      text: '@@ -10,3 +10,4 @@ procedure ConfigureWindow',
    ),
    DiffLine(
      kind: DiffLineKind.context,
      text: 'begin',
      oldNumber: 10,
      newNumber: 10,
    ),
    DiffLine(
      kind: DiffLineKind.delete,
      text: 'Scale := 1;',
      oldNumber: 11,
    ),
    DiffLine(
      kind: DiffLineKind.add,
      text: 'Scale := PixelRatio;',
      newNumber: 11,
    ),
    DiffLine(
      kind: DiffLineKind.hunk,
      text: '@@ -40 +41,2 @@',
    ),
    DiffLine(
      kind: DiffLineKind.add,
      text: 'Log(Scale);',
      newNumber: 41,
    ),
  ]);

  expect(document.headers.single, startsWith('diff --git'));
  expect(document.hunks, hasLength(2));
  expect(document.hunks.first.rangeLabel, '−10,3  +10,4');
  expect(document.hunks.first.context, 'procedure ConfigureWindow');
  expect(document.hunks.first.anchor.oldLine, 11);
  expect(document.hunks.first.anchor.newLine, 11);
  expect(document.hunks.last.rangeLabel, '−40  +41,2');
  expect(document.rows, hasLength(4));
});
```

삭제만 있는 Hunk의 앵커가 이전 줄만 갖는 테스트와 잘못된 `@@` 행에서
`FormatException`을 내는 테스트도 같은 파일에 작성합니다.

- [ ] **Step 2: 모델 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_model_test.dart`

Expected: FAIL because `full_diff_model.dart` and `DiffDocument` do not exist

- [ ] **Step 3: 바꿀 수 없는 모델과 Hunk 해석기를 작성합니다**

```dart
final _hunkHeader = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: ?(.*))?$',
);

@immutable
class DiffAnchor {
  const DiffAnchor({
    required this.hunkIndex,
    required this.oldLine,
    required this.newLine,
  });

  final int hunkIndex;
  final int? oldLine;
  final int? newLine;

  String get id => 'hunk-$hunkIndex-${oldLine ?? 0}-${newLine ?? 0}';
}

@immutable
class DiffHunk {
  const DiffHunk({
    required this.index,
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.context,
    required this.lines,
    required this.anchor,
  });

  final int index;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String context;
  final List<DiffLine> lines;
  final DiffAnchor anchor;

  String get rangeLabel {
    String range(int start, int count) => count == 1 ? '$start' : '$start,$count';
    return '−${range(oldStart, oldCount)}  +${range(newStart, newCount)}';
  }
}

@immutable
class DiffDocument {
  const DiffDocument({
    required this.headers,
    required this.hunks,
    required this.rows,
  });

  static const empty = DiffDocument(
    headers: <String>[],
    hunks: <DiffHunk>[],
    rows: <DiffLine>[],
  );

  final List<String> headers;
  final List<DiffHunk> hunks;
  final List<DiffLine> rows;

  factory DiffDocument.fromLines(List<DiffLine> lines) {
    final headers = <String>[];
    final hunks = <DiffHunk>[];
    final rows = <DiffLine>[];
    RegExpMatch? currentHeader;
    List<DiffLine>? currentLines;

    void finishHunk() {
      final header = currentHeader;
      final sourceLines = currentLines;
      if (header == null || sourceLines == null) return;

      int? oldAnchor;
      int? newAnchor;
      for (final line in sourceLines) {
        if (line.kind != DiffLineKind.add &&
            line.kind != DiffLineKind.delete) {
          continue;
        }
        oldAnchor ??= line.oldNumber;
        newAnchor ??= line.newNumber;
      }

      final index = hunks.length;
      final immutableLines = List<DiffLine>.unmodifiable(sourceLines);
      hunks.add(
        DiffHunk(
          index: index,
          oldStart: int.parse(header.group(1)!),
          oldCount: int.parse(header.group(2) ?? '1'),
          newStart: int.parse(header.group(3)!),
          newCount: int.parse(header.group(4) ?? '1'),
          context: header.group(5) ?? '',
          lines: immutableLines,
          anchor: DiffAnchor(
            hunkIndex: index,
            oldLine: oldAnchor,
            newLine: newAnchor,
          ),
        ),
      );
      rows.addAll(immutableLines);
    }

    for (final line in lines) {
      if (line.kind == DiffLineKind.header) {
        headers.add(line.text);
        continue;
      }
      if (line.kind == DiffLineKind.hunk) {
        finishHunk();
        currentHeader = _hunkHeader.firstMatch(line.text);
        if (currentHeader == null) {
          throw FormatException('Invalid hunk header: ${line.text}');
        }
        currentLines = <DiffLine>[];
        continue;
      }
      currentLines?.add(line);
    }
    finishHunk();

    return DiffDocument(
      headers: List<String>.unmodifiable(headers),
      hunks: List<DiffHunk>.unmodifiable(hunks),
      rows: List<DiffLine>.unmodifiable(rows),
    );
  }
}
```

`DiffDocument.fromLines`는 Hunk가 없으면 빈 `hunks`와 `rows`를
반환합니다. `rows`에는 header와 hunk marker를 넣지 않고 실제 소스
행만 순서대로 넣습니다. `List.unmodifiable`로 외부 변경을 막습니다.

- [ ] **Step 4: 모델 테스트를 통과시킵니다**

Run: `flutter test test/full_diff_model_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: 모델을 커밋합니다**

```bash
git add lib/full_diff_model.dart test/full_diff_model_test.dart
git commit -m "feat: model full diff hunks"
```

### Task 2: Git 옵션과 원본 바이트 경계

**Files:**

- Modify: `lib/git.dart:1-15`
- Modify: `lib/git.dart:538-690`
- Modify: `test/git_test.dart`
- Modify: `test/app_test.dart:6760-6795`

**Interfaces:**

- Consumes: `DiffAlgorithm`, `GitCommit`, parent SHA, path
- Produces:
  - `abstract interface class FullDiffRepository`
  - `GitRepository.loadDiff(..., bool ignoreWhitespace = false)`
  - `GitRepository.loadBlobBytes(String revision, String path)`
  - `RawCommandRunner`

- [ ] **Step 1: Git 인자와 바이트 보존 실패 테스트를 작성합니다**

`test/git_test.dart`의 알고리즘 테스트 옆에 다음 검증을 추가합니다.

```dart
test('requests three context lines and optionally ignores whitespace', () async {
  final calls = <List<String>>[];
  final repository = GitRepository(
    '.',
    runner: (executable, arguments, {workingDirectory}) async {
      calls.add(arguments);
      return ProcessResult(1, 0, '', '');
    },
  );
  final item = _commit('a', ['b']);

  await repository.loadDiff(
    item,
    'lib/a.dart',
    algorithm: DiffAlgorithm.histogram,
    ignoreWhitespace: true,
  );

  expect(calls.single, containsAllInOrder([
    '--unified=3',
    '--ignore-all-space',
    '--diff-algorithm=histogram',
  ]));
});
```

임시 Git 저장소에 `[0xff, 0xfe, 0x00, 0x41]`을 쓴 파일을 커밋한 뒤
`loadBlobBytes(commit.sha, 'raw.bin')`이 같은 바이트를 반환하는 테스트도
작성합니다.

- [ ] **Step 2: 새 테스트가 실패하는지 확인합니다**

Run:

```bash
flutter test test/git_test.dart --plain-name 'requests three context lines and optionally ignores whitespace'
flutter test test/git_test.dart --plain-name 'loads committed blob bytes without decoding them'
```

Expected: FAIL because `ignoreWhitespace` and `loadBlobBytes` do not exist

- [ ] **Step 3: 저장소 인터페이스와 raw runner를 추가합니다**

```dart
import 'dart:convert';
import 'dart:typed_data';

typedef RawCommandRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

Future<ProcessResult> runRawProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  stdoutEncoding: null,
  stderrEncoding: utf8,
);

abstract interface class FullDiffRepository {
  Future<List<GitFileChange>> loadFiles(
    GitCommit commit, {
    String? parent,
  });

  Future<List<DiffLine>> loadDiff(
    GitCommit commit,
    String path, {
    String? parent,
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
    bool ignoreWhitespace = false,
  });
}
```

`GitRepository`가 `FullDiffRepository`를 구현하게 하고 생성자에
`RawCommandRunner rawRunner = runRawProcess`를 추가합니다.

- [ ] **Step 4: diff 인자와 바이트 읽기를 구현합니다**

`loadDiff`의 인자는 다음 순서를 사용합니다.

```dart
[
  'diff',
  '--no-ext-diff',
  '--no-textconv',
  '--no-color',
  '--unified=3',
  if (ignoreWhitespace) '--ignore-all-space',
  ...algorithm.gitArguments,
  ...await _revisionsFor(commit, parent),
  '--',
  path,
]
```

`loadBlobBytes`는 문자열 변환 없이 결과를 복사합니다.

```dart
Future<Uint8List> loadBlobBytes(String revision, String path) async {
  final result = await rawRunner(
    gitExecutable,
    ['show', '$revision:$path'],
    workingDirectory: root,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      gitExecutable,
      ['show', '$revision:$path'],
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return Uint8List.fromList((result.stdout as List<int>));
}
```

`FakeGitRepository.loadDiff`와 관련 callback에도 `ignoreWhitespace` 인자를
추가합니다. 기존 호출은 기본값 `false`로 유지합니다.

- [ ] **Step 5: Git 테스트와 기존 테스트를 통과시킵니다**

Run:

```bash
flutter test test/git_test.dart
flutter test test/app_test.dart --plain-name 'opens the full diff and preserves timeline state on escape'
```

Expected: 두 명령 모두 `All tests passed!`

- [ ] **Step 6: Git 경계를 커밋합니다**

```bash
git add lib/git.dart test/git_test.dart test/app_test.dart
git commit -m "feat: preserve full diff options and bytes"
```

### Task 3: Full Diff 세션 컨트롤러

**Files:**

- Create: `lib/full_diff_controller.dart`
- Create: `test/full_diff_controller_test.dart`

**Interfaces:**

- Consumes: `FullDiffRepository`, `List<GitCommit>`, `DiffDocument.fromLines`
- Produces:
  - `FullDiffSessionController.initialize()`
  - `selectCommit`, `selectParent`, `selectFile`
  - `selectAlgorithm`, `setIgnoreWhitespace`, `setWrapLines`
  - `setFocusMode`, `selectHunk`, `stepHunk`
  - immutable `FullDiffSessionState`

- [ ] **Step 1: 초기 선택과 Hunk 생성 실패 테스트를 작성합니다**

```dart
test('loads the first file and selects the first hunk', () async {
  final repository = FakeFullDiffRepository(
    files: const [
      GitFileChange(
        path: 'lib/a.dart',
        status: 'M',
        additions: 1,
        deletions: 1,
      ),
    ],
    lines: const [
      DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@ main'),
      DiffLine(kind: DiffLineKind.delete, text: 'old', oldNumber: 1),
      DiffLine(kind: DiffLineKind.add, text: 'new', newNumber: 1),
    ],
  );
  final controller = FullDiffSessionController(
    repository: repository,
    commits: [commit('1', parents: const ['0'])],
    initialIndex: 0,
  );

  await controller.initialize();

  expect(controller.state.selectedPath, 'lib/a.dart');
  expect(controller.state.document?.hunks, hasLength(1));
  expect(controller.state.activeHunkIndex, 0);
  expect(controller.state.loadingFiles, isFalse);
  expect(controller.state.loadingDiff, isFalse);
});
```

같은 파일에 다음 테스트도 작성합니다.

- 늦게 끝난 이전 파일 요청이 새 커밋의 파일을 덮지 않습니다.
- 알고리즘이나 공백 설정을 바꾸는 동안 기존 문서를 유지합니다.
- 옵션 요청이 실패하면 마지막 성공 옵션으로 돌아갑니다.
- 커밋 diff는 같은 키를 한 번만 읽고 작업 트리 diff는 매번 읽습니다.
- 부모나 파일을 바꾸면 첫 Hunk를 선택합니다.
- `stepHunk`는 첫 번째와 마지막에서 멈춥니다.

- [ ] **Step 2: 컨트롤러 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_controller_test.dart`

Expected: FAIL because `FullDiffSessionController` does not exist

- [ ] **Step 3: 상태와 cache key를 정의합니다**

```dart
typedef FullDiffCacheKey = ({
  String sha,
  String? parent,
  String path,
  DiffAlgorithm algorithm,
  bool ignoreWhitespace,
});

@immutable
class FullDiffSessionState {
  const FullDiffSessionState({
    required this.commitIndex,
    required this.parent,
    required this.files,
    required this.selectedPath,
    required this.document,
    required this.activeHunkIndex,
    required this.algorithm,
    required this.displayedAlgorithm,
    required this.ignoreWhitespace,
    required this.displayedIgnoreWhitespace,
    required this.wrapLines,
    required this.focusMode,
    required this.loadingFiles,
    required this.loadingDiff,
    required this.error,
  });

  final int commitIndex;
  final String? parent;
  final List<GitFileChange> files;
  final String? selectedPath;
  final DiffDocument? document;
  final int activeHunkIndex;
  final DiffAlgorithm algorithm;
  final DiffAlgorithm displayedAlgorithm;
  final bool ignoreWhitespace;
  final bool displayedIgnoreWhitespace;
  final bool wrapLines;
  final bool focusMode;
  final bool loadingFiles;
  final bool loadingDiff;
  final Object? error;

  factory FullDiffSessionState.initial(
    GitCommit commit,
    int commitIndex,
  ) => FullDiffSessionState(
    commitIndex: commitIndex,
    parent: commit.parents.isEmpty ? null : commit.parents.first,
    files: const <GitFileChange>[],
    selectedPath: null,
    document: null,
    activeHunkIndex: 0,
    algorithm: DiffAlgorithm.gitSetting,
    displayedAlgorithm: DiffAlgorithm.gitSetting,
    ignoreWhitespace: false,
    displayedIgnoreWhitespace: false,
    wrapLines: true,
    focusMode: false,
    loadingFiles: false,
    loadingDiff: false,
    error: null,
  );
}
```

`wrapLines`의 초기값은 `true`, `focusMode`와 `ignoreWhitespace`의 초기값은
`false`로 둡니다. `copyWith`는 nullable 필드를 지울 수 있도록 내부
sentinel 값을 사용합니다.

- [ ] **Step 4: 요청 세대 번호와 옵션 복원을 구현합니다**

```dart
class FullDiffSessionController extends ChangeNotifier {
  FullDiffSessionController({
    required this.repository,
    required this.commits,
    required int initialIndex,
  }) : state = FullDiffSessionState.initial(
         commits[initialIndex.clamp(0, commits.length - 1)],
         initialIndex.clamp(0, commits.length - 1),
       );

  final FullDiffRepository repository;
  final List<GitCommit> commits;
  final Map<FullDiffCacheKey, Future<DiffDocument>> _cache = {};
  int _fileGeneration = 0;
  int _diffGeneration = 0;
  FullDiffSessionState state;

  Future<void> initialize() => _loadFiles();
}
```

파일 요청은 `_fileGeneration`, diff 요청은 `_diffGeneration`과 요청 당시
커밋·부모·경로를 함께 확인합니다. 옵션 변경은 `document`를 지우지 않고
`loadingDiff`만 켭니다. 성공하면 표시 옵션을 요청 옵션과 맞추고,
실패하면 요청 옵션을 표시 옵션으로 되돌립니다. 실패한 Future는
`_cache`에서 제거합니다.

- [ ] **Step 5: 컨트롤러 테스트를 통과시킵니다**

Run: `flutter test test/full_diff_controller_test.dart`

Expected: `All tests passed!`

- [ ] **Step 6: 컨트롤러를 커밋합니다**

```bash
git add lib/full_diff_controller.dart test/full_diff_controller_test.dart
git commit -m "feat: control full diff sessions"
```

### Task 4: 공통 페이지 스크롤

**Files:**

- Create: `lib/page_scroll_shortcuts.dart`
- Create: `test/page_scroll_shortcuts_test.dart`
- Modify: `lib/timeline.dart:628-651`
- Modify: `lib/timeline.dart:2566-2588`
- Modify: `test/app_test.dart:6240-6350`

**Interfaces:**

- Consumes: `KeyEvent`, `HardwareKeyboard`, `ScrollController`
- Produces:
  - `pageScrollStep = 48.0`
  - `PageScrollIntent`
  - `pageScrollIntentFor(KeyEvent)`
  - `applyPageScroll(...)`

- [ ] **Step 1: 키 판별과 이동량 실패 테스트를 작성합니다**

```dart
test('recognizes only command shift vertical arrows', () {
  expect(
    pageScrollIntentFor(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: LogicalKeyboardKey.arrowDown,
        timeStamp: Duration.zero,
      ),
      metaPressed: true,
      shiftPressed: true,
    )?.direction,
    1,
  );
  expect(
    pageScrollIntentFor(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: LogicalKeyboardKey.arrowDown,
        timeStamp: Duration.zero,
      ),
      metaPressed: true,
      shiftPressed: false,
    ),
    isNull,
  );
});
```

가짜 `ScrollPosition` 대신 작은 위젯에 실제 `ScrollController`를 붙여
48px 이동, 위·아래 끝 제한, 반복 입력의 즉시 이동을 검증합니다.

- [ ] **Step 2: 새 테스트가 실패하는지 확인합니다**

Run: `flutter test test/page_scroll_shortcuts_test.dart`

Expected: FAIL because the shared shortcut module does not exist

- [ ] **Step 3: 공통 intent와 이동 함수를 작성합니다**

```dart
const pageScrollStep = 48.0;

class PageScrollIntent extends Intent {
  const PageScrollIntent(this.direction);
  final int direction;
}

PageScrollIntent? pageScrollIntentFor(
  KeyEvent event, {
  required bool metaPressed,
  required bool shiftPressed,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  if (!metaPressed || !shiftPressed) return null;
  return switch (event.logicalKey) {
    LogicalKeyboardKey.arrowUp => const PageScrollIntent(-1),
    LogicalKeyboardKey.arrowDown => const PageScrollIntent(1),
    _ => null,
  };
}
```

`applyPageScroll`은 `position.pixels + direction * pageScrollStep`을
최소·최대 범위로 제한합니다. `animate`가 참이면 100ms `Curves.easeOut`,
거짓이면 `jumpTo`를 사용합니다.

- [ ] **Step 4: 타임라인의 중복 구현을 공통 함수로 바꿉니다**

`_onKeyEvent`에서 `pageScrollIntentFor`를 먼저 확인하고, 미리보기가 열려
있을 때 `_previewScrollController`에 적용합니다. 파일 이동용
`Command-Up/Down`은 Shift가 없을 때만 처리합니다. 기존
`_scrollPreview`는 삭제합니다.

- [ ] **Step 5: 공통 단위 테스트와 미리보기 통합 테스트를 실행합니다**

Run:

```bash
flutter test test/page_scroll_shortcuts_test.dart
flutter test test/app_test.dart --plain-name 'preview shortcuts scroll and distinguish identities'
flutter test test/app_test.dart --plain-name 'meta arrows walk the open preview through its files'
```

Expected: 세 명령 모두 `All tests passed!`

- [ ] **Step 6: 스크롤 동작을 커밋합니다**

```bash
git add lib/page_scroll_shortcuts.dart lib/timeline.dart \
  test/page_scroll_shortcuts_test.dart test/app_test.dart
git commit -m "refactor: share page scroll shortcuts"
```

### Task 5: 용도별 글꼴

**Files:**

- Create: `lib/typography.dart`
- Modify: `lib/diff_screen.dart:20-25`
- Modify: `lib/timeline.dart:1990-2090`
- Modify: `lib/timeline.dart:2445-2540`
- Modify: `test/app_test.dart:5980-6080`
- Modify: `test/app_test.dart:6250-6320`

**Interfaces:**

- Consumes: bundled D2Coding and macOS Menlo
- Produces:
  - `technicalFontFamily`
  - `technicalFontFallback`
  - `koreanFixedFontFamily`

- [ ] **Step 1: 글꼴 역할을 검증하는 실패 테스트로 기존 기대값을 바꿉니다**

Full Diff 키보드 테스트의 글꼴 검증을 다음처럼 바꿉니다.

```dart
final source = tester.widget<Text>(find.text('body of newer/one.dart'));
expect(source.style?.fontFamily, technicalFontFamily);
expect(source.style?.fontFamilyFallback, technicalFontFallback);

final commitTitle = tester.widget<Text>(find.text('newer commit').first);
expect(commitTitle.style?.fontFamily, isNull);
```

미리보기 hash는 Menlo 묶음을 사용하고 일반 작성자 이름은 시스템 글꼴을
사용하는 기대값도 추가합니다.

- [ ] **Step 2: 변경한 글꼴 테스트가 실패하는지 확인합니다**

Run:

```bash
flutter test test/app_test.dart --plain-name 'the diff screen walks files and commits from the keyboard'
flutter test test/app_test.dart --plain-name 'preview shortcuts scroll and distinguish identities'
```

Expected: FAIL because the current technical font is D2Coding

- [ ] **Step 3: 글꼴 상수를 만들고 사용처를 옮깁니다**

```dart
import 'package:flutter/material.dart';

const technicalFontFamily = 'Menlo';
const technicalFontFallback = <String>['D2Coding', 'Monaco'];
const koreanFixedFontFamily = 'D2Coding';
const koreanFixedFontFallback = <String>['Menlo', 'Monaco'];
const technicalTextStyle = TextStyle(
  fontFamily: technicalFontFamily,
  fontFamilyFallback: technicalFontFallback,
);
```

Full Diff 전체를 감싼 `Theme`과 `DefaultTextStyle.merge`를 제거합니다.
경로, hash, 줄 번호, Hunk 범위, 변경 수, 알고리즘 값, 단축키, 소스
행에만 기술 정보용 글꼴을 명시합니다. 커밋 제목, 작성자, 버튼, 메뉴,
설명은 스타일에 `fontFamily`를 넣지 않습니다.

타임라인에서 `cellFont`를 사용하던 기술 정보는 새 상수로 바꿉니다.
테스트가 가져다 쓰던 `cellFont`와 `cellFontFallback`도 새 이름으로
바꿉니다.

- [ ] **Step 4: 글꼴 관련 테스트를 통과시킵니다**

Run:

```bash
flutter test test/app_test.dart --plain-name 'the diff screen walks files and commits from the keyboard'
flutter test test/app_test.dart --plain-name 'preview shortcuts scroll and distinguish identities'
flutter test test/app_test.dart --plain-name 'the four data columns use the Korean-capable mono face'
```

Expected: 세 명령 모두 `All tests passed!`

- [ ] **Step 5: 글꼴 변경을 커밋합니다**

```bash
git add lib/typography.dart lib/diff_screen.dart lib/timeline.dart \
  test/app_test.dart
git commit -m "style: apply role-based monospace fonts"
```

### Task 6: Hunk 목록 위젯

**Files:**

- Create: `lib/full_diff_hunk_view.dart`
- Create: `test/full_diff_widgets_test.dart`

**Interfaces:**

- Consumes: `DiffDocument`, active Hunk index, `wrapLines`
- Produces:
  - `HunkListView`
  - `HunkCard`
  - `Map<String, GlobalKey> anchorKeys`

- [ ] **Step 1: Hunk 카드 표시와 선택 실패 테스트를 작성합니다**

```dart
testWidgets('shows readable hunk cards without raw patch headers', (tester) async {
  final document = DiffDocument.fromLines(const [
    DiffLine(kind: DiffLineKind.header, text: 'diff --git a/a.pas b/a.pas'),
    DiffLine(
      kind: DiffLineKind.hunk,
      text: '@@ -10,2 +10,2 @@ procedure ConfigureWindow',
    ),
    DiffLine(
      kind: DiffLineKind.delete,
      text: 'Scale := 1;',
      oldNumber: 10,
    ),
    DiffLine(
      kind: DiffLineKind.add,
      text: 'Scale := PixelRatio;',
      newNumber: 10,
    ),
  ]);

  await tester.pumpWidget(
    MaterialApp(
      home: HunkListView(
        document: document,
        activeHunkIndex: 0,
        wrapLines: true,
        onHunkSelected: (_) {},
      ),
    ),
  );

  expect(find.text('−10,2  +10,2'), findsOneWidget);
  expect(find.text('procedure ConfigureWindow'), findsOneWidget);
  expect(find.text('1 / 1'), findsOneWidget);
  expect(find.textContaining('diff --git'), findsNothing);
  expect(find.text('−'), findsOneWidget);
  expect(find.text('+'), findsOneWidget);
});
```

문맥 3줄과 추가·삭제 배경, active 테두리, Hunk별 `SelectionArea`,
빈 문서 상태, `ListView.builder` 사용을 확인하는 테스트를 추가합니다.

- [ ] **Step 2: 위젯 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_widgets_test.dart`

Expected: FAIL because `HunkListView` does not exist

- [ ] **Step 3: 지연 생성 Hunk 목록을 작성합니다**

```dart
class HunkListView extends StatelessWidget {
  const HunkListView({
    required this.document,
    required this.activeHunkIndex,
    required this.wrapLines,
    required this.onHunkSelected,
    this.controller,
    this.anchorKeys,
    super.key,
  });

  final DiffDocument document;
  final int activeHunkIndex;
  final bool wrapLines;
  final ValueChanged<int> onHunkSelected;
  final ScrollController? controller;
  final Map<String, GlobalKey>? anchorKeys;

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const Key('hunk-list'),
    controller: controller,
    itemCount: document.hunks.length,
    itemBuilder: (context, index) {
      final hunk = document.hunks[index];
      return HunkCard(
        key: anchorKeys?[hunk.anchor.id] ?? ValueKey(hunk.anchor.id),
        hunk: hunk,
        selected: index == activeHunkIndex,
        positionLabel: '${index + 1} / ${document.hunks.length}',
        wrapLines: wrapLines,
        onSelected: () => onHunkSelected(index),
      );
    },
  );
}
```

각 `HunkCard` 안에만 `SelectionArea`를 둡니다. 줄 번호 영역은 이전·새
번호 두 칸과 marker 한 칸으로 고정합니다. 줄바꿈을 끄면 Menlo 글자
폭으로 계산한 Hunk 콘텐츠 너비를 사용해 가로 스크롤이 생기게 합니다.

- [ ] **Step 4: 위젯 테스트를 통과시킵니다**

Run: `flutter test test/full_diff_widgets_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: Hunk 목록을 커밋합니다**

```bash
git add lib/full_diff_hunk_view.dart test/full_diff_widgets_test.dart
git commit -m "feat: render selectable hunk blocks"
```

### Task 7: 파일 머리글과 Diff 도구 모음

**Files:**

- Create: `lib/full_diff_header.dart`
- Modify: `test/full_diff_widgets_test.dart`

**Interfaces:**

- Consumes: 현재 파일, Hunk 위치, 알고리즘, 공백·줄바꿈·집중 모드 상태
- Produces:
  - `DiffFileHeader`
  - `DiffToolbar`

- [ ] **Step 1: 고정 이름과 인접 알고리즘 값의 실패 테스트를 작성합니다**

```dart
testWidgets('keeps the algorithm name fixed beside its selected value', (
  tester,
) async {
  DiffAlgorithm? selected;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DiffToolbar(
          activeHunkIndex: 1,
          hunkCount: 7,
          algorithm: DiffAlgorithm.histogram,
          ignoreWhitespace: false,
          wrapLines: true,
          focusMode: false,
          loading: false,
          onPreviousHunk: () {},
          onNextHunk: () {},
          onAlgorithmSelected: (value) => selected = value,
          onIgnoreWhitespaceChanged: (_) {},
          onWrapLinesChanged: (_) {},
          onFocusModeChanged: (_) {},
        ),
      ),
    ),
  );

  expect(find.text('diff 알고리즘'), findsOneWidget);
  expect(find.text('Histogram'), findsOneWidget);
  expect(find.text('2 / 7'), findsOneWidget);
  expect(find.text('Unified'), findsNothing);
  expect(find.text('Side-by-side'), findsNothing);
});
```

파일 경로, 상태, 추가·삭제 수, Hunk 활성 표시, loading indicator,
토글 접근성 상태를 확인하는 테스트도 작성합니다.

- [ ] **Step 2: 새 머리글 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_widgets_test.dart`

Expected: FAIL because `DiffFileHeader` and `DiffToolbar` do not exist

- [ ] **Step 3: 머리글과 도구 모음을 작성합니다**

`DiffFileHeader`는 경로, 상태, `+N −N`, 활성 `Hunk`만 표시합니다. 아직
구현하지 않은 File, Blame, History, 인코딩, 외부 편집기 동작은
표시하지 않습니다.

알고리즘 조작은 선택값 자체를 버튼 이름으로 쓰지 않습니다.

```dart
Semantics(
  container: true,
  button: true,
  label: 'diff 알고리즘: ${algorithm.label}',
  child: ExcludeSemantics(
    child: Row(
      children: [
        PopupMenuButton<DiffAlgorithm>(
          key: const Key('diff-algorithm'),
          tooltip: 'diff 알고리즘',
          onSelected: onAlgorithmSelected,
          itemBuilder: (context) => [
            for (final value in DiffAlgorithm.values)
              PopupMenuItem(
                value: value,
                child: Text(value.label),
              ),
          ],
          child: const Text('diff 알고리즘'),
        ),
        const SizedBox(width: 8),
        Text(
          algorithm.label,
          key: const Key('diff-algorithm-value'),
          style: technicalTextStyle,
        ),
      ],
    ),
  ),
)
```

이전·다음 버튼은 Hunk가 없거나 끝에 닿았을 때 비활성화합니다. 각
토글은 `Semantics(toggled: value, label: ...)`로 상태를 알립니다.
위젯 테스트의 `SemanticsTester`로 알고리즘 이름과 선택값이
`diff 알고리즘: Histogram`이라는 하나의 버튼으로 읽히는지도
확인합니다.

- [ ] **Step 4: 머리글 위젯 테스트를 통과시킵니다**

Run: `flutter test test/full_diff_widgets_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: 머리글을 커밋합니다**

```bash
git add lib/full_diff_header.dart test/full_diff_widgets_test.dart
git commit -m "feat: add full diff header and toolbar"
```

### Task 8: DiffScreen을 컨트롤러와 Hunk 화면으로 교체

**Files:**

- Modify: `lib/diff_screen.dart`
- Modify: `test/app_test.dart:2860-3300`
- Modify: `test/app_test.dart:5980-6240`

**Interfaces:**

- Consumes:
  - `FullDiffSessionController`
  - `DiffFileHeader`
  - `DiffToolbar`
  - `HunkListView`
- Produces: Hunk 중심의 `DiffScreen`

- [ ] **Step 1: 기존 통합 테스트를 Hunk 화면 기대값으로 바꿉니다**

`opens the full diff and preserves timeline state on escape` 테스트에서
다음을 확인합니다.

```dart
expect(find.byKey(const Key('hunk-list')), findsOneWidget);
expect(find.text('−1  +1'), findsOneWidget);
expect(find.text('1 / 1'), findsWidgets);
expect(find.text('Unified'), findsNothing);
expect(find.text('Side-by-side'), findsNothing);
expect(find.text('diff 알고리즘'), findsOneWidget);
expect(find.text('Git setting'), findsOneWidget);
```

기존 `side-by-side diff marks additions and deletions` 테스트는
`hunk blocks mark additions and deletions`로 바꾸고 Hunk 카드 안의
marker와 배경을 확인합니다.

- [ ] **Step 2: 바꾼 통합 테스트가 실패하는지 확인합니다**

Run:

```bash
flutter test test/app_test.dart --plain-name 'opens the full diff and preserves timeline state on escape'
flutter test test/app_test.dart --plain-name 'hunk blocks mark additions and deletions'
```

Expected: FAIL because the current screen still shows Unified and Side-by-side

- [ ] **Step 3: 화면이 컨트롤러를 소유하고 구독하게 바꿉니다**

```dart
class DiffScreen extends StatefulWidget {
  const DiffScreen({
    required this.repository,
    required this.commits,
    required this.initialIndex,
    this.controller,
    this.columnWidths = const FullDiffColumnWidths(),
    this.onColumnWidthsChanged,
    super.key,
  });

  final FullDiffRepository repository;
  final List<GitCommit> commits;
  final int initialIndex;
  final FullDiffSessionController? controller;
  final FullDiffColumnWidths columnWidths;
  final ValueChanged<FullDiffColumnWidths>? onColumnWidthsChanged;

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}
```

`initState`에서 주입받은 컨트롤러가 없으면 만들고 `initialize()`를
호출합니다. 화면이 만든 컨트롤러만 `dispose()`합니다.
`AnimatedBuilder(animation: controller, ...)`로 상태를 구독합니다.

현재 `DiffScreen` 안의 `_diffCache`, `_loadFiles`, `_loadDiff`,
`_fileRequest`, `_diffRequest`, `_lines`, `_pairs`, `_algorithm` 상태는
삭제합니다. 주변 커밋과 변경 파일의 선택 callback은 컨트롤러 명령을
호출합니다.

- [ ] **Step 4: 오른쪽 열을 머리글 두 줄과 Hunk 목록으로 조합합니다**

```dart
Column(
  children: [
    DiffFileHeader(
      file: selectedFile,
      path: state.selectedPath,
      hunkSelected: true,
    ),
    DiffToolbar(
      activeHunkIndex: state.activeHunkIndex,
      hunkCount: state.document?.hunks.length ?? 0,
      algorithm: state.algorithm,
      ignoreWhitespace: state.ignoreWhitespace,
      wrapLines: state.wrapLines,
      focusMode: state.focusMode,
      loading: state.loadingDiff,
      onPreviousHunk: () => controller.stepHunk(-1),
      onNextHunk: () => controller.stepHunk(1),
      onAlgorithmSelected: controller.selectAlgorithm,
      onIgnoreWhitespaceChanged: controller.setIgnoreWhitespace,
      onWrapLinesChanged: controller.setWrapLines,
      onFocusModeChanged: controller.setFocusMode,
    ),
    Expanded(
      child: HunkListView(
        document: state.document ?? DiffDocument.empty,
        activeHunkIndex: state.activeHunkIndex,
        wrapLines: state.wrapLines,
        controller: _diffScroll,
        anchorKeys: _anchorKeys,
        onHunkSelected: controller.selectHunk,
      ),
    ),
  ],
)
```

파일이나 부모가 바뀌면 `_diffScroll`을 0으로 옮깁니다. Hunk 선택이
바뀌면 해당 `GlobalKey`의 context를 `Scrollable.ensureVisible`로
이동합니다.

- [ ] **Step 5: 로딩·오류·옵션 복원을 화면에서 확인합니다**

알고리즘과 공백 설정을 바꾸는 동안 기존 Hunk가 남고 오른쪽 위에 작은
진행 표시가 나타나는지 테스트합니다. 실패하면 Hunk와 인접 알고리즘
값이 마지막 성공 상태로 돌아오는지 확인합니다.

- [ ] **Step 6: Full Diff 관련 기존 테스트를 실행합니다**

Run:

```bash
flutter test test/app_test.dart --plain-name 'full diff'
flutter test test/app_test.dart --plain-name 'algorithm'
flutter test test/app_test.dart --plain-name 'diff pane selects'
```

Expected: 세 명령 모두 `All tests passed!`

- [ ] **Step 7: 화면 교체를 커밋합니다**

```bash
git add lib/diff_screen.dart test/app_test.dart
git commit -m "feat: make hunks the full diff workspace"
```

### Task 9: 집중 모드, 반응형 탐색 열, 키보드 이동

**Files:**

- Modify: `lib/diff_screen.dart`
- Modify: `test/app_test.dart`

**Interfaces:**

- Consumes: 컨트롤러의 `focusMode`, Hunk 앵커, 공통 페이지 스크롤
- Produces:
  - `Command-Shift-F` 집중 모드
  - `Option-Up/Down` Hunk 이동
  - `Command-Shift-Up/Down` 48px 콘텐츠 스크롤
  - 폭에 따른 주변 커밋·변경 파일 열 접기

- [ ] **Step 1: 집중 모드와 폭 단계의 실패 테스트를 작성합니다**

```dart
testWidgets('focus mode hides navigation and restores saved widths', (
  tester,
) async {
  // 1200px 화면에서 두 열이 보이는 상태로 시작합니다.
  await tester.tap(find.byKey(const Key('focus-mode')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('nearby-column')), findsNothing);
  expect(find.byKey(const Key('details-files-column')), findsNothing);
  expect(tester.getSize(find.byKey(const Key('diff-column'))).width, 1200);

  await tester.tap(find.byKey(const Key('focus-mode')));
  await tester.pumpAndSettle();
  expect(tester.getSize(find.byKey(const Key('nearby-column'))).width, 240);
  expect(tester.getSize(find.byKey(const Key('details-files-column'))).width, 330);
});
```

화면을 760px로 줄이면 주변 커밋 열만 사라지고, 520px로 줄이면 변경 파일
열도 사라지는 테스트를 추가합니다. 자동으로 접힐 때 저장한 열 너비를
바꾸지 않는지도 확인합니다.

- [ ] **Step 2: 키보드 우선순위의 실패 테스트를 작성합니다**

Hunk가 세 개인 문서에서 다음 동작을 검증합니다.

```dart
await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
await tester.pumpAndSettle();
expect(find.byKey(const Key('active-hunk-1')), findsOneWidget);
```

`Command-Shift-Down`은 파일이나 커밋을 바꾸지 않고 Hunk 본문을 정확히
48px 내립니다. `Command-Down`은 커밋, bare Down은 파일 이동을
유지합니다. 메뉴가 열렸거나 선택 가능한 텍스트가 키를 처리한 경우에는
화면 명령이 실행되지 않는지도 확인합니다.

- [ ] **Step 3: 화면 폭과 집중 모드 배치를 구현합니다**

폭 계산은 다음 세 상태 중 하나만 고릅니다.

```dart
({bool showCommits, bool showFiles}) visiblePanes(double width) {
  const diffMinimum = 520.0;
  if (width < diffMinimum + FullDiffColumnWidths.minFiles) {
    return (showCommits: false, showFiles: false);
  }
  if (width <
      diffMinimum +
          FullDiffColumnWidths.minFiles +
          FullDiffColumnWidths.minCommits) {
    return (showCommits: false, showFiles: true);
  }
  return (showCommits: true, showFiles: true);
}
```

`focusMode`가 켜져 있으면 폭과 관계없이 두 탐색 열을 숨깁니다. 자동
접기와 집중 모드는 `_commitsWidth`, `_filesWidth`를 덮어쓰지 않습니다.

- [ ] **Step 4: Shortcuts와 Actions로 키보드 명령을 연결합니다**

`DiffScreen`의 루트에 `Shortcuts`와 `Actions`를 두고 다음
`SingleActivator`를 intent에 연결합니다.

```dart
<ShortcutActivator, Intent>{
  const SingleActivator(LogicalKeyboardKey.escape):
      const ReturnToTimelineIntent(),
  const SingleActivator(
    LogicalKeyboardKey.arrowUp,
    meta: true,
    shift: true,
  ): const PageScrollIntent(-1),
  const SingleActivator(
    LogicalKeyboardKey.arrowDown,
    meta: true,
    shift: true,
  ): const PageScrollIntent(1),
  const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
      const ToggleFocusModeIntent(),
  const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
      const StepHunkIntent(-1),
  const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
      const StepHunkIntent(1),
  const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
      const StepCommitIntent(-1),
  const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
      const StepCommitIntent(1),
  const SingleActivator(LogicalKeyboardKey.arrowUp):
      const StepFileIntent(-1),
  const SingleActivator(LogicalKeyboardKey.arrowDown):
      const StepFileIntent(1),
}
```

페이지 스크롤 action은 첫 호출에 `animate: true`로
`applyPageScroll`을 호출합니다. 키 반복 중 이미 애니메이션 중이면
현재 위치를 기준으로 `jumpTo`를 사용해 입력을 밀리지 않게 합니다.
Hunk 이동 뒤에는 활성 앵커를 `Scrollable.ensureVisible`로 화면에
넣습니다.

메뉴, 토글, `SelectionArea` 내부처럼 더 가까운 위젯이 같은 키를
처리하면 루트 action까지 전달하지 않습니다. 기존 루트
`Focus.onKeyEvent`의 파일·커밋 이동 분기는 제거해 한 키가 두 번
실행되지 않게 합니다.

- [ ] **Step 5: 집중 모드와 키보드 테스트를 통과시킵니다**

Run:

```bash
flutter test test/app_test.dart --plain-name 'focus mode hides navigation and restores saved widths'
flutter test test/app_test.dart --plain-name 'narrow full diff'
flutter test test/app_test.dart --plain-name 'the diff screen walks files and commits from the keyboard'
flutter test test/app_test.dart --plain-name 'full diff shares preview page scrolling'
```

Expected: 네 명령 모두 `All tests passed!`

- [ ] **Step 6: 화면 탐색을 커밋합니다**

```bash
git add lib/diff_screen.dart test/app_test.dart
git commit -m "feat: add full diff focus and hunk navigation"
```

### Task 10: 설계 대조와 1차 완료 검증

**Files:**

- Modify only if verification finds a defect:
  - `lib/full_diff_*.dart`
  - `lib/diff_screen.dart`
  - `lib/git.dart`
  - `lib/timeline.dart`
  - matching test file

**Interfaces:**

- Consumes: Tasks 0-9의 완성된 1차 화면
- Produces: 자동 검사와 DRL 수동 검사를 통과한 1차 결과

- [ ] **Step 1: 형식과 정적 분석을 실행합니다**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
```

Expected: 두 명령 모두 exit 0, analyzer issue 0개

- [ ] **Step 2: 단위·위젯 테스트를 모두 실행합니다**

Run: `flutter test`

Expected: `All tests passed!`

- [ ] **Step 3: macOS release build를 확인합니다**

Run: `flutter build macos --release`

Expected: exit 0 and
`build/macos/Build/Products/Release/yogit.app` exists

- [ ] **Step 4: DRL 검증 대상을 엽니다**

Run:

```bash
flutter run -d macos -- \
  --repo /Users/doortts/repos/drl
```

커밋 `40aff6d75bd16c5ccd9d45de615df8e9cbbb9fb0`의
`src/drlgfxio.pas`를 열고 다음 항목을 확인합니다.

- Hunk가 9개입니다.
- 각 제목의 이전·새 줄 범위가 Git patch와 일치합니다.
- 원본 `diff --git`, `index`, `---`, `+++`, `@@` 행은 소스 행으로
  보이지 않습니다.
- 이전·다음 버튼과 `Option-Up/Down`이 같은 9개 Hunk를 방문합니다.
- `Command-Shift-Up/Down`이 미리보기와 같은 속도로 움직입니다.
- 알고리즘과 공백 설정을 바꾸는 동안 마지막 Hunk 화면이 남습니다.
- 집중 모드를 끄면 탐색 열과 저장한 너비가 돌아옵니다.
- 경로·hash·줄 번호·소스는 Menlo를 사용하고 일반 UI 문장은 시스템
  글꼴을 사용합니다. 한국어 소스 문자는 D2Coding으로 표시됩니다.

- [ ] **Step 5: 최신 시안과 화면을 대조합니다**

다음 두 파일을 기준으로 머리글 두 줄, Hunk 카드, 간격, 색상, 글꼴
구역을 확인합니다.

```text
docs/superpowers/specs/assets/full-diff-workspace-mockup.svg
docs/superpowers/specs/assets/full-diff-settings-mockup.svg
```

Settings 시안은 2차 범위이므로 이번 단계에서는 구현하지 않습니다.

- [ ] **Step 6: 검증 중 고친 내용이 있으면 독립 커밋을 만듭니다**

```bash
git add lib test
git commit -m "fix: close full diff phase one gaps"
```

고칠 내용이 없으면 빈 커밋을 만들지 않습니다.

## 완료 조건

- Full Diff가 Hunk 블록으로 열립니다.
- 각 Hunk에 읽기 쉬운 줄 범위, 함수 문맥, 변경 위치가 표시됩니다.
- `diff 알고리즘` 이름과 현재 선택값이 따로 보입니다.
- 공백 무시, 줄바꿈, 집중 모드, 이전·다음 Hunk 이동이 동작합니다.
- 타임라인 미리보기와 Full Diff가 같은 페이지 스크롤 구현을 씁니다.
- 데이터 요청과 캐시는 `DiffScreen`이 아니라
  `FullDiffSessionController`가 관리합니다.
- 화면 전체 D2Coding이 사라지고 역할별 글꼴이 적용됩니다.
- 기존 머지 부모, 열 너비, 선택, 로딩, 오류, 키보드 동작을 잃지
  않습니다.
- 정적 분석, 전체 테스트, macOS release build가 모두 통과합니다.
