import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'full_diff_controller.dart';
import 'full_diff_header.dart';
import 'full_diff_hunk_view.dart';
import 'full_diff_model.dart';
import 'git.dart';
import 'page_scroll_shortcuts.dart';
import 'settings.dart';
import 'typography.dart';

const _background = Color(0xFF15171E);
const _surface = Color(0xFF1D2029);
const _raised = Color(0xFF252936);
const _border = Color(0xFF343946);
const _accent = Color(0xFF263246);
const _text = Color(0xFFE8EAF2);
const _muted = Color(0xFF8D94A8);
const _addedFill = Color(0xFF8AD6A1);
const _deleted = Color(0xFFF29AB2);
const _renamed = Color(0xFFB6A0EA);

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

class _StepCommitIntent extends Intent {
  const _StepCommitIntent(this.delta);

  final int delta;
}

class _StepFileIntent extends Intent {
  const _StepFileIntent(this.delta);

  final int delta;
}

class DiffScreen extends StatefulWidget {
  const DiffScreen({
    required this.repository,
    required this.commits,
    required this.initialIndex,
    this.controller,
    this.columnWidths = const FullDiffColumnWidths(),
    this.onColumnWidthsChanged,
    super.key,
  });

  final FullDiffRepository repository;
  final List<GitCommit> commits;
  final int initialIndex;
  final FullDiffSessionController? controller;
  final FullDiffColumnWidths columnWidths;
  final ValueChanged<FullDiffColumnWidths>? onColumnWidthsChanged;

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  static const _minDiffWidth = 520.0;

  final _diffScroll = ScrollController();
  Map<String, GlobalKey> _anchorKeys = <String, GlobalKey>{};

  late final FullDiffSessionController _controller;
  late final bool _ownsController;
  late FullDiffSessionState _observedState;
  late double _commitsWidth;
  late double _filesWidth;
  bool _effectScheduled = false;
  bool _pendingScrollToTop = false;
  bool _pendingActiveAnchor = false;

  @override
  void initState() {
    super.initState();
    _commitsWidth = widget.columnWidths.commits;
    _filesWidth = widget.columnWidths.files;
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        FullDiffSessionController(
          repository: widget.repository,
          commits: widget.commits,
          initialIndex: widget.initialIndex,
        );
    _observedState = _controller.state;
    _reconcileAnchorKeys(_observedState.document);
    _controller.addListener(_handleControllerChanged);
    if (_ownsController) _controller.initialize();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _diffScroll.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    final previous = _observedState;
    final next = _controller.state;
    _observedState = next;
    final movedContext =
        previous.commitIndex != next.commitIndex ||
        previous.parent != next.parent ||
        previous.selectedPath != next.selectedPath;
    final changedDocument = !identical(previous.document, next.document);

    if (changedDocument) _reconcileAnchorKeys(next.document);
    if (movedContext) {
      _pendingScrollToTop = true;
      if (next.activeHunkIndex == 0) _pendingActiveAnchor = false;
    }
    if (!_pendingScrollToTop &&
        (changedDocument || previous.activeHunkIndex != next.activeHunkIndex) &&
        !(movedContext && next.activeHunkIndex == 0)) {
      _pendingActiveAnchor = true;
    }
    if (_pendingScrollToTop || _pendingActiveAnchor) _scheduleScrollEffect();
  }

  void _reconcileAnchorKeys(DiffDocument? document) {
    final previous = _anchorKeys;
    _anchorKeys = <String, GlobalKey>{
      for (final hunk in document?.hunks ?? const <DiffHunk>[])
        hunk.anchor.id: previous[hunk.anchor.id] ?? GlobalKey(),
    };
  }

