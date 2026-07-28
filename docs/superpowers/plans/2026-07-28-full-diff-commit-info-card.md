# Full Diff 커밋 정보 카드와 Blame 키보드 탐색 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Blame과 History가 전체 커밋 메시지를 보여주는 공통 카드를 사용하고, 앱 전체 메모리 캐시와 파일 목록·Blame 사이의 화살표 키 탐색을 지원한다.

**Architecture:** `FullDiffRepository`가 전체 커밋 메시지를 읽고 `FullDiffCommitMessageCache.shared`가 저장소 경로와 SHA별로 성공한 결과를 앱 종료 시까지 보관한다. 공통 `FullDiffCommitInfoCard`가 비동기 메시지 갱신과 표시를 담당하며 Blame과 History는 선택 행에 `LayerLink`를 붙여 카드를 겹쳐 표시한다. `DiffScreen`은 파일, History, Blame 포커스 노드를 소유하고 화면 사이의 좌우 화살표 이동을 조정한다.

**Tech Stack:** Flutter 3.44.4, Dart, Material widgets, Git CLI, `flutter_test`

## Global Constraints

- 커밋 메시지는 제목과 본문을 포함해 최대 8줄까지 표시한다.
- 성공적으로 읽은 메시지는 `저장소 절대 경로 + SHA`별로 앱 프로세스가 종료될 때까지 메모리에 보관한다.
- 실패한 요청과 빈 결과는 캐시하지 않는다.
- 같은 키의 동시 요청은 Git 명령 하나를 함께 기다린다.
- 메시지를 읽는 동안 `Loading`을 표시하지 않고 기존 제목이나 Blame 요약을 사용한다.
- 커밋 정보 카드는 목록 위에 겹쳐 표시하며 다른 행을 아래로 밀지 않는다.
- Blame 카드의 왼쪽은 라인 번호 열의 시작점에 맞춘다.
- History 카드는 커밋 목록에 포커스가 있을 때만 표시한다.
- 사용자가 수정한 `docs/superpowers/plans/2026-07-27-full-diff-hunk-workspace.md`와 `.superpowers/brainstorm/`은 변경하거나 커밋하지 않는다.

---

## File Structure

- Create: `lib/full_diff_commit_message_cache.dart`
  - 앱 전체 커밋 메시지 캐시와 동시 요청 합치기를 담당한다.
- Create: `lib/full_diff_commit_info_card.dart`
  - 공통 카드 자료형, 비동기 메시지 갱신, 카드 UI와 시각 형식을 담당한다.
- Modify: `lib/git.dart`
  - `FullDiffRepository.loadCommitMessage` 계약과 Git 구현을 추가한다.
- Modify: `lib/full_blame_view.dart`
  - 공통 카드, 선택 행 기준 배치, 외부 포커스 노드와 좌우 탐색을 연결한다.
- Modify: `lib/full_history_view.dart`
  - 선택한 History 행 기준 공통 카드 오버레이를 추가한다.
- Modify: `lib/diff_screen.dart`
  - 앱 전체 캐시 로더와 Blame 포커스 노드를 두 화면에 전달한다.
- Modify: `test/support/full_diff_fixtures.dart`
  - 가짜 저장소가 전체 커밋 메시지 요청을 기록하고 응답하도록 확장한다.
- Create: `test/full_diff_commit_message_cache_test.dart`
  - 앱 전체 캐시 규칙을 독립적으로 검증한다.
- Create: `test/full_diff_commit_info_card_test.dart`
  - 공통 카드 형식, 8줄 제한, 비동기 갱신과 실패 대체 문구를 검증한다.
- Modify: `test/git_test.dart`
  - 실제 Git 명령 인자를 검증한다.
- Modify: `test/full_diff_content_views_test.dart`
  - Blame과 History 카드의 위치, 행 배치 유지, 화면 내부 키보드 동작을 검증한다.
- Modify: `test/full_diff_workspace_test.dart`
  - 파일 목록과 Blame 사이의 포커스 이동과 캐시 연결을 검증한다.
- Modify: `test/full_diff_visual_test.dart`
  - Blame과 History 선택 카드의 시각 검수 상태를 고정한다.

