# Full Diff 웹 시안 일치 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Yogit의 Full Diff를 승인된 웹 시안과 같은 구성과 색으로
구현하고, File·Diff·Blame·History와 Hunk·Inline·Split을 실제 Git
데이터로 동작하게 만듭니다.

**Architecture:** `GitRepository`는 셸을 거치지 않고 patch, 파일 원본,
Blame, 파일 History를 읽습니다. `FullDiffSessionController`는 선택
세대와 자원별 요청 번호, 제한된 세션 캐시를 관리하고 화면 위젯은
`DiffDocument`, `FileDocument`, `BlameDocument`, `FileHistoryEntry`만
그립니다. 공용 계약을 먼저 고정한 뒤 서로 다른 파일을 맡는 작업을
병렬로 진행하고, 마지막에 `DiffScreen`에서 조립합니다.

**Tech Stack:** Flutter 3.44.4, Dart 3.12.2, Git CLI, macOS AppKit,
`ChangeNotifier`, `highlighting` 0.9.0+11.8.0, `flutter_test`,
`image` 4.9.1

## Global Constraints

- 최종 구현 기준은
  `docs/superpowers/specs/2026-07-27-full-diff-web-mockup-parity-design.md`입니다.
- 시각 판정 기준은
  `docs/superpowers/specs/2026-07-27-full-diff-visual-qa-reference.md`와
  `docs/superpowers/specs/assets/full-diff-qa/`의 13개 기능별 이미지입니다.
- 첫 번째 머리글의 순서는 코드 파일 아이콘, 경로, 상태·변경 수,
  `편집기로 열기`, `File`, `Diff`, `Blame`, `History`, 인코딩입니다.
- 두 번째 머리글의 순서는 `집중 모드`, `Hunk`, `Inline`, `Split`,
  이전 변경, 변경 번호, 다음 변경, `diff 알고리즘`, `공백 무시`,
  `줄바꿈`입니다.
- 기본 선택은 `Diff`와 `Hunk`입니다.
- 닫힌 알고리즘 메뉴의 이름은 선택값과 관계없이 항상
  `diff 알고리즘`입니다.
- patch와 파일 목록에는 `--find-renames=50%`를 사용하고 공백 변경
  무시는 `--ignore-all-space`를 사용합니다.
- 파일은 엄격한 UTF-8로 해석합니다. NUL 바이트나 Git의 바이너리
  numstat은 `Binary`, 그 밖의 UTF-8 해석 실패는
  `Unsupported encoding`입니다.
- 2MiB 또는 50,000행을 넘으면 구문 강조, 단어 변경 강조와 기본
  줄바꿈을 끕니다. 10MiB 또는 200,000행을 넘으면 전체 텍스트를
  만들지 않습니다.
- 커밋된 자원의 캐시는 종류마다 최근 사용 32개로 제한합니다.
  patch와 파일 원본의 원본 바이트 합계는 64MiB를 넘지 않습니다.
  작업 트리 자원과 실패한 Future는 캐시에 남기지 않습니다.
- Menlo는 경로, SHA, 줄 번호, 범위, 변경 수, 인코딩과 소스에
  사용합니다. D2Coding은 한국어와 고정폭 정렬이 모두 필요할 때만
  Menlo의 대체 글꼴로 사용합니다.
- 타임라인 미리보기와 Full Diff는
  `Command-Shift-Up/Command-Shift-Down`, 48px, 첫 입력 100ms
  애니메이션을 함께 사용합니다.
- 650px 초과에서는 세 본문 열, 650px 이하에서는 변경 파일과 콘텐츠,
  480px 이하에서는 콘텐츠만 표시합니다. 480px의 Split은 결과 쪽만
  표시합니다.
- 바깥 카드의 안쪽 여백은 12px, 모서리 반지름은 20px입니다. 일반
  버튼과 선택 메뉴는 높이 28px, 모서리 반지름 12.5px입니다.
- 머리글과 탐색 열은 `#242424`, Diff 바탕은 `#181818`, 선택한 탐색
  행은 `#0D273F`, 강조 글자는 `#83C4FF`를 사용합니다.
- 구문 확장 묶음은 macOS release 앱의 압축 크기를 1MiB 이하로
  늘리고 DRL 첫 Hunk를 50ms 안에 강조할 때만 기본 배포에 포함합니다.
- 화면 안 편집, stage, discard, 커밋, 충돌 해결과 임의 문자 인코딩
  변환은 이번 범위에 넣지 않습니다.

## 파일 구성

### 먼저 고정할 공용 파일

- Modify: `lib/full_diff_model.dart`
  - 주 화면·Diff 표시 방식, 파일·Blame·History 문서, 앵커와 파생 행을
    정의합니다.
- Create: `lib/full_diff_theme.dart`
  - 승인된 색, 크기, 간격과 글꼴 역할을 상수로 제공합니다.
- Create: `lib/full_diff_syntax_contract.dart`
  - 표시 위젯과 구문 강조 구현 사이의 작은 인터페이스를 정의합니다.
- Modify: `lib/git.dart`
  - `FullDiffRepository`의 최종 메서드와 Git 원시 결과 모델을
    정의합니다.
- Modify: `lib/full_diff_controller.dart`
  - 독립 자원 슬롯, 선택 세대, 요청 번호, 캐시와 화면 명령을
    관리합니다.
- Create: `test/support/full_diff_fixtures.dart`
  - 이후 테스트가 공유하는 커밋, 파일, 문서와 저장소 대역을
    제공합니다.

### 공용 계약 뒤 병렬로 작업할 파일

- Modify: `lib/settings.dart`, `lib/main.dart`, `lib/timeline.dart`
  - 새 Full Diff 초기 화면 설정을 저장하고 새 화면에 전달합니다.
- Create: `lib/full_diff_syntax.dart`
  - 파일명 기반 언어 선택, 구문 토큰과 단어 변경 범위를 만듭니다.
- Create: `lib/full_diff_code_row.dart`
  - 한 줄의 번호, 부호, 배경, 현재 위치 선과 강조된 소스를 그립니다.
- Modify: `lib/full_diff_hunk_view.dart`
  - 활성 Hunk의 변경 행만 그립니다.
- Create: `lib/full_diff_inline_view.dart`
  - 모든 Hunk와 앞뒤 문맥 3줄을 한 열에 그립니다.
- Create: `lib/full_diff_split_view.dart`
  - 이전·결과 행을 짝지어 그리고 없는 쪽에 빗금을 표시합니다.
- Create: `lib/full_file_view.dart`
  - 전체 파일과 현재 앵커를 그립니다.
- Create: `lib/full_blame_view.dart`
  - 전체 파일 앞에 SHA와 작성자를 붙입니다.
- Create: `lib/full_history_view.dart`
  - 이름 변경을 따라간 파일 이력과 키보드 확정 동작을 제공합니다.
- Replace: `lib/full_diff_header.dart`
  - 승인된 두 머리글과 모든 조작 요소를 정확한 순서로 그립니다.
- Create: `lib/full_diff_minimap.dart`
  - 표시, 화면 범위, 클릭과 끌기를 담당합니다.
- Create: `lib/external_editor.dart`
  - 안전한 편집기 명령 해석과 실행 경계를 제공합니다.
- Modify: `macos/Runner/MainFlutterWindow.swift`
  - 편집기가 없을 때 검증된 file URL을 `NSWorkspace`로 엽니다.

### 마지막에 조립하고 검수할 파일

- Replace: `lib/diff_screen.dart`
  - 두 머리글, 반응형 탐색 열, 콘텐츠, 키보드와 스크롤만 조립합니다.
- Modify: `lib/timeline.dart`
  - Settings의 초기 화면 값을 Full Diff에 전달합니다.
- Create: `test/full_diff_workspace_test.dart`
  - 전환, 반응형, 키보드와 실제 조립을 검증합니다.
- Create: `test/full_diff_visual_test.dart`
  - 13개 기준 상태를 정해진 크기로 캡처합니다.
- Create: `test/support/full_diff_qa_harness.dart`
  - 웹 시안과 같은 고정 데이터를 제공합니다.
- Create: `tool/full_diff_visual_diff.dart`
  - 기준 이미지와 구현 이미지를 나란히 놓고 차이 이미지를 만듭니다.
- Create: `docs/superpowers/verification/full-diff-qa/README.md`
  - 기능별 이미지, 명령, 구문 강조 크기·속도 측정 결과를 기록합니다.

---

### Task 1: 공용 모델과 시각 상수 고정

**Files:**

- Modify: `lib/git.dart:420-520`
- Modify: `lib/full_diff_model.dart:1-137`
- Create: `lib/full_diff_theme.dart`
- Create: `lib/full_diff_syntax_contract.dart`
- Modify: `test/full_diff_model_test.dart`

**Interfaces:**

- Consumes: 기존 `DiffLine`, `DiffPair`, `DiffAlgorithm`, `GitCommit`,
  `GitFileChange`
- Produces:
  - `enum FullDiffView { file, diff, blame, history }`
  - `enum DiffPresentation { hunk, inline, split }`
  - `enum FullDiffInitialView { hunk, fullFile }`
  - `enum FileContentKind { utf8, binary, unsupportedEncoding, tooLarge }`
  - `enum FileDocumentSide { old, result }`
  - `GitBlameLine`
  - `FileDocument.fromBytes({revision, path, side, bytes, gitMarkedBinary})`
  - `BlameDocument.fromGitLines(FileDocument, List<GitBlameLine>)`
  - `FileHistoryEntry`
  - `DiffDocument.splitRows`
  - `DiffDocument.sourceLineCount`
  - `abstract interface FullDiffSyntaxHighlighter`

- [ ] **Step 1: 최종 문서 모델을 요구하는 실패 테스트를 작성합니다**

`test/full_diff_model_test.dart`에 다음 테스트를 추가합니다.

```dart
test('derives anchors, split rows, and displayed source length', () {
  final document = DiffDocument.fromLines(const [
    DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,3 +10,4 @@ SetupBase'),
    DiffLine(
      kind: DiffLineKind.context,
      text: 'begin',
      oldNumber: 10,
      newNumber: 10,
    ),
    DiffLine(kind: DiffLineKind.delete, text: 'Scale := 1;', oldNumber: 11),
    DiffLine(
      kind: DiffLineKind.add,
      text: 'Scale := WindowPixelRatio;',
      newNumber: 11,
    ),
    DiffLine(kind: DiffLineKind.add, text: 'Log(Scale);', newNumber: 12),
  ]);

  expect(document.hunks.single.anchor.hunkIndex, 0);
  expect(document.hunks.single.anchor.oldLine, 11);
  expect(document.hunks.single.anchor.newLine, 11);
  expect(document.hunks.single.changedLines, hasLength(3));
  expect(document.splitRows, hasLength(3));
  expect(document.splitRows[1].left?.text, 'Scale := 1;');
  expect(document.splitRows[1].right?.text, 'Scale := WindowPixelRatio;');
  expect(document.sourceLineCount, 12);
});

test('classifies bytes without treating unsupported text as binary', () {
  final utf8File = FileDocument.fromBytes(
    revision: 'abc',
    path: 'src/a.pas',
    side: FileDocumentSide.result,
    bytes: Uint8List.fromList(utf8.encode('begin\nend;\n')),
    gitMarkedBinary: false,
  );
  final unsupported = FileDocument.fromBytes(
    revision: 'abc',
    path: 'legacy.txt',
    side: FileDocumentSide.result,
    bytes: Uint8List.fromList(const [0x80, 0x81]),
    gitMarkedBinary: false,
  );
  final binary = FileDocument.fromBytes(
    revision: 'abc',
    path: 'asset.bin',
    side: FileDocumentSide.result,
    bytes: Uint8List.fromList(const [0x41, 0x00, 0x42]),
    gitMarkedBinary: false,
  );

  expect(utf8File.kind, FileContentKind.utf8);
  expect(utf8File.lines, ['begin', 'end;']);
  expect(utf8File.hasTrailingNewline, isTrue);
  expect(unsupported.kind, FileContentKind.unsupportedEncoding);
  expect(binary.kind, FileContentKind.binary);
});

test('rejects blame rows that do not match the file', () {
  final file = FileDocument.fromBytes(
    revision: 'abc',
    path: 'one.txt',
    side: FileDocumentSide.result,
    bytes: Uint8List.fromList(utf8.encode('one\n')),
    gitMarkedBinary: false,
  );
  expect(
    () => BlameDocument.fromGitLines(file, const []),
    throwsFormatException,
  );
});

test('stops materializing text beyond either hard limit', () {
  final bytesOverLimit = Uint8List(fullDiffTextByteLimit + 1)
    ..fillRange(0, fullDiffTextByteLimit + 1, 0x61);
  final linesOverLimit = Uint8List.fromList(
    utf8.encode(
      List.filled(fullDiffTextLineLimit + 1, 'x').join('\n'),
    ),
  );

  for (final bytes in [bytesOverLimit, linesOverLimit]) {
    final file = FileDocument.fromBytes(
      revision: 'abc',
      path: 'large.txt',
      side: FileDocumentSide.result,
      bytes: bytes,
      gitMarkedBinary: false,
    );
    expect(file.kind, FileContentKind.tooLarge);
    expect(file.lines, isEmpty);
    expect(file.disableRichRendering, isTrue);
  }
});
```

- [ ] **Step 2: 모델 테스트가 새 계약 때문에 실패하는지 확인합니다**

Run: `flutter test test/full_diff_model_test.dart`

Expected: FAIL because `FileDocument`, `changedLines`, `splitRows` and the new
enums do not exist

- [ ] **Step 3: 주 화면, 표시 방식과 파일 문서를 구현합니다**

`lib/full_diff_model.dart`에 다음 공개 계약을 추가합니다.

```dart
enum FullDiffView { file, diff, blame, history }
enum DiffPresentation { hunk, inline, split }
enum FullDiffInitialView { hunk, fullFile }
enum FileContentKind { utf8, binary, unsupportedEncoding, tooLarge }
enum FileDocumentSide { old, result }

const fullDiffLargeByteLimit = 2 * 1024 * 1024;
const fullDiffLargeLineLimit = 50000;
const fullDiffTextByteLimit = 10 * 1024 * 1024;
const fullDiffTextLineLimit = 200000;

@immutable
class FileDocument {
  const FileDocument({
    required this.revision,
    required this.path,
    required this.side,
    required this.bytes,
    required this.kind,
    required this.lines,
    required this.hasTrailingNewline,
    required this.disableRichRendering,
    required this.fingerprint,
  });

  final String revision;
  final String path;
  final FileDocumentSide side;
  final Uint8List bytes;
  final FileContentKind kind;
  final List<String> lines;
  final bool hasTrailingNewline;
  final bool disableRichRendering;
  final String fingerprint;

  factory FileDocument.fromBytes({
    required String revision,
    required String path,
    required FileDocumentSide side,
    required Uint8List bytes,
    required bool gitMarkedBinary,
  }) {
    final fingerprint = '${bytes.length}:${Object.hashAll(bytes)}';
    if (gitMarkedBinary || bytes.contains(0)) {
      return FileDocument(
        revision: revision,
        path: path,
        side: side,
        bytes: bytes,
        kind: FileContentKind.binary,
        lines: const [],
        hasTrailingNewline: false,
        disableRichRendering: true,
        fingerprint: fingerprint,
      );
    }
    late final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return FileDocument(
        revision: revision,
        path: path,
        side: side,
        bytes: bytes,
        kind: FileContentKind.unsupportedEncoding,
        lines: const [],
        hasTrailingNewline: false,
        disableRichRendering: true,
        fingerprint: fingerprint,
      );
    }
    final trailing = text.endsWith('\n');
    final lines = text.isEmpty ? <String>[] : text.split('\n');
    if (trailing) lines.removeLast();
    final tooLarge =
        bytes.length > fullDiffTextByteLimit ||
        lines.length > fullDiffTextLineLimit;
    return FileDocument(
      revision: revision,
      path: path,
      side: side,
      bytes: bytes,
      kind: tooLarge ? FileContentKind.tooLarge : FileContentKind.utf8,
      lines: List.unmodifiable(tooLarge ? const <String>[] : lines),
      hasTrailingNewline: trailing,
      disableRichRendering:
          bytes.length > fullDiffLargeByteLimit ||
          lines.length > fullDiffLargeLineLimit,
      fingerprint: fingerprint,
    );
  }
}
```

지문은 프로세스 안에서 작업 트리 Blame 요청이 같은 파일 원본을
가리키는지만 확인합니다. 디스크에 저장하거나 보안 용도로 쓰지
않으므로 byte length와 `Object.hashAll(bytes)`를 합친 세션용 문자열을
사용합니다.

- [ ] **Step 4: Hunk 파생 행, Blame과 History 모델을 구현합니다**

먼저 `lib/git.dart`에 Git 명령 결과를 운반하는 최소 DTO를 추가합니다.

```dart
class GitBlameLine {
  const GitBlameLine({
    required this.lineNumber,
    required this.sha,
    required this.author,
    required this.uncommitted,
  });
  final int lineNumber;
  final String sha;
  final String author;
  final bool uncommitted;
}
```

그다음 `lib/full_diff_model.dart`에 파생 행과 화면 문서를 추가합니다.

```dart
extension DiffHunkRows on DiffHunk {
  List<DiffLine> get changedLines => List.unmodifiable(
    lines.where(
      (line) =>
          line.kind == DiffLineKind.add || line.kind == DiffLineKind.delete,
    ),
  );

  String get displayRange {
    final useOld = newCount == 0;
    final start = useOld ? oldStart : newStart;
    final count = useOld ? oldCount : newCount;
    final end = count <= 1 ? start : start + count - 1;
    return start == end ? '$start' : '$start–$end';
  }
}

extension DiffDocumentDerived on DiffDocument {
  List<DiffPair> get splitRows => List.unmodifiable(
    hunks.expand((hunk) => pairDiff(hunk.lines)),
  );

  int get sourceLineCount {
    final newNumbers = rows.map((line) => line.newNumber).whereType<int>();
    final oldNumbers = rows.map((line) => line.oldNumber).whereType<int>();
    return newNumbers.isNotEmpty
        ? newNumbers.reduce(math.max)
        : oldNumbers.isEmpty
        ? 0
        : oldNumbers.reduce(math.max);
  }
}

@immutable
class BlameLine {
  const BlameLine({
    required this.lineNumber,
    required this.sha,
    required this.author,
    required this.uncommitted,
  });
  final int lineNumber;
  final String sha;
  final String author;
  final bool uncommitted;
}

@immutable
class BlameDocument {
  const BlameDocument({required this.file, required this.lines});
  final FileDocument file;
  final List<BlameLine> lines;

  factory BlameDocument.fromGitLines(
    FileDocument file,
    List<GitBlameLine> lines,
  ) {
    if (file.lines.length != lines.length) {
      throw FormatException(
        'Blame row count ${lines.length} != file row count '
        '${file.lines.length}',
      );
    }
    return BlameDocument(
      file: file,
      lines: List.unmodifiable([
        for (final line in lines)
          BlameLine(
            lineNumber: line.lineNumber,
            sha: line.sha,
            author: line.author,
            uncommitted: line.uncommitted,
          ),
      ]),
    );
  }
}

@immutable
class FileHistoryEntry {
  const FileHistoryEntry({
    required this.commit,
    required this.path,
    required this.oldPath,
    required this.status,
  });
  final GitCommit commit;
  final String path;
  final String? oldPath;
  final String status;
}
```

- [ ] **Step 5: 승인된 시각 상수와 구문 강조 계약을 만듭니다**

`lib/full_diff_theme.dart`의 공개 상수는 다음과 같이 고정합니다.

```dart
const fullDiffHeader = Color(0xFF242424);
const fullDiffControl = Color(0xF5363636);
const fullDiffDivider = Color(0x15FFFFFF);
const fullDiffCanvas = Color(0xFF181818);
const fullDiffHunkHeader = Color(0xFF292929);
const fullDiffSelection = Color(0xFF0D273F);
const fullDiffSelectedChip = Color(0xFF273E52);
const fullDiffAccent = Color(0xFF83C4FF);
const fullDiffChip = Color(0xFF3A3A3A);
const fullDiffMuted = Color(0xFF919191);
const fullDiffAddedSource = Color(0xFF262E36);
const fullDiffAddedGutter = Color(0xFF3D434A);
const fullDiffDeletedSource = Color(0xFF34251F);
const fullDiffDeletedGutter = Color(0xFF493B35);
const fullDiffWordChange = Color(0xFF394C5E);
const fullDiffString = Color(0xFFFFBFA0);
const fullDiffMinimapTrack = Color(0xFF2F2F2F);
const fullDiffMinimapViewport = Color(0xFF353A3E);
const fullDiffDeletedMark = Color(0xFFF68B59);

const fullDiffOuterPadding = 12.0;
const fullDiffOuterRadius = 20.0;
const fullDiffControlHeight = 28.0;
const fullDiffControlRadius = 12.5;
const fullDiffChipRadius = 7.5;
const fullDiffMinimapWidth = 18.0;
const fullDiffLineNumberWidth = 74.0;
```

`lib/full_diff_syntax_contract.dart`에는 다음 인터페이스만 둡니다.

```dart
@immutable
class CodeTokenSpan {
  const CodeTokenSpan({
    required this.start,
    required this.end,
    required this.style,
  });
  final int start;
  final int end;
  final TextStyle style;
}

abstract interface class FullDiffSyntaxHighlighter {
  String? languageForPath(String path);
  List<CodeTokenSpan> highlightLine(String path, String source);
}
```

- [ ] **Step 6: 모델 테스트와 정적 분석을 통과시킵니다**

