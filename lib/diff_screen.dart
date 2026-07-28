import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'avatars.dart';
import 'external_editor.dart';
import 'full_diff_algorithm_chooser.dart';
import 'full_blame_view.dart';
import 'full_diff_commit_message_cache.dart';
import 'full_diff_controller.dart';
import 'full_diff_header.dart';
import 'full_diff_minimap.dart';
import 'full_diff_model.dart';
import 'full_diff_resizable_pane.dart';
import 'full_diff_selectable_row.dart';
import 'full_diff_side_by_side_view.dart';
import 'full_diff_syntax.dart';
import 'full_diff_theme.dart';
import 'full_diff_unified_view.dart';
import 'full_diff_unavailable_panel.dart';
import 'full_history_view.dart';
import 'full_history_workspace.dart';
import 'git.dart';
import 'page_scroll_shortcuts.dart';
import 'settings.dart';
import 'typography.dart';

class _ReturnToTimelineIntent extends Intent {
  const _ReturnToTimelineIntent();
}

class _ToggleFocusModeIntent extends Intent {
  const _ToggleFocusModeIntent();
}

class _SelectViewIntent extends Intent {
  const _SelectViewIntent(this.view);

  final FullDiffView view;
}

class _ToggleLayoutIntent extends Intent {
  const _ToggleLayoutIntent();
}

class _ToggleScopeIntent extends Intent {
  const _ToggleScopeIntent();
}

class _ToggleWhitespaceIntent extends Intent {
  const _ToggleWhitespaceIntent();
}

class _ToggleWrapIntent extends Intent {
  const _ToggleWrapIntent();
}

class _OpenAlgorithmChooserIntent extends Intent {
  const _OpenAlgorithmChooserIntent();
}

class _StepHunkIntent extends Intent {
  const _StepHunkIntent(this.delta);

  final int delta;
}

class _StepFileIntent extends Intent {
  const _StepFileIntent(this.delta);

  final int delta;
}

class _StepPrimaryFileIntent extends Intent {
  const _StepPrimaryFileIntent(this.delta);

  final int delta;
}

enum _FullDiffNavigationPane { files, history, blame }

@visibleForTesting
class FullDiffScrollController extends ScrollController {
  FullDiffScrollController({super.onAttach});

  @visibleForTesting
  bool debugClientsAvailable = true;

  bool get clientsReady => debugClientsAvailable && hasClients;
}

/// Full-diff workspace for one controller-backed session.
///
/// Rebuilding an owned session with new [repository] or [commits] replaces that
/// session. Changing [controller] swaps the subscription, while an injected
/// controller remains externally owned and authoritative for its session.
class DiffScreen extends StatefulWidget {
  const DiffScreen({
    required this.repository,
    required this.commits,
    required this.initialIndex,
    this.initialPreferences = const FullDiffPreferences(),
    this.controller,
    this.columnWidths = const FullDiffColumnWidths(),
    this.onColumnWidthsChanged,
    this.onPreferencesChanged,
    this.editorService,
    this.avatarService,
    this.commitMessageCache,
    this.showRemoteAvatars = true,
    super.key,
  });

  final FullDiffRepository repository;
  final List<GitCommit> commits;
  final int initialIndex;
  final FullDiffPreferences initialPreferences;
  final FullDiffSessionController? controller;
  final FullDiffColumnWidths columnWidths;
  final ValueChanged<FullDiffColumnWidths>? onColumnWidthsChanged;
  final ValueChanged<FullDiffPreferences>? onPreferencesChanged;
  final ExternalEditorService? editorService;
  final AvatarService? avatarService;
  final FullDiffCommitMessageCache? commitMessageCache;
  final bool showRemoteAvatars;

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  late final FullDiffScrollController _contentScroll;
  final _historyScroll = ScrollController();
  final _fileListFocus = FocusNode(debugLabel: 'full diff files');
  final _historyListFocus = FocusNode(debugLabel: 'full diff history');
  final _blameListFocus = FocusNode(debugLabel: 'full diff blame');
  final _algorithmChooserKey = GlobalKey<FullDiffAlgorithmChooserState>();
  final _contentViewportKey = GlobalKey();
  final _fullFileScrollTargetKey = GlobalKey(
    debugLabel: 'full file scroll target',
  );
  final _highlighter = HighlightJsSyntaxHighlighter();
  Map<String, GlobalKey> _anchorKeys = <String, GlobalKey>{};
  final Map<String, Set<BuildContext>> _anchorProbeContexts = {};

  late FullDiffSessionController _controller;
  late ExternalEditorService _editorService;
  late bool _ownsController;
  late FullDiffSessionState _observedState;
  late FullDiffPreferences _lastReportedPreferences;
  late double _filesWidth;
  late double _historyWidth;
  late double _sideBySideRatio;
  _FullDiffNavigationPane _lastDiffHistoryNavigationPane =
      _FullDiffNavigationPane.files;
  _FullDiffNavigationPane _lastBlameNavigationPane =
      _FullDiffNavigationPane.files;
  double? _lastResponsiveWidth;

  bool _effectScheduled = false;
  bool _scrollSyncScheduled = false;
  bool _programmaticAnchorScroll = false;
  bool _pendingScrollToTop = false;
  bool _pendingHistoryScrollToTop = false;
  bool _pendingFullFileScrollToTop = false;
  String? _pendingAnchorId;
  DiffSourceTarget? _pendingFullFileScrollTarget;
  DiffSourceTargetIdentity? _pendingFullFileScrollIdentity;
  int _pendingAnchorDirection = 0;
  String? _editorError;
  bool _openingEditor = false;
  bool _commandHeld = false;
  int _editorRequestSerial = 0;

  FullDiffCommitMessageCache get _commitMessageCache =>
      widget.commitMessageCache ?? FullDiffCommitMessageCache.shared;

  Future<String> _loadCommitMessage(String sha) =>
      _commitMessageCache.getOrLoad(
        repositoryRoot: widget.repository.root,
        sha: sha,
        loader: () => widget.repository.loadCommitMessage(sha),
      );

