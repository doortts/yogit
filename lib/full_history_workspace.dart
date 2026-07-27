import 'package:flutter/material.dart';

import 'full_diff_resizable_pane.dart';
import 'settings.dart';

class FullHistoryWorkspace extends StatelessWidget {
  const FullHistoryWorkspace({
    required this.historyWidth,
    required this.onHistoryResized,
    required this.onHistoryResizeEnd,
    required this.history,
    required this.detail,
    super.key,
  });

  final double historyWidth;
  final ValueChanged<double> onHistoryResized;
  final VoidCallback onHistoryResizeEnd;
  final Widget history;
  final Widget detail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final maxHistory = (constraints.maxWidth - 320).clamp(
        FullDiffColumnWidths.minHistory,
        FullDiffColumnWidths.maxHistory,
      );
      return Row(
        children: [
          KeyedSubtree(
            key: const Key('history-list-pane'),
            child: FullDiffResizablePane(
              width: historyWidth,
              minWidth: FullDiffColumnWidths.minHistory,
              maxWidth: maxHistory,
              label: 'History pane width',
              resizerKey: const Key('history-list-column-resizer'),
              dividerKey: const Key('history-detail-divider'),
              onChanged: onHistoryResized,
              onChangeEnd: onHistoryResizeEnd,
              child: history,
            ),
          ),
          Expanded(
            key: const Key('full-diff-detail-pane'),
            child: KeyedSubtree(
              key: const Key('history-detail-pane'),
              child: detail,
            ),
          ),
        ],
      );
    },
  );
}
