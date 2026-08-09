import 'avatars.dart';
import 'github_api.dart';

/// One open pull request's place in the monitor, most blocked last.
enum PrMonitorState {
  draft,
  readyToReview,
  changesRequested,
  readyToMerge,
  ciFailing,
  conflict,
}

/// Ghost commits stack above HEAD in merge-likelihood order: the closest is
/// the one expected to land next.
int ghostPriority(PrMonitorState state) => switch (state) {
  PrMonitorState.readyToMerge => 0,
  PrMonitorState.readyToReview => 1,
  PrMonitorState.changesRequested => 2,
  PrMonitorState.ciFailing => 3,
  PrMonitorState.conflict => 4,
  PrMonitorState.draft => 5,
};

class MonitoredPullRequest {
  const MonitoredPullRequest({
    required this.number,
    required this.title,
    required this.author,
    required this.headRef,
    required this.baseRef,
    required this.state,
    required this.mergeCommitPossible,
    this.rebasePossible,
    this.reviewers = const [],
    this.reviewerTotal = 0,
    this.approvals = 0,
    this.commitCount = 0,
  });

  final int number;
  final String title;
  final String author;
  final String headRef;
  final String baseRef;
  final PrMonitorState state;

  /// From GitHub's `mergeable`; null while GitHub is still computing it.
  final bool? mergeCommitPossible;

  /// Judged locally with the rebase preview machinery; null until judged.
  final bool? rebasePossible;

  /// Distinct review authors, PR author excluded, in first-review order —
  /// only as many as one page carried.
  final List<String> reviewers;

  /// Every reviewer GitHub counts, author excluded, however few [reviewers]
  /// holds. A card showing three faces needs this to say how many more exist.
  final int reviewerTotal;

  final int approvals;
  final int commitCount;

  MonitoredPullRequest withRebasePossible(bool? value) => MonitoredPullRequest(
    number: number,
    title: title,
    author: author,
    headRef: headRef,
    baseRef: baseRef,
    state: state,
    mergeCommitPossible: mergeCommitPossible,
    rebasePossible: value,
    reviewers: reviewers,
    reviewerTotal: reviewerTotal,
    approvals: approvals,
    commitCount: commitCount,
  );
}

enum PrEventKind { merged, closed }

class PrHistoryEvent {
  const PrHistoryEvent({
    required this.kind,
    required this.number,
    required this.title,
    required this.actor,
    required this.targetRef,
    required this.when,
    this.mergeCommitSha,
    this.reason,
  });

  final PrEventKind kind;
  final int number;
  final String title;
  final String actor;
  final String targetRef;
  final DateTime when;

  /// Present on merge events that produced a merge commit; a rebase or squash
  /// leaves it null, which is itself the method signal.
  final String? mergeCommitSha;
  final String? reason;
}

class PrMonitorException implements Exception {
  const PrMonitorException(this.message);

  final String message;

  @override
  String toString() => 'PrMonitorException: $message';
}

/// Everything one poll puts on screen.
class PrMonitorSnapshot {
  const PrMonitorSnapshot({required this.pullRequests, required this.events});

  final List<MonitoredPullRequest> pullRequests;
  final List<PrHistoryEvent> events;
}

/// Reads pull requests for one repository over the GitHub GraphQL API.
///
/// One poll is one request. The document below asks for counts rather than
/// lists wherever a count is what the screen shows — reviewer totals, commit
/// totals — because GitHub prices a query by the nodes it *could* return, and
/// expanding those lists gets the whole request refused before it runs.
class PrMonitorService {
  PrMonitorService({
    required this.remote,
    required this.monitoredBranch,
    required this.api,
  });

  final RemoteRepository remote;
  final String monitoredBranch;
  final GitHubApi api;

  /// Three aliased connections: what is coming toward the monitored branch,
  /// what recently merged anywhere, what recently closed anywhere. A closed
  /// PR's last comment rides along as its closing reason, so the history strip
  /// needs no follow-up call per row.
  static const _document = r'''
query($owner:String!,$name:String!,$branch:String!){
  repository(owner:$owner,name:$name){
    open: pullRequests(states:OPEN, baseRefName:$branch, first:30,
        orderBy:{field:CREATED_AT,direction:DESC}){
      nodes{
        number title isDraft mergeable reviewDecision author{login}
        headRefName baseRefName
        latestReviews(first:10){ totalCount nodes{ author{login} state } }
        commits(last:1){
          totalCount nodes{ commit{ statusCheckRollup{ state } } } } } }
    merged: pullRequests(states:MERGED, first:20,
        orderBy:{field:UPDATED_AT,direction:DESC}){
      nodes{
        number title author{login} baseRefName mergedAt mergedBy{login}
        mergeCommit{oid} } }
    closed: pullRequests(states:CLOSED, first:20,
        orderBy:{field:UPDATED_AT,direction:DESC}){
      nodes{
        number title author{login} baseRefName closedAt
        comments(last:1){ nodes{ body } } } } } }
''';

  Future<PrMonitorSnapshot> loadSnapshot() async {
    final Map<String, dynamic> data;
    try {
      data = await api.graphql(_document, {
        'owner': remote.owner,
        'name': remote.repository,
        'branch': monitoredBranch,
      });
    } on GitHubApiException catch (error) {
      throw PrMonitorException(error.message);
    }
    final repository = data['repository'];
    if (repository is! Map<String, dynamic>) {
      return const PrMonitorSnapshot(pullRequests: [], events: []);
    }

    final pullRequests = <MonitoredPullRequest>[];
    for (final node in _nodes(repository['open'])) {
      final parsed = _parseOpen(node);
      if (parsed != null) pullRequests.add(parsed);
    }

    final events = <PrHistoryEvent>[];
    final mergedNumbers = <int>{};
    for (final node in _nodes(repository['merged'])) {
      final event = _parseMerged(node);
      if (event != null) {
        events.add(event);
        mergedNumbers.add(event.number);
      }
    }
    for (final node in _nodes(repository['closed'])) {
      final event = _parseClosed(node);
      // GitHub counts merged PRs as closed too; those already have an event.
      if (event != null && !mergedNumbers.contains(event.number)) {
        events.add(event);
      }
    }
    events.sort((left, right) => right.when.compareTo(left.when));

    return PrMonitorSnapshot(pullRequests: pullRequests, events: events);
  }

