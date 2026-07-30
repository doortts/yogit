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
    this.debugMetrics,
    this.splitRatio = 0.5,
    this.onSplitRatioChanged,
    this.onSplitRatioChangeEnd,
    this.showHunkHeaders = true,
    this.compactRows = false,
    this.currentMarkerColor = fullDiffAccent,
    this.header,
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
  final FullDiffLazyBuildMetrics? debugMetrics;
  final double splitRatio;
  final ValueChanged<double>? onSplitRatioChanged;
  final VoidCallback? onSplitRatioChangeEnd;
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
        key: const Key('side-by-side-list'),
        controller: controller,
        primary: controller == null,
        children: [
          header!,
          const SizedBox(height: 80, child: empty),
        ],
      );
    }

    return _SideBySideDocumentIndexCache(
      document: document,
      builder: _buildIndexed,
    );
  }

  Widget _buildIndexed(BuildContext context, _SideBySideDocumentIndex items) {
    final headerOffset = header == null ? 0 : 1;
    final sourceTargetIndex = items.indexForTarget(scrollTarget);
    final scrollTargetIndex = sourceTargetIndex < 0
        ? -1
        : sourceTargetIndex + headerOffset;
    final list = FullDiffSelectionArea(
      allSourceTextBuilder: () {
        debugMetrics?.recordSelectionTextBuild();
        return items.buildSelectionText(showOldSide: showOldSide);
      },
      child: ListView.builder(
        key: const Key('side-by-side-list'),
        controller: controller,
        primary: controller == null,
        itemCount: items.itemCount + headerOffset,
        itemBuilder: (context, itemIndex) {
          if (itemIndex < headerOffset) return header!;
          itemIndex -= headerOffset;
          final item = items.itemAt(itemIndex);
          debugMetrics?.recordItem(pair: item.pair != null);
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
              splitRatio: splitRatio.clamp(0.2, 0.8).toDouble(),
              compactRows: compactRows,
              currentMarkerColor: currentMarkerColor,
            );
          } else {
            child = showHunkHeaders
                ? SelectionContainer.disabled(
                    child: FullDiffHunkHeader(
                      hunk: hunk,
                      path: newPath,
                      hunkCount: document.hunks.length,
                    ),
                  )
                : const SizedBox.shrink();
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
    if (!showOldSide) return list;
    final ratio = splitRatio.clamp(0.2, 0.8).toDouble();
    return KeyedSubtree(
      key: const Key('side-by-side-old-pane'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final splitX = constraints.maxWidth * ratio;
          var dragRatio = ratio;
          return Stack(
            children: [
              Positioned.fill(child: list),
              Positioned(
                key: const Key('side-by-side-divider'),
                left: splitX,
                top: 0,
                bottom: 0,
                width: 1,
                child: const ColoredBox(color: fullDiffDivider),
              ),
              Positioned(
                left: splitX - 4,
                top: 0,
                bottom: 0,
                width: 8,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    key: const Key('side-by-side-resizer'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) {
                      dragRatio =
                          (dragRatio + details.delta.dx / constraints.maxWidth)
                              .clamp(0.2, 0.8)
                              .toDouble();
                      onSplitRatioChanged?.call(dragRatio);
                    },
                    onHorizontalDragEnd: (_) => onSplitRatioChangeEnd?.call(),
                    onHorizontalDragCancel: onSplitRatioChangeEnd,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  GlobalKey _anchorKey(DiffAnchor anchor) =>
      anchorKeys[anchor.id] ??
      (throw StateError('Missing GlobalKey for ${anchor.id}'));
}

class _SideBySideDocumentIndexCache extends StatefulWidget {
  const _SideBySideDocumentIndexCache({
    required this.document,
    required this.builder,
  });

  final DiffDocument document;
  final Widget Function(BuildContext, _SideBySideDocumentIndex) builder;

  @override
  State<_SideBySideDocumentIndexCache> createState() =>
      _SideBySideDocumentIndexCacheState();
}

class _SideBySideDocumentIndexCacheState
    extends State<_SideBySideDocumentIndexCache> {
  late _SideBySideDocumentIndex _index;

  @override
  void initState() {
    super.initState();
    _index = _SideBySideDocumentIndex(widget.document);
  }

  @override
  void didUpdateWidget(covariant _SideBySideDocumentIndexCache oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.document, oldWidget.document)) {
      _index = _SideBySideDocumentIndex(widget.document);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _index);
}

class _SideBySideDocumentIndex {
  _SideBySideDocumentIndex(DiffDocument document) {
    var itemStart = 0;
    var sourceRowStart = 0;
    for (final hunk in document.hunks) {
      final pairs = _LazyDiffPairs(hunk.lines);
      _hunks.add(
        _SideBySideHunkIndex(
          hunk: hunk,
          pairs: pairs,
          itemStart: itemStart,
          sourceRowStart: sourceRowStart,
        ),
      );
      itemStart += pairs.pairCount + 1;
      sourceRowStart += pairs.pairCount;
    }
    itemCount = itemStart;
  }

  final _hunks = <_SideBySideHunkIndex>[];
  late final int itemCount;

  _SideBySideItem itemAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', itemCount);
    final hunk = _hunkAt(index);
    final localIndex = index - hunk.itemStart;
    if (localIndex == hunk.pairs.leadingContextCount) {
      return _SideBySideItem(hunk: hunk.hunk, anchorTarget: true);
    }
    final pairIndex = localIndex < hunk.pairs.leadingContextCount
        ? localIndex
        : localIndex - 1;
    return _SideBySideItem(
      hunk: hunk.hunk,
      pair: hunk.pairs.pairAt(pairIndex),
      pairIndex: pairIndex,
      sourceRow: hunk.sourceRowStart + pairIndex,
    );
  }

  int indexForTarget(DiffSourceTarget? target) {
    if (target == null) return -1;
    for (final hunk in _hunks) {
      final pairIndex = hunk.pairs.indexForTarget(target);
      if (pairIndex < 0) continue;
      return hunk.itemStart +
          pairIndex +
          (pairIndex >= hunk.pairs.leadingContextCount ? 1 : 0);
    }
    return -1;
  }

  String buildSelectionText({required bool showOldSide}) {
    final text = StringBuffer();
    var first = true;
    for (final hunk in _hunks) {
      for (var pairIndex = 0; pairIndex < hunk.pairs.pairCount; pairIndex++) {
        if (!first) text.write('\n');
        first = false;
        text.write(_pairSourceText(hunk.pairs.pairAt(pairIndex), showOldSide));
      }
    }
    return text.toString();
  }

  _SideBySideHunkIndex _hunkAt(int itemIndex) {
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

class _SideBySideHunkIndex {
  const _SideBySideHunkIndex({
    required this.hunk,
    required this.pairs,
    required this.itemStart,
    required this.sourceRowStart,
  });

  final DiffHunk hunk;
  final _LazyDiffPairs pairs;
  final int itemStart;
  final int sourceRowStart;
}

class _LazyDiffPairs {
  _LazyDiffPairs(this.lines) {
    var lineIndex = 0;
    var pairs = 0;
    int? firstChange;
    while (lineIndex < lines.length) {
      if (lines[lineIndex].kind == DiffLineKind.delete) {
        firstChange ??= pairs;
        var deleteEnd = lineIndex;
        while (deleteEnd < lines.length &&
            lines[deleteEnd].kind == DiffLineKind.delete) {
          deleteEnd++;
        }
        var addEnd = deleteEnd;
        while (addEnd < lines.length &&
            lines[addEnd].kind == DiffLineKind.add) {
          addEnd++;
        }
        pairs += _max(deleteEnd - lineIndex, addEnd - deleteEnd);
        lineIndex = addEnd;
        continue;
      }
      if (lines[lineIndex].kind == DiffLineKind.add) firstChange ??= pairs;
      pairs++;
      lineIndex++;
    }
    pairCount = pairs;
    leadingContextCount = firstChange ?? 0;
    _checkpoints.add(
      const _PairCheckpoint(pairIndex: 0, state: _PairCursorState()),
    );
  }

  static const _checkpointInterval = 256;

  final List<DiffLine> lines;
  late final int pairCount;
  late final int leadingContextCount;
  final _checkpoints = <_PairCheckpoint>[];
  var _nextPairIndex = 0;
  var _lineIndex = 0;
  _PairChange? _change;
  var _changeOffset = 0;
  var _lastPairIndex = -1;
  DiffPair? _lastPair;

  DiffPair pairAt(int pairIndex) {
    RangeError.checkValidIndex(pairIndex, this, 'pairIndex', pairCount);
    if (pairIndex == _lastPairIndex) return _lastPair!;
    if (pairIndex < _nextPairIndex) _restoreFor(pairIndex);

    late DiffPair result;
    while (_nextPairIndex <= pairIndex) {
      if (_nextPairIndex % _checkpointInterval == 0 &&
          _checkpoints.last.pairIndex < _nextPairIndex) {
        _checkpoints.add(
          _PairCheckpoint(
            pairIndex: _nextPairIndex,
            state: _PairCursorState(
              lineIndex: _lineIndex,
              change: _change,
              changeOffset: _changeOffset,
            ),
          ),
        );
      }
      result = _takeNext();
      _lastPairIndex = _nextPairIndex++;
      _lastPair = result;
    }
    return result;
  }

  int indexForTarget(DiffSourceTarget target) {
    int? added;
    int? deleted;
    int? resultContext;
    int? oldContext;
    var lineIndex = 0;
    var pairIndex = 0;
    while (lineIndex < lines.length) {
      if (lines[lineIndex].kind == DiffLineKind.delete) {
        final deleteStart = lineIndex;
        while (lineIndex < lines.length &&
            lines[lineIndex].kind == DiffLineKind.delete) {
          lineIndex++;
        }
        final addStart = lineIndex;
        while (lineIndex < lines.length &&
            lines[lineIndex].kind == DiffLineKind.add) {
          lineIndex++;
        }
        final deleteCount = addStart - deleteStart;
        final addCount = lineIndex - addStart;
        for (var offset = 0; offset < deleteCount; offset++) {
          if (target.oldLine != null &&
              lines[deleteStart + offset].oldNumber == target.oldLine) {
            deleted ??= pairIndex + offset;
          }
        }
        for (var offset = 0; offset < addCount; offset++) {
          if (target.newLine != null &&
              lines[addStart + offset].newNumber == target.newLine) {
            added ??= pairIndex + offset;
          }
        }
        pairIndex += _max(deleteCount, addCount);
        continue;
      }
      final line = lines[lineIndex++];
      if (line.kind == DiffLineKind.add) {
        if (target.newLine != null && line.newNumber == target.newLine) {
          added ??= pairIndex;
        }
      } else {
        if (target.newLine != null && line.newNumber == target.newLine) {
          resultContext ??= pairIndex;
        }
        if (target.oldLine != null && line.oldNumber == target.oldLine) {
          oldContext ??= pairIndex;
        }
      }
      pairIndex++;
    }
    return added ?? deleted ?? resultContext ?? oldContext ?? -1;
  }

  DiffPair _takeNext() {
    while (true) {
      if (_change case final change?) {
        final offset = _changeOffset++;
        final pair = DiffPair(
          left: offset < change.deleteCount
              ? lines[change.deleteStart + offset]
              : null,
          right: offset < change.addCount
              ? lines[change.addStart + offset]
              : null,
        );
        if (_changeOffset == _max(change.deleteCount, change.addCount)) {
          _lineIndex = change.addStart + change.addCount;
          _change = null;
          _changeOffset = 0;
        }
        return pair;
      }

      final line = lines[_lineIndex];
      if (line.kind == DiffLineKind.delete) {
        final deleteStart = _lineIndex;
        var addStart = deleteStart;
        while (addStart < lines.length &&
            lines[addStart].kind == DiffLineKind.delete) {
          addStart++;
        }
        var addEnd = addStart;
        while (addEnd < lines.length &&
            lines[addEnd].kind == DiffLineKind.add) {
          addEnd++;
        }
        _change = _PairChange(
          deleteStart: deleteStart,
          deleteCount: addStart - deleteStart,
          addStart: addStart,
          addCount: addEnd - addStart,
        );
        continue;
      }
      _lineIndex++;
      return line.kind == DiffLineKind.add
          ? DiffPair(right: line)
          : DiffPair(left: line, right: line);
    }
  }

  void _restoreFor(int pairIndex) {
    var low = 0;
    var high = _checkpoints.length;
    while (low + 1 < high) {
      final middle = low + ((high - low) >> 1);
      if (_checkpoints[middle].pairIndex <= pairIndex) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final checkpoint = _checkpoints[low];
    _nextPairIndex = checkpoint.pairIndex;
    _lineIndex = checkpoint.state.lineIndex;
    _change = checkpoint.state.change;
    _changeOffset = checkpoint.state.changeOffset;
    _lastPairIndex = -1;
    _lastPair = null;
  }
}

class _PairChange {
  const _PairChange({
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

class _PairCursorState {
  const _PairCursorState({
    this.lineIndex = 0,
    this.change,
    this.changeOffset = 0,
  });

  final int lineIndex;
  final _PairChange? change;
  final int changeOffset;
}

class _PairCheckpoint {
  const _PairCheckpoint({required this.pairIndex, required this.state});

  final int pairIndex;
  final _PairCursorState state;
}

int _max(int left, int right) => left > right ? left : right;

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
    required this.splitRatio,
    required this.compactRows,
    required this.currentMarkerColor,
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
  final double splitRatio;
  final bool compactRows;
  final Color currentMarkerColor;

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
            compact: compactRows,
            currentMarkerColor: currentMarkerColor,
            selectionOrder: FullDiffSelectionOrder(
              row: sourceRow,
              column: showOldSide ? 1 : 0,
            ),
          );

    if (!showOldSide) return newSide;

    final oldSide = left == null
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
            compact: compactRows,
            currentMarkerColor: currentMarkerColor,
            selectionOrder: FullDiffSelectionOrder(row: sourceRow),
          );
    if (wrapLines) {
      const ratioPrecision = 1000000;
      final oldFlex = (splitRatio * ratioPrecision).round();
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: oldFlex, child: oldSide),
            Expanded(flex: ratioPrecision - oldFlex, child: newSide),
          ],
        ),
      );
    }
    return SizedBox(
      height: compactRows ? fullDiffSourceRowHeight : 27,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: constraints.maxWidth * splitRatio, child: oldSide),
            Expanded(child: newSide),
          ],
        ),
      ),
    );
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
