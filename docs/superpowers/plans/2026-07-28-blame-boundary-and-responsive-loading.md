# Blame Boundary and Responsive Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Blame 커밋 카드를 메타데이터 열 안에 가두고, Git이 Blame을 계산하는 동안에도 소스 코드와 키보드 탐색을 바로 사용할 수 있게 한다.

**Architecture:** `FullBlameView`가 행과 카드에 같은 메타데이터 폭 계산을 사용하게 한다. 파일 내용이 준비됐지만 Blame 결과가 없는 동안에는 같은 상태 객체를 유지하는 `FullBlameView.loading`을 표시한다. `DiffScreen`은 로딩 화면도 Blame 탐색 대상으로 보고 오른쪽 이동 의도를 보존한다.

**Tech Stack:** Flutter, Dart, Material widgets, `flutter_test`, Git subprocess integration

## Global Constraints

- 커밋 카드의 오른쪽 끝은 선택 행의 `blame-rail-<line>` 왼쪽 경계를 넘지 않는다.
- 커밋 카드는 현재처럼 아바타 열 오른쪽에서 시작한다.
- Blame 메타데이터 열의 현재 폭 규칙은 바꾸지 않는다.
- 파일 내용이 준비되면 Git Blame 계산을 기다리지 않고 소스 코드와 줄 번호를 표시한다.
- 계산 중인 Blame 화면에서도 화살표와 `h`·`j`·`k`·`l` 탐색을 지원한다.
- Blame 결과가 도착해도 선택한 줄, 포커스, 스크롤 위치를 유지한다.
- 실제 Blame 메타데이터가 없을 때는 커밋 정보 카드를 표시하지 않는다.
- `GitRepository.loadBlame`, `_blameCache`, 늦은 요청 차단 방식은 바꾸지 않는다.
- 인접 파일을 미리 계산하거나 Git 요청을 추가하지 않는다.
- 파일 History의 커밋 카드 동작은 바꾸지 않는다.
- 별도 계획의 긴 커밋 메시지 스크롤과 충돌하지 않도록 `lib/full_diff_commit_info_card.dart`는 수정하지 않는다.
- 새 패키지를 추가하지 않는다.
- 사용자가 수정한 `docs/superpowers/plans/2026-07-27-full-diff-hunk-workspace.md`와 `.superpowers/brainstorm/`은 건드리거나 커밋하지 않는다.

---

## File Structure

- `lib/full_blame_view.dart`: 메타데이터 폭, 카드 배치, 계산 중 행, Blame 목록의 선택과 키보드 상태를 담당한다.
- `lib/diff_screen.dart`: 컨트롤러 상태에 맞는 Blame 화면을 고르고 파일 목록과 Blame 목록 사이의 포커스를 연결한다.
- `test/full_diff_content_views_test.dart`: `FullBlameView`의 카드 경계와 계산 중 상태 전환을 검증한다.
- `test/full_diff_workspace_test.dart`: 실제 `DiffScreen`에서 Blame 요청을 지연시킨 채 포커스와 선택이 유지되는지 검증한다.

---

### Task 1: 커밋 카드를 Blame 메타데이터 열 안에 제한

**Files:**
- Modify: `lib/full_blame_view.dart:16-17`
- Modify: `lib/full_blame_view.dart:175-211`
- Modify: `lib/full_blame_view.dart:405-493`
- Test: `test/full_diff_content_views_test.dart:1918-1970`

**Interfaces:**
- Consumes: `fullBlameAvatarWidth`, `BlameSourceRow.viewportWidth`
- Produces: `fullBlameRailWidth`, `fullBlameMetadataWidth(double viewportWidth)`
- Produces: 메타데이터 색상선 앞에서 끝나는 Blame 커밋 카드

- [ ] **Step 1: 카드 경계를 메타데이터 색상선으로 바꾸는 실패 테스트 작성**

`test/full_diff_content_views_test.dart`의
`narrow blame keeps the offset commit card inside the list viewport`를
`blame commit card stops before the metadata rail`로 이름을 바꾼다. 300px
화면의 카드 검사에 다음 색상선 경계를 추가한다.