  MonitoredPullRequest? _parseOpen(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;
    final number = entry['number'];
    final title = entry['title'];
    final headRef = entry['headRefName'];
    final baseRef = entry['baseRefName'];
    if (number is! int || title is! String) return null;
    if (headRef is! String || baseRef is! String) return null;
    final author = _login(entry['author']) ?? '';

    final reviewers = <String>[];
    final approved = <String>{};
    var authorReviewed = false;
    for (final review in _nodes(entry['latestReviews'])) {
      if (review is! Map<String, dynamic>) continue;
      final login = _login(review['author']);
      if (login == null) continue;
      if (login == author) {
        // The author's own review is not a review of theirs to wait on, but
        // GitHub counted it, so totalCount has to lose it as well.
        authorReviewed = true;
        continue;
      }
      if (!reviewers.contains(login)) reviewers.add(login);
      if (review['state'] == 'APPROVED') approved.add(login);
    }
    final reviewerTotal =
        _totalCount(entry['latestReviews']) - (authorReviewed ? 1 : 0);

    final rollup = _rollupState(entry['commits']);
    final ciFailing = rollup == 'FAILURE' || rollup == 'ERROR';

    final mergeable = entry['mergeable'];
    final state = entry['isDraft'] == true
        ? PrMonitorState.draft
        : mergeable == 'CONFLICTING'
        ? PrMonitorState.conflict
        : ciFailing
        ? PrMonitorState.ciFailing
        : entry['reviewDecision'] == 'CHANGES_REQUESTED'
        ? PrMonitorState.changesRequested
        : entry['reviewDecision'] == 'APPROVED'
        ? PrMonitorState.readyToMerge
        : PrMonitorState.readyToReview;

    return MonitoredPullRequest(
      number: number,
      title: title,
      author: author,
      headRef: headRef,
      baseRef: baseRef,
      state: state,
      mergeCommitPossible: switch (mergeable) {
        'MERGEABLE' => true,
        'CONFLICTING' => false,
        _ => null,
      },
      reviewers: reviewers,
      reviewerTotal: reviewerTotal < 0 ? 0 : reviewerTotal,
      approvals: approved.length,
      commitCount: _totalCount(entry['commits']),
    );
  }

  PrHistoryEvent? _parseMerged(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;
    final number = entry['number'];
    final title = entry['title'];
    final baseRef = entry['baseRefName'];
    final when = DateTime.tryParse('${entry['mergedAt'] ?? ''}');
    if (number is! int || title is! String || baseRef is! String) return null;
    if (when == null) return null;
    final mergeCommit = entry['mergeCommit'];
    return PrHistoryEvent(
      kind: PrEventKind.merged,
      number: number,
      title: title,
      actor: _login(entry['mergedBy']) ?? _login(entry['author']) ?? '',
      targetRef: baseRef,
      when: when,
      mergeCommitSha: mergeCommit is Map<String, dynamic>
          ? mergeCommit['oid'] as String?
          : null,
    );
  }

  PrHistoryEvent? _parseClosed(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;
    final number = entry['number'];
    final title = entry['title'];
    final baseRef = entry['baseRefName'];
    final when = DateTime.tryParse('${entry['closedAt'] ?? ''}');
    if (number is! int || title is! String || baseRef is! String) return null;
    if (when == null) return null;
    return PrHistoryEvent(
      kind: PrEventKind.closed,
      number: number,
      title: title,
      actor: _login(entry['author']) ?? '',
      targetRef: baseRef,
      when: when,
      reason: _closeReason(entry['comments']),
    );
  }

  /// The last comment's first line — the closest thing GitHub has to a
  /// closing reason. Null when there are no comments.
  static String? _closeReason(Object? comments) {
    final nodes = _nodes(comments);
    if (nodes.isEmpty) return null;
    final last = nodes.last;
    if (last is! Map<String, dynamic>) return null;
    final body = '${last['body'] ?? ''}'.trim();
    if (body.isEmpty) return null;
    return body.split('\n').first.trim();
  }

  /// The tip commit's combined check state, or null when nothing ran.
  static Object? _rollupState(Object? commits) {
    final nodes = _nodes(commits);
    if (nodes.isEmpty) return null;
    final node = nodes.last;
    if (node is! Map<String, dynamic>) return null;
    final commit = node['commit'];
    if (commit is! Map<String, dynamic>) return null;
    final rollup = commit['statusCheckRollup'];
    return rollup is Map<String, dynamic> ? rollup['state'] : null;
  }

  static List<Object?> _nodes(Object? connection) {
    if (connection is! Map<String, dynamic>) return const [];
    final nodes = connection['nodes'];
    return nodes is List ? nodes : const [];
  }

  static int _totalCount(Object? connection) =>
      connection is Map<String, dynamic> && connection['totalCount'] is int
      ? connection['totalCount'] as int
      : 0;

  static String? _login(Object? value) =>
      value is Map<String, dynamic> && value['login'] is String
      ? value['login'] as String
      : null;
}
