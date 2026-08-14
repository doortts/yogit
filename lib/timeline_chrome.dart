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
      // The row is handed its own width because the wordmark has to know where
      // the window's centre is, and the padding is symmetric, so this box's
      // centre is the window's.
      child: LayoutBuilder(
        builder: (context, constraints) => _toolbarRow(constraints.maxWidth),
      ),
    ),
  );

  Widget _toolbarRow(double width) => Row(
    children: [
      Expanded(child: _toolbarLeft(width)),
      _toolbarRight(),
    ],
  );

  /// The selector takes what the bar has left once the window buttons, the
  /// cluster on the right, the drag stretch and the preview controls have
  /// theirs. Computed from the toolbar's own width rather than under a
  /// [LayoutBuilder] of its own, because the wordmark needs the same number to
  /// know where the left cluster ends.
  double _selectorWidth(double width) {
    final previewControlsWidth = _compareRef == null ? 0.0 : 212.0;
    // 이름이 잘리는 것보다 창을 끄는 빈칸이 좁아지는 편이 낫다: 그
    // 자리는 어차피 비어 있고, 최소 폭은 아래에서 지켜진다.
    return math.min(
      620.0,
      math.max(
        0.0,
        width -
            _TimelineScreenState._windowButtonsWidth -
            _toolbarRightWidth -
            _TimelineScreenState._minDragWidth -
            previewControlsWidth,
      ),
    );
  }

  /// Where the mark goes and whether it goes at all, decided from [dragWidth] —
  /// the drag stretch's own width, which is the free space itself now that the
  /// selector's box ends where its ink ends. The stretch's right edge is where
  /// the cluster on the right begins, so its left edge follows, and the window's
  /// centre restated in the stretch's coordinates is where the glyphs sit — the
  /// centre of the window, never the centre of what the row had left over.
  /// 26px while the whole mark plus 24px of air on each side clears both ends of
  /// the stretch, 20px while only the smaller band does, nothing once the centre
  /// belongs to the clusters.
  Widget _centeredWordmark(
    BuildContext context,
    double toolbarWidth,
    double dragWidth,
  ) {
    final dragRight = toolbarWidth - _toolbarRightWidth;
    final dragLeft = dragRight - dragWidth;
    final size = [26.0, 20.0].firstWhere((size) {
      final reach = Wordmark.widthAt(context, size) / 2 + 24;
      return toolbarWidth / 2 - reach >= dragLeft &&
          toolbarWidth / 2 + reach <= dragRight;
    }, orElse: () => 0.0);
    if (size == 0) return const SizedBox.expand();
    return Padding(
      padding: EdgeInsets.only(
        left: toolbarWidth / 2 - Wordmark.widthAt(context, size) / 2 - dragLeft,
      ),
      // The glyphs never eat a pointer: the bar still drags from under them.
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wordmark(key: const Key('wordmark'), fontSize: size),
        ),
      ),
    );
  }

  Widget _toolbarLeft(double width) => Row(
    children: [
      _windowButtons(),
      // A maximum, not a size: the selector's row shrink-wraps its ink inside
      // it, so the drag stretch that follows really is the room left over. The
      // cap still has to be finite — it is what the names ellipsize against.
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _selectorWidth(width)),
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
            tags: sortRefsNewestFirst(_refs.tags, _refs.tagCreatorTimes),
            tagTimes: _refs.tagCreatorTimes,
            selectedBranch: _baseBranch,
            comparedBranch: _compareRef,
            refsLoading: _refsLoading,
            refsLoadFailed: _refsLoadFailed,
            onRepositoryPressed: () => unawaited(_pickRepository()),
            recentRepositories: widget.recentRepositories,
            onRecentRepositorySelected: (path) =>
                unawaited(_openRepositoryPath(path)),
            onRecentRepositoryRemoved: widget.onForgetRecentRepository,
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
      Expanded(child: _dragRegion(width)),
    ],
  );

  /// Measured and drawn from one place, so the two cannot drift apart.
  static const _monitorLabel = '모니터링';

  /// What the cluster on the right takes, summed from the controls themselves.
  /// The selector's width and the wordmark's centre band both need it while the
  /// bar is still laying itself out, and a fourth control has to add its term
  /// here — a single constant for the lot would go stale in silence. The monitor
  /// button's term is measured rather than rounded: the mark's centre is only as
  /// true as this sum, and rounding the label up nudged the glyphs a few pixels
  /// right of the window's centre in the one configuration that ships.
  double get _toolbarRightWidth =>
      28 + // the preview toggle's own box
      12 +
      (widget.onOpenMonitor == null ? 0 : _monitorButtonWidth + 8) +
      40; // the settings gear at compact density

  /// The 모니터링 button's own width: its label laid out in the style the button
  /// draws it in — `labelLarge` is where a [TextButton] takes its text style
  /// from and 13 is what the child overrides it with — plus the 10px of padding
  /// on each side. Measured the way the profile chip measures itself, text scale
  /// included. The border strokes inside the shape, so it costs the box nothing.
  double get _monitorButtonWidth =>
      (TextPainter(
        text: TextSpan(
          text: _monitorLabel,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout()).width +
      20;

  Widget _toolbarRight() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      // Placement moved into the pane's own header. What stays here is the way
      // back in: with the pane shut there is no header to hold a button.
      _previewToggleButton(),
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
          child: const Text(_monitorLabel, style: TextStyle(fontSize: 13)),
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

  /// 미리보기를 여닫는 버튼. 왼쪽 패널의 버튼과 같은 그림을 좌우로 뒤집어 쓴다.
  Widget _previewToggleButton() => ListenableBuilder(
    listenable: _previewController,
    builder: (context, _) {
      final open =
          _previewController.previewPlacement != PreviewPlacement.closed;
      return Tooltip(
        message: open ? '미리보기 닫기 (Enter)' : '미리보기 열기 (Enter)',
        waitDuration: Duration.zero,
        child: SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            key: const Key('preview-toggle'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            onPressed: () {
              _togglePreview();
              _focusNode.requestFocus();
            },
            icon: CustomPaint(
              key: Key(open ? 'preview-collapse-icon' : 'preview-expand-icon'),
              size: const Size(14.4, 14.4),
              painter: PaneToggleIconPainter(
                opens: !open,
                color: open ? _palette.text : _palette.muted,
                mirrored: true,
              ),
            ),
          ),
        ),
      );
    },
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

  /// 작업 트리 행을 고르고 있는 동안만 서는 키 힌트 — 시안 statusbar의 넷.
  /// 좁은 창에서 legend를 밀어내지 않도록 잘려 나간다.
  Widget _commitModeKeyHints() => ValueListenableBuilder<int>(
    valueListenable: _selectedIndex,
    builder: (context, _, _) {
      if (!(_selectedCommit?.isWorkingTree ?? false)) {
        return const SizedBox.shrink();
      }
      return SingleChildScrollView(
        key: const Key('commit-key-hints'),
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            _commitKeyHint('Space', 'Stage / Unstage'),
            _commitKeyHint('⌘↵', '커밋'),
            _commitKeyHint('↑↓', '파일 이동'),
            _commitKeyHint('Esc', 'diff 닫기'),
          ],
        ),
      );
    },
  );

  Widget _commitKeyHint(String cap, String label) => Padding(
    padding: const EdgeInsets.only(left: 16),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: _palette.raised,
            border: Border.all(color: _palette.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            cap,
            style: TextStyle(
              color: _palette.muted,
              fontSize: 10,
              fontFamily: technicalFontFamily,
              fontFamilyFallback: technicalFontFallback,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: _palette.muted, fontSize: 11)),
      ],
    ),
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
                      Flexible(child: _commitModeKeyHints()),
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
              if (widget.commandLog case final log?) ...[
                _consoleToggle(log),
                const SizedBox(width: 8),
              ],
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

  /// The console's door, filed with the readouts: reading the log is checking
  /// state, not editing. A prompt rather than a terminal glyph — at the status
  /// bar's text size a drawn window frame turns to mush, `>_` still reads.
  Widget _consoleToggle(CommandLog log) => ListenableBuilder(
    listenable: log,
    builder: (context, _) => Tooltip(
      message: '콘솔 (⌘`)',
      child: HoverBuilder(
        // A gesture node says nothing about being pressable. The button this
        // replaced announced itself, so this has to announce itself too.
        builder: (hovered) => Semantics(
          button: true,
          onTap: _toggleConsole,
          // The glyph is a picture of a prompt, not a word: read out, `>_`
          // says less than the tooltip already does.
          excludeSemantics: true,
          child: GestureDetector(
            key: const Key('console-toggle'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggleConsole,
            child: Container(
              // Wider and taller than the two glyphs so the pointer has
              // something to hit, without the bar growing around it.
              width: _TimelineScreenState._consoleToggleWidth,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hovered ? _palette.raised : null,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '>_',
                style: TextStyle(
                  // The colour is the only sign a command is out there while
                  // the console is shut.
                  color: _consoleOpen
                      ? _palette.text
                      : log.runningCount > 0
                      ? behindOrange
                      : _palette.muted,
                  fontSize: 11,
                  letterSpacing: 0.5,
                  fontFamily: technicalFontFamily,
                  fontFamilyFallback: technicalFontFallback,
                ),
              ),
            ),
          ),
        ),
      ),
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
                    // 열 사이를 가르는 선이라, 마지막 열의 오른쪽에는 가를
                    // 것이 없다. 그 자리는 목록의 끝이고 그 끝은 이미 창이
                    // 그어 두었으니, 한 줄 더 그으면 두 줄로 보인다.
                    right:
                        timelineColumns.keys.where(_columnVisible).last ==
                            column
                        ? BorderSide.none
                        : BorderSide(color: _palette.border),
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