Run:

```bash
dart format lib/full_diff_model.dart lib/full_diff_theme.dart \
  lib/full_diff_syntax_contract.dart lib/git.dart \
  test/full_diff_model_test.dart
flutter test test/full_diff_model_test.dart
flutter analyze
```

Expected: both commands finish without errors and the test reports
`All tests passed!`

- [ ] **Step 7: 모델과 공용 시각 계약을 커밋합니다**

```bash
git add lib/full_diff_model.dart lib/full_diff_theme.dart \
  lib/full_diff_syntax_contract.dart lib/git.dart \
  test/full_diff_model_test.dart
git commit -m "refactor: define full diff workspace models"
```

### Task 2: Git 파일 원본, Blame와 History

**Files:**

- Modify: `lib/git.dart:420-874`
- Modify: `test/git_test.dart`
- Create: `test/full_diff_git_test.dart`
- Create: `test/support/full_diff_fixtures.dart`

**Interfaces:**

- Consumes: Task 1의 문서 모델, 기존 `GitCommit`, `GitFileChange`
- Produces:
  - 확장된 `FullDiffRepository`
  - `GitFileHistoryRecord`
  - 수정·추가·삭제·이름 변경·복사·머지·루트·작업 트리·추적하지
    않는 파일에 맞는 저장소 구현

- [ ] **Step 1: 저장소 인터페이스를 최종 형태로 넓힙니다**

`lib/git.dart`에서 `FullDiffRepository`와 Git 원시 결과를 다음처럼
정의합니다.

```dart
class GitFileChange {
  const GitFileChange({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
    this.oldPath,
    this.isBinary = false,
  });

  final String path;
  final String? oldPath;
  final String status;
  final int? additions;
  final int? deletions;
  final bool isBinary;
}

class GitFileHistoryRecord {
  const GitFileHistoryRecord({
    required this.commit,
    required this.path,
    required this.oldPath,
    required this.status,
  });
  final GitCommit commit;
  final String path;
  final String? oldPath;
  final String status;
}

abstract interface class FullDiffRepository {
  String get root;

  Future<List<GitFileChange>> loadFiles(GitCommit commit, {String? parent});

  Future<List<DiffLine>> loadDiff(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
    bool ignoreWhitespace = false,
  });

  Future<Uint8List> loadFileBytes(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
  });

  Future<List<GitBlameLine>> loadBlame(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    Uint8List? workingTreeBytes,
  });

  Future<List<GitFileHistoryRecord>> loadFileHistory(
    GitCommit commit,
    GitFileChange file,
  );
}
```

- [ ] **Step 2: 공용 테스트 대역을 새 계약에 맞춥니다**

`test/support/full_diff_fixtures.dart`에 `FakeFullDiffRepository`를 두고
모든 요청을 기록합니다.

```dart
class FakeFullDiffRepository implements FullDiffRepository {
  FakeFullDiffRepository({this.root = '/repo'});

  @override
  final String root;

  final fileRequests = <({String sha, String? parent})>[];
  final diffRequests =
      <({
        String sha,
        String path,
        String? parent,
        DiffAlgorithm algorithm,
        bool whitespace,
      })>[];
  final contentRequests =
      <({String sha, String path, String? parent})>[];
  final blameRequests =
      <({String sha, String path, String? parent})>[];
  final historyRequests = <({String sha, String path})>[];

  Future<List<GitFileChange>> Function(GitCommit, String?)? files;
  Future<List<DiffLine>> Function(
    GitCommit,
    GitFileChange,
    String?,
    DiffAlgorithm,
    bool,
  )? diff;
  Future<Uint8List> Function(GitCommit, GitFileChange, String?)? content;
  Future<List<GitBlameLine>> Function(
    GitCommit,
    GitFileChange,
    String?,
    Uint8List?,
  )? blame;
  Future<List<GitFileHistoryRecord>> Function(GitCommit, GitFileChange)?
  history;

  @override
  Future<List<GitFileChange>> loadFiles(
    GitCommit commit, {
    String? parent,
  }) {
    fileRequests.add((sha: commit.sha, parent: parent));
    return files?.call(commit, parent) ?? Future.value(const []);
  }

  @override
  Future<List<DiffLine>> loadDiff(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
    bool ignoreWhitespace = false,
  }) {
    diffRequests.add((
      sha: commit.sha,
      path: file.path,
      parent: parent,
      algorithm: algorithm,
      whitespace: ignoreWhitespace,
    ));
    return diff?.call(
          commit,
          file,
          parent,
          algorithm,
          ignoreWhitespace,
        ) ??
        Future.value(const []);
  }

  @override
  Future<Uint8List> loadFileBytes(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
  }) {
    contentRequests.add((sha: commit.sha, path: file.path, parent: parent));
    return content?.call(commit, file, parent) ??
        Future.value(Uint8List(0));
  }

  @override
  Future<List<GitBlameLine>> loadBlame(
    GitCommit commit,
    GitFileChange file, {
    String? parent,
    Uint8List? workingTreeBytes,
  }) {
    blameRequests.add((sha: commit.sha, path: file.path, parent: parent));
    return blame?.call(commit, file, parent, workingTreeBytes) ??
        Future.value(const []);
  }

  @override
  Future<List<GitFileHistoryRecord>> loadFileHistory(
    GitCommit commit,
    GitFileChange file,
  ) {
    historyRequests.add((sha: commit.sha, path: file.path));
    return history?.call(commit, file) ?? Future.value(const []);
  }
}

const fixtureIdentity = GitIdentity(
  name: 'Suwon Chae',
  email: 'suwon@example.com',
);

const commitA = GitCommit(
  sha: '40aff6d',
  shortSha: '40aff6d',
  parents: ['62874a0'],
  author: fixtureIdentity,
  authorTimestamp: 1720573200,
  committer: fixtureIdentity,
  committerTimestamp: 1720573200,
  refs: [],
  subject: 'Make Retina windows pixel-aware',
);

const fileA = GitFileChange(
  path: 'src/drlua.pas',
  status: 'M',
  additions: 12,
  deletions: 4,
);

const twoHunkLines = <DiffLine>[
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,7 +10,7 @@ Configure'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context before 1',
    oldNumber: 10,
    newNumber: 10,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context before 2',
    oldNumber: 11,
    newNumber: 11,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context before 3',
    oldNumber: 12,
    newNumber: 12,
  ),
  DiffLine(kind: DiffLineKind.delete, text: 'first old', oldNumber: 13),
  DiffLine(kind: DiffLineKind.add, text: 'first new', newNumber: 13),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context after 1',
    oldNumber: 14,
    newNumber: 14,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context after 2',
    oldNumber: 15,
    newNumber: 15,
  ),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'context after 3',
    oldNumber: 16,
    newNumber: 16,
  ),
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -20,2 +20,2 @@ SetupBase'),
  DiffLine(
    kind: DiffLineKind.context,
    text: 'second context',
    oldNumber: 20,
    newNumber: 20,
  ),
  DiffLine(kind: DiffLineKind.delete, text: 'second old', oldNumber: 21),
  DiffLine(kind: DiffLineKind.add, text: 'second new', newNumber: 21),
];

final twoHunkDocument = DiffDocument.fromLines(twoHunkLines);

final addedOnlyDocument = DiffDocument.fromLines(const [
  DiffLine(kind: DiffLineKind.hunk, text: '@@ -0,0 +1 @@'),
  DiffLine(kind: DiffLineKind.add, text: 'added line', newNumber: 1),
]);

final resultFile = FileDocument.fromBytes(
  revision: commitA.sha,
  path: fileA.path,
  side: FileDocumentSide.result,
  bytes: Uint8List.fromList(
    utf8.encode(
      '${List.filled(313, 'unchanged').join('\n')}\n'
      'Log(LOGINFO, BASE MODULE VERSION);\n',
    ),
  ),
  gitMarkedBinary: false,
);

final historyEntries = [
  FileHistoryEntry(
    commit: commitA,
    path: fileA.path,
    oldPath: null,
    status: 'M',
  ),
  FileHistoryEntry(
    commit: GitCommit(
      sha: '62874a0',
      shortSha: '62874a0',
      parents: const ['2db06c0'],
      author: fixtureIdentity,
      authorTimestamp: 1720486800,
      committer: fixtureIdentity,
      committerTimestamp: 1720486800,
      refs: const [],
      subject: 'Restore saved window pixel dimensions',
    ),
    path: fileA.path,
    oldPath: null,
    status: 'M',
  ),
];

class NoopSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const NoopSyntaxHighlighter();
  @override
  String? languageForPath(String path) => null;
  @override
  List<CodeTokenSpan> highlightLine(String path, String source) => const [];
}

const fakeHighlighter = NoopSyntaxHighlighter();

Widget qaApp(Widget child) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(body: child),
);
```

각 override의 기본값은 빈 목록이나 빈 `Uint8List`이며, `loadDiff`의
기본값은 `const <DiffLine>[]`입니다.

- [ ] **Step 3: 이름 변경, 양쪽 pathspec과 untracked 파일 실패 테스트를 작성합니다**

`test/full_diff_git_test.dart`에 실제 임시 저장소를 만드는 테스트를
작성합니다.

```dart
Future<String> runGit(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return result.stdout.toString();
}

Future<Directory> createGitFixture() async {
  final root = await Directory.systemTemp.createTemp('yogit_full_diff_');
  await runGit(root, ['init', '-b', 'main']);
  await runGit(root, ['config', 'user.name', 'Test User']);
  await runGit(root, ['config', 'user.email', 'test@example.com']);
  return root;
}

Future<void> writeAndCommit(
  Directory root,
  String path,
  String contents,
  String subject,
) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
  await runGit(root, ['add', '--', path]);
  await runGit(root, ['commit', '-m', subject]);
}

test('finds renames and passes both paths when loading its patch', () async {
  final root = await createGitFixture();
  addTearDown(() => root.delete(recursive: true));
  await writeAndCommit(root, 'old name.pas', 'begin\nend.\n', 'base');
  await runGit(root, ['mv', 'old name.pas', 'new name.pas']);
  await File('${root.path}/new name.pas').writeAsString(
    'begin\n  Writeln(\"renamed\");\nend.\n',
  );
  await runGit(root, ['commit', '-am', 'rename']);

  final calls = <List<String>>[];
  final repository = GitRepository(
    root.path,
    runner: (executable, arguments, {workingDirectory}) {
      calls.add(List.unmodifiable(arguments));
      return runProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
    },
  );
  final commit = (await repository.loadHistory()).first;
  final file = (await repository.loadFiles(commit)).single;
  await repository.loadDiff(commit, file);

  expect(file.status, startsWith('R'));
  expect(file.oldPath, 'old name.pas');
  expect(file.path, 'new name.pas');
  final patchArguments = calls.lastWhere(
    (arguments) =>
        arguments.first == 'diff' && arguments.contains('--unified=3'),
  );
  expect(patchArguments, containsAll([
    '--find-renames=50%',
    'old name.pas',
    'new name.pas',
  ]));
});

test('synthesizes an add document for an untracked working tree file', () async {
  final root = await createGitFixture();
  addTearDown(() => root.delete(recursive: true));
  await writeAndCommit(root, 'tracked.txt', 'tracked\n', 'base');
  await File('${root.path}/new file.txt').writeAsString('one\ntwo\n');
  final repository = GitRepository(root.path);
  final working = (await repository.loadWorkingTree())!;
  final file = (await repository.loadFiles(working))
      .singleWhere((entry) => entry.path == 'new file.txt');

  final lines = await repository.loadDiff(working, file);

  expect(file.status, 'A');
  expect(lines.where((line) => line.kind == DiffLineKind.add), hasLength(2));
  expect(lines.last.newNumber, 2);
});
```

- [ ] **Step 4: 파일 원본, Blame와 이름 변경 History 실패 테스트를 작성합니다**

```dart
test('loads the correct side for deleted files and follows renames', () async {
  final root = await createGitFixture();
  addTearDown(() => root.delete(recursive: true));
  await writeAndCommit(root, 'first.txt', 'old content\n', 'first');
  await runGit(root, ['mv', 'first.txt', 'second.txt']);
  await runGit(root, ['commit', '-m', 'rename once']);
  await runGit(root, ['mv', 'second.txt', 'final.txt']);
  await runGit(root, ['commit', '-m', 'rename twice']);
  await runGit(root, ['rm', 'final.txt']);
  await runGit(root, ['commit', '-m', 'delete']);

  final repository = GitRepository(root.path);
  final deletion = (await repository.loadHistory()).first;
  final file = (await repository.loadFiles(deletion)).single;
  final bytes = await repository.loadFileBytes(deletion, file);
  final history = await repository.loadFileHistory(deletion, file);

  expect(utf8.decode(bytes), 'old content\n');
  expect(history.map((entry) => entry.commit.subject), containsAll([
    'delete',
    'rename twice',
    'rename once',
    'first',
  ]));
  expect(history.map((entry) => entry.path), contains('first.txt'));
});

test('blames tracked and untracked working tree contents', () async {
  final root = await createGitFixture();
  addTearDown(() => root.delete(recursive: true));
  await writeAndCommit(root, 'tracked.txt', 'one\n', 'base');
  await File('${root.path}/tracked.txt').writeAsString('one\ntwo\n');
  await File('${root.path}/new.txt').writeAsString('new\n');

  final repository = GitRepository(root.path);
  final working = (await repository.loadWorkingTree())!;
  final files = await repository.loadFiles(working);
  final tracked = files.singleWhere((file) => file.path == 'tracked.txt');
  final untracked = files.singleWhere((file) => file.path == 'new.txt');
  final trackedBytes = await repository.loadFileBytes(working, tracked);
  final untrackedBytes = await repository.loadFileBytes(working, untracked);

  final trackedBlame = await repository.loadBlame(
    working,
    tracked,
    workingTreeBytes: trackedBytes,
  );
  final untrackedBlame = await repository.loadBlame(
    working,
    untracked,
    workingTreeBytes: untrackedBytes,
  );

  expect(trackedBlame, hasLength(2));
  expect(trackedBlame.last.uncommitted, isTrue);
  expect(untrackedBlame, hasLength(1));
  expect(untrackedBlame.single.author, 'Uncommitted');
});

test('keeps special-character paths intact in blame and history', () async {
  final root = await createGitFixture();
  addTearDown(() => root.delete(recursive: true));
  const oldPath = 'odd\tname.txt';
  const newPath = 'renamed\nname.txt';
  await writeAndCommit(root, oldPath, 'first\n', 'first');
  await runGit(root, ['mv', oldPath, newPath]);
  await runGit(root, ['commit', '-m', 'rename']);

  final repository = GitRepository(root.path);
  final commit = (await repository.loadHistory()).first;
  final file = (await repository.loadFiles(commit)).single;
  final blame = await repository.loadBlame(commit, file);
  final history = await repository.loadFileHistory(commit, file);

  expect(file.path, newPath);
  expect(blame.single.lineNumber, 1);
  expect(history.map((entry) => entry.path), containsAll([oldPath, newPath]));
});
```

- [ ] **Step 5: Git 테스트가 새 동작 때문에 실패하는지 확인합니다**

Run: `flutter test test/full_diff_git_test.dart`

Expected: FAIL because the repository methods still use the old path-only
signature and do not load blame or file history

- [ ] **Step 6: 파일 목록과 patch 명령을 비교 표에 맞춥니다**

`GitRepository.loadFiles`와 `loadDiff`의 공통 안전 인자는 다음과
같습니다.

```dart
const safeDiffArguments = <String>[
  '--no-ext-diff',
  '--no-textconv',
  '--no-color',
  '--find-renames=50%',
];

List<String> pathspecsFor(GitFileChange file) => [
  if (file.oldPath case final oldPath?) oldPath,
  file.path,
];
```

`loadFiles`는 `--name-status -z`와 `--numstat -z`에
`--find-renames=50%`를 넣습니다. 작업 트리에서는 다음 명령의 NUL 구분
경로를 읽어 기존 목록에 없는 파일을 `A`로 추가합니다.

`GitFileChange.isBinary`는 numstat의 추가·삭제 값이 둘 다 `-`인
경우에만 `true`입니다. 통계가 아예 없는 History 임시 정보와 숫자
해석 실패는 바이너리로 간주하지 않습니다.

```dart
[
  'ls-files',
  '--others',
  '--exclude-standard',
  '-z',
]
```

일반 patch는 다음 인자 순서를 사용합니다.

```dart
[
  'diff',
  ...safeDiffArguments,
  '--unified=3',
  if (ignoreWhitespace) '--ignore-all-space',
  ...algorithm.gitArguments,
  ...await _revisionsFor(commit, parent),
  '--',
  ...pathspecsFor(file),
]
```

추적하지 않는 작업 트리 파일은 엄격한 UTF-8로 읽은 각 행을
`DiffLineKind.add`로 만들고 `@@ -0,0 +1,N @@` Hunk를 앞에 붙입니다.
바이너리나 지원하지 않는 인코딩이면 실제 소스 행 없이 header만
반환합니다.

- [ ] **Step 7: 선택 상태별 파일 원본을 구현합니다**

```dart
@override
Future<Uint8List> loadFileBytes(
  GitCommit commit,
  GitFileChange file, {
  String? parent,
}) async {
  final deleted = file.status.startsWith('D');
  if (commit.isWorkingTree && !deleted) {
    return File('$root/${file.path}').readAsBytes();
  }
  final revision = deleted
      ? await _baseFor(commit, parent)
      : commit.sha;
  final path = deleted ? file.oldPath ?? file.path : file.path;
  return loadBlobBytes(revision, path);
}
```

작업 트리에서 삭제된 파일은 `HEAD` 쪽 blob을 읽고 루트 커밋의 추가
파일은 대상 커밋 blob을 읽습니다.

- [ ] **Step 8: Blame 명령과 porcelain 해석을 구현합니다**

상태별 인자는 다음 세 형태로만 만듭니다.

```dart
List<String> blameArguments({
  required GitCommit commit,
  required GitFileChange file,
  required String base,
  required String absolutePath,
}) {
  if (commit.isWorkingTree && !file.status.startsWith('D')) {
    return [
      'blame',
      '--line-porcelain',
      '--contents',
      absolutePath,
      'HEAD',
      '--',
      file.path,
    ];
  }
  return [
    'blame',
    '--line-porcelain',
    commit.isWorkingTree || file.status.startsWith('D') ? base : commit.sha,
    '--',
    file.status.startsWith('D') ? file.oldPath ?? file.path : file.path,
  ];
}
```

추적하지 않는 파일은 파일 행 수만큼 `sha: ''`,
`author: 'Uncommitted'`, `uncommitted: true`인 `GitBlameLine`을
만듭니다. porcelain은 머리행의 결과 행 번호와 `author ` 필드를
읽고 탭으로 시작하는 소스 행을 만날 때 한 행을 확정합니다.

추적 중인 작업 트리 파일은 `--contents` 호출 직전과 직후에 디스크
바이트를 읽습니다. 둘 중 하나라도 controller가 넘긴
`workingTreeBytes`와 다르면 `StateError('Working tree file changed')`를
내고 Blame 결과를 버립니다.

- [ ] **Step 9: NUL 구분 파일 History를 구현합니다**

History 명령은 다음 인자를 사용합니다.

```dart
[
  'log',
  '--follow',
  '--find-renames=50%',
  '--date-order',
  '--format=%x1e%H%x00%h%x00%P%x00%an%x00%ae%x00%at%x00%cn%x00%ce%x00%ct%x00%s%x00',
  '--name-status',
  '-z',
  commit.isWorkingTree ? 'HEAD' : commit.sha,
  '--',
  file.status.startsWith('D') ? file.oldPath ?? file.path : file.path,
]
```

각 `\x1e` 레코드에서 먼저 10개 커밋 필드를 읽고 이어지는 name-status
필드를 해석합니다. `R`과 `C`는 이전 경로와 결과 경로를 모두
보관합니다. `GitFileHistoryRecord.commit`은 전체 SHA, 부모, 작성자,
시간과 제목을 가진 `GitCommit`으로 만듭니다.

- [ ] **Step 10: Git 관련 테스트 전체를 통과시킵니다**

Run:

```bash
dart format lib/git.dart test/git_test.dart test/full_diff_git_test.dart \
  test/support/full_diff_fixtures.dart
flutter test test/git_test.dart test/full_diff_git_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 11: Git 데이터 계층을 커밋합니다**

```bash
git add lib/git.dart test/git_test.dart test/full_diff_git_test.dart \
  test/support/full_diff_fixtures.dart