  @override
  void initState() {
    super.initState();
    _contentScroll = FullDiffScrollController(
      onAttach: (_) => _handleContentScrollAttached(),
    );
    _filesWidth = widget.columnWidths.files;
    _historyWidth = widget.columnWidths.history;
    _sideBySideRatio = widget.columnWidths.sideBySideRatio;
    _editorService =
        widget.editorService ??
        ExternalEditorService(repositoryRoot: widget.repository.root);
    _attachController(_newController());
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    _contentScroll.addListener(_handleContentScrolled);
    _fileListFocus.addListener(_handleFileListFocusChanged);
    _historyListFocus.addListener(_handleHistoryListFocusChanged);
    _blameListFocus.addListener(_handleBlameListFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreNavigationFocus();
    });
    _queueAttachedAnchorScroll();
    if (_ownsController) unawaited(_controller.initialize());
  }

  FullDiffSessionController _newController() {
    _ownsController = widget.controller == null;
    return widget.controller ??
        FullDiffSessionController(
          repository: widget.repository,
          commits: widget.commits,
          initialIndex: widget.initialIndex,
          initialPreferences: widget.initialPreferences,
        );
  }

  void _attachController(FullDiffSessionController controller) {
    _controller = controller;
    _observedState = controller.state;
    _lastReportedPreferences = _observedState.preferences;
    _reconcileAnchorKeys(_observedState.patch.data);
    controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant DiffScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.columnWidths != oldWidget.columnWidths) {
      _filesWidth = widget.columnWidths.files;
      _historyWidth = widget.columnWidths.history;
      _sideBySideRatio = widget.columnWidths.sideBySideRatio;
    }
    final editorContextChanged =
        widget.editorService != oldWidget.editorService ||
        widget.repository.root != oldWidget.repository.root;
    if (editorContextChanged) {
      _editorService =
          widget.editorService ??
          ExternalEditorService(repositoryRoot: widget.repository.root);
    }

    final controllerChanged = !identical(
      widget.controller,
      oldWidget.controller,
    );
    final ownedInputsChanged =
        widget.controller == null &&
        oldWidget.controller == null &&
        (!identical(widget.repository, oldWidget.repository) ||
            !identical(widget.commits, oldWidget.commits) ||
            widget.initialIndex != oldWidget.initialIndex);
    if (editorContextChanged || controllerChanged || ownedInputsChanged) {
      _invalidateEditorRequest();
    }
    if (!controllerChanged && !ownedInputsChanged) return;

    _controller.removeListener(_handleControllerChanged);
    if (_ownsController) _controller.dispose();
    _attachController(_newController());
    _pendingScrollToTop = true;
    _pendingHistoryScrollToTop = true;
    _pendingAnchorId = null;
    _clearPendingFullFileScroll();
    _queueAttachedAnchorScroll();
    if (_pendingAnchorId == null && _pendingFullFileScrollTarget == null) {
      _scheduleScrollEffect();
    }
    if (_ownsController) unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _editorRequestSerial++;
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    _controller.removeListener(_handleControllerChanged);
    _contentScroll
      ..removeListener(_handleContentScrolled)
      ..dispose();
    _historyScroll.dispose();
    _fileListFocus.removeListener(_handleFileListFocusChanged);
    _historyListFocus.removeListener(_handleHistoryListFocusChanged);
    _blameListFocus.removeListener(_handleBlameListFocusChanged);
    _fileListFocus.dispose();
    _historyListFocus.dispose();
    _blameListFocus.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.metaLeft &&
        event.logicalKey != LogicalKeyboardKey.metaRight) {
      return false;
    }
    final held = HardwareKeyboard.instance.isMetaPressed;
    if (_commandHeld != held && mounted) {
      setState(() => _commandHeld = held);
    }
    return false;
  }

  KeyEventResult _handlePageScrollKeyEvent(FocusNode _, KeyEvent event) {
    final intent = pageScrollIntentFor(
      event,
      metaPressed: HardwareKeyboard.instance.isMetaPressed,
      shiftPressed: HardwareKeyboard.instance.isShiftPressed,
    );
    if (intent == null) return KeyEventResult.ignored;
    applyPageScroll(
      _contentScroll,
      direction: intent.direction,
      animate: event is KeyDownEvent,
    );
    return KeyEventResult.handled;
  }

  void _invalidateEditorRequest() {
    _editorRequestSerial++;
    _openingEditor = false;
    _editorError = null;
  }

  void _handleControllerChanged() {
    final previous = _observedState;
    final next = _controller.state;
    _observedState = next;
    _reportPreferences(next);
    final movedContext =
        previous.selectedCommit.sha != next.selectedCommit.sha ||
        previous.parent != next.parent ||
        previous.selectedFile?.path != next.selectedFile?.path;
    final changedDocument = !identical(previous.patch.data, next.patch.data);
    final enteredSourceView =
        previous.view != next.view && next.view == FullDiffView.blame;
    final previousIndex = previous.activeAnchor?.hunkIndex ?? 0;
    final nextIndex = next.activeAnchor?.hunkIndex ?? 0;
    final navigationRequested =
        previous.navigationSerial != next.navigationSerial;
    final nextAnchor = next.activeAnchor;
    final alignFullFileDocument =
        changedDocument &&
        next.view == FullDiffView.diff &&
        next.appliedScope == DiffScope.fullFile &&
        (next.fullFileScrollTarget != null || previous.patch.data == null);

    if (changedDocument) _reconcileAnchorKeys(next.patch.data);
    if (previous.history.data == null &&
        next.history.data != null &&
        next.view == FullDiffView.history) {
      _restoreNavigationFocus();
    }
    if (!identical(previous.blame.data, next.blame.data) &&
        next.view == FullDiffView.blame) {
      _restoreNavigationFocus();
    }
    if (previous.historyContext != next.historyContext) {
      _pendingHistoryScrollToTop = true;
    }
    if (movedContext) {
      _invalidateEditorRequest();
      _pendingScrollToTop = true;
      _pendingAnchorId = null;
      _clearPendingFullFileScroll();
    }
    final pendingSourceTarget = _pendingFullFileScrollTarget;
    if (pendingSourceTarget != null &&
        !_isCurrentFullFileScrollTarget(next, pendingSourceTarget)) {
      _clearPendingFullFileScroll();
    }
    if (nextAnchor != null &&
        (enteredSourceView ||
            (changedDocument && next.view == FullDiffView.blame))) {
      _pendingAnchorId = nextAnchor.id;
      _pendingAnchorDirection = nextIndex.compareTo(previousIndex);
    }
    if (alignFullFileDocument) {
      final sourceTarget = next.fullFileScrollTarget;
      if (sourceTarget != null) {
        _queueFullFileScroll(next, sourceTarget);
        _pendingAnchorId = null;
      } else if (nextAnchor != null) {
        _pendingAnchorId = nextAnchor.id;
        _pendingAnchorDirection = nextIndex == previousIndex
            ? 1
            : nextIndex.compareTo(previousIndex);
      }
    }
    if (navigationRequested && nextAnchor != null && !movedContext) {
      _clearPendingFullFileScroll();
      _pendingScrollToTop = false;
      _pendingAnchorId = nextAnchor.id;
      _pendingAnchorDirection = nextIndex.compareTo(previousIndex);
    }
    if (_pendingScrollToTop ||
        _pendingHistoryScrollToTop ||
        _pendingFullFileScrollTarget != null ||
        _pendingAnchorId != null) {
      _scheduleScrollEffect();
    }
  }

  void _reportPreferences(FullDiffSessionState state) {
    final next = state.preferences;
    if (next == _lastReportedPreferences) return;
    _lastReportedPreferences = next;
    widget.onPreferencesChanged?.call(next);
  }

  void _reconcileAnchorKeys(DiffDocument? document) {
    final previous = _anchorKeys;
    _anchorProbeContexts.clear();
    _anchorKeys = <String, GlobalKey>{
      for (final hunk in document?.hunks ?? const <DiffHunk>[])
        hunk.anchor.id: previous[hunk.anchor.id] ?? GlobalKey(),
    };
  }

  void _attachAnchorProbe(DiffAnchor anchor, BuildContext context) {
    (_anchorProbeContexts[anchor.id] ??= <BuildContext>{}).add(context);
    if (_pendingFullFileScrollTarget != null || _pendingAnchorId == anchor.id) {
      _scheduleScrollEffect();
    }
  }

  void _detachAnchorProbe(DiffAnchor anchor, BuildContext context) {
    final contexts = _anchorProbeContexts[anchor.id];
    contexts?.remove(context);
    if (contexts?.isEmpty ?? false) {
      _anchorProbeContexts.remove(anchor.id);
    }
  }

  void _queueAttachedAnchorScroll() {
    final state = _controller.state;
    final sourceTarget = state.fullFileScrollTarget;
    if (state.view == FullDiffView.diff &&
        state.appliedScope == DiffScope.fullFile &&
        sourceTarget != null) {
      _queueFullFileScroll(state, sourceTarget);
      _scheduleScrollEffect();
      return;
    }
    final anchor = state.activeAnchor;
    if (state.view == FullDiffView.history ||
        anchor == null ||
        (state.view == FullDiffView.diff &&
            state.appliedScope == DiffScope.hunks &&
            anchor.hunkIndex == 0)) {
      return;
    }
    _pendingAnchorId = anchor.id;
    _pendingAnchorDirection = 1;
    _scheduleScrollEffect();
  }

  void _scheduleScrollEffect() {
    if (_effectScheduled) return;
    _effectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _effectScheduled = false;
      if (!mounted) return;

      var sourceTarget = _pendingFullFileScrollTarget;
      if (sourceTarget != null &&
          !_isCurrentFullFileScrollTarget(_controller.state, sourceTarget)) {
        _clearPendingFullFileScroll();
        sourceTarget = null;
      }
      if (_pendingFullFileScrollToTop && _contentScroll.clientsReady) {
        _contentScroll.jumpTo(_contentScroll.position.minScrollExtent);
        _pendingFullFileScrollToTop = false;
      }
      if (_pendingScrollToTop && _contentScroll.clientsReady) {
        _contentScroll.jumpTo(_contentScroll.position.minScrollExtent);
        _pendingScrollToTop = false;
      }
      if (_pendingHistoryScrollToTop && _historyScroll.hasClients) {
        _historyScroll.jumpTo(_historyScroll.position.minScrollExtent);
        _pendingHistoryScrollToTop = false;
      }

      if (sourceTarget != null) {
        final targetContext = _fullFileScrollTargetKey.currentContext;
        if (targetContext != null) {
          final targetRenderObject = targetContext.findRenderObject();
          if (targetRenderObject == null || !_contentScroll.clientsReady) {
            return;
          }
          _clearPendingFullFileScroll();
          _programmaticAnchorScroll = true;
          unawaited(
            _contentScroll.position
                .ensureVisible(
                  targetRenderObject,
                  alignment: 0,
                  duration: const Duration(milliseconds: 100),
                )
                .whenComplete(() {
                  if (mounted) _programmaticAnchorScroll = false;
                }),
          );
          return;
        }
        if (!_contentScroll.clientsReady) return;
        final position = _contentScroll.position;
        final nextOffset = (position.pixels + position.viewportDimension).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((nextOffset - position.pixels).abs() < 0.5) {
          _clearPendingFullFileScroll();
          return;
        }
        position.jumpTo(nextOffset);
        _scheduleScrollEffect();
        return;
      }

      final anchorId = _pendingAnchorId;
      if (anchorId == null) return;
      final activeAnchor = _controller.state.activeAnchor;
      if (activeAnchor == null || activeAnchor.id != anchorId) {
        _pendingAnchorId = null;
        return;
      }
      final anchorContext = _anchorKeys[anchorId]?.currentContext;
      if (anchorContext != null) {
        final anchorRenderObject = anchorContext.findRenderObject();
        if (anchorRenderObject == null || !_contentScroll.clientsReady) {
          return;
        }
        _pendingAnchorId = null;
        _programmaticAnchorScroll = true;
        final state = _controller.state;
        final alignment = switch (state.view) {
          FullDiffView.blame => 0.2,
          FullDiffView.diff => 0.0,
          FullDiffView.history => 0.1,
        };
        unawaited(
          _contentScroll.position
              .ensureVisible(
                anchorRenderObject,
                alignment: alignment,
                duration: const Duration(milliseconds: 100),
              )
              .whenComplete(() {
                if (mounted) _programmaticAnchorScroll = false;
              }),
        );
        return;
      }
      if (!_contentScroll.clientsReady) {
        return;
      }

      final position = _contentScroll.position;
      final nextOffset = _nextAnchorSearchOffset(
        position,
        activeAnchor,
        _controller.state,
      );
      if ((nextOffset - position.pixels).abs() < 0.5) {
        _pendingAnchorId = null;
        return;
      }
      position.jumpTo(nextOffset);
      _scheduleScrollEffect();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _isCurrentFullFileScrollTarget(
    FullDiffSessionState state,
    DiffSourceTarget target,
  ) =>
      state.view == FullDiffView.diff &&
      state.requestedScope == DiffScope.fullFile &&
      state.appliedScope == DiffScope.fullFile &&
      state.fullFileScrollTarget == target &&
      _pendingFullFileScrollIdentity?.matches(
            document: state.patch.data,
            target: target,
          ) ==
          true;

  void _queueFullFileScroll(
    FullDiffSessionState state,
    DiffSourceTarget target,
  ) {
    final document = state.patch.data;
    if (document == null) return;
    _pendingFullFileScrollTarget = target;
    _pendingFullFileScrollIdentity = DiffSourceTargetIdentity(
      document: document,
      target: target,
    );
    _pendingFullFileScrollToTop = true;
  }

  void _handleContentScrollAttached() {
    if (_pendingScrollToTop ||
        _pendingFullFileScrollToTop ||
        _pendingFullFileScrollTarget != null ||
        _pendingAnchorId != null) {
      _scheduleScrollEffect();
    }
  }

  void _clearPendingFullFileScroll() {
    _pendingFullFileScrollTarget = null;
    _pendingFullFileScrollIdentity = null;
    _pendingFullFileScrollToTop = false;
  }

  double _nextAnchorSearchOffset(
    ScrollPosition position,
    DiffAnchor anchor,
    FullDiffSessionState state,
  ) {
    if (state.view == FullDiffView.blame) {
      final deleted = state.selectedFile?.status.startsWith('D') ?? false;
      final line = deleted ? anchor.oldLine : anchor.newLine;
      final lineCount =
          state.file.data?.lines.length ??
          state.patch.data?.sourceLineCount ??
          0;
      if (line != null && lineCount > 1) {
        return (position.maxScrollExtent * (line - 1) / (lineCount - 1)).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
      }
    }
    final direction = _pendingAnchorDirection == 0
        ? (anchor.hunkIndex == 0 ? -1 : 1)
        : _pendingAnchorDirection;
    return (position.pixels + direction * position.viewportDimension).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  void _handleContentScrolled() {
    if (_scrollSyncScheduled ||
        _pendingAnchorId != null ||
        _pendingFullFileScrollTarget != null ||
        _programmaticAnchorScroll) {
      return;
    }
    _scrollSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollSyncScheduled = false;
      if (mounted) _syncAnchorFromViewport();
    });
  }

  void _syncAnchorFromViewport() {
    final document = _controller.state.patch.data;
    final viewportContext = _contentViewportKey.currentContext;
    if (document == null || viewportContext == null) return;
    final viewport = viewportContext.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return;
    final centerY =
        viewport.localToGlobal(Offset.zero).dy + viewport.size.height / 2;
    final viewportRect = viewport.localToGlobal(Offset.zero) & viewport.size;
    DiffAnchor? nearest;
    var nearestDistance = double.infinity;
    var hasAttachedProbe = false;
    for (final hunk in document.hunks) {
      for (final context
          in _anchorProbeContexts[hunk.anchor.id] ?? const <BuildContext>{}) {
        final renderObject = context.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.attached) continue;
        hasAttachedProbe = true;
        final rect =
            renderObject.localToGlobal(Offset.zero) & renderObject.size;
        if (!rect.overlaps(viewportRect)) continue;
        final distance = (rect.center.dy - centerY).abs();
        if (distance < nearestDistance) {
          nearest = hunk.anchor;
          nearestDistance = distance;
        }
      }
    }
    if (hasAttachedProbe) {
      if (nearest != null) _controller.syncAnchorFromScroll(nearest);
      return;
    }
    for (final hunk in document.hunks) {
      final context = _anchorKeys[hunk.anchor.id]?.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final distance = (top + renderObject.size.height / 2 - centerY).abs();
      if (distance < nearestDistance) {
        nearest = hunk.anchor;
        nearestDistance = distance;
      }
    }
    if (nearest != null) _controller.syncAnchorFromScroll(nearest);
  }

  void _stepFile(int delta) {
    final state = _controller.state;
    if (state.files.isEmpty) return;
    final index = state.files.indexWhere(
      (file) => file.path == state.selectedFile?.path,
    );
    final next = (index + delta).clamp(0, state.files.length - 1);
    final file = state.files[next];
    if (file.path != state.selectedFile?.path) {
      unawaited(_controller.selectFile(file));
    }
  }

  void _handleFileListFocusChanged() {
    if (!_fileListFocus.hasFocus) return;
    switch (_controller.state.view) {
      case FullDiffView.diff:
        _lastDiffHistoryNavigationPane = _FullDiffNavigationPane.files;
      case FullDiffView.history:
        if (_historyListFocus.context?.mounted ?? false) {
          _lastDiffHistoryNavigationPane = _FullDiffNavigationPane.files;
        }
      case FullDiffView.blame:
        if ((_controller.state.blame.data?.lines.isNotEmpty ?? false) &&
            (_blameListFocus.context?.mounted ?? false)) {
          _lastBlameNavigationPane = _FullDiffNavigationPane.files;
        }
    }
  }

  void _handleHistoryListFocusChanged() {
    if (_historyListFocus.hasFocus &&
        (_fileListFocus.context?.mounted ?? false)) {
      _lastDiffHistoryNavigationPane = _FullDiffNavigationPane.history;
    }
  }

  void _handleBlameListFocusChanged() {
    if (_blameListFocus.hasFocus &&
        (_fileListFocus.context?.mounted ?? false)) {
      _lastBlameNavigationPane = _FullDiffNavigationPane.blame;
    }
  }

  FocusNode? _navigationTarget({
    required _FullDiffNavigationPane remembered,
    required _FullDiffNavigationPane detailPane,
    required FocusNode detailFocus,
    required bool detailConnected,
    required bool filesConnected,
  }) {
    if (remembered == detailPane && detailConnected) return detailFocus;
    if (filesConnected) return _fileListFocus;
    return detailConnected ? detailFocus : null;
  }

  void _restoreNavigationFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller.state.focusMode) return;
      final historyConnected =
          _controller.state.view == FullDiffView.history &&
          (_historyListFocus.context?.mounted ?? false);
      final blameConnected =
          _controller.state.view == FullDiffView.blame &&
          (_controller.state.blame.data?.lines.isNotEmpty ?? false) &&
          (_blameListFocus.context?.mounted ?? false);
      final filesConnected = _fileListFocus.context?.mounted ?? false;
      final target = switch (_controller.state.view) {
        FullDiffView.history => _navigationTarget(
          remembered: _lastDiffHistoryNavigationPane,
          detailPane: _FullDiffNavigationPane.history,
          detailFocus: _historyListFocus,
          detailConnected: historyConnected,
          filesConnected: filesConnected,
        ),
        FullDiffView.blame => _navigationTarget(
          remembered: _lastBlameNavigationPane,
          detailPane: _FullDiffNavigationPane.blame,
          detailFocus: _blameListFocus,
          detailConnected: blameConnected,
          filesConnected: filesConnected,
        ),
        FullDiffView.diff => filesConnected ? _fileListFocus : null,
      };
      target?.requestFocus();
    });
  }

  void _observeResponsiveWidth(double width) {
    if (_lastResponsiveWidth == null) {
      _lastResponsiveWidth = width;
      return;
    }
    if (_lastResponsiveWidth == width) return;
    _lastResponsiveWidth = width;
    _restoreNavigationFocus();
  }

  void _selectPrimaryView(FullDiffView view) {
    _controller.setPrimaryView(view);
    if (_controller.state.view == FullDiffView.diff) {
      _lastDiffHistoryNavigationPane = _FullDiffNavigationPane.files;
    }
    _restoreNavigationFocus();
  }

  void _selectLayout(DiffLayout layout) {
    _controller.setLayout(layout);
    _restoreNavigationFocus();
  }

  void _selectHistory(bool selected) {
    _controller.setHistorySelected(selected);
    if (!selected) {
      _lastDiffHistoryNavigationPane = _FullDiffNavigationPane.files;
    }
    _restoreNavigationFocus();
  }

  KeyEventResult _handleFileListKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _stepFile(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _stepFile(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        _controller.state.view == FullDiffView.history) {
      final entries = _controller.state.history.data;
      if (_controller.state.selectedHistoryEntry == null &&
          entries != null &&
          entries.isNotEmpty) {
        unawaited(_controller.selectHistoryEntry(entries.first));
      }
      _historyListFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        _controller.state.view == FullDiffView.blame) {
      if (_controller.state.blame.data?.lines.isNotEmpty ?? false) {
        _blameListFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _returnToTimeline() => Navigator.of(context).maybePop();

  bool _canOpenEditor(FullDiffSessionState state) {
    final file = state.selectedFile;
    return !_openingEditor &&
        state.selectedCommit.isWorkingTree &&
        file != null &&
        !file.status.startsWith('D') &&
        state.file.data != null;
  }

  Future<void> _openEditor() async {
    final state = _controller.state;
    final file = state.selectedFile;
    if (file == null || !_canOpenEditor(state)) return;
    final request = ++_editorRequestSerial;
    setState(() {
      _openingEditor = true;
      _editorError = null;
    });
    String? errorMessage;
    try {
      await _editorService.open(
        relativePath: file.path,
        line: _editorLine(state),
      );
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      if (mounted && request == _editorRequestSerial) {
        setState(() {
          _openingEditor = false;
          _editorError = errorMessage;
        });
      }
    }
  }

  int? _editorLine(FullDiffSessionState state) {
    final anchor = state.activeAnchor;
    if (anchor == null) return null;
    if (anchor.newLine != null) return anchor.newLine;
    final hunks = state.patch.data?.hunks;
    if (hunks == null ||
        anchor.hunkIndex < 0 ||
        anchor.hunkIndex >= hunks.length) {
      return null;
    }
    return math.max(1, hunks[anchor.hunkIndex].newStart);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final state = _controller.state;
      return Scaffold(
        backgroundColor: fullDiffCanvas,
        body: Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.escape):
                _ReturnToTimelineIntent(),
            const SingleActivator(
              LogicalKeyboardKey.keyF,
              meta: true,
              shift: true,
              includeRepeats: false,
            ): _ToggleFocusModeIntent(),
            const SingleActivator(
              LogicalKeyboardKey.digit1,
              meta: true,
              includeRepeats: false,
            ): const _SelectViewIntent(
              FullDiffView.diff,
            ),
            const SingleActivator(
              LogicalKeyboardKey.digit2,
              meta: true,
              includeRepeats: false,
            ): const _SelectViewIntent(
              FullDiffView.blame,
            ),
            const SingleActivator(
              LogicalKeyboardKey.digit3,
              meta: true,
              includeRepeats: false,
            ): const _SelectViewIntent(
              FullDiffView.history,
            ),
            const SingleActivator(
              LogicalKeyboardKey.keyU,
              meta: true,
              includeRepeats: false,
            ): _ToggleLayoutIntent(),
            const SingleActivator(
              LogicalKeyboardKey.keyH,
              meta: true,
              shift: true,
              includeRepeats: false,
            ): _ToggleScopeIntent(),
            const SingleActivator(
              LogicalKeyboardKey.space,
              meta: true,
              shift: true,
              includeRepeats: false,
            ): _ToggleWhitespaceIntent(),
            const SingleActivator(
              LogicalKeyboardKey.keyL,
              meta: true,
              shift: true,
              includeRepeats: false,
            ): _ToggleWrapIntent(),
            const SingleActivator(
              LogicalKeyboardKey.keyA,
              meta: true,
              shift: true,
              includeRepeats: false,
            ): _OpenAlgorithmChooserIntent(),
            const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
                _StepHunkIntent(-1),
            const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                _StepHunkIntent(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
                _StepFileIntent(-1),
            const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
                _StepFileIntent(1),
            if (state.view != FullDiffView.history)
              const SingleActivator(LogicalKeyboardKey.arrowUp):
                  _StepPrimaryFileIntent(-1),
            if (state.view != FullDiffView.history)
              const SingleActivator(LogicalKeyboardKey.arrowDown):
                  _StepPrimaryFileIntent(1),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _ReturnToTimelineIntent: CallbackAction<_ReturnToTimelineIntent>(
                onInvoke: (_) {
                  if (Tooltip.dismissAllToolTips()) return null;
                  _returnToTimeline();
                  return null;
                },
              ),
              _ToggleFocusModeIntent: CallbackAction<_ToggleFocusModeIntent>(
                onInvoke: (_) {
                  _controller.setFocusMode(!_controller.state.focusMode);
                  return null;
                },
              ),
              _SelectViewIntent: CallbackAction<_SelectViewIntent>(
                onInvoke: (intent) {
                  if (intent.view == FullDiffView.history) {
                    _selectHistory(!_controller.state.historySelected);
                  } else {
                    _selectPrimaryView(intent.view);
                  }
                  return null;
                },
              ),
              _ToggleLayoutIntent: CallbackAction<_ToggleLayoutIntent>(
                onInvoke: (_) {
                  _selectLayout(
                    _controller.state.layout == DiffLayout.unified
                        ? DiffLayout.sideBySide
                        : DiffLayout.unified,
                  );
                  return null;
                },
              ),
              _ToggleScopeIntent: CallbackAction<_ToggleScopeIntent>(
                onInvoke: (_) {
                  if (_controller.state.patch.loading) return null;
                  unawaited(
                    _controller
                        .setScope(
                          _controller.state.requestedScope == DiffScope.hunks
                              ? DiffScope.fullFile
                              : DiffScope.hunks,
                        )
                        .catchError((_) {}),
                  );
                  _restoreNavigationFocus();
                  return null;
                },
              ),
              _ToggleWhitespaceIntent: CallbackAction<_ToggleWhitespaceIntent>(
                onInvoke: (_) {
                  if (_controller.state.patch.loading) return null;
                  unawaited(
                    _controller
                        .setIgnoreWhitespace(
                          !_controller.state.requestedIgnoreWhitespace,
                        )
                        .catchError((_) {}),
                  );
                  return null;
                },
              ),
              _ToggleWrapIntent: CallbackAction<_ToggleWrapIntent>(
                onInvoke: (_) {
                  _controller.setWrapLines(!_controller.state.wrapLines);
                  return null;
                },
              ),
              _OpenAlgorithmChooserIntent:
                  CallbackAction<_OpenAlgorithmChooserIntent>(
                    onInvoke: (_) {
                      _algorithmChooserKey.currentState?.show();
                      return null;
                    },
                  ),
              _StepHunkIntent: CallbackAction<_StepHunkIntent>(
                onInvoke: (intent) {
                  _controller.stepAnchor(intent.delta);
                  return null;
                },
              ),
              _StepFileIntent: CallbackAction<_StepFileIntent>(
                onInvoke: (intent) {
                  _stepFile(intent.delta);
                  return null;
                },
              ),
              _StepPrimaryFileIntent: CallbackAction<_StepPrimaryFileIntent>(
                onInvoke: (intent) {
                  if (_controller.state.view != FullDiffView.history) {
                    _stepFile(intent.delta);
                  }
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              onKeyEvent: _handlePageScrollKeyEvent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(fullDiffOuterRadius),
                child: ColoredBox(
                  color: fullDiffHeader,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlobalFileBar(
                        file: state.selectedFile,
                        path: state.selectedFile?.path,
                        view: state.view,
                        encodingLabel: state.encodingLabel,
                        canOpenEditor: _canOpenEditor(state),
                        focusMode: state.focusMode,
                        showShortcutHints: _commandHeld,
                        editorError: _editorError,
                        onBack: _returnToTimeline,
                        onOpenEditor: _openEditor,
                        onViewSelected: _selectPrimaryView,
                        onFocusModeChanged: _controller.setFocusMode,
                      ),
                      GlobalDiffToolbar(
                        algorithmChooserKey: _algorithmChooserKey,
                        algorithmEnabled:
                            state.requestedAlgorithm == state.appliedAlgorithm,
                        view: state.view,
                        layout: state.layout,
                        hunkEnabled: state.requestedScope == DiffScope.hunks,
                        historySelected: state.historySelected,
                        activeIndex: state.activeAnchor?.hunkIndex ?? 0,
                        anchorCount: state.patch.data?.hunks.length ?? 0,
                        algorithm: state.appliedAlgorithm,
                        ignoreWhitespace: state.requestedIgnoreWhitespace,
                        wrapLines: state.wrapLines,
                        loadingPatch: state.patch.loading,
                        showShortcutHints: _commandHeld,
                        onLayoutSelected: _selectLayout,
                        onHunkChanged: (enabled) {
                          unawaited(
                            _controller
                                .setScope(
                                  enabled
                                      ? DiffScope.hunks
                                      : DiffScope.fullFile,
                                )
                                .catchError((_) {}),
                          );
                          _restoreNavigationFocus();
                        },
                        onHistoryChanged: _selectHistory,
                        onPrevious: () => _controller.stepAnchor(-1),
                        onNext: () => _controller.stepAnchor(1),
                        onAlgorithmSelected: (algorithm) {
                          unawaited(
                            _controller
                                .selectAlgorithm(algorithm)
                                .catchError((_) {}),
                          );
                        },
                        onIgnoreWhitespaceChanged: (value) {
                          unawaited(
                            _controller
                                .setIgnoreWhitespace(value)
                                .catchError((_) {}),
                          );
                        },
                        onWrapLinesChanged: _controller.setWrapLines,
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            _observeResponsiveWidth(constraints.maxWidth);
                            final viewportWidth = MediaQuery.sizeOf(
                              context,
                            ).width;
                            final showFiles =
                                !state.focusMode &&
                                viewportWidth > 480 &&
                                (state.view != FullDiffView.history ||
                                    constraints.maxWidth >=
                                        FullDiffColumnWidths.minFiles +
                                            FullDiffColumnWidths.minHistory +
                                            320);
                            return _ResponsiveDiffBody(
                              showFiles: showFiles,
                              filesWidth: _filesWidth,
                              minimumContentWidth:
                                  state.view == FullDiffView.history
                                  ? FullDiffColumnWidths.minHistory + 320
                                  : 320,
                              commitFiles: _commitFiles(state),
                              content: _content(state, viewportWidth),
                              onFilesResized: _resizeFiles,
                              onResizeEnd: _saveColumnWidths,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _commitFiles(FullDiffSessionState state) {
    final commit = state.selectedCommit;
    return ColoredBox(
      color: fullDiffCanvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (commit.parents.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: DropdownButton<String>(
                key: const Key('merge-parent-chooser'),
                isExpanded: true,
                value: state.parent,
                items: [
                  for (var index = 0; index < commit.parents.length; index++)
                    DropdownMenuItem(
                      value: commit.parents[index],
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'Parent ${index + 1} · '),
                            TextSpan(
                              text: _shortSha(commit.parents[index]),
                              style: technicalTextStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                onChanged: (parent) {
                  if (parent != null && parent != state.parent) {
                    unawaited(_controller.selectParent(parent));
                  }
                },
              ),
            ),
          _sectionHeader(
            LayoutBuilder(
              builder: (context, constraints) {
                final summary =
                    '${state.files.length} files · '
                    '+${state.files.fold<int>(0, (sum, file) => sum + (file.additions ?? 0))} '
                    '−${state.files.fold<int>(0, (sum, file) => sum + (file.deletions ?? 0))}';
                final narrow = constraints.maxWidth <= 140;
                return Row(
                  children: [
                    if (narrow)
                      const SizedBox(
                        width: 28,
                        child: Text('변경 파일', maxLines: 2),
                      )
                    else
                      const Expanded(
                        child: Text(
                          '변경 파일',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        summary,
                        maxLines: 2,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: technicalTextStyle.copyWith(
                          color: fullDiffMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: Focus(
              key: const Key('changed-files-focus'),
              focusNode: _fileListFocus,
              onKeyEvent: _handleFileListKey,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SelectionArea(
                      child: ListView.builder(
                        key: const Key('changed-files-list'),
                        itemCount: state.files.length,
                        itemBuilder: (context, index) {
                          final file = state.files[index];
                          final selected =
                              file.path == state.selectedFile?.path;
                          return Semantics(
                            selected: selected,
                            button: true,
                            child: InkWell(
                              onTap: () {
                                _fileListFocus.requestFocus();
                                if (!selected) {
                                  unawaited(_controller.selectFile(file));
                                }
                              },
                              child: ListenableBuilder(
                                listenable: _historyListFocus,
                                builder: (context, _) => FullDiffSelectableRowSurface(
                                  key: selected
                                      ? Key('selected-file-${file.path}')
                                      : null,
                                  selected: selected,
                                  focused:
                                      selected &&
                                      (state.view != FullDiffView.history ||
                                          !_historyListFocus.hasFocus),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 9,
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          child: Text(
                                            _statusLetter(file.status),
                                            style: const TextStyle(fontSize: 9),
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                file.path,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontFamily:
                                                      technicalFontFamily,
                                                  fontFamilyFallback:
                                                      technicalFontFallback,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '+${file.additions ?? '—'} '
                                                '−${file.deletions ?? '—'} · '
                                                '${formatByteSize(file.sizeBytes)}',
                                                style: technicalTextStyle
                                                    .copyWith(
                                                      color: fullDiffMuted,
                                                      fontSize: 12,
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
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (state.filesResource.loading)
                    const Center(
                      child: SizedBox.square(
                        key: Key('diff-pending-files'),
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (!state.filesResource.loading &&
                      state.filesResource.error != null)
                    Center(
                      key: const Key('files-error'),
                      child: Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                state.filesResource.error.toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: fullDiffDeletedMark,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                key: const Key('files-retry'),
                                onPressed: () =>
                                    unawaited(_controller.retryFiles()),
                                child: const Text('다시 시도'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (!state.filesResource.loading &&
                      state.filesResource.error == null &&
                      state.filesResource.data?.isEmpty == true)
                    const Center(
                      key: Key('files-empty'),
                      child: Text(
                        '변경된 파일이 없습니다',
                        style: TextStyle(color: fullDiffMuted, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(FullDiffSessionState state, double viewportWidth) =>
      ColoredBox(
        color: fullDiffCanvas,
        child: Row(
          children: [
            Expanded(
              child: KeyedSubtree(
                key: _contentViewportKey,
                child: PrimaryScrollController(
                  controller: _contentScroll,
                  child: KeyedSubtree(
                    key: const Key('content-scrollable'),
                    child: _contentFor(state, viewportWidth),
                  ),
                ),
              ),
            ),
            if (state.view != FullDiffView.history)
              SizedBox(
                width: fullDiffMinimapWidth,
                child: FullDiffMinimap(
                  document: state.patch.data ?? DiffDocument.empty,
                  activeAnchor: state.activeAnchor,
                  sourceLineCount: _minimapSourceLineCount(state),
                  sourceSide: _minimapSourceSide(state),
                  view: state.view,
                  scrollController: _contentScroll,
                  onAnchorSelected: _controller.selectAnchor,
                  onScrollFractionChanged: _scrollContentToFraction,
                ),
              ),
          ],
        ),
      );

  FileDocumentSide _minimapSourceSide(FullDiffSessionState state) {
    final loadedSide = state.file.data?.side;
    if (loadedSide != null) return loadedSide;
    return state.selectedFile?.status.startsWith('D') ?? false
        ? FileDocumentSide.old
        : FileDocumentSide.result;
  }

  int _minimapSourceLineCount(FullDiffSessionState state) {
    final loadedLineCount = state.file.data?.lines.length ?? 0;
    if (loadedLineCount > 0) return loadedLineCount;
    final patch = state.patch.data;
    return patch == null
        ? 0
        : sourceLineCountForSide(patch, _minimapSourceSide(state));
  }

  Widget _contentFor(FullDiffSessionState state, double viewportWidth) =>
      switch (state.view) {
        FullDiffView.diff => _diffContent(state, viewportWidth),
        FullDiffView.blame => _blameContent(state),
        FullDiffView.history => _historyContent(state),
      };

  Widget _diffContent(FullDiffSessionState state, double viewportWidth) {
    final patch = state.patch.data;
    final selectedFile = state.selectedFile;
    if (selectedFile != null && patch == null && state.patch.error != null) {
      return KeyedSubtree(
        key: const Key('diff-error-without-document'),
        child: _unavailablePanel(
          state,
          reason: FullDiffUnavailableReason.gitError,
          path: state.file.data?.path ?? selectedFile.path,
          error: state.patch.error,
          onRetry: () => unawaited(_controller.retryPatch()),
        ),
      );
    }
    if (patch == null || selectedFile == null) {
      return _resourceStatus(
        state.patch,
        state.file.loading ? '파일을 읽는 중입니다' : 'Diff를 읽는 중입니다',
        loadingKey: const Key('diff-pending-first-diff'),
        errorKey: const Key('diff-error-without-document'),
      );
    }
    final fileDocument = state.file.data;
    if (fileDocument == null) {
      if (state.file.error != null) {
        return _unavailablePanel(
          state,
          reason: FullDiffUnavailableReason.gitError,
          path: selectedFile.status.startsWith('D')
              ? selectedFile.oldPath ?? selectedFile.path
              : selectedFile.path,
          error: state.file.error,
          onRetry: () => unawaited(_controller.retryFile()),
        );
      }
      return _resourceStatus(state.file, '파일을 읽는 중입니다');
    }
    final unavailableReason = _unavailableReasonFor(fileDocument);
    if (unavailableReason != null) {
      return _unavailablePanel(
        state,
        reason: unavailableReason,
        path: fileDocument.path,
      );
    }
    if (patch.hunks.isEmpty) {
      return _withRefreshError(
        _unavailablePanel(
          state,
          reason: FullDiffUnavailableReason.noChanges,
          path: fileDocument.path,
        ),
        state.patch.error,
      );
    }
    final presentation = switch (state.layout) {
      DiffLayout.unified => UnifiedPresentationView(
        document: patch,
        activeAnchor: state.activeAnchor,
        path: selectedFile.path,
        wrapLines: state.wrapLines,
        highlighter: _highlighter,
        anchorKeys: _anchorKeys,
        richRenderingEnabled: state.richRenderingEnabled,
        onAnchorProbeAttached: _attachAnchorProbe,
        onAnchorProbeDetached: _detachAnchorProbe,
        controller: _contentScroll,
        scrollTarget: state.fullFileScrollTarget,
        scrollTargetKey: _fullFileScrollTargetKey,
      ),
      DiffLayout.sideBySide => SideBySidePresentationView(
        document: patch,
        activeAnchor: state.activeAnchor,
        oldPath: selectedFile.oldPath ?? selectedFile.path,
        newPath: selectedFile.path,
        wrapLines: state.wrapLines,
        showOldSide: viewportWidth > 480,
        highlighter: _highlighter,
        anchorKeys: _anchorKeys,
        richRenderingEnabled: state.richRenderingEnabled,
        onAnchorProbeAttached: _attachAnchorProbe,
        onAnchorProbeDetached: _detachAnchorProbe,
        controller: _contentScroll,
        scrollTarget: state.fullFileScrollTarget,
        scrollTargetKey: _fullFileScrollTargetKey,
        splitRatio: _sideBySideRatio,
        onSplitRatioChanged: _resizeSideBySide,
        onSplitRatioChangeEnd: _saveColumnWidths,
      ),
    };
    return _withRefreshError(presentation, state.patch.error);
  }

  Widget _withRefreshError(Widget presentation, Object? error) {
    if (error == null) return presentation;
    return Stack(
      fit: StackFit.expand,
      children: [
        presentation,
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            key: const Key('diff-refresh-error'),
            color: fullDiffCanvas.withValues(alpha: 0.92),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              error.toString(),
              style: const TextStyle(color: fullDiffDeletedMark, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  FullDiffUnavailableReason? _unavailableReasonFor(
    FileDocument file,
  ) => switch (file.kind) {
    FileContentKind.utf8 => null,
    FileContentKind.binary => FullDiffUnavailableReason.binary,
    FileContentKind.unsupportedEncoding =>
      FullDiffUnavailableReason.unsupportedEncoding,
    FileContentKind.tooLarge => switch (file.limitReason) {
      FileContentLimitReason.byteLimit => FullDiffUnavailableReason.byteLimit,
      FileContentLimitReason.lineLimit => FullDiffUnavailableReason.lineLimit,
      null => null,
    },
  };

  Widget _unavailablePanel(
    FullDiffSessionState state, {
    required FullDiffUnavailableReason reason,
    required String path,
    Object? error,
    VoidCallback? onRetry,
  }) {
    final file = state.selectedFile;
    if (file == null) {
      return _resourceStatus(state.patch, 'Diff를 읽는 중입니다');
    }
    return FullDiffUnavailablePanel(
      file: file,
      path: path,
      reason: reason,
      algorithm: state.requestedAlgorithm,
      ignoreWhitespace: state.requestedIgnoreWhitespace,
      error: error,
      onRetry: onRetry,
    );
  }

  Widget _blameContent(FullDiffSessionState state) {
    final blame = state.blame.data;
    if (blame == null) {
      return _resourceStatus(state.blame, 'Blame을 읽는 중입니다');
    }
    return FullBlameView(
      key: ValueKey((
        blame.file.revision,
        blame.file.path,
        blame.file.side,
        blame.file.fingerprint,
      )),
      document: blame,
      hunks: state.patch.data?.hunks ?? const [],
      activeAnchor: state.activeAnchor,
      wrapLines: state.wrapLines,
      highlighter: _highlighter,
      anchorKeys: _anchorKeys,
      onAnchorProbeAttached: _attachAnchorProbe,
      onAnchorProbeDetached: _detachAnchorProbe,
      controller: _contentScroll,
      avatarService: widget.avatarService,
      showRemoteAvatars: widget.showRemoteAvatars,
      focusNode: _blameListFocus,
      onMoveToFiles: _fileListFocus.requestFocus,
      loadCommitMessage: _loadCommitMessage,
    );
  }

  Widget _historyContent(FullDiffSessionState state) {
    final history = state.history.data;
    if (history == null) {
      return _resourceStatus(state.history, 'History를 읽는 중입니다');
    }
    return FullHistoryWorkspace(
      historyWidth: _historyWidth,
      onHistoryResized: _resizeHistory,
      onHistoryResizeEnd: _saveColumnWidths,
      showHistory: !state.focusMode,
      history: FullHistoryView(
        entries: history,
        selected: state.selectedHistoryEntry,
        onSelected: (entry) {
          _historyListFocus.requestFocus();
          unawaited(_controller.selectHistoryEntry(entry));
        },
        controller: _historyScroll,
        focusNode: _historyListFocus,
        onMoveToFiles: _fileListFocus.requestFocus,
        loadCommitMessage: _loadCommitMessage,
      ),
      detail: LayoutBuilder(
        builder: (context, constraints) =>
            _historyDetailContent(state, constraints.maxWidth),
      ),
    );
  }

  Widget _historyDetailContent(
    FullDiffSessionState state,
    double viewportWidth,
  ) {
    if (state.filesResource.loading) {
      return _resourceStatus(
        state.filesResource,
        '파일을 읽는 중입니다',
        loadingKey: const Key('history-detail-loading'),
      );
    }
    final entry = state.selectedHistoryEntry;
    final error = state.filesResource.error;
    if (entry != null && state.selectedFile == null && error != null) {
      return FullDiffUnavailablePanel(
        file: GitFileChange(
          path: entry.path,
          oldPath: entry.oldPath,
          status: entry.status,
          additions: null,
          deletions: null,
        ),
        path: entry.path,
        reason: FullDiffUnavailableReason.gitError,
        algorithm: state.requestedAlgorithm,
        ignoreWhitespace: state.requestedIgnoreWhitespace,
        error: error,
        onRetry: () => unawaited(_controller.retryFiles()),
      );
    }
    return _diffContent(state, viewportWidth);
  }

  Widget _resourceStatus<T>(
    AsyncResource<T> resource,
    String loadingLabel, {
    Key? loadingKey,
    Key? errorKey,
  }) => Center(
    key: resource.error != null ? errorKey : loadingKey,
    child: Text(
      resource.error?.toString() ??
          (resource.loading ? loadingLabel : '표시할 데이터가 없습니다'),
      style: const TextStyle(color: fullDiffMuted, fontSize: 10),
    ),
  );

  void _scrollContentToFraction(double fraction) {
    if (!_contentScroll.clientsReady) return;
    final position = _contentScroll.position;
    position.jumpTo(
      (position.maxScrollExtent * fraction).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _resizeFiles(double width) {
    setState(() {
      _filesWidth = width.clamp(
        FullDiffColumnWidths.minFiles,
        FullDiffColumnWidths.maxFiles,
      );
    });
  }

  void _resizeHistory(double width) {
    setState(() {
      _historyWidth = width.clamp(
        FullDiffColumnWidths.minHistory,
        FullDiffColumnWidths.maxHistory,
      );
    });
  }

  void _resizeSideBySide(double ratio) {
    setState(() {
      _sideBySideRatio = ratio.clamp(
        FullDiffColumnWidths.minSideBySideRatio,
        FullDiffColumnWidths.maxSideBySideRatio,
      );
    });
  }

  void _saveColumnWidths() => widget.onColumnWidthsChanged?.call(
    FullDiffColumnWidths(
      history: _historyWidth,
      files: _filesWidth,
      sideBySideRatio: _sideBySideRatio,
    ),
  );

  Widget _sectionHeader(Widget child) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.centerLeft,
    decoration: const BoxDecoration(
      color: fullDiffHeader,
      border: Border(bottom: BorderSide(color: fullDiffDivider)),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      child: child,
    ),
  );
}

class _ResponsiveDiffBody extends StatelessWidget {
  const _ResponsiveDiffBody({
    required this.showFiles,
    required this.filesWidth,
    required this.minimumContentWidth,
    required this.commitFiles,
    required this.content,
    required this.onFilesResized,
    required this.onResizeEnd,
  });

  final bool showFiles;
  final double filesWidth;
  final double minimumContentWidth;
  final Widget commitFiles;
  final Widget content;
  final ValueChanged<double> onFilesResized;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const minFiles = FullDiffColumnWidths.minFiles;
      final maxFiles = math
          .max(minFiles, constraints.maxWidth - minimumContentWidth)
          .clamp(minFiles, FullDiffColumnWidths.maxFiles)
          .toDouble();
      final effectiveFiles = filesWidth.clamp(minFiles, maxFiles);
      return Row(
        children: [
          if (showFiles)
            KeyedSubtree(
              key: const Key('details-files-column'),
              child: FullDiffResizablePane(
                width: effectiveFiles,
                minWidth: minFiles,
                maxWidth: maxFiles,
                label: 'Files pane width',
                resizerKey: const Key('details-files-column-resizer'),
                dividerKey: const Key('files-detail-divider'),
                onChanged: onFilesResized,
                onChangeEnd: onResizeEnd,
                child: KeyedSubtree(
                  key: const Key('commit-files-pane'),
                  child: commitFiles,
                ),
              ),
            ),
          Expanded(key: const Key('diff-column'), child: content),
        ],
      );
    },
  );
}

String _statusLetter(String status) =>
    status.characters.isEmpty ? '' : status.characters.first;

String _shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);
