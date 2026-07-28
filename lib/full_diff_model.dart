import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:yogit/full_diff_limits.dart';
import 'package:yogit/git.dart';

export 'package:yogit/full_diff_limits.dart';

enum FullDiffView { diff, blame, history }

enum DiffLayout { unified, sideBySide }

typedef DiffSourceTarget = ({int? oldLine, int? newLine});

@immutable
class DiffSourceTargetIdentity {
  const DiffSourceTargetIdentity({
    required this.document,
    required this.target,
  });

  final DiffDocument document;
  final DiffSourceTarget target;

  bool matches({
    required DiffDocument? document,
    required DiffSourceTarget? target,
  }) => identical(this.document, document) && this.target == target;
}

int diffSourceTargetIndex<T>({
  required List<T> rows,
  required DiffSourceTarget? target,
  required DiffLine? Function(T row) oldLineOf,
  required DiffLine? Function(T row) newLineOf,
}) {
  if (target == null) return -1;
  final newNumber = target.newLine;
  if (newNumber != null) {
    final added = rows.indexWhere((row) {
      final line = newLineOf(row);
      return line?.kind == DiffLineKind.add && line?.newNumber == newNumber;
    });
    if (added >= 0) return added;
  }
  final oldNumber = target.oldLine;
  if (oldNumber != null) {
    final deleted = rows.indexWhere((row) {
      final line = oldLineOf(row);
      return line?.kind == DiffLineKind.delete && line?.oldNumber == oldNumber;
    });
    if (deleted >= 0) return deleted;
  }
  if (newNumber != null) {
    final resultContext = rows.indexWhere(
      (row) => newLineOf(row)?.newNumber == newNumber,
    );
    if (resultContext >= 0) return resultContext;
  }
  if (oldNumber != null) {
    return rows.indexWhere((row) => oldLineOf(row)?.oldNumber == oldNumber);
  }
  return -1;
}

bool diffDocumentContainsSourceTarget(
  DiffDocument document,
  DiffSourceTarget? target,
) =>
    diffSourceTargetIndex(
      rows: document.rows,
      target: target,
      oldLineOf: (line) => line.kind == DiffLineKind.add ? null : line,
      newLineOf: (line) => line.kind == DiffLineKind.delete ? null : line,
    ) >=
    0;

@immutable
class FullDiffPreferences {
  const FullDiffPreferences({
    this.view = FullDiffView.diff,
    bool? historySelected,
    this.layout = DiffLayout.unified,
    this.scope = DiffScope.hunks,
    this.algorithm = DiffAlgorithm.gitSetting,
    this.ignoreWhitespace = false,
    this.wrapLines = true,
  }) : historySelected = historySelected ?? view == FullDiffView.history;

  final FullDiffView view;
  final bool historySelected;
  final DiffLayout layout;
  final DiffScope scope;
  final DiffAlgorithm algorithm;
  final bool ignoreWhitespace;
  final bool wrapLines;

  FullDiffPreferences copyWith({
    FullDiffView? view,
    bool? historySelected,
    DiffLayout? layout,
    DiffScope? scope,
    DiffAlgorithm? algorithm,
    bool? ignoreWhitespace,
    bool? wrapLines,
  }) => FullDiffPreferences(
    view: view ?? this.view,
    historySelected: historySelected ?? this.historySelected,
    layout: layout ?? this.layout,
    scope: scope ?? this.scope,
    algorithm: algorithm ?? this.algorithm,
    ignoreWhitespace: ignoreWhitespace ?? this.ignoreWhitespace,
    wrapLines: wrapLines ?? this.wrapLines,
  );