```dart
final rail = tester.getRect(
  find.byKey(const Key('blame-rail-1')),
);
expect(card.left, closeTo(numberColumn.left, 0.5));
expect(card.right, lessThanOrEqualTo(rail.left + 0.5));
expect(fullBlameMetadataWidth(300), 250);
```

같은 테스트에서 화면을 1000px로 늘린 뒤에도 전체 화면이 아니라 색상선
경계를 검사한다.

```dart
final wideCard = tester.getRect(
  find.byKey(const Key('blame-commit-details-1')),
);
final wideRail = tester.getRect(
  find.byKey(const Key('blame-rail-1')),
);
final wideNumberColumn = tester.getRect(
  find.byKey(const Key('blame-line-number-1')),
);
expect(wideCard.left, closeTo(wideNumberColumn.left, 0.5));
expect(wideCard.right, lessThanOrEqualTo(wideRail.left + 0.5));
expect(fullBlameMetadataWidth(1000), 360);
expect(tester.takeException(), isNull);
```

기존 `viewport.right`와 `viewport.width - fullBlameAvatarWidth` 검사는
삭제한다. 새 검사가 더 엄격한 실제 경계를 확인한다.

- [ ] **Step 2: 현재 코드에서 카드 경계 테스트가 실패하는지 확인**

Run:

```bash
flutter test test/full_diff_content_views_test.dart --plain-name "blame commit card stops before the metadata rail"
```

Expected: 현재 300px 카드의 오른쪽은 화면 오른쪽 부근이고 1000px 카드의
폭은 최대 420px이므로 두 경우 모두 색상선의 왼쪽을 넘어 FAIL.

- [ ] **Step 3: 메타데이터 폭과 색상선 폭을 한곳에 정의**

`lib/full_blame_view.dart`의 아바타 폭 상수 아래에 다음 값을 추가한다.

```dart
const fullBlameAvatarWidth = 20.0;
const fullBlameRailWidth = 1.0;

double fullBlameMetadataWidth(double viewportWidth) => viewportWidth >= 900
    ? 360.0
    : (viewportWidth * 0.38).clamp(250.0, 320.0).toDouble();
```

`BlameSourceRow.build` 안의 기존 계산을 함수 호출로 바꾼다.

```dart
final metadataWidth = fullBlameMetadataWidth(viewportWidth);
```

색상선의 `width: 1`도 공통 상수로 바꾼다.

```dart
width: fullBlameRailWidth,
```

- [ ] **Step 4: 카드가 사용할 수 있는 폭을 색상선 앞까지로 제한**

`FullBlameViewState.build`의 `LayoutBuilder` 안에서 카드 폭을 계산한다.

```dart
final metadataWidth = fullBlameMetadataWidth(constraints.maxWidth);
final cardWidth =
    (metadataWidth - fullBlameAvatarWidth - fullBlameRailWidth)
        .clamp(0.0, double.infinity)
        .toDouble();
```

커밋 카드를 감싸는 `SizedBox`의 폭을 다음과 같이 바꾼다.

```diff
- width: constraints.maxWidth <= fullBlameAvatarWidth
-     ? 0
-     : constraints.maxWidth - fullBlameAvatarWidth,
+ width: cardWidth,
```

`FullDiffCommitInfoCard`의 자체 최대 폭은 그대로 둔다.

- [ ] **Step 5: 카드 경계와 기존 Blame 화면 테스트 통과 확인**

Run:

```bash
flutter test test/full_diff_content_views_test.dart --plain-name "blame commit card stops before the metadata rail"
flutter test test/full_diff_content_views_test.dart --plain-name "blame rows expose one exact semantics label"
flutter test test/full_diff_visual_test.dart --plain-name "blame renders aligned metadata columns and source"
```

Expected: 세 테스트가 모두 PASS하고 레이아웃 예외가 없음.

