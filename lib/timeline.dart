import 'dart:async';
import 'dart:io'
    show Directory, FileSystemEvent, FileSystemException, ProcessException;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'avatars.dart';
import 'commit_time.dart';
import 'commit_profile_chip.dart';
import 'external_editor.dart';
import 'full_diff_commit_message_cache.dart';
import 'full_diff_controller.dart';
import 'full_diff_model.dart';
import 'full_diff_resizable_pane.dart';
import 'full_diff_shortcut_hint.dart';
import 'full_diff_side_by_side_view.dart';
import 'full_diff_syntax.dart';
import 'full_diff_unified_view.dart';
import 'full_diff_theme.dart';
import 'full_diff_workspace.dart';
import 'full_history_view.dart';
import 'fuzzy_match.dart';
import 'git.dart';
import 'monaco_editor_screen.dart';
import 'page_scroll_shortcuts.dart';
import 'preview_header.dart';
import 'timeline_graph_painters.dart';
import 'timeline_model.dart';
import 'timeline_widgets.dart';
import 'timeline_palette.dart';
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

/// The graph's painters live in their own library; the timeline is still the
/// door they are reached through.
export 'timeline_graph_painters.dart';
export 'timeline_model.dart';
export 'timeline_widgets.dart';
import 'yogit_alert.dart';

part 'timeline_branch_preview.dart';
part 'timeline_diff_mode.dart';
part 'timeline_preview_pane.dart';
part 'timeline_rows.dart';
part 'timeline_sidebar.dart';

/// The date group heading's box and label.
const _dateGroup = Color(0xFF5AB0FF);

/// Below this the diff has nothing left to show, so History steps aside.
const _minDiffWidth = 320.0;

/// A ref chip narrower than this is unreadable, so the extra chips hide instead.
const _minChipWidth = 40.0;

/// What a shortened ref name is marked with, wherever it gave way.

/// Long enough that arrowing past a row does not flash tooltips.
const _tooltipDelay = Duration(milliseconds: 400);

/// The status bar's commit stamp: a fixed-width format in a monospace face, so
/// its width can be measured from a sample rather than the live value.
const _statusStampStyle = TextStyle(fontSize: 11, fontFamily: 'monospace');

/// How many rows of road the selection keeps ahead of it before the list moves.
const _selectionScrollMargin = 2;

/// How much of a commit message the panel shows before it scrolls in place.
const _previewMessageLines = 10;
const _previewMessageLine = 17.4;

const _rebaseMappingAvatarBorderWidth = 3.0;

/// [name] cut to fit [maxWidth], with [measure] reporting how wide a candidate
/// draws in the style it will be drawn in.
///
/// The useful half of a branch or tag name is its end, so the front is what
/// gives way: leading namespace segments shrink to their first letter
/// (`codex/branch-lane` → `c…/branch-lane`), and only when that still does not
/// fit do characters drop off the front behind a leading ellipsis. The tail is
/// never cut. A width too narrow even for the ellipsis still gets the ellipsis:
/// an empty chip says less than a marked one.
enum BranchApplyStatus { idle, applying, applied, reverting, reverted, failed }

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

enum _RefSection {
  local('LOCAL', Icons.computer_outlined),
  remote('REMOTE', Icons.cloud_outlined),
  tags('TAGS', Icons.sell_outlined);

  const _RefSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    required this.repository,
    this.controller,
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
    this.timelineFont = TimelineFontChoice.system,
    this.timelineFontSize,
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
  static const rowHeight = 22.0;

  final GitRepository repository;
  final WindowFrameController? controller;
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

  /// The face every text column is set in, from settings.
  final TimelineFontChoice timelineFont;

  /// The commit message column's size; null takes the family's own default.
  final double? timelineFontSize;

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

  /// The commit message's size, and the face every text column shares.
  double get _baseFontSize =>
      widget.timelineFontSize ?? widget.timelineFont.defaultFontSize;
  String? get _fontFamily => widget.timelineFont.fontFamily;

  /// Branch / Tag, Date and Author sit a point under the message so the row
  /// keeps its hierarchy at any size, with 9px as the floor they stop at.
  double get _supportingFontSize => math.max(9, _baseFontSize - 1);

