import 'package:flutter/material.dart';

import 'full_diff_code_row.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';
import 'typography.dart';

class SplitPresentationView extends StatelessWidget {
  const SplitPresentationView({
    required this.document,
    required this.activeAnchor,
    required this.oldPath,
    required this.newPath,
    required this.wrapLines,
    required this.showOldSide,
    required this.highlighter,
    required this.anchorKeys,
    this.controller,
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
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    if (document.hunks.isEmpty) {
      return const Center(
        child: Text(
          '현재 옵션으로 표시할 변경이 없습니다',
          style: TextStyle(color: fullDiffMuted, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      controller: controller,
      primary: controller == null,
      itemCount: document.hunks.length,
      itemBuilder: (context, hunkIndex) {
        final hunk = document.hunks[hunkIndex];
        final current = activeAnchor?.hunkIndex == hunk.index;
        return KeyedSubtree(
          key: _anchorKey(hunk.anchor),
          child: SelectionArea(
            child: Column(
              key: Key('split-hunk-$hunkIndex'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SplitHunkHeader(
                  hunk: hunk,
                  path: newPath,
                  hunkCount: document.hunks.length,
                ),
                for (final (rowIndex, pair) in pairDiff(hunk.lines).indexed)
                  _SplitRow(
                    pair: pair,
                    rowIndex: rowIndex,
                    oldPath: oldPath,
                    newPath: newPath,
                    wrapLines: wrapLines,
                    showOldSide: showOldSide,
                    highlighter: highlighter,
                    current: current,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  GlobalKey _anchorKey(DiffAnchor anchor) =>
      anchorKeys[anchor.id] ??
      (throw StateError('Missing GlobalKey for ${anchor.id}'));
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.pair,
    required this.rowIndex,
    required this.oldPath,
    required this.newPath,
    required this.wrapLines,
    required this.showOldSide,
    required this.highlighter,
    required this.current,
  });

  final DiffPair pair;
  final int rowIndex;
  final String oldPath;
  final String newPath;
  final bool wrapLines;
  final bool showOldSide;
  final FullDiffSyntaxHighlighter highlighter;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final left = pair.left;
    final right = pair.right;
    final wordChanges =
        left?.kind == DiffLineKind.delete && right?.kind == DiffLineKind.add
        ? changedWordRanges(left!.text, right!.text)
        : WordChangeRanges.empty;
    final markCurrent =
        current &&
        (left?.kind == DiffLineKind.delete || right?.kind == DiffLineKind.add);
    final newSide = right == null
        ? HatchedDiffCell(key: Key('split-missing-new-$rowIndex'))
        : FullDiffCodeRow(
            line: right,
            path: newPath,
            wrapLines: wrapLines,
            highlighter: highlighter,
            current: markCurrent,
            wordRanges: wordChanges.newRanges,
          );

    if (!showOldSide) return newSide;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: left == null
              ? HatchedDiffCell(key: Key('split-missing-old-$rowIndex'))
              : FullDiffCodeRow(
                  line: left,
                  path: oldPath,
                  wrapLines: wrapLines,
                  highlighter: highlighter,
                  current: markCurrent,
                  wordRanges: wordChanges.oldRanges,
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
  Widget build(BuildContext context) => const CustomPaint(
    painter: _HatchedDiffPainter(),
    child: SizedBox(height: 27),
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

class _SplitHunkHeader extends StatelessWidget {
  const _SplitHunkHeader({
    required this.hunk,
    required this.path,
    required this.hunkCount,
  });

  final DiffHunk hunk;
  final String path;
  final int hunkCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: const BoxDecoration(
      color: fullDiffHunkHeader,
      border: Border(
        top: BorderSide(color: fullDiffDivider),
        bottom: BorderSide(color: fullDiffDivider),
      ),
    ),
    child: Text(
      '${hunk.context.isEmpty ? path : hunk.context} · '
      'lines ${hunk.displayRange} · '
      'change ${hunk.index + 1} of $hunkCount',
      style: const TextStyle(
        fontFamily: technicalFontFamily,
        fontFamilyFallback: technicalFontFallback,
        fontSize: 14,
        height: 21 / 14,
        color: fullDiffMuted,
      ),
    ),
  );
}
