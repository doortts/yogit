import 'full_diff_model.dart';
import 'git.dart';

DiffAnchor? nearestHunkAnchorForSourceLine({
  required List<DiffHunk> hunks,
  required FileDocumentSide side,
  required int lineNumber,
}) {
  if (hunks.isEmpty) return null;
  int coordinate(DiffHunk hunk) => switch (side) {
    FileDocumentSide.old => hunk.anchor.oldLine ?? hunk.oldStart,
    FileDocumentSide.result => hunk.anchor.newLine ?? hunk.newStart,
  };

  var nearest = hunks.first;
  var distance = (coordinate(nearest) - lineNumber).abs();
  for (final hunk in hunks.skip(1)) {
    final candidateDistance = (coordinate(hunk) - lineNumber).abs();
    if (candidateDistance < distance) {
      nearest = hunk;
      distance = candidateDistance;
    }
  }
  return nearest.anchor;
}

sealed class FullSourceHunkItem {
  const FullSourceHunkItem();
}

class FullSourceHunkHeaderItem extends FullSourceHunkItem {
  const FullSourceHunkHeaderItem(this.hunk);

  final DiffHunk hunk;
}

class FullSourceLineItem extends FullSourceHunkItem {
  const FullSourceLineItem({required this.lineNumber, required this.kind});

  final int lineNumber;
  final DiffLineKind kind;
}

/// Lazily combines source lines with one header per patch Hunk.
///
/// Only side-appropriate changes are projected onto the source: additions for
/// a result document and deletions for an old document. A Hunk that has no
/// source row on the selected side still gets a header at its clamped start,
/// including the valid `lineCount + 1` EOF position.
class FullSourceHunkMap {
  FullSourceHunkMap({
    required List<DiffHunk> hunks,
    required FileDocumentSide side,
    required this.lineCount,
    required DiffAnchor? activeAnchor,
  }) : _side = side,
       _lineKinds = <int, DiffLineKind>{},
       _activeLines = <int, int?>{} {
    final activeHunks = [
      for (final hunk in hunks)
        if (hunk.index == activeAnchor?.hunkIndex) hunk,
    ];
    _headers = _buildHeaders(activeHunks, side, lineCount);
    if (lineCount == 0) return;
    for (final hunk in activeHunks) {
      final sideLines = _sideLines(hunk, side, lineCount);
      _activeLines[hunk.index] = sideLines.isEmpty
          ? switch (side) {
              FileDocumentSide.old => hunk.oldStart,
              FileDocumentSide.result => hunk.newStart,
            }.clamp(1, lineCount)
          : sideLines.first.number;
      for (final line in sideLines) {
        _lineKinds[line.number] = line.kind;
      }
    }
  }

  final int lineCount;
  final FileDocumentSide _side;
  late final List<_HeaderPlacement> _headers;
  final Map<int, DiffLineKind> _lineKinds;
  final Map<int, int?> _activeLines;

  int get itemCount => lineCount + _headers.length;

  FullSourceHunkItem itemAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', itemCount);
    final headerIndex = _lowerBoundHeader(index);
    if (headerIndex < _headers.length &&
        _headers[headerIndex].displayIndex == index) {
      return FullSourceHunkHeaderItem(_headers[headerIndex].hunk);
    }
    final lineNumber = index - headerIndex + 1;
    return FullSourceLineItem(
      lineNumber: lineNumber,
      kind: _lineKinds[lineNumber] ?? DiffLineKind.context,
    );
  }

  DiffLineKind kindForLine(int lineNumber) {
    RangeError.checkValueInInterval(lineNumber, 1, lineCount, 'lineNumber');
    return _lineKinds[lineNumber] ?? DiffLineKind.context;
  }

  int? activeLine(DiffAnchor? anchor) {
    if (anchor == null || lineCount == 0) return null;
    final direct = switch (_side) {
      FileDocumentSide.old => anchor.oldLine,
      FileDocumentSide.result => anchor.newLine,
    };
    if (direct != null && direct >= 1 && direct <= lineCount) return direct;
    return _activeLines[anchor.hunkIndex];
  }

  int _lowerBoundHeader(int displayIndex) {
    var low = 0;
    var high = _headers.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_headers[middle].displayIndex < displayIndex) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static List<_HeaderPlacement> _buildHeaders(
    List<DiffHunk> hunks,
    FileDocumentSide side,
    int lineCount,
  ) {
    final pending =
        <({DiffHunk hunk, int beforeLine})>[
          for (final hunk in hunks)
            (hunk: hunk, beforeLine: _headerLine(hunk, side, lineCount)),
        ]..sort((left, right) {
          final lineOrder = left.beforeLine.compareTo(right.beforeLine);
          return lineOrder != 0
              ? lineOrder
              : left.hunk.index.compareTo(right.hunk.index);
        });
    return [
      for (final (ordinal, placement) in pending.indexed)
        _HeaderPlacement(
          displayIndex: placement.beforeLine - 1 + ordinal,
          hunk: placement.hunk,
        ),
    ];
  }

  static int _headerLine(DiffHunk hunk, FileDocumentSide side, int lineCount) {
    final sideLines = _sideLines(hunk, side, lineCount);
    if (sideLines.isNotEmpty) return sideLines.first.number;
    return switch (side) {
      FileDocumentSide.old => hunk.oldStart,
      FileDocumentSide.result => hunk.newStart,
    }.clamp(1, lineCount + 1);
  }

  static List<({int number, DiffLineKind kind})> _sideLines(
    DiffHunk hunk,
    FileDocumentSide side,
    int lineCount,
  ) => [
    for (final line in hunk.lines)
      if (switch (side) {
        FileDocumentSide.result =>
          line.kind == DiffLineKind.add &&
              line.newNumber != null &&
              line.newNumber! >= 1 &&
              line.newNumber! <= lineCount,
        FileDocumentSide.old =>
          line.kind == DiffLineKind.delete &&
              line.oldNumber != null &&
              line.oldNumber! >= 1 &&
              line.oldNumber! <= lineCount,
      })
        (
          number: switch (side) {
            FileDocumentSide.result => line.newNumber!,
            FileDocumentSide.old => line.oldNumber!,
          },
          kind: switch (side) {
            FileDocumentSide.result => DiffLineKind.add,
            FileDocumentSide.old => DiffLineKind.delete,
          },
        ),
  ];
}

class _HeaderPlacement {
  const _HeaderPlacement({required this.displayIndex, required this.hunk});

  final int displayIndex;
  final DiffHunk hunk;
}
