import 'package:flutter/material.dart';

import 'full_diff_anchor_probe.dart';
import 'full_diff_code_row.dart';
import 'full_diff_hunk_header.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';

class SideBySidePresentationView extends StatelessWidget {
  const SideBySidePresentationView({
    required this.document,
    required this.activeAnchor,
    required this.oldPath,
    required this.newPath,
    required this.wrapLines,
    required this.showOldSide,
    required this.highlighter,
    required this.anchorKeys,
    this.richRenderingEnabled = true,
    this.wordDiffer = changedWordRanges,
    this.onAnchorProbeAttached,
    this.onAnchorProbeDetached,
    this.controller,
    this.scrollTarget,
    this.scrollTargetKey,
    super.key,
  });

  final DiffDocument document;
  final DiffAnchor? activeAnchor;
  final String oldPath;
  final String newPath;
  final bool wrapLines;
  final bool showOldSide;
  final FullDiffSyntaxHighlighter highlighter;
  final Map<String, GlobalKey> anchorKeys;
  final bool richRenderingEnabled;
  final FullDiffWordDiffer wordDiffer;
  final FullDiffAnchorProbeCallback? onAnchorProbeAttached;
  final FullDiffAnchorProbeCallback? onAnchorProbeDetached;
  final ScrollController? controller;
  final DiffSourceTarget? scrollTarget;
  final GlobalKey? scrollTargetKey;

  @override
  Widget build(BuildContext context) {
    if (document.hunks.isEmpty) {
      return const Center(
        child: Text(
          '현재 옵션으로 표시할 변경이 없습니다',
          style: TextStyle(color: fullDiffMuted, fontSize: 10),
        ),
      );
    }

    final items = _sideBySideItems(document);
    final scrollTargetIndex = diffSourceTargetIndex(
      rows: items,
      target: scrollTarget,
      oldLineOf: (item) => item.pair?.left,
      newLineOf: (item) => item.pair?.right,
    );
    final allSourceText = [
      for (final item in items)
        if (item.pair case final pair?) _pairSourceText(pair, showOldSide),
    ].join('\n');
    final list = FullDiffSelectionArea(
      allSourceText: allSourceText,
      child: ListView.builder(
        key: const Key('side-by-side-list'),
        controller: controller,
        primary: controller == null,
        itemCount: items.length,
        itemBuilder: (context, itemIndex) {
          final item = items[itemIndex];
          final hunk = item.hunk;
          final current = activeAnchor?.hunkIndex == hunk.index;
          Widget child;
          if (item.pair case final pair?) {
            child = _SideBySideRow(
              key: Key('side-by-side-row-${hunk.index}-${item.pairIndex}'),
              pair: pair,
              sourceRow: item.sourceRow!,
              oldPath: oldPath,
              newPath: newPath,
              wrapLines: wrapLines,
              showOldSide: showOldSide,
              highlighter: highlighter,
              current: current,
              richRenderingEnabled: richRenderingEnabled,
              wordDiffer: wordDiffer,
            );
          } else {
            child = SelectionContainer.disabled(
              child: FullDiffHunkHeader(
                hunk: hunk,
                path: newPath,
                hunkCount: document.hunks.length,
              ),
            );
          }
          if (item.anchorTarget) {
            child = KeyedSubtree(
              key: _anchorKey(hunk.anchor),
              child: KeyedSubtree(
                key: Key('side-by-side-hunk-${hunk.index}'),
                child: child,
              ),
            );
          }
          if (itemIndex == scrollTargetIndex && scrollTargetKey != null) {
            child = KeyedSubtree(key: scrollTargetKey, child: child);
          }
          return FullDiffAnchorProbe(
            anchor: hunk.anchor,
            onAttached: onAnchorProbeAttached,
            onDetached: onAnchorProbeDetached,
            child: child,
          );
        },
      ),
    );
    return showOldSide
        ? KeyedSubtree(key: const Key('side-by-side-old-pane'), child: list)
        : list;
  }

  GlobalKey _anchorKey(DiffAnchor anchor) =>
      anchorKeys[anchor.id] ??
      (throw StateError('Missing GlobalKey for ${anchor.id}'));
}

