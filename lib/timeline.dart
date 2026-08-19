import 'dart:async';
import 'dart:io'
    show Directory, FileSystemEvent, FileSystemException, ProcessException;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'avatars.dart';
import 'branch_glyph.dart';
import 'command_log.dart';
import 'console_panel.dart';
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
import 'local_state_signature.dart';
import 'monaco_editor_screen.dart';
import 'page_scroll_shortcuts.dart';
import 'preview_header.dart';
import 'timeline_graph_painters.dart';
import 'timeline_model.dart';
import 'timeline_widgets.dart';
import 'timeline_palette.dart';
import 'ref_row_menu.dart';
import 'ref_tree.dart';
import 'search_icon.dart';
import 'remote_pull_menu.dart';
import 'repository_branch_selector.dart';
import 'settings.dart';
import 'shortcut_modifier.dart';
import 'timeline_theme.dart';
import 'typography.dart';
import 'upstream_push_summary.dart';
import 'upstream_sync.dart';
import 'upstream_sync_capsule.dart';
import 'vim_navigation.dart';
import 'window_frame.dart';
import 'working_tree_status.dart';

/// The graph's painters live in their own library; the timeline is still the
/// door they are reached through.
export 'timeline_graph_painters.dart';
export 'timeline_model.dart';
export 'timeline_widgets.dart';
import 'yogit_alert.dart';