git commit -m "feat: load full diff file blame and history data"
```

### Task 3: 세션 상태, 요청 순서와 제한된 캐시

**Files:**

- Replace: `lib/full_diff_controller.dart`
- Replace: `test/full_diff_controller_test.dart`

**Interfaces:**

- Consumes: Task 1의 문서 모델과 Task 2의 최종 `FullDiffRepository`
- Produces:
  - `AsyncResource<T>`
  - `FullDiffSessionState`
  - `FullDiffSessionController({repository, commits, initialIndex,
    initialView})`
  - `Future<void> initialize()`
  - `Future<void> selectCommit(GitCommit)`
  - `Future<void> selectParent(String?)`
  - `Future<void> selectFile(GitFileChange)`
  - `Future<void> selectHistoryEntry(FileHistoryEntry)`
  - `void replaceNearbyCommits(List<GitCommit>)`
  - `void setView(FullDiffView)`
  - `void setPresentation(DiffPresentation)`
  - `Future<void> selectAlgorithm(DiffAlgorithm)`
  - `Future<void> setIgnoreWhitespace(bool)`
  - `void setWrapLines(bool)`
  - `void setFocusMode(bool)`
  - `void selectAnchor(DiffAnchor)`
  - `void stepAnchor(int)`
  - `void syncAnchorFromScroll(DiffAnchor)`

- [ ] **Step 1: 독립 로딩과 화면 상태 실패 테스트를 작성합니다**

```dart
test('loads patch and content together and keeps views independent', () async {
  final patch = Completer<List<DiffLine>>();
  final content = Completer<Uint8List>();
  final repository = FakeFullDiffRepository()
    ..files = (_, _) async => const [fileA]
    ..diff = (_, _, _, _, _) => patch.future
    ..content = (_, _, _) => content.future;
  final controller = FullDiffSessionController(
    repository: repository,
    commits: [commitA],
    initialIndex: 0,
    initialView: FullDiffInitialView.hunk,
  );

  final loading = controller.initialize();
  await Future<void>.delayed(Duration.zero);

  expect(controller.state.patch.loading, isTrue);
  expect(controller.state.file.loading, isTrue);
  expect(controller.state.encodingLabel, 'Loading');
  controller
    ..setView(FullDiffView.file)
    ..setPresentation(DiffPresentation.split);
  expect(controller.state.view, FullDiffView.file);
  expect(controller.state.presentation, DiffPresentation.split);
  expect(repository.diffRequests, hasLength(1));

  patch.complete(twoHunkLines);
  content.complete(Uint8List.fromList(utf8.encode('one\ntwo\n')));
  await loading;

  expect(controller.state.patch.data?.hunks, hasLength(2));
  expect(controller.state.file.data?.kind, FileContentKind.utf8);
  expect(controller.state.activeAnchor?.hunkIndex, 0);
});
```

- [ ] **Step 2: 늦은 요청, 옵션 실패와 캐시 제한 실패 테스트를 작성합니다**

```dart
test('a late file cannot replace the current four resources', () async {
  const fileB = GitFileChange(
    path: 'src/window.pas',
    status: 'M',
    additions: 1,
    deletions: 1,
  );
  final patchA = Completer<List<DiffLine>>();
  final patchB = Completer<List<DiffLine>>();
  final contentA = Completer<Uint8List>();
  final contentB = Completer<Uint8List>();
  final repository = FakeFullDiffRepository()
    ..files = (_, _) async => const [fileA, fileB]
    ..diff = (_, file, _, _, _) =>
        file.path == fileA.path ? patchA.future : patchB.future
    ..content = (_, file, _) =>
        file.path == fileA.path ? contentA.future : contentB.future
    ..blame = (_, file, _, _) async => [
      GitBlameLine(
        lineNumber: 1,
        sha: commitA.sha,
        author: file.path,
        uncommitted: false,
      ),
    ]
    ..history = (_, file) async => [
      GitFileHistoryRecord(
        commit: commitA,
        path: file.path,
        oldPath: null,
        status: 'M',
      ),
    ];
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
    initialView: FullDiffInitialView.hunk,
  );
  final firstLoad = controller.initialize();
  await Future<void>.delayed(Duration.zero);
  final secondLoad = controller.selectFile(fileB);
  expect(controller.state.patch.data, isNull);
  expect(controller.state.file.data, isNull);
  expect(controller.state.blame.data, isNull);
  expect(controller.state.history.data, isNull);

  patchB.complete(const [
    DiffLine(kind: DiffLineKind.hunk, text: '@@ -1 +1 @@'),
    DiffLine(kind: DiffLineKind.add, text: 'current', newNumber: 1),
  ]);
  contentB.complete(Uint8List.fromList(utf8.encode('current\n')));
  await secondLoad;
  controller.setView(FullDiffView.blame);
  await Future<void>.delayed(Duration.zero);
  controller.setView(FullDiffView.history);
  await Future<void>.delayed(Duration.zero);

  patchA.complete(twoHunkLines);
  contentA.complete(Uint8List.fromList(utf8.encode('stale\n')));
  await firstLoad;

  expect(controller.state.selectedFile, fileB);
  expect(controller.state.patch.data?.rows.last.text, 'current');
  expect(controller.state.file.data?.lines.single, 'current');
  expect(controller.state.blame.data?.lines.single.author, fileB.path);
  expect(controller.state.history.data?.single.path, fileB.path);
});

test('failed options restore the last successful patch and controls', () async {
  var calls = 0;
  final repository = FakeFullDiffRepository()
    ..files = (_, _) async => const [fileA]
    ..content = (_, _, _) async =>
        Uint8List.fromList(utf8.encode('current\n'))
    ..diff = (_, _, _, algorithm, whitespace) async {
      calls++;
      if (algorithm == DiffAlgorithm.histogram || whitespace) {
        throw const GitRepositoryException('/repo', 'diff failed');
      }
      return twoHunkLines;
    };
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
    initialView: FullDiffInitialView.hunk,
  );
  await controller.initialize();
  final successful = controller.state.patch.data;

  await expectLater(
    controller.selectAlgorithm(DiffAlgorithm.histogram),
    throwsA(isA<GitRepositoryException>()),
  );
  expect(controller.state.patch.data, same(successful));
  expect(controller.state.requestedAlgorithm, DiffAlgorithm.gitSetting);
  expect(controller.state.appliedAlgorithm, DiffAlgorithm.gitSetting);
  expect(calls, 2);
});

test('committed caches stay within count and byte limits', () async {
  final commits = List.generate(
    40,
    (index) => GitCommit(
      sha: 'sha-$index',
      shortSha: '$index'.padLeft(7, '0'),
      parents: index == 39 ? const [] : ['sha-${index + 1}'],
      author: fixtureIdentity,
      authorTimestamp: 1720573200 - index,
      committer: fixtureIdentity,
      committerTimestamp: 1720573200 - index,
      refs: const [],
      subject: 'commit $index',
    ),
  );
  final repository = FakeFullDiffRepository()
    ..files = (_, _) async => const [fileA]
    ..diff = (_, _, _, _, _) async => twoHunkLines
    ..content = (_, _, _) async => Uint8List(2 * 1024 * 1024);
  final controller = FullDiffSessionController(
    repository: repository,
    commits: commits,
    initialIndex: 0,
    initialView: FullDiffInitialView.hunk,
  );
  await controller.initialize();
  for (final commit in commits.skip(1)) {
    await controller.selectCommit(commit);
  }

  expect(controller.debugPatchCacheLength, lessThanOrEqualTo(32));
  expect(controller.debugFileCacheLength, lessThanOrEqualTo(32));
  expect(controller.debugRawCacheBytes, lessThanOrEqualTo(64 * 1024 * 1024));
});

test('replaces a history-only commit with the canonical nearby object', () async {
  final historyCommit = GitCommit(
    sha: 'history-sha',
    shortSha: 'history',
    parents: const ['40aff6d'],
    author: fixtureIdentity,
    authorTimestamp: 1720573100,
    committer: fixtureIdentity,
    committerTimestamp: 1720573100,
    refs: const [],
    subject: 'history copy',
  );
  final canonical = GitCommit(
    sha: historyCommit.sha,
    shortSha: historyCommit.shortSha,
    parents: historyCommit.parents,
    author: historyCommit.author,
    authorTimestamp: historyCommit.authorTimestamp,
    committer: historyCommit.committer,
    committerTimestamp: historyCommit.committerTimestamp,
    refs: const [GitRef(name: 'main', isHead: true)],
    subject: 'canonical row',
  );
  final repository = FakeFullDiffRepository()
    ..files = (_, _) async => const [fileA]
    ..diff = (_, _, _, _, _) async => twoHunkLines
    ..content = (_, _, _) async =>
        Uint8List.fromList(utf8.encode('current\n'));
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
    initialView: FullDiffInitialView.hunk,
  );
  await controller.initialize();
  await controller.selectHistoryEntry(
    FileHistoryEntry(
      commit: historyCommit,
      path: fileA.path,
      oldPath: null,
      status: 'M',
    ),
  );
  controller.replaceNearbyCommits([canonical, commitA]);

  expect(controller.state.selectedCommit, same(canonical));
  expect(controller.state.nearbyCommits.first, same(canonical));
});
```

- [ ] **Step 3: 컨트롤러 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_controller_test.dart`

Expected: FAIL because the existing controller only has files and one diff slot

- [ ] **Step 4: 자원 슬롯과 최종 상태를 정의합니다**

```dart
@immutable
class AsyncResource<T> {
  const AsyncResource({this.data, this.loading = false, this.error});
  final T? data;
  final bool loading;
  final Object? error;

  AsyncResource<T> copyWith({
    Object? data = _unset,
    bool? loading,
    Object? error = _unset,
  }) => AsyncResource<T>(
    data: identical(data, _unset) ? this.data : data as T?,
    loading: loading ?? this.loading,
    error: identical(error, _unset) ? this.error : error,
  );
}

@immutable
class FullDiffSessionState {
  const FullDiffSessionState({
    required this.nearbyCommits,
    required this.selectedCommit,
    required this.parent,
    required this.files,
    required this.selectedFile,
    required this.view,
    required this.presentation,
    required this.activeAnchor,
    required this.requestedAlgorithm,
    required this.appliedAlgorithm,
    required this.requestedIgnoreWhitespace,
    required this.appliedIgnoreWhitespace,
    required this.wrapLines,
    required this.focusMode,
    required this.filesResource,
    required this.patch,
    required this.file,
    required this.blame,
    required this.history,
    required this.selectionGeneration,
    required this.navigationSerial,
  });

  final List<GitCommit> nearbyCommits;
  final GitCommit selectedCommit;
  final String? parent;
  final List<GitFileChange> files;
  final GitFileChange? selectedFile;
  final FullDiffView view;
  final DiffPresentation presentation;
  final DiffAnchor? activeAnchor;
  final DiffAlgorithm requestedAlgorithm;
  final DiffAlgorithm appliedAlgorithm;
  final bool requestedIgnoreWhitespace;
  final bool appliedIgnoreWhitespace;
  final bool wrapLines;
  final bool focusMode;
  final AsyncResource<List<GitFileChange>> filesResource;
  final AsyncResource<DiffDocument> patch;
  final AsyncResource<FileDocument> file;
  final AsyncResource<BlameDocument> blame;
  final AsyncResource<List<FileHistoryEntry>> history;
  final int selectionGeneration;
  final int navigationSerial;

  String get encodingLabel => switch (file.data?.kind) {
    FileContentKind.utf8 => 'UTF-8',
    FileContentKind.binary => 'Binary',
    FileContentKind.unsupportedEncoding => 'Unsupported encoding',
    FileContentKind.tooLarge => 'Too large',
    null => file.loading ? 'Loading' : '—',
  };
}
```

빈 patch는 `activeAnchor: null`입니다. `FullDiffInitialView.fullFile`이면
`view`를 `FullDiffView.file`로, 그 밖에는 `FullDiffView.diff`로
초기화합니다. `presentation`의 초기값은 항상
`DiffPresentation.hunk`입니다.

- [ ] **Step 5: 최근 사용 캐시를 구현합니다**

컨트롤러 안에서 사용할 캐시는 성공한 값의 크기와 접근 순서를
보관합니다.

```dart
typedef PatchCacheKey = ({
  String base,
  String target,
  String? parent,
  String? oldPath,
  String newPath,
  DiffAlgorithm algorithm,
  bool ignoreWhitespace,
});

typedef FileCacheKey = ({
  String revision,
  String path,
  FileDocumentSide side,
});

typedef BlameCacheKey = ({String revision, String path});
typedef HistoryCacheKey = ({String startRevision, String path});

class _CacheEntry<V> {
  _CacheEntry({required this.future, required this.tick});
  final Future<V> future;
  int tick;
  int bytes = 0;
}

class _LruFutureCache<K, V> {
  _LruFutureCache({
    required this.capacity,
    required this.sizeOf,
    required this.nextTick,
  });

  final int capacity;
  final int Function(V value) sizeOf;
  final int Function() nextTick;
  final _entries = LinkedHashMap<K, _CacheEntry<V>>();

  int get length => _entries.length;
  int get resolvedBytes => _entries.values.fold(
    0,
    (sum, entry) => sum + entry.bytes,
  );
  int? get oldestTick => _entries.isEmpty
      ? null
      : _entries.values.map((entry) => entry.tick).reduce(math.min);

  Future<V> getOrLoad(K key, Future<V> Function() loader) {
    final cached = _entries.remove(key);
    if (cached != null) {
      cached.tick = nextTick();
      _entries[key] = cached;
      return cached.future;
    }
    final entry = _CacheEntry<V>(future: loader(), tick: nextTick());
    _entries[key] = entry;
    entry.future.then((value) {
      entry.bytes = sizeOf(value);
      while (_entries.length > capacity) {
        _entries.remove(_entries.keys.first);
      }
    }, onError: (Object _) {
      if (identical(_entries[key], entry)) _entries.remove(key);
    });
    return entry.future;
  }

  void removeOldest() {
    if (_entries.isNotEmpty) _entries.remove(_entries.keys.first);
  }
}
```

컨트롤러의 `_cacheClock`을 두 캐시가 함께 쓰며
`nextTick: () => ++_cacheClock`을 넘깁니다. patch 크기는 모든 header와
source text의 UTF-8 byte length 합계로, 파일 크기는 `bytes.length`로
셉니다. patch와 파일 캐시 합계가 64MiB를 넘으면 두 캐시의
`oldestTick`을 비교해 더 오래된 항목을 하나씩 뺍니다.

`base`는 선택한 parent, parent가 없으면 커밋의 첫 부모, 루트 커밋이면
문자열 `'<empty-tree>'`입니다. `target`은 커밋 SHA이고 작업 트리는
`'<working-tree>'`입니다. 작업 트리이면 네 캐시를 모두 건너뜁니다.

- [ ] **Step 6: 선택 세대와 자원별 요청 번호를 구현합니다**

```dart
int _selectionGeneration = 0;
int _filesRequest = 0;
int _patchRequest = 0;
int _fileRequest = 0;
int _blameRequest = 0;
int _historyRequest = 0;

bool _accepts({
  required int generation,
  required int request,
  required int currentRequest,
  required GitCommit commit,
  required GitFileChange file,
}) =>
    !_disposed &&
    generation == _selectionGeneration &&
    request == currentRequest &&
    state.selectedCommit.sha == commit.sha &&
    state.selectedFile?.path == file.path &&
    state.selectedFile?.oldPath == file.oldPath;
```

파일을 선택하면 `Future.wait([_loadPatch(), _loadFile()])`로 두 요청을
동시에 시작합니다. 커밋·부모·경로를 바꾸는 메서드는 세대를 올리고
patch·file·blame·history의 `data`를 `null`로 만든 뒤 요청합니다.
알고리즘과 공백 옵션은 세대를 유지하고 patch의 마지막 성공
`data`를 남깁니다.

파일 원본이 돌아오면 다음 값으로 `FileDocument.fromBytes`를
호출합니다.

```dart
final deleted = file.status.startsWith('D');
final side = deleted ? FileDocumentSide.old : FileDocumentSide.result;
final revision = commit.isWorkingTree && !deleted
    ? '<working-tree>'
    : deleted
    ? parent ?? commit.parents.first
    : commit.sha;
  final document = FileDocument.fromBytes(
  revision: revision,
  path: deleted ? file.oldPath ?? file.path : file.path,
  side: side,
  bytes: bytes,
  gitMarkedBinary: file.isBinary,
);
```

루트 커밋에서 삭제 상태는 생길 수 없고, 작업 트리 삭제는 `HEAD`를
가리키는 첫 부모가 있으므로 위 `commit.parents.first`가 비지 않습니다.

- [ ] **Step 7: File 준비 뒤 Blame, 독립 History와 History 확정을 구현합니다**

```dart
void setView(FullDiffView view) {
  _replace(state.copyWith(view: view));
  if (view == FullDiffView.blame) unawaited(_ensureBlame());
  if (view == FullDiffView.history) unawaited(_ensureHistory());
}

Future<void> selectHistoryEntry(FileHistoryEntry entry) async {
  final commits = [
    entry.commit,
    for (final commit in state.nearbyCommits)
      if (commit.sha != entry.commit.sha) commit,
  ];
  final parent =
      entry.commit.parents.isEmpty ? null : entry.commit.parents.first;
  _beginSelection(
    commits: commits,
    commit: entry.commit,
    parent: parent,
    selectedFile: null,
  );
  final generation = _selectionGeneration;
  final files = await repository.loadFiles(entry.commit, parent: parent);
  if (_disposed || generation != _selectionGeneration) return;
  final file = files.firstWhere(
    (candidate) =>
        candidate.path == entry.path ||
        candidate.oldPath == entry.path ||
        candidate.path == entry.oldPath,
  );
  _replace(
    state.copyWith(
      files: List.unmodifiable(files),
      selectedFile: file,
      filesResource: AsyncResource(data: List.unmodifiable(files)),
    ),
  );
  await Future.wait([_loadPatch(), _loadFile()]);
}

void replaceNearbyCommits(List<GitCommit> commits) {
  final selectedSha = state.selectedCommit.sha;
  final selected = commits.where((commit) => commit.sha == selectedSha);
  _replace(
    state.copyWith(
      nearbyCommits: List.unmodifiable(
        selected.isEmpty ? [state.selectedCommit, ...commits] : commits,
      ),
      selectedCommit:
          selected.isEmpty ? state.selectedCommit : selected.single,
    ),
  );
}
```

Blame은 `FileContentKind.utf8`인 파일만 요청하며 작업 트리 요청에는
`file.bytes`를 넘깁니다.

- [ ] **Step 8: 앵커 보존과 이동을 구현합니다**

알고리즘 변경 전 앵커의 표시 쪽 소스 행을 기억합니다. 새 patch가
성공하면 다음 함수로 가장 가까운 Hunk를 고릅니다.

```dart
DiffAnchor? nearestAnchor(DiffDocument document, int? sourceLine) {
  if (document.hunks.isEmpty) return null;
  if (sourceLine == null) return document.hunks.first.anchor;
  return document.hunks
      .map((hunk) => hunk.anchor)
      .reduce((best, candidate) {
        int distance(DiffAnchor anchor) =>
            ((anchor.newLine ?? anchor.oldLine ?? 0) - sourceLine).abs();
        return distance(candidate) < distance(best) ? candidate : best;
      });
}
```

`syncAnchorFromScroll`은 상태만 바꾸고 자동 스크롤 신호를 만들지
않습니다. `selectAnchor`와 `stepAnchor`는 화면이 선택 위치를 보여
주도록 controller의 단조 증가 `navigationSerial`도 올립니다.

- [ ] **Step 9: 컨트롤러 테스트를 통과시킵니다**

Run:

```bash
dart format lib/full_diff_controller.dart test/full_diff_controller_test.dart
flutter test test/full_diff_controller_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 10: 컨트롤러를 커밋합니다**

```bash
git add lib/full_diff_controller.dart test/full_diff_controller_test.dart
git commit -m "feat: coordinate full diff workspace resources"
```

이 커밋 뒤 `git.dart`, `full_diff_model.dart`,
`full_diff_controller.dart`의 공개 계약을 구현 병렬 구간 동안
바꾸지 않습니다.

### Task 4: Full Diff 초기 화면 설정

**Files:**

- Modify: `lib/settings.dart:125-314`
- Modify: `lib/settings.dart:342-680`
- Modify: `lib/main.dart:161-322`
- Modify: `lib/timeline.dart:297-355`
- Modify: `lib/timeline.dart:2963-2981`
- Modify: `test/app_test.dart`

**Interfaces:**

- Consumes: Task 1의 `FullDiffView`, Task 3 컨트롤러 생성자의
  `FullDiffInitialView`
- Produces:
  - JSON `fullDiffInitialView`
  - Settings의 `Hunk`, `Full file focused on first change`
  - 새 `DiffScreen`에만 적용하는 초기값

- [ ] **Step 1: 설정 저장과 손상된 값의 실패 테스트를 작성합니다**

```dart
test('full diff initial view round-trips and defaults to hunk', () {
  const settings = AppSettings(
    fullDiffInitialView: FullDiffInitialView.fullFile,
  );

  expect(
    AppSettings.fromJson(settings.toJson()).fullDiffInitialView,
    FullDiffInitialView.fullFile,
  );
  expect(
    AppSettings.fromJson(
      const {'fullDiffInitialView': 'unknown'},
    ).fullDiffInitialView,
    FullDiffInitialView.hunk,
  );
  expect(const AppSettings().fullDiffInitialView, FullDiffInitialView.hunk);
});

testWidgets('settings exposes both full diff starting views', (tester) async {
  final saved = <AppSettings>[];
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        settings: const AppSettings(),
        onChanged: saved.add,
      ),
    ),
  );
  await tester.ensureVisible(
    find.text('Full file focused on first change'),
  );
  expect(find.text('Hunk'), findsOneWidget);
  expect(find.text('Full file focused on first change'), findsOneWidget);

  await tester.tap(find.text('Full file focused on first change'));
  await tester.pump();

  expect(saved.last.fullDiffInitialView, FullDiffInitialView.fullFile);
});

test('a settings change affects only a newly constructed full diff', () {
  var settings = const AppSettings();
  final open = DiffScreen(
    repository: FakeFullDiffRepository(),
    commits: const [commitA],
    initialIndex: 0,
    initialView: settings.fullDiffInitialView,
  );
  settings = settings.copyWith(
    fullDiffInitialView: FullDiffInitialView.fullFile,
  );
  final next = DiffScreen(
    repository: FakeFullDiffRepository(),
    commits: const [commitA],
    initialIndex: 0,
    initialView: settings.fullDiffInitialView,
  );

  expect(open.initialView, FullDiffInitialView.hunk);
  expect(next.initialView, FullDiffInitialView.fullFile);
});
```

- [ ] **Step 2: 설정 테스트가 실패하는지 확인합니다**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name 'full diff initial view round-trips and defaults to hunk'
```

