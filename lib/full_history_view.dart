import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'full_diff_model.dart';
import 'full_diff_selectable_row.dart';
import 'full_diff_theme.dart';
import 'typography.dart';

class FullHistoryView extends StatefulWidget {
  const FullHistoryView({
    required this.entries,
    required this.onSelected,
    this.selected,
    this.controller,
    this.focusNode,
    this.onMoveToFiles,
    super.key,
  });

  final List<FileHistoryEntry> entries;
  final ValueChanged<FileHistoryEntry> onSelected;
  final FileHistoryEntry? selected;
  final ScrollController? controller;
  final FocusNode? focusNode;
  final VoidCallback? onMoveToFiles;

  @override
  State<FullHistoryView> createState() => _FullHistoryViewState();
}

class _FullHistoryViewState extends State<FullHistoryView> {
  final _ownedFocusNode = FocusNode(debugLabel: 'full history list');
  final _ownedScrollController = ScrollController();
  final Map<String, GlobalKey> _rowKeys = {};
  bool _hasFocus = false;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;
  ScrollController get _scrollController =>
      widget.controller ?? _ownedScrollController;

  @override
  void didUpdateWidget(covariant FullHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shas = {for (final entry in widget.entries) entry.commit.sha};
    _rowKeys.removeWhere((sha, _) => !shas.contains(sha));
  }

  @override
  void dispose() {
    _ownedFocusNode.dispose();
    _ownedScrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onMoveToFiles?.call();
      return KeyEventResult.handled;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    _stepSelection(delta);
    return KeyEventResult.handled;
  }

  void _stepSelection(int delta) {
    if (widget.entries.isEmpty) return;
    final selectedIndex = widget.entries.indexWhere(
      (entry) => identical(entry, widget.selected),
    );
    final nextIndex = selectedIndex < 0
        ? (delta > 0 ? 0 : widget.entries.length - 1)
        : (selectedIndex + delta).clamp(0, widget.entries.length - 1);
    final entry = widget.entries[nextIndex];
    widget.onSelected(entry);
    _revealSelection(entry, nextIndex, delta);
  }

  void _revealSelection(
    FileHistoryEntry entry,
    int entryIndex,
    int direction, {
    bool mayApproximate = true,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _rowKeys[entry.commit.sha]?.currentContext;
      if (!mounted) return;
      if (rowContext == null) {
        if (!mayApproximate || !_scrollController.hasClients) return;
        final position = _scrollController.position;
        final fraction = widget.entries.length <= 1
            ? 0.0
            : entryIndex / (widget.entries.length - 1);
        position.jumpTo(position.maxScrollExtent * fraction);
        _revealSelection(entry, entryIndex, direction, mayApproximate: false);
        return;
      }
      Scrollable.ensureVisible(
        rowContext,
        alignmentPolicy: direction < 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const Center(
        child: Text(
          'No file history',
          style: TextStyle(color: fullDiffMuted, fontSize: 14),
        ),
      );
    }
    return Focus(
      key: const Key('history-list-focus'),
      focusNode: _focusNode,
      onFocusChange: (hasFocus) {
        if (_hasFocus != hasFocus) setState(() => _hasFocus = hasFocus);
      },
      onKeyEvent: _handleKey,
      child: FocusTraversalGroup(
        child: ListView.builder(
          key: const Key('history-list'),
          controller: _scrollController,
          primary: false,
          padding: EdgeInsets.zero,
          itemCount: widget.entries.length,
          itemBuilder: (context, index) {
            final entry = widget.entries[index];
            final isSelected = identical(entry, widget.selected);
            void activate() => widget.onSelected(entry);
            return KeyedSubtree(
              key: _rowKeys.putIfAbsent(
                entry.commit.sha,
                () => GlobalKey(debugLabel: 'history ${entry.commit.sha}'),
              ),
              child: Focus(
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
                    child: HistoryRow(
                      entry: entry,
                      selected: isSelected,
                      focused: isSelected && _hasFocus,
                    ),
                  ),
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
  const HistoryRow({
    required this.entry,
    this.selected = false,
    this.focused = false,
    super.key,
  });

  final FileHistoryEntry entry;
  final bool selected;
  final bool focused;

  @override
  Widget build(BuildContext context) => FullDiffSelectableRowSurface(
    key: Key('history-row-${entry.commit.sha}'),
    selected: selected,
    focused: focused,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    fontSize: 10,
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
                  style: TextStyle(
                    color: selected ? fullDiffAccent : Colors.white,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.commit.author.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? Colors.white70 : fullDiffMuted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    Text(
                      ' · ',
                      style: TextStyle(
                        color: selected ? Colors.white70 : fullDiffMuted,
                        fontSize: 10,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        _relativeTime(entry.commit.committerTimestamp),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? Colors.white70 : fullDiffMuted,
                          fontSize: 10,
                        ),
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
