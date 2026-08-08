import 'dart:async';
import 'dart:convert';
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
import 'full_diff_side_by_side_view.dart';
import 'full_diff_syntax.dart';
import 'full_diff_theme.dart';
import 'full_diff_unified_view.dart';
import 'full_diff_unavailable_panel.dart';
import 'git.dart';
import 'monaco_editor_screen.dart';
import 'package:yogit/vim_navigation.dart';

import 'page_scroll_shortcuts.dart';
import 'settings.dart';
import 'shortcut_modifier.dart';
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

@visibleForTesting
class FullDiffScrollController extends ScrollController {
  FullDiffScrollController({super.onAttach});

  @visibleForTesting
  bool debugClientsAvailable = true;

  bool get clientsReady => debugClientsAvailable && hasClients;
}

/// The full-diff machinery — both option rows, the commit line, the
/// diff/blame content, the minimap and the keyboard — with no route, Scaffold,
/// file list or history list of its own, so any pane can hold it.
///
/// The session belongs to whoever builds this: [controller] is never created or
/// disposed here, only observed. Whoever embeds it draws the navigation —
/// the file list and the History pane both live outside.
class FullDiffWorkspace extends StatefulWidget {
  const FullDiffWorkspace({
    required this.controller,
    required this.onBack,
    this.columnWidths = const FullDiffColumnWidths(),
    this.onColumnWidthsChanged,
    this.onPreferencesChanged,
    this.editorService,
    this.editorForTesting,
    this.documentLoaderForTesting,
    this.avatarService,
    this.commitMessageCache,
    this.showRemoteAvatars = true,
    this.focusNode,
    this.onMovePane,
    super.key,
  });

  final FullDiffSessionController controller;
  final VoidCallback onBack;
  final FullDiffColumnWidths columnWidths;
  final ValueChanged<FullDiffColumnWidths>? onColumnWidthsChanged;
  final ValueChanged<FullDiffPreferences>? onPreferencesChanged;
  final ExternalEditorService? editorService;

  @visibleForTesting
  final Widget? editorForTesting;

  @visibleForTesting
  final Future<WorkingTreeTextDocument> Function(String relativePath)?
  documentLoaderForTesting;
  final AvatarService? avatarService;
  final FullDiffCommitMessageCache? commitMessageCache;
  final bool showRemoteAvatars;

  /// Lets the embedder hand the keyboard to the diff itself.
  final FocusNode? focusNode;

  /// ← and → out of the diff, as the embedder orders its panes.
  final ValueChanged<int>? onMovePane;

  @override
  State<FullDiffWorkspace> createState() => _FullDiffWorkspaceState();
}

class _FullDiffWorkspaceState extends State<FullDiffWorkspace> {
  late final FullDiffScrollController _contentScroll;
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
  late FullDiffSessionState _observedState;
  late FullDiffPreferences _lastReportedPreferences;
  late double _sideBySideRatio;
  double? _lastResponsiveWidth;

