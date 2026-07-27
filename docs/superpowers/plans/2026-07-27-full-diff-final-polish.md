# Full Diff 최종 보완 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 승인된 최종 시안대로 Full Diff를 파일과 콘텐츠 중심의 화면으로 정리하고, 파일 크기·History 키보드 탐색·줄별 Blame을 완성합니다.

**Architecture:** `GitRepository.loadFiles()`가 기존 변경 목록을 만든 뒤 파일 크기를 한 번에 합성하고, Blame porcelain 파서는 SHA별 메타데이터를 재사용합니다. `DiffScreen`은 주변 커밋 열을 제거하고 변경 파일 열과 콘텐츠만 조정합니다. 머리글, History와 Blame은 각각 전용 위젯이 표시와 포커스를 맡되, 선택 상태와 비동기 데이터는 기존 `FullDiffSessionController`를 그대로 단일 기준으로 사용합니다.

**Tech Stack:** Flutter/Dart, Material, Flutter Shortcuts·Actions·Focus, Git CLI (`diff`, `ls-tree`, `blame`), 기존 `AvatarService`, `flutter_test`, 기존 Full Diff 시각 검수 도구

## Global Constraints

- 최신 기준은 `docs/superpowers/specs/2026-07-27-full-diff-final-polish-design.md`와 `docs/superpowers/specs/assets/full-diff-final-polish-mockup.svg`입니다.
- 파일 이름은 13px, 파일 보조 정보는 12px, diff 코드는 12px, 줄 번호와 기호는 10px, Hunk 제목은 12px로 고정합니다.
- 파일 경로, 변경 수, 파일 크기, SHA, 줄 번호와 Hunk 범위에는 `technicalFontFamily`과 `technicalFontFallback`을 사용합니다.
- `집중 모드`는 첫 번째 머리글에서 `편집기로 열기` 바로 왼쪽에 둡니다.
- 두 번째 머리글은 설정, Hunk 탐색, 표시 방식의 세 그룹을 유지합니다. `diff 알고리즘` 라벨은 메뉴 밖에 두고 메뉴에는 현재 선택값만 표시합니다.
- 일반 화면은 변경 파일과 콘텐츠만 표시합니다. 주변 커밋 목록과 너비 조절기는 만들지 않습니다.
- `FullDiffColumnWidths.commits` JSON 값은 이전 설정 파일을 읽고 다시 쓸 수 있도록 보존하되 화면 배치에는 사용하지 않습니다.
- History의 확정 선택과 키보드 포커스를 분리하고, 방향키는 현재 포커스된 목록만 움직입니다.
- Blame은 파일의 한 줄당 정확히 한 행만 만들고 Hunk 머리글을 삽입하지 않습니다.
- 파일 크기와 Blame 부가 메타데이터를 읽지 못해도 기존 파일 목록과 diff는 계속 사용할 수 있어야 합니다.
- 새 패키지 의존성, Gravatar 호출과 별도 아바타 서비스는 추가하지 않습니다.
- 각 작업은 실패 테스트, 최소 구현, 관련 테스트 통과, 커밋 순서로 진행합니다.
- 전체 테스트와 시각 캡처는 마지막 작업에서 한 번만 실행해 중복 시간을 줄입니다.

---

## 파일 구성

### 새 파일

- 새 제품 코드는 만들지 않습니다. 크기 형식은 기존 `lib/full_diff_header.dart`의 파일 요약 함수와 함께 유지합니다.
- `docs/superpowers/verification/full-diff-qa/final-polish-review.md`: 최종 설계와 구현을 대조한 검토 결과를 기록합니다.
- `docs/superpowers/verification/full-diff-qa/actual/18-final-default.png`
- `docs/superpowers/verification/full-diff-qa/actual/19-final-history.png`
- `docs/superpowers/verification/full-diff-qa/actual/20-final-blame.png`
- `docs/superpowers/verification/full-diff-qa/actual/21-final-focus.png`
- `docs/superpowers/verification/full-diff-qa/actual/22-final-responsive-650.png`
- `docs/superpowers/verification/full-diff-qa/actual/23-final-responsive-480.png`

### 수정 파일

- `lib/git.dart`: `GitFileChange.sizeBytes`, 묶음 파일 크기 조회, Blame 메타데이터 파싱을 맡습니다.
- `lib/full_diff_model.dart`: 작성자 메일·시각·제목을 Blame 화면 모델로 전달합니다.
- `lib/full_diff_header.dart`: 크기 형식, 집중 모드 위치, History 도움말, 알고리즘 라벨 분리와 도구 모음 순서를 맡습니다.
- `lib/full_diff_unavailable_panel.dart`: 공통 파일 요약에 파일 크기를 표시합니다.
- `lib/full_diff_code_row.dart`: 승인된 코드·줄 번호 크기와 Blame용 무(無) gutter 구성을 지원합니다.
- `lib/full_diff_hunk_header.dart`: Hunk 제목을 12px로 표시합니다.
- `lib/full_source_hunk_map.dart`: Hunk 머리글을 만들지 않고 소스 줄의 변경 종류와 현재 줄을 조회할 수 있게 합니다.
- `lib/full_blame_view.dart`: 줄별 작성자·제목·날짜·색상선·전체 소스를 표시합니다.
- `lib/full_history_view.dart`: History 선택 반전과 목록 방향키 탐색을 맡습니다.
- `lib/full_diff_split_view.dart`: 빗금 셀을 자신의 경계에서 자릅니다.
- `lib/diff_screen.dart`: 두 열 배치, 파일 목록, 포커스 전환, 단축키와 아바타 연결을 조정합니다.
- `lib/timeline.dart`: 기존 아바타 설정을 Full Diff에 전달합니다.
- `test/full_diff_git_test.dart`: 파일 크기 조회와 Blame porcelain 파싱을 검증합니다.
- `test/full_diff_model_test.dart`: 확장된 Blame 모델 전달을 검증합니다.
- `test/full_diff_header_test.dart`: 머리글 순서, 알고리즘 분리, History 도움말과 크기 형식을 검증합니다.
- `test/full_diff_widgets_test.dart`: 코드·gutter·Hunk 글자 크기와 표시 불가 파일 요약을 검증합니다.
- `test/full_diff_content_views_test.dart`: History 반전, 빗금 잘림과 Blame 열 구성을 검증합니다.
- `test/full_diff_workspace_test.dart`: 주변 커밋 제거, 파일 목록, 반응형 배치와 키보드 포커스를 검증합니다.
- `test/app_test.dart`: 실제 타임라인 진입 경로와 설정 호환성을 검증합니다.
- `test/support/full_diff_qa_harness.dart`: 크기와 Blame 메타데이터가 있는 고정 검수 데이터를 제공합니다.
- `test/full_diff_visual_test.dart`: 최종 보완 상태 여섯 장을 캡처합니다.
- `docs/superpowers/verification/full-diff-qa/README.md`: 새 캡처와 검수 판정을 기록합니다.