  void _scheduleScrollEffect() {
    if (_effectScheduled) return;
    _effectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _effectScheduled = false;
      if (!mounted) return;

      if (_pendingScrollToTop) {
        if (_diffScroll.hasClients) {
          _diffScroll.jumpTo(0);
          _pendingScrollToTop = false;
        }
      }
      if (!_pendingActiveAnchor) return;
      _pendingActiveAnchor = false;
      final state = _controller.state;
      final document = state.document;
      final index = state.activeHunkIndex;
      if (document == null || index < 0 || index >= document.hunks.length) {
        return;
      }
      final context =
          _anchorKeys[document.hunks[index].anchor.id]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.1,
        duration: const Duration(milliseconds: 100),
      );
    });
  }

  void _stepHunk(int delta) {
    _controller.stepHunk(delta);
    _pendingActiveAnchor = true;
    _scheduleScrollEffect();
  }

  void _stepFile(int delta) {
    final state = _controller.state;
    if (state.files.isEmpty) return;
    final index = state.files.indexWhere(
      (file) => file.path == state.selectedPath,
    );
    final next = (index + delta).clamp(0, state.files.length - 1);
    final path = state.files[next].path;
    if (path != state.selectedPath) _controller.selectFile(path);
  }

  void _stepCommit(int delta) {
    final index = _controller.state.commitIndex;
    final next = (index + delta).clamp(0, widget.commits.length - 1);
    if (next != index) _controller.selectCommit(next);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final state = _controller.state;
      return Scaffold(
        backgroundColor: _background,
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
                _StepCommitIntent(-1),
            SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
                _StepCommitIntent(1),
            SingleActivator(LogicalKeyboardKey.arrowUp): _StepFileIntent(-1),
            SingleActivator(LogicalKeyboardKey.arrowDown): _StepFileIntent(1),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _ReturnToTimelineIntent: CallbackAction<_ReturnToTimelineIntent>(
                onInvoke: (_) {
                  Navigator.of(context).maybePop();
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
                  _stepHunk(intent.delta);
                  return null;
                },
              ),
              _StepCommitIntent: CallbackAction<_StepCommitIntent>(
                onInvoke: (intent) {
                  _stepCommit(intent.delta);
                  return null;
                },
              ),
              _StepFileIntent: CallbackAction<_StepFileIntent>(
                onInvoke: (intent) {
                  _stepFile(intent.delta);
                  return null;
                },
              ),
              PageScrollIntent: CallbackAction<PageScrollIntent>(
                onInvoke: (intent) {
                  final animate =
                      !_diffScroll.hasClients ||
                      !_diffScroll.position.isScrollingNotifier.value;
                  applyPageScroll(
                    _diffScroll,
                    direction: intent.direction,
                    animate: animate,
                  );
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final panes = state.focusMode
                      ? (showCommits: false, showFiles: false)
                      : _visiblePanes(constraints.maxWidth);
                  final bothWidths = panes.showCommits
                      ? _effectiveColumnWidths(constraints.maxWidth)
                      : null;
                  final filesWidth = panes.showFiles
                      ? bothWidths?.files ??
                            _effectiveFilesWidth(constraints.maxWidth)
                      : 0.0;
                  return Row(
                    children: [
                      if (panes.showCommits)
                        _resizableColumn(
                          columnKey: 'nearby',
                          width: bothWidths!.commits,
                          child: _nearbyCommits(state),
                          onStart: () => _commitsWidth = bothWidths.commits,
                          onUpdate: (delta) => _resizeCommits(
                            delta,
                            viewportWidth: constraints.maxWidth,
                            filesWidth: filesWidth,
                          ),
                        ),
                      if (panes.showFiles)
                        _resizableColumn(
                          columnKey: 'details-files',
                          width: filesWidth,
                          child: _detailsAndFiles(state),
                          onStart: () => _filesWidth = filesWidth,
                          onUpdate: (delta) => _resizeFiles(
                            delta,
                            viewportWidth: constraints.maxWidth,
                            commitsWidth: bothWidths?.commits ?? 0,
                          ),
                        ),
                      Expanded(
                        key: const Key('diff-column'),
                        child: _diff(state),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );

  ({bool showCommits, bool showFiles}) _visiblePanes(double width) {
    if (width < _minDiffWidth + FullDiffColumnWidths.minFiles) {
      return (showCommits: false, showFiles: false);
    }
    if (width <
        _minDiffWidth +
            FullDiffColumnWidths.minFiles +
            FullDiffColumnWidths.minCommits) {
      return (showCommits: false, showFiles: true);
    }
    return (showCommits: true, showFiles: true);
  }

  double _effectiveFilesWidth(double viewport) {
    final files = _filesWidth.clamp(
      FullDiffColumnWidths.minFiles,
      FullDiffColumnWidths.maxFiles,
    );
    final budget = math.max(
      FullDiffColumnWidths.minFiles,
      viewport - _minDiffWidth,
    );
    return math.min(files, budget);
  }

  ({double commits, double files}) _effectiveColumnWidths(double viewport) {
    var commits = _commitsWidth.clamp(
      FullDiffColumnWidths.minCommits,
      FullDiffColumnWidths.maxCommits,
    );
    var files = _filesWidth.clamp(
      FullDiffColumnWidths.minFiles,
      FullDiffColumnWidths.maxFiles,
    );
    final minimumPanels =
        FullDiffColumnWidths.minCommits + FullDiffColumnWidths.minFiles;
    final panelBudget = math.max(minimumPanels, viewport - _minDiffWidth);
    var overflow = math.max(0, commits + files - panelBudget);
    final fileShrink = math.min(
      overflow,
      files - FullDiffColumnWidths.minFiles,
    );
    files -= fileShrink;
    overflow -= fileShrink;
    commits -= math.min(overflow, commits - FullDiffColumnWidths.minCommits);
    return (commits: commits, files: files);
  }

  void _resizeCommits(
    double delta, {
    required double viewportWidth,
    required double filesWidth,
  }) {
    final max = math.min(
      FullDiffColumnWidths.maxCommits,
      math.max(
        FullDiffColumnWidths.minCommits,
        viewportWidth - filesWidth - _minDiffWidth,
      ),
    );
    setState(() {
      _commitsWidth = (_commitsWidth + delta).clamp(
        FullDiffColumnWidths.minCommits,
        max,
      );
    });
  }

  void _resizeFiles(
    double delta, {
    required double viewportWidth,
    required double commitsWidth,
  }) {
    final max = math.min(
      FullDiffColumnWidths.maxFiles,
      math.max(
        FullDiffColumnWidths.minFiles,
        viewportWidth - commitsWidth - _minDiffWidth,
      ),
    );
    setState(() {
      _filesWidth = (_filesWidth + delta).clamp(
        FullDiffColumnWidths.minFiles,
        max,
      );
    });
  }

  Widget _resizableColumn({
    required String columnKey,
    required double width,
    required Widget child,
    required VoidCallback onStart,
    required ValueChanged<double> onUpdate,
  }) => SizedBox(
    key: Key('$columnKey-column'),
    width: width,
    child: Stack(
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
              onStart();
              onUpdate(delta);
              _saveColumnWidths();
              return KeyEventResult.handled;
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                key: Key('$columnKey-column-resizer'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => onStart(),
                onHorizontalDragUpdate: (details) => onUpdate(details.delta.dx),
                onHorizontalDragEnd: (_) => _saveColumnWidths(),
                onHorizontalDragCancel: _saveColumnWidths,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  void _saveColumnWidths() => widget.onColumnWidthsChanged?.call(
    FullDiffColumnWidths(commits: _commitsWidth, files: _filesWidth),
  );

  Widget _nearbyCommits(FullDiffSessionState state) => Material(
    color: _surface,
    shape: const Border(right: BorderSide(color: _border)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, size: 17),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Nearby commits',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _selectable(
            ListView.builder(
              key: const Key('nearby-commits-list'),
              itemCount: widget.commits.length,
              itemBuilder: (context, index) {
                final commit = widget.commits[index];
                final selected = index == state.commitIndex;
                return ListTile(
                  key: selected ? Key('selected-nearby-${commit.sha}') : null,
                  selected: selected,
                  dense: true,
                  title: Text(
                    commit.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(commit.shortSha),
                  onTap: () {
                    if (index != state.commitIndex) {
                      _controller.selectCommit(index);
                    }
                  },
                );
              },
            ),
          ),
        ),
      ],
    ),
  );

  Widget _detailsAndFiles(FullDiffSessionState state) {
    final commit = widget.commits[state.commitIndex];
    return Material(
      color: _surface,
      shape: const Border(right: BorderSide(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  commit.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${commit.shortSha} · ${commit.author.name}',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                if (commit.parents.length > 1) ...[
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    key: const Key('merge-parent-chooser'),
                    isExpanded: true,
                    value: state.parent,
                    items: [
                      for (
                        var index = 0;
                        index < commit.parents.length;
                        index++
                      )
                        DropdownMenuItem(
                          value: commit.parents[index],
                          child: Text(
                            'Parent ${index + 1} · '
                            '${_shortSha(commit.parents[index])}',
                          ),
                        ),
                    ],
                    onChanged: (parent) {
                      if (parent == null || parent == state.parent) return;
                      _controller.selectParent(parent);
                    },
                  ),
                ],
              ],
            ),
          ),
          _sectionHeader(const Text('Changed files')),
          Expanded(
            child: Stack(
              children: [
                _selectable(
                  ListView.builder(
                    key: const Key('changed-files-list'),
                    itemCount: state.files.length,
                    itemBuilder: (context, index) {
                      final file = state.files[index];
                      final selected = file.path == state.selectedPath;
                      return ListTile(
                        key: selected
                            ? Key('selected-file-${file.path}')
                            : null,
                        dense: true,
                        selected: selected,
                        minLeadingWidth: 18,
                        horizontalTitleGap: 7,
                        leading: _statusChip(file.status),
                        title: Text(
                          file.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: technicalFontFamily,
                            fontFamilyFallback: technicalFontFallback,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Text(
                          '+${file.additions ?? '-'} −${file.deletions ?? '-'}',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 10,
                            fontFamily: technicalFontFamily,
                            fontFamilyFallback: technicalFontFallback,
                          ),
                        ),
                        onTap: () {
                          if (file.path != state.selectedPath) {
                            _controller.selectFile(file.path);
                          }
                        },
                      );
                    },
                  ),
                ),
                if (state.loadingFiles)
                  const Center(
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `git` reports statuses like `M`, `A`, `D`, and `R100`, so the family comes
  /// from the first letter and only that letter fits the 18px chip.
  Widget _statusChip(String status) {
    final letter = status.isEmpty ? '' : status[0];
    final tint = switch (letter) {
      'A' => _addedFill,
      'D' => _deleted,
      'R' || 'C' => _renamed,
      _ => null,
    };
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint?.withValues(alpha: 0.2) ?? _accent,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        letter,
        maxLines: 1,
        style: TextStyle(
          color: tint ?? _text,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _diff(FullDiffSessionState state) {
    GitFileChange? selectedFile;
    for (final file in state.files) {
      if (file.path == state.selectedPath) {
        selectedFile = file;
        break;
      }
    }

    return ColoredBox(
      color: _background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: _surface,
            child: DiffFileHeader(
              file: selectedFile,
              path: state.selectedPath,
              hunkSelected: true,
            ),
          ),
          ColoredBox(
            color: _surface,
            child: DiffToolbar(
              activeHunkIndex: state.activeHunkIndex,
              hunkCount: state.document?.hunks.length ?? 0,
              algorithm: state.algorithm,
              ignoreWhitespace: state.ignoreWhitespace,
              wrapLines: state.wrapLines,
              focusMode: state.focusMode,
              loading: state.loadingDiff,
              onPreviousHunk: () => _stepHunk(-1),
              onNextHunk: () => _stepHunk(1),
              onAlgorithmSelected: (algorithm) {
                if (algorithm != state.algorithm) {
                  _controller.selectAlgorithm(algorithm);
                }
              },
              onIgnoreWhitespaceChanged: (value) {
                if (value != state.ignoreWhitespace) {
                  _controller.setIgnoreWhitespace(value);
                }
              },
              onWrapLinesChanged: (value) {
                if (value != state.wrapLines) {
                  _controller.setWrapLines(value);
                }
              },
              onFocusModeChanged: (value) {
                if (value != state.focusMode) {
                  _controller.setFocusMode(value);
                }
              },
            ),
          ),
          if (state.error != null)
            Container(
              color: const Color(0xFF492B37),
              padding: const EdgeInsets.all(8),
              child: Text(
                state.error.toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _deleted, fontSize: 11),
              ),
            ),
          Expanded(
            child: HunkListView(
              document: state.document ?? DiffDocument.empty,
              activeHunkIndex: state.activeHunkIndex,
              wrapLines: state.wrapLines,
              controller: _diffScroll,
              anchorKeys: _anchorKeys,
              onHunkSelected: (index) {
                if (index != state.activeHunkIndex) {
                  _controller.selectHunk(index);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectable(Widget child) => SelectionArea(child: child);

  Widget _sectionHeader(Widget child) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.centerLeft,
    decoration: const BoxDecoration(
      color: _raised,
      border: Border(bottom: BorderSide(color: _border)),
    ),
    child: DefaultTextStyle(
      style: const TextStyle(
        color: _text,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      child: child,
    ),
  );

  String _shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);
}