- [ ] **Step 6: 카드 경계 변경 커밋**

```bash
git add lib/full_blame_view.dart test/full_diff_content_views_test.dart
git commit -m "fix: contain blame commit card"
```

---

### Task 2: Blame 계산 중에도 소스 목록 표시

**Files:**
- Modify: `lib/full_blame_view.dart:19-225`
- Modify: `lib/full_blame_view.dart:398-533`
- Test: `test/full_diff_content_views_test.dart`

**Interfaces:**
- Consumes: `FileDocument`, `BlameDocument`, 외부 `FocusNode`, 외부 `ScrollController`
- Produces: `FileDocument`를 받는 `FullBlameView.loading` named constructor
- Produces: `FullBlameView.file`, `FullBlameView.lines`
- Produces: 로딩 행 키 `blame-loading-<line>`

- [ ] **Step 1: 같은 위젯 상태에서 로딩 결과를 교체하는 테스트 호스트 추가**

`test/full_diff_content_views_test.dart`의 파일 아래쪽에 다음 호스트를
추가한다. 두 화면은 같은 `ValueKey`와 같은 포커스·스크롤 컨트롤러를
사용한다.

```dart
class _LoadingBlameHost extends StatefulWidget {
  const _LoadingBlameHost({
    required this.file,
    required this.loaded,
    required this.focusNode,
    required this.scrollController,
    super.key,
  });

  final FileDocument file;
  final BlameDocument loaded;
  final FocusNode focusNode;
  final ScrollController scrollController;

  @override
  State<_LoadingBlameHost> createState() => _LoadingBlameHostState();
}

class _LoadingBlameHostState extends State<_LoadingBlameHost> {
  var _loaded = false;

  void complete() => setState(() => _loaded = true);

  @override
  Widget build(BuildContext context) {
    final key = ValueKey((
      widget.file.revision,
      widget.file.path,
      widget.file.side,
      widget.file.fingerprint,
    ));
    final commonAnchorKeys = <String, GlobalKey>{};
    return _loaded
        ? FullBlameView(
            key: key,
            document: widget.loaded,
            hunks: const [],
            activeAnchor: null,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: commonAnchorKeys,
            controller: widget.scrollController,
            focusNode: widget.focusNode,
            showRemoteAvatars: false,
          )
        : FullBlameView.loading(
            key: key,
            file: widget.file,
            hunks: const [],
            activeAnchor: null,
            wrapLines: false,
            highlighter: fakeHighlighter,
            anchorKeys: commonAnchorKeys,
            controller: widget.scrollController,
            focusNode: widget.focusNode,
            showRemoteAvatars: false,
          );
  }
}
```

- [ ] **Step 2: 로딩 중 선택·포커스·스크롤을 결과 화면이 이어받는 실패 테스트 작성**

`test/full_diff_content_views_test.dart`에 다음 테스트를 추가한다.

