import 'package:flutter/material.dart';

import 'full_diff_code_row.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';
import 'typography.dart';

class InlinePresentationView extends StatelessWidget {
  const InlinePresentationView({
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
      itemBuilder: (context, index) {
        final hunk = document.hunks[index];
        final wordRanges = _wordRangesByLine(hunk.lines);
        final current = activeAnchor?.hunkIndex == hunk.index;
        return KeyedSubtree(
          key: _anchorKey(hunk.anchor),
          child: FullDiffSelectionArea(
            child: Column(
              key: Key('inline-hunk-$index'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InlineHunkHeader(
                  hunk: hunk,
                  path: path,
                  hunkCount: document.hunks.length,
                ),
                for (final line in hunk.lines)
                  FullDiffCodeRow(
                    line: line,
                    path: path,
                    wrapLines: wrapLines,
                    highlighter: highlighter,
                    current:
                        current &&
                        (line.kind == DiffLineKind.add ||
                            line.kind == DiffLineKind.delete),
                    wordRanges: wordRanges[line] ?? const [],
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

class _InlineHunkHeader extends StatelessWidget {
  const _InlineHunkHeader({
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
