import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'avatars.dart';
import 'diff_screen.dart';
import 'git.dart';
import 'settings.dart';
import 'window_frame.dart';

const _background = Color(0xFF15171E);
const _surface = Color(0xFF1D2029);
const _panelSoft = Color(0xFF1A1D25);
const _raised = Color(0xFF252936);
const _border = Color(0xFF343946);
const _text = Color(0xFFE8EAF2);
const _muted = Color(0xFF8D94A8);
const _hash = Color(0xFFEF6C63);
const _accent = Color(0xFF263246);
const _selectedRow = Color(0xFF1F4D8F);
const _selectedChip = Color(0xFF2B4E86);
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
    this.avatarService,
    this.showRemoteAvatars = true,
    this.preferredPreviewPlacement = PreviewPlacement.right,
    this.columnWidths = const TimelineColumnWidths(),
    this.fullDiffColumnWidths = const FullDiffColumnWidths(),
    this.previewWidth = 288,
    this.previewHeight = 280,
    this.onPreviewPlacementChanged,
    this.onColumnWidthsChanged,
    this.onFullDiffColumnWidthsChanged,
    this.onPreviewSizeChanged,
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
  final AvatarService? avatarService;
  final bool showRemoteAvatars;
  final PreviewPlacement preferredPreviewPlacement;
  final TimelineColumnWidths columnWidths;
  final FullDiffColumnWidths fullDiffColumnWidths;
  final double previewWidth;
  final double previewHeight;
  final ValueChanged<PreviewPlacement>? onPreviewPlacementChanged;
  final ValueChanged<TimelineColumnWidths>? onColumnWidthsChanged;
  final ValueChanged<FullDiffColumnWidths>? onFullDiffColumnWidthsChanged;
  final ValueChanged<({double width, double height})>? onPreviewSizeChanged;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  static const _pageSize = 500;

  static const _sidebarRange = (min: 120.0, max: 320.0);

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
  static const _previewHeightRange = (min: 200.0, max: 480.0);

  final _focusNode = FocusNode();
  final _timelineKey = GlobalKey();
  final _scrollController = ScrollController();
  final _previewScrollController = ScrollController();
  final _commits = <GitCommit>[];
  final _committersBySha = <String, GitIdentity>{};
  var _rows = <GraphRow>[];
  var _entries = <TimelineEntry>[];
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

  var _refs = const RepoRefs();

  /// Which way the cursor last travelled, so the ref modal opens on the side the
  /// cursor came from. Null after a click or a jump, which have no direction.
  bool? _arrivedGoingDown;
  final _filterController = TextEditingController();
  var _filter = '';

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
    _ownsPreviewController = widget.controller == null;
    _previewController = widget.controller ?? WindowFrameController();
    _scrollController.addListener(_maybeLoadNextPage);
    // Refs load beside the first page, and neither blocks the first paint. The
    // detail pane stays hidden until Enter or Space asks for it.
    _loadNextPage();
    unawaited(_loadRefs());
  }

  Future<void> _loadRefs() async {
    try {
      final refs = await widget.repository.loadRefs();
      if (mounted) setState(() => _refs = refs);
    } catch (_) {
      // The sidebar just stays empty; the timeline does not depend on refs.
    }
  }

  @override
  void didUpdateWidget(covariant TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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
  }

  @override
  void dispose() {
    if (_ownsPreviewController) _previewController.dispose();
    _selectedIndex.dispose();
    _hoverIndex.dispose();
    _hoveredHeader.dispose();
    _scrollController
      ..removeListener(_maybeLoadNextPage)
      ..dispose();
    _previewScrollController.dispose();
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
    if (deepest != _ratchetLane) setState(() => _ratchetLane = deepest);
  }

  void _maybeLoadNextPage() {
    _updateRatchet();
    if (!_scrollController.hasClients || _end || _inFlight != null) return;
    if (_scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <=
        TimelineScreen.rowHeight * 12) {
      _loadNextPage();
    }
  }

  void _loadNextPage() {
    if (_end || _inFlight != null) return;
    final request = _fetchNextPage();
    _inFlight = request;
    request.whenComplete(() {
      if (identical(_inFlight, request)) _inFlight = null;
    });
  }

  /// Commits actually read from `git log`, so the working tree row never shifts
  /// the paging offset.
  int get _historyCount => _commits.length - (_hasWorkingTree ? 1 : 0);

  Future<void> _fetchNextPage() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      // The first page fetches the working tree and the log together.
      final (working, page) = _commits.isEmpty
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
          _commits.isNotEmpty &&
          page.length < _pageSize &&
          _scrollController.hasClients &&
          _scrollController.position.maxScrollExtent -
                  _scrollController.position.pixels <=
              TimelineScreen.rowHeight;
      setState(() {
        if (working != null) {
          _commits.add(working);
          _hasWorkingTree = true;
          // The working tree row inherits HEAD's committer color so its rail
          // matches the branch it sits on.
          if (page.isNotEmpty) _committersBySha[''] = page.first.committer;
        }
        _commits.addAll(page);
        _committersBySha.addEntries(
          page.map((commit) => MapEntry(commit.sha, commit.committer)),
        );
        _rows = layoutGraph(_commits);
        _entries = timelineEntries(_rows, DateTime.now());
        AvatarService.branchAssignments = assignBranchColors(
          _rows,
          widget.repository.root.hashCode,
        );
        // A heading never holds the selection across a load — including the
        // very first one, so the app opens on a commit.
        if (_entries[_selectedIndex.value].rowIndex < 0) {
          _selectedIndex.value = _entries.indexWhere(
            (entry) => entry.rowIndex >= 0,
          );
        }
        _end = page.length < _pageSize;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateRatchet());
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

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    // Holding an arrow keeps moving; everything else acts once per press.
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final step = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowDown => 1,
        LogicalKeyboardKey.arrowUp => -1,
        _ => 0,
      };
      // Meta walks preview files; adding Shift scrolls the preview body.
      if (step != 0 && HardwareKeyboard.instance.isMetaPressed) {
        if (_previewController.previewPlacement != PreviewPlacement.closed) {
          if (HardwareKeyboard.instance.isShiftPressed) {
            _scrollPreview(step, animate: event is KeyDownEvent);
          } else {
            _stepPreviewFile(step);
          }
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
    backgroundColor: _background,
    body: Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: Column(
        children: [
          _toolbar(),
          const Divider(height: 1, color: _border),
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
      final extent = math.min(_previewHeight, constraints.maxHeight);
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
    color: _surface,
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
      IconButton(
        key: const Key('pick-repository'),
        tooltip: '저장소 열기',
        visualDensity: VisualDensity.compact,
        onPressed: () => unawaited(_pickRepository()),
        icon: const Icon(Icons.folder_open_outlined, size: 24, color: _muted),
      ),
      Expanded(child: _pathAndWordmark()),
    ],
  );

  /// The path and the wordmark share whatever the two clusters leave. Measuring
  /// here means the right cluster's width never has to be guessed: the wordmark
  /// keeps its intrinsic slot, the path takes the rest, and the drag stretch wins
  /// the tie — the wordmark steps down to 20px and then goes rather than squeeze
  /// it. Landing near the bar's centre is a happy side effect, not a promise.
  Widget _pathAndWordmark() => LayoutBuilder(
    builder: (context, constraints) {
      // fontSize * 5 over-states 'Yogit' in DancingScript, so this errs toward
      // leaving the path room.
      final size = [26.0, 20.0].firstWhere(
        (size) => constraints.maxWidth - (size * 5 + 24) >= _minDragWidth,
        orElse: () => 0.0,
      );
      // The whole leftover is the window's drag handle — the name is short now,
      // so the empty space beside it has to count. Nothing here takes a tap: the
      // wordmark ignores pointers and the tooltip only wants hover.
      return GestureDetector(
        key: const Key('toolbar-drag'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => unawaited(_previewController.startDrag()),
        onDoubleTap: () => unawaited(_previewController.toggleZoom()),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Tooltip(
                message: widget.repository.root,
                child: Text(
                  _repositoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 18),
                ),
              ),
            ),
            if (size > 0) ...[
              // Equal shares either side: the wordmark centres in what the name
              // leaves, not on the bar.
              const Spacer(flex: 2),
              IgnorePointer(
                child: _Wordmark(key: const Key('wordmark'), fontSize: size),
              ),
              const Spacer(flex: 2),
            ],
          ],
        ),
      );
    },
  );

  Widget _toolbarRight(bool showPreviewLabel, bool showShortcuts) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      if (showShortcuts) ...[_shortcutHint(), const SizedBox(width: 12)],
      // The caption sits beside the box, not inside it.
      if (showPreviewLabel)
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Text('미리보기', style: TextStyle(color: _muted, fontSize: 14)),
        ),
      Container(
        key: const Key('preview-placement'),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: _panelSoft,
          border: Border.all(color: _border),
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
        icon: const Icon(Icons.settings_outlined, size: 22, color: _muted),
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
          color: pressed ? _selectedRow : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: pressed ? Colors.white : _muted,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _shortcutHint() => Row(
    key: const Key('shortcut-hint'),
    children: [
      const Text('상세', style: TextStyle(color: _muted, fontSize: 14)),
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
    decoration: const BoxDecoration(
      color: _panelSoft,
      border: Border(right: BorderSide(color: _border)),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: TextField(
            key: const Key('ref-filter'),
            controller: _filterController,
            onChanged: (value) => setState(() => _filter = value),
            style: const TextStyle(color: _text, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: '브랜치와 태그 찾기',
              hintStyle: const TextStyle(color: _muted, fontSize: 13),
              filled: true,
              fillColor: _raised,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 7,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: _border),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              // The checked-out branch leads the local list.
              ..._sidebarSection('LOCAL', _localBranches, _refs.current, null),
              ..._sidebarSection(
                'REMOTE',
                _refs.remote,
                null,
                Icons.cloud_outlined,
              ),
              ..._sidebarSection('TAGS', _refs.tags, null, Icons.sell_outlined),
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

  Iterable<Widget> _sidebarSection(
    String heading,
    List<String> names,
    String? current,
    IconData? icon,
  ) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 5),
      child: Text(
        heading,
        style: const TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.8,
        ),
      ),
    ),
    for (final name in names)
      if (_filter.isEmpty || name.toLowerCase().contains(_filter.toLowerCase()))
        _sidebarItem(name, icon: icon, current: name == current),
  ];

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
    return _muted;
  }

  Widget _sidebarItem(String name, {IconData? icon, required bool current}) {
    final birth = _refs.birthTimes[name];
    return GestureDetector(
      key: Key('sidebar-ref-$name'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectRef(name, remote: icon == Icons.cloud_outlined),
      child: Container(
        height: birth == null ? 28 : 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: current ? _accent : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            if (icon != null)
              Icon(icon, size: 12, color: _muted)
            else
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _refTipColor(name), width: 2),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: current ? _text : _muted,
                      fontSize: 13,
                    ),
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
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- status bar

  Widget _statusBar() => Container(
    height: 29,
    decoration: const BoxDecoration(
      color: _panelSoft,
      border: Border(top: BorderSide(color: _border)),
    ),
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _legend('commit', const _LegendDot()),
              _legend('merge', const _LegendDot(filled: true)),
              _legend('WIP', const _LegendDot(dashed: true)),
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
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _CopyButton(text: name, color: _muted, slot: 'status-copy'),
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
                  style: const TextStyle(
                    color: _muted,
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

  Widget _legend(String label, Widget dot) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Row(
      children: [
        dot,
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
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
        color: _background,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: fixed + commitWidth,
            child: Column(
              children: [
                SizedBox(
                  height: 29,
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
                        // A little cache keeps rows from popping in mid-scroll.
                        cacheExtent: 200,
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

  bool get _showFooter => true;

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
                decoration: const BoxDecoration(
                  color: _panelSoft,
                  border: Border(
                    bottom: BorderSide(color: _border),
                    right: BorderSide(color: _border),
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
                            color: hovered == column ? _text : _muted,
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
          foregroundColor: _muted,
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
        final delta = switch (event.logicalKey) {
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
            color: selected ? _selectedRow : _background,
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
    bool refConnector,
  ) => CommitGraphPainter(
    row: entry.row,
    previous: index > 0 ? _entries[index - 1].row : null,
    selected: selected,
    committerColor: AvatarService.branchColor(entry.row.branch),
    committersBySha: _committersBySha,
    laneSpacing: CommitGraphPainter.spacingFor(graphWidth, _ratchetLane),
    compact: graphWidth <= CommitGraphPainter.compactWidth,
    refConnector: refConnector,
    passThrough: entry.rowIndex < 0,
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
    final refs = _rowRefs(commit);
    final merge = commit.parents.length >= 2 && !commit.isWorkingTree;
    // Shrink stages: full spacing while the cell fits every lane, compressed
    // spacing below that, one collapsed lane at the narrowest.
    final painter = _painterFor(
      entry,
      index,
      graphWidth,
      selected,
      refs.isNotEmpty,
    );
    // Nodes keep their size at every width; only the overhang clips.
    const avatarSize = 22.0;
    // The author/committer stack reaches 45% further right than one disc, so it
    // only shows while that stays clear of the next lane's rail.
    final stacked =
        avatarSize * 0.95 <= painter.laneSpacing - CommitGraphPainter.railWidth;
    return MouseRegion(
      onEnter: (_) => _hoverIndex.value = index,
      onExit: (_) {
        if (_hoverIndex.value == index) _hoverIndex.value = -1;
      },
      child: GestureDetector(
        key: selected ? Key('selected-row-${commit.sha}') : null,
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(index),
        child: ColoredBox(
          color: selected
              ? _selectedRow
              : hovered
              ? _accent.withValues(alpha: 0.48)
              : _background,
          child: Row(
            children: [
              _refsCell(entry.rowIndex, commit, refs, branchColor, selected),
              _graphCell(
                Key('graph-painter-${entry.rowIndex}'),
                painter,
                graphWidth,
                cellKey: Key('graph-cell-${entry.rowIndex}'),
                node: commit.isWorkingTree || merge
                    ? null
                    : Positioned(
                        left: painter.laneX(row.lane) - avatarSize / 2,
                        top: (TimelineScreen.rowHeight - avatarSize) / 2,
                        child: CommitAvatarStack(
                          commit: commit,
                          avatarService: widget.avatarService,
                          showRemoteAvatars: widget.showRemoteAvatars,
                          size: avatarSize,
                          stacked: stacked,
                          discColor: branchColor,
                        ),
                      ),
              ),
              _cell(
                _w('hash'),
                Text(
                  commit.isWorkingTree ? '·······' : commit.shortSha,
                  style: TextStyle(
                    color: selected ? _text : _hash,
                    fontSize: 12,
                    fontFamily: cellFont,
                    fontFamilyFallback: cellFontFallback,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                leftBorder: branchColor,
                ruleKey: Key('hash-rule-${entry.rowIndex}'),
              ),
              _cell(
                commitWidth,
                Text(
                  commit.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 14,
                    fontFamily: cellFont,
                    fontFamilyFallback: cellFontFallback,
                  ),
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
                        color: selected ? _text : _muted,
                        fontSize: 12,
                        fontFamily: cellFont,
                        fontFamilyFallback: cellFontFallback,
                      ),
                    ),
                  ),
                ),
              if (_showName)
                _cell(
                  _w('name'),
                  commit.isWorkingTree
                      ? const Text(
                          '—',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontFamily: cellFont,
                            fontFamilyFallback: cellFontFallback,
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
                                      ? _text
                                      : Color.lerp(_text, _main, 0.12),
                                  fontSize: 12,
                                  fontFamily: cellFont,
                                  fontFamilyFallback: cellFontFallback,
                                  fontWeight: FontWeight.w500,
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
  }

  /// One chip per row: the first ref, plus a `+N` badge when the row carries
  /// more. The full list belongs to the floating modal the selected row shows.
  /// No bottom hairline here — the rules start at the hash column.
  Widget _refsCell(
    int index,
    GitCommit commit,
    List<GitRef> refs,
    Color color,
    bool selected,
  ) => SizedBox(
    key: Key('refs-cell-$index'),
    width: _w('refs'),
    child: refs.isEmpty
        ? null
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
                      child: _refChip(commit, shown[index], color, selected),
                    ),
                ],
              );
            },
          ),
  );

  Widget _refChip(GitCommit commit, GitRef ref, Color color, bool selected) =>
      Container(
        key: Key('ref-chip-${commit.sha}-${ref.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: selected ? _selectedChip : color.withValues(alpha: 0.14),
          border: Border.all(color: color.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            _refGlyph(ref, color, selected),
            _refName(ref, color, selected),
          ],
        ),
      );

  Widget _refGlyph(GitRef ref, Color color, bool selected) =>
      ref.isHead || ref.isTag
      ? Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Text(
            ref.isHead ? '✓' : '◇',
            style: TextStyle(color: selected ? _text : color, fontSize: 10),
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
      style: _refNameStyle(selected ? _text : color),
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
        text: TextSpan(text: ref.name, style: _refNameStyle(_text)),
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
              color: _raised,
              border: Border.all(color: _border),
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
    decoration: const BoxDecoration(
      color: _surface,
      border: Border(top: BorderSide(color: _border)),
    ),
    child: _loading
        ? const Text(
            'Loading more…',
            style: TextStyle(color: _muted, fontSize: 11),
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
            style: const TextStyle(color: _muted, fontSize: 11),
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
                _previewHeight = (_previewHeight - details.delta.dy).clamp(
                  _previewHeightRange.min,
                  _previewHeightRange.max,
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
      decoration: BoxDecoration(
        color: _surface,
        border: Border(
          left: placement == PreviewPlacement.right
              ? const BorderSide(color: _border)
              : BorderSide.none,
          right: placement == PreviewPlacement.left
              ? const BorderSide(color: _border)
              : BorderSide.none,
          top: placement == PreviewPlacement.bottom
              ? const BorderSide(color: _border)
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
                Container(
                  key: const Key('preview-shortcut-hint'),
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  child: const Text(
                    '파일 이동 ⌘↑/↓ · 화면 스크롤 ⇧⌘↑/↓',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 10,
                      fontFamily: cellFont,
                      fontFamilyFallback: cellFontFallback,
                    ),
                  ),
                ),
                Expanded(
                  child: commit == null
                      ? const Center(
                          child: Text(
                            'No commit selected',
                            style: TextStyle(color: _muted, fontSize: 13),
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

  Widget _previewHeader(GitCommit? commit) => Container(
    height: 36,
    padding: const EdgeInsets.only(left: 12, right: 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _border)),
    ),
    child: Row(
      children: [
        // Expanded, not Flexible plus a Spacer: the label is what yields when the
        // panel is dragged narrow.
        const Expanded(
          child: Text(
            'Commit & Diff',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.66,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _ShowDiffButton(
          key: const Key('preview-full-diff'),
          onTap: commit == null ? null : _openFullDiff,
          height: 28,
          labelSize: 11,
          shortcutSize: 8,
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 64),
          child: Text(
            key: const Key('preview-hash'),
            commit == null
                ? '—'
                : commit.isWorkingTree
                ? 'WIP'
                : commit.shortSha,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontFamily: cellFont,
              fontFamilyFallback: cellFontFallback,
            ),
          ),
        ),
      ],
    ),
  );

  /// The commit's changed files, remembered in resolved form as well so ⌘↑/⌘↓ can
  /// walk them without waiting on a future.
  Future<List<GitFileChange>> _previewFilesFor(GitCommit commit) =>
      _previewFiles.putIfAbsent(commit.sha, () {
        final request = widget.repository.loadFiles(commit);
        unawaited(
          request
              .then((files) => _previewFileLists[commit.sha] = files)
              .catchError((_) => const <GitFileChange>[]),
        );
        return request;
      });

  /// Steps the open preview through the commit's files, clamped at both ends.
  void _stepPreviewFile(int delta) {
    final commit = _selectedCommit;
    if (commit == null) return;
    final files = _previewFileLists[commit.sha];
    if (files == null || files.isEmpty) return;
    final current = _previewPaths[commit.sha] ?? files.first.path;
    final index = files.indexWhere((file) => file.path == current);
    final next = (index + delta).clamp(0, files.length - 1);
    setState(() => _previewPaths[commit.sha] = files[next].path);
  }

  void _scrollPreview(int delta, {required bool animate}) {
    if (!_previewScrollController.hasClients) return;
    final position = _previewScrollController.position;
    final target = (position.pixels + delta * 48).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    if (!animate) {
      _previewScrollController.jumpTo(target);
      return;
    }
    unawaited(
      _previewScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      ),
    );
  }

  Widget _previewBody(GitCommit commit, bool bottom) {
    final files = _previewFilesFor(commit);
    return FutureBuilder<List<GitFileChange>>(
      future: files,
      builder: (context, snapshot) {
        final changes = snapshot.data;
        final selectedPath =
            _previewPaths[commit.sha] ??
            (changes == null || changes.isEmpty ? null : changes.first.path);
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              commit.subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _text,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              commit.isWorkingTree
                  ? 'Working tree changes'
                  : 'commit ${commit.sha}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            _previewPerson(commit),
            _previewStats(changes),
            _previewFileList(commit, changes, snapshot.hasError, selectedPath),
          ],
        );
        final diff = Container(
          key: const Key('preview-diff'),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _border)),
          ),
          child: selectedPath == null
              ? const Center(
                  child: Text(
                    'Select a file to load its diff.',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                )
              : _previewDiff(commit, selectedPath),
        );
        // One scroll view for the whole body: nothing inside competes for the
        // drag, which is what lets a mouse drag select text across it.
        return SingleChildScrollView(
          key: const Key('preview-scroll'),
          controller: _previewScrollController,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: bottom
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 240, child: info),
                    const SizedBox(width: 16),
                    Expanded(child: diff),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [info, diff],
                ),
        );
      },
    );
  }

  Widget _previewPerson(GitCommit commit) {
    final separateCommitter =
        commit.author.name != commit.committer.name ||
        commit.author.email != commit.committer.email;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: _border),
          bottom: BorderSide(color: _border),
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
                  border: Border.all(color: _border),
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
                style: const TextStyle(
                  color: _text,
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
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              if (timestamp != null)
                Text(
                  exactCommitTime(timestamp),
                  maxLines: 1,
                  style: const TextStyle(
                    color: _muted,
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
              style: const TextStyle(color: _muted, fontSize: 12),
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

  Widget _previewFileList(
    GitCommit commit,
    List<GitFileChange>? changes,
    bool failed,
    String? selectedPath,
  ) => Container(
    key: const Key('preview-files'),
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
        ? const Center(
            child: Text(
              'No changed files',
              style: TextStyle(color: _muted, fontSize: 12),
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
        height: 28,
        child: InkWell(
          onTap: () => setState(() => _previewPaths[commit.sha] = file.path),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? _accent : null,
              border: const Border(top: BorderSide(color: Color(0x66343946))),
            ),
            child: Row(
              children: [
                Container(
                  key: Key('preview-state-${file.path}'),
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fileStateChipColor(file.status).background,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    file.status,
                    maxLines: 1,
                    style: TextStyle(
                      color: fileStateChipColor(file.status).letter,
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
                      color: selected ? _text : _muted,
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

  Widget _previewDiff(GitCommit commit, String path) {
    final future = _previewDiffs.putIfAbsent((
      sha: commit.sha,
      path: path,
    ), () => widget.repository.loadDiff(commit, path));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
          child: Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _text,
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
          color: line.kind == DiffLineKind.hunk ? _muted : _text,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  void _openFullDiff() {
    final commit = _selectedCommit!;
    if (widget.onOpenFullDiff case final callback?) {
      callback(commit);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DiffScreen(
          repository: widget.repository,
          commits: List.unmodifiable(_commits),
          initialIndex: _commits.indexOf(commit),
          columnWidths: widget.fullDiffColumnWidths,
          onColumnWidthsChanged: widget.onFullDiffColumnWidthsChanged,
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => MouseRegion(
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
          color: _hovered ? _selectedRow : _panelSoft,
          border: Border.all(color: _hovered ? _muted : _border),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(color: _text, fontSize: 13),
        ),
      ),
    ),
  );
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
    final ink = onTap == null ? _muted : AvatarService.onColor(green);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: height * 0.3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? _raised : green,
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
  Widget build(BuildContext context) => MouseRegion(
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
            ? _text
            : _muted,
      ),
    ),
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
  });

  static const laneInset = 28.0;
  static const defaultLaneSpacing = 30.0;
  static const railWidth = 2.0;

  /// Stage 3: at or below this cell width the graph collapses to one lane.
  static const compactWidth = 56.0;

  /// Stage 2 floor.
  static const minLaneSpacing = 12.0;

  /// Half the 22px node avatar plus a hair of air: how far right of the deepest
  /// lane's center a row still draws.
  static const nodeExtent = 13.0;

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
  static const connectorWidth = 2.0;
  static const nodeRadius = 6.0;
  static const wipNodeRadius = 8.0;
  static const wipNodeDash = 2.5;

  /// Every transition turns on one quarter arc of this radius beside the node it
  /// belongs to, so the horizontal run into or out of that node stays long and
  /// readable.
  static const cornerRadius = 8.0;

  final GraphRow row;
  final bool selected;

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
      canvas.drawLine(
        Offset(laneInset, rail.top),
        Offset(laneInset, rail.bottom),
        Paint()
          ..color = committerColor
          ..strokeWidth = railWidth
          ..strokeCap = StrokeCap.round,
      );
    } else {
      // Halves are painted apart: above the node a lane carries the rail it
      // waits for, below it the rail it hands down.
      for (final entry in laneVerticals(size).entries) {
        final x = laneX(entry.key);
        if (entry.value.top < centerY) {
          canvas.drawLine(
            Offset(x, entry.value.top),
            Offset(x, centerY),
            _railPaint(
              row.activeLaneBranches[entry.key],
              row.activeLaneShas[entry.key],
            ),
          );
        }
        if (entry.value.bottom > centerY) {
          canvas.drawLine(
            Offset(x, centerY),
            Offset(x, entry.value.bottom),
            _railPaint(
              row.nextLaneBranches[entry.key],
              row.nextLaneShas[entry.key],
            ),
          );
        }
      }

      // Arrival halves of the movements the row above started, then this row's
      // own departures. Every lane movement is a transition, so the two lists
      // are the whole story.
      if (previous case final previous?) {
        for (final transition in previous.transitions) {
          canvas.drawPath(
            transitionPath(
              transition.from,
              transition.to,
              centerY - size.height,
              size,
              // Classified against the row that started it, so the arrival half
              // repeats its departure half's shape and color exactly.
              bendEarly: isMergeEdge(previous, transition),
            ),
            _railPaint(transitionBranch(previous, transition), transition.sha),
          );
        }
      }
      for (final transition in row.transitions) {
        canvas.drawPath(
          transitionPath(
            transition.from,
            transition.to,
            centerY,
            size,
            bendEarly: isMergeEdge(row, transition),
          ),
          _railPaint(transitionBranch(row, transition), transition.sha),
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
  /// on rather than the global background — a selected row is blue.
  Color get nodeFillColor => selected ? _selectedRow : _background;

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
  Paint _railPaint(int? branch, String? sha) => Paint()
    ..color = branch == null
        ? AvatarService.color(committersBySha[sha] ?? row.commit.committer)
        : AvatarService.branchColor(branch)
    ..style = PaintingStyle.stroke
    ..strokeWidth = railWidth
    ..strokeCap = StrokeCap.round
    // Mitered, so a join's square corner renders as a crisp right angle. Curves
    // are unaffected.
    ..strokeJoin = StrokeJoin.miter;

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
      oldDelegate.passThrough != passThrough;
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
({Color background, Color letter}) fileStateChipColor(String status) =>
    switch (status.isEmpty ? '' : status[0]) {
      'A' => (background: _main.withValues(alpha: 0.2), letter: _main),
      'D' => (background: _deleted.withValues(alpha: 0.2), letter: _deleted),
      'R' ||
      'C' => (background: _renamed.withValues(alpha: 0.2), letter: _renamed),
      _ => (background: _accent, letter: _text),
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
