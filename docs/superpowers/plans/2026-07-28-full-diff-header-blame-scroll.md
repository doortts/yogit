# Full Diff Header and Blame Message Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full Diff 헤더의 파일 정보 글자를 2px 키우고 코드 아이콘을 없애며, 블레임 커밋 카드에서 8줄을 넘는 메시지를 카드 안에서 끝까지 스크롤할 수 있게 한다.

**Architecture:** 헤더 변경은 `GlobalFileBar`와 공용 배지의 표현값만 조정한다. 커밋 카드에는 기본값이 꺼진 `scrollLongMessage` 옵션과 카드 전용 스크롤 컨트롤러를 추가하고, 블레임 화면에서만 옵션을 켠다. 파일 히스토리 카드는 기존의 8줄 말줄임 동작을 유지한다.

**Tech Stack:** Flutter, Dart, Material widgets, `flutter_test`

## Global Constraints

- 파일 경로 글자 크기는 정확히 13px로 한다.
- 변경 요약과 인코딩 배지의 글자 크기는 정확히 11px로 한다.
- 파일 경로 왼쪽의 `<>` 코드 아이콘과 그 공백을 모두 없앤다.
- 블레임 커밋 메시지 영역은 최대 8줄 높이를 유지한다.
- 8줄을 넘는 메시지는 말줄임표로 자르지 않고 마우스 휠, 트랙패드, 스크롤바 드래그로 읽을 수 있게 한다.
- 커밋 해시, 작성자, 시간은 스크롤 영역 밖에 고정한다.
- 카드 스크롤은 블레임 라인 선택과 목록의 키보드 포커스를 바꾸지 않는다.
- 파일 히스토리 커밋 카드의 현재 동작은 바꾸지 않는다.
- 새 패키지를 추가하지 않는다.
- 사용자가 수정한 `docs/superpowers/plans/2026-07-27-full-diff-hunk-workspace.md`와 `.superpowers/brainstorm/`은 건드리거나 커밋하지 않는다.

---

## File Structure

- `lib/full_diff_header.dart`: 파일 경로, 변경 요약, 인코딩의 글자 크기와 헤더 요소 구성을 담당한다.
- `lib/full_diff_commit_info_card.dart`: 커밋 메시지 로딩, 8줄 제한, 선택적 내부 스크롤, 메타 정보 배치를 담당한다.
- `lib/full_blame_view.dart`: 블레임 커밋 카드에만 내부 스크롤을 허용하고 카드가 포인터 입력을 받을 수 있게 한다.
- `test/full_diff_header_test.dart`: 헤더 글자 크기와 코드 아이콘 제거를 검증한다.
- `test/full_diff_visual_test.dart`: 집중 모드 헤더의 실제 요소 순서와 겹침 없는 배치를 검증한다.
- `test/full_diff_commit_info_card_test.dart`: 기본 말줄임 동작과 선택적 메시지 스크롤의 경계, 위치 초기화를 검증한다.
- `test/full_diff_content_views_test.dart`: 블레임 화면에서 실제 카드 스크롤과 라인 선택·포커스 유지를 검증한다.

---

### Task 1: Full Diff 헤더 글자 크기와 요소 구성

**Files:**
- Modify: `lib/full_diff_header.dart:72-139`
- Modify: `lib/full_diff_header.dart:656-689`
- Test: `test/full_diff_header_test.dart`
- Test: `test/full_diff_visual_test.dart:889-925`

**Interfaces:**
- Consumes: `GlobalFileBar`, `_HeaderBadge`, `technicalTextStyle`
- Produces: 파일 경로 13px, 변경 요약·인코딩 11px, 코드 아이콘이 없는 `GlobalFileBar`

- [ ] **Step 1: 헤더 표현값을 고정하는 실패 테스트 작성**

`test/full_diff_header_test.dart`에 다음 테스트를 추가한다.

```dart
testWidgets('file identity text is larger and has no unexplained code icon', (
  tester,
) async {
  await pumpHeaders(tester);

  expect(find.byIcon(Icons.code), findsNothing);
  expect(
    tester.widget<Text>(find.text('src/drlua.pas')).style?.fontSize,
    13,
  );
  expect(
    tester.widget<Text>(find.text('M · +12 −4 · 1.5 KB')).style?.fontSize,
    11,
  );
  expect(tester.widget<Text>(find.text('UTF-8')).style?.fontSize, 11);

  final back = tester.getRect(find.byKey(const Key('full-diff-back')));
  final path = tester.getRect(find.byKey(const Key('file-path-chip')));
  expect(back.right, lessThan(path.left));
});
```