  factory FullDiffPreferences.fromJson(Object? value) {
    final json = value is Map<String, dynamic>
        ? value
        : const <String, dynamic>{};
    final view = switch (json['view']) {
      'blame' => FullDiffView.blame,
      'history' => FullDiffView.history,
      _ => FullDiffView.diff,
    };
    final historySelected =
        view == FullDiffView.history ||
        (json['historySelected'] is bool
            ? json['historySelected'] as bool
            : false);
    return FullDiffPreferences(
      view: view,
      historySelected: historySelected,
      layout: json['layout'] == 'sideBySide'
          ? DiffLayout.sideBySide
          : DiffLayout.unified,
      scope: json['scope'] == 'fullFile' ? DiffScope.fullFile : DiffScope.hunks,
      algorithm: DiffAlgorithm.values.firstWhere(
        (value) => value.name == json['algorithm'],
        orElse: () => DiffAlgorithm.gitSetting,
      ),
      ignoreWhitespace: json['ignoreWhitespace'] is bool
          ? json['ignoreWhitespace'] as bool
          : false,
      wrapLines: json['wrapLines'] is bool ? json['wrapLines'] as bool : true,
    );
  }

  Map<String, Object> toJson() => {
    'view': view.name,
    'historySelected': historySelected,
    'layout': layout.name,
    'scope': scope.name,
    'algorithm': algorithm.name,
    'ignoreWhitespace': ignoreWhitespace,
    'wrapLines': wrapLines,
  };

  @override
  bool operator ==(Object other) =>
      other is FullDiffPreferences &&
      view == other.view &&
      historySelected == other.historySelected &&
      layout == other.layout &&
      scope == other.scope &&
      algorithm == other.algorithm &&
      ignoreWhitespace == other.ignoreWhitespace &&
      wrapLines == other.wrapLines;

  @override
  int get hashCode => Object.hash(
    view,
    historySelected,
    layout,
    scope,
    algorithm,
    ignoreWhitespace,
    wrapLines,
  );
}

enum FileContentKind { utf8, binary, unsupportedEncoding, tooLarge }

enum FileContentLimitReason { byteLimit, lineLimit }

enum FileDocumentSide { old, result }

const fullDiffLargeByteLimit = 2 * 1024 * 1024;
const fullDiffLargeLineLimit = 50000;

bool _exceedsFullDiffTextLineLimit(Uint8List bytes) {
  var lineCount = 0;
  for (final byte in bytes) {
    if (byte == 0x0A && ++lineCount > fullDiffTextLineLimit) return true;
  }
  return lineCount == fullDiffTextLineLimit &&
      bytes.isNotEmpty &&
      bytes.last != 0x0A;
}

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

extension DiffHunkRows on DiffHunk {
  List<DiffLine> get changedLines => List.unmodifiable(
    lines.where(
      (line) =>
          line.kind == DiffLineKind.add || line.kind == DiffLineKind.delete,
    ),
  );

  String get displayRange {
    final useOld = newCount == 0;
    final start = useOld ? oldStart : newStart;
    final count = useOld ? oldCount : newCount;
    final end = count <= 1 ? start : start + count - 1;
    return start == end ? '$start' : '$start–$end';
  }
}

extension DiffDocumentDerived on DiffDocument {
  List<DiffPair> get splitRows =>
      List.unmodifiable(hunks.expand((hunk) => pairDiff(hunk.lines)));

  int get sourceLineCount {
    final newNumbers = rows.map((line) => line.newNumber).whereType<int>();
    final oldNumbers = rows.map((line) => line.oldNumber).whereType<int>();
    return newNumbers.isNotEmpty
        ? newNumbers.reduce(math.max)
        : oldNumbers.isEmpty
        ? 0
        : oldNumbers.reduce(math.max);
  }
}

@immutable
class FileDocument {
  const FileDocument({
    required this.revision,
    required this.path,
    required this.side,
    required this.bytes,
    required this.kind,
    required this.lines,
    required this.hasTrailingNewline,
    required this.disableRichRendering,
    required this.fingerprint,
    this.limitReason,
  });