---

### Task 1: 파일 크기 모델과 저비용 조회

**Files:**
- Modify: `lib/git.dart`
- Test: `test/full_diff_git_test.dart`

**Interfaces:**
- Produces: `GitFileChange.sizeBytes`
- Produces: `GitRepository.loadFiles()`가 크기를 포함한 파일 목록을 반환
- Preserves: `FullDiffRepository.loadFiles()` 서명, untracked 파일 판별과 기존 diff 로딩

- [ ] **Step 1: 파일 크기 계약의 실패 테스트를 작성합니다**

`test/full_diff_git_test.dart`에 실제 Git 저장소를 이용하는 다음 테스트를
추가합니다.

```dart
test('loads result blob sizes with one ls-tree query', () async {
  // 수정·추가·이름 변경 파일을 한 커밋에 만들고 loadFiles()를 호출합니다.
  // 각 sizeBytes가 결과 blob의 UTF-8 바이트 수인지 검사합니다.
  // 기록된 명령에서 `ls-tree -rlz <commit> -- ...`가 한 번인지 검사합니다.
});

test('loads deleted sizes from the selected parent with at most two queries',
    () async {
  // 수정 파일과 삭제 파일을 함께 만들고 결과 revision과 parent revision
  // 조회가 각각 한 번, 전체 두 번 이하인지 검사합니다.
});

test('parses ls-tree sizes for paths containing spaces and tabs', () async {
  // NUL 구분 출력에서 경로와 크기가 손실되지 않는지 검사합니다.
});

test('keeps files when size metadata lookup fails', () async {
  // ls-tree만 exitCode 1을 반환하는 runner를 주입합니다.
  // loadFiles()는 성공하고 모든 sizeBytes만 null인지 검사합니다.
});

test('loads working tree file and symbolic link sizes without blob reads',
    () async {
  // 일반 파일은 FileStat.size, 심볼릭 링크는 링크 대상 문자열의
  // UTF-8 바이트 길이인지 검사합니다.
});
```

첫 테스트에서는 다음 필드가 아직 없어서 컴파일이 실패해야 합니다.

```dart
expect(file.sizeBytes, utf8.encode(contents).length);
```

- [ ] **Step 2: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_git_test.dart --plain-name "loads result blob sizes with one ls-tree query" --reporter expanded
```

Expected: `GitFileChange`에 `sizeBytes` getter가 없다는 컴파일 오류

- [ ] **Step 3: `GitFileChange`에 선택적 크기를 추가합니다**

`lib/git.dart`:

```dart
class GitFileChange {
  const GitFileChange({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
    this.oldPath,
    this.isBinary = false,
    this.sizeBytes,
  });

  final String path;
  final String? oldPath;
  final String status;
  final int? additions;
  final int? deletions;
  final bool isBinary;
  final int? sizeBytes;
}
```

기존 테스트 fixture는 기본값 `null`을 사용하므로 한꺼번에 수정하지
않습니다.

- [ ] **Step 4: NUL 구분 `ls-tree` 크기 파서를 구현합니다**

`lib/git.dart`에 다음 순수 파서를 추가합니다.

```dart
Map<String, int> _parseLsTreeSizes(String output) {
  final result = <String, int>{};
  for (final record in output.split('\x00')) {
    if (record.isEmpty) continue;
    final tab = record.indexOf('\t');
    if (tab < 0) continue;
    final metadata = record.substring(0, tab).split(' ');
    if (metadata.length < 4) continue;
    final size = int.tryParse(metadata[3]);
    if (size != null) result[record.substring(tab + 1)] = size;
  }
  return result;
}
```

조회 명령은 revision마다 한 번만 실행합니다.

```dart
await _run(['ls-tree', '-rlz', revision, '--', ...paths]);
```

결과 revision에는 삭제 파일을 제외한 `file.path`를, 선택한 parent에는
삭제 파일의 `file.oldPath ?? file.path`를 전달합니다. 이름 변경 파일은
결과 경로만 조회합니다. 빈 경로 묶음에는 Git 명령을 실행하지 않습니다.

- [ ] **Step 5: 작업 트리 크기와 실패 격리를 구현합니다**

작업 트리의 삭제되지 않은 파일은 다음 규칙으로 읽습니다.

```dart
final type = await FileSystemEntity.type(
  absolutePath,
  followLinks: false,
);
final size = switch (type) {
  FileSystemEntityType.file => (await FileStat.stat(absolutePath)).size,
  FileSystemEntityType.link =>
    utf8.encode(await Link(absolutePath).target()).length,
  _ => null,
};
```

작업 트리 삭제 파일은 base revision의 `ls-tree`를 한 번 사용합니다.
각 로컬 파일 오류와 각 revision의 `ls-tree` 오류는 잡아서 해당 파일의
크기만 `null`로 둡니다.

크기를 넣기 위해 `GitFileChange`를 다시 만들 때 `_untrackedFiles`의
Expando 표시도 새 객체에 복사해 untracked diff와 Blame 동작을
보존합니다.

- [ ] **Step 6: 파일 크기 테스트와 기존 Git 테스트를 확인합니다**

Run:

```bash
dart format lib/git.dart test/full_diff_git_test.dart
flutter test test/full_diff_git_test.dart --reporter expanded
```

Expected: 새 크기 테스트와 기존 Full Diff Git 테스트가 모두 통과

- [ ] **Step 7: 작업을 커밋합니다**

```bash
git add lib/git.dart test/full_diff_git_test.dart
git commit -m "feat: load full diff file sizes"
```

---

### Task 2: Blame 메타데이터 파싱과 모델 전달

**Files:**
- Modify: `lib/git.dart`
- Modify: `lib/full_diff_model.dart`
- Test: `test/full_diff_git_test.dart`
- Test: `test/full_diff_model_test.dart`

**Interfaces:**
- Produces: `GitBlameLine.authorEmail`, `authorTimestamp`, `summary`
- Produces: 같은 필드를 가진 `BlameLine`
- Preserves: 기존 생성자의 호출부가 그대로 컴파일되도록 기본값 제공

- [ ] **Step 1: porcelain 메타데이터의 실패 테스트를 작성합니다**

`test/full_diff_git_test.dart`에 임시 저장소를 만들고 작성자 이름·메일,
고정 timestamp와 커밋 제목을 가진 두 커밋을 작성합니다. 같은 커밋에
속한 줄이 반복되는 파일에 `loadBlame()`을 호출해 다음을 검사합니다.

```dart
expect(lines.first.authorEmail, 'test@example.com');
expect(lines.first.authorTimestamp, isNotNull);
expect(lines.first.summary, 'add fixture');
expect(lines[1].authorEmail, lines.first.authorEmail);
expect(lines[1].summary, lines.first.summary);
```

별도 parser fixture에는 두 번째 SHA 블록에서 `author`, `author-mail`,
`author-time`, `summary`가 생략된 반복 형식을 넣어 SHA 캐시 재사용을
검사합니다. 메타데이터가 빠진 SHA와 40자리 zero SHA도 빈 값·`null`·
`uncommitted == true`로 계속 반환되는지 검사합니다.

`test/full_diff_model_test.dart`에는 `BlameDocument.fromGitLines()`가
네 필드를 손실 없이 복사하는 검사를 추가합니다.

- [ ] **Step 2: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_git_test.dart test/full_diff_model_test.dart --plain-name "preserves blame author metadata by sha" --reporter expanded
```