---

### Task 1: Git 전체 메시지 조회와 앱 전체 캐시

**Files:**
- Create: `lib/full_diff_commit_message_cache.dart`
- Modify: `lib/git.dart:670-705`
- Modify: `lib/git.dart:975-1075`
- Modify: `test/support/full_diff_fixtures.dart:9-135`
- Create: `test/full_diff_commit_message_cache_test.dart`
- Modify: `test/git_test.dart`

**Interfaces:**
- Produces: `Future<String> FullDiffRepository.loadCommitMessage(String sha)`
- Produces: `FullDiffCommitMessageCache.shared`
- Produces: `Future<String> FullDiffCommitMessageCache.getOrLoad({required String repositoryRoot, required String sha, required Future<String> Function() loader})`
- Produces: `FakeFullDiffRepository.commitMessageRequests` and `FakeFullDiffRepository.commitMessage`

- [ ] **Step 1: Write failing Git command and fake repository tests**

Add a `git_test.dart` test that records the command exactly:

```dart
test('loads the complete commit message body', () async {
  late List<String> arguments;
  final repository = GitRepository(
    '/repo',
    runner: (executable, args, {workingDirectory}) async {
      arguments = args;
      return ProcessResult(1, 0, 'Subject\n\nBody line\n', '');
    },
  );

  expect(
    await repository.loadCommitMessage('40aff6d'),
    'Subject\n\nBody line\n',
  );
  expect(arguments, [
    'show',
    '-s',
    '--format=%B',
    '40aff6d',
  ]);
});
```

Extend `FakeFullDiffRepository` with a request list and configurable result:

```dart
final commitMessageRequests = <String>[];
Future<String> Function(String sha)? commitMessage;

@override
Future<String> loadCommitMessage(String sha) {
  commitMessageRequests.add(sha);
  return commitMessage?.call(sha) ?? Future.value('');
}
```

- [ ] **Step 2: Run the Git test and verify it fails**

Run:

```bash
flutter test test/git_test.dart --plain-name "loads the complete commit message body"
```

Expected: FAIL because `FullDiffRepository` and `GitRepository` do not define `loadCommitMessage`.

- [ ] **Step 3: Add the repository contract and Git command**

Add the method to `FullDiffRepository`:

```dart
Future<String> loadCommitMessage(String sha);
```

Implement it in `GitRepository` without trimming the result at this layer:

```dart
@override
Future<String> loadCommitMessage(String sha) =>
    _run(['show', '-s', '--format=%B', sha]);
```

Update every `FullDiffRepository` implementation in tests and app fixtures so the project compiles.

- [ ] **Step 4: Run the Git and fixture compilation tests**

Run:

```bash
flutter test test/git_test.dart test/full_diff_git_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write failing cache tests**

Create `test/full_diff_commit_message_cache_test.dart` with independent cache instances:

```dart
test('coalesces concurrent requests and retains a successful value', () async {
  final cache = FullDiffCommitMessageCache();
  final completer = Completer<String>();
  var calls = 0;

  Future<String> load() {
    calls++;
    return completer.future;
  }

  final first = cache.getOrLoad(
    repositoryRoot: '/repo',
    sha: 'abc',
    loader: load,
  );
  final second = cache.getOrLoad(
    repositoryRoot: '/repo',
    sha: 'abc',
    loader: load,
  );
  expect(calls, 1);

  completer.complete('Subject\n\nBody\n');
  expect(await first, 'Subject\n\nBody');
  expect(await second, 'Subject\n\nBody');
  expect(
    await cache.getOrLoad(
      repositoryRoot: '/repo',
      sha: 'abc',
      loader: load,
    ),
    'Subject\n\nBody',
  );
  expect(calls, 1);
});

