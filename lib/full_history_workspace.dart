import 'package:flutter/material.dart';

import 'full_diff_theme.dart';

class FullHistoryWorkspace extends StatelessWidget {
  const FullHistoryWorkspace({
    required this.history,
    required this.detail,
    super.key,
  });

  final Widget history;
  final Widget detail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 760
          ? 280.0
          : (constraints.maxWidth * 0.35).clamp(180.0, 240.0);
      return Row(
        children: [
          SizedBox(
            key: const Key('history-list-pane'),
            width: width,
            child: history,
          ),
          const SizedBox(
            key: Key('history-detail-divider'),
            width: 1,
            child: ColoredBox(color: fullDiffDivider),
          ),
          Expanded(key: const Key('history-detail-pane'), child: detail),
        ],
      );
    },
  );
}