`test/full_diff_visual_test.dart`의 집중 모드 헤더 테스트에서 `Icons.code`를 찾는 부분을 없애고 다음 순서만 검사한다.

```dart
final back = tester.getRect(find.byKey(const Key('full-diff-back')));
final path = tester.getRect(find.byKey(const Key('file-path-chip')));
expect(back.left, lessThan(80));
expect(back.right, lessThan(path.left));
```

- [ ] **Step 2: 테스트가 현재 코드에서 실패하는지 확인**

Run:

```bash
flutter test test/full_diff_header_test.dart test/full_diff_visual_test.dart
```

Expected: 새 헤더 테스트가 `Icons.code`가 남아 있고 글자 크기가 각각 11px, 9px, 9px라서 실패한다.

- [ ] **Step 3: 헤더를 최소 범위로 수정**

`lib/full_diff_header.dart`의 `GlobalFileBar`에서 다음 코드 아이콘 분기를 삭제한다.

```dart
if (path != null)
  const Icon(Icons.code, size: 18, color: Colors.white),
```

파일 경로 스타일을 다음 값으로 바꾼다.

```dart
style: technicalTextStyle.copyWith(
  color: Colors.white,
  fontSize: 13,
),
```

`_HeaderBadge`의 글자 스타일을 다음 값으로 바꾼다.

```dart
style: technicalTextStyle.copyWith(
  color: foreground,
  fontSize: 11,
  height: 1,
),
```

- [ ] **Step 4: 헤더 테스트 통과 확인**

Run:

```bash
flutter test test/full_diff_header_test.dart test/full_diff_visual_test.dart
```

Expected: 두 테스트 파일이 모두 통과하고 레이아웃 오버플로가 발생하지 않는다.

- [ ] **Step 5: 헤더 변경 커밋**

```bash
git add lib/full_diff_header.dart test/full_diff_header_test.dart test/full_diff_visual_test.dart
git commit -m "style: enlarge full diff file identity"
```

---

### Task 2: 커밋 정보 카드의 선택적 메시지 스크롤

**Files:**
- Modify: `lib/full_diff_commit_info_card.dart`
- Test: `test/full_diff_commit_info_card_test.dart`

**Interfaces:**
- Consumes: `FullDiffCommitInfo`, `FullDiffCommitMessageLoader`
- Produces: `FullDiffCommitInfoCard({required info, loadMessage, scrollLongMessage = false})`
- Produces: 스크롤 영역 키 `full-diff-commit-message-scroll`

- [ ] **Step 1: 선택적 스크롤의 실패 테스트 작성**

`test/full_diff_commit_info_card_test.dart`에 긴 메시지를 만드는 도우미를 추가한다.

```dart
String commitMessageLines(int count) =>
    List.generate(count, (index) => 'line ${index + 1}').join('\n');
```

8줄 이하에서는 스크롤 범위가 없고 메타 정보가 보이는지 검사한다.

```dart
testWidgets('scrollable message stays idle at eight lines', (tester) async {
  await tester.pumpWidget(
    qaApp(
      FullDiffCommitInfoCard(
        info: FullDiffCommitInfo(
          sha: 'eight',
          shortSha: 'eight',
          fallbackMessage: commitMessageLines(8),
          author: 'Suwon Chae',
          timestamp: 1704067200,
        ),
        scrollLongMessage: true,
      ),
    ),
  );

  final scrollable = tester.state<ScrollableState>(
    find.descendant(
      of: find.byKey(const Key('full-diff-commit-message-scroll')),
      matching: find.byType(Scrollable),
    ),
  );
  expect(scrollable.position.maxScrollExtent, 0);
  expect(find.byKey(const Key('full-diff-commit-metadata')), findsOneWidget);
});
```

9줄 이상에서는 메시지만 스크롤되고 메타 정보 위치가 고정되는지 검사한다.

