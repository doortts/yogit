import 'package:flutter/foundation.dart';

import 'git.dart';

/// 기준 브랜치와 upstream 사이의 판정. 공짜 사실(ahead/behind)이 대부분을
/// 정하고, 어긋났을 때만 숨은 worktree 재연이 나머지 하나 — 로컬 커밋이 원격
/// 끝 위에 깨끗이 얹히는가 — 를 답한다. docs/upstream-sync-design.md.
enum UpstreamSyncKind {
  /// 기준이 없거나 원격 ref다 — 캡슐 자체가 서지 않는다.
  hidden,

  /// upstream이 없거나 그 원격 ref가 사라졌다 — push -u가 처음 올린다.
  firstPush,

  /// ahead 0 · behind 0. 점 하나, 침묵.
  synced,

  /// 로컬에만 커밋이 있다 — 그대로 Push.
  pushOnly,

  /// 원격에만 커밋이 있다 — 빨리감기 Pull.
  pullOnly,

  /// 어긋났고, 재연이 아직 답하지 않았다 — 무채색 숫자.
  measuring,

  /// 재연이 깨끗했다 — 받아 얹으면 충돌 없이 Push까지 간다.
  divergedClean,

  /// 재연이 충돌했다 — 실행 대신 해결 흐름이 열린다.
  divergedConflict,
}

class UpstreamSyncState {
  const UpstreamSyncState({
    required this.kind,
    this.branch,
    this.remote,
    this.upstreamRef,
    this.ahead = 0,
    this.behind = 0,
    this.localTip,
    this.remoteTip,
    this.checkedOut = false,
    this.conflictFiles = const [],
    this.virtualTip,
    this.measuredAt,
    this.checkedAt,
    this.measureError,
  });

  static const none = UpstreamSyncState(kind: UpstreamSyncKind.hidden);

  final UpstreamSyncKind kind;

  /// 판정의 주인공: 기준 브랜치와 그 upstream.
  final String? branch;
  final String? remote;
  final String? upstreamRef;

  /// 로컬에만 있는 커밋 수(올라갈)와 원격에만 있는 커밋 수(들어올).
  final int ahead;
  final int behind;

  /// 판정이 잰 두 끝. 실행은 이 값을 expected로 걸어 그 사이의 이동을 막는다.
  final String? localTip;
  final String? remoteTip;

  /// divergedConflict가 이름 대는 파일들.
  final List<String> conflictFiles;

  /// divergedClean이 만들어 둔 새 tip — 실행은 ref를 여기로 옮기면 된다.
  final String? virtualTip;

  /// 기준 브랜치가 지금 체크아웃되어 있는가 — Pull의 두 경로를 가른다.
  final bool checkedOut;

  /// 재연이 답한 시각. tooltip의 'N분 전'.
  final DateTime? measuredAt;

  /// 마지막 fetch가 끝난 시각 — synced·pushOnly·pullOnly tooltip의 'N분 전에
  /// 확인'. refs가 로컬 작업으로 다시 로드돼도 이 시각은 fetch의 것이다.
  final DateTime? checkedAt;

  /// 재연이 실패했을 때 그 이유. 상태바가 이 문장을 되풀이한다.
  final String? measureError;
}

/// 재연 한 번: [remoteTip] 위에 [localTip]의 전용 커밋을 얹어 본다.
typedef UpstreamRebaseMeasure =
    Future<RebasePreviewResult> Function({
      required String remoteTip,
      required String localTip,
    });

class UpstreamSyncController extends ChangeNotifier {
  UpstreamSyncController({
    required UpstreamRebaseMeasure measure,
    DateTime Function()? now,
  }) : _measure = measure,
       _now = now ?? DateTime.now;

  final UpstreamRebaseMeasure _measure;
  final DateTime Function() _now;

  UpstreamSyncState _state = UpstreamSyncState.none;
  UpstreamSyncState get state => _state;

