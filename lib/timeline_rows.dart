part of 'timeline.dart';

/// A commit row as the timeline draws it: the graph node, the ref chips, the
/// badges its git facts earn, and the modal that lists the rest of them.

extension _TimelineRows on _TimelineScreenState {
  double _rowContentWidth(String column, GitCommit commit) => switch (column) {
    'refs' => _refsContentWidth(commit),
    'hash' => _textWidth(
      commit.isWorkingTree ? '·······' : commit.shortSha,
      _TimelineScreenState._hashStyle,
    ),
    // Just the subject. The row's badges ride an `Expanded` that only takes room
    // the subject is not using, so they are decoration the fit does not owe
    // width to.
    'commit' => _textWidth(
      commit.subject,
      TextStyle(fontFamily: _fontFamily, fontSize: _baseFontSize),
    ),
    'time' => _textWidth(
      commit.isWorkingTree
          ? 'working tree'
          : _socialTime(commit.committerTimestamp),
      TextStyle(fontFamily: _fontFamily, fontSize: _supportingFontSize),
    ),
    _ => _textWidth(
      commit.author.name,
      TextStyle(
        fontFamily: _fontFamily,
        fontSize: _supportingFontSize,
        fontWeight: FontWeight.w500,
      ),
    ),
  };

  /// Only the rows whose selected or hovered state flipped rebuild.
  Widget _row(int index, double commitWidth, double graphWidth) =>
      RowStateScope(
        index: index,
        selectedIndex: _selectedIndex,
        hoverIndex: _hoverIndex,
        builder: (selected, hovered) =>
            _rowContent(index, commitWidth, graphWidth, selected, hovered),
      );

  /// The date heading: no node, no hairline, just the rails running through and
  /// a boxed label where the hash column starts.
  Widget _dateRow(int index, TimelineEntry entry, double graphWidth) =>
      RowStateScope(
        index: index,
        selectedIndex: _selectedIndex,
        hoverIndex: _hoverIndex,
        builder: (selected, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _select(index),
          child: ColoredBox(
            color: selected ? _timelineSelectionColor : _palette.background,
            child: _dateRowContent(index, entry, graphWidth),
          ),
        ),
      );

