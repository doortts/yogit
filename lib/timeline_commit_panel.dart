part of 'timeline.dart';

/// 커밋 패널: 작업 트리 행을 고르면 미리보기 판이 되는 것. Unstaged / Staged 두
/// 섹션과 그 위의 파일 단위 조작, 그리고 인덱스를 커밋하는 폼이 여기 산다.
///
/// 승인된 시안: docs/commit-mode-mockup.html.

/// 커밋 버튼의 전경. 시안의 `#0F1A13`으로, 초록 위에 얹는 이 어두운 글자색을
/// 담을 토큰이 팔레트에 없다.
const _commitButtonForeground = Color(0xFF0F1A13);

/// 제목 한 줄의 관례적 길이. 넘으면 색만 바뀌고 입력은 막지 않는다.
const _commitSubjectLimit = 50;

extension _TimelineCommitPanel on _TimelineScreenState {
  Future<WorkingTreeStatus> _readWorkingTreeStatus() async {
    final status = await widget.repository.loadWorkingTreeStatus();
    _commitStatus = status;
    return status;
  }

  Widget _commitPanel(GitCommit commit) => FutureBuilder<WorkingTreeStatus>(
    future: _commitStatusRequest ??= _readWorkingTreeStatus(),
    builder: (context, snapshot) {
      final status = snapshot.data ?? _commitStatus;
      if (status == null && snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            '${snapshot.error}',
            key: const Key('commit-status-error'),
            style: const TextStyle(color: hashRed, fontSize: 11),
          ),
        );
      }
      final hasHead = commit.parents.isNotEmpty;
      return Column(
        key: const Key('commit-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _commitSection(
                    WorkingTreeArea.unstaged,
                    status?.unstaged ?? const [],
                    hasHead: hasHead,
                  ),
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(top: 6, bottom: 2),
                    color: _palette.border,
                  ),
                  _commitSection(
                    WorkingTreeArea.staged,
                    status?.staged ?? const [],
                    hasHead: hasHead,
                  ),
                ],
              ),
            ),
          ),
          _commitForm(commit, status),
        ],
      );
    },
  );

  Widget _commitSection(
    WorkingTreeArea area,
    List<WorkingTreeEntry> entries, {
    required bool hasHead,
  }) {
    final unstaged = area == WorkingTreeArea.unstaged;
    final collapsed = unstaged
        ? _commitUnstagedCollapsed
        : _commitStagedCollapsed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('commit-section-${area.name}'),
          onTap: () => _rebuild(() {
            if (unstaged) {
              _commitUnstagedCollapsed = !collapsed;
            } else {
              _commitStagedCollapsed = !collapsed;
            }
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 5),
            child: Row(
              children: [
                Text(
                  collapsed ? '▸' : '▾',
                  style: TextStyle(color: _palette.muted, fontSize: 9),
                ),
                const SizedBox(width: 7),
                Text(
                  unstaged ? 'Unstaged' : 'Staged',
                  style: TextStyle(
                    color: _palette.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: _palette.raised,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${entries.length}',
                    style: TextStyle(
                      color: _palette.muted,
                      fontSize: 10.5,
                      height: 16 / 10.5,
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  key: Key(
                    unstaged ? 'commit-stage-all' : 'commit-unstage-all',
                  ),
                  onTap: _commitModeBusy || entries.isEmpty
                      ? null
                      : () => unawaited(
                          _runCommitAction(
                            unstaged
                                ? () => widget.repository.stageFiles(const [])
                                : () => widget.repository.unstageFiles(
                                    const [],
                                    hasHead: hasHead,
                                  ),
                          ),
                        ),
                  child: Text(
                    unstaged ? 'Stage All' : 'Unstage All',
                    style: TextStyle(
                      color: _palette.interactive,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          for (final entry in entries)
            _commitFileRow(entry, area, hasHead: hasHead),
      ],
    );
  }

  /// 행 글자는 섹션이 정한다 — Unstaged는 Y축, Staged는 X축. 통계 자리는 마우스가
  /// 올라오면 그 축에서 할 수 있는 조작으로 바뀐다.
  Widget _commitFileRow(
    WorkingTreeEntry entry,
    WorkingTreeArea area, {
    required bool hasHead,
  }) {
    final unstaged = area == WorkingTreeArea.unstaged;
    final letter = unstaged ? entry.worktreeStatus : entry.indexStatus;
    final additions = unstaged
        ? entry.unstagedAdditions
        : entry.stagedAdditions;
    final deletions = unstaged
        ? entry.unstagedDeletions
        : entry.stagedDeletions;
    final slash = entry.path.lastIndexOf('/');
    final cursor = _commitCursor;
    final selected = cursor?.area == area && cursor?.path == entry.path;
    return HoverBuilder(
      key: Key('commit-row-${area.name}-${entry.path}'),
      builder: (hovered) => InkWell(
        onTap: () {
          _rebuild(() => _commitCursor = (area: area, path: entry.path));
          _openCommitAreaDiff(area, entry.path);
        },
        child: Container(
          color: selected ? _palette.selectedRow : null,
          height: 26,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  child: Text(
                    letter,
                    style: TextStyle(
                      color: entry.conflicted
                          ? previewConflict
                          : switch (letter) {
                              'D' => deletedPink,
                              'R' || 'C' => renamedPurple,
                              _ => mainAccent,
                            },
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (slash >= 0)
                          TextSpan(
                            text: entry.path.substring(0, slash + 1),
                            style: TextStyle(color: _palette.muted),
                          ),
                        TextSpan(text: entry.path.substring(slash + 1)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _palette.text,
                      fontSize: 11.5,
                      fontFamily: technicalFontFamily,
                      fontFamilyFallback: technicalFontFallback,
                    ),
                  ),
                ),
                if (entry.untracked) _commitRowChip('untracked'),
                if (entry.conflicted)
                  _commitRowChip('충돌', color: previewConflict),
                if (entry.submodule) _commitRowChip('서브모듈'),
                if (hovered)
                  ..._commitRowActions(entry, area, hasHead: hasHead)
                else ...[
                  if ((additions ?? 0) > 0)
                    _commitRowStat('+$additions', mainAccent),
                  if ((deletions ?? 0) > 0)
                    _commitRowStat('−$deletions', hashRed),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _commitRowChip(String label, {Color? color}) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      color: color?.withValues(alpha: 0.16) ?? _palette.raised,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      style: TextStyle(color: color ?? _palette.muted, fontSize: 10),
    ),
  );

  Widget _commitRowStat(String label, Color color) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Text(label, style: TextStyle(color: color, fontSize: 10.5)),
  );

  /// Unstaged 행은 Stage와 Discard, Staged 행은 Unstage 하나. 충돌 파일의 Stage는
  /// 마커 검사를 지나고, 충돌과 서브모듈에는 Discard가 없다.
  List<Widget> _commitRowActions(
    WorkingTreeEntry entry,
    WorkingTreeArea area, {
    required bool hasHead,
  }) {
    if (area == WorkingTreeArea.staged) {
      return [
        _commitRowAction(
          key: Key('commit-unstage-${entry.path}'),
          tooltip: 'Unstage File',
          glyph: '−',
          color: behindOrange,
          // rename은 두 경로를 함께 넘긴다 — 옛 경로가 인덱스로 돌아오고 새
          // 경로가 빠진다.
          onTap: () => _runCommitAction(
            () => widget.repository.unstageFiles([
              entry.path,
              ?entry.origPath,
            ], hasHead: hasHead),
          ),
        ),
      ];
    }
    return [
      _commitRowAction(
        key: Key('commit-stage-${entry.path}'),
        tooltip: 'Stage File',
        glyph: '＋',
        color: mainAccent,
        onTap: () => _runCommitAction(
          entry.conflicted
              ? () => widget.repository.stageResolvedFile(entry.path)
              : () => widget.repository.stageFiles([entry.path]),
        ),
      ),
      if (!entry.conflicted && !entry.submodule)
        _commitRowAction(
          key: Key('commit-discard-${entry.path}'),
          tooltip: 'Discard',
          glyph: '↺',
          color: deletedPink,
          onTap: () => _confirmCommitDiscard(entry),
        ),
    ];
  }

  Widget _commitRowAction({
    required Key key,
    required String tooltip,
    required String glyph,
    required Color color,
    required Future<void> Function() onTap,
  }) => Tooltip(
    message: tooltip,
    waitDuration: _tooltipDelay,
    child: Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(5),
        onTap: _commitModeBusy ? null : () => unawaited(onTap()),
        child: Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _palette.raised,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            glyph,
            style: TextStyle(color: color, fontSize: 12, height: 1),
          ),
        ),
      ),
    ),
  );

  /// 파일 행과 filebar 세그먼트가 함께 쓰는 자리. 축이 그대로면 열린 세션에서
  /// 파일만 고르고, 축이 바뀌면 세션을 다시 세운다 — 어댑터가 축을 final로 물고
  /// 있어 갈아 끼울 수가 없다.
  void _openCommitAreaDiff(WorkingTreeArea area, String? path) {
    final commit = _selectedCommit;
    if (commit == null || !commit.isWorkingTree) return;
    if (_fullDiffOpen && _commitDiffArea == area) {
      _showFullDiffFile(path);
      return;
    }
    final previous = _fullDiffSession;
    _rebuild(() => _commitDiffArea = area);
    _openFullDiff(commit, path, focusDiff: false);
    previous
      ?..removeListener(_followFullDiffSession)
      ..dispose();
  }

  /// 세그먼트 전환. 보고 있던 경로가 반대 축에도 있으면 그 파일로, 없으면 그 축의
  /// 첫 파일로 간다.
  void _selectCommitArea(WorkingTreeArea area) {
    final path = _fullDiffSession?.state.selectedFile?.path;
    final entries = _commitAreaEntries(area);
    _openCommitAreaDiff(
      area,
      entries.any((entry) => entry.path == path) ? path : null,
    );
  }

  /// 작업 트리 행이 선택되어 있고 판이 열려 있을 때만 커밋 모드의 키가 산다.
  bool get _commitPanelOpen =>
      _cherryPickState == null &&
      (_selectedCommit?.isWorkingTree ?? false) &&
      _previewController.previewPlacement != PreviewPlacement.closed;

  /// 커서가 걷는 평평한 줄 — 두 섹션을 이어 붙인 것. 접힌 섹션은 빠진다: 보이지
  /// 않는 행에 커서가 앉을 자리는 없다.
  List<({WorkingTreeArea area, String path})> get _commitCursorRows => [
    for (final area in WorkingTreeArea.values)
      if (!(area == WorkingTreeArea.unstaged
          ? _commitUnstagedCollapsed
          : _commitStagedCollapsed))
        for (final entry in _commitAreaEntries(area))
          (area: area, path: entry.path),
  ];

  void _moveCommitCursor(int delta) {
    final rows = _commitCursorRows;
    if (rows.isEmpty) return;
    final cursor = _commitCursor;
    final here = rows.indexWhere(
      (row) => row.area == cursor?.area && row.path == cursor?.path,
    );
    final next = here < 0
        ? (delta > 0 ? 0 : rows.length - 1)
        : (here + delta).clamp(0, rows.length - 1);
    _rebuild(() => _commitCursor = rows[next]);
  }

  /// Space: 커서 행을 그 축의 반대편으로 넘긴다.
  Future<void> _toggleCommitCursorRow() async {
    if (_commitCursor case final cursor?) {
      await _toggleCommitFile(cursor.area, cursor.path);
    }
  }

  /// →로 미리보기에 들어올 때 여는 diff. 커서가 없으면 첫 행이다.
  void _openCommitCursorDiff() {
    final cursor = _commitCursor ?? _commitCursorRows.firstOrNull;
    if (cursor == null) return;
    _rebuild(() => _commitCursor = cursor);
    _openCommitAreaDiff(cursor.area, cursor.path);
  }

  /// ⌘↵의 게이트는 커밋 버튼의 것과 같아야 한다 — 버튼이 막는 것을 키가 지나
  /// 가면 두 입구가 다른 말을 하게 된다.
  bool get _commitReady =>
      !_commitModeBusy &&
      !(_commitStatus?.hasConflict ?? false) &&
      (_commitStatus?.staged.isNotEmpty ?? false) &&
      _commitTitle.text.trim().isNotEmpty;

  List<WorkingTreeEntry> _commitAreaEntries(WorkingTreeArea area) =>
      (area == WorkingTreeArea.unstaged
          ? _commitStatus?.unstaged
          : _commitStatus?.staged) ??
      const [];

  bool _commitAreaSelectable(WorkingTreeArea area) =>
      area == _commitDiffArea || _commitAreaEntries(area).isNotEmpty;

  WorkingTreeEntry? _commitEntryFor(String path) {
    for (final entry in _commitStatus?.entries ?? const <WorkingTreeEntry>[]) {
      if (entry.path == path) return entry;
    }
    return null;
  }

  /// filebar의 Stage File / Unstage File — 패널 행의 것과 같은 조작이고, 무엇을
  /// 하는지는 보고 있는 축이 정한다.
  Future<void> _stageSelectedCommitFile(WorkingTreeArea area) =>
      _toggleCommitFile(area, _fullDiffSession?.state.selectedFile?.path);

  /// 한 파일을 자기 축의 반대편으로 넘긴다. filebar 버튼과 Space가 같은 자리를
  /// 지난다.
  Future<void> _toggleCommitFile(WorkingTreeArea area, String? path) async {
    if (path == null) return;
    final entry = _commitEntryFor(path);
    final hasHead = _selectedCommit?.parents.isNotEmpty ?? true;
    await _runCommitAction(
      area == WorkingTreeArea.staged
          ? () => widget.repository.unstageFiles([
              path,
              ?entry?.origPath,
            ], hasHead: hasHead)
          : entry?.conflicted ?? false
          ? () => widget.repository.stageResolvedFile(path)
          : () => widget.repository.stageFiles([path]),
    );
  }

  /// 헝크 헤더가 다는 버튼. 축이 무엇을 걸 수 있는지 정하고, 헝크로 다룰 수 없는
  /// 파일에는 아무것도 걸지 않는다 — untracked에는 헝크가 없고, rename의 부분
  /// 적용은 두 경로가 얽히며, 바이너리·서브모듈·심볼릭 링크는 헝크가 의미를 갖지
  /// 않는다.
  List<Widget> _commitHunkActions(DiffHunk hunk) {
    final state = _fullDiffSession?.state;
    final path = state?.selectedFile?.path;
    if (state == null || path == null) return const [];
    // 거대 컨텍스트 한 덩이의 부분 적용은 의미가 없다.
    if (state.appliedScope != DiffScope.hunks) return const [];
    final entry = _commitEntryFor(path);
    if (entry == null) return const [];
    final unstaged = _commitDiffArea == WorkingTreeArea.unstaged;
    if (entry.untracked ||
        entry.conflicted ||
        entry.submodule ||
        entry.symlink ||
        entry.origPath != null ||
        (unstaged ? entry.unstagedBinary : entry.stagedBinary)) {
      return const [];
    }
    // 공백 무시 보기의 패치는 컨텍스트가 실제 바이트와 달라 적용이 깨진다.
    final blocked = state.appliedIgnoreWhitespace
        ? '공백 무시 보기에서는 Hunk 단위로 조작할 수 없습니다'
        : null;
    final expected = (
      oldStart: hunk.oldStart,
      oldCount: hunk.oldCount,
      newStart: hunk.newStart,
      newCount: hunk.newCount,
    );
    final algorithm = state.appliedAlgorithm;
    return [
      _commitHunkButton(
        key: Key('commit-${unstaged ? 'stage' : 'unstage'}-hunk-${hunk.index}'),
        label: unstaged ? 'Stage Hunk' : 'Unstage Hunk',
        color: mainAccent,
        blocked: blocked,
        onTap: () => _runCommitAction(
          unstaged
              ? () => widget.repository.stageHunk(
                  path,
                  hunk.index,
                  expected: expected,
                  algorithm: algorithm,
                )
              : () => widget.repository.unstageHunk(
                  path,
                  hunk.index,
                  expected: expected,
                  algorithm: algorithm,
                ),
        ),
      ),
      if (unstaged)
        _commitHunkButton(
          key: Key('commit-discard-hunk-${hunk.index}'),
          label: 'Discard Hunk',
          color: deletedPink,
          blocked: blocked,
          onTap: () =>
              _confirmCommitDiscardHunk(path, hunk.index, expected, algorithm),
        ),
    ];
  }

  Widget _commitHunkButton({
    required Key key,
    required String label,
    required Color color,
    required String? blocked,
    required Future<void> Function() onTap,
  }) {
    final button = InkWell(
      key: key,
      borderRadius: BorderRadius.circular(5),
      onTap: blocked != null || _commitModeBusy
          ? null
          : () => unawaited(onTap()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: blocked == null ? color : color.withValues(alpha: 0.4),
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    if (blocked == null) return button;
    return Tooltip(
      message: blocked,
      waitDuration: _tooltipDelay,
      child: button,
    );
  }

  Future<void> _confirmCommitDiscardHunk(
    String path,
    int hunkIndex,
    HunkRange expected,
    DiffAlgorithm algorithm,
  ) async {
    final approved = await showYogitAlert<bool>(
      context,
      const YogitAlert(
        title: '이 Hunk를 버릴까요?',
        message: '이 Hunk의 변경이 작업 트리에서 사라집니다. 되돌릴 수 없습니다.',
        role: YogitAlertRole.destructive,
        confirmLabel: 'Discard Hunk',
        confirmKey: Key('commit-discard-confirm'),
        cancelKey: Key('commit-discard-cancel'),
      ),
    );
    if (approved != true || !mounted) return;
    await _runCommitAction(
      () => widget.repository.discardHunk(
        path,
        hunkIndex,
        expected: expected,
        algorithm: algorithm,
      ),
    );
  }

  /// Discard만이 파괴적이라 확인창을 먼저 띄운다. untracked 파일은 되돌릴 인덱스
  /// 사본이 없어 Discard가 곧 파일 삭제이고, 확인창이 그렇게 말한다.
  Future<void> _confirmCommitDiscard(WorkingTreeEntry entry) async {
    final deleted = !entry.untracked && entry.worktreeStatus == 'D';
    final approved = await showYogitAlert<bool>(
      context,
      YogitAlert(
        title: entry.untracked
            ? '파일을 삭제할까요?'
            : deleted
            ? '삭제를 취소할까요?'
            : '변경 내용을 버릴까요?',
        message: entry.untracked
            ? '추적되지 않는 파일이라 Discard는 파일 삭제입니다. '
                  '${entry.path}가 디스크에서 지워집니다. 되돌릴 수 없습니다.'
            : deleted
            ? '${entry.path}를 인덱스 내용으로 되살립니다.'
            : '${entry.path}의 작업 트리 변경이 사라집니다. Staged 변경은 남습니다. 되돌릴 수 없습니다.',
        role: deleted ? YogitAlertRole.normal : YogitAlertRole.destructive,
        confirmLabel: entry.untracked
            ? '삭제'
            : deleted
            ? '되살리기'
            : 'Discard',
        confirmKey: const Key('commit-discard-confirm'),
        cancelKey: const Key('commit-discard-cancel'),
      ),
    );
    if (approved != true || !mounted) return;
    await _runCommitAction(
      () => widget.repository.discardWorktreeFile(
        entry.path,
        untracked: entry.untracked,
      ),
    );
  }

  Widget _commitForm(GitCommit commit, WorkingTreeStatus? status) {
    final staged = status?.staged.length ?? 0;
    final blocked = status?.hasConflict ?? false;
    final hasHead = commit.parents.isNotEmpty;
    final pushed = _amendPushedUpstream();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _palette.border)),
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _commitTitle,
        builder: (context, title, _) {
          final ready = _commitReady;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _commitFieldBox(
                child: Row(
                  children: [
                    Expanded(
                      child: _commitTextField(
                        key: const Key('commit-title'),
                        controller: _commitTitle,
                        hint: '제목',
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${title.text.length}/$_commitSubjectLimit',
                      key: const Key('commit-title-counter'),
                      style: TextStyle(
                        color: title.text.length > _commitSubjectLimit
                            ? behindOrange
                            : _palette.muted,
                        fontSize: 10.5,
                        fontFamily: technicalFontFamily,
                        fontFamilyFallback: technicalFontFallback,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _commitFieldBox(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 38),
                  child: _commitTextField(
                    key: const Key('commit-body'),
                    controller: _commitBody,
                    hint: '본문 (선택) — 무엇을, 왜 바꿨는지',
                    fontSize: 12,
                    lines: 3,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _commitAmendRow(hasHead: hasHead),
              if (_commitAmend && pushed != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '이미 $pushed에 올라간 커밋입니다. 수정하면 원격과 히스토리가 갈라집니다.',
                    key: const Key('commit-amend-warning'),
                    style: const TextStyle(color: behindOrange, fontSize: 10.5),
                  ),
                ),
              if (blocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '충돌 파일을 먼저 해결해야 합니다',
                    key: const Key('commit-conflict-note'),
                    style: const TextStyle(
                      color: previewConflict,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              if (_commitError case final error?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    error,
                    key: const Key('commit-error'),
                    style: const TextStyle(color: hashRed, fontSize: 10.5),
                  ),
                ),
              InkWell(
                key: const Key('commit-submit'),
                borderRadius: BorderRadius.circular(7),
                onTap: ready ? () => unawaited(_commitIndex()) : null,
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ready
                        ? mainAccent
                        : mainAccent.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    _commitAmend ? '커밋 수정' : 'Staged $staged개 파일 커밋',
                    style: const TextStyle(
                      color: _commitButtonForeground,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _commitFieldBox({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: _palette.raised,
      border: Border.all(color: _palette.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: child,
  );

  Widget _commitTextField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required double fontSize,
    int? lines,
  }) => TextField(
    key: key,
    controller: controller,
    maxLines: lines,
    minLines: lines == null ? null : 1,
    style: TextStyle(
      color: _palette.text,
      fontSize: fontSize,
      fontFamily: technicalFontFamily,
      fontFamilyFallback: technicalFontFallback,
    ),
    decoration: InputDecoration(
      isDense: true,
      border: InputBorder.none,
      focusedBorder: InputBorder.none,
      enabledBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      hintText: hint,
      hintStyle: TextStyle(color: _palette.muted, fontSize: fontSize),
    ),
  );

  Widget _commitAmendRow({required bool hasHead}) => InkWell(
    key: const Key('commit-amend'),
    onTap: hasHead && !_commitModeBusy
        ? () => unawaited(_toggleCommitAmend(!_commitAmend))
        : null,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 13,
            height: 13,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _commitAmend ? _palette.interactive : null,
              border: Border.all(color: _palette.border, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '이전 커밋에 합치기',
            style: TextStyle(
              color: hasHead
                  ? _palette.muted
                  : _palette.muted.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '--amend',
            style: TextStyle(
              color: _palette.muted,
              fontSize: 11,
              fontFamily: technicalFontFamily,
              fontFamilyFallback: technicalFontFallback,
            ),
          ),
        ],
      ),
    ),
  );

  /// 현재 브랜치의 HEAD가 이미 올라가 있는 upstream. amend가 히스토리를 가르게
  /// 되는 경우이고, 막지는 않는다.
  String? _amendPushedUpstream() {
    final current = _refs.current;
    final upstream = current == null ? null : _refs.upstreams[current];
    if (upstream == null) return null;
    return (_refs.aheadBehind[current]?.ahead ?? 1) == 0 ? upstream : null;
  }

  /// 체크하면 비어 있는 폼에만 HEAD 메시지를 채운다. 풀 때는 채워 넣은 그대로일
  /// 때만 비운다 — 사용자가 고쳐 쓴 글을 도로 가져가지 않는다.
  Future<void> _toggleCommitAmend(bool amend) async {
    _rebuild(() => _commitAmend = amend);
    if (!amend) {
      if (_commitAmendPrefill == _commitMessageText()) {
        _commitTitle.clear();
        _commitBody.clear();
      }
      _rebuild(() => _commitAmendPrefill = null);
      return;
    }
    if (_commitTitle.text.isNotEmpty || _commitBody.text.isNotEmpty) return;
    final message = await widget.repository.loadCommitMessage('HEAD');
    if (!mounted) return;
    final newline = message.indexOf('\n');
    _commitTitle.text = newline < 0 ? message : message.substring(0, newline);
    _commitBody.text = _commitMessageBody(message);
    _rebuild(() => _commitAmendPrefill = _commitMessageText());
  }

  String _commitMessageText() {
    final title = _commitTitle.text.trim();
    final body = _commitBody.text.trim();
    return body.isEmpty ? title : '$title\n\n$body';
  }

  Future<void> _commitIndex() async {
    final done = await _runCommitAction(
      () => widget.repository.commitIndex(
        message: _commitMessageText(),
        amend: _commitAmend,
      ),
      reloadTimeline: true,
      inlineError: true,
    );
    if (!done || !mounted) return;
    _commitTitle.clear();
    _commitBody.clear();
    _rebuild(() {
      _commitAmend = false;
      _commitAmendPrefill = null;
    });
  }

  /// 패널의 git 조작은 전부 여기를 지난다. 한 번에 하나만 돌고, 감시자는 그동안
  /// 물러나 있으며, 끝나면 목록을 다시 읽는다. [inlineError]는 커밋처럼 실패
  /// 문구가 폼 자리에 남아야 하는 조작만 준다 — 나머지는 SnackBar다.
  Future<bool> _runCommitAction(
    Future<void> Function() action, {
    bool reloadTimeline = false,
    bool inlineError = false,
  }) async {
    if (_commitModeBusy) return false;
    _rebuild(() {
      _commitModeBusy = true;
      _commitError = null;
    });
    String? failure;
    try {
      await _changingRepository(action);
    } catch (error) {
      failure = error is GitRepositoryException ? error.message : '$error';
    }
    if (!mounted) return failure == null;
    if (failure != null && !inlineError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure)));
    }
    _rebuild(() {
      _commitModeBusy = false;
      if (inlineError) _commitError = failure;
    });
    await _reloadCommitMode(timelineToo: reloadTimeline && failure == null);
    return failure == null;
  }

  /// 조작 뒤 목록을 다시 읽는다. 빈 sha를 키로 쓰는 미리보기 캐시 셋은 무효화되지
  /// 않는 함정이라 여기서 끊는다. 커밋 모드로 열린 diff는 파일 목록도 패치도
  /// 낡았으므로 같이 다시 읽는다.
  Future<void> _reloadCommitMode({bool timelineToo = false}) async {
    _rebuild(() {
      _commitStatusRequest = _readWorkingTreeStatus();
      _previewFiles.remove('');
      _previewFileLists.remove('');
      _previewDiffs.removeWhere((key, _) => key.sha.isEmpty);
    });
    final status = await _commitStatusRequest;
    if (!mounted) return;
    if (_fullDiffSession case final session?
        when session.repository is WorkingTreeAreaRepository) {
      await session.refreshWorkingTree();
    }
    // 마지막 변경까지 버렸으면 작업 트리 행 자체가 없어져야 한다.
    if (timelineToo || (status?.entries.isEmpty ?? false)) {
      await _reloadTimelineAfterCherryPick(null);
    }
  }
}
