part of 'timeline.dart';

/// The preview panel: its header, the commit it names, the files it lists, the
/// identities it shows, and the adjacent diff the branch preview still draws.

extension _TimelinePreviewPane on _TimelineScreenState {
  void _showPreviewDiff(GitCommit commit, String path) {
    if (_fullDiffOpen) {
      _showFullDiffFile(path);
    } else {
      // The preview keeps the keyboard so its own arrows keep walking files.
      _openFullDiff(commit, path, focusDiff: false);
    }
  }

  double _previewDiffExtent(PreviewPlacement placement, double available) {
    _maxPreviewDiffExtent = available;
    final saved = switch (placement) {
      PreviewPlacement.left => _previewDiffLeftWidth,
      PreviewPlacement.right => _previewDiffRightWidth,
      PreviewPlacement.bottom => _previewDiffBottomHeight,
      PreviewPlacement.closed => null,
    };
    _visiblePreviewDiffExtent = _previewDiffOpen
        ? (saved ?? math.max(0.0, available - 100)).clamp(0.0, available)
        : 0.0;
    return _visiblePreviewDiffExtent;
  }

  bool _canCherryPick(GitCommit commit) {
    if (_cherryPickBusy ||
        _cherryPickState != null ||
        _refs.current == null ||
        commit.isWorkingTree ||
        commit.sha == _refs.localTips[_refs.current]) {
      return false;
    }
    final comparison = _comparison;
    if (comparison == null) return true;
    if (_previewGraph?.kinds.containsKey(commit.sha) == true) return false;
    return comparison.commits
            .firstWhere((entry) => entry.commit.sha == commit.sha)
            .side ==
        BranchCommitSide.compareOnly;
  }

  /// 선택된 커밋이 행에서 달고 있는 라벨을 미리보기 판 머리에도 같은 문구·색으로
  /// 올린다. 라벨이 없는 평범한 커밋이면 위젯 자체가 없다.
  Widget _previewCommitLabels(GitCommit commit) {
    final progress = _commitProgressLabel(commit);
    final badges = _commitBadges(commit);
    if (progress == null && badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Wrap(
        runSpacing: 3,
        children: [
          if (progress != null)
            _rowBadge(
              key: Key('preview-commit-progress-${commit.sha}'),
              text: progress.text,
              color: progress.color,
              textColor: progress.textColor,
            ),
          for (final badge in badges)
            _tooltip(
              badge.tooltip,
              _rowBadge(
                key: Key('preview-commit-${badge.id}-${commit.sha}'),
                text: badge.text,
                color: badge.color,
              ),
            ),
        ],
      ),
    );
  }

  Widget _preview() => ValueListenableBuilder<int>(
    valueListenable: _selectedIndex,
    builder: (context, _, _) => _previewFor(_selectedCommit),
  );