test('separates repositories and retries failed or empty loads', () async {
  final cache = FullDiffCommitMessageCache();
  var calls = 0;

  Future<String> load() async {
    calls++;
    if (calls == 1) throw StateError('temporary');
    if (calls == 2) return '   ';
    return 'Recovered';
  }

  await expectLater(
    cache.getOrLoad(repositoryRoot: '/a', sha: 'abc', loader: load),
    throwsStateError,
  );
  await expectLater(
    cache.getOrLoad(repositoryRoot: '/a', sha: 'abc', loader: load),
    throwsFormatException,
  );
  expect(
    await cache.getOrLoad(
      repositoryRoot: '/a',
      sha: 'abc',
      loader: load,
    ),
    'Recovered',
  );
  expect(
    await cache.getOrLoad(
      repositoryRoot: '/b',
      sha: 'abc',
      loader: () async => 'Other repository',
    ),
    'Other repository',
  );
  expect(calls, 3);
});
```

- [ ] **Step 6: Run the cache tests and verify they fail**

Run:

```bash
flutter test test/full_diff_commit_message_cache_test.dart
```

Expected: FAIL because `FullDiffCommitMessageCache` does not exist.

- [ ] **Step 7: Implement the shared cache**

Create `lib/full_diff_commit_message_cache.dart`:

```dart
import 'package:flutter/foundation.dart';

typedef FullDiffCommitMessageCacheKey = ({
  String repositoryRoot,
  String sha,
});

class FullDiffCommitMessageCache {
  FullDiffCommitMessageCache();

  static final FullDiffCommitMessageCache shared =
      FullDiffCommitMessageCache();

  final _values = <FullDiffCommitMessageCacheKey, String>{};
  final _inFlight =
      <FullDiffCommitMessageCacheKey, Future<String>>{};

  Future<String> getOrLoad({
    required String repositoryRoot,
    required String sha,
    required Future<String> Function() loader,
  }) {
    final key = (repositoryRoot: repositoryRoot, sha: sha);
    final value = _values[key];
    if (value != null) return SynchronousFuture(value);
    final pending = _inFlight[key];
    if (pending != null) return pending;

    late final Future<String> request;
    request = Future<String>.sync(loader).then((raw) {
      final message = raw.trimRight();
      if (message.trim().isEmpty) {
        throw const FormatException('Empty commit message');
      }
      _values[key] = message;
      return message;
    }).whenComplete(() {
      if (identical(_inFlight[key], request)) _inFlight.remove(key);
    });
    _inFlight[key] = request;
    return request;
  }
}
```

Do not add eviction or disk persistence.

- [ ] **Step 8: Run focused tests**

Run:

```bash
flutter test test/full_diff_commit_message_cache_test.dart test/git_test.dart test/full_diff_git_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit the repository and cache**

```bash
git add lib/full_diff_commit_message_cache.dart lib/git.dart test/support/full_diff_fixtures.dart test/full_diff_commit_message_cache_test.dart test/git_test.dart
git commit -m "feat: cache full diff commit messages"
```

---

### Task 2: 공통 커밋 정보 카드

**Files:**
- Create: `lib/full_diff_commit_info_card.dart`
- Create: `test/full_diff_commit_info_card_test.dart`

**Interfaces:**
- Consumes: `Future<String> Function(String sha)` supplied by `DiffScreen`
- Produces: `FullDiffCommitInfo`
- Produces: `FullDiffCommitInfoCard`
- Produces: stable keys `full-diff-commit-message`, `full-diff-commit-metadata`, and `full-diff-commit-card-surface`

- [ ] **Step 1: Write failing card layout and formatting tests**

Create `test/full_diff_commit_info_card_test.dart`:

```dart
testWidgets('shows fallback immediately and complete message up to eight lines', (
  tester,
) async {
  final completer = Completer<String>();
  await tester.pumpWidget(
    qaApp(
      FullDiffCommitInfoCard(
        info: const FullDiffCommitInfo(
          sha: '40aff6d123',
          shortSha: '40aff6d',
          fallbackMessage: 'Fallback subject',
          author: 'Suwon Chae',
          timestamp: 1704067200,
        ),
        loadMessage: (_) => completer.future,
      ),
    ),
  );

  expect(find.text('Fallback subject'), findsOneWidget);
  expect(find.text('Loading'), findsNothing);

  completer.complete(List.generate(10, (index) => 'line $index').join('\n'));
  await tester.pump();

  final message = tester.widget<Text>(
    find.byKey(const Key('full-diff-commit-message')),
  );
  expect(message.maxLines, 8);
  expect(message.overflow, TextOverflow.ellipsis);
  expect(message.data, contains('line 9'));
  expect(find.textContaining('Suwon Chae'), findsOneWidget);
  final local = DateTime.fromMillisecondsSinceEpoch(1704067200 * 1000);
  final expectedTime =
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  expect(find.textContaining(expectedTime), findsOneWidget);
});

testWidgets('keeps fallback when loading fails', (tester) async {
  await tester.pumpWidget(
    qaApp(
      FullDiffCommitInfoCard(
        info: const FullDiffCommitInfo(
          sha: 'bad',
          shortSha: 'bad',
          fallbackMessage: 'Known subject',
          author: 'Author',
          timestamp: 1704067200,
        ),
        loadMessage: (_) async => throw StateError('failed'),
      ),
    ),
  );
  await tester.pump();
  expect(find.text('Known subject'), findsOneWidget);
});
```

