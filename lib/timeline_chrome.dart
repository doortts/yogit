part of 'timeline.dart';

/// The frame around the list: the toolbar at the top, the status bar at the
/// bottom, and the column header between them.

extension _TimelineChrome on _TimelineScreenState {
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
                constraints.maxWidth -
                    _TimelineScreenState._minDragWidth -
                    previewControlsWidth,
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
                      trailing: _upstreamSyncCapsule(),
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

  /// 재연이 실패하면 캡슐은 무채색으로 판정을 보류한다 — 왜인지는 여기,
  /// 상태바가 말한다. 다음 refs 로드가 다시 잰다.
  Widget _upstreamMeasureNotice() => ListenableBuilder(
    listenable: _upstreamSync,
    builder: (context, _) {
      final error = _upstreamSync.state.measureError;
      if (error == null) return const SizedBox.shrink();
      return Tooltip(
        message: error,
        child: Text(
          key: const Key('upstream-measure-error'),
          '동기화 판정 실패 · 다시 잽니다',
          style: TextStyle(color: behindOrange, fontSize: 10),
        ),
      );
    },
  );

  Widget _statusBar() => _normalStatusBar();

  Widget _normalStatusBar() => LayoutBuilder(
    builder: (context, constraints) {
      _statusBarWidth = constraints.maxWidth;
      return _normalStatusBarContent();
    },
  );

  Widget _normalStatusBarContent() => Container(
    height: _TimelineScreenState._statusBarHeight,
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
                      _frameRevivalNotice(),
                      _upstreamMeasureNotice(),
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
                  horizontal: _TimelineScreenState._columnTextInset,
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
                          style: _TimelineScreenState._headerLabelStyle
                              .copyWith(
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
        _resizer(column),
      ],
    ),
  );
}
