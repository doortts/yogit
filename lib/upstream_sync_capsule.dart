import 'package:flutter/material.dart';

import 'commit_time.dart';
import 'timeline_palette.dart';
import 'timeline_theme.dart';
import 'timeline_widgets.dart';
import 'upstream_sync.dart';
import 'typography.dart';

/// 기준 브랜치 선택기 곁의 동기화 캡슐. 동사는 '무엇을 하겠다'가 아니라 '하면
/// 어떻게 되는지'를 입는다 — 초록: 그대로 됨, 주황: 받아 얹기를 거치면 됨,
/// 빨강: 충돌(실행 대신 해결 흐름의 문). 동기화 상태는 점 하나가 전부다.
/// docs/upstream-sync-mockup.html이 계약이다.
class UpstreamSyncCapsule extends StatelessWidget {
  const UpstreamSyncCapsule({
    required this.state,
    required this.enabled,
    required this.onPull,
    required this.onPush,
    required this.onResolveConflict,
    super.key,
  });

  final UpstreamSyncState state;

  /// 브랜치 diff의 worktree 흐름이 도는 동안 실행 버튼이 잠긴다 — 판정은
  /// 그대로 보이되, 두 흐름을 겹치지 않는다.
  final bool enabled;

  final VoidCallback onPull;
  final VoidCallback onPush;
  final VoidCallback onResolveConflict;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    if (state.kind == UpstreamSyncKind.hidden) return const SizedBox.shrink();
    return Container(
      key: const Key('upstream-sync-capsule'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.raised,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: switch (state.kind) {
          UpstreamSyncKind.hidden => const [],
          UpstreamSyncKind.synced => [_dot(palette)],
          UpstreamSyncKind.firstPush => [
            _verb(
              key: const Key('upstream-sync-push'),
              palette: palette,
              color: palette.muted,
              count: '처음',
              word: 'Push',
              tooltip:
                  '${state.remote}에 ${state.branch} 브랜치를 만들고 추적을 '
                  '연결합니다 (push -u)',
              onTap: onPush,
            ),
          ],
          UpstreamSyncKind.pushOnly => [
            _verb(
              key: const Key('upstream-sync-push'),
              palette: palette,
              color: mainAccent,
              count: '↑ ${state.ahead}',
              word: 'Push',
              tooltip: '그대로 Push할 수 있습니다 — 커밋 ${state.ahead}개$_freshness',
              onTap: onPush,
            ),
          ],
          UpstreamSyncKind.pullOnly => [
            _verb(
              key: const Key('upstream-sync-pull'),
              palette: palette,
              color: mainAccent,
              count: '↓ ${state.behind}',
              word: 'Pull',
              tooltip: '빨리감기로 받습니다 — 커밋 ${state.behind}개$_freshness',
              onTap: onPull,
            ),
          ],
          // 재는 동안은 동사가 없다 — 무엇을 하게 될지가 아직 답이 아니라서다.
          // 아랫줄은 동사 자리에 도는 것 하나를 놓아, 기다리는 중이라는 말을
          // 글자 없이 한다.
          UpstreamSyncKind.measuring => [
            Padding(
              key: const Key('upstream-sync-measuring'),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '↓ ${state.behind} ↑ ${state.ahead}',
                    style: TextStyle(
                      fontFamily: technicalFontFamily,
                      fontFamilyFallback: technicalFontFallback,
                      fontSize: 11,
                      height: 1.25,
                      color: palette.muted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
          UpstreamSyncKind.divergedClean => [
            _verb(
              key: const Key('upstream-sync-pull'),
              palette: palette,
              color: behindOrange,
              count: '↓ ${state.behind}',
              word: 'Pull',
              tooltip:
                  '빨리감기는 불가, 받아 얹기(--rebase)로 받습니다 — '
                  '충돌 없음$_measured',
              onTap: onPull,
            ),
            _verb(
              key: const Key('upstream-sync-push'),
              palette: palette,
              color: behindOrange,
              count: '↑ ${state.ahead}',
              word: 'Push',
              tooltip:
                  '${state.behind}개를 받아 얹은 뒤 충돌 없이 Push할 수 '
                  '있습니다$_measured',
              onTap: onPush,
            ),
          ],
          UpstreamSyncKind.divergedConflict => [
            _verb(
              key: const Key('upstream-sync-conflict'),
              palette: palette,
              color: remoteBehindRed,
              count: '↓ ${state.behind}',
              word: '충돌 ${state.conflictFiles.length}',
              tooltip:
                  '빨리감기는 불가, 받아 얹으면 ${_conflictSummary()}에서 '
                  '충돌합니다 — 눌러서 해결$_measured',
              onTap: onResolveConflict,
            ),
            // 빨강은 판정이고, 이 칸은 판정이 아니라 나가는 길이다. 판정 색이
            // 아닌 컨트롤의 파랑을 입어 '막혔다' 옆에 '이리로 나간다'가 선다 —
            // 여기서 실행되는 것은 없고, 해결 화면이 열릴 뿐이다.
            _verb(
              key: const Key('upstream-sync-conflict-push'),
              palette: palette,
              color: previewControlBlue,
              // 46개가 막혀 있다는 사실은 여전히 판정의 것이다.
              countColor: remoteBehindRed,
              count: '↑ ${state.ahead}',
              word: '해결하기',
              tooltip:
                  '충돌 해결 화면을 엽니다 — 여기서 실행되는 것은 없습니다. '
                  '해결하고 적용해야 Push까지 갈 수 있습니다',
              onTap: onResolveConflict,
            ),
          ],
        },
      ),
    );
  }

  String _conflictSummary() {
    final files = state.conflictFiles;
    if (files.isEmpty) return '파일';
    return files.length == 1
        ? files.single
        : '${files.first} 외 ${files.length - 1}개';
  }

  String get _freshness => switch (state.checkedAt) {
    null => '',
    final at => ' · ${_agoPhrase(at, '확인')}',
  };

  String get _measured => switch (state.measuredAt) {
    null => '',
    final at => ' · ${_agoPhrase(at, '잰 판정')}',
  };

  Widget _dot(TimelineThemePalette palette) => Tooltip(
    message: '${state.upstreamRef} 브랜치와 같습니다$_freshness',
    child: Container(
      key: const Key('upstream-sync-dot'),
      width: 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      decoration: BoxDecoration(
        color: mainAccent.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );

  /// 숫자가 위, 동사가 아래. 옆의 저장소·브랜치 칸이 '설명 줄 · 값 줄'로 서
  /// 있는 것과 같은 격자라, 굵은 동사가 브랜치 이름과 같은 높이에서 읽힌다.
  /// 접힌 만큼 캡슐은 한 줄로 늘어서던 때의 절반 폭으로 선다.
  /// [countColor]는 윗줄만 따로 입힌다: 개수는 언제나 판정에 딸린 사실이라,
  /// 아랫줄이 판정을 벗어나도(충돌의 '해결하기') 숫자까지 함께 옮겨 가지는
  /// 않는다.
  Widget _twoLines({
    required String count,
    required String word,
    required Color color,
    Color? countColor,
  }) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          // 개수는 고정폭으로 — 자릿수가 늘어도 동사가 흔들리지 않는다.
          text: count,
          style: TextStyle(
            fontFamily: technicalFontFamily,
            fontFamilyFallback: technicalFontFallback,
            fontSize: 11,
            height: 1.25,
            color: countColor == null
                ? null
                : enabled
                ? countColor
                : countColor.withValues(alpha: 0.45),
          ),
        ),
        const TextSpan(text: '\n'),
        TextSpan(
          text: word,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ],
    ),
    textAlign: TextAlign.center,
    style: TextStyle(
      color: enabled ? color : color.withValues(alpha: 0.45),
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _verb({
    required Key key,
    required TimelineThemePalette palette,
    required Color color,
    required String count,
    required String word,
    required String tooltip,
    required VoidCallback onTap,
    Color? countColor,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: HoverBuilder(
        enabled: enabled,
        builder: (hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: hovered && enabled
                  ? palette.selectedRow
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Padding(
              key: key,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: _twoLines(
                count: count,
                word: word,
                color: color,
                countColor: countColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// '4분 전에 확인' — 조사까지 문장으로 만든다. '방금'에는 '에'가 붙지 않는다.
String _agoPhrase(DateTime at, String verb) {
  final minutes = DateTime.now().difference(at).inMinutes;
  if (minutes < 1) return '방금 $verb';
  if (minutes < 60) return '$minutes분 전에 $verb';
  final exact = exactCommitTime(
    at.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond,
  );
  return '$exact에 $verb';
}
