import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'avatars.dart';
import 'git.dart';
import 'settings.dart';
import 'timeline_palette.dart';

const _ellipsis = '…';

/// The timeline's model: how commits become rows, how a branch preview lays out
/// its virtual commits, how refs pick their colours, and how a name is fitted to
/// a chip. No widgets here — every function is one the tests can call directly.

String fitRefName(
  String name,
  double maxWidth,
  double Function(String) measure,
) {
  if (measure(name) <= maxWidth) return name;
  var base = name;
  if (name.contains('/')) {
    final segments = name.split('/');
    final short = [
      for (final segment in segments.take(segments.length - 1))
        // A segment of two characters or fewer already costs what its
        // abbreviation would, so it stays whole.
        segment.characters.length > 2
            ? '${segment.characters.first}$_ellipsis'
            : segment,
      segments.last,
    ].join('/');
    if (short.length < name.length) {
      if (measure(short) <= maxWidth) return short;
      base = short;
    }
  }
  final tail = base.characters;
  for (var dropped = 1; dropped < tail.length; dropped++) {
    final candidate = '$_ellipsis${tail.skip(dropped)}';
    if (measure(candidate) <= maxWidth) return candidate;
  }
  return _ellipsis;
}

enum PreviewGraphNodeKind {
  actual,
  virtualMerge,
  virtualRebase,
  virtualRebaseMerge,
  conflictTarget,
}

typedef RebaseGraphMapping = ({
  String originalSha,
  String rewrittenSha,
  int originalRow,
  int rewrittenRow,
  int routeLane,
  Color color,
});

class BranchPreviewGraph {
  const BranchPreviewGraph({
    required this.rows,
    this.kinds = const {},
    this.dashedLanes = const {},
    this.mappings = const [],
  });

  final List<GraphRow> rows;
  final Map<String, PreviewGraphNodeKind> kinds;
  final Map<int, Set<int>> dashedLanes;
  final List<RebaseGraphMapping> mappings;
}

BranchPreviewGraph layoutMergePreviewGraph(BranchComparisonResult comparison) {
  final existing = layoutBranchComparison(comparison.commits);
  final base = existing.firstWhere(
    (row) => row.commit.sha == comparison.baseTip,
  );
  final compare = existing.firstWhere(
    (row) => row.commit.sha == comparison.compareTip,
  );
  final template = comparison.commits.first.commit;
  final sha = 'virtual-merge-${comparison.baseTip}-${comparison.compareTip}';
  final virtual = GitCommit(
    sha: sha,
    shortSha: comparison.merge.status == MergeConflictStatus.conflicts
        ? '중단'
        : 'VM',
    parents: [comparison.baseTip, comparison.compareTip],
    author: template.author,
    authorTimestamp: template.authorTimestamp,
    committer: template.committer,
    committerTimestamp: template.committerTimestamp + 1,
    refs: const [],
    subject:
        "Merge branch '${comparison.compareRef}' into ${comparison.baseRef}",
  );
  final lanes = {base.lane, compare.lane}.toList()..sort();
  final rows = [
    GraphRow(
      commit: virtual,
      lane: base.lane,
      parentLanes: [base.lane, compare.lane],
      activeLanes: [base.lane],
      nextLanes: lanes,
      activeLaneShas: {base.lane: sha},
      nextLaneShas: {
        base.lane: comparison.baseTip,
        compare.lane: comparison.compareTip,
      },
      transitions: base.lane == compare.lane
          ? const []
          : [(from: base.lane, to: compare.lane, sha: comparison.compareTip)],
      branch: base.branch,
      activeLaneBranches: {base.lane: base.branch},
      nextLaneBranches: {base.lane: base.branch, compare.lane: compare.branch},
    ),
    ...existing,
  ];
  final dashedLanes = <int, Set<int>>{};
  for (final parent in [base, compare]) {
    final parentIndex = rows.indexWhere(
      (row) => row.commit.sha == parent.commit.sha,
    );
    for (var index = 0; index < parentIndex; index++) {
      (dashedLanes[index] ??= {}).add(parent.lane);
    }
  }
  return BranchPreviewGraph(
    rows: rows,
    kinds: {sha: PreviewGraphNodeKind.virtualMerge},
    dashedLanes: dashedLanes,
  );
}

