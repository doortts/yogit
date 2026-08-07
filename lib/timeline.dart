import 'dart:async';
import 'dart:io'
    show Directory, FileSystemEvent, FileSystemException, ProcessException;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'avatars.dart';
import 'commit_profile_chip.dart';
import 'diff_screen.dart';
import 'external_editor.dart';
import 'full_diff_commit_message_cache.dart';
import 'full_diff_model.dart';
import 'full_diff_shortcut_hint.dart';
import 'full_diff_side_by_side_view.dart';
import 'full_diff_syntax.dart';
import 'full_diff_unified_view.dart';
import 'fuzzy_match.dart';
import 'git.dart';
import 'monaco_editor_screen.dart';
import 'page_scroll_shortcuts.dart';
import 'ref_tree.dart';
import 'search_icon.dart';
import 'remote_pull_menu.dart';
import 'repository_branch_selector.dart';
import 'settings.dart';
import 'shortcut_modifier.dart';
import 'timeline_theme.dart';
import 'typography.dart';
import 'vim_navigation.dart';
import 'window_frame.dart';
import 'yogit_alert.dart';

const _hash = Color(0xFFEF6C63);
const _deleted = Color(0xFFF29AB2);
const _renamed = Color(0xFFB6A0EA);

/// The date group heading's box and label.
const _dateGroup = Color(0xFF5AB0FF);

/// A ref chip narrower than this is unreadable, so the extra chips hide instead.
const _minChipWidth = 40.0;

/// Long enough that arrowing past a row does not flash tooltips.
const _tooltipDelay = Duration(milliseconds: 400);

/// The design's `--yo-main` accent: additions, lane dots, the name tint.
const _main = Color(0xFF8AD6A1);
const _success = Color(0xFF34C759);
const _behind = Color(0xFFF0A35E);

/// The status bar's commit stamp: a fixed-width format in a monospace face, so
/// its width can be measured from a sample rather than the live value.
const _statusStampStyle = TextStyle(fontSize: 11, fontFamily: 'monospace');
const _remoteBehind = Color(0xFFFF453A);
const _previewPurple = Color(0xFFC69AFF);
const _previewPurplePanel = Color(0xFF29243A);
const _previewConflict = Color(0xFFFF7A84);
const _previewConflictPanel = Color(0xFF4B252C);
const _previewControlBlue = Color(0xFF4388EE);

/// 커밋 행 배지와 '양쪽 유지' 미리보기의 색. 초록이 브랜치 쪽(그리고 이미 반영된
/// 커밋), 파랑이 기준 쪽 추가, 주황이 충돌 예고다.
const _duplicateBadge = Color(0xFF7CE0A0);
const _forecastBadge = Color(0xFFF0A35E);
const _keepBothOursColor = Color(0xFF8FCBFF);
const _keepBothTheirsColor = Color(0xFF7CE0A0);

List<Color> rebaseMappingColors(Color branchColor) {
  final source = HSLColor.fromColor(branchColor);
  final startLightness = source.lightness + (1 - source.lightness) * 0.12;
  return [
    for (var index = 0; index < 5; index++)
      source
          .withSaturation(source.saturation * (0.92 - index * 0.11))
          .withLightness(startLightness * (1 - index * 0.09))
          .toColor(),
  ];
}

const _rebaseMappingAvatarBorderWidth = 3.0;

enum PreviewGraphNodeKind {
  actual,
  virtualMerge,
  virtualRebase,
  virtualRebaseMerge,
  conflictTarget,
}

enum BranchApplyStatus { idle, applying, applied, reverting, reverted, failed }

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
    virtualOldestFirst.add(
      GitCommit(
        sha: rewrite.rewrittenSha,
        shortSha: 'new SHA',
        parents: [parent],
        author: original.author,
        authorTimestamp: original.authorTimestamp,
        committer: original.committer,
        committerTimestamp: original.committerTimestamp,
        refs: const [],
        subject: original.subject,
      ),
    );
    parent = rewrite.rewrittenSha;
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
    mappings: [
      for (var index = 0; index < preview.rewritten.length; index++)
        (
          originalSha: preview.rewritten[index].original.sha,
          rewrittenSha: preview.rewritten[index].rewrittenSha,
          originalRow: rowBySha[preview.rewritten[index].original.sha]!,
          rewrittenRow: rowBySha[preview.rewritten[index].rewrittenSha]!,
          routeLane: index,
          color: colors[math.min(index, colors.length - 1)],
        ),
    ],
  );
}

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _commitMessageBody(String? message) {
  if (message == null) return '';
  final newline = message.indexOf('\n');
  return newline < 0 ? '' : message.substring(newline + 1).trim();
}

/// Line numbers read as line numbers once they pass a thousand: 1,412.
String _groupedNumber(int value) => value.toString().replaceAllMapped(
  RegExp(r'\d(?=(\d{3})+$)'),
  (match) => '${match[0]},',
);

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

enum _RefSection {
  local('LOCAL', Icons.computer_outlined),
  remote('REMOTE', Icons.cloud_outlined),
  tags('TAGS', Icons.sell_outlined);

