import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/pr_monitor.dart';

void main() {
  const remote = RemoteRepository(
    host: 'github.company.com',
    owner: 'team',
    repository: 'yonalist',
  );

  Map<String, Object?> pr({
    int number = 22,
    String title = 'feat: palette',
    String author = 'sc',
    String head = 'codex/palette',
    String base = 'dev',
    bool draft = false,
    String mergeable = 'MERGEABLE',
    String? reviewDecision,
    List<Map<String, Object?>> reviews = const [],
    List<Map<String, Object?>> checks = const [],
  }) => {
    'number': number,
    'title': title,
    'author': {'login': author},
    'headRefName': head,
    'baseRefName': base,
    'isDraft': draft,
    'mergeable': mergeable,
    'reviewDecision': reviewDecision,
    'reviews': reviews,
    'statusCheckRollup': checks,
  };

  /// The GraphQL shape gh returns for the commit-count query.
  String commitCountReply(Map<int, int> counts) => jsonEncode({
    'data': {
      'repository': {
        'pullRequests': {
          'nodes': [
            for (final entry in counts.entries)
              {
                'number': entry.key,
                'commits': {'totalCount': entry.value},
              },
          ],
        },
      },
    },
  });

  /// [respond] answers the `pr list` calls; the commit-count call is answered
  /// separately because it goes through `gh api graphql`, not `gh pr list`.
  PrMonitorService service(
    List<Object?> Function(List<String> arguments) respond, {
    Map<int, int> commitCounts = const {},
    List<String>? record,
  }) => PrMonitorService(
    remote: remote,
    monitoredBranch: 'dev',
    ghExecutable: 'gh',
    runner: (executable, arguments, {workingDirectory, environment}) async {
      record?.addAll(arguments);
      if (arguments.first == 'api') {
        return ProcessResult(1, 0, commitCountReply(commitCounts), '');
      }
      return ProcessResult(1, 0, jsonEncode(respond(arguments)), '');
    },
  );

  group('open PR classification', () {
    test('classifies each state with the documented precedence', () async {
      final prs = await service(
        (_) => [
          pr(number: 1, draft: true),
          pr(number: 2, mergeable: 'CONFLICTING', reviewDecision: 'APPROVED'),
          pr(
            number: 3,
            reviewDecision: 'APPROVED',
            checks: [
              {'conclusion': 'FAILURE'},
            ],
          ),
          pr(number: 4, reviewDecision: 'CHANGES_REQUESTED'),
          pr(
            number: 5,
            reviewDecision: 'APPROVED',
            checks: [
              {'conclusion': 'SUCCESS'},
            ],
          ),
          pr(number: 6),
        ],
      ).loadOpenPullRequests();

      expect(prs.map((entry) => entry.state).toList(), [
        PrMonitorState.draft,
        PrMonitorState.conflict,
        PrMonitorState.ciFailing,
        PrMonitorState.changesRequested,
        PrMonitorState.readyToMerge,
        PrMonitorState.readyToReview,
      ]);
    });

    test('keeps only PRs targeting the monitored branch', () async {
      final prs = await service(
        (_) => [pr(number: 1, base: 'dev'), pr(number: 2, base: 'release/1.4')],
      ).loadOpenPullRequests();

      expect(prs.map((entry) => entry.number).toList(), [1]);
    });

    test(
      'collects reviewers without the author, capped order stable',
      () async {
        final prs = await service(
          (_) => [
            pr(
              author: 'sc',
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
                  'author': {'login': 'jh'},
                  'state': 'COMMENTED',
                },
                {
                  'author': {'login': 'sc'},
                  'state': 'COMMENTED',
                },
                {
                  'author': {'login': 'yj'},
                  'state': 'CHANGES_REQUESTED',
                },
              ],
            ),
          ],
        ).loadOpenPullRequests();

        final entry = prs.single;
        expect(entry.reviewers, ['jh', 'mk', 'yj']);
        expect(entry.approvals, 2);
        expect(entry.author, 'sc');
      },
    );

    test('commit counts arrive per number from the count query', () async {
      final prs = await service(
        (_) => [pr(number: 7), pr(number: 9)],
        commitCounts: {7: 3, 9: 12},
      ).loadOpenPullRequests();

      expect(prs.map((entry) => entry.commitCount).toList(), [3, 12]);
    });

    test('a pull request the count query skipped still lists', () async {
      final prs = await service(
        (_) => [pr(number: 7)],
        commitCounts: const {},
      ).loadOpenPullRequests();

      expect(prs.single.number, 7);
      expect(prs.single.commitCount, 0);
    });

    // GitHub refuses a query by the nodes it could return, not the ones it
    // does. gh expands these fields into a hundred rows per pull request, so
    // at the listing limit any one of them puts the whole request over the
    // 500,000-node ceiling and nothing loads — for every repository, however
    // few pull requests are open.
    test('the listing never asks for a per-commit connection', () async {
      final arguments = <String>[];
      await service((_) => [pr()], record: arguments).loadOpenPullRequests();

      final fields = arguments[arguments.indexOf('--json') + 1].split(',');
      expect(fields, isNot(contains('commits')));
      expect(fields, isNot(contains('comments')));
      expect(fields, isNot(contains('files')));
      expect(fields, isNot(contains('closingIssuesReferences')));
    });

    test(
      'mergeCommitPossible follows gh mergeable, unknown stays null',
      () async {
        final prs = await service(
          (_) => [
            pr(number: 1, mergeable: 'MERGEABLE'),
            pr(number: 2, mergeable: 'CONFLICTING'),
            pr(number: 3, mergeable: 'UNKNOWN'),
          ],
        ).loadOpenPullRequests();

        expect(prs[0].mergeCommitPossible, isTrue);
        expect(prs[1].mergeCommitPossible, isFalse);
        expect(prs[2].mergeCommitPossible, isNull);
      },
    );

    test('malformed entries are dropped, not fatal', () async {
      final prs = await service(
        (_) => [
          'garbage',
          {'number': 'NaN'},
          pr(number: 7),
        ],
      ).loadOpenPullRequests();

      expect(prs.single.number, 7);
    });
  });

  group('history', () {
    test('merged and closed PRs become events, any target branch', () async {
      final events = await service(
        (arguments) =>
            arguments.join(' ').contains('state=merged') ||
                arguments.any((argument) => argument.contains('merged'))
            ? [
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
              ]
            : [
                {
                  'number': 18,
                  'title': 'dup lane cache',
                  'author': {'login': 'mk'},
                  'baseRefName': 'dev',
                  'closedAt': '2026-08-04T01:00:00Z',
                },
              ],
      ).loadHistory();

      expect(events, hasLength(3));
      expect(events[0].number, 20);
      expect(events[0].kind, PrEventKind.merged);
      expect(events[0].targetRef, 'dev');
      expect(events[0].mergeCommitSha, 'abc123');
      expect(events[1].number, 19);
      expect(events[1].targetRef, 'release/1.4');
      expect(events[2].kind, PrEventKind.closed);
      expect(events[2].actor, 'mk');
      // Newest first.
      expect(
        [for (final event in events) event.when.isAfter(events.last.when)],
        [true, true, false],
      );
    });
  });

  test('ghost ordering: closest to HEAD merges first', () {
    final order = [
      PrMonitorState.draft,
      PrMonitorState.conflict,
      PrMonitorState.readyToMerge,
      PrMonitorState.readyToReview,
      PrMonitorState.changesRequested,
      PrMonitorState.ciFailing,
    ]..sort((left, right) => ghostPriority(left) - ghostPriority(right));

    expect(order, [
      PrMonitorState.readyToMerge,
      PrMonitorState.readyToReview,
      PrMonitorState.changesRequested,
      PrMonitorState.ciFailing,
      PrMonitorState.conflict,
      PrMonitorState.draft,
    ]);
  });

  test('close reason is the last comment, first line only', () async {
    final withComments = PrMonitorService(
      remote: remote,
      monitoredBranch: 'dev',
      ghExecutable: 'gh',
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(
            1,
            0,
            jsonEncode({
              'comments': [
                {'body': '먼저 남긴 코멘트'},
                {'body': '중복 구현 — #17로 대체\n자세한 배경은 위 스레드 참고'},
              ],
            }),
            '',
          ),
    );
    expect(await withComments.loadCloseReason(18), '중복 구현 — #17로 대체');

    final noComments = PrMonitorService(
      remote: remote,
      monitoredBranch: 'dev',
      ghExecutable: 'gh',
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 0, jsonEncode({'comments': []}), ''),
    );
    expect(await noComments.loadCloseReason(18), isNull);
  });

  test('a failing gh call surfaces a PrMonitorException', () async {
    final failing = PrMonitorService(
      remote: remote,
      monitoredBranch: 'dev',
      ghExecutable: 'gh',
      runner: (executable, arguments, {workingDirectory, environment}) async =>
          ProcessResult(1, 4, '', 'gh: Not logged in'),
    );

    await expectLater(
      failing.loadOpenPullRequests(),
      throwsA(
        isA<PrMonitorException>().having(
          (error) => error.message,
          'message',
          contains('Not logged in'),
        ),
      ),
    );
  });
}