  /// 어긋남의 판정, (브랜치, localTip, remoteTip)으로. 같은 물음은 다시 재지
  /// 않고, 판정은 잰 브랜치의 이름을 달고 있어 남의 것이 되지 못한다.
  // ponytail: unbounded verdict map — a human-paced session stays in the
  // hundreds; add an LRU trim if a bot ever drives this.
  final _verdicts = <(String, String, String), UpstreamSyncState>{};

  /// 마지막으로 성립한 어긋남 판정 — 재연이 실패했을 때 남겨 둘 답. 브랜치가
  /// 다르면 남의 답이라 되살리지 않는다.
  UpstreamSyncState? _lastVerdict;

  (String, String, String)? _measuringPair;
  var _serial = 0;

  /// 마지막 fetch 완료 시각. updateRefs가 실어다 주고, 없으면 이전 값이 산다.
  DateTime? _checkedAt;

  String? _measureError;

  @override
  void dispose() {
    _serial++;
    super.dispose();
  }

  /// refs가 새로 로드될 때마다 타임라인이 부른다. 감시는 여기서 하지 않는다 —
  /// tip의 이동은 기존 ref watcher가 이미 본다. [refreshedAt]은 이 refs가
  /// fetch에서 왔을 때 그 fetch가 끝난 시각이다.
  void updateRefs(RepoRefs refs, String? baseBranch, {DateTime? refreshedAt}) {
    if (refreshedAt != null) _checkedAt = refreshedAt;
    if (_lastVerdict != null && _lastVerdict!.branch != baseBranch) {
      _lastVerdict = null;
    }
    final next = _judge(refs, baseBranch);
    // 어긋남이 끝났으면 날던 재연도 끝이다: 끝난 물음의 답이 산 판정을
    // 덮어쓰지 못하게 여기서 무효로 한다.
    if (next.kind != UpstreamSyncKind.measuring && _measuringPair != null) {
      _measuringPair = null;
      _serial++;
    }
    _set(next);
  }

  UpstreamSyncState _judge(RepoRefs refs, String? branch) {
    if (branch == null || !refs.local.contains(branch)) {
      return UpstreamSyncState.none;
    }
    final upstreamRef = refs.upstreams[branch];
    // 원격이 하나도 없으면 '처음 Push'는 성립하지 않는 약속이다 — 캡슐이 서지
    // 않는다. 올릴 원격: 추적이 말해 주면 그것, 아니면 저장소에 원격이 하나뿐일
    // 때 그 하나. 'origin'은 짐작이 아니라 마지막 관례다.
    if (upstreamRef == null && refs.remoteNames.isEmpty) {
      return UpstreamSyncState.none;
    }
    final remote =
        refs.upstreamRemotes[branch] ??
        (refs.remoteNames.length == 1 ? refs.remoteNames.single : 'origin');
    final localTip = refs.localTips[branch];
    final remoteTip = upstreamRef == null ? null : refs.tips[upstreamRef];
    final checkedOut = refs.current == branch;
    if (upstreamRef == null || remoteTip == null) {
      return UpstreamSyncState(
        kind: UpstreamSyncKind.firstPush,
        branch: branch,
        remote: remote,
        localTip: localTip,
        checkedOut: checkedOut,
        checkedAt: _checkedAt,
      );
    }
    final counts =
        refs.aheadBehind[branch] ??
        const BranchAheadBehind(ahead: 0, behind: 0);
    UpstreamSyncState plain(UpstreamSyncKind kind) => UpstreamSyncState(
      kind: kind,
      branch: branch,
      remote: remote,
      upstreamRef: upstreamRef,
      ahead: counts.ahead,
      behind: counts.behind,
      localTip: localTip,
      remoteTip: remoteTip,
      checkedOut: checkedOut,
      checkedAt: _checkedAt,
      measureError: _measureError,
    );
    if (counts.ahead == 0 && counts.behind == 0) {
      _measureError = null;
      return plain(UpstreamSyncKind.synced);
    }
    if (counts.behind == 0) {
      _measureError = null;
      return plain(UpstreamSyncKind.pushOnly);
    }
    if (counts.ahead == 0) {
      _measureError = null;
      return plain(UpstreamSyncKind.pullOnly);
    }
    // 어긋남 — 재연이 답했었다면 그 답, 아니면 재기 시작.
    if (localTip == null) return UpstreamSyncState.none;
    final pair = (branch, localTip, remoteTip);
    final verdict = _verdicts[pair];
    if (verdict != null) {
      // 판정은 그때 것이라도 체크아웃과 fetch 시각은 오늘 것을 말한다.
      return UpstreamSyncState(
        kind: verdict.kind,
        branch: verdict.branch,
        remote: verdict.remote,
        upstreamRef: verdict.upstreamRef,
        ahead: verdict.ahead,
        behind: verdict.behind,
        localTip: verdict.localTip,
        remoteTip: verdict.remoteTip,
        checkedOut: checkedOut,
        checkedAt: _checkedAt,
        conflictFiles: verdict.conflictFiles,
        virtualTip: verdict.virtualTip,
        measuredAt: verdict.measuredAt,
      );
    }
    if (_measuringPair != pair) {
      _measuringPair = pair;
      _startMeasure(pair, plain);
    }
    return plain(UpstreamSyncKind.measuring);
  }