Expected: FAIL because `AppSettings.fullDiffInitialView` does not exist

- [ ] **Step 3: 설정 모델과 JSON을 구현합니다**

생성자와 필드는 다음 두 줄을 현재 `fullDiffColumnWidths` 바로 뒤에
추가합니다.

```dart
this.fullDiffInitialView = FullDiffInitialView.hunk,

final FullDiffInitialView fullDiffInitialView;
```

`copyWith`에는 매개변수와 생성자 전달을 각각 추가합니다.

```dart
FullDiffInitialView? fullDiffInitialView,

fullDiffInitialView:
    fullDiffInitialView ?? this.fullDiffInitialView,
```

`fromJson`이 반환하는 `AppSettings` 생성자에는 다음 값을 넣습니다.

```dart
fullDiffInitialView: switch (value['fullDiffInitialView']) {
  'fullFile' => FullDiffInitialView.fullFile,
  _ => FullDiffInitialView.hunk,
},
```

`toJson`, 동등 비교와 hash에는 각각 다음 항목을 추가합니다.

```dart
'fullDiffInitialView': fullDiffInitialView.name,

fullDiffInitialView == other.fullDiffInitialView

fullDiffInitialView,
```

- [ ] **Step 4: Settings 화면에 Full Diff 영역을 추가합니다**

```dart
const Text(
  'Full Diff',
  style: TextStyle(
    color: Color(0xFFE8EAF2),
    fontSize: 12,
    fontWeight: FontWeight.w600,
  ),
),
RadioGroup<FullDiffInitialView>(
  groupValue: _settings.fullDiffInitialView,
  onChanged: (value) {
    if (value != null) {
      _change(_settings.copyWith(fullDiffInitialView: value));
    }
  },
  child: const Column(
    children: [
      RadioListTile(
        value: FullDiffInitialView.hunk,
        title: Text('Hunk'),
      ),
      RadioListTile(
        value: FullDiffInitialView.fullFile,
        title: Text('Full file focused on first change'),
      ),
    ],
  ),
)
```

화면에 보이는 두 이름은 위 문자열을 그대로 사용합니다.

- [ ] **Step 5: 앱에서 새 Full Diff 화면으로 초기값을 전달합니다**

`TimelineScreen`에 다음 필드를 추가하고 `_openFullDiff`에서
`DiffScreen.initialView`로 넘깁니다.

```dart
final FullDiffInitialView fullDiffInitialView;

DiffScreen(
  repository: widget.repository,
  commits: List.unmodifiable(_commits),
  initialIndex: _commits.indexOf(commit),
  initialView: widget.fullDiffInitialView,
  columnWidths: widget.fullDiffColumnWidths,
  onColumnWidthsChanged: widget.onFullDiffColumnWidthsChanged,
)
```

`YogitApp`은 `_settings.fullDiffInitialView`를 `TimelineScreen`에
전달합니다.

- [ ] **Step 6: 설정 테스트를 통과시킵니다**

Run:

```bash
dart format lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart
flutter test test/app_test.dart \
  --plain-name 'full diff initial view round-trips and defaults to hunk'
flutter test test/app_test.dart \
  --plain-name 'full diff initial view applies only when opening a new screen'
```

Expected: both tests report `All tests passed!`

- [ ] **Step 7: 설정 기능을 커밋합니다**

```bash
git add lib/settings.dart lib/main.dart lib/timeline.dart test/app_test.dart
git commit -m "feat: choose the initial full diff view"
```

### Task 5: 파일명 기반 구문 강조와 단어 변경

**Files:**

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/full_diff_syntax.dart`
- Create: `test/full_diff_syntax_test.dart`

**Interfaces:**

- Consumes: Task 1의 `FullDiffSyntaxHighlighter`, `CodeTokenSpan`
- Produces:
  - `HighlightJsSyntaxHighlighter`
  - `languageForPath`
  - `changedWordRanges(String oldText, String newText)`
  - 512토큰·20,000자 제한

- [ ] **Step 1: 언어 선택과 단어 변경 실패 테스트를 작성합니다**

```dart
test('maps source and configuration names without guessing', () {
  final highlighter = HighlightJsSyntaxHighlighter();
  expect(highlighter.languageForPath('src/drlua.pas'), 'delphi');
  expect(highlighter.languageForPath('lib/main.dart'), 'dart');
  expect(highlighter.languageForPath('Dockerfile'), 'dockerfile');
  expect(highlighter.languageForPath('CMakeLists.txt'), 'cmake');
  expect(highlighter.languageForPath('.env.production'), 'ini');
  expect(highlighter.languageForPath('nginx.conf'), 'nginx');
  expect(highlighter.languageForPath('unknown.data'), isNull);
});

test('marks changed words but skips pathological lines', () {
  final ranges = changedWordRanges(
    'Scale := WindowScale;',
    'Scale := WindowPixelRatio;',
  );
  expect(ranges.oldRanges.single.text, 'WindowScale');
  expect(ranges.newRanges.single.text, 'WindowPixelRatio');
  expect(
    changedWordRanges('a' * 20001, 'b' * 20001).isEmpty,
    isTrue,
  );
  final tooManyOld = List.generate(513, (index) => 'old$index').join(' ');
  final tooManyNew = List.generate(513, (index) => 'new$index').join(' ');
  expect(changedWordRanges(tooManyOld, tooManyNew).isEmpty, isTrue);
});

test('maps every approved extended syntax by file extension', () {
  final highlighter = HighlightJsSyntaxHighlighter();
  const expected = <String, String>{
    'pl': 'perl',
    'r': 'r',
    'jl': 'julia',
    'scala': 'scala',
    'ex': 'elixir',
    'erl': 'erlang',
    'hs': 'haskell',
    'ml': 'ocaml',
    'fs': 'fsharp',
    'clj': 'clojure',
    'lisp': 'lisp',
    'scm': 'scheme',
    'v': 'verilog',
    'vhd': 'vhdl',
    'asm': 'x86asm',
    's': 'armasm',
    'f90': 'fortran',
    'matlab': 'matlab',
    'qml': 'qml',
    'tex': 'latex',
  };
  for (final entry in expected.entries) {
    expect(
      highlighter.languageForPath('fixture.${entry.key}'),
      entry.value,
      reason: entry.key,
    );
  }
});
```

- [ ] **Step 2: 구문 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_syntax_test.dart`

Expected: FAIL because `HighlightJsSyntaxHighlighter` does not exist

- [ ] **Step 3: 확인된 패키지 버전을 추가합니다**

`pubspec.yaml`에 다음 버전을 추가합니다.

```yaml
dependencies:
  flutter:
    sdk: flutter
  highlighting: ^0.9.0+11.8.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  image: ^4.9.1
```

Run: `flutter pub get`

Expected: dependency resolution succeeds and `pubspec.lock` records both
packages

- [ ] **Step 4: 파일명과 확장자 매핑을 구현합니다**

`lib/full_diff_syntax.dart`의 핵심 매핑은 다음과 같습니다.

```dart
const _fileNames = <String, String>{
  'dockerfile': 'dockerfile',
  'makefile': 'makefile',
  'gnumakefile': 'makefile',
  'cmakelists.txt': 'cmake',
  'build.gradle': 'gradle',
  'settings.gradle': 'gradle',
  'nginx.conf': 'nginx',
};

const _extensions = <String, String>{
  'pas': 'delphi',
  'pp': 'delphi',
  'dpr': 'delphi',
  'dart': 'dart',
  'c': 'c',
  'h': 'c',
  'cc': 'cpp',
  'cpp': 'cpp',
  'cxx': 'cpp',
  'm': 'objectivec',
  'mm': 'objectivec',
  'cs': 'csharp',
  'swift': 'swift',
  'java': 'java',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'js': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'go': 'go',
  'rs': 'rust',
  'rb': 'ruby',
  'php': 'php',
  'sh': 'bash',
  'bash': 'bash',
  'ps1': 'powershell',
  'sql': 'sql',
  'lua': 'lua',
  'html': 'xml',
  'htm': 'xml',
  'xml': 'xml',
  'css': 'css',
  'scss': 'scss',
  'json': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
  'toml': 'ini',
  'ini': 'ini',
  'md': 'markdown',
  'markdown': 'markdown',
  'graphql': 'graphql',
  'proto': 'protobuf',
  'diff': 'diff',
  'patch': 'diff',
  'cmake': 'cmake',
  'gradle': 'gradle',
  'properties': 'properties',
  'env': 'ini',
  'nix': 'nix',
  'conf': 'apache',
  'http': 'http',
  'pl': 'perl',
  'pm': 'perl',
  'r': 'r',
  'jl': 'julia',
  'scala': 'scala',
  'ex': 'elixir',
  'exs': 'elixir',
  'erl': 'erlang',
  'hrl': 'erlang',
  'hs': 'haskell',
  'ml': 'ocaml',
  'mli': 'ocaml',
  'fs': 'fsharp',
  'fsx': 'fsharp',
  'clj': 'clojure',
  'cljs': 'clojure',
  'lisp': 'lisp',
  'scm': 'scheme',
  'v': 'verilog',
  'sv': 'verilog',
  'vhd': 'vhdl',
  'vhdl': 'vhdl',
  'asm': 'x86asm',
  's': 'armasm',
  'f': 'fortran',
  'f90': 'fortran',
  'matlab': 'matlab',
  'qml': 'qml',
  'tex': 'latex',
};

String? languageForPath(String path) {
  final name = path.split('/').last.toLowerCase();
  if (_fileNames[name] case final language?) return language;
  if (name == '.env' || name.startsWith('.env.')) return 'ini';
  final dot = name.lastIndexOf('.');
  return dot < 0 ? null : _extensions[name.substring(dot + 1)];
}
```

자동 감지는 호출하지 않습니다. 언어 ID가 없으면 빈 토큰 목록을
반환합니다. `.m`은 Yogit의 macOS 중심 저장소에서 Objective-C와
충돌하므로 Objective-C로 고정하고 MATLAB은 `.matlab` 확장자를
사용합니다.

- [ ] **Step 5: HighlightJS 노드를 Flutter 토큰으로 바꿉니다**

언어 모듈은 다음처럼 직접 가져옵니다.

```dart
import 'package:highlighting/highlighting.dart';
import 'package:highlighting/languages/apache.dart' as lang_apache;
import 'package:highlighting/languages/armasm.dart' as lang_armasm;
import 'package:highlighting/languages/bash.dart' as lang_bash;
import 'package:highlighting/languages/c.dart' as lang_c;
import 'package:highlighting/languages/clojure.dart' as lang_clojure;
import 'package:highlighting/languages/cmake.dart' as lang_cmake;
import 'package:highlighting/languages/cpp.dart' as lang_cpp;
import 'package:highlighting/languages/csharp.dart' as lang_csharp;
import 'package:highlighting/languages/css.dart' as lang_css;
import 'package:highlighting/languages/dart.dart' as lang_dart;
import 'package:highlighting/languages/delphi.dart' as lang_delphi;
import 'package:highlighting/languages/diff.dart' as lang_diff;
import 'package:highlighting/languages/dockerfile.dart' as lang_dockerfile;
import 'package:highlighting/languages/elixir.dart' as lang_elixir;
import 'package:highlighting/languages/erlang.dart' as lang_erlang;
import 'package:highlighting/languages/fortran.dart' as lang_fortran;
import 'package:highlighting/languages/fsharp.dart' as lang_fsharp;
import 'package:highlighting/languages/go.dart' as lang_go;
import 'package:highlighting/languages/gradle.dart' as lang_gradle;
import 'package:highlighting/languages/graphql.dart' as lang_graphql;
import 'package:highlighting/languages/groovy.dart' as lang_groovy;
import 'package:highlighting/languages/haskell.dart' as lang_haskell;
import 'package:highlighting/languages/http.dart' as lang_http;
import 'package:highlighting/languages/ini.dart' as lang_ini;
import 'package:highlighting/languages/java.dart' as lang_java;
import 'package:highlighting/languages/javascript.dart' as lang_javascript;
import 'package:highlighting/languages/json.dart' as lang_json;
import 'package:highlighting/languages/julia.dart' as lang_julia;
import 'package:highlighting/languages/kotlin.dart' as lang_kotlin;
import 'package:highlighting/languages/latex.dart' as lang_latex;
import 'package:highlighting/languages/lisp.dart' as lang_lisp;
import 'package:highlighting/languages/lua.dart' as lang_lua;
import 'package:highlighting/languages/makefile.dart' as lang_makefile;
import 'package:highlighting/languages/markdown.dart' as lang_markdown;
import 'package:highlighting/languages/matlab.dart' as lang_matlab;
import 'package:highlighting/languages/nginx.dart' as lang_nginx;
import 'package:highlighting/languages/nix.dart' as lang_nix;
import 'package:highlighting/languages/objectivec.dart' as lang_objectivec;
import 'package:highlighting/languages/ocaml.dart' as lang_ocaml;
import 'package:highlighting/languages/perl.dart' as lang_perl;
import 'package:highlighting/languages/php.dart' as lang_php;
import 'package:highlighting/languages/powershell.dart' as lang_powershell;
import 'package:highlighting/languages/properties.dart' as lang_properties;
import 'package:highlighting/languages/protobuf.dart' as lang_protobuf;
import 'package:highlighting/languages/python.dart' as lang_python;
import 'package:highlighting/languages/qml.dart' as lang_qml;
import 'package:highlighting/languages/r.dart' as lang_r;
import 'package:highlighting/languages/ruby.dart' as lang_ruby;
import 'package:highlighting/languages/rust.dart' as lang_rust;
import 'package:highlighting/languages/scala.dart' as lang_scala;
import 'package:highlighting/languages/scheme.dart' as lang_scheme;
import 'package:highlighting/languages/scss.dart' as lang_scss;
import 'package:highlighting/languages/sql.dart' as lang_sql;
import 'package:highlighting/languages/swift.dart' as lang_swift;
import 'package:highlighting/languages/typescript.dart' as lang_typescript;
import 'package:highlighting/languages/verilog.dart' as lang_verilog;
import 'package:highlighting/languages/vhdl.dart' as lang_vhdl;
import 'package:highlighting/languages/x86asm.dart' as lang_x86asm;
import 'package:highlighting/languages/xml.dart' as lang_xml;
import 'package:highlighting/languages/yaml.dart' as lang_yaml;
```

기본 모듈은 다음 목록을 한 번 등록합니다.

```dart
final _baseLanguages = [
  lang_delphi.delphi,
  lang_dart.dart,
  lang_c.c,
  lang_cpp.cpp,
  lang_objectivec.objectivec,
  lang_csharp.csharp,
  lang_swift.swift,
  lang_java.java,
  lang_kotlin.kotlin,
  lang_javascript.javascript,
  lang_typescript.typescript,
  lang_python.python,
  lang_go.go,
  lang_rust.rust,
  lang_ruby.ruby,
  lang_php.php,
  lang_bash.bash,
  lang_powershell.powershell,
  lang_sql.sql,
  lang_lua.lua,
  lang_xml.xml,
  lang_css.css,
  lang_scss.scss,
  lang_json.json,
  lang_yaml.yaml,
  lang_ini.ini,
  lang_markdown.markdown,
  lang_graphql.graphql,
  lang_protobuf.protobuf,
  lang_diff.diff,
  lang_dockerfile.dockerfile,
  lang_makefile.makefile,
  lang_cmake.cmake,
  lang_gradle.gradle,
  lang_groovy.groovy,
  lang_properties.properties,
  lang_nginx.nginx,
  lang_nix.nix,
  lang_apache.apache,
  lang_http.http,
];
```

`HighlightJsSyntaxHighlighter.highlightLine`은 결과의 `Node` 트리를
깊이 우선으로 순회하며 다음 색을 적용합니다.

```dart
const _syntaxStyles = <String, TextStyle>{
  'keyword': TextStyle(color: Color(0xFF83C4FF)),
  'built_in': TextStyle(color: Color(0xFF83C4FF)),
  'type': TextStyle(color: Color(0xFF83C4FF)),
  'string': TextStyle(color: Color(0xFFFFBFA0)),
  'number': TextStyle(color: Color(0xFFC9E28B)),
  'literal': TextStyle(color: Color(0xFFC9E28B)),
  'comment': TextStyle(color: Color(0xFF919191)),
  'title': TextStyle(color: Color(0xFFD7BA7D)),
  'attr': TextStyle(color: Color(0xFF9CDCFE)),
  'variable': TextStyle(color: Color(0xFF9CDCFE)),
};
```

각 `CodeTokenSpan`의 `start`와 `end`는 원본 한 줄의 UTF-16 offset을
사용합니다. 분류가 없는 텍스트는 기본 흰색으로 남깁니다.

- [ ] **Step 6: 단어 변경 범위를 구현합니다**

```dart
const maxWordDiffTokens = 512;
const maxWordDiffCharacters = 20000;

@immutable
class WordRange {
  const WordRange({
    required this.text,
    required this.start,
    required this.end,
  });
  final String text;
  final int start;
  final int end;
}

@immutable
class WordChangeRanges {
  const WordChangeRanges({
    required this.oldRanges,
    required this.newRanges,
  });
  static const empty = WordChangeRanges(oldRanges: [], newRanges: []);
  final List<WordRange> oldRanges;
  final List<WordRange> newRanges;
  bool get isEmpty => oldRanges.isEmpty && newRanges.isEmpty;
}

WordChangeRanges changedWordRanges(String oldText, String newText) {
  if (oldText.length > maxWordDiffCharacters ||
      newText.length > maxWordDiffCharacters) {
    return WordChangeRanges.empty;
  }
  final oldTokens = tokenizeWords(oldText);
  final newTokens = tokenizeWords(newText);
  if (oldTokens.length > maxWordDiffTokens ||
      newTokens.length > maxWordDiffTokens) {
    return WordChangeRanges.empty;
  }
  var prefix = 0;
  while (prefix < oldTokens.length &&
      prefix < newTokens.length &&
      oldTokens[prefix].text == newTokens[prefix].text) {
    prefix++;
  }
  var oldSuffix = oldTokens.length;
  var newSuffix = newTokens.length;
  while (oldSuffix > prefix &&
      newSuffix > prefix &&
      oldTokens[oldSuffix - 1].text == newTokens[newSuffix - 1].text) {
    oldSuffix--;
    newSuffix--;
  }
  return WordChangeRanges(
    oldRanges: List.unmodifiable(oldTokens.sublist(prefix, oldSuffix)),
    newRanges: List.unmodifiable(newTokens.sublist(prefix, newSuffix)),
  );
}
```

`tokenizeWords`는 `RegExp(r'\w+|[^\w\s]+|\s+')`의 모든 match에서
text, start, end를 보관합니다.

- [ ] **Step 7: 기본 문법과 확장 문법을 분리해 등록합니다**

```dart
const extendedSyntaxEnabled = bool.fromEnvironment(
  'YOGIT_EXTENDED_SYNTAX',
  defaultValue: true,
);

const extendedLanguageIds = <String>{
  'perl', 'r', 'julia', 'scala', 'elixir', 'erlang', 'haskell', 'ocaml',
  'fsharp', 'clojure', 'lisp', 'scheme', 'verilog', 'vhdl', 'x86asm',
  'armasm', 'fortran', 'matlab', 'qml', 'latex',
};

List<dynamic> get _extendedLanguages => [
  lang_perl.perl,
  lang_r.r,
  lang_julia.julia,
  lang_scala.scala,
  lang_elixir.elixir,
  lang_erlang.erlang,
  lang_haskell.haskell,
  lang_ocaml.ocaml,
  lang_fsharp.fsharp,
  lang_clojure.clojure,
  lang_lisp.lisp,
  lang_scheme.scheme,
  lang_verilog.verilog,
  lang_vhdl.vhdl,
  lang_x86asm.x86asm,
  lang_armasm.armasm,
  lang_fortran.fortran,
  lang_matlab.matlab,
  lang_qml.qml,
  lang_latex.latex,
];

var _languagesRegistered = false;

void registerFullDiffLanguages() {
  if (_languagesRegistered) return;
  _languagesRegistered = true;
  for (final language in _baseLanguages) {
    highlight.registerLanguage(language);
  }
  if (extendedSyntaxEnabled) {
    for (final language in _extendedLanguages) {
      highlight.registerLanguage(language);
    }
  }
}
```

기본 언어와 확장 언어를 각각 직접 import합니다. 확장 언어 등록은
`if (extendedSyntaxEnabled)` 안에서만 해당 symbol을 참조해
`--dart-define=YOGIT_EXTENDED_SYNTAX=false` 빌드에서 tree shaking할 수
있게 합니다.

- [ ] **Step 8: 구문 테스트를 통과시킵니다**

Run:

```bash
dart format lib/full_diff_syntax.dart test/full_diff_syntax_test.dart
flutter test test/full_diff_syntax_test.dart
flutter analyze
```

Expected: tests report `All tests passed!` and analysis finishes without errors

- [ ] **Step 9: 구문 강조를 커밋합니다**

```bash
git add pubspec.yaml pubspec.lock lib/full_diff_syntax.dart \
  test/full_diff_syntax_test.dart
git commit -m "feat: highlight full diff source and changed words"
```

### Task 6: Hunk, Inline와 Split 표시

**Files:**

