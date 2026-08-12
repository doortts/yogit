import 'package:flutter/material.dart';

import 'local_state_signature.dart';
import 'timeline_palette.dart';
import 'timeline_theme.dart';

/// Push 확인창의 몸통: 저장소 변경 알림과 같은 형식으로, 요약줄 아래 오갈
/// 커밋이 서고 물음은 맨 끝이다 — 무엇이 움직이는지 읽은 뒤에 답하는 순서.
/// 주황(받아 얹고 Push)일 때는 두 걸음이 블록 둘로 선다.
/// docs/upstream-sync-mockup.html '누르면' 절이 계약이다.
class PushReceipt extends StatelessWidget {
  const PushReceipt({
    required this.branch,
    required this.incoming,
    required this.outgoing,
    required this.footnote,
    this.incomingTotal,
    this.outgoingTotal,
    super.key,
  });

  /// `loadMovedCommits(remoteTip, localTip)`에서: `<`(incoming=false)가 원격
  /// 전용 — pull로 들어올 커밋이고, `>`(incoming=true)가 로컬 전용 — push로
  /// 올라갈 커밋이다. 이름이 엇갈리므로 호출부가 여기서 갈라 담는다.
  final String branch;
  final List<MovedCommit> incoming;
  final List<MovedCommit> outgoing;

  /// 물음 직전의 한 줄: ref 이동 해시, 또는 재연 확인 문장.
  final String footnote;

  /// 실제 오갈 개수 — 목록은 아홉 개에서 잘려도 요약과 '외 N개'는 이 수를
  /// 말한다. 영수증이 실물보다 적게 말하는 일은 없어야 한다.
  final int? incomingTotal;
  final int? outgoingTotal;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    return Column(
      key: const Key('push-receipt'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (incoming.isNotEmpty)
          _block(
            palette,
            key: const Key('push-receipt-pull-block'),
            op: 'pull --rebase',
            count: '커밋 ${incomingTotal ?? incoming.length}개 들어옴',
            countColor: mainAccent,
            commits: incoming,
            more: (incomingTotal ?? incoming.length) - incoming.length,
            mark: '+',
            markColor: mainAccent,
          ),
        if (outgoing.isNotEmpty)
          _block(
            palette,
            key: const Key('push-receipt-push-block'),
            op: 'push',
            count: '커밋 ${outgoingTotal ?? outgoing.length}개 올라감',
            countColor: previewControlBlue,
            commits: outgoing,
            more: (outgoingTotal ?? outgoing.length) - outgoing.length,
            mark: '↑',
            markColor: previewControlBlue,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Text(
            footnote,
            key: const Key('push-receipt-footnote'),
            style: TextStyle(
              color: palette.text.withValues(alpha: 0.82),
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _block(
    TimelineThemePalette palette, {
    required Key key,
    required String op,
    required String count,
    required Color countColor,
    required List<MovedCommit> commits,
    required int more,
    required String mark,
    required Color markColor,
  }) => Container(
    key: key,
    margin: const EdgeInsets.only(top: 9),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: palette.background.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: branch,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: '  ·  ',
                  style: TextStyle(color: palette.muted),
                ),
                TextSpan(
                  text: op,
                  style: TextStyle(
                    color: previewControlBlue,
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                  ),
                ),
                TextSpan(
                  text: '  ·  ',
                  style: TextStyle(color: palette.muted),
                ),
                TextSpan(
                  text: count,
                  style: TextStyle(color: countColor),
                ),
              ],
            ),
            style: TextStyle(color: palette.text, fontSize: 12.5),
          ),
        ),
        Divider(height: 1, color: palette.border),
        const SizedBox(height: 6),
        for (final commit in commits)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 17,
                  child: Text(
                    mark,
                    style: TextStyle(
                      color: markColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  commit.shortSha,
                  style: const TextStyle(
                    color: hashRed,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    commit.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.text, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(left: 17, top: 3),
            child: Text(
              '외 $more개',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ),
      ],
    ),
  );
}
