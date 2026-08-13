import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/git.dart';
import 'package:yogit/window_frame.dart';

import 'app_test.dart' show FakeGitRepository, app, commit;

/// 커밋 찾기: ⌘F로 줄이 열리고, 한 글자마다 해시와 제목을 다시 훑는다. 행이
/// 걸러지는 것이 아니라 찾은 글자에 불이 켜지고, 선택이 그 행으로 옮겨 간다.
/// Enter는 다음 결과, ⇧Enter는 이전 결과로 걸어간다.
void main() {
  late WindowFrameController controller;

  setUp(() {
    controller = WindowFrameController(
      channel: const MethodChannel('test/yogit-window'),
    );
  });

  final commits = [
    commit('a1b2c3d', 'fix(merge): 충돌 표시를 바로잡는다'),
    commit('b7e0f19', 'feat: 타임라인에서 커밋을 찾는다'),
    // 글자 단위로 읽으면 'nam'이 이 문장에서도 걸린다 — n(find)·a(hash)·m(commit).
    commit('c3d4e5f', 'feat: find a commit by hash or subject'),
    commit('d9a8b7c', 'feat: name a clipped sidebar ref in full on hover'),
  ];

  Future<void> pumpTimeline(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(FakeGitRepository((_, _) async => commits), controller),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const Key('timeline-search-field')),
      query,
    );
    await tester.pumpAndSettle();
  }

  /// 어떤 글자에 불이 켜졌는지. 행 전체가 아니라 질의가 짚은 글자만 나온다.
  List<String> litText(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(find.byType(Text)))
      if (text.textSpan case final TextSpan span)
        for (final child in span.children ?? const <InlineSpan>[])
          if (child case final TextSpan lit)
            if (lit.style?.backgroundColor != null) lit.text ?? '',
  ];

  String countLabel(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('timeline-search-count'))).data!;

  testWidgets('⌘F opens the field, and typing lights what it finds', (
    tester,
  ) async {
    await pumpTimeline(tester);
    expect(find.byKey(const Key('timeline-search')), findsNothing);

    await openSearch(tester);
    expect(find.byKey(const Key('timeline-search')), findsOneWidget);

    await search(tester, '커밋을');
    expect(countLabel(tester), '1/1');
    expect(litText(tester).join(), '커밋을');
    expect(
      find.byKey(const Key('selected-row-b7e0f19')),
      findsOneWidget,
      reason: '찾은 커밋으로 선택이 따라간다',
    );
  });

  testWidgets('the hash finds its row even where only seven are drawn', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await openSearch(tester);

    await search(tester, 'd9a8');
    expect(countLabel(tester), '1/1');
    expect(litText(tester).join(), 'd9a8');
  });

  testWidgets('a hash answers for what it draws, not for its buried middle', (
    tester,
  ) async {
    // '09c'는 40자리 해시 어딘가에는 거의 언제나 그 순서로 들어 있다. 그렇게
    // 찾으면 저장소의 거의 모든 커밋이 결과가 되고, 정작 화면에는 불이 켜질
    // 자리가 없다 — 결과에는 있는데 아무것도 안 보이는 행이 생긴다.
    const drawnSeven = GitCommit(
      sha: '89d85a509fc4b3a2918e7d6c5b4a39281f0e6d5c',
      shortSha: '89d85a5',
      parents: [],
      author: GitIdentity(name: 'Ada Author', email: 'ada@example.com'),
      authorTimestamp: 1700000000,
      committer: GitIdentity(name: 'Cam Committer', email: 'cam@example.com'),
      committerTimestamp: 1700000120,
      refs: [],
      subject: 'feat: 잘린 이름을 마우스 아래에서 펼친다',
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      app(FakeGitRepository((_, _) async => [drawnSeven]), controller),
    );
    await tester.pumpAndSettle();
    await openSearch(tester);

    await search(tester, '09c');
    expect(countLabel(tester), '없음');
    expect(litText(tester), isEmpty);

    // 화면에 그려진 일곱 자리로는 찾는다.
    await search(tester, '85a5');
    expect(countLabel(tester), '1/1');
    expect(litText(tester).join(), '85a5');

    // 통째로 붙여 넣은 긴 해시도 찾고, 그려진 일곱 자리 전부에 불이 켜진다.
    await search(tester, '89d85a509fc4');
    expect(countLabel(tester), '1/1');
    expect(litText(tester).join(), '89d85a5');
  });

  testWidgets('a query is read by words, not by scattered letters', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await openSearch(tester);

    // 'nam'은 'name' 안에 있다. 'find a commit by hash'에서 n·a·m을 주워 오지는
    // 않는다 — 그것이 낱말이 아니라 글자 세 개일 뿐이라서다.
    await search(tester, 'nam');
    expect(countLabel(tester), '1/1');
    expect(litText(tester).join(), 'nam');
    expect(find.byKey(const Key('selected-row-d9a8b7c')), findsOneWidget);

    // 낱말 하나가 여러 낱말에 걸칠 수는 없다.
    await search(tester, 'mrgfix');
    expect(countLabel(tester), '없음');

    // 구두점은 낱말을 가를 뿐이라, 붙여 쓴 질의도 낱말 둘로 읽는다.
    await search(tester, 'fix(merge)');
    expect(countLabel(tester), '1/1');
    expect(find.byKey(const Key('selected-row-a1b2c3d')), findsOneWidget);
  });

  testWidgets('two words are found in any order', (tester) async {
    await pumpTimeline(tester);
    await openSearch(tester);

    await search(tester, 'name hover');
    expect(countLabel(tester), '1/1');
    expect(litText(tester).join(' '), 'name hover');

    await search(tester, 'hover name');
    expect(countLabel(tester), '1/1', reason: '순서를 묻지 않는다');
    expect(litText(tester).join(' '), 'name hover');

    await search(tester, 'name 없는말');
    expect(countLabel(tester), '없음', reason: '하나라도 못 찾으면 결과가 아니다');
    expect(litText(tester), isEmpty, reason: '결과가 아닌 행에는 불도 켜지 않는다');
  });

  testWidgets('a word may answer from the hash and another from the subject', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await openSearch(tester);

    await search(tester, 'b7e0 커밋');
    expect(countLabel(tester), '1/1');
    expect(litText(tester).join(' '), 'b7e0 커밋');
  });

  testWidgets('Enter walks the matches and comes round the end', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await openSearch(tester);

    // 'feat'는 세 커밋의 제목에 있다.
    await search(tester, 'feat');
    expect(countLabel(tester), '1/3');
    expect(find.byKey(const Key('selected-row-b7e0f19')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(countLabel(tester), '2/3');
    expect(find.byKey(const Key('selected-row-c3d4e5f')), findsOneWidget);

    // 끝에서 한 번 더 가면 처음으로 돈다.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(countLabel(tester), '3/3');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(countLabel(tester), '1/3');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(countLabel(tester), '3/3', reason: '⇧Enter는 반대로 걷는다');
  });

  testWidgets('the buttons walk the same matches as the keys', (tester) async {
    await pumpTimeline(tester);
    await openSearch(tester);
    await search(tester, 'feat');

    await tester.tap(find.byKey(const Key('timeline-search-next')));
    await tester.pumpAndSettle();
    expect(countLabel(tester), '2/3');

    await tester.tap(find.byKey(const Key('timeline-search-previous')));
    await tester.pumpAndSettle();
    expect(countLabel(tester), '1/3');
  });

  testWidgets('a query nothing answers says so and moves nothing', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await openSearch(tester);
    await search(tester, 'zzzz');

    expect(countLabel(tester), '없음');
    expect(litText(tester), isEmpty);
    expect(
      find.byKey(const Key('selected-row-a1b2c3d')),
      findsOneWidget,
      reason: '찾은 것이 없으면 선택은 있던 자리에 남는다',
    );
  });

  testWidgets('a search that found nothing gives the reader their row back', (
    tester,
  ) async {
    await pumpTimeline(tester);
    // 검색을 열기 전에 읽고 있던 줄.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-c3d4e5f')), findsOneWidget);

    await openSearch(tester);
    // 찾은 줄로 선택이 옮겨 가고, 질의를 좁히면 결과가 사라진다.
    await search(tester, 'name');
    expect(find.byKey(const Key('selected-row-d9a8b7c')), findsOneWidget);
    await search(tester, 'name zzzz');
    expect(countLabel(tester), '없음');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('selected-row-c3d4e5f')),
      findsOneWidget,
      reason: '찾은 것이 없으면 검색을 열 때 서 있던 줄로 돌아온다',
    );
  });

  testWidgets('with no row read before the search, nothing found goes to the '
      'first row', (tester) async {
    await pumpTimeline(tester);
    await openSearch(tester);
    await search(tester, 'name');
    expect(find.byKey(const Key('selected-row-d9a8b7c')), findsOneWidget);
    await search(tester, 'zzzz');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-row-a1b2c3d')), findsOneWidget);
  });

  testWidgets('a search that found something leaves the reader on it', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await openSearch(tester);
    await search(tester, 'name');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('selected-row-d9a8b7c')),
      findsOneWidget,
      reason: '찾아서 간 줄은 검색을 닫아도 그대로다',
    );
  });

  testWidgets('Escape closes the field and puts the lights out', (
    tester,
  ) async {
    await pumpTimeline(tester);
    await openSearch(tester);
    await search(tester, 'fix');
    expect(litText(tester), isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('timeline-search')), findsNothing);
    expect(litText(tester), isEmpty);
    expect(
      find.text('fix(merge): 충돌 표시를 바로잡는다'),
      findsOneWidget,
      reason: '검색을 닫으면 행은 원래 글자로 돌아온다',
    );
  });

  testWidgets('the field never pushes the history down', (tester) async {
    await pumpTimeline(tester);
    final before = tester.getRect(find.byKey(const Key('timeline-list')));

    await openSearch(tester);

    expect(tester.getRect(find.byKey(const Key('timeline-list'))), before);
  });
}
