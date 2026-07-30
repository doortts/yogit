import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'avatars.dart';
import 'diff_screen.dart';
import 'external_editor.dart';
import 'full_diff_commit_message_cache.dart';
import 'full_diff_model.dart';
import 'full_diff_side_by_side_view.dart';
import 'full_diff_syntax.dart';
import 'full_diff_unified_view.dart';
import 'git.dart';
import 'monaco_editor_screen.dart';
import 'page_scroll_shortcuts.dart';
import 'ref_tree.dart';
import 'repository_branch_selector.dart';
import 'settings.dart';
import 'timeline_theme.dart';
import 'typography.dart';
import 'vim_navigation.dart';
import 'window_frame.dart';

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
const _remoteBehind = Color(0xFFFF453A);
const _previewPurple = Color(0xFFC69AFF);
const _previewPurplePanel = Color(0xFF29243A);
const _previewConflict = Color(0xFFFF7A84);
const _previewConflictPanel = Color(0xFF4B252C);

List<Color> rebaseMappingColors(Iterable<Color> reserved) {
  final used = reserved.map((color) => color.toARGB32()).toSet();
  final colors = <Color>[];
  for (var index = 0; index < 360 && colors.length < 5; index++) {
    final color = HSLColor.fromAHSL(
      1,
      (18 + index * 67) % 360,
      0.26,
      0.38,
    ).toColor();
    if (used.add(color.toARGB32())) colors.add(color);
  }
  if (colors.length < 5) {
    throw StateError('Could not allocate rebase mapping colors.');
  }
  return colors;
}

enum PreviewGraphNodeKind {
  actual,
  virtualMerge,
  virtualRebase,
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
  return BranchPreviewGraph(
    rows: rows,
    kinds: {sha: PreviewGraphNodeKind.virtualMerge},
    dashedLanes: {0: lanes.toSet()},
  );
}