List<_SideBySideItem> _sideBySideItems(DiffDocument document) {
  final items = <_SideBySideItem>[];
  var sourceRow = 0;
  for (final hunk in document.hunks) {
    final pairs = pairDiff(hunk.lines);
    final firstChange = pairs.indexWhere(
      (pair) =>
          pair.left?.kind == DiffLineKind.delete ||
          pair.right?.kind == DiffLineKind.add,
    );
    final leadingContextCount = firstChange < 0 ? 0 : firstChange;
    void addPair(int pairIndex) {
      items.add(
        _SideBySideItem(
          hunk: hunk,
          pair: pairs[pairIndex],
          pairIndex: pairIndex,
          sourceRow: sourceRow++,
        ),
      );
    }

    for (var index = 0; index < leadingContextCount; index++) {
      addPair(index);
    }
    items.add(_SideBySideItem(hunk: hunk, anchorTarget: true));
    for (var index = leadingContextCount; index < pairs.length; index++) {
      addPair(index);
    }
  }
  return items;
}

String _pairSourceText(DiffPair pair, bool showOldSide) {
  final left = pair.left?.text;
  final right = pair.right?.text;
  if (!showOldSide) return right ?? '';
  if (left == null) return right ?? '';
  if (right == null) return left;
  return '$left\t$right';
}

class _SideBySideItem {
  const _SideBySideItem({
    required this.hunk,
    this.pair,
    this.pairIndex,
    this.sourceRow,
    this.anchorTarget = false,
  });

  final DiffHunk hunk;
  final DiffPair? pair;
  final int? pairIndex;
  final int? sourceRow;
  final bool anchorTarget;
}

class _SideBySideRow extends StatelessWidget {
  const _SideBySideRow({
    required this.pair,
    required this.sourceRow,
    required this.oldPath,
    required this.newPath,
    required this.wrapLines,
    required this.showOldSide,
    required this.highlighter,
    required this.current,
    required this.richRenderingEnabled,
    required this.wordDiffer,
    super.key,
  });

  final DiffPair pair;
  final int sourceRow;
  final String oldPath;
  final String newPath;
  final bool wrapLines;
  final bool showOldSide;
  final FullDiffSyntaxHighlighter highlighter;
  final bool current;
  final bool richRenderingEnabled;
  final FullDiffWordDiffer wordDiffer;

  @override
  Widget build(BuildContext context) {
    final left = pair.left;
    final right = pair.right;
    final wordChanges =
        richRenderingEnabled &&
            left?.kind == DiffLineKind.delete &&
            right?.kind == DiffLineKind.add
        ? wordDiffer(left!.text, right!.text)
        : WordChangeRanges.empty;
    final markCurrent =
        current &&
        (left?.kind == DiffLineKind.delete || right?.kind == DiffLineKind.add);
    final newSide = right == null
        ? HatchedDiffCell(key: Key('side-by-side-missing-new-$sourceRow'))
        : FullDiffCodeRow(
            line: right,
            path: newPath,
            wrapLines: wrapLines,
            highlighter: highlighter,
            current: markCurrent,
            wordRanges: wordChanges.newRanges,
            compactGutter: true,
            richRenderingEnabled: richRenderingEnabled,
            selectionOrder: FullDiffSelectionOrder(
              row: sourceRow,
              column: showOldSide ? 1 : 0,
            ),
          );

    if (!showOldSide) return newSide;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: left == null
              ? HatchedDiffCell(key: Key('side-by-side-missing-old-$sourceRow'))
              : FullDiffCodeRow(
                  line: left,
                  path: oldPath,
                  wrapLines: wrapLines,
                  highlighter: highlighter,
                  current: markCurrent,
                  wordRanges: wordChanges.oldRanges,
                  compactGutter: true,
                  richRenderingEnabled: richRenderingEnabled,
                  selectionOrder: FullDiffSelectionOrder(row: sourceRow),
                ),
        ),
        const VerticalDivider(width: 1, color: fullDiffDivider),
        Expanded(child: newSide),
      ],
    );
    return wrapLines
        ? IntrinsicHeight(child: row)
        : SizedBox(height: 27, child: row);
  }
}

class HatchedDiffCell extends StatelessWidget {
  const HatchedDiffCell({super.key});

  @override
  Widget build(BuildContext context) => const ClipRect(
    child: CustomPaint(
      painter: _HatchedDiffPainter(),
      child: SizedBox(height: 27),
    ),
  );
}

class _HatchedDiffPainter extends CustomPainter {
  const _HatchedDiffPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF353535),
    );
    final paint = Paint()
      ..color = const Color(0xFF4A4A4A)
      ..strokeWidth = 1;
    for (var offset = -size.height; offset < size.width; offset += 8) {
      canvas.drawLine(
        Offset(offset, size.height),
        Offset(offset + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchedDiffPainter oldDelegate) => false;
}