  /// Drags the panel's inner edge. The stored size is what the open/close tween
  /// targets, so resizing and animating stay in step.
  Widget _previewResizer(PreviewPlacement placement) {
    final vertical = placement == PreviewPlacement.bottom;
    final handle = MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const Key('preview-resizer'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: vertical
            ? null
            : (details) => _rebuild(() {
                final delta = placement == PreviewPlacement.right
                    ? -details.delta.dx
                    : details.delta.dx;
                _previewWidth = (_previewWidth + delta).clamp(
                  _TimelineScreenState._previewMinWidth,
                  MediaQuery.sizeOf(context).width *
                      _TimelineScreenState._previewMaxWidthFraction,
                );
              }),
        onHorizontalDragEnd: vertical ? null : (_) => _savePreviewSize(),
        onVerticalDragUpdate: vertical
            ? (details) => _rebuild(() {
                _previewHeight = (_previewHeight - details.delta.dy).clamp(
                  math.min(
                    _TimelineScreenState._previewMinHeight,
                    _bottomPreviewMaxHeight,
                  ),
                  _bottomPreviewMaxHeight,
                );
              })
            : null,
        onVerticalDragEnd: vertical ? (_) => _savePreviewSize() : null,
      ),
    );
    return vertical
        ? Positioned(left: 0, right: 0, top: 0, height: 8, child: handle)
        : Positioned(
            left: placement == PreviewPlacement.right ? 0 : null,
            right: placement == PreviewPlacement.left ? 0 : null,
            top: 0,
            bottom: 0,
            width: 8,
            child: handle,
          );
  }

  Widget _previewFor(GitCommit? commit) {
    final placement = _previewController.previewPlacement;
    return Container(
      key: const Key('preview-surface'),
      decoration: BoxDecoration(
        color: _palette.surface,
        border: Border(
          left: placement == PreviewPlacement.right
              ? BorderSide(color: _palette.border)
              : BorderSide.none,
          right: placement == PreviewPlacement.left
              ? BorderSide(color: _palette.border)
              : BorderSide.none,
          top: placement == PreviewPlacement.bottom
              ? BorderSide(color: _palette.border)
              : BorderSide.none,
        ),
      ),
      // Everything in here is text worth copying; taps still reach the buttons.
      child: Stack(
        children: [
          Focus(
            focusNode: _previewFocusNode,
            onKeyEvent: _onPreviewKeyEvent,
            child: SelectionArea(
              onSelectionChanged: (selection) =>
                  debugPreviewSelection = selection?.plainText,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _previewHeader(commit),
                  if (!_usesBranchPreviewResult(commit))
                    Container(
                      key: const Key('preview-shortcut-hint'),
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _cherryPickState == null
                            ? '파일 이동 ⌘↑/↓ · 화면 스크롤 ⇧⌘↑/↓'
                            : '충돌 파일을 해결한 뒤 계속할 수 있습니다',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _palette.muted,
                          fontSize: 10,
                          fontFamily: technicalFontFamily,
                          fontFamilyFallback: technicalFontFallback,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _cherryPickState != null
                        ? _cherryPickPanel()
                        : commit == null
                        ? Center(
                            child: Text(
                              'No commit selected',
                              style: TextStyle(
                                color: _palette.muted,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : _previewBody(commit),
                  ),
                ],
              ),
            ),
          ),
          _previewResizer(placement),
        ],
      ),
    );
  }

  Widget _previewHeader(GitCommit? commit) {
    final branchPreview = _usesBranchPreviewResult(commit);
    final branchTitle = _branchPreviewMode == BranchPreviewMode.merge
        ? _branchPreviewHasConflict
              ? 'Merge 충돌 해결'
              : '가상 병합 커밋'
        : _branchPreviewHasConflict
        ? 'Rebase 상태 및 결정'
        : '가상 리베이스 결과';
    final branchStatus = _branchPreviewHasConflict
        ? _branchPreviewMode == BranchPreviewMode.merge
              ? '파일 ${_mergePreview?.conflictFiles.length ?? _comparison?.merge.files.length ?? 0}개'
              : '충돌 커밋에 포커스'
        : switch (_branchApplyStatus) {
            BranchApplyStatus.applying => '적용 중',
            BranchApplyStatus.applied => '적용 완료',
            BranchApplyStatus.reverting => '되돌리는 중',
            BranchApplyStatus.reverted => '되돌리기 완료',
            BranchApplyStatus.failed => '작업 실패',
            BranchApplyStatus.idle => '아직 적용하지 않음',
          };
    final namesCommit =
        !branchPreview && _cherryPickState == null && commit != null;
    return Container(
      key: const Key('preview-header'),
      height: 36,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _palette.border)),
      ),
      child: namesCommit
          ? _previewCommitLine(commit)
          : Row(
              children: [
                Expanded(
                  child: Text(
                    _cherryPickState != null
                        ? '체리픽 충돌'
                        : branchPreview
                        ? branchTitle
                        : '선택한 커밋의 diff',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: branchPreview ? _palette.text : _palette.muted,
                      fontSize: 12,
                      fontWeight: branchPreview
                          ? FontWeight.w700
                          : FontWeight.w500,
                      letterSpacing: branchPreview ? 0 : 0.66,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (branchPreview)
                  Text(
                    branchStatus,
                    style: TextStyle(color: _palette.muted, fontSize: 10),
                  ),
              ],
            ),
    );
  }

  /// `커밋 <7자리> ⧉ · 부모 <7자리> <부모 제목>`. The hashes and the parent's
  /// subject are the header now: Full Diff still opens from ⌘D, the toolbar and
  /// any file in the list.
  Widget _previewCommitLine(GitCommit commit) {
    final parentSha = commit.parents.isEmpty ? null : commit.parents.first;
    final label = TextStyle(color: _palette.muted, fontSize: 10);
    final mono = TextStyle(
      fontFamily: technicalFontFamily,
      fontFamilyFallback: technicalFontFallback,
      fontSize: 12,
      color: commit.isWorkingTree ? _palette.muted : hashRed,
    );
    return Row(
      children: [
        Text('커밋', style: label),
        const SizedBox(width: 6),
        Text(
          commit.isWorkingTree ? 'WIP' : commit.shortSha,
          key: commit.isWorkingTree
              ? const Key('preview-working-tree')
              : const Key('preview-sha'),
          style: mono,
        ),
        if (!commit.isWorkingTree) ...[
          const SizedBox(width: 6),
          SelectionContainer.disabled(
            child: KeyedSubtree(
              key: const Key('preview-sha-copy'),
              // Seven characters read; the whole hash is what pastes.
              child: CopyButton(
                text: commit.sha,
                color: hashRed,
                slot: 'preview-sha',
              ),
            ),
          ),
        ],
        const SizedBox(width: 6),
        Text('·', style: label),
        const SizedBox(width: 6),
        Expanded(
          child: parentSha == null
              ? Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '부모 ', style: label),
                      TextSpan(
                        text: '루트 커밋',
                        style: TextStyle(color: _palette.muted, fontSize: 11),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : PreviewParent(
                  key: const Key('preview-parent'),
                  shas: commit.parents,
                  commitOf: _commitBySha,
                  loadMessage: _commitMessageFor,
                  hashColor: hashRed,
                ),
        ),
      ],
    );
  }

  Widget _cherryPickPanel() {
    final state = _cherryPickState!;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${state.conflicts.length}개 충돌 파일',
            style: TextStyle(
              color: _palette.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: state.conflicts.isEmpty
                ? Center(
                    child: Text(
                      '모든 충돌 파일이 해결되었습니다.',
                      style: TextStyle(color: _palette.muted, fontSize: 12),
                    ),
                  )
                : ListView(
                    children: [
                      for (final path in state.conflicts)
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            dense: true,
                            selected: path == _selectedConflictPath,
                            selectedColor: _palette.text,
                            selectedTileColor: _palette.neutralChip,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            onTap: () =>
                                _rebuild(() => _selectedConflictPath = path),
                            title: Text(
                              path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                            trailing: Text(
                              '해결 필요',
                              style: TextStyle(
                                color: behindOrange,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          if (_cherryPickError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _cherryPickError.toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: behindOrange, fontSize: 11),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const Key('cherry-pick-open-editor'),
                onPressed: _cherryPickBusy || _selectedConflictPath == null
                    ? null
                    : () => unawaited(_openConflictEditor()),
                child: const Text('편집기로 열기'),
              ),
              TextButton(
                key: const Key('cherry-pick-abort'),
                onPressed: _cherryPickBusy
                    ? null
                    : () => unawaited(_confirmAbortCherryPick()),
                child: const Text('체리픽 중단'),
              ),
              FilledButton(
                key: const Key('cherry-pick-continue'),
                onPressed: !_cherryPickBusy && state.canContinue
                    ? () => unawaited(_continueCherryPick())
                    : null,
                child: const Text('계속'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _previewKey(GitCommit commit) {
    final range = _usesBranchPreviewResult(commit) ? _branchPreviewRange : null;
    return range == null
        ? commit.sha
        : '${_branchPreviewMode.name}:${range.from}..${range.to}';
  }

  /// Steps the open preview through the commit's files, clamped at both ends.
  void _stepPreviewFile(int delta, {bool animate = true}) {
    final commit = _selectedCommit;
    if (commit == null) return;
    final key = _previewKey(commit);
    final files = _previewFileLists[key];
    if (files == null || files.isEmpty) return;
    final current = _previewPaths[key] ?? files.first.path;
    final index = files.indexWhere((file) => file.path == current);
    final next = (index + delta).clamp(0, files.length - 1);
    if (files[next].path == current) return;
    _selectPreviewFile(
      commit,
      files[next].path,
      revealDirection: delta,
      animateReveal: animate,
    );
  }

  void _selectPreviewFile(
    GitCommit commit,
    String path, {
    int? revealDirection,
    bool animateReveal = true,
    int? line,
  }) {
    final adjacent = _showsBranchPreviewDiff(commit);
    _rebuild(() {
      _previewPaths[_previewKey(commit)] = path;
      _previewDiffOpen = adjacent;
      if (adjacent) {
        // 파일 줄을 그냥 누르면 위에서부터, 근접 구역을 누르면 그 줄에서 시작한다.
        _previewDiffLineTarget = line == null ? null : (path: path, line: line);
        // 같은 구역을 다시 누르면 diff가 맨 위로 돌아가니 한 번 더 데려다줘야 한다.
        if (line != null) _previewDiffLineRevealed = null;
      }
    });
    if (!adjacent) {
      if (_fullDiffOpen) {
        _showFullDiffFile(path);
      } else {
        _openFullDiff(commit, path);
      }
    } else {
      _focusNode.requestFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final outerOffset = _previewFilesScrollController.hasClients
          ? _previewFilesScrollController.offset
          : null;
      if (adjacent && _previewDiffScrollController.hasClients) {
        _previewDiffScrollController.jumpTo(0);
      }
      if (outerOffset != null && _previewFilesScrollController.hasClients) {
        _previewFilesScrollController.jumpTo(
          outerOffset.clamp(
            _previewFilesScrollController.position.minScrollExtent,
            _previewFilesScrollController.position.maxScrollExtent,
          ),
        );
      }
      if (revealDirection != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _revealSelectedPreviewFile(revealDirection, animate: animateReveal);
          }
        });
      }
    });
  }

  ScrollController? _previewPageScrollController(int direction) {
    bool canScroll(ScrollController controller) {
      if (!controller.hasClients) return false;
      final position = controller.position;
      return direction > 0
          ? position.extentAfter > 0
          : position.extentBefore > 0;
    }

    if (_previewDiffOpen && canScroll(_previewDiffScrollController)) {
      return _previewDiffScrollController;
    }
    if (canScroll(_previewFilesScrollController)) {
      return _previewFilesScrollController;
    }
    return null;
  }

  void _revealSelectedPreviewFile(int direction, {required bool animate}) {
    final selectedContext = _selectedPreviewFileKey.currentContext;
    if (selectedContext == null) {
      if (_previewFilesScrollController.hasClients &&
          _previewFilesScrollController.position.pixels >
              _previewFilesScrollController.position.minScrollExtent) {
        _previewFilesScrollController.jumpTo(0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _revealSelectedPreviewFile(direction, animate: animate);
          }
        });
      }
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        selectedContext,
        duration: animate ? const Duration(milliseconds: 100) : Duration.zero,
        curve: Curves.easeOut,
        alignmentPolicy: direction < 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ),
    );
  }

  Widget _previewBody(GitCommit commit) {
    final branchPreview = _usesBranchPreviewResult(commit);
    final files = _previewFilesFor(commit);
    return FutureBuilder<List<GitFileChange>>(
      key: branchPreview ? null : ValueKey(commit.sha),
      future: files,
      builder: (context, snapshot) {
        final changes = snapshot.data;
        final key = _previewKey(commit);
        // Nothing is chosen until the panel has actually been walked into: a
        // highlight on a pane the keyboard never visited reads as focus.
        final requestedPath = _previewPaths[key];
        GitFileChange? selectedFile;
        if (requestedPath != null && changes != null && changes.isNotEmpty) {
          selectedFile = changes.firstWhere(
            (file) => file.path == requestedPath,
            orElse: () => changes.first,
          );
        }
        final selectedPath = selectedFile?.path;
        final info = Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _previewCommitLabels(commit),
              if (!branchPreview) ...[
                Text(
                  commit.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (!commit.isWorkingTree)
                  FutureBuilder<String>(
                    future: _previewMessageFor(commit),
                    builder: (context, snapshot) {
                      final body = _commitMessageBody(snapshot.data);
                      if (body.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        // Ten lines is as much room as a message earns here;
                        // past that it scrolls in place instead of pushing the
                        // file list off the panel.
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight:
                                _previewMessageLines * _previewMessageLine,
                          ),
                          // Always drawn while there is more message than
                          // room — a bar that fades out leaves the rest of the
                          // message looking like the whole of it. Flutter
                          // hides it on its own when nothing can scroll.
                          child: Scrollbar(
                            controller: _previewMessageScrollController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              key: const Key('preview-commit-body-scroll'),
                              controller: _previewMessageScrollController,
                              primary: false,
                              child: Text(
                                body,
                                key: const Key('preview-commit-body'),
                                style: TextStyle(
                                  color: _palette.text,
                                  fontSize: 12,
                                  height: _previewMessageLine / 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
              if (branchPreview && _branchPreviewHasConflict) ...[
                _branchPreviewConflictStatusCard(),
                _branchPreviewSafeWorkspace(),
              ],
              if (branchPreview && _branchPreviewResolutionComplete)
                _branchPreviewResolutionCard(),
              if (branchPreview && _branchPreviewDropped)
                _branchPreviewDroppedCard(),
              if (branchPreview &&
                  _branchPreviewReady &&
                  !_branchPreviewResolutionComplete)
                _branchPreviewApplyCard(),
              if (branchPreview &&
                  !_branchPreviewHasConflict &&
                  (_branchPreviewMode == BranchPreviewMode.merge
                          ? _mergePreviewError
                          : _rebasePreviewError) !=
                      null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    (_branchPreviewMode == BranchPreviewMode.merge
                            ? _mergePreviewError
                            : _rebasePreviewError)
                        .toString(),
                    style: const TextStyle(color: behindOrange, fontSize: 10),
                  ),
                ),
              if (!branchPreview) _previewPerson(commit),
              _previewStats(changes),
              KeyedSubtree(
                key:
                    _branchPreviewMode == BranchPreviewMode.rebase &&
                        _rebasePreview?.status == RebasePreviewStatus.conflict
                    ? const Key('rebase-conflict-files')
                    : null,
                child: _previewFileList(
                  commit,
                  changes,
                  snapshot.hasError,
                  selectedPath,
                ),
              ),
            ],
          ),
        );
        // One box, one scroll view. A NestedScrollView used to hold this, and
        // its empty body let the header scroll clean off the panel even when
        // everything already fit.
        return SingleChildScrollView(
          key: const Key('preview-content-scroll'),
          controller: _previewFilesScrollController,
          child: KeyedSubtree(
            key: const Key('preview-files-scroll'),
            child: info,
          ),
        );
      },
    );
  }

  Widget _previewDiffResizer(PreviewPlacement placement) {
    final vertical = placement == PreviewPlacement.bottom;
    final handle = MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      onEnter: vertical
          ? null
          : (_) => _rebuild(() => _previewDiffResizerHovered = true),
      onExit: vertical
          ? null
          : (_) => _rebuild(() => _previewDiffResizerHovered = false),
      child: GestureDetector(
        key: const Key('preview-diff-resizer'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: vertical
            ? null
            : (details) => _rebuild(() {
                final delta = placement == PreviewPlacement.right
                    ? -details.delta.dx
                    : details.delta.dx;
                _setPreviewDiffExtent(
                  placement,
                  ((_storedPreviewDiffExtent(placement) ??
                              _visiblePreviewDiffExtent) +
                          delta)
                      .clamp(0.0, _maxPreviewDiffExtent),
                );
              }),
        onHorizontalDragEnd: vertical
            ? null
            : (_) => _savePreviewDiffExtent(placement),
        onVerticalDragUpdate: vertical
            ? (details) => _rebuild(
                () => _setPreviewDiffExtent(
                  placement,
                  ((_storedPreviewDiffExtent(placement) ??
                              _visiblePreviewDiffExtent) -
                          details.delta.dy)
                      .clamp(0.0, _maxPreviewDiffExtent),
                ),
              )
            : null,
        onVerticalDragEnd: vertical
            ? (_) => _savePreviewDiffExtent(placement)
            : null,
        child: vertical
            ? const SizedBox.expand()
            : Align(
                alignment: placement == PreviewPlacement.right
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: ColoredBox(
                  key: const Key('preview-diff-hover-line'),
                  color: _previewDiffResizerHovered
                      ? const Color(0xFF5AB0FF)
                      : Colors.transparent,
                  child: const SizedBox(width: 2, height: double.infinity),
                ),
              ),
      ),
    );
    return vertical
        ? Positioned(left: 0, right: 0, top: 0, height: 8, child: handle)
        : Positioned(
            left: placement == PreviewPlacement.right ? 0 : null,
            right: placement == PreviewPlacement.left ? 0 : null,
            top: 0,
            bottom: 0,
            width: 12,
            child: handle,
          );
  }

  Widget _previewPerson(GitCommit commit) {
    final separateCommitter =
        commit.author.name != commit.committer.name ||
        commit.author.email != commit.committer.email;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _palette.border),
          bottom: BorderSide(color: _palette.border),
        ),
      ),
      child: Column(
        children: [
          _previewIdentity(
            commit,
            committer: false,
            timestamp: commit.isWorkingTree
                ? null
                : separateCommitter
                ? commit.authorTimestamp
                : commit.committerTimestamp,
          ),
          if (!commit.isWorkingTree && separateCommitter) ...[
            const SizedBox(height: 10),
            _previewIdentity(
              commit,
              committer: true,
              timestamp: commit.committerTimestamp,
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewIdentity(
    GitCommit commit, {
    required bool committer,
    required int? timestamp,
  }) {
    final identity = committer ? commit.committer : commit.author;
    final role = committer ? 'Committer' : 'Author';
    final email = identity.email.trim();
    final roleLine = email.isEmpty ? role : '$role · $email';
    return Row(
      key: Key(committer ? 'preview-committer' : 'preview-author'),
      children: [
        commit.isWorkingTree
            ? Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _palette.border),
                ),
              )
            : CommitAvatarStack(
                commit: commit,
                avatarService: widget.avatarService,
                showRemoteAvatars: widget.showRemoteAvatars,
                size: 42,
                stacked: false,
                committerOnly: committer,
                discColor: AvatarService.branchColor(_branchOf(commit)),
              ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                commit.isWorkingTree ? 'Not committed' : identity.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _palette.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                commit.isWorkingTree
                    ? 'No commit object or committer'
                    : roleLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _palette.muted, fontSize: 12),
              ),
              if (timestamp != null)
                Text(
                  exactCommitTime(timestamp),
                  maxLines: 1,
                  style: TextStyle(
                    color: _palette.muted,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewStats(List<GitFileChange>? changes) {
    int total(int? Function(GitFileChange file) value) =>
        (changes ?? const []).fold(0, (sum, file) => sum + (value(file) ?? 0));
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '${changes?.length ?? 0} '
              '${changes?.length == 1 ? 'file' : 'files'} changed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _palette.muted, fontSize: 12),
            ),
          ),
          const Spacer(),
          Text(
            '+${total((file) => file.additions)}',
            style: const TextStyle(
              color: mainAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '−${total((file) => file.deletions)}',
            style: const TextStyle(
              color: hashRed,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewFileList(
    GitCommit commit,
    List<GitFileChange>? changes,
    bool failed,
    String? selectedPath,
  ) => Container(
    key: Key(
      _usesBranchPreviewResult(commit)
          ? 'branch-preview-file-list'
          : 'preview-files',
    ),
    alignment: Alignment.topLeft,
    child: failed
        ? const Center(
            child: Text(
              'Could not load files',
              style: TextStyle(color: Color(0xFFF29AB2), fontSize: 12),
            ),
          )
        : changes == null
        ? const Center(
            child: SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          )
        : changes.isEmpty
        ? Center(
            child: Text(
              'No changed files',
              style: TextStyle(color: _palette.muted, fontSize: 12),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final file in changes) ...[
                _previewFileRow(commit, file, file.path == selectedPath),
                ?_previewProximityLine(commit, file),
              ],
            ],
          ),
  );

  /// The regions themselves, under the file they belong to. Clicking one opens
  /// the same result diff a file row opens, positioned on the region.
  Widget? _previewProximityLine(GitCommit commit, GitFileChange file) {
    final regions = _previewProximity(commit, file);
    if (regions.isEmpty) return null;
    return Padding(
      key: Key('preview-proximity-${file.path}'),
      padding: const EdgeInsets.only(left: 34, right: 14, bottom: 7),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '양쪽 편집이 10줄 안에서 겹침',
            style: TextStyle(color: _palette.muted, fontSize: 10),
          ),
          for (final region in regions)
            InkWell(
              key: Key('preview-proximity-${file.path}-${region.startLine}'),
              borderRadius: BorderRadius.circular(4),
              onTap: () =>
                  _selectPreviewFile(commit, file.path, line: region.startLine),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: previewConflict.withValues(alpha: 0.10),
                  border: Border.all(
                    color: previewConflict.withValues(alpha: 0.35),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_groupedNumber(region.startLine)}~'
                  '${_groupedNumber(region.endLine)}줄',
                  style: const TextStyle(
                    color: Color(0xFFFF9AA2),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _previewProvenanceChip(
    String path,
    ({String label, bool bothSides}) provenance,
  ) {
    final color = provenance.bothSides ? previewConflict : _palette.muted;
    return Container(
      key: Key('preview-provenance-$path'),
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: provenance.bothSides
            ? color.withValues(alpha: 0.16)
            : _palette.raised,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        provenance.label,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: provenance.bothSides ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _previewFileRow(GitCommit commit, GitFileChange file, bool selected) {
    final stats = [
      if ((file.additions ?? 0) > 0) '+${file.additions}',
      if ((file.deletions ?? 0) > 0) '-${file.deletions}',
    ].join(' ');
    final stateColor = switch (file.status.isEmpty ? '' : file.status[0]) {
      'D' => deletedPink,
      'R' || 'C' => renamedPurple,
      '!' => hashRed,
      _ => mainAccent,
    };
    return SizedBox(
      key: selected ? _selectedPreviewFileKey : null,
      height: 34,
      child: InkWell(
        onTap: () => _selectPreviewFile(commit, file.path),
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? _previewSelectionColor : null,
            borderRadius: selected ? BorderRadius.circular(6) : null,
          ),
          child: Row(
            children: [
              Container(
                key: Key('preview-state-${file.path}'),
                width: 28,
                height: 20,
                alignment: Alignment.center,
                child: Text(
                  file.status,
                  maxLines: 1,
                  style: TextStyle(color: stateColor, fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _palette.text, fontSize: 12),
                ),
              ),
              if (_previewProvenance(commit, file) case final provenance?)
                _previewProvenanceChip(file.path, provenance),
              if (stats.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  stats,
                  style: TextStyle(color: _palette.muted, fontSize: 11),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewDiff(GitCommit commit, GitFileChange file) {
    final path = file.path;
    final key = _previewKey(commit);
    final future = _previewDiffs.putIfAbsent((sha: key, path: path), () {
      final comparison = _comparison;
      if (comparison == null || !_usesBranchPreviewResult(commit)) {
        return widget.repository.loadDiff(commit, file);
      }
      if (_branchPreviewHasConflict) {
        final session = _branchPreviewMode == BranchPreviewMode.merge
            ? _mergePreviewSession
            : _rebasePreviewSession;
        if (session is MergePreviewSession) {
          return session.loadConflictDiff(path);
        }
        if (session is RebasePreviewSession) {
          return session.loadConflictDiff(path);
        }
      }
      return widget.repository.loadDiffBetween(
        _branchPreviewRange!.from,
        _branchPreviewRange!.to,
        file,
      );
    });
    final comparison = _comparison;
    if (comparison == null || !_usesBranchPreviewResult(commit)) {
      final parent = commit.parents.isEmpty ? null : commit.parents.first;
      final parentLabel = parent == null
          ? '—'
          : parent.substring(0, math.min(7, parent.length));
      return _previewDiffView(
        future: future,
        file: file,
        status: commit.isWorkingTree
            ? 'WIP · diff'
            : 'commit ${commit.shortSha}',
        baseRef: parentLabel,
        baseSubject: parent == null ? '빈 트리' : '이전 상태',
        compareRef: commit.isWorkingTree ? 'WIP' : commit.shortSha,
        compareSubject: commit.isWorkingTree ? '작업 트리' : commit.subject,
        baseRole: '이전 상태',
        compareRole: '선택한 커밋',
      );
    }

    final baseCommits = comparison.commits
        .where((entry) => entry.side == BranchCommitSide.baseOnly)
        .map((entry) => entry.commit)
        .toList();
    final compareCommits = comparison.commits
        .where((entry) => entry.side == BranchCommitSide.compareOnly)
        .map((entry) => entry.commit)
        .toList();
    final base = baseCommits.isEmpty ? null : baseCommits.first;
    final compare =
        _rebasePreview?.currentCommit ??
        (compareCommits.isEmpty ? null : compareCommits.first);
    final mergeMode = _branchPreviewMode == BranchPreviewMode.merge;
    final conflict = _branchPreviewHasConflict;
    return _previewDiffView(
      future: future,
      file: file,
      status: conflict
          ? mergeMode
                ? '병합 충돌 1개 · ${comparison.compareRef} → ${comparison.baseRef}'
                : '현재 충돌 · ${compare?.subject ?? comparison.compareRef}'
          : '${mergeMode ? 'Merge' : 'Rebase'} 결과 · '
                '${comparison.compareRef} → ${comparison.baseRef}',
      baseRef: comparison.baseRef,
      baseSubject: base?.subject ?? '현재 상태',
      compareRef: comparison.compareRef,
      compareSubject: conflict
          ? compare?.subject ?? '적용할 변경'
          : '${mergeMode ? 'Merge' : 'Rebase'} 미리보기 결과',
      baseRole: '기준 브랜치',
      compareRole: conflict && _branchPreviewMode == BranchPreviewMode.rebase
          ? '적용 중'
          : conflict
          ? '비교 브랜치'
          : '가상 결과',
      conflict: conflict,
      showConflictChoices: conflict,
    );
  }

  Widget _previewDiffView({
    required Future<List<DiffLine>> future,
    required GitFileChange file,
    required String status,
    required String baseRef,
    required String baseSubject,
    required String compareRef,
    required String compareSubject,
    required String baseRole,
    required String compareRole,
    bool conflict = false,
    bool showConflictChoices = false,
  }) {
    final path = file.path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('branch-preview-diff-toolbar'),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _palette.surface,
            border: Border(bottom: BorderSide(color: _palette.border)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 80
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      Flexible(
                        child: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _palette.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: conflict ? previewConflict : deletedPink,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            key: const Key('branch-preview-layout-switch'),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: _palette.background,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _previewDiffLayoutButton(
                                  key: const Key(
                                    'branch-preview-layout-unified',
                                  ),
                                  label: 'Unified',
                                  layout: DiffLayout.unified,
                                ),
                                _previewDiffLayoutButton(
                                  key: const Key(
                                    'branch-preview-layout-side-by-side',
                                  ),
                                  label: 'Side-by-side',
                                  layout: DiffLayout.sideBySide,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox.square(
                        dimension: 24,
                        child: IconButton(
                          key: const Key('preview-diff-close'),
                          tooltip: 'diff 닫기',
                          padding: EdgeInsets.zero,
                          onPressed: _closePreviewDiff,
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: _palette.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        Expanded(
          flex: showConflictChoices ? 2 : 1,
          child: FutureBuilder<List<DiffLine>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Could not load diff',
                    style: TextStyle(color: Color(0xFFF29AB2), fontSize: 12),
                  ),
                );
              }
              if (snapshot.data case final lines?) {
                final document = DiffDocument.fromLines(lines);
                final anchors = {
                  for (final hunk in document.hunks)
                    hunk.anchor.id: GlobalKey(),
                };
                final line = _previewDiffLineTarget?.path == path
                    ? _previewDiffLineTarget
                    : null;
                final nearest = line == null
                    ? null
                    : _nearestPreviewDiffLine(document, line.line);
                final lineTarget = nearest == null
                    ? null
                    : (oldLine: null, newLine: nearest);
                if (line != null &&
                    nearest != null &&
                    line != _previewDiffLineRevealed &&
                    !_previewDiffRevealScheduled) {
                  _previewDiffRevealScheduled = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _previewDiffRevealScheduled = false;
                    if (mounted) _revealPreviewDiffTarget(line);
                  });
                }
                final activeAnchor = conflict && document.hunks.isNotEmpty
                    ? document.hunks.first.anchor
                    : null;
                final titles = _previewDiffTitles(
                  baseRef: baseRef,
                  baseSubject: baseSubject,
                  compareRef: compareRef,
                  compareSubject: compareSubject,
                  baseRole: baseRole,
                  compareRole: compareRole,
                  sideBySide: _previewDiffLayout == DiffLayout.sideBySide,
                );
                return _previewDiffLayout == DiffLayout.unified
                    ? UnifiedPresentationView(
                        document: document,
                        activeAnchor: activeAnchor,
                        path: path,
                        wrapLines: false,
                        highlighter: _previewDiffHighlighter,
                        anchorKeys: anchors,
                        controller: _previewDiffScrollController,
                        scrollTarget: lineTarget,
                        scrollTargetKey: _previewDiffTargetKey,
                        showHunkHeaders: false,
                        compactRows: true,
                        currentMarkerColor: previewConflict,
                        header: titles,
                      )
                    : SideBySidePresentationView(
                        document: document,
                        activeAnchor: activeAnchor,
                        oldPath: file.oldPath ?? path,
                        newPath: path,
                        wrapLines: false,
                        showOldSide: true,
                        highlighter: _previewDiffHighlighter,
                        anchorKeys: anchors,
                        controller: _previewDiffScrollController,
                        scrollTarget: lineTarget,
                        scrollTargetKey: _previewDiffTargetKey,
                        showHunkHeaders: false,
                        compactRows: true,
                        currentMarkerColor: previewConflict,
                        header: titles,
                      );
              }
              return const Center(
                child: SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              );
            },
          ),
        ),
        if (showConflictChoices)
          Expanded(
            child: SingleChildScrollView(
              child: _branchPreviewConflictChoices(),
            ),
          ),
      ],
    );
  }

  Widget _previewDiffTitles({
    required String baseRef,
    required String baseSubject,
    required String compareRef,
    required String compareSubject,
    required String baseRole,
    required String compareRole,
    required bool sideBySide,
  }) {
    Widget title(String branch, String subject, String role) => Expanded(
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: _palette.panel,
          border: Border(right: BorderSide(color: _palette.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: branch,
                      style: TextStyle(
                        color: _palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' · $subject',
                      style: TextStyle(color: _palette.muted),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ),
            const SizedBox(width: 8),
            Text(role, style: TextStyle(color: _palette.muted, fontSize: 10)),
          ],
        ),
      ),
    );
    if (sideBySide) {
      return Container(
        key: const Key('branch-preview-side-titles'),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: _palette.border)),
        ),
        child: Row(
          children: [
            title(baseRef, baseSubject, baseRole),
            title(compareRef, compareSubject, compareRole),
          ],
        ),
      );
    }
    return Container(
      key: const Key('branch-preview-unified-title'),
      height: 30,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: _palette.panel,
        border: Border(bottom: BorderSide(color: _palette.border)),
      ),
      child: Text(
        '$baseRef · $baseSubject ← $compareRef · $compareSubject',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: _palette.muted, fontSize: 10),
      ),
    );
  }

  Widget _previewDiffLayoutButton({
    required Key key,
    required String label,
    required DiffLayout layout,
  }) => InkWell(
    key: key,
    onTap: () => _rebuild(() => _previewDiffLayout = layout),
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _previewDiffLayout == layout
            ? _palette.neutralChip
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _palette.text,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

extension _TimelinePreviewFlows on _TimelineScreenState {
  Future<void> _restoreCherryPickThenRefresh() async {
    await Future.wait([_loadRefs(), _reloadCherryPickState()]);
    if (_cherryPickState == null) await _refreshRemotes();
  }

  Future<void> _reloadCherryPickState() async {
    try {
      final state = await widget.repository.loadCherryPickState();
      if (!mounted) return;
      _rebuild(() {
        _cherryPickState = state;
        _cherryPickError = null;
        _selectedConflictPath =
            state?.conflicts.contains(_selectedConflictPath) == true
            ? _selectedConflictPath
            : state == null || state.conflicts.isEmpty
            ? null
            : state.conflicts.first;
      });
      if (state != null &&
          _previewController.previewPlacement == PreviewPlacement.closed) {
        await _previewController.setPreview(widget.preferredPreviewPlacement);
      }
    } catch (error) {
      if (mounted) _rebuild(() => _cherryPickError = error);
    }
  }

  /// Enter and Space toggle the panel; Esc always closes.
  void _togglePreview() {
    final closing =
        _previewController.previewPlacement != PreviewPlacement.closed;
    if (closing && _previewDiffOpen) _closePreviewDiff();
    if (closing) _closeFullDiff();
    unawaited(
      _previewController.setPreview(
        closing ? PreviewPlacement.closed : widget.preferredPreviewPlacement,
      ),
    );
  }

  /// The preview's, under the same rule.
  Color get _previewSelectionColor =>
      _previewFocusNode.hasFocus ? _palette.selectedRow : _restingSelection;

  Widget _animatedPreview({
    required Axis axis,
    required double extent,
    required double width,
    required double height,
    bool visible = true,
  }) => TweenAnimationBuilder<double>(
    key: const Key('preview-panel'),
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    tween: Tween(begin: 0, end: extent),
    builder: (context, value, child) {
      final visibleExtent = math.min(value, extent);
      return SizedBox(
        width: axis == Axis.horizontal ? visibleExtent : width,
        height: axis == Axis.vertical ? visibleExtent : height,
        child: child,
      );
    },
    child: visible
        ? ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: width,
              maxWidth: width,
              minHeight: height,
              maxHeight: height,
              child: SizedBox(width: width, height: height, child: _preview()),
            ),
          )
        : null,
  );

  Future<void> _confirmCherryPick(GitCommit commit) async {
    final current = _refs.current;
    if (current == null || !_canCherryPick(commit)) return;
    final approved = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: '이 커밋을 체리픽할까요?',
        message: commit.subject,
        body: YogitAlertBlock([commit.sha, '→ $current']),
        confirmLabel: '체리픽',
        confirmKey: const Key('cherry-pick-confirm'),
      ),
    );
    if (approved == true) await _runCherryPick(commit.sha);
  }

  Future<void> _runCherryPick(String sha) async {
    if (_cherryPickBusy) return;
    _rebuild(() {
      _cherryPickBusy = true;
      _cherryPickError = null;
    });
    try {
      await _handleCherryPickResult(await widget.repository.cherryPick(sha));
    } catch (error) {
      if (mounted) {
        _rebuild(() => _cherryPickError = error);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) _rebuild(() => _cherryPickBusy = false);
    }
  }

  Future<void> _handleCherryPickResult(CherryPickResult result) async {
    if (!mounted) return;
    if (result.outcome == CherryPickOutcome.conflicts) {
      _rebuild(() {
        _cherryPickState = result.state;
        _selectedConflictPath = result.state?.conflicts.isEmpty == false
            ? result.state!.conflicts.first
            : null;
      });
      if (_previewController.previewPlacement == PreviewPlacement.closed) {
        await _previewController.setPreview(widget.preferredPreviewPlacement);
      }
      return;
    }
    _rebuild(() {
      _cherryPickState = null;
      _selectedConflictPath = null;
    });
    if (result.outcome == CherryPickOutcome.empty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('적용할 변경이 없습니다')));
    }
    await _reloadTimelineAfterCherryPick(result.headSha);
  }

  Future<void> _continueCherryPick() async {
    if (_cherryPickBusy || _cherryPickState?.canContinue != true) return;
    _rebuild(() {
      _cherryPickBusy = true;
      _cherryPickError = null;
    });
    try {
      await _handleCherryPickResult(
        await widget.repository.continueCherryPick(),
      );
    } catch (error) {
      if (mounted) {
        _rebuild(() => _cherryPickError = error);
        await _reloadCherryPickState();
      }
    } finally {
      if (mounted) _rebuild(() => _cherryPickBusy = false);
    }
  }

  Future<void> _confirmAbortCherryPick() async {
    final approved = await showYogitAlert<bool>(
      context,
      const YogitAlert(
        title: '체리픽을 중단할까요?',
        message: '체리픽을 시작하기 전 상태로 되돌립니다.',
        role: YogitAlertRole.destructive,
        confirmLabel: '중단',
        confirmKey: Key('abort-cherry-pick-confirm'),
      ),
    );
    if (approved != true || !mounted) return;
    _rebuild(() => _cherryPickBusy = true);
    try {
      await widget.repository.abortCherryPick();
      if (!mounted) return;
      _rebuild(() {
        _cherryPickState = null;
        _selectedConflictPath = null;
        _cherryPickError = null;
      });
      await _reloadTimelineAfterCherryPick(null);
    } catch (error) {
      if (mounted) _rebuild(() => _cherryPickError = error);
    } finally {
      if (mounted) _rebuild(() => _cherryPickBusy = false);
    }
  }

  Future<void> _reloadTimelineAfterCherryPick(String? headSha) async {
    widget.repository.invalidateHistory();
    _rebuild(() {
      _normalCommits.clear();
      _normalRows = [];
      _normalEntries = [];
      _committersBySha.clear();
      _previewFiles.clear();
      _previewFileLists.clear();
      _previewDiffs.clear();
      _previewPaths.clear();
      _hasWorkingTree = false;
      _end = false;
      _loadError = null;
      _selectedIndex.value = 0;
    });
    await _fetchNextPage();
    await _loadRefs();
    // Whatever the repository says after a reload is what the timeline shows,
    // so an app-initiated change never comes back as a prompt.
    await _syncLocalSignature();
    if (!mounted || headSha == null) return;
    final index = _entries.indexWhere(
      (entry) => entry.rowIndex >= 0 && entry.row.commit.sha == headSha,
    );
    if (index >= 0) _selectedIndex.value = index;
  }

  Future<void> _openConflictEditor() async {
    final path = _selectedConflictPath;
    if (path == null || _cherryPickBusy) return;
    _rebuild(() {
      _cherryPickBusy = true;
      _cherryPickError = null;
    });
    try {
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          overlay.size.width - 260,
          overlay.size.height - 160,
          16,
          16,
        ),
        items: [
          const PopupMenuItem(value: 'internal', child: Text('내장 에디터')),
          const PopupMenuItem(value: 'external', child: Text('외부 에디터')),
        ],
      );
      if (!mounted || choice == null) return;
      final externalEditor = ExternalEditorService(
        repositoryRoot: widget.repository.root,
      );
      if (choice == 'external') {
        await externalEditor.open(relativePath: path);
        return;
      }
      final document =
          await widget.documentLoaderForTesting?.call(path) ??
          await WorkingTreeTextDocument.load(
            repositoryRoot: widget.repository.root,
            relativePath: path,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MonacoEditorScreen(
            title: path,
            initialText: document.text,
            language: monacoLanguageForPath(path),
            readOnly: false,
            onSave: (text) async {
              await document.save(text);
              await widget.repository.stageResolvedFile(path);
              await _reloadCherryPickState();
              if (mounted) Navigator.of(context).pop();
            },
            onOpenExternal: () async {
              try {
                await externalEditor.open(relativePath: path);
              } catch (error) {
                if (mounted) _rebuild(() => _cherryPickError = error);
              }
            },
            editorForTesting: widget.editorForTesting,
          ),
        ),
      );
    } catch (error) {
      if (mounted) _rebuild(() => _cherryPickError = error);
    } finally {
      if (mounted) _rebuild(() => _cherryPickBusy = false);
    }
  }

  Future<List<GitFileChange>> _previewFilesFor(GitCommit commit) {
    final key = _previewKey(commit);
    return _previewFiles.putIfAbsent(key, () {
      final comparison = _comparison;
      final preview = _rebasePreview;
      final request = comparison == null || !_usesBranchPreviewResult(commit)
          ? widget.repository.loadFiles(commit)
          : _branchPreviewMode == BranchPreviewMode.merge
          ? Future.value(
              _effectiveMergeStatus == MergeConflictStatus.clean
                  ? (_mergePreview?.treeSha ?? comparison.merge.treeSha) == null
                        ? comparison.files
                        : _mergePreview?.resultFiles ??
                              comparison.merge.resultFiles
                  : [
                      for (final path
                          in _mergePreview?.conflictFiles ??
                              comparison.merge.files)
                        GitFileChange(
                          path: path,
                          status: 'U',
                          additions: null,
                          deletions: null,
                        ),
                    ],
            )
          : preview?.status == RebasePreviewStatus.clean &&
                preview?.virtualTip != null
          ? widget.repository.loadFilesBetween(
              comparison.baseTip,
              preview!.virtualTip!,
            )
          : Future.value([
              for (final path in preview?.conflictFiles ?? const <String>[])
                GitFileChange(
                  path: path,
                  status: 'U',
                  additions: null,
                  deletions: null,
                ),
            ]);
      unawaited(
        request
            .then((files) => _previewFileLists[key] = files)
            .catchError((_) => const <GitFileChange>[]),
      );
      return request;
    });
  }

  Future<String> _previewMessageFor(GitCommit commit) =>
      _commitMessageFor(commit.sha);

  Widget _adjacentPreviewDiff(PreviewPlacement placement) => Stack(
    children: [
      Positioned.fill(
        child: ValueListenableBuilder<int>(
          valueListenable: _selectedIndex,
          builder: (context, _, _) {
            final commit = _selectedCommit;
            if (commit == null) return const SizedBox.shrink();
            return FutureBuilder<List<GitFileChange>>(
              key: ValueKey(_previewKey(commit)),
              future: _previewFilesFor(commit),
              builder: (context, snapshot) {
                final changes = snapshot.data;
                if (changes == null || changes.isEmpty) {
                  return const SizedBox.shrink();
                }
                final requestedPath = _previewPaths[_previewKey(commit)];
                final file = changes.firstWhere(
                  (file) => file.path == requestedPath,
                  orElse: () => changes.first,
                );
                return Container(
                  key: const Key('preview-diff'),
                  decoration: BoxDecoration(
                    color: _palette.background,
                    border: Border.all(color: _palette.border),
                  ),
                  child: SelectionArea(
                    child: KeyedSubtree(
                      key: const Key('preview-diff-scroll'),
                      child: _previewDiff(commit, file),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      _previewDiffResizer(placement),
    ],
  );

  void _closePreviewDiff() {
    _rebuild(() => _previewDiffOpen = false);
    _focusNode.requestFocus();
  }

  /// Merge-result line spans where both sides edited within ten lines of each
  /// other. Empty outside the clean merge preview, and for files only one side
  /// touched.
  List<LineSpan> _previewProximity(GitCommit commit, GitFileChange file) {
    final comparison = _comparison;
    if (comparison == null ||
        _branchPreviewMode != BranchPreviewMode.merge ||
        _effectiveMergeStatus != MergeConflictStatus.clean ||
        !_usesBranchPreviewResult(commit)) {
      return const [];
    }
    return comparison.merge.proximity[file.path] ?? const [];
  }

  /// The nearest line the loaded result diff actually draws. A region's first
  /// line is often a base-side edit the result diff never shows, and a number no
  /// row carries would leave the scroll target attached nowhere.
  int? _nearestPreviewDiffLine(DiffDocument document, int line) {
    int? nearest;
    for (final hunk in document.hunks) {
      for (final diffLine in hunk.lines) {
        final number = diffLine.newNumber;
        if (number == null) continue;
        if (nearest == null || (number - line).abs() < (nearest - line).abs()) {
          nearest = number;
        }
      }
    }
    return nearest;
  }

  /// Scrolls the open result diff onto the line a pill asked for, once the diff
  /// itself has rendered. The diff builds its rows lazily, so a target below the
  /// first viewport only exists after paging down to it.
  void _revealPreviewDiffTarget(({String path, int line}) line) {
    final target = _previewDiffTargetKey.currentContext;
    if (target == null) {
      if (!_previewDiffScrollController.hasClients) return;
      final position = _previewDiffScrollController.position;
      final next = (position.pixels + position.viewportDimension).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((next - position.pixels).abs() < 0.5) return;
      position.jumpTo(next);
      _previewDiffRevealScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _previewDiffRevealScheduled = false;
        if (mounted) _revealPreviewDiffTarget(line);
      });
      return;
    }
    _previewDiffLineRevealed = line;
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        alignment: 0.2,
      ),
    );
  }
}
