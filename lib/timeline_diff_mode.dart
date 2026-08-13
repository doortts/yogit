part of 'timeline.dart';

/// Diff mode: the embedded full-diff workspace that takes the timeline's place,
/// the History pane beside it, and the walk between the two and the preview.

extension _TimelineDiffMode on _TimelineScreenState {
  /// → (or l) from the timeline: the preview takes the keyboard and shows the
  /// diff of whatever file it is pointing at, opening the panel if it is away.
  void _enterPreview() {
    final commit = _selectedCommit;
    if (commit == null) return;
    if (_previewController.previewPlacement == PreviewPlacement.closed) {
      unawaited(
        _previewController.setPreview(widget.preferredPreviewPlacement),
      );
    }
    _previewFocusNode.requestFocus();
    // 커밋 패널의 파일은 축이 있는 목록이라 `loadFiles`가 답하는 작업 트리 ↔
    // HEAD 목록과 다르다. 커서가 앉은 행이 곧 열 파일이다.
    if (_commitPanelOpen) {
      _openCommitCursorDiff();
      return;
    }
    if (_showsBranchPreviewDiff(commit)) return;
    final key = _previewKey(commit);
    final known =
        _previewPaths[key] ?? _previewFileLists[key]?.firstOrNull?.path;
    if (known != null) {
      _showPreviewDiff(commit, known);
      return;
    }
    // A panel that was away has no file list yet; the diff opens as soon as
    // git answers with one.
    unawaited(
      _previewFilesFor(commit).then((files) {
        if (!mounted || files.isEmpty) return;
        if (!identical(commit, _selectedCommit)) return;
        _showPreviewDiff(commit, _previewPaths[key] ?? files.first.path);
      }),
    );
  }

  /// ← (or h) from the preview: the diff folds away and the timeline takes the
  /// keyboard back, with the panel itself left alone.
  void _leavePreview() {
    if (_fullDiffOpen) _closeFullDiff();
    _focusNode.requestFocus();
  }

  /// Where ← and → land inside diff mode. The panes read left to right as the
  /// layout draws them, and → off the right end folds the diff away.
  void _movePaneFocus(int step) {
    final nodes = <FocusNode>[
      if (_previewController.previewPlacement == PreviewPlacement.left) ...[
        _previewFocusNode,
        if (_historyPaneOpen) _historyPaneFocusNode,
        _diffFocusNode,
      ] else ...[
        _diffFocusNode,
        if (_historyPaneOpen) _historyPaneFocusNode,
        _previewFocusNode,
      ],
    ];
    final here = nodes.indexWhere((node) => node.hasFocus);
    if (here < 0) return;
    final next = here + step;
    if (next < 0 || next >= nodes.length) {
      // Off the end the diff has nothing more to show: hand the keyboard back
      // to the commit list it came from.
      _leavePreview();
      return;
    }
    nodes[next].requestFocus();
  }

  bool get _historyPaneOpen =>
      _fullDiffOpen && _fullDiffHistoryOpen && !_fullDiffFocusMode;

