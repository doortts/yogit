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

  /// Pull: 초록(빨리감기)은 확인 없이 즉시 — 로컬만 움직인다. 주황은 재연이
  /// 만들어 둔 tip으로 ref만 옮기는 받아 얹기. 완료는 타임라인이 말한다.
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
            title: '${state.branch}을(를) ${state.remote}에 처음 Push할까요?',
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
            title: '${state.branch}을(를) ${state.remote}에 Push할까요?',
            body: PushReceipt(
              branch: state.branch!,
              incoming: const [],
              outgoing: moved.outgoing,
              footnote:
                  '원격 ${state.branch}이(가) ${shortSha(state.remoteTip!)}에서 '
                  '${shortSha(state.localTip!)}(으)로 움직입니다.',
            ),
            confirmLabel: 'Push',
            confirmKey: const Key('upstream-push-confirm'),
          ),
        );
        if (approved != true) return;
        await _runUpstreamAction(() async {
          await widget.repository.pushBranch(
            state.remote!,
            state.branch!,
            toBranch: _upstreamBranchName(state),
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
              outgoing: moved.outgoing,
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
  Future<({List<MovedCommit> incoming, List<MovedCommit> outgoing})?>
  _upstreamMovedCommits(UpstreamSyncState state) async {
    final remoteTip = state.remoteTip;
    final localTip = state.localTip;
    if (remoteTip == null || localTip == null) return null;
    final moved = await widget.repository.loadMovedCommits(remoteTip, localTip);
    return (
      incoming: [
        for (final c in moved)
          if (!c.incoming) c,
      ],
      outgoing: [
        for (final c in moved)
          if (c.incoming) c,
      ],
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
      if (!mounted) return;
      await _reloadTimelineAfterCherryPick(null);
    } on ProcessException catch (error) {
      _upstreamActionFailed(failure, error.message);
    } on GitRepositoryException catch (error) {
      _upstreamActionFailed(failure, error.message);
    } finally {
      if (mounted) {
        _rebuild(() => _upstreamSyncBusy = false);
      } else {
        _upstreamSyncBusy = false;
      }
      // 성공이든 거절이든 판정은 다시 선다 — 거절의 이유는 새 refs가 말한다.
      if (mounted) _judgeUpstreamSync();
    }
  }

  void _upstreamActionFailed(String failure, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$failure: ${message.trim()}')));
  }

  /// P4에서 브랜치 diff의 충돌 해결 흐름으로 연결된다. 그때까지 빨간 버튼은
  /// tooltip이 충돌 파일을 말하는 데서 멈춘다.
  void _openUpstreamConflictFlow() {}
}
