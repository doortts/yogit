part of 'timeline.dart';

/// 기준 브랜치의 upstream 동기화 — 판정 배선과 세 실행.
/// docs/upstream-sync-design.md P3.

extension _TimelineUpstreamSync on _TimelineScreenState {
  /// refs가 새로 실릴 때마다, 그리고 기준 브랜치가 바뀔 때마다 판정을 다시
  /// 세운다. fetch에서 온 refs면 그 시각이 tooltip의 '확인'으로 실린다.
  void _judgeUpstreamSync({DateTime? refreshedAt}) {
    _upstreamSync.updateRefs(_refs, _baseBranch, refreshedAt: refreshedAt);
  }

  /// 캡슐 실행이 잠기는 동안: 브랜치 diff의 worktree 흐름이나 다른 원격 작업이
  /// 도는 중이다. 판정은 그대로 보인다.
  bool get _upstreamSyncEnabled =>
      _compareRef == null &&
      !_branchApplyBusy &&
      _pullingRemote == null &&
      _cherryPickState == null &&
      !_upstreamSyncBusy;

  Widget _upstreamSyncCapsule() => ListenableBuilder(
    listenable: _upstreamSync,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.only(right: 10),
      child: UpstreamSyncCapsule(
        state: _upstreamSync.state,
        enabled: _upstreamSyncEnabled,
        onPull: () => unawaited(_upstreamPull()),
        onPush: () => unawaited(_upstreamPush()),
        onResolveConflict: _openUpstreamConflictFlow,
      ),
    ),
  );

  /// Pull: 초록(빨리감기)은 확인 없이 즉시 — 로컬을 움직이되 역사는 그대로다.
  /// 주황은 받아 얹기라 로컬 커밋의 해시가 달라지므로, 무엇이 들어오고 무엇이
  /// 다시 쓰이는지 영수증을 보인 뒤에만 움직인다.
  Future<void> _upstreamPull() async {
    final state = _upstreamSync.state;
    switch (state.kind) {
      case UpstreamSyncKind.pullOnly:
        await _runUpstreamAction(() async {
          await widget.repository.pullRemoteBranch(
            state.remote!,
            state.branch!,
            checkedOut: state.checkedOut,
          );
        }, failure: 'Pull 실패');
      case UpstreamSyncKind.divergedClean:
        final moved = await _upstreamMovedCommits(state);
        if (moved == null || !mounted) return;
        final approved = await showYogitAlert<bool>(
          context,
          YogitAlert(
            title: '받아 얹을까요? (Pull --rebase)',
            body: PushReceipt(
              branch: state.branch!,
              incoming: moved.incoming,
              incomingTotal: state.behind,
              outgoing: const [],
              footnote:
                  '충돌 없음은 방금 재연으로 확인했습니다. '
                  '얹힌 커밋은 해시가 달라집니다.',
            ),
            confirmLabel: '받아 얹기',
            confirmKey: const Key('upstream-rebase-pull-confirm'),
          ),
        );
        if (approved != true) return;
        await _runUpstreamAction(() async {
          await widget.repository.applyUpstreamRebase(
            branch: state.branch!,
            expectedTip: state.localTip!,
            virtualTip: state.virtualTip!,
          );
        }, failure: 'Pull --rebase 실패');
      default:
        return;
    }
  }

  /// Push는 원격을 움직이므로 항상 확인을 거치고, 확인창에는 오갈 커밋이
  /// 저장소 변경 알림의 형식으로 선다. 주황은 확인 한 번에 두 걸음.
  Future<void> _upstreamPush() async {
    final state = _upstreamSync.state;
    switch (state.kind) {
      case UpstreamSyncKind.firstPush:
        final approved = await showYogitAlert<bool>(
          context,
          YogitAlert(
            title: '${state.branch} 브랜치를 ${state.remote}에 처음 Push할까요?',
            message: '원격에 ${state.branch} 브랜치를 만들고 추적을 연결합니다.',
            confirmLabel: 'Push',
            confirmKey: const Key('upstream-first-push-confirm'),
          ),
        );
        if (approved != true) return;
        await _runUpstreamAction(() async {
          await widget.repository.pushBranch(
            state.remote!,
            state.branch!,
            setUpstream: true,
          );
        }, failure: 'Push 실패');
      case UpstreamSyncKind.pushOnly:
        final moved = await _upstreamMovedCommits(state);
        if (moved == null || !mounted) return;
        final approved = await showYogitAlert<bool>(
          context,
          YogitAlert(
            title: '${state.branch} 브랜치를 ${state.remote}에 Push할까요?',
            body: PushReceipt(
              branch: state.branch!,
              incoming: const [],
              outgoing: moved.outgoing,
              outgoingTotal: state.ahead,
              footnote:
                  '원격 ${state.branch} 브랜치가 ${shortSha(state.remoteTip!)}에서 '
                  '${shortSha(state.localTip!)}로 움직입니다.',
            ),
            confirmLabel: 'Push',
            confirmKey: const Key('upstream-push-confirm'),
          ),
        );
        if (approved != true) return;
        await _runUpstreamAction(() async {
          // 영수증이 보인 그 끝을 올린다 — 확인창이 열린 사이에 도착한 커밋이
          // 소리 없이 딸려 올라가지 않는다.
          await widget.repository.pushBranch(
            state.remote!,
            state.branch!,
            toBranch: _upstreamBranchName(state),
            fromTip: state.localTip,
          );
        }, failure: 'Push 실패');
      case UpstreamSyncKind.divergedClean:
        final moved = await _upstreamMovedCommits(state);
        if (moved == null || !mounted) return;
        final approved = await showYogitAlert<bool>(
          context,
          YogitAlert(
            title: '받아 얹은 뒤 Push할까요? (Pull Rebase and Push)',
            body: PushReceipt(
              branch: state.branch!,
              incoming: moved.incoming,
              incomingTotal: state.behind,
              outgoing: moved.outgoing,
              outgoingTotal: state.ahead,
              footnote:
                  '충돌 없음은 방금 재연으로 확인했습니다. '
                  '얹힌 커밋은 해시가 달라집니다.',
            ),
            confirmLabel: '받아 얹고 Push',
            confirmKey: const Key('upstream-rebase-push-confirm'),
          ),
        );
        if (approved != true) return;
        await _runUpstreamAction(() async {
          // 첫걸음이 expected 불일치로 거절되면 여기서 멈추고, 아래의 재판정이
          // 이유를 다시 잰다. push가 거절되면 로컬 rebase는 남는다 — 다음
          // 판정은 대개 pushOnly거나 다시 어긋남이다.
          await widget.repository.applyUpstreamRebase(
            branch: state.branch!,
            expectedTip: state.localTip!,
            virtualTip: state.virtualTip!,
          );
          await widget.repository.pushBranch(
            state.remote!,
            state.branch!,
            toBranch: _upstreamBranchName(state),
            fromTip: state.virtualTip,
          );
        }, failure: 'Push 실패');
      default:
        return;
    }
  }

  /// upstream의 원격 쪽 이름 — main이 origin/trunk를 추적하면 trunk. 잰
  /// 브랜치로 올리기 위해서다.
  String? _upstreamBranchName(UpstreamSyncState state) {
    final upstreamRef = state.upstreamRef;
    if (upstreamRef == null) return null;
    return splitRemoteBranchName(upstreamRef, _refs.remoteNames)?.branch;
  }

  /// 영수증에 설 커밋들. `<`가 들어올(pull) 쪽, `>`가 올라갈(push) 쪽이다 —
  /// incoming이라는 이름과 방향이 엇갈리므로 여기서 한 번만 갈라 담는다.
  /// 기본 아홉 개는 양쪽 합계라 한쪽이 다른 쪽을 굶길 수 있다 — 창을 넓혀
  /// 각 블록이 저마다 아홉 줄까지 서고, 넘친 것은 '외 N개'가 정직하게 센다.
  Future<({List<MovedCommit> incoming, List<MovedCommit> outgoing})?>
  _upstreamMovedCommits(UpstreamSyncState state) async {
    final remoteTip = state.remoteTip;
    final localTip = state.localTip;
    if (remoteTip == null || localTip == null) return null;
    final moved = await widget.repository.loadMovedCommits(
      remoteTip,
      localTip,
      limit: 18,
    );
    return (
      incoming: [
        for (final c in moved)
          if (!c.incoming) c,
      ].take(9).toList(),
      outgoing: [
        for (final c in moved)
          if (c.incoming) c,
      ].take(9).toList(),
    );
  }

  Future<void> _runUpstreamAction(
    Future<void> Function() action, {
    required String failure,
  }) async {
    if (!_upstreamSyncEnabled) return;
    _rebuild(() => _upstreamSyncBusy = true);
    try {
      await action();
    } on ProcessException catch (error) {
      _upstreamActionFailed(failure, error.message);
    } on GitRepositoryException catch (error) {
      _upstreamActionFailed(failure, error.message);
    } finally {
      // 성공이든 거절이든 새로 읽는다: 두 걸음 중 첫걸음만 성공했어도 ref는
      // 이미 움직였고, 낡은 화면 위의 판정은 판정이 아니다. 새 refs가
      // 실리면서 재판정도 함께 선다.
      if (mounted) await _reloadTimelineAfterCherryPick(null);
      if (mounted) {
        _rebuild(() => _upstreamSyncBusy = false);
      } else {
        _upstreamSyncBusy = false;
      }
    }
  }

  void _upstreamActionFailed(String failure, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$failure: ${message.trim()}')));
  }

  /// 빨간 버튼: 기준을 upstream ref로, 비교를 로컬 브랜치로 하는 브랜치 diff에
  /// rebase 모드로 들어간다 — 재연이 충돌 지점에 멈춰 있는 그 화면, 그 부품
  /// 그대로. 흐름이 끝나면(적용이든 포기든) 기준 브랜치가 돌아온다.
  void _openUpstreamConflictFlow() {
    final state = _upstreamSync.state;
    if (state.kind != UpstreamSyncKind.divergedConflict ||
        !_upstreamSyncEnabled) {
      return;
    }
    final upstreamRef = state.upstreamRef;
    final branch = state.branch;
    if (upstreamRef == null ||
        branch == null ||
        !_refs.remote.contains(upstreamRef)) {
      return;
    }
    _upstreamConflictLoan = (borrowed: upstreamRef, returnTo: branch);
    if (_branchPreviewMode != BranchPreviewMode.rebase) {
      _setBranchPreviewMode(BranchPreviewMode.rebase);
    }
    // 빌린 기준은 취향으로 저장하지 않는다 — 흐름 중에 앱이 꺼져도 다음
    // 시작은 원래 브랜치에서다.
    _selectBaseBranch(upstreamRef, persist: false);
    unawaited(_selectComparison(branch));
  }

  /// 브랜치 diff가 닫힐 때 한 번 — 충돌 흐름이 빌려 간 기준을 되돌린다.
  /// 사용자가 흐름 중에 기준을 손수 옮겼으면 빌림은 이미 끝난 것: 그 선택을
  /// 덮지 않고 표만 지운다. 되돌아온 뒤에는 refs를 새로 읽는다 — 해결을 마치고
  /// 적용한 흐름이라면 어긋남은 이미 끝났고, 그 사실은 새 refs만이 안다.
  void _restoreUpstreamConflictBase() {
    final loan = _upstreamConflictLoan;
    if (loan == null) return;
    _upstreamConflictLoan = null;
    if (_baseBranch != loan.borrowed) return;
    if (!_refs.local.contains(loan.returnTo)) return;
    _selectBaseBranch(loan.returnTo, persist: false);
    unawaited(_loadRefs());
  }
}
