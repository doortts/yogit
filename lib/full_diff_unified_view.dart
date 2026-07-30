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
    this.debugMetrics,
    this.showHunkHeaders = true,
    this.compactRows = false,
    this.currentMarkerColor = fullDiffAccent,
    this.header,
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
  final FullDiffLazyBuildMetrics? debugMetrics;
  final bool showHunkHeaders;
  final bool compactRows;
  final Color currentMarkerColor;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    if (document.hunks.isEmpty) {
      const empty = Center(
        child: Text(
          '현재 옵션으로 표시할 변경이 없습니다',
          style: TextStyle(color: fullDiffMuted, fontSize: 10),
        ),
      );
      if (header == null) return empty;
      return ListView(
        key: const Key('unified-list'),
        controller: controller,
        primary: controller == null,
        children: [
          header!,
          const SizedBox(height: 80, child: empty),
        ],
      );
    }

    final items = _UnifiedDocumentIndex(document);
    final headerOffset = header == null ? 0 : 1;
    final sourceTargetIndex = items.indexForTarget(scrollTarget);
    final scrollTargetIndex = sourceTargetIndex < 0
        ? -1
        : sourceTargetIndex + headerOffset;
    return FullDiffSelectionArea(
      allSourceTextBuilder: () {
        debugMetrics?.recordSelectionTextBuild();
        return items.buildSelectionText();
      },
      child: ListView.builder(
        key: const Key('unified-list'),
        controller: controller,
        primary: controller == null,
        itemCount: items.itemCount + headerOffset,
        itemBuilder: (context, itemIndex) {
          if (itemIndex < headerOffset) return header!;
          itemIndex -= headerOffset;
          final item = items.itemAt(itemIndex);
          debugMetrics?.recordItem(pair: item.pairedLine != null);
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
              compact: compactRows,
              currentMarkerColor: currentMarkerColor,
              selectionOrder: FullDiffSelectionOrder(row: item.sourceRow!),
            );
          } else {
            child = showHunkHeaders
                ? SelectionContainer.disabled(
                    child: FullDiffHunkHeader(
                      hunk: hunk,
                      path: path,
                      hunkCount: document.hunks.length,
                    ),
                  )
                : const SizedBox.shrink();
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

class _UnifiedDocumentIndex {
  _UnifiedDocumentIndex(DiffDocument document) {
    var itemStart = 0;
    var sourceRowStart = 0;
    for (final hunk in document.hunks) {
      var leadingContextCount = 0;
      while (leadingContextCount < hunk.lines.length) {
        final kind = hunk.lines[leadingContextCount].kind;
        if (kind == DiffLineKind.add || kind == DiffLineKind.delete) break;
        leadingContextCount++;
      }
      if (leadingContextCount == hunk.lines.length) {
        leadingContextCount = 0;
      }
      _hunks.add(
        _UnifiedHunkIndex(
          hunk: hunk,
          itemStart: itemStart,
          sourceRowStart: sourceRowStart,
          leadingContextCount: leadingContextCount,
        ),
      );
      itemStart += hunk.lines.length + 1;
      sourceRowStart += hunk.lines.length;
    }
    itemCount = itemStart;
  }

  final _hunks = <_UnifiedHunkIndex>[];
  late final int itemCount;

  _UnifiedItem itemAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', itemCount);
    final hunk = _hunkAt(index);
    final localIndex = index - hunk.itemStart;
    if (localIndex == hunk.leadingContextCount) {
      return _UnifiedItem(hunk: hunk.hunk, anchorTarget: true);
    }
    final lineIndex = localIndex < hunk.leadingContextCount
        ? localIndex
        : localIndex - 1;
    final descriptor = hunk.lineAt(lineIndex);
    return _UnifiedItem(
      hunk: hunk.hunk,
      line: descriptor.line,
      lineIndex: lineIndex,
      sourceRow: hunk.sourceRowStart + lineIndex,
      pairedLine: descriptor.pairedLine,
      oldSide: descriptor.oldSide,
    );
  }

  int indexForTarget(DiffSourceTarget? target) {
    if (target == null) return -1;
    int? added;
    int? deleted;
    int? resultContext;
    int? oldContext;
    for (final hunk in _hunks) {
      for (var lineIndex = 0; lineIndex < hunk.hunk.lines.length; lineIndex++) {
        final line = hunk.hunk.lines[lineIndex];
        final itemIndex =
            hunk.itemStart +
            lineIndex +
            (lineIndex >= hunk.leadingContextCount ? 1 : 0);
        if (target.newLine != null &&
            line.kind == DiffLineKind.add &&
            line.newNumber == target.newLine) {
          added ??= itemIndex;
        } else if (target.oldLine != null &&
            line.kind == DiffLineKind.delete &&
            line.oldNumber == target.oldLine) {
          deleted ??= itemIndex;
        } else {
          if (target.newLine != null && line.newNumber == target.newLine) {
            resultContext ??= itemIndex;
          }
          if (target.oldLine != null && line.oldNumber == target.oldLine) {
            oldContext ??= itemIndex;
          }
        }
      }
    }
    return added ?? deleted ?? resultContext ?? oldContext ?? -1;
  }

  String buildSelectionText() {
    final text = StringBuffer();
    var first = true;
    for (final hunk in _hunks) {
      for (final line in hunk.hunk.lines) {
        if (!first) text.write('\n');
        first = false;
        text.write(line.text);
      }
    }
    return text.toString();
  }

  _UnifiedHunkIndex _hunkAt(int itemIndex) {
    var low = 0;
    var high = _hunks.length;
    while (low + 1 < high) {
      final middle = low + ((high - low) >> 1);
      if (_hunks[middle].itemStart <= itemIndex) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return _hunks[low];
  }
}

class _UnifiedHunkIndex {
  _UnifiedHunkIndex({
    required this.hunk,
    required this.itemStart,
    required this.sourceRowStart,
    required this.leadingContextCount,
  });

  final DiffHunk hunk;
  final int itemStart;
  final int sourceRowStart;
  final int leadingContextCount;
  _UnifiedChangeRun? _lastChangeRun;

  _UnifiedLineDescriptor lineAt(int lineIndex) {
    final line = hunk.lines[lineIndex];
    if (line.kind != DiffLineKind.add && line.kind != DiffLineKind.delete) {
      return _UnifiedLineDescriptor(line: line);
    }
    final run = _changeRunAt(lineIndex);
    if (line.kind == DiffLineKind.delete) {
      final offset = lineIndex - run.deleteStart;
      return _UnifiedLineDescriptor(
        line: line,
        pairedLine: offset < run.addCount
            ? hunk.lines[run.addStart + offset]
            : null,
        oldSide: true,
      );
    }
    final offset = lineIndex - run.addStart;
    return _UnifiedLineDescriptor(
      line: line,
      pairedLine: offset < run.deleteCount
          ? hunk.lines[run.deleteStart + offset]
          : null,
    );
  }

  _UnifiedChangeRun _changeRunAt(int lineIndex) {
    final cached = _lastChangeRun;
    if (cached != null &&
        lineIndex >= cached.deleteStart &&
        lineIndex < cached.addStart + cached.addCount) {
      return cached;
    }
    var deleteStart = lineIndex;
    var addStart = lineIndex;
    if (hunk.lines[lineIndex].kind == DiffLineKind.delete) {
      while (deleteStart > 0 &&
          hunk.lines[deleteStart - 1].kind == DiffLineKind.delete) {
        deleteStart--;
      }
      addStart = lineIndex;
      while (addStart < hunk.lines.length &&
          hunk.lines[addStart].kind == DiffLineKind.delete) {
        addStart++;
      }
    } else {
      while (addStart > 0 &&
          hunk.lines[addStart - 1].kind == DiffLineKind.add) {
        addStart--;
      }
      deleteStart = addStart;
      while (deleteStart > 0 &&
          hunk.lines[deleteStart - 1].kind == DiffLineKind.delete) {
        deleteStart--;
      }
    }
    var addEnd = addStart;
    while (addEnd < hunk.lines.length &&
        hunk.lines[addEnd].kind == DiffLineKind.add) {
      addEnd++;
    }
    return _lastChangeRun = _UnifiedChangeRun(
      deleteStart: deleteStart,
      deleteCount: addStart - deleteStart,
      addStart: addStart,
      addCount: addEnd - addStart,
    );
  }
}

class _UnifiedChangeRun {
  const _UnifiedChangeRun({
    required this.deleteStart,
    required this.deleteCount,
    required this.addStart,
    required this.addCount,
  });

  final int deleteStart;
  final int deleteCount;
  final int addStart;
  final int addCount;
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