part 'timeline_branch_preview.dart';
part 'timeline_commit_panel.dart';
part 'timeline_data.dart';
part 'timeline_chrome.dart';
part 'timeline_diff_mode.dart';
part 'timeline_preview_pane.dart';
part 'timeline_rows.dart';
part 'timeline_search.dart';
part 'timeline_upstream_sync.dart';
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
const _statusStampStyle = TextStyle(
  fontSize: 11,
  fontFamily: technicalFontFamily,
  fontFamilyFallback: technicalFontFallback,
);

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
  local('LOCAL', Icons.computer_outlined, '브랜치'),
  remote('REMOTE', Icons.cloud_outlined, '원격 브랜치'),
  tags('TAGS', Icons.sell_outlined, '태그');

  const _RefSection(this.label, this.icon, this.noun);

  final String label;
  final IconData icon;

  /// 이 섹션의 ref를 사람에게 부르는 이름. 삭제 도구 설명과 확인 대화상자가
  /// 같은 말을 쓰도록 한자리에 둔다.
  final String noun;
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
    this.commandLog,
    this.deletedBranchNames = const {},
    this.deletedBranchNamesReady = true,
    this.onDeletedBranchNamesChanged,
    this.hiddenRefs = const {},
    this.onHiddenRefsChanged,
    this.showRemoteAvatars = true,
    this.precisePush = false,
    this.autoReloadExternalChanges = false,
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

  /// Every process the app runs, for the console dock. Null in a window with
  /// no console to open.
  final CommandLog? commandLog;

  final Map<String, String> deletedBranchNames;
  final bool deletedBranchNamesReady;
  final ValueChanged<Map<String, String>>? onDeletedBranchNamesChanged;

  /// Refs the graph leaves out of the log's starting points, so what only they
  /// reach never draws. Saved per repository.
  final Set<String> hiddenRefs;
  final ValueChanged<Set<String>>? onHiddenRefsChanged;
  final bool showRemoteAvatars;

  /// Push the tip a confirmation showed instead of the branch name — see
  /// [AppSettings.precisePush].
  final bool precisePush;

  /// Reload a change made outside the app without asking — see
  /// [AppSettings.autoReloadExternalChanges].
  final bool autoReloadExternalChanges;

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

  /// Three 12px lights, two 8px gaps, and the 14px the selector keeps clear of
  /// them. Declared rather than left to the row's own sum: the toolbar has to
  /// know where its left cluster starts before it can find the window's centre.
  static const _windowButtonsWidth = 66.0;

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

  /// Branch line id → the name of the ref that tips it, so a commit partway
  /// down a line can still say which branch it sits on.
  var _branchLineNames = <int, String>{};

  /// Branch line id → tip SHA, for the lines no ref points at. The key the
  /// recovered names below are filed under, and the reason a hovered row can
  /// ask whose line it is on without walking the rows.
  var _branchLineTips = <int, String>{};

  /// Tip SHA → the branch name a merge commit in the loaded history gave it.
  /// Rebuilt with the graph, so reading another page widens it.
  var _mergedBranchNames = <String, String>{};

  /// Tip SHA → the branch name the `HEAD` reflog remembers. Read once in the
  /// background per repository; empty until it lands, and empty forever where
  /// there is no reflog left.
  var _reflogBranchNames = <String, String>{};

  /// Long enough that the reflog read lands behind the first page and the refs
  /// rather than beside them, short enough that a reader looking around still
  /// finds the names waiting.
  static const _reflogFoldDelay = Duration(seconds: 2);
  Timer? _reflogFoldTimer;

  /// Refs the reader has closed the eye on. Held here rather than read from the
  /// widget so a press redraws at once instead of waiting for the round trip
  /// through settings.
  late final Set<String> _hiddenRefs = {...widget.hiddenRefs};

  /// The commits [_hiddenRefs] takes out of the log's starting points. The
  /// checked-out branch is never among them: HEAD is a starting point too, and
  /// a graph that hides the ground you stand on is worse than a busy one.
  /// What the loaded log was actually told to leave out, so a later ref load
  /// can notice it now resolves a tip the first page could not.
  var _loadedHiddenTips = <String>{};

  Set<String> get _hiddenTips => {
    for (final ref in _hiddenRefs)
      if (ref != _refs.current) ?_refs.tips[ref],
  };
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

  /// ⇧+화살표로 커서와 함께 잡은 커밋들의 sha. 커서가 선 커밋은 이 집합에
  /// 없어도 늘 함께 센다 — 잡은 것이 하나뿐이면 집합은 비어 있다.
  final _checkedCommits = <String>{};

  /// 커서가 선 행. ↵가 열 메뉴의 위치를 이 행에서 잰다.
  final _cursorRowKey = GlobalKey();

  /// 메시지 고치기·합치기 대화창이 함께 쓰는 입력칸.
  final _commitMessageDraft = TextEditingController();
  final _authorDraft = TextEditingController();
  final _dateDraft = TextEditingController();
  final _branchNameDraft = TextEditingController();
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

  /// 커밋 패널이 읽고 있는 작업 트리. 요청은 한 번만 나가고, 조작이 끝나면
  /// `_reloadCommitMode`가 요청을 버려 다시 읽게 한다. 마지막으로 읽은 값은
  /// 다시 읽는 동안 목록이 비어 보이지 않도록 남겨 둔다.
  Future<WorkingTreeStatus>? _commitStatusRequest;
  WorkingTreeStatus? _commitStatus;

  /// 패널 전체가 한 번에 한 조작만 한다 — index.lock 경합을 UI에서 막는다.
  var _commitModeBusy = false;

  /// 열린 diff가 보고 있는 축. 세션의 어댑터가 이 값을 물고 있어서 축을 바꾸면
  /// 세션을 다시 세운다.
  var _commitDiffArea = WorkingTreeArea.unstaged;

  /// Space와 ↑↓이 겨누는 행. 두 섹션을 하나의 평평한 줄로 걷는다.
  ({WorkingTreeArea area, String path})? _commitCursor;
  var _commitUnstagedCollapsed = false;
  var _commitStagedCollapsed = false;
  final _commitTitle = TextEditingController();
  final _commitBody = TextEditingController();
  var _commitAmend = false;

  /// amend가 채워 넣은 메시지. 손대지 않은 그대로면 체크를 풀 때 비운다.
  String? _commitAmendPrefill;
  String? _commitError;

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

  /// Whether a refresh came due while the window was behind another app and
  /// was skipped. One bit rather than a clock: it says exactly what the window
  /// coming back has to make up.
  var _missedRemoteRefresh = false;
  Timer? _localWatchTimer;
  Timer? _localWatchDebounceTimer;
  final _refWatchers = <StreamSubscription<FileSystemEvent>>[];

  /// The local fingerprint the timeline is currently showing.
  String? _localSignature;

  /// A fingerprint the user chose not to load, so the same change is not asked
  /// about twice.
  String? _declinedSignature;

  /// How many moved branches get asked about. Past this the notice states the
  /// fact and stops spending round trips on a line already too long to read.
  static const _detailedBranchLimit = 3;

  /// 밖에서 벌어진 변화를 설명하는 알림에 선 읽음들, 오래된 것부터. 스스로
  /// 사라지지 않고 esc나 바깥 클릭을 기다린다. 읽는 중에 저장소가 또 바뀌면
  /// 갈아치우지 않고 여기에 하나 더 쌓인다 — 방금 읽던 줄이 사라지지 않도록.
  final _localChangeReadings = <LocalChangeDetails>[];

  final _localChangeNoticeOverlay = OverlayPortalController();

  /// 화면에서 자리를 차지하지 않는 걸개. 카드는 방금 답한 물음이 서 있던 자리에
  /// — 화면 한가운데에 — 이어서 선다. 답을 한 곳과 답이 오는 곳이 같아야 눈이
  /// 화면 반대편까지 가지 않는다.
  Widget _localChangeNoticeHost() => OverlayPortal(
    controller: _localChangeNoticeOverlay,
    overlayChildBuilder: (context) {
      if (_localChangeReadings.isEmpty) return const SizedBox.shrink();
      // 여백은 카드가 창을 넘지 않게 잡아 두는 천장이다. 쌓인 영역이 그보다
      // 길어지면 카드가 자라는 대신 제 안에서 구른다.
      return Positioned.fill(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: LocalChangeNotice(
              readings: List.of(_localChangeReadings),
              onDismiss: _dismissLocalChangeNotice,
            ),
          ),
        ),
      );
    },
    child: const SizedBox.shrink(),
  );

  void _showLocalChangeNotice(LocalChangeDetails details) {
    _rebuild(() => _localChangeReadings.add(details));
    if (!_localChangeNoticeOverlay.isShowing) {
      _localChangeNoticeOverlay.show();
    }
  }

  void _dismissLocalChangeNotice() {
    if (_localChangeReadings.isEmpty) return;
    _rebuild(_localChangeReadings.clear);
    if (_localChangeNoticeOverlay.isShowing) _localChangeNoticeOverlay.hide();
  }

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
  // upstream 동기화 — 판정은 컨트롤러가, 실행은 이 화면이.
  late final _upstreamSync = UpstreamSyncController(
    measure: widget.repository.measureUpstreamRebase,
  );
  var _upstreamSyncBusy = false;

  /// 충돌 해결 흐름이 잠깐 빌린 기준: 빌려 간 원격 ref와 돌아갈 로컬 브랜치.
  /// 사용자가 흐름 중에 기준을 손수 바꿨다면 빌림은 끝난 것이라 되돌리지 않는다.
  ({String borrowed, String returnTo})? _upstreamConflictLoan;

  // 커밋 찾기 — 목록을 거르지 않고 찾은 자리에 불을 켠다.
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'timeline search');
  var _searchQuery = '';
  var _searchOpen = false;

  /// 이 검색의 기점 — 검색을 열 때 선택이 서 있던 줄. 찾은 것이 없이 검색창이
  /// 닫히면 선택을 여기로 돌려보낸다.
  int? _searchOrigin;
  final _collapsedRefSections = <_RefSection>{};
  final _collapsedRefFolders = <String>{};
  var _showAllTags = false;
  var _sidebarCollapsed = false;

  /// The console dock. Shut on launch — it is for the moment something looks
  /// wrong, not for every moment.
  var _consoleOpen = false;
  var _consoleHeight = 200.0;

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

  /// Deepest lane on screen right now. Squeezing measures against this, so a
  /// depth left behind further down the list never pushes these lanes left.
  var _visibleLane = 0;
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
    // detail pane follows the controller: the window opens it at startup, and
    // Enter or the toolbar's button moves it from there.
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
    _scheduleReflogFold();
  }

  /// Reads the reflog once, after the picture is up and a beat has passed. The
  /// names it holds are worth having for every row at once, but not worth
  /// making the first paint wait — nobody is asking for them yet at that
  /// moment.
  void _scheduleReflogFold() {
    _reflogFoldTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 저장소가 연달아 바뀌면 앞선 콜백이 여기 먼저 닿는다. 그때 세워 둔 타이머를
      // 여기서 한 번 더 걷어야 같은 reflog를 두 번 읽지 않는다.
      _reflogFoldTimer?.cancel();
      _reflogFoldTimer = Timer(_reflogFoldDelay, () {
        unawaited(_foldReflogBranchNames());
      });
    });
  }

  Future<void> _foldReflogBranchNames() async {
    final generation = _deletedBranchLookupGeneration;
    final repository = widget.repository;
    final names = await repository.loadReflogBranchNames();
    // 저장소가 바뀌었으면 앞 저장소의 이름을 새 화면에 얹지 않는다.
    if (!mounted ||
        names.isEmpty ||
        generation != _deletedBranchLookupGeneration ||
        !identical(widget.repository, repository)) {
      return;
    }
    _reflogBranchNames = names;
    _deletedBranchRevision.value++;
  }

  /// The remotes a local branch is measured against: every upstream, and every
  /// remote holding a branch of the same name. A count on a row is only as
  /// true as the last fetch of these, so their failures are the ones worth
  /// telling the reader about.
  Set<String> get _measuredRemotes {
    final remotes = <String>{..._refs.upstreamRemotes.values};
    for (final remoteBranch in _refs.remote) {
      final split = splitRemoteBranchName(remoteBranch, _refs.remoteNames);
      if (split == null || !_refs.local.contains(split.branch)) continue;
      remotes.add(split.remote);
    }
    return remotes;
  }

  /// Every remote the screen shows anything of. The list under REMOTE is a
  /// claim about a server, and a remote nobody happens to track locally would
  /// otherwise sit there unrefreshed for the life of the window.
  List<String> get _remotesToRefresh {
    final remotes = {..._measuredRemotes};
    for (final remoteBranch in _refs.remote) {
      final split = splitRemoteBranchName(remoteBranch, _refs.remoteNames);
      if (split != null) remotes.add(split.remote);
    }
    return remotes.toList()..sort();
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

  /// How many changes the app itself is part way through. The watcher exists
  /// to notice what happens *outside* the app; a branch the app is deleting is
  /// already going to be reported by the code that deleted it, and the two
  /// telling the reader the same thing is how the same sentence arrives twice.
  ///
  /// A count rather than a flag: a reload can be running while a second change
  /// starts, and the first one finishing must not open the window early.
  var _repositoryChanges = 0;

  bool get _isChangingRepository =>
      _repositoryChanges > 0 || _branchApplyBusy || _pullingRemote != null;

  /// Runs [change] with the watcher held off, and leaves the fingerprint on
  /// what the repository looks like afterwards, so the next reading finds
  /// nothing to report.
  Future<T> _changingRepository<T>(Future<T> Function() change) async {
    _repositoryChanges++;
    try {
      return await change();
    } finally {
      _repositoryChanges--;
      if (!_isChangingRepository) await _syncLocalSignature();
    }
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
  ///
  /// Branches that merely disappeared are the exception and load without being
  /// asked about. Nothing on screen can be lost to a deletion the user just
  /// performed, and deleting a dozen branches from a terminal is a dozen
  /// separate readings — one question each, which no debounce can collapse.
  ///
  /// [TimelineScreen.autoReloadExternalChanges] widens that exception to every
  /// reading: nothing is asked, and the card carries what changed.
  Future<void> _checkLocalChanges() async {
    if (!mounted || _localChangePromptOpen) return;
    // A mutation the app is running will refresh on its own; interrupting it
    // with a question would race its own reload. The silent path leans on the
    // same guards, so it cannot fight an app-initiated change either.
    if (_isChangingRepository) return;
    final signature = await widget.repository.loadLocalStateSignature();
    // Reading the fingerprint takes a moment, and the app can start changing
    // the repository inside it. What comes back then is half the app's own
    // work, which it is about to report itself.
    if (!mounted || signature == null || _isChangingRepository) return;
    final previous = _localSignature;
    if (previous == null) {
      _localSignature = signature;
      return;
    }
    if (signature == previous || signature == _declinedSignature) return;
    final change = diffLocalState(
      parseLocalState(previous),
      parseLocalState(signature),
    );
    // Text that differs while nothing it describes does — a ref list git
    // handed back in another order — is worth recording, never worth asking
    // about.
    if (change.isEmpty) {
      _localSignature = signature;
      return;
    }
    // What changed is read before anyone is asked about it: an answer to
    // "새로 읽어올까요?" needs the change in front of it, not after it.
    final details = await _localChangeDetails(change);
    if (!mounted) return;
    // With 자동 새로고침 on, everything else takes the deletion path too: load
    // it, and let the card be the only place the reading is told.
    if (!change.isPureDeletion && !widget.autoReloadExternalChanges) {
      _localChangePromptOpen = true;
      final accepted = await showYogitAlert<bool>(
        context,
        YogitAlert(
          // Wider than an alert of prose: commit subjects have to be readable
          // or the list is decoration.
          boxWidth: YogitAlert.listWidth,
          title: '저장소가 밖에서 바뀌었습니다',
          body: details == null
              ? null
              : YogitAlertPanel(
                  child: LocalChangeDetailsView(details: details),
                ),
          detail: '새로 읽어올까요?',
          cancelLabel: '나중에',
          cancelKey: const Key('local-change-dismiss'),
          confirmLabel: '새로고침',
          confirmKey: const Key('local-change-refresh'),
        ),
      );
      if (!mounted) return;
      _localChangePromptOpen = false;
      if (accepted != true) {
        // The declined reading is remembered whole, so the same state does not
        // come back as the same question.
        _declinedSignature = signature;
        return;
      }
      _localSignature = signature;
      _declinedSignature = null;
      await _reloadTimelineAfterCherryPick(null);
      // The question already said what changed. Saying it again once it is
      // answered is the app talking to itself.
      return;
    }
    _localSignature = signature;
    _declinedSignature = null;
    await _reloadTimelineAfterCherryPick(null);
    if (!mounted || details == null) return;
    // Nothing asked, so nothing has said it yet. The card is the only place
    // this reading gets told.
    _showLocalChangeNotice(details);
  }

  /// Turns what changed into the lines that explain it, asking git only for
  /// the parts the fingerprint cannot know: what the operation was, and which
  /// commits it moved.
  Future<LocalChangeDetails?> _localChangeDetails(
    LocalStateChange change,
  ) async {
    if (change.isEmpty) return null;
    final repository = widget.repository;
    final lines = <String>[];
    if (change.headRefChanged) {
      lines.add(
        change.currentBranch == null
            ? 'HEAD 분리됨'
            : '${change.currentBranch} 체크아웃',
      );
    }
    // Asking about every branch a terminal sweep touched would be a dozen
    // round trips for a line nobody reads to the end. The rest are counted.
    final detailed = change.moved.take(_detailedBranchLimit);
    ({int outgoing, int incoming})? firstCounts;
    for (final tip in detailed) {
      final counts = await repository.countMovedCommits(tip.before, tip.after);
      firstCounts ??= counts;
      lines.add(
        movedBranchLine(
          tip.branch,
          operation: await repository.loadBranchOperation(tip.branch),
          outgoing: counts?.outgoing,
          incoming: counts?.incoming,
          before: tip.before,
          after: tip.after,
        ),
      );
    }
    for (final tip in change.moved.skip(_detailedBranchLimit)) {
      lines.add('${tip.branch} 브랜치 갱신됨');
    }
    // 터미널이 한 번에 열두 개를 지우면 열두 줄짜리 카드가 된다. 이름을 나열하는
    // 기존 한계와 같은 선에서, 넘치면 세어서 말한다.
    lines.addAll(branchLines(change.added, '추가됨'));
    lines.addAll(branchLines(change.removed, '삭제됨'));
    if (lines.isEmpty) return null;
    // The commits themselves only fit when one thing happened. Two branches
    // moving is already a list of its own.
    final single = lines.length == 1 && change.moved.length == 1;
    final commits = single
        ? await repository.loadMovedCommits(
            change.moved.single.before,
            change.moved.single.after,
            limit: LocalChangeDetails.maxCommits + 1,
          )
        : const <MovedCommit>[];
    // 개수는 머리줄을 지으며 이미 셌다. 같은 것을 두 번 묻지 않는다.
    final total = single && firstCounts != null
        ? firstCounts.outgoing + firstCounts.incoming
        : commits.length;
    return LocalChangeDetails(
      headline: lines.first,
      lines: lines.skip(1).toList(),
      commits: commits
          .take(LocalChangeDetails.maxCommits)
          .map(
            (commit) => (
              incoming: commit.incoming,
              shortSha: commit.shortSha,
              subject: commit.subject,
            ),
          )
          .toList(),
      more: math.max(0, total - LocalChangeDetails.maxCommits),
      // 펼칠 것이 있는 쪽만 누를 자리를 얻는다 — 브랜치가 여럿이면 애초에
      // 커밋 목록이 서지 않는다.
      loadRest: single ? () => _restMovedCommits(change.moved.single) : null,
    );
  }

  /// '외 N개'를 누를 때 도는 조회. 카드를 여는 조회는 아홉 개로 가볍게 두고,
  /// 나머지는 실제로 펼친 사람만 값을 치른다.
  /// ponytail: 500-commit ceiling, same as the push summary's; past it the
  /// count stays honest and the list simply stops.
  Future<List<NoticeCommit>> _restMovedCommits(MovedTip tip) async {
    final moved = await widget.repository.loadMovedCommits(
      tip.before,
      tip.after,
      limit: 500,
    );
    return [
      for (final commit in moved)
        (
          incoming: commit.incoming,
          shortSha: commit.shortSha,
          subject: commit.subject,
        ),
    ];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_reloadCherryPickState());
    // A refresh only runs while the app is in front, so any that came due
    // behind another window was dropped — including the one a window opened
    // unfocused makes on the way up. Coming back is where it is made up;
    // flipping between two windows without missing one costs nothing.
    if (!_missedRemoteRefresh) return;
    _missedRemoteRefresh = false;
    unawaited(_refreshRemotes());
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
      // 접어 둔 reflog는 저장소 하나의 기억이다. 새 저장소로 넘어가면 버리고
      // 그쪽 것을 다시 접는다.
      _reflogBranchNames = const {};
      _scheduleReflogFold();
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
        _judgeUpstreamSync();
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
    _reflogFoldTimer?.cancel();
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
    _commitMessageDraft.dispose();
    _authorDraft.dispose();
    _dateDraft.dispose();
    _branchNameDraft.dispose();
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
    _commitTitle.dispose();
    _commitBody.dispose();
    _upstreamSync.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
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

  /// The depth a narrowing column measures itself against: what is drawn on
  /// this screen, so lanes hold still until the deepest node the reader can
  /// see reaches the column boundary.
  int get _graphSqueezeDepth =>
      _comparison == null ? _visibleLane : _graphLayoutDepth;

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
      ).clamp(
        CommitGraphPainter.minAutoFitWidth,
        timelineColumns['graph']!.max,
      );

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

  /// Commits actually read from `git log`, so the working tree row never shifts
  /// the paging offset.
  int get _historyCount => _normalCommits.length - (_hasWorkingTree ? 1 : 0);

  void _rebuildGraph() {
    _normalRows = layoutGraph(_normalCommits, preferredTip: _preferredTip);
    _normalEntries = timelineEntries(_normalRows, DateTime.now());
    // The palette goes over as it is: the rail colour a ring is drawn in — and
    // so what the avatar's tone has to be compared against — is read out of it
    // there, by the one function that already knows which palettes are
    // readable.
    _branchPaletteIndexes = assignBranchPaletteIndexes(
      _normalRows,
      widget.repository.root.hashCode,
      refPaletteAssignments: widget.refPaletteAssignments,
      refPalette: widget.refPalette,
      avoidTone: _avatarTone,
    );
    _branchLineNames = branchLineNames(_normalRows);
    _branchLineTips = branchLineTips(_normalRows, _refs);
    // 머지 제목이 기억하는 이름은 이미 읽어 둔 커밋 안에 있다. 줄 하나를 물을
    // 때마다 훑는 대신 그래프를 만드는 이 자리에서 한 번에 색인한다.
    _mergedBranchNames = mergedBranchNamesByTip(_normalCommits);
    AvatarService.branchAssignments = {
      for (final entry in _branchPaletteIndexes.entries)
        entry.key: refPaletteColorsAt(entry.value, widget.refPalette).text,
    };
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

  /// The average colour of that identity's avatar, which the lane assignment
  /// steers clear of so the branch ring around a photo stays visible. Null
  /// until it arrives, and null forever where there is no face to read.
  Color? _avatarTone;

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
      final editing = _editableDescendantHasFocus;
      final key = normalizeNavigationKey(
        event.logicalKey,
        hasModifier:
            keyboard.isMetaPressed ||
            keyboard.isAltPressed ||
            keyboard.isShiftPressed ||
            keyboard.isControlPressed ||
            editing,
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
        if (_commitPanelOpen) {
          _moveCommitCursor(step);
        } else if (_previewController.previewPlacement !=
            PreviewPlacement.closed) {
          _stepPreviewFile(step, animate: event is KeyDownEvent);
        }
        return KeyEventResult.handled;
      }
      // 타자 중에는 맨 화살표가 캐럿의 것이다 — 위의 ⌘↑↓만 앱의 파일 걷기로
      // 남고, 아래 ⌘↵·Space·Esc는 각자의 가드를 그대로 쓴다.
      // Autorepeat jumps instead of animating: queued animations would lag
      // behind a held key and never catch up.
      if (step != 0 && !editing) {
        _moveSelection(
          step,
          animate: event is KeyDownEvent,
          extend: keyboard.isShiftPressed,
        );
        return KeyEventResult.handled;
      }
      // ← (or h) walks over to the sidebar while the pane is open.
      if (key == LogicalKeyboardKey.arrowLeft &&
          event is KeyDownEvent &&
          !editing &&
          !_sidebarCollapsed) {
        _sidebarFocusNode.requestFocus();
        if (_sidebarCursor == null) _moveSidebarCursor(1);
        return KeyEventResult.handled;
      }
      // → (or l) walks the other way, into the preview and its diff.
      if (key == LogicalKeyboardKey.arrowRight &&
          event is KeyDownEvent &&
          !editing) {
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
    // ⌘F opens the find field, and opens it again on the search already there.
    if (event.logicalKey == LogicalKeyboardKey.keyF && shortcutModifierHeld) {
      _openSearch();
      return KeyEventResult.handled;
    }
    // ⌘R 원격 새로고침. 사이드바 REMOTE 머리줄의 버튼과 같은 자리로 간다.
    if (event.logicalKey == LogicalKeyboardKey.keyR && shortcutModifierHeld) {
      _refreshRemotesNow();
      return KeyEventResult.handled;
    }
    // ⌘` 콘솔. 편집 중에도 열려야 한다 — 방금 무엇이 나갔는지 보려는 것이다.
    if (event.logicalKey == LogicalKeyboardKey.backquote &&
        shortcutModifierHeld) {
      _toggleConsole();
      return KeyEventResult.handled;
    }
    // ⌘, 설정. macOS 관례다. 편집 중에도 열린다 — ⌘를 쥔 쉼표는 글자가 아니라서
    // 캐럿이 쓸 일이 없다.
    if (event.logicalKey == LogicalKeyboardKey.comma && shortcutModifierHeld) {
      widget.onOpenSettings?.call();
      return KeyEventResult.handled;
    }
    // ⌘↵ 커밋. 제목칸에 포커스가 있어도 동작한다 — 치고 바로 커밋하는 흐름이다.
    // 게이트는 커밋 버튼의 것과 같고, 막히면 아래 Enter로 새지 않는다.
    if (event.logicalKey == LogicalKeyboardKey.enter && shortcutModifierHeld) {
      if (_commitPanelOpen && _commitReady) unawaited(_commitIndex());
      return KeyEventResult.handled;
    }
    // Space는 커서 행을 축 사이로 넘긴다. 제목·본문을 치는 중에는 스페이스가
    // 글자라 손대지 않는다 — 그 키 이벤트는 여기까지 버블로 올라온다.
    if (event.logicalKey == LogicalKeyboardKey.space &&
        !shortcutModifierHeld &&
        !_editableDescendantHasFocus &&
        _commitPanelOpen) {
      unawaited(_toggleCommitCursorRow());
      return KeyEventResult.handled;
    }
    // ↵는 커서가 선 커밋의 메뉴다 — 우클릭이 여는 그 메뉴, 그 자리.
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        !shortcutModifierHeld &&
        _commits.isNotEmpty) {
      unawaited(_openCursorCommitMenu());
      return KeyEventResult.handled;
    }
    // 미리보기 여닫기는 ↵가 두고 간 자리를 ⌘]로 옮겼다.
    if (event.logicalKey == LogicalKeyboardKey.bracketRight &&
        shortcutModifierHeld) {
      _togglePreview();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // 방금 선 알림이 가장 앞의 관심사다. 미리보기나 diff보다 먼저 닫힌다.
      if (_localChangeReadings.isNotEmpty) {
        _dismissLocalChangeNotice();
      } else if (_fullDiffOpen) {
        _closeFullDiff();
      } else if (_previewDiffOpen) {
        _closePreviewDiff();
      } else if (_previewController.previewPlacement !=
          PreviewPlacement.closed) {
        unawaited(_previewController.setPreview(PreviewPlacement.closed));
      } else if (_searchLive) {
        // 접혀서 살아 있는 찾기는 배경이다. 방금 열린 판이 먼저 닫히고, 닫을
        // 것이 다 닫힌 뒤에야 흐림이 걷힌다.
        _closeSearch();
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
  void _moveSelection(int delta, {bool animate = true, bool extend = false}) {
    if (_entries.isEmpty) return;
    final left = _selectedCommit;
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
    // ⇧는 지나온 커밋을 함께 잡고, 맨 화살표는 잡은 것을 놓는다. 작업 트리 행은
    // 커밋이 아니라 어느 쪽으로도 잡히지 않는다.
    _setCheckedCommits(
      extend
          ? {
              ..._checkedCommits,
              for (final commit in [left, _selectedCommit])
                if (commit != null && !commit.isWorkingTree) commit.sha,
            }
          : const {},
    );
    _scrollToSelection(animate: animate);
  }

  /// 잡은 커밋 목록을 갈아 끼운다. 달라진 것이 없으면 다시 그리지 않는다 —
  /// 화살표를 누르고 있는 동안 매 걸음이 전체 목록을 다시 그리면 안 된다.
  void _setCheckedCommits(Set<String> next) {
    if (next.length == _checkedCommits.length &&
        next.every(_checkedCommits.contains)) {
      return;
    }
    setState(() {
      _checkedCommits
        ..clear()
        ..addAll(next);
    });
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
    _setCheckedCommits(const {});
    _focusNode.requestFocus();
  }

  /// 행을 누른 손: ⌘는 커밋을 하나씩 집어 넣고 빼내고 — 떨어져 있어도 된다 —,
  /// ⇧는 커서부터 이 행까지를 한 구간으로 잡는다. 맨 클릭은 잡은 것을 놓는다.
  void _selectRow(int index) {
    final commit = _commitAt(index);
    if (commit == null || commit.isWorkingTree) {
      _select(index);
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed || keyboard.isControlPressed) {
      final next = {..._checkedCommits, ?_selectedCommit?.sha};
      if (!next.remove(commit.sha)) next.add(commit.sha);
      _arrivedGoingDown = null;
      _selectedIndex.value = index;
      _setCheckedCommits(next);
      _focusNode.requestFocus();
      return;
    }
    if (keyboard.isShiftPressed) {
      final from = _selectedIndex.value;
      final span = [
        for (
          var probe = math.min(from, index);
          probe <= math.max(from, index);
          probe++
        )
          ?_commitAt(probe),
      ];
      _arrivedGoingDown = null;
      _selectedIndex.value = index;
      _setCheckedCommits({
        for (final row in span)
          if (!row.isWorkingTree) row.sha,
      });
      _focusNode.requestFocus();
      return;
    }
    _select(index);
  }

  /// 그 줄의 커밋. 날짜 머리줄처럼 커밋이 없는 줄은 null이다.
  GitCommit? _commitAt(int index) {
    if (index < 0 || index >= _entries.length) return null;
    final rowIndex = _entries[index].rowIndex;
    return rowIndex < 0 ? null : _commits[rowIndex];
  }

  void _selectedCommitChanged() {
    // The commit panel has no worktree watcher, so a selection landing back on
    // the working tree row is when it catches up with whatever happened outside
    // the app. Clearing here costs nothing while another row is selected: the
    // panel is not built, so nothing asks git anything.
    _commitStatusRequest = null;
    unawaited(_resolveSelectedDeletedBranchName());
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
  GitCommit? get _selectedCommit =>
      _entries.isEmpty ? null : _commitAt(_selectedIndex.value);

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

  /// The row the sidebar's keyboard cursor sits on, highlighted like a hover.
  (_RefSection, String)? _sidebarCursor;

  /// The rows a ⌘-click or a ⇧-click has gathered, for the actions that can
  /// take more than one ref at a time. Empty means the cursor's row stands on
  /// its own. Every ref in here belongs to one section: deleting a branch and
  /// deleting a tag are not the same loss, so one selection never mixes them.
  final _checkedRefs = <(_RefSection, String)>{};

  /// One key per named row so the cursor can be scrolled into view.
  final _sidebarRowKeys = <String, GlobalKey>{};

  /// Switches HEAD to a local branch from the sidebar strip.
  Future<void> _runLocalCheckout(String branch) async {
    if (_pullingRemote != null || _branchApplyBusy) return;
    try {
      await _changingRepository(() async {
        await widget.repository.checkoutLocalBranch(branch);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$branch 체크아웃')));
        await _reloadTimelineAfterCherryPick(null);
      });
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

  String? _lastRefRowTap;
  int _lastRefRowTapMs = 0;

  /// One controller per named row so the row's double-click can open the menu
  /// its anchor holds. Keyed by section and name: a tag and a branch may
  /// answer to the same name.
  final _refMenuControllers = <String, MenuController>{};

  /// Double-click on a remote row: the one state where the outcome is safe and
  /// obvious asks for a fast-forward pull; every other state opens the menu,
  /// which names the state and offers what that ref can do instead of mutating
  /// anything. A remote belonging to no known remote has no menu to open.
  void _runRemotePullDefault(String remoteBranch) {
    final state = remotePullState(_refs, remoteBranch);
    if (state == null) return;
    if (state.kind == RemotePullKind.fastForward) {
      unawaited(_confirmRemotePull(remoteBranch, state));
      return;
    }
    _refMenuController(_RefSection.remote, remoteBranch).open();
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
  Widget build(BuildContext context) => _withCommandLog(
    Scaffold(
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
            _console(),
            // 알림은 오버레이로 뜬다. 화면 구조에 Stack을 얹으면 미리보기 판이
            // 겹쳐 놓인 것이 되어, 그것이 나란한 형제라는 약속이 깨진다.
            _localChangeNoticeHost(),
            _statusBar(),
          ],
        ),
      ),
    ),
  );

  /// Puts the log where a menu item or a button can reach it: they know the
  /// name of what the user pressed, and the console needs that name.
  Widget _withCommandLog(Widget child) {
    final log = widget.commandLog;
    return log == null ? child : CommandLogScope(log: log, child: child);
  }

  /// The console, docked under everything and across the whole window: the
  /// commands it shows belong to the repository, not to the timeline column.
  /// Closed it takes no room at all.
  Widget _console() {
    final log = widget.commandLog;
    if (log == null || !_consoleOpen) return const SizedBox.shrink();
    // The window's height is read in here rather than in the screen's own
    // build, so a resize rebuilds this box and not the timeline behind it.
    return Builder(
      builder: (context) {
        final most = math.max(
          _consoleMinHeight,
          MediaQuery.sizeOf(context).height / 2,
        );
        return SizedBox(
          key: const Key('console-dock'),
          height: _consoleHeight.clamp(_consoleMinHeight, most),
          child: ConsolePanel(
            log: log,
            repositoryRoot: widget.repository.root,
            onClose: () => _rebuild(() => _consoleOpen = false),
            onResize: (delta) => _rebuild(
              () => _consoleHeight = (_consoleHeight + delta).clamp(
                _consoleMinHeight,
                most,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Whether asking for a refresh right now would actually send anything.
  /// A fetch already in flight, a repository with no remote, and the middle of
  /// a cherry-pick are all reasons [_refreshRemotes] would return without a
  /// word — the button says so instead of taking a press that does nothing.
  bool get _canRefreshRemotesNow =>
      !_fetchingRemotes.value &&
      _cherryPickState == null &&
      _remotesToRefresh.isNotEmpty;

  /// The manual remote refresh, named so the console says who asked. Runs even
  /// when the timer has just run: pressing it is the point.
  void _refreshRemotesNow() {
    if (!_canRefreshRemotesNow) return;
    final log = widget.commandLog;
    if (log == null) return unawaited(_refreshRemotes());
    log.runNamed('원격 새로고침', () => unawaited(_refreshRemotes()));
  }

  void _toggleConsole() {
    if (widget.commandLog == null) return;
    _rebuild(() => _consoleOpen = !_consoleOpen);
  }

  /// Never smaller than this; never more than half the window, which the box
  /// above works out from the window it is being laid out in.
  static const _consoleMinHeight = 80.0;

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

  Widget _windowButtons() => SizedBox(
    width: _windowButtonsWidth,
    child: WindowButtons(controller: _previewController),
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

  /// Whatever the functional clusters leave is where the window drags from —
  /// [_minDragWidth] of it is reserved before the branch selector takes its
  /// width. The wordmark rides in here, not because it belongs to the drag
  /// target but because this stretch is the free space itself: the selector's
  /// box ends where its ink ends, so this width is the room the mark has to ask
  /// for. It is still drawn at the window's centre, not at this stretch's.
  Widget _dragRegion(double toolbarWidth) => GestureDetector(
    key: const Key('toolbar-drag'),
    behavior: HitTestBehavior.opaque,
    onPanStart: (_) => unawaited(_previewController.startDrag()),
    onDoubleTap: () => unawaited(_previewController.toggleZoom()),
    child: LayoutBuilder(
      builder: (context, constraints) =>
          _centeredWordmark(context, toolbarWidth, constraints.maxWidth),
    ),
  );

  /// 기준은 원격 브랜치도 될 수 있다. 로컬 브랜치를 원격 위로 재배치하는 방향은
  /// 그렇게 골라야만 나온다. 대신 기준이 원격이면 기준을 옮기는 적용(Merge, Rebase
  /// 후 Merge)은 받을 로컬 브랜치가 없어 막힌다.
  void _selectBaseBranch(String branch, {bool persist = true}) {
    if (_branchApplyBusy ||
        !(_refs.local.contains(branch) || _refs.remote.contains(branch)) ||
        branch == _baseBranch) {
      return;
    }
    final compared = _compareRef;
    setState(() {
      _baseBranch = branch;
      _resetBranchApply();
      _rebuildGraph();
    });
    _judgeUpstreamSync();
    _scheduleRatchetUpdate();
    if (compared != null) {
      if (compared == branch) {
        _clearComparison();
      } else {
        unawaited(_selectComparison(compared));
      }
    }
    // 충돌 해결 흐름이 잠깐 빌리는 기준은 취향이 아니다 — 저장해 두면 흐름
    // 도중에 앱이 꺼졌을 때 원격 ref가 기준으로 되살아나 사용자가 좌초한다.
    if (persist) {
      if (widget.preferredBranchReady) {
        widget.onPreferredBranchChanged?.call(branch);
      } else {
        _pendingBaseBranch = branch;
        _pendingBaseBranchIsUserSelection = true;
      }
    }
    unawaited(_refreshRemotes());
    _focusNode.requestFocus();
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

  void _dropCommitBadges() {
    _conflictForecastSerial++;
    _duplicateCommits = const {};
    _conflictForecast = const {};
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

  /// ↵가 여는 메뉴: 커서 행의 위치에서, 우클릭이 여는 그 메뉴를 그대로 띄운다.
  Future<void> _openCursorCommitMenu() async {
    final commit = _selectedCommit;
    if (commit == null) return;
    final box = _cursorRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    await _showCommitMenu(
      commit,
      box.localToGlobal(Offset(box.size.width * 0.2, box.size.height * 0.9)),
    );
  }

  /// 메뉴가 손댈 커밋들 — 새 것부터 오래된 것 순. 잡아 둔 행 위에서 열었으면 잡은
  /// 전부, 아니면 그 행 하나다.
  List<GitCommit> _menuCommits(GitCommit commit) {
    if (!_checkedCommits.contains(commit.sha)) return [commit];
    return [
      for (final row in _commits)
        if (_checkedCommits.contains(row.sha)) row,
    ];
  }

  /// HEAD에서 첫 부모만 따라 [commits]를 모두 지나는 줄 — 새 것부터. 히스토리를
  /// 다시 쓰는 일은 이 줄 위에서만 한다. 하나라도 줄에서 벗어나면 null이다.
  List<GitCommit>? _headChain(List<GitCommit> commits) {
    final current = _refs.current;
    final tip = current == null ? null : _refs.localTips[current];
    if (tip == null || _comparison != null || commits.isEmpty) return null;
    final wanted = {for (final commit in commits) commit.sha};
    final bySha = {for (final commit in _commits) commit.sha: commit};
    final chain = <GitCommit>[];
    var walk = bySha[tip];
    while (walk != null && !walk.isWorkingTree) {
      chain.add(walk);
      wanted.remove(walk.sha);
      if (wanted.isEmpty) return chain;
      walk = walk.parents.isEmpty ? null : bySha[walk.parents.first];
    }
    return null;
  }

  /// 잡은 커밋들이 그 줄에서 끊기지 않고 붙어 있는지. 합치기와 순서 뒤집기는
  /// 붙어 있는 구간만 다룬다 — 사이에 남을 커밋을 어디로 보낼지 정해 줄 사람이
  /// 없다.
  bool _contiguousRun(List<GitCommit> chain, List<GitCommit> commits) {
    final indexes = [
      for (final commit in commits)
        chain.indexWhere((row) => row.sha == commit.sha),
    ]..sort();
    if (indexes.isEmpty || indexes.first < 0) return false;
    return indexes.last - indexes.first == indexes.length - 1;
  }

  /// 히스토리를 다시 쓸 수 있는 상태인지 — 줄 위에 있고, 첫 커밋이 아니고, 작업
  /// 트리가 깨끗해야 한다. rebase는 더러운 트리를 거부하니 미리 막는다.
  bool _rewritable(List<GitCommit>? chain) =>
      chain != null && !_hasWorkingTree && chain.last.parents.length == 1;

  Future<void> _showCommitMenu(GitCommit commit, Offset position) async {
    final commits = _menuCommits(commit);
    final several = commits.length > 1;
    final chain = _headChain(commits);
    final rewritable = _rewritable(chain);
    final run = chain != null && _contiguousRun(chain, commits);
    final canPick =
        commits.every(_canCherryPick) && !commit.isWorkingTree;
    final atHead = chain != null && chain.first.sha == commits.first.sha;
    final items = <PopupMenuEntry<String>>[
      if (several)
        PopupMenuItem(
          key: const Key('commit-menu-count'),
          enabled: false,
          height: 26,
          child: Text(
            '커밋 ${commits.length}개',
            style: TextStyle(fontSize: 11, color: _palette.muted),
          ),
        ),
      _commitMenuItem(
        key: 'cherry-pick',
        label: '현재 브랜치로 체리픽',
        enabled: canPick,
      ),
      if (several)
        _commitMenuItem(
          key: 'squash',
          label: '커밋 ${commits.length}개 합치기',
          enabled: rewritable && run,
        ),
      if (!several)
        _commitMenuItem(
          key: 'reword',
          label: '커밋 메시지 고치기',
          enabled: rewritable,
        ),
      if (!several)
        _commitMenuItem(
          key: 'identity',
          label: '작성자 · 시각 고치기',
          enabled: rewritable,
        ),
      if (several)
        _commitMenuItem(
          key: 'reorder',
          label: '선택 구간 순서 뒤집기',
          enabled: rewritable && run,
        ),
      _commitMenuItem(
        key: 'rebase-onto',
        label: '다른 브랜치 위로 옮기기',
        enabled: rewritable && run && atHead && _otherLocalBranches().isNotEmpty,
      ),
      const PopupMenuDivider(),
      if (!several)
        _commitMenuItem(key: 'branch', label: '이 커밋에서 브랜치 만들기'),
      if (!several) _commitMenuItem(key: 'copy-sha', label: 'SHA 복사'),
      _commitMenuItem(
        key: 'revert',
        label: several ? '커밋 ${commits.length}개 되돌리기' : '이 커밋 되돌리기',
        enabled: !commit.isWorkingTree && _cherryPickState == null,
        danger: true,
      ),
      _commitMenuItem(
        key: 'drop',
        label: several ? '커밋 ${commits.length}개 버리기' : '이 커밋 버리기',
        enabled: rewritable,
        danger: true,
      ),
    ];
    if (commit.isWorkingTree) return;
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
      items: items,
    );
    if (!mounted) return;
    switch (action) {
      case 'cherry-pick':
        await _confirmCherryPickAll(commits);
      case 'reword':
        await _rewordCommit(commit, chain!);
      case 'identity':
        await _editCommitIdentity(commit, chain!);
      case 'squash':
        await _squashCommits(commits, chain!);
      case 'reorder':
        await _reorderCommits(commits, chain!);
      case 'rebase-onto':
        await _rebaseCommitsOnto(commits, position);
      case 'branch':
        await _createBranchAtCommit(commit);
      case 'copy-sha':
        await Clipboard.setData(ClipboardData(text: commit.sha));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${commit.shortSha} 복사됨')),
          );
        }
      case 'revert':
        await _revertCommits(commits);
      case 'drop':
        await _dropCommits(commits, chain!);
    }
  }

  PopupMenuItem<String> _commitMenuItem({
    required String key,
    required String label,
    bool enabled = true,
    bool danger = false,
  }) => PopupMenuItem(
    key: Key('commit-menu-$key'),
    value: key,
    enabled: enabled,
    height: 34,
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        color: danger && enabled ? YogitAlert.destructiveText : null,
      ),
    ),
  );

  List<String> _otherLocalBranches() => [
    for (final branch in _refs.local)
      if (branch != _refs.current) branch,
  ];

  /// 잡은 커밋들을 차례로 체리픽한다 — 오래된 것부터. 충돌이 나면 그 자리에서
  /// 멈추고, 남은 것은 기존 체리픽 화면이 이어받는다.
  Future<void> _confirmCherryPickAll(List<GitCommit> commits) async {
    if (commits.length == 1) {
      await _confirmCherryPick(commits.single);
      return;
    }
    final current = _refs.current;
    if (current == null) return;
    final approved = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: '커밋 ${commits.length}개를 체리픽할까요?',
        boxWidth: YogitAlert.listWidth,
        body: YogitAlertBlock([
          for (final commit in commits.reversed)
            '${commit.shortSha} ${commit.subject}',
          '→ $current',
        ]),
        confirmLabel: '체리픽',
        confirmKey: const Key('cherry-pick-confirm'),
      ),
    );
    if (approved != true) return;
    for (final commit in commits.reversed) {
      if (!mounted || _cherryPickState != null) return;
      await _runCherryPick(commit.sha);
    }
  }

  /// 커밋 메시지를 고친다. HEAD면 amend 한 걸음, 그 아래면 히스토리를 다시 쓴다.
  Future<void> _rewordCommit(GitCommit commit, List<GitCommit> chain) async {
    final String loaded;
    try {
      loaded = await widget.repository.loadCommitMessage(commit.sha);
    } catch (error) {
      if (mounted) _showCommitActionError('메시지를 읽지 못했습니다', error);
      return;
    }
    if (!mounted) return;
    final pushed = _amendPushedUpstream();
    final message = await _askCommitMessage(
      title: '커밋 메시지 고치기',
      subject: '${commit.shortSha} ${commit.subject}',
      detail: pushed == null ? null : '$pushed에 올라간 커밋이라 히스토리가 갈립니다.',
      initial: loaded.trimRight(),
      confirmLabel: '고치기',
    );
    if (message == null || message.trim().isEmpty || !mounted) return;
    final text = '${message.trim()}\n';
    if (chain.length == 1) {
      await _changingRepository(() async {
        try {
          await widget.repository.rewordHead(text);
          if (!mounted) return;
          await _reloadTimelineAfterCherryPick(null);
        } catch (error) {
          if (mounted) _showCommitActionError('메시지 고치기 실패', error);
        }
      });
      return;
    }
    await _runRewrite('메시지 고치기', chain, (oldestFirst) {
      return [
        for (final row in oldestFirst)
          RewriteStep(row.sha, message: row.sha == commit.sha ? text : null),
      ];
    });
  }

  /// 작성자와 작성 시각을 고친다. 커밋 내용은 그대로다.
  Future<void> _editCommitIdentity(
    GitCommit commit,
    List<GitCommit> chain,
  ) async {
    final identity = await _askCommitIdentity(commit);
    if (identity == null || !mounted) return;
    final (author, date) = identity;
    if (author.isEmpty && date.isEmpty) return;
    await _runRewrite('작성자 · 시각 고치기', chain, (oldestFirst) {
      return [
        for (final row in oldestFirst)
          RewriteStep(
            row.sha,
            author: row.sha == commit.sha && author.isNotEmpty ? author : null,
            date: row.sha == commit.sha && date.isNotEmpty ? date : null,
          ),
      ];
    });
  }

  /// 잡은 구간을 하나로 합친다 — 가장 오래된 커밋을 집고 나머지를 그 위에 얹은
  /// 뒤, 이어 붙인 메시지로 한 번 고친다.
  Future<void> _squashCommits(
    List<GitCommit> commits,
    List<GitCommit> chain,
  ) async {
    final oldest = commits.last;
    final messages = <String>[];
    try {
      for (final commit in commits.reversed) {
        messages.add(
          (await widget.repository.loadCommitMessage(commit.sha)).trim(),
        );
      }
    } catch (error) {
      if (mounted) _showCommitActionError('메시지를 읽지 못했습니다', error);
      return;
    }
    if (!mounted) return;
    final message = await _askCommitMessage(
      title: '커밋 ${commits.length}개를 하나로',
      subject: '${oldest.shortSha}..${commits.first.shortSha}',
      detail: '오래된 것부터 이어 붙인 메시지입니다. 고쳐서 커밋하세요.',
      initial: messages.join('\n\n'),
      confirmLabel: '합치기',
    );
    if (message == null || message.trim().isEmpty || !mounted) return;
    final selected = {for (final commit in commits) commit.sha};
    await _runRewrite('커밋 ${commits.length}개 합치기', chain, (oldestFirst) {
      return [
        for (final row in oldestFirst)
          if (!selected.contains(row.sha))
            RewriteStep(row.sha)
          else if (row.sha == oldest.sha)
            RewriteStep(row.sha, message: '${message.trim()}\n')
          else
            RewriteStep(row.sha, action: RewriteAction.fixup),
      ];
    });
  }

  /// 잡은 구간의 순서를 뒤집는다. 구간 밖의 커밋은 제자리에 있는다.
  Future<void> _reorderCommits(
    List<GitCommit> commits,
    List<GitCommit> chain,
  ) async {
    final selected = {for (final commit in commits) commit.sha};
    await _runRewrite('순서 뒤집기', chain, (oldestFirst) {
      final flipped = [
        for (final row in oldestFirst)
          if (selected.contains(row.sha)) row.sha,
      ].reversed.toList();
      var next = 0;
      return [
        for (final row in oldestFirst)
          RewriteStep(
            selected.contains(row.sha) ? flipped[next++] : row.sha,
          ),
      ];
    });
  }

  /// 잡은 커밋들을 히스토리에서 뺀다. 되돌리기와 달리 흔적이 남지 않는다.
  Future<void> _dropCommits(
    List<GitCommit> commits,
    List<GitCommit> chain,
  ) async {
    final approved = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: commits.length > 1 ? '커밋 ${commits.length}개를 버릴까요?' : '이 커밋을 버릴까요?',
        boxWidth: YogitAlert.listWidth,
        body: YogitAlertBlock([
          for (final commit in commits) '${commit.shortSha} ${commit.subject}',
        ]),
        detail: '히스토리에서 사라집니다. 되돌리는 커밋을 남기려면 되돌리기를 쓰세요.',
        role: YogitAlertRole.destructive,
        confirmLabel: '버리기',
        confirmKey: const Key('commit-drop-confirm'),
      ),
    );
    if (approved != true || !mounted) return;
    final selected = {for (final commit in commits) commit.sha};
    await _runRewrite('커밋 버리기', chain, (oldestFirst) {
      return [
        for (final row in oldestFirst)
          RewriteStep(
            row.sha,
            action: selected.contains(row.sha)
                ? RewriteAction.drop
                : RewriteAction.pick,
          ),
      ];
    });
  }

  /// 잡은 커밋들을 되돌리는 커밋을 쌓는다 — 새 것부터.
  Future<void> _revertCommits(List<GitCommit> commits) async {
    final approved = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: commits.length > 1
            ? '커밋 ${commits.length}개를 되돌릴까요?'
            : '이 커밋을 되돌릴까요?',
        boxWidth: YogitAlert.listWidth,
        body: YogitAlertBlock([
          for (final commit in commits) '${commit.shortSha} ${commit.subject}',
        ]),
        detail: '되돌리는 커밋이 새로 쌓입니다. 히스토리는 그대로 남습니다.',
        confirmLabel: '되돌리기',
        confirmKey: const Key('commit-revert-confirm'),
      ),
    );
    if (approved != true || !mounted) return;
    await _changingRepository(() async {
      try {
        await widget.repository.revertCommits([
          for (final commit in commits) commit.sha,
        ]);
        if (!mounted) return;
        _setCheckedCommits(const {});
        await _reloadTimelineAfterCherryPick(null);
      } catch (error) {
        if (mounted) _showCommitActionError('되돌리기 실패', error);
      }
    });
  }

  /// 이 커밋을 가리키는 새 브랜치. 체크아웃은 하지 않는다 — 표시만 남긴다.
  Future<void> _createBranchAtCommit(GitCommit commit) async {
    final name = await _askBranchName(commit);
    if (name == null || name.trim().isEmpty || !mounted) return;
    await _changingRepository(() async {
      try {
        await widget.repository.createBranchAt(name.trim(), commit.sha);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${name.trim()} 브랜치 만듦')),
        );
        await _reloadTimelineAfterCherryPick(null);
      } catch (error) {
        if (mounted) _showCommitActionError('브랜치 만들기 실패', error);
      }
    });
  }

  /// 잡은 구간을 고른 브랜치 위로 옮긴다. 현재 브랜치가 함께 따라간다.
  Future<void> _rebaseCommitsOnto(
    List<GitCommit> commits,
    Offset position,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final target = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        for (final branch in _otherLocalBranches())
          PopupMenuItem(
            key: Key('commit-menu-onto-$branch'),
            value: branch,
            height: 32,
            child: Text(branch, style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
    if (target == null || !mounted) return;
    await _changingRepository(() async {
      try {
        await widget.repository.rebaseRangeOnto(
          target: target,
          oldest: commits.last.sha,
        );
        if (!mounted) return;
        _setCheckedCommits(const {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$target 위로 옮김')));
        await _reloadTimelineAfterCherryPick(null);
      } catch (error) {
        if (mounted) _showCommitActionError('옮기기 실패', error);
      }
    });
  }

  /// 다시 쓰기 한 걸음: 줄의 가장 오래된 커밋의 부모를 바닥으로 두고, [build]가
  /// 적은 todo를 돌린다. 충돌은 git이 되돌리고 예외로 올라온다.
  Future<void> _runRewrite(
    String label,
    List<GitCommit> chain,
    List<RewriteStep> Function(List<GitCommit> oldestFirst) build,
  ) async {
    final oldest = chain.last;
    if (oldest.parents.length != 1) {
      _showCommitActionError(label, '첫 커밋과 병합 커밋은 다시 쓸 수 없습니다');
      return;
    }
    await _changingRepository(() async {
      try {
        await widget.repository.rewriteHistory(
          base: oldest.parents.first,
          steps: build(chain.reversed.toList()),
        );
        if (!mounted) return;
        _setCheckedCommits(const {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label 완료')));
        await _reloadTimelineAfterCherryPick(null);
      } catch (error) {
        if (mounted) _showCommitActionError('$label 실패', error);
      }
    });
  }

  void _showCommitActionError(String what, Object error) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$what: ${error.toString().trim()}')),
      );

  /// 메시지 한 통을 받는 대화창. 고치기와 합치기가 같은 창을 쓴다.
  Future<String?> _askCommitMessage({
    required String title,
    required String subject,
    required String initial,
    required String confirmLabel,
    String? detail,
  }) {
    // 대화창이 닫히는 애니메이션이 아직 이 컨트롤러를 읽으니, 창마다 새로 만들고
    // 버리지 않는다. 화면이 사라질 때 한 번 버린다.
    _commitMessageDraft.text = initial;
    return showYogitAlert<String>(
      context,
      YogitAlert(
        title: title,
        boxWidth: YogitAlert.listWidth,
        subtitle: _menuSubtitle(subject),
        detail: detail,
        confirmLabel: confirmLabel,
        confirmKey: const Key('commit-message-confirm'),
        onConfirm: () => _commitMessageDraft.text,
        body: TextField(
          key: const Key('commit-message-field'),
          controller: _commitMessageDraft,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          style: TextStyle(fontSize: 13, color: _palette.text),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  /// 작성자와 시각을 받는 대화창. 비워 둔 칸은 손대지 않는다.
  Future<(String, String)?> _askCommitIdentity(GitCommit commit) {
    _authorDraft.text = '${commit.author.name} <${commit.author.email}>';
    _dateDraft.text = DateTime.fromMillisecondsSinceEpoch(
      commit.authorTimestamp * 1000,
    ).toIso8601String();
    return showYogitAlert<(String, String)>(
      context,
      YogitAlert(
        title: '작성자 · 시각 고치기',
        boxWidth: YogitAlert.listWidth,
        subtitle: _menuSubtitle('${commit.shortSha} ${commit.subject}'),
        detail: '비워 둔 칸은 그대로 둡니다.',
        confirmLabel: '고치기',
        confirmKey: const Key('commit-identity-confirm'),
        onConfirm: () => (_authorDraft.text.trim(), _dateDraft.text.trim()),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _draftField(
              key: 'commit-author-field',
              controller: _authorDraft,
              label: '이름 <메일>',
              autofocus: true,
            ),
            const SizedBox(height: 8),
            _draftField(
              key: 'commit-date-field',
              controller: _dateDraft,
              label: '2024-03-04T05:06:07+09:00',
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askBranchName(GitCommit commit) {
    _branchNameDraft.text = '';
    return showYogitAlert<String>(
      context,
      YogitAlert(
        title: '이 커밋에서 브랜치 만들기',
        boxWidth: YogitAlert.listWidth,
        subtitle: _menuSubtitle('${commit.shortSha} ${commit.subject}'),
        confirmLabel: '만들기',
        confirmKey: const Key('commit-branch-confirm'),
        onConfirm: () => _branchNameDraft.text,
        body: _draftField(
          key: 'commit-branch-field',
          controller: _branchNameDraft,
          label: 'feature/이름',
          autofocus: true,
        ),
      ),
    );
  }

  Widget _menuSubtitle(String text) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 11, color: _palette.muted),
  );

  Widget _draftField({
    required String key,
    required TextEditingController controller,
    required String label,
    bool autofocus = false,
  }) => TextField(
    key: Key(key),
    controller: controller,
    autofocus: autofocus,
    style: TextStyle(fontSize: 13, color: _palette.text),
    decoration: InputDecoration(
      isDense: true,
      border: const OutlineInputBorder(),
      hintText: label,
      hintStyle: TextStyle(fontSize: 12, color: _palette.muted),
    ),
  );

  /// The local branch whose context menu is open; its row keeps the hover
  /// highlight while the popup covers the pointer.
  String? _contextMenuRef;

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
      await _changingRepository(() async {
        await widget.repository.deleteLocalBranch(branch);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$branch 브랜치 삭제됨')));
        // The deleted ref may be the timeline's base or decorate loaded rows,
        // so the whole page reloads rather than patching refs in place.
        await _reloadTimelineAfterCherryPick(null);
      });
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
      // 클로저 안에서는 위의 널 검사가 이어지지 않으니 여기서 붙잡아 둔다.
      final worktree = path;
      await _changingRepository(() async {
        await widget.repository.removeWorktree(worktree);
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
      });
    } on ProcessException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: ${error.message.trim()}')),
        );
      }
    }
  }

  /// Deletes a remote branch — the one sidebar action that changes something
  /// outside this repository, so the dialog says so before the button does it.
  /// The local branch it tracks is left where it stands.
  Future<void> _confirmDeleteRemoteBranch(String remoteBranch) async {
    final split = splitRemoteBranchName(remoteBranch, _refs.remoteNames);
    if (split == null) return;
    final approved = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: '원격 브랜치를 삭제할까요?',
        message: remoteBranch,
        detail:
            '${split.remote}에서 ${split.branch} 브랜치가 사라집니다. 같은 원격을 쓰는 다른 '
            '사람에게도 사라집니다. 로컬 브랜치는 그대로 남습니다.',
        role: YogitAlertRole.destructive,
        confirmLabel: '삭제',
        confirmKey: const Key('delete-remote-branch-confirm'),
      ),
    );
    if (approved != true || !mounted) return;
    await _deletingRef(
      () => widget.repository.deleteRemoteRef(
        split.remote,
        'refs/heads/${split.branch}',
      ),
      done: '$remoteBranch 삭제됨',
      failed: '원격 브랜치 삭제 실패',
    );
  }

  /// Where a tag's own copy would be pushed or deleted: what the branch's
  /// upstream says for a branch has no counterpart on a tag, so this follows
  /// the same last convention — the one remote if there is only one, else
  /// `origin` when it exists. Null leaves the deletion local-only.
  String? get _tagRemote => _refs.remoteNames.length == 1
      ? _refs.remoteNames.single
      : _refs.remoteNames.contains('origin')
      ? 'origin'
      : null;

  /// A tag deleted here alone comes back with the next fetch while the remote
  /// still holds it, so the dialog offers both reaches: the local delete as the
  /// safe primary, the remote one tinted beside it.
  Future<void> _confirmDeleteTag(String tag) async {
    final remote = _tagRemote;
    final answer = await showYogitAlert<Object>(
      context,
      YogitAlert(
        title: '태그를 삭제할까요?',
        message: tag,
        detail: remote == null
            ? '이 저장소에서 태그가 사라집니다. 태그가 가리키던 커밋은 그대로 남습니다.'
            : '로컬에서만 지우면 $remote에 남은 같은 태그가 다음 fetch에 돌아옵니다.',
        role: remote == null
            ? YogitAlertRole.destructive
            : YogitAlertRole.normal,
        confirmLabel: remote == null ? '삭제' : '로컬에서만 삭제',
        confirmKey: const Key('delete-tag-confirm'),
        destructiveLabel: remote == null ? null : '원격에서도 삭제',
        destructiveKey: const Key('delete-tag-remote-confirm'),
      ),
    );
    if (answer == null || !mounted) return;
    final alsoRemote = answer == 'destructive' && remote != null;
    await _deletingRef(
      () async {
        // The remote goes first: a refused push leaves the tag standing on both
        // sides, which is one state to retry from rather than two. A remote
        // that never held this tag is not a refusal — git warns and succeeds.
        if (alsoRemote) {
          await widget.repository.deleteRemoteRef(remote, 'refs/tags/$tag');
        }
        await widget.repository.deleteTag(tag);
      },
      done: alsoRemote ? '$tag 태그 삭제됨 · $remote에서도 삭제' : '$tag 태그 삭제됨',
      failed: '태그 삭제 실패',
    );
  }

  /// Several refs at once, from the sidebar's multi-selection: one dialog that
  /// names every one of them, then git once per ref, so a refusal on one — a
  /// branch git will not drop, a remote that says no — takes only that one down
  /// and the rest still go.
  ///
  /// One ref falls back to its own dialog: the worktree follow-up question and
  /// the tag's remote question only make sense a ref at a time.
  Future<void> _confirmDeleteRefs(
    _RefSection section,
    List<String> names,
  ) async {
    final targets = _deletableNames(section, names);
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      return switch (section) {
        _RefSection.local => _confirmDeleteBranch(targets.single),
        _RefSection.remote => _confirmDeleteRemoteBranch(targets.single),
        _RefSection.tags => _confirmDeleteTag(targets.single),
      };
    }
    final noun = section.noun;
    // 태그만 원격에도 같은 것이 남아 있는지를 묻는다 — 단일 삭제와 같은 물음이다.
    final tagRemote = section == _RefSection.tags ? _tagRemote : null;
    // 이름이 아주 많으면 목록이 대화상자를 밀어낸다. 앞의 것만 보이고 나머지는 수로.
    const shown = 8;
    final answer = await showYogitAlert<Object>(
      context,
      YogitAlert(
        title: '$noun ${targets.length}개를 삭제할까요?',
        body: YogitAlertBlock([
          ...targets.take(shown),
          if (targets.length > shown) '외 ${targets.length - shown}개',
        ]),
        detail: switch (section) {
          _RefSection.local => '병합되지 않은 커밋도 함께 사라집니다.',
          _RefSection.remote => '같은 원격을 쓰는 다른 사람에게도 사라집니다. 로컬 브랜치는 그대로 남습니다.',
          _RefSection.tags =>
            tagRemote == null
                ? '이 저장소에서 태그가 사라집니다. 태그가 가리키던 커밋은 그대로 남습니다.'
                : '로컬에서만 지우면 $tagRemote에 남은 같은 태그가 다음 fetch에 돌아옵니다.',
        },
        role: tagRemote == null
            ? YogitAlertRole.destructive
            : YogitAlertRole.normal,
        confirmLabel: tagRemote == null ? '삭제' : '로컬에서만 삭제',
        confirmKey: const Key('delete-refs-confirm'),
        destructiveLabel: tagRemote == null ? null : '원격에서도 삭제',
        destructiveKey: const Key('delete-refs-remote-confirm'),
      ),
    );
    if (answer == null || !mounted) return;
    final alsoRemote = answer == 'destructive' && tagRemote != null;
    final failed = <String>[];
    await _changingRepository(() async {
      for (final name in targets) {
        try {
          switch (section) {
            case _RefSection.local:
              await widget.repository.deleteLocalBranch(name);
            case _RefSection.remote:
              final split = splitRemoteBranchName(name, _refs.remoteNames);
              if (split == null) {
                failed.add(name);
              } else {
                await widget.repository.deleteRemoteRef(
                  split.remote,
                  'refs/heads/${split.branch}',
                );
              }
            case _RefSection.tags:
              // 원격이 먼저다 — 거절당하면 태그는 양쪽에 그대로 남아, 다시
              // 해 볼 자리가 하나로 남는다.
              if (alsoRemote) {
                await widget.repository.deleteRemoteRef(
                  tagRemote,
                  'refs/tags/$name',
                );
              }
              await widget.repository.deleteTag(name);
          }
        } on ProcessException {
          failed.add(name);
        }
      }
      if (!mounted) return;
      final done = targets.length - failed.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed.isEmpty
                ? '$noun $done개 삭제됨'
                : '$noun $done개 삭제됨 · ${failed.length}개 실패: ${failed.join(', ')}',
          ),
        ),
      );
      // 지운 ref가 기준이었거나 적재된 줄을 꾸미고 있었을 수 있으니 페이지째 다시 읽는다.
      await _reloadTimelineAfterCherryPick(null);
    });
    if (mounted) {
      _rebuild(_checkedRefs.clear);
    } else {
      _checkedRefs.clear();
    }
  }

  /// Runs a ref deletion and reloads the page whole: the ref that just died may
  /// have been the timeline's base or decorated a loaded row, so patching refs
  /// in place would leave the graph pointing at something gone.
  Future<void> _deletingRef(
    Future<void> Function() delete, {
    required String done,
    required String failed,
  }) async {
    try {
      await _changingRepository(() async {
        await delete();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
        await _reloadTimelineAfterCherryPick(null);
      });
    } on ProcessException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failed: ${error.message.trim()}')),
      );
    }
  }

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

  /// The status bar's own width, so the profile chip can shed its email on a
  /// narrow window without a LayoutBuilder between Stack and Positioned.
  double _statusBarWidth = 0;

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
        _statusBarWidth -
        12 -
        _statusChipWidth() -
        8 -
        // The console glyph shares the chip's end of the row, so the stamp has
        // to yield for it too — otherwise a narrow bar overflows by its width.
        (widget.commandLog == null ? 0 : _consoleToggleWidth + 8) -
        _statusStampWidth;
    return math.max(
      0,
      math.min(_hashColumnLeft + _railedColumnTextInset, rightmost),
    );
  }

  /// 프레임이 굳었다가 되살아난 적이 있을 때만 나오는 표시. 평소에는 자리를
  /// 차지하지 않는다. 사용자가 "가끔 멈춰요"라고 할 때 이 줄 하나가 원인을
  /// 짚어준다 — 로그도 예외도 안 남는 종류의 멈춤이라서다.
  Widget _frameRevivalNotice() => ValueListenableBuilder<int>(
    valueListenable: WindowFrameController.frameRevivals,
    builder: (context, count, _) => count == 0
        ? const SizedBox.shrink()
        : Tooltip(
            message:
                '창이 다시 보이는데도 화면 갱신이 꺼져 있어 $count번 되살렸습니다. '
                'macOS가 창 상태를 늦게 알려줄 때 생깁니다.',
            child: Text(
              key: const Key('frame-revival-notice'),
              '화면 갱신 복구 $count',
              style: TextStyle(color: behindOrange, fontSize: 10),
            ),
          ),
  );

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
              // 찾기 줄은 목록 위에 떠 있다. 행 하나를 차지하면 검색을 여는
              // 것만으로 읽고 있던 역사가 밀려난다.
              child: Stack(
                children: [
                  SingleChildScrollView(
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
                                    if (index == _entries.length) {
                                      return _footer();
                                    }
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
                  if (_searchOpen)
                    _searchBar()
                  else if (_searchLive)
                    _searchPill(),
                ],
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

  /// 기준 브랜치가 원격 추적 브랜치인지. 그러면 기준을 옮기는 적용은 받을 로컬
  /// 브랜치가 없어 성립하지 않는다: Merge도, 재배치 위에 머지 커밋을 얹는 쪽도.
  bool get _baseBranchIsRemote {
    final base = _comparison?.baseRef ?? _baseBranch;
    return base != null &&
        !_refs.local.contains(base) &&
        _refs.remote.contains(base);
  }

  /// 카드가 고른 착지. 기준이 원격이면 머지 커밋을 얹을 수 없으니 'Rebase만'으로
  /// 고정된다.
  bool get _rebaseApplyMergeEffective =>
      _rebaseApplyMerge && !_baseBranchIsRemote;

  /// Which rebase apply path the card has selected. Merge mode never asks.
  bool get _rebaseThenMergeSelected =>
      _branchPreviewMode == BranchPreviewMode.rebase &&
      _rebaseApplyMergeEffective;

  static String _applyModeLabel(BranchApplyMode mode) => switch (mode) {
    BranchApplyMode.merge => 'Merge',
    BranchApplyMode.rebase => 'Rebase',
    BranchApplyMode.rebaseMerge => 'Rebase 후 Merge',
  };

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

  /// The room a fitted ref name keeps clear of its box, for the ink a glyph
  /// draws beyond the width it reports. A trailing descender at these sizes
  /// reaches about a point past its advance, so two is the safe side of one.
  static const _refNameInkCushion = 2.0;

  /// The hairline a chip draws around itself. A [Container] lays its child out
  /// inside the decoration as well as the padding, so this is room the name
  /// does not get.
  static const _refChipBorder = 1.0;
  static const _refGlyphWidth = 16.0;

  /// Every box a row draws inside itself — a ref chip, a date heading — is this
  /// tall, which is [TimelineScreen.rowHeight] less the hairline of background
  /// the row keeps above and below so stacked chips never touch.
  /// One step of the sidebar's ref tree, and the disclosure arrow's column.
  /// Small on purpose: three levels of `origin/codex/spike` used to push a
  /// name past half the pane before its first letter.
  static const _refIndentStep = 10.0;
  static const _refDisclosureWidth = 14.0;

  static const _rowChipHeight = TimelineScreen.rowHeight - 2;

  /// The strip along the bottom. What floats above the timeline has to clear
  /// it rather than sit on it.
  static const _statusBarHeight = 29.0;

  /// The console glyph's slot, left of the chip. Fixed rather than measured so
  /// the stamp's column can budget for it before either one is laid out.
  static const _consoleToggleWidth = 28.0;

  /// The header label and the hash cell, without the colors that come and go
  /// with hover and selection. Shared with the double-click fit, which measures
  /// what these two actually draw.
  static const _headerLabelStyle = TextStyle(
    fontSize: 12,
    fontFamily: technicalFontFamily,
    fontFamilyFallback: technicalFontFallback,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.66,
  );
  static const _hashStyle = TextStyle(
    fontSize: 12,
    fontFamily: technicalFontFamily,
    fontFamilyFallback: technicalFontFallback,
    fontWeight: FontWeight.w500,
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

  /// The column's width as it stands *now*, not as it stood when the divider
  /// was built. A fast mouse delivers several moves between frames, and each
  /// one has to build on what the one before it left.
  double _liveWidth(String column) => switch (column) {
    'graph' => _graphColumnWidth,
    // The title column holds no width of its own; its divider moves by
    // transfer, so [_resizeBy] never reads this.
    'commit' => _commitAvailableWidth,
    _ => _w(column),
  };

  Widget _resizer(String column) => Positioned(
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
        _resizeBy(column, _liveWidth(column), delta);
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
            _resizeBy(column, _liveWidth(column), details.delta.dx);
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
      _graphSqueezeDepth,
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

  /// Whether a chip [width] wide has to cut [ref]'s name. Measured the way the
  /// chip is built: its own side padding, the glyph and the gap after it, then
  /// the name in the type the row actually paints with.
  ///
  /// A point either way only moves where the whole-name copy starts opening,
  /// which is a far cheaper mistake than cutting a name that fits.
  /// How wide the chip would be with its whole name on show: its own side
  /// padding, the border it draws inside that, the glyph and the gap after it,
  /// and the name in the type the row actually paints with.
  ///
  /// The border counts because a [Container] lays its child out inside the
  /// decoration as well as the padding. Forgetting it leaves this two points
  /// under the room the name is really cut against, and names that overrun by
  /// exactly that much are judged to fit — cut on screen and refusing to open.
  double _wholeRefChipWidth(GitRef ref, Color color, BuildContext context) {
    final inherited = DefaultTextStyle.of(context).style;
    final glyph = ref.isHead || ref.isTag
        ? _textWidth(
                ref.isHead ? '✓' : '◇',
                inherited.merge(const TextStyle(fontSize: 10)),
              ) +
              3
        : 0.0;
    return _refChipPadding +
        _refChipBorder * 2 +
        glyph +
        _textWidth(ref.name, inherited.merge(_refNameStyle(color)));
  }

  bool _refNameIsCut(
    GitRef ref,
    Color color,
    double width,
    BuildContext context,
  ) {
    if (_comparison != null || !width.isFinite) return false;
    return _wholeRefChipWidth(ref, color, context) + _refNameInkCushion > width;
  }

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
          builder: (context, constraints) {
            // Measure the style the row actually paints with. A chip carries
            // no letter spacing of its own and inherits a quarter point of it,
            // so measuring the bare style comes up short by that much per
            // character — a couple of points on a short name, five on a long
            // one, and the tail is cut off inside its own box.
            final painted = DefaultTextStyle.of(context).style.merge(style);
            return Text(
              fitRefName(
                name,
                // A glyph can ink a hair past the advance width it measures, so
                // a name cut to exactly its box loses the last letter's tail to
                // the chip's border. Stop one point short of the edge.
                constraints.maxWidth - _refNameInkCushion,
                (text) => _textWidth(text, painted),
              ),
              maxLines: 1,
              softWrap: false,
              // The string is already cut to the width; clip only guards
              // against a font that draws a shade wider than it measures.
              overflow: TextOverflow.clip,
              style: style,
            );
          },
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

  Future<String> _commitMessageFor(String sha) =>
      FullDiffCommitMessageCache.shared.getOrLoad(
        repositoryRoot: widget.repository.root,
        sha: sha,
        loader: () => widget.repository.loadCommitMessage(sha),
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