- Create: `lib/full_diff_code_row.dart`
- Replace: `lib/full_diff_hunk_view.dart`
- Create: `lib/full_diff_inline_view.dart`
- Create: `lib/full_diff_split_view.dart`
- Replace: `test/full_diff_widgets_test.dart`

**Interfaces:**

- Consumes: Task 1의 문서·색상·구문 계약, Task 5의 단어 변경 범위
- Produces:
  - `FullDiffCodeRow`
  - `HunkPresentationView`
  - `InlinePresentationView`
  - `SplitPresentationView`
  - 각 앵커의 `GlobalKey`

- [ ] **Step 1: 세 표시 방식의 실패 위젯 테스트를 작성합니다**

```dart
Future<void> pumpPresentation(
  WidgetTester tester, {
  required DiffPresentation presentation,
  required DiffDocument document,
  DiffAnchor? activeAnchor,
}) async {
  final child = switch (presentation) {
    DiffPresentation.hunk => HunkPresentationView(
      document: document,
      activeAnchor: activeAnchor ??
          (document.hunks.isEmpty ? null : document.hunks.first.anchor),
      path: fileA.path,
      wrapLines: false,
      highlighter: fakeHighlighter,
    ),
    DiffPresentation.inline => InlinePresentationView(
      document: document,
      activeAnchor: activeAnchor ??
          (document.hunks.isEmpty ? null : document.hunks.first.anchor),
      path: fileA.path,
      wrapLines: false,
      highlighter: fakeHighlighter,
    ),
    DiffPresentation.split => SplitPresentationView(
      document: document,
      activeAnchor: activeAnchor ??
          (document.hunks.isEmpty ? null : document.hunks.first.anchor),
      oldPath: fileA.oldPath ?? fileA.path,
      newPath: fileA.path,
      wrapLines: false,
      showOldSide: true,
      highlighter: fakeHighlighter,
    ),
  };
  await tester.pumpWidget(qaApp(SizedBox(width: 800, child: child)));
  await tester.pumpAndSettle();
}

testWidgets('hunk shows only changed rows for the active block', (tester) async {
  await pumpPresentation(
    tester,
    presentation: DiffPresentation.hunk,
    document: twoHunkDocument,
    activeAnchor: twoHunkDocument.hunks.last.anchor,
  );

  expect(find.text('second old'), findsOneWidget);
  expect(find.text('second new'), findsOneWidget);
  expect(find.text('second context'), findsNothing);
  expect(find.text('first old'), findsNothing);
  expect(find.text('SetupBase · lines 20–21 · change 2 of 2'), findsOneWidget);
});

testWidgets('inline shows every hunk with three context lines', (tester) async {
  await pumpPresentation(
    tester,
    presentation: DiffPresentation.inline,
    document: twoHunkDocument,
  );
  expect(find.byKey(const Key('inline-hunk-0')), findsOneWidget);
  expect(find.byKey(const Key('inline-hunk-1')), findsOneWidget);
  expect(find.text('context before 3'), findsOneWidget);
  expect(find.text('context after 3'), findsOneWidget);
});

testWidgets('split pairs replacements and hatches a missing side', (
  tester,
) async {
  await pumpPresentation(
    tester,
    presentation: DiffPresentation.split,
    document: addedOnlyDocument,
  );
  expect(find.byKey(const Key('split-missing-old-0')), findsOneWidget);
  expect(find.text('added line'), findsOneWidget);
});

testWidgets('hunk empty state and each hunk selection boundary are explicit', (
  tester,
) async {
  await pumpPresentation(
    tester,
    presentation: DiffPresentation.hunk,
    document: DiffDocument.fromLines(const []),
  );
  expect(find.text('현재 옵션으로 표시할 변경이 없습니다'), findsOneWidget);

  await pumpPresentation(
    tester,
    presentation: DiffPresentation.inline,
    document: twoHunkDocument,
  );
  expect(find.byType(SelectionArea), findsNWidgets(2));
});

testWidgets('code rows expose sign current line and word emphasis', (
  tester,
) async {
  await tester.pumpWidget(
    qaApp(
      FullDiffCodeRow(
        line: const DiffLine(
          kind: DiffLineKind.add,
          text: 'Scale := WindowPixelRatio;',
          newNumber: 314,
        ),
        path: fileA.path,
        wrapLines: false,
        highlighter: fakeHighlighter,
        current: true,
        wordRanges: const [
          WordRange(text: 'WindowPixelRatio', start: 9, end: 25),
        ],
      ),
    ),
  );

  expect(find.text('+'), findsOneWidget);
  expect(find.text('314'), findsOneWidget);
  expect(find.byKey(const Key('code-row-current-marker')), findsOneWidget);
  expect(
    find.byKey(const Key('code-row-horizontal-scroll')),
    findsOneWidget,
  );
  final richText = tester.widget<RichText>(
    find.byKey(const Key('code-row-source-text')),
  );
  final spans = (richText.text as TextSpan).children!.cast<TextSpan>();
  expect(
    spans.any(
      (span) =>
          span.style?.backgroundColor == fullDiffWordChange &&
          span.style?.decoration == TextDecoration.underline,
    ),
    isTrue,
  );
});
```

- [ ] **Step 2: 표시 방식 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_widgets_test.dart`

Expected: FAIL because the three final presentation widgets do not exist

- [ ] **Step 3: 공용 소스 행을 구현합니다**

`FullDiffCodeRow`는 다음 생성자와 고정 gutter를 사용합니다.

```dart
class FullDiffCodeRow extends StatelessWidget {
  const FullDiffCodeRow({
    required this.line,
    required this.path,
    required this.wrapLines,
    required this.highlighter,
    this.current = false,
    this.wordRanges = const [],
    this.compactGutter = false,
    super.key,
  });

  final DiffLine line;
  final String path;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final bool current;
  final List<WordRange> wordRanges;
  final bool compactGutter;
}
```

행 바탕과 번호 영역은 다음 switch로 고정합니다.

```dart
final (sourceColor, gutterColor, marker) = switch (line.kind) {
  DiffLineKind.add =>
    (fullDiffAddedSource, fullDiffAddedGutter, '+'),
  DiffLineKind.delete =>
    (fullDiffDeletedSource, fullDiffDeletedGutter, '−'),
  _ => (fullDiffCanvas, fullDiffCanvas, ' '),
};
```

현재 행은 source 영역 왼쪽 안쪽에 `Container(width: 3,
color: fullDiffAccent)`를 겹쳐 놓습니다. 소스는 Menlo 14px,
line-height 21px이고 구문 span 위에 단어 변경 배경과 파란 밑줄을
합칩니다.

테스트가 구조와 스타일을 직접 확인할 수 있도록 현재 행 선,
가로 스크롤과 소스 `RichText`에는 각각
`code-row-current-marker`, `code-row-horizontal-scroll`,
`code-row-source-text` 키를 둡니다. `wrapLines`가 참이면 가로 스크롤
위젯 대신 줄바꿈하는 `RichText`를 사용합니다.

- [ ] **Step 4: 활성 Hunk만 그리는 보기를 구현합니다**

```dart
class HunkPresentationView extends StatelessWidget {
  const HunkPresentationView({
    required this.document,
    required this.activeAnchor,
    required this.path,
    required this.wrapLines,
    required this.highlighter,
    super.key,
  });

  final DiffDocument document;
  final DiffAnchor? activeAnchor;
  final String path;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;

  @override
  Widget build(BuildContext context) {
    if (activeAnchor == null) {
      return const Center(
        child: Text(
          '현재 옵션으로 표시할 변경이 없습니다',
          style: TextStyle(color: fullDiffMuted, fontSize: 14),
        ),
      );
    }
    final hunk = document.hunks[activeAnchor!.hunkIndex];
    return SelectionArea(
      child: ListView(
        primary: true,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: const BoxDecoration(
              color: fullDiffHunkHeader,
              border: Border(
                top: BorderSide(color: fullDiffDivider),
                bottom: BorderSide(color: fullDiffDivider),
              ),
            ),
            child: Text(
              '${hunk.context.isEmpty ? path : hunk.context} · '
              'lines ${hunk.displayRange} · '
              'change ${hunk.index + 1} of ${document.hunks.length}',
              style: const TextStyle(
                fontFamily: technicalFontFamily,
                fontFamilyFallback: technicalFontFallback,
                fontSize: 14,
                height: 21 / 14,
                color: fullDiffMuted,
              ),
            ),
          ),
          for (final line in hunk.changedLines)
            FullDiffCodeRow(
              line: line,
              path: path,
              wrapLines: wrapLines,
              highlighter: highlighter,
              current: true,
            ),
        ],
      ),
    );
  }
}
```

삭제 전용 Hunk의 `displayRange`는 이전 쪽 범위를 사용하고, 나머지는
결과 쪽 범위를 사용합니다.

- [ ] **Step 5: Inline과 Split 보기를 구현합니다**

Inline은 `ListView.builder(primary: true,
itemCount: document.hunks.length)`로 각 Hunk 머리글과 `hunk.lines`를
이어 붙입니다. Split도 `primary: true`인 `ListView.builder`에서
`pairDiff(hunk.lines)`를 사용합니다.

```dart
Widget splitRow(DiffPair pair, int index) => Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Expanded(
      child: pair.left == null
          ? HatchedDiffCell(key: Key('split-missing-old-$index'))
          : FullDiffCodeRow(
              line: pair.left!,
              path: oldPath,
              wrapLines: wrapLines,
              highlighter: highlighter,
            ),
    ),
    const VerticalDivider(width: 1, color: fullDiffDivider),
    Expanded(
      child: pair.right == null
          ? HatchedDiffCell(key: Key('split-missing-new-$index'))
          : FullDiffCodeRow(
              line: pair.right!,
              path: newPath,
              wrapLines: wrapLines,
              highlighter: highlighter,
            ),
    ),
  ],
);
```

`HatchedDiffCell`의 painter는 `#353535` 바탕에 `#4A4A4A` 1px 선을
8px 간격으로 왼쪽 아래에서 오른쪽 위로 긋습니다.

- [ ] **Step 6: 짝지은 삭제·추가 행에 단어 변경을 연결합니다**

Split에서는 같은 `DiffPair`의 좌우가 삭제·추가일 때
`changedWordRanges`를 한 번 호출합니다. Inline에서는 연속된 삭제 묶음과
바로 뒤 추가 묶음을 `pairDiff`로 짝지어 같은 범위를 각 원래 행에
연결합니다. Hunk도 같은 방식으로 활성 Hunk 안에서만 계산합니다.

```dart
final wordChanges = left?.kind == DiffLineKind.delete &&
        right?.kind == DiffLineKind.add
    ? changedWordRanges(left!.text, right!.text)
    : WordChangeRanges.empty;
```

`FileDocument.disableRichRendering`이 참이면 highlighter와 단어 범위에
빈 구현을 넘깁니다.

- [ ] **Step 7: 표시 위젯 테스트를 통과시킵니다**

Run:

```bash
dart format lib/full_diff_code_row.dart lib/full_diff_hunk_view.dart \
  lib/full_diff_inline_view.dart lib/full_diff_split_view.dart \
  test/full_diff_widgets_test.dart
flutter test test/full_diff_widgets_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 8: 세 Diff 표시 방식을 커밋합니다**

```bash
git add lib/full_diff_code_row.dart lib/full_diff_hunk_view.dart \
  lib/full_diff_inline_view.dart lib/full_diff_split_view.dart \
  test/full_diff_widgets_test.dart
git commit -m "feat: render hunk inline and split diffs"
```

### Task 7: File, Blame와 History 보기

**Files:**

- Create: `lib/full_file_view.dart`
- Create: `lib/full_blame_view.dart`
- Create: `lib/full_history_view.dart`
- Create: `test/full_diff_content_views_test.dart`

**Interfaces:**

- Consumes: Task 3의 독립 자원 슬롯, Task 5의 highlighter, Task 6의
  `FullDiffCodeRow`
- Produces:
  - `FullFileView`
  - `FullBlameView`
  - `FullHistoryView`
  - `HistoryEntryIntent`

- [ ] **Step 1: File과 특수 파일 상태 실패 테스트를 작성합니다**

```dart
testWidgets('file view shows the selected side and current source line', (
  tester,
) async {
  await tester.pumpWidget(
    qaApp(
      FullFileView(
        document: resultFile,
        path: 'src/drlua.pas',
        activeAnchor: const DiffAnchor(
          hunkIndex: 0,
          oldLine: 313,
          newLine: 314,
        ),
        wrapLines: false,
        highlighter: fakeHighlighter,
      ),
    ),
  );

  expect(find.text('314'), findsOneWidget);
  expect(find.byKey(const Key('file-current-line-314')), findsOneWidget);
  expect(find.text('Log(LOGINFO, BASE MODULE VERSION);'), findsOneWidget);
});

testWidgets('file view distinguishes every non-source state', (tester) async {
  final cases = <(FileContentKind, String)>[
    (FileContentKind.binary, 'Binary file'),
    (FileContentKind.unsupportedEncoding, 'Unsupported encoding'),
    (FileContentKind.tooLarge, 'File too large'),
  ];
  for (final (kind, label) in cases) {
    await tester.pumpWidget(
      qaApp(
        FullFileView(
          document: FileDocument(
            revision: commitA.sha,
            path: fileA.path,
            side: FileDocumentSide.result,
            bytes: Uint8List(0),
            kind: kind,
            lines: const [],
            hasTrailingNewline: false,
            disableRichRendering: true,
            fingerprint: '0:0',
          ),
          path: fileA.path,
          activeAnchor: null,
          wrapLines: false,
          highlighter: fakeHighlighter,
        ),
      ),
    );
    expect(find.text(label), findsOneWidget, reason: '$kind');
  }

  final empty = FileDocument.fromBytes(
    revision: commitA.sha,
    path: 'empty.txt',
    side: FileDocumentSide.result,
    bytes: Uint8List(0),
    gitMarkedBinary: false,
  );
  await tester.pumpWidget(
    qaApp(
      FullFileView(
        document: empty,
        path: empty.path,
        activeAnchor: null,
        wrapLines: false,
        highlighter: fakeHighlighter,
      ),
    ),
  );
  expect(find.text('Empty file'), findsOneWidget);

  final deleted = FileDocument.fromBytes(
    revision: commitA.parents.single,
    path: 'deleted.txt',
    side: FileDocumentSide.old,
    bytes: Uint8List.fromList(utf8.encode('old content\n')),
    gitMarkedBinary: false,
  );
  await tester.pumpWidget(
    qaApp(
      FullFileView(
        document: deleted,
        path: deleted.path,
        activeAnchor: null,
        wrapLines: false,
        highlighter: fakeHighlighter,
      ),
    ),
  );
  expect(find.text('Deleted file · showing previous version'), findsOneWidget);
  expect(find.text('old content'), findsOneWidget);
});
```

- [ ] **Step 2: Blame 정렬과 History 확정 실패 테스트를 작성합니다**

```dart
testWidgets('history focus does not select until enter or click', (
  tester,
) async {
  FileHistoryEntry? selected;
  await tester.pumpWidget(
    qaApp(
      FullHistoryView(
        entries: historyEntries,
        onSelected: (entry) => selected = entry,
      ),
    ),
  );

  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  expect(selected, isNull);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  expect(selected, historyEntries[1]);
});

testWidgets('blame keeps metadata and source rows aligned', (tester) async {
  final file = FileDocument.fromBytes(
    revision: commitA.sha,
    path: 'two.txt',
    side: FileDocumentSide.result,
    bytes: Uint8List.fromList(utf8.encode('alpha\nbeta\n')),
    gitMarkedBinary: false,
  );
  final blame = BlameDocument.fromGitLines(file, const [
    GitBlameLine(
      lineNumber: 1,
      sha: '',
      author: 'Uncommitted',
      uncommitted: true,
    ),
    GitBlameLine(
      lineNumber: 2,
      sha: '40aff6d123456789',
      author: 'Suwon Chae',
      uncommitted: false,
    ),
  ]);
  await tester.pumpWidget(
    qaApp(
      FullBlameView(
        document: blame,
        activeAnchor: const DiffAnchor(
          hunkIndex: 0,
          oldLine: 1,
          newLine: 1,
        ),
        wrapLines: false,
        highlighter: fakeHighlighter,
      ),
    ),
  );

  expect(find.byKey(const Key('blame-list')), findsOneWidget);
  expect(find.text('·······'), findsOneWidget);
  expect(find.text('Uncommitted'), findsOneWidget);
  expect(find.text('40aff6d'), findsOneWidget);
  expect(find.text('Suwon Chae'), findsOneWidget);
  expect(find.text('alpha'), findsOneWidget);
  expect(find.text('beta'), findsOneWidget);
});
```

- [ ] **Step 3: 콘텐츠 보기 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_content_views_test.dart`

Expected: FAIL because the three content view widgets do not exist

- [ ] **Step 4: 전체 파일 보기를 구현합니다**

`FullFileView`는 `ListView.builder(primary: true)`로
`FileDocument.lines`만 필요한 만큼 만듭니다.

```dart
class FullFileView extends StatelessWidget {
  const FullFileView({
    required this.document,
    required this.path,
    required this.activeAnchor,
    required this.wrapLines,
    required this.highlighter,
    super.key,
  });

  final FileDocument document;
  final String path;
  final DiffAnchor? activeAnchor;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
}

final line = DiffLine(
  kind: DiffLineKind.context,
  text: document.lines[index],
  oldNumber: document.side == FileDocumentSide.old ? index + 1 : null,
  newNumber: document.side == FileDocumentSide.result ? index + 1 : null,
);
return KeyedSubtree(
  key: index + 1 == activeSourceLine
      ? Key('file-current-line-${index + 1}')
      : null,
  child: FullDiffCodeRow(
    line: line,
    path: path,
    wrapLines: wrapLines,
    highlighter: highlighter,
    current: index + 1 == activeSourceLine,
  ),
);
```

삭제 파일은 old 번호를 사용합니다. `kind`가 `utf8`이 아니면 list를
만들지 않고 `Binary file`, `Unsupported encoding`, `File too large`를
가운데 표시합니다. UTF-8 행이 없으면 `Empty file`을 표시합니다.
`side == FileDocumentSide.old`이면 소스 위에
`Deleted file · showing previous version` 배너를 둡니다.

- [ ] **Step 5: Blame 보기를 구현합니다**

Blame의 각 행은 폭 76px SHA, 폭 108px 작성자와
`FullDiffCodeRow(compactGutter: true)`를 한 행에 둡니다. SHA는 7자로
줄이고 Menlo 12px, 작성자는 시스템 UI 12px로 표시합니다.
`Uncommitted` 행은 SHA 자리에 `·······`를 표시합니다.

```dart
class FullBlameView extends StatelessWidget {
  const FullBlameView({
    required this.document,
    required this.activeAnchor,
    required this.wrapLines,
    required this.highlighter,
    super.key,
  });

  final BlameDocument document;
  final DiffAnchor? activeAnchor;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
}

ListView.builder(
  key: const Key('blame-list'),
  primary: true,
  itemCount: document.file.lines.length,
  itemBuilder: (context, index) => BlameSourceRow(
    blame: document.lines[index],
    source: document.file.lines[index],
    current: index + 1 == activeSourceLine,
  ),
)
```

- [ ] **Step 6: History 보기를 구현합니다**

각 행은 SHA, 제목, 작성자, 상대 시간을 표시하고 `Focus`와
`InkWell`을 함께 사용합니다.

```dart
class FullHistoryView extends StatelessWidget {
  const FullHistoryView({
    required this.entries,
    required this.onSelected,
    this.selected,
    super.key,
  });

  final List<FileHistoryEntry> entries;
  final ValueChanged<FileHistoryEntry> onSelected;
  final FileHistoryEntry? selected;
}

onKeyEvent: (_, event) {
  if (event is KeyDownEvent &&
      event.logicalKey == LogicalKeyboardKey.enter) {
    onSelected(entry);
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
},
child: InkWell(
  onTap: () => onSelected(entry),
  child: HistoryRow(entry: entry),
),
```

행 선택은 모서리 없는 `fullDiffSelection` 배경으로 알립니다. History
보기 자체는 미니맵을 만들지 않습니다.

- [ ] **Step 7: 콘텐츠 보기 테스트를 통과시킵니다**

Run:

```bash
dart format lib/full_file_view.dart lib/full_blame_view.dart \
  lib/full_history_view.dart test/full_diff_content_views_test.dart
flutter test test/full_diff_content_views_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 8: 세 콘텐츠 보기를 커밋합니다**

```bash
git add lib/full_file_view.dart lib/full_blame_view.dart \
  lib/full_history_view.dart test/full_diff_content_views_test.dart
git commit -m "feat: render full file blame and file history"
```

### Task 8: 승인된 두 머리글과 조작 요소

**Files:**

- Replace: `lib/full_diff_header.dart`
- Create: `test/full_diff_header_test.dart`

**Interfaces:**

- Consumes: Task 1의 상태 enum·시각 상수, `DiffAlgorithm`,
  `GitFileChange`
- Produces:
  - `GlobalFileBar`
  - `GlobalDiffToolbar`
  - `FullDiffSegmentedControl<T>`
  - 웹 시안과 같은 이름, 순서, 선택·사용 가능 상태
  - 접근성 이름, 선택 상태와 사용 가능 상태

- [ ] **Step 1: 메뉴 이름과 순서를 고정하는 실패 테스트를 작성합니다**

```dart
Future<void> pumpHeaders(
  WidgetTester tester, {
  FullDiffView view = FullDiffView.diff,
  bool focusMode = false,
}) => tester.pumpWidget(
  qaApp(
    Column(
      children: [
        GlobalFileBar(
          file: fileA,
          path: fileA.path,
          view: view,
          encodingLabel: 'UTF-8',
          canOpenEditor: true,
          onOpenEditor: () {},
          onViewSelected: (_) {},
        ),
        GlobalDiffToolbar(
          view: view,
          presentation: DiffPresentation.hunk,
          activeIndex: 1,
          anchorCount: 7,
          algorithm: DiffAlgorithm.histogram,
          ignoreWhitespace: false,
          wrapLines: false,
          focusMode: focusMode,
          loadingPatch: false,
          onPresentationSelected: (_) {},
          onPrevious: () {},
          onNext: () {},
          onAlgorithmSelected: (_) {},
          onIgnoreWhitespaceChanged: (_) {},
          onWrapLinesChanged: (_) {},
          onFocusModeChanged: (_) {},
        ),
      ],
    ),
  ),
);