Expected: `GitBlameLine`과 `BlameLine`에 새 필드가 없다는 컴파일 오류

- [ ] **Step 3: 호환 가능한 모델 필드를 추가합니다**

`lib/git.dart`:

```dart
class GitBlameLine {
  const GitBlameLine({
    required this.lineNumber,
    required this.sha,
    required this.author,
    required this.uncommitted,
    this.authorEmail = '',
    this.authorTimestamp,
    this.summary = '',
  });

  final int lineNumber;
  final String sha;
  final String author;
  final String authorEmail;
  final int? authorTimestamp;
  final String summary;
  final bool uncommitted;
}
```

`lib/full_diff_model.dart`의 `BlameLine`에도 같은 기본값과 타입을
추가하고 `BlameDocument.fromGitLines()`에서 모두 복사합니다.

- [ ] **Step 4: SHA별 메타데이터 캐시로 parser를 바꿉니다**

`_parseBlamePorcelain()`은 다음 record를 사용합니다.

```dart
typedef _BlameMetadata = ({
  String author,
  String email,
  int? timestamp,
  String summary,
});
```

새 SHA 헤더를 읽으면 캐시 값을 현재 메타데이터의 기본값으로 가져오고,
`author `, `author-mail `, `author-time `, `summary `을 읽을 때 값을
갱신합니다. `author-mail`의 바깥쪽 `<`와 `>`만 제거합니다. 탭으로
시작하는 source 행에서 완성된 값을 캐시에 저장한 뒤 `GitBlameLine`을
만듭니다.

반복 SHA 블록에 메타데이터 줄이 없으면 캐시 값을 그대로 사용하고,
처음 보는 불완전한 SHA면 이름·메일·제목은 빈 문자열, 시각은 `null`을
사용합니다.

- [ ] **Step 5: 모델과 parser 테스트를 확인합니다**

Run:

```bash
dart format lib/git.dart lib/full_diff_model.dart test/full_diff_git_test.dart test/full_diff_model_test.dart
flutter test test/full_diff_git_test.dart test/full_diff_model_test.dart --reporter expanded
```

Expected: 모든 Git·모델 테스트 통과

- [ ] **Step 6: 작업을 커밋합니다**

```bash
git add lib/git.dart lib/full_diff_model.dart test/full_diff_git_test.dart test/full_diff_model_test.dart
git commit -m "feat: preserve full blame metadata"
```

---

### Task 3: 머리글 순서, 파일 정보와 글자 크기

**Files:**
- Modify: `lib/full_diff_header.dart`
- Modify: `lib/full_diff_unavailable_panel.dart`
- Modify: `lib/full_diff_code_row.dart`
- Modify: `lib/full_diff_hunk_header.dart`
- Modify: `lib/diff_screen.dart`
- Test: `test/full_diff_header_test.dart`
- Test: `test/full_diff_widgets_test.dart`
- Test: `test/full_diff_workspace_test.dart`

**Interfaces:**
- Produces: `formatByteSize(int?)`
- Changes: `GlobalFileBar`가 집중 모드 상태와 callback을 받음
- Changes: `GlobalDiffToolbar`에서 집중 모드 인자 제거
- Changes: `FullDiffSegmentedControl.tooltipFor`

- [ ] **Step 1: 크기 형식과 머리글 순서의 실패 테스트를 작성합니다**

`test/full_diff_header_test.dart`에 다음 순수 함수 검사를 추가합니다.

```dart
expect(formatByteSize(null), '—');
expect(formatByteSize(0), '0 B');
expect(formatByteSize(1023), '1023 B');
expect(formatByteSize(1536), '1.5 KB');
expect(formatByteSize(10 * 1024), '10 KB');
expect(formatByteSize(3 * 1024 * 1024), '3 MB');
```

`GlobalFileBar` 테스트 fixture에 `focusMode`와 callback을 전달하고
다음 x 좌표 순서를 검사합니다.

```dart
expect(
  tester.getCenter(find.byKey(const Key('focus-mode'))).dx,
  lessThan(tester.getCenter(find.byKey(const Key('open-editor'))).dx),
);
expect(
  tester.getCenter(find.byKey(const Key('open-editor'))).dx,
  lessThan(tester.getCenter(find.text('File')).dx),
);
```

선택 파일에 `sizeBytes: 1536`을 넣고 첫 번째 머리글과 표시 불가
패널에 `1.5 KB`가 보이는지 검사합니다.

- [ ] **Step 2: 알고리즘 분리와 History 도움말의 실패 테스트를 작성합니다**

