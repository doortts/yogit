import 'package:flutter/material.dart';

import 'full_diff_code_row.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax_contract.dart';
import 'git.dart';
import 'typography.dart';

class FullBlameView extends StatelessWidget {
  const FullBlameView({
    required this.document,
    required this.hunks,
    required this.activeAnchor,
    required this.wrapLines,
    required this.highlighter,
    required this.anchorKeys,
    this.controller,
    super.key,
  });

  final BlameDocument document;
  final List<DiffHunk> hunks;
  final DiffAnchor? activeAnchor;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final Map<String, GlobalKey> anchorKeys;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final lineCount = document.file.lines.length;
    final sourceLine = _sourceLine(
      activeAnchor,
      document.file.side,
      hunks,
      lineCount,
    );
    final anchorHunks = _hunksByLine(hunks, document.file.side, lineCount);
    return SelectionArea(
      child: ListView.builder(
        key: const Key('blame-list'),
        controller: controller,
        primary: controller == null,
        itemCount: document.file.lines.length,
        itemBuilder: (context, index) {
          final lineNumber = index + 1;
          final current = lineNumber == sourceLine;
          Widget row = BlameSourceRow(
            blame: document.lines[index],
            source: document.file.lines[index],
            path: document.file.path,
            wrapLines: wrapLines,
            highlighter: document.file.disableRichRendering
                ? const _NoopSyntaxHighlighter()
                : highlighter,
            current: current,
          );
          for (final hunk in anchorHunks[lineNumber] ?? const <DiffHunk>[]) {
            row = KeyedSubtree(key: _anchorKey(hunk.anchor), child: row);
          }
          return row;
        },
      ),
    );
  }

  GlobalKey _anchorKey(DiffAnchor anchor) =>
      anchorKeys[anchor.id] ??
      (throw StateError('Missing GlobalKey for ${anchor.id}'));
}

int? _sourceLine(
  DiffAnchor? anchor,
  FileDocumentSide side,
  List<DiffHunk> hunks,
  int lineCount,
) {
  if (anchor == null || lineCount == 0) return null;
  final direct = switch (side) {
    FileDocumentSide.old => anchor.oldLine,
    FileDocumentSide.result => anchor.newLine,
  };
  if (direct != null) return direct.clamp(1, lineCount);
  if (anchor.hunkIndex < 0 || anchor.hunkIndex >= hunks.length) return null;
  return _hunkLine(hunks[anchor.hunkIndex], side, lineCount);
}

Map<int, List<DiffHunk>> _hunksByLine(
  List<DiffHunk> hunks,
  FileDocumentSide side,
  int lineCount,
) {
  final result = <int, List<DiffHunk>>{};
  if (lineCount == 0) return result;
  for (final hunk in hunks) {
    (result[_hunkLine(hunk, side, lineCount)] ??= []).add(hunk);
  }
  return result;
}

int _hunkLine(DiffHunk hunk, FileDocumentSide side, int lineCount) {
  final line = switch (side) {
    FileDocumentSide.old => hunk.anchor.oldLine ?? hunk.oldStart,
    FileDocumentSide.result => hunk.anchor.newLine ?? hunk.newStart,
  };
  return line.clamp(1, lineCount);
}

class BlameSourceRow extends StatelessWidget {
  const BlameSourceRow({
    required this.blame,
    required this.source,
    required this.path,
    required this.wrapLines,
    required this.highlighter,
    required this.current,
    super.key,
  });

  final BlameLine blame;
  final String source;
  final String path;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final bool current;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 76,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
          child: Text(
            blame.uncommitted ? '·······' : _shortSha(blame.sha),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(
              fontFamily: technicalFontFamily,
              fontFamilyFallback: technicalFontFallback,
              fontSize: 12,
            ),
          ),
        ),
      ),
      SizedBox(
        width: 108,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
          child: Text(
            blame.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
      Expanded(
        child: FullDiffCodeRow(
          line: DiffLine(
            kind: DiffLineKind.context,
            text: source,
            oldNumber: null,
            newNumber: blame.lineNumber,
          ),
          path: path,
          wrapLines: wrapLines,
          highlighter: highlighter,
          current: current,
          compactGutter: true,
        ),
      ),
    ],
  );
}

String _shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);

class _NoopSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const _NoopSyntaxHighlighter();

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) => const [];

  @override
  String? languageForPath(String path) => null;
}
