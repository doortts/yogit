import 'package:flutter/material.dart';

import 'full_diff_code_row.dart';
import 'full_diff_hunk_header.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';

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
        final firstChange = hunk.lines.indexWhere(
          (line) =>
              line.kind == DiffLineKind.add || line.kind == DiffLineKind.delete,
        );
        final leadingContextCount = firstChange < 0 ? 0 : firstChange;
        Widget codeRow(DiffLine line) => FullDiffCodeRow(
          line: line,
          path: path,
          wrapLines: wrapLines,
          highlighter: highlighter,
          current:
              current &&
              (line.kind == DiffLineKind.add ||
                  line.kind == DiffLineKind.delete),
          wordRanges: wordRanges[line] ?? const [],
          compactGutter: true,
        );
        return KeyedSubtree(
          key: _anchorKey(hunk.anchor),
          child: FullDiffSelectionArea(
            child: Column(
              key: Key('inline-hunk-$index'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in hunk.lines.take(leadingContextCount))
                  codeRow(line),
                FullDiffHunkHeader(
                  hunk: hunk,
                  path: path,
                  hunkCount: document.hunks.length,
                ),
                for (final line in hunk.lines.skip(leadingContextCount))
                  codeRow(line),
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
