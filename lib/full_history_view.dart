import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yogit/vim_navigation.dart';

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
    final key = normalizeNavigationKey(
      event.logicalKey,
      hasModifier:
          keyboard.isMetaPressed ||
          keyboard.isAltPressed ||
          keyboard.isShiftPressed ||
          keyboard.isControlPressed,
    );
    if (keyboard.isMetaPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onMoveToFiles?.call();
      return KeyEventResult.handled;
    }
    final delta = switch (key) {
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
    final selected = widget.selected;
    return Focus(
      key: const Key('history-list-focus'),
      focusNode: _focusNode,
      onFocusChange: (hasFocus) {
        if (_hasFocus != hasFocus) setState(() => _hasFocus = hasFocus);
      },
      onKeyEvent: _handleKey,
      child: FocusTraversalGroup(
        child: ColoredBox(
          color: fullDiffCanvas,
          child: ListView.builder(
            key: const Key('history-list'),
            controller: _scrollController,
            primary: false,
            padding: EdgeInsets.zero,
            itemCount: widget.entries.length,
            itemBuilder: (context, index) {
              final entry = widget.entries[index];
              final isSelected = identical(entry, selected);
              void activate() {
                _focusNode.requestFocus();
                widget.onSelected(entry);
              }

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
  Widget build(BuildContext context) {
    final secondary = selected ? Colors.white70 : fullDiffMuted;
    return FullDiffSelectableRowSurface(
      key: Key('history-row-${entry.commit.sha}'),
      selected: selected,
      focused: focused,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            // The bar names the selected commit even where the row's own fill
            // is hidden under a scrollbar or a neighbouring pane.
            left: BorderSide(
              color: selected ? fullDiffAccent : Colors.transparent,
              width: 2,
            ),
            bottom: BorderSide(color: fullDiffDivider.withValues(alpha: 0.4)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(9, 7, 11, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  entry.commit.shortSha,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: technicalTextStyle.copyWith(
                    color: fullDiffAccent,
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                Text(
                  _shortDate(entry.commit.committerTimestamp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: technicalTextStyle.copyWith(
                    color: secondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              entry.commit.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            const SizedBox(height: 1),
            Text(
              entry.commit.author.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortDate(int timestamp) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)}';
}