Calculate the expected display value from `DateTime.fromMillisecondsSinceEpoch` in the test process, as shown above, so CI does not depend on a fixed timezone.

- [ ] **Step 2: Run the card tests and verify they fail**

Run:

```bash
flutter test test/full_diff_commit_info_card_test.dart
```

Expected: FAIL because the common card types do not exist.

- [ ] **Step 3: Implement the common card model and async state**

Create `lib/full_diff_commit_info_card.dart` with these public types:

```dart
@immutable
class FullDiffCommitInfo {
  const FullDiffCommitInfo({
    required this.sha,
    required this.shortSha,
    required this.fallbackMessage,
    required this.author,
    required this.timestamp,
  });

  final String sha;
  final String shortSha;
  final String fallbackMessage;
  final String author;
  final int? timestamp;
}

typedef FullDiffCommitMessageLoader =
    Future<String> Function(String sha);

class FullDiffCommitInfoCard extends StatefulWidget {
  const FullDiffCommitInfoCard({
    required this.info,
    this.loadMessage,
    super.key,
  });

  final FullDiffCommitInfo info;
  final FullDiffCommitMessageLoader? loadMessage;
}
```

Make `FullDiffCommitInfoCard` stateful. In `initState` and when `info.sha` changes:

```dart
void _load() {
  final serial = ++_requestSerial;
  _message = null;
  final sha = widget.info.sha;
  if (sha.isEmpty || widget.loadMessage == null) return;
  widget.loadMessage!(sha).then((message) {
    if (!mounted || serial != _requestSerial) return;
    setState(() => _message = message);
  }, onError: (_) {
    // Keep fallbackMessage and allow the shared cache to retry later.
  });
}
```

Render `_message ?? info.fallbackMessage` with:

```dart
Text(
  message,
  key: const Key('full-diff-commit-message'),
  maxLines: 8,
  overflow: TextOverflow.ellipsis,
  style: const TextStyle(fontWeight: FontWeight.w600),
)
```

Use a `1.0` pixel border whose color is visibly stronger than `fullDiffDivider`, for example:

```dart
border: Border.all(
  color: fullDiffAccent.withValues(alpha: 0.72),
  width: 1,
),
```

Keep the existing header background, 8 pixel radius, shadow, 420 pixel maximum width, technical font for SHA, and inherited UI font for message, author, and time.

- [ ] **Step 4: Add a late-result test**

Add a test that swaps from SHA `first` to `second`, completes `second`, then completes `first`. Assert that the card still shows the second message:

```dart
expect(
  tester.widget<Text>(
    find.byKey(const Key('full-diff-commit-message')),
  ).data,
  'Second body',
);
```

- [ ] **Step 5: Run card tests**

Run:

