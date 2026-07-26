import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'full_diff_controller.dart';
import 'full_diff_header.dart';
import 'full_diff_hunk_view.dart';
import 'full_diff_model.dart';
import 'git.dart';
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
  static const _minDiffWidth = 360.0;

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
      final hunks = state.document?.hunks ?? const <DiffHunk>[];
      if (hunks.isEmpty) return;
      final index = state.activeHunkIndex.clamp(0, hunks.length - 1);
      final context = _anchorKeys[hunks[index].anchor.id]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(context, alignment: 0.1);
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    // Arrows repeat while held, like the timeline's.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    // Meta walks the commits beside the diff; bare arrows walk this commit's
    // files, which is the move you make far more often.
    if (HardwareKeyboard.instance.isMetaPressed) {
      _stepCommit(step);
    } else {
      _stepFile(step);
    }
    return KeyEventResult.handled;
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
        body: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final widths = _effectiveColumnWidths(constraints.maxWidth);
              return Row(
                children: [
                  _resizableColumn(
                    columnKey: 'nearby',
                    width: widths.commits,
                    child: _nearbyCommits(state),
                    onStart: () => _commitsWidth = widths.commits,
                    onUpdate: (delta) => _resizeCommits(
                      delta,
                      viewportWidth: constraints.maxWidth,
                      filesWidth: widths.files,
                    ),
                  ),
                  _resizableColumn(
                    columnKey: 'details-files',
                    width: widths.files,
                    child: _detailsAndFiles(state),
                    onStart: () => _filesWidth = widths.files,
                    onUpdate: (delta) => _resizeFiles(
                      delta,
                      viewportWidth: constraints.maxWidth,
                      commitsWidth: widths.commits,
                    ),
                  ),
                  Expanded(key: const Key('diff-column'), child: _diff(state)),
                ],
              );
            },
          ),
        ),
      );
    },
  );

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
              onPreviousHunk: () => _controller.stepHunk(-1),
              onNextHunk: () => _controller.stepHunk(1),
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
