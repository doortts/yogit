import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'full_diff_anchor_probe.dart';
import 'full_diff_code_row.dart';
import 'full_diff_hunk_header.dart';
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
    this.richRenderingEnabled = true,
    this.wordDiffer = changedWordRanges,
    this.onAnchorProbeAttached,
    this.onAnchorProbeDetached,
    this.controller,
    super.key,
  });

  final DiffDocument document;
  final DiffAnchor? activeAnchor;
  final String path;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final Map<String, GlobalKey> anchorKeys;
  final bool richRenderingEnabled;
  final FullDiffWordDiffer wordDiffer;
  final FullDiffAnchorProbeCallback? onAnchorProbeAttached;
  final FullDiffAnchorProbeCallback? onAnchorProbeDetached;
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
          style: TextStyle(color: fullDiffMuted, fontSize: 10),
        ),
      );
    }

    final hunk = document.hunks[hunkIndex];
    final lines = _hunkLines(hunk.lines);
    final allSourceText = lines
        .map((descriptor) => descriptor.line.text)
        .join('\n');
    Widget list({required bool horizontalScroll}) => ListView.builder(
      key: const Key('hunk-list'),
      controller: controller,
      primary: controller == null,
      itemCount: lines.length + 1,
      itemBuilder: (context, itemIndex) {
        if (itemIndex == 0) {
          Widget header = SelectionContainer.disabled(
            child: FullDiffHunkHeader(
              hunk: hunk,
              path: path,
              hunkCount: document.hunks.length,
            ),
          );
          if (lines.isEmpty) {
            header = KeyedSubtree(
              key: Key('hunk-card-surface-${hunk.anchor.id}'),
              child: KeyedSubtree(key: _anchorKey(hunk.anchor), child: header),
            );
          }
          return FullDiffAnchorProbe(
            anchor: hunk.anchor,
            onAttached: onAnchorProbeAttached,
            onDetached: onAnchorProbeDetached,
            child: header,
          );
        }
        final lineIndex = itemIndex - 1;
        final descriptor = lines[lineIndex];
        final wordRanges = richRenderingEnabled
            ? descriptor.wordRanges(wordDiffer)
            : const <WordRange>[];
        Widget row = FullDiffCodeRow(
          key: Key('hunk-line-${hunk.anchor.id}-$lineIndex'),
          line: descriptor.line,
          path: path,
          wrapLines: wrapLines,
          highlighter: highlighter,
          current: lineIndex == 0,
          wordRanges: wordRanges,
          horizontalScroll: horizontalScroll,
          richRenderingEnabled: richRenderingEnabled,
          selectionOrder: FullDiffSelectionOrder(row: lineIndex),
        );
        if (lineIndex == 0) {
          row = KeyedSubtree(
            key: Key('hunk-card-surface-${hunk.anchor.id}'),
            child: KeyedSubtree(key: _anchorKey(hunk.anchor), child: row),
          );
        }
        return FullDiffAnchorProbe(
          anchor: hunk.anchor,
          onAttached: onAnchorProbeAttached,
          onDetached: onAnchorProbeDetached,
          child: row,
        );
      },
    );

    if (wrapLines) {
      return FullDiffSelectionArea(
        allSourceText: allSourceText,
        child: list(horizontalScroll: false),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(
          constraints.maxWidth,
          _unwrappedContentWidth(context, hunk.changedLines),
        );
        return FullDiffSelectionArea(
          allSourceText: allSourceText,
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
        fontSize: 10,
      ),
    );
    painter.layout();
    widest = math.max(widest, painter.width);
  }
  return fullDiffLineNumberWidth + widest + 20;
}

List<_HunkLineDescriptor> _hunkLines(List<DiffLine> lines) {
  final descriptors = <DiffLine, _HunkLineDescriptor>{};
  for (final pair in pairDiff(lines)) {
    final left = pair.left;
    final right = pair.right;
    if (left?.kind != DiffLineKind.delete || right?.kind != DiffLineKind.add) {
      continue;
    }
    descriptors[left!] = _HunkLineDescriptor(
      line: left,
      pairedLine: right!,
      oldSide: true,
    );
    descriptors[right] = _HunkLineDescriptor(
      line: right,
      pairedLine: left,
      oldSide: false,
    );
  }
  return [
    for (final line in lines)
      if (line.kind == DiffLineKind.add || line.kind == DiffLineKind.delete)
        descriptors[line] ?? _HunkLineDescriptor(line: line),
  ];
}

class _HunkLineDescriptor {
  const _HunkLineDescriptor({
    required this.line,
    this.pairedLine,
    this.oldSide = false,
  });

  final DiffLine line;
  final DiffLine? pairedLine;
  final bool oldSide;

  List<WordRange> wordRanges(FullDiffWordDiffer differ) {
    final paired = pairedLine;
    if (paired == null) return const [];
    final changes = oldSide
        ? differ(line.text, paired.text)
        : differ(paired.text, line.text);
    return oldSide ? changes.oldRanges : changes.newRanges;
  }
}