  final String revision;
  final String path;
  final FileDocumentSide side;
  final Uint8List bytes;
  final FileContentKind kind;
  final List<String> lines;
  final bool hasTrailingNewline;
  final bool disableRichRendering;
  final String fingerprint;
  final FileContentLimitReason? limitReason;

  factory FileDocument.fromBytes({
    required String revision,
    required String path,
    required FileDocumentSide side,
    required Uint8List bytes,
    required bool gitMarkedBinary,
  }) {
    final fingerprint = '${bytes.length}:${Object.hashAll(bytes)}';
    if (gitMarkedBinary || bytes.contains(0)) {
      return FileDocument(
        revision: revision,
        path: path,
        side: side,
        bytes: bytes,
        kind: FileContentKind.binary,
        lines: const [],
        hasTrailingNewline: false,
        disableRichRendering: true,
        fingerprint: fingerprint,
      );
    }
    if (bytes.length > fullDiffTextByteLimit) {
      return FileDocument(
        revision: revision,
        path: path,
        side: side,
        bytes: bytes,
        kind: FileContentKind.tooLarge,
        lines: const [],
        hasTrailingNewline: false,
        disableRichRendering: true,
        fingerprint: fingerprint,
        limitReason: FileContentLimitReason.byteLimit,
      );
    }
    if (_exceedsFullDiffTextLineLimit(bytes)) {
      return FileDocument(
        revision: revision,
        path: path,
        side: side,
        bytes: bytes,
        kind: FileContentKind.tooLarge,
        lines: const [],
        hasTrailingNewline: false,
        disableRichRendering: true,
        fingerprint: fingerprint,
        limitReason: FileContentLimitReason.lineLimit,
      );
    }
    late final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return FileDocument(
        revision: revision,
        path: path,
        side: side,
        bytes: bytes,
        kind: FileContentKind.unsupportedEncoding,
        lines: const [],
        hasTrailingNewline: false,
        disableRichRendering: true,
        fingerprint: fingerprint,
      );
    }
    final trailing = text.endsWith('\n');
    final lines = text.isEmpty ? <String>[] : text.split('\n');
    if (trailing) lines.removeLast();
    return FileDocument(
      revision: revision,
      path: path,
      side: side,
      bytes: bytes,
      kind: FileContentKind.utf8,
      lines: List.unmodifiable(lines),
      hasTrailingNewline: trailing,
      disableRichRendering:
          bytes.length > fullDiffLargeByteLimit ||
          lines.length > fullDiffLargeLineLimit,
      fingerprint: fingerprint,
    );
  }
}

@immutable
class BlameLine {
  const BlameLine({
    required this.lineNumber,
    required this.sha,
    required this.author,
    required this.uncommitted,
    this.authorEmail = '',
    this.authorTimestamp,
    this.summary = '',
  });

  final int lineNumber;
  final String sha;
  final String author;
  final String authorEmail;
  final int? authorTimestamp;
  final String summary;
  final bool uncommitted;
}

@immutable
class BlameDocument {
  const BlameDocument({required this.file, required this.lines});

  final FileDocument file;
  final List<BlameLine> lines;

  factory BlameDocument.fromGitLines(
    FileDocument file,
    List<GitBlameLine> lines,
  ) {
    if (file.lines.length != lines.length) {
      throw FormatException(
        'Blame row count ${lines.length} != file row count '
        '${file.lines.length}',
      );
    }
    return BlameDocument(
      file: file,
      lines: List.unmodifiable([
        for (final line in lines)
          BlameLine(
            lineNumber: line.lineNumber,
            sha: line.sha,
            author: line.author,
            authorEmail: line.authorEmail,
            authorTimestamp: line.authorTimestamp,
            summary: line.summary,
            uncommitted: line.uncommitted,
          ),
      ]),
    );
  }
}

@immutable
class FileHistoryEntry {
  const FileHistoryEntry({
    required this.commit,
    required this.path,
    required this.oldPath,
    required this.status,
  });

  final GitCommit commit;
  final String path;
  final String? oldPath;
  final String status;
}
