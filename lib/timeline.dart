import 'dart:async';
import 'dart:math' as math;

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

/// The design's `--yo-main` accent: additions, lane dots, the name tint.
const _main = Color(0xFF8AD6A1);

typedef ColumnSpec = ({String label, double min, double max});

/// The six resizable timeline columns, in display order.
const timelineColumns = <String, ColumnSpec>{
  'refs': (label: 'Branch / Tag', min: 110, max: 240),
  'graph': (label: 'Graph', min: 96, max: 260),
  'hash': (label: 'Hash', min: 64, max: 120),
  'commit': (label: 'Commit title', min: 140, max: 620),
  'time': (label: 'Social time', min: 112, max: 170),
  'name': (label: 'Name', min: 88, max: 180),
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
    this.onPreviewPlacementChanged,
    this.onColumnWidthsChanged,
    super.key,
  });

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
  final ValueChanged<PreviewPlacement>? onPreviewPlacementChanged;
  final ValueChanged<TimelineColumnWidths>? onColumnWidthsChanged;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  static const _pageSize = 500;
  static const _rowHeight = 36.0;
  static const _sidebarWidth = 150.0;
  static const _sidePreviewWidth = 288.0;
  static const _bottomPreviewHeight = 280.0;

  final _focusNode = FocusNode();
  final _timelineKey = GlobalKey();
  final _scrollController = ScrollController();
  final _commits = <GitCommit>[];
  final _committersBySha = <String, GitIdentity>{};
  var _rows = <GraphRow>[];
  late final WindowFrameController _previewController;
  late final bool _ownsPreviewController;

  var _selectedIndex = 0;
  var _hoverIndex = -1;
  var _loading = false;
  var _end = false;
  var _hasWorkingTree = false;
  Object? _loadError;
  Future<void>? _inFlight;
  final _previewFiles = <String, Future<List<GitFileChange>>>{};
  final _previewDiffs = <({String sha, String path}), Future<List<DiffLine>>>{};
  final _previewPaths = <String, String>{};

  late final Future<RepoRefs> _refsFuture = widget.repository.loadRefs();
  final _filterController = TextEditingController();
  var _filter = '';

  late final Map<String, double> _widths = _widthMap(widget.columnWidths);
  late double? _commitWidth = widget.columnWidths.commit;
  late double? _graphWidth = widget.columnWidths.graph;
  var _deepestLane = 0;
  final _resizerFocus = {
    for (final column in timelineColumns.keys) column: FocusNode(),
  };

  @override
  void initState() {
    super.initState();
    _ownsPreviewController = widget.controller == null;
    _previewController = widget.controller ?? WindowFrameController();
    _previewController.addListener(_previewChanged);
    _scrollController.addListener(_maybeLoadNextPage);
    _loadNextPage();
    // The detail pane is part of the resting layout, so it opens on launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _previewController.previewPlacement == PreviewPlacement.closed) {
        unawaited(
          _previewController.setPreview(widget.preferredPreviewPlacement),
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.columnWidths != oldWidget.columnWidths) {
      _widths.addAll(_widthMap(widget.columnWidths));
      _commitWidth = widget.columnWidths.commit;
      _graphWidth = widget.columnWidths.graph;
    }
  }

  @override
  void dispose() {
    _previewController.removeListener(_previewChanged);
    if (_ownsPreviewController) _previewController.dispose();
    _scrollController
      ..removeListener(_maybeLoadNextPage)
      ..dispose();
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

  /// Auto-fit: just wide enough for the deepest lane in the loaded rows, clamped
  /// to the design range. Lane coordinates never move with it — the cell clips.
  double get _graphColumnWidth =>
      _graphWidth ??
      (CommitGraphPainter.laneInset +
              (_deepestLane + 1) * CommitGraphPainter.defaultLaneSpacing)
          .clamp(timelineColumns['graph']!.min, timelineColumns['graph']!.max);

  void _previewChanged() {
    if (mounted) setState(() {});
  }

  void _maybeLoadNextPage() {
    if (!_scrollController.hasClients || _end || _inFlight != null) return;
    if (_scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <=
        _rowHeight * 12) {
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
      final working = _commits.isEmpty
          ? await widget.repository.loadWorkingTree()
          : null;
      final page = await widget.repository.loadHistory(
        skip: _historyCount,
        limit: _pageSize,
      );
      if (!mounted) return;
      final keepEndVisible =
          _commits.isNotEmpty &&
          page.length < _pageSize &&
          _scrollController.hasClients &&
          _scrollController.position.maxScrollExtent -
                  _scrollController.position.pixels <=
              _rowHeight;
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
        for (final row in _rows) {
          for (final lane in [row.lane, ...row.activeLanes, ...row.nextLanes]) {
            if (lane > _deepestLane) _deepestLane = lane;
          }
        }
        _end = page.length < _pageSize;
        _loading = false;
      });
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
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && _commits.isNotEmpty) {
      _openPreview();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_previewController.setPreview(PreviewPlacement.closed));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveSelection(int delta) {
    if (_commits.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, _commits.length - 1);
    });
    _scrollToSelection();
  }

  void _scrollToSelection() {
    if (!_scrollController.hasClients) return;
    final target = (_selectedIndex * _rowHeight).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _selectAndOpen(int index) {
    setState(() => _selectedIndex = index);
    _openPreview();
    _focusNode.requestFocus();
  }

  void _openPreview() {
    final placement =
        _previewController.previewPlacement == PreviewPlacement.closed
        ? widget.preferredPreviewPlacement
        : _previewController.previewPlacement;
    unawaited(_previewController.setPreview(placement));
  }

  /// Sidebar click: jump to the newest commit decorated with [name]. Remote
  /// entries also match the branch name without their remote prefix.
  void _selectRef(String name, {bool remote = false}) {
    final candidates = {
      name,
      if (remote && name.contains('/')) name.substring(name.indexOf('/') + 1),
    };
    final index = _commits.indexWhere(
      (commit) => commit.refs.any((ref) => candidates.contains(ref.name)),
    );
    if (index < 0) return;
    setState(() => _selectedIndex = index);
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

  Widget _workspace() => LayoutBuilder(
    builder: (context, constraints) {
      final placement = _previewController.previewPlacement;
      final timeline = Expanded(
        key: const Key('timeline-viewport'),
        child: KeyedSubtree(key: _timelineKey, child: _timeline()),
      );
      if (placement == PreviewPlacement.bottom) {
        final extent = math.min(_bottomPreviewHeight, constraints.maxHeight);
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
      final extent = beside
          ? math.min(_sidePreviewWidth, constraints.maxWidth)
          : 0.0;
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
    },
  );

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
    height: 47,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    color: _surface,
    child: Row(
      children: [
        const Icon(
          Icons.account_tree_outlined,
          size: 15,
          color: Color(0xFF7AD6E8),
        ),
        IconButton(
          key: const Key('pick-repository'),
          tooltip: '저장소 열기',
          visualDensity: VisualDensity.compact,
          onPressed: () => unawaited(_pickRepository()),
          icon: const Icon(Icons.folder_open_outlined, size: 16, color: _muted),
        ),
        Expanded(
          child: Text(
            widget.repository.root,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _panelSoft,
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  '미리보기',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ),
              _placementButton('좌측', PreviewPlacement.left),
              _placementButton('우측', PreviewPlacement.right),
              _placementButton('하단', PreviewPlacement.bottom),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _shortcutHint(),
        IconButton(
          key: const Key('open-settings'),
          tooltip: 'Settings',
          visualDensity: VisualDensity.compact,
          onPressed: widget.onOpenSettings,
          icon: const Icon(Icons.settings_outlined, size: 16, color: _muted),
        ),
      ],
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
        height: 24,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: pressed ? _selectedRow : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: pressed ? Colors.white : _muted,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _shortcutHint() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        _kbd('↑'),
        _kbd('↓'),
        const Text(' 이동 · ', style: TextStyle(color: _muted, fontSize: 10)),
        _kbd('Enter'),
        const Text(' 상세', style: TextStyle(color: _muted, fontSize: 10)),
      ],
    ),
  );

  Widget _kbd(String label) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 2),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: _panelSoft,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: const TextStyle(color: _text, fontSize: 10)),
  );

  // ---------------------------------------------------------------- sidebar

  Widget _sidebar() => Container(
    width: _sidebarWidth,
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
            style: const TextStyle(color: _text, fontSize: 11),
            decoration: InputDecoration(
              isDense: true,
              hintText: '브랜치와 태그 찾기',
              hintStyle: const TextStyle(color: _muted, fontSize: 11),
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
          child: FutureBuilder<RepoRefs>(
            future: _refsFuture,
            builder: (context, snapshot) {
              final refs = snapshot.data ?? const RepoRefs();
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  // The checked-out branch leads the local list.
                  ..._sidebarSection(
                    'LOCAL',
                    [
                      if (refs.local.contains(refs.current)) refs.current!,
                      ...refs.local.where((name) => name != refs.current),
                    ],
                    refs.current,
                    null,
                  ),
                  ..._sidebarSection(
                    'REMOTE',
                    refs.remote,
                    null,
                    Icons.cloud_outlined,
                  ),
                  ..._sidebarSection(
                    'TAGS',
                    refs.tags,
                    null,
                    Icons.sell_outlined,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

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
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.8,
        ),
      ),
    ),
    for (final name in names)
      if (_filter.isEmpty || name.toLowerCase().contains(_filter.toLowerCase()))
        _sidebarItem(name, icon: icon, current: name == current),
  ];

  /// The committer color of the branch tip, so the sidebar dot matches the rail
  /// the branch sits on. Falls back to muted while that commit is unloaded.
  Color _refTipColor(String name) {
    for (final commit in _commits) {
      if (commit.refs.any((ref) => ref.name == name)) {
        return AvatarService.color(
          _committersBySha[commit.sha] ?? commit.committer,
        );
      }
    }
    return _muted;
  }

  Widget _sidebarItem(String name, {IconData? icon, required bool current}) =>
      GestureDetector(
        key: Key('sidebar-ref-$name'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectRef(name, remote: icon == Icons.cloud_outlined),
        child: Container(
          height: 28,
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
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: current ? _text : _muted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  // -------------------------------------------------------------- status bar

  Widget _statusBar() => Container(
    height: 29,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: _panelSoft,
      border: Border(top: BorderSide(color: _border)),
    ),
    child: Row(
      children: [
        _legend('commit', const _LegendDot()),
        _legend('merge', const _LegendDot(filled: true)),
        _legend('WIP', const _LegendDot(dashed: true)),
        const Spacer(),
        const Text(
          '둥근 직각 · 8px radius · 2px rail',
          style: TextStyle(color: _muted, fontSize: 10),
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
      // The title column takes whatever the other five leave, so the six always
      // fill the viewport — a dragged width is only a floor that widens it past
      // the fill, never a pin that leaves a dead strip on the right.
      final graphWidth = _graphColumnWidth;
      final fixed = _widths.values.reduce((a, b) => a + b) + graphWidth;
      final commitWidth = math.max(
        _commitWidth ?? timelineColumns['commit']!.min,
        constraints.maxWidth - fixed,
      );
      double width(String column) => switch (column) {
        'commit' => commitWidth,
        'graph' => graphWidth,
        _ => _w(column),
      };
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
                        _header(column, width(column)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    key: const Key('timeline-list'),
                    controller: _scrollController,
                    cacheExtent: 0,
                    itemExtent: _rowHeight,
                    itemCount: _commits.length + (_showFooter ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _commits.length) return _footer();
                      return _row(index, commitWidth, graphWidth);
                    },
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              color: _panelSoft,
              border: Border(
                bottom: BorderSide(color: _border),
                right: BorderSide(color: _border),
              ),
            ),
            child: Text(
              timelineColumns[column]!.label.toUpperCase(),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _muted,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                letterSpacing: 0.66,
              ),
            ),
          ),
        ),
        _resizer(column, width),
      ],
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
          onHorizontalDragUpdate: (details) =>
              _resize(column, width + details.delta.dx),
          onHorizontalDragEnd: (_) => _saveColumnWidths(),
          onHorizontalDragCancel: _saveColumnWidths,
        ),
      ),
    ),
  );

  /// Resizes from the width on screen, so dragging a flexing title column picks
  /// up where it is rather than jumping to a stored value.
  void _resize(String column, double next) {
    final spec = timelineColumns[column]!;
    final clamped = next.clamp(spec.min, spec.max);
    setState(() {
      if (column == 'commit') {
        _commitWidth = clamped;
      } else if (column == 'graph') {
        _graphWidth = clamped;
      } else {
        _widths[column] = clamped;
      }
    });
  }

  void _saveColumnWidths() => widget.onColumnWidthsChanged?.call(
    TimelineColumnWidths(
      refs: _w('refs'),
      graph: _graphWidth,
      hash: _w('hash'),
      commit: _commitWidth,
      time: _w('time'),
      name: _w('name'),
    ),
  );

  Widget _row(int index, double commitWidth, double graphWidth) {
    final row = _rows[index];
    final commit = row.commit;
    final selected = index == _selectedIndex;
    final committerColor = AvatarService.color(
      _committersBySha[commit.sha] ?? commit.committer,
    );
    final merge = commit.parents.length >= 2 && !commit.isWorkingTree;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoverIndex = index),
      onExit: (_) => setState(() {
        if (_hoverIndex == index) _hoverIndex = -1;
      }),
      child: GestureDetector(
        key: selected ? Key('selected-row-${commit.sha}') : null,
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectAndOpen(index),
        child: ColoredBox(
          color: selected
              ? _selectedRow
              : index == _hoverIndex
              ? _accent.withValues(alpha: 0.48)
              : _background,
          child: Row(
            children: [
              _refsCell(index, commit, committerColor, selected),
              SizedBox(
                key: Key('graph-cell-$index'),
                width: graphWidth,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // Transition curves sweep a full row, so the cell clips the
                    // halves that belong to the neighbouring rows.
                    Positioned.fill(
                      child: ClipRect(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            key: Key('graph-painter-$index'),
                            painter: CommitGraphPainter(
                              row: row,
                              previous: index > 0 ? _rows[index - 1] : null,
                              selected: selected,
                              committerColor: committerColor,
                              committersBySha: _committersBySha,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!commit.isWorkingTree && !merge)
                      Positioned(
                        left:
                            CommitGraphPainter.laneInset +
                            row.lane * CommitGraphPainter.defaultLaneSpacing -
                            9,
                        top: 9,
                        child: CommitAvatarStack(
                          commit: commit,
                          avatarService: widget.avatarService,
                          showRemoteAvatars: widget.showRemoteAvatars,
                          ringColor: committerColor,
                          ringWidth: CommitGraphPainter.railWidth,
                        ),
                      ),
                  ],
                ),
              ),
              _cell(
                _w('hash'),
                Text(
                  commit.isWorkingTree ? '·······' : commit.shortSha,
                  style: TextStyle(
                    color: selected ? _text : _hash,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                leftBorder: committerColor,
              ),
              _cell(
                commitWidth,
                Text(
                  commit.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 13),
                ),
              ),
              _cell(
                _w('time'),
                Text(
                  commit.isWorkingTree
                      ? 'working tree'
                      : _socialTime(commit.committerTimestamp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _text : _muted,
                    fontSize: 11,
                  ),
                ),
              ),
              _cell(
                _w('name'),
                commit.isWorkingTree
                    ? const Text(
                        '—',
                        style: TextStyle(color: _muted, fontSize: 11),
                      )
                    : Row(
                        children: [
                          CommitAvatarStack(
                            commit: commit,
                            avatarService: widget.avatarService,
                            showRemoteAvatars: widget.showRemoteAvatars,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              commit.author.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? _text
                                    : Color.lerp(_text, _main, 0.12),
                                fontSize: 11,
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

  Widget _refsCell(int index, GitCommit commit, Color color, bool selected) {
    return SizedBox(
      key: Key('refs-cell-$index'),
      width: _w('refs'),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _border)),
              ),
            ),
          ),
          if (commit.refs.isNotEmpty)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Chips pack toward the graph: the last one ends on the cell
                  // boundary, so the only connector left is the short run the
                  // graph cell paints from its own edge to the node.
                  final lastIndex = commit.refs.length - 1;
                  final available = math.max(0.0, constraints.maxWidth - 8);
                  final width = math.min(76.0, available);
                  final step = lastIndex == 0
                      ? 0.0
                      : math.max(0.0, (available - width) / lastIndex);
                  return Stack(
                    children: [
                      for (var index = 0; index < commit.refs.length; index++)
                        Positioned(
                          left:
                              constraints.maxWidth -
                              width -
                              (lastIndex - index) * step,
                          top: 6,
                          width: width,
                          height: 24,
                          child: _refChip(
                            commit,
                            commit.refs[index],
                            color,
                            selected,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

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
            if (ref.isHead || ref.isTag)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Text(
                  ref.isHead ? '✓' : '◇',
                  style: TextStyle(
                    color: selected ? _text : color,
                    fontSize: 9,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                ref.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: selected ? _text : color, fontSize: 10),
              ),
            ),
            // Branch chips carry their tip committer; tags belong to nobody.
            if (!ref.isTag) ...[
              const SizedBox(width: 4),
              _committerAvatar(
                commit,
                16,
                key: Key('ref-avatar-${commit.sha}-${ref.name}'),
              ),
            ],
          ],
        ),
      );

  Widget _committerAvatar(GitCommit commit, double size, {Key? key}) {
    final service = widget.showRemoteAvatars ? widget.avatarService : null;
    return SizedBox(
      key: key,
      width: size,
      height: size,
      child: service == null
          ? IdentityAvatar(identity: commit.committer, size: size)
          : FutureBuilder<CommitAvatars>(
              future: service.resolve(commit.sha),
              builder: (context, snapshot) => IdentityAvatar(
                identity: commit.committer,
                remoteAvatar: snapshot.data?.committer,
                size: size,
              ),
            ),
    );
  }

  Widget _cell(double width, Widget child, {Color? leftBorder}) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      border: Border(
        bottom: const BorderSide(color: _border),
        left: leftBorder == null
            ? BorderSide.none
            : BorderSide(color: leftBorder, width: 2),
      ),
    ),
    child: child,
  );

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

  Widget _preview() {
    final commit = _commits.isEmpty ? null : _commits[_selectedIndex];
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewHeader(commit),
          Expanded(
            child: commit == null
                ? const Center(
                    child: Text(
                      'No commit selected',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  )
                : _previewBody(commit, placement == PreviewPlacement.bottom),
          ),
        ],
      ),
    );
  }

  Widget _previewHeader(GitCommit? commit) => Container(
    height: 29,
    padding: const EdgeInsets.only(left: 12, right: 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _border)),
    ),
    child: Row(
      children: [
        const Flexible(
          child: Text(
            'Commit & Diff',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.66,
            ),
          ),
        ),
        const Spacer(),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: _muted,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 22),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 10),
          ),
          onPressed: commit == null ? null : _openFullDiff,
          child: const Text('Open full diff'),
        ),
        const SizedBox(width: 6),
        Text(
          commit == null
              ? '—'
              : commit.isWorkingTree
              ? 'WIP'
              : commit.shortSha,
          style: const TextStyle(
            color: _muted,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ],
    ),
  );

  Widget _previewBody(GitCommit commit, bool bottom) {
    final files = _previewFiles.putIfAbsent(
      commit.sha,
      () => widget.repository.loadFiles(commit),
    );
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
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              commit.isWorkingTree
                  ? 'Working tree changes'
                  : 'commit ${commit.sha}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _muted,
                fontSize: 10,
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
                    style: TextStyle(color: _muted, fontSize: 10),
                  ),
                )
              : _previewDiff(commit, selectedPath),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: bottom
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 240,
                      child: SingleChildScrollView(child: info),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: diff),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Flexible so a short window scrolls the summary instead of
                    // overflowing it.
                    Flexible(child: SingleChildScrollView(child: info)),
                    Expanded(child: diff),
                  ],
                ),
        );
      },
    );
  }

  Widget _previewPerson(GitCommit commit) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(
        top: BorderSide(color: _border),
        bottom: BorderSide(color: _border),
      ),
    ),
    child: Row(
      children: [
        commit.isWorkingTree
            ? Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _border),
                ),
              )
            : _committerAvatar(commit, 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                commit.isWorkingTree ? 'Not committed' : commit.committer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                commit.isWorkingTree
                    ? 'No commit object or committer'
                    : 'Committer · ${_socialTime(commit.committerTimestamp)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _previewStats(List<GitFileChange>? changes) {
    int total(int? Function(GitFileChange file) value) =>
        (changes ?? const []).fold(0, (sum, file) => sum + (value(file) ?? 0));
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Text(
            '${changes?.length ?? 0} '
            '${changes?.length == 1 ? 'file' : 'files'} changed',
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
          const Spacer(),
          Text(
            '+${total((file) => file.additions)}',
            style: const TextStyle(
              color: _main,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '−${total((file) => file.deletions)}',
            style: const TextStyle(
              color: _hash,
              fontSize: 10,
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
  ) => SizedBox(
    key: const Key('preview-files'),
    height: 92,
    child: failed
        ? const Center(
            child: Text(
              'Could not load files',
              style: TextStyle(color: Color(0xFFF29AB2), fontSize: 10),
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
              style: TextStyle(color: _muted, fontSize: 10),
            ),
          )
        : ListView.builder(
            itemExtent: 29,
            itemCount: changes.length,
            itemBuilder: (context, index) {
              final file = changes[index];
              final selected = file.path == selectedPath;
              return InkWell(
                onTap: () =>
                    setState(() => _previewPaths[commit.sha] = file.path),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected ? _accent : null,
                    border: const Border(
                      top: BorderSide(color: Color(0x66343946)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        key: Key('preview-state-${file.path}'),
                        width: 18,
                        height: 18,
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
                            fontSize: 9,
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
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<DiffLine>>(
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
                    style: TextStyle(color: Color(0xFFF29AB2), fontSize: 10),
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
              return ListView.builder(
                itemExtent: 18,
                itemCount: lines.length,
                itemBuilder: (context, index) {
                  final line = lines[index];
                  final prefix = switch (line.kind) {
                    DiffLineKind.add => '+',
                    DiffLineKind.delete => '-',
                    // The hunk header reads as its own line, like the mockup.
                    DiffLineKind.hunk => '',
                    _ => ' ',
                  };
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
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
                        color:
                            line.kind == DiffLineKind.hunk ||
                                line.kind == DiffLineKind.header
                            ? _muted
                            : _text,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _openFullDiff() {
    final commit = _commits[_selectedIndex];
    if (widget.onOpenFullDiff case final callback?) {
      callback(commit);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DiffScreen(
          repository: widget.repository,
          commits: List.unmodifiable(_commits),
          initialIndex: _selectedIndex,
        ),
      ),
    );
  }
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
  });

  static const laneInset = 28.0;
  static const defaultLaneSpacing = 30.0;
  static const railWidth = 2.0;

  /// Rails are opaque.
  static const railOpacity = 1.0;
  static const connectorWidth = 2.0;
  static const nodeRadius = 6.0;
  static const wipNodeRadius = 8.0;
  static const wipNodeDash = 2.5;

  /// A transition runs along a jog line this far above the arrival center, and
  /// turns onto and off it with quarter arcs.
  static const jogInset = 8.0;
  static const departureRadius = 5.0;
  static const arrivalRadius = 8.0;

  final GraphRow row;
  final bool selected;
  final Color committerColor;

  /// The row above. A lane transition sweeps a full row height, so its arrival
  /// half belongs to this row's cell and is derived from [previous].
  final GraphRow? previous;
  final Map<String, GitIdentity> committersBySha;
  final double laneSpacing;

  double laneX(int lane) => laneInset + lane * laneSpacing;

  /// The straight vertical rails [row] hands down past its node center, keyed by
  /// lane. A rail that moves — a branch, a merge, or a git-style collapse slide —
  /// is left to its transition path, and so is a lane a movement lands in that
  /// carried no rail of its own.
  static Set<int> railsBelow(GraphRow row) {
    final departing = {
      for (final transition in row.transitions) transition.from,
    };
    final arriving = {for (final transition in row.transitions) transition.to};
    return {
      for (final lane in row.nextLanes)
        if (lane == row.lane
            // The node hands its first parent straight down, unless its lane
            // emptied here and a slide refilled it.
            ? !arriving.contains(lane)
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
    if (selected) {
      canvas.drawRect(
        selectedBandRect(size),
        Paint()..color = committerColor.withValues(alpha: 0.22),
      );
    }

    // Halves are painted apart: above the node a lane carries the rail it waits
    // for, below it the rail it hands down.
    for (final entry in laneVerticals(size).entries) {
      final x = laneX(entry.key);
      if (entry.value.top < centerY) {
        canvas.drawLine(
          Offset(x, entry.value.top),
          Offset(x, centerY),
          _railPaint(row.activeLaneShas[entry.key]),
        );
      }
      if (entry.value.bottom > centerY) {
        canvas.drawLine(
          Offset(x, centerY),
          Offset(x, entry.value.bottom),
          _railPaint(row.nextLaneShas[entry.key]),
        );
      }
    }

    // Arrival halves of the movements the row above started, then this row's own
    // departures. Every lane movement is a transition, so the two lists are the
    // whole story.
    for (final transition in previous?.transitions ?? const []) {
      canvas.drawPath(
        transitionPath(
          transition.from,
          transition.to,
          centerY - size.height,
          size,
        ),
        _railPaint(transition.sha),
      );
    }
    for (final transition in row.transitions) {
      canvas.drawPath(
        transitionPath(transition.from, transition.to, centerY, size),
        _railPaint(transition.sha),
      );
    }
    final nodeX = laneX(row.lane);
    if (row.commit.refs.isNotEmpty) {
      canvas.drawLine(
        Offset.zero.translate(0, centerY),
        Offset(nodeX, centerY),
        Paint()
          ..color = committerColor
          ..strokeWidth = connectorWidth
          ..strokeCap = StrokeCap.round,
      );
    }
    if (row.commit.isWorkingTree) {
      _drawWorkingTreeNode(canvas, Offset(nodeX, centerY));
    } else if (showsMergeDot) {
      canvas.drawCircle(
        Offset(nodeX, centerY),
        nodeRadius,
        Paint()..color = committerColor,
      );
    }
  }

  /// The working tree ring takes the lane color of the commit it sits on, which
  /// for the working tree row is `HEAD` — its own sha is empty and carries no
  /// committer.
  Color get workingTreeRingColor => AvatarService.color(
    committersBySha[row.nextLaneShas[row.lane] ??
            row.activeLaneShas[row.lane]] ??
        row.commit.committer,
  );

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

  /// One lane transition: straight down, a rounded right angle onto the jog
  /// line, across, then a rounded right angle down into the arrival lane. It
  /// spans a whole row height from a node center at [startY] to the next row's
  /// center, and both rows paint the same path — the child from its own center,
  /// the next row with [startY] a row height above its center — so the halves
  /// meet exactly. Distant lanes only lengthen the horizontal run.
  Path transitionPath(int from, int to, double startY, Size size) {
    final x0 = laneX(from);
    final x1 = laneX(to);
    final endY = startY + size.height;
    final jogY = endY - jogInset;
    final direction = x1 > x0 ? 1.0 : -1.0;
    final half = (x1 - x0).abs() / 2;
    final out = math.min(math.min(departureRadius, half), jogY - startY);
    final into = math.min(math.min(arrivalRadius, half), endY - jogY);
    return Path()
      ..moveTo(x0, startY)
      ..lineTo(x0, jogY - out)
      ..quadraticBezierTo(x0, jogY, x0 + direction * out, jogY)
      ..lineTo(x1 - direction * into, jogY)
      ..quadraticBezierTo(x1, jogY, x1, jogY + into)
      ..lineTo(x1, endY);
  }

  Paint _railPaint(String? sha) => Paint()
    ..color = AvatarService.color(committersBySha[sha] ?? row.commit.committer)
    ..style = PaintingStyle.stroke
    ..strokeWidth = railWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  bool shouldRepaint(covariant CommitGraphPainter oldDelegate) =>
      oldDelegate.row != row ||
      oldDelegate.previous != previous ||
      oldDelegate.selected != selected ||
      oldDelegate.committerColor != committerColor ||
      oldDelegate.committersBySha != committersBySha ||
      oldDelegate.laneSpacing != laneSpacing;
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

String _socialTime(int timestamp) => socialTimeLabel(
  DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
  ),
);

/// Long-form relative time, as the mockup spells it out.
String socialTimeLabel(Duration elapsed) {
  String ago(int value, String unit) =>
      '$value $unit${value == 1 ? '' : 's'} ago';
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return ago(elapsed.inMinutes, 'minute');
  if (elapsed.inDays < 1) return ago(elapsed.inHours, 'hour');
  if (elapsed.inDays == 1) return 'yesterday';
  if (elapsed.inDays < 30) return ago(elapsed.inDays, 'day');
  if (elapsed.inDays < 365) return ago(elapsed.inDays ~/ 30, 'month');
  return ago(elapsed.inDays ~/ 365, 'year');
}
