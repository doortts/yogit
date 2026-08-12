import 'package:flutter/material.dart';

import 'commit_time.dart';
import 'timeline_palette.dart';
import 'timeline_theme.dart';
import 'timeline_widgets.dart';
import 'upstream_sync.dart';

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
              text: '↑ 처음 Push',
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
              text: '↑ ${state.ahead} Push',
              tooltip: '그대로 Push할 수 있습니다 — 커밋 ${state.ahead}개$_freshness',
              onTap: onPush,
            ),
          ],
          UpstreamSyncKind.pullOnly => [
            _verb(
              key: const Key('upstream-sync-pull'),
              palette: palette,
              color: mainAccent,
              text: '↓ ${state.behind} Pull',
              tooltip: '빨리감기로 받습니다 — 커밋 ${state.behind}개$_freshness',
              onTap: onPull,
            ),
          ],
          UpstreamSyncKind.measuring => [
            Padding(
              key: const Key('upstream-sync-measuring'),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: Text(
                '↓ ${state.behind} ↑ ${state.ahead} …',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          UpstreamSyncKind.divergedClean => [
            _verb(
              key: const Key('upstream-sync-pull'),
              palette: palette,
              color: behindOrange,
              text: '↓ ${state.behind} Pull',
              tooltip:
                  '빨리감기는 불가, 받아 얹기(--rebase)로 받습니다 — '
                  '충돌 없음$_measured',
              onTap: onPull,
            ),
            _verb(
              key: const Key('upstream-sync-push'),
              palette: palette,
              color: behindOrange,
              text: '↑ ${state.ahead} Push',
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
              text: '↓ ${state.behind} 충돌 ${state.conflictFiles.length}파일',
              tooltip:
                  '빨리감기는 불가, 받아 얹으면 ${_conflictSummary()}에서 '
                  '충돌합니다 — 눌러서 해결$_measured',
              onTap: onResolveConflict,
            ),
            _verb(
              key: const Key('upstream-sync-conflict-push'),
              palette: palette,
              color: remoteBehindRed,
              text: '↑ ${state.ahead}',
              tooltip: '충돌을 해결해야 Push까지 갈 수 있습니다',
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
    final at => ' · ${_ago(at)}에 확인',
  };

  String get _measured => switch (state.measuredAt) {
    null => '',
    final at => ' · ${_ago(at)}에 잰 판정',
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

  Widget _verb({
    required Key key,
    required TimelineThemePalette palette,
    required Color color,
    required String text,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final parts = text.split(' ');
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
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    for (var index = 0; index < parts.length; index++) ...[
                      if (index > 0) const TextSpan(text: ' '),
                      TextSpan(
                        text: parts[index],
                        // 개수는 판정 색과 함께, 고정폭으로.
                        style: int.tryParse(parts[index]) != null
                            ? const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              )
                            : null,
                      ),
                    ],
                  ],
                ),
                style: TextStyle(
                  color: enabled ? color : color.withValues(alpha: 0.45),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// '4분 전' — 잰 지 얼마 안 됐으면 '방금'.
String _ago(DateTime at) {
  final minutes = DateTime.now().difference(at).inMinutes;
  if (minutes < 1) return '방금';
  if (minutes < 60) return '$minutes분 전';
  final exact = exactCommitTime(
    at.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond,
  );
  return exact;
}
