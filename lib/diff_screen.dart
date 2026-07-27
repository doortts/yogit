import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'avatars.dart';
import 'external_editor.dart';
import 'full_blame_view.dart';
import 'full_diff_controller.dart';
import 'full_diff_header.dart';
import 'full_diff_minimap.dart';
import 'full_diff_model.dart';
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
    this.editorService,
    this.avatarService,
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
  final ExternalEditorService? editorService;
  final AvatarService? avatarService;
  final bool showRemoteAvatars;

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  final _contentScroll = ScrollController();
  final _historyScroll = ScrollController();
  final _fileListFocus = FocusNode(debugLabel: 'full diff files');
  final _historyListFocus = FocusNode(debugLabel: 'full diff history');
  final _contentViewportKey = GlobalKey();
  final _highlighter = HighlightJsSyntaxHighlighter();
  Map<String, GlobalKey> _anchorKeys = <String, GlobalKey>{};
  final Map<String, Set<BuildContext>> _anchorProbeContexts = {};

  late FullDiffSessionController _controller;
  late ExternalEditorService _editorService;
  late bool _ownsController;
  late FullDiffSessionState _observedState;
  late double _filesWidth;

  bool _effectScheduled = false;
  bool _scrollSyncScheduled = false;
  bool _programmaticAnchorScroll = false;
  bool _pendingScrollToTop = false;
  bool _pendingHistoryScrollToTop = false;
  String? _pendingAnchorId;
  int _pendingAnchorDirection = 0;
  String? _editorError;
  bool _openingEditor = false;
  int _editorRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    _filesWidth = widget.columnWidths.files;
    _editorService =
        widget.editorService ??
        ExternalEditorService(repositoryRoot: widget.repository.root);
    _attachController(_newController());
    _contentScroll.addListener(_handleContentScrolled);
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
    _reconcileAnchorKeys(_observedState.patch.data);
    controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant DiffScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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
            widget.initialIndex != oldWidget.initialIndex ||
            widget.initialPreferences != oldWidget.initialPreferences);
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
    _queueAttachedAnchorScroll();
    if (_pendingAnchorId == null) _scheduleScrollEffect();
    if (_ownsController) unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _editorRequestSerial++;
    _controller.removeListener(_handleControllerChanged);
    _contentScroll
      ..removeListener(_handleContentScrolled)
      ..dispose();
    _historyScroll.dispose();
    _fileListFocus.dispose();
    _historyListFocus.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
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

    if (changedDocument) _reconcileAnchorKeys(next.patch.data);
    if (previous.historyContext != next.historyContext) {
      _pendingHistoryScrollToTop = true;
    }
    if (movedContext) {
      _invalidateEditorRequest();
      _pendingScrollToTop = true;
      _pendingAnchorId = null;
    }
    if (nextAnchor != null &&
        (enteredSourceView ||
            (changedDocument && next.view == FullDiffView.blame))) {
      _pendingAnchorId = nextAnchor.id;
      _pendingAnchorDirection = nextIndex.compareTo(previousIndex);
    }
    if (!_pendingScrollToTop && navigationRequested && nextAnchor != null) {
      _pendingAnchorId = nextAnchor.id;
      _pendingAnchorDirection = nextIndex.compareTo(previousIndex);
    }
    if (_pendingScrollToTop ||
        _pendingHistoryScrollToTop ||
        _pendingAnchorId != null) {
      _scheduleScrollEffect();
    }
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
    final anchor = state.activeAnchor;
    if (state.view == FullDiffView.history ||
        anchor == null ||
        (state.view == FullDiffView.diff && anchor.hunkIndex == 0)) {
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

      if (_pendingScrollToTop && _contentScroll.hasClients) {
        _contentScroll.jumpTo(_contentScroll.position.minScrollExtent);
        _pendingScrollToTop = false;
      }
      if (_pendingHistoryScrollToTop && _historyScroll.hasClients) {
        _historyScroll.jumpTo(_historyScroll.position.minScrollExtent);
        _pendingHistoryScrollToTop = false;
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
        if (anchorRenderObject == null || !_contentScroll.hasClients) {
          _pendingAnchorId = null;
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
      if (!_contentScroll.hasClients) {
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
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape):
                _ReturnToTimelineIntent(),
            SingleActivator(
              LogicalKeyboardKey.arrowUp,
              meta: true,
              shift: true,
            ): PageScrollIntent(
              -1,
            ),
            SingleActivator(
              LogicalKeyboardKey.arrowDown,
              meta: true,
              shift: true,
            ): PageScrollIntent(
              1,
            ),
            SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
                _ToggleFocusModeIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
                _StepHunkIntent(-1),
            SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                _StepHunkIntent(1),
            SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
                _StepFileIntent(-1),
            SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
                _StepFileIntent(1),
            SingleActivator(LogicalKeyboardKey.arrowUp): _StepPrimaryFileIntent(
              -1,
            ),
            SingleActivator(LogicalKeyboardKey.arrowDown):
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
              PageScrollIntent: CallbackAction<PageScrollIntent>(
                onInvoke: (intent) {
                  final animate =
                      !_contentScroll.hasClients ||
                      !_contentScroll.position.isScrollingNotifier.value;
                  applyPageScroll(
                    _contentScroll,
                    direction: intent.direction,
                    animate: animate,
                  );
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
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
                        editorError: _editorError,
                        onBack: _returnToTimeline,
                        onOpenEditor: _openEditor,
                        onViewSelected: _controller.setView,
                        onFocusModeChanged: _controller.setFocusMode,
                      ),
                      GlobalDiffToolbar(
                        view: state.view,
                        layout: state.layout,
                        hunkEnabled: state.requestedScope == DiffScope.hunks,
                        activeIndex: state.activeAnchor?.hunkIndex ?? 0,
                        anchorCount: state.patch.data?.hunks.length ?? 0,
                        algorithm: state.requestedAlgorithm,
                        ignoreWhitespace: state.requestedIgnoreWhitespace,
                        wrapLines: state.wrapLines,
                        loadingPatch: state.patch.loading,
                        onLayoutSelected: _controller.setLayout,
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
                        },
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
                            final viewportWidth = MediaQuery.sizeOf(
                              context,
                            ).width;
                            return _ResponsiveDiffBody(
                              showFiles:
                                  !state.focusMode && viewportWidth > 480,
                              filesWidth: _filesWidth,
                              commitFiles: _commitFiles(state),
                              content: _content(state, viewportWidth),
                              onFilesResized: (delta) =>
                                  _resizeFiles(delta, constraints.maxWidth),
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
                              onTap: selected
                                  ? null
                                  : () =>
                                        unawaited(_controller.selectFile(file)),
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
    );
  }

  Widget _historyContent(FullDiffSessionState state) {
    final history = state.history.data;
    if (history == null) {
      return _resourceStatus(state.history, 'History를 읽는 중입니다');
    }
    return FullHistoryWorkspace(
      history: FullHistoryView(
        entries: history,
        selected: state.selectedHistoryEntry,
        onSelected: (entry) => unawaited(_controller.selectHistoryEntry(entry)),
        controller: _historyScroll,
        focusNode: _historyListFocus,
        onMoveToFiles: _fileListFocus.requestFocus,
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
    if (!_contentScroll.hasClients) return;
    final position = _contentScroll.position;
    position.jumpTo(
      (position.maxScrollExtent * fraction).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _resizeFiles(double delta, double bodyWidth) {
    final max = math.max(FullDiffColumnWidths.minFiles, bodyWidth - 280);
    setState(() {
      _filesWidth = (_filesWidth + delta).clamp(
        FullDiffColumnWidths.minFiles,
        max,
      );
    });
  }

  void _saveColumnWidths() => widget.onColumnWidthsChanged?.call(
    FullDiffColumnWidths(
      commits: widget.columnWidths.commits,
      files: _filesWidth,
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
    required this.commitFiles,
    required this.content,
    required this.onFilesResized,
    required this.onResizeEnd,
  });

  final bool showFiles;
  final double filesWidth;
  final Widget commitFiles;
  final Widget content;
  final ValueChanged<double> onFilesResized;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const minFiles = FullDiffColumnWidths.minFiles;
      const minContent = 280.0;
      final maxFiles = math.max(minFiles, constraints.maxWidth - minContent);
      final effectiveFiles = filesWidth.clamp(minFiles, maxFiles);
      return Row(
        children: [
          if (showFiles)
            SizedBox(
              key: const Key('commit-files-pane'),
              width: effectiveFiles,
              child: KeyedSubtree(
                key: const Key('details-files-column'),
                child: _ResizablePane(
                  resizerKey: const Key('details-files-column-resizer'),
                  onUpdate: onFilesResized,
                  onEnd: onResizeEnd,
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

class _ResizablePane extends StatelessWidget {
  const _ResizablePane({
    required this.resizerKey,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final Key resizerKey;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: child),
      Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: 8,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyUpEvent) return KeyEventResult.ignored;
            final delta = switch (event.logicalKey) {
              LogicalKeyboardKey.arrowLeft => -8.0,
              LogicalKeyboardKey.arrowRight => 8.0,
              _ => null,
            };
            if (delta == null) return KeyEventResult.ignored;
            onUpdate(delta);
            onEnd();
            return KeyEventResult.handled;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              key: resizerKey,
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) => onUpdate(details.delta.dx),
              onHorizontalDragEnd: (_) => onEnd(),
              onHorizontalDragCancel: onEnd,
            ),
          ),
        ),
      ),
    ],
  );
}

String _statusLetter(String status) =>
    status.characters.isEmpty ? '' : status.characters.first;

String _shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);