```dart
testWidgets('long message scrolls inside an eight-line viewport', (
  tester,
) async {
  await tester.pumpWidget(
    qaApp(
      FullDiffCommitInfoCard(
        info: FullDiffCommitInfo(
          sha: 'long',
          shortSha: 'long',
          fallbackMessage: commitMessageLines(12),
          author: 'Suwon Chae',
          timestamp: 1704067200,
        ),
        scrollLongMessage: true,
      ),
    ),
  );

  final messageArea = find.byKey(
    const Key('full-diff-commit-message-scroll'),
  );
  final metadataTop = tester.getTopLeft(
    find.byKey(const Key('full-diff-commit-metadata')),
  );
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: messageArea, matching: find.byType(Scrollable)),
  );

  expect(scrollable.position.maxScrollExtent, greaterThan(0));
  await tester.drag(messageArea, const Offset(0, -80));
  await tester.pump();
  expect(scrollable.position.pixels, greaterThan(0));
  expect(
    tester.getTopLeft(find.byKey(const Key('full-diff-commit-metadata'))),
    metadataTop,
  );
  final message = tester.widget<Text>(
    find.byKey(const Key('full-diff-commit-message')),
  );
  expect(message.maxLines, isNull);
  expect(message.overflow, TextOverflow.clip);
  expect(find.byType(Scrollbar), findsOneWidget);
});
```

같은 카드 상태에서 커밋이 바뀌면 스크롤 위치가 맨 위로 돌아오는 테스트를 추가한다. 테스트용 상태 위젯은 첫 번째와 두 번째 `FullDiffCommitInfo`를 같은 `FullDiffCommitInfoCard`에 차례로 전달한다.

```dart
testWidgets('changing the commit resets message scroll to the top', (
  tester,
) async {
  final hostKey = GlobalKey<_ScrollableCardHostState>();
  await tester.pumpWidget(qaApp(_ScrollableCardHost(key: hostKey)));

  final messageArea = find.byKey(
    const Key('full-diff-commit-message-scroll'),
  );
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: messageArea, matching: find.byType(Scrollable)),
  );
  await tester.drag(messageArea, const Offset(0, -80));
  await tester.pump();
  expect(scrollable.position.pixels, greaterThan(0));

  hostKey.currentState!.showSecond();
  await tester.pump();

  expect(scrollable.position.pixels, 0);
  expect(find.textContaining('second line 1'), findsOneWidget);
});
```

테스트 파일 아래쪽에 같은 카드 상태를 유지하는 다음 호스트를 추가한다. 두 메시지는 모두 12줄이라서 커밋 전환 전후에 실제 스크롤 범위를 갖는다.

```dart
class _ScrollableCardHost extends StatefulWidget {
  const _ScrollableCardHost({super.key});

  @override
  State<_ScrollableCardHost> createState() => _ScrollableCardHostState();
}

class _ScrollableCardHostState extends State<_ScrollableCardHost> {
  var _second = false;

  void showSecond() => setState(() => _second = true);

  @override
  Widget build(BuildContext context) => FullDiffCommitInfoCard(
    info: FullDiffCommitInfo(
      sha: _second ? 'second' : 'first',
      shortSha: _second ? 'second' : 'first',
      fallbackMessage: List.generate(
        12,
        (index) => '${_second ? 'second' : 'first'} line ${index + 1}',
      ).join('\n'),
      author: 'Suwon Chae',
      timestamp: 1704067200,
    ),
    scrollLongMessage: true,
  );
}
```

기존 기본 동작 테스트는 `scrollLongMessage`를 넘기지 않은 상태에서 `maxLines == 8`, `overflow == TextOverflow.ellipsis`를 계속 검사한다.

- [ ] **Step 2: 새 카드 테스트가 실패하는지 확인**

Run:

```bash
flutter test test/full_diff_commit_info_card_test.dart
```

Expected: `scrollLongMessage` 매개변수와 `full-diff-commit-message-scroll` 키가 없어서 컴파일 또는 검색 단계에서 실패한다.

- [ ] **Step 3: 카드에 전용 스크롤 상태와 공개 옵션 추가**

`FullDiffCommitInfoCard` 생성자와 필드에 기본값이 꺼진 옵션을 추가한다.

```dart
const FullDiffCommitInfoCard({
  required this.info,
  this.loadMessage,
  this.scrollLongMessage = false,
  super.key,
});

final bool scrollLongMessage;
```

상태에 전용 컨트롤러를 만들고 해제한다.

```dart
final _messageScrollController = ScrollController();

@override
void dispose() {
  _requestSerial++;
  _messageScrollController.dispose();
  super.dispose();
}
```

커밋이 바뀌면 기존 메시지 요청을 갱신하면서 스크롤 위치도 맨 위로 돌린다.

```dart
@override
void didUpdateWidget(covariant FullDiffCommitInfoCard oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.info.sha == widget.info.sha) return;
  if (_messageScrollController.hasClients) {
    _messageScrollController.jumpTo(0);
  }
  _load();
}
```

- [ ] **Step 4: 8줄 높이의 스크롤 메시지 영역 구현**

카드의 메시지 스타일을 명시적으로 공유한다.