  Widget _dateRowContent(
    int index,
    TimelineEntry entry,
    double graphWidth,
  ) => Row(
    key: Key('date-row-$index'),
    children: [
      SizedBox(width: _w('refs')),
      _graphCell(
        Key('date-painter-$index'),
        _painterFor(entry, index, graphWidth, false, false),
        graphWidth,
      ),
      Padding(
        // 5px left of the hash text (whose rule shifts it), so the box reads as
        // heading the row rather than sitting in the hash column, and pushed
        // down far enough to hang under the group above without clipping.
        padding: const EdgeInsets.only(left: 6, right: 9, top: 2),
        child: Container(
          key: Key('date-box-$index'),
          // The row is the ceiling: box plus downward shift has to clear it, so
          // the height comes from the row rather than from the label's own line
          // height, which would leave the box taller than the row it heads.
          height: _TimelineScreenState._rowChipHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: _dateGroup),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            entry.label!,
            style: const TextStyle(
              color: _dateGroup,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _rowContent(
    int index,
    double commitWidth,
    double graphWidth,
    bool selected,
    bool hovered,
  ) {
    final entry = _entries[index];
    final row = entry.row;
    final commit = row.commit;
    final commonBoundary =
        _comparison?.commits.any(
          (entry) =>
              entry.commit.sha == commit.sha &&
              entry.side == BranchCommitSide.commonBoundary,
        ) ??
        false;
    // One branch line, one color: rails, chips, node ring and hash border.
    final branchColor = commonBoundary
        ? _palette.muted
        : AvatarService.branchColor(row.branch);
    final previewKind = _previewGraph?.kinds[commit.sha];
    final virtualMerge = previewKind == PreviewGraphNodeKind.virtualMerge;
    final virtualRebaseMerge =
        previewKind == PreviewGraphNodeKind.virtualRebaseMerge;
    final rebaseConflict =
        _rebasePreview?.status == RebasePreviewStatus.conflict &&
        _rebasePreview?.currentCommit?.sha == commit.sha;
    final rebaseApplying = _rebaseApplyingSha == commit.sha;
    final virtualPreview =
        virtualMerge ||
        virtualRebaseMerge ||
        previewKind == PreviewGraphNodeKind.virtualRebase;
    final mergeConflict =
        virtualMerge && _effectiveMergeStatus == MergeConflictStatus.conflicts;
    final synthetic =
        commit.isWorkingTree || virtualMerge || virtualRebaseMerge;
    final previewColor = previewKind == PreviewGraphNodeKind.conflictTarget
        ? previewPurple
        : virtualPreview
        ? mergeConflict
              ? previewConflict
              : previewPurple
        : branchColor;
    final rebasePreview = _rebasePreview;
    final originalIndex =
        rebasePreview?.rewritten.indexWhere(
          (rewrite) => rewrite.original.sha == commit.sha,
        ) ??
        -1;
    final compareOnly = _isCompareOnly(commit.sha);
    final resolvedRebaseConflict =
        rebasePreview?.status == RebasePreviewStatus.conflict &&
        originalIndex >= 0 &&
        !rebaseConflict;
    // 재배치가 건너뛸 커밋은 대기 중이 아니라서 대기 색도 받지 않는다.
    final pendingRebaseConflict =
        rebasePreview?.status == RebasePreviewStatus.conflict &&
        compareOnly &&
        originalIndex < 0 &&
        !rebaseConflict &&
        !_duplicateCommits.contains(commit.sha);
    final rowAccentColor = rebaseConflict
        ? previewConflict
        : resolvedRebaseConflict
        ? previewPurple
        : pendingRebaseConflict
        ? behindOrange
        : previewColor;
    final progress = _commitProgressLabel(commit);
    final badges = _commitBadges(commit);
    final refs = _rowRefs(commit);
    final rowColor = mergeConflict
        ? previewConflictPanel
        : rebaseConflict
        ? const Color(0xFF8F2F3A)
        : resolvedRebaseConflict
        ? previewPurplePanel
        : rebaseApplying
        ? const Color(0xFF4D376D)
        : virtualPreview
        ? previewPurplePanel
        : selected
        ? _palette.background
        : hovered
        ? _palette.neutralChip.withValues(alpha: 0.48)
        : _palette.background;
    Widget refsCell() {
      final lineTip = selected && refs.isEmpty
          ? _deletedBranchTipSha(row.branch)
          : null;
      final cell = _refsCell(
        entry.rowIndex,
        commit,
        refs,
        rowAccentColor,
        row.branch,
        rowColor: rowColor,
        showConnector: _comparison == null,
        deletedBranchName: lineTip == null
            ? null
            : _deletedBranchNames[lineTip],
        deletedBranchLoading:
            lineTip != null && _resolvingDeletedBranchTips.contains(lineTip),
        // A commit partway down a line says which branch it sits on. The tip
        // itself already wears the chip, so it is not asked twice. A line no
        // ref points at falls back to the name memory already holds — and only
        // to that: hovering a line must never start a lookup.
        lineName: (selected || hovered) && refs.isEmpty
            ? _branchLineNames[row.branch] ?? _knownDeletedLineName(row.branch)
            : null,
      );
      if (mergeConflict) {
        return KeyedSubtree(
          key: const Key('virtual-merge-conflict-chip'),
          child: cell,
        );
      }
      if (previewKind == PreviewGraphNodeKind.virtualMerge) {
        return KeyedSubtree(
          key: const Key('virtual-preview-chip'),
          child: cell,
        );
      }
      if (previewKind == PreviewGraphNodeKind.virtualRebase) {
        return KeyedSubtree(
          key: Key('virtual-rebase-chip-${commit.sha}'),
          child: cell,
        );
      }
      if (virtualRebaseMerge) {
        return KeyedSubtree(
          key: const Key('virtual-rebase-merge-chip'),
          child: cell,
        );
      }
      return cell;
    }

    final merge = commit.parents.length >= 2 && !commit.isWorkingTree;
    // Shrink stages: full spacing while the cell fits every lane, compressed
    // spacing below that, one collapsed lane at the narrowest.
    final painter = _painterFor(
      entry,
      index,
      graphWidth,
      selected && !virtualPreview,
      refs.isNotEmpty && _comparison == null,
      committerColor: previewColor,
      outgoingRailColor: commonBoundary ? _palette.muted : null,
    );
    // Nodes keep their size at every width; only the overhang clips.
    const avatarSize = CommitGraphPainter.avatarDiameter;
    // The author/committer stack reaches 45% further right than one disc, so it
    // only shows while that stays clear of the next lane's rail.
    final stacked =
        avatarSize * 0.95 <= painter.laneSpacing - CommitGraphPainter.railWidth;
    final mappings = _previewGraph?.mappings ?? const <RebaseGraphMapping>[];
    final content = MouseRegion(
      onEnter: (_) => _hoverIndex.value = index,
      onExit: (_) {
        if (_hoverIndex.value == index) _hoverIndex.value = -1;
      },
      child: GestureDetector(
        key: rebaseConflict
            ? const Key('rebase-conflict-current-row')
            : rebaseApplying
            ? const Key('rebase-apply-current-row')
            : selected
            ? Key('selected-row-${commit.sha}')
            : null,
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(index),
        onSecondaryTapDown: (details) =>
            unawaited(_showCommitMenu(commit, details.globalPosition)),
        child: Container(
          key: mergeConflict
              ? const Key('virtual-merge-conflict-row')
              : previewKind == PreviewGraphNodeKind.virtualMerge
              ? const Key('virtual-preview-row')
              : virtualRebaseMerge
              ? const Key('virtual-rebase-merge-row')
              : previewKind == PreviewGraphNodeKind.virtualRebase
              ? Key('virtual-rebase-row-${commit.sha}')
              : null,
          color: rowColor,
          child: Stack(
            children: [
              if (virtualPreview)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: ColoredBox(color: previewColor),
                ),
              if (selected && !rebaseConflict)
                Positioned(
                  left: _w('refs') + painter.laneX(row.lane),
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: ColoredBox(
                    key: Key('selection-band-${commit.sha}'),
                    color: _timelineSelectionColor,
                  ),
                ),
              Row(
                children: [
                  selected
                      ? ValueListenableBuilder<int>(
                          valueListenable: _deletedBranchRevision,
                          builder: (_, _, _) => refsCell(),
                        )
                      : refsCell(),
                  _graphCell(
                    Key('graph-painter-${entry.rowIndex}'),
                    painter,
                    graphWidth,
                    cellKey: Key('graph-cell-${entry.rowIndex}'),
                    overlay: mappings.isEmpty
                        ? null
                        : Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: RebaseMappingPainter(
                                  rows: _comparisonRows,
                                  entries: _entries,
                                  selectedIndex: _selectedIndex,
                                  mappings: mappings,
                                  rowIndex: index,
                                  laneSpacing: painter.laneSpacing,
                                  compact: painter.compact,
                                ),
                              ),
                            ),
                          ),
                    node:
                        commit.isWorkingTree ||
                            (merge &&
                                previewKind !=
                                    PreviewGraphNodeKind.virtualMerge &&
                                !virtualRebaseMerge)
                        ? null
                        : _graphNode(
                            commit: commit,
                            kind: previewKind,
                            painter: painter,
                            row: row,
                            size: avatarSize,
                            stacked: stacked,
                            branchColor: previewColor,
                            conflict: mergeConflict,
                          ),
                  ),
                  _cell(
                    _w('hash'),
                    _searchableHash(
                      commit,
                      commit.isWorkingTree ? '·······' : commit.shortSha,
                      style: _TimelineScreenState._hashStyle.copyWith(
                        color: selected ? _palette.text : hashRed,
                      ),
                    ),
                    leftBorder: previewColor,
                    ruleKey: Key('hash-rule-${entry.rowIndex}'),
                  ),
                  _cell(
                    commitWidth,
                    Row(
                      children: [
                        if (progress != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: progress.color.withValues(
                                alpha: virtualRebaseMerge ? 0.28 : 0.2,
                              ),
                              border: virtualRebaseMerge
                                  ? Border.all(color: const Color(0xFF9D79D0))
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              progress.text,
                              style: TextStyle(
                                color: progress.textColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: _searchableSubject(
                            commit.subject,
                            style: TextStyle(
                              color: _palette.text,
                              fontFamily: _fontFamily,
                              fontSize: _baseFontSize,
                            ),
                          ),
                        ),
                        // 배지 묶음도 제목과 같은 flex 몫을 받는다 — 열이 좁아지면
                        // 배지가 줄어들 뿐, 행이 넘치는 일은 구조적으로 없다.
                        if (badges.isNotEmpty)
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                for (final badge in badges)
                                  Flexible(
                                    child: _tooltip(
                                      badge.tooltip,
                                      _rowBadge(
                                        key: Key(
                                          'commit-${badge.id}-'
                                          '${commit.sha}',
                                        ),
                                        text: badge.text,
                                        color: badge.color,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_showTime)
                    _cell(
                      _w('time'),
                      // The cell reads socially; the tooltip gives the exact moment.
                      _tooltip(
                        synthetic
                            ? null
                            : exactCommitTime(commit.committerTimestamp),
                        Text(
                          commit.isWorkingTree
                              ? 'working tree'
                              : virtualMerge || virtualRebaseMerge
                              ? '—'
                              : _socialTime(commit.committerTimestamp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? _palette.text : _palette.muted,
                            fontFamily: _fontFamily,
                            fontSize: _supportingFontSize,
                          ),
                        ),
                      ),
                    ),
                  if (_showName)
                    _cell(
                      _w('name'),
                      synthetic
                          ? Text(
                              '—',
                              style: TextStyle(
                                color: _palette.muted,
                                fontFamily: _fontFamily,
                                fontSize: _supportingFontSize,
                              ),
                            )
                          // The graph node already wears this commit's avatar,
                          // so the author cell spends its width on the name.
                          : Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    commit.author.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: selected
                                          ? _palette.text
                                          : Color.lerp(
                                              _palette.text,
                                              mainAccent,
                                              0.12,
                                            ),
                                      fontFamily: _fontFamily,
                                      fontSize: _supportingFontSize,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final focusableContent = rebaseConflict
        ? KeyedSubtree(key: _rebaseConflictRowContextKey, child: content)
        : rebaseApplying
        ? KeyedSubtree(key: _rebaseApplyRowContextKey, child: content)
        : content;
    if (!_canCherryPick(commit)) return focusableContent;
    return Draggable<GitCommit>(
      data: commit,
      affinity: Axis.horizontal,
      feedback: Material(
        color: _palette.raised,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(commit.subject, style: TextStyle(color: _palette.text)),
        ),
      ),
      child: focusableContent,
    );
  }

  Widget _graphNode({
    required GitCommit commit,
    required PreviewGraphNodeKind? kind,
    required CommitGraphPainter painter,
    required GraphRow row,
    required double size,
    required bool stacked,
    required Color branchColor,
    bool conflict = false,
  }) {
    Color? mappingColor;
    for (final mapping in _previewGraph?.mappings ?? const []) {
      if (mapping.originalSha == commit.sha ||
          mapping.rewrittenSha == commit.sha) {
        mappingColor = mapping.color;
        break;
      }
    }
    final child = kind == PreviewGraphNodeKind.virtualMerge && conflict
        ? _virtualNode(
            key: const Key('virtual-merge-conflict-node'),
            size: size,
            fill: previewConflict,
            ring: const Color(0xFFFFB8BD),
            ringWidth: 2,
            child: const Text(
              '!',
              style: TextStyle(
                color: Color(0xFF4D1118),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          )
        : kind == PreviewGraphNodeKind.virtualMerge
        ? _virtualNode(
            key: const Key('virtual-merge-node'),
            size: size,
            fill: previewPurple,
            ring: _palette.background,
            ringWidth: 2,
            child: const Text(
              'VM',
              style: TextStyle(
                color: Colors.black,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : kind == PreviewGraphNodeKind.virtualRebaseMerge
        ? _virtualNode(
            key: const Key('virtual-rebase-merge-node'),
            size: size,
            fill: previewPurplePanel,
            ring: previewPurple,
            ringWidth: 2,
            child: const Text(
              'VM',
              style: TextStyle(
                color: previewPurple,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : kind == PreviewGraphNodeKind.virtualRebase
        ? _virtualNode(
            key: Key('virtual-rebase-node-${commit.sha}'),
            size: size,
            fill: const Color(0xFF8D6BB8),
            ring: mappingColor ?? const Color(0xFFB78BEF),
            ringWidth: _rebaseMappingAvatarBorderWidth,
            child: const Text(
              'VR',
              style: TextStyle(
                color: Colors.black,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : kind == PreviewGraphNodeKind.conflictTarget
        ? Container(
            key: const Key('rebase-conflict-target-node'),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _palette.background,
              border: Border.all(color: previewPurple, width: 1),
            ),
          )
        : mappingColor == null
        ? CommitAvatarStack(
            commit: commit,
            avatarService: widget.avatarService,
            showRemoteAvatars: widget.showRemoteAvatars,
            size: size,
            stacked: stacked,
            discColor: branchColor,
            fontFamily: _fontFamily,
            fontScale: _initialsFontScale,
          )
        : Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: mappingColor,
                width: _rebaseMappingAvatarBorderWidth,
              ),
            ),
            // No branch ring inside this one: the border already colors the
            // node, and a second ring would leave 8px of face for the initials.
            child: CommitAvatarStack(
              commit: commit,
              avatarService: widget.avatarService,
              showRemoteAvatars: widget.showRemoteAvatars,
              size: size - _rebaseMappingAvatarBorderWidth * 2,
              stacked: stacked,
              fontFamily: _fontFamily,
              fontScale: _initialsFontScale,
            ),
          );
    return Positioned(
      left: painter.laneX(row.lane) - size / 2,
      top: (TimelineScreen.rowHeight - size) / 2,
      child: child,
    );
  }

  /// One chip per row: the first ref, plus a `+N` badge when the row carries
  /// more. The full list belongs to the floating modal the selected row shows.
  /// No bottom hairline here — the rules start at the hash column.
  Widget _refsCell(
    int index,
    GitCommit commit,
    List<GitRef> refs,
    Color color,
    int branch, {
    required Color rowColor,
    bool showConnector = true,
    String? deletedBranchName,
    bool deletedBranchLoading = false,
    String? lineName,
  }) {
    // The branch a row merely sits on wears the same chip its tip does, only
    // dimmed — same shape, same colour, a fraction of the weight — so the two
    // read as one vocabulary rather than two.
    final dim = refs.isEmpty && deletedBranchName == null && lineName != null;
    final shownRefs = dim ? [GitRef(name: lineName)] : refs;
    // The loop below reuses the name `index` for the chip slot.
    final cellIndex = index;
    return SizedBox(
      key: Key('refs-cell-$index'),
      width: _w('refs'),
      child: shownRefs.isEmpty
          ? deletedBranchLoading
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '브랜치 이름 찾는 중…',
                        key: Key('deleted-branch-loading-${commit.sha}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _palette.muted, fontSize: 11),
                      ),
                    ),
                  )
                : deletedBranchName != null
                ? _deletedBranchLabel(commit, deletedBranchName, color)
                : null
          : LayoutBuilder(
              builder: (context, constraints) {
                // Chips split the cell evenly, each keeping at least 40px, and
                // whatever no longer fits simply does not show.
                const inset = _TimelineScreenState._refsCellInset;
                final width = constraints.maxWidth - inset * 2;
                final slots = math.max(1, (width / _minChipWidth).floor());
                final shown = shownRefs.take(slots).toList();
                final slot = width / shown.length;
                return Stack(
                  children: [
                    for (var index = 0; index < shown.length; index++)
                      Positioned(
                        left: inset + index * slot,
                        top:
                            (TimelineScreen.rowHeight -
                                _TimelineScreenState._rowChipHeight) /
                            2,
                        width: slot,
                        height: _TimelineScreenState._rowChipHeight,
                        child: _refChip(
                          commit,
                          shown[index],
                          color,
                          rowColor: rowColor,
                          paletteIndex: _comparison == null && index == 0
                              ? _branchPaletteIndexes[branch]
                              : null,
                          dim: dim,
                          key: dim ? Key('row-branch-name-$cellIndex') : null,
                        ),
                      ),
                    // No arrow for a dimmed chip: nothing points at this row.
                    if (showConnector && !dim)
                      Positioned(
                        key: Key('ref-chip-connector-${commit.sha}'),
                        left: constraints.maxWidth - inset,
                        right: 0,
                        top: (TimelineScreen.rowHeight - 1) / 2,
                        height: 1,
                        child: ColoredBox(color: color),
                      ),
                  ],
                );
              },
            ),
    );
  }

  /// Wide enough for the longest ref in full, capped by the timeline viewport.
  double _refsModalWidth(List<GitRef> refs) {
    var longest = 0.0;
    for (final ref in refs) {
      final glyph = ref.isHead || ref.isTag
          ? _TimelineScreenState._refGlyphWidth
          : 0.0;
      longest = math.max(
        longest,
        _textWidth(ref.name, _refNameStyle(_palette.text)) + glyph,
      );
    }
    // accent bar, its gap, the copy button with its gaps, and the box padding.
    return math.min(
      longest + 2 + 7 + 6 + 16 + 4 + 16,
      _timelineViewportWidth - 16,
    );
  }

  /// The floating list of every ref on the selected row. It sits above the row
  /// when the cursor arrived heading down and below it heading up — a click has
  /// no direction, so it takes whichever side has more room — stays inside the
  /// viewport, and vanishes with the selection or when the row scrolls away.
  Widget _refsModal(double viewportHeight) {
    final index = _selectedIndex.value;
    if (index >= _entries.length || _entries[index].rowIndex < 0) {
      return const SizedBox.shrink();
    }
    final row = _entries[index].row;
    final refs = _rowRefs(row.commit);
    final offset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final rowTop = index * TimelineScreen.rowHeight - offset;
    final rowBottom = rowTop + TimelineScreen.rowHeight;
    if (refs.length < 2 || rowBottom <= 0 || rowTop >= viewportHeight) {
      return const SizedBox.shrink();
    }
    final color = AvatarService.branchColor(row.branch);
    final height = refs.length * 24.0 + 8;
    final width = _refsModalWidth(refs);
    final above = _arrivedGoingDown ?? rowTop > viewportHeight - rowBottom;
    final double top = (above ? rowTop - height - 4 : rowBottom + 4).clamp(
      0.0,
      math.max(0.0, viewportHeight - height),
    );
    return Stack(
      children: [
        Positioned(
          key: const Key('refs-modal'),
          left: 8,
          top: top,
          width: width,
          // Only the box takes pointers; the rest of the overlay stays through.
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: _palette.raised,
              border: Border.all(color: _palette.border),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var refIndex = 0; refIndex < refs.length; refIndex++)
                  Builder(
                    builder: (context) {
                      final ref = refs[refIndex];
                      final refColor = _comparison == null
                          ? refPaletteColorsAt(
                              refIndex == 0
                                  ? _branchPaletteIndexes[row.branch] ?? 0
                                  : refPaletteIndexForName(
                                      ref.name,
                                      widget.refPaletteAssignments,
                                    ),
                              widget.refPalette,
                            ).text
                          : color;
                      return SizedBox(
                        height: 24,
                        child: Row(
                          children: [
                            // A straight 2px bar, no rounding.
                            Container(
                              key: Key('modal-accent-${ref.name}'),
                              width: 2,
                              height: 20,
                              color: refColor,
                            ),
                            const SizedBox(width: 7),
                            _refGlyph(ref, refColor, false),
                            _refName(ref, refColor, false, ellipsis: false),
                            const SizedBox(width: 6),
                            CopyButton(text: ref.name, color: refColor),
                            const SizedBox(width: 4),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 커밋 행 오른쪽 배지. 근거가 도착하기 전에는 이 위젯 자체가 없으니 자리도
  /// 차지하지 않는다.
  Widget _rowBadge({
    required Key key,
    required String text,
    required Color color,
    Color? textColor,
  }) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor ?? color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  /// The hash column's rule is the only line in a row: a 1px hairline stopping
  /// 1px short top and bottom so stacked rows read apart.
  Widget _cell(double width, Widget child, {Color? leftBorder, Key? ruleKey}) {
    final cell = Container(
      width: width,
      padding: EdgeInsets.only(
        left: leftBorder == null
            ? _TimelineScreenState._columnTextInset
            : _TimelineScreenState._railedColumnTextInset,
        right: _TimelineScreenState._columnTextInset,
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
    if (leftBorder == null) return cell;
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          cell,
          Positioned(
            key: ruleKey,
            left: 0,
            top: 1,
            bottom: 1,
            width: 1,
            child: ColoredBox(color: leftBorder),
          ),
        ],
      ),
    );
  }
}
