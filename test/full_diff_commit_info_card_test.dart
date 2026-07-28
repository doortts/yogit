import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/full_diff_commit_info_card.dart';
import 'package:yogit/typography.dart';

import 'support/full_diff_fixtures.dart';

String commitMessageLines(int count) =>
    List.generate(count, (index) => 'line ${index + 1}').join('\n');

void main() {
  testWidgets(
    'shows fallback immediately and complete message up to eight lines',
    (tester) async {
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

      completer.complete(
        List.generate(10, (index) => 'line $index').join('\n'),
      );
      await tester.pump();

      final message = tester.widget<Text>(
        find.byKey(const Key('full-diff-commit-message')),
      );
      expect(message.maxLines, 8);
      expect(message.overflow, TextOverflow.ellipsis);
      expect(message.data, contains('line 9'));
      expect(find.textContaining('Suwon Chae'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('full-diff-commit-metadata')),
          matching: find.text('·'),
        ),
        findsNWidgets(2),
      );
      expect(
        tester.widget<Text>(find.text('40aff6d')).style?.fontFamily,
        technicalFontFamily,
      );
      expect(
        tester.widget<Text>(find.text('Suwon Chae')).style?.fontFamily,
        isNot(technicalFontFamily),
      );
      final local = DateTime.fromMillisecondsSinceEpoch(1704067200 * 1000);
      final expectedTime =
          '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
      expect(find.textContaining(expectedTime), findsOneWidget);
    },
  );

  testWidgets('metadata separators wrap inside a narrow commit card', (
    tester,
  ) async {
    await tester.pumpWidget(
      qaApp(
        const SizedBox(
          width: 150,
          child: FullDiffCommitInfoCard(
            info: FullDiffCommitInfo(
              sha: '40aff6d123',
              shortSha: '40aff6d',
              fallbackMessage: 'Fallback subject',
              author: 'Suwon Chae',
              timestamp: 1704067200,
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .getSize(find.byKey(const Key('full-diff-commit-card-surface')))
          .width,
      lessThanOrEqualTo(150),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('full-diff-commit-metadata')),
        matching: find.text('·'),
      ),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('ignores a late message for the previously selected SHA', (
    tester,
  ) async {
    final first = Completer<String>();
    final second = Completer<String>();
    final key = GlobalKey<_CardHostState>();

    await tester.pumpWidget(
      qaApp(_CardHost(key: key, first: first, second: second)),
    );

    key.currentState!.showSecond();
    await tester.pump();
    second.complete('Second body');
    await tester.pump();
    first.complete('First body');
    await tester.pump();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('full-diff-commit-message')))
          .data,
      'Second body',
    );
  });

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
}

class _CardHost extends StatefulWidget {
  const _CardHost({required this.first, required this.second, super.key});

  final Completer<String> first;
  final Completer<String> second;

  @override
  State<_CardHost> createState() => _CardHostState();
}

class _CardHostState extends State<_CardHost> {
  var _showingSecond = false;

  void showSecond() => setState(() => _showingSecond = true);

  @override
  Widget build(BuildContext context) => FullDiffCommitInfoCard(
    info: _showingSecond
        ? const FullDiffCommitInfo(
            sha: 'second',
            shortSha: 'second',
            fallbackMessage: 'Second fallback',
            author: 'Second author',
            timestamp: null,
          )
        : const FullDiffCommitInfo(
            sha: 'first',
            shortSha: 'first',
            fallbackMessage: 'First fallback',
            author: 'First author',
            timestamp: null,
          ),
    loadMessage: (sha) =>
        sha == 'first' ? widget.first.future : widget.second.future,
  );
}

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
