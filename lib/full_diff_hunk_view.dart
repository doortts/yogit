import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'full_diff_code_row.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';
import 'typography.dart';

class HunkPresentationView extends StatelessWidget {
  const HunkPresentationView({
    required this.document,
    required this.activeAnchor,
    required this.path,
    required this.wrapLines,
    required this.highlighter,
    required this.anchorKeys,
    this.controller,
    super.key,
  });

  final DiffDocument document;
  final DiffAnchor? activeAnchor;
  final String path;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final Map<String, GlobalKey> anchorKeys;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final hunkIndex = activeAnchor?.hunkIndex;
    if (hunkIndex == null ||
        hunkIndex < 0 ||
        hunkIndex >= document.hunks.length) {
      return const Center(
        child: Text(
          '현재 옵션으로 표시할 변경이 없습니다',
          style: TextStyle(color: fullDiffMuted, fontSize: 14),
        ),
      );
    }

    final hunk = document.hunks[hunkIndex];
    final wordRanges = _wordRangesByLine(hunk.lines);
    Widget list({required bool horizontalScroll}) => ListView(
      key: const Key('hunk-list'),
      controller: controller,
      primary: controller == null,
      children: [
        KeyedSubtree(
          key: Key('hunk-card-surface-${hunk.anchor.id}'),
          child: KeyedSubtree(
            key: _anchorKey(hunk.anchor),
            child: _PresentationHunkHeader(
              hunk: hunk,
              path: path,
              hunkCount: document.hunks.length,
            ),
          ),
        ),
        for (final (index, line) in hunk.changedLines.indexed)
          FullDiffCodeRow(
            key: Key('hunk-line-${hunk.anchor.id}-$index'),
            line: line,
            path: path,
            wrapLines: wrapLines,
            highlighter: highlighter,
            current: index == 0,
            wordRanges: wordRanges[line] ?? const [],
            horizontalScroll: horizontalScroll,
          ),
      ],
    );

    if (wrapLines) {
      return FullDiffSelectionArea(child: list(horizontalScroll: false));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          constraints.maxWidth,
          _unwrappedContentWidth(context, hunk.changedLines),
        );
        return FullDiffSelectionArea(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: list(horizontalScroll: false),
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

double _unwrappedContentWidth(BuildContext context, Iterable<DiffLine> lines) {
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  );
  var widest = 0.0;
  for (final line in lines) {
    painter.text = TextSpan(
      text: line.text,
      style: const TextStyle(
        fontFamily: technicalFontFamily,
        fontFamilyFallback: technicalFontFallback,
        fontSize: 14,
      ),
    );
    painter.layout();
    widest = math.max(widest, painter.width);
  }
  return fullDiffLineNumberWidth + widest + 20;
}

class _PresentationHunkHeader extends StatelessWidget {
  const _PresentationHunkHeader({
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

Map<DiffLine, List<WordRange>> _wordRangesByLine(List<DiffLine> lines) {
  final ranges = <DiffLine, List<WordRange>>{};
  for (final pair in pairDiff(lines)) {
    final left = pair.left;
    final right = pair.right;
    if (left?.kind != DiffLineKind.delete || right?.kind != DiffLineKind.add) {
      continue;
    }
    final changes = changedWordRanges(left!.text, right!.text);
    ranges[left] = changes.oldRanges;
    ranges[right] = changes.newRanges;
  }
  return ranges;
}