/// The rebase preview as the timeline draws it. The replayed commits continue
/// the base branch's own lane, and the oldest copy's rail reaches the base
/// branch's real HEAD row — the node it is replayed onto. With [mergeCommit] the
/// base branch also gets the merge commit it would land on, one row above the
/// replayed commits; the base lane then runs straight from that node down to
/// HEAD and the chain steps aside into a bubble lane, both of its ends reaching
/// the base branch again — the same tree, one more virtual node.
BranchPreviewGraph layoutRebasePreviewGraph(
  BranchComparisonResult comparison,
  RebasePreviewResult preview, {
  bool mergeCommit = false,
}) {
  final laidOut = layoutBranchComparison(comparison.commits);
  final compare = laidOut.firstWhere(
    (row) => row.commit.sha == comparison.compareTip,
  );
  final compareLane = compare.lane;
  final colors = rebaseMappingColors(AvatarService.branchColor(compare.branch));
  GraphRow hideCompareRail(GraphRow row) {
    final activeLaneShas = Map<int, String>.of(row.activeLaneShas)
      ..remove(compareLane);
    final nextLaneShas = Map<int, String>.of(row.nextLaneShas)
      ..remove(compareLane);
    final activeLaneBranches = Map<int, int>.of(row.activeLaneBranches)
      ..remove(compareLane);
    final nextLaneBranches = Map<int, int>.of(row.nextLaneBranches)
      ..remove(compareLane);
    return _copyGraphRow(
      row,
      activeLanes: row.activeLanes
          .where((lane) => lane != compareLane)
          .toList(),
      nextLanes: row.nextLanes.where((lane) => lane != compareLane).toList(),
      activeLaneShas: activeLaneShas,
      nextLaneShas: nextLaneShas,
      activeLaneBranches: activeLaneBranches,
      nextLaneBranches: nextLaneBranches,
    );
  }

  final firstCompareRow = comparison.commits.indexWhere(
    (entry) => entry.side == BranchCommitSide.compareOnly,
  );
  final existing = [
    for (var index = 0; index < laidOut.length; index++)
      index < firstCompareRow &&
              comparison.commits[index].side == BranchCommitSide.baseOnly
          ? hideCompareRail(laidOut[index])
          : laidOut[index],
  ];
  if (preview.status == RebasePreviewStatus.conflict) {
    final base = existing.firstWhere(
      (row) => row.commit.sha == comparison.baseTip,
    );
    final template = comparison.commits.first.commit;
    final sha =
        'virtual-rebase-target-${comparison.baseTip}-${comparison.compareTip}';
    final target = GitCommit(
      sha: sha,
      shortSha: '—',
      parents: [comparison.baseTip],
      author: template.author,
      authorTimestamp: template.authorTimestamp,
      committer: template.committer,
      committerTimestamp: template.committerTimestamp + 1,
      refs: const [],
      subject: '${comparison.baseRef} HEAD 위 예상 위치',
    );
    return BranchPreviewGraph(
      rows: [
        GraphRow(
          commit: target,
          lane: base.lane,
          parentLanes: [base.lane],
          activeLanes: [base.lane],
          nextLanes: [base.lane],
          activeLaneShas: {base.lane: sha},
          nextLaneShas: {base.lane: comparison.baseTip},
          branch: base.branch,
          activeLaneBranches: {base.lane: base.branch},
          nextLaneBranches: {base.lane: base.branch},
        ),
        ...existing,
      ],
      kinds: {sha: PreviewGraphNodeKind.conflictTarget},
      dashedLanes: {
        0: {base.lane},
      },
    );
  }
  if (preview.rewritten.isEmpty) return BranchPreviewGraph(rows: existing);
  final baseIndex = existing.indexWhere(
    (row) => row.commit.sha == comparison.baseTip,
  );
  final base = existing[baseIndex];
  // 'Rebase만'이면 재배치된 복사본은 현행 그림대로 기준 브랜치 레인을 그대로 잇는다.
  // 가상 머지가 있으면 그 레인은 머지 노드에서 HEAD까지 곧게 내려가야 하니 복사본이
  // 옆 버블로 비켜 앉고, 기준 브랜치 HEAD보다 위에 원본 줄이 남아 있으면 그 줄들보다
  // 한 칸 더 오른쪽으로 비켜 앉는다.
  final chainLane = !mergeCommit
      ? base.lane
      : existing
                .take(baseIndex)
                .fold<int>(
                  base.lane,
                  (deepest, row) => math.max(deepest, row.maxLane),
                ) +
            1;
  final virtualOldestFirst = <GitCommit>[];
  var parent = comparison.baseTip;
  for (final rewrite in preview.rewritten) {
    final original = rewrite.original;
    // 재배치가 커밋을 그대로 두면 range-diff가 원본 sha를 그대로 돌려준다. 그 sha로
    // 가상 행을 만들면 원본 행과 키가 겹쳐 원본까지 가상 커밋으로 그려지고 이동
    // 화살표도 자기 자신을 가리키니, 겹칠 때만 가상 행에 따로 키를 준다.
    final sameSha = rewrite.rewrittenSha == original.sha;
    virtualOldestFirst.add(
      GitCommit(
        sha: sameSha
            ? 'virtual-rebase-copy-${original.sha}'
            : rewrite.rewrittenSha,
        // sha가 그대로면 'new SHA'는 사실과 다르니 원본 해시를 그대로 보여준다.
        shortSha: sameSha ? original.shortSha : 'new SHA',
        parents: [parent],
        author: original.author,
        authorTimestamp: original.authorTimestamp,
        committer: original.committer,
        committerTimestamp: original.committerTimestamp,
        refs: const [],
        subject: original.subject,
      ),
    );
    parent = virtualOldestFirst.last.sha;
  }
  final virtualNewestFirst = virtualOldestFirst.reversed.toList();
  final template = comparison.commits.first.commit;
  final mergeSha =
      'virtual-rebase-merge-${comparison.baseTip}-${virtualOldestFirst.last.sha}';
  // 가상 머지가 있으면 기준 브랜치 레인은 그 노드에서 HEAD까지 곧게 내려간다.
  // 'Rebase만'이면 HEAD 위로는 기준 브랜치 선이 없다.
  final baseRail = [if (mergeCommit) base.lane];
  // 체인의 뿌리에서 기준 브랜치 HEAD 노드로 들어가는 점선. 인라인이면 같은 레인의
  // 직선이 그대로 HEAD 노드로 내려가니 꺾을 것이 없다.
  final chainRoot = chainLane == base.lane
      ? null
      : (from: chainLane, to: base.lane, sha: comparison.baseTip);
  final mergeRow = !mergeCommit
      ? null
      : GraphRow(
          commit: GitCommit(
            sha: mergeSha,
            shortSha: 'new SHA',
            parents: [comparison.baseTip, virtualOldestFirst.last.sha],
            author: template.author,
            authorTimestamp: template.authorTimestamp,
            committer: template.committer,
            committerTimestamp: template.committerTimestamp + 1,
            refs: const [],
            subject:
                "Merge branch '${comparison.compareRef}' into ${comparison.baseRef}",
          ),
          lane: base.lane,
          // 첫 부모는 기준 브랜치 HEAD, 두 번째 부모는 옆 레인의 재배치 tip이다.
          parentLanes: [base.lane, chainLane],
          activeLanes: [base.lane],
          nextLanes: [base.lane, chainLane],
          activeLaneShas: {base.lane: mergeSha},
          nextLaneShas: {
            base.lane: comparison.baseTip,
            chainLane: virtualNewestFirst.first.sha,
          },
          transitions: [
            (from: base.lane, to: chainLane, sha: virtualNewestFirst.first.sha),
          ],
          branch: base.branch,
          activeLaneBranches: {base.lane: base.branch},
          nextLaneBranches: {base.lane: base.branch, chainLane: base.branch},
        );
  // 체인이 기준 브랜치 HEAD보다 위에 남은 원본 줄들을 지나가야 하면 그 줄들에 체인
  // 레인과 기준 브랜치 레인을 함께 얹는다. 원본 줄에는 기준 브랜치 선이 없을 수도
  // 있어서, 얹지 않으면 가상 머지의 첫 부모 선이 HEAD에 닿기 전에 끊긴다. 버블이면
  // HEAD 바로 윗줄에서 HEAD 노드로 꺾고, 인라인이면 레인이 같아 그대로 내려간다.
  final carried = {...baseRail, chainLane};
  List<int> sortedLanes(Iterable<int> lanes) => lanes.toSet().toList()..sort();
  Map<int, T> fillLanes<T>(Map<int, T> source, List<int> lanes, T value) => {
    ...source,
    for (final lane in lanes)
      if (!source.containsKey(lane)) lane: value,
  };
  GraphRow carryChain(GraphRow row, {required bool bends}) {
    final bend = bends ? chainRoot : null;
    final active = sortedLanes([...row.activeLanes, ...carried]);
    final next = sortedLanes([
      ...row.nextLanes,
      ...bend == null ? carried : carried.difference({chainLane}),
    ]);
    return _copyGraphRow(
      row,
      activeLanes: active,
      nextLanes: next,
      activeLaneShas: fillLanes(row.activeLaneShas, active, comparison.baseTip),
      nextLaneShas: fillLanes(row.nextLaneShas, next, comparison.baseTip),
      activeLaneBranches: fillLanes(
        row.activeLaneBranches,
        active,
        base.branch,
      ),
      nextLaneBranches: fillLanes(row.nextLaneBranches, next, base.branch),
      transitions: bend == null ? null : [...row.transitions, bend],
    );
  }

  final rows = [
    ?mergeRow,
    for (var index = 0; index < virtualNewestFirst.length; index++)
      () {
        final commit = virtualNewestFirst[index];
        final root = index == virtualNewestFirst.length - 1;
        // 바로 아래가 HEAD 줄이면 뿌리 줄에서 곧장 꺾는다.
        final bend = root && baseIndex == 0 ? chainRoot : null;
        final bends = bend != null;
        final active = [...baseRail, chainLane];
        final next = [...baseRail, if (!bends) chainLane];
        return GraphRow(
          commit: commit,
          lane: chainLane,
          parentLanes: [root ? base.lane : chainLane],
          activeLanes: active,
          nextLanes: next,
          activeLaneShas: {
            for (final lane in active)
              lane: lane == chainLane ? commit.sha : comparison.baseTip,
          },
          nextLaneShas: {
            for (final lane in next)
              lane: lane == chainLane
                  ? commit.parents.single
                  : comparison.baseTip,
          },
          transitions: [?bend],
          branch: base.branch,
          activeLaneBranches: {for (final lane in active) lane: base.branch},
          nextLaneBranches: {for (final lane in next) lane: base.branch},
        );
      }(),
    for (var index = 0; index < existing.length; index++)
      index < baseIndex
          ? carryChain(existing[index], bends: index == baseIndex - 1)
          : existing[index],
  ];
  final rowBySha = {
    for (var index = 0; index < rows.length; index++)
      rows[index].commit.sha: index,
  };
  return BranchPreviewGraph(
    rows: rows,
    kinds: {
      if (mergeRow != null) mergeSha: PreviewGraphNodeKind.virtualRebaseMerge,
      for (final commit in virtualOldestFirst)
        commit.sha: PreviewGraphNodeKind.virtualRebase,
    },
    // 가상 노드들, 그리고 체인이 지나가는 원본 줄들까지가 점선이다. 기준 브랜치
    // HEAD 줄부터는 실제 히스토리라 실선으로 돌아온다.
    dashedLanes: {
      for (
        var index = 0;
        index < rows.length - existing.length + baseIndex;
        index++
      )
        index: carried,
    },
    // 짝은 가상 행의 키로 잇는다. sha가 그대로인 재배치에서 원본 sha로 이으면
    // 화살표가 원본 행에서 원본 행으로 되돌아온다.
    mappings: [
      for (var index = 0; index < preview.rewritten.length; index++)
        (
          originalSha: preview.rewritten[index].original.sha,
          rewrittenSha: virtualOldestFirst[index].sha,
          originalRow: rowBySha[preview.rewritten[index].original.sha]!,
          rewrittenRow: rowBySha[virtualOldestFirst[index].sha]!,
          routeLane: index,
          color: colors[math.min(index, colors.length - 1)],
        ),
    ],
  );
}

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Whole local calendar days from [day] to [now]. Counted in hours and rounded,
/// so a DST shift cannot turn yesterday into today. Every relative label in the
/// timeline measures with this, which is what keeps the Date column and the group
/// headings telling the same story.
int calendarDaysBetween(DateTime day, DateTime now) {
  final from = DateTime(day.year, day.month, day.day);
  final to = DateTime(now.year, now.month, now.day);
  return (to.difference(from).inHours / 24).round();
}

