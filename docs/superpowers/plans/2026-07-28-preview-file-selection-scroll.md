# Preview File Selection Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 타임라인 미리보기에서 `⌘↑/↓`로 파일을 이동할 때 선택 행이 파일 목록 화면 안에 남도록 스크롤을 함께 조정한다.

**Architecture:** 선택된 미리보기 파일 행 하나에만 `GlobalKey`를 붙이고 키보드 이동이 끝난 다음 프레임에 `Scrollable.ensureVisible`을 호출한다. 이동 방향에 따라 가까운 위·아래 가장자리에만 맞추며 마우스 선택 경로에는 이 동작을 연결하지 않는다.

**Tech Stack:** Flutter, Dart, Flutter widget tests

## Global Constraints

- 선택 행이 이미 보이면 파일 목록을 움직이지 않는다.
- 아래로 이동하면 행의 아래쪽을, 위로 이동하면 행의 위쪽을 화면에 맞춘다.
- 일반 키 입력은 100ms 애니메이션을 사용하고 반복 입력은 즉시 이동한다.
- 마우스로 파일을 선택하면 파일 목록의 현재 스크롤 위치를 유지한다.
- 파일을 바꾸면 코드 diff를 맨 위로 돌리는 기존 동작을 유지한다.
- 목록의 처음과 끝에서는 선택과 파일 목록 스크롤을 더 움직이지 않는다.
- 일반 `↑/↓` 커밋 이동과 Full Diff 파일 목록 동작은 바꾸지 않는다.
- 새 패키지를 추가하지 않는다.

---

## File Structure

- Modify: `lib/timeline.dart`
  - 키보드 입력이 일반 입력인지 반복 입력인지 파일 이동 경로에 전달한다.
  - 선택된 파일 행의 `GlobalKey`를 보관하고 다음 프레임에 해당 행을 화면 안으로 옮긴다.
  - 마우스 클릭과 키보드 이동의 스크롤 동작을 구분한다.
- Modify: `test/app_test.dart`
  - 화면보다 긴 파일 목록에서 아래·위 키보드 이동과 마우스 선택을 검증한다.

### Task 1: Keep the keyboard-selected preview file visible

**Files:**
- Modify: `lib/timeline.dart:400-402`
- Modify: `lib/timeline.dart:802-813`
- Modify: `lib/timeline.dart:2868-2890`
- Modify: `lib/timeline.dart:3197-3204`
- Test: `test/app_test.dart:9107-9223`

**Interfaces:**
- Consumes:
  - `_previewFilesScrollController`
  - `_previewPaths`
  - `Scrollable.ensureVisible(BuildContext, {double alignment, Duration duration, Curve curve, ScrollPositionAlignmentPolicy alignmentPolicy})`
- Produces:
  - `final GlobalKey _selectedPreviewFileKey`
  - `void _stepPreviewFile(int delta, {bool animate = true})`
  - `void _selectPreviewFile(GitCommit commit, String path, {int? revealDirection, bool animateReveal = true})`
  - `void _revealSelectedPreviewFile(int direction, {required bool animate})`

- [ ] **Step 1: Write the failing visibility and pointer-preservation test**

Add this test after `meta arrows walk the open preview through its files` in
`test/app_test.dart`:

```dart
testWidgets('preview keyboard file walking keeps the selected row visible', (
  tester,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 600);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    app(
      FakeGitRepository(
        (_, _) async => [commit('1', 'many changed files')],
        files: (_, _) async => [
          for (var index = 0; index < 20; index++)
            GitFileChange(
              path: 'lib/file$index.dart',
              status: 'M',
              additions: 1,
              deletions: 0,
            ),
        ],
        diff: (_, _, path, _, _) async => [
          DiffLine(
            kind: DiffLineKind.add,
            text: 'body of $path',
            newNumber: 1,
          ),
        ],
      ),
      controller,
    ),
  );
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();

  final filesViewport = find.byKey(const Key('preview-files-scroll'));
  final filesPosition = tester
      .state<ScrollableState>(
        find.descendant(
          of: filesViewport,
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  Future<void> metaArrow(LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  Finder fileRow(String path) => find.ancestor(
    of: find.byKey(Key('preview-state-$path')),
    matching: find.byType(InkWell),
  );

  void expectRowVisible(String path) {
    final viewportRect = tester.getRect(filesViewport);
    final rowRect = tester.getRect(fileRow(path));
    expect(rowRect.top, greaterThanOrEqualTo(viewportRect.top - 0.5));
    expect(rowRect.bottom, lessThanOrEqualTo(viewportRect.bottom + 0.5));
  }

  for (var index = 0; index < 15; index++) {
    await metaArrow(LogicalKeyboardKey.arrowDown);
  }
  expect(filesPosition.pixels, greaterThan(0));
  expectRowVisible('lib/file15.dart');

  final downOffset = filesPosition.pixels;
  await metaArrow(LogicalKeyboardKey.arrowUp);
  expect(filesPosition.pixels, moreOrLessEquals(downOffset));
  expectRowVisible('lib/file14.dart');

  for (var index = 0; index < 14; index++) {
    await metaArrow(LogicalKeyboardKey.arrowUp);
  }
  expect(filesPosition.pixels, lessThan(downOffset));
  expectRowVisible('lib/file0.dart');

  final pointerOffset = filesPosition.pixels;
  await tester.tap(find.byKey(const Key('preview-state-lib/file1.dart')));
  await tester.pumpAndSettle();
  expect(filesPosition.pixels, moreOrLessEquals(pointerOffset));
  expect(find.text('+body of lib/file1.dart'), findsOneWidget);
});
```

