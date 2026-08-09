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
          if (_rebaseApplyMergeEffective) {
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

  /// 재계산이 사실은 기준과 비교를 맞바꾸는 경우. 비교 대상이 기준 브랜치의 추적
  /// 브랜치라, 재배치 결과를 받을 로컬 브랜치가 기준 브랜치 자신이다. 다시 계산할
  /// 다른 브랜치가 없으니 기준을 그 원격으로 옮겨야 방향이 선다.
  bool get _recalculateBySwappingSides {
    final comparison = _comparison;
    final target = _branchPreviewTarget;
    return comparison != null &&
        target != null &&
        target.needsRecalculation &&
        target.localBranch == comparison.baseRef;
  }

  String get _branchPreviewApplyLabel {
    final comparison = _comparison!;
    final target = _branchPreviewTarget;
    // 받을 로컬 브랜치가 없으면 무엇을 적용한다고 적을 수도 없다.
    if (target == null) return '실제 적용 불가';
    if (target.needsRecalculation) {
      return _recalculateBySwappingSides
          ? '${comparison.compareRef} 기준으로 다시 계산'
          : '로컬 ${target.localBranch} 기준으로 다시 계산';
    }
    // Rebase 쪽은 무엇을 적용할지 카드의 선택이 말하니 버튼 문구는 고정이다.
    return _branchPreviewMode == BranchPreviewMode.merge
        ? '${comparison.compareRef}를 ${target.localBranch}에 Merge 실제 적용'
        : '실제 적용하기';
  }

  String get _branchPreviewApplyHelp {
    final comparison = _comparison!;
    final target = _branchPreviewTarget;
    if (target == null) {
      return _baseBranchIsRemote
          ? '기준 ${comparison.baseRef}은 원격 브랜치라 결과를 받을 로컬 브랜치가 없습니다.'
          : '적용할 로컬 브랜치를 찾을 수 없습니다.';
    }
    if (target.needsRecalculation) {
      return _recalculateBySwappingSides
          ? '${comparison.compareRef} 기준으로 다시 계산하면 로컬 ${target.localBranch} 브랜치를 그 위로 재배치합니다.'
          : '기존 로컬 ${target.localBranch} 기준으로 다시 계산해야 합니다.';
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
            mergeCommit: _rebaseApplyMergeEffective,
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

extension _TimelineBranchPreviewFlows on _TimelineScreenState {
  /// A merge or rebase preview is worth seeing the moment it exists, so the
  /// detail pane opens itself rather than waiting for a conflict to force it.
  /// A pane the user already placed is left where it is.
  Future<void> _openPaneForBranchPreview() async {
    if (_comparison == null || !mounted) return;
    if (_previewController.previewPlacement != PreviewPlacement.closed) return;
    await _previewController.setPreview(widget.preferredPreviewPlacement);
  }

  Future<void> _selectComparison(
    String compareRef, {
    bool preserveCurrent = false,
  }) async {
    final baseRef = _baseBranch;
    if (_branchApplyBusy || baseRef == null || compareRef == baseRef) return;
    final serial = ++_comparisonSerial;
    if (!preserveCurrent) {
      _dropMergePreview();
      _dropRebasePreview();
      _rebuild(() {
        _compareRef = compareRef;
        _resetBranchApply();
        _comparison = null;
        _comparisonRows = [];
        _comparisonEntries = [];
        _previewGraph = null;
        _rebaseCheck = null;
        _dropRecommendation();
        _dropCommitBadges();
        _comparisonError = null;
        _selectedIndex.value = 0;
      });
    }
    try {
      final result = await widget.repository.compareBranches(
        baseRef,
        compareRef,
      );
      if (!mounted ||
          serial != _comparisonSerial ||
          _baseBranch != baseRef ||
          _compareRef != compareRef) {
        return;
      }
      final rows = layoutBranchComparison(result.commits);
      if (preserveCurrent) {
        _dropMergePreview();
        _dropRebasePreview();
      }
      _rebuild(() {
        _compareRef = compareRef;
        _resetBranchApply();
        _comparison = result;
        _previewGraph = _branchPreviewMode == BranchPreviewMode.merge
            ? layoutMergePreviewGraph(result)
            : null;
        _comparisonRows = _previewGraph?.rows ?? rows;
        _comparisonEntries = [
          for (var index = 0; index < _comparisonRows.length; index++)
            (rowIndex: index, label: null, row: _comparisonRows[index]),
        ];
        _rebaseCheck = null;
        _dropRecommendation();
        _dropCommitBadges();
        _comparisonError = null;
        _selectedIndex.value = 0;
      });
      _scheduleRatchetUpdate();
      _showFirstComparisonRow();
      unawaited(_loadDuplicateCommits(result, serial));
      unawaited(_loadConflictForecast(result, serial));
      unawaited(_openPaneForBranchPreview());
      if (_branchPreviewMode == BranchPreviewMode.rebase) {
        unawaited(_startRebasePreview());
      } else if (result.merge.status == MergeConflictStatus.conflicts) {
        unawaited(_startMergePreview());
        // 이 경로에는 재배치 실측이 없으니 추천 엔진이 직접 시뮬레이션한다.
        unawaited(_loadRecommendation(result, serial));
      } else {
        unawaited(_checkRebase(baseRef, compareRef, serial));
      }
    } catch (error) {
      if (!mounted ||
          serial != _comparisonSerial ||
          _compareRef != compareRef) {
        return;
      }
      _rebuild(() => _comparisonError = error);
    }
  }

  /// P3 — 충돌 파일마다 '양쪽 유지' 자격을 미리 물어 둔다. 자격이 있는 파일만
  /// 지도에 남고 그 파일에만 세 번째 버튼이 생긴다.
  Future<void> _loadKeepBothCandidates(
    Future<KeepBothCandidate?> Function(String path) probe,
    List<String> paths,
    bool Function() stale,
  ) async {
    final request = ++_keepBothSerial;
    for (final path in paths) {
      try {
        final candidate = await probe(path);
        if (!mounted || request != _keepBothSerial || stale()) return;
        if (candidate == null) continue;
        _rebuild(() => _keepBothCandidates[path] = candidate);
      } catch (_) {
        // 제안은 부가 기능이라 실패하면 버튼 없이 기존 선택지만 남는다.
      }
    }
  }

  Future<void> _startMergePreview() async {
    final comparison = _comparison;
    if (_branchPreviewMode != BranchPreviewMode.merge ||
        comparison == null ||
        comparison.merge.status != MergeConflictStatus.conflicts) {
      return;
    }
    final request = ++_mergePreviewSerial;
    final previous = _mergePreviewSession;
    _mergePreviewSession = null;
    _mergePreview = null;
    if (previous != null) await previous.dispose();
    if (!mounted ||
        request != _mergePreviewSerial ||
        _branchPreviewMode != BranchPreviewMode.merge) {
      return;
    }
    try {
      final session = await widget.repository.openMergePreview(
        baseRef: comparison.baseRef,
        compareRef: comparison.compareRef,
      );
      if (!mounted ||
          request != _mergePreviewSerial ||
          _comparison != comparison ||
          _branchPreviewMode != BranchPreviewMode.merge) {
        await session.dispose();
        return;
      }
      _mergePreviewSession = session;
      final result = await session.start();
      if (!mounted ||
          request != _mergePreviewSerial ||
          _comparison != comparison ||
          _branchPreviewMode != BranchPreviewMode.merge) {
        await session.dispose();
        return;
      }
      if (result.baseTip != comparison.baseTip ||
          result.compareTip != comparison.compareTip) {
        _mergePreviewSession = null;
        await session.dispose();
        if (!mounted || request != _mergePreviewSerial) return;
        _rebuild(() {
          _mergePreview = MergePreviewResult(
            status: MergePreviewStatus.failed,
            baseTip: result.baseTip,
            compareTip: result.compareTip,
            error: '브랜치가 변경되었습니다. 미리보기를 다시 선택해 주세요.',
          );
          _mergePreviewError = _mergePreview!.error;
        });
        return;
      }
      _rebuild(() {
        _mergePreview = result;
        _mergePreviewError = null;
        _mergeResolvedFiles.clear();
        _dropKeepBoth();
      });
      if (result.status == MergePreviewStatus.conflict) {
        unawaited(
          _loadKeepBothCandidates(
            session.keepBothCandidate,
            result.conflictFiles,
            () => !identical(_mergePreviewSession, session),
          ),
        );
      }
      if (result.status == MergePreviewStatus.conflict &&
          _previewController.previewPlacement == PreviewPlacement.closed) {
        await _previewController.setPreview(widget.preferredPreviewPlacement);
      }
    } catch (error) {
      if (mounted && request == _mergePreviewSerial) {
        _rebuild(() => _mergePreviewError = error);
      }
    }
  }

  Future<void> _startRebasePreview() async {
    final comparison = _comparison;
    if (_branchPreviewMode != BranchPreviewMode.rebase || comparison == null) {
      return;
    }
    final request = ++_rebasePreviewSerial;
    final previous = _rebasePreviewSession;
    _rebasePreviewSession = null;
    _rebasePreview = null;
    if (previous != null) await previous.dispose();
    if (!mounted ||
        request != _rebasePreviewSerial ||
        _branchPreviewMode != BranchPreviewMode.rebase) {
      return;
    }
    _rebuild(() => _rebaseCheck = null);
    try {
      final session = await widget.repository.openRebasePreview(
        baseRef: comparison.baseRef,
        compareRef: comparison.compareRef,
      );
      if (!mounted ||
          request != _rebasePreviewSerial ||
          _comparison != comparison ||
          _branchPreviewMode != BranchPreviewMode.rebase) {
        await session.dispose();
        return;
      }
      _rebasePreviewSession = session;
      final result = await session.start();
      if (!mounted ||
          request != _rebasePreviewSerial ||
          _comparison != comparison ||
          _branchPreviewMode != BranchPreviewMode.rebase) {
        await session.dispose();
        return;
      }
      await _applyRebasePreviewResult(comparison, result, request);
    } catch (error) {
      if (!mounted || request != _rebasePreviewSerial) return;
      _rebuild(
        () => _rebaseCheck = RebaseCheckResult(
          status: RebaseCheckStatus.failed,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> _applyRebasePreviewResult(
    BranchComparisonResult comparison,
    RebasePreviewResult result,
    int request,
  ) async {
    if (result.baseTip != comparison.baseTip ||
        result.compareTip != comparison.compareTip) {
      final session = _rebasePreviewSession;
      _rebasePreviewSession = null;
      await session?.dispose();
      if (!mounted ||
          request != _rebasePreviewSerial ||
          _branchPreviewMode != BranchPreviewMode.rebase ||
          _comparison != comparison) {
        return;
      }
      const message = '브랜치가 변경되었습니다. 미리보기를 다시 선택해 주세요.';
      _rebuild(() {
        _rebasePreview = RebasePreviewResult(
          status: RebasePreviewStatus.failed,
          baseTip: result.baseTip,
          compareTip: result.compareTip,
          error: message,
        );
        _rebasePreviewError = message;
        _rebaseCheck = const RebaseCheckResult(
          status: RebaseCheckStatus.failed,
          error: message,
        );
      });
      return;
    }
    final graph = layoutRebasePreviewGraph(
      comparison,
      result,
      mergeCommit: _rebaseApplyMergeEffective,
    );
    final conflictIndex = graph.rows.indexWhere(
      (row) => row.commit.sha == result.currentCommit?.sha,
    );
    final session = _rebasePreviewSession;
    final operationInProgress = result.status == RebasePreviewStatus.conflict
        ? await widget.repository.operationInProgress()
        : false;
    if (!mounted ||
        request != _rebasePreviewSerial ||
        _branchPreviewMode != BranchPreviewMode.rebase ||
        _comparison != comparison ||
        !identical(_rebasePreviewSession, session)) {
      return;
    }
    _rebuild(() {
      _rebasePreview = result;
      if (result.status == RebasePreviewStatus.conflict) {
        _rebaseHadConflict = true;
      }
      _rebasePreviewError = null;
      _repositoryOperationInProgress = operationInProgress;
      _rebaseResolvedFiles.clear();
      _rebaseEditedFiles.clear();
      _dropKeepBoth();
      _rebaseCheck = switch (result.status) {
        RebasePreviewStatus.clean => const RebaseCheckResult(
          status: RebaseCheckStatus.clean,
        ),
        RebasePreviewStatus.conflict => RebaseCheckResult(
          status: RebaseCheckStatus.conflicts,
          stoppedCommit: result.currentCommit?.sha,
          files: result.conflictFiles,
        ),
        RebasePreviewStatus.failed => RebaseCheckResult(
          status: RebaseCheckStatus.failed,
          error: result.error,
        ),
      };
      _previewGraph = graph;
      _comparisonRows = graph.rows;
      _comparisonEntries = [
        for (var index = 0; index < graph.rows.length; index++)
          (rowIndex: index, label: null, row: graph.rows[index]),
      ];
      _selectedIndex.value =
          result.status == RebasePreviewStatus.conflict && conflictIndex >= 0
          ? conflictIndex
          : 0;
    });
    _showPreviewTop();
    if (_rebaseCheck case final check?) {
      unawaited(
        _loadRecommendation(comparison, _comparisonSerial, rebaseCheck: check),
      );
    }
    if (result.status == RebasePreviewStatus.conflict && session != null) {
      unawaited(
        _loadKeepBothCandidates(
          session.keepBothCandidate,
          result.conflictFiles,
          () => !identical(_rebasePreviewSession, session),
        ),
      );
    }
    if (result.status == RebasePreviewStatus.conflict &&
        _previewController.previewPlacement == PreviewPlacement.closed) {
      await _previewController.setPreview(widget.preferredPreviewPlacement);
    }
    _scheduleRatchetUpdate();
    if (result.status == RebasePreviewStatus.clean) {
      _showFirstComparisonRow();
    } else if (result.status == RebasePreviewStatus.conflict) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rowContext = _rebaseConflictRowContextKey.currentContext;
        if (!mounted || rowContext == null) return;
        unawaited(
          Scrollable.ensureVisible(
            rowContext,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          ),
        );
      });
    }
  }

  void _clearComparison() {
    if (_branchApplyBusy || _compareRef == null) return;
    _dropMergePreview();
    _dropRebasePreview();
    _comparisonSerial++;
    _rebuild(() {
      _compareRef = null;
      _resetBranchApply();
      _comparison = null;
      _comparisonRows = [];
      _comparisonEntries = [];
      _previewGraph = null;
      _rebaseCheck = null;
      _dropRecommendation();
      _dropCommitBadges();
      _comparisonError = null;
      if (_normalEntries.isNotEmpty) {
        _selectedIndex.value = _selectedIndex.value.clamp(
          0,
          _normalEntries.length - 1,
        );
      }
    });
    _scheduleRatchetUpdate();
    _focusNode.requestFocus();
  }

  Future<void> _prepareBranchPreviewApply() async {
    final target = _branchPreviewTarget;
    if (target == null || !_branchPreviewReady || _branchApplyBusy) return;
    if (target.needsRecalculation) {
      // 맞바꾸는 쪽은 재계산할 상대가 기준 브랜치 자신이라, 기준을 원격으로 옮기고
      // 그 로컬 브랜치를 비교 대상으로 세운다. 알림은 실제로 옮긴 뒤에 띄운다.
      final swap = _recalculateBySwappingSides;
      final comparison = _comparison!;
      final nextBase = swap ? comparison.compareRef : _baseBranch;
      final nextCompare = swap ? comparison.baseRef : target.localBranch;
      if (swap) _selectBaseBranch(nextBase!);
      await _selectComparison(nextCompare);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            swap
                ? '$nextBase 기준으로 미리보기를 다시 계산했습니다.'
                : '기존 로컬 $nextCompare 기준으로 미리보기를 다시 계산했습니다.',
          ),
        ),
      );
      return;
    }
    await _confirmBranchPreviewApply();
  }

  Future<void> _confirmBranchPreviewApply() async {
    final rebaseThenMerge = _rebaseThenMergeSelected;
    final comparison = _comparison;
    final target = _branchPreviewTarget;
    if (comparison == null ||
        target == null ||
        !_branchPreviewCanApply ||
        _branchApplyBusy) {
      return;
    }
    final merge = _branchPreviewMode == BranchPreviewMode.merge;
    // An apply that writes a merge commit asks for its message instead of a
    // confirmation: writing the message is the confirmation. A plain rebase
    // carries the original messages over, so there is nothing to write.
    if (merge || rebaseThenMerge) {
      final message = await showYogitAlert<String>(
        context,
        CommitMessageDialog(
          lead: merge
              ? '${comparison.baseRef} ← ${comparison.compareRef} · '
              : '${comparison.compareRef} 재배치 → ',
          emphasis: merge
              ? '머지 커밋 1개 생성'
              : '머지 커밋 1개로 ${comparison.baseRef} 이동',
          message: renderCommitMessageTemplate(
            merge
                ? widget.mergeMessageTemplate
                : widget.rebaseMergeMessageTemplate,
            source: comparison.compareRef,
            target: comparison.baseRef,
            profile: _commitMessageProfile,
          ),
          templated:
              (merge
                      ? widget.mergeMessageTemplate
                      : widget.rebaseMergeMessageTemplate)
                  .trim()
                  .isNotEmpty,
        ),
      );
      if (message != null && mounted) {
        await _runBranchPreviewApply(comparison, message: message);
      }
      return;
    }
    // 남은 길은 'Rebase만' 하나뿐이라 문구도 그 한 가지다.
    final confirmed = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: 'Rebase를 실제로 적용할까요?',
        message:
            '로컬 ${target.localBranch} 브랜치만 변경합니다. '
            '원격 추적 브랜치와 원격 저장소는 그대로입니다.',
        body: YogitAlertBlock([
          '기준 ${comparison.baseRef}  ${comparison.baseTip}',
          '대상 ${comparison.compareRef}  ${comparison.compareTip}',
        ]),
        detail: '완료 뒤 적용 전 SHA로 되돌릴 수 있습니다.',
        confirmLabel: '적용',
        confirmKey: const Key('branch-apply-confirm'),
      ),
    );
    if (confirmed == true && mounted) {
      await _runBranchPreviewApply(comparison);
    }
  }

  Future<void> _runBranchPreviewApply(
    BranchComparisonResult comparison, {
    String? message,
  }) async {
    final rebaseThenMerge = _rebaseThenMergeSelected;
    final mode = _branchPreviewMode;
    final request = ++_branchApplySerial;
    _rebuild(() {
      _branchApplyStatus = BranchApplyStatus.applying;
      _branchApplyError = null;
    });
    try {
      BranchApplyResult result;
      if (mode == BranchPreviewMode.merge) {
        result = await widget.repository.applyMergePreview(
          comparison: comparison,
          treeSha: (_mergePreview?.treeSha ?? comparison.merge.treeSha)!,
          message: message,
        );
      } else {
        final preview = _rebasePreview!;
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220);
        // 훑고 지나가는 건 가상 행이라 그래프가 정한 키로 찾는다.
        final rebaseMappings = _previewGraph?.mappings ?? const [];
        for (var index = 0; index < preview.rewritten.length; index++) {
          if (!mounted || request != _branchApplySerial) return;
          final sha = index < rebaseMappings.length
              ? rebaseMappings[index].rewrittenSha
              : preview.rewritten[index].rewrittenSha;
          final row = _comparisonRows.indexWhere(
            (entry) => entry.commit.sha == sha,
          );
          _rebuild(() => _rebaseApplyingSha = sha);
          if (row >= 0) _selectedIndex.value = row;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final rowContext = _rebaseApplyRowContextKey.currentContext;
            if (!mounted || rowContext == null) return;
            unawaited(
              Scrollable.ensureVisible(
                rowContext,
                duration: duration,
                curve: Curves.easeOut,
              ),
            );
          });
          if (duration > Duration.zero) await Future<void>.delayed(duration);
        }
        result = rebaseThenMerge
            ? await widget.repository.applyRebaseThenMerge(
                comparison: comparison,
                virtualTip: preview.virtualTip!,
                message: message,
              )
            : await widget.repository.applyRebasePreview(
                comparison: comparison,
                virtualTip: preview.virtualTip!,
              );
      }
      if (!mounted || request != _branchApplySerial) return;
      final mergeSession = _mergePreviewSession;
      final rebaseSession = _rebasePreviewSession;
      _rebuild(() {
        _branchApplyStatus = BranchApplyStatus.applied;
        _branchApplyResult = result;
        _rebaseApplyingSha = null;
        if (mode == BranchPreviewMode.merge) {
          _mergePreviewSession = null;
        } else {
          _rebasePreviewSession = null;
        }
      });
      // 카드가 짧아지면서 스크롤이 내용 밖에 남을 수 있으니 결과를 위에서 보여준다.
      _showPreviewTop();
      if (mode == BranchPreviewMode.merge && mergeSession != null) {
        unawaited(mergeSession.dispose());
      } else if (mode == BranchPreviewMode.rebase && rebaseSession != null) {
        unawaited(rebaseSession.dispose());
      }
    } catch (error) {
      if (!mounted || request != _branchApplySerial) return;
      _rebuild(() {
        _branchApplyStatus = BranchApplyStatus.failed;
        _branchApplyError = error;
        _rebaseApplyingSha = null;
      });
    }
  }

  Future<void> _confirmBranchPreviewRollback() async {
    final result = _branchApplyResult;
    if (result == null || _branchApplyStatus != BranchApplyStatus.applied) {
      return;
    }
    final confirmed = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title:
            '${_TimelineScreenState._applyModeLabel(result.mode)} 이전 시점으로 되돌릴까요?',
        body: YogitAlertBlock(
          _branchPreviewRollbackMessage(result).split('\n'),
        ),
        role: YogitAlertRole.destructive,
        confirmLabel: '되돌리기',
        confirmKey: const Key('branch-rollback-confirm'),
      ),
    );
    if (confirmed != true || !mounted) return;
    final request = ++_branchApplySerial;
    _rebuild(() {
      _branchApplyStatus = BranchApplyStatus.reverting;
      _branchApplyError = null;
    });
    try {
      await widget.repository.restoreBranchApply(result);
      if (mounted && request == _branchApplySerial) {
        _rebuild(() => _branchApplyStatus = BranchApplyStatus.reverted);
      }
    } catch (error) {
      if (mounted && request == _branchApplySerial) {
        _rebuild(() {
          _branchApplyStatus = BranchApplyStatus.failed;
          _branchApplyError = error;
        });
      }
    }
  }

  /// The two ways a clean rebase preview can land, as one choice: replay the
  /// commits, or replay them and put one merge commit over them. What is
  /// selected is what both graphs draw and what the button applies.
  List<Widget> _branchPreviewApplyOptions() {
    final comparison = _comparison;
    // 옮길 커밋이 하나도 없으면 재배치 결과가 곧 기준 브랜치라 얹을 머지 커밋이
    // 없다. 고를 것이 하나뿐이면 라디오도 내보내지 않는다.
    if (comparison == null || (_rebasePreview?.rewritten.isEmpty ?? true)) {
      return const [];
    }
    Widget option({
      required Key key,
      required bool mergeCommit,
      required String title,
      required String description,
      Key? descriptionKey,
    }) {
      final selected = _rebaseApplyMergeEffective == mergeCommit;
      return Padding(
        padding: const EdgeInsets.only(top: 7),
        child: InkWell(
          key: key,
          onTap: _branchApplyBusy
              ? null
              : () => _selectRebaseApplyMerge(mergeCommit),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? previewPurple.withValues(alpha: 0.08)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? const Color(0xFF9D79D0)
                    : const Color(0xFF4A4157),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    width: 14,
                    height: 14,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? previewPurple
                            : const Color(0xFF8A8494),
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: previewPurple,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFFE8DCFF)
                              : _palette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        key: descriptionKey,
                        style: TextStyle(color: _palette.muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return [
      option(
        key: const Key('branch-preview-option-rebase'),
        mergeCommit: false,
        title: 'Rebase만',
        description:
            '${comparison.compareRef}를 ${comparison.baseRef} 위로 재배치합니다. '
            '${comparison.baseRef}은 움직이지 않습니다.',
      ),
      // 기준이 원격이면 머지 커밋을 얹어도 옮길 로컬 기준 브랜치가 없다.
      if (!_baseBranchIsRemote)
        option(
          key: const Key('branch-preview-option-rebase-merge'),
          mergeCommit: true,
          title: 'Rebase 후 Merge 커밋으로 병합',
          descriptionKey: const Key('branch-preview-rebase-merge-caption'),
          description:
              '재배치한 커밋 위에 머지 커밋 하나를 만들어 ${comparison.baseRef}을 옮깁니다. '
              '${comparison.baseRef}이 체크아웃돼 있지 않으면 포인터만 이동합니다.',
        ),
    ];
  }

  Future<void> _dropResolvedBranchPreview() async {
    if (_branchApplyBusy) return;
    final mergeSession = _mergePreviewSession;
    final rebaseSession = _rebasePreviewSession;
    _rebuild(() {
      _mergePreviewSession = null;
      _rebasePreviewSession = null;
      _resetBranchApply();
      _dropCommitBadges();
      _dropKeepBoth();
      _branchPreviewDropped = true;
    });
    await mergeSession?.dispose();
    await rebaseSession?.dispose();
  }

  /// 고른 순서의 결합 내용을 쓰고 해결로 표시한다. 파일은 그 뒤로도 편집할 수 있고
  /// 마커가 남으면 markResolved가 막는다(P1a).
  Future<void> _applyKeepBoth(
    String path,
    KeepBothCandidate candidate, {
    required bool mergeMode,
    required bool baseFirst,
  }) async {
    final mergeSession = _mergePreviewSession;
    final rebaseSession = _rebasePreviewSession;
    if ((mergeMode ? mergeSession == null : rebaseSession == null) ||
        (mergeMode ? _mergePreviewBusy : _rebasePreviewBusy) ||
        _repositoryOperationInProgress) {
      return;
    }
    _rebuild(() {
      if (mergeMode) {
        _mergePreviewBusy = true;
        _mergePreviewError = null;
      } else {
        _rebasePreviewBusy = true;
        _rebasePreviewError = null;
      }
    });
    try {
      final content = baseFirst ? candidate.baseFirst : candidate.branchFirst;
      if (mergeMode) {
        await mergeSession!.applyKeepBoth(path, content);
      } else {
        await rebaseSession!.applyKeepBoth(path, content);
      }
      if (!mounted) return;
      _rebuild(() {
        if (mergeMode) {
          _mergeResolvedFiles.add(path);
        } else {
          _rebaseResolvedFiles.add(path);
        }
        _keepBothCandidates.remove(path);
        _keepBothOpenPath = null;
        _previewDiffs.removeWhere((key, _) => key.path == path);
      });
    } catch (error) {
      if (mounted) {
        _rebuild(() {
          if (mergeMode) {
            _mergePreviewError = error;
          } else {
            _rebasePreviewError = error;
          }
        });
      }
    } finally {
      if (mounted) {
        _rebuild(() {
          if (mergeMode) {
            _mergePreviewBusy = false;
          } else {
            _rebasePreviewBusy = false;
          }
        });
      }
    }
  }

  Future<void> _finishMergePreview() async {
    final session = _mergePreviewSession;
    if (session == null || !_canFinishMergePreview || _mergePreviewBusy) return;
    _rebuild(() {
      _mergePreviewBusy = true;
      _mergePreviewError = null;
    });
    try {
      final result = await session.finish();
      if (!mounted || !identical(session, _mergePreviewSession)) return;
      _rebuild(() {
        _mergePreview = result;
        _previewFiles.clear();
        _previewFileLists.clear();
        _previewDiffs.clear();
      });
      _showPreviewTop();
    } catch (error) {
      if (mounted) _rebuild(() => _mergePreviewError = error);
    } finally {
      if (mounted) _rebuild(() => _mergePreviewBusy = false);
    }
  }

  Future<void> _resolveRebaseConflict(RebaseConflictChoice choice) async {
    final session = _rebasePreviewSession;
    final path = _selectedRebaseConflictPath;
    if (session == null ||
        path == null ||
        _rebasePreviewBusy ||
        _repositoryOperationInProgress) {
      return;
    }
    _rebuild(() {
      _rebasePreviewBusy = true;
      _rebasePreviewError = null;
    });
    try {
      await session.resolveFile(path, choice);
      if (mounted && identical(session, _rebasePreviewSession)) {
        _rebuild(() {
          _rebaseResolvedFiles.add(path);
          _keepBothCandidates.remove(path);
          if (_keepBothOpenPath == path) _keepBothOpenPath = null;
          _previewDiffs.removeWhere((key, _) => key.path == path);
        });
      }
    } catch (error) {
      if (mounted) _rebuild(() => _rebasePreviewError = error);
    } finally {
      if (mounted) _rebuild(() => _rebasePreviewBusy = false);
    }
  }

  Future<void> _continueRebasePreview() async {
    final session = _rebasePreviewSession;
    final comparison = _comparison;
    final request = _rebasePreviewSerial;
    if (session == null ||
        comparison == null ||
        !_canContinueRebasePreview ||
        _rebasePreviewBusy) {
      return;
    }
    _rebuild(() {
      _rebasePreviewBusy = true;
      _rebasePreviewError = null;
    });
    try {
      for (final path in _rebaseEditedFiles.difference(_rebaseResolvedFiles)) {
        await session.markResolved(path);
      }
      final result = await session.continueAfterResolving();
      if (!mounted ||
          request != _rebasePreviewSerial ||
          !identical(session, _rebasePreviewSession)) {
        return;
      }
      await _applyRebasePreviewResult(comparison, result, request);
    } catch (error) {
      if (mounted &&
          request == _rebasePreviewSerial &&
          identical(session, _rebasePreviewSession)) {
        _rebuild(() => _rebasePreviewError = error);
      }
    } finally {
      if (mounted &&
          request == _rebasePreviewSerial &&
          identical(session, _rebasePreviewSession)) {
        _rebuild(() => _rebasePreviewBusy = false);
      }
    }
  }

  Future<void> _openBranchPreviewConflictEditor({
    required bool mergeMode,
  }) async {
    final mergeSession = _mergePreviewSession;
    final rebaseSession = _rebasePreviewSession;
    final path = mergeMode
        ? _selectedMergeConflictPath
        : _selectedRebaseConflictPath;
    final worktree = mergeMode
        ? mergeSession?.worktreePath
        : rebaseSession?.worktreePath;
    if ((mergeMode ? mergeSession == null : rebaseSession == null) ||
        path == null ||
        worktree == null ||
        (mergeMode ? _mergePreviewBusy : _rebasePreviewBusy) ||
        _repositoryOperationInProgress) {
      return;
    }
    _rebuild(() {
      if (mergeMode) {
        _mergePreviewBusy = true;
        _mergePreviewError = null;
      } else {
        _rebasePreviewBusy = true;
        _rebasePreviewError = null;
      }
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
        items: const [
          PopupMenuItem(value: 'internal', child: Text('내장 에디터')),
          PopupMenuItem(value: 'external', child: Text('외부 에디터')),
        ],
      );
      if (!mounted || choice == null) return;
      final externalEditor = ExternalEditorService(repositoryRoot: worktree);
      if (choice == 'external') {
        await externalEditor.open(relativePath: path);
        if (mounted) _rebuild(() => _rebaseEditedFiles.add(path));
        return;
      }
      final document =
          await widget.documentLoaderForTesting?.call(path) ??
          await WorkingTreeTextDocument.load(
            repositoryRoot: worktree,
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
              if (mergeMode) {
                await mergeSession!.markResolved(path);
              } else {
                await rebaseSession!.markResolved(path);
              }
              if (mounted) {
                _rebuild(() {
                  if (mergeMode) {
                    _mergeResolvedFiles.add(path);
                  } else {
                    _rebaseEditedFiles.add(path);
                    _rebaseResolvedFiles.add(path);
                  }
                  _previewDiffs.removeWhere((key, _) => key.path == path);
                });
                Navigator.of(context).pop();
              }
            },
            onOpenExternal: () async {
              await externalEditor.open(relativePath: path);
              if (mounted && !mergeMode) {
                _rebuild(() => _rebaseEditedFiles.add(path));
              }
            },
            editorForTesting: widget.editorForTesting,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        _rebuild(() {
          if (mergeMode) {
            _mergePreviewError = error;
          } else {
            _rebasePreviewError = error;
          }
        });
      }
    } finally {
      if (mounted) {
        _rebuild(() {
          if (mergeMode) {
            _mergePreviewBusy = false;
          } else {
            _rebasePreviewBusy = false;
          }
        });
      }
    }
  }
}
