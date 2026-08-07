import 'dart:convert';

import 'avatars.dart';
import 'git.dart';

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
    this.approvals = 0,
    this.commitCount = 0,
  });

  final int number;
  final String title;
  final String author;
  final String headRef;
  final String baseRef;
  final PrMonitorState state;

  /// From gh's `mergeable`; null while GitHub is still computing it.
  final bool? mergeCommitPossible;

  /// Judged locally with the rebase preview machinery; null until judged.
  final bool? rebasePossible;

  /// Distinct review authors, PR author excluded, in first-review order.
  final List<String> reviewers;
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

/// Reads pull requests for one repository through the gh CLI, the same
/// executable the avatar service already depends on. Every method throws
/// [PrMonitorException] when gh fails, so the screen can show one banner.
class PrMonitorService {
  PrMonitorService({
    required this.remote,
    required this.monitoredBranch,
    this.ghExecutable = 'gh',
    this.runner = runProcess,
  });

  final RemoteRepository remote;
  final String monitoredBranch;
  final String ghExecutable;
  final CommandRunner runner;

  String get _repoFlag => '${remote.host}/${remote.owner}/${remote.repository}';

  /// Open PRs targeting [monitoredBranch], in gh's listing order.
  ///
  /// The field list is deliberately free of `commits`. GitHub rejects a query
  /// by the nodes it *could* return, and gh expands `commits` into a hundred
  /// commits per pull request: at [_listLimit] that alone is 500,000 nodes and
  /// the whole request is refused before it runs, no matter how few pull
  /// requests are actually open. The commit count comes from [_commitCounts]
  /// instead, which asks for the number rather than the commits.
  Future<List<MonitoredPullRequest>> loadOpenPullRequests() async {
    final entries = await _list('open', [
      'number',
      'title',
      'author',
      'headRefName',
      'baseRefName',
      'isDraft',
      'mergeable',
      'reviewDecision',
      'reviews',
      'statusCheckRollup',
    ]);
    final counts = await _commitCounts();
    final result = <MonitoredPullRequest>[];
    for (final entry in entries) {
      final parsed = _parseOpen(entry, counts);
      if (parsed != null && parsed.baseRef == monitoredBranch) {
        result.add(parsed);
      }
    }
    return result;
  }

  /// Commits per open pull request, keyed by number.
  ///
  /// `totalCount` on its own costs nothing to speak of, where asking for the
  /// commits and counting them locally costs the node budget the listing needs.
  /// A count is decoration on a row, so a failure here returns nothing rather
  /// than throwing: the monitor is worth more without the numbers than not at
  /// all.
  Future<Map<int, int>> _commitCounts() async {
    const query =
        'query(\$owner:String!,\$name:String!){'
        'repository(owner:\$owner,name:\$name){'
        'pullRequests(first:$_listLimit,states:OPEN){'
        'nodes{number commits{totalCount}}}}}';
    final result = await runner(ghExecutable, [
      'api',
      'graphql',
      '--hostname',
      remote.host,
      '-f',
      'query=$query',
      '-f',
      'owner=${remote.owner}',
      '-f',
      'name=${remote.repository}',
    ]);
    if (result.exitCode != 0) return const {};
    try {
      final json = jsonDecode(result.stdout.toString());
      if (json is! Map<String, dynamic>) return const {};
      final nodes = _dig(json, ['data', 'repository', 'pullRequests', 'nodes']);
      if (nodes is! List) return const {};
      final counts = <int, int>{};
      for (final node in nodes) {
        if (node is! Map<String, dynamic>) continue;
        final number = node['number'];
        final total = _dig(node, ['commits', 'totalCount']);
        if (number is int && total is int) counts[number] = total;
      }
      return counts;
    } on FormatException {
      return const {};
    }
  }

  static Object? _dig(Map<String, dynamic> json, List<String> path) {
    Object? here = json;
    for (final key in path) {
      if (here is! Map<String, dynamic>) return null;
      here = here[key];
    }
    return here;
  }