```dart
testWidgets('loaded blame keeps loading selection focus and scroll', (
  tester,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 220);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  final focusNode = FocusNode();
  final scrollController = ScrollController();
  final hostKey = GlobalKey<_LoadingBlameHostState>();
  addTearDown(focusNode.dispose);
  addTearDown(scrollController.dispose);

  final file = FileDocument.fromBytes(
    revision: commitA.sha,
    path: 'loading.dart',
    side: FileDocumentSide.result,
    bytes: Uint8List.fromList(
      utf8.encode(
        '${List.generate(40, (index) => 'source ${index + 1}').join('\n')}\n',
      ),
    ),
    gitMarkedBinary: false,
  );
  final loaded = BlameDocument.fromGitLines(file, [
    for (var line = 1; line <= file.lines.length; line++)
      GitBlameLine(
        lineNumber: line,
        sha: '40aff6d123456789',
        author: 'Suwon Chae',
        summary: 'Loaded summary $line',
        uncommitted: false,
      ),
  ]);

  await tester.pumpWidget(
    qaApp(
      _LoadingBlameHost(
        key: hostKey,
        file: file,
        loaded: loaded,
        focusNode: focusNode,
        scrollController: scrollController,
      ),
    ),
  );

  scrollController.jumpTo(fullDiffSourceRowHeight * 4);
  await tester.pump();
  await tester.tap(find.byKey(const Key('blame-line-6')));
  await tester.pump();
  final beforeScroll = scrollController.position.pixels;

  expect(focusNode.hasFocus, isTrue);
  expect(find.byKey(const Key('blame-selected-6')), findsOneWidget);
  expect(find.byKey(const Key('blame-loading-6')), findsOneWidget);
  expect(find.byKey(const Key('blame-commit-details-6')), findsNothing);

  hostKey.currentState!.complete();
  await tester.pump();

  expect(focusNode.hasFocus, isTrue);
  expect(find.byKey(const Key('blame-selected-6')), findsOneWidget);
  expect(find.byKey(const Key('blame-loading-6')), findsNothing);
  expect(find.text('Loaded summary 6'), findsOneWidget);
  expect(find.byKey(const Key('blame-commit-details-6')), findsOneWidget);
  expect(scrollController.position.pixels, closeTo(beforeScroll, 0.5));
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 3: 새 로딩 테스트가 현재 코드에서 실패하는지 확인**

Run:

```bash
flutter test test/full_diff_content_views_test.dart --plain-name "loaded blame keeps loading selection focus and scroll"
```

Expected: `FullBlameView.loading` 생성자가 없어서 컴파일 단계에서 FAIL.

- [ ] **Step 4: `FullBlameView`가 준비된 행과 로딩 행을 같은 상태로 표시하게 변경**

기본 생성자가 기존 `BlameDocument`를 `file`과 `lines`로 나눠 보관하게 한다.
기존 호출부는 바뀌지 않는다.

```dart
FullBlameView({
  required BlameDocument document,
  required this.hunks,
  required this.activeAnchor,
  required this.wrapLines,
  required this.highlighter,
  required this.anchorKeys,
  this.onAnchorProbeAttached,
  this.onAnchorProbeDetached,
  this.controller,
  this.avatarService,
  this.showRemoteAvatars = true,
  this.focusNode,
  this.onMoveToFiles,
  this.loadCommitMessage,
  super.key,
}) : file = document.file,
     lines = document.lines;

FullBlameView.loading({
  required this.file,
  required this.hunks,
  required this.activeAnchor,
  required this.wrapLines,
  required this.highlighter,
  required this.anchorKeys,
  this.onAnchorProbeAttached,
  this.onAnchorProbeDetached,
  this.controller,
  this.avatarService,
  this.showRemoteAvatars = true,
  this.focusNode,
  this.onMoveToFiles,
  this.loadCommitMessage,
  super.key,
}) : lines = null;

final FileDocument file;
final List<BlameLine>? lines;
```

`FullBlameViewState`에서 `widget.document.file`은 `widget.file`로 바꾼다.
선택한 줄의 실제 Blame이 준비됐을 때만 카드를 만든다.

```dart
final lines = widget.lines;
final selectedBlame = selectedLine == null || lines == null
    ? null
    : lines[selectedLine - 1];
```

행을 만들 때 로딩 중이면 `blame`에 `null`을 넘긴다.

```dart
final blame = lines?[index];
BlameSourceRow(
  blame: blame,
  lineNumber: lineNumber,
  source: widget.file.lines[index],
  path: widget.file.path,
  side: widget.file.side,
  kind: sourceMap.kindForLine(lineNumber),
  wrapLines: widget.wrapLines,
  highlighter: widget.file.disableRichRendering
      ? const _NoopSyntaxHighlighter()
      : widget.highlighter,
  current: current,
  hovered: lineNumber == _hoveredLine,
  selected: selected,
  viewportWidth: constraints.maxWidth,
  avatarService: widget.avatarService,
  showRemoteAvatars: widget.showRemoteAvatars,
)
```

- [ ] **Step 5: `BlameSourceRow`에 낮은 강조도의 로딩 메타데이터 추가**

`BlameSourceRow.blame`을 nullable로 바꾸고 실제 값이 없을 때 다음 표현을
사용한다.

필드 선언은 nullable로 바꾼다.

```dart
final BlameLine? blame;
```

`build`를 시작할 때 지역 변수로 받아 상태별 표시 값을 정한다.

```dart
final blame = this.blame;
final loading = blame == null;
final summary = loading ? 'Blame 계산 중…' : blame.summary;
final date = loading ? '' : _formatDate(blame.authorTimestamp);
final railColor = loading
    ? fullDiffMuted.withValues(alpha: 0.35)
    : _railColor(blame.sha);