다음 요소가 별개인지 검사합니다.

```dart
expect(find.byKey(const Key('diff-algorithm-label')), findsOneWidget);
expect(find.text('diff 알고리즘'), findsOneWidget);
expect(find.byKey(const Key('diff-algorithm-value')), findsOneWidget);
expect(find.text('Git setting'), findsOneWidget);
```

`diff-algorithm-label`의 오른쪽이 `diff-algorithm-value`의 왼쪽보다
작아야 합니다. 선택값 메뉴의 tooltip과 접근성 설명에는 현재 선택값과
`Git이 변경 구간을 나누는 방식을 정합니다.`가 남아 있어야 합니다.

History 버튼에 마우스를 500ms 올린 뒤 정확히 다음 문구가 하나
표시되는지 검사합니다.

```dart
expect(find.text('파일의 변경 이력을 보여줍니다'), findsOneWidget);
```

- [ ] **Step 3: 파일 목록과 코드 글자 크기의 실패 테스트를 작성합니다**

`test/full_diff_workspace_test.dart`에서 파일 행 안의 이름을 감싼
`Container`가 배경색이나 둥근 모서리를 갖지 않는지 검사하고, 선택은
`selected-file-<path>` 행 전체의 `fullDiffSelection`만 사용하는지
검사합니다.

다음 크기를 각각 검사합니다.

```dart
expect(fileName.style?.fontSize, 13);
expect(fileStats.style?.fontSize, 12);
expect(sourceSpan.style?.fontSize, 12);
expect(lineNumber.style?.fontSize, 10);
expect(marker.style?.fontSize, 10);
expect(hunkTitle.style?.fontSize, 12);
```