  void _startMeasure(
    (String, String, String) pair,
    UpstreamSyncState Function(UpstreamSyncKind) plain,
  ) {
    final serial = ++_serial;
    _measure(remoteTip: pair.$3, localTip: pair.$2)
        .then((result) {
          if (serial != _serial || _measuringPair != pair) return;
          _measuringPair = null;
          switch (result.status) {
            case RebasePreviewStatus.clean:
              _settle(pair, plain, UpstreamSyncKind.divergedClean, result);
            case RebasePreviewStatus.conflict:
              _settle(pair, plain, UpstreamSyncKind.divergedConflict, result);
            case RebasePreviewStatus.failed:
              _withhold(result.error ?? '재연이 실패했습니다');
          }
        })
        .catchError((Object error) {
          if (serial != _serial || _measuringPair != pair) return;
          _measuringPair = null;
          _withhold(error.toString());
        });
  }

  /// 실패는 답이 아니다: 캐시하지 않아 다음 updateRefs가 다시 재고, 그동안은
  /// 이 브랜치의 마지막 판정이 남는다. 남의 브랜치 판정은 updateRefs가 이미
  /// 지웠으니 되살아날 수 없다. 이유는 상태에 실려 상태바가 되풀이한다.
  void _withhold(String error) {
    _measureError = error;
    final last = _lastVerdict;
    if (last != null) {
      _set(last);
      return;
    }
    _set(
      UpstreamSyncState(
        kind: _state.kind,
        branch: _state.branch,
        remote: _state.remote,
        upstreamRef: _state.upstreamRef,
        ahead: _state.ahead,
        behind: _state.behind,
        localTip: _state.localTip,
        remoteTip: _state.remoteTip,
        checkedOut: _state.checkedOut,
        checkedAt: _state.checkedAt,
        measureError: error,
      ),
    );
  }

  void _settle(
    (String, String, String) pair,
    UpstreamSyncState Function(UpstreamSyncKind) plain,
    UpstreamSyncKind kind,
    RebasePreviewResult result,
  ) {
    _measureError = null;
    final base = plain(kind);
    final verdict = UpstreamSyncState(
      kind: kind,
      branch: pair.$1,
      remote: base.remote,
      upstreamRef: base.upstreamRef,
      ahead: base.ahead,
      behind: base.behind,
      localTip: pair.$2,
      remoteTip: pair.$3,
      checkedOut: base.checkedOut,
      checkedAt: base.checkedAt,
      conflictFiles: result.conflictFiles,
      virtualTip: result.virtualTip,
      measuredAt: _now(),
    );
    _verdicts[pair] = verdict;
    _lastVerdict = verdict;
    _set(verdict);
  }

  void _set(UpstreamSyncState next) {
    _state = next;
    notifyListeners();
  }
}