  const _RefSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

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

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    required this.repository,
    this.controller,
    this.onOpenFullDiff,
    this.onOpenSettings,
    this.onOpenMonitor,
    this.onOpenRepository,
    this.recentRepositories = const [],
    this.onForgetRecentRepository,
    this.commitProfiles = const [],
    this.onCommitProfilesChanged,
    this.preferredBranch,
    this.preferredBranchReady = true,
    this.onPreferredBranchChanged,
    this.avatarService,
    this.deletedBranchNames = const {},
    this.deletedBranchNamesReady = true,
    this.onDeletedBranchNamesChanged,
    this.showRemoteAvatars = true,
    this.preferredPreviewPlacement = PreviewPlacement.right,
    this.columnWidths = const TimelineColumnWidths(),
    this.fullDiffColumnWidths = const FullDiffColumnWidths(),
    this.fullDiffPreferences = const FullDiffPreferences(),
    this.refPalette = AppSettings.defaultRefPalette,
    this.refPaletteAssignments = AppSettings.defaultRefPaletteAssignments,
    this.branchPreviewMode = BranchPreviewMode.merge,
    this.mergeMessageTemplate = AppSettings.defaultMergeMessageTemplate,
    this.rebaseMergeMessageTemplate = AppSettings.defaultMergeMessageTemplate,
    this.previewWidth = 288,
    this.previewHeight = 280,
    this.previewDiffLeftWidth,
    this.previewDiffRightWidth,
    this.previewDiffBottomHeight,
    this.onPreviewPlacementChanged,
    this.onColumnWidthsChanged,
    this.onFullDiffColumnWidthsChanged,
    this.onFullDiffPreferencesChanged,
    this.onBranchPreviewModeChanged,
    this.onPreviewSizeChanged,
    this.onPreviewDiffSizeChanged,
    this.editorForTesting,
    this.documentLoaderForTesting,
    super.key,
  });

  /// Every row is this tall — commits and date headings alike.
  static const rowHeight = 30.0;

  final GitRepository repository;
  final WindowFrameController? controller;
  final ValueChanged<GitCommit>? onOpenFullDiff;
  final VoidCallback? onOpenSettings;

  /// Called with the base branch when the toolbar's monitor button is
  /// pressed; the monitor opens as its own window.
  final ValueChanged<String>? onOpenMonitor;

  /// Called with the validated root of a repository the user picked.
  final ValueChanged<String>? onOpenRepository;

  /// Repository roots, most recently opened first.
  final List<String> recentRepositories;
  final ValueChanged<String>? onForgetRecentRepository;

  /// The commit identities the status bar chip offers.
  final List<CommitProfile> commitProfiles;
  final ValueChanged<List<CommitProfile>>? onCommitProfilesChanged;
  final String? preferredBranch;

  /// Whether [preferredBranch] has finished loading from persistent settings.
  final bool preferredBranchReady;
  final ValueChanged<String>? onPreferredBranchChanged;
  final AvatarService? avatarService;
  final Map<String, String> deletedBranchNames;
  final bool deletedBranchNamesReady;
  final ValueChanged<Map<String, String>>? onDeletedBranchNamesChanged;
  final bool showRemoteAvatars;
  final PreviewPlacement preferredPreviewPlacement;
  final TimelineColumnWidths columnWidths;
  final FullDiffColumnWidths fullDiffColumnWidths;
  final FullDiffPreferences fullDiffPreferences;
  final List<RefPaletteEntry> refPalette;
  final List<int> refPaletteAssignments;
  final BranchPreviewMode branchPreviewMode;

  /// What the commit message box is prefilled with when an apply creates a
  /// merge commit.
  final String mergeMessageTemplate;
  final String rebaseMergeMessageTemplate;
  final double previewWidth;
  final double previewHeight;
  final double? previewDiffLeftWidth;
  final double? previewDiffRightWidth;
  final double? previewDiffBottomHeight;
  final ValueChanged<PreviewPlacement>? onPreviewPlacementChanged;
  final ValueChanged<TimelineColumnWidths>? onColumnWidthsChanged;
  final ValueChanged<FullDiffColumnWidths>? onFullDiffColumnWidthsChanged;
  final ValueChanged<FullDiffPreferences>? onFullDiffPreferencesChanged;
  final ValueChanged<BranchPreviewMode>? onBranchPreviewModeChanged;
  final ValueChanged<({double width, double height})>? onPreviewSizeChanged;
  final ValueChanged<({PreviewPlacement placement, double extent})>?
  onPreviewDiffSizeChanged;

  @visibleForTesting
  final Widget? editorForTesting;

  @visibleForTesting
  final Future<WorkingTreeTextDocument> Function(String relativePath)?
  documentLoaderForTesting;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen>
    with WidgetsBindingObserver {
  static const _collapsedTagLimit = 10;
  static const _fetchInterval = Duration(minutes: 3);

  /// The safety net behind the ref-directory watcher. FSEvents can coalesce or
  /// drop notifications under load, so the fingerprint is still re-read on a
  /// slow timer — rarely enough to cost nothing, often enough that a missed
  /// event cannot go unnoticed for a whole session.
  static const _localWatchInterval = Duration(seconds: 60);

  /// One git command writes several files, so events are collected for this
  /// long before the fingerprint is read once.
  static const _localWatchDebounce = Duration(milliseconds: 250);

  static const _pageSize = 500;

  static const _sidebarRange = (min: 150.0, max: 320.0);
  static const _collapsedSidebarWidth = 52.0;

  TimelineThemePalette get _palette => context.timelineTheme;

  /// The window drag stretch the path keeps for itself before the wordmark is
  /// allowed any room.
  static const _minDragWidth = 200.0;

  /// The repository's last path segment; the full path lives in its tooltip. A
  /// root with no segment ('/') keeps the whole string.
  String get _repositoryName {
    final root = widget.repository.root;
    final segments = root.split('/').where((part) => part.isNotEmpty);
    return segments.isEmpty ? root : segments.last;
  }

  static const _previewMinWidth = 240.0;
  static const _previewMaxWidthFraction = 0.75;
  static const _previewMinHeight = 200.0;
  static const _timelineHeaderHeight = 29.0;
  static const _branchPreviewSummaryHeight = 52.0;

  final _focusNode = FocusNode();
  final _timelineKey = GlobalKey();
  final _scrollController = ScrollController();
  final _previewFilesScrollController = ScrollController();
  final _previewDiffScrollController = ScrollController();
  final _selectedPreviewFileKey = GlobalKey(
    debugLabel: 'selected preview file',
  );
  final _normalCommits = <GitCommit>[];
  final _committersBySha = <String, GitIdentity>{};
  var _normalRows = <GraphRow>[];
  var _branchPaletteIndexes = <int, int>{};
  var _normalEntries = <TimelineEntry>[];
  String? _compareRef;
  BranchComparisonResult? _comparison;
  var _comparisonRows = <GraphRow>[];
  var _comparisonEntries = <TimelineEntry>[];
  BranchPreviewGraph? _previewGraph;
  RebaseCheckResult? _rebaseCheck;
  BranchRecommendation? _recommendation;
  var _recommendationSerial = 0;
  MergePreviewSession? _mergePreviewSession;
  MergePreviewResult? _mergePreview;
  var _mergePreviewSerial = 0;
  var _mergePreviewBusy = false;
  Object? _mergePreviewError;
  final _mergeResolvedFiles = <String>{};
  RebasePreviewSession? _rebasePreviewSession;
  RebasePreviewResult? _rebasePreview;
  var _rebasePreviewSerial = 0;
  var _rebasePreviewBusy = false;
  Object? _rebasePreviewError;
  var _rebaseHadConflict = false;
  var _repositoryOperationInProgress = false;
  final _rebaseResolvedFiles = <String>{};
  final _rebaseEditedFiles = <String>{};

  /// P1b/P2 — 커밋 행 배지의 근거. 비동기로 도착하고 도착 전에는 아무 자리도
  /// 차지하지 않는다. 비교가 바뀌면 둘 다 버려진다.
  var _duplicateCommits = const <String>{};
  var _conflictForecast = const <String, List<String>>{};
  var _conflictForecastSerial = 0;

  /// P3 — 자격이 있는 충돌 파일만 여기 남는다. 열려 있는 순서 선택은 한 파일뿐.
  final _keepBothCandidates = <String, KeepBothCandidate>{};
  var _keepBothSerial = 0;
  String? _keepBothOpenPath;
  final _rebaseConflictRowContextKey = GlobalKey();
  final _rebaseApplyRowContextKey = GlobalKey();
  var _branchApplyStatus = BranchApplyStatus.idle;
  var _branchApplySerial = 0;
  BranchApplyResult? _branchApplyResult;
  Object? _branchApplyError;
  String? _rebaseApplyingSha;

  /// 어떤 rebase 결과를 적용할지 카드에서 고른 값. 미리보기가 바뀌면 함께
  /// 초기화되니 비교 대상이 달라지면 다시 'Rebase만'에서 시작한다.
  var _rebaseApplyMerge = false;
  var _branchPreviewDropped = false;
  Object? _comparisonError;
  var _comparisonSerial = 0;
  late BranchPreviewMode _branchPreviewMode = widget.branchPreviewMode;
  var _previewDiffLayout = DiffLayout.unified;
  final _previewDiffHighlighter = HighlightJsSyntaxHighlighter();

  List<GitCommit> get _commits => _comparison == null
      ? _normalCommits
      : [for (final row in _comparisonRows) row.commit];
  List<GraphRow> get _rows =>
      _comparison == null ? _normalRows : _comparisonRows;
  List<TimelineEntry> get _entries =>
      _comparison == null ? _normalEntries : _comparisonEntries;
  late final WindowFrameController _previewController;
  late final bool _ownsPreviewController;

  /// Selection and hover live in notifiers so moving the cursor rebuilds the two
  /// rows that changed instead of every row on screen.
  final _selectedIndex = ValueNotifier(0);
  final _hoverIndex = ValueNotifier(-1);
  final _hoveredHeader = ValueNotifier<String?>(null);
  var _loading = false;
  var _end = false;
  var _hasWorkingTree = false;
  Object? _loadError;
  Future<void>? _inFlight;
  final _previewFiles = <String, Future<List<GitFileChange>>>{};
  final _previewFileLists = <String, List<GitFileChange>>{};
  final _previewDiffs = <({String sha, String path}), Future<List<DiffLine>>>{};
  final _previewPaths = <String, String>{};
  var _previewDiffOpen = false;

  /// The line a proximity pill asked for, and the one already scrolled to, so a
  /// region is revealed once and the scroll is the user's again afterwards.
  ({String path, int line})? _previewDiffLineTarget;
  ({String path, int line})? _previewDiffLineRevealed;
  var _previewDiffRevealScheduled = false;
  final _previewDiffTargetKey = GlobalKey(debugLabel: 'preview diff line');
  late final Map<String, String> _deletedBranchNames;
  final _deletedBranchLookupAttempts = <String>{};
  final _deletedBranchRevision = ValueNotifier(0);
  var _deletedBranchLookupGeneration = 0;
  final _resolvingDeletedBranchTips = <String>{};

  var _refs = const RepoRefs();
  var _refsLoading = true;
  var _refsLoadFailed = false;
  var _refsLoaded = false;
  Timer? _fetchTimer;
  Timer? _localWatchTimer;
  Timer? _localWatchDebounceTimer;
  final _refWatchers = <StreamSubscription<FileSystemEvent>>[];

  /// The local fingerprint the timeline is currently showing.
  String? _localSignature;

  /// A fingerprint the user chose not to load, so the same change is not asked
  /// about twice.
  String? _declinedSignature;
  var _localChangePromptOpen = false;
  final _fetchingRemotes = ValueNotifier(false);
  final _fetchError = ValueNotifier<Object?>(null);
  CherryPickState? _cherryPickState;
  Object? _cherryPickError;
  var _cherryPickBusy = false;
  String? _selectedConflictPath;
  String? _baseBranch;
  String? _pendingBaseBranch;
  var _pendingBaseBranchIsUserSelection = false;

  String? get _preferredTip => _baseBranch == null
      ? null
      : _refs.localTips[_baseBranch!] ?? _refs.tips[_baseBranch!];

  String? _refTip(RepoRefs refs, String ref) =>
      refs.localTips[ref] ?? refs.tips[ref];

  /// Which way the cursor last travelled, so the ref modal opens on the side the
  /// cursor came from. Null after a click or a jump, which have no direction.
  bool? _arrivedGoingDown;
  final _filterController = TextEditingController();
  var _filter = '';
  final _collapsedRefSections = <_RefSection>{};
  final _collapsedRefFolders = <String>{};
  var _showAllTags = false;
  var _sidebarCollapsed = false;

  late final Map<String, double> _widths = _widthMap(widget.columnWidths);
  late double? _commitWidth = widget.columnWidths.commit;
  late double? _graphWidth = widget.columnWidths.graph;
  late double _sidebarWidth = widget.columnWidths.sidebar;
  late bool _showTime = widget.columnWidths.showTime;
  late bool _showName = widget.columnWidths.showName;

  /// Test hook: the preview text the user last selected, so a test can prove that
  /// dragging over the panel really selects.
  @visibleForTesting
  String? debugPreviewSelection;

  /// Where the Date column starts, so the status bar can line its stamp up with
  /// it. Written while the timeline lays out, read by the status bar built right
  /// after it in the same frame.
  var _hashColumnLeft = 0.0;
  var _commitAvailableWidth = 0.0;
  late double _previewWidth = widget.previewWidth;
  late double _previewHeight = widget.previewHeight;
  late double? _previewDiffLeftWidth = widget.previewDiffLeftWidth;
  late double? _previewDiffRightWidth = widget.previewDiffRightWidth;
  late double? _previewDiffBottomHeight = widget.previewDiffBottomHeight;
  var _previewDiffResizerHovered = false;
  var _visiblePreviewDiffExtent = 0.0;
  var _maxPreviewDiffExtent = 0.0;
  var _bottomPreviewMaxHeight = double.maxFinite;
  _FullDiffRouteSession? _fullDiffRouteSession;
  FullDiffPreferences? _pendingFullDiffPreferences;
  FullDiffColumnWidths? _pendingFullDiffColumnWidths;
  var _fullDiffPersistenceFlushScheduled = false;

  /// Deepest lane the viewport has shown so far. It only grows, so the column
  /// never shrinks under the user mid-session; a new repository remounts.
  var _ratchetLane = 0;
  final _resizerFocus = {
    for (final column in timelineColumns.keys) column: FocusNode(),
  };
  Map<String, double> _resizeStartWidths = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsPreviewController = widget.controller == null;
    _previewController = widget.controller ?? WindowFrameController();
    _deletedBranchNames = Map.of(widget.deletedBranchNames);
    _scrollController.addListener(_maybeLoadNextPage);
    _selectedIndex.addListener(_selectedCommitChanged);
    // The sidebar cursor and the timeline selection dim whichever of the two
    // panes does not hold the keyboard, so both repaint on focus flips.
    _sidebarFocusNode.addListener(_onPaneFocusChanged);
    _focusNode.addListener(_onPaneFocusChanged);
    HardwareKeyboard.instance.addHandler(_handleModifierKeyEvent);
    // Refs load beside the first page, and neither blocks the first paint. The
    // detail pane stays hidden until Enter or Space asks for it.
    _loadNextPage();
    unawaited(_loadCommitIdentity());
    unawaited(_restoreCherryPickThenRefresh());
    _fetchTimer = Timer.periodic(
      _fetchInterval,
      (_) => unawaited(_refreshRemotes()),
    );
    unawaited(_syncLocalSignature());
    unawaited(_startRefWatchers());
    _localWatchTimer = Timer.periodic(
      _localWatchInterval,
      (_) => unawaited(_checkLocalChanges()),
    );
  }

  List<String> get _remotesToRefresh {
    final remotes = <String>{};
    final branch = _baseBranch;
    final upstreamRemote = branch == null
        ? null
        : _refs.upstreamRemotes[branch];
    if (upstreamRemote != null) remotes.add(upstreamRemote);
    for (final remoteBranch in _refs.remote) {
      final split = splitRemoteBranchName(remoteBranch, _refs.remoteNames);
      if (split == null || !_refs.local.contains(split.branch)) {
        continue;
      }
      remotes.add(split.remote);
    }
    return remotes.toList()..sort();
  }

  Future<void> _refreshRemotes() async {
    final remotes = _remotesToRefresh;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if ((lifecycleState != null &&
            lifecycleState != AppLifecycleState.resumed) ||
        remotes.isEmpty ||
        _fetchingRemotes.value ||
        _cherryPickState != null) {
      return;
    }
    _fetchingRemotes.value = true;
    try {
      var updated = false;
      Object? fetchError;
      for (final remote in remotes) {
        try {
          final result = await widget.repository.fetchRemote(remote);
          updated |= result == FetchOriginResult.updated;
        } catch (error) {
          fetchError ??= error;
        }
      }
      if (!mounted) return;
      if (updated) await _loadRefs();
      if (mounted) _fetchError.value = fetchError;
    } finally {
      if (mounted) _fetchingRemotes.value = false;
    }
  }

  /// Subscribes to the directories Git rewrites when a ref moves, so a
  /// checkout or commit made elsewhere is noticed as it happens instead of on
  /// the next poll. A directory that cannot be watched is skipped; the timer
  /// above still covers it.
  Future<void> _startRefWatchers() async {
    final dirs = await widget.repository.loadGitDirectories();
    if (!mounted || dirs == null) return;
    for (final path in refWatchPaths(
      gitDir: dirs.gitDir,
      commonDir: dirs.commonDir,
    )) {
      final directory = Directory(path);
      if (!directory.existsSync()) continue;
      try {
        _refWatchers.add(
          // Only `refs` needs the recursive walk; a branch name can nest, but
          // the git dirs themselves hold HEAD and packed-refs at the top.
          directory
              .watch(recursive: path.endsWith('refs'))
              .listen((_) => _scheduleLocalCheck()),
        );
      } on FileSystemException {
        // A platform or path that refuses to be watched falls back to polling.
      }
    }
  }

  /// Collapses the burst of events one git command produces into a single
  /// fingerprint read.
  void _scheduleLocalCheck() {
    _localWatchDebounceTimer?.cancel();
    _localWatchDebounceTimer = Timer(
      _localWatchDebounce,
      () => unawaited(_checkLocalChanges()),
    );
  }

  /// Records what the repository looks like right now as the state the
  /// timeline is showing, so an app-initiated change never prompts.
  Future<void> _syncLocalSignature() async {
    final signature = await widget.repository.loadLocalStateSignature();
    if (mounted && signature != null) _localSignature = signature;
  }

  /// Polls the repository's fingerprint and offers to reload when someone
  /// moved HEAD or a branch outside the app — a terminal checkout, a commit
  /// from another tool, a rebase in a second window.
  Future<void> _checkLocalChanges() async {
    if (!mounted || _localChangePromptOpen) return;
    // A mutation the app is running will refresh on its own; interrupting it
    // with a question would race its own reload.
    if (_branchApplyBusy || _pullingRemote != null) return;
    final signature = await widget.repository.loadLocalStateSignature();
    if (!mounted || signature == null) return;
    if (_localSignature == null) {
      _localSignature = signature;
      return;
    }
    if (signature == _localSignature || signature == _declinedSignature) return;
    _localChangePromptOpen = true;
    final accepted = await showYogitAlert<bool>(
      context,
      const YogitAlert(
        title: '저장소가 바뀌었습니다',
        message: '앱 밖에서 HEAD나 브랜치가 변경되었습니다. 새로 읽어올까요?',
        cancelLabel: '나중에',
        cancelKey: Key('local-change-dismiss'),
        confirmLabel: '새로고침',
        confirmKey: Key('local-change-refresh'),
      ),
    );
    if (!mounted) return;
    _localChangePromptOpen = false;
    if (accepted == true) {
      _localSignature = signature;
      _declinedSignature = null;
      await _reloadTimelineAfterCherryPick(null);
    } else {
      _declinedSignature = signature;
    }
  }

  Future<void> _restoreCherryPickThenRefresh() async {
    await Future.wait([_loadRefs(), _reloadCherryPickState()]);
    if (_cherryPickState == null) await _refreshRemotes();
  }

  Future<void> _reloadCherryPickState() async {
    try {
      final state = await widget.repository.loadCherryPickState();
      if (!mounted) return;
      setState(() {
        _cherryPickState = state;
        _cherryPickError = null;
        _selectedConflictPath =
            state?.conflicts.contains(_selectedConflictPath) == true
            ? _selectedConflictPath
            : state == null || state.conflicts.isEmpty
            ? null
            : state.conflicts.first;
      });
      if (state != null &&
          _previewController.previewPlacement == PreviewPlacement.closed) {
        await _previewController.setPreview(widget.preferredPreviewPlacement);
      }
    } catch (error) {
      if (mounted) setState(() => _cherryPickError = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reloadCherryPickState());
    }
  }

  Future<void> _loadRefs() async {
    try {
      final refs = await widget.repository.loadRefs();
      if (!mounted) return;
      final branch = resolveBaseBranch(refs, _refsLoaded ? _baseBranch : null);
      if (!widget.preferredBranchReady) {
        _pendingBaseBranch = branch;
        _pendingBaseBranchIsUserSelection = false;
      }
      final compared = _compareRef;
      final comparisonStillExists =
          compared != null &&
          (refs.local.contains(compared) ||
              refs.remote.contains(compared) ||
              refs.tags.contains(compared));
      final comparison = _comparison;
      final baseTip = comparison == null
          ? null
          : _refTip(refs, comparison.baseRef);
      final compareTip = comparison == null
          ? null
          : _refTip(refs, comparison.compareRef);
      final comparisonTipsChanged =
          comparisonStillExists &&
          comparison != null &&
          baseTip != null &&
          compareTip != null &&
          (baseTip != comparison.baseTip ||
              compareTip != comparison.compareTip);
      final retryComparison =
          comparisonStillExists &&
          comparison == null &&
          _comparisonError != null;
      setState(() {
        _refs = refs;
        _refsLoading = false;
        _refsLoadFailed = false;
        _refsLoaded = true;
        _baseBranch = branch;
        if (compared != null && !comparisonStillExists) {
          _comparisonSerial++;
          _compareRef = null;
          _comparison = null;
          _comparisonRows = [];
          _comparisonEntries = [];
          _rebaseCheck = null;
          _comparisonError = null;
        }
        _rebuildGraph();
      });
      _scheduleRatchetUpdate();
      unawaited(_resolveSelectedDeletedBranchName());
      if (comparisonTipsChanged || retryComparison) {
        unawaited(
          _selectComparison(compared, preserveCurrent: comparison != null),
        );
      }
      if (widget.preferredBranchReady &&
          branch != null &&
          branch != widget.preferredBranch) {
        widget.onPreferredBranchChanged?.call(branch);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refsLoading = false;
        _refsLoadFailed = true;
        _refsLoaded = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final deletedBranchNamesChanged = !mapEquals(
      widget.deletedBranchNames,
      oldWidget.deletedBranchNames,
    );
    final recoveryContextChanged =
        !identical(widget.repository, oldWidget.repository) ||
        !identical(widget.avatarService, oldWidget.avatarService);
    if (recoveryContextChanged) {
      _deletedBranchLookupGeneration++;
      _deletedBranchLookupAttempts.clear();
      _resolvingDeletedBranchTips.clear();
    }
    // A new repository has its own identity; an edited profile list can rename
    // the one already in force.
    if (!identical(widget.repository, oldWidget.repository)) {
      unawaited(_loadCommitIdentity());
    } else if (!listEquals(widget.commitProfiles, oldWidget.commitProfiles)) {
      _commitIdentity = resolveCommitIdentity(
        _commitIdentity.identity,
        widget.commitProfiles,
      );
    }
    if (deletedBranchNamesChanged) {
      _deletedBranchNames
        ..clear()
        ..addAll(widget.deletedBranchNames);
    }
    if ((widget.deletedBranchNamesReady &&
            !oldWidget.deletedBranchNamesReady) ||
        deletedBranchNamesChanged ||
        recoveryContextChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_resolveSelectedDeletedBranchName());
      });
    }
    if (!identical(widget.repository, oldWidget.repository)) {
      _resetBranchApply();
      _dropMergePreview();
      _dropRebasePreview();
      _clearFullDiffRouteSession();
    } else if (widget.onFullDiffPreferencesChanged !=
            oldWidget.onFullDiffPreferencesChanged ||
        widget.onFullDiffColumnWidthsChanged !=
            oldWidget.onFullDiffColumnWidthsChanged) {
      _scheduleFullDiffPersistenceFlush();
    }
    if (widget.columnWidths != oldWidget.columnWidths) {
      _widths.addAll(_widthMap(widget.columnWidths));
      _commitWidth = widget.columnWidths.commit;
      _graphWidth = widget.columnWidths.graph;
      _sidebarWidth = widget.columnWidths.sidebar;
      _showTime = widget.columnWidths.showTime;
      _showName = widget.columnWidths.showName;
    }
    if (widget.previewWidth != oldWidget.previewWidth ||
        widget.previewHeight != oldWidget.previewHeight) {
      _previewWidth = widget.previewWidth;
      _previewHeight = widget.previewHeight;
    }
    if (widget.previewDiffLeftWidth != oldWidget.previewDiffLeftWidth ||
        widget.previewDiffRightWidth != oldWidget.previewDiffRightWidth ||
        widget.previewDiffBottomHeight != oldWidget.previewDiffBottomHeight) {
      _previewDiffLeftWidth = widget.previewDiffLeftWidth;
      _previewDiffRightWidth = widget.previewDiffRightWidth;
      _previewDiffBottomHeight = widget.previewDiffBottomHeight;
    }
    if (widget.branchPreviewMode != oldWidget.branchPreviewMode) {
      _branchPreviewMode = widget.branchPreviewMode;
    }
    if (!listEquals(widget.refPalette, oldWidget.refPalette) ||
        !listEquals(
          widget.refPaletteAssignments,
          oldWidget.refPaletteAssignments,
        )) {
      _rebuildGraph();
    }
    final preferredBranchBecameReady =
        widget.preferredBranchReady && !oldWidget.preferredBranchReady;
    if (_refsLoaded &&
        (preferredBranchBecameReady ||
            (widget.preferredBranchReady &&
                widget.preferredBranch != oldWidget.preferredBranch))) {
      final pendingUserSelection =
          preferredBranchBecameReady &&
          _pendingBaseBranchIsUserSelection &&
          _refs.local.contains(_pendingBaseBranch);
      final branch = pendingUserSelection
          ? _pendingBaseBranch
          : preferredBranchBecameReady
          ? _baseBranch ?? resolveBaseBranch(_refs, null)
          : resolveBaseBranch(_refs, widget.preferredBranch);
      if (preferredBranchBecameReady) {
        _pendingBaseBranch = null;
        _pendingBaseBranchIsUserSelection = false;
      }
      if (branch != _baseBranch) {
        setState(() {
          _baseBranch = branch;
          _rebuildGraph();
        });
        _scheduleRatchetUpdate();
        unawaited(_refreshRemotes());
      }
      if (branch != null &&
          (pendingUserSelection || branch != widget.preferredBranch)) {
        final onChanged = widget.onPreferredBranchChanged;
        if (onChanged != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) onChanged(branch);
          });
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleModifierKeyEvent);
    _fetchTimer?.cancel();
    _localWatchTimer?.cancel();
    _localWatchDebounceTimer?.cancel();
    for (final watcher in _refWatchers) {
      unawaited(watcher.cancel());
    }
    _dropMergePreview();
    _dropRebasePreview();
    _clearFullDiffRouteSession();
    if (_ownsPreviewController) _previewController.dispose();
    _selectedIndex.removeListener(_selectedCommitChanged);
    _selectedIndex.dispose();
    _fetchingRemotes.dispose();
    _fetchError.dispose();
    _deletedBranchRevision.dispose();
    _hoverIndex.dispose();
    _hoveredHeader.dispose();
    _scrollController
      ..removeListener(_maybeLoadNextPage)
      ..dispose();
    _previewFilesScrollController.dispose();
    _previewDiffScrollController.dispose();
    for (final node in _resizerFocus.values) {
      node.dispose();
    }
    _filterController.dispose();
    _focusNode.dispose();
    _sidebarFocusNode.dispose();
    super.dispose();
  }

  /// Every column except `graph` and `commit`, which size themselves until
  /// dragged.
  static Map<String, double> _widthMap(TimelineColumnWidths widths) => {
    'refs': widths.refs,
    'hash': widths.hash,
    'time': widths.time,
    'name': widths.name,
  };

  double _w(String column) => _widths[column]!;

  bool _columnVisible(String column) => switch (column) {
    'time' => _showTime,
    'name' => _showName,
    _ => true,
  };

  int get _graphLayoutDepth {
    if (_comparison == null || _comparisonRows.isEmpty) return _ratchetLane;
    final deepest = _comparisonRows.fold<int>(
      0,
      (value, row) => math.max(value, row.maxLane),
    );
    final mappings = _previewGraph?.mappings.length ?? 0;
    return mappings == 0 ? deepest : deepest + ((mappings + 2) ~/ 2);
  }

  double get _graphLayoutSpacing => _comparison == null
      ? CommitGraphPainter.defaultLaneSpacing
      : CommitGraphPainter.previewLaneSpacing;

  /// Auto-fit: the snuggest width that still shows every loaded lane's node, so
  /// the first launch shows the whole graph and no more. The resizer reaches
  /// further down than this range; auto-fit never does.
  double get _graphColumnWidth =>
      _graphWidth ??
      CommitGraphPainter.contentWidth(
        _graphLayoutDepth,
        laneSpacing: _graphLayoutSpacing,
      ).clamp(96.0, timelineColumns['graph']!.max);

  /// Widens the ratchet when deeper lanes scroll into view. Rows off screen do
  /// not count, so a shallow head of history opens at its snuggest width.
  void _updateRatchet() {
    if (!mounted ||
        _comparison != null ||
        _entries.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final first = (position.pixels / TimelineScreen.rowHeight).floor().clamp(
      0,
      _entries.length - 1,
    );
    final last =
        ((position.pixels + position.viewportDimension) /
                TimelineScreen.rowHeight)
            .ceil()
            .clamp(0, _entries.length - 1);
    var deepest = _ratchetLane;
    for (var index = first; index <= last; index++) {
      final row = _entries[index].row;
      for (final lane in [row.lane, ...row.activeLanes, ...row.nextLanes]) {
        if (lane > deepest) deepest = lane;
      }
    }
    if (deepest != _ratchetLane) setState(() => _ratchetLane = deepest);
  }

  void _scheduleRatchetUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateRatchet());
  }

  void _maybeLoadNextPage() {
    _updateRatchet();
    if (_compareRef != null ||
        !_scrollController.hasClients ||
        _end ||
        _inFlight != null) {
      return;
    }
    if (_scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <=
        TimelineScreen.rowHeight * 12) {
      _loadNextPage();
    }
  }

  void _loadNextPage() {
    if (_compareRef != null || _end || _inFlight != null) return;
    final request = _fetchNextPage();
    _inFlight = request;
    request.whenComplete(() {
      if (identical(_inFlight, request)) _inFlight = null;
    });
  }

  /// Commits actually read from `git log`, so the working tree row never shifts
  /// the paging offset.
  int get _historyCount => _normalCommits.length - (_hasWorkingTree ? 1 : 0);

  void _rebuildGraph() {
    _normalRows = layoutGraph(_normalCommits, preferredTip: _preferredTip);
    _normalEntries = timelineEntries(_normalRows, DateTime.now());
    _branchPaletteIndexes = assignBranchPaletteIndexes(
      _normalRows,
      widget.repository.root.hashCode,
      refPaletteAssignments: widget.refPaletteAssignments,
    );
    AvatarService.branchAssignments = {
      for (final entry in _branchPaletteIndexes.entries)
        entry.key: refPaletteColorsAt(entry.value, widget.refPalette).text,
    };
  }

  Future<void> _fetchNextPage() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      // The first page fetches the working tree and the log together.
      final (working, page) = _normalCommits.isEmpty
          ? await (
              widget.repository.loadWorkingTree(),
              widget.repository.loadHistory(limit: _pageSize),
            ).wait
          : (
              null,
              await widget.repository.loadHistory(
                skip: _historyCount,
                limit: _pageSize,
              ),
            );
      if (!mounted) return;
      final keepEndVisible =
          _normalCommits.isNotEmpty &&
          page.length < _pageSize &&
          _scrollController.hasClients &&
          _scrollController.position.maxScrollExtent -
                  _scrollController.position.pixels <=
              TimelineScreen.rowHeight;
      setState(() {
        if (working != null) {
          _normalCommits.add(working);
          _hasWorkingTree = true;
          // The working tree row inherits HEAD's committer color so its rail
          // matches the branch it sits on.
          if (page.isNotEmpty) _committersBySha[''] = page.first.committer;
        }
        _normalCommits.addAll(page);
        _committersBySha.addEntries(
          page.map((commit) => MapEntry(commit.sha, commit.committer)),
        );
        _rebuildGraph();
        // A heading never holds the selection across a load — including the
        // very first one, so the app opens on a commit.
        if (_entries.isNotEmpty &&
            _entries[_selectedIndex.value].rowIndex < 0) {
          _selectedIndex.value = _entries.indexWhere(
            (entry) => entry.rowIndex >= 0,
          );
        }
        _end = page.length < _pageSize;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateRatchet());
      unawaited(_resolveSelectedDeletedBranchName());
      if (keepEndVisible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  bool get _editableDescendantHasFocus {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  // ------------------------------------------------------- commit identity

  /// The repository's commit identity, re-read rather than remembered: the
  /// CLI, an includeIf rule, or another GUI can change it behind the app.
  var _commitIdentity = const CommitIdentityState.unknown();

  Future<void> _loadCommitIdentity() async {
    try {
      final identity = await widget.repository.loadCommitIdentity();
      if (!mounted) return;
      setState(
        () => _commitIdentity = resolveCommitIdentity(
          identity,
          widget.commitProfiles,
        ),
      );
    } catch (_) {
      // A repository that cannot answer keeps the chip on its last reading.
    }
  }

  /// Who a commit message template's `{profile}` names: the profile this
  /// repository commits as, or the bare `user.name` behind it. Null where Git
  /// has neither, so the line naming nobody can be dropped instead.
  String? get _commitMessageProfile {
    final profile = _commitIdentity.profile?.name.trim() ?? '';
    if (profile.isNotEmpty) return profile;
    final name = _commitIdentity.identity.name.trim();
    return name.isEmpty ? null : name;
  }

  Future<void> _applyCommitProfile(CommitProfile profile) async {
    try {
      await widget.repository.setLocalCommitIdentity(
        GitIdentity(name: profile.name, email: profile.email),
      );
      await _loadCommitIdentity();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('커밋 신원: ${profile.name} <${profile.email}>')),
      );
    } on ProcessException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('커밋 신원 변경 실패: ${error.message.trim()}')),
        );
      }
    }
  }

  /// Saves the identity the repository already carries as a named profile, so
  /// a setup made outside the app joins the list instead of fighting it.
  void _registerCurrentIdentity() {
    final identity = _commitIdentity.identity;
    if (identity.email.trim().isEmpty) return;
    final profiles = [
      ...widget.commitProfiles,
      CommitProfile(
        label: identity.name.trim().isEmpty ? identity.email : identity.name,
        name: identity.name,
        email: identity.email,
        color:
            CommitProfile.paletteColors[widget.commitProfiles.length %
                CommitProfile.paletteColors.length],
      ),
    ];
    widget.onCommitProfilesChanged?.call(profiles);
    setState(() => _commitIdentity = resolveCommitIdentity(identity, profiles));
  }

  /// Opens the profile menu above the chip, right-aligned with it.
  Future<void> _openCommitProfileMenu() async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final chip =
        _profileChipKey.currentContext?.findRenderObject() as RenderBox?;
    if (chip == null) return;
    final topLeft = chip.localToGlobal(Offset.zero, ancestor: overlay);
    final right = overlay.size.width - (topLeft.dx + chip.size.width);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => Stack(
        children: [
          Positioned(
            right: right,
            bottom: overlay.size.height - topLeft.dy + 7,
            child: CommitProfileMenu(
              repositoryName: repositoryNameOf(widget.repository.root),
              state: _commitIdentity,
              profiles: widget.commitProfiles,
              onSelected: (profile) {
                Navigator.pop(context);
                unawaited(_applyCommitProfile(profile));
              },
              onRegisterCurrent: () {
                Navigator.pop(context);
                _registerCurrentIdentity();
              },
              onManage: () {
                Navigator.pop(context);
                widget.onOpenSettings?.call();
              },
            ),
          ),
        ],
      ),
    );
  }

  final _profileChipKey = GlobalKey();

  /// Whether ⌘ (Ctrl off Apple platforms) is down right now: every on-screen
  /// control with a shortcut shows its key combination while it is.
  var _modifierHeld = false;

  bool _handleModifierKeyEvent(KeyEvent event) {
    if (!isShortcutModifierKey(event.logicalKey)) return false;
    if (_modifierHeld != shortcutModifierHeld && mounted) {
      setState(() => _modifierHeld = shortcutModifierHeld);
    }
    return false;
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    // Holding an arrow keeps moving; everything else acts once per press.
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final keyboard = HardwareKeyboard.instance;
      final pageScrollIntent = pageScrollIntentFor(
        event,
        metaPressed: keyboard.isMetaPressed,
        shiftPressed: keyboard.isShiftPressed,
      );
      if (pageScrollIntent != null) {
        if (_previewController.previewPlacement != PreviewPlacement.closed) {
          final controller = _previewPageScrollController(
            pageScrollIntent.direction,
          );
          if (controller != null) {
            applyPageScroll(
              controller,
              direction: pageScrollIntent.direction,
              animate: event is KeyDownEvent,
            );
          }
        }
        return KeyEventResult.handled;
      }
      final key = normalizeNavigationKey(
        event.logicalKey,
        hasModifier:
            keyboard.isMetaPressed ||
            keyboard.isAltPressed ||
            keyboard.isShiftPressed ||
            keyboard.isControlPressed ||
            _editableDescendantHasFocus,
      );
      final step = switch (key) {
        LogicalKeyboardKey.arrowDown => 1,
        LogicalKeyboardKey.arrowUp => -1,
        _ => 0,
      };
      // Meta without Shift walks preview files.
      if (step != 0 &&
          (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowUp) &&
          keyboard.isMetaPressed &&
          !keyboard.isShiftPressed) {
        if (_previewController.previewPlacement != PreviewPlacement.closed) {
          _stepPreviewFile(step, animate: event is KeyDownEvent);
        }
        return KeyEventResult.handled;
      }
      // Autorepeat jumps instead of animating: queued animations would lag
      // behind a held key and never catch up.
      if (step != 0) {
        _moveSelection(step, animate: event is KeyDownEvent);
        return KeyEventResult.handled;
      }
      // ← (or h) walks over to the sidebar while the pane is open.
      if (key == LogicalKeyboardKey.arrowLeft &&
          event is KeyDownEvent &&
          !_sidebarCollapsed) {
        _sidebarFocusNode.requestFocus();
        if (_sidebarCursor == null) _moveSidebarCursor(1);
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.keyD && shortcutModifierHeld) {
      if (_selectedCommit != null) _openFullDiff();
      return KeyEventResult.handled;
    }
    // ⌘1 hands the keyboard to the sidebar, expanding it when collapsed; a
    // second ⌘1 while the sidebar holds the keyboard puts the pane away.
    if (event.logicalKey == LogicalKeyboardKey.digit1 && shortcutModifierHeld) {
      if (!_sidebarCollapsed && _sidebarFocusNode.hasFocus) {
        setState(() => _sidebarCollapsed = true);
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_sidebarCollapsed) setState(() => _sidebarCollapsed = false);
      _sidebarFocusNode.requestFocus();
      if (_sidebarCursor == null) _moveSidebarCursor(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && _commits.isNotEmpty) {
      _togglePreview();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_previewDiffOpen) {
        _closePreviewDiff();
      } else {
        unawaited(_previewController.setPreview(PreviewPlacement.closed));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The topmost heading is the only one the selection may land on; the rest are
  /// skip-only, so walking the list never stops on them.
  bool _selectable(int index) =>
      _entries[index].rowIndex >= 0 ||
      index == _entries.indexWhere((entry) => entry.rowIndex < 0);

  /// Steps one entry, walking on past skip-only headings. Running off the end
  /// comes back the other way, so the walk always lands somewhere selectable.
  void _moveSelection(int delta, {bool animate = true}) {
    if (_entries.isEmpty) return;
    _arrivedGoingDown = delta > 0;
    final step = delta < 0 ? -1 : 1;
    var next = (_selectedIndex.value + delta).clamp(0, _entries.length - 1);
    for (final direction in [step, -step]) {
      var probe = next;
      while (probe >= 0 && probe < _entries.length && !_selectable(probe)) {
        probe += direction;
      }
      if (probe >= 0 && probe < _entries.length) {
        next = probe;
        break;
      }
    }
    if (!_selectable(next)) return;
    _selectedIndex.value = next;
    _scrollToSelection(animate: animate);
  }

  /// The selection walks the visible rows without moving the list; only when it
  /// would step past an edge does the list scroll, and then just far enough to
  /// hold the row flush against that edge.
  void _scrollToSelection({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final rowTop = _selectedIndex.value * TimelineScreen.rowHeight;
    final rowBottom = rowTop + TimelineScreen.rowHeight;
    final double? target =
        rowBottom > position.pixels + position.viewportDimension
        ? rowBottom - position.viewportDimension
        : rowTop < position.pixels
        ? rowTop
        : null;
    if (target == null) return;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (!animate) {
      _scrollController.jumpTo(clamped);
      return;
    }
    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  /// A click only moves the selection. An open preview follows it; a closed one
  /// stays closed until Enter or Space. A skip-only heading takes no click.
  void _select(int index) {
    if (!_selectable(index)) return;
    _arrivedGoingDown = null;
    _selectedIndex.value = index;
    _focusNode.requestFocus();
  }

  void _selectedCommitChanged() =>
      unawaited(_resolveSelectedDeletedBranchName());

  String? _deletedBranchTipSha(int branch) {
    for (final row in _normalRows) {
      if (row.branch != branch || row.commit.isWorkingTree) continue;
      return _rowRefs(row.commit).isEmpty ? row.commit.sha : null;
    }
    return null;
  }

  ({String selectedSha, String tipSha})? _selectedDeletedBranchLine() {
    if (!_refsLoaded || _comparison != null || _entries.isEmpty) return null;
    final entry = _entries[_selectedIndex.value];
    if (entry.rowIndex < 0 || entry.row.commit.isWorkingTree) return null;
    final tipSha = _deletedBranchTipSha(entry.row.branch);
    if (tipSha == null) return null;
    return (selectedSha: entry.row.commit.sha, tipSha: tipSha);
  }

  Future<void> _resolveSelectedDeletedBranchName() async {
    if (!widget.deletedBranchNamesReady) return;
    final line = _selectedDeletedBranchLine();
    if (line == null ||
        _deletedBranchNames.containsKey(line.tipSha) ||
        !_deletedBranchLookupAttempts.add(line.tipSha)) {
      return;
    }
    final generation = _deletedBranchLookupGeneration;
    final repository = widget.repository;
    final avatarService = widget.avatarService;
    _resolvingDeletedBranchTips.add(line.tipSha);
    _deletedBranchRevision.value++;
    String? name;
    try {
      name = await repository.loadLocalDeletedBranchName(
        line.tipSha,
        _normalCommits,
      );
      name ??= await avatarService?.resolveMergedBranchName(line.tipSha);
    } catch (_) {
      name = null;
    }
    if (!mounted ||
        generation != _deletedBranchLookupGeneration ||
        !identical(widget.repository, repository) ||
        !identical(widget.avatarService, avatarService)) {
      return;
    }
    if (name == null && avatarService == null) {
      _deletedBranchLookupAttempts.remove(line.tipSha);
    }
    if (name != null) _deletedBranchNames[line.tipSha] = name;
    _resolvingDeletedBranchTips.remove(line.tipSha);
    _deletedBranchRevision.value++;
    if (name != null) {
      widget.onDeletedBranchNamesChanged?.call(Map.of(_deletedBranchNames));
    }
  }

  /// The branch or tag naming the focused commit's line: the topmost loaded row
  /// on the same branch line that carries a ref, which is that line's tip. The
  /// working tree belongs to whatever is checked out; a date heading and a line
  /// whose tip is not loaded (or was deleted) name nothing.
  String? get _selectedLineRef {
    if (_entries.isEmpty) return null;
    final entry = _entries[_selectedIndex.value];
    if (entry.rowIndex < 0) return null;
    if (entry.row.commit.isWorkingTree) return _refs.current;
    for (final row in _rows) {
      if (row.branch != entry.row.branch) continue;
      final refs = _rowRefs(row.commit);
      if (refs.isNotEmpty) return refs.first.name;
    }
    return null;
  }

  /// The commit the selection sits on, or null before the first page lands.
  GitCommit? get _selectedCommit {
    if (_entries.isEmpty) return null;
    final rowIndex = _entries[_selectedIndex.value].rowIndex;
    return rowIndex < 0 ? null : _commits[rowIndex];
  }

  /// Enter and Space toggle the panel; Esc always closes.
  void _togglePreview() {
    final closing =
        _previewController.previewPlacement != PreviewPlacement.closed;
    if (closing && _previewDiffOpen) _closePreviewDiff();
    unawaited(
      _previewController.setPreview(
        closing ? PreviewPlacement.closed : widget.preferredPreviewPlacement,
      ),
    );
  }

  /// Sidebar click: jump to the newest commit decorated with [name]. Remote
  /// entries also match the branch name without their remote prefix.
  /// Keyboard navigation inside the sidebar keeps its own focus, so it asks
  /// for the jump without stealing the timeline focus back.
  void _selectRef(
    String name, {
    bool remote = false,
    bool focusTimeline = true,
  }) {
    final candidates = {
      name,
      if (remote && name.contains('/')) name.substring(name.indexOf('/') + 1),
    };
    final tip = _refs.tips[name];
    final index = _entries.indexWhere(
      (entry) =>
          entry.rowIndex >= 0 &&
          (entry.row.commit.sha == tip ||
              entry.row.commit.refs.any(
                (ref) => candidates.contains(ref.name),
              )),
    );
    if (index < 0) return;
    _arrivedGoingDown = null;
    _selectedIndex.value = index;
    _scrollToSelection();
    if (focusTimeline) _focusNode.requestFocus();
  }

  // ------------------------------------------- sidebar keyboard navigation

  final _sidebarFocusNode = FocusNode(debugLabel: 'sidebar');

  void _onPaneFocusChanged() {
    if (mounted) setState(() {});
  }

  /// The unfocused pane keeps its selection, drained of color: same
  /// luminance, zero chroma, so only the focused pane reads as active.
  static Color _achromatic(Color color) {
    final gray = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
    return Color.from(alpha: color.a, red: gray, green: gray, blue: gray);
  }

  /// The timeline's selection color, gray while the sidebar has the keyboard.
  Color get _timelineSelectionColor => _sidebarFocusNode.hasFocus
      ? _achromatic(_palette.selectedRow)
      : _palette.selectedRow;

  /// The row the sidebar's keyboard cursor sits on, highlighted like a hover.
  (_RefSection, String)? _sidebarCursor;

  /// One key per named row so the cursor can be scrolled into view.
  final _sidebarRowKeys = <String, GlobalKey>{};

  /// The named rows currently on screen, in paint order: sections top-down,
  /// minus collapsed sections, collapsed folders, and filtered-out names.
  List<(_RefSection, String)> _visibleRefRows() {
    final filtering = _filter.trim().isNotEmpty;
    final rows = <(_RefSection, String)>[];
    void walk(_RefSection section, List<RefTreeNode> nodes, String parentPath) {
      for (final node in nodes) {
        final path = parentPath.isEmpty
            ? node.segment
            : '$parentPath/${node.segment}';
        if (node.fullName case final name?) rows.add((section, name));
        final collapsed =
            !filtering &&
            _collapsedRefFolders.contains('${section.name}:$path');
        if (node.children.isNotEmpty && !collapsed) {
          walk(section, node.children, path);
        }
      }
    }

    for (final (section, names) in [
      (_RefSection.local, _localBranches),
      (_RefSection.remote, _refs.remote),
      (_RefSection.tags, _refs.tags),
    ]) {
      if (!filtering && _collapsedRefSections.contains(section)) continue;
      walk(section, buildRefTree(_visibleSectionNames(section, names)), '');
    }
    return rows;
  }

  KeyEventResult _onSidebarKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _sidebarCursor = null);
      _focusNode.requestFocus();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final key = normalizeNavigationKey(
      event.logicalKey,
      hasModifier:
          keyboard.isMetaPressed ||
          keyboard.isAltPressed ||
          keyboard.isShiftPressed ||
          keyboard.isControlPressed,
    );
    // → (or l) hands the keyboard back to the timeline; the cursor stays so
    // the gray selection marks where the sidebar left off.
    if (key == LogicalKeyboardKey.arrowRight && event is KeyDownEvent) {
      _focusNode.requestFocus();
      return KeyEventResult.handled;
    }
    final step = switch (key) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    _moveSidebarCursor(step);
    return KeyEventResult.handled;
  }

  /// The strip under the search field: what the cursor's ref can do, with
  /// impossible actions disabled in place so the layout never jumps.
  Widget _sidebarActionStrip() {
    final cursor = _sidebarCursor;
    final section = cursor?.$1;
    final name = cursor?.$2;
    final isLocal = section == _RefSection.local && name != null;
    final isRemote = section == _RefSection.remote && name != null;
    final current = isLocal && name == _refs.current;
    final pullState = isRemote ? remotePullState(_refs, name) : null;
    final busy = _pullingRemote != null || _branchApplyBusy;

    Widget button({
      required Key key,
      required IconData icon,
      required String tooltip,
      VoidCallback? onPressed,
      Color? color,
    }) => IconButton(
      key: key,
      icon: Icon(icon, size: 15),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
      style: IconButton.styleFrom(
        foregroundColor: color ?? _palette.text,
        disabledForegroundColor: _palette.muted.withValues(alpha: 0.4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Container(
        key: const Key('sidebar-action-strip'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _palette.raised,
          border: Border.all(color: _palette.border),
          borderRadius: BorderRadius.circular(6),
        ),
        // Focus stays on the list: the buttons act without taking the
        // keyboard, so the cursor keeps moving from where it was.
        child: ExcludeFocus(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final buttons = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button(
                    key: const Key('sidebar-action-base'),
                    icon: Icons.anchor,
                    tooltip: '기준 브랜치로',
                    onPressed: isLocal && name != _baseBranch
                        ? () => _selectBaseBranch(name)
                        : null,
                  ),
                  button(
                    key: const Key('sidebar-action-compare'),
                    icon: Icons.compare_arrows,
                    tooltip: '브랜치 diff로 비교',
                    onPressed: name != null && name != _baseBranch && !busy
                        ? () => unawaited(_selectComparison(name))
                        : null,
                  ),
                  button(
                    key: const Key('sidebar-action-pull'),
                    icon: Icons.arrow_downward,
                    tooltip: 'Pull',
                    onPressed:
                        pullState?.kind == RemotePullKind.fastForward && !busy
                        ? () => unawaited(_confirmRemotePull(name!, pullState!))
                        : null,
                  ),
                  button(
                    key: const Key('sidebar-action-checkout'),
                    icon: Icons.logout,
                    tooltip: '체크아웃',
                    onPressed: busy
                        ? null
                        : isLocal && !current
                        ? () => unawaited(_runLocalCheckout(name))
                        : pullState != null && !pullState.checkedOut
                        ? () => unawaited(_runRemoteCheckout(name!, pullState))
                        : null,
                  ),
                  SizedBox(
                    height: 16,
                    child: VerticalDivider(width: 9, color: _palette.border),
                  ),
                  button(
                    key: const Key('sidebar-action-delete'),
                    icon: Icons.delete_outline,
                    tooltip: '브랜치 삭제',
                    color: _remoteBehind,
                    onPressed: isLocal && !current && !busy
                        ? () => unawaited(_confirmDeleteBranch(name))
                        : null,
                  ),
                ],
              );
              // 26px per button plus the divider; below that plus a readable
              // name, the name yields and the buttons scale to the pane.
              const buttonsWidth = 26.0 * 5 + 9;
              if (constraints.maxWidth < buttonsWidth + 48) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: buttons,
                );
              }
              return Row(
                children: [
                  // Nothing selected leaves the slot empty; the disabled
                  // buttons already say the strip is waiting.
                  Expanded(
                    child: Text(
                      name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: _palette.text),
                    ),
                  ),
                  buttons,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Switches HEAD to a local branch from the sidebar strip.
  Future<void> _runLocalCheckout(String branch) async {
    if (_pullingRemote != null || _branchApplyBusy) return;
    try {
      await widget.repository.checkoutLocalBranch(branch);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$branch 체크아웃')));
      await _reloadTimelineAfterCherryPick(null);
    } on ProcessException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('체크아웃 실패: ${error.message.trim()}')),
        );
      }
    }
  }

  /// Moves the cursor and mirrors it on the timeline, like clicking the row.
  void _moveSidebarCursor(int step) {
    final rows = _visibleRefRows();
    if (rows.isEmpty) return;
    final cursor = _sidebarCursor;
    final index = cursor == null ? -1 : rows.indexOf(cursor);
    final next = index < 0
        ? (step > 0 ? 0 : rows.length - 1)
        : (index + step).clamp(0, rows.length - 1);
    final (section, name) = rows[next];
    setState(() => _sidebarCursor = rows[next]);
    _selectRef(
      name,
      remote: section == _RefSection.remote,
      focusTimeline: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _sidebarRowKeys['${section.name}:$name']?.currentContext;
      if (context != null) {
        unawaited(Scrollable.ensureVisible(context, alignment: 0.5));
      }
    });
  }

  /// The remote branch a pull or checkout is currently running for. One at a
  /// time: the sidebar shows a spinner on this row and ignores further asks.
  String? _pullingRemote;

  String? _lastRemoteRowTap;
  int _lastRemoteRowTapMs = 0;

  /// The first click jumps the timeline like any ref row; a second click on
  /// the same row within the double-click window runs the default pull action.
  void _tapRemoteRow(String name) {
    _selectRef(name, remote: true, focusTimeline: false);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastRemoteRowTap == name &&
        now - _lastRemoteRowTapMs <= kDoubleTapTimeout.inMilliseconds) {
      _lastRemoteRowTap = null;
      _runRemotePullDefault(name);
      return;
    }
    _lastRemoteRowTap = name;
    _lastRemoteRowTapMs = now;
  }

  /// One controller per remote row so a double-click can open the same menu
  /// the ↓ button anchors.
  final _pullMenuControllers = <String, MenuController>{};

  /// Double-click: the one state where the outcome is safe and obvious asks
  /// for a fast-forward pull; every other state just opens the menu, which
  /// names the state instead of mutating anything.
  void _runRemotePullDefault(String remoteBranch) {
    final state = remotePullState(_refs, remoteBranch);
    if (state == null) return;
    if (state.kind == RemotePullKind.fastForward) {
      unawaited(_confirmRemotePull(remoteBranch, state));
      return;
    }
    _pullMenuControllers[remoteBranch]?.open();
  }

  Future<void> _confirmRemotePull(
    String remoteBranch,
    RemotePullState state,
  ) async {
    if (_pullingRemote != null || _branchApplyBusy) return;
    final approved = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: '로컬로 Pull할까요?',
        message: remoteBranch,
        detail:
            '로컬 ${state.localBranch}보다 ${state.ahead}개 커밋 앞서 있습니다. '
            'fast-forward로 받아올 수 있습니다.',
        confirmLabel: 'Pull',
        confirmKey: const Key('remote-pull-confirm'),
      ),
    );
    if (approved == true) await _runRemotePull(remoteBranch, state);
  }

  Future<void> _runRemotePull(
    String remoteBranch,
    RemotePullState state,
  ) async {
    if (_pullingRemote != null || _branchApplyBusy) return;
    setState(() => _pullingRemote = remoteBranch);
    try {
      await widget.repository.pullRemoteBranch(
        state.remote,
        state.localBranch,
        checkedOut: state.checkedOut,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${state.localBranch} ← $remoteBranch · ${state.ahead}개 커밋',
          ),
        ),
      );
      await _reloadTimelineAfterCherryPick(null);
    } on ProcessException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pull 실패: ${error.message.trim()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pullingRemote = null);
      } else {
        _pullingRemote = null;
      }
    }
  }

  Future<void> _runRemoteCheckout(
    String remoteBranch,
    RemotePullState state,
  ) async {
    if (_pullingRemote != null || _branchApplyBusy) return;
    setState(() => _pullingRemote = remoteBranch);
    try {
      await widget.repository.checkoutRemoteBranch(
        state.remote,
        state.localBranch,
        createLocal: state.kind == RemotePullKind.noLocal,
      );
      // The menu promised "switch, then pull" when the remote was ahead.
      if (state.kind == RemotePullKind.fastForward) {
        await widget.repository.pullRemoteBranch(
          state.remote,
          state.localBranch,
          checkedOut: true,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${state.localBranch} 체크아웃')));
      await _reloadTimelineAfterCherryPick(null);
    } on ProcessException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('체크아웃 실패: ${error.message.trim()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pullingRemote = null);
      } else {
        _pullingRemote = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _palette.background,
    body: Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: Column(
        children: [
          _toolbar(),
          Divider(height: 1, color: _palette.border),
          Expanded(
            child: Row(
              children: [
                _sidebar(),
                Expanded(child: _workspace()),
              ],
            ),
          ),
          _statusBar(),
        ],
      ),
    ),
  );

  /// Opening or closing the panel re-lays out this subtree only, never the whole
  /// screen.
  Widget _workspace() => ListenableBuilder(
    listenable: _previewController,
    builder: (context, _) => LayoutBuilder(builder: _workspaceLayout),
  );

  Widget _workspaceLayout(BuildContext context, BoxConstraints constraints) {
    final placement = _previewController.previewPlacement;
    final timeline = Expanded(
      key: const Key('timeline-viewport'),
      child: KeyedSubtree(key: _timelineKey, child: _timeline()),
    );
    if (placement == PreviewPlacement.bottom) {
      final timelineChromeHeight =
          _timelineHeaderHeight +
          (_compareRef == null ? 0 : _branchPreviewSummaryHeight);
      _bottomPreviewMaxHeight = math.max(
        0,
        constraints.maxHeight - timelineChromeHeight,
      );
      final extent = math.min(_previewHeight, _bottomPreviewMaxHeight);
      final diffExtent = _previewDiffExtent(
        placement,
        math.max(0.0, constraints.maxHeight - extent),
      );
      return Column(
        key: const Key('preview-layout-bottom'),
        children: [
          timeline,
          if (_previewDiffOpen)
            SizedBox(
              height: diffExtent,
              width: constraints.maxWidth,
              child: _adjacentPreviewDiff(placement),
            ),
          _animatedPreview(
            axis: Axis.vertical,
            extent: extent,
            width: constraints.maxWidth,
            height: extent,
          ),
        ],
      );
    }
    final onLeft = placement == PreviewPlacement.left;
    final beside = onLeft || placement == PreviewPlacement.right;
    final maxPreviewWidth = math.min(
      constraints.maxWidth,
      MediaQuery.sizeOf(context).width * _previewMaxWidthFraction,
    );
    final extent = beside ? math.min(_previewWidth, maxPreviewWidth) : 0.0;
    final preview = _animatedPreview(
      axis: Axis.horizontal,
      extent: extent,
      width: extent,
      height: constraints.maxHeight,
      visible: beside,
    );
    final diffExtent = _previewDiffExtent(
      placement,
      beside ? math.max(0.0, constraints.maxWidth - extent) : 0.0,
    );
    final diff = SizedBox(
      width: diffExtent,
      height: constraints.maxHeight,
      child: _adjacentPreviewDiff(placement),
    );
    return Row(
      key: Key(onLeft ? 'preview-layout-left' : 'preview-layout-right'),
      children: onLeft
          ? [preview, if (_previewDiffOpen) diff, timeline]
          : [timeline, if (_previewDiffOpen) diff, preview],
    );
  }

  double _previewDiffExtent(PreviewPlacement placement, double available) {
    _maxPreviewDiffExtent = available;
    final saved = switch (placement) {
      PreviewPlacement.left => _previewDiffLeftWidth,
      PreviewPlacement.right => _previewDiffRightWidth,
      PreviewPlacement.bottom => _previewDiffBottomHeight,
      PreviewPlacement.closed => null,
    };
    _visiblePreviewDiffExtent = _previewDiffOpen
        ? (saved ?? math.max(0.0, available - 100)).clamp(0.0, available)
        : 0.0;
    return _visiblePreviewDiffExtent;
  }

  Widget _animatedPreview({
    required Axis axis,
    required double extent,
    required double width,
    required double height,
    bool visible = true,
  }) => TweenAnimationBuilder<double>(
    key: const Key('preview-panel'),
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    tween: Tween(begin: 0, end: extent),
    builder: (context, value, child) {
      final visibleExtent = math.min(value, extent);
      return SizedBox(
        width: axis == Axis.horizontal ? visibleExtent : width,
        height: axis == Axis.vertical ? visibleExtent : height,
        child: child,
      );
    },
    child: visible
        ? ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: width,
              maxWidth: width,
              minHeight: height,
              maxHeight: height,
              child: SizedBox(width: width, height: height, child: _preview()),
            ),
          )
        : null,
  );

  // ---------------------------------------------------------------- toolbar

  PreviewPlacement get _activePlacement =>
      _previewController.previewPlacement == PreviewPlacement.closed
      ? widget.preferredPreviewPlacement
      : _previewController.previewPlacement;

  /// Native folder chooser → `git rev-parse --show-toplevel`. A directory that
  /// is not a repository leaves the current one alone and says so inline.
  Future<void> _pickRepository() async {
    if (_branchApplyBusy) return;
    final path = await _previewController.pickRepository();
    if (path == null || !mounted) return;
    await _openRepositoryPath(path);
  }

  /// A remembered path can have been moved or deleted since it was stored, so
  /// it goes through the same validation as a freshly picked folder.
  Future<void> _openRepositoryPath(String path) async {
    if (_branchApplyBusy) return;
    try {
      final root = await resolveRepositoryRoot(
        path,
        gitExecutable: widget.repository.gitExecutable,
        runner: widget.repository.runner,
      );
      if (mounted) widget.onOpenRepository?.call(root);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Git 저장소가 아닙니다: $path')));
    }
  }

  Widget _toolbar() => Container(
    key: const Key('toolbar'),
    height: 56,
    color: _palette.surface,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      // Decoration goes before anything functional when the window narrows:
      // the wordmark first, then the caption, then the shortcut keycaps.
      child: LayoutBuilder(
        builder: (context, constraints) => _toolbarRow(
          showPreviewLabel: constraints.maxWidth >= 900,
          showShortcuts: constraints.maxWidth >= 880,
        ),
      ),
    ),
  );

  Widget _windowButtons() => Row(
    children: [
      WindowButtons(controller: _previewController),
      const SizedBox(width: 14),
    ],
  );

  Widget _toolbarRow({
    required bool showPreviewLabel,
    required bool showShortcuts,
  }) => Row(
    children: [
      Expanded(child: _toolbarLeft()),
      _toolbarRight(showPreviewLabel, showShortcuts),
    ],
  );

  Widget _toolbarLeft() => Row(
    children: [
      _windowButtons(),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final previewControlsWidth = _compareRef == null ? 0.0 : 212.0;
            final selectorWidth = math.min(
              460.0,
              math.max(
                0.0,
                constraints.maxWidth - _minDragWidth - previewControlsWidth,
              ),
            );
            return Row(
              children: [
                SizedBox(
                  width: selectorWidth,
                  child: AbsorbPointer(
                    key: const Key('branch-preview-toolbar-lock'),
                    absorbing: _branchApplyBusy,
                    child: RepositoryBranchSelector(
                      repositoryName: _repositoryName,
                      repositoryPath: widget.repository.root,
                      localBranches: _recentLocalBranches,
                      branchTimes: _refs.branchActivityTimes,
                      remoteBranches: sortRefsNewestFirst(
                        _refs.remote,
                        _refs.branchActivityTimes,
                      ),
                      tags: sortRefsNewestFirst(
                        _refs.tags,
                        _refs.tagCreatorTimes,
                      ),
                      tagTimes: _refs.tagCreatorTimes,
                      selectedBranch: _baseBranch,
                      comparedBranch: _compareRef,
                      refsLoading: _refsLoading,
                      refsLoadFailed: _refsLoadFailed,
                      onRepositoryPressed: () => unawaited(_pickRepository()),
                      recentRepositories: widget.recentRepositories,
                      onRecentRepositorySelected: (path) =>
                          unawaited(_openRepositoryPath(path)),
                      onRecentRepositoryRemoved:
                          widget.onForgetRecentRepository,
                      onBranchSelected: _selectBaseBranch,
                      onComparisonSelected: (branch) =>
                          unawaited(_selectComparison(branch)),
                      onComparisonCleared: _clearComparison,
                    ),
                  ),
                ),
                if (_compareRef != null) ...[
                  const SizedBox(width: 8),
                  SizedBox(width: 200, child: _branchPreviewControls()),
                ],
                Expanded(child: _dragAndWordmark()),
              ],
            );
          },
        ),
      ),
    ],
  );

  List<String> get _recentLocalBranches => sortRefsNewestFirst(_refs.local, {
    for (final name in _refs.local)
      if (_refs.branchActivityTimes[name] != null ||
          _refs.birthTimes[name] != null)
        name: math.max(
          _refs.branchActivityTimes[name] ?? 0,
          _refs.birthTimes[name] ?? 0,
        ),
  });

  /// The drag stretch and wordmark share whatever the functional clusters
  /// leave. The wordmark steps down to 20px and then goes rather than squeeze
  /// the drag target.
  Widget _dragAndWordmark() => LayoutBuilder(
    builder: (context, constraints) {
      final size = [26.0, 20.0].firstWhere(
        (size) => constraints.maxWidth - (size * 5 + 24) >= _minDragWidth,
        orElse: () => 0.0,
      );
      return GestureDetector(
        key: const Key('toolbar-drag'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => unawaited(_previewController.startDrag()),
        onDoubleTap: () => unawaited(_previewController.toggleZoom()),
        child: SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Row(
            children: [
              const Spacer(flex: 5),
              if (size > 0) ...[
                const Spacer(flex: 2),
                IgnorePointer(
                  child: _Wordmark(key: const Key('wordmark'), fontSize: size),
                ),
                const Spacer(flex: 2),
              ],
              const Spacer(flex: 5),
            ],
          ),
        ),
      );
    },
  );

  Widget _branchPreviewControls() {
    Widget button(BranchPreviewMode mode, String label, Key key, Key labelKey) {
      final selected = _branchPreviewMode == mode;
      return Expanded(
        child: InkWell(
          key: key,
          onTap: _branchApplyBusy ? null : () => _setBranchPreviewMode(mode),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? _previewControlBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              key: labelKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : _palette.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const Key('branch-preview-segmented'),
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _palette.background,
        border: Border.all(color: _palette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          button(
            BranchPreviewMode.merge,
            'Merge 미리보기',
            const Key('branch-preview-merge-button'),
            const Key('branch-preview-merge'),
          ),
          button(
            BranchPreviewMode.rebase,
            'Rebase 미리보기',
            const Key('branch-preview-rebase-button'),
            const Key('branch-preview-rebase'),
          ),
        ],
      ),
    );
  }

  /// A merge or rebase preview is worth seeing the moment it exists, so the
  /// detail pane opens itself rather than waiting for a conflict to force it.
  /// A pane the user already placed is left where it is.
  Future<void> _openPaneForBranchPreview() async {
    if (_comparison == null || !mounted) return;
    if (_previewController.previewPlacement != PreviewPlacement.closed) return;
    await _previewController.setPreview(widget.preferredPreviewPlacement);
  }

  void _setBranchPreviewMode(BranchPreviewMode mode) {
    if (_branchPreviewMode == mode ||
        _branchApplyStatus == BranchApplyStatus.applying ||
        _branchApplyStatus == BranchApplyStatus.reverting) {
      return;
    }
    setState(() {
      _branchPreviewMode = mode;
      _resetBranchApply();
      final comparison = _comparison;
      if (comparison != null) {
        _previewGraph = mode == BranchPreviewMode.merge
            ? layoutMergePreviewGraph(comparison)
            : null;
        _comparisonRows =
            _previewGraph?.rows ?? layoutBranchComparison(comparison.commits);
        _comparisonEntries = [
          for (var index = 0; index < _comparisonRows.length; index++)
            (rowIndex: index, label: null, row: _comparisonRows[index]),
        ];
        _selectedIndex.value = 0;
      }
    });
    _showFirstComparisonRow();
    widget.onBranchPreviewModeChanged?.call(mode);
    unawaited(_openPaneForBranchPreview());
    _scheduleRatchetUpdate();
    if (mode == BranchPreviewMode.rebase) {
      _dropMergePreview();
      unawaited(_startRebasePreview());
    } else {
      _dropRebasePreview();
      if (_comparison?.merge.status == MergeConflictStatus.conflicts) {
        unawaited(_startMergePreview());
      }
    }
  }

  void _selectBaseBranch(String branch) {
    if (_branchApplyBusy ||
        !_refs.local.contains(branch) ||
        branch == _baseBranch) {
      return;
    }
    final compared = _compareRef;
    setState(() {
      _baseBranch = branch;
      _resetBranchApply();
      _rebuildGraph();
    });
    _scheduleRatchetUpdate();
    if (compared != null) {
      if (compared == branch) {
        _clearComparison();
      } else {
        unawaited(_selectComparison(compared));
      }
    }
    if (widget.preferredBranchReady) {
      widget.onPreferredBranchChanged?.call(branch);
    } else {
      _pendingBaseBranch = branch;
      _pendingBaseBranchIsUserSelection = true;
    }
    unawaited(_refreshRemotes());
    _focusNode.requestFocus();
  }

  Future<void> _selectComparison(
    String compareRef, {
    bool preserveCurrent = false,
  }) async {
    final baseRef = _baseBranch;
    if (_branchApplyBusy || baseRef == null || compareRef == baseRef) return;
    final serial = ++_comparisonSerial;
    if (!preserveCurrent) {
      _dropMergePreview();
      _dropRebasePreview();
      setState(() {
        _compareRef = compareRef;
        _resetBranchApply();
        _comparison = null;
        _comparisonRows = [];
        _comparisonEntries = [];
        _previewGraph = null;
        _rebaseCheck = null;
        _dropRecommendation();
        _dropCommitBadges();
        _comparisonError = null;
        _selectedIndex.value = 0;
      });
    }
    try {
      final result = await widget.repository.compareBranches(
        baseRef,
        compareRef,
      );
      if (!mounted ||
          serial != _comparisonSerial ||
          _baseBranch != baseRef ||
          _compareRef != compareRef) {
        return;
      }
      final rows = layoutBranchComparison(result.commits);
      if (preserveCurrent) {
        _dropMergePreview();
        _dropRebasePreview();
      }
      setState(() {
        _compareRef = compareRef;
        _resetBranchApply();
        _comparison = result;
        _previewGraph = _branchPreviewMode == BranchPreviewMode.merge
            ? layoutMergePreviewGraph(result)
            : null;
        _comparisonRows = _previewGraph?.rows ?? rows;
        _comparisonEntries = [
          for (var index = 0; index < _comparisonRows.length; index++)
            (rowIndex: index, label: null, row: _comparisonRows[index]),
        ];
        _rebaseCheck = null;
        _dropRecommendation();
        _dropCommitBadges();
        _comparisonError = null;
        _selectedIndex.value = 0;
      });
      _scheduleRatchetUpdate();
      _showFirstComparisonRow();
      unawaited(_loadDuplicateCommits(result, serial));
      unawaited(_loadConflictForecast(result, serial));
      unawaited(_openPaneForBranchPreview());
      if (_branchPreviewMode == BranchPreviewMode.rebase) {
        unawaited(_startRebasePreview());
      } else if (result.merge.status == MergeConflictStatus.conflicts) {
        unawaited(_startMergePreview());
        // 이 경로에는 재배치 실측이 없으니 추천 엔진이 직접 시뮬레이션한다.
        unawaited(_loadRecommendation(result, serial));
      } else {
        unawaited(_checkRebase(baseRef, compareRef, serial));
      }
    } catch (error) {
      if (!mounted ||
          serial != _comparisonSerial ||
          _compareRef != compareRef) {
        return;
      }
      setState(() => _comparisonError = error);
    }
  }

  Future<void> _checkRebase(
    String baseRef,
    String compareRef,
    int serial,
  ) async {
    try {
      await widget.repository.cleanupStalePreviewWorktrees();
      final result = await widget.repository.simulateRebase(
        baseRef: baseRef,
        compareRef: compareRef,
      );
      if (!mounted ||
          serial != _comparisonSerial ||
          _baseBranch != baseRef ||
          _compareRef != compareRef) {
        return;
      }
      setState(() => _rebaseCheck = result);
      final comparison = _comparison;
      if (comparison != null) {
        await _loadRecommendation(comparison, serial, rebaseCheck: result);
      }
    } catch (error) {
      if (!mounted ||
          serial != _comparisonSerial ||
          _compareRef != compareRef) {
        return;
      }
      setState(
        () => _rebaseCheck = RebaseCheckResult(
          status: RebaseCheckStatus.failed,
          error: error.toString(),
        ),
      );
    }
  }

  void _dropRecommendation() {
    _recommendationSerial++;
    _recommendation = null;
  }

  /// Asks the engine what the git facts lean towards. Nothing waits on this: the
  /// chip shows up whenever it lands, and a comparison change drops the answer.
  Future<void> _loadRecommendation(
    BranchComparisonResult comparison,
    int serial, {
    RebaseCheckResult? rebaseCheck,
  }) async {
    final request = ++_recommendationSerial;
    try {
      final recommendation = await widget.repository.recommendBranchIntegration(
        comparison: comparison,
        rebaseCheck: rebaseCheck,
      );
      if (!mounted ||
          request != _recommendationSerial ||
          serial != _comparisonSerial ||
          _comparison != comparison) {
        return;
      }
      setState(() => _recommendation = recommendation);
    } catch (_) {
      // 추천은 부가 정보라 실패하면 칩을 띄우지 않고 넘어간다.
    }
  }

  void _dropCommitBadges() {
    _conflictForecastSerial++;
    _duplicateCommits = const {};
    _conflictForecast = const {};
  }

  /// P1b — patch-id가 이미 base에 있는 커밋을 행 배지로 올린다. 기다리는 것은 없고
  /// 비교가 바뀌면 답은 버려진다. 자동 skip 같은 동작은 없다.
  Future<void> _loadDuplicateCommits(
    BranchComparisonResult comparison,
    int serial,
  ) async {
    try {
      final duplicates = await widget.repository.duplicateCompareCommits(
        baseTip: comparison.baseTip,
        compareTip: comparison.compareTip,
      );
      if (!mounted ||
          serial != _comparisonSerial ||
          _comparison != comparison) {
        return;
      }
      setState(() => _duplicateCommits = duplicates);
    } catch (_) {
      // 배지는 부가 정보라 실패하면 붙지 않고 넘어간다.
    }
  }

  /// P2 — 커밋별 단독 재생 예고. 새 비교나 미리보기 Drop이 진행 중인 예고를
  /// 취소하고 늦게 도착한 결과는 다른 브랜치 쌍에 붙지 못한다.
  Future<void> _loadConflictForecast(
    BranchComparisonResult comparison,
    int serial,
  ) async {
    final request = ++_conflictForecastSerial;
    try {
      final forecast = await widget.repository.probeRebaseConflicts(
        baseTip: comparison.baseTip,
        compareTip: comparison.compareTip,
        commits: [
          for (final entry in comparison.commits)
            if (entry.side == BranchCommitSide.compareOnly) entry.commit.sha,
        ],
        cancelled: () => !mounted || request != _conflictForecastSerial,
      );
      if (!mounted ||
          request != _conflictForecastSerial ||
          serial != _comparisonSerial ||
          _comparison != comparison) {
        return;
      }
      setState(() => _conflictForecast = forecast);
    } catch (_) {
      // 예고는 부가 정보라 실패하면 배지를 띄우지 않고 넘어간다.
    }
  }

  /// P3 — 충돌 파일마다 '양쪽 유지' 자격을 미리 물어 둔다. 자격이 있는 파일만
  /// 지도에 남고 그 파일에만 세 번째 버튼이 생긴다.
  Future<void> _loadKeepBothCandidates(
    Future<KeepBothCandidate?> Function(String path) probe,
    List<String> paths,
    bool Function() stale,
  ) async {
    final request = ++_keepBothSerial;
    for (final path in paths) {
      try {
        final candidate = await probe(path);
        if (!mounted || request != _keepBothSerial || stale()) return;
        if (candidate == null) continue;
        setState(() => _keepBothCandidates[path] = candidate);
      } catch (_) {
        // 제안은 부가 기능이라 실패하면 버튼 없이 기존 선택지만 남는다.
      }
    }
  }

  Future<void> _startMergePreview() async {
    final comparison = _comparison;
    if (_branchPreviewMode != BranchPreviewMode.merge ||
        comparison == null ||
        comparison.merge.status != MergeConflictStatus.conflicts) {
      return;
    }
    final request = ++_mergePreviewSerial;
    final previous = _mergePreviewSession;
    _mergePreviewSession = null;
    _mergePreview = null;
    if (previous != null) await previous.dispose();
    if (!mounted ||
        request != _mergePreviewSerial ||
        _branchPreviewMode != BranchPreviewMode.merge) {
      return;
    }
    try {
      final session = await widget.repository.openMergePreview(
        baseRef: comparison.baseRef,
        compareRef: comparison.compareRef,
      );
      if (!mounted ||
          request != _mergePreviewSerial ||
          _comparison != comparison ||
          _branchPreviewMode != BranchPreviewMode.merge) {
        await session.dispose();
        return;
      }
      _mergePreviewSession = session;
      final result = await session.start();
      if (!mounted ||
          request != _mergePreviewSerial ||
          _comparison != comparison ||
          _branchPreviewMode != BranchPreviewMode.merge) {
        await session.dispose();
        return;
      }
      if (result.baseTip != comparison.baseTip ||
          result.compareTip != comparison.compareTip) {
        _mergePreviewSession = null;
        await session.dispose();
        if (!mounted || request != _mergePreviewSerial) return;
        setState(() {
          _mergePreview = MergePreviewResult(
            status: MergePreviewStatus.failed,
            baseTip: result.baseTip,
            compareTip: result.compareTip,
            error: '브랜치가 변경되었습니다. 미리보기를 다시 선택해 주세요.',
          );
          _mergePreviewError = _mergePreview!.error;
        });
        return;
      }
      setState(() {
        _mergePreview = result;
        _mergePreviewError = null;
        _mergeResolvedFiles.clear();
        _dropKeepBoth();
      });
      if (result.status == MergePreviewStatus.conflict) {
        unawaited(
          _loadKeepBothCandidates(
            session.keepBothCandidate,
            result.conflictFiles,
            () => !identical(_mergePreviewSession, session),
          ),
        );
      }
      if (result.status == MergePreviewStatus.conflict &&
          _previewController.previewPlacement == PreviewPlacement.closed) {
        await _previewController.setPreview(widget.preferredPreviewPlacement);
      }
    } catch (error) {
      if (mounted && request == _mergePreviewSerial) {
        setState(() => _mergePreviewError = error);
      }
    }
  }

  void _dropMergePreview() {
    _mergePreviewSerial++;
    final session = _mergePreviewSession;
    _mergePreviewSession = null;
    _mergePreview = null;
    _mergePreviewBusy = false;
    _mergePreviewError = null;
    _mergeResolvedFiles.clear();
    _dropKeepBoth();
    if (session != null) unawaited(session.dispose());
  }

  void _dropKeepBoth() {
    _keepBothSerial++;
    _keepBothCandidates.clear();
    _keepBothOpenPath = null;
  }

  Future<void> _startRebasePreview() async {
    final comparison = _comparison;
    if (_branchPreviewMode != BranchPreviewMode.rebase || comparison == null) {
      return;
    }
    final request = ++_rebasePreviewSerial;
    final previous = _rebasePreviewSession;
    _rebasePreviewSession = null;
    _rebasePreview = null;
    if (previous != null) await previous.dispose();
    if (!mounted ||
        request != _rebasePreviewSerial ||
        _branchPreviewMode != BranchPreviewMode.rebase) {
      return;
    }
    setState(() => _rebaseCheck = null);
    try {
      final session = await widget.repository.openRebasePreview(
        baseRef: comparison.baseRef,
        compareRef: comparison.compareRef,
      );
      if (!mounted ||
          request != _rebasePreviewSerial ||
          _comparison != comparison ||
          _branchPreviewMode != BranchPreviewMode.rebase) {
        await session.dispose();
        return;
      }
      _rebasePreviewSession = session;
      final result = await session.start();
      if (!mounted ||
          request != _rebasePreviewSerial ||
          _comparison != comparison ||
          _branchPreviewMode != BranchPreviewMode.rebase) {
        await session.dispose();
        return;
      }
      await _applyRebasePreviewResult(comparison, result, request);
    } catch (error) {
      if (!mounted || request != _rebasePreviewSerial) return;
      setState(
        () => _rebaseCheck = RebaseCheckResult(
          status: RebaseCheckStatus.failed,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> _applyRebasePreviewResult(
    BranchComparisonResult comparison,
    RebasePreviewResult result,
    int request,
  ) async {
    if (result.baseTip != comparison.baseTip ||
        result.compareTip != comparison.compareTip) {
      final session = _rebasePreviewSession;
      _rebasePreviewSession = null;
      await session?.dispose();
      if (!mounted ||
          request != _rebasePreviewSerial ||
          _branchPreviewMode != BranchPreviewMode.rebase ||
          _comparison != comparison) {
        return;
      }
      const message = '브랜치가 변경되었습니다. 미리보기를 다시 선택해 주세요.';
      setState(() {
        _rebasePreview = RebasePreviewResult(
          status: RebasePreviewStatus.failed,
          baseTip: result.baseTip,
          compareTip: result.compareTip,
          error: message,
        );
        _rebasePreviewError = message;
        _rebaseCheck = const RebaseCheckResult(
          status: RebaseCheckStatus.failed,
          error: message,
        );
      });
      return;
    }
    final graph = layoutRebasePreviewGraph(
      comparison,
      result,
      mergeCommit: _rebaseApplyMerge,
    );
    final conflictIndex = graph.rows.indexWhere(
      (row) => row.commit.sha == result.currentCommit?.sha,
    );
    final session = _rebasePreviewSession;
    final operationInProgress = result.status == RebasePreviewStatus.conflict
        ? await widget.repository.operationInProgress()
        : false;
    if (!mounted ||
        request != _rebasePreviewSerial ||
        _branchPreviewMode != BranchPreviewMode.rebase ||
        _comparison != comparison ||
        !identical(_rebasePreviewSession, session)) {
      return;
    }
    setState(() {
      _rebasePreview = result;
      if (result.status == RebasePreviewStatus.conflict) {
        _rebaseHadConflict = true;
      }
      _rebasePreviewError = null;
      _repositoryOperationInProgress = operationInProgress;
      _rebaseResolvedFiles.clear();
      _rebaseEditedFiles.clear();
      _dropKeepBoth();
      _rebaseCheck = switch (result.status) {
        RebasePreviewStatus.clean => const RebaseCheckResult(
          status: RebaseCheckStatus.clean,
        ),
        RebasePreviewStatus.conflict => RebaseCheckResult(
          status: RebaseCheckStatus.conflicts,
          stoppedCommit: result.currentCommit?.sha,
          files: result.conflictFiles,
        ),
        RebasePreviewStatus.failed => RebaseCheckResult(
          status: RebaseCheckStatus.failed,
          error: result.error,
        ),
      };
      _previewGraph = graph;
      _comparisonRows = graph.rows;
      _comparisonEntries = [
        for (var index = 0; index < graph.rows.length; index++)
          (rowIndex: index, label: null, row: graph.rows[index]),
      ];
      _selectedIndex.value =
          result.status == RebasePreviewStatus.conflict && conflictIndex >= 0
          ? conflictIndex
          : 0;
    });
    _showPreviewTop();
    if (_rebaseCheck case final check?) {
      unawaited(
        _loadRecommendation(comparison, _comparisonSerial, rebaseCheck: check),
      );
    }
    if (result.status == RebasePreviewStatus.conflict && session != null) {
      unawaited(
        _loadKeepBothCandidates(
          session.keepBothCandidate,
          result.conflictFiles,
          () => !identical(_rebasePreviewSession, session),
        ),
      );
    }
    if (result.status == RebasePreviewStatus.conflict &&
        _previewController.previewPlacement == PreviewPlacement.closed) {
      await _previewController.setPreview(widget.preferredPreviewPlacement);
    }
    _scheduleRatchetUpdate();
    if (result.status == RebasePreviewStatus.clean) {
      _showFirstComparisonRow();
    } else if (result.status == RebasePreviewStatus.conflict) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rowContext = _rebaseConflictRowContextKey.currentContext;
        if (!mounted || rowContext == null) return;
        unawaited(
          Scrollable.ensureVisible(
            rowContext,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          ),
        );
      });
    }
  }

  void _showFirstComparisonRow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _compareRef == null ||
          !_scrollController.hasClients ||
          _scrollController.offset == 0) {
        return;
      }
      _scrollController.jumpTo(0);
    });
  }

  void _showPreviewTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _previewFilesScrollController.hasClients) {
        _previewFilesScrollController.jumpTo(
          _previewFilesScrollController.position.minScrollExtent,
        );
      }
    });
  }

  void _dropRebasePreview() {
    _rebasePreviewSerial++;
    final session = _rebasePreviewSession;
    _rebasePreviewSession = null;
    _rebasePreview = null;
    _rebasePreviewBusy = false;
    _repositoryOperationInProgress = false;
    _rebaseHadConflict = false;
    _rebaseResolvedFiles.clear();
    _rebaseEditedFiles.clear();
    _rebasePreviewError = null;
    _rebaseApplyMerge = false;
    _dropKeepBoth();
    if (session != null) unawaited(session.dispose());
  }

  void _resetBranchApply() {
    _branchApplySerial++;
    _branchApplyStatus = BranchApplyStatus.idle;
    _branchApplyResult = null;
    _branchApplyError = null;
    _rebaseApplyingSha = null;
    _rebaseApplyMerge = false;
    _branchPreviewDropped = false;
  }

  void _clearComparison() {
    if (_branchApplyBusy || _compareRef == null) return;
    _dropMergePreview();
    _dropRebasePreview();
    _comparisonSerial++;
    setState(() {
      _compareRef = null;
      _resetBranchApply();
      _comparison = null;
      _comparisonRows = [];
      _comparisonEntries = [];
      _previewGraph = null;
      _rebaseCheck = null;
      _dropRecommendation();
      _dropCommitBadges();
      _comparisonError = null;
      if (_normalEntries.isNotEmpty) {
        _selectedIndex.value = _selectedIndex.value.clamp(
          0,
          _normalEntries.length - 1,
        );
      }
    });
    _scheduleRatchetUpdate();
    _focusNode.requestFocus();
  }

  bool _canCherryPick(GitCommit commit) {
    if (_cherryPickBusy ||
        _cherryPickState != null ||
        _refs.current == null ||
        commit.isWorkingTree ||
        commit.sha == _refs.localTips[_refs.current]) {
      return false;
    }
    final comparison = _comparison;
    if (comparison == null) return true;
    if (_previewGraph?.kinds.containsKey(commit.sha) == true) return false;
    return comparison.commits
            .firstWhere((entry) => entry.commit.sha == commit.sha)
            .side ==
        BranchCommitSide.compareOnly;
  }

  Future<void> _showCommitMenu(GitCommit commit, Offset position) async {
    if (!_canCherryPick(commit)) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'cherry-pick', child: Text('현재 브랜치로 체리픽')),
      ],
    );
    if (action == 'cherry-pick' && mounted) {
      await _confirmCherryPick(commit);
    }
  }

  Future<void> _confirmCherryPick(GitCommit commit) async {
    final current = _refs.current;
    if (current == null || !_canCherryPick(commit)) return;
    final approved = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: '이 커밋을 체리픽할까요?',
        message: commit.subject,
        body: YogitAlertBlock([commit.sha, '→ $current']),
        confirmLabel: '체리픽',
        confirmKey: const Key('cherry-pick-confirm'),
      ),
    );
    if (approved == true) await _runCherryPick(commit.sha);
  }

  Future<void> _runCherryPick(String sha) async {
    if (_cherryPickBusy) return;
    setState(() {
      _cherryPickBusy = true;
      _cherryPickError = null;
    });
    try {
      await _handleCherryPickResult(await widget.repository.cherryPick(sha));
    } catch (error) {
      if (mounted) {
        setState(() => _cherryPickError = error);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _cherryPickBusy = false);
    }
  }

  Future<void> _handleCherryPickResult(CherryPickResult result) async {
    if (!mounted) return;
    if (result.outcome == CherryPickOutcome.conflicts) {
      setState(() {
        _cherryPickState = result.state;
        _selectedConflictPath = result.state?.conflicts.isEmpty == false
            ? result.state!.conflicts.first
            : null;
      });
      if (_previewController.previewPlacement == PreviewPlacement.closed) {
        await _previewController.setPreview(widget.preferredPreviewPlacement);
      }
      return;
    }
    setState(() {
      _cherryPickState = null;
      _selectedConflictPath = null;
    });
    if (result.outcome == CherryPickOutcome.empty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('적용할 변경이 없습니다')));
    }
    await _reloadTimelineAfterCherryPick(result.headSha);
  }

  Future<void> _continueCherryPick() async {
    if (_cherryPickBusy || _cherryPickState?.canContinue != true) return;
    setState(() {
      _cherryPickBusy = true;
      _cherryPickError = null;
    });
    try {
      await _handleCherryPickResult(
        await widget.repository.continueCherryPick(),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _cherryPickError = error);
        await _reloadCherryPickState();
      }
    } finally {
      if (mounted) setState(() => _cherryPickBusy = false);
    }
  }

  Future<void> _confirmAbortCherryPick() async {
    final approved = await showYogitAlert<bool>(
      context,
      const YogitAlert(
        title: '체리픽을 중단할까요?',
        message: '체리픽을 시작하기 전 상태로 되돌립니다.',
        role: YogitAlertRole.destructive,
        confirmLabel: '중단',
        confirmKey: Key('abort-cherry-pick-confirm'),
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _cherryPickBusy = true);
    try {
      await widget.repository.abortCherryPick();
      if (!mounted) return;
      setState(() {
        _cherryPickState = null;
        _selectedConflictPath = null;
        _cherryPickError = null;
      });
      await _reloadTimelineAfterCherryPick(null);
    } catch (error) {
      if (mounted) setState(() => _cherryPickError = error);
    } finally {
      if (mounted) setState(() => _cherryPickBusy = false);
    }
  }

  /// The local branch whose context menu is open; its row keeps the hover
  /// highlight while the popup covers the pointer.
  String? _contextMenuRef;

  /// Right-click on a local branch row: the delete menu at the pointer.
  Future<void> _showLocalBranchMenu(Offset position, String branch) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    setState(() => _contextMenuRef = branch);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          key: Key('sidebar-delete-branch-$branch'),
          value: 'delete',
          height: 34,
          child: const Text('브랜치 삭제', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
    if (mounted) {
      setState(() => _contextMenuRef = null);
    } else {
      _contextMenuRef = null;
    }
    if (action == 'delete' && mounted) await _confirmDeleteBranch(branch);
  }

  Future<void> _confirmDeleteBranch(String branch) async {
    final approved = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: '브랜치를 삭제할까요?',
        message: branch,
        detail: '병합되지 않은 커밋도 함께 사라집니다.',
        role: YogitAlertRole.destructive,
        confirmLabel: '삭제',
        confirmKey: const Key('delete-branch-confirm'),
      ),
    );
    if (approved != true || !mounted) return;
    try {
      await widget.repository.deleteLocalBranch(branch);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$branch 브랜치 삭제됨')));
      // The deleted ref may be the timeline's base or decorate loaded rows, so
      // the whole page reloads rather than patching refs in place.
      await _reloadTimelineAfterCherryPick(null);
    } on ProcessException catch (error) {
      if (!mounted) return;
      if (error.message.contains('used by worktree')) {
        await _confirmDeleteWorktreeAndBranch(branch);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('브랜치 삭제 실패: ${error.message.trim()}')),
      );
    }
  }

  /// The branch lives in a worktree, so deleting it means deleting that
  /// checkout too. A second dialog says which directory dies and how much
  /// space that frees.
  Future<void> _confirmDeleteWorktreeAndBranch(String branch) async {
    String? path;
    int? size;
    try {
      path = await widget.repository.branchWorktreePath(branch);
      if (path != null) size = await directorySizeBytes(path);
    } catch (_) {
      // A half-broken worktree still gets the dialog; only the size line goes.
    }
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$branch: 워크트리를 찾지 못해 삭제하지 않았습니다.')),
      );
      return;
    }
    final approved = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: '워크트리도 함께 삭제할까요?',
        message: '$branch 브랜치는 아래 워크트리에 체크아웃되어 있습니다.',
        body: YogitAlertBlock([shortenHomePath(path)]),
        detail: size == null ? null : '함께 삭제하면 ${byteSizeLabel(size)}를 확보합니다.',
        role: YogitAlertRole.destructive,
        confirmLabel: '둘 다 삭제',
        confirmKey: const Key('delete-worktree-confirm'),
      ),
    );
    if (approved != true || !mounted) return;
    try {
      await widget.repository.removeWorktree(path);
      await widget.repository.deleteLocalBranch(branch);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            size == null
                ? '$branch 브랜치와 워크트리 삭제됨'
                : '$branch 브랜치와 워크트리 삭제됨 · ${byteSizeLabel(size)} 확보',
          ),
        ),
      );
      await _reloadTimelineAfterCherryPick(null);
    } on ProcessException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: ${error.message.trim()}')),
        );
      }
    }
  }

  Future<void> _reloadTimelineAfterCherryPick(String? headSha) async {
    widget.repository.invalidateHistory();
    setState(() {
      _normalCommits.clear();
      _normalRows = [];
      _normalEntries = [];
      _committersBySha.clear();
      _previewFiles.clear();
      _previewFileLists.clear();
      _previewDiffs.clear();
      _previewPaths.clear();
      _hasWorkingTree = false;
      _end = false;
      _loadError = null;
      _selectedIndex.value = 0;
    });
    await _fetchNextPage();
    await _loadRefs();
    // Whatever the repository says after a reload is what the timeline shows,
    // so an app-initiated change never comes back as a prompt.
    await _syncLocalSignature();
    if (!mounted || headSha == null) return;
    final index = _entries.indexWhere(
      (entry) => entry.rowIndex >= 0 && entry.row.commit.sha == headSha,
    );
    if (index >= 0) _selectedIndex.value = index;
  }

  Widget _toolbarRight(bool showPreviewLabel, bool showShortcuts) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      if (showShortcuts) ...[_shortcutHint(), const SizedBox(width: 12)],
      // The caption sits beside the box, not inside it.
      if (showPreviewLabel)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            '미리보기',
            style: TextStyle(color: _palette.muted, fontSize: 14),
          ),
        ),
      Container(
        key: const Key('preview-placement'),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: _palette.raised,
          border: Border.all(color: _palette.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            _placementButton('좌측', PreviewPlacement.left),
            _placementButton('우측', PreviewPlacement.right),
            _placementButton('하단', PreviewPlacement.bottom),
          ],
        ),
      ),
      const SizedBox(width: 12),
      if (widget.onOpenMonitor != null) ...[
        TextButton(
          key: const Key('toolbar-monitor'),
          style: TextButton.styleFrom(
            foregroundColor: _palette.text,
            backgroundColor: _palette.raised,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: _palette.border),
            ),
          ),
          onPressed: () {
            final branch = _baseBranch ?? _refs.current;
            if (branch != null) widget.onOpenMonitor!(branch);
          },
          child: const Text('모니터링', style: TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 8),
      ],
      _toolbarFullDiffButton(),
      const SizedBox(width: 8),
      _HoverBuilder(
        enabled: widget.onOpenSettings != null,
        builder: (hovered) => Container(
          key: const Key('settings-hover-surface'),
          decoration: BoxDecoration(
            color: hovered ? _palette.selectedRow : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: IconButton(
            key: const Key('open-settings'),
            tooltip: 'Settings',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onOpenSettings,
            icon: AnimatedRotation(
              key: const Key('settings-hover-turn'),
              turns: hovered ? 0.05 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(
                Icons.settings_outlined,
                size: 22,
                color: hovered ? _palette.text : _palette.muted,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  /// The full-diff shortcut in the toolbar: the name with its key combination
  /// under it, dimmed while the selection is a date heading with no commit.
  Widget _toolbarFullDiffButton() => ValueListenableBuilder<int>(
    valueListenable: _selectedIndex,
    builder: (context, _, _) => _ShowDiffButton(
      key: const Key('toolbar-full-diff'),
      onTap: _selectedCommit == null ? null : _openFullDiff,
    ),
  );

  Widget _placementButton(String label, PreviewPlacement placement) {
    final pressed = _activePlacement == placement;
    return _HoverBuilder(
      builder: (hovered) => GestureDetector(
        key: Key('placement-$placement'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.onPreviewPlacementChanged?.call(placement);
          unawaited(_previewController.setPreview(placement));
          _focusNode.requestFocus();
        },
        child: Container(
          key: Key('placement-hover-$placement'),
          height: 30,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: pressed || hovered ? _palette.selectedRow : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: pressed || hovered ? Colors.white : _palette.muted,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _shortcutHint() => Row(
    key: const Key('shortcut-hint'),
    children: [
      Text('상세', style: TextStyle(color: _palette.muted, fontSize: 14)),
      const SizedBox(width: 6),
      _KeyCap(
        label: 'Enter',
        onTap: () {
          if (_commits.isEmpty) return;
          _togglePreview();
          _focusNode.requestFocus();
        },
      ),
    ],
  );

  // ---------------------------------------------------------------- sidebar

  /// The sidebar, with a drag handle on its right edge. The timeline sits in the
  /// leftover width, so its own flex math follows along for free.
  Widget _sidebar() {
    final width = _sidebarCollapsed ? _collapsedSidebarWidth : _sidebarWidth;
    return SizedBox(
      key: const Key('sidebar'),
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: _sidebarCollapsed ? _collapsedSidebarBody() : _sidebarBody(),
          ),
          if (!_sidebarCollapsed)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  key: const Key('sidebar-resizer'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) => setState(
                    () => _sidebarWidth = (_sidebarWidth + details.delta.dx)
                        .clamp(_sidebarRange.min, _sidebarRange.max),
                  ),
                  onHorizontalDragEnd: (_) => _saveColumnWidths(),
                  onHorizontalDragCancel: _saveColumnWidths,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sidebarBody() => Container(
    decoration: BoxDecoration(
      color: _palette.panel,
      border: Border(right: BorderSide(color: _palette.border)),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  label: '브랜치와 태그 찾기',
                  textField: true,
                  child: TextField(
                    key: const Key('ref-filter'),
                    controller: _filterController,
                    onChanged: (value) => setState(() => _filter = value),
                    style: TextStyle(color: _palette.text, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      // The magnifier replaces the hint sentence; the wording
                      // lives on in the semantics label and the tooltip.
                      prefixIcon: Tooltip(
                        message: '브랜치와 태그 찾기',
                        child: Center(
                          widthFactor: 1,
                          child: SearchIcon(
                            key: const Key('ref-filter-search-icon'),
                            color: _palette.muted,
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      filled: true,
                      fillColor: _palette.raised,
                      contentPadding: const EdgeInsets.only(
                        right: 8,
                        top: 7,
                        bottom: 7,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: _palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: _palette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: _palette.interactive),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _sidebarToggleButton(opens: false),
            ],
          ),
        ),
        _sidebarActionStrip(),
        Expanded(
          child: Focus(
            focusNode: _sidebarFocusNode,
            onKeyEvent: _onSidebarKeyEvent,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                // The checked-out branch leads the local list.
                ..._refSection(_RefSection.local, _localBranches),
                ..._refSection(_RefSection.remote, _refs.remote),
                ..._refSection(_RefSection.tags, _refs.tags),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _collapsedSidebarBody() => Container(
    decoration: BoxDecoration(
      color: _palette.panel,
      border: Border(right: BorderSide(color: _palette.border)),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: _sidebarToggleButton(opens: true),
        ),
        _compactSidebarSection(_RefSection.local, _localBranches.length),
        _compactSidebarSection(_RefSection.remote, _refs.remote.length),
        _compactSidebarSection(_RefSection.tags, _refs.tags.length),
      ],
    ),
  );

  Widget _sidebarToggleButton({required bool opens}) => _shortcutBadge(
    label: shortcutLabel('1'),
    hintKey: const Key('sidebar-toggle-shortcut'),
    child: Tooltip(
      message: opens ? '왼쪽 패널 열기' : '왼쪽 패널 닫기',
      waitDuration: Duration.zero,
      child: SizedBox(
        width: 28,
        height: 28,
        child: IconButton(
          key: Key(opens ? 'sidebar-expand-button' : 'sidebar-collapse-button'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          onPressed: () => setState(() => _sidebarCollapsed = !opens),
          icon: CustomPaint(
            key: Key(opens ? 'sidebar-expand-icon' : 'sidebar-collapse-icon'),
            size: const Size(14.4, 14.4),
            painter: _PaneToggleIconPainter(
              opens: opens,
              color: _palette.muted,
            ),
          ),
        ),
      ),
    ),
  );

  /// Hangs a key-combination badge under [child] while the command modifier
  /// is held, in the timeline's own palette.
  Widget _shortcutBadge({
    required String label,
    required Widget child,
    Key? hintKey,
  }) => FullDiffShortcutHint(
    visible: _modifierHeld,
    label: label,
    hintKey: hintKey,
    background: _palette.raised,
    borderColor: _palette.border,
    textColor: _palette.text,
    child: child,
  );

  Widget _compactSidebarSection(_RefSection section, int count) => Semantics(
    label: '${section.label} $count',
    child: Container(
      key: Key('sidebar-compact-section-${section.name}'),
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _palette.border)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(section.icon, size: 14, color: _palette.muted),
          const SizedBox(height: 3),
          Text(
            '$count',
            style: TextStyle(
              color: _palette.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );

  /// Checked-out branch first, then by how far up the timeline each tip sits, so
  /// the freshest work leads. A tip outside the loaded rows trails alphabetically.
  List<String> get _localBranches {
    final rest = [..._refs.local.where((name) => name != _refs.current)];
    final rows = <String, int>{};
    for (final name in rest) {
      final tip = _refs.tips[name];
      final row = _entries.indexWhere(
        (entry) =>
            entry.rowIndex >= 0 &&
            (entry.row.commit.sha == tip ||
                entry.row.commit.refs.any((ref) => ref.name == name)),
      );
      if (row >= 0) rows[name] = row;
    }
    rest.sort((a, b) {
      final left = rows[a];
      final right = rows[b];
      if (left != null && right != null) return left.compareTo(right);
      if (left != null) return -1;
      if (right != null) return 1;
      return a.compareTo(b);
    });
    return [if (_refs.local.contains(_refs.current)) _refs.current!, ...rest];
  }

  Iterable<Widget> _refSection(_RefSection section, List<String> names) sync* {
    final filtering = _filter.trim().isNotEmpty;
    final collapsed = !filtering && _collapsedRefSections.contains(section);
    final headerColor = _palette.text.withValues(alpha: 0.82);
    yield GestureDetector(
      key: Key('sidebar-section-${section.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (!_collapsedRefSections.remove(section)) {
          _collapsedRefSections.add(section);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 5),
        child: Container(
          key: Key('sidebar-section-band-${section.name}'),
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: _palette.raised.withValues(alpha: 0.7),
            border: Border.symmetric(
              horizontal: BorderSide(
                color: _palette.border.withValues(alpha: 0.7),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 16,
                color: headerColor,
              ),
              const SizedBox(width: 2),
              Icon(
                section.icon,
                key: Key('sidebar-section-icon-${section.name}'),
                size: 14,
                color: headerColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: headerColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              SizedBox(
                key: Key('sidebar-section-count-${section.name}'),
                child: Text(
                  '${names.length}',
                  style: TextStyle(
                    color: headerColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (collapsed) return;

    final hiddenTagCount = section == _RefSection.tags
        ? math.max(0, names.length - _collapsedTagLimit)
        : 0;
    yield* _refTreeRows(
      section,
      buildRefTree(_visibleSectionNames(section, names)),
    );
    if (section == _RefSection.tags && !filtering && hiddenTagCount > 0) {
      yield _tagOverflowRow(hiddenTagCount);
    }
  }

  /// The names a section shows, after tag ordering/projection and the filter.
  /// Shared with [_visibleRefRows] so keyboard navigation walks exactly the
  /// rows on screen.
  List<String> _visibleSectionNames(_RefSection section, List<String> names) {
    final query = _filter.trim().toLowerCase();
    final filtering = query.isNotEmpty;
    final orderedNames = section == _RefSection.tags
        ? sortRefsNewestFirst(names, _refs.tagCreatorTimes)
        : names;
    final projectedNames =
        section == _RefSection.tags && !filtering && !_showAllTags
        ? orderedNames.take(_collapsedTagLimit).toList()
        : orderedNames;
    return filtering
        ? orderedNames.where((name) => fuzzyMatch(name, query)).toList()
        : projectedNames;
  }

  Widget _tagOverflowRow(int hiddenTagCount) => GestureDetector(
    key: const Key('sidebar-tags-overflow'),
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _showAllTags = !_showAllTags),
    child: SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(
              _showAllTags ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: _palette.muted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _showAllTags ? '태그 접기' : '나머지 $hiddenTagCount개',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _palette.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Iterable<Widget> _refTreeRows(
    _RefSection section,
    List<RefTreeNode> nodes, {
    int depth = 0,
    String parentPath = '',
  }) sync* {
    final filtering = _filter.trim().isNotEmpty;
    for (final node in nodes) {
      final path = parentPath.isEmpty
          ? node.segment
          : '$parentPath/${node.segment}';
      yield _refTreeRow(section, node, path, depth);
      final folderKey = '${section.name}:$path';
      final collapsed = !filtering && _collapsedRefFolders.contains(folderKey);
      if (node.children.isNotEmpty && !collapsed) {
        yield* _refTreeRows(
          section,
          node.children,
          depth: depth + 1,
          parentPath: path,
        );
      }
    }
  }

  /// The dot takes the color of the branch line the ref tip sits on. Muted while
  /// that commit is still unloaded.
  Color _refTipColor(String name) {
    final tip = _refs.tips[name];
    for (final row in _rows) {
      if (row.commit.sha == tip ||
          row.commit.refs.any((ref) => ref.name == name)) {
        return AvatarService.branchColor(row.branch);
      }
    }
    return _palette.muted;
  }

  Widget _refTreeRow(
    _RefSection section,
    RefTreeNode node,
    String path,
    int depth,
  ) {
    final name = node.fullName;
    final hasChildren = node.children.isNotEmpty;
    final folderKey = '${section.name}:$path';
    final folderCollapsed =
        _filter.trim().isEmpty && _collapsedRefFolders.contains(folderKey);
    final birth = name == null ? null : _refs.birthTimes[name];
    final current =
        section == _RefSection.local && name != null && name == _refs.current;
    final icon = name == null
        ? Icons.folder_outlined
        : section == _RefSection.tags
        ? Icons.sell_outlined
        : Icons.call_split;
    final iconColor = name != null && section != _RefSection.tags
        ? _refTipColor(name)
        : _palette.muted;
    final selectedLocal =
        section == _RefSection.local && name != null && name == _baseBranch;
    final behind = selectedLocal ? _refs.aheadBehind[name]?.behind ?? 0 : 0;
    final remoteDifference = section == _RefSection.remote && name != null
        ? _refs.remoteAheadBehind[name]
        : null;
    final remoteAhead = remoteDifference?.ahead ?? 0;
    final remoteBehind = remoteDifference?.behind ?? 0;
    final pullState = section == _RefSection.remote && name != null
        ? remotePullState(_refs, name)
        : null;
    final inFolderTree = name == null || depth > 0;

    void toggleFolder() => setState(() {
      if (!_collapsedRefFolders.remove(folderKey)) {
        _collapsedRefFolders.add(folderKey);
      }
    });

    Widget buildContent(bool hovered) => Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  node.segment,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: current || hovered ? _palette.text : _palette.muted,
                    fontSize: 13,
                  ),
                ),
              ),
              if (current) const SizedBox(width: 2),
              if (current)
                Tooltip(
                  message: '현재 체크아웃된 브랜치입니다',
                  child: Container(
                    key: Key('sidebar-head-$name'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      border: Border.all(
                        color: iconColor.withValues(alpha: 0.8),
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'HEAD',
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        fontFamily: technicalFontFamily,
                        fontFamilyFallback: technicalFontFallback,
                      ),
                    ),
                  ),
                ),
              if (behind > 0) const SizedBox(width: 4),
              if (behind > 0)
                Tooltip(
                  message: '원격보다 $behind개 커밋 뒤처져 있습니다',
                  child: SizedBox(
                    key: Key('sidebar-behind-$name'),
                    child: Text(
                      '$behind',
                      style: const TextStyle(
                        color: _remoteBehind,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              // On hover the ↓ button takes this slot; the menu header
              // repeats the divergence, so the badge can yield to it.
              if ((remoteAhead > 0 || remoteBehind > 0) &&
                  !(pullState != null &&
                      (hovered || _pullingRemote == name))) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: [
                    if (remoteAhead > 0) '로컬보다 $remoteAhead개 커밋 앞서 있습니다',
                    if (remoteBehind > 0) '로컬보다 $remoteBehind개 커밋 뒤처져 있습니다',
                  ].join(' · '),
                  child: SizedBox(
                    width: 36,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text.rich(
                        key: Key('sidebar-remote-divergence-$name'),
                        TextSpan(
                          children: [
                            if (remoteAhead > 0)
                              TextSpan(
                                text: '+$remoteAhead',
                                style: const TextStyle(color: _success),
                              ),
                            if (remoteAhead > 0 && remoteBehind > 0)
                              const TextSpan(text: ' '),
                            if (remoteBehind > 0)
                              TextSpan(
                                text: '−$remoteBehind',
                                style: const TextStyle(color: _remoteBehind),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // When the branch was cut, in the Date column's own words.
          if (birth != null)
            Text(
              socialTimeLabel(
                DateTime.fromMillisecondsSinceEpoch(birth * 1000),
                DateTime.now(),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hovered
                    ? _palette.text.withValues(alpha: 0.72)
                    : _palette.muted,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );

    Widget buildRow() => SizedBox(
      key: name == null ? null : Key('sidebar-row-$name'),
      height: birth == null ? 28 : 40,
      child: Padding(
        padding: EdgeInsets.only(
          left: 4 + (inFolderTree ? 18 : 0) + depth * 16.0,
          right: 4,
        ),
        child: Row(
          children: [
            if (hasChildren)
              GestureDetector(
                key: Key('sidebar-folder-${section.name}-$path'),
                behavior: HitTestBehavior.opaque,
                onTap: toggleFolder,
                child: SizedBox(
                  width: 18,
                  height: double.infinity,
                  child: Icon(
                    folderCollapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 16,
                    color: _palette.muted,
                  ),
                ),
              )
            else
              const SizedBox(width: 18),
            if (name == null) ...[
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 7),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: toggleFolder,
                  child: buildContent(false),
                ),
              ),
            ] else
              Expanded(
                child: _HoverBuilder(
                  // The row keeps its hover look while its context menu is
                  // open or the keyboard cursor sits on it, so the highlight
                  // doesn't die under the popup or between key presses.
                  builder: (pointerHovered) {
                    final pointerActive =
                        pointerHovered || _contextMenuRef == name;
                    final cursorHere = _sidebarCursor == (section, name);
                    final hovered = pointerActive || cursorHere;
                    // The cursor keeps its shape but drains to gray while the
                    // keyboard lives in the timeline, so only one pane's
                    // selection carries color at a time.
                    final sidebarFocused = _sidebarFocusNode.hasFocus;
                    final cursorFill = sidebarFocused
                        ? _palette.selectedRow
                        : _achromatic(_palette.selectedRow);
                    final cursorEdge = sidebarFocused
                        ? iconColor
                        : _achromatic(iconColor);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Double-clicks are detected by hand: an onDoubleTap
                      // recognizer would hold the gesture arena and delay every
                      // single click on the row and its pull button by 300 ms.
                      onTap: () {
                        // A click moves the keyboard cursor here too, so the
                        // arrows continue from the clicked row.
                        setState(() => _sidebarCursor = (section, name));
                        _sidebarFocusNode.requestFocus();
                        if (pullState == null) {
                          _selectRef(
                            name,
                            remote: section == _RefSection.remote,
                            focusTimeline: false,
                          );
                        } else {
                          _tapRemoteRow(name);
                        }
                      },
                      // HEAD is excluded: git refuses to delete the checked-out
                      // branch, so the menu never offers it.
                      onSecondaryTapDown:
                          section == _RefSection.local && !current
                          ? (details) => unawaited(
                              _showLocalBranchMenu(
                                details.globalPosition,
                                name,
                              ),
                            )
                          : null,
                      child: Stack(
                        key: Key('sidebar-ref-hover-$name'),
                        clipBehavior: Clip.none,
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            left: -5,
                            top: 0,
                            right: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              key: Key('sidebar-ref-hover-background-$name'),
                              decoration: BoxDecoration(
                                // Selection paints like the timeline's
                                // selected row, a plain hover like the
                                // timeline's hover chip.
                                color: cursorHere
                                    ? cursorFill
                                    : pointerActive
                                    ? _palette.neutralChip.withValues(
                                        alpha: 0.48,
                                      )
                                    : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: cursorHere
                                        ? cursorEdge
                                        : Colors.transparent,
                                    width: cursorHere ? 2 : 0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Icon(icon, size: 13, color: iconColor),
                              const SizedBox(width: 7),
                              Expanded(
                                child: KeyedSubtree(
                                  key: Key('sidebar-ref-$name'),
                                  child: buildContent(hovered),
                                ),
                              ),
                            ],
                          ),
                          // Overlaid on the row's right edge so the ↓ button
                          // never widens the row when it appears on hover.
                          if (pullState != null)
                            Positioned(
                              right: 2,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _pullingRemote == name
                                    ? SizedBox(
                                        key: Key('sidebar-pull-busy-$name'),
                                        width: 22,
                                        height: 22,
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _palette.interactive,
                                          ),
                                        ),
                                      )
                                    : RemotePullMenuButton(
                                        remoteBranch: name,
                                        state: pullState,
                                        controller:
                                            _pullMenuControllers[name] ??=
                                                MenuController(),
                                        visible: hovered,
                                        onPull: () => unawaited(
                                          _runRemotePull(name, pullState),
                                        ),
                                        onCheckout: () => unawaited(
                                          _runRemoteCheckout(name, pullState),
                                        ),
                                        onCompare: () =>
                                            unawaited(_selectComparison(name)),
                                      ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );

    // Named rows carry a GlobalKey so the keyboard cursor can scroll to them.
    final row = name == null
        ? buildRow()
        : KeyedSubtree(
            key: _sidebarRowKeys['${section.name}:$name'] ??= GlobalKey(),
            child: buildRow(),
          );
    if (!current) return row;
    return DragTarget<GitCommit>(
      onWillAcceptWithDetails: (details) => _canCherryPick(details.data),
      onAcceptWithDetails: (details) =>
          unawaited(_confirmCherryPick(details.data)),
      builder: (context, candidates, rejected) => DecoratedBox(
        decoration: BoxDecoration(
          border: candidates.isEmpty
              ? null
              : Border.all(color: _main, width: 1.5),
          borderRadius: BorderRadius.circular(5),
        ),
        child: row,
      ),
    );
  }

  // -------------------------------------------------------------- status bar

  Widget _statusBar() => _normalStatusBar();

  Widget _normalStatusBar() => LayoutBuilder(
    builder: (context, constraints) {
      _statusBarWidth = constraints.maxWidth;
      return _normalStatusBarContent();
    },
  );

  /// The status bar's own width, so the profile chip can shed its email on a
  /// narrow window without a LayoutBuilder between Stack and Positioned.
  double _statusBarWidth = 0;

  Widget _normalStatusBarContent() => Container(
    height: 29,
    decoration: BoxDecoration(
      color: _palette.surface,
      border: Border(top: BorderSide(color: _palette.border)),
    ),
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ValueListenableBuilder<Object?>(
            valueListenable: _fetchError,
            builder: (context, error, _) => error == null
                ? Row(
                    children: [
                      _legend('commit', const _LegendDot()),
                      _legend('merge', const _LegendDot(filled: true)),
                      _legend('WIP', const _LegendDot(dashed: true)),
                    ],
                  )
                : Row(
                    children: [
                      Text(
                        '원격 갱신 실패',
                        style: TextStyle(color: _behind, fontSize: 10),
                      ),
                      const SizedBox(width: 4),
                      ValueListenableBuilder<bool>(
                        valueListenable: _fetchingRemotes,
                        builder: (context, fetching, _) => TextButton(
                          key: const Key('retry-origin-fetch'),
                          onPressed: fetching
                              ? null
                              : () => unawaited(_refreshRemotes()),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 24),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('다시 시도'),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        // The branch the focused commit's line belongs to, under the column that
        // line's chip sits in.
        Positioned(
          left: _sidebarWidth,
          top: 0,
          bottom: 0,
          width: math.max(0, _statusReadoutLeft - _sidebarWidth - 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ValueListenableBuilder<int>(
              valueListenable: _selectedIndex,
              builder: (context, _, _) {
                final name = _selectedLineRef;
                if (name == null) {
                  return const SizedBox(key: Key('status-ref'), height: 0);
                }
                return Row(
                  key: const Key('status-ref'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _palette.muted, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _CopyButton(
                      text: name,
                      color: _palette.muted,
                      slot: 'status-copy',
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        // The focused commit's moment under the column it belongs to, and the
        // identity on the far right. They share one row so a narrow window
        // cannot let the chip cover the date: the chip gives up its address
        // first, and only then does the stamp slide left of it.
        Positioned(
          left: _statusReadoutLeft,
          right: 12,
          top: 0,
          bottom: 0,
          child: Row(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _selectedIndex,
                builder: (context, _, _) {
                  final commit = _selectedCommit;
                  return Text(
                    key: const Key('status-timestamp'),
                    commit == null || commit.isWorkingTree || !_showTime
                        ? ''
                        : exactCommitTime(commit.committerTimestamp),
                    maxLines: 1,
                    style: _statusStampStyle.copyWith(color: _palette.muted),
                  );
                },
              ),
              const Spacer(),
              KeyedSubtree(
                key: _profileChipKey,
                child: CommitProfileChip(
                  state: _commitIdentity,
                  // A narrow window keeps the name and drops the address,
                  // which the tooltip still carries.
                  showEmail: _statusChipShowsEmail,
                  maxWidth: _statusChipWidth(),
                  warningColor: _behind,
                  onPressed: () => unawaited(_openCommitProfileMenu()),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// A narrow window keeps the name and drops the address, which the chip's
  /// tooltip still carries.
  bool get _statusChipShowsEmail => _statusBarWidth >= 900;

  /// The stamp's own width, measured from the widest form it can take — a
  /// commit from another year, which keeps its year. Measuring the widest form
  /// rather than the live value keeps the row from jittering as the selection
  /// moves between years.
  double get _statusStampWidth {
    final painter = TextPainter(
      text: const TextSpan(
        text: '2026-08-04 00:00:00',
        style: _statusStampStyle,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  /// What the chip needs: its avatar, gaps, padding and border plus the text
  /// it is showing, measured rather than guessed, and capped so one very long
  /// address cannot take the whole bar. Measuring means the stamp yields only
  /// the space the chip actually occupies.
  double _statusChipWidth() {
    // Measured in the style the chip actually renders — inheriting the app's
    // font, not the default one. Measuring in a narrower font made the chip's
    // box too small and clipped the very address it was meant to show.
    final chipTextStyle = DefaultTextStyle.of(
      context,
    ).style.copyWith(fontSize: 11);
    double textWidth(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: chipTextStyle),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    final email = _commitIdentity.identity.email.trim();
    var width =
        CommitProfileChip.minWidth + 6 + textWidth(_commitIdentity.label);
    if (_statusChipShowsEmail && email.isNotEmpty) {
      width += 6 + textWidth(email);
    }
    // No cap: an address the user needs to read is worth more than the stamp's
    // preferred column, and clipping it to a share of the bar hid the very
    // thing the chip exists to show. A few pixels of slack because a box
    // measured to the exact glyph advance still ellipsizes when rounding goes
    // the wrong way.
    return width + 4;
  }

  /// Where the stamp-and-identity row starts: under the sha the stamp belongs
  /// to, indented by the same 9px the column pads its text by. It is pulled
  /// left only when there is no room for the whole stamp plus a usable chip —
  /// the date is the thing that must stay readable, so the chip yields.
  double get _statusReadoutLeft {
    final rightmost =
        _statusBarWidth - 12 - _statusChipWidth() - 8 - _statusStampWidth;
    return math.max(
      0,
      math.min(_hashColumnLeft + _railedColumnTextInset, rightmost),
    );
  }

  Widget _legend(String label, Widget dot) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Row(
      children: [
        dot,
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: _palette.muted, fontSize: 10)),
      ],
    ),
  );

  // ---------------------------------------------------------------- timeline

  Widget _timeline() => LayoutBuilder(
    builder: (context, constraints) {
      // The title column gives first: it fills whatever the other five leave,
      // and a narrowing window compresses it — down to 100px, dragged or not —
      // before any other column clips.
      final graphWidth = _graphColumnWidth;
      final fixed = _widths.entries
          .where((entry) => _columnVisible(entry.key))
          .fold(graphWidth, (sum, entry) => sum + entry.value);
      final available = constraints.maxWidth - fixed;
      // The title column always swallows the leftover: nothing sits right of
      // the last column, so a narrower title could only ever produce dead
      // space. A dragged width is still saved, but the viewport decides —
      // down to the 100px minimum on a narrow window, as before.
      final commitWidth = math.max(timelineColumns['commit']!.min, available);
      _commitAvailableWidth = math.max(
        timelineColumns['commit']!.min,
        available,
      );
      double width(String column) => switch (column) {
        'commit' => commitWidth,
        'graph' => graphWidth,
        _ => _w(column),
      };
      _hashColumnLeft = _sidebarWidth + _w('refs') + graphWidth;
      return ColoredBox(
        color: _palette.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_compareRef != null) _branchPreviewSummary(),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  key: const Key('timeline-horizontal-content'),
                  width: fixed + commitWidth,
                  child: Column(
                    children: [
                      SizedBox(
                        height: _timelineHeaderHeight,
                        child: Row(
                          children: [
                            for (final column in timelineColumns.keys)
                              if (_columnVisible(column))
                                _header(column, width(column)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            ListView.builder(
                              key: const Key('timeline-list'),
                              controller: _scrollController,
                              itemExtent: TimelineScreen.rowHeight,
                              itemCount:
                                  _entries.length + (_showFooter ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _entries.length) return _footer();
                                final entry = _entries[index];
                                return entry.label == null
                                    ? _row(index, commitWidth, graphWidth)
                                    : _dateRow(index, entry, graphWidth);
                              },
                            ),
                            Positioned.fill(
                              child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    ListenableBuilder(
                                      listenable: Listenable.merge([
                                        _selectedIndex,
                                        _scrollController,
                                      ]),
                                      builder: (context, _) =>
                                          _refsModal(constraints.maxHeight),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  bool get _showFooter => _compareRef == null;

  MergeConflictStatus? get _effectiveMergeStatus =>
      switch (_mergePreview?.status) {
        MergePreviewStatus.clean => MergeConflictStatus.clean,
        MergePreviewStatus.conflict => MergeConflictStatus.conflicts,
        MergePreviewStatus.failed => MergeConflictStatus.failed,
        null => _comparison?.merge.status,
      };

  Widget _branchPreviewSummary() {
    final comparison = _comparison;
    final mergeMode = _branchPreviewMode == BranchPreviewMode.merge;
    final mergeStatus = _effectiveMergeStatus;
    final rebaseStatus = _rebasePreview?.status;
    final comparisonFailed = _comparisonError != null;
    final success = mergeMode
        ? mergeStatus == MergeConflictStatus.clean
        : _rebaseCheck?.status == RebaseCheckStatus.clean;
    final resultLabel = comparisonFailed
        ? '브랜치 비교 실패'
        : mergeMode
        ? switch (mergeStatus) {
            MergeConflictStatus.clean => 'Merge 성공',
            MergeConflictStatus.conflicts => 'Merge 충돌',
            MergeConflictStatus.failed => 'Merge 검사 실패',
            null => 'Merge 검사 중',
          }
        : switch (_rebaseCheck?.status) {
            RebaseCheckStatus.clean => 'Rebase 성공',
            RebaseCheckStatus.conflicts => 'Rebase 충돌',
            RebaseCheckStatus.failed => 'Rebase 검사 실패',
            null => 'Rebase 검사 중',
          };
    Widget detail(String value, {Color? color}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.12) ?? _palette.raised,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: color ?? _palette.muted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final details = <Widget>[];
    if (comparison != null) {
      if (mergeMode) {
        if (mergeStatus == MergeConflictStatus.clean) {
          details.addAll([
            detail('가상 커밋 1', color: _previewPurple),
            detail('충돌 없음', color: _success),
          ]);
        } else if (mergeStatus == MergeConflictStatus.conflicts) {
          final conflicts =
              _mergePreview?.conflictFiles.length ??
              comparison.merge.files.length;
          details.addAll([
            detail('충돌 $conflicts개', color: _previewConflict),
            detail('임시 공간 사용 중'),
          ]);
        }
      } else if (rebaseStatus == RebasePreviewStatus.conflict) {
        final preview = _rebasePreview!;
        details.addAll([
          detail(
            preview.completed == 0 ? '최초 충돌' : '다음 충돌',
            color: _previewConflict,
          ),
          detail('진행 ${preview.completed + 1}/${preview.total}'),
          detail('임시 공간 사용 중'),
        ]);
      } else if (_rebaseCheck?.status == RebaseCheckStatus.clean) {
        final count = _rebasePreview?.rewritten.length ?? 0;
        if (count > 0) {
          details.add(detail('가상 커밋 $count개'));
          // 선택에 따라 타임라인에 머지 커밋이 하나 더 그려지면 요약에서도 센다.
          if (_rebaseApplyMerge) {
            details.add(detail('머지 커밋 1개', color: _previewPurple));
          }
        }
        details.addAll([
          detail('점선 이동 경로', color: _previewPurple),
          detail('실제 브랜치 변경 없음'),
        ]);
      }
      // 칩은 두 모드 모두에서 상세 줄 끝에 붙는다. 계산이 끝나기 전에는 없다.
      if (_recommendation case final recommendation?) {
        details.add(_branchPreviewRecommendationChip(recommendation));
      }
    }
    final resultColor = comparisonFailed
        ? _behind
        : success
        ? _success
        : mergeStatus == MergeConflictStatus.conflicts ||
              rebaseStatus == RebasePreviewStatus.conflict
        ? _previewConflict
        : _palette.muted;
    final title = success
        ? mergeMode
              ? 'Merge 미리보기'
              : 'Rebase 미리보기'
        : resultLabel;
    return Container(
      key: const Key('branch-preview-summary'),
      height: _branchPreviewSummaryHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _palette.surface,
        border: Border(bottom: BorderSide(color: _palette.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: success ? _palette.text : resultColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (success) ...[
              const SizedBox(width: 5),
              const Icon(
                Icons.check_circle,
                key: Key('branch-preview-success-icon'),
                color: _success,
                size: 15,
              ),
            ],
            for (final detail in details) ...[const SizedBox(width: 8), detail],
            if (comparison != null) ...[
              const SizedBox(width: 12),
              Text(
                mergeMode
                    ? '${comparison.baseRef} ← ${comparison.compareRef}'
                    : '${comparison.compareRef} → ${comparison.baseRef}',
                style: TextStyle(color: _palette.muted, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The verdict chip, with the measured reasons a hover or a click away. It
  /// says what the facts lean towards and asks nothing.
  Widget _branchPreviewRecommendationChip(
    BranchRecommendation recommendation,
  ) => MenuAnchor(
    style: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(Color(0xFF202022)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: _palette.border),
        ),
      ),
    ),
    menuChildren: [
      Container(
        key: const Key('branch-preview-recommendation-reasons'),
        width: 430,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '왜 ${recommendation.label}인가',
              style: const TextStyle(
                color: _previewPurple,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final reason in recommendation.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '·',
                      style: TextStyle(color: _palette.muted, fontSize: 11),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(color: _palette.text, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
    builder: (context, controller, child) => MouseRegion(
      onEnter: (_) => controller.open(),
      child: InkWell(
        key: const Key('branch-preview-recommendation'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: _previewPurple.withValues(alpha: 0.10),
            border: Border.all(color: const Color(0xFF695786)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '추천: ${recommendation.label}',
                style: const TextStyle(
                  color: _previewPurple,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                recommendation.summary,
                style: TextStyle(
                  color: _palette.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  bool get _branchPreviewReady {
    final comparison = _comparison;
    if (comparison == null || _branchPreviewDropped) return false;
    return _branchPreviewMode == BranchPreviewMode.merge
        ? _effectiveMergeStatus == MergeConflictStatus.clean &&
              (_mergePreview?.treeSha ?? comparison.merge.treeSha) != null
        : _rebasePreview?.status == RebasePreviewStatus.clean &&
              _rebasePreview?.virtualTip != null;
  }

  BranchApplyTarget? get _branchPreviewTarget {
    final comparison = _comparison;
    if (comparison == null) return null;
    return resolveBranchApplyTarget(
      mode: _branchPreviewMode == BranchPreviewMode.merge
          ? BranchApplyMode.merge
          : BranchApplyMode.rebase,
      comparison: comparison,
      refs: _refs,
    );
  }

  bool get _branchPreviewCanPrepare =>
      _branchPreviewReady && _branchPreviewTarget != null;

  bool get _branchPreviewCanApply =>
      _branchPreviewCanPrepare && !_branchPreviewTarget!.needsRecalculation;

  bool get _branchApplyBusy =>
      _branchApplyStatus == BranchApplyStatus.applying ||
      _branchApplyStatus == BranchApplyStatus.reverting;

  String get _branchPreviewApplyLabel {
    final comparison = _comparison!;
    final target = _branchPreviewTarget;
    if (target?.needsRecalculation == true) {
      return '로컬 ${target!.localBranch} 기준으로 다시 계산';
    }
    // Rebase 쪽은 무엇을 적용할지 카드의 선택이 말하니 버튼 문구는 고정이다.
    return _branchPreviewMode == BranchPreviewMode.merge
        ? '${comparison.compareRef}를 ${target?.localBranch ?? comparison.baseRef}에 Merge 실제 적용'
        : '실제 적용하기';
  }

  String get _branchPreviewApplyHelp {
    final comparison = _comparison!;
    final target = _branchPreviewTarget;
    if (target == null) return '적용할 로컬 브랜치를 찾을 수 없습니다.';
    if (target.needsRecalculation) {
      return '기존 로컬 ${target.localBranch} 기준으로 다시 계산해야 합니다.';
    }
    if (target.createsBranch) {
      return '로컬 ${target.localBranch}를 ${target.selectedRef}에서 만든 뒤 결과를 적용합니다.';
    }
    if (_branchPreviewMode == BranchPreviewMode.merge &&
        _refs.remote.contains(comparison.compareRef)) {
      return '${comparison.compareRef}는 입력으로만 사용합니다. 실제 변경은 로컬 ${target.localBranch}에 적용됩니다.';
    }
    return '가상 결과를 로컬 ${target.localBranch}에 적용할 수 있습니다.';
  }

  /// Which rebase apply path the card has selected. Merge mode never asks.
  bool get _rebaseThenMergeSelected =>
      _branchPreviewMode == BranchPreviewMode.rebase && _rebaseApplyMerge;

  Future<void> _prepareBranchPreviewApply() async {
    final target = _branchPreviewTarget;
    if (target == null || !_branchPreviewReady || _branchApplyBusy) return;
    if (target.needsRecalculation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('기존 로컬 ${target.localBranch} 기준으로 미리보기를 다시 계산했습니다.'),
        ),
      );
      await _selectComparison(target.localBranch);
      return;
    }
    await _confirmBranchPreviewApply();
  }

  Future<void> _confirmBranchPreviewApply() async {
    final rebaseThenMerge = _rebaseThenMergeSelected;
    final comparison = _comparison;
    final target = _branchPreviewTarget;
    if (comparison == null ||
        target == null ||
        !_branchPreviewCanApply ||
        _branchApplyBusy) {
      return;
    }
    final merge = _branchPreviewMode == BranchPreviewMode.merge;
    // An apply that writes a merge commit asks for its message instead of a
    // confirmation: writing the message is the confirmation. A plain rebase
    // carries the original messages over, so there is nothing to write.
    if (merge || rebaseThenMerge) {
      final message = await showYogitAlert<String>(
        context,
        _CommitMessageDialog(
          lead: merge
              ? '${comparison.baseRef} ← ${comparison.compareRef} · '
              : '${comparison.compareRef} 재배치 → ',
          emphasis: merge
              ? '머지 커밋 1개 생성'
              : '머지 커밋 1개로 ${comparison.baseRef} 이동',
          message: renderCommitMessageTemplate(
            merge
                ? widget.mergeMessageTemplate
                : widget.rebaseMergeMessageTemplate,
            source: comparison.compareRef,
            target: comparison.baseRef,
            profile: _commitMessageProfile,
          ),
          templated:
              (merge
                      ? widget.mergeMessageTemplate
                      : widget.rebaseMergeMessageTemplate)
                  .trim()
                  .isNotEmpty,
        ),
      );
      if (message != null && mounted) {
        await _runBranchPreviewApply(comparison, message: message);
      }
      return;
    }
    // 남은 길은 'Rebase만' 하나뿐이라 문구도 그 한 가지다.
    final confirmed = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: 'Rebase를 실제로 적용할까요?',
        message:
            '로컬 ${target.localBranch} 브랜치만 변경합니다. '
            '원격 추적 브랜치와 원격 저장소는 그대로입니다.',
        body: YogitAlertBlock([
          '기준 ${comparison.baseRef}  ${comparison.baseTip}',
          '대상 ${comparison.compareRef}  ${comparison.compareTip}',
        ]),
        detail: '완료 뒤 적용 전 SHA로 되돌릴 수 있습니다.',
        confirmLabel: '적용',
        confirmKey: const Key('branch-apply-confirm'),
      ),
    );
    if (confirmed == true && mounted) {
      await _runBranchPreviewApply(comparison);
    }
  }

  Future<void> _runBranchPreviewApply(
    BranchComparisonResult comparison, {
    String? message,
  }) async {
    final rebaseThenMerge = _rebaseThenMergeSelected;
    final mode = _branchPreviewMode;
    final request = ++_branchApplySerial;
    setState(() {
      _branchApplyStatus = BranchApplyStatus.applying;
      _branchApplyError = null;
    });
    try {
      BranchApplyResult result;
      if (mode == BranchPreviewMode.merge) {
        result = await widget.repository.applyMergePreview(
          comparison: comparison,
          treeSha: (_mergePreview?.treeSha ?? comparison.merge.treeSha)!,
          message: message,
        );
      } else {
        final preview = _rebasePreview!;
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220);
        for (final rewrite in preview.rewritten) {
          if (!mounted || request != _branchApplySerial) return;
          final row = _comparisonRows.indexWhere(
            (entry) => entry.commit.sha == rewrite.rewrittenSha,
          );
          setState(() => _rebaseApplyingSha = rewrite.rewrittenSha);
          if (row >= 0) _selectedIndex.value = row;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final rowContext = _rebaseApplyRowContextKey.currentContext;
            if (!mounted || rowContext == null) return;
            unawaited(
              Scrollable.ensureVisible(
                rowContext,
                duration: duration,
                curve: Curves.easeOut,
              ),
            );
          });
          if (duration > Duration.zero) await Future<void>.delayed(duration);
        }
        result = rebaseThenMerge
            ? await widget.repository.applyRebaseThenMerge(
                comparison: comparison,
                virtualTip: preview.virtualTip!,
                message: message,
              )
            : await widget.repository.applyRebasePreview(
                comparison: comparison,
                virtualTip: preview.virtualTip!,
              );
      }
      if (!mounted || request != _branchApplySerial) return;
      final mergeSession = _mergePreviewSession;
      final rebaseSession = _rebasePreviewSession;
      setState(() {
        _branchApplyStatus = BranchApplyStatus.applied;
        _branchApplyResult = result;
        _rebaseApplyingSha = null;
        if (mode == BranchPreviewMode.merge) {
          _mergePreviewSession = null;
        } else {
          _rebasePreviewSession = null;
        }
      });
      // 카드가 짧아지면서 스크롤이 내용 밖에 남을 수 있으니 결과를 위에서 보여준다.
      _showPreviewTop();
      if (mode == BranchPreviewMode.merge && mergeSession != null) {
        unawaited(mergeSession.dispose());
      } else if (mode == BranchPreviewMode.rebase && rebaseSession != null) {
        unawaited(rebaseSession.dispose());
      }
    } catch (error) {
      if (!mounted || request != _branchApplySerial) return;
      setState(() {
        _branchApplyStatus = BranchApplyStatus.failed;
        _branchApplyError = error;
        _rebaseApplyingSha = null;
      });
    }
  }

  static String _applyModeLabel(BranchApplyMode mode) => switch (mode) {
    BranchApplyMode.merge => 'Merge',
    BranchApplyMode.rebase => 'Rebase',
    BranchApplyMode.rebaseMerge => 'Rebase 후 Merge',
  };

  String get _branchPreviewAppliedSummary {
    final result = _branchApplyResult!;
    final compareLine = result.compareBranchCreated
        ? '${result.compareBranch}: 새 브랜치 → ${result.compareAfter}'
        : '${result.compareBranch}: ${result.compareBefore} → ${result.compareAfter}';
    final compareRef = _comparison?.compareRef;
    final remote = compareRef != null && _refs.remote.contains(compareRef)
        ? '\n$compareRef: 변경 없음'
        : '';
    if (result.mode == BranchApplyMode.rebaseMerge) {
      final head = result.workingTreeUpdated
          ? '\n${result.baseBranch} 체크아웃 · 작업 트리가 병합 결과입니다'
          : result.compareWorkingTreeUpdated
          ? '\n${result.compareBranch} 체크아웃 · 작업 트리가 재배치 결과입니다'
                '\n${result.baseBranch} 브랜치는 머지 커밋을 가리키고 작업 트리는 그대로입니다'
          : '\n두 브랜치 모두 새 커밋을 가리키고 작업 트리는 그대로입니다'
                '\n브랜치를 체크아웃하면 결과가 작업 트리에 반영됩니다';
      return '$compareLine\n'
          '${result.baseBranch}: ${result.baseBefore} → ${result.baseAfter}'
          '$remote$head';
    }
    final merge = result.mode == BranchApplyMode.merge;
    final local = merge
        ? '${result.baseBranch}: ${result.baseBefore} → ${result.baseAfter}'
        : compareLine;
    final moved = merge ? result.baseBranch : result.compareBranch;
    final head = result.workingTreeUpdated
        ? '\n$moved 체크아웃 · 작업 트리가 ${merge ? 'Merge' : 'Rebase'} 결과입니다'
        : '\n$moved 브랜치는 새 커밋을 가리키고 작업 트리는 그대로입니다'
              '\n$moved 브랜치를 체크아웃하면 결과가 작업 트리에 반영됩니다';
    return '$local$remote$head';
  }

  String _branchPreviewRollbackMessage(BranchApplyResult result) {
    final compareLine = result.compareBranchCreated
        ? '적용 과정에서 만든 로컬 ${result.compareBranch}를 삭제합니다.'
        : '로컬 ${result.compareBranch}를 ${result.compareBefore}으로 되돌립니다.';
    final local = switch (result.mode) {
      BranchApplyMode.merge =>
        '로컬 ${result.baseBranch}을 ${result.baseBefore}으로 되돌립니다.',
      BranchApplyMode.rebase => compareLine,
      BranchApplyMode.rebaseMerge =>
        '로컬 ${result.baseBranch}을 ${result.baseBefore}으로 되돌립니다.\n'
            '$compareLine',
    };
    final compareRef = _comparison?.compareRef;
    final remote = compareRef != null && _refs.remote.contains(compareRef)
        ? '\n$compareRef는 변경하지 않습니다.'
        : '';
    final moved = switch (result.mode) {
      BranchApplyMode.merge => {result.baseBranch},
      BranchApplyMode.rebase => {result.compareBranch},
      BranchApplyMode.rebaseMerge => {result.baseBranch, result.compareBranch},
    };
    // 되돌리기는 그 시점의 체크아웃을 다시 확인하니, 적용 당시가 아니라 지금 상태로
    // 안내합니다. 적용은 ref만 옮겼어도 그 사이 체크아웃했다면 작업 트리까지 바뀝니다.
    final head = moved.contains(_refs.current)
        ? '\n되돌린 뒤에도 ${_refs.current}에 체크아웃된 상태로 남고 작업 트리도 이전 상태로 돌아갑니다.'
        : '\n되돌릴 때도 작업 트리는 건드리지 않습니다.';
    return '$local$remote$head\n원격 저장소는 변경하지 않습니다.';
  }

  Future<void> _confirmBranchPreviewRollback() async {
    final result = _branchApplyResult;
    if (result == null || _branchApplyStatus != BranchApplyStatus.applied) {
      return;
    }
    final confirmed = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: '${_applyModeLabel(result.mode)} 이전 시점으로 되돌릴까요?',
        body: YogitAlertBlock(
          _branchPreviewRollbackMessage(result).split('\n'),
        ),
        role: YogitAlertRole.destructive,
        confirmLabel: '되돌리기',
        confirmKey: const Key('branch-rollback-confirm'),
      ),
    );
    if (confirmed != true || !mounted) return;
    final request = ++_branchApplySerial;
    setState(() {
      _branchApplyStatus = BranchApplyStatus.reverting;
      _branchApplyError = null;
    });
    try {
      await widget.repository.restoreBranchApply(result);
      if (mounted && request == _branchApplySerial) {
        setState(() => _branchApplyStatus = BranchApplyStatus.reverted);
      }
    } catch (error) {
      if (mounted && request == _branchApplySerial) {
        setState(() {
          _branchApplyStatus = BranchApplyStatus.failed;
          _branchApplyError = error;
        });
      }
    }
  }

  Widget _branchPreviewApplyButton() => FilledButton(
    key: const Key('branch-preview-apply'),
    onPressed: _branchApplyBusy || !_branchPreviewCanPrepare
        ? null
        : () => unawaited(_prepareBranchPreviewApply()),
    style: FilledButton.styleFrom(
      foregroundColor: const Color(0xFFFFF4FF),
      backgroundColor: const Color(0xFF594576),
      side: const BorderSide(color: Color(0xFF9D79D0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    ),
    child: Text(
      _branchPreviewApplyLabel,
      textAlign: TextAlign.center,
      softWrap: true,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );

  /// Picking a landing changes nothing but the drawing: the pane's graph and the
  /// timeline's dashed path redraw from the tree we already have.
  void _selectRebaseApplyMerge(bool mergeCommit) {
    if (_rebaseApplyMerge == mergeCommit || _branchApplyBusy) return;
    final comparison = _comparison;
    final preview = _rebasePreview;
    setState(() {
      _rebaseApplyMerge = mergeCommit;
      if (comparison == null || preview == null) return;
      final graph = layoutRebasePreviewGraph(
        comparison,
        preview,
        mergeCommit: mergeCommit,
      );
      _previewGraph = graph;
      _comparisonRows = graph.rows;
      _comparisonEntries = [
        for (var index = 0; index < graph.rows.length; index++)
          (rowIndex: index, label: null, row: graph.rows[index]),
      ];
      _selectedIndex.value = 0;
    });
    _showFirstComparisonRow();
  }

  /// The two ways a clean rebase preview can land, as one choice: replay the
  /// commits, or replay them and put one merge commit over them. What is
  /// selected is what both graphs draw and what the button applies.
  List<Widget> _branchPreviewApplyOptions() {
    final comparison = _comparison;
    // 옮길 커밋이 하나도 없으면 재배치 결과가 곧 기준 브랜치라 얹을 머지 커밋이
    // 없다. 고를 것이 하나뿐이면 라디오도 내보내지 않는다.
    if (comparison == null || (_rebasePreview?.rewritten.isEmpty ?? true)) {
      return const [];
    }
    Widget option({
      required Key key,
      required bool mergeCommit,
      required String title,
      required String description,
      Key? descriptionKey,
    }) {
      final selected = _rebaseApplyMerge == mergeCommit;
      return Padding(
        padding: const EdgeInsets.only(top: 7),
        child: InkWell(
          key: key,
          onTap: _branchApplyBusy
              ? null
              : () => _selectRebaseApplyMerge(mergeCommit),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? _previewPurple.withValues(alpha: 0.08)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? const Color(0xFF9D79D0)
                    : const Color(0xFF4A4157),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    width: 14,
                    height: 14,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? _previewPurple
                            : const Color(0xFF8A8494),
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _previewPurple,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFFE8DCFF)
                              : _palette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        key: descriptionKey,
                        style: TextStyle(color: _palette.muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return [
      option(
        key: const Key('branch-preview-option-rebase'),
        mergeCommit: false,
        title: 'Rebase만',
        description:
            '${comparison.compareRef}를 ${comparison.baseRef} 위로 재배치합니다. '
            '${comparison.baseRef}은 움직이지 않습니다.',
      ),
      option(
        key: const Key('branch-preview-option-rebase-merge'),
        mergeCommit: true,
        title: 'Rebase 후 Merge 커밋으로 병합',
        descriptionKey: const Key('branch-preview-rebase-merge-caption'),
        description:
            '재배치한 커밋 위에 머지 커밋 하나를 만들어 ${comparison.baseRef}을 옮깁니다. '
            '${comparison.baseRef}이 체크아웃돼 있지 않으면 포인터만 이동합니다.',
      ),
    ];
  }

  /// What the selected landing leaves behind: the replayed commits carrying on
  /// along the base rail, or riding a dashed arc onto a merge commit.
  Widget _branchPreviewRebaseMergeGraph(BranchComparisonResult comparison) =>
      SizedBox(
        key: const Key('branch-preview-rebase-merge-graph'),
        height: 86,
        child: CustomPaint(
          painter: RebaseMergeResultPainter(
            commitCount: _rebasePreview?.rewritten.length ?? 0,
            baseLabel: comparison.baseRef,
            mergeCommit: _rebaseApplyMerge,
            railColor: _palette.border,
            mutedColor: _palette.muted,
          ),
        ),
      );

  Widget _branchPreviewApplyCard() {
    final merge = _branchPreviewMode == BranchPreviewMode.merge;
    final result = _branchApplyResult;
    final previewCommitCount = merge
        ? 1
        : _rebasePreview?.rewritten.length ?? 0;
    Widget metric(String value, String label, String key) => Expanded(
      child: Container(
        key: Key(key),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF202125),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: TextStyle(color: _palette.muted, fontSize: 10)),
          ],
        ),
      ),
    );
    return Container(
      key: const Key('branch-preview-apply-card'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _previewPurplePanel,
        border: Border.all(color: const Color(0xFF695786)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result == null
                      ? merge
                            ? 'Merge 미리보기 성공'
                            : 'Rebase 미리보기 성공'
                      : '${_applyModeLabel(result.mode)} 적용 완료',
                  style: TextStyle(
                    color: _palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_branchApplyStatus != BranchApplyStatus.idle)
                Flexible(
                  child: Text(
                    switch (_branchApplyStatus) {
                      BranchApplyStatus.applying => '커밋 적용 중',
                      BranchApplyStatus.applied => '로컬 브랜치 적용됨',
                      BranchApplyStatus.reverting => '되돌리는 중',
                      BranchApplyStatus.reverted => 'SHA 일치 확인',
                      BranchApplyStatus.failed => '작업 실패',
                      BranchApplyStatus.idle => '',
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          _branchApplyStatus == BranchApplyStatus.reverted ||
                              _branchApplyStatus == BranchApplyStatus.applied
                          ? _success
                          : _palette.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (result == null) ...[
            const SizedBox(height: 9),
            Container(
              key: const Key('branch-preview-progress'),
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF17181B),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const FractionallySizedBox(
                widthFactor: 1,
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _previewPurple,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                metric(
                  '$previewCommitCount',
                  '가상 커밋',
                  'branch-preview-virtual-count',
                ),
                const SizedBox(width: 5),
                metric(
                  '${merge ? 2 : previewCommitCount}',
                  merge ? '부모 커밋' : '원본 커밋',
                  'branch-preview-source-count',
                ),
                const SizedBox(width: 5),
                metric('0', '충돌', 'branch-preview-conflict-count'),
              ],
            ),
            if (_comparison case final comparison? when !merge)
              _branchPreviewRebaseMergeGraph(comparison),
          ],
          if (result != null) ...[
            const SizedBox(height: 8),
            Text(
              _branchPreviewAppliedSummary,
              style: TextStyle(
                color: _palette.muted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (_branchApplyError != null) ...[
            const SizedBox(height: 8),
            Text(
              _branchApplyError.toString(),
              style: TextStyle(color: _behind, fontSize: 10),
            ),
          ],
          const SizedBox(height: 10),
          if (result != null)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                key: const Key('branch-preview-rollback'),
                onPressed: _branchApplyStatus == BranchApplyStatus.applied
                    ? () => unawaited(_confirmBranchPreviewRollback())
                    : null,
                child: Text('${_applyModeLabel(result.mode)} 이전 시점으로 되돌리기'),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _branchPreviewApplyHelp,
                  style: TextStyle(color: _palette.muted, fontSize: 10),
                ),
                if (!merge) ..._branchPreviewApplyOptions(),
                const SizedBox(height: 7),
                SizedBox(
                  width: double.infinity,
                  child: _branchPreviewApplyButton(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  bool get _branchPreviewResolutionComplete =>
      !_branchPreviewDropped &&
      (_branchPreviewMode == BranchPreviewMode.merge
          ? _mergePreviewSession != null &&
                _mergePreview?.status == MergePreviewStatus.clean
          : _rebaseHadConflict &&
                _rebasePreview?.status == RebasePreviewStatus.clean);

  Widget _branchPreviewConflictStatusCard() {
    final comparison = _comparison!;
    final merge = _branchPreviewMode == BranchPreviewMode.merge;
    if (merge) {
      final count =
          _mergePreview?.conflictFiles.length ?? comparison.merge.files.length;
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: _previewConflictPanel,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '가상 Merge 커밋을 만들 수 없습니다',
                    style: TextStyle(
                      color: _palette.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '충돌 파일 $count개',
                  style: const TextStyle(
                    color: _previewConflict,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              '아래 diff에서 충돌을 해결하세요. 임시 공간은 자동으로 준비했습니다.',
              style: TextStyle(color: _palette.muted, fontSize: 10),
            ),
          ],
        ),
      );
    }
    final preview = _rebasePreview!;
    final current = preview.completed + 1;
    Widget metric(Key key, String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF202125),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              value,
              key: key,
              style: TextStyle(
                color: _palette.text,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: TextStyle(color: _palette.muted, fontSize: 10)),
          ],
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _previewPurplePanel,
        border: Border.all(color: const Color(0xFF695786)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '리베이스 진행 $current/${preview.total}',
                  style: TextStyle(
                    color: _palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${comparison.compareRef} → ${comparison.baseRef}',
                style: TextStyle(color: _palette.muted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: preview.total == 0 ? 0 : current / preview.total,
            minHeight: 5,
            borderRadius: BorderRadius.circular(4),
            color: _previewConflict,
            backgroundColor: const Color(0xFF17181B),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              metric(
                const Key('rebase-preview-applied-count'),
                '${preview.completed}',
                '적용 완료',
              ),
              const SizedBox(width: 5),
              metric(const Key('rebase-preview-conflict-count'), '1', '현재 충돌'),
              const SizedBox(width: 5),
              metric(
                const Key('rebase-preview-pending-count'),
                '${math.max(0, preview.total - current)}',
                '적용 대기',
              ),
            ],
          ),
          if (preview.currentCommit != null) ...[
            const SizedBox(height: 8),
            Text(
              '현재: ${preview.currentCommit!.subject}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _palette.text, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _branchPreviewSafeWorkspace() {
    final comparison = _comparison!;
    Widget tag(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF173741),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF9ADCE7),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Container(
      key: const Key('branch-preview-safe-workspace'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2328),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.diamond_outlined,
                color: Color(0xFF8CD8E6),
                size: 15,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '임시 공간에서 해결 중',
                  style: TextStyle(
                    color: _palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text(
                '자동 준비됨',
                style: TextStyle(
                  color: Color(0xFF8CD8E6),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '충돌 해결 과정은 임시 공간에서만 진행합니다. '
            '기준 브랜치 ${comparison.baseRef}과 대상 브랜치 '
            '${comparison.compareRef}를 직접 변경하지 않습니다.',
            style: TextStyle(color: _palette.text, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              tag('두 브랜치 변경 없음'),
              tag('현재 작업 트리 변경 없음'),
              tag('종료 시 자동 삭제'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _branchPreviewResolutionCard() => Container(
    key: const Key('branch-preview-resolution-complete'),
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: Color.lerp(_palette.raised, _renamed, 0.14),
      border: Border.all(color: _renamed.withValues(alpha: 0.48)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '충돌 해결을 마쳤습니다',
          style: TextStyle(
            color: _palette.text,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_branchPreviewMode == BranchPreviewMode.merge ? 'Merge' : 'Rebase'} 가능',
          style: const TextStyle(
            color: _success,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              key: const Key('branch-preview-drop'),
              onPressed: _branchApplyBusy
                  ? null
                  : () => unawaited(_dropResolvedBranchPreview()),
              child: const Text('Drop'),
            ),
            const SizedBox(width: 6),
            Expanded(child: _branchPreviewApplyButton()),
          ],
        ),
      ],
    ),
  );

  Widget _branchPreviewDroppedCard() => Container(
    key: const Key('branch-preview-dropped'),
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: _palette.raised,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '임시 결과를 Drop했습니다',
            style: TextStyle(
              color: _palette.text,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Text(
          '변경 없음',
          style: TextStyle(
            color: _success,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Future<void> _dropResolvedBranchPreview() async {
    if (_branchApplyBusy) return;
    final mergeSession = _mergePreviewSession;
    final rebaseSession = _rebasePreviewSession;
    setState(() {
      _mergePreviewSession = null;
      _rebasePreviewSession = null;
      _resetBranchApply();
      _dropCommitBadges();
      _dropKeepBoth();
      _branchPreviewDropped = true;
    });
    await mergeSession?.dispose();
    await rebaseSession?.dispose();
  }

  /// The horizontal padding a timeline column pads its text by, shared so the
  /// status bar can line up under a column's text instead of its edge. A cell
  /// with a branch rail down its left edge indents by two more.
  static const _columnTextInset = 9.0;
  static const _railedColumnTextInset = 11.0;

  Widget _header(String column, double width) => SizedBox(
    key: Key('$column-header'),
    width: width,
    child: Stack(
      children: [
        Positioned.fill(
          child: _headerHover(
            column,
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: column == 'time' || column == 'name'
                  ? () => _hideColumn(column)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: _columnTextInset,
                ),
                decoration: BoxDecoration(
                  color: _palette.panel,
                  border: Border(
                    bottom: BorderSide(color: _palette.border),
                    right: BorderSide(color: _palette.border),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder(
                        valueListenable: _hoveredHeader,
                        builder: (context, hovered, _) => Text(
                          timelineColumns[column]!.label.toUpperCase(),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hovered == column
                                ? _palette.text
                                : _palette.muted,
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.66,
                          ),
                        ),
                      ),
                    ),
                    if (column == 'commit' && !_showTime)
                      _restoreColumnButton('time', 'D'),
                    if (column == 'commit' && !_showName)
                      _restoreColumnButton('name', 'A'),
                  ],
                ),
              ),
            ),
          ),
        ),
        _resizer(column, width),
      ],
    ),
  );

  Widget _headerHover(String column, Widget child) {
    if (column != 'time' && column != 'name') return child;
    final label = timelineColumns[column]!.label;
    final initial = column == 'time' ? 'D' : 'A';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _hoveredHeader.value = column,
      onExit: (_) {
        if (_hoveredHeader.value == column) _hoveredHeader.value = null;
      },
      child: Tooltip(
        message: "Hide $label. Click '$initial' to restore",
        waitDuration: Duration.zero,
        child: child,
      ),
    );
  }

  Widget _restoreColumnButton(String column, String label) => Tooltip(
    message: 'Show ${timelineColumns[column]!.label} column',
    waitDuration: _tooltipDelay,
    child: SizedBox(
      width: 22,
      height: 22,
      child: TextButton(
        key: Key('show-$column-column'),
        onPressed: () {
          setState(() {
            if (column == 'time') {
              _showTime = true;
            } else {
              _showName = true;
            }
          });
          _saveColumnWidths();
        },
        style: TextButton.styleFrom(
          foregroundColor: _palette.muted,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    ),
  );

  Widget _resizer(String column, double width) => Positioned(
    right: 0,
    top: 0,
    bottom: 0,
    width: 8,
    child: Focus(
      key: Key('$column-resizer-focus'),
      focusNode: _resizerFocus[column],
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        final keyboard = HardwareKeyboard.instance;
        final key = normalizeNavigationKey(
          event.logicalKey,
          hasModifier:
              keyboard.isMetaPressed ||
              keyboard.isAltPressed ||
              keyboard.isShiftPressed ||
              keyboard.isControlPressed,
        );
        final delta = switch (key) {
          LogicalKeyboardKey.arrowLeft => -8.0,
          LogicalKeyboardKey.arrowRight => 8.0,
          _ => null,
        };
        if (delta == null) return KeyEventResult.ignored;
        _resize(column, width + delta);
        _saveColumnWidths();
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: Key('$column-resizer'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _startResize(column),
          onHorizontalDragUpdate: (details) =>
              _resize(column, width + details.delta.dx),
          onHorizontalDragEnd: (_) => _finishResize(),
          onHorizontalDragCancel: _finishResize,
        ),
      ),
    ),
  );

  void _startResize(String column) {
    _resizeStartWidths = {
      if (column == 'commit' || column == 'time') 'time': _w('time'),
      if (column == 'commit' || column == 'name') 'name': _w('name'),
    };
  }

  void _finishResize() {
    _saveColumnWidths();
    _resizeStartWidths = const {};
  }

  /// Resizes from the width on screen, so dragging a flexing title column picks
  /// up where it is rather than jumping to a stored value.
  void _resize(String column, double next) {
    if (column == 'commit') {
      _resizeCommit(next);
      return;
    }
    final spec = timelineColumns[column]!;
    if ((column == 'time' || column == 'name') &&
        next < spec.min &&
        _w(column) <= spec.min) {
      _hideColumn(column, restoreWidth: _resizeStartWidths[column]);
      return;
    }
    final clamped = next.clamp(spec.min, spec.max);
    setState(() {
      if (column == 'graph') {
        _graphWidth = clamped;
      } else {
        _widths[column] = clamped;
      }
    });
  }

  void _resizeCommit(double next) {
    final spec = timelineColumns['commit']!;
    if (next <= _commitAvailableWidth) {
      setState(() {
        _commitWidth = next.clamp(
          spec.min,
          math.max(spec.max, _commitAvailableWidth),
        );
      });
      return;
    }

    var overflow = next - _commitAvailableWidth;
    var commitWidth = _commitAvailableWidth;
    var hidColumn = false;
    setState(() {
      void consume(String column) {
        if (overflow <= 0 || !_columnVisible(column)) return;
        final columnSpec = timelineColumns[column]!;
        final current = _w(column);
        final shrink = math.min(overflow, current - columnSpec.min);
        _widths[column] = current - shrink;
        commitWidth += shrink;
        overflow -= shrink;
        if (overflow <= 0 || _w(column) > columnSpec.min) return;

        final hiddenWidth = _w(column);
        commitWidth += hiddenWidth;
        overflow = math.max(0, overflow - hiddenWidth);
        _widths[column] = _resizeStartWidths[column] ?? hiddenWidth;
        if (column == 'time') {
          _showTime = false;
        } else {
          _showName = false;
        }
        hidColumn = true;
      }

      consume('time');
      consume('name');
      _commitWidth = commitWidth;
    });
    if (hidColumn) _saveColumnWidths();
  }

  void _hideColumn(String column, {double? restoreWidth}) {
    setState(() {
      if (restoreWidth != null) _widths[column] = restoreWidth;
      if (column == 'time') {
        _showTime = false;
      } else {
        _showName = false;
      }
    });
    _saveColumnWidths();
  }

  void _saveColumnWidths() => widget.onColumnWidthsChanged?.call(
    TimelineColumnWidths(
      sidebar: _sidebarWidth,
      refs: _w('refs'),
      graph: _graphWidth,
      hash: _w('hash'),
      commit: _commitWidth,
      time: _w('time'),
      name: _w('name'),
      showTime: _showTime,
      showName: _showName,
    ),
  );

  /// The chips a row shows: the `for-each-ref` tips landing on this commit,
  /// unioned with the log decorations so remotes and detached HEAD still show.
  List<GitRef> _rowRefs(GitCommit commit) {
    if (_comparison case BranchComparisonResult comparison) {
      final previewKind = _previewGraph?.kinds[commit.sha];
      if (previewKind == PreviewGraphNodeKind.virtualMerge) {
        final conflict = _effectiveMergeStatus == MergeConflictStatus.conflicts;
        return [
          GitRef(
            name: conflict ? '! 병합 충돌' : '${comparison.baseRef} · 가상',
            isHead: !conflict,
          ),
        ];
      }
      if (previewKind == PreviewGraphNodeKind.virtualRebase) {
        return [
          GitRef(
            name: '${comparison.compareRef} · 가상',
            isHead: commit.sha == _rebasePreview?.virtualTip,
          ),
        ];
      }
      // 머지 커밋을 얹으면 기준 브랜치는 이 가상 노드로 옮겨간다.
      if (previewKind == PreviewGraphNodeKind.virtualRebaseMerge) {
        return [GitRef(name: comparison.baseRef, isHead: true)];
      }
      if (previewKind == PreviewGraphNodeKind.conflictTarget) {
        return const [GitRef(name: '가상 rebase 위치')];
      }
      final side = comparison.commits
          .firstWhere((entry) => entry.commit.sha == commit.sha)
          .side;
      var compareLabel = '${comparison.compareRef} · 원본';
      if (side == BranchCommitSide.compareOnly &&
          _branchPreviewMode == BranchPreviewMode.rebase) {
        final preview = _rebasePreview;
        if (preview?.status == RebasePreviewStatus.clean) {
          compareLabel = '${comparison.compareRef} · 원본';
        } else if (preview?.status == RebasePreviewStatus.conflict) {
          compareLabel = commit.sha == preview?.currentCommit?.sha
              ? '${comparison.compareRef} · 현재 충돌'
              : preview!.rewritten.any(
                  (rewrite) => rewrite.original.sha == commit.sha,
                )
              ? '${comparison.compareRef} · 적용됨'
              : '${comparison.compareRef} · 대기';
        }
      }
      return [
        GitRef(
          name: switch (side) {
            BranchCommitSide.baseOnly =>
              _branchPreviewMode == BranchPreviewMode.rebase &&
                      _rebasePreview?.status == RebasePreviewStatus.conflict &&
                      commit.sha == comparison.baseTip
                  ? '${comparison.baseRef} · HEAD'
                  : comparison.baseRef,
            BranchCommitSide.compareOnly => compareLabel,
            BranchCommitSide.commonBoundary => '공통',
          },
          // 가상 머지 노드가 있으면 기준 브랜치 칩은 그 줄로 올라가고 실제 tip은
          // 표시 없는 칩만 남는다.
          isHead: side == BranchCommitSide.baseOnly && !_rebaseApplyMerge,
        ),
      ];
    }
    return timelineRefsForCommit(commit, _refs);
  }

  /// Only the rows whose selected or hovered state flipped rebuild.
  Widget _row(int index, double commitWidth, double graphWidth) =>
      _RowStateScope(
        index: index,
        selectedIndex: _selectedIndex,
        hoverIndex: _hoverIndex,
        builder: (selected, hovered) =>
            _rowContent(index, commitWidth, graphWidth, selected, hovered),
      );

  /// The date heading: no node, no hairline, just the rails running through and
  /// a boxed label where the hash column starts.
  Widget _dateRow(int index, TimelineEntry entry, double graphWidth) =>
      _RowStateScope(
        index: index,
        selectedIndex: _selectedIndex,
        hoverIndex: _hoverIndex,
        builder: (selected, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _select(index),
          child: ColoredBox(
            color: selected ? _timelineSelectionColor : _palette.background,
            child: _dateRowContent(index, entry, graphWidth),
          ),
        ),
      );

  Widget _dateRowContent(
    int index,
    TimelineEntry entry,
    double graphWidth,
  ) => Row(
    key: Key('date-row-$index'),
    children: [
      SizedBox(width: _w('refs')),
      _graphCell(
        Key('date-painter-$index'),
        _painterFor(entry, index, graphWidth, false, false),
        graphWidth,
      ),
      Padding(
        // 5px left of the hash text (whose 2px rule shifts it), so the box reads
        // as heading the row rather than sitting in the hash column, and pushed
        // down far enough to hang under the group above without clipping.
        padding: const EdgeInsets.only(left: 6, right: 9, top: 4),
        child: Container(
          key: Key('date-box-$index'),
          // Tight enough that the box plus its downward shift clears the row.
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: _dateGroup),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            entry.label!,
            style: const TextStyle(
              color: _dateGroup,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ],
  );

  /// The graph cell both row kinds share: rails and sweeps below, the node's
  /// avatar above. A childless CustomPaint has no size of its own, so the cell
  /// pins the row height — without it a date heading paints nothing at all.
  Widget _graphCell(
    Key painterKey,
    CommitGraphPainter painter,
    double graphWidth, {
    Key? cellKey,
    Widget? overlay,
    Widget? node,
  }) => SizedBox(
    key: cellKey,
    width: graphWidth,
    height: TimelineScreen.rowHeight,
    child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Transition curves sweep a full row, so the cell clips the halves that
        // belong to the neighbouring rows.
        Positioned.fill(
          child: ClipRect(
            child: RepaintBoundary(
              child: CustomPaint(key: painterKey, painter: painter),
            ),
          ),
        ),
        ?overlay,
        // Last, so a node always covers the rails behind it.
        ?node,
      ],
    ),
  );

  /// One painter for both row kinds: a heading passes through, drawing the rails
  /// and the sweeps arriving from the row above but no node of its own.
  CommitGraphPainter _painterFor(
    TimelineEntry entry,
    int index,
    double graphWidth,
    bool selected,
    bool refConnector, {
    Color? committerColor,
    Color? outgoingRailColor,
  }) => CommitGraphPainter(
    row: entry.row,
    previous: index > 0 ? _entries[index - 1].row : null,
    selected: selected,
    committerColor:
        committerColor ?? AvatarService.branchColor(entry.row.branch),
    committersBySha: _committersBySha,
    laneSpacing: CommitGraphPainter.spacingFor(
      graphWidth,
      _graphLayoutDepth,
      maxLaneSpacing: _graphLayoutSpacing,
    ),
    compact: graphWidth <= CommitGraphPainter.compactWidth,
    refConnector: refConnector,
    passThrough: entry.rowIndex < 0,
    dashedLanes: _previewGraph?.dashedLanes[index] ?? const {},
    previousDashedLanes: index > 0
        ? _previewGraph?.dashedLanes[index - 1] ?? const {}
        : const {},
    previewRailColor: _comparison == null
        ? null
        : _branchPreviewMode == BranchPreviewMode.merge &&
              _branchPreviewHasConflict
        ? _previewConflict
        : _previewPurple,
    previewMergeArrow:
        _previewGraph?.kinds[entry.row.commit.sha] ==
        PreviewGraphNodeKind.virtualMerge,
    outgoingRailColor: outgoingRailColor,
    backgroundColor: _palette.background,
    selectedRowColor: _timelineSelectionColor,
  );

  Widget _rowContent(
    int index,
    double commitWidth,
    double graphWidth,
    bool selected,
    bool hovered,
  ) {
    final entry = _entries[index];
    final row = entry.row;
    final commit = row.commit;
    final commonBoundary =
        _comparison?.commits.any(
          (entry) =>
              entry.commit.sha == commit.sha &&
              entry.side == BranchCommitSide.commonBoundary,
        ) ??
        false;
    // One branch line, one color: rails, chips, node ring and hash border.
    final branchColor = commonBoundary
        ? _palette.muted
        : AvatarService.branchColor(row.branch);
    final previewKind = _previewGraph?.kinds[commit.sha];
    final virtualMerge = previewKind == PreviewGraphNodeKind.virtualMerge;
    final virtualRebaseMerge =
        previewKind == PreviewGraphNodeKind.virtualRebaseMerge;
    final rebaseConflict =
        _rebasePreview?.status == RebasePreviewStatus.conflict &&
        _rebasePreview?.currentCommit?.sha == commit.sha;
    final rebaseApplying = _rebaseApplyingSha == commit.sha;
    final virtualPreview =
        virtualMerge ||
        virtualRebaseMerge ||
        previewKind == PreviewGraphNodeKind.virtualRebase;
    final mergeConflict =
        virtualMerge && _effectiveMergeStatus == MergeConflictStatus.conflicts;
    final synthetic =
        commit.isWorkingTree || virtualMerge || virtualRebaseMerge;
    final previewColor = previewKind == PreviewGraphNodeKind.conflictTarget
        ? _previewPurple
        : virtualPreview
        ? mergeConflict
              ? _previewConflict
              : _previewPurple
        : branchColor;
    final rebasePreview = _rebasePreview;
    final originalIndex =
        rebasePreview?.rewritten.indexWhere(
          (rewrite) => rewrite.original.sha == commit.sha,
        ) ??
        -1;
    final compareOnly = _isCompareOnly(commit.sha);
    final resolvedRebaseConflict =
        rebasePreview?.status == RebasePreviewStatus.conflict &&
        originalIndex >= 0 &&
        !rebaseConflict;
    // 재배치가 건너뛸 커밋은 대기 중이 아니라서 대기 색도 받지 않는다.
    final pendingRebaseConflict =
        rebasePreview?.status == RebasePreviewStatus.conflict &&
        compareOnly &&
        originalIndex < 0 &&
        !rebaseConflict &&
        !_duplicateCommits.contains(commit.sha);
    final rowAccentColor = rebaseConflict
        ? _previewConflict
        : resolvedRebaseConflict
        ? _previewPurple
        : pendingRebaseConflict
        ? _behind
        : previewColor;
    final progress = _commitProgressLabel(commit);
    final badges = _commitBadges(commit);
    final refs = _rowRefs(commit);
    Widget refsCell() {
      final lineTip = selected && refs.isEmpty
          ? _deletedBranchTipSha(row.branch)
          : null;
      final cell = _refsCell(
        entry.rowIndex,
        commit,
        refs,
        rowAccentColor,
        row.branch,
        showConnector: _comparison == null,
        deletedBranchName: lineTip == null
            ? null
            : _deletedBranchNames[lineTip],
        deletedBranchLoading:
            lineTip != null && _resolvingDeletedBranchTips.contains(lineTip),
      );
      if (mergeConflict) {
        return KeyedSubtree(
          key: const Key('virtual-merge-conflict-chip'),
          child: cell,
        );
      }
      if (previewKind == PreviewGraphNodeKind.virtualMerge) {
        return KeyedSubtree(
          key: const Key('virtual-preview-chip'),
          child: cell,
        );
      }
      if (previewKind == PreviewGraphNodeKind.virtualRebase) {
        return KeyedSubtree(
          key: Key('virtual-rebase-chip-${commit.sha}'),
          child: cell,
        );
      }
      if (virtualRebaseMerge) {
        return KeyedSubtree(
          key: const Key('virtual-rebase-merge-chip'),
          child: cell,
        );
      }
      return cell;
    }

    final merge = commit.parents.length >= 2 && !commit.isWorkingTree;
    // Shrink stages: full spacing while the cell fits every lane, compressed
    // spacing below that, one collapsed lane at the narrowest.
    final painter = _painterFor(
      entry,
      index,
      graphWidth,
      selected && !virtualPreview,
      refs.isNotEmpty && _comparison == null,
      committerColor: previewColor,
      outgoingRailColor: commonBoundary ? _palette.muted : null,
    );
    // Nodes keep their size at every width; only the overhang clips.
    const avatarSize = CommitGraphPainter.avatarDiameter;
    // The author/committer stack reaches 45% further right than one disc, so it
    // only shows while that stays clear of the next lane's rail.
    final stacked =
        avatarSize * 0.95 <= painter.laneSpacing - CommitGraphPainter.railWidth;
    final mappings = _previewGraph?.mappings ?? const <RebaseGraphMapping>[];
    final content = MouseRegion(
      onEnter: (_) => _hoverIndex.value = index,
      onExit: (_) {
        if (_hoverIndex.value == index) _hoverIndex.value = -1;
      },
      child: GestureDetector(
        key: rebaseConflict
            ? const Key('rebase-conflict-current-row')
            : rebaseApplying
            ? const Key('rebase-apply-current-row')
            : selected
            ? Key('selected-row-${commit.sha}')
            : null,
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(index),
        onSecondaryTapDown: (details) =>
            unawaited(_showCommitMenu(commit, details.globalPosition)),
        child: Container(
          key: mergeConflict
              ? const Key('virtual-merge-conflict-row')
              : previewKind == PreviewGraphNodeKind.virtualMerge
              ? const Key('virtual-preview-row')
              : virtualRebaseMerge
              ? const Key('virtual-rebase-merge-row')
              : previewKind == PreviewGraphNodeKind.virtualRebase
              ? Key('virtual-rebase-row-${commit.sha}')
              : null,
          color: mergeConflict
              ? _previewConflictPanel
              : rebaseConflict
              ? const Color(0xFF8F2F3A)
              : resolvedRebaseConflict
              ? _previewPurplePanel
              : rebaseApplying
              ? const Color(0xFF4D376D)
              : virtualPreview
              ? _previewPurplePanel
              : selected
              ? _palette.background
              : hovered
              ? _palette.neutralChip.withValues(alpha: 0.48)
              : _palette.background,
          child: Stack(
            children: [
              if (virtualPreview)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: ColoredBox(color: previewColor),
                ),
              if (selected && !rebaseConflict)
                Positioned(
                  left: _w('refs') + painter.laneX(row.lane),
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: ColoredBox(
                    key: Key('selection-band-${commit.sha}'),
                    color: _timelineSelectionColor,
                  ),
                ),
              Row(
                children: [
                  selected
                      ? ValueListenableBuilder<int>(
                          valueListenable: _deletedBranchRevision,
                          builder: (_, _, _) => refsCell(),
                        )
                      : refsCell(),
                  _graphCell(
                    Key('graph-painter-${entry.rowIndex}'),
                    painter,
                    graphWidth,
                    cellKey: Key('graph-cell-${entry.rowIndex}'),
                    overlay: mappings.isEmpty
                        ? null
                        : Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: RebaseMappingPainter(
                                  rows: _comparisonRows,
                                  entries: _entries,
                                  selectedIndex: _selectedIndex,
                                  mappings: mappings,
                                  rowIndex: index,
                                  laneSpacing: painter.laneSpacing,
                                  compact: painter.compact,
                                ),
                              ),
                            ),
                          ),
                    node:
                        commit.isWorkingTree ||
                            (merge &&
                                previewKind !=
                                    PreviewGraphNodeKind.virtualMerge &&
                                !virtualRebaseMerge)
                        ? null
                        : _graphNode(
                            commit: commit,
                            kind: previewKind,
                            painter: painter,
                            row: row,
                            size: avatarSize,
                            stacked: stacked,
                            branchColor: previewColor,
                            conflict: mergeConflict,
                          ),
                  ),
                  _cell(
                    _w('hash'),
                    Text(
                      commit.isWorkingTree ? '·······' : commit.shortSha,
                      style: TextStyle(
                        color: selected ? _palette.text : _hash,
                        fontSize: 12,
                        fontFamily: technicalFontFamily,
                        fontFamilyFallback: technicalFontFallback,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    leftBorder: previewColor,
                    ruleKey: Key('hash-rule-${entry.rowIndex}'),
                  ),
                  _cell(
                    commitWidth,
                    Row(
                      children: [
                        if (progress != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: progress.color.withValues(
                                alpha: virtualRebaseMerge ? 0.28 : 0.2,
                              ),
                              border: virtualRebaseMerge
                                  ? Border.all(color: const Color(0xFF9D79D0))
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              progress.text,
                              style: TextStyle(
                                color: progress.textColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            commit.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _palette.text,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        // 배지 묶음도 제목과 같은 flex 몫을 받는다 — 열이 좁아지면
                        // 배지가 줄어들 뿐, 행이 넘치는 일은 구조적으로 없다.
                        if (badges.isNotEmpty)
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                for (final badge in badges)
                                  Flexible(
                                    child: _tooltip(
                                      badge.tooltip,
                                      _rowBadge(
                                        key: Key(
                                          'commit-${badge.id}-'
                                          '${commit.sha}',
                                        ),
                                        text: badge.text,
                                        color: badge.color,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_showTime)
                    _cell(
                      _w('time'),
                      // The cell reads socially; the tooltip gives the exact moment.
                      _tooltip(
                        synthetic
                            ? null
                            : exactCommitTime(commit.committerTimestamp),
                        Text(
                          commit.isWorkingTree
                              ? 'working tree'
                              : virtualMerge || virtualRebaseMerge
                              ? '—'
                              : _socialTime(commit.committerTimestamp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? _palette.text : _palette.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  if (_showName)
                    _cell(
                      _w('name'),
                      synthetic
                          ? Text(
                              '—',
                              style: TextStyle(
                                color: _palette.muted,
                                fontSize: 12,
                              ),
                            )
                          : Row(
                              children: [
                                if (_w('name') >= 47) ...[
                                  CommitAvatarStack(
                                    commit: commit,
                                    avatarService: widget.avatarService,
                                    showRemoteAvatars: widget.showRemoteAvatars,
                                    discColor: branchColor,
                                    stacked: _w('name') >= 57,
                                  ),
                                  const SizedBox(width: 7),
                                ],
                                Expanded(
                                  child: Text(
                                    commit.author.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: selected
                                          ? _palette.text
                                          : Color.lerp(
                                              _palette.text,
                                              _main,
                                              0.12,
                                            ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final focusableContent = rebaseConflict
        ? KeyedSubtree(key: _rebaseConflictRowContextKey, child: content)
        : rebaseApplying
        ? KeyedSubtree(key: _rebaseApplyRowContextKey, child: content)
        : content;
    if (!_canCherryPick(commit)) return focusableContent;
    return Draggable<GitCommit>(
      data: commit,
      affinity: Axis.horizontal,
      feedback: Material(
        color: _palette.raised,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(commit.subject, style: TextStyle(color: _palette.text)),
        ),
      ),
      child: focusableContent,
    );
  }

  /// A commit that does not exist yet — the merge preview's virtual commit, the
  /// virtual merge, a rewritten rebase copy. Same disc, same ring color and
  /// width as before; only the ring is dashed.
  Widget _virtualNode({
    required Key key,
    required double size,
    required Color fill,
    required Color ring,
    required double ringWidth,
    required Widget child,
  }) => CustomPaint(
    key: key,
    painter: DashedRingNodePainter(
      fill: fill,
      ring: ring,
      ringWidth: ringWidth,
    ),
    child: SizedBox.square(
      dimension: size,
      child: Center(child: child),
    ),
  );

  Widget _graphNode({
    required GitCommit commit,
    required PreviewGraphNodeKind? kind,
    required CommitGraphPainter painter,
    required GraphRow row,
    required double size,
    required bool stacked,
    required Color branchColor,
    bool conflict = false,
  }) {
    Color? mappingColor;
    for (final mapping in _previewGraph?.mappings ?? const []) {
      if (mapping.originalSha == commit.sha ||
          mapping.rewrittenSha == commit.sha) {
        mappingColor = mapping.color;
        break;
      }
    }
    final child = kind == PreviewGraphNodeKind.virtualMerge && conflict
        ? _virtualNode(
            key: const Key('virtual-merge-conflict-node'),
            size: size,
            fill: _previewConflict,
            ring: const Color(0xFFFFB8BD),
            ringWidth: 2,
            child: const Text(
              '!',
              style: TextStyle(
                color: Color(0xFF4D1118),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          )
        : kind == PreviewGraphNodeKind.virtualMerge
        ? _virtualNode(
            key: const Key('virtual-merge-node'),
            size: size,
            fill: _previewPurple,
            ring: _palette.background,
            ringWidth: 2,
            child: const Text(
              'VM',
              style: TextStyle(
                color: Colors.black,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : kind == PreviewGraphNodeKind.virtualRebaseMerge
        ? _virtualNode(
            key: const Key('virtual-rebase-merge-node'),
            size: size,
            fill: _previewPurplePanel,
            ring: _previewPurple,
            ringWidth: 2,
            child: const Text(
              'VM',
              style: TextStyle(
                color: _previewPurple,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : kind == PreviewGraphNodeKind.virtualRebase
        ? _virtualNode(
            key: Key('virtual-rebase-node-${commit.sha}'),
            size: size,
            fill: const Color(0xFF8D6BB8),
            ring: mappingColor ?? const Color(0xFFB78BEF),
            ringWidth: _rebaseMappingAvatarBorderWidth,
            child: const Text(
              'VR',
              style: TextStyle(
                color: Colors.black,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : kind == PreviewGraphNodeKind.conflictTarget
        ? Container(
            key: const Key('rebase-conflict-target-node'),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _palette.background,
              border: Border.all(color: _previewPurple, width: 1),
            ),
          )
        : mappingColor == null
        ? CommitAvatarStack(
            commit: commit,
            avatarService: widget.avatarService,
            showRemoteAvatars: widget.showRemoteAvatars,
            size: size,
            stacked: stacked,
            discColor: branchColor,
          )
        : Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: mappingColor,
                width: _rebaseMappingAvatarBorderWidth,
              ),
            ),
            child: CommitAvatarStack(
              commit: commit,
              avatarService: widget.avatarService,
              showRemoteAvatars: widget.showRemoteAvatars,
              size: size - _rebaseMappingAvatarBorderWidth * 2,
              stacked: stacked,
              discColor: branchColor,
            ),
          );
    return Positioned(
      left: painter.laneX(row.lane) - size / 2,
      top: (TimelineScreen.rowHeight - size) / 2,
      child: child,
    );
  }

  /// One chip per row: the first ref, plus a `+N` badge when the row carries
  /// more. The full list belongs to the floating modal the selected row shows.
  /// No bottom hairline here — the rules start at the hash column.
  Widget _refsCell(
    int index,
    GitCommit commit,
    List<GitRef> refs,
    Color color,
    int branch, {
    bool showConnector = true,
    String? deletedBranchName,
    bool deletedBranchLoading = false,
  }) => SizedBox(
    key: Key('refs-cell-$index'),
    width: _w('refs'),
    child: refs.isEmpty
        ? deletedBranchLoading
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '브랜치 이름 찾는 중…',
                      key: Key('deleted-branch-loading-${commit.sha}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _palette.muted, fontSize: 11),
                    ),
                  ),
                )
              : deletedBranchName == null
              ? null
              : _deletedBranchLabel(commit, deletedBranchName, color)
        : LayoutBuilder(
            builder: (context, constraints) {
              // Chips split the cell evenly, each keeping at least 40px, and
              // whatever no longer fits simply does not show.
              const inset = 14.0;
              final width = constraints.maxWidth - inset * 2;
              final slots = math.max(1, (width / _minChipWidth).floor());
              final shown = refs.take(slots).toList();
              final slot = width / shown.length;
              return Stack(
                children: [
                  for (var index = 0; index < shown.length; index++)
                    Positioned(
                      left: inset + index * slot,
                      top: (TimelineScreen.rowHeight - 24) / 2,
                      width: slot,
                      height: 24,
                      child: _refChip(
                        commit,
                        shown[index],
                        color,
                        paletteIndex: _comparison == null && index == 0
                            ? _branchPaletteIndexes[branch]
                            : null,
                      ),
                    ),
                  if (showConnector)
                    Positioned(
                      key: Key('ref-chip-connector-${commit.sha}'),
                      left: constraints.maxWidth - inset,
                      right: 0,
                      top: (TimelineScreen.rowHeight - 1) / 2,
                      height: 1,
                      child: ColoredBox(color: color),
                    ),
                ],
              );
            },
          ),
  );

  Widget _deletedBranchLabel(GitCommit commit, String name, Color color) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Container(
              key: Key('deleted-branch-badge-${commit.sha}'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '삭제됨',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                name,
                key: Key('deleted-branch-name-${commit.sha}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11),
              ),
            ),
          ],
        ),
      );

  Widget _refChip(
    GitCommit commit,
    GitRef ref,
    Color color, {
    int? paletteIndex,
  }) {
    final colors = paletteIndex == null
        ? refPaletteColorsForName(
            ref.name,
            widget.refPalette,
            refPaletteAssignments: widget.refPaletteAssignments,
          )
        : refPaletteColorsAt(paletteIndex, widget.refPalette);
    final background = _comparison == null
        ? colors.base.withValues(alpha: .18)
        : color.withValues(alpha: .14);
    final border = _comparison == null
        ? colors.text.withValues(alpha: .30)
        : color.withValues(alpha: .55);
    final foreground = _comparison == null ? colors.text : color;
    return Container(
      key: Key('ref-chip-${commit.sha}-${ref.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          _refGlyph(ref, foreground, false),
          _refName(ref, foreground, false),
        ],
      ),
    );
  }

  Widget _refGlyph(GitRef ref, Color color, bool selected) =>
      ref.isHead || ref.isTag
      ? Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Text(
            ref.isHead ? '✓' : '◇',
            style: TextStyle(
              color: selected ? _palette.text : color,
              fontSize: 10,
            ),
          ),
        )
      : const SizedBox.shrink();

  static TextStyle _refNameStyle(Color color) =>
      TextStyle(color: color, fontSize: 11);

  /// Chips ellipsize inside their share of the cell; the modal, which sizes to
  /// its longest name, shows every name whole.
  Widget _refName(
    GitRef ref,
    Color color,
    bool selected, {
    bool ellipsis = true,
  }) {
    final text = Text(
      ref.name,
      maxLines: 1,
      softWrap: false,
      overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.visible,
      style: _refNameStyle(selected ? _palette.text : color),
    );
    return ellipsis ? Expanded(child: text) : text;
  }

  /// The width the timeline viewport has, for clamping the ref modal.
  double get _timelineViewportWidth {
    final box = _timelineKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.width : 320;
  }

  /// Wide enough for the longest ref in full, capped by the timeline viewport.
  double _refsModalWidth(List<GitRef> refs) {
    var longest = 0.0;
    for (final ref in refs) {
      final painter = TextPainter(
        text: TextSpan(text: ref.name, style: _refNameStyle(_palette.text)),
        textDirection: TextDirection.ltr,
      )..layout();
      final glyph = ref.isHead || ref.isTag ? 16.0 : 0.0;
      longest = math.max(longest, painter.width + glyph);
    }
    // accent bar, its gap, the copy button with its gaps, and the box padding.
    return math.min(
      longest + 2 + 7 + 6 + 16 + 4 + 16,
      _timelineViewportWidth - 16,
    );
  }

  /// The floating list of every ref on the selected row. It sits above the row
  /// when the cursor arrived heading down and below it heading up — a click has
  /// no direction, so it takes whichever side has more room — stays inside the
  /// viewport, and vanishes with the selection or when the row scrolls away.
  Widget _refsModal(double viewportHeight) {
    final index = _selectedIndex.value;
    if (index >= _entries.length || _entries[index].rowIndex < 0) {
      return const SizedBox.shrink();
    }
    final row = _entries[index].row;
    final refs = _rowRefs(row.commit);
    final offset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final rowTop = index * TimelineScreen.rowHeight - offset;
    final rowBottom = rowTop + TimelineScreen.rowHeight;
    if (refs.length < 2 || rowBottom <= 0 || rowTop >= viewportHeight) {
      return const SizedBox.shrink();
    }
    final color = AvatarService.branchColor(row.branch);
    final height = refs.length * 24.0 + 8;
    final width = _refsModalWidth(refs);
    final above = _arrivedGoingDown ?? rowTop > viewportHeight - rowBottom;
    final double top = (above ? rowTop - height - 4 : rowBottom + 4).clamp(
      0.0,
      math.max(0.0, viewportHeight - height),
    );
    return Stack(
      children: [
        Positioned(
          key: const Key('refs-modal'),
          left: 8,
          top: top,
          width: width,
          // Only the box takes pointers; the rest of the overlay stays through.
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: _palette.raised,
              border: Border.all(color: _palette.border),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var refIndex = 0; refIndex < refs.length; refIndex++)
                  Builder(
                    builder: (context) {
                      final ref = refs[refIndex];
                      final refColor = _comparison == null
                          ? refPaletteColorsAt(
                              refIndex == 0
                                  ? _branchPaletteIndexes[row.branch] ?? 0
                                  : refPaletteIndexForName(
                                      ref.name,
                                      widget.refPaletteAssignments,
                                    ),
                              widget.refPalette,
                            ).text
                          : color;
                      return SizedBox(
                        height: 24,
                        child: Row(
                          children: [
                            // A straight 2px bar, no rounding.
                            Container(
                              key: Key('modal-accent-${ref.name}'),
                              width: 2,
                              height: 20,
                              color: refColor,
                            ),
                            const SizedBox(width: 7),
                            _refGlyph(ref, refColor, false),
                            _refName(ref, refColor, false, ellipsis: false),
                            const SizedBox(width: 6),
                            _CopyButton(text: ref.name, color: refColor),
                            const SizedBox(width: 4),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Wraps [child] only when there is something to say about it.
  Widget _tooltip(String? message, Widget child) => message == null
      ? child
      : Tooltip(message: message, waitDuration: _tooltipDelay, child: child);

  bool _isCompareOnly(String sha) =>
      _comparison?.commits.any(
        (entry) =>
            entry.commit.sha == sha &&
            entry.side == BranchCommitSide.compareOnly,
      ) ??
      false;

  /// 커밋 하나가 Merge/Rebase 미리보기에서 받는 진행 라벨. 행과 미리보기 판이 같은
  /// 함수를 불러 문구와 색이 두 자리에서 갈라질 수 없게 한다.
  ({String text, Color color, Color textColor})? _commitProgressLabel(
    GitCommit commit,
  ) {
    final kind = _previewGraph?.kinds[commit.sha];
    if (kind == PreviewGraphNodeKind.virtualMerge) {
      return _effectiveMergeStatus == MergeConflictStatus.conflicts
          ? (text: '충돌', color: _previewConflict, textColor: _previewConflict)
          : (text: '가상', color: _previewPurple, textColor: _previewPurple);
    }
    if (kind == PreviewGraphNodeKind.virtualRebaseMerge) {
      return (
        text: '가상 머지',
        color: _previewPurple,
        textColor: const Color(0xFFE4D4FF),
      );
    }
    final preview = _rebasePreview;
    if (preview == null) return null;
    final rewrittenIndex = preview.rewritten.indexWhere(
      (rewrite) => rewrite.rewrittenSha == commit.sha,
    );
    if (rewrittenIndex >= 0) {
      return (
        text: '재작성 ${rewrittenIndex + 1}/${preview.total}',
        color: _previewPurple,
        textColor: _previewPurple,
      );
    }
    if (preview.status != RebasePreviewStatus.conflict) return null;
    if (preview.currentCommit?.sha == commit.sha) {
      return (
        text: '충돌 해결 중',
        color: _previewConflict,
        textColor: const Color(0xFFFFC4C8),
      );
    }
    if (preview.rewritten.any(
      (rewrite) => rewrite.original.sha == commit.sha,
    )) {
      return (text: '해결 완료', color: _previewPurple, textColor: _previewPurple);
    }
    if (!_isCompareOnly(commit.sha)) return null;
    // 재배치는 patch-id가 이미 base에 있는 커밋을 재생하지 않는다. 미리보기가 그
    // 커밋을 지나가도 재작성본이 생기지 않으니 남은 '다음' 대신 건너뛴 사실을 적는다.
    return _duplicateCommits.contains(commit.sha)
        ? (
            text: '건너뜀 · 이미 반영',
            color: _duplicateBadge,
            textColor: _duplicateBadge,
          )
        : (text: '다음', color: _behind, textColor: _behind);
  }

  /// 커밋 하나가 근거로 얻은 배지들. 행 오른쪽과 미리보기 판이 함께 쓴다.
  List<({String id, String text, Color color, String tooltip})> _commitBadges(
    GitCommit commit,
  ) {
    final baseRef = _comparison?.baseRef;
    if (baseRef == null) return const [];
    final alreadyInBase = _duplicateCommits.contains(commit.sha);
    final forecast = _conflictForecast[commit.sha];
    return [
      if (alreadyInBase)
        (
          id: 'already-in-base',
          text: '이미 $baseRef에 반영됨',
          color: _duplicateBadge,
          tooltip: '재배치는 이 커밋을 건너뜁니다',
        ),
      // 이미 base에 있는 커밋은 재배치가 재생하지 않으니 단독 재생의 충돌 예고는
      // 일어날 수 없는 일을 경고하는 셈이다. 예고를 만들 때 이미 걸러 두지만 뒤늦게
      // 도착한 예고가 있어도 배지로 올리지 않는다.
      if (!alreadyInBase && forecast != null && forecast.isNotEmpty)
        (
          id: 'conflict-forecast',
          text: _conflictForecastLabel(forecast),
          color: _forecastBadge,
          tooltip: '순차 재배치에서는 앞 커밋의 해결이 이 예상을 바꿀 수 있습니다',
        ),
    ];
  }

  /// 선택된 커밋이 행에서 달고 있는 라벨을 미리보기 판 머리에도 같은 문구·색으로
  /// 올린다. 라벨이 없는 평범한 커밋이면 위젯 자체가 없다.
  Widget _previewCommitLabels(GitCommit commit) {
    final progress = _commitProgressLabel(commit);
    final badges = _commitBadges(commit);
    if (progress == null && badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Wrap(
        runSpacing: 3,
        children: [
          if (progress != null)
            _rowBadge(
              key: Key('preview-commit-progress-${commit.sha}'),
              text: progress.text,
              color: progress.color,
              textColor: progress.textColor,
            ),
          for (final badge in badges)
            _tooltip(
              badge.tooltip,
              _rowBadge(
                key: Key('preview-commit-${badge.id}-${commit.sha}'),
                text: badge.text,
                color: badge.color,
              ),
            ),
        ],
      ),
    );
  }

  /// 커밋 행 오른쪽 배지. 근거가 도착하기 전에는 이 위젯 자체가 없으니 자리도
  /// 차지하지 않는다.
  Widget _rowBadge({
    required Key key,
    required String text,
    required Color color,
    Color? textColor,
  }) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor ?? color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  /// '충돌 예상 · settings.dart 외 2' — 첫 파일 이름과 나머지 개수.
  static String _conflictForecastLabel(List<String> files) {
    final first = files.first.split('/').last;
    return files.length == 1
        ? '충돌 예상 · $first'
        : '충돌 예상 · $first 외 ${files.length - 1}';
  }

  /// No hairlines anywhere: the hash column's rule is the only line, a 2px strip
  /// stopping 1px short top and bottom so stacked rows read apart.
  Widget _cell(double width, Widget child, {Color? leftBorder, Key? ruleKey}) {
    final cell = Container(
      width: width,
      padding: EdgeInsets.only(
        left: leftBorder == null ? _columnTextInset : _railedColumnTextInset,
        right: _columnTextInset,
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
    if (leftBorder == null) return cell;
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          cell,
          Positioned(
            key: ruleKey,
            left: 0,
            top: 1,
            bottom: 1,
            width: 2,
            child: ColoredBox(color: leftBorder),
          ),
        ],
      ),
    );
  }

  // Left aligned: the footer sits inside the horizontally scrollable body, so
  // centering it across every column would push it out of view.
  Widget _footer() => Container(
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: _palette.surface,
      border: Border(top: BorderSide(color: _palette.border)),
    ),
    child: _loading
        ? Text(
            'Loading more…',
            style: TextStyle(color: _palette.muted, fontSize: 11),
          )
        : _loadError != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Could not load history',
                style: TextStyle(color: Color(0xFFF29AB2), fontSize: 11),
              ),
              TextButton(onPressed: _loadNextPage, child: const Text('Retry')),
            ],
          )
        : _end
        ? Text(
            _commits.isEmpty ? 'No commits' : 'End of history',
            style: TextStyle(color: _palette.muted, fontSize: 11),
          )
        : const SizedBox.shrink(),
  );

  // ----------------------------------------------------------------- preview

  /// The branch line a commit's row sits on, for the accents outside the list.
  int _branchOf(GitCommit commit) => _rows
      .firstWhere(
        (row) => row.commit.sha == commit.sha,
        orElse: () => _rows.first,
      )
      .branch;

  Widget _preview() => ValueListenableBuilder<int>(
    valueListenable: _selectedIndex,
    builder: (context, _, _) => _previewFor(_selectedCommit),
  );

  /// Drags the panel's inner edge. The stored size is what the open/close tween
  /// targets, so resizing and animating stay in step.
  Widget _previewResizer(PreviewPlacement placement) {
    final vertical = placement == PreviewPlacement.bottom;
    final handle = MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const Key('preview-resizer'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: vertical
            ? null
            : (details) => setState(() {
                final delta = placement == PreviewPlacement.right
                    ? -details.delta.dx
                    : details.delta.dx;
                _previewWidth = (_previewWidth + delta).clamp(
                  _previewMinWidth,
                  MediaQuery.sizeOf(context).width * _previewMaxWidthFraction,
                );
              }),
        onHorizontalDragEnd: vertical ? null : (_) => _savePreviewSize(),
        onVerticalDragUpdate: vertical
            ? (details) => setState(() {
                _previewHeight = (_previewHeight - details.delta.dy).clamp(
                  math.min(_previewMinHeight, _bottomPreviewMaxHeight),
                  _bottomPreviewMaxHeight,
                );
              })
            : null,
        onVerticalDragEnd: vertical ? (_) => _savePreviewSize() : null,
      ),
    );
    return vertical
        ? Positioned(left: 0, right: 0, top: 0, height: 8, child: handle)
        : Positioned(
            left: placement == PreviewPlacement.right ? 0 : null,
            right: placement == PreviewPlacement.left ? 0 : null,
            top: 0,
            bottom: 0,
            width: 8,
            child: handle,
          );
  }

  void _savePreviewSize() => widget.onPreviewSizeChanged?.call((
    width: _previewWidth,
    height: _previewHeight,
  ));

  Widget _previewFor(GitCommit? commit) {
    final placement = _previewController.previewPlacement;
    return Container(
      key: const Key('preview-surface'),
      decoration: BoxDecoration(
        color: _palette.surface,
        border: Border(
          left: placement == PreviewPlacement.right
              ? BorderSide(color: _palette.border)
              : BorderSide.none,
          right: placement == PreviewPlacement.left
              ? BorderSide(color: _palette.border)
              : BorderSide.none,
          top: placement == PreviewPlacement.bottom
              ? BorderSide(color: _palette.border)
              : BorderSide.none,
        ),
      ),
      // Everything in here is text worth copying; taps still reach the buttons.
      child: Stack(
        children: [
          SelectionArea(
            onSelectionChanged: (selection) =>
                debugPreviewSelection = selection?.plainText,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _previewHeader(commit),
                if (!_usesBranchPreviewResult(commit))
                  Container(
                    key: const Key('preview-shortcut-hint'),
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _cherryPickState == null
                          ? '파일 이동 ⌘↑/↓ · 화면 스크롤 ⇧⌘↑/↓'
                          : '충돌 파일을 해결한 뒤 계속할 수 있습니다',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _palette.muted,
                        fontSize: 10,
                        fontFamily: technicalFontFamily,
                        fontFamilyFallback: technicalFontFallback,
                      ),
                    ),
                  ),
                Expanded(
                  child: _cherryPickState != null
                      ? _cherryPickPanel()
                      : commit == null
                      ? Center(
                          child: Text(
                            'No commit selected',
                            style: TextStyle(
                              color: _palette.muted,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : _previewBody(commit),
                ),
              ],
            ),
          ),
          _previewResizer(placement),
        ],
      ),
    );
  }

  Widget _previewHeader(GitCommit? commit) {
    final branchPreview = _usesBranchPreviewResult(commit);
    final branchTitle = _branchPreviewMode == BranchPreviewMode.merge
        ? _branchPreviewHasConflict
              ? 'Merge 충돌 해결'
              : '가상 병합 커밋'
        : _branchPreviewHasConflict
        ? 'Rebase 상태 및 결정'
        : '가상 리베이스 결과';
    final branchStatus = _branchPreviewHasConflict
        ? _branchPreviewMode == BranchPreviewMode.merge
              ? '파일 ${_mergePreview?.conflictFiles.length ?? _comparison?.merge.files.length ?? 0}개'
              : '충돌 커밋에 포커스'
        : switch (_branchApplyStatus) {
            BranchApplyStatus.applying => '적용 중',
            BranchApplyStatus.applied => '적용 완료',
            BranchApplyStatus.reverting => '되돌리는 중',
            BranchApplyStatus.reverted => '되돌리기 완료',
            BranchApplyStatus.failed => '작업 실패',
            BranchApplyStatus.idle => '아직 적용하지 않음',
          };
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _palette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _cherryPickState != null
                  ? '체리픽 충돌'
                  : branchPreview
                  ? branchTitle
                  : _comparison != null
                  ? '선택한 커밋의 diff'
                  : 'Commit & Diff',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: branchPreview ? _palette.text : _palette.muted,
                fontSize: 12,
                fontWeight: branchPreview ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: branchPreview ? 0 : 0.66,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (branchPreview)
            Text(
              branchStatus,
              style: TextStyle(color: _palette.muted, fontSize: 10),
            )
          else ...[
            _ShowDiffButton(
              key: const Key('preview-full-diff'),
              onTap: commit == null || _cherryPickState != null
                  ? null
                  : _openFullDiff,
              height: 28,
              labelSize: 11,
              shortcutSize: 8,
            ),
            if (_cherryPickState == null &&
                (commit?.isWorkingTree ?? false)) ...[
              const SizedBox(width: 8),
              Text(
                'WIP',
                key: const Key('preview-working-tree'),
                style: TextStyle(
                  color: _palette.muted,
                  fontSize: 11,
                  fontFamily: technicalFontFamily,
                  fontFamilyFallback: technicalFontFallback,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _cherryPickPanel() {
    final state = _cherryPickState!;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${state.conflicts.length}개 충돌 파일',
            style: TextStyle(
              color: _palette.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: state.conflicts.isEmpty
                ? Center(
                    child: Text(
                      '모든 충돌 파일이 해결되었습니다.',
                      style: TextStyle(color: _palette.muted, fontSize: 12),
                    ),
                  )
                : ListView(
                    children: [
                      for (final path in state.conflicts)
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            dense: true,
                            selected: path == _selectedConflictPath,
                            selectedColor: _palette.text,
                            selectedTileColor: _palette.neutralChip,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            onTap: () =>
                                setState(() => _selectedConflictPath = path),
                            title: Text(
                              path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                            trailing: Text(
                              '해결 필요',
                              style: TextStyle(
                                color: _behind,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          if (_cherryPickError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _cherryPickError.toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _behind, fontSize: 11),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const Key('cherry-pick-open-editor'),
                onPressed: _cherryPickBusy || _selectedConflictPath == null
                    ? null
                    : () => unawaited(_openConflictEditor()),
                child: const Text('편집기로 열기'),
              ),
              TextButton(
                key: const Key('cherry-pick-abort'),
                onPressed: _cherryPickBusy
                    ? null
                    : () => unawaited(_confirmAbortCherryPick()),
                child: const Text('체리픽 중단'),
              ),
              FilledButton(
                key: const Key('cherry-pick-continue'),
                onPressed: !_cherryPickBusy && state.canContinue
                    ? () => unawaited(_continueCherryPick())
                    : null,
                child: const Text('계속'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openConflictEditor() async {
    final path = _selectedConflictPath;
    if (path == null || _cherryPickBusy) return;
    setState(() {
      _cherryPickBusy = true;
      _cherryPickError = null;
    });
    try {
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          overlay.size.width - 260,
          overlay.size.height - 160,
          16,
          16,
        ),
        items: [
          const PopupMenuItem(value: 'internal', child: Text('내장 에디터')),
          const PopupMenuItem(value: 'external', child: Text('외부 에디터')),
        ],
      );
      if (!mounted || choice == null) return;
      final externalEditor = ExternalEditorService(
        repositoryRoot: widget.repository.root,
      );
      if (choice == 'external') {
        await externalEditor.open(relativePath: path);
        return;
      }
      final document =
          await widget.documentLoaderForTesting?.call(path) ??
          await WorkingTreeTextDocument.load(
            repositoryRoot: widget.repository.root,
            relativePath: path,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MonacoEditorScreen(
            title: path,
            initialText: document.text,
            language: monacoLanguageForPath(path),
            readOnly: false,
            onSave: (text) async {
              await document.save(text);
              await widget.repository.stageResolvedFile(path);
              await _reloadCherryPickState();
              if (mounted) Navigator.of(context).pop();
            },
            onOpenExternal: () async {
              try {
                await externalEditor.open(relativePath: path);
              } catch (error) {
                if (mounted) setState(() => _cherryPickError = error);
              }
            },
            editorForTesting: widget.editorForTesting,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _cherryPickError = error);
    } finally {
      if (mounted) setState(() => _cherryPickBusy = false);
    }
  }

  /// The commit's changed files, remembered in resolved form as well so ⌘↑/⌘↓ can
  /// walk them without waiting on a future.
  bool _usesBranchPreviewResult(GitCommit? commit) {
    final kind = commit == null ? null : _previewGraph?.kinds[commit.sha];
    return kind == PreviewGraphNodeKind.virtualMerge ||
        kind == PreviewGraphNodeKind.virtualRebase ||
        kind == PreviewGraphNodeKind.virtualRebaseMerge ||
        (_comparison != null &&
            (_branchPreviewMode == BranchPreviewMode.merge
                ? _mergePreviewError != null
                : _rebasePreviewError != null)) ||
        (_branchPreviewMode == BranchPreviewMode.rebase &&
            _rebasePreview?.status == RebasePreviewStatus.conflict &&
            _rebasePreview?.currentCommit?.sha == commit?.sha);
  }

  ({String from, String to})? get _branchPreviewRange {
    final comparison = _comparison;
    if (comparison == null) return null;
    if (_branchPreviewMode == BranchPreviewMode.merge) {
      return (
        from: comparison.baseTip,
        to:
            _mergePreview?.treeSha ??
            comparison.merge.treeSha ??
            comparison.compareTip,
      );
    }
    final preview = _rebasePreview;
    if (preview?.status == RebasePreviewStatus.clean &&
        preview?.virtualTip != null) {
      return (from: comparison.baseTip, to: preview!.virtualTip!);
    }
    final current = preview?.currentCommit;
    return (
      from: current == null || current.parents.isEmpty
          ? comparison.baseTip
          : current.parents.first,
      to: current?.sha ?? comparison.compareTip,
    );
  }

  String _previewKey(GitCommit commit) {
    final range = _usesBranchPreviewResult(commit) ? _branchPreviewRange : null;
    return range == null
        ? commit.sha
        : '${_branchPreviewMode.name}:${range.from}..${range.to}';
  }

  Future<List<GitFileChange>> _previewFilesFor(GitCommit commit) {
    final key = _previewKey(commit);
    return _previewFiles.putIfAbsent(key, () {
      final comparison = _comparison;
      final preview = _rebasePreview;
      final request = comparison == null || !_usesBranchPreviewResult(commit)
          ? widget.repository.loadFiles(commit)
          : _branchPreviewMode == BranchPreviewMode.merge
          ? Future.value(
              _effectiveMergeStatus == MergeConflictStatus.clean
                  ? (_mergePreview?.treeSha ?? comparison.merge.treeSha) == null
                        ? comparison.files
                        : _mergePreview?.resultFiles ??
                              comparison.merge.resultFiles
                  : [
                      for (final path
                          in _mergePreview?.conflictFiles ??
                              comparison.merge.files)
                        GitFileChange(
                          path: path,
                          status: 'U',
                          additions: null,
                          deletions: null,
                        ),
                    ],
            )
          : preview?.status == RebasePreviewStatus.clean &&
                preview?.virtualTip != null
          ? widget.repository.loadFilesBetween(
              comparison.baseTip,
              preview!.virtualTip!,
            )
          : Future.value([
              for (final path in preview?.conflictFiles ?? const <String>[])
                GitFileChange(
                  path: path,
                  status: 'U',
                  additions: null,
                  deletions: null,
                ),
            ]);
      unawaited(
        request
            .then((files) => _previewFileLists[key] = files)
            .catchError((_) => const <GitFileChange>[]),
      );
      return request;
    });
  }

  Future<String> _previewMessageFor(GitCommit commit) =>
      FullDiffCommitMessageCache.shared.getOrLoad(
        repositoryRoot: widget.repository.root,
        sha: commit.sha,
        loader: () => widget.repository.loadCommitMessage(commit.sha),
      );

  /// Steps the open preview through the commit's files, clamped at both ends.
  void _stepPreviewFile(int delta, {bool animate = true}) {
    final commit = _selectedCommit;
    if (commit == null) return;
    final key = _previewKey(commit);
    final files = _previewFileLists[key];
    if (files == null || files.isEmpty) return;
    final current = _previewPaths[key] ?? files.first.path;
    final index = files.indexWhere((file) => file.path == current);
    final next = (index + delta).clamp(0, files.length - 1);
    if (files[next].path == current) return;
    _selectPreviewFile(
      commit,
      files[next].path,
      revealDirection: delta,
      animateReveal: animate,
    );
  }

  void _selectPreviewFile(
    GitCommit commit,
    String path, {
    int? revealDirection,
    bool animateReveal = true,
    int? line,
  }) {
    setState(() {
      _previewPaths[_previewKey(commit)] = path;
      _previewDiffOpen = true;
      // 파일 줄을 그냥 누르면 위에서부터, 근접 구역을 누르면 그 줄에서 시작한다.
      _previewDiffLineTarget = line == null ? null : (path: path, line: line);
      // 같은 구역을 다시 누르면 diff가 맨 위로 돌아가니 한 번 더 데려다줘야 한다.
      if (line != null) _previewDiffLineRevealed = null;
    });
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final outerOffset = _previewFilesScrollController.hasClients
          ? _previewFilesScrollController.offset
          : null;
      if (_previewDiffScrollController.hasClients) {
        _previewDiffScrollController.jumpTo(0);
      }
      if (outerOffset != null && _previewFilesScrollController.hasClients) {
        _previewFilesScrollController.jumpTo(
          outerOffset.clamp(
            _previewFilesScrollController.position.minScrollExtent,
            _previewFilesScrollController.position.maxScrollExtent,
          ),
        );
      }
      if (revealDirection != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _revealSelectedPreviewFile(revealDirection, animate: animateReveal);
          }
        });
      }
    });
  }

  ScrollController? _previewPageScrollController(int direction) {
    bool canScroll(ScrollController controller) {
      if (!controller.hasClients) return false;
      final position = controller.position;
      return direction > 0
          ? position.extentAfter > 0
          : position.extentBefore > 0;
    }

    if (_previewDiffOpen && canScroll(_previewDiffScrollController)) {
      return _previewDiffScrollController;
    }
    if (canScroll(_previewFilesScrollController)) {
      return _previewFilesScrollController;
    }
    return null;
  }

  void _revealSelectedPreviewFile(int direction, {required bool animate}) {
    final selectedContext = _selectedPreviewFileKey.currentContext;
    if (selectedContext == null) {
      if (_previewFilesScrollController.hasClients &&
          _previewFilesScrollController.position.pixels >
              _previewFilesScrollController.position.minScrollExtent) {
        _previewFilesScrollController.jumpTo(0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _revealSelectedPreviewFile(direction, animate: animate);
          }
        });
      }
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        selectedContext,
        duration: animate ? const Duration(milliseconds: 100) : Duration.zero,
        curve: Curves.easeOut,
        alignmentPolicy: direction < 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ),
    );
  }

  Widget _previewBody(GitCommit commit) {
    final branchPreview = _usesBranchPreviewResult(commit);
    final files = _previewFilesFor(commit);
    return FutureBuilder<List<GitFileChange>>(
      key: branchPreview ? null : ValueKey(commit.sha),
      future: files,
      builder: (context, snapshot) {
        final changes = snapshot.data;
        final key = _previewKey(commit);
        final requestedPath = _previewDiffOpen ? _previewPaths[key] : null;
        GitFileChange? selectedFile;
        if (changes != null && changes.isNotEmpty) {
          selectedFile = changes.firstWhere(
            (file) => file.path == requestedPath,
            orElse: () => changes.first,
          );
        }
        final selectedPath = selectedFile?.path;
        final info = Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _previewCommitLabels(commit),
              if (!branchPreview) ...[
                Text(
                  commit.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (!commit.isWorkingTree)
                  FutureBuilder<String>(
                    future: _previewMessageFor(commit),
                    builder: (context, snapshot) {
                      final body = _commitMessageBody(snapshot.data);
                      if (body.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          body,
                          key: const Key('preview-commit-body'),
                          style: TextStyle(
                            color: _palette.text,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 9),
                Text(
                  commit.isWorkingTree
                      ? 'Working tree changes'
                      : 'commit ${commit.sha}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _palette.muted,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              if (branchPreview && _branchPreviewHasConflict) ...[
                _branchPreviewConflictStatusCard(),
                _branchPreviewSafeWorkspace(),
              ],
              if (branchPreview && _branchPreviewResolutionComplete)
                _branchPreviewResolutionCard(),
              if (branchPreview && _branchPreviewDropped)
                _branchPreviewDroppedCard(),
              if (branchPreview &&
                  _branchPreviewReady &&
                  !_branchPreviewResolutionComplete)
                _branchPreviewApplyCard(),
              if (branchPreview &&
                  !_branchPreviewHasConflict &&
                  (_branchPreviewMode == BranchPreviewMode.merge
                          ? _mergePreviewError
                          : _rebasePreviewError) !=
                      null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    (_branchPreviewMode == BranchPreviewMode.merge
                            ? _mergePreviewError
                            : _rebasePreviewError)
                        .toString(),
                    style: const TextStyle(color: _behind, fontSize: 10),
                  ),
                ),
              if (!branchPreview) _previewPerson(commit),
              _previewStats(changes),
              KeyedSubtree(
                key:
                    _branchPreviewMode == BranchPreviewMode.rebase &&
                        _rebasePreview?.status == RebasePreviewStatus.conflict
                    ? const Key('rebase-conflict-files')
                    : null,
                child: _previewFileList(
                  commit,
                  changes,
                  snapshot.hasError,
                  selectedPath,
                ),
              ),
            ],
          ),
        );
        return NestedScrollView(
          key: const Key('preview-content-scroll'),
          controller: _previewFilesScrollController,
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: const Key('preview-files-scroll'),
                child: info,
              ),
            ),
          ],
          body: const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _adjacentPreviewDiff(PreviewPlacement placement) => Stack(
    children: [
      Positioned.fill(
        child: ValueListenableBuilder<int>(
          valueListenable: _selectedIndex,
          builder: (context, _, _) {
            final commit = _selectedCommit;
            if (commit == null) return const SizedBox.shrink();
            return FutureBuilder<List<GitFileChange>>(
              key: ValueKey(_previewKey(commit)),
              future: _previewFilesFor(commit),
              builder: (context, snapshot) {
                final changes = snapshot.data;
                if (changes == null || changes.isEmpty) {
                  return const SizedBox.shrink();
                }
                final requestedPath = _previewPaths[_previewKey(commit)];
                final file = changes.firstWhere(
                  (file) => file.path == requestedPath,
                  orElse: () => changes.first,
                );
                return Container(
                  key: const Key('preview-diff'),
                  decoration: BoxDecoration(
                    color: _palette.background,
                    border: Border.all(color: _palette.border),
                  ),
                  child: SelectionArea(
                    child: KeyedSubtree(
                      key: const Key('preview-diff-scroll'),
                      child: _previewDiff(commit, file),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      _previewDiffResizer(placement),
    ],
  );

  Widget _previewDiffResizer(PreviewPlacement placement) {
    final vertical = placement == PreviewPlacement.bottom;
    final handle = MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      onEnter: vertical
          ? null
          : (_) => setState(() => _previewDiffResizerHovered = true),
      onExit: vertical
          ? null
          : (_) => setState(() => _previewDiffResizerHovered = false),
      child: GestureDetector(
        key: const Key('preview-diff-resizer'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: vertical
            ? null
            : (details) => setState(() {
                final delta = placement == PreviewPlacement.right
                    ? -details.delta.dx
                    : details.delta.dx;
                _setPreviewDiffExtent(
                  placement,
                  ((_storedPreviewDiffExtent(placement) ??
                              _visiblePreviewDiffExtent) +
                          delta)
                      .clamp(0.0, _maxPreviewDiffExtent),
                );
              }),
        onHorizontalDragEnd: vertical
            ? null
            : (_) => _savePreviewDiffExtent(placement),
        onVerticalDragUpdate: vertical
            ? (details) => setState(
                () => _setPreviewDiffExtent(
                  placement,
                  ((_storedPreviewDiffExtent(placement) ??
                              _visiblePreviewDiffExtent) -
                          details.delta.dy)
                      .clamp(0.0, _maxPreviewDiffExtent),
                ),
              )
            : null,
        onVerticalDragEnd: vertical
            ? (_) => _savePreviewDiffExtent(placement)
            : null,
        child: vertical
            ? const SizedBox.expand()
            : Align(
                alignment: placement == PreviewPlacement.right
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: ColoredBox(
                  key: const Key('preview-diff-hover-line'),
                  color: _previewDiffResizerHovered
                      ? const Color(0xFF5AB0FF)
                      : Colors.transparent,
                  child: const SizedBox(width: 2, height: double.infinity),
                ),
              ),
      ),
    );
    return vertical
        ? Positioned(left: 0, right: 0, top: 0, height: 8, child: handle)
        : Positioned(
            left: placement == PreviewPlacement.right ? 0 : null,
            right: placement == PreviewPlacement.left ? 0 : null,
            top: 0,
            bottom: 0,
            width: 12,
            child: handle,
          );
  }

  void _setPreviewDiffExtent(PreviewPlacement placement, double extent) {
    switch (placement) {
      case PreviewPlacement.left:
        _previewDiffLeftWidth = extent;
        return;
      case PreviewPlacement.right:
        _previewDiffRightWidth = extent;
        return;
      case PreviewPlacement.bottom:
        _previewDiffBottomHeight = extent;
        return;
      case PreviewPlacement.closed:
        return;
    }
  }

  double? _storedPreviewDiffExtent(PreviewPlacement placement) =>
      switch (placement) {
        PreviewPlacement.left => _previewDiffLeftWidth,
        PreviewPlacement.right => _previewDiffRightWidth,
        PreviewPlacement.bottom => _previewDiffBottomHeight,
        PreviewPlacement.closed => null,
      };

  void _savePreviewDiffExtent(PreviewPlacement placement) =>
      widget.onPreviewDiffSizeChanged?.call((
        placement: placement,
        extent:
            _storedPreviewDiffExtent(placement) ?? _visiblePreviewDiffExtent,
      ));

  void _closePreviewDiff() {
    setState(() => _previewDiffOpen = false);
    _focusNode.requestFocus();
  }

  Widget _previewPerson(GitCommit commit) {
    final separateCommitter =
        commit.author.name != commit.committer.name ||
        commit.author.email != commit.committer.email;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _palette.border),
          bottom: BorderSide(color: _palette.border),
        ),
      ),
      child: Column(
        children: [
          _previewIdentity(
            commit,
            committer: false,
            timestamp: commit.isWorkingTree
                ? null
                : separateCommitter
                ? commit.authorTimestamp
                : commit.committerTimestamp,
          ),
          if (!commit.isWorkingTree && separateCommitter) ...[
            const SizedBox(height: 10),
            _previewIdentity(
              commit,
              committer: true,
              timestamp: commit.committerTimestamp,
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewIdentity(
    GitCommit commit, {
    required bool committer,
    required int? timestamp,
  }) {
    final identity = committer ? commit.committer : commit.author;
    final role = committer ? 'Committer' : 'Author';
    final email = identity.email.trim();
    final roleLine = email.isEmpty ? role : '$role · $email';
    return Row(
      key: Key(committer ? 'preview-committer' : 'preview-author'),
      children: [
        commit.isWorkingTree
            ? Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _palette.border),
                ),
              )
            : CommitAvatarStack(
                commit: commit,
                avatarService: widget.avatarService,
                showRemoteAvatars: widget.showRemoteAvatars,
                size: 42,
                stacked: false,
                committerOnly: committer,
                discColor: AvatarService.branchColor(_branchOf(commit)),
              ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                commit.isWorkingTree ? 'Not committed' : identity.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _palette.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                commit.isWorkingTree
                    ? 'No commit object or committer'
                    : roleLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _palette.muted, fontSize: 12),
              ),
              if (timestamp != null)
                Text(
                  exactCommitTime(timestamp),
                  maxLines: 1,
                  style: TextStyle(
                    color: _palette.muted,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewStats(List<GitFileChange>? changes) {
    int total(int? Function(GitFileChange file) value) =>
        (changes ?? const []).fold(0, (sum, file) => sum + (value(file) ?? 0));
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '${changes?.length ?? 0} '
              '${changes?.length == 1 ? 'file' : 'files'} changed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _palette.muted, fontSize: 12),
            ),
          ),
          const Spacer(),
          Text(
            '+${total((file) => file.additions)}',
            style: const TextStyle(
              color: _main,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '−${total((file) => file.deletions)}',
            style: const TextStyle(
              color: _hash,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  bool get _branchPreviewHasConflict =>
      !_branchPreviewDropped &&
      (_branchPreviewMode == BranchPreviewMode.merge
          ? _effectiveMergeStatus == MergeConflictStatus.conflicts
          : _rebasePreview?.status == RebasePreviewStatus.conflict);

  Widget _branchPreviewConflictChoices() {
    final comparison = _comparison!;
    final mergeMode = _branchPreviewMode == BranchPreviewMode.merge;
    final interactive = mergeMode
        ? _mergePreviewSession != null
        : _rebasePreviewSession != null;
    final conflictPath = mergeMode
        ? _selectedMergeConflictPath
        : _selectedRebaseConflictPath;
    final keepBoth = conflictPath == null
        ? null
        : _keepBothCandidates[conflictPath];
    Widget choice({
      required Key key,
      required String label,
      required VoidCallback onTap,
      bool accent = false,
    }) => InkWell(
      key: key,
      onTap:
          !interactive ||
              _mergePreviewBusy ||
              _rebasePreviewBusy ||
              _repositoryOperationInProgress
          ? null
          : onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: accent
              ? _previewPurple.withValues(alpha: 0.08)
              : _palette.raised,
          border: Border.all(
            color: accent
                ? const Color(0xFF9D79D0)
                : _palette.muted.withValues(alpha: 0.55),
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent ? _previewPurple : _palette.text,
            fontSize: 10,
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('branch-preview-conflict-actions'),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _previewConflictPanel.withValues(alpha: 0.72),
            border: Border(
              top: BorderSide(color: _previewConflict.withValues(alpha: 0.45)),
            ),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!mergeMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '이 충돌 해결:',
                    style: TextStyle(
                      color: _previewConflict.withValues(alpha: 0.92),
                      fontSize: 10,
                    ),
                  ),
                ),
              choice(
                key: Key(
                  mergeMode
                      ? 'merge-conflict-use-base'
                      : 'rebase-conflict-use-base',
                ),
                label: '${comparison.baseRef} 사용',
                onTap: () => unawaited(
                  mergeMode
                      ? _resolveMergeConflict(MergeConflictChoice.base)
                      : _resolveRebaseConflict(RebaseConflictChoice.base),
                ),
              ),
              choice(
                key: Key(
                  mergeMode
                      ? 'merge-conflict-use-compare'
                      : 'rebase-conflict-use-compare',
                ),
                label: '${comparison.compareRef} 사용',
                onTap: () => unawaited(
                  mergeMode
                      ? _resolveMergeConflict(MergeConflictChoice.compare)
                      : _resolveRebaseConflict(RebaseConflictChoice.commit),
                ),
              ),
              // P3 — 양쪽 모두 순수 추가로 판정된 파일에만 나타나는 세 번째 선택지.
              if (keepBoth != null)
                choice(
                  key: const Key('conflict-keep-both'),
                  label: '양쪽 유지',
                  accent: true,
                  onTap: () => setState(
                    () => _keepBothOpenPath = _keepBothOpenPath == conflictPath
                        ? null
                        : conflictPath,
                  ),
                ),
              choice(
                key: Key(
                  mergeMode
                      ? 'merge-conflict-use-both'
                      : 'rebase-conflict-edit',
                ),
                // 두 모드 모두 에디터를 여는 같은 동작이다 — 문구도 같아야 '양쪽
                // 유지'(P3 결합)와 헷갈리지 않는다.
                label: '직접 편집',
                onTap: () => unawaited(
                  _openBranchPreviewConflictEditor(mergeMode: mergeMode),
                ),
              ),
            ],
          ),
        ),
        if (keepBoth != null && _keepBothOpenPath == conflictPath)
          _keepBothChooser(
            conflictPath!,
            keepBoth,
            baseRef: comparison.baseRef,
            mergeMode: mergeMode,
          ),
        if (interactive)
          mergeMode ? _mergeConflictActions() : _rebaseConflictActions(),
      ],
    );
  }

  /// P3 상태 B — 결합 순서 두 가지를 나란히 놓고 하나만 고르게 한다. 미리보기는
  /// 실제 결합 내용 그대로다: 파랑이 기준 쪽 추가, 초록이 브랜치 쪽 추가.
  Widget _keepBothChooser(
    String path,
    KeepBothCandidate candidate, {
    required String baseRef,
    required bool mergeMode,
  }) {
    Widget order({
      required Key key,
      required String caption,
      required bool baseFirst,
    }) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            caption,
            style: TextStyle(
              color: _palette.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _palette.background,
              border: Border.all(color: _palette.muted.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(7),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text.rich(
                _keepBothPreview(candidate, baseFirst: baseFirst),
                softWrap: false,
              ),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton(
            key: key,
            onPressed:
                (mergeMode ? _mergePreviewBusy : _rebasePreviewBusy) ||
                    _repositoryOperationInProgress
                ? null
                : () => unawaited(
                    _applyKeepBoth(
                      path,
                      candidate,
                      mergeMode: mergeMode,
                      baseFirst: baseFirst,
                    ),
                  ),
            child: const Text('이 순서로 적용'),
          ),
        ],
      ),
    );
    return Container(
      key: const Key('conflict-keep-both-chooser'),
      padding: const EdgeInsets.all(8),
      color: _previewPurplePanel.withValues(alpha: 0.72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$path — 양쪽 유지',
            style: TextStyle(
              color: _palette.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '충돌 구역 ${candidate.hunks.length}곳 전부에서 양쪽이 서로 다른 코드를 '
            '추가했습니다. 순서만 고르면 됩니다.',
            style: TextStyle(color: _palette.muted, fontSize: 10),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              order(
                key: const Key('keep-both-apply-base-first'),
                caption: '기준($baseRef) 먼저',
                baseFirst: true,
              ),
              const SizedBox(width: 10),
              order(
                key: const Key('keep-both-apply-branch-first'),
                caption: '브랜치 먼저',
                baseFirst: false,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '적용해도 파일은 계속 편집할 수 있습니다. 파랑은 기준 쪽 추가, 초록은 '
            '브랜치 쪽 추가입니다.',
            style: TextStyle(color: _palette.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  TextSpan _keepBothPreview(
    KeepBothCandidate candidate, {
    required bool baseFirst,
  }) => TextSpan(
    children: [
      for (final hunk in candidate.hunks)
        for (final side
            in baseFirst
                ? [
                    (lines: hunk.ours, color: _keepBothOursColor),
                    (lines: hunk.theirs, color: _keepBothTheirsColor),
                  ]
                : [
                    (lines: hunk.theirs, color: _keepBothTheirsColor),
                    (lines: hunk.ours, color: _keepBothOursColor),
                  ])
          if (side.lines.isNotEmpty)
            TextSpan(
              text: '${side.lines.join('\n')}\n',
              style: TextStyle(
                color: side.color,
                fontSize: 10,
                height: 1.5,
                fontFamily: technicalFontFamily,
                fontFamilyFallback: technicalFontFallback,
              ),
            ),
    ],
  );

  /// 고른 순서의 결합 내용을 쓰고 해결로 표시한다. 파일은 그 뒤로도 편집할 수 있고
  /// 마커가 남으면 markResolved가 막는다(P1a).
  Future<void> _applyKeepBoth(
    String path,
    KeepBothCandidate candidate, {
    required bool mergeMode,
    required bool baseFirst,
  }) async {
    final mergeSession = _mergePreviewSession;
    final rebaseSession = _rebasePreviewSession;
    if ((mergeMode ? mergeSession == null : rebaseSession == null) ||
        (mergeMode ? _mergePreviewBusy : _rebasePreviewBusy) ||
        _repositoryOperationInProgress) {
      return;
    }
    setState(() {
      if (mergeMode) {
        _mergePreviewBusy = true;
        _mergePreviewError = null;
      } else {
        _rebasePreviewBusy = true;
        _rebasePreviewError = null;
      }
    });
    try {
      final content = baseFirst ? candidate.baseFirst : candidate.branchFirst;
      if (mergeMode) {
        await mergeSession!.applyKeepBoth(path, content);
      } else {
        await rebaseSession!.applyKeepBoth(path, content);
      }
      if (!mounted) return;
      setState(() {
        if (mergeMode) {
          _mergeResolvedFiles.add(path);
        } else {
          _rebaseResolvedFiles.add(path);
        }
        _keepBothCandidates.remove(path);
        _keepBothOpenPath = null;
        _previewDiffs.removeWhere((key, _) => key.path == path);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          if (mergeMode) {
            _mergePreviewError = error;
          } else {
            _rebasePreviewError = error;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          if (mergeMode) {
            _mergePreviewBusy = false;
          } else {
            _rebasePreviewBusy = false;
          }
        });
      }
    }
  }

  String? get _selectedMergeConflictPath {
    final preview = _mergePreview;
    if (preview == null || preview.conflictFiles.isEmpty) return null;
    final commit = _selectedCommit;
    final selected = commit == null ? null : _previewPaths[_previewKey(commit)];
    return preview.conflictFiles.contains(selected)
        ? selected
        : preview.conflictFiles.first;
  }

  bool get _canFinishMergePreview {
    final files = _mergePreview?.conflictFiles ?? const <String>[];
    return files.isNotEmpty && files.every(_mergeResolvedFiles.contains);
  }

  Widget _mergeConflictActions() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_mergePreviewError != null)
          Expanded(
            child: Text(
              _mergePreviewError.toString(),
              style: TextStyle(color: _behind, fontSize: 10),
            ),
          ),
        FilledButton(
          key: const Key('merge-conflict-continue'),
          onPressed: !_mergePreviewBusy && _canFinishMergePreview
              ? () => unawaited(_finishMergePreview())
              : null,
          child: const Text('해결 후 계속'),
        ),
      ],
    ),
  );

  Future<void> _resolveMergeConflict(MergeConflictChoice choice) async {
    final session = _mergePreviewSession;
    final path = _selectedMergeConflictPath;
    if (session == null || path == null || _mergePreviewBusy) return;
    setState(() {
      _mergePreviewBusy = true;
      _mergePreviewError = null;
    });
    try {
      await session.resolveFile(path, choice);
      if (mounted && identical(session, _mergePreviewSession)) {
        setState(() {
          _mergeResolvedFiles.add(path);
          _keepBothCandidates.remove(path);
          if (_keepBothOpenPath == path) _keepBothOpenPath = null;
          _previewDiffs.removeWhere((key, _) => key.path == path);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _mergePreviewError = error);
    } finally {
      if (mounted) setState(() => _mergePreviewBusy = false);
    }
  }

  Future<void> _finishMergePreview() async {
    final session = _mergePreviewSession;
    if (session == null || !_canFinishMergePreview || _mergePreviewBusy) return;
    setState(() {
      _mergePreviewBusy = true;
      _mergePreviewError = null;
    });
    try {
      final result = await session.finish();
      if (!mounted || !identical(session, _mergePreviewSession)) return;
      setState(() {
        _mergePreview = result;
        _previewFiles.clear();
        _previewFileLists.clear();
        _previewDiffs.clear();
      });
      _showPreviewTop();
    } catch (error) {
      if (mounted) setState(() => _mergePreviewError = error);
    } finally {
      if (mounted) setState(() => _mergePreviewBusy = false);
    }
  }

  String? get _selectedRebaseConflictPath {
    final preview = _rebasePreview;
    final current = preview?.currentCommit;
    if (preview == null || current == null || preview.conflictFiles.isEmpty) {
      return null;
    }
    final selected = _previewPaths[_previewKey(current)];
    return preview.conflictFiles.contains(selected)
        ? selected
        : preview.conflictFiles.first;
  }

  bool get _canContinueRebasePreview {
    final files = _rebasePreview?.conflictFiles ?? const <String>[];
    return files.isNotEmpty &&
        files.every(
          (path) =>
              _rebaseResolvedFiles.contains(path) ||
              _rebaseEditedFiles.contains(path),
        );
  }

  Widget _rebaseConflictActions() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_repositoryOperationInProgress)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              '현재 Git 작업을 마친 뒤 해결할 수 있습니다',
              style: TextStyle(color: _behind, fontSize: 10),
            ),
          ),
        if (_rebasePreviewError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              _rebasePreviewError.toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _behind, fontSize: 10),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 7,
          runSpacing: 7,
          children: [
            OutlinedButton(
              key: const Key('rebase-conflict-open-editor'),
              onPressed:
                  _rebasePreviewBusy ||
                      _repositoryOperationInProgress ||
                      _selectedRebaseConflictPath == null
                  ? null
                  : () => unawaited(
                      _openBranchPreviewConflictEditor(mergeMode: false),
                    ),
              child: const Text('편집기로 열기'),
            ),
            TextButton(
              key: const Key('rebase-conflict-abort'),
              onPressed: _rebasePreviewBusy
                  ? null
                  : () => _setBranchPreviewMode(BranchPreviewMode.merge),
              child: const Text('미리보기 중단'),
            ),
            FilledButton(
              key: const Key('rebase-conflict-continue'),
              onPressed:
                  !_rebasePreviewBusy &&
                      !_repositoryOperationInProgress &&
                      _canContinueRebasePreview
                  ? () => unawaited(_continueRebasePreview())
                  : null,
              child: const Text('계속'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _resolveRebaseConflict(RebaseConflictChoice choice) async {
    final session = _rebasePreviewSession;
    final path = _selectedRebaseConflictPath;
    if (session == null ||
        path == null ||
        _rebasePreviewBusy ||
        _repositoryOperationInProgress) {
      return;
    }
    setState(() {
      _rebasePreviewBusy = true;
      _rebasePreviewError = null;
    });
    try {
      await session.resolveFile(path, choice);
      if (mounted && identical(session, _rebasePreviewSession)) {
        setState(() {
          _rebaseResolvedFiles.add(path);
          _keepBothCandidates.remove(path);
          if (_keepBothOpenPath == path) _keepBothOpenPath = null;
          _previewDiffs.removeWhere((key, _) => key.path == path);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _rebasePreviewError = error);
    } finally {
      if (mounted) setState(() => _rebasePreviewBusy = false);
    }
  }

  Future<void> _continueRebasePreview() async {
    final session = _rebasePreviewSession;
    final comparison = _comparison;
    final request = _rebasePreviewSerial;
    if (session == null ||
        comparison == null ||
        !_canContinueRebasePreview ||
        _rebasePreviewBusy) {
      return;
    }
    setState(() {
      _rebasePreviewBusy = true;
      _rebasePreviewError = null;
    });
    try {
      for (final path in _rebaseEditedFiles.difference(_rebaseResolvedFiles)) {
        await session.markResolved(path);
      }
      final result = await session.continueAfterResolving();
      if (!mounted ||
          request != _rebasePreviewSerial ||
          !identical(session, _rebasePreviewSession)) {
        return;
      }
      await _applyRebasePreviewResult(comparison, result, request);
    } catch (error) {
      if (mounted &&
          request == _rebasePreviewSerial &&
          identical(session, _rebasePreviewSession)) {
        setState(() => _rebasePreviewError = error);
      }
    } finally {
      if (mounted &&
          request == _rebasePreviewSerial &&
          identical(session, _rebasePreviewSession)) {
        setState(() => _rebasePreviewBusy = false);
      }
    }
  }

  Future<void> _openBranchPreviewConflictEditor({
    required bool mergeMode,
  }) async {
    final mergeSession = _mergePreviewSession;
    final rebaseSession = _rebasePreviewSession;
    final path = mergeMode
        ? _selectedMergeConflictPath
        : _selectedRebaseConflictPath;
    final worktree = mergeMode
        ? mergeSession?.worktreePath
        : rebaseSession?.worktreePath;
    if ((mergeMode ? mergeSession == null : rebaseSession == null) ||
        path == null ||
        worktree == null ||
        (mergeMode ? _mergePreviewBusy : _rebasePreviewBusy) ||
        _repositoryOperationInProgress) {
      return;
    }
    setState(() {
      if (mergeMode) {
        _mergePreviewBusy = true;
        _mergePreviewError = null;
      } else {
        _rebasePreviewBusy = true;
        _rebasePreviewError = null;
      }
    });
    try {
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          overlay.size.width - 260,
          overlay.size.height - 160,
          16,
          16,
        ),
        items: const [
          PopupMenuItem(value: 'internal', child: Text('내장 에디터')),
          PopupMenuItem(value: 'external', child: Text('외부 에디터')),
        ],
      );
      if (!mounted || choice == null) return;
      final externalEditor = ExternalEditorService(repositoryRoot: worktree);
      if (choice == 'external') {
        await externalEditor.open(relativePath: path);
        if (mounted) setState(() => _rebaseEditedFiles.add(path));
        return;
      }
      final document =
          await widget.documentLoaderForTesting?.call(path) ??
          await WorkingTreeTextDocument.load(
            repositoryRoot: worktree,
            relativePath: path,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MonacoEditorScreen(
            title: path,
            initialText: document.text,
            language: monacoLanguageForPath(path),
            readOnly: false,
            onSave: (text) async {
              await document.save(text);
              if (mergeMode) {
                await mergeSession!.markResolved(path);
              } else {
                await rebaseSession!.markResolved(path);
              }
              if (mounted) {
                setState(() {
                  if (mergeMode) {
                    _mergeResolvedFiles.add(path);
                  } else {
                    _rebaseEditedFiles.add(path);
                    _rebaseResolvedFiles.add(path);
                  }
                  _previewDiffs.removeWhere((key, _) => key.path == path);
                });
                Navigator.of(context).pop();
              }
            },
            onOpenExternal: () async {
              await externalEditor.open(relativePath: path);
              if (mounted && !mergeMode) {
                setState(() => _rebaseEditedFiles.add(path));
              }
            },
            editorForTesting: widget.editorForTesting,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          if (mergeMode) {
            _mergePreviewError = error;
          } else {
            _rebasePreviewError = error;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          if (mergeMode) {
            _mergePreviewBusy = false;
          } else {
            _rebasePreviewBusy = false;
          }
        });
      }
    }
  }

  Widget _previewFileList(
    GitCommit commit,
    List<GitFileChange>? changes,
    bool failed,
    String? selectedPath,
  ) => Container(
    key: Key(
      _usesBranchPreviewResult(commit)
          ? 'branch-preview-file-list'
          : 'preview-files',
    ),
    alignment: Alignment.topLeft,
    child: failed
        ? const Center(
            child: Text(
              'Could not load files',
              style: TextStyle(color: Color(0xFFF29AB2), fontSize: 12),
            ),
          )
        : changes == null
        ? const Center(
            child: SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          )
        : changes.isEmpty
        ? Center(
            child: Text(
              'No changed files',
              style: TextStyle(color: _palette.muted, fontSize: 12),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final file in changes) ...[
                _previewFileRow(commit, file, file.path == selectedPath),
                ?_previewProximityLine(commit, file),
              ],
            ],
          ),
  );

  /// Which side of a clean merge brought this result file in. Null outside the
  /// clean merge preview, and without a merge base to measure our side against.
  ({String label, bool bothSides})? _previewProvenance(
    GitCommit commit,
    GitFileChange file,
  ) {
    final comparison = _comparison;
    if (comparison == null ||
        _branchPreviewMode != BranchPreviewMode.merge ||
        _effectiveMergeStatus != MergeConflictStatus.clean ||
        !_usesBranchPreviewResult(commit)) {
      return null;
    }
    final ours = comparison.merge.baseChangedFiles;
    if (ours.isEmpty) return null;
    if (ours.contains(file.path) || ours.contains(file.oldPath)) {
      final regions = _previewProximity(commit, file);
      return (
        label: regions.isEmpty ? '양쪽 수정' : '양쪽 수정 · 근접 ${regions.length}곳',
        bothSides: true,
      );
    }
    return (
      label: switch (file.status.isEmpty ? '' : file.status[0]) {
        'D' => '브랜치에서 삭제',
        'A' => '브랜치에서 추가',
        'R' || 'C' => '브랜치에서 이름 변경',
        _ => '브랜치에서 수정',
      },
      bothSides: false,
    );
  }

  /// Merge-result line spans where both sides edited within ten lines of each
  /// other. Empty outside the clean merge preview, and for files only one side
  /// touched.
  List<LineSpan> _previewProximity(GitCommit commit, GitFileChange file) {
    final comparison = _comparison;
    if (comparison == null ||
        _branchPreviewMode != BranchPreviewMode.merge ||
        _effectiveMergeStatus != MergeConflictStatus.clean ||
        !_usesBranchPreviewResult(commit)) {
      return const [];
    }
    return comparison.merge.proximity[file.path] ?? const [];
  }

  /// The regions themselves, under the file they belong to. Clicking one opens
  /// the same result diff a file row opens, positioned on the region.
  Widget? _previewProximityLine(GitCommit commit, GitFileChange file) {
    final regions = _previewProximity(commit, file);
    if (regions.isEmpty) return null;
    return Padding(
      key: Key('preview-proximity-${file.path}'),
      padding: const EdgeInsets.only(left: 34, right: 14, bottom: 7),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '양쪽 편집이 10줄 안에서 겹침',
            style: TextStyle(color: _palette.muted, fontSize: 10),
          ),
          for (final region in regions)
            InkWell(
              key: Key('preview-proximity-${file.path}-${region.startLine}'),
              borderRadius: BorderRadius.circular(4),
              onTap: () =>
                  _selectPreviewFile(commit, file.path, line: region.startLine),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _previewConflict.withValues(alpha: 0.10),
                  border: Border.all(
                    color: _previewConflict.withValues(alpha: 0.35),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_groupedNumber(region.startLine)}~'
                  '${_groupedNumber(region.endLine)}줄',
                  style: const TextStyle(
                    color: Color(0xFFFF9AA2),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The nearest line the loaded result diff actually draws. A region's first
  /// line is often a base-side edit the result diff never shows, and a number no
  /// row carries would leave the scroll target attached nowhere.
  static int? _nearestPreviewDiffLine(DiffDocument document, int line) {
    int? nearest;
    for (final hunk in document.hunks) {
      for (final diffLine in hunk.lines) {
        final number = diffLine.newNumber;
        if (number == null) continue;
        if (nearest == null || (number - line).abs() < (nearest - line).abs()) {
          nearest = number;
        }
      }
    }
    return nearest;
  }

  /// Scrolls the open result diff onto the line a pill asked for, once the diff
  /// itself has rendered. The diff builds its rows lazily, so a target below the
  /// first viewport only exists after paging down to it.
  void _revealPreviewDiffTarget(({String path, int line}) line) {
    final target = _previewDiffTargetKey.currentContext;
    if (target == null) {
      if (!_previewDiffScrollController.hasClients) return;
      final position = _previewDiffScrollController.position;
      final next = (position.pixels + position.viewportDimension).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((next - position.pixels).abs() < 0.5) return;
      position.jumpTo(next);
      _previewDiffRevealScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _previewDiffRevealScheduled = false;
        if (mounted) _revealPreviewDiffTarget(line);
      });
      return;
    }
    _previewDiffLineRevealed = line;
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        alignment: 0.2,
      ),
    );
  }

  Widget _previewProvenanceChip(
    String path,
    ({String label, bool bothSides}) provenance,
  ) {
    final color = provenance.bothSides ? _previewConflict : _palette.muted;
    return Container(
      key: Key('preview-provenance-$path'),
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: provenance.bothSides
            ? color.withValues(alpha: 0.16)
            : _palette.raised,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        provenance.label,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: provenance.bothSides ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _previewFileRow(GitCommit commit, GitFileChange file, bool selected) {
    final stats = [
      if ((file.additions ?? 0) > 0) '+${file.additions}',
      if ((file.deletions ?? 0) > 0) '-${file.deletions}',
    ].join(' ');
    final stateColor = switch (file.status.isEmpty ? '' : file.status[0]) {
      'D' => _deleted,
      'R' || 'C' => _renamed,
      '!' => _hash,
      _ => _main,
    };
    return SizedBox(
      key: selected ? _selectedPreviewFileKey : null,
      height: 34,
      child: InkWell(
        onTap: () => _selectPreviewFile(commit, file.path),
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? _palette.neutralChip : null,
            borderRadius: selected ? BorderRadius.circular(6) : null,
          ),
          child: Row(
            children: [
              Container(
                key: Key('preview-state-${file.path}'),
                width: 28,
                height: 20,
                alignment: Alignment.center,
                child: Text(
                  file.status,
                  maxLines: 1,
                  style: TextStyle(color: stateColor, fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _palette.text, fontSize: 12),
                ),
              ),
              if (_previewProvenance(commit, file) case final provenance?)
                _previewProvenanceChip(file.path, provenance),
              if (stats.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  stats,
                  style: TextStyle(color: _palette.muted, fontSize: 11),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewDiff(GitCommit commit, GitFileChange file) {
    final path = file.path;
    final key = _previewKey(commit);
    final future = _previewDiffs.putIfAbsent((sha: key, path: path), () {
      final comparison = _comparison;
      if (comparison == null || !_usesBranchPreviewResult(commit)) {
        return widget.repository.loadDiff(commit, file);
      }
      if (_branchPreviewHasConflict) {
        final session = _branchPreviewMode == BranchPreviewMode.merge
            ? _mergePreviewSession
            : _rebasePreviewSession;
        if (session is MergePreviewSession) {
          return session.loadConflictDiff(path);
        }
        if (session is RebasePreviewSession) {
          return session.loadConflictDiff(path);
        }
      }
      return widget.repository.loadDiffBetween(
        _branchPreviewRange!.from,
        _branchPreviewRange!.to,
        file,
      );
    });
    final comparison = _comparison;
    if (comparison == null || !_usesBranchPreviewResult(commit)) {
      final parent = commit.parents.isEmpty ? null : commit.parents.first;
      final parentLabel = parent == null
          ? '—'
          : parent.substring(0, math.min(7, parent.length));
      return _previewDiffView(
        future: future,
        file: file,
        status: commit.isWorkingTree
            ? 'WIP · diff'
            : 'commit ${commit.shortSha}',
        baseRef: parentLabel,
        baseSubject: parent == null ? '빈 트리' : '이전 상태',
        compareRef: commit.isWorkingTree ? 'WIP' : commit.shortSha,
        compareSubject: commit.isWorkingTree ? '작업 트리' : commit.subject,
        baseRole: '이전 상태',
        compareRole: '선택한 커밋',
      );
    }

    final baseCommits = comparison.commits
        .where((entry) => entry.side == BranchCommitSide.baseOnly)
        .map((entry) => entry.commit)
        .toList();
    final compareCommits = comparison.commits
        .where((entry) => entry.side == BranchCommitSide.compareOnly)
        .map((entry) => entry.commit)
        .toList();
    final base = baseCommits.isEmpty ? null : baseCommits.first;
    final compare =
        _rebasePreview?.currentCommit ??
        (compareCommits.isEmpty ? null : compareCommits.first);
    final mergeMode = _branchPreviewMode == BranchPreviewMode.merge;
    final conflict = _branchPreviewHasConflict;
    return _previewDiffView(
      future: future,
      file: file,
      status: conflict
          ? mergeMode
                ? '병합 충돌 1개 · ${comparison.compareRef} → ${comparison.baseRef}'
                : '현재 충돌 · ${compare?.subject ?? comparison.compareRef}'
          : '${mergeMode ? 'Merge' : 'Rebase'} 결과 · '
                '${comparison.compareRef} → ${comparison.baseRef}',
      baseRef: comparison.baseRef,
      baseSubject: base?.subject ?? '현재 상태',
      compareRef: comparison.compareRef,
      compareSubject: conflict
          ? compare?.subject ?? '적용할 변경'
          : '${mergeMode ? 'Merge' : 'Rebase'} 미리보기 결과',
      baseRole: '기준 브랜치',
      compareRole: conflict && _branchPreviewMode == BranchPreviewMode.rebase
          ? '적용 중'
          : conflict
          ? '비교 브랜치'
          : '가상 결과',
      conflict: conflict,
      showConflictChoices: conflict,
    );
  }

  Widget _previewDiffView({
    required Future<List<DiffLine>> future,
    required GitFileChange file,
    required String status,
    required String baseRef,
    required String baseSubject,
    required String compareRef,
    required String compareSubject,
    required String baseRole,
    required String compareRole,
    bool conflict = false,
    bool showConflictChoices = false,
  }) {
    final path = file.path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('branch-preview-diff-toolbar'),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _palette.surface,
            border: Border(bottom: BorderSide(color: _palette.border)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 80
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      Flexible(
                        child: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _palette.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: conflict ? _previewConflict : _deleted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            key: const Key('branch-preview-layout-switch'),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: _palette.background,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _previewDiffLayoutButton(
                                  key: const Key(
                                    'branch-preview-layout-unified',
                                  ),
                                  label: 'Unified',
                                  layout: DiffLayout.unified,
                                ),
                                _previewDiffLayoutButton(
                                  key: const Key(
                                    'branch-preview-layout-side-by-side',
                                  ),
                                  label: 'Side-by-side',
                                  layout: DiffLayout.sideBySide,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox.square(
                        dimension: 24,
                        child: IconButton(
                          key: const Key('preview-diff-close'),
                          tooltip: 'diff 닫기',
                          padding: EdgeInsets.zero,
                          onPressed: _closePreviewDiff,
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: _palette.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        Expanded(
          flex: showConflictChoices ? 2 : 1,
          child: FutureBuilder<List<DiffLine>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Could not load diff',
                    style: TextStyle(color: Color(0xFFF29AB2), fontSize: 12),
                  ),
                );
              }
              if (snapshot.data case final lines?) {
                final document = DiffDocument.fromLines(lines);
                final anchors = {
                  for (final hunk in document.hunks)
                    hunk.anchor.id: GlobalKey(),
                };
                final line = _previewDiffLineTarget?.path == path
                    ? _previewDiffLineTarget
                    : null;
                final nearest = line == null
                    ? null
                    : _nearestPreviewDiffLine(document, line.line);
                final lineTarget = nearest == null
                    ? null
                    : (oldLine: null, newLine: nearest);
                if (line != null &&
                    nearest != null &&
                    line != _previewDiffLineRevealed &&
                    !_previewDiffRevealScheduled) {
                  _previewDiffRevealScheduled = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _previewDiffRevealScheduled = false;
                    if (mounted) _revealPreviewDiffTarget(line);
                  });
                }
                final activeAnchor = conflict && document.hunks.isNotEmpty
                    ? document.hunks.first.anchor
                    : null;
                final titles = _previewDiffTitles(
                  baseRef: baseRef,
                  baseSubject: baseSubject,
                  compareRef: compareRef,
                  compareSubject: compareSubject,
                  baseRole: baseRole,
                  compareRole: compareRole,
                  sideBySide: _previewDiffLayout == DiffLayout.sideBySide,
                );
                return _previewDiffLayout == DiffLayout.unified
                    ? UnifiedPresentationView(
                        document: document,
                        activeAnchor: activeAnchor,
                        path: path,
                        wrapLines: false,
                        highlighter: _previewDiffHighlighter,
                        anchorKeys: anchors,
                        controller: _previewDiffScrollController,
                        scrollTarget: lineTarget,
                        scrollTargetKey: _previewDiffTargetKey,
                        showHunkHeaders: false,
                        compactRows: true,
                        currentMarkerColor: _previewConflict,
                        header: titles,
                      )
                    : SideBySidePresentationView(
                        document: document,
                        activeAnchor: activeAnchor,
                        oldPath: file.oldPath ?? path,
                        newPath: path,
                        wrapLines: false,
                        showOldSide: true,
                        highlighter: _previewDiffHighlighter,
                        anchorKeys: anchors,
                        controller: _previewDiffScrollController,
                        scrollTarget: lineTarget,
                        scrollTargetKey: _previewDiffTargetKey,
                        showHunkHeaders: false,
                        compactRows: true,
                        currentMarkerColor: _previewConflict,
                        header: titles,
                      );
              }
              return const Center(
                child: SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              );
            },
          ),
        ),
        if (showConflictChoices)
          Expanded(
            child: SingleChildScrollView(
              child: _branchPreviewConflictChoices(),
            ),
          ),
      ],
    );
  }

  Widget _previewDiffTitles({
    required String baseRef,
    required String baseSubject,
    required String compareRef,
    required String compareSubject,
    required String baseRole,
    required String compareRole,
    required bool sideBySide,
  }) {
    Widget title(String branch, String subject, String role) => Expanded(
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: _palette.panel,
          border: Border(right: BorderSide(color: _palette.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: branch,
                      style: TextStyle(
                        color: _palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' · $subject',
                      style: TextStyle(color: _palette.muted),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ),
            const SizedBox(width: 8),
            Text(role, style: TextStyle(color: _palette.muted, fontSize: 10)),
          ],
        ),
      ),
    );
    if (sideBySide) {
      return Container(
        key: const Key('branch-preview-side-titles'),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: _palette.border)),
        ),
        child: Row(
          children: [
            title(baseRef, baseSubject, baseRole),
            title(compareRef, compareSubject, compareRole),
          ],
        ),
      );
    }
    return Container(
      key: const Key('branch-preview-unified-title'),
      height: 30,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: _palette.panel,
        border: Border(bottom: BorderSide(color: _palette.border)),
      ),
      child: Text(
        '$baseRef · $baseSubject ← $compareRef · $compareSubject',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: _palette.muted, fontSize: 10),
      ),
    );
  }

  Widget _previewDiffLayoutButton({
    required Key key,
    required String label,
    required DiffLayout layout,
  }) => InkWell(
    key: key,
    onTap: () => setState(() => _previewDiffLayout = layout),
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _previewDiffLayout == layout
            ? _palette.neutralChip
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _palette.text,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  bool _acceptsFullDiffRouteEvents(_FullDiffRouteSession session) =>
      mounted &&
      identical(_fullDiffRouteSession, session) &&
      identical(widget.repository, session.repository) &&
      session.route?.isActive == true;

  bool _canFlushFullDiffPersistence(_FullDiffRouteSession session) =>
      mounted &&
      identical(_fullDiffRouteSession, session) &&
      identical(widget.repository, session.repository);

  void _forwardFullDiffPreferences(
    _FullDiffRouteSession session,
    FullDiffPreferences preferences,
  ) {
    if (!_acceptsFullDiffRouteEvents(session)) return;
    if (widget.onFullDiffPreferencesChanged case final callback?
        when _pendingFullDiffPreferences == null &&
            !_fullDiffPersistenceFlushScheduled) {
      callback(preferences);
      return;
    }
    _pendingFullDiffPreferences = preferences;
    _scheduleFullDiffPersistenceFlush();
  }

  void _forwardFullDiffColumnWidths(
    _FullDiffRouteSession session,
    FullDiffColumnWidths widths,
  ) {
    if (!_acceptsFullDiffRouteEvents(session)) return;
    if (widget.onFullDiffColumnWidthsChanged case final callback?
        when _pendingFullDiffColumnWidths == null &&
            !_fullDiffPersistenceFlushScheduled) {
      callback(widths);
      return;
    }
    _pendingFullDiffColumnWidths = widths;
    _scheduleFullDiffPersistenceFlush();
  }

  void _scheduleFullDiffPersistenceFlush() {
    final session = _fullDiffRouteSession;
    if (session == null ||
        _fullDiffPersistenceFlushScheduled ||
        (_pendingFullDiffPreferences == null &&
            _pendingFullDiffColumnWidths == null) ||
        (widget.onFullDiffPreferencesChanged == null &&
            widget.onFullDiffColumnWidthsChanged == null)) {
      return;
    }
    _fullDiffPersistenceFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fullDiffPersistenceFlushScheduled = false;
      if (!_canFlushFullDiffPersistence(session)) {
        _scheduleFullDiffPersistenceFlush();
        return;
      }

      final preferences = _pendingFullDiffPreferences;
      final preferencesCallback = widget.onFullDiffPreferencesChanged;
      if (preferences != null && preferencesCallback != null) {
        _pendingFullDiffPreferences = null;
        preferencesCallback(preferences);
      }

      if (!_canFlushFullDiffPersistence(session)) return;
      final widths = _pendingFullDiffColumnWidths;
      final widthsCallback = widget.onFullDiffColumnWidthsChanged;
      if (widths != null && widthsCallback != null) {
        _pendingFullDiffColumnWidths = null;
        widthsCallback(widths);
      }
    });
  }

  void _clearFullDiffRouteSession([_FullDiffRouteSession? session]) {
    if (session != null && !identical(_fullDiffRouteSession, session)) return;
    _fullDiffRouteSession = null;
    _pendingFullDiffPreferences = null;
    _pendingFullDiffColumnWidths = null;
    _fullDiffPersistenceFlushScheduled = false;
  }

  void _openFullDiff() {
    final commit = _selectedCommit!;
    if (widget.onOpenFullDiff case final callback?) {
      callback(commit);
      return;
    }
    final repository = widget.repository;
    final commits = List<GitCommit>.unmodifiable(_commits);
    final initialIndex = _commits.indexOf(commit);
    final initialPreferences =
        _pendingFullDiffPreferences ?? widget.fullDiffPreferences;
    final columnWidths =
        _pendingFullDiffColumnWidths ?? widget.fullDiffColumnWidths;
    final avatarService = widget.avatarService;
    final showRemoteAvatars = widget.showRemoteAvatars;
    final session = _FullDiffRouteSession(repository);
    late final MaterialPageRoute<void> route;
    route = MaterialPageRoute<void>(
      builder: (context) => DiffScreen(
        repository: repository,
        commits: commits,
        initialIndex: initialIndex,
        initialPreferences: initialPreferences,
        onPreferencesChanged: (preferences) =>
            _forwardFullDiffPreferences(session, preferences),
        columnWidths: columnWidths,
        onColumnWidthsChanged: (widths) =>
            _forwardFullDiffColumnWidths(session, widths),
        editorService: ExternalEditorService(repositoryRoot: repository.root),
        avatarService: avatarService,
        showRemoteAvatars: showRemoteAvatars,
      ),
    );
    session.route = route;
    _fullDiffRouteSession = session;
    Navigator.of(context).push(route);
  }
}

class _FullDiffRouteSession {
  _FullDiffRouteSession(this.repository);

  final GitRepository repository;
  Route<void>? route;
}

/// The app's wordmark: one soft pastel per letter, legible on the dark bar, with
/// a small cloud badge tucked over the final letter.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.fontSize, super.key});

  final double fontSize;

  static const letters = <(String, Color)>[
    ('Y', Color(0xFFFFB3BA)),
    ('o', Color(0xFFFFDFBA)),
    ('g', Color(0xFFFFFFB3)),
    ('i', Color(0xFFBAFFC9)),
    ('t', Color(0xFFBAE1FF)),
  ];

  TextStyle get _style => TextStyle(
    fontFamily: 'DancingScript',
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
  );

  /// Where the 'Y' ends, so the badge can float in the space the lowercase
  /// letters leave above them.
  double get _afterY => (TextPainter(
    text: TextSpan(text: letters.first.$1, style: _style),
    textDirection: TextDirection.ltr,
  )..layout()).width;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Text.rich(
        TextSpan(
          children: [
            for (final (glyph, color) in letters)
              TextSpan(
                text: glyph,
                style: TextStyle(color: color),
              ),
          ],
        ),
        style: _style,
      ),
      Positioned(
        left: _afterY + fontSize * 0.03,
        // Above the x-height, below the Y's cap: the lowercase tops stay clear.
        top: fontSize * 0.06,
        child: CustomPaint(
          key: const Key('wordmark-cloud'),
          size: Size(fontSize * 0.92, fontSize * 0.54),
          painter: const _CloudBadgePainter(),
        ),
      ),
    ],
  );
}

/// The little blue cloud with wind streaks that rides the wordmark. Drawn at a
/// nominal 24x14 and scaled by whatever size the wordmark asks for.
class _CloudBadgePainter extends CustomPainter {
  const _CloudBadgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    Offset at(double x, double y) => Offset(x * unit, y * unit);

    final cloud = Path()
      ..addOval(Rect.fromCircle(center: at(5, 9), radius: 3.2 * unit))
      ..addOval(Rect.fromCircle(center: at(9, 6.6), radius: 4.4 * unit))
      ..addOval(Rect.fromCircle(center: at(13, 8.6), radius: 3.4 * unit))
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2 * unit, 8.4 * unit, 12.4 * unit, 3.6 * unit),
          Radius.circular(1.8 * unit),
        ),
      );
    canvas.drawPath(
      cloud,
      Paint()
        ..isAntiAlias = true
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCFE8FF), Color(0xFF8EC9FF)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final wind = Paint()
      ..color = const Color(0xFFBAE1FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * unit
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(at(16.6, 4.8), at(19.8, 4.8), wind);
    canvas.drawLine(at(16.8, 10.6), at(19.2, 10.6), wind);
    // The long middle streak curls up at the tail.
    canvas.drawPath(
      Path()
        ..moveTo(17 * unit, 7.7 * unit)
        ..lineTo(21.4 * unit, 7.7 * unit)
        ..quadraticBezierTo(23.2 * unit, 7.7 * unit, 22.4 * unit, 5.9 * unit),
      wind,
    );
  }

  @override
  bool shouldRepaint(_CloudBadgePainter oldDelegate) => false;
}

class _HoverBuilder extends StatefulWidget {
  const _HoverBuilder({required this.builder, this.enabled = true});

  final Widget Function(bool hovered) builder;
  final bool enabled;

  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
    onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
    onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
    child: widget.builder(_hovered),
  );
}

/// A keycap that also works as a button — the Enter chip runs the same toggle the
/// Enter key does.
class _KeyCap extends StatefulWidget {
  const _KeyCap({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<_KeyCap> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: Key('keycap-${widget.label}'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? palette.selectedRow : palette.raised,
            border: Border.all(
              color: _hovered ? palette.muted : palette.border,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            widget.label,
            style: TextStyle(color: palette.text, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _ShowDiffButton extends StatelessWidget {
  const _ShowDiffButton({
    required this.onTap,
    this.height = 40,
    this.labelSize = 13,
    this.shortcutSize = 10,
    super.key,
  });

  static const green = Color(0xFF2EA043);
  static const hoverGreen = Color(0xFF3FB950);

  final VoidCallback? onTap;
  final double height;
  final double labelSize;
  final double shortcutSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    final ink = onTap == null ? palette.muted : AvatarService.onColor(green);
    return _HoverBuilder(
      enabled: onTap != null,
      builder: (hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: height * 0.3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap == null
                ? palette.raised
                : hovered
                ? hoverGreen
                : green,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Full Diff',
                style: TextStyle(
                  color: ink,
                  fontSize: labelSize,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              Text(
                shortcutLabel('D'),
                style: TextStyle(
                  color: ink.withValues(alpha: 0.75),
                  fontSize: shortcutSize,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaneToggleIconPainter extends CustomPainter {
  const _PaneToggleIconPainter({required this.opens, required this.color});

  final bool opens;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
        const Radius.circular(3.5),
      ),
      paint,
    );
    final dividerX = size.width * (opens ? 0.36 : 0.25);
    canvas.drawLine(
      Offset(dividerX, 3.5),
      Offset(dividerX, size.height - 3.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PaneToggleIconPainter oldDelegate) =>
      oldDelegate.opens != opens || oldDelegate.color != color;
}

/// Copies a ref name and answers with a check for a moment, so the click has
/// feedback without a snackbar.
class _CopyButton extends StatefulWidget {
  const _CopyButton({
    required this.text,
    required this.color,
    this.slot = 'copy-ref',
  });

  final String text;
  final Color color;

  /// Names this button apart from the other copier for the same ref: the modal's
  /// item and the status bar can both be on screen at once.
  final String slot;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  Timer? _reset;
  var _copied = false;
  var _hovered = false;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: Key('${widget.slot}-${widget.text}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_copy()),
        child: Icon(
          _copied ? Icons.check : Icons.copy_outlined,
          size: 16,
          color: _copied
              ? widget.color
              : _hovered
              ? palette.text
              : palette.muted,
        ),
      ),
    );
  }
}

/// The message the merge commit an apply is about to write will carry. Prefilled
/// from the settings template; confirming pops the text exactly as edited, and
/// Escape or 취소 pops nothing at all — the apply itself is off.
///
/// Its own surface rather than [YogitAlert]'s: the mockup draws a wider card
/// with an editor in it, radius 12, and the preview's purple on 적용.
class _CommitMessageDialog extends StatefulWidget {
  const _CommitMessageDialog({
    required this.lead,
    required this.emphasis,
    required this.message,
    required this.templated,
  });

  /// The context line, split where the mockup colors it: quiet up to [lead],
  /// then [emphasis] in the preview's purple.
  final String lead;
  final String emphasis;
  final String message;

  /// Whether [message] came from the settings template or, with that emptied,
  /// from git's own wording — the helper line names whichever filled the box.
  final bool templated;

  @override
  State<_CommitMessageDialog> createState() => _CommitMessageDialogState();
}

class _CommitMessageDialogState extends State<_CommitMessageDialog> {
  late final _message = TextEditingController(text: widget.message);

  /// 무엇이 채웠는지 그대로 말한다 — 템플릿을 비웠으면 git 표준 메시지가 채운
  /// 것이고, Reviewed-by 줄이 없으면 그 줄을 설명할 일도 없다.
  String get _prefillHelp {
    final source = widget.templated
        ? '설정의 기본 메시지 템플릿으로 채워졌습니다'
        : 'git 표준 메시지로 채워졌습니다';
    return widget.message.contains('Reviewed-by:')
        ? '$source · Reviewed-by는 이 저장소의 커밋 프로필 이름입니다'
        : source;
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    // An empty message would write a subject-less merge commit, so it is the one
    // edit the dialog refuses; the helper line says so while it is refusing.
    final blank = _message.text.trim().isEmpty;
    // 시안의 CSS 그대로: 440 너비, 16/16/14 패딩, 줄 사이 10, 편집기는 88부터.
    return Center(
      child: Material(
        color: palette.surface,
        elevation: 24,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF48484A)),
        ),
        child: SizedBox(
          width: 440,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '실제 적용하기',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    text: widget.lead,
                    children: [
                      TextSpan(
                        text: widget.emphasis,
                        style: const TextStyle(
                          color: _previewPurple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Text(
                  '커밋 메시지',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 10.5,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  key: const Key('branch-apply-message'),
                  controller: _message,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 10,
                  cursorColor: _previewPurple,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 11.5,
                    height: 1.55,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: palette.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    // 편집기는 포커스를 받아도 테두리가 변하지 않는다 — 커서가 말해 준다.
                    border: _editorBorder(palette),
                    enabledBorder: _editorBorder(palette),
                    focusedBorder: _editorBorder(palette),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  blank
                      ? '비워서 적용할 수는 없습니다 · Esc 또는 취소로 적용 자체를 중단합니다'
                      : _prefillHelp,
                  style: TextStyle(color: palette.muted, fontSize: 10),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('branch-apply-cancel'),
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.text,
                        backgroundColor: palette.raised,
                        side: const BorderSide(color: Color(0xFF48484A)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        visualDensity: VisualDensity.standard,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                      ),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('branch-apply-confirm'),
                      onPressed: blank
                          ? null
                          : () => Navigator.pop(context, _message.text),
                      style: FilledButton.styleFrom(
                        foregroundColor: const Color(0xFFFFF4FF),
                        backgroundColor: const Color(0xFF594576),
                        disabledForegroundColor: const Color(
                          0xFFFFF4FF,
                        ).withValues(alpha: 0.4),
                        disabledBackgroundColor: const Color(
                          0xFF594576,
                        ).withValues(alpha: 0.35),
                        side: const BorderSide(color: Color(0xFF9D79D0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        visualDensity: VisualDensity.standard,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                      ),
                      child: const Text('적용'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _editorBorder(TimelineThemePalette palette) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: palette.border),
      );
}

/// Rebuilds one row only when *its* selected or hovered state flips. Every row
/// listens, but a notification that does not change this row's pair is dropped
/// before it can rebuild the subtree.
class _RowStateScope extends StatefulWidget {
  const _RowStateScope({
    required this.index,
    required this.selectedIndex,
    required this.hoverIndex,
    required this.builder,
  });

  final int index;
  final ValueListenable<int> selectedIndex;
  final ValueListenable<int> hoverIndex;
  final Widget Function(bool selected, bool hovered) builder;

  @override
  State<_RowStateScope> createState() => _RowStateScopeState();
}

class _RowStateScopeState extends State<_RowStateScope> {
  late bool _selected = widget.selectedIndex.value == widget.index;
  late bool _hovered = widget.hoverIndex.value == widget.index;

  @override
  void initState() {
    super.initState();
    widget.selectedIndex.addListener(_sync);
    widget.hoverIndex.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant _RowStateScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list recycles elements across indexes, so re-read without a rebuild.
    if (oldWidget.index != widget.index) {
      _selected = widget.selectedIndex.value == widget.index;
      _hovered = widget.hoverIndex.value == widget.index;
    }
  }

  @override
  void dispose() {
    widget.selectedIndex.removeListener(_sync);
    widget.hoverIndex.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final selected = widget.selectedIndex.value == widget.index;
    final hovered = widget.hoverIndex.value == widget.index;
    if (selected == _selected && hovered == _hovered) return;
    setState(() {
      _selected = selected;
      _hovered = hovered;
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(_selected, _hovered);
}

/// What the selected rebase landing leaves behind. Without [mergeCommit] the
/// replayed commits carry the base rail straight on, because rebasing onto the
/// base branch is that line continuing; with it they ride a dashed arc onto the
/// merge commit the base branch lands on. Drawn in a 560 wide design space and
/// stretched to whatever the pane gives it.
class RebaseMergeResultPainter extends CustomPainter {
  const RebaseMergeResultPainter({
    required this.commitCount,
    required this.baseLabel,
    required this.mergeCommit,
    required this.railColor,
    required this.mutedColor,
  });

  final int commitCount;
  final String baseLabel;
  final bool mergeCommit;
  final Color railColor;
  final Color mutedColor;

  /// Past a dozen the dots would touch, so the label carries the exact count.
  static const maxDots = 12;
  static const _designWidth = 560.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    double x(double design) => design / _designWidth * size.width;
    void label(String text, double centerX, double top, Color color) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
        // 좁은 pane에서도 한 줄로 남아야 선과 점 위로 겹치지 않는다.
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width);
      painter.paint(
        canvas,
        Offset(
          (centerX - painter.width / 2).clamp(0, size.width - painter.width),
          top,
        ),
      );
    }

    // 머지 커밋이 없으면 기준 브랜치 선이 재배치된 커밋으로 그대로 이어지니
    // 회색 구간은 기준 tip에서 끝난다.
    canvas.drawLine(
      Offset(x(20), 58),
      Offset(x(mergeCommit ? 540 : 130), 58),
      Paint()
        ..color = railColor
        ..strokeWidth = 2,
    );
    final dot = Paint()..color = mutedColor;
    canvas.drawCircle(Offset(x(60), 58), 5, dot);
    canvas.drawCircle(Offset(x(130), 58), 5, dot);
    label(baseLabel, x(95), 68, mutedColor);

    final path = mergeCommit
        ? (Path()
            ..moveTo(x(130), 58)
            ..cubicTo(x(170), 58, x(170), 26, x(210), 26)
            ..lineTo(x(400), 26)
            ..cubicTo(x(450), 26, x(450), 58, x(490), 58))
        : (Path()
            ..moveTo(x(130), 58)
            ..lineTo(x(470), 58));
    final rail = Paint()
      ..color = _previewPurple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 9) {
        canvas.drawPath(
          metric.extractPath(start, math.min(start + 5, metric.length)),
          rail,
        );
      }
    }

    final dots = math.min(commitCount, maxDots);
    final replayed = Paint()..color = _previewPurple;
    final (from, to, y) = mergeCommit
        ? (210.0, 400.0, 26.0)
        : (140.0, 460.0, 58.0);
    for (var index = 0; index < dots; index++) {
      final at = from + (to - from) * (index + 1) / (dots + 1);
      canvas.drawCircle(Offset(x(at), y), 4.5, replayed);
    }

    if (!mergeCommit) {
      label(
        '재배치된 커밋 $commitCount개 — $baseLabel 선 위에 그대로 이어짐',
        x(300),
        34,
        _previewPurple,
      );
      label('브랜치 tip', x(505), 51, mutedColor);
      return;
    }
    label('재배치된 커밋 $commitCount개', x(305), 2, _previewPurple);
    canvas.drawCircle(
      Offset(x(490), 58),
      6,
      Paint()..color = _previewPurplePanel,
    );
    canvas.drawCircle(
      Offset(x(490), 58),
      6,
      Paint()
        ..color = _previewPurple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    label('머지 커밋', x(490), 70, _previewPurple);
  }

  @override
  bool shouldRepaint(covariant RebaseMergeResultPainter oldDelegate) =>
      oldDelegate.commitCount != commitCount ||
      oldDelegate.baseLabel != baseLabel ||
      oldDelegate.mergeCommit != mergeCommit ||
      oldDelegate.railColor != railColor ||
      oldDelegate.mutedColor != mutedColor;
}

class RebaseMappingPainter extends CustomPainter {
  const RebaseMappingPainter({
    required this.rows,
    this.entries = const [],
    this.selectedIndex,
    required this.mappings,
    required this.rowIndex,
    required this.laneSpacing,
    required this.compact,
  }) : super(repaint: selectedIndex);

  final List<GraphRow> rows;
  final List<TimelineEntry> entries;
  final ValueListenable<int>? selectedIndex;
  final List<RebaseGraphMapping> mappings;
  final int rowIndex;
  final double laneSpacing;
  final bool compact;

  double _laneX(int lane) => compact
      ? CommitGraphPainter.laneInset
      : CommitGraphPainter.laneInset + lane * laneSpacing;

  String? get _focusedSha {
    final index = selectedIndex?.value;
    if (index == null || index < 0 || index >= entries.length) return null;
    final entry = entries[index];
    return entry.rowIndex < 0 ? null : entry.row.commit.sha;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (compact || size.isEmpty || rowIndex < 0 || rowIndex >= rows.length) {
      return;
    }
    final deepest = rows.fold<int>(
      0,
      (value, row) => math.max(value, row.maxLane),
    );
    final firstRouteX = _laneX(deepest + 1);
    final routeSpacing = laneSpacing / 2;
    final fitsAll = mappings.every(
      (mapping) =>
          firstRouteX + mapping.routeLane * routeSpacing <= size.width - 1,
    );
    final visibleMappings = fitsAll
        ? mappings
        : mappings
              .where(
                (mapping) =>
                    mapping.originalSha == _focusedSha ||
                    mapping.rewrittenSha == _focusedSha,
              )
              .take(1);
    final centerY = size.height / 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final mapping in visibleMappings) {
      final top = math.min(mapping.rewrittenRow, mapping.originalRow);
      final bottom = math.max(mapping.rewrittenRow, mapping.originalRow);
      if (rowIndex < top || rowIndex > bottom) continue;
      final routeX = fitsAll
          ? firstRouteX + mapping.routeLane * routeSpacing
          : math.min(firstRouteX, size.width - 1);
      final rewrittenX = _laneX(rows[mapping.rewrittenRow].lane);
      final originalX = _laneX(rows[mapping.originalRow].lane);
      final path = Path();
      if (rowIndex == mapping.rewrittenRow) {
        path
          ..moveTo(routeX, size.height + 1)
          ..lineTo(routeX, centerY + 6)
          ..quadraticBezierTo(routeX, centerY, routeX - 6, centerY)
          ..lineTo(rewrittenX + CommitGraphPainter.avatarDiameter / 2, centerY);
      } else if (rowIndex == mapping.originalRow) {
        path
          ..moveTo(originalX + CommitGraphPainter.avatarDiameter / 2, centerY)
          ..lineTo(routeX - 6, centerY)
          ..quadraticBezierTo(routeX, centerY, routeX, centerY - 6)
          ..lineTo(routeX, -1);
      } else {
        path
          ..moveTo(routeX, -1)
          ..lineTo(routeX, size.height + 1);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = mapping.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (rowIndex == mapping.rewrittenRow) {
        final tip = Offset(
          rewrittenX + CommitGraphPainter.avatarDiameter / 2,
          centerY,
        );
        final arrow = Path()
          ..moveTo(tip.dx + 5, tip.dy - 4)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(tip.dx + 5, tip.dy + 4);
        canvas.drawPath(
          arrow,
          Paint()
            ..color = mapping.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RebaseMappingPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.entries != entries ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.mappings != mappings ||
      oldDelegate.rowIndex != rowIndex ||
      oldDelegate.laneSpacing != laneSpacing ||
      oldDelegate.compact != compact;
}

/// Draws one row of the commit graph: pass-through rails, the rounded lane
/// curves into parent lanes, and the row's own node.
class CommitGraphPainter extends CustomPainter {
  CommitGraphPainter({
    required this.row,
    required this.selected,
    required this.committerColor,
    this.previous,
    this.committersBySha = const {},
    this.laneSpacing = defaultLaneSpacing,
    this.compact = false,
    this.refConnector = false,
    this.passThrough = false,
    this.dashedLanes = const {},
    this.previousDashedLanes = const {},
    this.previewRailColor,
    this.previewMergeArrow = false,
    this.outgoingRailColor,
    this.backgroundColor = const Color(0xFF1C1C1E),
    this.selectedRowColor = const Color(0xFF234D72),
  }) : baseBranchColor = AvatarService.baseBranchColor;

  static const laneInset = 28.0;
  static const defaultLaneSpacing = 30.0;
  static const previewLaneSpacing = 49.0;
  static const railWidth = 2.0;
  static const previewRailWidth = 1.0;
  static const avatarDiameter = 22.0;
  static const hashRailClearance = 3.0;

  /// Stage 3: at or below this cell width the graph collapses to one lane.
  static const compactWidth = 56.0;

  /// Stage 2 floor.
  static const minLaneSpacing = 12.0;

  /// Half the node avatar plus the required gap before the hash column's rail.
  static const nodeExtent = avatarDiameter / 2 + hashRailClearance;

  /// Below this spacing the graph node shows the small avatar stack.
  static const compressedAvatarSpacing = 22.0;

  /// The narrowest cell that still shows every node whole. Empty space right of
  /// it clips away before any lane moves.
  static double contentWidth(
    int deepestLane, {
    double laneSpacing = defaultLaneSpacing,
  }) => laneInset + deepestLane * laneSpacing + nodeExtent;

  /// Stage 1 (the cell still holds the rightmost node) keeps
  /// [defaultLaneSpacing]; stage 2 squeezes the lanes so that node stays just
  /// inside the cell.
  static double spacingFor(
    double width,
    int deepestLane, {
    double maxLaneSpacing = defaultLaneSpacing,
  }) {
    if (width >= contentWidth(deepestLane, laneSpacing: maxLaneSpacing)) {
      return maxLaneSpacing;
    }
    return ((width - laneInset - nodeExtent) / math.max(deepestLane, 1)).clamp(
      minLaneSpacing,
      maxLaneSpacing,
    );
  }

  /// Rails are opaque.
  static const railOpacity = 1.0;
  static const connectorWidth = 1.0;
  static const avatarRadius = 11.0;
  static const refArrowGap = 4.0;
  static const refArrowLength = 7.0;
  static const refArrowHalfHeight = 5.0;
  static const nodeRadius = 6.0;
  static const wipNodeRadius = 8.0;
  static const wipNodeDash = 2.5;

  /// Every transition turns on one quarter arc of this radius beside the node it
  /// belongs to, so the horizontal run into or out of that node stays long and
  /// readable.
  static const cornerRadius = 8.0;

  final GraphRow row;
  final bool selected;
  final Color backgroundColor;
  final Color selectedRowColor;
  final Color baseBranchColor;

  /// The color of the branch line this row's node sits on: `row.branch` through
  /// the settings palette. Named for history — nothing here is per-committer.
  final Color committerColor;

  /// The row above. A lane transition sweeps a full row height, so its arrival
  /// half belongs to this row's cell and is derived from [previous].
  final GraphRow? previous;
  final Map<String, GitIdentity> committersBySha;
  final double laneSpacing;

  /// Stage 3: every lane collapses onto [laneInset] and only the row's own rail
  /// and node survive.
  final bool compact;

  /// Whether this row shows ref chips, which the cell to the left resolves from
  /// both `for-each-ref` tips and the log decorations.
  final bool refConnector;

  /// A date heading: the rails and the arriving sweeps run through it, but it
  /// owns no node, no selected band and no ref connector.
  final bool passThrough;
  final Set<int> dashedLanes;
  final Set<int> previousDashedLanes;

  /// Whether this row is a merge preview's virtual commit. Its dashed second
  /// parent edge then ends in an arrowhead, so the line reads as the compare
  /// branch arriving at the merge rather than leaving it.
  final bool previewMergeArrow;
  final Color? previewRailColor;
  final Color? outgoingRailColor;

  bool isDashedLane(int lane) => dashedLanes.contains(lane);
  bool isDashedAbove(int lane) =>
      isDashedLane(lane) || previousDashedLanes.contains(lane);

  /// A lane movement is a preview line when the lane it LEAVES is dashed;
  /// [above] asks the row that started it. The lane it arrives in is never
  /// asked — a real branch converging on a lane the preview borrows is still
  /// real history and keeps its solid rail.
  bool isDashedTransition(LaneTransition transition, {bool above = false}) =>
      (above ? previousDashedLanes : dashedLanes).contains(transition.from);

  double laneX(int lane) =>
      compact ? laneInset : laneInset + lane * laneSpacing;

  double get refMarkerRadius {
    if (row.commit.isWorkingTree) return wipNodeRadius;
    if (showsMergeDot) return nodeRadius;
    return avatarRadius;
  }

  double get refArrowTipX => laneX(row.lane) - refMarkerRadius - refArrowGap;

  Path refArrowheadPath(double centerY) {
    final tipX = refArrowTipX;
    return Path()
      ..moveTo(tipX - refArrowLength, centerY - refArrowHalfHeight)
      ..lineTo(tipX, centerY)
      ..lineTo(tipX - refArrowLength, centerY + refArrowHalfHeight);
  }

  /// The arrowhead is stroked at the dashed rail's own weight, not the solid
  /// rail's: at [railWidth] the head came out twice as heavy as the line it
  /// closes and as every other arrow in the graph.
  Paint previewMergeArrowPaint() => Paint()
    ..color = previewRailColor ?? committerColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = previewRailWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// The arrowhead closing the dashed merge edge, or null when this row has no
  /// such edge. The tip sits one node-radius plus a gap from the node center,
  /// on the side the edge leaves toward, and points back at the node.
  Path? previewMergeArrowheadPath(double centerY) {
    if (!previewMergeArrow) return null;
    final edge = row.transitions
        .where(
          (transition) =>
              transition.from == row.lane && isDashedLane(transition.to),
        )
        .firstOrNull;
    if (edge == null) return null;
    // Which way the edge leaves decides which way the head points.
    final direction = laneX(edge.to) > laneX(edge.from) ? 1.0 : -1.0;
    final tipX = laneX(row.lane) + direction * (nodeRadius + refArrowGap);
    final baseX = tipX + direction * refArrowLength;
    return Path()
      ..moveTo(baseX, centerY - refArrowHalfHeight)
      ..lineTo(tipX, centerY)
      ..lineTo(baseX, centerY + refArrowHalfHeight);
  }

  /// A line being born out of this row's node: the second-or-later parent edge of
  /// a merge. Everything else is an existing line moving — a foreign column
  /// converging on its parent, or this row's own first-parent tail. Color and
  /// geometry both hang off this one question.
  static bool isMergeEdge(GraphRow row, LaneTransition transition) =>
      transitionBendsAtSource(row, transition);

  /// The branch line a sweep belongs to, so a whole line keeps one color:
  /// a foreign column converging on its parent stays its own line's color, a
  /// commit's first-parent tail stays the commit's, and only a merge edge to a
  /// further parent takes the line it lands in. Null falls back to the sha color.
  static int? transitionBranch(GraphRow row, LaneTransition transition) {
    if (transition.from != row.lane) {
      return row.activeLaneBranches[transition.from];
    }
    return isMergeEdge(row, transition)
        ? row.nextLaneBranches[transition.to]
        : row.branch;
  }

  /// The single rail stage 3 paints, colored by this row's committer.
  ({double top, double bottom}) compactRail(Size size) => (
    top: (previous?.nextLanes.isNotEmpty ?? false) ? 0.0 : size.height / 2,
    bottom: row.nextLanes.isEmpty ? size.height / 2 : size.height,
  );

  /// The straight vertical rails [row] hands down past its node center, keyed by
  /// lane. A rail that moves — a branch, a merge, or a git-style collapse slide —
  /// is left to its transition path, and so is a lane a movement lands in that
  /// carried no rail of its own.
  static Set<int> railsBelow(GraphRow row) {
    final departing = {
      for (final transition in row.transitions) transition.from,
    };
    final joining = {
      for (final transition in row.transitions)
        if (!transitionBendsAtSource(row, transition)) transition.from,
    };
    final arriving = {for (final transition in row.transitions) transition.to};
    return {
      for (final lane in row.nextLanes)
        if (lane == row.lane
            // Keep the first-parent rail when another branch joins it. A lane
            // filled only by a collapsing slide remains owned by the curve.
            ? !joining.contains(lane) &&
                  (!arriving.contains(lane) ||
                      (row.parentLanes.isNotEmpty &&
                          row.parentLanes.first == lane))
            : row.activeLanes.contains(lane) && !departing.contains(lane))
          lane,
    };
  }

  /// True when a rail reaches this row vertically in [lane]. A branch tip starts
  /// its lane here and an arriving curve owns its own top half, so neither gets
  /// a straight segment above the node.
  bool continuesFromAbove(int lane) {
    if (previous case final previous?) {
      return railsBelow(previous).contains(lane);
    }
    return false;
  }

  /// Straight vertical rail segments this row paints, keyed by lane. A lane that
  /// arrives or departs on a curve gets no straight segment over that half, so
  /// the curve is never overdrawn.
  Map<int, ({double top, double bottom})> laneVerticals(Size size) {
    final centerY = size.height / 2;
    final below = railsBelow(row);
    final verticals = <int, ({double top, double bottom})>{};
    for (final lane in {...row.activeLanes, ...row.nextLanes}) {
      final top = continuesFromAbove(lane) ? 0.0 : centerY;
      final bottom = below.contains(lane) ? size.height : centerY;
      if (bottom > top) verticals[lane] = (top: top, bottom: bottom);
    }
    return verticals;
  }

  /// Merge commits replace the avatar stack with a filled lane-colored dot.
  bool get showsMergeDot =>
      !row.commit.isWorkingTree && row.commit.parents.length >= 2;

  Rect selectedBandRect(Size size) =>
      Rect.fromLTRB(laneX(row.lane), 0, size.width, size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    if (selected && !passThrough) {
      canvas.drawRect(
        selectedBandRect(size),
        Paint()..color = committerColor.withValues(alpha: 0.22),
      );
    }

    if (compact) {
      // Stage 3: one rail in this row's committer color, no lanes, no curves.
      final rail = compactRail(size);
      void draw(double top, double bottom, {required bool dashed}) {
        if (bottom <= top) return;
        final paint = Paint()
          ..color = dashed ? previewRailColor ?? committerColor : committerColor
          ..strokeWidth = dashed ? previewRailWidth : railWidth
          ..strokeCap = StrokeCap.round;
        _drawVerticalRail(
          canvas,
          Offset(laneInset, top),
          Offset(laneInset, bottom),
          paint,
          dashed: dashed,
        );
      }

      draw(
        rail.top,
        math.min(rail.bottom, centerY),
        dashed: isDashedAbove(row.lane),
      );
      draw(
        math.max(rail.top, centerY),
        rail.bottom,
        dashed: isDashedLane(row.lane),
      );
    } else {
      // Halves are painted apart: above the node a lane carries the rail it
      // waits for, below it the rail it hands down.
      for (final entry in laneVerticals(size).entries) {
        final x = laneX(entry.key);
        if (entry.value.top < centerY) {
          final dashed = isDashedAbove(entry.key);
          final paint = _railPaint(
            row.activeLaneBranches[entry.key],
            row.activeLaneShas[entry.key],
            dashed: dashed,
          );
          _drawVerticalRail(
            canvas,
            Offset(x, entry.value.top),
            Offset(x, centerY),
            paint,
            dashed: dashed,
          );
        }
        if (entry.value.bottom > centerY) {
          final dashed = isDashedLane(entry.key);
          final paint = _railPaint(
            row.nextLaneBranches[entry.key],
            row.nextLaneShas[entry.key],
            dashed: dashed,
            colorOverride: entry.key == row.lane ? outgoingRailColor : null,
          );
          _drawVerticalRail(
            canvas,
            Offset(x, centerY),
            Offset(x, entry.value.bottom),
            paint,
            dashed: dashed,
          );
        }
      }

      // Arrival halves of the movements the row above started, then this row's
      // own departures. Every lane movement is a transition, so the two lists
      // are the whole story.
      if (previous case final previous?) {
        for (final transition in previous.transitions) {
          final dashed = isDashedTransition(transition, above: true);
          _drawRailPath(
            canvas,
            transitionPath(
              transition.from,
              transition.to,
              centerY - size.height,
              size,
              // Classified against the row that started it, so the arrival half
              // repeats its departure half's shape and color exactly.
              bendEarly: isMergeEdge(previous, transition),
            ),
            _railPaint(
              transitionBranch(previous, transition),
              transition.sha,
              dashed: dashed,
            ),
            dashed: dashed,
          );
        }
      }
      for (final transition in row.transitions) {
        final dashed = isDashedTransition(transition);
        _drawRailPath(
          canvas,
          transitionPath(
            transition.from,
            transition.to,
            centerY,
            size,
            bendEarly: isMergeEdge(row, transition),
          ),
          _railPaint(
            transitionBranch(row, transition),
            transition.sha,
            dashed: dashed,
          ),
          dashed: dashed,
        );
      }
    }
    if (passThrough) return;
    final nodeX = laneX(row.lane);
    if (previewMergeArrowheadPath(centerY) case final head?) {
      canvas.drawPath(head, previewMergeArrowPaint());
    }
    if (refConnector) {
      final connectorPaint = Paint()
        ..color = committerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = connectorWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawLine(
        Offset(0, centerY),
        Offset(refArrowTipX, centerY),
        connectorPaint,
      );
      canvas.drawPath(refArrowheadPath(centerY), connectorPaint);
    }
    _drawNode(canvas, Offset(nodeX, centerY));
  }

  /// The node glyph: a dashed ring for the working tree, a filled dot for a
  /// merge, and nothing for a plain commit — its avatar stack sits on top.
  void _drawNode(Canvas canvas, Offset center) {
    if (row.commit.isWorkingTree) {
      _drawWorkingTreeNode(canvas, center);
    } else if (showsMergeDot) {
      canvas.drawCircle(center, nodeRadius, Paint()..color = committerColor);
    }
  }

  /// The working tree ring takes the color of the branch line it sits on, which
  /// for the working tree row is the line `HEAD` is on.
  Color get workingTreeRingColor {
    final branch =
        row.nextLaneBranches[row.lane] ?? row.activeLaneBranches[row.lane];
    return branch == null
        ? AvatarService.color(
            committersBySha[row.nextLaneShas[row.lane] ??
                    row.activeLaneShas[row.lane]] ??
                row.commit.committer,
          )
        : AvatarService.branchColor(branch);
  }

  /// The node fill hides the rail behind it, so it has to match the row it sits
  /// on rather than the global background.
  Color get nodeFillColor => selected ? selectedRowColor : backgroundColor;

  /// The working tree node is a dashed ring, so it reads as pending next to the
  /// avatars that mark real commits.
  void _drawWorkingTreeNode(Canvas canvas, Offset center) {
    canvas.drawCircle(center, wipNodeRadius, Paint()..color = nodeFillColor);
    drawDashedRing(
      canvas,
      center,
      wipNodeRadius,
      Paint()
        ..color = workingTreeRingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = railWidth
        ..strokeCap = StrokeCap.round,
      wipNodeDash,
    );
  }

  /// One lane transition, spanning a row height from a node center at [startY] to
  /// the next row's center. Both rows paint the same path — the child from its own
  /// center, the next row with [startY] a row height above its center — so the
  /// halves meet exactly.
  ///
  /// Each kind turns on a single [cornerRadius] quarter arc, horizontal where it
  /// meets its node, so the line reads as entering or leaving that node sideways:
  ///
  /// * [bendEarly] — a line being born runs flat out of its source's side, then
  ///   arcs down into the vertical of its new column.
  /// * otherwise — a line joining its parent runs down its own column, arcs onto
  ///   the parent's own level, and runs flat into the dot from the side. Nothing
  ///   rides the parent's rail, and the dying branch leaves no stub.
  ///
  /// The flat run carries whatever distance the corner does not.
  Path transitionPath(
    int from,
    int to,
    double startY,
    Size size, {
    bool bendEarly = false,
  }) {
    final x0 = laneX(from);
    final x1 = laneX(to);
    final endY = startY + size.height;
    final direction = x1 > x0 ? 1.0 : -1.0;
    final corner = math.min(
      math.min(cornerRadius, (x1 - x0).abs() / 2),
      endY - startY,
    );
    if (bendEarly) {
      return Path()
        ..moveTo(x0, startY)
        ..lineTo(x1 - direction * corner, startY)
        ..quadraticBezierTo(x1, startY, x1, startY + corner)
        ..lineTo(x1, endY);
    }
    return Path()
      ..moveTo(x0, startY)
      ..lineTo(x0, endY - corner)
      ..quadraticBezierTo(x0, endY, x0 + direction * corner, endY)
      ..lineTo(x1, endY);
  }

  /// A rail paints in its branch line's color. Before [GraphRow] carries branch
  /// ids for a lane it falls back to the committer color, so the graph degrades
  /// to the old look instead of to one flat color.
  Paint _railPaint(
    int? branch,
    String? sha, {
    bool dashed = false,
    Color? colorOverride,
  }) => Paint()
    ..color = dashed && previewRailColor != null
        ? previewRailColor!
        : colorOverride ??
              (branch == null
                  ? AvatarService.color(
                      committersBySha[sha] ?? row.commit.committer,
                    )
                  : branch == 0
                  ? AvatarService.branchAssignments[0] ?? baseBranchColor
                  : AvatarService.branchColor(branch))
    ..style = PaintingStyle.stroke
    ..strokeWidth = dashed ? previewRailWidth : railWidth
    ..strokeCap = StrokeCap.round
    // Mitered, so a join's square corner renders as a crisp right angle. Curves
    // are unaffected.
    ..strokeJoin = StrokeJoin.miter;

  void _drawVerticalRail(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    required bool dashed,
  }) {
    if (!dashed) {
      canvas.drawLine(start, end, paint);
      return;
    }
    _drawRailPath(
      canvas,
      Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, end.dy),
      paint,
      dashed: true,
    );
  }

  void _drawRailPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required bool dashed,
  }) {
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 6) {
        canvas.drawPath(
          metric.extractPath(start, math.min(start + 3, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CommitGraphPainter oldDelegate) =>
      oldDelegate.row != row ||
      oldDelegate.previous != previous ||
      oldDelegate.selected != selected ||
      oldDelegate.committerColor != committerColor ||
      oldDelegate.baseBranchColor != baseBranchColor ||
      oldDelegate.committersBySha != committersBySha ||
      oldDelegate.laneSpacing != laneSpacing ||
      oldDelegate.compact != compact ||
      oldDelegate.refConnector != refConnector ||
      oldDelegate.passThrough != passThrough ||
      !setEquals(oldDelegate.dashedLanes, dashedLanes) ||
      !setEquals(oldDelegate.previousDashedLanes, previousDashedLanes) ||
      oldDelegate.previewRailColor != previewRailColor ||
      oldDelegate.outgoingRailColor != outgoingRailColor ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.selectedRowColor != selectedRowColor;
}

/// Dashes a ring by walking its perimeter. The dash count is FITTED to that
/// perimeter — whole [dash] + [gap] periods only, [gap] defaulting to [dash] —
/// so the pattern closes at the seam instead of butting a clipped dash against
/// a full one.
void drawDashedRing(
  Canvas canvas,
  Offset center,
  double radius,
  Paint paint,
  double dash, {
  double? gap,
}) {
  final period = dash + (gap ?? dash);
  final ring = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  for (final metric in ring.computeMetrics()) {
    final count = math.max(1, (metric.length / period).round());
    final step = metric.length / count;
    for (var i = 0; i < count; i++) {
      canvas.drawPath(
        metric.extractPath(i * step, i * step + step * dash / period),
        paint,
      );
    }
  }
}

/// A virtual commit's node: the same filled disc and the same ring color and
/// width as a real node's, but the ring is DASHED — the commit does not exist
/// yet, just like the dashed rails that lead into it. A `BoxDecoration` border
/// can only be solid, so the ring moves onto the canvas.
class DashedRingNodePainter extends CustomPainter {
  const DashedRingNodePainter({
    required this.fill,
    required this.ring,
    required this.ringWidth,
  });

  /// Denser than the rails' dash, so it still reads as a dash around a circle
  /// this small.
  static const dash = 4.0;
  static const gap = 3.0;

  final Color fill;
  final Color ring;
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    // Same geometry as the BoxDecoration this replaces: the disc fills the box
    // and the ring is stroked just inside its edge.
    final radius = math.min(size.width, size.height) / 2;
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, radius, Paint()..color = fill);
    drawDashedRing(
      canvas,
      center,
      radius - ringWidth / 2,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth,
      dash,
      gap: gap,
    );
  }

  @override
  bool shouldRepaint(covariant DashedRingNodePainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.ring != ring ||
      oldDelegate.ringWidth != ringWidth;
}

/// Status bar legend marker: outlined commit, filled merge, dashed WIP.
class _LegendDot extends StatelessWidget {
  const _LegendDot({this.filled = false, this.dashed = false});

  final bool filled;
  final bool dashed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 10,
    child: CustomPaint(painter: _LegendDotPainter(filled, dashed)),
  );
}

class _LegendDotPainter extends CustomPainter {
  const _LegendDotPainter(this.filled, this.dashed);

  final bool filled;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (filled) {
      canvas.drawCircle(center, 4, Paint()..color = _main);
      return;
    }
    final stroke = Paint()
      ..color = _main
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (dashed) {
      drawDashedRing(canvas, center, 3, stroke, 2.5);
      return;
    }
    canvas.drawCircle(center, 3, stroke);
  }

  @override
  bool shouldRepaint(covariant _LegendDotPainter oldDelegate) =>
      oldDelegate.filled != filled || oldDelegate.dashed != dashed;
}

/// Per-state color for the 18px file chips in the preview.
({Color background, Color letter}) fileStateChipColor(
  String status, {
  TimelineThemePalette palette = TimelineThemePalette.systemGraphite,
}) => switch (status.isEmpty ? '' : status[0]) {
  'A' => (background: _main.withValues(alpha: 0.2), letter: _main),
  'D' => (background: _deleted.withValues(alpha: 0.2), letter: _deleted),
  'R' || 'C' => (background: _renamed.withValues(alpha: 0.2), letter: _renamed),
  _ => (background: palette.neutralChip, letter: palette.text),
};

/// The commit's own moment, local and zero-padded, for the places where "2 hours
/// ago" is not precise enough. `07-26 14:05:09` this year, and
/// `2025-12-31 23:59:59` any other — the year only earns its space when it is
/// not the obvious one.
String exactCommitTime(int timestamp, {DateTime? now}) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  String pad(int value) => value.toString().padLeft(2, '0');
  final year = time.year == (now ?? DateTime.now()).year ? '' : '${time.year}-';
  return '$year${pad(time.month)}-${pad(time.day)} '
      '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
}

String _socialTime(int timestamp) => socialTimeLabel(
  DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
  DateTime.now(),
);

/// Long-form relative time, as the mockup spells it out. The first two days read
/// in hours — precise, and never contradicting the heading a row sits under —
/// and past that the buckets count calendar days, the same basis
/// [dateGroupLabel] uses.
String socialTimeLabel(DateTime time, DateTime now) {
  String ago(int value, String unit) =>
      '$value $unit${value == 1 ? '' : 's'} ago';
  final elapsed = now.difference(time);
  if (elapsed.inHours < 48) {
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return ago(elapsed.inMinutes, 'minute');
    return ago(elapsed.inHours, 'hour');
  }
  final days = calendarDaysBetween(time, now);
  if (days < 30) return ago(days, 'day');
  if (days < 365) return ago(days ~/ 30, 'month');
  return ago(days ~/ 365, 'year');
}