  /// Merged and closed PRs toward any branch, newest first — the history
  /// strip records work outside the monitored branch instead of drawing it.
  Future<List<PrHistoryEvent>> loadHistory() async {
    final merged = await _list('merged', [
      'number',
      'title',
      'author',
      'baseRefName',
      'mergedAt',
      'mergedBy',
      'mergeCommit',
    ]);
    final closed = await _list('closed', [
      'number',
      'title',
      'author',
      'baseRefName',
      'closedAt',
    ]);
    final events = <PrHistoryEvent>[];
    final mergedNumbers = <int>{};
    for (final entry in merged) {
      final event = _parseMerged(entry);
      if (event != null) {
        events.add(event);
        mergedNumbers.add(event.number);
      }
    }
    for (final entry in closed) {
      final event = _parseClosed(entry);
      // gh counts merged PRs as closed too; those already have an event.
      if (event != null && !mergedNumbers.contains(event.number)) {
        events.add(event);
      }
    }
    events.sort((left, right) => right.when.compareTo(left.when));
    return events;
  }

  /// The last comment's first line — the closest thing GitHub has to a
  /// closing reason. Null when there are no comments.
  Future<String?> loadCloseReason(int number) async {
    final result = await runner(ghExecutable, [
      'pr',
      'view',
      '$number',
      '--repo',
      _repoFlag,
      '--json',
      'comments',
    ]);
    if (result.exitCode != 0) {
      throw PrMonitorException(result.stderr.toString().trim());
    }
    try {
      final json = jsonDecode(result.stdout.toString());
      if (json is! Map<String, dynamic>) return null;
      final comments = json['comments'];
      if (comments is! List || comments.isEmpty) return null;
      final last = comments.last;
      if (last is! Map<String, dynamic>) return null;
      final body = '${last['body'] ?? ''}'.trim();
      if (body.isEmpty) return null;
      return body.split('\n').first.trim();
    } on FormatException {
      return null;
    }
  }

  /// How many pull requests one listing asks for. It is also the multiplier on
  /// every field's node cost, so raising it means re-checking what the fields
  /// expand to — see [loadOpenPullRequests].
  static const _listLimit = 50;

  Future<List<Object?>> _list(String state, List<String> fields) async {
    final result = await runner(ghExecutable, [
      'pr',
      'list',
      '--repo',
      _repoFlag,
      '--state',
      state,
      '--limit',
      '$_listLimit',
      '--json',
      fields.join(','),
    ]);
    if (result.exitCode != 0) {
      throw PrMonitorException(result.stderr.toString().trim());
    }
    try {
      final json = jsonDecode(result.stdout.toString());
      return json is List ? json : const [];
    } on FormatException {
      throw const PrMonitorException('gh가 올바른 JSON을 돌려주지 않았습니다');
    }
  }

  MonitoredPullRequest? _parseOpen(Object? entry, Map<int, int> commitCounts) {
    if (entry is! Map<String, dynamic>) return null;
    final number = entry['number'];
    final title = entry['title'];
    final headRef = entry['headRefName'];
    final baseRef = entry['baseRefName'];
    if (number is! int || title is! String) return null;
    if (headRef is! String || baseRef is! String) return null;
    final author = _login(entry['author']) ?? '';

    final reviews = entry['reviews'];
    final reviewers = <String>[];
    final approved = <String>{};
    if (reviews is List) {
      for (final review in reviews) {
        if (review is! Map<String, dynamic>) continue;
        final login = _login(review['author']);
        if (login == null || login == author) continue;
        if (!reviewers.contains(login)) reviewers.add(login);
        if (review['state'] == 'APPROVED') approved.add(login);
      }
    }

    final checks = entry['statusCheckRollup'];
    final ciFailing =
        checks is List &&
        checks.any(
          (check) =>
              check is Map<String, dynamic> && check['conclusion'] == 'FAILURE',
        );

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
      approvals: approved.length,
      commitCount: commitCounts[number] ?? 0,
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
    );
  }

  String? _login(Object? value) =>
      value is Map<String, dynamic> && value['login'] is String
      ? value['login'] as String
      : null;
}