```dart
const _commitMessageStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
);
```

현재 `Text(message, maxLines: 8, overflow: TextOverflow.ellipsis)`를 다음 분기로 교체한다.

```dart
if (widget.scrollLongMessage)
  _ScrollableCommitMessage(
    message: message,
    controller: _messageScrollController,
  )
else
  Text(
    message,
    key: const Key('full-diff-commit-message'),
    maxLines: 8,
    overflow: TextOverflow.ellipsis,
    style: _commitMessageStyle,
  ),
```

같은 파일에 전용 표현 위젯을 추가한다. 8줄 높이는 실제 글꼴과 시스템 글자 배율로 계산하며, `Scrollbar`는 스크롤 범위가 있을 때만 손잡이를 그린다.

```dart
class _ScrollableCommitMessage extends StatelessWidget {
  const _ScrollableCommitMessage({
    required this.message,
    required this.controller,
  });

  final String message;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(_commitMessageStyle);
    final lineProbe = TextPainter(
      text: TextSpan(
        text: List.filled(8, 'M').join('\n'),
        style: style,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 8,
    )..layout();
    final maxHeight = lineProbe.height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        interactive: true,
        thickness: 4,
        radius: const Radius.circular(2),
        child: SingleChildScrollView(
          key: const Key('full-diff-commit-message-scroll'),
          controller: controller,
          primary: false,
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            message,
            key: const Key('full-diff-commit-message'),
            maxLines: null,
            overflow: TextOverflow.clip,
            style: _commitMessageStyle,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 카드 테스트 통과 확인**

Run:

```bash
dart format lib/full_diff_commit_info_card.dart test/full_diff_commit_info_card_test.dart
flutter test test/full_diff_commit_info_card_test.dart
```

Expected: 기본 8줄 말줄임 테스트와 새 내부 스크롤 테스트가 모두 통과한다.

- [ ] **Step 6: 카드 변경 커밋**

```bash
git add lib/full_diff_commit_info_card.dart test/full_diff_commit_info_card_test.dart
git commit -m "feat: scroll long full diff commit messages"
```

---

### Task 3: 블레임 화면 연결과 상호작용 검증

**Files:**
- Modify: `lib/full_blame_view.dart:138-210`
- Test: `test/full_diff_content_views_test.dart:1755-1870`

**Interfaces:**
- Consumes: `FullDiffCommitInfoCard.scrollLongMessage`
- Produces: 블레임 카드 안에서만 동작하는 긴 커밋 메시지 스크롤

- [ ] **Step 1: 실제 블레임 카드 스크롤의 실패 테스트 작성**

`test/full_diff_content_views_test.dart`에 다음 테스트를 추가한다.

```dart
testWidgets(
  'blame long message scroll keeps the selected line and list focus',
  (tester) async {
    final blameFocus = FocusNode();
    addTearDown(blameFocus.dispose);
    await pumpInteractiveBlameView(
      tester,
      focusNode: blameFocus,
      loadCommitMessage: (_) async =>
          List.generate(14, (index) => 'message line ${index + 1}').join('\n'),
    );

    await tester.tap(find.byKey(const Key('blame-line-3')));
    await tester.pump();
    await tester.pump();

    final details = find.byKey(const Key('blame-commit-details-3'));
    final messageArea = find.descendant(
      of: details,
      matching: find.byKey(
        const Key('full-diff-commit-message-scroll'),
      ),
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: messageArea, matching: find.byType(Scrollable)),
    );
    expect(blameFocus.hasFocus, isTrue);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    await tester.drag(messageArea, const Offset(0, -80));
    await tester.pump();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.byKey(const Key('blame-selected-3')), findsOneWidget);
    expect(blameFocus.hasFocus, isTrue);
  },
);
```

파일 히스토리 카드가 스크롤 모드로 바뀌지 않았다는 검사도 기존 히스토리 카드 테스트에 추가한다.

```dart
expect(
  find.descendant(
    of: find.byKey(Key('history-commit-details-${selected.commit.sha}')),
    matching: find.byKey(
      const Key('full-diff-commit-message-scroll'),
    ),
  ),
  findsNothing,
);
```

- [ ] **Step 2: 블레임 통합 테스트가 실패하는지 확인**

Run:

```bash
flutter test test/full_diff_content_views_test.dart
```

Expected: 블레임 카드가 아직 `scrollLongMessage`를 켜지 않고 포인터 입력도 차단하므로 메시지 스크롤 영역을 찾지 못해 실패한다.

- [ ] **Step 3: 블레임 카드에서만 스크롤 허용**

`lib/full_blame_view.dart`의 선택 카드에서 전체 `IgnorePointer`를 제거한다. `Positioned.fill` 아래 구조는 `ClipRect`와 `CompositedTransformFollower`로 바로 이어지게 해서 실제 카드 경계 안에서만 포인터 입력을 받게 한다.

블레임 카드 생성에 다음 옵션을 추가한다.

```dart
FullDiffCommitInfoCard(
  key: Key('blame-commit-details-$selectedLine'),
  info: FullDiffCommitInfo(
    sha: selectedBlame.sha,
    shortSha: _shortSha(selectedBlame.sha),
    fallbackMessage: selectedBlame.summary,
    author: selectedBlame.author,
    timestamp: selectedBlame.authorTimestamp,
  ),
  loadMessage: _canLoadCommitMessage(selectedBlame)
      ? widget.loadCommitMessage
      : null,
  scrollLongMessage: true,
),
```

`lib/full_history_view.dart`는 수정하지 않는다. 기본값 `false`가 기존 말줄임 동작을 보존한다.

- [ ] **Step 4: 블레임·히스토리 상호작용 테스트 통과 확인**

Run:

```bash
dart format lib/full_blame_view.dart test/full_diff_content_views_test.dart
flutter test test/full_diff_content_views_test.dart
```

Expected: 긴 블레임 메시지가 카드 안에서 움직이고 선택 라인과 목록 포커스가 유지된다. 히스토리 카드는 스크롤 영역을 만들지 않는다.

- [ ] **Step 5: 블레임 연결 변경 커밋**

```bash
git add lib/full_blame_view.dart test/full_diff_content_views_test.dart
git commit -m "feat: enable blame commit message scrolling"
```

---

### Task 4: 전체 검증과 정리

**Files:**
- Verify: `lib/full_diff_header.dart`
- Verify: `lib/full_diff_commit_info_card.dart`
- Verify: `lib/full_blame_view.dart`
- Verify: `test/full_diff_header_test.dart`
- Verify: `test/full_diff_visual_test.dart`
- Verify: `test/full_diff_commit_info_card_test.dart`
- Verify: `test/full_diff_content_views_test.dart`

**Interfaces:**
- Consumes: Task 1~3의 최종 구현
- Produces: 분석, 형식, 관련 테스트, 전체 테스트를 모두 통과한 변경

- [ ] **Step 1: 변경 파일 형식과 정적 분석 확인**

Run:

```bash
dart format --output=none --set-exit-if-changed \
  lib/full_diff_header.dart \
  lib/full_diff_commit_info_card.dart \
  lib/full_blame_view.dart \
  test/full_diff_header_test.dart \
  test/full_diff_visual_test.dart \
  test/full_diff_commit_info_card_test.dart \
  test/full_diff_content_views_test.dart
