import 'package:flutter/material.dart';

import 'full_diff_theme.dart';
import 'typography.dart';

@immutable
class FullDiffCommitInfo {
  const FullDiffCommitInfo({
    required this.sha,
    required this.shortSha,
    required this.fallbackMessage,
    required this.author,
    required this.timestamp,
  });

  final String sha;
  final String shortSha;
  final String fallbackMessage;
  final String author;
  final int? timestamp;
}

typedef FullDiffCommitMessageLoader = Future<String> Function(String sha);

class FullDiffCommitInfoCard extends StatefulWidget {
  const FullDiffCommitInfoCard({
    required this.info,
    this.loadMessage,
    this.scrollLongMessage = false,
    super.key,
  });

  final FullDiffCommitInfo info;
  final FullDiffCommitMessageLoader? loadMessage;
  final bool scrollLongMessage;

  @override
  State<FullDiffCommitInfoCard> createState() => _FullDiffCommitInfoCardState();
}

class _FullDiffCommitInfoCardState extends State<FullDiffCommitInfoCard> {
  String? _message;
  var _requestSerial = 0;
  final _messageScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FullDiffCommitInfoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.sha == widget.info.sha) return;
    if (_messageScrollController.hasClients) {
      _messageScrollController.jumpTo(0);
    }
    _load();
  }

  @override
  void dispose() {
    _requestSerial++;
    _messageScrollController.dispose();
    super.dispose();
  }

  void _load() {
    final serial = ++_requestSerial;
    _message = null;
    final sha = widget.info.sha;
    if (sha.isEmpty || widget.loadMessage == null) return;
    widget.loadMessage!(sha).then(
      (message) {
        if (!mounted || serial != _requestSerial) return;
        setState(() => _message = message);
      },
      onError: (_) {
        // Keep fallbackMessage and allow the shared cache to retry later.
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final message = _message ?? info.fallbackMessage;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        key: const Key('full-diff-commit-card-surface'),
        decoration: BoxDecoration(
          color: fullDiffHeader,
          border: Border.all(
            color: fullDiffAccent.withValues(alpha: 0.72),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white, fontSize: 11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.scrollLongMessage)
                  _ScrollableCommitMessage(
                    message: message,
                    controller: _messageScrollController,
                  )
                else
                  Text(
                    message,
                    key: const Key('full-diff-commit-message'),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: _commitMessageStyle,
                  ),
                const SizedBox(height: 4),
                Wrap(
                  key: const Key('full-diff-commit-metadata'),
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    Text(
                      info.shortSha,
                      style: const TextStyle(
                        color: fullDiffAccent,
                        fontFamily: technicalFontFamily,
                        fontFamilyFallback: technicalFontFallback,
                        fontSize: 10,
                      ),
                    ),
                    const Text('·'),
                    Text(info.author),
                    const Text('·'),
                    Text(
                      _formatDateTime(info.timestamp),
                      style: const TextStyle(
                        color: fullDiffMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _commitMessageStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
);

class _ScrollableCommitMessage extends StatelessWidget {
  const _ScrollableCommitMessage({
    required this.message,
    required this.controller,
  });

  final String message;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(_commitMessageStyle);
    final lineProbe = TextPainter(
      text: TextSpan(text: List.filled(8, 'M').join('\n'), style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 8,
    )..layout();
    final maxHeight = lineProbe.height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        interactive: true,
        thickness: 4,
        radius: const Radius.circular(2),
        child: SingleChildScrollView(
          key: const Key('full-diff-commit-message-scroll'),
          controller: controller,
          primary: false,
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            message,
            key: const Key('full-diff-commit-message'),
            maxLines: null,
            overflow: TextOverflow.clip,
            style: _commitMessageStyle,
          ),
        ),
      ),
    );
  }
}

String _formatDateTime(int? timestamp) {
  if (timestamp == null) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch(
    timestamp * Duration.millisecondsPerSecond,
  );
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}
