part of 'timeline.dart';

/// The branch-preview half of the timeline screen: simulating a merge or a
/// rebase, showing what it would produce, resolving what it conflicts on, and
/// applying or rolling it back. The state itself stays with the screen — an
/// extension cannot hold fields — but everything that acts on it lives here.

extension _TimelineBranchPreview on _TimelineScreenState {
  Widget _branchPreviewControls() {
    Widget button(BranchPreviewMode mode, String label, Key key, Key labelKey) {
      final selected = _branchPreviewMode == mode;
      return Expanded(
        child: InkWell(
          key: key,
          onTap: _branchApplyBusy ? null : () => _setBranchPreviewMode(mode),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? previewControlBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              key: labelKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : _palette.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const Key('branch-preview-segmented'),
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _palette.background,
        border: Border.all(color: _palette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          button(
            BranchPreviewMode.merge,
            'Merge 미리보기',
            const Key('branch-preview-merge-button'),
            const Key('branch-preview-merge'),
          ),
          button(
            BranchPreviewMode.rebase,
            'Rebase 미리보기',
            const Key('branch-preview-rebase-button'),
            const Key('branch-preview-rebase'),
          ),
        ],
      ),
    );
  }

  void _setBranchPreviewMode(BranchPreviewMode mode) {
    if (_branchPreviewMode == mode ||
        _branchApplyStatus == BranchApplyStatus.applying ||
        _branchApplyStatus == BranchApplyStatus.reverting) {
      return;
    }
    _rebuild(() {
      _branchPreviewMode = mode;
      _resetBranchApply();
      final comparison = _comparison;
      if (comparison != null) {
        _previewGraph = mode == BranchPreviewMode.merge
            ? layoutMergePreviewGraph(comparison)
            : null;
        _comparisonRows =
            _previewGraph?.rows ?? layoutBranchComparison(comparison.commits);
        _comparisonEntries = [
          for (var index = 0; index < _comparisonRows.length; index++)
            (rowIndex: index, label: null, row: _comparisonRows[index]),
        ];
        _selectedIndex.value = 0;
      }
    });
    _showFirstComparisonRow();
    widget.onBranchPreviewModeChanged?.call(mode);
    unawaited(_openPaneForBranchPreview());
    _scheduleRatchetUpdate();
    if (mode == BranchPreviewMode.rebase) {
      _dropMergePreview();
      unawaited(_startRebasePreview());
    } else {
      _dropRebasePreview();
      if (_comparison?.merge.status == MergeConflictStatus.conflicts) {
        unawaited(_startMergePreview());
      }
    }
  }

  void _dropMergePreview() {
    _mergePreviewSerial++;
    final session = _mergePreviewSession;
    _mergePreviewSession = null;
    _mergePreview = null;
    _mergePreviewBusy = false;
    _mergePreviewError = null;
    _mergeResolvedFiles.clear();
    _dropKeepBoth();
    if (session != null) unawaited(session.dispose());
  }

  void _dropKeepBoth() {
    _keepBothSerial++;
    _keepBothCandidates.clear();
    _keepBothOpenPath = null;
  }

  void _dropRebasePreview() {
    _rebasePreviewSerial++;
    final session = _rebasePreviewSession;
    _rebasePreviewSession = null;
    _rebasePreview = null;
    _rebasePreviewBusy = false;
    _repositoryOperationInProgress = false;
    _rebaseHadConflict = false;
    _rebaseResolvedFiles.clear();
    _rebaseEditedFiles.clear();
    _rebasePreviewError = null;
    _rebaseApplyMerge = false;
    _dropKeepBoth();
    if (session != null) unawaited(session.dispose());
  }

  Widget _branchPreviewSummary() {
    final comparison = _comparison;
    final mergeMode = _branchPreviewMode == BranchPreviewMode.merge;
    final mergeStatus = _effectiveMergeStatus;
    final rebaseStatus = _rebasePreview?.status;
    final comparisonFailed = _comparisonError != null;
    final success = mergeMode
        ? mergeStatus == MergeConflictStatus.clean
        : _rebaseCheck?.status == RebaseCheckStatus.clean;
    final resultLabel = comparisonFailed
        ? '브랜치 비교 실패'
        : mergeMode
        ? switch (mergeStatus) {
            MergeConflictStatus.clean => 'Merge 성공',
            MergeConflictStatus.conflicts => 'Merge 충돌',
            MergeConflictStatus.failed => 'Merge 검사 실패',
            null => 'Merge 검사 중',
          }
        : switch (_rebaseCheck?.status) {
            RebaseCheckStatus.clean => 'Rebase 성공',
            RebaseCheckStatus.conflicts => 'Rebase 충돌',
            RebaseCheckStatus.failed => 'Rebase 검사 실패',
            null => 'Rebase 검사 중',
          };
    Widget detail(String value, {Color? color}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.12) ?? _palette.raised,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: color ?? _palette.muted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final details = <Widget>[];
    if (comparison != null) {
      if (mergeMode) {
        if (mergeStatus == MergeConflictStatus.clean) {
          details.addAll([
            detail('가상 커밋 1', color: previewPurple),
            detail('충돌 없음', color: successGreen),
          ]);
        } else if (mergeStatus == MergeConflictStatus.conflicts) {
          final conflicts =
              _mergePreview?.conflictFiles.length ??
              comparison.merge.files.length;
          details.addAll([
            detail('충돌 $conflicts개', color: previewConflict),
            detail('임시 공간 사용 중'),
          ]);
        }
      } else if (rebaseStatus == RebasePreviewStatus.conflict) {
        final preview = _rebasePreview!;
        details.addAll([
          detail(
            preview.completed == 0 ? '최초 충돌' : '다음 충돌',
            color: previewConflict,
          ),
          detail('진행 ${preview.completed + 1}/${preview.total}'),
          detail('임시 공간 사용 중'),
        ]);
      } else if (_rebaseCheck?.status == RebaseCheckStatus.clean) {
        final count = _rebasePreview?.rewritten.length ?? 0;
        if (count > 0) {
          details.add(detail('가상 커밋 $count개'));
          // 선택에 따라 타임라인에 머지 커밋이 하나 더 그려지면 요약에서도 센다.
          if (_rebaseApplyMerge) {
            details.add(detail('머지 커밋 1개', color: previewPurple));
          }
        }
        details.addAll([
          detail('점선 이동 경로', color: previewPurple),
          detail('실제 브랜치 변경 없음'),
        ]);
      }
      // 칩은 두 모드 모두에서 상세 줄 끝에 붙는다. 계산이 끝나기 전에는 없다.
      if (_recommendation case final recommendation?) {
        details.add(_branchPreviewRecommendationChip(recommendation));
      }
    }
    final resultColor = comparisonFailed
        ? behindOrange
        : success
        ? successGreen
        : mergeStatus == MergeConflictStatus.conflicts ||
              rebaseStatus == RebasePreviewStatus.conflict
        ? previewConflict
        : _palette.muted;
    final title = success
        ? mergeMode
              ? 'Merge 미리보기'
              : 'Rebase 미리보기'
        : resultLabel;
    return Container(
      key: const Key('branch-preview-summary'),
      height: _TimelineScreenState._branchPreviewSummaryHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _palette.surface,
        border: Border(bottom: BorderSide(color: _palette.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: success ? _palette.text : resultColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (success) ...[
              const SizedBox(width: 5),
              const Icon(
                Icons.check_circle,
                key: Key('branch-preview-success-icon'),
                color: successGreen,
                size: 15,
              ),
            ],
            for (final detail in details) ...[const SizedBox(width: 8), detail],
            if (comparison != null) ...[
              const SizedBox(width: 12),
              Text(
                mergeMode
                    ? '${comparison.baseRef} ← ${comparison.compareRef}'
                    : '${comparison.compareRef} → ${comparison.baseRef}',
                style: TextStyle(color: _palette.muted, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The verdict chip, with the measured reasons a hover or a click away. It
  /// says what the facts lean towards and asks nothing.
  Widget _branchPreviewRecommendationChip(
    BranchRecommendation recommendation,
  ) => MenuAnchor(
    style: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(Color(0xFF202022)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: _palette.border),
        ),
      ),
    ),
    menuChildren: [
      Container(
        key: const Key('branch-preview-recommendation-reasons'),
        width: 430,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '왜 ${recommendation.label}인가',
              style: const TextStyle(
                color: previewPurple,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final reason in recommendation.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '·',
                      style: TextStyle(color: _palette.muted, fontSize: 11),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(color: _palette.text, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
    builder: (context, controller, child) => MouseRegion(
      onEnter: (_) => controller.open(),
      child: InkWell(
        key: const Key('branch-preview-recommendation'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: previewPurple.withValues(alpha: 0.10),
            border: Border.all(color: const Color(0xFF695786)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '추천: ${recommendation.label}',
                style: const TextStyle(
                  color: previewPurple,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                recommendation.summary,
                style: TextStyle(
                  color: _palette.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  bool get _branchPreviewReady {
    final comparison = _comparison;
    if (comparison == null || _branchPreviewDropped) return false;
    return _branchPreviewMode == BranchPreviewMode.merge
        ? _effectiveMergeStatus == MergeConflictStatus.clean &&
              (_mergePreview?.treeSha ?? comparison.merge.treeSha) != null
        : _rebasePreview?.status == RebasePreviewStatus.clean &&
              _rebasePreview?.virtualTip != null;
  }

  BranchApplyTarget? get _branchPreviewTarget {
    final comparison = _comparison;
    if (comparison == null) return null;
    return resolveBranchApplyTarget(
      mode: _branchPreviewMode == BranchPreviewMode.merge
          ? BranchApplyMode.merge
          : BranchApplyMode.rebase,
      comparison: comparison,
      refs: _refs,
    );
  }

  bool get _branchPreviewCanPrepare =>
      _branchPreviewReady && _branchPreviewTarget != null;

  bool get _branchPreviewCanApply =>
      _branchPreviewCanPrepare && !_branchPreviewTarget!.needsRecalculation;

  String get _branchPreviewApplyLabel {
    final comparison = _comparison!;
    final target = _branchPreviewTarget;
    if (target?.needsRecalculation == true) {
      return '로컬 ${target!.localBranch} 기준으로 다시 계산';
    }
    // Rebase 쪽은 무엇을 적용할지 카드의 선택이 말하니 버튼 문구는 고정이다.
    return _branchPreviewMode == BranchPreviewMode.merge
        ? '${comparison.compareRef}를 ${target?.localBranch ?? comparison.baseRef}에 Merge 실제 적용'
        : '실제 적용하기';
  }

  String get _branchPreviewApplyHelp {
    final comparison = _comparison!;
    final target = _branchPreviewTarget;
    if (target == null) return '적용할 로컬 브랜치를 찾을 수 없습니다.';
    if (target.needsRecalculation) {
      return '기존 로컬 ${target.localBranch} 기준으로 다시 계산해야 합니다.';
    }
    if (target.createsBranch) {
      return '로컬 ${target.localBranch}를 ${target.selectedRef}에서 만든 뒤 결과를 적용합니다.';
    }
    if (_branchPreviewMode == BranchPreviewMode.merge &&
        _refs.remote.contains(comparison.compareRef)) {
      return '${comparison.compareRef}는 입력으로만 사용합니다. 실제 변경은 로컬 ${target.localBranch}에 적용됩니다.';
    }
    return '가상 결과를 로컬 ${target.localBranch}에 적용할 수 있습니다.';
  }

  String get _branchPreviewAppliedSummary {
    final result = _branchApplyResult!;
    final compareLine = result.compareBranchCreated
        ? '${result.compareBranch}: 새 브랜치 → ${result.compareAfter}'
        : '${result.compareBranch}: ${result.compareBefore} → ${result.compareAfter}';
    final compareRef = _comparison?.compareRef;
    final remote = compareRef != null && _refs.remote.contains(compareRef)
        ? '\n$compareRef: 변경 없음'
        : '';
    if (result.mode == BranchApplyMode.rebaseMerge) {
      final head = result.workingTreeUpdated
          ? '\n${result.baseBranch} 체크아웃 · 작업 트리가 병합 결과입니다'
          : result.compareWorkingTreeUpdated
          ? '\n${result.compareBranch} 체크아웃 · 작업 트리가 재배치 결과입니다'
                '\n${result.baseBranch} 브랜치는 머지 커밋을 가리키고 작업 트리는 그대로입니다'
          : '\n두 브랜치 모두 새 커밋을 가리키고 작업 트리는 그대로입니다'
                '\n브랜치를 체크아웃하면 결과가 작업 트리에 반영됩니다';
      return '$compareLine\n'
          '${result.baseBranch}: ${result.baseBefore} → ${result.baseAfter}'
          '$remote$head';
    }
    final merge = result.mode == BranchApplyMode.merge;
    final local = merge
        ? '${result.baseBranch}: ${result.baseBefore} → ${result.baseAfter}'
        : compareLine;
    final moved = merge ? result.baseBranch : result.compareBranch;
    final head = result.workingTreeUpdated
        ? '\n$moved 체크아웃 · 작업 트리가 ${merge ? 'Merge' : 'Rebase'} 결과입니다'
        : '\n$moved 브랜치는 새 커밋을 가리키고 작업 트리는 그대로입니다'
              '\n$moved 브랜치를 체크아웃하면 결과가 작업 트리에 반영됩니다';
    return '$local$remote$head';
  }

  String _branchPreviewRollbackMessage(BranchApplyResult result) {
    final compareLine = result.compareBranchCreated
        ? '적용 과정에서 만든 로컬 ${result.compareBranch}를 삭제합니다.'
        : '로컬 ${result.compareBranch}를 ${result.compareBefore}으로 되돌립니다.';
    final local = switch (result.mode) {
      BranchApplyMode.merge =>
        '로컬 ${result.baseBranch}을 ${result.baseBefore}으로 되돌립니다.',
      BranchApplyMode.rebase => compareLine,
      BranchApplyMode.rebaseMerge =>
        '로컬 ${result.baseBranch}을 ${result.baseBefore}으로 되돌립니다.\n'
            '$compareLine',
    };
    final compareRef = _comparison?.compareRef;
    final remote = compareRef != null && _refs.remote.contains(compareRef)
        ? '\n$compareRef는 변경하지 않습니다.'
        : '';
    final moved = switch (result.mode) {
      BranchApplyMode.merge => {result.baseBranch},
      BranchApplyMode.rebase => {result.compareBranch},
      BranchApplyMode.rebaseMerge => {result.baseBranch, result.compareBranch},
    };
    // 되돌리기는 그 시점의 체크아웃을 다시 확인하니, 적용 당시가 아니라 지금 상태로
    // 안내합니다. 적용은 ref만 옮겼어도 그 사이 체크아웃했다면 작업 트리까지 바뀝니다.
    final head = moved.contains(_refs.current)
        ? '\n되돌린 뒤에도 ${_refs.current}에 체크아웃된 상태로 남고 작업 트리도 이전 상태로 돌아갑니다.'
        : '\n되돌릴 때도 작업 트리는 건드리지 않습니다.';
    return '$local$remote$head\n원격 저장소는 변경하지 않습니다.';
  }

  Widget _branchPreviewApplyButton() => FilledButton(
    key: const Key('branch-preview-apply'),
    onPressed: _branchApplyBusy || !_branchPreviewCanPrepare
        ? null
        : () => unawaited(_prepareBranchPreviewApply()),
    style: FilledButton.styleFrom(
      foregroundColor: const Color(0xFFFFF4FF),
      backgroundColor: const Color(0xFF594576),
      side: const BorderSide(color: Color(0xFF9D79D0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    ),
    child: Text(
      _branchPreviewApplyLabel,
      textAlign: TextAlign.center,
      softWrap: true,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );

  /// What the selected landing leaves behind: the replayed commits carrying on
  /// along the base rail, or riding a dashed arc onto a merge commit.
  Widget _branchPreviewRebaseMergeGraph(BranchComparisonResult comparison) =>
      SizedBox(
        key: const Key('branch-preview-rebase-merge-graph'),
        height: 86,
        child: CustomPaint(
          painter: RebaseMergeResultPainter(
            commitCount: _rebasePreview?.rewritten.length ?? 0,
            baseLabel: comparison.baseRef,
            mergeCommit: _rebaseApplyMerge,
            railColor: _palette.border,
            mutedColor: _palette.muted,
          ),
        ),
      );

  Widget _branchPreviewApplyCard() {
    final merge = _branchPreviewMode == BranchPreviewMode.merge;
    final result = _branchApplyResult;
    final previewCommitCount = merge
        ? 1
        : _rebasePreview?.rewritten.length ?? 0;
    Widget metric(String value, String label, String key) => Expanded(
      child: Container(
        key: Key(key),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF202125),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: TextStyle(color: _palette.muted, fontSize: 10)),
          ],
        ),
      ),
    );
    return Container(
      key: const Key('branch-preview-apply-card'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: previewPurplePanel,
        border: Border.all(color: const Color(0xFF695786)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result == null
                      ? merge
                            ? 'Merge 미리보기 성공'
                            : 'Rebase 미리보기 성공'
                      : '${_TimelineScreenState._applyModeLabel(result.mode)} 적용 완료',
                  style: TextStyle(
                    color: _palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_branchApplyStatus != BranchApplyStatus.idle)
                Flexible(
                  child: Text(
                    switch (_branchApplyStatus) {
                      BranchApplyStatus.applying => '커밋 적용 중',
                      BranchApplyStatus.applied => '로컬 브랜치 적용됨',
                      BranchApplyStatus.reverting => '되돌리는 중',
                      BranchApplyStatus.reverted => 'SHA 일치 확인',
                      BranchApplyStatus.failed => '작업 실패',
                      BranchApplyStatus.idle => '',
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          _branchApplyStatus == BranchApplyStatus.reverted ||
                              _branchApplyStatus == BranchApplyStatus.applied
                          ? successGreen
                          : _palette.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (result == null) ...[
            const SizedBox(height: 9),
            Container(
              key: const Key('branch-preview-progress'),
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF17181B),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const FractionallySizedBox(
                widthFactor: 1,
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: previewPurple,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                metric(
                  '$previewCommitCount',
                  '가상 커밋',
                  'branch-preview-virtual-count',
                ),
                const SizedBox(width: 5),
                metric(
                  '${merge ? 2 : previewCommitCount}',
                  merge ? '부모 커밋' : '원본 커밋',
                  'branch-preview-source-count',
                ),
                const SizedBox(width: 5),
                metric('0', '충돌', 'branch-preview-conflict-count'),
              ],
            ),
            if (_comparison case final comparison? when !merge)
              _branchPreviewRebaseMergeGraph(comparison),
          ],
          if (result != null) ...[
            const SizedBox(height: 8),
            Text(
              _branchPreviewAppliedSummary,
              style: TextStyle(
                color: _palette.muted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (_branchApplyError != null) ...[
            const SizedBox(height: 8),
            Text(
              _branchApplyError.toString(),
              style: TextStyle(color: behindOrange, fontSize: 10),
            ),
          ],
          const SizedBox(height: 10),
          if (result != null)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                key: const Key('branch-preview-rollback'),
                onPressed: _branchApplyStatus == BranchApplyStatus.applied
                    ? () => unawaited(_confirmBranchPreviewRollback())
                    : null,
                child: Text(
                  '${_TimelineScreenState._applyModeLabel(result.mode)} 이전 시점으로 되돌리기',
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _branchPreviewApplyHelp,
                  style: TextStyle(color: _palette.muted, fontSize: 10),
                ),
                if (!merge) ..._branchPreviewApplyOptions(),
                const SizedBox(height: 7),
                SizedBox(
                  width: double.infinity,
                  child: _branchPreviewApplyButton(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  bool get _branchPreviewResolutionComplete =>
      !_branchPreviewDropped &&
      (_branchPreviewMode == BranchPreviewMode.merge
          ? _mergePreviewSession != null &&
                _mergePreview?.status == MergePreviewStatus.clean
          : _rebaseHadConflict &&
                _rebasePreview?.status == RebasePreviewStatus.clean);

  Widget _branchPreviewConflictStatusCard() {
    final comparison = _comparison!;
    final merge = _branchPreviewMode == BranchPreviewMode.merge;
    if (merge) {
      final count =
          _mergePreview?.conflictFiles.length ?? comparison.merge.files.length;
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: previewConflictPanel,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '가상 Merge 커밋을 만들 수 없습니다',
                    style: TextStyle(
                      color: _palette.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '충돌 파일 $count개',
                  style: const TextStyle(
                    color: previewConflict,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              '아래 diff에서 충돌을 해결하세요. 임시 공간은 자동으로 준비했습니다.',
              style: TextStyle(color: _palette.muted, fontSize: 10),
            ),
          ],
        ),
      );
    }
    final preview = _rebasePreview!;
    final current = preview.completed + 1;
    Widget metric(Key key, String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF202125),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              value,
              key: key,
              style: TextStyle(
                color: _palette.text,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: TextStyle(color: _palette.muted, fontSize: 10)),
          ],
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: previewPurplePanel,
        border: Border.all(color: const Color(0xFF695786)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '리베이스 진행 $current/${preview.total}',
                  style: TextStyle(
                    color: _palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${comparison.compareRef} → ${comparison.baseRef}',
                style: TextStyle(color: _palette.muted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: preview.total == 0 ? 0 : current / preview.total,
            minHeight: 5,
            borderRadius: BorderRadius.circular(4),
            color: previewConflict,
            backgroundColor: const Color(0xFF17181B),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              metric(
                const Key('rebase-preview-applied-count'),
                '${preview.completed}',
                '적용 완료',
              ),
              const SizedBox(width: 5),
              metric(const Key('rebase-preview-conflict-count'), '1', '현재 충돌'),
              const SizedBox(width: 5),
              metric(
                const Key('rebase-preview-pending-count'),
                '${math.max(0, preview.total - current)}',
                '적용 대기',
              ),
            ],
          ),
          if (preview.currentCommit != null) ...[
            const SizedBox(height: 8),
            Text(
              '현재: ${preview.currentCommit!.subject}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _palette.text, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _branchPreviewSafeWorkspace() {
    final comparison = _comparison!;
    Widget tag(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF173741),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF9ADCE7),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Container(
      key: const Key('branch-preview-safe-workspace'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2328),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.diamond_outlined,
                color: Color(0xFF8CD8E6),
                size: 15,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '임시 공간에서 해결 중',
                  style: TextStyle(
                    color: _palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text(
                '자동 준비됨',
                style: TextStyle(
                  color: Color(0xFF8CD8E6),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '충돌 해결 과정은 임시 공간에서만 진행합니다. '
            '기준 브랜치 ${comparison.baseRef}과 대상 브랜치 '
            '${comparison.compareRef}를 직접 변경하지 않습니다.',
            style: TextStyle(color: _palette.text, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              tag('두 브랜치 변경 없음'),
              tag('현재 작업 트리 변경 없음'),
              tag('종료 시 자동 삭제'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _branchPreviewResolutionCard() => Container(
    key: const Key('branch-preview-resolution-complete'),
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: Color.lerp(_palette.raised, renamedPurple, 0.14),
      border: Border.all(color: renamedPurple.withValues(alpha: 0.48)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '충돌 해결을 마쳤습니다',
          style: TextStyle(
            color: _palette.text,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_branchPreviewMode == BranchPreviewMode.merge ? 'Merge' : 'Rebase'} 가능',
          style: const TextStyle(
            color: successGreen,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              key: const Key('branch-preview-drop'),
              onPressed: _branchApplyBusy
                  ? null
                  : () => unawaited(_dropResolvedBranchPreview()),
              child: const Text('Drop'),
            ),
            const SizedBox(width: 6),
            Expanded(child: _branchPreviewApplyButton()),
          ],
        ),
      ],
    ),
  );

  Widget _branchPreviewDroppedCard() => Container(
    key: const Key('branch-preview-dropped'),
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: _palette.raised,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '임시 결과를 Drop했습니다',
            style: TextStyle(
              color: _palette.text,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Text(
          '변경 없음',
          style: TextStyle(
            color: successGreen,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  /// The commit's changed files, remembered in resolved form as well so ⌘↑/⌘↓ can
  /// walk them without waiting on a future.
  bool _usesBranchPreviewResult(GitCommit? commit) {
    final kind = commit == null ? null : _previewGraph?.kinds[commit.sha];
    return kind == PreviewGraphNodeKind.virtualMerge ||
        kind == PreviewGraphNodeKind.virtualRebase ||
        kind == PreviewGraphNodeKind.virtualRebaseMerge ||
        (_comparison != null &&
            (_branchPreviewMode == BranchPreviewMode.merge
                ? _mergePreviewError != null
                : _rebasePreviewError != null)) ||
        (_branchPreviewMode == BranchPreviewMode.rebase &&
            _rebasePreview?.status == RebasePreviewStatus.conflict &&
            _rebasePreview?.currentCommit?.sha == commit?.sha);
  }

  /// The branch preview's virtual commits have no diff a commit session can
  /// load, so they keep the adjacent pane; every other commit opens the
  /// embedded workspace.
  bool _showsBranchPreviewDiff(GitCommit commit) =>
      _comparison != null && _usesBranchPreviewResult(commit);

  bool get _branchPreviewHasConflict =>
      !_branchPreviewDropped &&
      (_branchPreviewMode == BranchPreviewMode.merge
          ? _effectiveMergeStatus == MergeConflictStatus.conflicts
          : _rebasePreview?.status == RebasePreviewStatus.conflict);

  Widget _branchPreviewConflictChoices() {
    final comparison = _comparison!;
    final mergeMode = _branchPreviewMode == BranchPreviewMode.merge;
    final interactive = mergeMode
        ? _mergePreviewSession != null
        : _rebasePreviewSession != null;
    final conflictPath = mergeMode
        ? _selectedMergeConflictPath
        : _selectedRebaseConflictPath;
    final keepBoth = conflictPath == null
        ? null
        : _keepBothCandidates[conflictPath];
    Widget choice({
      required Key key,
      required String label,
      required VoidCallback onTap,
      bool accent = false,
    }) => InkWell(
      key: key,
      onTap:
          !interactive ||
              _mergePreviewBusy ||
              _rebasePreviewBusy ||
              _repositoryOperationInProgress
          ? null
          : onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: accent
              ? previewPurple.withValues(alpha: 0.08)
              : _palette.raised,
          border: Border.all(
            color: accent
                ? const Color(0xFF9D79D0)
                : _palette.muted.withValues(alpha: 0.55),
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent ? previewPurple : _palette.text,
            fontSize: 10,
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('branch-preview-conflict-actions'),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: previewConflictPanel.withValues(alpha: 0.72),
            border: Border(
              top: BorderSide(color: previewConflict.withValues(alpha: 0.45)),
            ),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!mergeMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '이 충돌 해결:',
                    style: TextStyle(
                      color: previewConflict.withValues(alpha: 0.92),
                      fontSize: 10,
                    ),
                  ),
                ),
              choice(
                key: Key(
                  mergeMode
                      ? 'merge-conflict-use-base'
                      : 'rebase-conflict-use-base',
                ),
                label: '${comparison.baseRef} 사용',
                onTap: () => unawaited(
                  mergeMode
                      ? _resolveMergeConflict(MergeConflictChoice.base)
                      : _resolveRebaseConflict(RebaseConflictChoice.base),
                ),
              ),
              choice(
                key: Key(
                  mergeMode
                      ? 'merge-conflict-use-compare'
                      : 'rebase-conflict-use-compare',
                ),
                label: '${comparison.compareRef} 사용',
                onTap: () => unawaited(
                  mergeMode
                      ? _resolveMergeConflict(MergeConflictChoice.compare)
                      : _resolveRebaseConflict(RebaseConflictChoice.commit),
                ),
              ),
              // P3 — 양쪽 모두 순수 추가로 판정된 파일에만 나타나는 세 번째 선택지.
              if (keepBoth != null)
                choice(
                  key: const Key('conflict-keep-both'),
                  label: '양쪽 유지',
                  accent: true,
                  onTap: () => _rebuild(
                    () => _keepBothOpenPath = _keepBothOpenPath == conflictPath
                        ? null
                        : conflictPath,
                  ),
                ),
              choice(
                key: Key(
                  mergeMode
                      ? 'merge-conflict-use-both'
                      : 'rebase-conflict-edit',
                ),
                // 두 모드 모두 에디터를 여는 같은 동작이다 — 문구도 같아야 '양쪽
                // 유지'(P3 결합)와 헷갈리지 않는다.
                label: '직접 편집',
                onTap: () => unawaited(
                  _openBranchPreviewConflictEditor(mergeMode: mergeMode),
                ),
              ),
            ],
          ),
        ),
        if (keepBoth != null && _keepBothOpenPath == conflictPath)
          _keepBothChooser(
            conflictPath!,
            keepBoth,
            baseRef: comparison.baseRef,
            mergeMode: mergeMode,
          ),
        if (interactive)
          mergeMode ? _mergeConflictActions() : _rebaseConflictActions(),
      ],
    );
  }

  /// P3 상태 B — 결합 순서 두 가지를 나란히 놓고 하나만 고르게 한다. 미리보기는
  /// 실제 결합 내용 그대로다: 파랑이 기준 쪽 추가, 초록이 브랜치 쪽 추가.
  Widget _keepBothChooser(
    String path,
    KeepBothCandidate candidate, {
    required String baseRef,
    required bool mergeMode,
  }) {
    Widget order({
      required Key key,
      required String caption,
      required bool baseFirst,
    }) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            caption,
            style: TextStyle(
              color: _palette.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _palette.background,
              border: Border.all(color: _palette.muted.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(7),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text.rich(
                _keepBothPreview(candidate, baseFirst: baseFirst),
                softWrap: false,
              ),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton(
            key: key,
            onPressed:
                (mergeMode ? _mergePreviewBusy : _rebasePreviewBusy) ||
                    _repositoryOperationInProgress
                ? null
                : () => unawaited(
                    _applyKeepBoth(
                      path,
                      candidate,
                      mergeMode: mergeMode,
                      baseFirst: baseFirst,
                    ),
                  ),
            child: const Text('이 순서로 적용'),
          ),
        ],
      ),
    );
    return Container(
      key: const Key('conflict-keep-both-chooser'),
      padding: const EdgeInsets.all(8),
      color: previewPurplePanel.withValues(alpha: 0.72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$path — 양쪽 유지',
            style: TextStyle(
              color: _palette.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '충돌 구역 ${candidate.hunks.length}곳 전부에서 양쪽이 서로 다른 코드를 '
            '추가했습니다. 순서만 고르면 됩니다.',
            style: TextStyle(color: _palette.muted, fontSize: 10),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              order(
                key: const Key('keep-both-apply-base-first'),
                caption: '기준($baseRef) 먼저',
                baseFirst: true,
              ),
              const SizedBox(width: 10),
              order(
                key: const Key('keep-both-apply-branch-first'),
                caption: '브랜치 먼저',
                baseFirst: false,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '적용해도 파일은 계속 편집할 수 있습니다. 파랑은 기준 쪽 추가, 초록은 '
            '브랜치 쪽 추가입니다.',
            style: TextStyle(color: _palette.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  TextSpan _keepBothPreview(
    KeepBothCandidate candidate, {
    required bool baseFirst,
  }) => TextSpan(
    children: [
      for (final hunk in candidate.hunks)
        for (final side
            in baseFirst
                ? [
                    (lines: hunk.ours, color: keepBothOursColor),
                    (lines: hunk.theirs, color: keepBothTheirsColor),
                  ]
                : [
                    (lines: hunk.theirs, color: keepBothTheirsColor),
                    (lines: hunk.ours, color: keepBothOursColor),
                  ])
          if (side.lines.isNotEmpty)
            TextSpan(
              text: '${side.lines.join('\n')}\n',
              style: TextStyle(
                color: side.color,
                fontSize: 10,
                height: 1.5,
                fontFamily: technicalFontFamily,
                fontFamilyFallback: technicalFontFallback,
              ),
            ),
    ],
  );

  bool get _canFinishMergePreview {
    final files = _mergePreview?.conflictFiles ?? const <String>[];
    return files.isNotEmpty && files.every(_mergeResolvedFiles.contains);
  }

  String? get _selectedRebaseConflictPath {
    final preview = _rebasePreview;
    final current = preview?.currentCommit;
    if (preview == null || current == null || preview.conflictFiles.isEmpty) {
      return null;
    }
    final selected = _previewPaths[_previewKey(current)];
    return preview.conflictFiles.contains(selected)
        ? selected
        : preview.conflictFiles.first;
  }

  bool get _canContinueRebasePreview {
    final files = _rebasePreview?.conflictFiles ?? const <String>[];
    return files.isNotEmpty &&
        files.every(
          (path) =>
              _rebaseResolvedFiles.contains(path) ||
              _rebaseEditedFiles.contains(path),
        );
  }

  Widget _rebaseConflictActions() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_repositoryOperationInProgress)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              '현재 Git 작업을 마친 뒤 해결할 수 있습니다',
              style: TextStyle(color: behindOrange, fontSize: 10),
            ),
          ),
        if (_rebasePreviewError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              _rebasePreviewError.toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: behindOrange, fontSize: 10),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 7,
          runSpacing: 7,
          children: [
            OutlinedButton(
              key: const Key('rebase-conflict-open-editor'),
              onPressed:
                  _rebasePreviewBusy ||
                      _repositoryOperationInProgress ||
                      _selectedRebaseConflictPath == null
                  ? null
                  : () => unawaited(
                      _openBranchPreviewConflictEditor(mergeMode: false),
                    ),
              child: const Text('편집기로 열기'),
            ),
            TextButton(
              key: const Key('rebase-conflict-abort'),
              onPressed: _rebasePreviewBusy
                  ? null
                  : () => _setBranchPreviewMode(BranchPreviewMode.merge),
              child: const Text('미리보기 중단'),
            ),
            FilledButton(
              key: const Key('rebase-conflict-continue'),
              onPressed:
                  !_rebasePreviewBusy &&
                      !_repositoryOperationInProgress &&
                      _canContinueRebasePreview
                  ? () => unawaited(_continueRebasePreview())
                  : null,
              child: const Text('계속'),
            ),
          ],
        ),
      ],
    ),
  );
}