```bash
flutter test test/full_diff_commit_info_card_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the common card**

```bash
git add lib/full_diff_commit_info_card.dart test/full_diff_commit_info_card_test.dart
git commit -m "feat: add shared full diff commit card"
```

---

### Task 3: Blame 카드와 내부 키보드 탐색

**Files:**
- Modify: `lib/full_blame_view.dart:14-240`
- Modify: `lib/full_blame_view.dart:322-548`
- Modify: `test/full_diff_content_views_test.dart:24-82`
- Modify: `test/full_diff_content_views_test.dart:1657-1885`

**Interfaces:**
- Consumes: `FullDiffCommitInfoCard`
- Consumes: optional `FocusNode focusNode`
- Consumes: optional `VoidCallback onMoveToFiles`
- Consumes: optional `FullDiffCommitMessageLoader loadCommitMessage`
- Produces: focus key `blame-list-focus`
- Keeps: detail key `blame-commit-details-<line>`

- [ ] **Step 1: Write failing Blame geometry and card tests**

Extend `pumpInteractiveBlameView` so tests can pass `focusNode`, `onMoveToFiles`, `activeAnchor`, and `loadCommitMessage`.

Add tests that select line 3 and assert:

```dart
final card = find.byKey(const Key('blame-commit-details-3'));
final numberColumn = find.byKey(const Key('blame-line-number-3'));
expect(card, findsOneWidget);
expect(
  tester.getTopLeft(card).dx,
  closeTo(tester.getTopLeft(numberColumn).dx, 0.5),
);
final surface = tester.widget<DecoratedBox>(
  find.descendant(
    of: card,
    matching: find.byKey(const Key('full-diff-commit-card-surface')),
  ),
);
final border = (surface.decoration as BoxDecoration).border as Border;
expect(border.top.width, 1);
expect(
  border.top.color,
  fullDiffAccent.withValues(alpha: 0.72),
);
```

Record the next row position before selecting and assert that it does not move after the card appears.

- [ ] **Step 2: Write failing Blame focus navigation tests**

Use an external `FocusNode` and callbacks:

```dart
final blameFocus = FocusNode();
var movedToFiles = false;
await pumpInteractiveBlameView(
  tester,
  focusNode: blameFocus,
  onMoveToFiles: () => movedToFiles = true,
);

blameFocus.requestFocus();
await tester.pump();
expect(find.byKey(const Key('blame-selected-1')), findsOneWidget);

await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
await tester.pump();
expect(find.byKey(const Key('blame-selected-2')), findsOneWidget);

