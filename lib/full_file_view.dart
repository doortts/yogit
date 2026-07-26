import 'package:flutter/material.dart';

import 'full_diff_code_row.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';

class FullFileView extends StatelessWidget {
  const FullFileView({
    required this.document,
    required this.path,
    required this.activeAnchor,
    required this.wrapLines,
    required this.highlighter,
    required this.anchorKeys,
    this.controller,
    super.key,
  });

  final FileDocument document;
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
      return Center(
        child: Text(
          status,
          style: const TextStyle(color: fullDiffMuted, fontSize: 14),
        ),
      );
    }

    final sourceLine = _sourceLine(activeAnchor, document.side);
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
        if (current && activeAnchor != null) {
          row = KeyedSubtree(key: _anchorKey(activeAnchor!), child: row);
        }
        return row;
      },
    );

    if (document.side != FileDocumentSide.old) return list;
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
        Expanded(child: list),
      ],
    );
  }

  GlobalKey _anchorKey(DiffAnchor anchor) =>
      anchorKeys[anchor.id] ??
      (throw StateError('Missing GlobalKey for ${anchor.id}'));
}

int? _sourceLine(DiffAnchor? anchor, FileDocumentSide side) => switch (side) {
  FileDocumentSide.old => anchor?.oldLine,
  FileDocumentSide.result => anchor?.newLine,
};

class _NoopSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const _NoopSyntaxHighlighter();

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) => const [];

  @override
  String? languageForPath(String path) => null;
}