- [ ] **Step 4: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_header_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart --reporter expanded
```

Expected: 집중 모드가 두 번째 줄에 있고, 알고리즘 이름이 메뉴 안에
있으며, 파일 크기와 승인 글자 크기가 적용되지 않아 새 검사가 실패

- [ ] **Step 5: 파일 크기 형식과 공통 요약을 구현합니다**

`lib/full_diff_header.dart`의 공개 helper는 다음 규칙을 사용합니다.

```dart
String formatByteSize(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value < 10 && value != value.roundToDouble() ? 1 : 0;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
```

`fileSummary()`는 다음 형식을 반환합니다.

```text
M · +7 −0 · 3.1 KB
```

`FullDiffUnavailablePanel`의 중복 `_fileSummary()`를 제거하고 같은
`fileSummary()`를 사용합니다. `DiffScreen` 파일 목록 보조 줄은
`+7 −0 · 3.1 KB` 형식을 사용합니다.

- [ ] **Step 6: 첫 번째 머리글과 History 도움말을 구현합니다**

`GlobalFileBar`에 다음 인자를 추가합니다.

```dart
required bool focusMode,
required ValueChanged<bool> onFocusModeChanged,
```

오른쪽 `Wrap`의 첫 요소에 `focus-mode` 버튼을 두고 그 다음을
`open-editor`, File·Diff·Blame·History, encoding 순서로 유지합니다.
집중 모드가 켜지면 버튼 문구는 기존처럼 `탐색 패널`, 꺼져 있으면
`집중 모드`를 사용합니다.

`FullDiffSegmentedControl<T>`에 다음 선택 인자를 추가합니다.

```dart
final String? Function(T value)? tooltipFor;
```

각 `_SegmentButton`을 해당 값의 tooltip이 있을 때만 `Tooltip`로 감싸고
`FullDiffView.history`에는 `파일의 변경 이력을 보여줍니다`를
반환합니다. Tooltip은 pointer event를 가로막지 않습니다.

- [ ] **Step 7: 두 번째 머리글의 세 그룹을 구현합니다**

`GlobalDiffToolbar`에서 `focusMode`와 `onFocusModeChanged`를 제거합니다.
자식은 다음 세 `Wrap`으로 나눕니다.

1. `diff 알고리즘` 라벨 + 현재 선택값 메뉴 + 공백 무시 + 줄바꿈
2. 이전 Hunk + 카운터 + 다음 Hunk
3. Hunk + Inline + Split

부모 `Wrap`은 `WrapAlignment.spaceBetween`을 사용하고 줄이 바뀌어도
각 그룹 내부 순서를 보존합니다. 알고리즘 라벨과 선택값은 같은 내부
`Wrap`에 둡니다.

`_AlgorithmMenu`는 버튼 안에서 `widget.algorithm.label`만 표시합니다.
바깥 라벨은 `Key('diff-algorithm-label')`, 버튼 값은
`Key('diff-algorithm-value')`, 전체 의미 영역은 기존
`Key('diff-algorithm')`을 유지해 기존 자동화와 `Esc` 동작을
깨뜨리지 않습니다.

- [ ] **Step 8: 파일 행과 승인된 글자 크기를 적용합니다**

파일 이름을 감싼 회색 `Container`를 제거하고 `Text`를 바로 둡니다.
행의 전체 선택 배경과 클릭 영역은 유지합니다.

`lib/full_diff_code_row.dart`의 `_sourceStyle`은 `fontSize: 12`,
`height: 21 / 12`, `_gutterStyle`은 `fontSize: 10`,
`height: 21 / 10`으로 바꿉니다. `lib/full_diff_hunk_header.dart`의
제목은 12px로 바꿉니다. 행 최소 높이 27px와 기존 패딩은 유지합니다.

- [ ] **Step 9: 관련 테스트를 확인합니다**

Run:

```bash
dart format lib/full_diff_header.dart lib/full_diff_unavailable_panel.dart lib/full_diff_code_row.dart lib/full_diff_hunk_header.dart lib/diff_screen.dart test/full_diff_header_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart
flutter test test/full_diff_header_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart --reporter expanded
```

Expected: 머리글·파일 목록·글자 크기 테스트 통과

- [ ] **Step 10: 작업을 커밋합니다**

```bash
git add lib/full_diff_header.dart lib/full_diff_unavailable_panel.dart lib/full_diff_code_row.dart lib/full_diff_hunk_header.dart lib/diff_screen.dart test/full_diff_header_test.dart test/full_diff_widgets_test.dart test/full_diff_workspace_test.dart
git commit -m "feat: polish full diff controls and file metadata"
```

---

### Task 4: 두 열 작업 영역, History 선택과 키보드 포커스

**Files:**
- Modify: `lib/diff_screen.dart`
- Modify: `lib/full_history_view.dart`
- Modify: `lib/full_diff_split_view.dart`
- Test: `test/full_diff_workspace_test.dart`
- Test: `test/full_diff_content_views_test.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Removes from UI: 주변 커밋 열과 `_StepCommitIntent`
- Preserves: `FullDiffColumnWidths.commits` 설정 직렬화
- Changes: `FullHistoryView.focusNode`, `onMoveToFiles`
- Produces: 파일 목록과 History 목록 사이의 명시적 포커스 이동

- [ ] **Step 1: 주변 커밋 제거와 반응형 배치의 실패 테스트를 작성합니다**

`test/full_diff_workspace_test.dart`와 `test/app_test.dart`의 기존
651·650·481·480px 표를 다음 기준으로 바꿉니다.

| 너비 | 주변 커밋 | 변경 파일 | 콘텐츠 |
|---:|---|---|---|
| 1070 | 없음 | 표시 | 표시 |
| 650 | 없음 | 표시 | 표시 |
| 481 | 없음 | 표시 | 표시 |
| 480 | 없음 | 숨김 | 표시 |
| 집중 모드 | 없음 | 숨김 | 표시 |

모든 너비에서 `nearby-commits-pane`, `nearby-commits-list`,
`nearby-column-resizer`가 없어야 합니다. 481px 이상에서는
`commit-files-pane`, 480px 이하와 집중 모드에서는 `diff-column`만
있어야 합니다.

일반 커밋의 파일 열에는 커밋 제목·작성자 블록이 없고 `변경 파일`
머리글로 바로 시작하는지 검사합니다. merge commit fixture에서는
`merge-parent-chooser`가 계속 표시되는지도 별도로 검사합니다.

- [ ] **Step 2: 파일과 History 키보드 이동의 실패 테스트를 작성합니다**

다음 시나리오를 `test/full_diff_workspace_test.dart`에 추가합니다.

1. 파일 목록에 포커스를 둔 `Down`은 다음 파일을 선택합니다.
2. `Cmd+Down`은 콘텐츠나 History에 포커스가 있어도 다음 파일을
   선택합니다.
3. History 화면에서 파일 목록의 `Right`는 History 목록으로 포커스를
   옮깁니다.
4. History 목록의 `Down`은 다음 History를 확정 선택하고 오른쪽 상세
   diff를 바꿉니다.
5. History 목록의 `Left`는 파일 목록으로 포커스를 돌립니다.
6. History 목록에서 `Down`을 눌러도 변경 파일 선택은 바뀌지 않습니다.
7. `Option+Up/Down`, `Cmd+Shift+Up/Down`, `Cmd+Shift+F`, `Esc`의
   기존 동작은 그대로입니다.

포커스는 다음 key로 확인합니다.

```dart
expect(
  tester.widget<Focus>(
    find.byKey(const Key('changed-files-focus')),
  ).focusNode?.hasFocus,
  isTrue,
);
expect(
  tester.widget<Focus>(
    find.byKey(const Key('history-list-focus')),
  ).focusNode?.hasFocus,
  isTrue,
);
```

- [ ] **Step 3: History 선택 반전과 빗금 잘림의 실패 테스트를 작성합니다**

`test/full_diff_content_views_test.dart`에서 선택 History 행의 배경은
`fullDiffSelection`, 제목은 `fullDiffAccent` 또는 흰색, 보조 정보는
선택 상태에서 읽을 수 있는 대비색인지 검사합니다. 선택하지 않은 행은
`fullDiffCanvas`를 유지해야 합니다.

키보드 포커스가 있는 선택 행에는 별도 1px 포커스 테두리가 있고,
마우스로 확정 선택한 뒤 포커스를 파일 목록으로 옮겨도 선택 배경은
남아 있어야 합니다.

`HatchedDiffCell` 아래에 `ClipRect`가 있고 painter의 paint bounds가
cell bounds를 넘지 않는지 검사합니다.

- [ ] **Step 4: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_workspace_test.dart test/full_diff_content_views_test.dart test/app_test.dart --reporter expanded
```

Expected: 주변 커밋 열이 남아 있고, `Cmd+Up/Down`이 커밋을 움직이며,
History 선택이 중립 배경이고, 빗금이 잘리지 않아 새 검사가 실패

- [ ] **Step 5: `DiffScreen`을 파일과 콘텐츠의 두 열로 단순화합니다**

다음을 제거합니다.

- `_StepCommitIntent`
- `_commitsWidth`
- `_nearbyCommits()`
- `_resizeCommits()`
- `_ResponsiveDiffBody`의 `showCommits`, `commitsWidth`,
  `nearbyCommits`, `onCommitsResized`

`_ResponsiveDiffBody`는 `showFiles`, `filesWidth`, `commitFiles`,
`content`, `onFilesResized`, `onResizeEnd`만 받습니다. 481px 이상에서
파일 열을 표시하고, 저장된 `_filesWidth`를
`FullDiffColumnWidths.minFiles`와 `bodyWidth - 280` 사이로 제한합니다.
480px 이하에서는 콘텐츠만 표시합니다.

너비 저장 시 더 이상 화면에서 바꾸지 않는 값을 보존합니다.

```dart
FullDiffColumnWidths(
  commits: widget.columnWidths.commits,
  files: _filesWidth,
)
```

파일 열의 일반 커밋 제목·작성자 블록은 제거합니다. merge commit의
parent chooser만 `변경 파일` 머리글 위에 간결하게 유지합니다.

- [ ] **Step 6: 파일 목록의 포커스와 단축키를 구현합니다**

`_DiffScreenState`에 다음 노드를 추가하고 `dispose()`에서 해제합니다.

```dart
final _fileListFocus = FocusNode(debugLabel: 'full diff files');
final _historyListFocus = FocusNode(debugLabel: 'full diff history');
```

변경 파일 목록은 `Key('changed-files-focus')`의 `Focus`로 감쌉니다.
plain `Up/Down`은 이 Focus에서 `_stepFile(-1/1)`을 호출하고,
History 화면의 `Right`는 `_historyListFocus.requestFocus()`를
호출합니다. meta나 alt modifier가 있으면 처리하지 않고 상위
Shortcuts로 보냅니다.

최상위 Shortcuts에서는 plain `Up/Down`과 `_StepCommitIntent`를
제거하고 `Cmd+Up/Down`을 `_StepFileIntent`에 연결합니다. 따라서
History나 콘텐츠에 포커스가 있어도 Cmd 조합은 파일을 움직입니다.

- [ ] **Step 7: History 목록을 제어형 선택과 포커스 목록으로 바꿉니다**

`FullHistoryView`를 `StatefulWidget`으로 바꾸고 다음 선택 인자를
추가합니다.

```dart
final FocusNode? focusNode;
final VoidCallback? onMoveToFiles;
```

목록 전체를 `Key('history-list-focus')`의 `Focus`로 감쌉니다.
`Up/Down`은 `selected`의 index를 기준으로 새 entry를 계산해
`onSelected`를 즉시 호출하고 `Scrollable.ensureVisible()`로 행을
보이게 합니다. 선택이 없으면 Down은 첫 행, Up은 마지막 행을
선택합니다. `Left`는 `onMoveToFiles`를 호출합니다.

개별 행의 Enter와 클릭은 유지합니다. 행은 다음 세 상태를
독립적으로 그립니다.

- 선택 안 됨: `fullDiffCanvas`
- 확정 선택: `fullDiffSelection`
- 확정 선택이면서 목록 포커스: 같은 선택 배경 + 1px
  `fullDiffAccent` 안쪽 테두리

- [ ] **Step 8: History 포커스 연결과 빗금 clip을 적용합니다**

`DiffScreen._historyContent()`은 `_historyListFocus`와
`_fileListFocus.requestFocus` callback을 `FullHistoryView`에
전달합니다. 파일 목록에서 History로 이동할 때 현재 선택 History가
없으면 첫 항목을 선택한 뒤 포커스를 옮깁니다.

`HatchedDiffCell`은 painter를 다음처럼 자릅니다.

```dart
@override
Widget build(BuildContext context) => const ClipRect(
  child: CustomPaint(
    painter: _HatchedDiffPainter(),
    child: SizedBox(height: 27),
  ),
);
```

- [ ] **Step 9: 관련 테스트를 확인합니다**

Run:

```bash
dart format lib/diff_screen.dart lib/full_history_view.dart lib/full_diff_split_view.dart test/full_diff_workspace_test.dart test/full_diff_content_views_test.dart test/app_test.dart
flutter test test/full_diff_workspace_test.dart test/full_diff_content_views_test.dart test/app_test.dart --reporter expanded
```

Expected: 두 열 배치, History 선택·포커스, 빗금과 기존 앱 이동 테스트
통과

- [ ] **Step 10: 작업을 커밋합니다**

```bash
git add lib/diff_screen.dart lib/full_history_view.dart lib/full_diff_split_view.dart test/full_diff_workspace_test.dart test/full_diff_content_views_test.dart test/app_test.dart
git commit -m "feat: simplify full diff navigation workspace"
```

---

### Task 5: 전체 파일 줄 정렬 Blame과 기존 아바타 연결

**Files:**
- Modify: `lib/full_diff_code_row.dart`
- Modify: `lib/full_source_hunk_map.dart`
- Modify: `lib/full_blame_view.dart`
- Modify: `lib/diff_screen.dart`
- Modify: `lib/timeline.dart`
- Test: `test/full_diff_content_views_test.dart`
- Test: `test/full_diff_workspace_test.dart`
- Test: `test/app_test.dart`

**Interfaces:**
- Changes: `FullDiffCodeRow.showGutter`
- Produces: `FullSourceHunkMap.kindForLine(int)`
- Changes: `FullBlameView.avatarService`, `showRemoteAvatars`
- Changes: `DiffScreen.avatarService`, `showRemoteAvatars`

- [ ] **Step 1: 줄별 Blame 구성의 실패 테스트를 작성합니다**

`test/full_diff_content_views_test.dart`의 기존 Blame 테스트를 다음
기준으로 바꿉니다.

```dart
expect(find.byKey(Key('blame-hunk-header-${anchor.id}')), findsNothing);
expect(find.byKey(const Key('blame-line-1')), findsOneWidget);
expect(find.byKey(const Key('blame-line-2')), findsOneWidget);
expect(find.byKey(const Key('blame-avatar-2')), findsOneWidget);
expect(find.byKey(const Key('blame-line-number-2')), findsOneWidget);
expect(find.byKey(const Key('blame-summary-2')), findsOneWidget);
expect(find.byKey(const Key('blame-date-2')), findsOneWidget);
expect(find.byKey(const Key('blame-rail-2')), findsOneWidget);
```

각 key의 x 좌표가 아바타, 줄 번호, 제목, 날짜, 4px rail, source 순서인지
검사합니다. `blame-rail-2`의 너비는 정확히 4px이어야 합니다.
Blame 행 수는 `document.file.lines.length`와 같고, Hunk 수가 늘어나도
추가 행이 생기지 않아야 합니다.

긴 제목은 `TextOverflow.ellipsis`, 날짜는 `yyyy-MM-dd`, 소스는 기존
highlighter의 token 색을 사용해야 합니다. 메일이 있는
`GitIdentity`가 `IdentityAvatar`에 전달되고 원격 결과가 없을 때
작성자 이니셜이 보이는지도 검사합니다.

- [ ] **Step 2: 활성 Hunk와 스크롤 anchor의 실패 테스트를 작성합니다**

두 Hunk가 있는 fixture에서 활성 Hunk를 바꿔도 다음을 확인합니다.

- 현재 source 행에 `blame-current-line-<line>`가 하나만 있음
- 해당 행의 `DiffLineKind`만 add 또는 delete이고 나머지는 context
- 현재 anchor의 `GlobalKey`가 source 행에 붙어 있음
- 미니맵과 `nearestHunkAnchorForSourceLine()` probe는 계속 동작함
- Hunk 제목을 source 사이에 삽입하지 않음

- [ ] **Step 3: 아바타 설정 전달의 실패 테스트를 작성합니다**

`test/app_test.dart`에서 `TimelineScreen`에 주입한 `AvatarService`와
`showRemoteAvatars: false`가 타임라인에서 연 `DiffScreen`과
`FullBlameView`까지 전달되는지 위젯 속성으로 검사합니다.

원격 표시가 꺼진 경우 runner 호출 없이 이니셜을 보여야 합니다.
원격 표시가 켜졌지만 서비스가 `null`인 경우도 같은 fallback을
사용합니다.

- [ ] **Step 4: 실패 이유를 확인합니다**

Run:

```bash
flutter test test/full_diff_content_views_test.dart test/full_diff_workspace_test.dart test/app_test.dart --reporter expanded
```

Expected: Blame에 Hunk 머리글과 SHA 80px 메타데이터가 남아 있고,
새 모델 값과 아바타 설정을 표시하지 않아 새 검사가 실패

- [ ] **Step 5: 코드 행에 Blame용 gutter 비표시 옵션을 추가합니다**

`FullDiffCodeRow`에 기본값이 true인 옵션을 추가합니다.

```dart
final bool showGutter;
```

`showGutter == false`이면 왼쪽 `fullDiffLineNumberWidth` spacer와
overlay gutter를 만들지 않습니다. 일반 Hunk·Inline·Split·File
호출부는 기본값을 사용해 기존 모양을 유지합니다. Blame은 줄 번호를
메타데이터 열 안에 직접 표시하므로 `showGutter: false`를 사용합니다.

- [ ] **Step 6: 소스 매핑을 머리글 없이 조회할 수 있게 합니다**

`FullSourceHunkMap`에 다음 메서드를 추가합니다.

```dart
DiffLineKind kindForLine(int lineNumber) {
  RangeError.checkValueInInterval(lineNumber, 1, lineCount, 'lineNumber');
  return _lineKinds[lineNumber] ?? DiffLineKind.context;
}
```

`FullBlameView`는 `sourceMap.itemCount`나 `itemAt()`을 순회하지 않고
`document.file.lines.length`만큼 순회합니다. `lineNumber = index + 1`,
`kind = sourceMap.kindForLine(lineNumber)`를 사용합니다.

현재 Hunk의 source 줄에는 기존 `_anchorKey(activeAnchor)`와
`blame-current-line-<line>`를 붙입니다. 다른 행의
`FullDiffAnchorProbe`는 `nearestHunkAnchorForSourceLine()`을 계속
사용해 스크롤에 따른 현재 Hunk 갱신을 유지합니다.

- [ ] **Step 7: Blame 메타데이터 행을 구현합니다**

`BlameSourceRow`은 `FullDiffCodeRow(showGutter: false)`의
`leadingMetadata`에 다음 고정 순서를 그립니다.

1. 22px `IdentityAvatar`
2. 42px 오른쪽 정렬 줄 번호
3. 남은 너비의 제목
4. 76px 날짜
5. 4px commit rail

메타데이터 전체 너비는 900px 이상에서 360px, 그보다 좁을 때
`viewportWidth * 0.38`을 250~320px로 제한합니다. 제목만
`TextOverflow.ellipsis`를 사용하고 아바타·줄 번호·날짜·rail은
숨기지 않습니다.

날짜 helper는 새 패키지 없이 `DateTime.fromMillisecondsSinceEpoch()`
와 `padLeft(2, '0')`으로 `yyyy-MM-dd`를 만듭니다. 시각이 `null`이면
`—`를 표시합니다.

rail 색은 `AvatarService.branchColor(blame.sha)`를 사용하고 zero SHA나
빈 SHA는 `fullDiffMuted`를 사용합니다. 작성자 identity는 다음처럼
만듭니다.

```dart
GitIdentity(name: blame.author, email: blame.authorEmail)
```

원격 표시가 켜지고 `avatarService`와 SHA가 있으면
`avatarService.resolve(sha)`의 `author`를 `IdentityAvatar`에
전달합니다. 서비스 캐시가 SHA별 Future를 재사용하므로 행마다 새
외부 요청을 만들지 않습니다.

- [ ] **Step 8: 아바타 설정을 타임라인에서 Blame까지 전달합니다**

`DiffScreen` 생성자에 다음 기본 인자를 추가합니다.

```dart
final AvatarService? avatarService;
final bool showRemoteAvatars;
```

`TimelineScreen._openFullDiff()`가 `widget.avatarService`와
`widget.showRemoteAvatars`를 전달하고, `DiffScreen._blameContent()`가
같은 값을 `FullBlameView`에 전달합니다. 테스트와 QA harness의 직접
생성은 기본값 `null`, `true`를 사용합니다.

- [ ] **Step 9: 관련 테스트를 확인합니다**

Run:

```bash
dart format lib/full_diff_code_row.dart lib/full_source_hunk_map.dart lib/full_blame_view.dart lib/diff_screen.dart lib/timeline.dart test/full_diff_content_views_test.dart test/full_diff_workspace_test.dart test/app_test.dart
flutter test test/full_diff_content_views_test.dart test/full_diff_workspace_test.dart test/app_test.dart --reporter expanded
```

Expected: 줄 수·열 순서·Hunk 정렬·fallback 아바타와 실제 진입 경로
테스트 통과

- [ ] **Step 10: 작업을 커밋합니다**

```bash
git add lib/full_diff_code_row.dart lib/full_source_hunk_map.dart lib/full_blame_view.dart lib/diff_screen.dart lib/timeline.dart test/full_diff_content_views_test.dart test/full_diff_workspace_test.dart test/app_test.dart
git commit -m "feat: render aligned full file blame rows"
```

---

### Task 6: 시각 자료, 전체 회귀 검증과 독립 검토

**Files:**
- Modify: `test/support/full_diff_qa_harness.dart`
- Modify: `test/full_diff_visual_test.dart`
- Modify: `docs/superpowers/verification/full-diff-qa/README.md`
- Create: `docs/superpowers/verification/full-diff-qa/final-polish-review.md`
- Create: `docs/superpowers/verification/full-diff-qa/actual/18-final-default.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/19-final-history.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/20-final-blame.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/21-final-focus.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/22-final-responsive-650.png`
- Create: `docs/superpowers/verification/full-diff-qa/actual/23-final-responsive-480.png`

**Interfaces:**
- Produces: 최종 보완 전용 회귀 이미지 여섯 장
- Produces: 승인 설계의 각 완료 기준과 테스트 증거를 잇는 검토 문서

- [ ] **Step 1: 검수 fixture를 실제 새 모델과 맞춥니다**

`test/support/full_diff_qa_harness.dart`의 변경 파일에 서로 다른
`sizeBytes`를 넣고 Blame fixture에는 실제처럼 작성자 메일·시각·제목을
넣습니다. 기본 화면에 일반·추가·삭제 파일이 함께 보여 크기 형식
`B`, `KB`, `—`를 한 번에 확인할 수 있게 합니다.

History fixture는 선택 행과 키보드 포커스 행이 다른 상태도 만들 수 있게
합니다. Blame fixture의 긴 제목 하나는 말줄임 검수에 사용합니다.

- [ ] **Step 2: 최종 보완 전용 시각 테스트를 추가합니다**

`test/full_diff_visual_test.dart`에 다음 여섯 캡처를 추가합니다.

| 이름 | 크기 | 상태 |
|---|---:|---|
| `18-final-default` | 1070×842 | 두 열, 크기, 첫·둘째 머리글 |
| `19-final-history` | 1070×842 | History 도움말, 선택 반전, 상세 diff |
| `20-final-blame` | 1440×842 | 아바타·줄 번호·제목·날짜·rail·소스 |
| `21-final-focus` | 1070×842 | 집중 모드와 머리글 버튼 순서 |
| `22-final-responsive-650` | 650×549 | 파일 + 콘텐츠 |
| `23-final-responsive-480` | 480×549 | 콘텐츠만 표시 |

History 캡처는 마우스를 History 버튼에 올려 tooltip이 보인 상태로
찍습니다. Blame 캡처는 원격 서비스 없이 이니셜 fallback을 사용해
네트워크와 무관하게 결정적인 이미지를 만듭니다.

- [ ] **Step 3: 기존 시각 회귀가 의도대로 실패하는지 확인합니다**

Run:

```bash
flutter test test/full_diff_visual_test.dart --reporter expanded
```

Expected: 제품 배치가 바뀐 기존 이미지와 아직 생성하지 않은
18~23 이미지가 golden mismatch 또는 missing golden으로 실패

- [ ] **Step 4: 승인 시안과 대조한 뒤 기준 캡처를 갱신합니다**

Run:

```bash
flutter test --update-goldens test/full_diff_visual_test.dart --reporter expanded
```

다음 항목을 `full-diff-final-polish-mockup.svg`와 나란히 확인합니다.

- `집중 모드` 바로 오른쪽에 `편집기로 열기`
- `diff 알고리즘` 라벨과 선택값 메뉴 분리
- 설정, Hunk 탐색, Hunk·Inline·Split 그룹 순서
- 주변 커밋 열 없음
- 파일 이름에 회색 칩 없음
- 파일 이름과 크기 보조 줄의 정렬
- History 선택 반전과 빗금 경계
- Blame의 여섯 열과 4px rail
- 650px의 파일 열, 480px의 콘텐츠 단독 표시

실제 데이터에 따라 바뀌는 문자열을 제외하고 승인 시안과 버튼 위치,
색, 글자 크기, 테두리나 간격이 1px보다 크게 다르면 구현을 조정하고
다시 캡처합니다.

- [ ] **Step 5: 시각 회귀를 다시 확인합니다**

Run:

```bash
flutter test test/full_diff_visual_test.dart --reporter expanded
```

Expected: 기존 이미지와 18~23 이미지가 모두 통과

- [ ] **Step 6: 포맷, 정적 분석과 전체 테스트를 실행합니다**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter test --dart-define=YOGIT_EXTENDED_SYNTAX=false
flutter test --concurrency=1 benchmark/full_diff_syntax_benchmark_test.dart --reporter expanded
flutter build macos --release
```

Expected:

- Dart format 변경 0
- 정적 분석 문제 0
- 기본·축소 syntax 전체 테스트 통과
- syntax benchmark 기준 통과
- macOS release build 성공

- [ ] **Step 7: placeholder와 타입 일관성을 검사합니다**

Run:

```bash
rg -n "TODO|FIXME|placeholder|not implemented|임시 구현" lib test docs/superpowers/verification/full-diff-qa
rg -n "GitBlameLine\\(|BlameLine\\(|GitFileChange\\(" lib test
git diff --check
```

Expected:

- 이번 구현에서 추가한 placeholder 없음
- 모든 새 모델 생성자가 호환 가능한 기본값 또는 실제 값을 사용
- trailing whitespace와 공백 오류 없음

- [ ] **Step 8: 독립 검토 문서를 작성합니다**

`docs/superpowers/verification/full-diff-qa/final-polish-review.md`에
다음을 기록합니다.

1. 설계의 완료 기준별 구현 파일과 테스트 이름
2. 파일 크기 Git 호출 수와 실패 격리 결과
3. History 포커스·선택 상태와 키보드 조합 결과
4. Blame 줄 수·열 순서·fallback 아바타 결과
5. 18~23 이미지의 크기와 수동 판정
6. 전체 테스트 수, 분석, benchmark와 release build 결과
7. 남은 P0~P3 지적 사항 또는 `없음`

`docs/superpowers/verification/full-diff-qa/README.md`에는 18~23 이미지
링크와 판정 요약을 추가합니다.

- [ ] **Step 9: 최종 검증 자료를 커밋합니다**

```bash
git add test/support/full_diff_qa_harness.dart test/full_diff_visual_test.dart docs/superpowers/verification/full-diff-qa
git commit -m "test: verify full diff final polish"
```

- [ ] **Step 10: 마지막 상태를 확인합니다**

Run:

```bash
git status --short
git log --oneline -6
```

Expected: 작업 트리가 깨끗하고 이 계획의 여섯 커밋이 순서대로 표시

---

## 빠른 실행 순서

1. Task 1과 Task 2에서 Git·모델 계약을 먼저 고정합니다.
2. Task 3은 머리글과 글자 크기, Task 4는 작업 영역과 포커스,
   Task 5는 Blame을 각각 독립 커밋으로 끝냅니다.
3. 각 Task에서는 관련 테스트만 실행합니다.
4. Task 6에서만 전체 테스트, 두 syntax 구성, benchmark, 시각 캡처와
   release build를 실행합니다.
5. 구현 중 실패가 생기면 해당 Task의 마지막 통과 커밋으로 범위를
   좁혀 수정하며, 다른 완료 Task를 되돌리지 않습니다.