BranchPreviewGraph layoutRebasePreviewGraph(
  BranchComparisonResult comparison,
  RebasePreviewResult preview,
  List<Color> colors,
) {
  final existing = layoutBranchComparison(comparison.commits);
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
  final base = existing.firstWhere(
    (row) => row.commit.sha == comparison.baseTip,
  );
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
  final rows = [
    for (final commit in virtualNewestFirst)
      GraphRow(
        commit: commit,
        lane: base.lane,
        parentLanes: [base.lane],
        activeLanes: [base.lane],
        nextLanes: [base.lane],
        activeLaneShas: {base.lane: commit.sha},
        nextLaneShas: {base.lane: commit.parents.single},
        branch: base.branch,
        activeLaneBranches: {base.lane: base.branch},
        nextLaneBranches: {base.lane: base.branch},
      ),
    ...existing,
  ];
  final rowBySha = {
    for (var index = 0; index < rows.length; index++)
      rows[index].commit.sha: index,
  };
  return BranchPreviewGraph(
    rows: rows,
    kinds: {
      for (final commit in virtualOldestFirst)
        commit.sha: PreviewGraphNodeKind.virtualRebase,
    },
    dashedLanes: {
      for (var index = 0; index < virtualNewestFirst.length; index++)
        index: {base.lane},
    },
    mappings: [
      for (var index = 0; index < preview.rewritten.length; index++)
        (
          originalSha: preview.rewritten[index].original.sha,
          rewrittenSha: preview.rewritten[index].rewrittenSha,
          originalRow: rowBySha[preview.rewritten[index].original.sha]!,
          rewrittenRow: rowBySha[preview.rewritten[index].rewrittenSha]!,
          routeLane: index,
          color: colors[index % colors.length],
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

/// The mainline is fixed, the second line is one of two, and every later line
/// takes the first pool color no line running beside it at birth already wears.
const _branchColorPool = [
  Color(0xFF3B82F6),
  Color(0xFFFFF01F),
  Color(0xFFB026FF),
];
const _secondBranchColors = [Color(0xFF00E5FF), Color(0xFFFF3131)];

/// Branch id → color, decided at each line's birth row and therefore stable as
/// pages append. [seed] keeps a repository's colors the same across launches.
Map<int, Color> assignBranchColors(List<GraphRow> rows, int seed) {
  final colors = <int, Color>{};
  final overflow = [
    for (final color in AvatarService.defaultColors)
      if (!_branchColorPool.contains(color) &&
          !_secondBranchColors.contains(color) &&
          color != AvatarService.mainBranchColor)
        color,
  ]..shuffle(math.Random(seed));
  var taken = 0;
  for (final row in rows) {
    final ids = {
      row.branch,
      ...row.activeLaneBranches.values,
      ...row.nextLaneBranches.values,
    }.toList()..sort();
    for (final id in ids) {
      if (id < 0 || colors.containsKey(id)) continue;
      if (id == 0) {
        colors[id] = AvatarService.mainBranchColor;
        continue;
      }
      if (id == 1) {
        colors[id] = _secondBranchColors[math.Random(seed).nextInt(2)];
        continue;
      }
      // Lines already on screen where this one is born keep their colors.
      final beside = {
        for (final other in [
          ...row.activeLaneBranches.values,
          ...row.nextLaneBranches.values,
        ])
          colors[other],
      };
      colors[id] = _branchColorPool.firstWhere(
        (color) => !beside.contains(color),
        orElse: () => overflow.isEmpty
            ? _branchColorPool.first
            : overflow[taken++ % overflow.length],
      );
    }
  }
  return colors;
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
    this.onOpenRepository,
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
    this.branchPreviewMode = BranchPreviewMode.merge,
    this.previewWidth = 288,
    this.previewHeight = 280,
    this.onPreviewPlacementChanged,
    this.onColumnWidthsChanged,
    this.onFullDiffColumnWidthsChanged,
    this.onFullDiffPreferencesChanged,
    this.onBranchPreviewModeChanged,
    this.onPreviewSizeChanged,
    this.editorForTesting,
    this.documentLoaderForTesting,
    super.key,
  });

  /// Every row is this tall — commits and date headings alike.
  static const rowHeight = 32.0;

  final GitRepository repository;
  final WindowFrameController? controller;
  final ValueChanged<GitCommit>? onOpenFullDiff;
  final VoidCallback? onOpenSettings;

  /// Called with the validated root of a repository the user picked.
  final ValueChanged<String>? onOpenRepository;
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
  final BranchPreviewMode branchPreviewMode;
  final double previewWidth;
  final double previewHeight;
  final ValueChanged<PreviewPlacement>? onPreviewPlacementChanged;
  final ValueChanged<TimelineColumnWidths>? onColumnWidthsChanged;
  final ValueChanged<FullDiffColumnWidths>? onFullDiffColumnWidthsChanged;
  final ValueChanged<FullDiffPreferences>? onFullDiffPreferencesChanged;
  final ValueChanged<BranchPreviewMode>? onBranchPreviewModeChanged;
  final ValueChanged<({double width, double height})>? onPreviewSizeChanged;

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

  static const _pageSize = 500;

  static const _sidebarRange = (min: 150.0, max: 320.0);

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

  static const _previewWidthRange = (min: 240.0, max: 560.0);
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
  ScrollController? _activePreviewScrollController;
  final _normalCommits = <GitCommit>[];
  final _committersBySha = <String, GitIdentity>{};
  var _normalRows = <GraphRow>[];
  var _normalEntries = <TimelineEntry>[];
  String? _compareRef;
  BranchComparisonResult? _comparison;
  var _comparisonRows = <GraphRow>[];
  var _comparisonEntries = <TimelineEntry>[];
  BranchPreviewGraph? _previewGraph;
  RebaseCheckResult? _rebaseCheck;
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
  final _rebaseConflictRowContextKey = GlobalKey();
  final _rebaseApplyRowContextKey = GlobalKey();
  var _branchApplyStatus = BranchApplyStatus.idle;
  var _branchApplySerial = 0;
  BranchApplyResult? _branchApplyResult;
  Object? _branchApplyError;
  String? _rebaseApplyingSha;
  var _branchPreviewDropped = false;
  Object? _comparisonError;
  var _comparisonSerial = 0;
  late BranchPreviewMode _branchPreviewMode = widget.branchPreviewMode;
  var _branchPreviewLayout = DiffLayout.unified;
  final _branchPreviewHighlighter = HighlightJsSyntaxHighlighter();

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
  var _fetchingOrigin = false;
  Object? _fetchError;
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

  /// Which way the cursor last travelled, so the ref modal opens on the side the
  /// cursor came from. Null after a click or a jump, which have no direction.
  bool? _arrivedGoingDown;
  final _filterController = TextEditingController();
  var _filter = '';
  final _collapsedRefSections = <_RefSection>{};
  final _collapsedRefFolders = <String>{};
  var _showAllTags = false;

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
  var _dateColumnLeft = 0.0;
  var _commitAvailableWidth = 0.0;
  late double _previewWidth = widget.previewWidth;
  late double _previewHeight = widget.previewHeight;
  var _bottomPreviewMaxHeight = double.infinity;
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
    // Refs load beside the first page, and neither blocks the first paint. The
    // detail pane stays hidden until Enter or Space asks for it.
    _loadNextPage();
    unawaited(_restoreCherryPickThenRefresh());
    _fetchTimer = Timer.periodic(
      _fetchInterval,
      (_) => unawaited(_refreshSelectedRemote()),
    );
  }

  Future<void> _refreshSelectedRemote() async {
    final branch = _baseBranch;
    final remote = branch == null ? null : _refs.upstreamRemotes[branch];
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if ((lifecycleState != null &&
            lifecycleState != AppLifecycleState.resumed) ||
        remote == null ||
        _fetchingOrigin ||
        _cherryPickState != null) {
      return;
    }
    setState(() => _fetchingOrigin = true);
    try {
      final result = await widget.repository.fetchRemote(remote);
      if (!mounted) return;
      if (result == FetchOriginResult.updated) await _loadRefs();
      if (mounted) setState(() => _fetchError = null);
    } catch (error) {
      if (mounted) setState(() => _fetchError = error);
    } finally {
      if (mounted) setState(() => _fetchingOrigin = false);
    }
  }

  Future<void> _restoreCherryPickThenRefresh() async {
    await Future.wait([_loadRefs(), _reloadCherryPickState()]);
    if (_cherryPickState == null) await _refreshSelectedRemote();
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
          (refs.local.contains(compared) || refs.remote.contains(compared));
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
      if (comparisonStillExists) unawaited(_selectComparison(compared));
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
    if (widget.branchPreviewMode != oldWidget.branchPreviewMode) {
      _branchPreviewMode = widget.branchPreviewMode;
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
        unawaited(_refreshSelectedRemote());
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
    _fetchTimer?.cancel();
    _dropMergePreview();
    _dropRebasePreview();
    _clearFullDiffRouteSession();
    if (_ownsPreviewController) _previewController.dispose();
    _selectedIndex.removeListener(_selectedCommitChanged);
    _selectedIndex.dispose();
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

  /// Auto-fit: the snuggest width that still shows every loaded lane's node, so
  /// the first launch shows the whole graph and no more. The resizer reaches
  /// further down than this range; auto-fit never does.
  double get _graphColumnWidth =>
      _graphWidth ??
      CommitGraphPainter.contentWidth(
        _ratchetLane,
      ).clamp(96.0, timelineColumns['graph']!.max);

  /// Widens the ratchet when deeper lanes scroll into view. Rows off screen do
  /// not count, so a shallow head of history opens at its snuggest width.
  void _updateRatchet() {
    if (!mounted || _entries.isEmpty || !_scrollController.hasClients) return;
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
    if (_previewGraph?.mappings case final mappings? when mappings.isNotEmpty) {
      final graphDeepest = _comparisonRows.fold<int>(
        0,
        (value, row) => math.max(value, row.maxLane),
      );
      deepest = math.max(deepest, graphDeepest + mappings.length);
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
    AvatarService.branchAssignments = assignBranchColors(
      _normalRows,
      widget.repository.root.hashCode,
    );
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
          applyPageScroll(
            _activePreviewScrollController ?? _previewDiffScrollController,
            direction: pageScrollIntent.direction,
            animate: event is KeyDownEvent,
          );
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
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.keyD &&
        HardwareKeyboard.instance.isMetaPressed) {
      if (_selectedCommit != null) _openFullDiff();
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) &&
        _commits.isNotEmpty) {
      _togglePreview();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_previewController.setPreview(PreviewPlacement.closed));
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
  void _togglePreview() => unawaited(
    _previewController.setPreview(
      _previewController.previewPlacement == PreviewPlacement.closed
          ? widget.preferredPreviewPlacement
          : PreviewPlacement.closed,
    ),
  );

  /// Sidebar click: jump to the newest commit decorated with [name]. Remote
  /// entries also match the branch name without their remote prefix.
  void _selectRef(String name, {bool remote = false}) {
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
    _focusNode.requestFocus();
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
          if (_compareRef == null) _statusBar(),
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
      return Column(
        key: const Key('preview-layout-bottom'),
        children: [
          timeline,
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
    final extent = beside ? math.min(_previewWidth, constraints.maxWidth) : 0.0;
    final preview = _animatedPreview(
      axis: Axis.horizontal,
      extent: extent,
      width: extent,
      height: constraints.maxHeight,
      visible: beside,
    );
    return Row(
      key: Key(onLeft ? 'preview-layout-left' : 'preview-layout-right'),
      children: onLeft ? [preview, timeline] : [timeline, preview],
    );
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
    builder: (context, value, child) => SizedBox(
      width: axis == Axis.horizontal ? value : width,
      height: axis == Axis.vertical ? value : height,
      child: child,
    ),
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

  /// The window controls the titlebar no longer draws, in macOS order.
  Widget _windowButtons() => Row(
    children: [
      _WindowButton(
        key: const Key('window-close'),
        color: const Color(0xFFFF5F57),
        glyph: '×',
        onTap: () => unawaited(_previewController.closeWindow()),
      ),
      const SizedBox(width: 8),
      _WindowButton(
        key: const Key('window-minimize'),
        color: const Color(0xFFFEBC2E),
        glyph: '−',
        onTap: () => unawaited(_previewController.minimizeWindow()),
      ),
      const SizedBox(width: 8),
      _WindowButton(
        key: const Key('window-zoom'),
        color: const Color(0xFF28C840),
        glyph: '+',
        onTap: () => unawaited(_previewController.toggleZoom()),
      ),
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
                      localBranches: _refs.local,
                      remoteBranches: _refs.remote,
                      selectedBranch: _baseBranch,
                      comparedBranch: _compareRef,
                      refsLoading: _refsLoading,
                      refsLoadFailed: _refsLoadFailed,
                      onRepositoryPressed: () => unawaited(_pickRepository()),
                      onBranchSelected: _selectBaseBranch,
                      onComparisonSelected: (branch) =>
                          unawaited(_selectComparison(branch)),
                      onComparisonCleared: _clearComparison,
                    ),
                  ),
                ),
                if (_compareRef != null) ...[
                  const SizedBox(width: 8),
                  SizedBox(width: 204, child: _branchPreviewControls()),
                ],
                Expanded(child: _dragAndWordmark()),
              ],
            );
          },
        ),
      ),
    ],
  );

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

  Widget _branchPreviewControls() => SizedBox(
    height: 32,
    child: SegmentedButton<BranchPreviewMode>(
      key: const Key('branch-preview-segmented'),
      segments: const [
        ButtonSegment(
          value: BranchPreviewMode.merge,
          label: Text(
            'Merge 미리보기',
            key: Key('branch-preview-merge'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ButtonSegment(
          value: BranchPreviewMode.rebase,
          label: Text(
            'Rebase 미리보기',
            key: Key('branch-preview-rebase'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      selected: {_branchPreviewMode},
      showSelectedIcon: false,
      onSelectionChanged: _branchApplyBusy
          ? null
          : (selected) => _setBranchPreviewMode(selected.single),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _palette.text
              : _palette.muted,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _palette.selectedRow
              : _palette.background,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: _palette.border)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 6),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );

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
    unawaited(_refreshSelectedRemote());
    _focusNode.requestFocus();
  }

  Future<void> _selectComparison(String compareRef) async {
    final baseRef = _baseBranch;
    if (_branchApplyBusy || baseRef == null || compareRef == baseRef) return;
    final serial = ++_comparisonSerial;
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
      _comparisonError = null;
      _selectedIndex.value = 0;
    });
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
      setState(() {
        _comparison = result;
        _previewGraph = _branchPreviewMode == BranchPreviewMode.merge
            ? layoutMergePreviewGraph(result)
            : null;
        _comparisonRows = _previewGraph?.rows ?? rows;
        _comparisonEntries = [
          for (var index = 0; index < _comparisonRows.length; index++)
            (rowIndex: index, label: null, row: _comparisonRows[index]),
        ];
      });
      _scheduleRatchetUpdate();
      _showFirstComparisonRow();
      if (_branchPreviewMode == BranchPreviewMode.rebase) {
        unawaited(_startRebasePreview());
      } else if (result.merge.status == MergeConflictStatus.conflicts) {
        unawaited(_startMergePreview());
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
      });
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
    if (session != null) unawaited(session.dispose());
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
    final colors = rebaseMappingColors([
      ...AvatarService.palette,
      _palette.background,
      _palette.surface,
      _palette.panel,
      _palette.raised,
      _palette.border,
      _palette.text,
      _palette.muted,
      _palette.selectedRow,
      _palette.interactive,
    ]);
    final graph = layoutRebasePreviewGraph(comparison, result, colors);
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
    if (session != null) unawaited(session.dispose());
  }

  void _resetBranchApply() {
    _branchApplySerial++;
    _branchApplyStatus = BranchApplyStatus.idle;
    _branchApplyResult = null;
    _branchApplyError = null;
    _rebaseApplyingSha = null;
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
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('현재 브랜치로 체리픽'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(commit.sha),
            const SizedBox(height: 6),
            Text(commit.subject),
            const SizedBox(height: 6),
            Text('→ $current'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('체리픽'),
          ),
        ],
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
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('체리픽을 중단할까요?'),
        content: const Text('체리픽을 시작하기 전 상태로 되돌립니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('체리픽 중단'),
          ),
        ],
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
      _toolbarFullDiffButton(),
      const SizedBox(width: 8),
      IconButton(
        key: const Key('open-settings'),
        tooltip: 'Settings',
        visualDensity: VisualDensity.compact,
        onPressed: widget.onOpenSettings,
        icon: Icon(Icons.settings_outlined, size: 22, color: _palette.muted),
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
    return GestureDetector(
      key: Key('placement-$placement'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onPreviewPlacementChanged?.call(placement);
        unawaited(_previewController.setPreview(placement));
        _focusNode.requestFocus();
      },
      child: Container(
        height: 30,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: pressed ? _palette.selectedRow : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: pressed ? Colors.white : _palette.muted,
            fontSize: 14,
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
  Widget _sidebar() => SizedBox(
    key: const Key('sidebar'),
    width: _sidebarWidth,
    child: Stack(
      children: [
        Positioned.fill(child: _sidebarBody()),
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
                () => _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(
                  _sidebarRange.min,
                  _sidebarRange.max,
                ),
              ),
              onHorizontalDragEnd: (_) => _saveColumnWidths(),
              onHorizontalDragCancel: _saveColumnWidths,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _sidebarBody() => Container(
    decoration: BoxDecoration(
      color: _palette.panel,
      border: Border(right: BorderSide(color: _palette.border)),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: TextField(
            key: const Key('ref-filter'),
            controller: _filterController,
            onChanged: (value) => setState(() => _filter = value),
            style: TextStyle(color: _palette.text, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: '브랜치와 태그 찾기',
              hintStyle: TextStyle(color: _palette.muted, fontSize: 13),
              filled: true,
              fillColor: _palette.raised,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 7,
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
        Expanded(
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
      ],
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
    final query = _filter.trim().toLowerCase();
    final filtering = query.isNotEmpty;
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

    final orderedNames = section == _RefSection.tags
        ? sortTagsNewestFirst(names, _refs.tagCreatorTimes)
        : names;
    final hiddenTagCount = section == _RefSection.tags
        ? math.max(0, orderedNames.length - _collapsedTagLimit)
        : 0;
    final projectedNames =
        section == _RefSection.tags && !filtering && !_showAllTags
        ? orderedNames.take(_collapsedTagLimit).toList()
        : orderedNames;
    final visibleNames = filtering
        ? orderedNames
              .where((name) => name.toLowerCase().contains(query))
              .toList()
        : projectedNames;
    yield* _refTreeRows(section, buildRefTree(visibleNames));
    if (section == _RefSection.tags && !filtering && hiddenTagCount > 0) {
      yield _tagOverflowRow(hiddenTagCount);
    }
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
    final inFolderTree = name == null || depth > 0;

    void toggleFolder() => setState(() {
      if (!_collapsedRefFolders.remove(folderKey)) {
        _collapsedRefFolders.add(folderKey);
      }
    });

    final row = SizedBox(
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
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 7),
            Expanded(
              child: GestureDetector(
                key: name == null ? null : Key('sidebar-ref-$name'),
                behavior: HitTestBehavior.opaque,
                onTap: name == null
                    ? toggleFolder
                    : () => _selectRef(
                        name,
                        remote: section == _RefSection.remote,
                      ),
                child: Container(
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
                                color: current ? _palette.text : _palette.muted,
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
                          style: TextStyle(color: _palette.muted, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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

  Widget _statusBar() =>
      _compareRef == null ? _normalStatusBar() : _comparisonStatusBar();

  Widget _normalStatusBar() => Container(
    height: 29,
    decoration: BoxDecoration(
      color: _palette.surface,
      border: Border(top: BorderSide(color: _palette.border)),
    ),
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _fetchError == null
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
                    TextButton(
                      key: const Key('retry-origin-fetch'),
                      onPressed: _fetchingOrigin
                          ? null
                          : () => unawaited(_refreshSelectedRemote()),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 24),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
        ),
        // The branch the focused commit's line belongs to, under the column that
        // line's chip sits in.
        Positioned(
          left: _sidebarWidth,
          top: 0,
          bottom: 0,
          width: math.max(0, _dateColumnLeft - _sidebarWidth - 12),
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
        // The focused commit's exact moment, under the column it belongs to.
        Positioned(
          left: _dateColumnLeft,
          top: 0,
          bottom: 0,
          child: Align(
            child: ValueListenableBuilder<int>(
              valueListenable: _selectedIndex,
              builder: (context, _, _) {
                final commit = _selectedCommit;
                return Text(
                  key: const Key('status-timestamp'),
                  commit == null || commit.isWorkingTree || !_showTime
                      ? ''
                      : exactCommitTime(commit.committerTimestamp),
                  style: TextStyle(
                    color: _palette.muted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );

  Widget _comparisonStatusBar() {
    final comparison = _comparison;
    final labels = comparison == null
        ? [if (_comparisonError == null) '브랜치 비교 중' else '브랜치 비교 실패']
        : [
            comparison.sameFirstParent ? '부모 동일' : '부모 다름',
            '공통 ${comparison.mergeBases.length}',
            '${comparison.baseRef}만 ${comparison.commits.where((entry) => entry.side == BranchCommitSide.baseOnly).length}',
            '${comparison.compareRef}만 ${comparison.commits.where((entry) => entry.side == BranchCommitSide.compareOnly).length}',
            switch (comparison.merge.status) {
              MergeConflictStatus.clean => '병합 충돌 없음',
              MergeConflictStatus.conflicts =>
                '병합 충돌 ${comparison.merge.files.length}',
              MergeConflictStatus.failed => '병합 검사 실패',
            },
            switch (_rebaseCheck?.status) {
              null => '리베이스 검사 중',
              RebaseCheckStatus.clean => '리베이스 가능',
              RebaseCheckStatus.conflicts =>
                '리베이스 충돌 ${_rebaseCheck!.files.length}',
              RebaseCheckStatus.failed => '리베이스 검사 실패',
            },
          ];
    return Container(
      key: const Key('comparison-status'),
      height: 29,
      decoration: BoxDecoration(
        color: _palette.surface,
        border: Border(top: BorderSide(color: _palette.border)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('·', style: TextStyle(color: _palette.muted)),
        ),
        itemBuilder: (_, index) => Center(
          child: Text(
            labels[index],
            style: TextStyle(
              color: _comparisonError == null ? _palette.muted : _behind,
              fontSize: 10,
            ),
          ),
        ),
      ),
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
      final commitWidth = math.max(
        timelineColumns['commit']!.min,
        math.min(_commitWidth ?? available, available),
      );
      _commitAvailableWidth = math.max(
        timelineColumns['commit']!.min,
        available,
      );
      double width(String column) => switch (column) {
        'commit' => commitWidth,
        'graph' => graphWidth,
        _ => _w(column),
      };
      _dateColumnLeft =
          _sidebarWidth + _w('refs') + graphWidth + _w('hash') + commitWidth;
      return ColoredBox(
        color: _palette.background,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: fixed + commitWidth,
            child: Column(
              children: [
                if (_compareRef != null) _branchPreviewSummary(),
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
                        itemCount: _entries.length + (_showFooter ? 1 : 0),
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
                          builder: (context, constraints) => ListenableBuilder(
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
    final success = mergeMode
        ? mergeStatus == MergeConflictStatus.clean
        : _rebaseCheck?.status == RebaseCheckStatus.clean;
    final resultLabel = mergeMode
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
            detail('두 부모'),
            detail('충돌 없음', color: _success),
          ]);
        } else if (mergeStatus == MergeConflictStatus.conflicts) {
          final conflicts =
              _mergePreview?.conflictFiles.length ??
              comparison.merge.files.length;
          details.addAll([
            detail('충돌 $conflicts개', color: _previewConflict),
            detail('두 부모'),
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
        if (count > 0) details.add(detail('가상 커밋 $count개'));
        details.addAll([
          detail('점선 이동 경로', color: _previewPurple),
          detail('실제 브랜치 변경 없음'),
        ]);
      }
    }
    final resultColor = success
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

  bool get _branchPreviewReady {
    final comparison = _comparison;
    if (comparison == null || _branchPreviewDropped) return false;
    return _branchPreviewMode == BranchPreviewMode.merge
        ? _effectiveMergeStatus == MergeConflictStatus.clean &&
              (_mergePreview?.treeSha ?? comparison.merge.treeSha) != null
        : _rebasePreview?.status == RebasePreviewStatus.clean &&
              _rebasePreview?.virtualTip != null;
  }

  bool get _branchPreviewCanApply =>
      _branchPreviewReady &&
      _refs.local.contains(_comparison!.baseRef) &&
      _refs.local.contains(_comparison!.compareRef);

  bool get _branchApplyBusy =>
      _branchApplyStatus == BranchApplyStatus.applying ||
      _branchApplyStatus == BranchApplyStatus.reverting;

  String get _branchPreviewApplyLabel {
    final comparison = _comparison!;
    return _branchPreviewMode == BranchPreviewMode.merge
        ? '${comparison.compareRef}를 ${comparison.baseRef}에 Merge 실제 적용'
        : '${comparison.baseRef} 위로 ${comparison.compareRef} Rebase 실제 적용';
  }

  Future<void> _confirmBranchPreviewApply() async {
    final comparison = _comparison;
    if (comparison == null || !_branchPreviewCanApply || _branchApplyBusy) {
      return;
    }
    final merge = _branchPreviewMode == BranchPreviewMode.merge;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${merge ? 'Merge' : 'Rebase'} 실제 적용'),
        content: Text(
          '기준 브랜치 ${comparison.baseRef}\n'
          '${comparison.baseTip}\n\n'
          '대상 브랜치 ${comparison.compareRef}\n'
          '${comparison.compareTip}\n\n'
          '${merge ? comparison.baseRef : comparison.compareRef} 로컬 브랜치만 변경합니다. '
          '원격 저장소로 push하지 않습니다.\n'
          '완료한 뒤에도 두 브랜치를 이 시작 SHA의 이전 시점으로 되돌릴 수 있습니다.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('${merge ? 'Merge' : 'Rebase'} 실제 적용'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runBranchPreviewApply(comparison);
    }
  }

  Future<void> _runBranchPreviewApply(BranchComparisonResult comparison) async {
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
        result = await widget.repository.applyRebasePreview(
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

  Future<void> _confirmBranchPreviewRollback() async {
    final result = _branchApplyResult;
    if (result == null || _branchApplyStatus != BranchApplyStatus.applied) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${result.mode == BranchApplyMode.merge ? 'Merge' : 'Rebase'} 이전 시점으로 되돌리기',
        ),
        content: Text(
          '${result.baseBranch}: ${result.baseBefore}\n'
          '${result.compareBranch}: ${result.compareBefore}\n\n'
          '두 로컬 브랜치를 위 SHA로 되돌립니다. 원격 저장소는 변경하지 않습니다.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('되돌리기'),
          ),
        ],
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
    onPressed: _branchApplyBusy || !_branchPreviewCanApply
        ? null
        : () => unawaited(_confirmBranchPreviewApply()),
    style: FilledButton.styleFrom(
      foregroundColor: const Color(0xFFF1E7FF),
      backgroundColor: const Color(0xFF46385F),
      side: const BorderSide(color: Color(0xFF7D68A6)),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    ),
    child: Text(
      _branchPreviewApplyLabel,
      textAlign: TextAlign.center,
      softWrap: true,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _branchPreviewApplyCard() {
    final merge = _branchPreviewMode == BranchPreviewMode.merge;
    final result = _branchApplyResult;
    final comparison = _comparison!;
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
                      : '${merge ? 'Merge' : 'Rebase'} 적용 완료',
                  style: TextStyle(
                    color: _palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  result == null && _branchApplyStatus == BranchApplyStatus.idle
                      ? '${comparison.baseRef}과 ${comparison.compareRef} 유지'
                      : switch (_branchApplyStatus) {
                          BranchApplyStatus.applying => '커밋 적용 중',
                          BranchApplyStatus.applied => '로컬 브랜치 적용됨',
                          BranchApplyStatus.reverting => '되돌리는 중',
                          BranchApplyStatus.reverted => 'SHA 일치 확인',
                          BranchApplyStatus.failed => '작업 실패',
                          BranchApplyStatus.idle => '아직 적용하지 않음',
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
          ],
          if (result != null) ...[
            const SizedBox(height: 8),
            Text(
              '${result.baseBranch}: ${result.baseBefore} → ${result.baseAfter}\n'
              '${result.compareBranch}: ${result.compareBefore} → ${result.compareAfter}',
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
                child: Text('${merge ? 'Merge' : 'Rebase'} 이전 시점으로 되돌리기'),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_branchPreviewCanApply || merge) ...[
                  Text(
                    !_branchPreviewCanApply
                        ? '원격 브랜치는 바로 적용할 수 없습니다. 로컬 브랜치를 선택해 주세요.'
                        : '가상 결과를 실제 브랜치에 적용할 수 있습니다.',
                    style: TextStyle(color: _palette.muted, fontSize: 10),
                  ),
                  const SizedBox(height: 7),
                ],
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
      _branchPreviewDropped = true;
    });
    await mergeSession?.dispose();
    await rebaseSession?.dispose();
  }

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
                padding: const EdgeInsets.symmetric(horizontal: 9),
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
        return [
          GitRef(
            name: _effectiveMergeStatus == MergeConflictStatus.conflicts
                ? '! 병합 충돌'
                : '가상 병합',
            isHead: _effectiveMergeStatus != MergeConflictStatus.conflicts,
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
      if (previewKind == PreviewGraphNodeKind.conflictTarget) {
        return const [GitRef(name: '가상 rebase 위치')];
      }
      final side = comparison.commits
          .firstWhere((entry) => entry.commit.sha == commit.sha)
          .side;
      var compareLabel = '${comparison.compareRef}만';
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
              _branchPreviewMode == BranchPreviewMode.rebase
                  ? _rebasePreview?.status == RebasePreviewStatus.conflict &&
                            commit.sha == comparison.baseTip
                        ? '${comparison.baseRef} · HEAD'
                        : comparison.baseRef
                  : '${comparison.baseRef}만',
            BranchCommitSide.compareOnly => compareLabel,
            BranchCommitSide.commonBoundary => '공통',
          },
          isHead: side == BranchCommitSide.baseOnly,
        ),
      ];
    }
    final refs = [...commit.refs];
    if (commit.sha.isEmpty || _refs.tips.isEmpty) return refs;
    final seen = {for (final ref in refs) ref.name};
    for (final entry in _refs.tips.entries) {
      if (entry.value != commit.sha || !seen.add(entry.key)) continue;
      refs.add(
        GitRef(
          name: entry.key,
          isHead: entry.key == _refs.current,
          isTag: _refs.tags.contains(entry.key),
        ),
      );
    }
    return refs;
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
            color: selected ? _palette.selectedRow : _palette.background,
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
  }) => CommitGraphPainter(
    row: entry.row,
    previous: index > 0 ? _entries[index - 1].row : null,
    selected: selected,
    committerColor:
        committerColor ?? AvatarService.branchColor(entry.row.branch),
    committersBySha: _committersBySha,
    laneSpacing: CommitGraphPainter.spacingFor(graphWidth, _ratchetLane),
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
    backgroundColor: _palette.background,
    selectedRowColor: _palette.selectedRow,
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
    // One branch line, one color: rails, chips, node ring and hash border.
    final branchColor = AvatarService.branchColor(row.branch);
    final previewKind = _previewGraph?.kinds[commit.sha];
    final rebaseConflict =
        _rebasePreview?.status == RebasePreviewStatus.conflict &&
        _rebasePreview?.currentCommit?.sha == commit.sha;
    final rebaseApplying = _rebaseApplyingSha == commit.sha;
    final virtualPreview =
        previewKind == PreviewGraphNodeKind.virtualMerge ||
        previewKind == PreviewGraphNodeKind.virtualRebase;
    final mergeConflict =
        previewKind == PreviewGraphNodeKind.virtualMerge &&
        _effectiveMergeStatus == MergeConflictStatus.conflicts;
    final previewColor = previewKind == PreviewGraphNodeKind.conflictTarget
        ? _previewPurple
        : virtualPreview
        ? mergeConflict
              ? _previewConflict
              : _previewPurple
        : branchColor;
    final rebasePreview = _rebasePreview;
    final rewrittenIndex =
        rebasePreview?.rewritten.indexWhere(
          (rewrite) => rewrite.rewrittenSha == commit.sha,
        ) ??
        -1;
    final originalIndex =
        rebasePreview?.rewritten.indexWhere(
          (rewrite) => rewrite.original.sha == commit.sha,
        ) ??
        -1;
    final compareOnly =
        _comparison?.commits.any(
          (entry) =>
              entry.commit.sha == commit.sha &&
              entry.side == BranchCommitSide.compareOnly,
        ) ??
        false;
    final resolvedRebaseConflict =
        rebasePreview?.status == RebasePreviewStatus.conflict &&
        originalIndex >= 0 &&
        !rebaseConflict;
    final pendingRebaseConflict =
        rebasePreview?.status == RebasePreviewStatus.conflict &&
        compareOnly &&
        originalIndex < 0 &&
        !rebaseConflict;
    final rowAccentColor = rebaseConflict
        ? _previewConflict
        : resolvedRebaseConflict
        ? _previewPurple
        : pendingRebaseConflict
        ? _behind
        : previewColor;
    final progressTag = previewKind == PreviewGraphNodeKind.virtualMerge
        ? mergeConflict
              ? '충돌'
              : '가상'
        : rewrittenIndex >= 0
        ? '재작성 ${rewrittenIndex + 1}/${rebasePreview!.total}'
        : rebasePreview?.status == RebasePreviewStatus.conflict &&
              commit.sha == rebasePreview?.currentCommit?.sha
        ? '현재 적용 중'
        : rebasePreview?.status == RebasePreviewStatus.conflict &&
              originalIndex >= 0
        ? '해결 완료'
        : rebasePreview?.status == RebasePreviewStatus.conflict && compareOnly
        ? '다음'
        : null;
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
      refs.isNotEmpty,
      committerColor: previewColor,
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
                    color: _palette.selectedRow,
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
                                  mappings: mappings,
                                  rowIndex: index,
                                  laneSpacing: painter.laneSpacing,
                                  compact: painter.compact,
                                  backgroundColor: _palette.background,
                                ),
                              ),
                            ),
                          ),
                    node:
                        commit.isWorkingTree ||
                            (merge &&
                                previewKind !=
                                    PreviewGraphNodeKind.virtualMerge)
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
                        if (progressTag != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  rowAccentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              progressTag,
                              style: TextStyle(
                                color: rebaseConflict
                                    ? const Color(0xFFFFC4C8)
                                    : rowAccentColor,
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
                      ],
                    ),
                  ),
                  if (_showTime)
                    _cell(
                      _w('time'),
                      // The cell reads socially; the tooltip gives the exact moment.
                      _tooltip(
                        commit.isWorkingTree
                            ? null
                            : exactCommitTime(commit.committerTimestamp),
                        Text(
                          commit.isWorkingTree
                              ? 'working tree'
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
                      commit.isWorkingTree
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
        ? Container(
            key: const Key('virtual-merge-conflict-node'),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _previewConflict,
              border: Border.all(color: const Color(0xFFFFB8BD), width: 2),
            ),
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
        ? Container(
            key: const Key('virtual-merge-node'),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _previewPurple,
              border: Border.all(color: _palette.background, width: 2),
            ),
            child: const Text(
              'VM',
              style: TextStyle(
                color: Colors.black,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : kind == PreviewGraphNodeKind.virtualRebase
        ? Container(
            key: Key('virtual-rebase-node-${commit.sha}'),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF8D6BB8),
              border: Border.all(
                color: mappingColor ?? const Color(0xFFB78BEF),
                width: 1,
              ),
            ),
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
        : Container(
            padding: mappingColor == null
                ? EdgeInsets.zero
                : const EdgeInsets.all(1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: mappingColor == null
                  ? null
                  : Border.all(color: mappingColor, width: 1),
            ),
            child: CommitAvatarStack(
              commit: commit,
              avatarService: widget.avatarService,
              showRemoteAvatars: widget.showRemoteAvatars,
              size: mappingColor == null ? size : size - 2,
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
    Color color, {
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
              final slots = math.max(
                1,
                (constraints.maxWidth / _minChipWidth).floor(),
              );
              final shown = refs.take(slots).toList();
              final slot = constraints.maxWidth / shown.length;
              return Stack(
                children: [
                  for (var index = 0; index < shown.length; index++)
                    Positioned(
                      left: index * slot,
                      top: 6,
                      width: slot - 2,
                      height: 24,
                      child: _refChip(commit, shown[index], color),
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

  Widget _refChip(GitCommit commit, GitRef ref, Color color) => Container(
    key: Key('ref-chip-${commit.sha}-${ref.name}'),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      border: Border.all(color: color.withValues(alpha: 0.55)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      children: [_refGlyph(ref, color, false), _refName(ref, color, false)],
    ),
  );

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
                for (final ref in refs)
                  SizedBox(
                    height: 24,
                    child: Row(
                      children: [
                        // A straight 2px bar, no rounding.
                        Container(
                          key: Key('modal-accent-${ref.name}'),
                          width: 2,
                          height: 20,
                          color: color,
                        ),
                        const SizedBox(width: 7),
                        _refGlyph(ref, color, false),
                        _refName(ref, color, false, ellipsis: false),
                        const SizedBox(width: 6),
                        _CopyButton(text: ref.name, color: color),
                        const SizedBox(width: 4),
                      ],
                    ),
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

  /// No hairlines anywhere: the hash column's rule is the only line, a 2px strip
  /// stopping 1px short top and bottom so stacked rows read apart.
  Widget _cell(double width, Widget child, {Color? leftBorder, Key? ruleKey}) {
    final cell = Container(
      width: width,
      padding: EdgeInsets.only(left: leftBorder == null ? 9 : 11, right: 9),
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
                  _previewWidthRange.min,
                  _previewWidthRange.max,
                );
              }),
        onHorizontalDragEnd: vertical ? null : (_) => _savePreviewSize(),
        onVerticalDragUpdate: vertical
            ? (details) => setState(() {
                final minHeight = math.min(
                  _previewMinHeight,
                  _bottomPreviewMaxHeight,
                );
                _previewHeight = (_previewHeight - details.delta.dy).clamp(
                  minHeight,
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
                      : _previewBody(
                          commit,
                          placement == PreviewPlacement.bottom,
                        ),
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
                color: _comparison == null ? _palette.muted : _palette.text,
                fontSize: 12,
                fontWeight: _comparison == null
                    ? FontWeight.w500
                    : FontWeight.w700,
                letterSpacing: _comparison == null ? 0.66 : 0,
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
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 64),
              child: Text(
                key: const Key('preview-hash'),
                _cherryPickState != null
                    ? _cherryPickState!.commitSha
                    : commit == null
                    ? '—'
                    : commit.isWorkingTree
                    ? 'WIP'
                    : commit.shortSha,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _palette.muted,
                  fontSize: 11,
                  fontFamily: technicalFontFamily,
                  fontFamilyFallback: technicalFontFallback,
                ),
              ),
            ),
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
  }) {
    setState(() => _previewPaths[_previewKey(commit)] = path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_previewDiffScrollController.hasClients) {
        _previewDiffScrollController.jumpTo(0);
      }
      if (revealDirection != null) {
        _revealSelectedPreviewFile(revealDirection, animate: animateReveal);
      }
    });
  }

  void _revealSelectedPreviewFile(int direction, {required bool animate}) {
    final selectedContext = _selectedPreviewFileKey.currentContext;
    if (selectedContext == null) return;
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

  Widget _previewBody(GitCommit commit, bool bottom) {
    final branchPreview = _usesBranchPreviewResult(commit);
    final files = _previewFilesFor(commit);
    return FutureBuilder<List<GitFileChange>>(
      key: branchPreview ? null : ValueKey(commit.sha),
      future: files,
      builder: (context, snapshot) {
        final changes = snapshot.data;
        final key = _previewKey(commit);
        final requestedPath =
            _previewPaths[key] ??
            (changes == null || changes.isEmpty ? null : changes.first.path);
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
              if (branchPreview && _branchPreviewHasConflict)
                _branchPreviewConflictChoices(),
            ],
          ),
        );
        final diff = Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Container(
            key: const Key('preview-diff'),
            child: selectedPath == null
                ? Center(
                    child: Text(
                      'Select a file to load its diff.',
                      style: TextStyle(color: _palette.muted, fontSize: 12),
                    ),
                  )
                : _previewDiff(commit, selectedFile!),
          ),
        );
        return bottom
            ? Row(
                children: [
                  SizedBox(width: 240, child: _previewScrollableInfo(info)),
                  VerticalDivider(width: 1, color: _palette.border),
                  Expanded(
                    child: _previewScrollableDiff(
                      diff,
                      branchPreview: branchPreview,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(child: _previewScrollableInfo(info)),
                  Divider(height: 1, color: _palette.border),
                  Expanded(
                    child: _previewScrollableDiff(
                      diff,
                      branchPreview: branchPreview,
                    ),
                  ),
                ],
              );
      },
    );
  }

  Widget _previewScrollableInfo(Widget info) => _previewScrollable(
    key: const Key('preview-files-scroll'),
    controller: _previewFilesScrollController,
    child: info,
  );

  Widget _previewScrollableDiff(Widget diff, {required bool branchPreview}) =>
      !branchPreview
      ? _previewScrollable(
          key: const Key('preview-diff-scroll'),
          controller: _previewDiffScrollController,
          child: diff,
        )
      : KeyedSubtree(key: const Key('preview-diff-scroll'), child: diff);

  Widget _previewScrollable({
    required Key key,
    required ScrollController controller,
    required Widget child,
  }) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _activePreviewScrollController = controller,
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle) {
          _activePreviewScrollController = controller;
        }
        return false;
      },
      child: SingleChildScrollView(
        key: key,
        controller: controller,
        child: child,
      ),
    ),
  );

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
                    : committer
                    ? 'Committer'
                    : 'Author',
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
    final interactive = mergeMode
        ? _mergePreviewSession != null
        : _rebasePreviewSession != null;
    Widget choice({
      required Key key,
      required String branch,
      required String subject,
      required VoidCallback onTap,
    }) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        key: key,
        onTap:
            !interactive ||
                _mergePreviewBusy ||
                _rebasePreviewBusy ||
                _repositoryOperationInProgress
            ? null
            : onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: _palette.raised,
            border: Border.all(color: _palette.border),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$branch · $subject',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _palette.text, fontSize: 11),
                ),
              ),
              Text('사용', style: TextStyle(color: _palette.muted, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
    return Column(
      children: [
        choice(
          key: Key(
            mergeMode ? 'merge-conflict-use-base' : 'rebase-conflict-use-base',
          ),
          branch: comparison.baseRef,
          subject: base?.subject ?? '현재 상태',
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
          branch: comparison.compareRef,
          subject: compare?.subject ?? '적용할 변경',
          onTap: () => unawaited(
            mergeMode
                ? _resolveMergeConflict(MergeConflictChoice.compare)
                : _resolveRebaseConflict(RebaseConflictChoice.commit),
          ),
        ),
        if (interactive)
          mergeMode ? _mergeConflictActions() : _rebaseConflictActions(),
      ],
    );
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
                  : () => unawaited(_openRebaseConflictEditor()),
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

  Future<void> _openRebaseConflictEditor() async {
    final session = _rebasePreviewSession;
    final path = _selectedRebaseConflictPath;
    final worktree = session?.worktreePath;
    if (session == null ||
        path == null ||
        worktree == null ||
        _rebasePreviewBusy ||
        _repositoryOperationInProgress) {
      return;
    }
    setState(() {
      _rebasePreviewBusy = true;
      _rebasePreviewError = null;
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
              await session.markResolved(path);
              if (mounted) {
                setState(() {
                  _rebaseEditedFiles.add(path);
                  _rebaseResolvedFiles.add(path);
                  _previewDiffs.removeWhere((key, _) => key.path == path);
                });
                Navigator.of(context).pop();
              }
            },
            onOpenExternal: () async {
              await externalEditor.open(relativePath: path);
              if (mounted) setState(() => _rebaseEditedFiles.add(path));
            },
            editorForTesting: widget.editorForTesting,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _rebasePreviewError = error);
    } finally {
      if (mounted) setState(() => _rebasePreviewBusy = false);
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
              for (final file in changes)
                _previewFileRow(commit, file, file.path == selectedPath),
            ],
          ),
  );

  Widget _previewFileRow(GitCommit commit, GitFileChange file, bool selected) =>
      SizedBox(
        key: selected ? _selectedPreviewFileKey : null,
        height: 28,
        child: InkWell(
          onTap: () => _selectPreviewFile(commit, file.path),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? _palette.neutralChip : null,
              border: Border(top: BorderSide(color: _palette.border)),
            ),
            child: Row(
              children: [
                Container(
                  key: Key('preview-state-${file.path}'),
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fileStateChipColor(
                      file.status,
                      palette: _palette,
                    ).background,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    file.status,
                    maxLines: 1,
                    style: TextStyle(
                      color: fileStateChipColor(
                        file.status,
                        palette: _palette,
                      ).letter,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? _palette.text : _palette.muted,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

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
    if (_usesBranchPreviewResult(commit)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _palette.text,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                _branchPreviewLayoutButton(
                  key: const Key('branch-preview-layout-unified'),
                  label: 'Unified',
                  layout: DiffLayout.unified,
                ),
                const SizedBox(width: 5),
                _branchPreviewLayoutButton(
                  key: const Key('branch-preview-layout-side-by-side'),
                  label: 'Side-by-side',
                  layout: DiffLayout.sideBySide,
                ),
              ],
            ),
          ),
          Expanded(
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
                  return _branchPreviewLayout == DiffLayout.unified
                      ? UnifiedPresentationView(
                          document: document,
                          activeAnchor: null,
                          path: path,
                          wrapLines: false,
                          highlighter: _branchPreviewHighlighter,
                          anchorKeys: anchors,
                        )
                      : SideBySidePresentationView(
                          document: document,
                          activeAnchor: null,
                          oldPath: file.oldPath ?? path,
                          newPath: path,
                          wrapLines: false,
                          showOldSide: true,
                          highlighter: _branchPreviewHighlighter,
                          anchorKeys: anchors,
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
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
          child: Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _palette.text,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
        FutureBuilder<List<DiffLine>>(
          future: future,
          builder: (context, snapshot) {
            // The file name is already the head line, so the raw `diff --git`
            // and `index` preamble is noise here. The full DiffScreen keeps it.
            final lines = snapshot.data
                ?.where((line) => line.kind != DiffLineKind.header)
                .toList(growable: false);
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Could not load diff',
                  style: TextStyle(color: Color(0xFFF29AB2), fontSize: 12),
                ),
              );
            }
            if (lines == null) {
              return const Center(
                child: SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              );
            }
            // The panel shows one file, so its lines flow with the rest of the
            // body instead of scrolling on their own.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final line in lines) _previewDiffLine(line)],
            );
          },
        ),
      ],
    );
  }

  Widget _branchPreviewLayoutButton({
    required Key key,
    required String label,
    required DiffLayout layout,
  }) => InkWell(
    key: key,
    onTap: () => setState(() => _branchPreviewLayout = layout),
    borderRadius: BorderRadius.circular(5),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _branchPreviewLayout == layout
            ? _palette.interactive
            : _palette.raised,
        borderRadius: BorderRadius.circular(5),
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

  Widget _previewDiffLine(DiffLine line) {
    final prefix = switch (line.kind) {
      DiffLineKind.add => '+',
      DiffLineKind.delete => '-',
      // The hunk header reads as its own line, like the mockup.
      DiffLineKind.hunk => '',
      _ => ' ',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      color: switch (line.kind) {
        DiffLineKind.add => _main.withValues(alpha: 0.15),
        DiffLineKind.delete => _hash.withValues(alpha: 0.15),
        _ => null,
      },
      child: Text(
        '$prefix${line.text}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: line.kind == DiffLineKind.hunk
              ? _palette.muted
              : _palette.text,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

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

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.color,
    required this.glyph,
    required this.onTap,
    super.key,
  });

  final Color color;
  final String glyph;
  final VoidCallback onTap;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        width: 12,
        height: 12,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
        ),
        child: _hovered
            ? Text(
                widget.glyph,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.55),
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
    ),
  );
}

/// The green 'Show Diff' affordance, name over shortcut. The toolbar and the
/// preview header show the same button at their own scale.
class _ShowDiffButton extends StatelessWidget {
  const _ShowDiffButton({
    required this.onTap,
    this.height = 40,
    this.labelSize = 13,
    this.shortcutSize = 10,
    super.key,
  });

  static const green = Color(0xFF2EA043);

  final VoidCallback? onTap;
  final double height;
  final double labelSize;
  final double shortcutSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    final ink = onTap == null ? palette.muted : AvatarService.onColor(green);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: height * 0.3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? palette.raised : green,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Show Diff',
              style: TextStyle(
                color: ink,
                fontSize: labelSize,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
            Text(
              '⌘D',
              style: TextStyle(
                color: ink.withValues(alpha: 0.75),
                fontSize: shortcutSize,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
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

class RebaseMappingPainter extends CustomPainter {
  const RebaseMappingPainter({
    required this.rows,
    required this.mappings,
    required this.rowIndex,
    required this.laneSpacing,
    required this.compact,
    required this.backgroundColor,
  });

  final List<GraphRow> rows;
  final List<RebaseGraphMapping> mappings;
  final int rowIndex;
  final double laneSpacing;
  final bool compact;
  final Color backgroundColor;

  double _laneX(int lane) => compact
      ? CommitGraphPainter.laneInset
      : CommitGraphPainter.laneInset + lane * laneSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    if (compact || rowIndex < 0 || rowIndex >= rows.length) return;
    final deepest = rows.fold<int>(
      0,
      (value, row) => math.max(value, row.maxLane),
    );
    final centerY = size.height / 2;
    for (final mapping in mappings) {
      final top = math.min(mapping.rewrittenRow, mapping.originalRow);
      final bottom = math.max(mapping.rewrittenRow, mapping.originalRow);
      if (rowIndex < top || rowIndex > bottom) continue;
      final routeX = _laneX(deepest + 1 + mapping.routeLane);
      final rewrittenX = _laneX(rows[mapping.rewrittenRow].lane);
      final originalX = _laneX(rows[mapping.originalRow].lane);
      final path = Path();
      if (rowIndex == mapping.rewrittenRow) {
        path
          ..moveTo(routeX, size.height)
          ..lineTo(routeX, centerY + 6)
          ..quadraticBezierTo(routeX, centerY, routeX - 6, centerY)
          ..lineTo(rewrittenX + CommitGraphPainter.avatarDiameter / 2, centerY);
      } else if (rowIndex == mapping.originalRow) {
        path
          ..moveTo(originalX + CommitGraphPainter.avatarDiameter / 2, centerY)
          ..lineTo(routeX - 6, centerY)
          ..quadraticBezierTo(routeX, centerY, routeX, centerY - 6)
          ..lineTo(routeX, 0);
      } else {
        path
          ..moveTo(routeX, 0)
          ..lineTo(routeX, size.height);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = backgroundColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
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
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(tip.dx + 5, tip.dy - 3)
          ..lineTo(tip.dx + 5, tip.dy + 3)
          ..close();
        canvas.drawPath(arrow, Paint()..color = mapping.color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RebaseMappingPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.mappings != mappings ||
      oldDelegate.rowIndex != rowIndex ||
      oldDelegate.laneSpacing != laneSpacing ||
      oldDelegate.compact != compact ||
      oldDelegate.backgroundColor != backgroundColor;
}

/// Draws one row of the commit graph: pass-through rails, the rounded lane
/// curves into parent lanes, and the row's own node.
class CommitGraphPainter extends CustomPainter {
  const CommitGraphPainter({
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
    this.backgroundColor = const Color(0xFF1C1C1E),
    this.selectedRowColor = const Color(0xFF234D72),
  });

  static const laneInset = 28.0;
  static const defaultLaneSpacing = 30.0;
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
  static double contentWidth(int deepestLane) =>
      laneInset + deepestLane * defaultLaneSpacing + nodeExtent;

  /// Stage 1 (the cell still holds the rightmost node) keeps
  /// [defaultLaneSpacing]; stage 2 squeezes the lanes so that node stays just
  /// inside the cell.
  static double spacingFor(double width, int deepestLane) {
    if (width >= contentWidth(deepestLane)) return defaultLaneSpacing;
    return ((width - laneInset - nodeExtent) / math.max(deepestLane, 1)).clamp(
      minLaneSpacing,
      defaultLaneSpacing,
    );
  }

  /// Rails are opaque.
  static const railOpacity = 1.0;
  static const connectorWidth = 1.0;
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
  final Color? previewRailColor;

  bool isDashedLane(int lane) => dashedLanes.contains(lane);
  bool isDashedAbove(int lane) =>
      isDashedLane(lane) || previousDashedLanes.contains(lane);

  double laneX(int lane) =>
      compact ? laneInset : laneInset + lane * laneSpacing;

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
            // The node hands its first parent straight down, unless its lane
            // joins another lane or a slide refills it.
            ? !joining.contains(lane) && !arriving.contains(lane)
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
      final dashed = isDashedLane(row.lane);
      final paint = Paint()
        ..color = dashed ? previewRailColor ?? committerColor : committerColor
        ..strokeWidth = dashed ? previewRailWidth : railWidth
        ..strokeCap = StrokeCap.round;
      _drawVerticalRail(
        canvas,
        Offset(laneInset, rail.top),
        Offset(laneInset, rail.bottom),
        paint,
        dashed: dashed,
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
          final dashed =
              previousDashedLanes.contains(transition.from) ||
              previousDashedLanes.contains(transition.to);
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
        final dashed =
            isDashedLane(transition.from) || isDashedLane(transition.to);
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
    if (refConnector) {
      canvas.drawLine(
        Offset.zero.translate(0, centerY),
        Offset(nodeX, centerY),
        Paint()
          ..color = committerColor
          ..strokeWidth = connectorWidth
          ..strokeCap = StrokeCap.round,
      );
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
  Paint _railPaint(int? branch, String? sha, {bool dashed = false}) => Paint()
    ..color = dashed && previewRailColor != null
        ? previewRailColor!
        : branch == null
        ? AvatarService.color(committersBySha[sha] ?? row.commit.committer)
        : AvatarService.branchColor(branch)
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
      oldDelegate.committersBySha != committersBySha ||
      oldDelegate.laneSpacing != laneSpacing ||
      oldDelegate.compact != compact ||
      oldDelegate.refConnector != refConnector ||
      oldDelegate.passThrough != passThrough ||
      !setEquals(oldDelegate.dashedLanes, dashedLanes) ||
      !setEquals(oldDelegate.previousDashedLanes, previousDashedLanes) ||
      oldDelegate.previewRailColor != previewRailColor ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.selectedRowColor != selectedRowColor;
}

void drawDashedRing(
  Canvas canvas,
  Offset center,
  double radius,
  Paint paint,
  double dash,
) {
  final ring = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  for (final metric in ring.computeMetrics()) {
    for (var start = 0.0; start < metric.length; start += dash * 2) {
      canvas.drawPath(
        metric.extractPath(start, math.min(start + dash, metric.length)),
        paint,
      );
    }
  }
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
/// ago" is not precise enough.
String exactCommitTime(int timestamp) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${pad(time.month)}-${pad(time.day)} '
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