testWidgets('global bars keep the approved labels in exact order', (
  tester,
) async {
  await pumpHeaders(tester);
  final labels = tester.widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .toList();

  expect(labels, containsAllInOrder([
    'src/drlua.pas',
    'M · +12 −4',
    '편집기로 열기',
    'File',
    'Diff',
    'Blame',
    'History',
    'UTF-8',
    '집중 모드',
    'Hunk',
    'Inline',
    'Split',
    '2 / 7',
    'diff 알고리즘',
    '공백 무시',
    '줄바꿈',
  ]));
  expect(find.text('Histogram'), findsNothing);
});

testWidgets('algorithm menu shows five choices but keeps its closed label', (
  tester,
) async {
  await pumpHeaders(tester);
  await tester.tap(find.byKey(const Key('diff-algorithm')));
  await tester.pumpAndSettle();

  for (final label in [
    'Git setting',
    'Myers',
    'Minimal',
    'Patience',
    'Histogram',
  ]) {
    expect(find.text(label), findsOneWidget);
  }
  final checked = tester
      .widgetList<CheckedPopupMenuItem<DiffAlgorithm>>(
        find.byType(CheckedPopupMenuItem<DiffAlgorithm>),
      )
      .singleWhere((item) => item.checked);
  expect(checked.value, DiffAlgorithm.histogram);

  await tester.tap(find.text('Histogram'));
  await tester.pumpAndSettle();
  expect(find.text('diff 알고리즘'), findsOneWidget);
  expect(find.text('Histogram'), findsNothing);
});

testWidgets('history keeps navigation slots disabled and focus mode renames', (
  tester,
) async {
  await pumpHeaders(tester, view: FullDiffView.history);
  expect(
    tester.widget<IconButton>(
      find.byKey(const Key('previous-change')),
    ).onPressed,
    isNull,
  );
  expect(
    tester.widget<IconButton>(
      find.byKey(const Key('next-change')),
    ).onPressed,
    isNull,
  );
  expect(find.byKey(const Key('change-counter')), findsOneWidget);

  await pumpHeaders(tester, focusMode: true);
  expect(find.text('탐색 패널'), findsOneWidget);
  expect(find.text('집중 모드'), findsNothing);
});
```

- [ ] **Step 2: 머리글 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_header_test.dart`

Expected: FAIL because the current header has different components and order

- [ ] **Step 3: 첫 번째 머리글을 구현합니다**

```dart
class GlobalFileBar extends StatelessWidget {
  const GlobalFileBar({
    required this.file,
    required this.path,
    required this.view,
    required this.encodingLabel,
    required this.canOpenEditor,
    required this.onOpenEditor,
    required this.onViewSelected,
    this.editorError,
    super.key,
  });
}
```

본문은 `Wrap` 두 그룹을 가진 `Row`이며 왼쪽 그룹 뒤에 `Spacer`를
둡니다. 높이가 부족하면 바깥 `Wrap`이 같은 순서를 유지한 채 다음
줄로 넘깁니다. 경로 칩은 최대 한 줄, 7.5px 반지름, Menlo 14px입니다.
상태 배지는 다음 문자열을 사용합니다.

```dart
String fileSummary(GitFileChange file) =>
    '${file.status.characters.first} · '
    '+${file.additions ?? '—'} −${file.deletions ?? '—'}';
```

선택한 주 화면 버튼은 흰 배경과 검은 글자, 나머지는
`fullDiffControl`과 흰 글자를 사용합니다.

- [ ] **Step 4: 두 번째 머리글을 구현합니다**

```dart
class GlobalDiffToolbar extends StatelessWidget {
  const GlobalDiffToolbar({
    required this.view,
    required this.presentation,
    required this.activeIndex,
    required this.anchorCount,
    required this.algorithm,
    required this.ignoreWhitespace,
    required this.wrapLines,
    required this.focusMode,
    required this.loadingPatch,
    required this.onPresentationSelected,
    required this.onPrevious,
    required this.onNext,
    required this.onAlgorithmSelected,
    required this.onIgnoreWhitespaceChanged,
    required this.onWrapLinesChanged,
    required this.onFocusModeChanged,
    super.key,
  });
}
```

`view == FullDiffView.history`이면 이전·다음 버튼과 번호에
`enabled: false`를 주되 위젯을 제거하지 않습니다. Hunk가 없으면
`0 / 0`입니다. 이전·다음 tooltip과 Semantics label은 각각
`이전 변경 구간`, `다음 변경 구간`입니다. 테스트와 키보드 연결에
쓰는 키는 `previous-change`, `change-counter`, `next-change`로
고정합니다.

- [ ] **Step 5: 알고리즘과 toggle을 시안대로 구현합니다**

```dart
PopupMenuButton<DiffAlgorithm>(
  key: const Key('diff-algorithm'),
  tooltip: 'diff 알고리즘',
  onSelected: onAlgorithmSelected,
  itemBuilder: (context) => [
    for (final value in DiffAlgorithm.values)
      CheckedPopupMenuItem(
        value: value,
        checked: value == algorithm,
        child: Text(value.label),
      ),
  ],
  child: const SizedBox(
    height: fullDiffControlHeight,
    child: Row(
      children: [
        Text('diff 알고리즘'),
        SizedBox(width: 6),
        Icon(Icons.arrow_drop_down, size: 16),
      ],
    ),
  ),
)
```

`공백 무시`와 `줄바꿈`은 선택 상태를 `Semantics(toggled: value)`로
제공합니다. 집중 모드가 켜지면 아이콘은
`Icons.view_sidebar_outlined`, 이름은 `탐색 패널`입니다.

- [ ] **Step 6: 접근성, 높이, 반지름과 글꼴을 검증합니다**

```dart
final semantics = tester.ensureSemantics();
expect(find.semantics.byLabel('이전 변경 구간'), findsOneWidget);
expect(find.semantics.byLabel('다음 변경 구간'), findsOneWidget);
expect(find.semantics.byLabel('주 화면'), findsOneWidget);
expect(find.semantics.byLabel('Diff 표시 방식'), findsOneWidget);
expect(
  tester.getSemantics(find.semantics.byLabel('Diff')).hasFlag(
    SemanticsFlag.isSelected,
  ),
  isTrue,
);
semantics.dispose();
```

`FullDiffSegmentedControl`은 바깥에
`Semantics(container: true, explicitChildNodes: true, label: groupLabel)`을
두고 각 버튼에 `button`, `selected`, `enabled`를 제공합니다. 아이콘만
있는 화살표에는 위 두 한국어 이름을 사용합니다.

Run:

```bash
dart format lib/full_diff_header.dart test/full_diff_header_test.dart
flutter test test/full_diff_header_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 7: 머리글을 커밋합니다**

```bash
git add lib/full_diff_header.dart test/full_diff_header_test.dart
git commit -m "feat: match the approved full diff headers"
```

### Task 9: 미니맵과 스크롤 동기화

**Files:**

- Create: `lib/full_diff_minimap.dart`
- Create: `test/full_diff_minimap_test.dart`

**Interfaces:**

- Consumes: `DiffDocument`, `DiffAnchor`, 콘텐츠 scroll metrics
- Produces:
  - `FullDiffMinimap`
  - `MinimapGeometry`
  - marker·track click, viewport drag
  - 사용자 스크롤의 앵커 갱신

- [ ] **Step 1: 좌표 계산 실패 테스트를 작성합니다**

```dart
test('maps additions and deletions to source line ratios', () {
  final document = DiffDocument.fromLines(const [
    DiffLine(kind: DiffLineKind.hunk, text: '@@ -10,0 +11 @@ add'),
    DiffLine(kind: DiffLineKind.add, text: 'added', newNumber: 11),
    DiffLine(kind: DiffLineKind.hunk, text: '@@ -81 +82,0 @@ delete'),
    DiffLine(kind: DiffLineKind.delete, text: 'deleted', oldNumber: 81),
  ]);
  final geometry = MinimapGeometry.fromDocument(
    document: document,
    activeAnchor: document.hunks[1].anchor,
    sourceLineCount: 100,
    height: 500,
    deletedFile: false,
  );

  expect(geometry.markers[0].top, closeTo(50.202, 0.001));
  expect(geometry.markers[0].height, 3);
  expect(geometry.markers[0].color, fullDiffAccent);
  expect(geometry.markers[1].color, fullDiffDeletedMark);
});

test('maps the scrollable viewport and chooses the nearest marker', () {
  final viewport = scrollViewport(
    pixels: 200,
    maxScrollExtent: 800,
    viewportDimension: 200,
    height: 500,
  );
  expect(viewport.top, 100);
  expect(viewport.height, 100);

  final document = DiffDocument.fromLines(const [
    DiffLine(kind: DiffLineKind.hunk, text: '@@ -10 +10 @@ one'),
    DiffLine(kind: DiffLineKind.add, text: 'one', newNumber: 10),
    DiffLine(kind: DiffLineKind.hunk, text: '@@ -90 +90 @@ two'),
    DiffLine(kind: DiffLineKind.add, text: 'two', newNumber: 90),
  ]);
  final geometry = MinimapGeometry.fromDocument(
    document: document,
    activeAnchor: document.hunks.first.anchor,
    sourceLineCount: 100,
    height: 500,
    deletedFile: false,
  );
  expect(
    nearestAnchorForY(460, 500, geometry.markers),
    document.hunks.last.anchor,
  );
});