  KeyEventResult _onPreviewKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _leavePreview();
      return KeyEventResult.handled;
    }
    // 제목·본문을 치는 중이면 h·j·k·l은 글자고 화살표는 캐럿의 것이다. 루트
    // 핸들러가 쓰는 가드를 그대로 써서 탐색 키를 TextField에 흘려보낸다.
    if (_editableDescendantHasFocus) return KeyEventResult.ignored;
    final key = normalizeNavigationKey(
      event.logicalKey,
      hasModifier: keyboard.isShiftPressed || keyboard.isControlPressed,
    );
    // Inside diff mode the arrows walk the panes; with the diff away, ← still
    // means "back to the commits" and → has nowhere else to go.
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_fullDiffOpen) {
        _movePaneFocus(-1);
      } else {
        _leavePreview();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _leavePreview();
      return KeyEventResult.handled;
    }
    final step = switch (key) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    if (_commitPanelOpen) {
      _moveCommitCursor(step);
    } else {
      _stepPreviewFile(step, animate: event is KeyDownEvent);
    }
    return KeyEventResult.handled;
  }

  GitCommit? _commitBySha(String sha) {
    for (final candidate in _commits) {
      if (candidate.sha == sha) return candidate;
    }
    return null;
  }

  void _forwardFullDiffPreferences(FullDiffPreferences preferences) {
    if (!mounted) return;
    if (widget.onFullDiffPreferencesChanged case final callback?
        when _pendingFullDiffPreferences == null &&
            !_fullDiffPersistenceFlushScheduled) {
      callback(preferences);
      return;
    }
    _pendingFullDiffPreferences = preferences;
    _scheduleFullDiffPersistenceFlush();
  }

  void _forwardFullDiffColumnWidths(FullDiffColumnWidths widths) {
    if (!mounted) return;
    if (widget.onFullDiffColumnWidthsChanged case final callback?
        when _pendingFullDiffColumnWidths == null &&
            !_fullDiffPersistenceFlushScheduled) {
      callback(widths);
      return;
    }
    _pendingFullDiffColumnWidths = widths;
    _scheduleFullDiffPersistenceFlush();
  }

  void _clearPendingFullDiffPersistence() {
    _pendingFullDiffPreferences = null;
    _pendingFullDiffColumnWidths = null;
    _fullDiffPersistenceFlushScheduled = false;
  }

  /// ⌘D and both Full Diff buttons: the diff takes the sidebar and timeline
  /// area, or hands it back. A closed preview opens first — it is the file
  /// navigation the diff mode relies on.
  void _openFullDiff(GitCommit commit, String? path, {bool focusDiff = true}) {
    // 커밋 모드의 diff는 축 하나에 묶인 어댑터를 통해 읽고, 그 어댑터는 어떤
    // 커밋을 줘도 작업 트리를 답하므로 이웃 커밋을 데리고 다니지 않는다.
    final commitMode = commit.isWorkingTree && _cherryPickState == null;
    final preferences =
        _pendingFullDiffPreferences ?? widget.fullDiffPreferences;
    final controller = FullDiffSessionController(
      repository: commitMode
          ? WorkingTreeAreaRepository(widget.repository, _commitDiffArea)
          : widget.repository,
      commits: commitMode ? [commit] : List<GitCommit>.unmodifiable(_commits),
      initialIndex: commitMode ? 0 : math.max(0, _commits.indexOf(commit)),
      // 인덱스 blob에는 blame을 물을 대상이 없다. 저장된 뷰가 Blame이면 키를
      // 누르지 않아도 그 자리로 열리므로 인덱스 축에서는 접어 둔다.
      initialPreferences:
          commitMode && _commitDiffArea == WorkingTreeArea.staged
          ? preferences.copyWith(view: FullDiffView.diff)
          : preferences,
      initialPath: path,
    )..addListener(_followFullDiffSession);
    if (_scrollController.hasClients) {
      _timelineOffsetBeforeDiff = _scrollController.offset;
      _timelineIndexBeforeDiff = _selectedIndex.value;
    }
    _rebuild(() {
      _previewDiffOpen = false;
      _fullDiffSession = controller;
      _fullDiffHistoryOpen = controller.state.historySelected;
      _fullDiffFocusMode = controller.state.focusMode;
    });
    // The workspace carries its own shortcuts, so it needs the keyboard —
    // unless the caller is handing it to the preview instead. The node is not
    // attached until the workspace builds, so a request here outlives this
    // frame and would steal focus back.
    if (focusDiff) _diffFocusNode.requestFocus();
    unawaited(_startFullDiff(controller, path));
  }

  void _showFullDiffFile(String? path) {
    final controller = _fullDiffSession;
    if (controller == null || path == null) return;
    for (final file in controller.state.files) {
      if (file.path == path) {
        unawaited(controller.selectFile(file));
        return;
      }
    }
  }

  /// The preview list is the diff's navigation, so its highlight follows
  /// whatever the workspace's own keyboard selects — and scrolls after it.
  /// The History and 집중 모드 flags ride along: both change what the timeline
  /// lays out beside the diff.
  void _followFullDiffSession() {
    final controller = _fullDiffSession;
    if (controller == null || !mounted) return;
    final state = controller.state;
    if (_fullDiffHistoryOpen != state.historySelected ||
        _fullDiffFocusMode != state.focusMode) {
      _rebuild(() {
        _fullDiffHistoryOpen = state.historySelected;
        _fullDiffFocusMode = state.focusMode;
      });
    }
    final commit = _selectedCommit;
    final path = state.selectedFile?.path;
    if (commit == null || path == null) return;
    final key = _previewKey(commit);
    final previous = _previewPaths[key];
    if (previous == path) return;
    final files = state.files;
    final direction =
        files.indexWhere((file) => file.path == path) <
            files.indexWhere((file) => file.path == previous)
        ? -1
        : 1;
    _rebuild(() => _previewPaths[key] = path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealSelectedPreviewFile(direction, animate: false);
    });
  }

  void _closeFullDiff() {
    final controller = _fullDiffSession;
    if (controller == null) return;
    _rebuild(() => _fullDiffSession = null);
    controller
      ..removeListener(_followFullDiffSession)
      ..dispose();
    _focusNode.requestFocus();
    _restoreTimelineOffset();
  }

  /// The list is rebuilt from scratch when it comes back, so it starts at the
  /// top; put it back where the reader left it — unless the diff moved the
  /// selection, in which case the new row is what they want to see.
  void _restoreTimelineOffset() {
    final offset = _timelineOffsetBeforeDiff;
    final index = _timelineIndexBeforeDiff;
    _timelineOffsetBeforeDiff = null;
    _timelineIndexBeforeDiff = null;
    if (offset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (index != _selectedIndex.value) {
        _scrollToSelection(animate: false);
        return;
      }
      final position = _scrollController.position;
      _scrollController.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  /// History rides beside the preview, not inside the diff: the two panes
  /// together are the navigation the diff mode reads from.
  Widget _historyPane(FullDiffSessionController controller) => KeyedSubtree(
    key: const Key('history-pane'),
    child: FullDiffResizablePane(
      width: _historyWidth,
      minWidth: FullDiffColumnWidths.minHistory,
      maxWidth: FullDiffColumnWidths.maxHistory,
      label: 'History pane width',
      resizerKey: const Key('history-pane-resizer'),
      dividerKey: const Key('history-pane-divider'),
      // The seam this pane widens across is the diff's, except at the bottom
      // where the diff is overhead and the preview is the neighbour. The other
      // seam belongs to the preview's own handle.
      handleOnLeft:
          _previewController.previewPlacement != PreviewPlacement.left,
      onChanged: (width) => _rebuild(
        () => _historyWidth = width.clamp(
          FullDiffColumnWidths.minHistory,
          FullDiffColumnWidths.maxHistory,
        ),
      ),
      onChangeEnd: () {
        // 설정이 아직 로딩 중이면 pending이 최신이다 — widget 값으로 되돌리면
        // 같은 세션에서 바꾼 side-by-side 비율을 지워 버린다.
        final base =
            _pendingFullDiffColumnWidths ?? widget.fullDiffColumnWidths;
        _forwardFullDiffColumnWidths(
          FullDiffColumnWidths(
            history: _historyWidth,
            sideBySideRatio: base.sideBySideRatio,
          ),
        );
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final state = controller.state;
          final entries = state.history.data;
          return ColoredBox(
            color: fullDiffHeader,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _historyPaneHeader(state, entries?.length ?? 0),
                Expanded(
                  child: entries == null
                      ? Center(
                          child: Text(
                            state.history.error?.toString() ??
                                'History를 읽는 중입니다',
                            style: const TextStyle(
                              color: fullDiffMuted,
                              fontSize: 10,
                            ),
                          ),
                        )
                      : FullHistoryView(
                          // A new file or commit is a new list: rebuilding it
                          // under a fresh key parks it back at the top.
                          key: ValueKey(state.historyContext),
                          entries: entries,
                          selected: state.selectedHistoryEntry,
                          focusNode: _historyPaneFocusNode,
                          onMoveToFiles: () => _movePaneFocus(-1),
                          onSelected: (entry) =>
                              _selectHistoryEntry(controller, entry),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _historyPaneHeader(FullDiffSessionState state, int count) {
    final path = state.selectedFile?.path ?? '';
    final name = path.isEmpty ? '' : path.split('/').last;
    return Container(
      key: const Key('history-pane-header'),
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: fullDiffDivider)),
      ),
      child: Row(
        children: [
          const Text(
            'History',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$name · $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: technicalTextStyle.copyWith(
                color: fullDiffMuted,
                fontSize: 10,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Picking an entry points all three at that commit: the diff reloads it, and
  /// the timeline selection moves so the preview pane follows along. The move
  /// goes first, so the session's own notifications land on the new commit.
  void _selectHistoryEntry(
    FullDiffSessionController controller,
    FileHistoryEntry entry,
  ) {
    final index = _entries.indexWhere(
      (candidate) =>
          candidate.rowIndex >= 0 &&
          candidate.row.commit.sha == entry.commit.sha,
    );
    if (index >= 0) _selectedIndex.value = index;
    unawaited(controller.selectHistoryEntry(entry));
  }

  Widget _embeddedFullDiff(FullDiffSessionController controller) {
    final repository = controller.repository;
    final area = repository is WorkingTreeAreaRepository
        ? repository.area
        : null;
    return FullDiffWorkspace(
      controller: controller,
      onBack: _closeFullDiff,
      focusNode: _diffFocusNode,
      onMovePane: _movePaneFocus,
      columnWidths: _pendingFullDiffColumnWidths ?? widget.fullDiffColumnWidths,
      onColumnWidthsChanged: _forwardFullDiffColumnWidths,
      onPreferencesChanged: _forwardFullDiffPreferences,
      avatarService: widget.avatarService,
      showRemoteAvatars: widget.showRemoteAvatars,
      commitArea: area,
      onCommitAreaSelected: area == null ? null : _selectCommitArea,
      commitAreaEnabled: area == null ? null : _commitAreaSelectable,
      onStageFile: area == null || _commitModeBusy
          ? null
          : () => unawaited(_stageSelectedCommitFile(area)),
      hunkActions: area == null ? null : _commitHunkActions,
    );
  }
}
