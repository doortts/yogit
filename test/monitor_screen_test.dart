import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/git.dart';
import 'package:yogit/main.dart';
import 'package:yogit/monitor_screen.dart';
import 'package:yogit/pr_monitor.dart';
import 'package:yogit/window_frame.dart';

MonitoredPullRequest pr({
  int number = 22,
  String title = 'feat: palette',
  String author = 'sc',
  PrMonitorState state = PrMonitorState.readyToMerge,
  bool? mergeCommitPossible = true,
  bool? rebasePossible,
  List<String> reviewers = const ['jh'],
  int approvals = 1,
}) => MonitoredPullRequest(
  number: number,
  title: title,
  author: author,
  headRef: 'codex/palette',
  baseRef: 'dev',
  state: state,
  mergeCommitPossible: mergeCommitPossible,
  rebasePossible: rebasePossible,
  reviewers: reviewers,
  approvals: approvals,
  commitCount: 3,
);

void main() {
  group('MonitorLayout', () {
    const size = Size(1200, 800);

    test('ghosts stack above HEAD, ready-to-merge closest', () {
      final layout = MonitorLayout(
        size: size,
        commitCount: 4,
        pullRequests: [
          pr(number: 21, state: PrMonitorState.readyToReview),
          pr(number: 22, state: PrMonitorState.readyToMerge),
        ],
      );

      expect(layout.orderedPullRequests.first.number, 22);
      final ready = layout.ghostCenter(0);
      final review = layout.ghostCenter(1);
      expect(ready.dx, layout.laneX);
      expect(review.dx, layout.laneX);
      // Closest to HEAD = largest y (HEAD sits below the future zone).
      expect(ready.dy, greaterThan(review.dy));
      expect(ready.dy, lessThan(layout.headY));
      expect(layout.commitCenter(0).dy, layout.headY);
      expect(layout.commitCenter(1).dy, greaterThan(layout.commitCenter(0).dy));
    });

    test('cards never touch the lane column and never overlap', () {
      final layout = MonitorLayout(
        size: size,
        commitCount: 4,
        pullRequests: [
          pr(number: 1, state: PrMonitorState.readyToMerge),
          pr(number: 2, state: PrMonitorState.readyToReview),
          pr(number: 3, state: PrMonitorState.changesRequested),
          pr(number: 4, state: PrMonitorState.draft),
        ],
      );

      final laneColumn = Rect.fromLTRB(
        layout.laneX - 40,
        0,
        layout.laneX + 40,
        size.height,
      );
      final rects = [for (var i = 0; i < 4; i++) layout.cardRect(i)];
      for (final rect in rects) {
        expect(rect.overlaps(laneColumn), isFalse);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
      }
      for (var a = 0; a < rects.length; a++) {
        for (var b = a + 1; b < rects.length; b++) {
          expect(
            rects[a].overlaps(rects[b]),
            isFalse,
            reason: 'card $a overlaps card $b',
          );
        }
      }
    });

    test('arrows run from the card side edge to the ghost edge', () {
      final layout = MonitorLayout(
        size: size,
        commitCount: 2,
        pullRequests: [
          pr(number: 1, state: PrMonitorState.readyToMerge),
          pr(number: 2, state: PrMonitorState.readyToReview),
        ],
      );

      final leftArrow = layout.arrow(0);
      final leftCard = layout.cardRect(0);
      expect(leftArrow.from.dx, leftCard.right);
      expect(leftArrow.to.dx, lessThan(layout.laneX));
      expect(leftArrow.to.dx, greaterThan(leftCard.right));

      final rightArrow = layout.arrow(1);
      final rightCard = layout.cardRect(1);
      expect(rightArrow.from.dx, rightCard.left);
      expect(rightArrow.to.dx, greaterThan(layout.laneX));
    });
  });

  group('MonitorScreen', () {
    PrMonitorService service(
      Object? Function(List<String> arguments) respond, {
      List<int>? callCount,
    }) => PrMonitorService(
      remote: const RemoteRepository(
        host: 'github.company.com',
        owner: 'team',
        repository: 'yonalist',
      ),
      monitoredBranch: 'dev',
      ghExecutable: 'gh',
      runner: (executable, arguments, {workingDirectory, environment}) async {
        callCount?.add(1);
        final body = respond(arguments);
        if (body == null) return ProcessResult(1, 4, '', 'gh: Not logged in');
        return ProcessResult(1, 0, jsonEncode(body), '');
      },
    );

    GitRepository localRepository() => GitRepository(
      '/repo',
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(
            1,
            0,
            'aaa1\x00feat: lane cache\x00sc\x001754500000\n'
                'bbb2\x00fix: plan audit\x00jh\x001754400000\n',
            '',
          ),
    );

    Map<String, Object?> openPr({
      required int number,
      String author = 'sc',
      String? reviewDecision = 'APPROVED',
      List<Map<String, Object?>> reviews = const [],
    }) => {
      'number': number,
      'title': 'feat: palette',
      'author': {'login': author},
      'headRefName': 'codex/palette',
      'baseRefName': 'dev',
      'isDraft': false,
      'mergeable': 'MERGEABLE',
      'reviewDecision': reviewDecision,
      'reviews': reviews,
      'statusCheckRollup': const <Object>[],
      'commits': const [<String, Object?>{}],
    };

    Object? respondWithPrs(List<String> arguments) {
      if (arguments.contains('view')) {
        return {
          'comments': [
            {'body': '중복 구현 — #17로 대체'},
          ],
        };
      }
      if (arguments.contains('merged')) {
        return [
          {
            'number': 20,
            'title': 'palette fix',
            'author': {'login': 'sc'},
            'baseRefName': 'dev',
            'mergedAt': '2026-08-07T01:00:00Z',
            'mergedBy': {'login': 'sc'},
            'mergeCommit': {'oid': 'abc123'},
          },
          {
            'number': 19,
            'title': 'audit recovery',
            'author': {'login': 'jh'},
            'baseRefName': 'release/1.4',
            'mergedAt': '2026-08-06T01:00:00Z',
            'mergedBy': {'login': 'jh'},
            'mergeCommit': null,
          },
        ];
      }
      if (arguments.contains('closed')) {
        return [
          {
            'number': 18,
            'title': 'dup lane cache',
            'author': {'login': 'mk'},
            'baseRefName': 'dev',
            'closedAt': '2026-08-04T01:00:00Z',
          },
        ];
      }
      return [
        openPr(
          number: 22,
          reviews: [
            {
              'author': {'login': 'jh'},
              'state': 'APPROVED',
            },
            {
              'author': {'login': 'mk'},
              'state': 'APPROVED',
            },
            {
              'author': {'login': 'yj'},
              'state': 'APPROVED',
            },
            {
              'author': {'login': 'ab'},
              'state': 'APPROVED',
            },
            {
              'author': {'login': 'cd'},
              'state': 'COMMENTED',
            },
          ],
        ),
        openPr(number: 21, author: 'mk', reviewDecision: null),
      ];
    }

    Widget app(Widget child) => MaterialApp(home: child);

    testWidgets('renders lane, cards, reviewer overflow, and history', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(
        app(
          MonitorScreen(
            repository: localRepository(),
            branch: 'dev',
            repositoryName: 'yonalist',
            service: service(respondWithPrs),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('yonalist / dev'), findsOneWidget);
      expect(find.text('#22 feat: palette'), findsOneWidget);
      expect(find.text('#21 feat: palette'), findsOneWidget);
      // Reviewer avatars cap at three, the rest become 외 N명.
      expect(find.byKey(const Key('monitor-reviewer-22-jh')), findsOneWidget);
      expect(find.byKey(const Key('monitor-reviewer-22-mk')), findsOneWidget);
      expect(find.byKey(const Key('monitor-reviewer-22-yj')), findsOneWidget);
      expect(find.byKey(const Key('monitor-reviewer-22-ab')), findsNothing);
      expect(find.textContaining('외 2명'), findsOneWidget);
      // Judgments and ghost labels.
      expect(find.textContaining('M✓'), findsNWidgets(2));
      expect(find.textContaining('#22 머지 예정'), findsOneWidget);
      // Local commits under HEAD.
      expect(find.textContaining('feat: lane cache'), findsOneWidget);
      // History strip: method by merge commit presence, closed with reason.
      expect(find.textContaining('merge commit → dev'), findsOneWidget);
      expect(
        find.textContaining('rebase/squash → release/1.4'),
        findsOneWidget,
      );
      expect(find.textContaining('중복 구현 — #17로 대체'), findsOneWidget);

      // The ready PR's card must not cover the lane.
      final laneX = tester.getSize(find.byType(MonitorScreen)).width / 2;
      final cardRect = tester.getRect(find.byKey(const Key('monitor-card-22')));
      expect(
        cardRect.overlaps(Rect.fromLTRB(laneX - 40, 0, laneX + 40, 900)),
        isFalse,
      );
    });

    testWidgets('says so when no PR approaches the branch', (tester) async {
      await tester.pumpWidget(
        app(
          MonitorScreen(
            repository: localRepository(),
            branch: 'dev',
            repositoryName: 'yonalist',
            service: service(
              (arguments) => arguments.contains('open') ? [] : <Object>[],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('dev로 향하는 열린 PR 없음'), findsOneWidget);
    });

    testWidgets('esc asks the native window to close', (tester) async {
      final calls = <String>[];
      const channel = MethodChannel('test/yogit-monitor-window');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return null;
          });

      await tester.pumpWidget(
        app(
          MonitorWindow(
            controller: WindowFrameController(channel: channel),
            child: MonitorScreen(
              repository: localRepository(),
              branch: 'dev',
              repositoryName: 'yonalist',
              service: service(
                (arguments) => arguments.contains('open') ? [] : <Object>[],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The window maximizes itself once on entry.
      expect(calls, contains('toggleZoom'));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(calls, contains('closeWindow'));
    });

    testWidgets('missing gh offers the download link', (tester) async {
      final opened = <List<String>>[];
      await tester.pumpWidget(
        MonitorBootstrap(
          requestedPath: '/repo',
          branch: 'dev',
          gitExecutable: '/usr/bin/git',
          ghExecutable: null,
          runner:
              (executable, arguments, {workingDirectory, environment}) async {
                if (executable == '/usr/bin/open') {
                  opened.add(arguments);
                  return ProcessResult(1, 0, '', '');
                }
                if (arguments.contains('rev-parse')) {
                  return ProcessResult(1, 0, '/repo\n', '');
                }
                return ProcessResult(1, 1, '', 'no origin');
              },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('모니터링에는 GitHub CLI(gh)가 필요합니다.'), findsOneWidget);
      await tester.tap(find.text('https://cli.github.com'));
      expect(opened, [
        ['https://cli.github.com'],
      ]);
    });

    testWidgets('a gh failure shows the banner and retry reloads', (
      tester,
    ) async {
      var failing = true;
      final calls = <int>[];
      await tester.pumpWidget(
        app(
          MonitorScreen(
            repository: localRepository(),
            branch: 'dev',
            repositoryName: 'yonalist',
            service: service(
              (arguments) => failing ? null : respondWithPrs(arguments),
              callCount: calls,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Not logged in'), findsOneWidget);
      expect(find.text('재시도'), findsOneWidget);

      failing = false;
      await tester.tap(find.text('재시도'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not logged in'), findsNothing);
      expect(find.text('#22 feat: palette'), findsOneWidget);
    });
  });
}