testWidgets('history hides the minimap and external scroll does not echo', (
  tester,
) async {
  final scrollController = ScrollController();
  addTearDown(scrollController.dispose);
  var scrollCallbacks = 0;
  await tester.pumpWidget(
    qaApp(
      SizedBox(
        height: 300,
        child: FullDiffMinimap(
          document: twoHunkDocument,
          activeAnchor: twoHunkDocument.hunks.first.anchor,
          sourceLineCount: 100,
          deletedFile: false,
          view: FullDiffView.history,
          scrollController: scrollController,
          onAnchorSelected: (_) {},
          onScrollFractionChanged: (_) => scrollCallbacks++,
        ),
      ),
    ),
  );
  expect(find.byKey(const Key('full-diff-minimap')), findsNothing);

  await tester.pumpWidget(
    qaApp(
      SizedBox(
        height: 300,
        child: Row(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                children: const [SizedBox(height: 1200)],
              ),
            ),
            FullDiffMinimap(
              document: twoHunkDocument,
              activeAnchor: twoHunkDocument.hunks.first.anchor,
              sourceLineCount: 100,
              deletedFile: false,
              view: FullDiffView.inline,
              scrollController: scrollController,
              onAnchorSelected: (_) {},
              onScrollFractionChanged: (_) => scrollCallbacks++,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  scrollController.jumpTo(120);
  await tester.pump();
  expect(scrollCallbacks, 0);
});
```

- [ ] **Step 2: 미니맵 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_minimap_test.dart`

Expected: FAIL because `FullDiffMinimap` does not exist

- [ ] **Step 3: 미니맵 좌표 모델을 구현합니다**

```dart
double lineToTop(int line, int lineCount, double height) {
  if (lineCount <= 1) return 0;
  return ((line - 1) / (lineCount - 1) * (height - 3))
      .clamp(0, height - 3);
}

MinimapViewport scrollViewport({
  required double pixels,
  required double maxScrollExtent,
  required double viewportDimension,
  required double height,
}) {
  final total = maxScrollExtent + viewportDimension;
  if (total <= 0) return MinimapViewport(top: 0, height: height);
  return MinimapViewport(
    top: pixels / total * height,
    height: math.max(18, viewportDimension / total * height),
  );
}
```

일반 파일은 `newLine`, 삭제 파일은 `oldLine`을 marker 좌표로
사용합니다. 추가나 혼합 Hunk는 `fullDiffAccent`, 삭제 전용 Hunk는
`fullDiffDeletedMark`입니다.

- [ ] **Step 4: painter와 포인터 동작을 구현합니다**

`FullDiffMinimap`은 고정 폭 18px, 왼쪽 1px 테두리의
`CustomPaint`이며 `view == FullDiffView.history`이면
`SizedBox.shrink()`를 반환합니다. `GestureDetector`에는
`full-diff-minimap` 키를 둡니다. 포인터의 y를 소스 비율로 바꾸고 가장
가까운 앵커를 찾습니다.

```dart
class FullDiffMinimap extends StatefulWidget {
  const FullDiffMinimap({
    required this.document,
    required this.activeAnchor,
    required this.sourceLineCount,
    required this.deletedFile,
    required this.view,
    required this.scrollController,
    required this.onAnchorSelected,
    required this.onScrollFractionChanged,
    super.key,
  });

  final DiffDocument document;
  final DiffAnchor? activeAnchor;
  final int sourceLineCount;
  final bool deletedFile;
  final FullDiffView view;
  final ScrollController scrollController;
  final ValueChanged<DiffAnchor> onAnchorSelected;
  final ValueChanged<double> onScrollFractionChanged;

  @override
  State<FullDiffMinimap> createState() => _FullDiffMinimapState();
}

DiffAnchor nearestAnchorForY(
  double y,
  double height,
  List<MinimapMarker> markers,
) => markers.reduce(
  (best, marker) =>
      (marker.center - y).abs() < (best.center - y).abs()
      ? marker
      : best,
).anchor;
```

viewport 안에서 시작한 drag는 스크롤 가능한 보기에서는
`onScrollFractionChanged`, Hunk에서는 `onAnchorSelected`를 호출합니다.
외부 scroll listener가 상태만 갱신할 때는 `_dragging`과
`_programmaticScrollSerial`을 확인해 다시 scroll을 요청하지 않습니다.
marker나 빈 track을 클릭하면 `nearestAnchorForY`의 결과를
`onAnchorSelected`에 한 번 전달합니다.

- [ ] **Step 5: 미니맵 테스트를 통과시킵니다**

Run:

```bash
dart format lib/full_diff_minimap.dart test/full_diff_minimap_test.dart
flutter test test/full_diff_minimap_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: 미니맵을 커밋합니다**

```bash
git add lib/full_diff_minimap.dart test/full_diff_minimap_test.dart
git commit -m "feat: navigate full diff with a minimap"
```

### Task 10: 안전한 외부 편집기와 macOS 대체 열기

**Files:**

- Create: `lib/external_editor.dart`
- Modify: `macos/Runner/MainFlutterWindow.swift:12-56`
- Create: `test/external_editor_test.dart`
- Modify: `macos/RunnerTests/RunnerTests.swift`

**Interfaces:**

- Consumes: 저장소 루트, 작업 트리 경로, 현재 결과 행, `VISUAL`,
  `EDITOR`
- Produces:
  - `parsePosixWords(String)`
  - `ExternalEditorService.open({required String relativePath, int? line})`
  - MethodChannel `yogit/window`의 `openFile`

- [ ] **Step 1: 안전한 단어 해석 실패 테스트를 작성합니다**

```dart
test('parses quoted editor arguments without invoking a shell', () {
  expect(
    parsePosixWords('code --reuse-window "profile name"'),
    ['code', '--reuse-window', 'profile name'],
  );
});

for (final unsafe in [
  'code $(touch bad)',
  'code `touch bad`',
  'code file | cat',
  'code > output',
  'code; other',
  'code && other',
  'code "unterminated',
]) {
  test('rejects unsafe editor setting: $unsafe', () {
    expect(() => parsePosixWords(unsafe), throwsFormatException);
  });
}

test('passes a difficult file path as one final editor argument', () async {
  final root = await Directory.systemTemp.createTemp('yogit_editor_');
  addTearDown(() => root.delete(recursive: true));
  final bin = File('${root.path}/code');
  await bin.writeAsString('#!/bin/sh\nexit 0\n');
  await Process.run('chmod', ['+x', bin.path]);
  const relativePath = '-leading space;name.txt';
  final target = File('${root.path}/$relativePath');
  await target.writeAsString('one\n');
  final launches = <({String executable, List<String> arguments})>[];
  final service = ExternalEditorService(
    repositoryRoot: root.path,
    environment: {'VISUAL': '${bin.path} --reuse-window'},
    processStarter: (executable, arguments) async {
      launches.add((
        executable: executable,
        arguments: List.unmodifiable(arguments),
      ));
    },
  );

  await service.open(relativePath: relativePath, line: 7);

  final canonical = await target.resolveSymbolicLinks();
  expect(launches.single.executable, bin.path);
  expect(launches.single.arguments, [
    '--reuse-window',
    '--goto',
    '$canonical:7',
  ]);
});

test('rejects a symbolic link that escapes the repository', () async {
  final root = await Directory.systemTemp.createTemp('yogit_root_');
  final outside = await Directory.systemTemp.createTemp('yogit_outside_');
  addTearDown(() => root.delete(recursive: true));
  addTearDown(() => outside.delete(recursive: true));
  await File('${outside.path}/secret.txt').writeAsString('secret\n');
  await Link('${root.path}/escape').create(outside.path);
  final service = ExternalEditorService(
    repositoryRoot: root.path,
    environment: const {},
    nativeFileOpener: (_) async {},
  );

  expect(
    service.open(relativePath: 'escape/secret.txt'),
    throwsA(isA<FileSystemException>()),
  );
});
```

- [ ] **Step 2: 외부 편집기 테스트가 실패하는지 확인합니다**

Run: `flutter test test/external_editor_test.dart`

Expected: FAIL because `ExternalEditorService` does not exist

- [ ] **Step 3: 제한된 POSIX 단어 해석기를 구현합니다**

```dart
List<String> parsePosixWords(String source) {
  final words = <String>[];
  final current = StringBuffer();
  String? quote;
  var escaping = false;
  void finish() {
    if (current.isNotEmpty) {
      words.add(current.toString());
      current.clear();
    }
  }
  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    if (escaping) {
      current.write(char);
      escaping = false;
      continue;
    }
    if (char == '\\' && quote != "'") {
      escaping = true;
      continue;
    }
    if (char == "'" || char == '"') {
      if (quote == null) {
        quote = char;
      } else if (quote == char) {
        quote = null;
      } else {
        current.write(char);
      }
      continue;
    }
    if (quote == null && r'`$|><;&'.contains(char)) {
      throw FormatException('Unsafe editor setting');
    }
    if (quote == null && char.trim().isEmpty) {
      finish();
      continue;
    }
    current.write(char);
  }
  if (quote != null || escaping) {
    throw FormatException('Unterminated editor setting');
  }
  finish();
  if (words.isEmpty) throw FormatException('Empty editor setting');
  return List.unmodifiable(words);
}
```

- [ ] **Step 4: 경로 검증과 편집기별 행 인자를 구현합니다**

```dart
typedef EditorProcessStarter =
    Future<void> Function(String executable, List<String> arguments);
typedef NativeFileOpener = Future<void> Function(String absolutePath);

class ExternalEditorService {
  ExternalEditorService({
    required this.repositoryRoot,
    Map<String, String>? environment,
    EditorProcessStarter? processStarter,
    NativeFileOpener? nativeFileOpener,
  }) : environment = environment ?? Platform.environment,
       processStarter =
           processStarter ?? ((executable, arguments) async {
             await Process.start(executable, arguments);
           }),
       nativeFileOpener =
           nativeFileOpener ??
           ((path) => const MethodChannel(
             'yogit/window',
           ).invokeMethod<void>('openFile', {'path': path}));

  final String repositoryRoot;
  final Map<String, String> environment;
  final EditorProcessStarter processStarter;
  final NativeFileOpener nativeFileOpener;

  Future<void> open({
    required String relativePath,
    int? line,
  }) async {
    final root = await Directory(repositoryRoot).resolveSymbolicLinks();
    final file = await File(
      '$root${Platform.pathSeparator}$relativePath',
    ).resolveSymbolicLinks();
    if (!file.startsWith('$root${Platform.pathSeparator}')) {
      throw FileSystemException('File escapes repository root', file);
    }
    if ((await FileStat.stat(file)).type != FileSystemEntityType.file) {
      throw FileSystemException('Editor target is not a regular file', file);
    }
    for (final key in const ['VISUAL', 'EDITOR']) {
      final configured = environment[key];
      if (configured == null || configured.trim().isEmpty) continue;
      final words = parsePosixWords(configured);
      final command = words.first;
      final executable = command.contains(Platform.pathSeparator)
          ? isExecutableFile(command)
                ? command
                : null
          : resolveOptionalExecutable(command, environment: environment);
      if (executable == null) continue;
      final arguments = editorArguments(
        executable,
        words.skip(1).toList(growable: false),
        file,
        line,
      );
      await processStarter(executable, arguments);
      return;
    }
    await nativeFileOpener(file);
  }
}

List<String> editorArguments(
  String executable,
  List<String> configured,
  String path,
  int? line,
) {
  final name = executable.split('/').last.toLowerCase();
  final location = line ?? 1;
  return switch (name) {
    'code' || 'code-insiders' || 'cursor' =>
      [...configured, '--goto', '$path:$location'],
    'subl' || 'sublime_text' =>
      [...configured, '$path:$location'],
    'vim' || 'nvim' || 'mvim' =>
      [...configured, '+$location', '--', path],
    'emacs' || 'emacsclient' =>
      [...configured, '+$location', path],
    _ => [...configured, path],
  };
}
```

`ExternalEditorService.open`은 저장소 루트와 파일을 각각
`resolveSymbolicLinks()`한 뒤 파일 경로가
`'$canonicalRoot${Platform.pathSeparator}'`로 시작하는지 확인합니다.
`VISUAL`, `EDITOR` 순서로 첫 유효 값을 사용하고 `Process.start`에
프로그램과 인자 배열을 직접 넘깁니다. 두 설정이 모두 없으면
MethodChannel의 `openFile`을 `{path: canonicalFile}`로 호출합니다.

- [ ] **Step 5: macOS `NSWorkspace` 대체 열기를 구현합니다**

`MainFlutterWindow.swift`에 다음 작은 경계를 추가합니다.

```swift
protocol WorkspaceOpening {
  @discardableResult
  func open(_ url: URL) -> Bool
}

extension NSWorkspace: WorkspaceOpening {}

class MainFlutterWindow: NSWindow {
  static var workspace: WorkspaceOpening = NSWorkspace.shared

  static func openFile(path: String) -> Bool {
    workspace.open(URL(fileURLWithPath: path))
  }
}
```

channel switch에는 다음 case를 추가합니다.

```swift
case "openFile":
  guard
    let arguments = call.arguments as? [String: Any],
    let path = arguments["path"] as? String
  else {
    result(
      FlutterError(
        code: "invalid_path",
        message: "A file path is required.",
        details: nil
      )
    )
    return
  }
  result(MainFlutterWindow.openFile(path: path))
```

Swift 테스트는 다음 대역으로 전달된 URL을 확인합니다.

```swift
final class RecordingWorkspace: WorkspaceOpening {
  var opened: URL?
  func open(_ url: URL) -> Bool {
    opened = url
    return true
  }
}

func testOpenFileUsesAFileURL() {
  let workspace = RecordingWorkspace()
  MainFlutterWindow.workspace = workspace
  defer { MainFlutterWindow.workspace = NSWorkspace.shared }

  XCTAssertTrue(MainFlutterWindow.openFile(path: "/tmp/a b;name.txt"))
  XCTAssertEqual(workspace.opened?.isFileURL, true)
  XCTAssertEqual(workspace.opened?.path, "/tmp/a b;name.txt")
}
```

- [ ] **Step 6: 편집기와 Swift 테스트를 통과시킵니다**

Run:

```bash
dart format lib/external_editor.dart test/external_editor_test.dart
flutter test test/external_editor_test.dart
xcodebuild test -workspace macos/Runner.xcworkspace \
  -scheme Runner -destination 'platform=macOS'
```

Expected: Flutter test reports `All tests passed!` and Xcode reports
`** TEST SUCCEEDED **`

- [ ] **Step 7: 외부 편집기를 커밋합니다**

```bash
git add lib/external_editor.dart macos/Runner/MainFlutterWindow.swift \
  macos/RunnerTests/RunnerTests.swift test/external_editor_test.dart
git commit -m "feat: open working files in an external editor"
```

### Task 11: 화면 조립, 반응형 열, 키보드와 스크롤

**Files:**

- Replace: `lib/diff_screen.dart`
- Modify: `lib/timeline.dart:2963-2981`
- Create: `test/full_diff_workspace_test.dart`
- Modify: `test/app_test.dart`

**Interfaces:**

- Consumes: Tasks 3–10의 controller와 모든 leaf widget
- Produces:
  - 승인된 `FullDiffWorkspace`
  - 651·650·481·480px 경계
  - 모든 화면 전환과 앵커 이동
  - 공통 페이지 스크롤과 기존 키보드 동작

- [ ] **Step 1: 전체 화면 전환 실패 테스트를 작성합니다**

```dart
Future<({
  FullDiffSessionController controller,
  FakeFullDiffRepository repository,
})> workspaceFixture() async {
  final repository = FakeFullDiffRepository()
    ..files = (_, _) async => const [fileA]
    ..diff = (_, _, _, _, _) async => twoHunkLines
    ..content = (_, _, _) async => resultFile.bytes
    ..blame = (_, _, _, _) async => [
      for (var index = 0; index < resultFile.lines.length; index++)
        GitBlameLine(
          lineNumber: index + 1,
          sha: commitA.sha,
          author: fixtureIdentity.name,
          uncommitted: false,
        ),
    ]
    ..history = (_, _) async => [
      for (final entry in historyEntries)
        GitFileHistoryRecord(
          commit: entry.commit,
          path: entry.path,
          oldPath: entry.oldPath,
          status: entry.status,
        ),
    ];
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
    initialView: FullDiffInitialView.hunk,
  );
  await controller.initialize();
  return (controller: controller, repository: repository);
}

Future<void> pumpWorkspace(
  WidgetTester tester, {
  required FullDiffSessionController controller,
  required Size size,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      home: DiffScreen(
        repository: controller.repository,
        commits: controller.state.nearbyCommits,
        initialIndex: 0,
        initialView: FullDiffInitialView.hunk,
        controller: controller,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

testWidgets('keeps presentation and anchor while switching main views', (
  tester,
) async {
  final fixture = await workspaceFixture();
  final controller = fixture.controller
    ..setView(FullDiffView.diff)
    ..setPresentation(DiffPresentation.hunk)
    ..selectAnchor(twoHunkDocument.hunks[1].anchor);
  await pumpWorkspace(tester, controller: controller, size: const Size(1070, 842));

  await tester.tap(find.text('Split'));
  await tester.tap(find.text('File'));
  await tester.tap(find.text('Blame'));
  await tester.tap(find.text('History'));
  await tester.tap(find.text('Diff'));

  expect(controller.state.presentation, DiffPresentation.split);
  expect(controller.state.activeAnchor?.hunkIndex, 1);
  expect(fixture.repository.diffRequests, hasLength(1));
});

test('navigation boundaries and scroll synchronization do not bounce', () async {
  final fixture = await workspaceFixture();
  final controller = fixture.controller;
  controller.selectAnchor(twoHunkDocument.hunks.last.anchor);
  final lastSerial = controller.state.navigationSerial;
  controller.stepAnchor(1);
  expect(controller.state.activeAnchor, twoHunkDocument.hunks.last.anchor);
  expect(controller.state.navigationSerial, lastSerial);

  controller.syncAnchorFromScroll(twoHunkDocument.hunks.first.anchor);
  expect(controller.state.activeAnchor, twoHunkDocument.hunks.first.anchor);
  expect(controller.state.navigationSerial, lastSerial);
  controller.stepAnchor(1);
  expect(controller.state.activeAnchor, twoHunkDocument.hunks.last.anchor);
  expect(controller.state.navigationSerial, lastSerial + 1);
});

test('parent 2 reaches files patch and content without resetting views', () async {
  final merge = GitCommit(
    sha: 'merge-sha',
    shortSha: 'merge12',
    parents: const ['parent-1', 'parent-2'],
    author: fixtureIdentity,
    authorTimestamp: 1720573300,
    committer: fixtureIdentity,
    committerTimestamp: 1720573300,
    refs: const [],
    subject: 'merge',
  );
  final repository = FakeFullDiffRepository()
    ..files = (_, _) async => const [fileA]
    ..diff = (_, _, _, _, _) async => twoHunkLines
    ..content = (_, _, _) async =>
        Uint8List.fromList(utf8.encode('current\n'));
  final controller = FullDiffSessionController(
    repository: repository,
    commits: [merge],
    initialIndex: 0,
    initialView: FullDiffInitialView.hunk,
  );
  await controller.initialize();
  controller
    ..setView(FullDiffView.file)
    ..setPresentation(DiffPresentation.split);

  await controller.selectParent('parent-2');

  expect(repository.fileRequests.last.parent, 'parent-2');
  expect(repository.diffRequests.last.parent, 'parent-2');
  expect(repository.contentRequests.last.parent, 'parent-2');
  expect(controller.state.view, FullDiffView.file);
  expect(controller.state.presentation, DiffPresentation.split);
});
```

- [ ] **Step 2: 반응형과 집중 모드 실패 테스트를 작성합니다**

```dart
for (final scenario in [
  (width: 651.0, commits: true, files: true, oldSplit: true),
  (width: 650.0, commits: false, files: true, oldSplit: true),
  (width: 481.0, commits: false, files: true, oldSplit: true),
  (width: 480.0, commits: false, files: false, oldSplit: false),
]) {
  testWidgets('responsive width ${scenario.width}', (tester) async {
    final fixture = await workspaceFixture();
    fixture.controller.setPresentation(DiffPresentation.split);
    await pumpWorkspace(
      tester,
      controller: fixture.controller,
      size: Size(scenario.width, 549),
    );
    expect(
      find.byKey(const Key('nearby-commits-pane')),
      scenario.commits ? findsOneWidget : findsNothing,
    );
    expect(
      find.byKey(const Key('commit-files-pane')),
      scenario.files ? findsOneWidget : findsNothing,
    );
    expect(
      find.byKey(const Key('split-old-pane')),
      scenario.oldSplit ? findsOneWidget : findsNothing,
    );
  });
}

testWidgets('focus mode restores panes widths and selection', (tester) async {
  final fixture = await workspaceFixture();
  await pumpWorkspace(
    tester,
    controller: fixture.controller,
    size: const Size(1070, 842),
  );
  final commitWidth = tester.getSize(
    find.byKey(const Key('nearby-commits-pane')),
  ).width;
  final fileWidth = tester.getSize(
    find.byKey(const Key('commit-files-pane')),
  ).width;
  final commit = fixture.controller.state.selectedCommit;
  final file = fixture.controller.state.selectedFile;

  await tester.tap(find.text('집중 모드'));
  await tester.pump();
  expect(find.byKey(const Key('nearby-commits-pane')), findsNothing);
  expect(find.byKey(const Key('commit-files-pane')), findsNothing);
  expect(find.text('탐색 패널'), findsOneWidget);

  await tester.tap(find.text('탐색 패널'));
  await tester.pump();
  expect(
    tester.getSize(find.byKey(const Key('nearby-commits-pane'))).width,
    commitWidth,
  );
  expect(
    tester.getSize(find.byKey(const Key('commit-files-pane'))).width,
    fileWidth,
  );
  expect(fixture.controller.state.selectedCommit, same(commit));
  expect(fixture.controller.state.selectedFile, same(file));
});

testWidgets('selected rows and source state are not color-only', (tester) async {
  final fixture = await workspaceFixture();
  await pumpWorkspace(
    tester,
    controller: fixture.controller,
    size: const Size(1070, 842),
  );
  final semantics = tester.ensureSemantics();
  expect(
    tester.getSemantics(
      find.byKey(Key('selected-file-${fileA.path}')),
    ).hasFlag(SemanticsFlag.isSelected),
    isTrue,
  );
  semantics.dispose();
  expect(find.text('+'), findsWidgets);
  expect(find.text('−'), findsWidgets);
  expect(find.byKey(const Key('code-row-current-marker')), findsOneWidget);
});
```

- [ ] **Step 3: 키보드 충돌과 페이지 스크롤 실패 테스트를 작성합니다**

```dart
Future<void> sendChord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool alt = false,
  bool shift = false,
}) async {
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

testWidgets('navigation and focus shortcuts update only their target', (
  tester,
) async {
  const fileB = GitFileChange(
    path: 'src/window.pas',
    status: 'M',
    additions: 1,
    deletions: 1,
  );
  final repository = FakeFullDiffRepository()
    ..files = (_, _) async => const [fileA, fileB]
    ..diff = (_, _, _, _, _) async => twoHunkLines
    ..content = (_, _, _) async => resultFile.bytes;
  final controller = FullDiffSessionController(
    repository: repository,
    commits: [commitA, historyEntries[1].commit],
    initialIndex: 0,
    initialView: FullDiffInitialView.hunk,
  );
  await controller.initialize();
  await pumpWorkspace(
    tester,
    controller: controller,
    size: const Size(1070, 842),
  );

  await sendChord(tester, LogicalKeyboardKey.arrowDown);
  expect(controller.state.selectedFile, fileB);
  await sendChord(tester, LogicalKeyboardKey.arrowDown, meta: true);
  expect(controller.state.selectedCommit, historyEntries[1].commit);
  await sendChord(tester, LogicalKeyboardKey.arrowDown, alt: true);
  expect(controller.state.activeAnchor?.hunkIndex, 1);
  await sendChord(
    tester,
    LogicalKeyboardKey.keyF,
    meta: true,
    shift: true,
  );
  expect(controller.state.focusMode, isTrue);
  await sendChord(tester, LogicalKeyboardKey.escape);
  expect(controller.state.focusMode, isFalse);
});

testWidgets('page scroll moves 48px and an open menu consumes its keys', (
  tester,
) async {
  final fixture = await workspaceFixture();
  fixture.controller.setView(FullDiffView.file);
  await pumpWorkspace(
    tester,
    controller: fixture.controller,
    size: const Size(1070, 549),
  );
  final scrollable = find.descendant(
    of: find.byKey(const Key('content-scrollable')),
    matching: find.byType(Scrollable),
  ).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  final before = position.pixels;
  await sendChord(
    tester,
    LogicalKeyboardKey.arrowDown,
    meta: true,
    shift: true,
  );
  await tester.pump(const Duration(milliseconds: 100));
  expect(position.pixels, closeTo(before + 48, 0.5));

  await tester.tap(find.byKey(const Key('diff-algorithm')));
  await tester.pumpAndSettle();
  final menuPosition = position.pixels;
  await sendChord(
    tester,
    LogicalKeyboardKey.arrowDown,
    meta: true,
    shift: true,
  );
  expect(position.pixels, menuPosition);
});
```

- [ ] **Step 4: 조립 테스트가 실패하는지 확인합니다**

Run: `flutter test test/full_diff_workspace_test.dart`

Expected: FAIL because `DiffScreen` still renders the phase-one Hunk-only layout

- [ ] **Step 5: 두 머리글과 반응형 본문을 조립합니다**

`DiffScreen.build`의 큰 구조를 다음과 같이 고정합니다.

```dart
return Scaffold(
  backgroundColor: fullDiffCanvas,
  body: Padding(
    padding: const EdgeInsets.all(fullDiffOuterPadding),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(fullDiffOuterRadius),
      child: ColoredBox(
        color: fullDiffHeader,
        child: Column(
          children: [
            GlobalFileBar(
              file: state.selectedFile,
              path: state.selectedFile?.path,
              view: state.view,
              encodingLabel: state.encodingLabel,
              canOpenEditor: _canOpenEditor(state),
              editorError: _editorError,
              onOpenEditor: _openEditor,
              onViewSelected: _controller.setView,
            ),
            GlobalDiffToolbar(
              view: state.view,
              presentation: state.presentation,
              activeIndex: state.activeAnchor?.hunkIndex ?? 0,
              anchorCount: state.patch.data?.hunks.length ?? 0,
              algorithm: state.requestedAlgorithm,
              ignoreWhitespace: state.requestedIgnoreWhitespace,
              wrapLines: state.wrapLines,
              focusMode: state.focusMode,
              loadingPatch: state.patch.loading,
              onPresentationSelected: _controller.setPresentation,
              onPrevious: () => _controller.stepAnchor(-1),
              onNext: () => _controller.stepAnchor(1),
              onAlgorithmSelected: _controller.selectAlgorithm,
              onIgnoreWhitespaceChanged: _controller.setIgnoreWhitespace,
              onWrapLinesChanged: _controller.setWrapLines,
              onFocusModeChanged: _controller.setFocusMode,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _ResponsiveDiffBody(
                  showCommits:
                      !state.focusMode && constraints.maxWidth > 650,
                  showFiles:
                      !state.focusMode && constraints.maxWidth > 480,
                  narrow: constraints.maxWidth <= 650,
                  nearbyCommits: _nearbyCommits(state),
                  commitFiles: _commitFiles(state),
                  content: _content(state, constraints.maxWidth),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
```

`_ResponsiveDiffBody`는 다음처럼 열을 조합합니다.

```dart
class _ResponsiveDiffBody extends StatelessWidget {
  const _ResponsiveDiffBody({
    required this.showCommits,
    required this.showFiles,
    required this.narrow,
    required this.nearbyCommits,
    required this.commitFiles,
    required this.content,
  });

  final bool showCommits;
  final bool showFiles;
  final bool narrow;
  final Widget nearbyCommits;
  final Widget commitFiles;
  final Widget content;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (showCommits)
        Flexible(
          flex: 82,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 126),
            child: KeyedSubtree(
              key: const Key('nearby-commits-pane'),
              child: nearbyCommits,
            ),
          ),
        ),
      if (showFiles)
        Flexible(
          flex: narrow ? 80 : 100,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: narrow ? 138 : 158),
            child: KeyedSubtree(
              key: const Key('commit-files-pane'),
              child: commitFiles,
            ),
          ),
        ),
      Expanded(flex: narrow ? 280 : 420, child: content),
    ],
  );
}
```

세 열의 최소 너비와 flex는 650px 초과에서 `126, 158, 0`과
`0.82 : 1 : 4.2`, 650px 이하에서 `138, 0`과 `0.8 : 2.8`을
사용합니다. phase-one의 520px 콘텐츠 최소값과 resizer 계산은
제거합니다. 저장된 열 너비는 650px 초과의 세 열 배치에만 적용합니다.

- [ ] **Step 6: 탐색 열을 시안의 평면 행으로 바꿉니다**

주변 커밋 행은 제목과 SHA 두 줄, 변경 파일 행은 상태 한 글자와 경로
칩, 추가·삭제 수를 표시합니다. 선택 행은 열 너비 전체에
`fullDiffSelection`을 칠하고 모서리를 둥글게 만들지 않습니다.
상태 글자에는 별도 배경을 넣지 않습니다.

선택 커밋에 부모가 둘 이상이면 커밋 제목과 변경 파일 제목 사이에
현재 phase-one과 같은 parent chooser를 둡니다. 메뉴 항목은
`Parent 1 · <shortSha>`, `Parent 2 · <shortSha>` 형식이고
`onChanged`는 `_controller.selectParent(parent)`를 호출합니다.

```dart
Semantics(
  selected: selected,
  button: true,
  child: Container(
  key: selected ? Key('selected-file-${file.path}') : null,
  color: selected ? fullDiffSelection : Colors.transparent,
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
  child: Row(
    children: [
      SizedBox(width: 24, child: Text(file.status.characters.first)),
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? fullDiffSelectedChip : fullDiffChip,
            borderRadius: BorderRadius.circular(fullDiffChipRadius),
          ),
          child: Text(
            file.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: technicalFontFamily,
              fontFamilyFallback: technicalFontFallback,
              fontSize: 14,
            ),
          ),
        ),
      ),
      Text('+${file.additions ?? '—'} −${file.deletions ?? '—'}'),
    ],
  ),
  ),
)
```

- [ ] **Step 7: 상태별 콘텐츠와 미니맵을 조립합니다**

```dart
Widget contentFor(FullDiffSessionState state) => switch (state.view) {
  FullDiffView.file => state.file.data case final file?
      ? FullFileView(
          document: file,
          path: file.path,
          activeAnchor: state.activeAnchor,
          wrapLines: state.wrapLines,
          highlighter: _highlighter,
        )
      : _resourceStatus(state.file, '파일을 읽는 중입니다'),
  FullDiffView.diff => state.patch.data case final patch?
      ? switch (state.presentation) {
          DiffPresentation.hunk => HunkPresentationView(
            document: patch,
            activeAnchor: state.activeAnchor,
            path: state.selectedFile!.path,
            wrapLines: state.wrapLines,
            highlighter: _highlighter,
          ),
          DiffPresentation.inline => InlinePresentationView(
            document: patch,
            activeAnchor: state.activeAnchor,
            path: state.selectedFile!.path,
            wrapLines: state.wrapLines,
            highlighter: _highlighter,
          ),
          DiffPresentation.split => SplitPresentationView(
            document: patch,
            activeAnchor: state.activeAnchor,
            oldPath:
                state.selectedFile!.oldPath ?? state.selectedFile!.path,
            newPath: state.selectedFile!.path,
            wrapLines: state.wrapLines,
            showOldSide: MediaQuery.sizeOf(context).width > 480,
            highlighter: _highlighter,
          ),
        }
      : _resourceStatus(state.patch, 'Diff를 읽는 중입니다'),
  FullDiffView.blame => state.blame.data case final blame?
      ? FullBlameView(
          document: blame,
          activeAnchor: state.activeAnchor,
          wrapLines: state.wrapLines,
          highlighter: _highlighter,
        )
      : _resourceStatus(state.blame, 'Blame을 읽는 중입니다'),
  FullDiffView.history => state.history.data case final history?
      ? FullHistoryView(
          entries: history,
          onSelected: _controller.selectHistoryEntry,
        )
      : _resourceStatus(state.history, 'History를 읽는 중입니다'),
};

Widget _resourceStatus<T>(AsyncResource<T> resource, String loadingLabel) =>
    Center(
      child: Text(
        resource.error?.toString() ??
            (resource.loading ? loadingLabel : '표시할 데이터가 없습니다'),
        style: const TextStyle(color: fullDiffMuted, fontSize: 14),
      ),
    );
