import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// The preview header names the commit, not the pane.
///
/// docs 시안(preview-header-mockup): `커밋 <7자리> ⧉ · 부모 <7자리> <부모 제목>`.
/// 'Commit & Diff' 제목과 헤더의 Full Diff 버튼은 물러나고, 해시는 드래그로도
/// 복사 아이콘으로도 복사된다. 부모 쪽에 커서를 올리면 그 커밋의 메시지와
/// 날짜가 바로 뜬다.
void main() {
  late WindowFrameController controller;
  final copied = <String>[];

  setUp(() {
    copied.clear();
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // 전체 해시와 7자리 표기가 다른 커밋: 무엇을 보여주고 무엇을 복사하는지 갈린다.
  const child = GitCommit(
    sha: '2280d5885a9b36360ebc23f49606a37cfe1b4d90',
    shortSha: '2280d58',
    parents: ['a9b3636'],
    author: GitIdentity(name: 'Ada Author', email: 'ada@example.com'),
    authorTimestamp: 1700000000,
    committer: GitIdentity(name: 'Cam Committer', email: 'cam@example.com'),
    committerTimestamp: 1700000120,
    refs: [],
    subject: 'docs(readme): 최근 작업 반영',
  );
  final parent = commit('a9b3636', 'feat(app): 메뉴바 밝기를 외양에 맞춘다');

  FakeGitRepository repository({
    List<GitCommit>? commits,
    Future<String> Function(String sha)? commitMessage,
  }) => FakeGitRepository(
    (_, _) async => commits ?? [child, parent],
    files: (_, _) async => const [
      GitFileChange(
        path: 'lib/a.dart',
        status: 'M',
        additions: 1,
        deletions: 1,
      ),
    ],
    commitMessage:
        commitMessage ??
        (sha) async => sha == parent.sha
            ? '${parent.subject}\n\n막대는 파랑이고 팝오버는 민트라 같은 창이 두 색으로 보였다.'
            : child.subject,
  );

  Future<void> pumpPreview(
    WidgetTester tester, {
    List<GitCommit>? commits,
    Future<String> Function(String sha)? commitMessage,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(
        repository(commits: commits, commitMessage: commitMessage),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  testWidgets('the header names both commits instead of the pane', (
    tester,
  ) async {
    await pumpPreview(tester);

    final header = find.byKey(const Key('preview-header'));
    expect(header, findsOneWidget);
    expect(find.text('Commit & Diff'), findsNothing);
    expect(
      find.byKey(const Key('preview-full-diff')),
      findsNothing,
      reason: '⌘D와 툴바 버튼이 남으니 헤더 버튼은 물러난다',
    );

    expect(
      find.descendant(of: header, matching: find.text('2280d58')),
      findsOneWidget,
    );
    final parentLine = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('preview-parent')),
            matching: find.byType(Text),
          ),
        )
        .textSpan!
        .toPlainText();
    expect(parentLine, contains('a9b3636'));
    expect(
      parentLine,
      contains('feat(app): 메뉴바 밝기를 외양에 맞춘다'),
      reason: '부모 제목이 남는 폭을 쓴다',
    );
  });

  testWidgets('the copy button hands over the whole hash', (tester) async {
    await pumpPreview(tester);

    await tester.tap(find.byKey(const Key('preview-sha-copy')));
    await tester.pumpAndSettle();
    expect(copied, [child.sha], reason: '보이는 건 7자리, 붙는 건 전체 해시');
  });

  testWidgets('the header line can be dragged and copied', (tester) async {
    await pumpPreview(tester);

    final sha = tester.getRect(find.byKey(const Key('preview-sha')));
    final gesture = await tester.startGesture(
      sha.centerLeft + const Offset(1, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(sha.centerRight - const Offset(1, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(copied.single, contains('228'), reason: '헤더 글자도 드래그로 잡혀 복사된다');
  });

  testWidgets('hovering the parent tells its message and date', (tester) async {
    await pumpPreview(tester);
    expect(find.byKey(const Key('preview-parent-card')), findsNothing);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byKey(const Key('preview-parent')))),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('preview-parent-card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.textContaining('팝오버는 민트라')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('2023')),
      findsOneWidget,
      reason: '부모 커밋의 날짜도 함께 말한다',
    );

    await tester.sendEventToBinding(pointer.hover(const Offset(700, 400)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-parent-card')), findsNothing);
  });

  testWidgets('the parent card stays inside the window', (tester) async {
    await pumpPreview(tester);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byKey(const Key('preview-parent')))),
    );
    await tester.pumpAndSettle();

    // 미리보기는 오른쪽 끝에 붙어 있다 — 카드를 그 자리에서 오른쪽으로 펼치면
    // 창 밖으로 나간다.
    final card = tester.getRect(find.byKey(const Key('preview-parent-card')));
    expect(card.left, greaterThanOrEqualTo(0));
    expect(card.right, lessThanOrEqualTo(1400));
    expect(card.top, greaterThanOrEqualTo(0));
    expect(card.bottom, lessThanOrEqualTo(800));
  });

  testWidgets('a long parent message is cut, not spilled', (tester) async {
    // 카드는 커서에 매달려 있어 스크롤할 수 없다. 긴 메시지를 그대로 두면
    // 카드 밖으로 넘쳐 제 글자 위에 overflow 줄무늬가 그려진다.
    const child = GitCommit(
      sha: '6c1b0a7e4d3f29185a0b7c6d5e4f39281a0b7c6d',
      shortSha: '6c1b0a7',
      parents: ['b4e77c1'],
      author: GitIdentity(name: 'Ada Author', email: 'ada@example.com'),
      authorTimestamp: 1700000000,
      committer: GitIdentity(name: 'Cam Committer', email: 'cam@example.com'),
      committerTimestamp: 1700000120,
      refs: [],
      subject: 'fix: 긴 메시지를 가진 부모',
    );
    final longParent = commit('b4e77c1', 'fix: 창이 가려진 사이 그림을 되돌린다');
    await pumpPreview(
      tester,
      commits: [child, longParent],
      commitMessage: (sha) async => sha == longParent.sha
          ? [
              longParent.subject,
              '',
              for (var line = 1; line <= 40; line++)
                '본문 $line 번째 줄 — 한 줄로는 끝나지 않을 만큼 길게 이어지는 설명이 여기에 들어간다.',
            ].join('\n')
          : child.subject,
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byKey(const Key('preview-parent')))),
    );
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(const Key('preview-parent-card')));
    expect(card.bottom, lessThanOrEqualTo(800));
    expect(card.height, lessThan(400), reason: '본문은 열 줄에서 끊긴다');
  });

  testWidgets('a long message scrolls in ten lines, with no hash under it', (
    tester,
  ) async {
    // 메시지 캐시는 앱 하나를 살아 있으니, 이 커밋만의 sha를 쓴다.
    const long = GitCommit(
      sha: 'f17ac0de5c4b3a2918e7d6c5b4a39281f0e6d5c4',
      shortSha: 'f17ac0d',
      parents: ['a9b3636'],
      author: GitIdentity(name: 'Ada Author', email: 'ada@example.com'),
      authorTimestamp: 1700000000,
      committer: GitIdentity(name: 'Cam Committer', email: 'cam@example.com'),
      committerTimestamp: 1700000120,
      refs: [],
      subject: 'docs: 긴 메시지',
    );
    await tester.pumpWidget(
      app(
        FakeGitRepository(
          (_, _) async => [long, parent],
          files: (_, _) async => const [
            GitFileChange(
              path: 'lib/a.dart',
              status: 'M',
              additions: 1,
              deletions: 1,
            ),
          ],
          commitMessage: (_) async => [
            long.subject,
            '',
            for (var line = 1; line <= 40; line++) '본문 $line 번째 줄',
          ].join('\n'),
        ),
        controller,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final body = find.byKey(const Key('preview-commit-body'));
    expect(body, findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('preview-commit-body-scroll')))
          .height,
      lessThanOrEqualTo(10 * 17.4),
      reason: '열 줄 넘게 자리를 차지하지 않는다',
    );
    expect(
      tester.getSize(body).height,
      greaterThan(10 * 17.4),
      reason: '나머지는 잘리는 게 아니라 스크롤 안에 남는다',
    );
    expect(
      find.textContaining(long.sha),
      findsNothing,
      reason: '전체 해시 줄은 헤더가 대신한다',
    );
    // 스크롤 막대는 손대기 전부터 보인다 — 넘치는 게 있다는 걸 알려야 하니까.
    expect(
      tester
          .widget<Scrollbar>(
            find.ancestor(
              of: find.byKey(const Key('preview-commit-body-scroll')),
              matching: find.byType(Scrollbar),
            ),
          )
          .thumbVisibility,
      isTrue,
    );
  });

  testWidgets('a preview that fits does not scroll away', (tester) async {
    await pumpPreview(tester);

    final scroll = find.byKey(const Key('preview-content-scroll'));
    final subject = find.descendant(
      of: find.byKey(const Key('preview-panel')),
      matching: find.text(child.subject),
    );
    final before = tester.getRect(subject);

    await tester.drag(scroll, const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.getRect(subject), before, reason: '더 볼 것이 없으면 내용이 제자리에 남는다');
  });

  testWidgets('a root commit has no parent to point at', (tester) async {
    await pumpPreview(tester, commits: [commit('91d03aa', 'feat: 첫 커밋')]);

    final header = find.byKey(const Key('preview-header'));
    expect(
      tester
          .widgetList<Text>(
            find.descendant(of: header, matching: find.byType(Text)),
          )
          .map((text) => text.textSpan?.toPlainText() ?? text.data ?? '')
          .join(' '),
      contains('루트 커밋'),
    );
    expect(find.byKey(const Key('preview-parent-card')), findsNothing);
  });
}
