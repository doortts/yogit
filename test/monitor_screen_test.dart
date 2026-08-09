import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/git.dart';
import 'package:yogit/github_api.dart';
import 'package:yogit/main.dart';
import 'package:yogit/monitor_screen.dart';
import 'package:yogit/pr_monitor.dart';
import 'package:yogit/settings.dart';
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
    /// [respond] returns one poll's `data`, or null to fail the request the way
    /// GitHub does — HTTP 200 with an `errors` array.
    PrMonitorService service(Map<String, Object?>? Function() respond) =>
        PrMonitorService(
          remote: const RemoteRepository(
            host: 'github.company.com',
            owner: 'team',
            repository: 'yonalist',
          ),
          monitoredBranch: 'dev',
          api: GitHubApi(
            apiBaseUrl: 'https://github.company.com/api/v3',
            token: 'token-1',
            send: (uri, {required method, required headers, body}) async {
              final data = respond();
              return (
                status: 200,
                body: jsonEncode(
                  data == null
                      ? {
                          'errors': [
                            {'message': 'gh: Not logged in'},
                          ],
                        }
                      : {'data': data},
                ),
              );
            },
          ),
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
      'latestReviews': {'totalCount': reviews.length, 'nodes': reviews},
      'commits': {
        'totalCount': 3,
        'nodes': [
          {
            'commit': {'statusCheckRollup': null},
          },
        ],
      },
    };

    Map<String, Object?> review(String login, String state) => {
      'author': {'login': login},
      'state': state,
    };

    Map<String, Object?> snapshot({
      List<Map<String, Object?>> open = const [],
      List<Map<String, Object?>> merged = const [],
      List<Map<String, Object?>> closed = const [],
    }) => {
      'repository': {
        'open': {'nodes': open},
        'merged': {'nodes': merged},
        'closed': {'nodes': closed},
      },
    };

    Map<String, Object?> snapshotWithPrs() => snapshot(
      open: [
        openPr(
          number: 22,
          reviews: [
            review('jh', 'APPROVED'),
            review('mk', 'APPROVED'),
            review('yj', 'APPROVED'),
            review('ab', 'APPROVED'),
            review('cd', 'COMMENTED'),
          ],
        ),
        openPr(number: 21, author: 'mk', reviewDecision: null),
      ],
      merged: [
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
      ],
      closed: [
        {
          'number': 18,
          'title': 'dup lane cache',
          'author': {'login': 'mk'},
          'baseRefName': 'dev',
          'closedAt': '2026-08-04T01:00:00Z',
          'comments': {
            'nodes': [
              {'body': '중복 구현 — #17로 대체'},
            ],
          },
        },
      ],
    );

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
            service: service(snapshotWithPrs),
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
            service: service(snapshot),
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
              service: service(snapshot),
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

      // The traffic lights clear the screen's own top bar content.
      final buttons = tester.getRect(find.byKey(const Key('window-close')));
      final title = tester.getRect(find.text('yonalist / dev'));
      expect(buttons.right, lessThan(title.left));
    });

    testWidgets('every monitor state can close its own window', (tester) async {
      final opened = <List<String>>[];
      final calls = <String>[];
      const channel = MethodChannel('test/yogit-notice-window');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return null;
          });

      await tester.pumpWidget(
        MonitorBootstrap(
          requestedPath: '/repo',
          branch: 'dev',
          gitExecutable: '/usr/bin/git',
          settingsStore: _FixedSettingsStore(),
          windowFrameController: WindowFrameController(channel: channel),
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

      expect(find.text('GitHub 연결이 필요합니다 — 설정에서 서버에 로그인하세요.'), findsOneWidget);
      // Outside an .app bundle there is nothing to open, so the button is away.
      expect(find.byKey(const Key('monitor-open-settings')), findsNothing);
      expect(opened, isEmpty);

      // The notice is a real window: traffic lights, esc, and a drag region.
      calls.clear();
      await tester.tap(find.byKey(const Key('window-minimize')));
      await tester.pumpAndSettle();
      expect(calls, ['minimizeWindow']);

      calls.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(calls, ['closeWindow']);

      calls.clear();
      await tester.tap(find.byKey(const Key('window-close')));
      await tester.pumpAndSettle();
      expect(calls, ['closeWindow']);

      calls.clear();
      await tester.drag(
        find.byKey(const Key('monitor-drag')),
        const Offset(30, 12),
      );
      await tester.pumpAndSettle();
      expect(calls, ['startDrag']);
    });

    testWidgets('an API failure shows the banner and retry reloads', (
      tester,
    ) async {
      var failing = true;
      await tester.pumpWidget(
        app(
          MonitorScreen(
            repository: localRepository(),
            branch: 'dev',
            repositoryName: 'yonalist',
            service: service(() => failing ? null : snapshotWithPrs()),
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

/// Settings that never touch the disk: the boot future gates a spinner, and
/// real file IO cannot complete while pumpAndSettle animates one.
class _FixedSettingsStore extends SettingsStore {
  _FixedSettingsStore() : super(File('/tmp/yogit-monitor-test-unused.json'));

  @override
  Future<AppSettings> load() async => const AppSettings();
}