```

History를 제외한 콘텐츠 오른쪽에는 다음 미니맵을 둡니다.

```dart
SizedBox(
  width: fullDiffMinimapWidth,
  child: FullDiffMinimap(
    document: state.patch.data ?? DiffDocument.empty,
    activeAnchor: state.activeAnchor,
    sourceLineCount:
        state.file.data?.lines.length ??
        state.patch.data?.sourceLineCount ??
        0,
    deletedFile: state.selectedFile?.status.startsWith('D') ?? false,
    view: state.view,
    scrollController: _contentScroll,
    onAnchorSelected: _controller.selectAnchor,
    onScrollFractionChanged: _scrollContentToFraction,
  ),
)
```

patch 로딩 중 기존 patch가 있으면 그대로 보이고 toolbar에만 진행
상태를 표시합니다.

`contentFor(state)`는 다음 wrapper 안에 넣습니다. 각 소스 `ListView`는
`primary: true`로 만들어 미니맵과 페이지 스크롤 명령이 같은
`ScrollPosition`을 사용하게 합니다.

```dart
PrimaryScrollController(
  controller: _contentScroll,
  child: KeyedSubtree(
    key: const Key('content-scrollable'),
    child: contentFor(state),
  ),
)
```

- [ ] **Step 8: 앵커 key와 스크롤 동기화를 연결합니다**

`Map<String, GlobalKey>`는 document가 바뀔 때 같은 anchor id를
재사용합니다. controller의 `navigationSerial`이 바뀌었을 때만
`Scrollable.ensureVisible(duration: 100ms, alignment: 0.1)`을
호출합니다. scroll listener는 viewport 중앙과 각 anchor render box의
거리를 비교해 `syncAnchorFromScroll`을 호출하며 `ensureVisible`을
부르지 않습니다.

- [ ] **Step 9: 키보드와 편집기 버튼을 연결합니다**

기존 `Shortcuts`와 `Actions`를 유지하되 toolbar와 History의
`Focus` 하위에 둡니다. `PageScrollIntent`는 현재 보이는 콘텐츠의
scroll controller에 적용합니다. 외부 편집기 버튼은 선택한 커밋이
작업 트리이고 파일이 삭제되지 않았으며 검증된 파일이 있을 때만
활성화합니다.

- [ ] **Step 10: 조립 테스트와 기존 Full Diff 통합 테스트를 통과시킵니다**

Run:

```bash
dart format lib/diff_screen.dart lib/timeline.dart \
  test/full_diff_workspace_test.dart test/app_test.dart
flutter test test/full_diff_workspace_test.dart
flutter test test/app_test.dart --name 'full diff|Full Diff|diff screen'
```

Expected: both commands report `All tests passed!`

- [ ] **Step 11: 화면 조립을 커밋합니다**

```bash
git add lib/diff_screen.dart lib/timeline.dart \
  test/full_diff_workspace_test.dart test/app_test.dart
git commit -m "feat: assemble the approved full diff workspace"
```

### Task 12: 기능별 이미지, 성능·용량 기준과 최종 검증

**Files:**

- Create: `test/support/full_diff_qa_harness.dart`
- Create: `test/full_diff_visual_test.dart`
- Create: `test/full_diff_syntax_benchmark_test.dart`
- Create: `tool/full_diff_visual_diff.dart`
- Create: `docs/superpowers/verification/full-diff-qa/README.md`
- Create: `docs/superpowers/verification/full-diff-qa/actual/*.png`
- Create: `docs/superpowers/verification/full-diff-qa/diff/*.png`

**Interfaces:**

- Consumes: 승인된 13개 기준 이미지와 완성된 `DiffScreen`
- Produces: 같은 크기의 구현 이미지, 차이 이미지, 구문 강조 측정,
  DRL 수동 검증 기록

- [ ] **Step 1: 웹 시안과 같은 고정 fixture를 만듭니다**

`test/support/full_diff_qa_harness.dart`에 다음 helper와 widget을
제공합니다.

```dart
Future<FullDiffSessionController> qaControllerFor({
  FullDiffView view = FullDiffView.diff,
  DiffPresentation presentation = DiffPresentation.hunk,
  bool focusMode = false,
  bool ignoreWhitespace = false,
  bool wrapLines = false,
  int activeHunkIndex = 1,
  DiffAlgorithm algorithm = DiffAlgorithm.gitSetting,
}) async {
  final repository = FakeFullDiffRepository()
    ..files = (_, _) async => qaFiles
    ..diff = (_, _, _, selectedAlgorithm, whitespace) async =>
        whitespace ? qaWhitespacePatchLines : qaPatchLines
    ..content = (_, _, _) async => qaFileBytes
    ..blame = (_, _, _, _) async => qaBlameLines
    ..history = (_, _) async => qaHistoryRecords;
  final controller = FullDiffSessionController(
    repository: repository,
    commits: qaCommits,
    initialIndex: 1,
    initialView: FullDiffInitialView.hunk,
  );
  await controller.initialize();
  controller
    ..setView(view)
    ..setPresentation(presentation)
    ..setFocusMode(focusMode)
    ..setWrapLines(wrapLines);
  if (ignoreWhitespace) await controller.setIgnoreWhitespace(true);
  if (algorithm != DiffAlgorithm.gitSetting) {
    await controller.selectAlgorithm(algorithm);
  }
  final document = controller.state.patch.data;
  if (document != null && document.hunks.isNotEmpty) {
    controller.selectAnchor(
      document.hunks[
        activeHunkIndex.clamp(0, document.hunks.length - 1)
      ].anchor,
    );
  }
  return controller;
}

class FullDiffQaHarness extends StatelessWidget {
  const FullDiffQaHarness({
    required this.controller,
    this.detailOnly = false,
    super.key,
  });

  final FullDiffSessionController controller;
  final bool detailOnly;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const Key('full-diff-qa-root'),
    child: detailOnly
        ? FullDiffQaDetail(controller: controller)
        : DiffScreen(
            repository: controller.repository,
            commits: controller.state.nearbyCommits,
            initialIndex: 0,
            initialView: FullDiffInitialView.hunk,
            controller: controller,
          ),
  );
}

class FullDiffQaDetail extends StatelessWidget {
  const FullDiffQaDetail({required this.controller, super.key});
  final FullDiffSessionController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.state;
      final patch = state.patch.data ?? DiffDocument.empty;
      return ColoredBox(
        color: fullDiffCanvas,
        child: Column(
          children: [
            GlobalDiffToolbar(
              view: state.view,
              presentation: state.presentation,
              activeIndex: state.activeAnchor?.hunkIndex ?? 0,
              anchorCount: patch.hunks.length,
              algorithm: state.requestedAlgorithm,
              ignoreWhitespace: state.requestedIgnoreWhitespace,
              wrapLines: state.wrapLines,
              focusMode: state.focusMode,
              loadingPatch: state.patch.loading,
              onPresentationSelected: controller.setPresentation,
              onPrevious: () => controller.stepAnchor(-1),
              onNext: () => controller.stepAnchor(1),
              onAlgorithmSelected: controller.selectAlgorithm,
              onIgnoreWhitespaceChanged: controller.setIgnoreWhitespace,
              onWrapLinesChanged: controller.setWrapLines,
              onFocusModeChanged: controller.setFocusMode,
            ),
            Expanded(
              child: HunkPresentationView(
                document: patch,
                activeAnchor: state.activeAnchor,
                path: state.selectedFile?.path ?? 'src/drlua.pas',
                wrapLines: state.wrapLines,
                highlighter: const NoopSyntaxHighlighter(),
              ),
            ),
          ],
        ),
      );
    },
  );
}
```

fixture의 경로는 `src/drlua.pas`, 선택 커밋은 `40aff6d`,
제목은 `Make Retina windows pixel-aware`, 작성자는 `Suwon Chae`,
상태는 `M · +12 −4`, Hunk 수는 7개로 고정합니다. 파일 목록과 소스
문자열은 `full-diff-redesign-direct.html`에서 보이는 7개 Hunk를
`qaPatchLines`, 공백 변경 행을 뺀 결과를 `qaWhitespacePatchLines`,
전체 결과 파일을 `qaFileBytes`, 각 결과 행의 blame을
`qaBlameLines`, 보이는 History 행을 `qaHistoryRecords`에 순서대로
넣습니다.

- [ ] **Step 2: 13개 캡처 테스트를 작성합니다**

```dart
Future<void> capture(
  WidgetTester tester, {
  required String name,
  required Size size,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
  await expectLater(
    find.byKey(const Key('full-diff-qa-root')),
    matchesGoldenFile(
      '../docs/superpowers/verification/full-diff-qa/actual/$name.png',
    ),
  );
}
```

테스트 이름, 크기와 상태는 다음 목록을 그대로 사용합니다.

```dart
typedef QaCase = ({
  String name,
  Size size,
  FullDiffView view,
  DiffPresentation presentation,
  bool focus,
  bool whitespace,
  bool wrap,
  int hunk,
  DiffAlgorithm algorithm,
  bool detailOnly,
});

const qaCases = <QaCase>[
  (name: '00-overview-hunk', size: Size(782, 842), view: FullDiffView.diff,
   presentation: DiffPresentation.hunk, focus: false, whitespace: false,
   wrap: false, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
  (name: '01-diff-inline', size: Size(782, 842), view: FullDiffView.diff,
   presentation: DiffPresentation.inline, focus: false, whitespace: false,
   wrap: false, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
  (name: '02-diff-split', size: Size(1070, 842), view: FullDiffView.diff,
   presentation: DiffPresentation.split, focus: false, whitespace: false,
   wrap: false, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
  (name: '03-file-view', size: Size(1070, 842), view: FullDiffView.file,
   presentation: DiffPresentation.hunk, focus: false, whitespace: false,
   wrap: false, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
  (name: '04-blame-view', size: Size(1070, 842), view: FullDiffView.blame,
   presentation: DiffPresentation.hunk, focus: false, whitespace: false,
   wrap: false, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
  (name: '05-history-view', size: Size(1070, 842), view: FullDiffView.history,
   presentation: DiffPresentation.hunk, focus: false, whitespace: false,
   wrap: false, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
  (name: '06-focus-mode', size: Size(1070, 842), view: FullDiffView.diff,
   presentation: DiffPresentation.hunk, focus: true, whitespace: false,
   wrap: false, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
  (name: '07-ignore-whitespace', size: Size(1070, 842), view: FullDiffView.diff,
   presentation: DiffPresentation.hunk, focus: false, whitespace: true,
   wrap: false, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
  (name: '08-wrap-lines', size: Size(1070, 842), view: FullDiffView.diff,
   presentation: DiffPresentation.hunk, focus: false, whitespace: false,
   wrap: true, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
  (name: '09-next-change', size: Size(1280, 720), view: FullDiffView.diff,
   presentation: DiffPresentation.hunk, focus: false, whitespace: false,
   wrap: false, hunk: 2, algorithm: DiffAlgorithm.gitSetting, detailOnly: true),
  (name: '10-algorithm-histogram', size: Size(1280, 720),
   view: FullDiffView.diff, presentation: DiffPresentation.hunk, focus: false,
   whitespace: false, wrap: false, hunk: 1,
   algorithm: DiffAlgorithm.histogram, detailOnly: true),
  (name: '11-responsive-650', size: Size(650, 549), view: FullDiffView.diff,
   presentation: DiffPresentation.hunk, focus: false, whitespace: false,
   wrap: false, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
  (name: '12-responsive-480', size: Size(480, 549), view: FullDiffView.diff,
   presentation: DiffPresentation.hunk, focus: false, whitespace: false,
   wrap: false, hunk: 1, algorithm: DiffAlgorithm.gitSetting, detailOnly: false),
];

for (final scenario in qaCases) {
  testWidgets('capture ${scenario.name}', (tester) async {
    final controller = await qaControllerFor(
      view: scenario.view,
      presentation: scenario.presentation,
      focusMode: scenario.focus,
      ignoreWhitespace: scenario.whitespace,
      wrapLines: scenario.wrap,
      activeHunkIndex: scenario.hunk,
      algorithm: scenario.algorithm,
    );
    await capture(
      tester,
      name: scenario.name,
      size: scenario.size,
      child: FullDiffQaHarness(
        controller: controller,
        detailOnly: scenario.detailOnly,
      ),
    );
  });
}
```

`09`와 `10`은 기준과 같이 `FullDiffQaDetail`의 두 번째 머리글과
콘텐츠만 캡처합니다.

- [ ] **Step 3: 구현 이미지를 생성합니다**

Run:

```bash
flutter test --update-goldens test/full_diff_visual_test.dart
```

Expected: 13 PNG files are written under
`docs/superpowers/verification/full-diff-qa/actual/`

- [ ] **Step 4: 기준·구현·차이 이미지를 만드는 도구를 구현합니다**

`tool/full_diff_visual_diff.dart`는 reference와 actual PNG를 읽어 RGB
절대 차이를 `diff` 이미지에 쓰고, 두 이미지를 좌우로 붙인
`side-by-side` 이미지도 만듭니다.

```dart
import 'dart:io';
import 'package:image/image.dart' as img;

const names = [
  '00-overview-hunk',
  '01-diff-inline',
  '02-diff-split',
  '03-file-view',
  '04-blame-view',
  '05-history-view',
  '06-focus-mode',
  '07-ignore-whitespace',
  '08-wrap-lines',
  '09-next-change',
  '10-algorithm-histogram',
  '11-responsive-650',
  '12-responsive-480',
];

void main() {
  final referenceRoot = Directory(
    'docs/superpowers/specs/assets/full-diff-qa',
  );
  final actualRoot = Directory(
    'docs/superpowers/verification/full-diff-qa/actual',
  );
  final outputRoot = Directory(
    'docs/superpowers/verification/full-diff-qa/diff',
  )..createSync(recursive: true);
  for (final name in names) {
    final reference = img.decodePng(
      File('${referenceRoot.path}/$name.png').readAsBytesSync(),
    )!;
    final actual = img.decodePng(
      File('${actualRoot.path}/$name.png').readAsBytesSync(),
    )!;
    if (reference.width != actual.width ||
        reference.height != actual.height) {
      throw StateError('$name size mismatch');
    }
    final difference = img.Image(
      width: reference.width,
      height: reference.height,
    );
    for (var y = 0; y < reference.height; y++) {
      for (var x = 0; x < reference.width; x++) {
        final a = reference.getPixel(x, y);
        final b = actual.getPixel(x, y);
        difference.setPixelRgba(
          x,
          y,
          (a.r - b.r).abs().toInt(),
          (a.g - b.g).abs().toInt(),
          (a.b - b.b).abs().toInt(),
          255,
        );
      }
    }
    final sideBySide = img.Image(
      width: reference.width * 2,
      height: reference.height,
    );
    img.compositeImage(sideBySide, reference);
    img.compositeImage(sideBySide, actual, dstX: reference.width);
    File('${outputRoot.path}/$name.png').writeAsBytesSync(
      img.encodePng(difference),
    );
    File('${outputRoot.path}/$name-side-by-side.png').writeAsBytesSync(
      img.encodePng(sideBySide),
    );
  }
}
```

Run: `dart run tool/full_diff_visual_diff.dart`

Expected: 13 difference images and 13 side-by-side images are created

- [ ] **Step 5: 구문 확장 묶음의 압축 크기와 속도를 측정합니다**

기본 문법과 확장 문법 빌드를 각각 만들고 app bundle을 zip으로
압축합니다.

```bash
flutter build macos --release \
  --dart-define=YOGIT_EXTENDED_SYNTAX=false
ditto -c -k --keepParent build/macos/Build/Products/Release/yogit.app \
  /tmp/yogit-base.zip
flutter build macos --release \
  --dart-define=YOGIT_EXTENDED_SYNTAX=true
ditto -c -k --keepParent build/macos/Build/Products/Release/yogit.app \
  /tmp/yogit-extended.zip
stat -f '%z %N' /tmp/yogit-base.zip /tmp/yogit-extended.zip
```

`test/full_diff_syntax_benchmark_test.dart`에는 다음 측정을 둡니다.

```dart
const drlFirstHunkLines = <String>[
  'procedure TDRLLua.ReadWad;',
  'var iProgBase : DWord;',
  '    iModule   : TDRLModule;',
  '    iData     : TVDataFile;',
  'function CheckID( const iID : Ansistring ) : Boolean;',
  'begin',
  "  Exit( ( iID <> 'core' ) and ( iID <> 'drl' ) );",
  'end;',
  'procedure SetupBase;',
  'begin',
  "  Log( LOGINFO, 'BASE MODULE VERSION: '+VersionModule );",
  'end;',
];

test('DRL first hunk highlighting stays within the release gate', () {
  final highlighter = HighlightJsSyntaxHighlighter();
  final samples = <int>[];
  for (var run = 0; run < 30; run++) {
    final watch = Stopwatch()..start();
    for (final line in drlFirstHunkLines) {
      highlighter.highlightLine('src/drlua.pas', line);
    }
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }
  final sorted = [...samples]..sort();
  final p95 = sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
  print('syntax-first-us=${samples.first} syntax-p95-us=$p95');
  expect(samples.first, lessThanOrEqualTo(50000));
});
```

Run:

```bash
flutter test test/full_diff_syntax_benchmark_test.dart --reporter expanded
```

확장 zip이 기본 zip보다
1,048,576 bytes 이하로 크고 첫 Hunk가 50ms 안에 끝나면
`extendedSyntaxEnabled`의 기본값을 `true`로 유지합니다. 한 기준이라도
넘으면 `latex`, `matlab`, `fortran`, `x86asm`, `armasm`, `vhdl`,
`verilog`, `scheme`, `lisp`, `clojure`, `fsharp`, `ocaml`, `haskell`,
`erlang`, `elixir`, `scala`, `julia`, `r`, `perl`, `qml` 순서로
등록과 import를 빼고 두 기준을 다시 측정합니다. 최종 포함 목록과
두 zip 크기, 첫 실행, p95를 README에 숫자로 기록합니다.

- [ ] **Step 6: 이미지별 수동 판정을 기록합니다**

README의 표는 다음 열을 사용합니다.

```markdown
| 상태 | 기준 | 구현 | 차이 | 메뉴·순서 | 색·테두리 | 크기·배치 | 판정 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 00 Hunk | reference/00-overview-hunk.png | actual/00-overview-hunk.png | diff/00-overview-hunk.png | 일치 | 일치 | 일치 | 통과 |
```

13개 행을 모두 채웁니다. 동적 데이터 문자열은 제외하되 위치, 글꼴,
말줄임과 줄바꿈은 판정합니다. 구성 요소 위치나 크기가 기준 CSS 논리
픽셀에서 1px보다 많이 벗어나면 코드를 고치고 Step 3부터 다시
실행합니다.

- [ ] **Step 7: 전체 자동 검증을 실행합니다**

Run:

```bash
flutter test
flutter analyze
flutter build macos --release
```

Expected:

- `flutter test`: `All tests passed!`
- `flutter analyze`: `No issues found!`
- `flutter build macos --release`: exit code 0 and a release app bundle

- [ ] **Step 8: DRL 저장소에서 실제 기능을 확인합니다**

Run:

```bash
flutter run -d macos -- /Users/doortts/repos/drl
```

다음 순서로 확인하고 README에 결과를 기록합니다.

1. `40aff6d`의 `src/drlua.pas`를 엽니다.
2. File·Diff·Blame·History를 한 번씩 선택합니다.
3. Diff에서 Hunk·Inline·Split을 한 번씩 선택합니다.
4. 이전·다음, Histogram, 공백 무시, 줄바꿈, 집중 모드를 켰다 끕니다.
5. History에서 행에 포커스만 옮긴 뒤 Enter로 확정합니다.
6. Settings의 두 초기값으로 새 Full Diff를 각각 엽니다.
7. 작업 트리 파일에서 `편집기로 열기`를 누릅니다.
8. 창을 651, 650, 481, 480px 부근으로 줄여 열 전환을 확인합니다.

Expected: 오래된 선택의 내용이 새 머리글 아래 나타나지 않고, 모든
기능과 배치가 설계 문서와 일치합니다.

- [ ] **Step 9: 검수 자료와 최종 보정을 커밋합니다**

```bash
git add test/support/full_diff_qa_harness.dart \
  test/full_diff_visual_test.dart test/full_diff_syntax_benchmark_test.dart \
  tool/full_diff_visual_diff.dart \
  docs/superpowers/verification/full-diff-qa
git commit -m "test: capture full diff visual parity"
```

## 병렬 실행 순서

공용 계약을 바꾸는 충돌을 막기 위해 다음 순서를 지킵니다.

1. Task 1, Task 2, Task 3은 순서대로 실행합니다.
2. 첫 번째 병렬 묶음은 Task 4(Settings), Task 5(구문 강조),
   Task 8(머리글)입니다.
3. 두 번째 병렬 묶음은 Task 6(Diff 표시), Task 9(미니맵),
   Task 10(외부 편집기)입니다.
4. Task 7은 Task 6의 `FullDiffCodeRow`가 확정된 뒤 실행합니다.
5. Task 11에서 각 작업의 커밋을 순서대로 합치고 화면을 조립합니다.
6. Task 12는 자동 테스트, 이미지 대조, 성능·용량 측정과 DRL 확인을
   끝낸 뒤 실행 완료로 판정합니다.

병렬 작업 중에는 `git.dart`, `full_diff_model.dart`,
`full_diff_controller.dart`, `diff_screen.dart`,
`test/support/full_diff_fixtures.dart`를 공동 수정하지 않습니다.
공용 계약 변경이 필요하면 작업을 멈추고 Task 1 담당자가 먼저 계약
커밋을 보완한 뒤 나머지 작업을 다시 시작합니다.
