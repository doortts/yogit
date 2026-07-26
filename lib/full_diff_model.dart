import 'package:flutter/foundation.dart';
import 'package:yogit/git.dart';

final _hunkHeader = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: ?(.*))?$',
);

@immutable
class DiffAnchor {
  const DiffAnchor({
    required this.hunkIndex,
    required this.oldLine,
    required this.newLine,
  });

  final int hunkIndex;
  final int? oldLine;
  final int? newLine;

  String get id => 'hunk-$hunkIndex-${oldLine ?? 0}-${newLine ?? 0}';
}

@immutable
class DiffHunk {
  const DiffHunk({
    required this.index,
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.context,
    required this.lines,
    required this.anchor,
  });

  final int index;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String context;
  final List<DiffLine> lines;
  final DiffAnchor anchor;

  String get rangeLabel {
    String range(int start, int count) =>
        count == 1 ? '$start' : '$start,$count';
    return '−${range(oldStart, oldCount)}  +${range(newStart, newCount)}';
  }
}

@immutable
class DiffDocument {
  const DiffDocument({
    required this.headers,
    required this.hunks,
    required this.rows,
  });

  static const empty = DiffDocument(
    headers: <String>[],
    hunks: <DiffHunk>[],
    rows: <DiffLine>[],
  );

  final List<String> headers;
  final List<DiffHunk> hunks;
  final List<DiffLine> rows;

  factory DiffDocument.fromLines(List<DiffLine> lines) {
    final headers = <String>[];
    final hunks = <DiffHunk>[];
    final rows = <DiffLine>[];
    RegExpMatch? currentHeader;
    List<DiffLine>? currentLines;

    void finishHunk() {
      final header = currentHeader;
      final sourceLines = currentLines;
      if (header == null || sourceLines == null) return;

      int? oldAnchor;
      int? newAnchor;
      for (final line in sourceLines) {
        if (line.kind != DiffLineKind.add && line.kind != DiffLineKind.delete) {
          continue;
        }
        oldAnchor ??= line.oldNumber;
        newAnchor ??= line.newNumber;
      }

      final index = hunks.length;
      final immutableLines = List<DiffLine>.unmodifiable(sourceLines);
      hunks.add(
        DiffHunk(
          index: index,
          oldStart: int.parse(header.group(1)!),
          oldCount: int.parse(header.group(2) ?? '1'),
          newStart: int.parse(header.group(3)!),
          newCount: int.parse(header.group(4) ?? '1'),
          context: header.group(5) ?? '',
          lines: immutableLines,
          anchor: DiffAnchor(
            hunkIndex: index,
            oldLine: oldAnchor,
            newLine: newAnchor,
          ),
        ),
      );
      rows.addAll(immutableLines);
    }

    for (final line in lines) {
      if (line.kind == DiffLineKind.header) {
        headers.add(line.text);
        continue;
      }
      if (line.kind == DiffLineKind.hunk) {
        finishHunk();
        currentHeader = _hunkHeader.firstMatch(line.text);
        if (currentHeader == null) {
          throw FormatException('Invalid hunk header: ${line.text}');
        }
        currentLines = <DiffLine>[];
        continue;
      }
      currentLines?.add(line);
    }
    finishHunk();

    return DiffDocument(
      headers: List<String>.unmodifiable(headers),
      hunks: List<DiffHunk>.unmodifiable(hunks),
      rows: List<DiffLine>.unmodifiable(rows),
    );
  }
}