/// The heading over a day's commits: Today, Yesterday, `MM.DD Www` inside this
/// year, and `YY.MM.DD Www` beyond it.
String dateGroupLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(day.year, day.month, day.day);
  final elapsed = calendarDaysBetween(day, now);
  if (elapsed == 0) return 'Today';
  if (elapsed == 1) return 'Yesterday';
  String pad(int value) => value.toString().padLeft(2, '0');
  final stamp =
      '${pad(date.month)}.${pad(date.day)} ${_weekdayNames[date.weekday - 1]}';
  return date.year == today.year ? stamp : '${pad(date.year % 100)}.$stamp';
}

/// One line of the timeline list: a commit row, or the date heading opening the
/// group below it. [rowIndex] indexes the commit rows and is -1 on a heading,
/// which instead carries a synthetic pass-through row.
typedef TimelineEntry = ({int rowIndex, String? label, GraphRow row});

/// A line born from a merge commit bends beside its source. All other
/// transitions keep their lane until they reach the parent row.
bool transitionBendsAtSource(GraphRow row, LaneTransition transition) =>
    transition.from == row.lane &&
    !(row.parentLanes.isNotEmpty && transition.to == row.parentLanes.first);

GraphRow _copyGraphRow(
  GraphRow row, {
  List<int>? activeLanes,
  List<int>? nextLanes,
  Map<int, String>? activeLaneShas,
  Map<int, String>? nextLaneShas,
  List<LaneTransition>? transitions,
  Map<int, int>? activeLaneBranches,
  Map<int, int>? nextLaneBranches,
}) => GraphRow(
  commit: row.commit,
  lane: row.lane,
  parentLanes: row.parentLanes,
  activeLanes: activeLanes ?? row.activeLanes,
  nextLanes: nextLanes ?? row.nextLanes,
  activeLaneShas: activeLaneShas ?? row.activeLaneShas,
  nextLaneShas: nextLaneShas ?? row.nextLaneShas,
  transitions: transitions ?? row.transitions,
  branch: row.branch,
  activeLaneBranches: activeLaneBranches ?? row.activeLaneBranches,
  nextLaneBranches: nextLaneBranches ?? row.nextLaneBranches,
);