  bool _effectScheduled = false;
  bool _scrollSyncScheduled = false;
  bool _programmaticAnchorScroll = false;
  bool _pendingScrollToTop = false;
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
        repositoryRoot: _controller.repository.root,
        sha: sha,
        loader: () => _controller.repository.loadCommitMessage(sha),
      );

  @override
  void initState() {
    super.initState();
    _contentScroll = FullDiffScrollController(
      onAttach: (_) => _handleContentScrollAttached(),
    );
    _sideBySideRatio = widget.columnWidths.sideBySideRatio;
    _editorService =
        widget.editorService ??
        ExternalEditorService(
          repositoryRoot: widget.controller.repository.root,
        );
    _attachController(widget.controller);
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    _contentScroll.addListener(_handleContentScrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreNavigationFocus();
    });
    _queueAttachedAnchorScroll();
  }

  void _attachController(FullDiffSessionController controller) {
    _controller = controller;
    _observedState = controller.state;
    _lastReportedPreferences = _observedState.preferences;
    _reconcileAnchorKeys(_observedState.patch.data);
    controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant FullDiffWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.columnWidths != oldWidget.columnWidths) {
      _sideBySideRatio = widget.columnWidths.sideBySideRatio;
    }
    final controllerChanged = !identical(
      widget.controller,
      oldWidget.controller,
    );
    final editorContextChanged =
        widget.editorService != oldWidget.editorService ||
        widget.controller.repository.root !=
            oldWidget.controller.repository.root;
    if (editorContextChanged) {
      _editorService =
          widget.editorService ??
          ExternalEditorService(
            repositoryRoot: widget.controller.repository.root,
          );
    }
    if (editorContextChanged || controllerChanged) {
      _invalidateEditorRequest();
    }
    if (!controllerChanged) return;

    oldWidget.controller.removeListener(_handleControllerChanged);
    _attachController(widget.controller);
    _pendingScrollToTop = true;
    _pendingAnchorId = null;
    _clearPendingFullFileScroll();
    _queueAttachedAnchorScroll();
    if (_pendingAnchorId == null && _pendingFullFileScrollTarget == null) {
      _scheduleScrollEffect();
    }
  }

  @override
  void dispose() {
    _editorRequestSerial++;
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    _controller.removeListener(_handleControllerChanged);
    _contentScroll
      ..removeListener(_handleContentScrolled)
      ..dispose();
    _blameListFocus.dispose();
    super.dispose();
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!isShortcutModifierKey(event.logicalKey)) return false;
    final held = shortcutModifierHeld;
    if (_commandHeld != held && mounted) {
      setState(() => _commandHeld = held);
    }
    return false;
  }

  /// The diff's own keys, plus the steps out of it: ← and → hand the keyboard
  /// to whichever pane the embedder put on that side. Consuming them both also
  /// keeps a stray arrow from reaching the list behind the diff.
  KeyEventResult _handleWorkspaceKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        widget.onMovePane != null &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      final key = normalizeNavigationKey(
        event.logicalKey,
        hasModifier:
            HardwareKeyboard.instance.isShiftPressed ||
            HardwareKeyboard.instance.isControlPressed,
      );
      final step = switch (key) {
        LogicalKeyboardKey.arrowLeft => -1,
        LogicalKeyboardKey.arrowRight => 1,
        _ => 0,
      };
      if (step != 0) {
        widget.onMovePane!(step);
        return KeyEventResult.handled;
      }
    }
    return _handlePageScrollKeyEvent(node, event);
  }

  KeyEventResult _handlePageScrollKeyEvent(FocusNode _, KeyEvent event) {
    final intent = pageScrollIntentFor(
      event,
      metaPressed: HardwareKeyboard.instance.isMetaPressed,
      shiftPressed: HardwareKeyboard.instance.isShiftPressed,
    );
    if (intent == null) return KeyEventResult.ignored;
    // At the content's edge the keys travel on, so an embedder can page its own
    // list once the diff has nothing left to give.
    if (!_contentScroll.clientsReady) return KeyEventResult.ignored;
    final position = _contentScroll.position;
    final room = intent.direction > 0
        ? position.extentAfter
        : position.extentBefore;
    if (room <= 0) return KeyEventResult.ignored;
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
    final blameFileBecameReady =
        previous.file.data == null &&
        next.file.data?.kind == FileContentKind.utf8 &&
        next.view == FullDiffView.blame;
    final blameStartedLoading =
        !previous.blame.loading &&
        next.blame.loading &&
        next.view == FullDiffView.blame;
    if (blameStartedLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_controller.state.blame.loading ||
            !_blameListFocus.hasFocus) {
          return;
        }
        _blameListFocus.unfocus();
        scheduleMicrotask(() {
          if (mounted && _controller.state.blame.loading) {
            _blameListFocus.requestFocus();
          }
        });
      });
    }
    if (blameFileBecameReady) {
      _restoreNavigationFocus();
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

  bool _blameDetailConnected(FullDiffSessionState state) =>
      state.view == FullDiffView.blame &&
      state.file.data?.kind == FileContentKind.utf8 &&
      (_blameListFocus.context?.mounted ?? false);

  /// The blame list is the only list the workspace still owns, so it is the
  /// only place the keyboard is handed back to.
  void _restoreNavigationFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller.state.focusMode) return;
      if (_blameDetailConnected(_controller.state)) {
        _blameListFocus.requestFocus();
      }
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
    _restoreNavigationFocus();
  }

  void _selectLayout(DiffLayout layout) {
    _controller.setLayout(layout);
    _restoreNavigationFocus();
  }

  void _selectHistory(bool selected) {
    _controller.setHistorySelected(selected);
    _restoreNavigationFocus();
  }

  bool _canOpenEditor(FullDiffSessionState state) {
    final file = state.selectedFile;
    return !_openingEditor &&
        file != null &&
        (!state.selectedCommit.isWorkingTree || !file.status.startsWith('D')) &&
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
      String? internalError;
      final fileDocument = state.file.data!;
      if (fileDocument.kind != FileContentKind.utf8) {
        internalError = switch (fileDocument.kind) {
          FileContentKind.binary => '바이너리 파일은 내장 에디터에서 열 수 없습니다',
          FileContentKind.unsupportedEncoding => 'UTF-8 파일만 내장 에디터에서 열 수 있습니다',
          FileContentKind.tooLarge => '파일이 너무 커서 내장 에디터에서 열 수 없습니다',
          FileContentKind.utf8 => null,
        };
      }
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          overlay.size.width - 260,
          54,
          16,
          overlay.size.height - 54,
        ),
        items: [
          PopupMenuItem(
            value: 'internal',
            enabled: internalError == null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('내장 에디터'),
                if (internalError != null)
                  Text(
                    internalError,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'external',
            enabled: state.selectedCommit.isWorkingTree,
            child: const Text('외부 에디터'),
          ),
        ],
      );
      if (!mounted || request != _editorRequestSerial || choice == null) return;
      if (choice == 'external') {
        await _editorService.open(
          relativePath: file.path,
          line: _editorLine(state),
        );
        return;
      }
      WorkingTreeTextDocument? document;
      late final String text;
      if (state.selectedCommit.isWorkingTree) {
        document =
            await widget.documentLoaderForTesting?.call(file.path) ??
            await WorkingTreeTextDocument.load(
              repositoryRoot: _controller.repository.root,
              relativePath: file.path,
            );
        text = document.text;
      } else {
        final bytes = fileDocument.bytes;
        final offset =
            bytes.length >= 3 &&
                bytes[0] == 0xEF &&
                bytes[1] == 0xBB &&
                bytes[2] == 0xBF
            ? 3
            : 0;
        text = utf8.decode(bytes.sublist(offset)).replaceAll('\r\n', '\n');
      }
      if (!mounted || request != _editorRequestSerial) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MonacoEditorScreen(
            title: file.path,
            initialText: text,
            language: monacoLanguageForPath(file.path),
            readOnly: !state.selectedCommit.isWorkingTree,
            onSave: document?.save,
            onOpenExternal: state.selectedCommit.isWorkingTree
                ? () async {
                    try {
                      await _editorService.open(
                        relativePath: file.path,
                        line: _editorLine(state),
                      );
                    } catch (error) {
                      if (mounted && request == _editorRequestSerial) {
                        setState(() => _editorError = error.toString());
                      }
                    }
                  }
                : null,
            editorForTesting: widget.editorForTesting,
          ),
        ),
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
      return Shortcuts(
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
          // Plain arrows walk the change the reader is looking at. Files are
          // the preview pane's list now, and ⌘↑/↓ still reaches them.
          const SingleActivator(LogicalKeyboardKey.arrowUp): _StepHunkIntent(
            -1,
          ),
          const SingleActivator(LogicalKeyboardKey.arrowDown): _StepHunkIntent(
            1,
          ),
          const SingleActivator(LogicalKeyboardKey.keyK): _StepHunkIntent(-1),
          const SingleActivator(LogicalKeyboardKey.keyJ): _StepHunkIntent(1),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _ReturnToTimelineIntent: CallbackAction<_ReturnToTimelineIntent>(
              onInvoke: (_) {
                if (Tooltip.dismissAllToolTips()) return null;
                widget.onBack();
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
            key: const Key('diff-focus'),
            autofocus: widget.focusNode == null,
            focusNode: widget.focusNode,
            onKeyEvent: _handleWorkspaceKeyEvent,
            // Square corners: the workspace fills a pane between two others
            // now, and a rounded edge there cuts a notch out of the window.
            child: ClipRect(
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
                      onBack: widget.onBack,
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
                      gitDiffAlgorithmSetting: state.gitDiffAlgorithmSetting,
                      ignoreWhitespace: state.requestedIgnoreWhitespace,
                      wrapLines: state.wrapLines,
                      loadingPatch: state.patch.loading,
                      showShortcutHints: _commandHeld,
                      onLayoutSelected: _selectLayout,
                      onHunkChanged: (enabled) {
                        unawaited(
                          _controller
                              .setScope(
                                enabled ? DiffScope.hunks : DiffScope.fullFile,
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
                    _commitLine(state),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _observeResponsiveWidth(constraints.maxWidth);
                          return _content(
                            state,
                            MediaQuery.sizeOf(context).width,
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
      );
    },
  );

  /// Names the commit whose diff is showing — after a History pick, that is
  /// the picked commit, not the one the timeline sits on.
  Widget _commitLine(FullDiffSessionState state) {
    final commit = state.selectedCommit;
    final parent =
        state.parent ?? (commit.parents.isEmpty ? null : commit.parents.first);
    final compare = commit.isWorkingTree
        ? 'WIP · 작업 트리'
        : '${commit.shortSha} · ${commit.subject}';
    return Container(
      key: const Key('full-diff-commit-line'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: fullDiffHeader,
        border: Border(bottom: BorderSide(color: fullDiffDivider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${parent == null ? '—' : _shortSha(parent)} · '
              '${parent == null ? '빈 트리' : '이전 상태'} ← $compare',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: technicalTextStyle.copyWith(
                color: fullDiffMuted,
                fontSize: 10.5,
              ),
            ),
          ),
          if (commit.parents.length > 1) _parentChooser(state, commit),
        ],
      ),
    );
  }

  Widget _parentChooser(FullDiffSessionState state, GitCommit commit) =>
      DropdownButton<String>(
        key: const Key('merge-parent-chooser'),
        value: state.parent,
        isDense: true,
        underline: const SizedBox.shrink(),
        style: const TextStyle(color: fullDiffMuted, fontSize: 10.5),
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
      );

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
            // Every view here is a diff of one file now that History reads
            // from its own pane, so the map always has something to map.
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
        FullDiffView.history => _historyDetailContent(state, viewportWidth),
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
        // 21px rows, per the approved mockup: the diff sits beside two panes
        // now, so every row it can show is one the reader keeps.
        compactRows: true,
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
        compactRows: true,
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
      algorithm: state.requestedConcreteAlgorithm,
      ignoreWhitespace: state.requestedIgnoreWhitespace,
      error: error,
      onRetry: onRetry,
    );
  }

  Widget _blameContent(FullDiffSessionState state) {
    final blame = state.blame.data;
    final file = blame?.file ?? state.file.data;
    if (file == null ||
        file.kind != FileContentKind.utf8 ||
        (blame == null && !state.blame.loading)) {
      return _resourceStatus(state.blame, 'Blame을 읽는 중입니다');
    }
    final key = ValueKey((
      file.revision,
      file.path,
      file.side,
      file.fingerprint,
    ));
    if (blame == null) {
      return FullBlameView.loading(
        key: key,
        file: file,
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
        loadCommitMessage: _loadCommitMessage,
      );
    }
    return FullBlameView(
      key: key,
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
      loadCommitMessage: _loadCommitMessage,
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
        algorithm: state.requestedConcreteAlgorithm,
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
      history: widget.columnWidths.history,
      files: widget.columnWidths.files,
      sideBySideRatio: _sideBySideRatio,
    ),
  );
}

String _shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);
