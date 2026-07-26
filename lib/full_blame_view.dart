import 'package:flutter/material.dart';

import 'full_diff_code_row.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax_contract.dart';
import 'git.dart';
import 'typography.dart';

class FullBlameView extends StatelessWidget {
  const FullBlameView({
    required this.document,
    required this.activeAnchor,
    required this.wrapLines,
    required this.highlighter,
    required this.anchorKeys,
    this.controller,
    super.key,
  });

  final BlameDocument document;
  final DiffAnchor? activeAnchor;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final Map<String, GlobalKey> anchorKeys;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final sourceLine = switch (document.file.side) {
      FileDocumentSide.old => activeAnchor?.oldLine,
      FileDocumentSide.result => activeAnchor?.newLine,
    };
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
          if (current && activeAnchor != null) {
            row = KeyedSubtree(key: _anchorKey(activeAnchor!), child: row);
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