  /// The graph disc's initials were drawn at 0.42 of the disc against a 13px
  /// base, so they scale by how far the base has moved from there. The disc
  /// itself never changes size — a row is [TimelineScreen.rowHeight] whatever
  /// the font says.
  double get _initialsFontScale =>
      _baseFontSize / TimelineFontChoice.system.defaultFontSize;

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
  final _previewMessageScrollController = ScrollController();
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
  late double? _graphWidth = widget.columnWidths.graph;
  late double _sidebarWidth = widget.columnWidths.sidebar;
  late bool _showTime = widget.columnWidths.showTime;
  late bool _showName = widget.columnWidths.showName;

  /// The preview text the user last selected. ⌘C copies it, and a test can read
  /// it to prove that dragging over the panel really selects.
  @visibleForTesting
  String? debugPreviewSelection;

  /// Where the Date column starts, so the status bar can line its stamp up with
  /// it. Written while the timeline lays out, read by the status bar built right
  /// after it in the same frame.
  var _hashColumnLeft = 0.0;

  /// How wide the title column is on screen: the leftover the other five leave.
  /// The layout writes it every frame, and a divider drag spends it — the column
  /// has no stored width of its own, so this is what a drag or a fit measures
  /// against, and what stops the two from handing away width that is not there.
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

  /// Non-null while the diff takes over the sidebar and timeline area.
  FullDiffSessionController? _fullDiffSession;

  /// Mirrored from the session so opening History or 집중 모드 relays out the
  /// panes without rebuilding them on every scroll notification.
  var _fullDiffHistoryOpen = false;
  var _fullDiffFocusMode = false;
  late double _historyWidth = widget.fullDiffColumnWidths.history;
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