await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
expect(movedToFiles, isTrue);
```

Add a second test with an active anchor at line 4 and assert that requesting Blame focus initially selects line 4. Keep the existing first/last boundary assertions.

- [ ] **Step 3: Run the focused Blame tests and verify they fail**

Run:

```bash
flutter test test/full_diff_content_views_test.dart --plain-name "blame"
```

Expected: FAIL because Blame owns a private focus node, does not handle `←`, and still uses the old card.

- [ ] **Step 4: Accept an external focus node and initialize selection on focus**

Add these optional constructor fields to `FullBlameView`:

```dart
final FocusNode? focusNode;
final VoidCallback? onMoveToFiles;
final FullDiffCommitMessageLoader? loadCommitMessage;
```

Use the same ownership pattern as `FullHistoryView`:

```dart
final _ownedFocusNode = FocusNode(debugLabel: 'full blame lines');
FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;
```

Only dispose `_ownedFocusNode`. Add `onFocusChange` to the `Focus` widget. When it gains focus and no line is selected, choose:

```dart
final sourceMap = FullSourceHunkMap(
  hunks: widget.hunks,
  side: widget.document.file.side,
  lineCount: widget.document.file.lines.length,
  activeAnchor: widget.activeAnchor,
);
final initial = sourceMap.activeLine(widget.activeAnchor) ?? 1;
```

Do nothing if the file has no lines.

- [ ] **Step 5: Handle left-arrow return and preserve modifier behavior**

Before calculating the up/down delta:

```dart
if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
  widget.onMoveToFiles?.call();
  return KeyEventResult.handled;
}
```

Keep Meta, Alt, Shift, and Control combinations ignored so page scrolling and global shortcuts continue to work.

- [ ] **Step 6: Replace the old card and align it to the line-number column**

Define one shared layout constant for the avatar column:

```dart
const fullBlameAvatarWidth = 20.0;
```

Use it both in `BlameSourceRow` and in the follower offset:

```dart
offset: const Offset(
  fullBlameAvatarWidth,
  fullDiffSourceRowHeight * 2,
),
```

Replace `BlameCommitDetailsCard` with:

```dart
FullDiffCommitInfoCard(
  key: Key('blame-commit-details-$selectedLine'),
  info: FullDiffCommitInfo(
    sha: blame.sha,
    shortSha: _shortSha(blame.sha),
    fallbackMessage: blame.summary,
    author: blame.author,
    timestamp: blame.authorTimestamp,
  ),
  loadMessage: widget.loadCommitMessage,
)
```

Delete `BlameCommitDetailsCard` and the duplicate date/card styling code after all tests use the common card.

- [ ] **Step 7: Run Blame and card tests**

Run:

```bash
flutter test test/full_diff_commit_info_card_test.dart test/full_diff_content_views_test.dart --plain-name "blame"
```

Expected: PASS.

- [ ] **Step 8: Commit Blame integration**

```bash
git add lib/full_blame_view.dart test/full_diff_content_views_test.dart
git commit -m "feat: navigate and explain full diff blame lines"
```

---

### Task 4: History 선택 행 커밋 카드

**Files:**
- Modify: `lib/full_history_view.dart:9-184`
- Modify: `test/full_diff_content_views_test.dart:378-690`

**Interfaces:**
- Consumes: `FullDiffCommitInfoCard`
- Consumes: optional `FullDiffCommitMessageLoader loadCommitMessage`
- Produces: detail key `history-commit-details-<sha>`
- Keeps: existing `history-list-focus` and `history-row-<sha>` keys

- [ ] **Step 1: Write failing History visibility and geometry tests**

Pump a `FullHistoryView` with a controlled `FocusNode`, selection, and message loader. Before requesting focus, assert that no card exists. After requesting focus:

```dart
final card = find.byKey(Key('history-commit-details-${commitA.sha}'));
expect(card, findsOneWidget);
final row = find.byKey(Key('history-row-${commitA.sha}'));
expect(
  tester.getTopLeft(card).dy,
  closeTo(tester.getBottomLeft(row).dy + 4, 0.5),
);
```

Record the second row top before focus and assert that showing the card does not change it. Move selection with `↓`, then assert the card key, fallback message, and position follow the second row. Move focus to a separate file-list node and assert that the card disappears while `selected` remains the second entry.

- [ ] **Step 2: Run History tests and verify they fail**

Run:

```bash
flutter test test/full_diff_content_views_test.dart --plain-name "history"
```

Expected: FAIL because History does not render a commit information card.

- [ ] **Step 3: Add a selected-row transform target**

Add this optional constructor field to `FullHistoryView`:

```dart
final FullDiffCommitMessageLoader? loadCommitMessage;
```

Add one `LayerLink _selectedLink` to `_FullHistoryViewState`. Wrap only the selected row:

```dart
Widget row = HistoryRow(
  entry: entry,
  selected: isSelected,
  focused: isSelected && _hasFocus,
);
if (isSelected) {
  row = CompositedTransformTarget(
    link: _selectedLink,
    child: row,
  );
}
```

Keep `_rowKeys` on the outer keyed subtree so existing visibility navigation continues to find the selected row.

- [ ] **Step 4: Render a non-layout overlay only while focused**

Replace the direct `ListView.builder` child with a clipped `Stack`. Keep the list in `Positioned.fill`. Store `final selected = widget.selected;` before building the overlay, then add:

```dart
if (_hasFocus && selected != null)
  Positioned.fill(
    child: IgnorePointer(
      child: ClipRect(
        child: CompositedTransformFollower(
          link: _selectedLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: Align(
            alignment: Alignment.topLeft,
            child: FullDiffCommitInfoCard(
              key: Key(
                'history-commit-details-${selected.commit.sha}',
              ),
              info: FullDiffCommitInfo(
                sha: selected.commit.sha,
                shortSha: selected.commit.shortSha,
                fallbackMessage: selected.commit.subject,
                author: selected.commit.author.name,
                timestamp: selected.commit.authorTimestamp,
              ),
              loadMessage: widget.loadCommitMessage,
            ),
          ),
        ),
      ),
    ),
  ),