/// Splits parent-side transitions around a date heading. [above] finishes in
/// the state before those joins, and the synthetic heading completes them into
/// the original state handed to the commit below.
({GraphRow above, GraphRow heading}) _dateHeadingRows({
  required GraphRow above,
  required GitCommit below,
}) {
  final deferred = above.transitions
      .where((transition) => !transitionBendsAtSource(above, transition))
      .toList();
  if (deferred.isEmpty) {
    return (above: above, heading: passThroughRow(commit: below, above: above));
  }

  final middleShas = Map<int, String>.of(above.nextLaneShas);
  final middleBranches = Map<int, int>.of(above.nextLaneBranches);
  for (final transition in deferred.reversed) {
    final previousSha = above.activeLaneShas[transition.to];
    final previousBranch = above.activeLaneBranches[transition.to];
    if (previousSha == null) {
      middleShas.remove(transition.to);
      middleBranches.remove(transition.to);
    } else {
      middleShas[transition.to] = previousSha;
      if (previousBranch == null) {
        middleBranches.remove(transition.to);
      } else {
        middleBranches[transition.to] = previousBranch;
      }
    }

    middleShas[transition.from] = transition.sha;
    final sourceBranch =
        above.activeLaneBranches[transition.from] ??
        (transition.from == above.lane ? above.branch : null);
    if (sourceBranch == null) {
      middleBranches.remove(transition.from);
    } else {
      middleBranches[transition.from] = sourceBranch;
    }
  }
  final middleLanes = middleShas.keys.toList()..sort();
  final kept = above.transitions
      .where((transition) => transitionBendsAtSource(above, transition))
      .toList();
  final visualAbove = _copyGraphRow(
    above,
    nextLanes: middleLanes,
    nextLaneShas: middleShas,
    nextLaneBranches: middleBranches,
    transitions: kept,
  );
  return (
    above: visualAbove,
    heading: GraphRow(
      commit: below,
      lane: -1,
      parentLanes: const [],
      activeLanes: middleLanes,
      nextLanes: above.nextLanes,
      activeLaneShas: middleShas,
      nextLaneShas: above.nextLaneShas,
      transitions: deferred,
      activeLaneBranches: middleBranches,
      nextLaneBranches: above.nextLaneBranches,
    ),
  );
}