  /// Whether the drag in progress has moved a divider at all, and which divider
  /// was last clicked without moving, for spotting the second click.
  var _dragResized = false;
  String? _lastResizerClick;
  int _lastResizerClickMs = 0;

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
    _previewFocusNode.addListener(_onPaneFocusChanged);
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
      _closeFullDiff();
      _clearPendingFullDiffPersistence();
    } else if (widget.onFullDiffPreferencesChanged !=
            oldWidget.onFullDiffPreferencesChanged ||
        widget.onFullDiffColumnWidthsChanged !=
            oldWidget.onFullDiffColumnWidthsChanged) {
      _scheduleFullDiffPersistenceFlush();
    }
    if (widget.columnWidths != oldWidget.columnWidths) {
      _widths.addAll(_widthMap(widget.columnWidths));
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
    if (widget.fullDiffColumnWidths.history !=
        oldWidget.fullDiffColumnWidths.history) {
      _historyWidth = widget.fullDiffColumnWidths.history;
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
    _fullDiffSession
      ?..removeListener(_followFullDiffSession)
      ..dispose();
    _clearPendingFullDiffPersistence();
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
    _previewFocusNode.removeListener(_onPaneFocusChanged);
    _previewFocusNode.dispose();
    _historyPaneFocusNode.dispose();
    _diffFocusNode.dispose();
    _previewMessageScrollController.dispose();
    super.dispose();
  }

  /// Every column with a width of its own. `graph` fits the deepest loaded lane
  /// until dragged, and `commit` takes whatever the other five leave.
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
      // → (or l) walks the other way, into the preview and its diff.
      if (key == LogicalKeyboardKey.arrowRight && event is KeyDownEvent) {
        _enterPreview();
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // The panel's own copy shortcut only fires while the panel holds the
    // keyboard, and the timeline never lets go of it. Hand the selection over
    // ourselves so dragging over the preview and pressing ⌘C does what it says.
    if (event.logicalKey == LogicalKeyboardKey.keyC && shortcutModifierHeld) {
      final selection = debugPreviewSelection;
      if (selection == null || selection.isEmpty) {
        return KeyEventResult.ignored;
      }
      unawaited(Clipboard.setData(ClipboardData(text: selection)));
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
      if (_fullDiffOpen) {
        _closeFullDiff();
      } else if (_previewDiffOpen) {
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

  /// The selection walks the visible rows without moving the list; the list
  /// starts moving while two rows of road are still ahead, so the cursor never
  /// runs into the edge before the view answers.
  void _scrollToSelection({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final rowTop = _selectedIndex.value * TimelineScreen.rowHeight;
    final rowBottom = rowTop + TimelineScreen.rowHeight;
    const margin = _selectionScrollMargin * TimelineScreen.rowHeight;
    final double? target =
        rowBottom + margin > position.pixels + position.viewportDimension
        ? rowBottom + margin - position.viewportDimension
        : rowTop - margin < position.pixels
        ? rowTop - margin
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
    if (closing) _closeFullDiff();
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
  final _previewFocusNode = FocusNode(debugLabel: 'preview');
  final _historyPaneFocusNode = FocusNode(debugLabel: 'history pane');
  final _diffFocusNode = FocusNode(debugLabel: 'diff');

  /// Extensions in this library rebuild through here: `setState` is protected,
  /// and an extension is not the class itself.
  void _rebuild(VoidCallback change) => setState(change);

  void _onPaneFocusChanged() {
    if (mounted) setState(() {});
  }

  /// The unfocused pane keeps its selection, drained of color: same
  /// luminance, zero chroma, so only the focused pane reads as active.
  static Color _achromatic(Color color) {
    final gray = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
    return Color.from(alpha: color.a, red: gray, green: gray, blue: gray);
  }

  /// What a selection fades to while its pane has no keyboard: the same weight
  /// a hovered row carries, enough to keep the place without claiming focus.
  Color get _restingSelection => _palette.neutralChip.withValues(alpha: 0.48);

  /// The timeline's selection color, resting while another pane has the
  /// keyboard.
  Color get _timelineSelectionColor =>
      _sidebarFocusNode.hasFocus || _previewFocusNode.hasFocus
      ? _restingSelection
      : _palette.selectedRow;

  /// The preview's, under the same rule.
  Color get _previewSelectionColor =>
      _previewFocusNode.hasFocus ? _palette.selectedRow : _restingSelection;

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

  /// The remote branch a pull or checkout is currently running for. One at a
  /// time: the sidebar shows a spinner on this row and ignores further asks.
  String? _pullingRemote;

  String? _lastRemoteRowTap;
  int _lastRemoteRowTapMs = 0;

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
                if (!_fullDiffOpen) _sidebar(),
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
    final session = _fullDiffSession;
    // Diff mode takes the timeline's place; the preview keeps its own.
    final timeline = session == null
        ? Expanded(
            key: const Key('timeline-viewport'),
            child: KeyedSubtree(key: _timelineKey, child: _timeline()),
          )
        : Expanded(child: _embeddedFullDiff(session));
    // 집중 모드 leaves the diff alone on screen; the preview only hides, its
    // placement setting is untouched.
    final wantsHistory =
        session != null && _fullDiffHistoryOpen && !_fullDiffFocusMode;
    final historyWidth = wantsHistory
        ? _historyWidth.clamp(
            FullDiffColumnWidths.minHistory,
            FullDiffColumnWidths.maxHistory,
          )
        : 0.0;
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
      final history =
          wantsHistory && constraints.maxWidth - historyWidth >= _minDiffWidth
          ? _historyPane(session)
          : null;
      final previewWidth = math.max(0.0, constraints.maxWidth - historyWidth);
      final preview = _animatedPreview(
        axis: Axis.vertical,
        extent: extent,
        width: previewWidth,
        height: extent,
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
          if (_fullDiffFocusMode)
            const SizedBox.shrink()
          else if (history == null)
            preview
          else
            SizedBox(
              height: extent,
              child: Row(children: [preview, history]),
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
    // The diff keeps a working width: History yields before it is squeezed.
    final history =
        wantsHistory &&
            constraints.maxWidth - extent - historyWidth >= _minDiffWidth
        ? _historyPane(session)
        : null;
    final preview = _fullDiffFocusMode
        ? null
        : _animatedPreview(
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
          ? [?preview, ?history, if (_previewDiffOpen) diff, timeline]
          : [timeline, if (_previewDiffOpen) diff, ?history, ?preview],
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
                  child: Wordmark(key: const Key('wordmark'), fontSize: size),
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

  /// A merge or rebase preview is worth seeing the moment it exists, so the
  /// detail pane opens itself rather than waiting for a conflict to force it.
  /// A pane the user already placed is left where it is.
  Future<void> _openPaneForBranchPreview() async {
    if (_comparison == null || !mounted) return;
    if (_previewController.previewPlacement != PreviewPlacement.closed) return;
    await _previewController.setPreview(widget.preferredPreviewPlacement);
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
      HoverBuilder(
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

  Widget _placementButton(String label, PreviewPlacement placement) {
    final pressed = _activePlacement == placement;
    return HoverBuilder(
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
      KeyCap(
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
                      _legend('commit', const LegendDot()),
                      _legend('merge', const LegendDot(filled: true)),
                      _legend('WIP', const LegendDot(dashed: true)),
                    ],
                  )
                : Row(
                    children: [
                      Text(
                        '원격 갱신 실패',
                        style: TextStyle(color: behindOrange, fontSize: 10),
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
                      child: _fittedRefName(
                        name,
                        TextStyle(color: _palette.muted, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 6),
                    CopyButton(
                      // Shortened on screen, whole on the clipboard.
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
                  warningColor: behindOrange,
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
      // space. Its divider therefore moves by resizing Date and Author, and the
      // viewport decides the rest — down to the 100px minimum on a narrow
      // window.
      final commitWidth = math.max(timelineColumns['commit']!.min, available);
      _commitAvailableWidth = commitWidth;
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

  bool get _branchApplyBusy =>
      _branchApplyStatus == BranchApplyStatus.applying ||
      _branchApplyStatus == BranchApplyStatus.reverting;

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
        CommitMessageDialog(
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
        // 훑고 지나가는 건 가상 행이라 그래프가 정한 키로 찾는다.
        final rebaseMappings = _previewGraph?.mappings ?? const [];
        for (var index = 0; index < preview.rewritten.length; index++) {
          if (!mounted || request != _branchApplySerial) return;
          final sha = index < rebaseMappings.length
              ? rebaseMappings[index].rewrittenSha
              : preview.rewritten[index].rewrittenSha;
          final row = _comparisonRows.indexWhere(
            (entry) => entry.commit.sha == sha,
          );
          setState(() => _rebaseApplyingSha = sha);
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
                  ? previewPurple.withValues(alpha: 0.08)
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
                            ? previewPurple
                            : const Color(0xFF8A8494),
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: previewPurple,
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

  /// The refs cell pads itself instead: the right gutter is where the chip's
  /// connector line runs out to the graph.
  static const _refsCellInset = 14.0;

  /// A chip's own horizontal padding, and the room its ✓/◇ glyph takes with the
  /// gap after it — the same allowance the ref modal sizes itself by.
  static const _refChipPadding = 10.0;
  static const _refGlyphWidth = 16.0;

  /// Every box a row draws inside itself — a ref chip, a date heading — is this
  /// tall, which is [TimelineScreen.rowHeight] less the hairline of background
  /// the row keeps above and below so stacked chips never touch.
  static const _rowChipHeight = TimelineScreen.rowHeight - 2;

  /// The header label and the hash cell, without the colors that come and go
  /// with hover and selection. Shared with the double-click fit, which measures
  /// what these two actually draw.
  static const _headerLabelStyle = TextStyle(
    fontSize: 12,
    fontFamily: 'monospace',
    fontWeight: FontWeight.w500,
    letterSpacing: 0.66,
  );
  static const _hashStyle = TextStyle(
    fontSize: 12,
    fontFamily: technicalFontFamily,
    fontFamilyFallback: technicalFontFallback,
    fontWeight: FontWeight.w500,
  );

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
                          style: _headerLabelStyle.copyWith(
                            color: hovered == column
                                ? _palette.text
                                : _palette.muted,
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
        _resizeBy(column, width, delta);
        _saveColumnWidths();
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: Key('$column-resizer'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _startResize(column),
          onHorizontalDragUpdate: (details) {
            _dragResized = true;
            _resizeBy(column, width, details.delta.dx);
          },
          onHorizontalDragEnd: (_) => _finishResize(column),
          onHorizontalDragCancel: () => _finishResize(column),
        ),
      ),
    ),
  );

  /// Double-clicking a divider fits its column to the widest thing the column
  /// draws right now — its header and every loaded row — clamped to the column's
  /// own range and to the width the other columns leave it.
  void _fitColumn(String column) {
    // The graph column already has a fit of its own — the deepest loaded lane —
    // so a double click hands it back to that instead of measuring text.
    if (column == 'graph') {
      if (_graphWidth == null) return;
      setState(() => _graphWidth = null);
      _saveColumnWidths();
      return;
    }
    final spec = timelineColumns[column]!;
    // The title column holds no width to set, so it fits the same way its
    // divider drags: the difference between what it draws and what it needs goes
    // to Date and Author, or comes back from them. They may not take more than
    // their maximums or give up more than their minimums, so a fit narrower than
    // they can absorb lands as close as they allow — the row stays inside the
    // viewport either way.
    if (column == 'commit') {
      final fitted = _contentWidth('commit').clamp(spec.min, spec.max);
      _resizeCommit(fitted - _commitAvailableWidth, collapse: false);
      _saveColumnWidths();
      return;
    }
    final taken = timelineColumns.keys
        .where((other) => other != column && _columnVisible(other))
        .fold(
          0.0,
          (sum, other) =>
              sum +
              switch (other) {
                'commit' => timelineColumns['commit']!.min,
                'graph' => _graphColumnWidth,
                _ => _w(other),
              },
        );
    final fitted = _contentWidth(column)
        .clamp(
          spec.min,
          math.max(
            spec.min,
            math.min(spec.max, _timelineViewportWidth - taken),
          ),
        )
        .toDouble();
    if (fitted == _w(column)) return;
    setState(() => _widths[column] = fitted);
    _saveColumnWidths();
  }

  /// What [column] would need to clip nothing: its header label and its widest
  /// loaded row, plus the insets the cell pads its text by.
  double _contentWidth(String column) {
    var widest = _textWidth(
      timelineColumns[column]!.label.toUpperCase(),
      _headerLabelStyle,
    );
    for (final entry in _entries) {
      // A date heading spans the row instead of sitting inside one column.
      if (entry.rowIndex < 0) continue;
      widest = math.max(widest, _rowContentWidth(column, entry.row.commit));
    }
    return widest +
        switch (column) {
          // The refs cell keeps its own gutters, one of them for the connector.
          'refs' => _refsCellInset * 2,
          'hash' => _railedColumnTextInset + _columnTextInset,
          _ => _columnTextInset * 2,
        };
  }

  /// Chips split the cell into equal slots, so a row needs its widest chip in
  /// every slot it fills — not the sum of the chips it happens to carry.
  double _refsContentWidth(GitCommit commit) {
    final refs = _rowRefs(commit);
    var widest = 0.0;
    for (final ref in refs) {
      widest = math.max(
        widest,
        _textWidth(ref.name, _refNameStyle(_palette.text)) +
            (ref.isHead || ref.isTag ? _refGlyphWidth : 0) +
            _refChipPadding,
      );
    }
    return widest * refs.length;
  }

  double _textWidth(String text, TextStyle style) => (TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout()).width;

  void _startResize(String column) {
    _dragResized = false;
    _resizeStartWidths = {
      if (column == 'commit' || column == 'time') 'time': _w('time'),
      if (column == 'commit' || column == 'time' || column == 'name')
        'name': _w('name'),
    };
  }

  /// A drag that never moved is a click, and two of them inside the
  /// double-click window fit the column. The counting happens here rather than
  /// through an `onDoubleTap`, because a second recognizer in the divider's
  /// gesture arena would cost the drag its first 18px before it starts.
  void _finishResize(String column) {
    _resizeStartWidths = const {};
    if (_dragResized) {
      _dragResized = false;
      _lastResizerClick = null;
      _saveColumnWidths();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastResizerClick == column &&
        now - _lastResizerClickMs <= kDoubleTapTimeout.inMilliseconds) {
      _lastResizerClick = null;
      _fitColumn(column);
      return;
    }
    _lastResizerClick = column;
    _lastResizerClickMs = now;
  }

  /// Moves the divider on [column]'s right edge by the distance the cursor just
  /// travelled.
  ///
  /// The two dividers around the title column move by transfer rather than by
  /// setting a width, because the title column absorbs whatever the fixed
  /// columns leave. Widening Date used to shrink the title column by the same
  /// amount and leave the dragged line exactly where it was, with Author
  /// untouched; narrowing the title column changed a width nothing drew. The
  /// column the drag shrinks gives up the whole distance — that is what keeps
  /// the line under the cursor — and the other takes as much of it as its own
  /// maximum allows, so the row never totals more than it did.
  void _resizeBy(String column, double width, double delta) {
    if (column == 'commit') {
      _resizeCommit(delta);
      return;
    }
    if (column != 'time' || !_showName) {
      _resize(column, width + delta);
      return;
    }
    final time = timelineColumns['time']!;
    final name = timelineColumns['name']!;
    final timeWidth = _w('time');
    final nameWidth = _w('name');
    // Both ends bound the transfer: what one column can give AND what the
    // other can take. Otherwise a column sitting at its own limit would keep
    // taking width from its neighbour while the line under the cursor stayed
    // put — the very thing this method exists to prevent.
    if (delta > 0) {
      if (nameWidth <= name.min) {
        _hideColumn('name', restoreWidth: _resizeStartWidths['name']);
        return;
      }
      final given = math.min(
        delta,
        math.min(nameWidth - name.min, time.max - timeWidth),
      );
      if (given <= 0) return;
      setState(() {
        _widths['name'] = nameWidth - given;
        _widths['time'] = timeWidth + given;
      });
    } else if (delta < 0) {
      if (timeWidth <= time.min) {
        _hideColumn('time', restoreWidth: _resizeStartWidths['time']);
        return;
      }
      final given = math.min(
        -delta,
        math.min(timeWidth - time.min, name.max - nameWidth),
      );
      if (given <= 0) return;
      setState(() {
        _widths['time'] = timeWidth - given;
        _widths['name'] = nameWidth + given;
      });
    }
  }

  /// Resizes from the width on screen, so dragging a flexing title column picks
  /// up where it is rather than jumping to a stored value.
  void _resize(String column, double next) {
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

  /// Moves the title column's right-hand divider by [delta], the only way that
  /// column resizes: it holds no width of its own, so the line moves by taking
  /// width from Date and Author or handing it back to them. Date goes first —
  /// the divider touches it — and Author takes over once Date is at its limit.
  /// The line stops where both of them run out.
  ///
  /// [collapse] is what separates a drag from a fit: dragging right past Date's
  /// minimum hides Date and keeps going, while a fit only ever resizes.
  void _resizeCommit(double delta, {bool collapse = true}) {
    if (delta > 0) {
      var taking = delta;
      var hidColumn = false;
      setState(() {
        for (final column in const ['time', 'name']) {
          if (taking <= 0 || !_columnVisible(column)) continue;
          final spec = timelineColumns[column]!;
          final shrink = math.min(taking, _w(column) - spec.min);
          _widths[column] = _w(column) - shrink;
          taking -= shrink;
          _commitAvailableWidth += shrink;
          if (!collapse || taking <= 0 || _w(column) > spec.min) continue;
          // At its minimum with the drag still going: the column goes, and the
          // minimum it was holding goes to the title column with it. The width
          // it had when the drag started is what a later restore hands back.
          taking = math.max(0, taking - _w(column));
          _commitAvailableWidth += _w(column);
          _widths[column] = _resizeStartWidths[column] ?? _w(column);
          if (column == 'time') {
            _showTime = false;
          } else {
            _showName = false;
          }
          hidColumn = true;
        }
      });
      if (hidColumn) _saveColumnWidths();
      return;
    }
    // Going the other way the title column is the one that pays, so it may only
    // hand over what it has above its own minimum — otherwise the row would
    // outgrow the viewport and open a horizontal scroll the timeline never has.
    var giving = math.min(
      -delta,
      _commitAvailableWidth - timelineColumns['commit']!.min,
    );
    if (giving <= 0) return;
    setState(() {
      for (final column in const ['time', 'name']) {
        if (giving <= 0 || !_columnVisible(column)) continue;
        final grow = math.min(
          giving,
          timelineColumns[column]!.max - _w(column),
        );
        if (grow <= 0) continue;
        _widths[column] = _w(column) + grow;
        giving -= grow;
        _commitAvailableWidth -= grow;
      }
    });
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
        ? previewConflict
        : previewPurple,
    previewMergeArrow:
        _previewGraph?.kinds[entry.row.commit.sha] ==
        PreviewGraphNodeKind.virtualMerge,
    outgoingRailColor: outgoingRailColor,
    backgroundColor: _palette.background,
    selectedRowColor: _timelineSelectionColor,
  );

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

  TextStyle _refNameStyle(Color color) => TextStyle(
    color: color,
    fontFamily: _fontFamily,
    fontSize: _supportingFontSize,
  );

  /// A chip gives its name up from the front to fit its share of the cell — see
  /// [fitRefName], which the chip measures against the room it actually got.
  /// The modal sizes itself to its longest name instead, so it shows every name
  /// whole. A name longer than the whole viewport is the one case the modal
  /// cannot grow for, and it flexes rather than pushing the copy button out of
  /// its own box.
  Widget _refName(
    GitRef ref,
    Color color,
    bool selected, {
    bool ellipsis = true,
  }) {
    final style = _refNameStyle(selected ? _palette.text : color);
    return ellipsis
        ? Expanded(child: _fittedRefName(ref.name, style))
        : Flexible(
            child: Text(
              ref.name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: style,
            ),
          );
  }

  /// [name] drawn in whatever room it was given. A real branch or tag gives way
  /// from the front — see [fitRefName] — and the status bar readout, which names
  /// a line's branch in the width of the chip column, does the same.
  ///
  /// A branch preview labels its chips `기준브랜치 · 가상` instead, where the
  /// branch sits at the front and the annotation after it is what can go, so
  /// those keep giving way from the right.
  Widget _fittedRefName(String name, TextStyle style) => _comparison != null
      ? Text(
          name,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        )
      : LayoutBuilder(
          builder: (context, constraints) => Text(
            fitRefName(
              name,
              constraints.maxWidth,
              (text) => _textWidth(text, style),
            ),
            maxLines: 1,
            softWrap: false,
            // The string is already cut to the width; clip only guards against
            // a font that draws a shade wider than it measures.
            overflow: TextOverflow.clip,
            style: style,
          ),
        );

  /// The width the timeline viewport has, for clamping the ref modal.
  double get _timelineViewportWidth {
    final box = _timelineKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.width : 320;
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
          ? (text: '충돌', color: previewConflict, textColor: previewConflict)
          : (text: '가상', color: previewPurple, textColor: previewPurple);
    }
    if (kind == PreviewGraphNodeKind.virtualRebaseMerge) {
      return (
        text: '가상 머지',
        color: previewPurple,
        textColor: const Color(0xFFE4D4FF),
      );
    }
    final preview = _rebasePreview;
    if (preview == null) return null;
    // 가상 행의 키는 그래프가 정한다. sha가 그대로인 재배치에서 원본 sha로 찾으면
    // 재작성 라벨이 원본 행에 붙는다. 충돌 미리보기는 가상 행이 없어 짝도 비니, 그때만
    // 예전대로 재배치 결과에서 찾는다.
    final rebaseMappings = _previewGraph?.mappings ?? const [];
    final rewrittenIndex = rebaseMappings.isEmpty
        ? preview.rewritten.indexWhere(
            (rewrite) => rewrite.rewrittenSha == commit.sha,
          )
        : rebaseMappings.indexWhere(
            (mapping) => mapping.rewrittenSha == commit.sha,
          );
    if (rewrittenIndex >= 0) {
      return (
        text: '재작성 ${rewrittenIndex + 1}/${preview.total}',
        color: previewPurple,
        textColor: previewPurple,
      );
    }
    if (preview.status != RebasePreviewStatus.conflict) return null;
    if (preview.currentCommit?.sha == commit.sha) {
      return (
        text: '충돌 해결 중',
        color: previewConflict,
        textColor: const Color(0xFFFFC4C8),
      );
    }
    if (preview.rewritten.any(
      (rewrite) => rewrite.original.sha == commit.sha,
    )) {
      return (text: '해결 완료', color: previewPurple, textColor: previewPurple);
    }
    if (!_isCompareOnly(commit.sha)) return null;
    // 재배치는 patch-id가 이미 base에 있는 커밋을 재생하지 않는다. 미리보기가 그
    // 커밋을 지나가도 재작성본이 생기지 않으니 남은 '다음' 대신 건너뛴 사실을 적는다.
    return _duplicateCommits.contains(commit.sha)
        ? (
            text: '건너뜀 · 이미 반영',
            color: duplicateBadge,
            textColor: duplicateBadge,
          )
        : (text: '다음', color: behindOrange, textColor: behindOrange);
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
          color: duplicateBadge,
          tooltip: '재배치는 이 커밋을 건너뜁니다',
        ),
      // 이미 base에 있는 커밋은 재배치가 재생하지 않으니 단독 재생의 충돌 예고는
      // 일어날 수 없는 일을 경고하는 셈이다. 예고를 만들 때 이미 걸러 두지만 뒤늦게
      // 도착한 예고가 있어도 배지로 올리지 않는다.
      if (!alreadyInBase && forecast != null && forecast.isNotEmpty)
        (
          id: 'conflict-forecast',
          text: _conflictForecastLabel(forecast),
          color: forecastBadge,
          tooltip: '순차 재배치에서는 앞 커밋의 해결이 이 예상을 바꿀 수 있습니다',
        ),
    ];
  }

  /// '충돌 예상 · settings.dart 외 2' — 첫 파일 이름과 나머지 개수.
  static String _conflictForecastLabel(List<String> files) {
    final first = files.first.split('/').last;
    return files.length == 1
        ? '충돌 예상 · $first'
        : '충돌 예상 · $first 외 ${files.length - 1}';
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

  void _savePreviewSize() => widget.onPreviewSizeChanged?.call((
    width: _previewWidth,
    height: _previewHeight,
  ));

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
      _commitMessageFor(commit.sha);

  Future<String> _commitMessageFor(String sha) =>
      FullDiffCommitMessageCache.shared.getOrLoad(
        repositoryRoot: widget.repository.root,
        sha: sha,
        loader: () => widget.repository.loadCommitMessage(sha),
      );

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

  Widget _mergeConflictActions() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_mergePreviewError != null)
          Expanded(
            child: Text(
              _mergePreviewError.toString(),
              style: TextStyle(color: behindOrange, fontSize: 10),
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

  /// Options changed before the settings file finished loading have nowhere to
  /// go yet, so they wait here until a persistence callback arrives.
  void _scheduleFullDiffPersistenceFlush() {
    if (_fullDiffPersistenceFlushScheduled ||
        (_pendingFullDiffPreferences == null &&
            _pendingFullDiffColumnWidths == null) ||
        (widget.onFullDiffPreferencesChanged == null &&
            widget.onFullDiffColumnWidthsChanged == null)) {
      return;
    }
    _fullDiffPersistenceFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fullDiffPersistenceFlushScheduled = false;
      if (!mounted) return;

      final preferences = _pendingFullDiffPreferences;
      final preferencesCallback = widget.onFullDiffPreferencesChanged;
      if (preferences != null && preferencesCallback != null) {
        _pendingFullDiffPreferences = null;
        preferencesCallback(preferences);
      }

      final widths = _pendingFullDiffColumnWidths;
      final widthsCallback = widget.onFullDiffColumnWidthsChanged;
      if (widths != null && widthsCallback != null) {
        _pendingFullDiffColumnWidths = null;
        widthsCallback(widths);
      }
    });
  }

  bool get _fullDiffOpen => _fullDiffSession != null;

  /// Where the commit list stood when the diff took its place, so returning
  /// lands on the same rows instead of at the top of the repository.
  double? _timelineOffsetBeforeDiff;
  int? _timelineIndexBeforeDiff;

  Future<void> _startFullDiff(
    FullDiffSessionController controller,
    String? path,
  ) async {
    await controller.initialize();
    if (!mounted || !identical(_fullDiffSession, controller)) return;
    _showFullDiffFile(path);
  }
}

/// The app's wordmark: one soft pastel per letter, legible on the dark bar, with
/// a small cloud badge tucked over the final letter.
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
