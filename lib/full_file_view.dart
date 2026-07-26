import 'package:flutter/material.dart';

import 'full_diff_code_row.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';

class FullFileView extends StatelessWidget {
  const FullFileView({
    required this.document,
    required this.hunks,
    required this.path,
    required this.activeAnchor,
    required this.wrapLines,
    required this.highlighter,
    required this.anchorKeys,
    this.controller,
    super.key,
  });

  final FileDocument document;
  final List<DiffHunk> hunks;
  final String path;
  final DiffAnchor? activeAnchor;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final Map<String, GlobalKey> anchorKeys;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final status = switch (document.kind) {
      FileContentKind.binary => 'Binary file',
      FileContentKind.unsupportedEncoding => 'Unsupported encoding',
      FileContentKind.tooLarge => 'File too large',
      FileContentKind.utf8 when document.lines.isEmpty => 'Empty file',
      FileContentKind.utf8 => null,
    };
    if (status != null) {
      return _withDeletedBanner(
        Center(
          child: Text(
            status,
            style: const TextStyle(color: fullDiffMuted, fontSize: 14),
          ),
        ),
      );
    }

    final sourceLine = _sourceLine(
      activeAnchor,
      document.side,
      hunks,
      document.lines.length,
    );
    final anchorHunks = _hunksByLine(
      hunks,
      document.side,
      document.lines.length,
    );
    final list = ListView.builder(
      key: const Key('file-list'),
      controller: controller,
      primary: controller == null,
      itemCount: document.lines.length,
      itemBuilder: (context, index) {
        final lineNumber = index + 1;
        final current = lineNumber == sourceLine;
        final line = DiffLine(
          kind: DiffLineKind.context,
          text: document.lines[index],
          oldNumber: document.side == FileDocumentSide.old ? lineNumber : null,
          newNumber: document.side == FileDocumentSide.result
              ? lineNumber
              : null,
        );
        Widget row = KeyedSubtree(
          key: current ? Key('file-current-line-$lineNumber') : null,
          child: FullDiffCodeRow(
            line: line,
            path: path,
            wrapLines: wrapLines,
            highlighter: document.disableRichRendering
                ? const _NoopSyntaxHighlighter()
                : highlighter,
            current: current,
          ),
        );
        for (final hunk in anchorHunks[lineNumber] ?? const <DiffHunk>[]) {
          row = KeyedSubtree(key: _anchorKey(hunk.anchor), child: row);
        }
        return row;
      },
    );

    return _withDeletedBanner(SelectionArea(child: list));
  }

  Widget _withDeletedBanner(Widget content) {
    if (document.side != FileDocumentSide.old) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ColoredBox(
          color: fullDiffHunkHeader,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              'Deleted file · showing previous version',
              style: TextStyle(color: fullDiffMuted, fontSize: 14),
            ),
          ),
        ),
        Expanded(child: content),
      ],
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

class _NoopSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const _NoopSyntaxHighlighter();

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) => const [];

  @override
  String? languageForPath(String path) => null;
}
