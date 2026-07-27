import 'package:flutter/material.dart';

import 'full_diff_anchor_probe.dart';
import 'full_diff_code_row.dart';
import 'full_diff_hunk_header.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';

class UnifiedPresentationView extends StatelessWidget {
  const UnifiedPresentationView({
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
    this.scrollTarget,
    this.scrollTargetKey,
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

    final items = _unifiedItems(document);
    final scrollTargetIndex = _unifiedScrollTargetIndex(items, scrollTarget);
    final allSourceText = [
      for (final item in items)
        if (item.line case final line?) line.text,
    ].join('\n');
    return FullDiffSelectionArea(
      allSourceText: allSourceText,
      child: ListView.builder(
        key: const Key('unified-list'),
        controller: controller,
        primary: controller == null,
        itemCount: items.length,
        itemBuilder: (context, itemIndex) {
          final item = items[itemIndex];
          final hunk = item.hunk;
          final current = activeAnchor?.hunkIndex == hunk.index;
          Widget child;
          if (item.line case final line?) {
            final wordRanges = richRenderingEnabled
                ? item.wordRanges(wordDiffer)
                : const <WordRange>[];
            child = FullDiffCodeRow(
              key: Key('unified-line-${hunk.index}-${item.lineIndex}'),
              line: line,
              path: path,
              wrapLines: wrapLines,
              highlighter: highlighter,
              current:
                  current &&
                  (line.kind == DiffLineKind.add ||
                      line.kind == DiffLineKind.delete),
              wordRanges: wordRanges,
              compactGutter: true,
              richRenderingEnabled: richRenderingEnabled,
              selectionOrder: FullDiffSelectionOrder(row: item.sourceRow!),
            );
          } else {
            child = SelectionContainer.disabled(
              child: FullDiffHunkHeader(
                hunk: hunk,
                path: path,
                hunkCount: document.hunks.length,
              ),
            );
          }
          if (item.anchorTarget) {
            child = KeyedSubtree(
              key: _anchorKey(hunk.anchor),
              child: KeyedSubtree(
                key: Key('unified-hunk-${hunk.index}'),
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
  }

  GlobalKey _anchorKey(DiffAnchor anchor) =>
      anchorKeys[anchor.id] ??
      (throw StateError('Missing GlobalKey for ${anchor.id}'));
}

int _unifiedScrollTargetIndex(
  List<_UnifiedItem> items,
  DiffSourceTarget? target,
) {
  if (target == null) return -1;
  final oldLine = target.oldLine;
  if (oldLine != null) {
    final deleted = items.indexWhere(
      (item) =>
          item.line?.kind == DiffLineKind.delete &&
          item.line?.oldNumber == oldLine,
    );
    if (deleted >= 0) return deleted;
  }
  final newLine = target.newLine;
  if (newLine != null) {
    final added = items.indexWhere(
      (item) =>
          item.line?.kind == DiffLineKind.add &&
          item.line?.newNumber == newLine,
    );
    if (added >= 0) return added;
  }
  return items.indexWhere(
    (item) =>
        (newLine != null && item.line?.newNumber == newLine) ||
        (oldLine != null && item.line?.oldNumber == oldLine),
  );
}

List<_UnifiedItem> _unifiedItems(DiffDocument document) {
  final items = <_UnifiedItem>[];
  var sourceRow = 0;
  for (final hunk in document.hunks) {
    final lineDescriptors = _unifiedLines(hunk.lines);
    final firstChange = hunk.lines.indexWhere(
      (line) =>
          line.kind == DiffLineKind.add || line.kind == DiffLineKind.delete,
    );
    final leadingContextCount = firstChange < 0 ? 0 : firstChange;
    void addLine(int lineIndex) {
      final descriptor = lineDescriptors[lineIndex];
      items.add(
        _UnifiedItem(
          hunk: hunk,
          line: descriptor.line,
          lineIndex: lineIndex,
          sourceRow: sourceRow++,
          pairedLine: descriptor.pairedLine,
          oldSide: descriptor.oldSide,
        ),
      );
    }

    for (var index = 0; index < leadingContextCount; index++) {
      addLine(index);
    }
    items.add(_UnifiedItem(hunk: hunk, anchorTarget: true));
    for (var index = leadingContextCount; index < hunk.lines.length; index++) {
      addLine(index);
    }
  }
  return items;
}

List<_UnifiedLineDescriptor> _unifiedLines(List<DiffLine> lines) {
  final descriptors = <DiffLine, _UnifiedLineDescriptor>{};
  for (final pair in pairDiff(lines)) {
    final left = pair.left;
    final right = pair.right;
    if (left?.kind != DiffLineKind.delete || right?.kind != DiffLineKind.add) {
      continue;
    }
    descriptors[left!] = _UnifiedLineDescriptor(
      line: left,
      pairedLine: right!,
      oldSide: true,
    );
    descriptors[right] = _UnifiedLineDescriptor(
      line: right,
      pairedLine: left,
      oldSide: false,
    );
  }
  return [
    for (final line in lines)
      descriptors[line] ?? _UnifiedLineDescriptor(line: line),
  ];
}

class _UnifiedLineDescriptor {
  const _UnifiedLineDescriptor({
    required this.line,
    this.pairedLine,
    this.oldSide = false,
  });

  final DiffLine line;
  final DiffLine? pairedLine;
  final bool oldSide;
}

class _UnifiedItem {
  const _UnifiedItem({
    required this.hunk,
    this.line,
    this.lineIndex,
    this.sourceRow,
    this.pairedLine,
    this.oldSide = false,
    this.anchorTarget = false,
  });

  final DiffHunk hunk;
  final DiffLine? line;
  final int? lineIndex;
  final int? sourceRow;
  final DiffLine? pairedLine;
  final bool oldSide;
  final bool anchorTarget;

  List<WordRange> wordRanges(FullDiffWordDiffer differ) {
    final current = line;
    final paired = pairedLine;
    if (current == null || paired == null) return const [];
    final changes = oldSide
        ? differ(current.text, paired.text)
        : differ(paired.text, current.text);
    return oldSide ? changes.oldRanges : changes.newRanges;
  }
}