- [ ] **Step 2: Run the new test and verify the current behavior fails**

Run:

```bash
flutter test test/app_test.dart \
  --plain-name "preview keyboard file walking keeps the selected row visible"
```

Expected: FAIL when `lib/file15.dart` is selected because
`filesPosition.pixels` remains `0` and the selected row lies below the file
viewport.

- [ ] **Step 3: Add one retained key for the selected preview row**

In `_TimelineScreenState`, add the key beside the preview scroll controllers:

```dart
final _previewFilesScrollController = ScrollController();
final _previewDiffScrollController = ScrollController();
final _selectedPreviewFileKey = GlobalKey(
  debugLabel: 'selected preview file',
);
```

Add the key between the existing `SizedBox` opening and `height`:

```diff
 Widget _previewFileRow(
   GitCommit commit,
   GitFileChange file,
   bool selected,
 ) => SizedBox(
+  key: selected ? _selectedPreviewFileKey : null,
   height: 28,
```

This attaches the retained key only to the selected row. The existing
`InkWell`, row layout, and pointer callback remain unchanged.

- [ ] **Step 4: Pass key-repeat timing through the preview file walk**

Update the Meta-arrow branch in `_onKeyEvent`:

```dart
if (_previewController.previewPlacement != PreviewPlacement.closed) {
  _stepPreviewFile(step, animate: event is KeyDownEvent);
}
```

Update `_stepPreviewFile` so an end-of-list input has no side effect and a real
move carries the direction and timing:

```dart
void _stepPreviewFile(int delta, {bool animate = true}) {
  final commit = _selectedCommit;
  if (commit == null) return;
  final files = _previewFileLists[commit.sha];
  if (files == null || files.isEmpty) return;
  final current = _previewPaths[commit.sha] ?? files.first.path;
  final index = files.indexWhere((file) => file.path == current);
  final next = (index + delta).clamp(0, files.length - 1);
  if (files[next].path == current) return;
  _selectPreviewFile(
    commit,
    files[next].path,
    revealDirection: delta,
    animateReveal: animate,
  );
}
```

- [ ] **Step 5: Reveal only keyboard-selected rows after layout**

Extend `_selectPreviewFile` and add the focused reveal helper:

```dart
void _selectPreviewFile(
  GitCommit commit,
  String path, {
  int? revealDirection,
  bool animateReveal = true,
}) {
  setState(() => _previewPaths[commit.sha] = path);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (_previewDiffScrollController.hasClients) {
      _previewDiffScrollController.jumpTo(0);
    }
    if (revealDirection != null) {
      _revealSelectedPreviewFile(
        revealDirection,
        animate: animateReveal,
      );
    }
  });
}

void _revealSelectedPreviewFile(
  int direction, {
  required bool animate,
}) {
  final selectedContext = _selectedPreviewFileKey.currentContext;
  if (selectedContext == null) return;
  unawaited(
    Scrollable.ensureVisible(
      selectedContext,
      duration: animate
          ? const Duration(milliseconds: 100)
          : Duration.zero,
      curve: Curves.easeOut,
      alignmentPolicy: direction < 0
          ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
          : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    ),
  );
}
```

The pointer callback remains
`onTap: () => _selectPreviewFile(commit, file.path)`. It does not provide a
direction, so it preserves the file-list offset while still resetting the diff
offset.

- [ ] **Step 6: Format and run the focused test**

Run:

```bash
dart format lib/timeline.dart test/app_test.dart
flutter test test/app_test.dart \
  --plain-name "preview keyboard file walking keeps the selected row visible"
```

Expected: PASS. The selected row stays inside the file viewport in both
directions and pointer selection keeps the current file-list offset.

- [ ] **Step 7: Run related preview interaction tests**

Run:

```bash
flutter test test/app_test.dart \
  --name "preview file and diff panes scroll independently|preview shortcuts scroll and distinguish identities|meta arrows walk the open preview through its files|preview keyboard file walking keeps the selected row visible"
```

Expected: all matching tests PASS.

- [ ] **Step 8: Run static analysis and the full test suite**

Run:

```bash
flutter analyze
flutter test
```

Expected: both commands exit with status `0`.

- [ ] **Step 9: Review the diff and commit the implementation**

Run:

```bash
git diff --check
git diff -- lib/timeline.dart test/app_test.dart
git add lib/timeline.dart test/app_test.dart
git commit -m "fix: keep preview file selection visible"
```

Expected: the commit contains only the preview selection scroll implementation
and its widget test. The user's existing changes under
`docs/superpowers/plans/2026-07-27-full-diff-hunk-workspace.md` and
`.superpowers/brainstorm/` remain untouched.