```

The card must not be inserted into `itemBuilder`.

- [ ] **Step 5: Run History and shared card tests**

Run:

```bash
flutter test test/full_diff_commit_info_card_test.dart test/full_diff_content_views_test.dart --plain-name "history"
```

Expected: PASS.

- [ ] **Step 6: Commit History integration**

```bash
git add lib/full_history_view.dart test/full_diff_content_views_test.dart
git commit -m "feat: show commit details in full diff history"
```

---

### Task 5: DiffScreen 포커스와 캐시 연결

**Files:**
- Modify: `lib/diff_screen.dart:81-190`
- Modify: `lib/diff_screen.dart:699-794`
- Modify: `lib/diff_screen.dart:1581-1632`
- Modify: `test/full_diff_workspace_test.dart:110-165`
- Modify: `test/full_diff_workspace_test.dart:324-370`
- Modify: `test/full_diff_workspace_test.dart:2980-3070`

**Interfaces:**
- Consumes: `FullDiffCommitMessageCache`
- Consumes: `FullDiffRepository.loadCommitMessage`
- Produces: optional `DiffScreen.commitMessageCache` injection for deterministic tests
- Produces: `FocusNode _blameListFocus`
- Extends: `_FullDiffNavigationPane` with `blame`

- [ ] **Step 1: Write failing workspace arrow-navigation test**

Start in Blame, focus the file list, and send `→`:

```dart
fixture.controller.setPrimaryView(FullDiffView.blame);
await tester.pumpAndSettle();
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
expect(find.byKey(const Key('blame-selected-1')), findsOneWidget);

await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
await tester.pump();
expect(filesFocus.focusNode!.hasFocus, isTrue);
```

Also assert that `↑/↓` on the Blame focus changes the selected line but does not change the selected file.

- [ ] **Step 2: Write failing cache wiring and screen-reopen test**

Add `FullDiffCommitMessageCache? commitMessageCache` to the local `pumpWorkspace` helper and pass it into `DiffScreen`.

Configure:

```dart
fixture.repository.commitMessage = (sha) async =>
    'Complete subject\n\nComplete body';
final cache = FullDiffCommitMessageCache();
```

Select a Blame line, wait for the complete body, dispose the screen, create a new controller and `DiffScreen` using the same cache, then select the same SHA again. Assert:

```dart
expect(fixture.repository.commitMessageRequests, [commitA.sha]);
expect(find.textContaining('Complete body'), findsOneWidget);
```

Add a History assertion using the same loader so Blame and History share the same cached value.

- [ ] **Step 3: Run the workspace tests and verify they fail**

Run:

```bash
flutter test test/full_diff_workspace_test.dart --plain-name "Blame"
flutter test test/full_diff_workspace_test.dart --plain-name "commit message cache"
```

Expected: FAIL because `DiffScreen` has no Blame focus node or cache loader.

- [ ] **Step 4: Add cache injection and a single loader**

Add to `DiffScreen`:

```dart
final FullDiffCommitMessageCache? commitMessageCache;
```

Add `this.commitMessageCache` to the existing constructor. Keep the constructor `const` by making the field nullable. In state:

```dart
FullDiffCommitMessageCache get _commitMessageCache =>
    widget.commitMessageCache ?? FullDiffCommitMessageCache.shared;

Future<String> _loadCommitMessage(String sha) =>
    _commitMessageCache.getOrLoad(
      repositoryRoot: widget.repository.root,
      sha: sha,
      loader: () => widget.repository.loadCommitMessage(sha),
    );
```

Pass `_loadCommitMessage` to both `FullBlameView` and `FullHistoryView`.

- [ ] **Step 5: Add and manage the Blame focus node**

Add:

```dart
final _blameListFocus = FocusNode(debugLabel: 'full diff blame');
```

Register a listener in `initState`, remove it and dispose the node in `dispose`. Extend the navigation state so Diff/History remembers files versus History and Blame independently remembers files versus lines. Do not let a temporary fallback to the file list erase the remembered Blame-lines preference.

Pass to `FullBlameView`:

```dart
focusNode: _blameListFocus,
onMoveToFiles: _fileListFocus.requestFocus,
loadCommitMessage: _loadCommitMessage,
```

- [ ] **Step 6: Extend file-list right-arrow handling**

Keep the existing History branch. Add the Blame branch only when loaded Blame data has at least one line:

```dart
if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
    _controller.state.view == FullDiffView.blame &&
    (_controller.state.blame.data?.lines.isNotEmpty ?? false)) {
  _blameListFocus.requestFocus();
  return KeyEventResult.handled;
}
```

If Blame is loading, failed, or empty, leave focus on the file list.

- [ ] **Step 7: Run workspace and content tests**

Run:

```bash
flutter test test/full_diff_workspace_test.dart test/full_diff_content_views_test.dart test/full_diff_commit_info_card_test.dart test/full_diff_commit_message_cache_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit DiffScreen wiring**

