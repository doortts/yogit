import 'package:flutter/material.dart';

import 'local_state_signature.dart';
import 'timeline_palette.dart';
import 'timeline_theme.dart';
import 'timeline_widgets.dart';
import 'typography.dart';

/// Push 확인창의 제목 아래 한 줄: 'origin'이 실제로 어디인지. 올리기 전에
/// 회사 저장소인지 포크인지 눈으로 확인할 마지막 자리다. `origin: 주소` —
/// 키보드로 못 치는 글자는 쓰지 않고, 주소는 끌어서 골라 복사할 수 있다.
/// 고르는 것은 주소뿐이라 복사한 값에 이름표가 딸려 오지 않는다.
/// docs/alert-square-command-mockup.html이 계약이다.
class PushTarget extends StatelessWidget {
  const PushTarget({required this.remote, required this.url, super.key});

  final String remote;
  final String url;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    return Row(
      key: const Key('push-target'),
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$remote:', style: TextStyle(fontSize: 11, color: palette.muted)),
        const SizedBox(width: 6),
        Flexible(
          child: SelectableText(
            url,
            key: const Key('push-target-url'),
            maxLines: 1,
            style: TextStyle(
              color: palette.muted,
              fontFamily: technicalFontFamily,
              fontFamilyFallback: technicalFontFallback,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// 버튼 바로 위: 확인을 누르면 실제로 돌아갈 git 명령. 여러 걸음이면 여러
/// 줄이고 순서가 곧 실행 순서다. 이 상자도 끌어서 복사된다 — 터미널에서 직접
/// 해 보려면 그대로 붙이면 된다. 늘 두르는 자격증명 차단 인자
/// (`-c credential.interactive=never`)는 행위가 아니므로 적지 않는다.
class CommandPreview extends StatelessWidget {
  const CommandPreview(this.lines, {super.key});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    return Container(
      key: const Key('command-preview'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.75),
        border: Border.all(color: palette.border, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '실행할 명령',
            style: TextStyle(
              color: palette.muted,
              fontSize: 10,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            lines.join('\n'),
            key: const Key('command-preview-text'),
            style: TextStyle(
              color: palette.text,
              fontFamily: technicalFontFamily,
              fontFamilyFallback: technicalFontFallback,
              fontSize: 11.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Push 확인창의 몸통: 저장소 변경 알림과 같은 형식으로, 요약줄 아래 오갈
/// 커밋이 서고 물음은 맨 끝이다 — 무엇이 움직이는지 읽은 뒤에 답하는 순서.
/// 주황(받아 얹고 Push)일 때는 두 걸음이 블록 둘로 선다.
/// docs/upstream-sync-mockup.html '누르면' 절이 계약이다.
class PushSummary extends StatelessWidget {
  const PushSummary({
    required this.branch,
    required this.incoming,
    required this.outgoing,
    required this.footnote,
    this.incomingTotal,
    this.outgoingTotal,
    this.loadIncomingRest,
    this.loadOutgoingRest,
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
  /// 말한다. 목록이 실물보다 적게 말하는 일은 없어야 한다.
  final int? incomingTotal;
  final int? outgoingTotal;

  /// '외 N개'를 누를 때에야 나머지를 읽어 온다 — 확인창을 여는 조회는 가볍게
  /// 두고, 값은 실제로 펼친 사람만 치른다. null이면 그 블록은 세기만 한다.
  final Future<List<MovedCommit>> Function()? loadIncomingRest;
  final Future<List<MovedCommit>> Function()? loadOutgoingRest;

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    return Column(
      key: const Key('push-summary'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 목록이 비어도 올 것이 있으면 블록은 선다 — 창이 한쪽으로 쏠려도
        // 확인창에서 걸음 하나가 통째로 사라지지는 않는다.
        // ponytail: 18-commit shared window; query the two sides separately
        // if a summary ever needs full rows on both under extreme skew.
        if ((incomingTotal ?? incoming.length) > 0)
          _SummaryBlock(
            key: const Key('push-summary-pull-block'),
            branch: branch,
            op: 'pull --rebase',
            count: '커밋 ${incomingTotal ?? incoming.length}개 들어옴',
            countColor: mainAccent,
            commits: incoming,
            total: incomingTotal ?? incoming.length,
            mark: '+',
            markColor: mainAccent,
            moreKey: const Key('push-summary-pull-more'),
            loadRest: loadIncomingRest,
          ),
        if ((outgoingTotal ?? outgoing.length) > 0)
          _SummaryBlock(
            key: const Key('push-summary-push-block'),
            branch: branch,
            op: 'push',
            count: '커밋 ${outgoingTotal ?? outgoing.length}개 올라감',
            countColor: previewControlBlue,
            commits: outgoing,
            total: outgoingTotal ?? outgoing.length,
            mark: '↑',
            markColor: previewControlBlue,
            moreKey: const Key('push-summary-push-more'),
            loadRest: loadOutgoingRest,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Text(
            footnote,
            key: const Key('push-summary-footnote'),
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
}

/// 오갈 커밋 목록의 한 걸음. 목록은 아홉 줄에서 멈추고 '외 N개'가 남은 수를 센다 —
/// 누르면 나머지를 그때 읽어 와 아홉 줄 높이 안에서 구른다. 창은 커지지 않고,
/// 다시 누르면 접힌다. 펼침은 블록마다 따로다.
class _SummaryBlock extends StatefulWidget {
  const _SummaryBlock({
    required this.branch,
    required this.op,
    required this.count,
    required this.countColor,
    required this.commits,
    required this.total,
    required this.mark,
    required this.markColor,
    required this.moreKey,
    required this.loadRest,
    super.key,
  });

  final String branch;
  final String op;
  final String count;
  final Color countColor;
  final List<MovedCommit> commits;
  final int total;
  final String mark;
  final Color markColor;
  final Key moreKey;
  final Future<List<MovedCommit>> Function()? loadRest;

  @override
  State<_SummaryBlock> createState() => _SummaryBlockState();
}

class _SummaryBlockState extends State<_SummaryBlock> {
  /// 스크롤 영역의 키: 접힌 목록과 같은 아홉 줄 높이.
  static const _openHeight = 168.0;

  bool _open = false;
  bool _loading = false;
  List<MovedCommit>? _rest;

  List<MovedCommit> get _shown =>
      _open ? _rest ?? widget.commits : widget.commits;

  Future<void> _toggle() async {
    if (_open) {
      setState(() => _open = false);
      return;
    }
    if (_rest != null) {
      setState(() => _open = true);
      return;
    }
    final loader = widget.loadRest;
    if (loader == null) return;
    setState(() => _loading = true);
    final loaded = await loader();
    if (!mounted) return;
    setState(() {
      _loading = false;
      // 읽어 온 것이 이미 보이는 것보다 적으면 — 그새 원격이 움직였거나 조회가
      // 실패했다 — 보이던 목록을 그대로 두고 펼치지 않는다.
      if (loaded.length <= widget.commits.length) return;
      _rest = loaded;
      _open = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.timelineTheme;
    final shown = _shown;
    final more = widget.total - shown.length;
    final rows = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final commit in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 17,
                  child: Text(
                    widget.mark,
                    style: TextStyle(
                      color: widget.markColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  commit.shortSha,
                  style: const TextStyle(
                    color: hashRed,
                    fontFamily: technicalFontFamily,
                    fontFamilyFallback: technicalFontFallback,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    commit.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // 제목도 해시와 같은 계열로 — 커밋 목록은 프롬프트에서
                    // 읽는 그 글자로 선다.
                    style: TextStyle(
                      color: palette.text,
                      fontFamily: technicalFontFamily,
                      fontFamilyFallback: technicalFontFallback,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 펼쳐도 남는 것이 있으면(500 천장) 스크롤 끝에서 계속 센다.
        if (_open && more > 0)
          Padding(
            padding: const EdgeInsets.only(left: 17, top: 3),
            child: Text(
              '외 $more개',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ),
      ],
    );
    return Container(
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
                    text: widget.branch,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '  ·  ',
                    style: TextStyle(color: palette.muted),
                  ),
                  TextSpan(
                    text: widget.op,
                    style: TextStyle(
                      color: previewControlBlue,
                      fontFamily: technicalFontFamily,
                      fontFamilyFallback: technicalFontFallback,
                      fontSize: 11.5,
                    ),
                  ),
                  TextSpan(
                    text: '  ·  ',
                    style: TextStyle(color: palette.muted),
                  ),
                  TextSpan(
                    text: widget.count,
                    style: TextStyle(color: widget.countColor),
                  ),
                ],
              ),
              style: TextStyle(color: palette.text, fontSize: 12.5),
            ),
          ),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 6),
          if (_open)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _openHeight),
              child: SingleChildScrollView(child: rows),
            )
          else
            rows,
          if (_open || (more > 0 && widget.loadRest != null))
            MoreLink(
              key: widget.moreKey,
              label: _loading
                  ? '불러오는 중'
                  : _open
                  ? '접기'
                  : '외 $more개',
              onTap: _loading ? null : _toggle,
            )
          else if (more > 0)
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
}