/// The commit rows with a date heading wherever the local day changes, including
/// above the first commit. The working tree row belongs to no day, so it leads
/// the list above the first heading.
List<TimelineEntry> timelineEntries(List<GraphRow> rows, DateTime now) {
  final entries = <TimelineEntry>[];
  DateTime? group;
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    if (row.commit.isWorkingTree) {
      entries.add((rowIndex: index, label: null, row: row));
      continue;
    }
    final time = DateTime.fromMillisecondsSinceEpoch(
      row.commit.committerTimestamp * 1000,
    );
    final date = DateTime(time.year, time.month, time.day);
    if (group != date) {
      group = date;
      var heading = passThroughRow(
        commit: row.commit,
        above: index == 0 ? null : rows[index - 1],
      );
      if (index > 0 && entries.isNotEmpty) {
        final previousEntry = entries.removeLast();
        final split = _dateHeadingRows(
          above: previousEntry.row,
          below: row.commit,
        );
        entries.add((
          rowIndex: previousEntry.rowIndex,
          label: previousEntry.label,
          row: split.above,
        ));
        heading = split.heading;
      }
      entries.add((
        rowIndex: -1,
        label: dateGroupLabel(date, now),
        row: heading,
      ));
    }
    entries.add((rowIndex: index, label: null, row: row));
  }
  return entries;
}