```bash
git add lib/diff_screen.dart test/full_diff_workspace_test.dart
git commit -m "feat: connect full diff commit details and blame focus"
```

---

### Task 6: 시각 검수와 전체 품질 확인

**Files:**
- Modify: `test/full_diff_visual_test.dart:302-327`
- Update: Full Diff golden images written by `test/full_diff_visual_test.dart`

**Interfaces:**
- Consumes: completed Blame and History card behavior
- Produces: stable visual references for selected Blame and History cards

- [ ] **Step 1: Strengthen the Blame visual case**

In case `28-blame-selection`, keep the existing no-row-shift assertion and add:

```dart
final lineNumber = find.byKey(const Key('blame-line-number-294'));
expect(
  tester.getTopLeft(card).dx,
  closeTo(tester.getTopLeft(lineNumber).dx, 0.5),
);
expect(
  find.descendant(
    of: card,
    matching: find.byKey(const Key('full-diff-commit-message')),
  ),
  findsOneWidget,
);
```

Inspect the generated image and confirm the 1 pixel border is visible against `fullDiffHeader`.

- [ ] **Step 2: Add a focused History card visual state**

In case `29-history-resizers`, request `history-list-focus`, keep the selected first history entry, and assert:

```dart
final selectedSha = controller.state.selectedHistoryEntry!.commit.sha;
expect(
  find.byKey(Key('history-commit-details-$selectedSha')),
  findsOneWidget,
);
```

Record the second History row top before the card appears and assert it remains unchanged.

- [ ] **Step 3: Run the visual test**

Regenerate the intentional visual references, then verify them normally:

```bash
flutter test --update-goldens test/full_diff_visual_test.dart
flutter test test/full_diff_visual_test.dart
```

Expected: PASS after intentional golden updates. Review the Blame and History images for border contrast, line-number alignment, 8-line card width, and clipping inside their panes.

- [ ] **Step 4: Run formatter and static analysis**

Run:

```bash
dart format lib/full_diff_commit_message_cache.dart lib/full_diff_commit_info_card.dart lib/git.dart lib/full_blame_view.dart lib/full_history_view.dart lib/diff_screen.dart test/support/full_diff_fixtures.dart test/full_diff_commit_message_cache_test.dart test/full_diff_commit_info_card_test.dart test/git_test.dart test/full_diff_content_views_test.dart test/full_diff_workspace_test.dart test/full_diff_visual_test.dart
flutter analyze
```

Expected: formatter exits 0 and `flutter analyze` reports no issues.

- [ ] **Step 5: Run all tests**

Run:

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Build the macOS release**

Run:

```bash
flutter build macos --release
```

Expected: exit 0 and a release app under `build/macos/Build/Products/Release/`.

- [ ] **Step 7: Commit visual references and final corrections**

Stage only the visual test and the two changed reference images:

```bash
git add test/full_diff_visual_test.dart \
  docs/superpowers/verification/full-diff-qa/actual/28-blame-selection.png \
  docs/superpowers/verification/full-diff-qa/actual/29-history-resizers.png
git status --short
git commit -m "test: verify full diff commit detail cards"
```

Before committing, remove from the staging area any unrelated file, especially `docs/superpowers/plans/2026-07-27-full-diff-hunk-workspace.md` and `.superpowers/brainstorm/`.

- [ ] **Step 8: Review the final diff**

Run:

```bash
git diff ebd2cb2..HEAD --stat
git diff ebd2cb2..HEAD --check
git status --short
```

Expected: only the files listed in this plan and intentional golden images appear in the feature commits; the two user-owned paths remain unstaged.