flutter analyze
```

Expected: 형식 변경이 필요하지 않고 분석 오류가 없다.

- [ ] **Step 2: 관련 테스트를 한 번에 실행**

Run:

```bash
flutter test \
  test/full_diff_header_test.dart \
  test/full_diff_visual_test.dart \
  test/full_diff_commit_info_card_test.dart \
  test/full_diff_content_views_test.dart
```

Expected: 모든 관련 테스트가 통과한다.

- [ ] **Step 3: 전체 테스트 실행**

Run:

```bash
flutter test
```

Expected: 전체 테스트가 통과한다.

- [ ] **Step 4: 사용자 소유 변경과 커밋 범위 확인**

Run:

```bash
git status --short
git diff --check
git log -4 --oneline
```

Expected:

```text
 M docs/superpowers/plans/2026-07-27-full-diff-hunk-workspace.md
?? .superpowers/brainstorm/
```

위 두 경로만 사용자 소유 변경으로 남고, 구현 파일은 앞선 세 커밋에 포함되어 있어야 한다.

- [ ] **Step 5: 검증 중 필요한 수정이 있었다면 별도 커밋**

검증에서 실제 수정이 생긴 경우에만 수정한 파일 경로를 명시해서 커밋한다.

```bash
git add \
  lib/full_diff_header.dart \
  lib/full_diff_commit_info_card.dart \
  lib/full_blame_view.dart \
  test/full_diff_header_test.dart \
  test/full_diff_visual_test.dart \
  test/full_diff_commit_info_card_test.dart \
  test/full_diff_content_views_test.dart
git commit -m "fix: address full diff header and blame scroll QA"
```

수정이 없으면 이 단계에서는 커밋하지 않는다.