```

요약 텍스트는 상태에 따라 키를 나눈다.

```dart
Text(
  summary,
  key: loading
      ? Key('blame-loading-$lineNumber')
      : Key('blame-summary-$lineNumber'),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(
    color: loading ? fullDiffMuted : null,
    fontSize: 12,
  ),
)
```

`_avatar()`는 `blame == null`이면 원격 조회를 시작하지 않고 빈 상자를
반환한다.

```dart
final blame = this.blame;
if (blame == null) {
  return SizedBox(key: Key('blame-avatar-$lineNumber'));
}
```

`_semanticsLabel`도 nullable 값을 받아 로딩 상태를 분명히 한다.

```dart
String _semanticsLabel(int lineNumber, BlameLine? blame) {
  if (blame == null) return 'Line $lineNumber, Blame loading';
  final summary = blame.summary.trim();
  if (summary.isNotEmpty) return 'Line $lineNumber, $summary';
  return 'Line $lineNumber, ${_shortSha(blame.sha)}, ${blame.author}';
}
```

- [ ] **Step 6: 로딩 상태 전환과 기존 Blame 행 테스트 통과 확인**

Run:

```bash
flutter test test/full_diff_content_views_test.dart --plain-name "loaded blame keeps loading selection focus and scroll"
flutter test test/full_diff_content_views_test.dart --plain-name "blame focus selects, navigates, and returns to files"
flutter test test/full_diff_content_views_test.dart --plain-name "blame retains a constant number of row GlobalKeys"
flutter test test/full_diff_content_views_test.dart --plain-name "blame rows expose one exact semantics label"
```

Expected: 네 테스트가 모두 PASS. 로딩 화면은 원격 아바타나 커밋 메시지를
요청하지 않음.

- [ ] **Step 7: 계산 중 Blame 화면 커밋**

```bash
git add lib/full_blame_view.dart test/full_diff_content_views_test.dart
git commit -m "feat: show blame source while loading"
```

---

### Task 3: 파일 목록에서 계산 중 Blame으로 포커스 이동

**Files:**
- Modify: `lib/diff_screen.dart:340-375`
- Modify: `lib/diff_screen.dart:715-815`
- Modify: `lib/diff_screen.dart:835-885`
- Modify: `lib/diff_screen.dart:1677-1704`
- Test: `test/full_diff_workspace_test.dart:3100-3325`

**Interfaces:**
- Consumes: `FullDiffSessionState.file`, `FullDiffSessionState.blame`, `FullBlameView.loading`
- Produces: `_blameDetailConnected(FullDiffSessionState state)`
- Produces: 오른쪽 화살표와 `l` 한 번으로 계산 중 Blame에 들어가는 포커스 흐름

- [ ] **Step 1: 지연된 Blame에도 오른쪽 이동이 즉시 반응하는 실패 테스트 작성**

`test/full_diff_workspace_test.dart`에 다음 테스트를 추가한다.

```dart
testWidgets('right enters source while blame metadata is loading', (
  tester,
) async {
  final pendingBlame = Completer<List<GitBlameLine>>();
  final repository = FakeFullDiffRepository()
    ..files = ((_, _) async => const [_sizedFile])
    ..diff = ((_, _, _, _, _) async => const [])
    ..content = ((_, _, _) async => resultFile.bytes)
    ..blame = ((_, _, _, _) => pendingBlame.future);
  final controller = FullDiffSessionController(
    repository: repository,
    commits: const [commitA],
    initialIndex: 0,
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  controller.setPrimaryView(FullDiffView.blame);
  await pumpWorkspace(
    tester,
    controller: controller,
    size: const Size(1070, 842),
    settle: false,
  );
  await tester.pump();

  final filesFocus = tester.widget<Focus>(
    find.byKey(const Key('changed-files-focus')),
  );
  filesFocus.focusNode!.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.pump();

  final blameFocus = tester.widget<Focus>(
    find.byKey(const Key('blame-list-focus')),
  );
  expect(blameFocus.focusNode!.hasFocus, isTrue);
  expect(find.byKey(const Key('blame-loading-1')), findsOneWidget);
  expect(find.byKey(const Key('blame-selected-1')), findsOneWidget);

  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pump();
  expect(find.byKey(const Key('blame-selected-2')), findsOneWidget);

  pendingBlame.complete([
    for (var index = 0; index < resultFile.lines.length; index++)
      GitBlameLine(
        lineNumber: index + 1,
        sha: commitA.sha,
        author: fixtureIdentity.name,
        summary: 'Loaded line ${index + 1}',
        uncommitted: false,
      ),
  ]);
  await tester.pumpAndSettle();

  expect(blameFocus.focusNode!.hasFocus, isTrue);
  expect(find.byKey(const Key('blame-selected-2')), findsOneWidget);
  expect(find.text('Loaded line 2'), findsOneWidget);
  expect(find.byKey(const Key('blame-loading-2')), findsNothing);
});
```

같은 테스트에서 파일 목록으로 돌아온 뒤 `l`도 같은 결과를 내는지 추가한다.

```dart
await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
await tester.pump();
expect(filesFocus.focusNode!.hasFocus, isTrue);
await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
await tester.pump();
expect(blameFocus.focusNode!.hasFocus, isTrue);
```

- [ ] **Step 2: 현재 화면에서 지연 포커스 테스트가 실패하는지 확인**

Run:

```bash
flutter test test/full_diff_workspace_test.dart --plain-name "right enters source while blame metadata is loading"
```

Expected: 현재 `_blameContent`는 Blame 결과가 없을 때 로딩 문구만
표시하므로 `blame-list-focus`를 찾지 못해 FAIL.

- [ ] **Step 3: 로딩 Blame도 포커스를 받을 수 있는 대상으로 판정**

`_DiffScreenState`에 다음 도우미를 추가한다.

```dart
bool _blameDetailConnected(FullDiffSessionState state) =>
    state.view == FullDiffView.blame &&
    state.file.data?.kind == FileContentKind.utf8 &&
    (_blameListFocus.context?.mounted ?? false);
```

`_handleFileListFocusChanged`와 `_restoreNavigationFocus`에서
`state.blame.data` 검사 대신 이 도우미를 사용한다. 사용자가 로딩 목록에서
`h`로 파일 목록에 돌아오면 `_lastBlameNavigationPane`이 `files`로 바뀌어
이후 프레임이 포커스를 다시 빼앗지 않게 한다.

```dart
case FullDiffView.blame:
  if (_blameDetailConnected(_controller.state)) {
    _lastBlameNavigationPane = _FullDiffNavigationPane.files;
  }
```

```dart
final blameConnected = _blameDetailConnected(_controller.state);
```

- [ ] **Step 4: 파일 내용이 도착하는 프레임에도 포커스 복원 예약**

`_handleControllerChanged`에서 Blame 데이터뿐 아니라 파일 데이터가
준비될 때도 포커스 복원을 예약한다.

```dart
final blameFileBecameReady =
    previous.file.data == null &&
    next.file.data?.kind == FileContentKind.utf8 &&
    next.view == FullDiffView.blame;
if (blameFileBecameReady ||
    (!identical(previous.blame.data, next.blame.data) &&
        next.view == FullDiffView.blame)) {
  _restoreNavigationFocus();
}
```

오른쪽 이동키가 파일 내용보다 먼저 들어오면 다음 단계에서 기억한
`_lastBlameNavigationPane` 값에 따라 첫 로딩 화면 프레임에서 포커스가
Blame으로 간다.

- [ ] **Step 5: 오른쪽 화살표와 `l`이 Blame 이동 의도를 즉시 기록하게 변경**

`_handleFileListKey`의 Blame 분기에서 `event.logicalKey` 대신 이미 정규화한
`key`를 사용한다. 데이터 유무와 관계없이 이동 대상을 Blame으로 기억하고,
화면이 붙어 있으면 바로 포커스를 요청한다.

```dart
if (key == LogicalKeyboardKey.arrowRight &&
    _controller.state.view == FullDiffView.blame) {
  _lastBlameNavigationPane = _FullDiffNavigationPane.blame;
  if (_blameListFocus.context?.mounted ?? false) {
    _blameListFocus.requestFocus();
  }
  return KeyEventResult.handled;
}
```

- [ ] **Step 6: `DiffScreen`이 파일 내용부터 Blame 목록을 만들게 변경**

`_blameContent`는 실제 Blame이 있으면 기존 화면을 만들고, Blame을 읽는
중이며 UTF-8 파일 내용이 있으면 같은 파일 키로 로딩 화면을 만든다.

```dart
Widget _blameContent(FullDiffSessionState state) {
  final blame = state.blame.data;
  final file = blame?.file ?? state.file.data;
  if (file == null ||
      file.kind != FileContentKind.utf8 ||
      (blame == null && !state.blame.loading)) {
    return _resourceStatus(state.blame, 'Blame을 읽는 중입니다');
  }
  final key = ValueKey((
    file.revision,
    file.path,
    file.side,
    file.fingerprint,
  ));
  if (blame == null) {
    return FullBlameView.loading(
      key: key,
      file: file,
      hunks: state.patch.data?.hunks ?? const [],
      activeAnchor: state.activeAnchor,
      wrapLines: state.wrapLines,
      highlighter: _highlighter,
      anchorKeys: _anchorKeys,
      onAnchorProbeAttached: _attachAnchorProbe,
      onAnchorProbeDetached: _detachAnchorProbe,
      controller: _contentScroll,
      avatarService: widget.avatarService,
      showRemoteAvatars: widget.showRemoteAvatars,
      focusNode: _blameListFocus,
      onMoveToFiles: _fileListFocus.requestFocus,
      loadCommitMessage: _loadCommitMessage,
    );
  }
  return FullBlameView(
    key: key,
    document: blame,
    hunks: state.patch.data?.hunks ?? const [],
    activeAnchor: state.activeAnchor,
    wrapLines: state.wrapLines,
    highlighter: _highlighter,
    anchorKeys: _anchorKeys,
    onAnchorProbeAttached: _attachAnchorProbe,
    onAnchorProbeDetached: _detachAnchorProbe,
    controller: _contentScroll,
    avatarService: widget.avatarService,
    showRemoteAvatars: widget.showRemoteAvatars,
    focusNode: _blameListFocus,
    onMoveToFiles: _fileListFocus.requestFocus,
    loadCommitMessage: _loadCommitMessage,
  );
}
```

실패 상태와 비 UTF-8 파일은 기존 안내 화면을 유지한다.

- [ ] **Step 7: 기존 로딩 포커스 테스트를 새 동작에 맞게 강화**

`Blame line focus survives a loading fallback to Files` 테스트에서 두 번째
파일의 Blame을 기다리는 구간을 다음 기대값으로 바꾼다.

```dart
final selection = controller.selectFile(secondFile);
await tester.pump();
expect(find.byKey(const Key('blame-list-focus')), findsOneWidget);
expect(find.byKey(const Key('blame-loading-1')), findsOneWidget);
expect(
  tester
      .widget<Focus>(find.byKey(const Key('blame-list-focus')))
      .focusNode!
      .hasFocus,
  isTrue,
);
```

`pendingBlame.complete` 뒤의 기존 포커스, 선택 파일, 선택 줄 검사는 유지한다.

- [ ] **Step 8: 포커스 통합 테스트 통과 확인**

Run:

```bash
flutter test test/full_diff_workspace_test.dart --plain-name "right enters source while blame metadata is loading"
flutter test test/full_diff_workspace_test.dart --plain-name "Blame line focus survives a loading fallback to Files"
flutter test test/full_diff_workspace_test.dart --plain-name "Files and Blame lines move selection and focus explicitly"
flutter test test/full_diff_workspace_test.dart --plain-name "History and Blame restore their independent detail-list focus"
```

Expected: 네 테스트가 모두 PASS. 지연된 Blame은 한 번만 요청되고 계산 중
선택한 줄과 포커스가 결과 화면에 남음.

- [ ] **Step 9: 계산 중 포커스 연결 커밋**

```bash
git add lib/diff_screen.dart test/full_diff_workspace_test.dart
git commit -m "fix: enter blame while metadata loads"
```

---

### Task 4: 전체 검증과 완료 정리

**Files:**
- Verify: `lib/full_blame_view.dart`
- Verify: `lib/diff_screen.dart`
- Verify: `test/full_diff_content_views_test.dart`
- Verify: `test/full_diff_workspace_test.dart`

**Interfaces:**
- Consumes: Tasks 1-3의 카드 경계, 로딩 화면, 포커스 연결
- Produces: 형식, 테스트, 분석, macOS 빌드가 모두 통과한 병합 가능한 브랜치

- [ ] **Step 1: 변경 파일 형식과 공백 오류 검사**

Run:

```bash
dart format --output=none --set-exit-if-changed \
  lib/full_blame_view.dart \
  lib/diff_screen.dart \
  test/full_diff_content_views_test.dart \
  test/full_diff_workspace_test.dart
git diff --check
```

Expected: Dart 파일 변경 없음, Git 공백 오류 없음.

- [ ] **Step 2: 관련 Blame 테스트 전체 실행**

Run:

```bash
flutter test test/full_diff_content_views_test.dart
flutter test test/full_diff_workspace_test.dart
flutter test test/full_diff_commit_info_card_test.dart
flutter test test/full_diff_visual_test.dart
```

Expected: 관련 테스트 파일이 모두 PASS. 커밋 카드, 긴 메시지 계획과 맞닿는
카드 테스트, 시각 기준에서 레이아웃 예외가 없음.

- [ ] **Step 3: 전체 테스트와 정적 분석 실행**

Run:

```bash
flutter test
flutter analyze
```

Expected: 전체 테스트 PASS, `No issues found!`.

- [ ] **Step 4: macOS 디버그 앱 빌드**

Run:

```bash
flutter build macos --debug
```

Expected: `build/macos/Build/Products/Debug/yogit.app` 생성 성공.

- [ ] **Step 5: 변경 범위와 사용자 파일 보존 확인**

Run:

```bash
git status --short
git diff --stat main...HEAD
git log --oneline --decorate main..HEAD
```

Expected:

- 기능 변경은 `full_blame_view.dart`, `diff_screen.dart`와 두 테스트 파일에
  한정됨.
- 설계와 구현 계획 문서는 브랜치의 기준 커밋에 이미 포함됨.
- 사용자의 기존 수정 파일과 `.superpowers/brainstorm/`은 커밋되지 않음.
- Tasks 1-3의 커밋이 순서대로 보임.

- [ ] **Step 6: 검증 중 필요한 수정이 있었다면 별도 커밋**

검증 중 코드나 테스트를 고쳤을 때만 실행한다.

```bash
git add \
  lib/full_blame_view.dart \
  lib/diff_screen.dart \
  test/full_diff_content_views_test.dart \
  test/full_diff_workspace_test.dart
git commit -m "fix: address blame loading verification"
```

Expected: 검증 수정이 없으면 이 단계는 건너뜀. 수정이 있으면 해당 파일만
커밋됨.
