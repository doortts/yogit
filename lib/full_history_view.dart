import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'full_diff_model.dart';
import 'full_diff_theme.dart';
import 'typography.dart';

class HistoryEntryIntent extends Intent {
  const HistoryEntryIntent(this.entry);

  final FileHistoryEntry entry;
}

class FullHistoryView extends StatelessWidget {
  const FullHistoryView({
    required this.entries,
    required this.onSelected,
    this.selected,
    this.controller,
    super.key,
  });

  final List<FileHistoryEntry> entries;
  final ValueChanged<FileHistoryEntry> onSelected;
  final FileHistoryEntry? selected;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No file history',
          style: TextStyle(color: fullDiffMuted, fontSize: 14),
        ),
      );
    }
    return Actions(
      actions: {
        HistoryEntryIntent: CallbackAction<HistoryEntryIntent>(
          onInvoke: (intent) {
            onSelected(intent.entry);
            return null;
          },
        ),
      },
      child: FocusTraversalGroup(
        child: ListView.builder(
          key: const Key('history-list'),
          controller: controller,
          primary: controller == null,
          padding: const EdgeInsets.all(12),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final isSelected = identical(entry, selected);
            void activate() =>
                Actions.invoke(context, HistoryEntryIntent(entry));
            return Focus(
              autofocus: index == 0,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  activate();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Semantics(
                selected: isSelected,
                button: true,
                onTap: activate,
                child: InkWell(
                  onTap: activate,
                  child: HistoryRow(entry: entry),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class HistoryRow extends StatelessWidget {
  const HistoryRow({required this.entry, super.key});

  final FileHistoryEntry entry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: Key('history-row-${entry.commit.sha}'),
    color: fullDiffCanvas,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: fullDiffChip,
                  borderRadius: BorderRadius.circular(fullDiffChipRadius),
                ),
                child: Text(
                  entry.commit.shortSha,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    fontFamily: technicalFontFamily,
                    fontFamilyFallback: technicalFontFallback,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.commit.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.commit.author.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: fullDiffMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Text(
                      ' · ',
                      style: TextStyle(color: fullDiffMuted, fontSize: 12),
                    ),
                    Text(
                      _relativeTime(entry.commit.committerTimestamp),
                      maxLines: 1,
                      style: const TextStyle(
                        color: fullDiffMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _relativeTime(int timestamp) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  final elapsed = DateTime.now().difference(time);
  String ago(int value, String unit) =>
      '$value $unit${value == 1 ? '' : 's'} ago';
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return ago(elapsed.inMinutes, 'minute');
  if (elapsed.inHours < 48) return ago(elapsed.inHours, 'hour');
  if (elapsed.inDays < 30) return ago(elapsed.inDays, 'day');
  if (elapsed.inDays < 365) return ago(elapsed.inDays ~/ 30, 'month');
  return ago(elapsed.inDays ~/ 365, 'year');
}