@visibleForTesting
String? branchLineTipSha(List<GraphRow> rows, int branch) {
  for (final row in rows) {
    if (row.branch == branch && !row.commit.isWorkingTree) {
      return row.commit.sha;
    }
  }
  return null;
}

/// The lanes [above] hands down, with no node and no lane of its own, so the
/// rails and the arriving sweeps run through a date heading unbroken.
GraphRow passThroughRow({required GitCommit commit, GraphRow? above}) =>
    GraphRow(
      commit: commit,
      lane: -1,
      parentLanes: const [],
      activeLanes: above?.nextLanes ?? const [],
      nextLanes: above?.nextLanes ?? const [],
      activeLaneShas: above?.nextLaneShas ?? const {},
      nextLaneShas: above?.nextLaneShas ?? const {},
      activeLaneBranches: above?.nextLaneBranches ?? const {},
      nextLaneBranches: above?.nextLaneBranches ?? const {},
    );

int stableRefPaletteIndex(String name, int length) {
  var hash = 0;
  for (final codeUnit in name.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash % length;
}

List<int> randomRefPaletteIndexes(List<int> assignments) {
  final valid = assignments.length == AppSettings.defaultRefPalette.length
      ? assignments
      : AppSettings.defaultRefPaletteAssignments;
  final random = [
    for (var index = 1; index < valid.length; index++)
      if (valid[index] == 0) index,
  ];
  return random.isEmpty
      ? [for (var index = 1; index < valid.length; index++) index]
      : random;
}

int refPaletteIndexForName(String name, List<int> assignments) {
  final candidates = randomRefPaletteIndexes(assignments);
  return candidates[stableRefPaletteIndex(name, candidates.length)];
}

RefPaletteColors refPaletteColorsAt(int index, List<RefPaletteEntry> palette) {
  final valid =
      palette.length == AppSettings.defaultRefPalette.length &&
          palette.every(
            (entry) =>
                parseHexColor(entry.base) != null &&
                parseHexColor(entry.text) != null,
          )
      ? palette
      : AppSettings.defaultRefPalette;
  final entry = valid[index.clamp(0, valid.length - 1)];
  return (base: parseHexColor(entry.base)!, text: parseHexColor(entry.text)!);
}

RefPaletteColors refPaletteColorsForName(
  String name,
  List<RefPaletteEntry> palette, {
  List<int> refPaletteAssignments = AppSettings.defaultRefPaletteAssignments,
}) => refPaletteColorsAt(
  refPaletteIndexForName(name, refPaletteAssignments),
  palette,
);

int refPriority(GitRef ref, RepoRefs refs) {
  if (ref.isHead || ref.name == refs.current) return 0;
  if (refs.local.contains(ref.name)) return 1;
  if (refs.remote.contains(ref.name)) return 2;
  if (ref.isTag || refs.tags.contains(ref.name)) return 3;
  return 4;
}

int compareTimelineRefs(GitRef left, GitRef right, RepoRefs refs) {
  final priority = refPriority(left, refs).compareTo(refPriority(right, refs));
  return priority != 0 ? priority : left.name.compareTo(right.name);
}

List<GitRef> timelineRefsForCommit(GitCommit commit, RepoRefs refs) {
  final byName = <String, GitRef>{};
  void add(GitRef ref) {
    final previous = byName[ref.name];
    byName[ref.name] = GitRef(
      name: ref.name,
      isHead: ref.isHead || previous?.isHead == true,
      isTag: ref.isTag || previous?.isTag == true,
    );
  }

  for (final ref in commit.refs) {
    add(ref);
  }
  if (commit.sha.isNotEmpty) {
    for (final entry in refs.tips.entries) {
      if (entry.value != commit.sha) continue;
      add(
        GitRef(
          name: entry.key,
          isHead: entry.key == refs.current,
          isTag: refs.tags.contains(entry.key),
        ),
      );
    }
  }
  final result = byName.values.toList();
  result.sort((left, right) => compareTimelineRefs(left, right, refs));
  return result;
}

Map<int, int> assignBranchPaletteIndexes(
  List<GraphRow> rows,
  int seed, {
  List<int> refPaletteAssignments = AppSettings.defaultRefPaletteAssignments,
}) {
  final indexes = <int, int>{};
  final candidates = randomRefPaletteIndexes(refPaletteAssignments);
  for (final row in rows) {
    final ids = {
      row.branch,
      ...row.activeLaneBranches.values,
      ...row.nextLaneBranches.values,
    }.toList()..sort();
    for (final id in ids) {
      if (id < 0 || indexes.containsKey(id)) continue;
      if (id == 0) {
        indexes[id] = 0;
        continue;
      }
      final pinned =
          refPaletteAssignments.length == AppSettings.defaultRefPalette.length
          ? refPaletteAssignments.indexOf(id + 1, 1)
          : -1;
      if (pinned > 0) {
        indexes[id] = pinned;
        continue;
      }
      final key = '$seed:$id';
      indexes[id] = candidates[stableRefPaletteIndex(key, candidates.length)];
    }
  }
  return indexes;
}

/// Branch id → Text / line color from its assigned palette row.
Map<int, Color> assignBranchColors(
  List<GraphRow> rows,
  int seed, {
  List<RefPaletteEntry> refPalette = AppSettings.defaultRefPalette,
  List<int> refPaletteAssignments = AppSettings.defaultRefPaletteAssignments,
}) {
  final indexes = assignBranchPaletteIndexes(
    rows,
    seed,
    refPaletteAssignments: refPaletteAssignments,
  );
  return {
    for (final entry in indexes.entries)
      entry.key: refPaletteColorsAt(entry.value, refPalette).text,
  };
}

typedef ColumnSpec = ({String label, double min, double max});

/// The six resizable timeline columns, in display order.
const timelineColumns = <String, ColumnSpec>{
  'refs': (label: 'Branch / Tag', min: 110, max: 240),
  'graph': (label: 'Graph', min: 40, max: 260),
  'hash': (label: 'Hash', min: 64, max: 120),
  'commit': (label: 'Commit Message', min: 100, max: 620),
  'time': (label: 'Date', min: 20, max: 170),
  'name': (label: 'Author', min: 20, max: 240),
};

/// What each branch line is called: the ref worn by the line's topmost row,
/// because a line is born at its tip. A ref further down belongs to history the
/// line passes through, not to the line, so it never renames it — and a tip
/// wearing nothing leaves its line unnamed rather than borrowing a name.
///
/// A branch beats a tag on the same commit: the row sits *on* the branch.
Map<int, String> branchLineNames(List<GraphRow> rows) {
  final names = <int, String>{};
  final seen = <int>{};
  for (final row in rows) {
    if (!seen.add(row.branch)) continue;
    final refs = row.commit.refs;
    if (refs.isEmpty) continue;
    final pick = refs.firstWhere((ref) => !ref.isTag, orElse: () => refs.first);
    names[row.branch] = pick.name;
  }
  return names;
}
