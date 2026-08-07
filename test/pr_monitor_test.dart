import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yogit/avatars.dart';
import 'package:yogit/github_api.dart';
import 'package:yogit/pr_monitor.dart';

/// Contract for the GraphQL-backed monitor service.
///
/// One poll = ONE GraphQL request. The document aliases three pull-request
/// connections (open toward the monitored branch, recently merged, recently
/// closed) and the response carries everything the screen needs — reviewer
/// identities via latestReviews (one entry per reviewer), exact reviewer
/// counts via totalCount, commit counts via totalCount, CI state via the tip
/// commit's statusCheckRollup, and each closed PR's last comment as its
/// closing reason. No follow-up calls.
void main() {
  Map<String, Object?> openNode({
    int number = 22,
    String title = 'feat: palette',
    String author = 'sc',
    bool draft = false,
    String mergeable = 'MERGEABLE',
    String? reviewDecision,
    List<Map<String, Object?>> latestReviews = const [],
    int? reviewerTotal,
    String? rollup,
    int commits = 1,
  }) => {
    'number': number,
    'title': title,
    'author': {'login': author},
    'headRefName': 'codex/palette',
    'baseRefName': 'dev',
    'isDraft': draft,
    'mergeable': mergeable,
    'reviewDecision': reviewDecision,
    'latestReviews': {
      'totalCount': reviewerTotal ?? latestReviews.length,
      'nodes': latestReviews,
    },
    'commits': {
      'totalCount': commits,
      'nodes': [
        {
          'commit': {
            'statusCheckRollup': rollup == null ? null : {'state': rollup},
          },
        },
      ],
    },
  };

  Map<String, Object?> review(String login, String state) => {
    'author': {'login': login},
    'state': state,
  };

  Map<String, Object?> snapshotBody({
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

  ({List<(Uri, String?)> calls, PrMonitorService service}) serviceWith(
    Map<String, Object?> data, {
    int status = 200,
  }) {
    final calls = <(Uri, String?)>[];
    final service = PrMonitorService(
      remote: const RemoteRepository(
        host: 'oss.navercorp.com',
        owner: 'team',
        repository: 'yonalist',
      ),
      monitoredBranch: 'dev',
      api: GitHubApi(
        apiBaseUrl: 'https://oss.navercorp.com/api/v3',
        token: 'token-1',
        send: (uri, {required method, required headers, body}) async {
          calls.add((uri, body));
          return (status: status, body: jsonEncode({'data': data}));
        },
      ),
    );
    return (calls: calls, service: service);
  }

  test('one poll is one GraphQL request carrying the branch', () async {
    final fixture = serviceWith(snapshotBody());
    await fixture.service.loadSnapshot();

    final (uri, body) = fixture.calls.single;
    expect(uri, Uri.parse('https://oss.navercorp.com/api/graphql'));
    final document = jsonDecode(body!) as Map<String, dynamic>;
    expect(document['variables'], {
      'owner': 'team',
      'name': 'yonalist',
      'branch': 'dev',
    });
    final query = document['query'] as String;
    // The three aliased connections and the count-not-list fields.
    expect(query, contains('open:'));
    expect(query, contains('merged:'));
    expect(query, contains('closed:'));
    expect(query, contains('latestReviews'));
    expect(query, contains('totalCount'));
    expect(query, contains('baseRefName'));
  });

  group('open pull requests', () {
    test('classifies each state with the documented precedence', () async {
      final fixture = serviceWith(
        snapshotBody(
          open: [
            openNode(number: 1, draft: true),
            openNode(
              number: 2,
              mergeable: 'CONFLICTING',
              reviewDecision: 'APPROVED',
            ),
            openNode(number: 3, reviewDecision: 'APPROVED', rollup: 'FAILURE'),
            openNode(number: 4, reviewDecision: 'CHANGES_REQUESTED'),
            openNode(number: 5, reviewDecision: 'APPROVED', rollup: 'SUCCESS'),
            openNode(number: 6),
          ],
        ),
      );

      final snapshot = await fixture.service.loadSnapshot();
      expect(snapshot.pullRequests.map((entry) => entry.state).toList(), [
        PrMonitorState.draft,
        PrMonitorState.conflict,
        PrMonitorState.ciFailing,
        PrMonitorState.changesRequested,
        PrMonitorState.readyToMerge,
        PrMonitorState.readyToReview,
      ]);
    });

    test('an ERROR rollup is a CI failure too', () async {
      final fixture = serviceWith(
        snapshotBody(open: [openNode(rollup: 'ERROR')]),
      );
      final snapshot = await fixture.service.loadSnapshot();
      expect(snapshot.pullRequests.single.state, PrMonitorState.ciFailing);
    });

    test(
      'mergeable maps to the merge-commit judgment, UNKNOWN to null',
      () async {
        final fixture = serviceWith(
          snapshotBody(
            open: [
              openNode(number: 1, mergeable: 'MERGEABLE'),
              openNode(number: 2, mergeable: 'CONFLICTING'),
              openNode(number: 3, mergeable: 'UNKNOWN'),
            ],
          ),
        );
        final snapshot = await fixture.service.loadSnapshot();
        expect(snapshot.pullRequests[0].mergeCommitPossible, isTrue);
        expect(snapshot.pullRequests[1].mergeCommitPossible, isFalse);
        expect(snapshot.pullRequests[2].mergeCommitPossible, isNull);
      },
    );

    test('latestReviews carries one entry per reviewer; the exact count comes '
        'from totalCount, not from the fetched page', () async {
      final fixture = serviceWith(
        snapshotBody(
          open: [
            openNode(
              author: 'sc',
              latestReviews: [
                review('jh', 'APPROVED'),
                review('mk', 'APPROVED'),
                // The author's own comment-review is not a reviewer.
                review('sc', 'COMMENTED'),
                review('yj', 'CHANGES_REQUESTED'),
              ],
              // GitHub says 12 reviewers exist; we only fetched a page.
              reviewerTotal: 12,
              commits: 3,
            ),
          ],
        ),
      );

      final entry = (await fixture.service.loadSnapshot()).pullRequests.single;
      expect(entry.reviewers, ['jh', 'mk', 'yj']);
      expect(entry.approvals, 2);
      // totalCount minus the author's own entry seen in the page.
      expect(entry.reviewerTotal, 11);
      expect(entry.commitCount, 3);
    });

    test('malformed nodes are dropped, not fatal', () async {
      final fixture = serviceWith(
        snapshotBody(
          open: [
            {'number': 'NaN'},
            openNode(number: 7),
          ],
        ),
      );
      final snapshot = await fixture.service.loadSnapshot();
      expect(snapshot.pullRequests.single.number, 7);
    });
  });

  group('history', () {
    test(
      'merged and closed become events with method and reason inline',
      () async {
        final fixture = serviceWith(
          snapshotBody(
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
                    {'body': '중복 구현 — #17로 대체\n상세는 스레드 참고'},
                  ],
                },
              },
            ],
          ),
        );

        final events = (await fixture.service.loadSnapshot()).events;
        expect(events, hasLength(3));
        expect(events[0].number, 20);
        expect(events[0].kind, PrEventKind.merged);
        expect(events[0].mergeCommitSha, 'abc123');
        expect(events[1].targetRef, 'release/1.4');
        expect(events[1].mergeCommitSha, isNull);
        expect(events[2].kind, PrEventKind.closed);
        expect(events[2].reason, '중복 구현 — #17로 대체');
      },
    );

    test('a merged PR appearing in the closed list stays one event', () async {
      final fixture = serviceWith(
        snapshotBody(
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
          ],
          closed: [
            {
              'number': 20,
              'title': 'palette fix',
              'author': {'login': 'sc'},
              'baseRefName': 'dev',
              'closedAt': '2026-08-07T01:00:00Z',
            },
          ],
        ),
      );
      final events = (await fixture.service.loadSnapshot()).events;
      expect(events.map((event) => event.number), [20]);
      expect(events.single.kind, PrEventKind.merged);
    });
  });

  test(
    'an API failure surfaces as PrMonitorException for the banner',
    () async {
      final fixture = serviceWith(const {}, status: 401);
      await expectLater(
        fixture.service.loadSnapshot(),
        throwsA(
          isA<PrMonitorException>().having(
            (error) => error.message,
            'message',
            contains('토큰'),
          ),
        ),
      );
    },
  );

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
}
