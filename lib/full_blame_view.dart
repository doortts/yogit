import 'package:flutter/material.dart';

import 'full_diff_anchor_probe.dart';
import 'full_diff_code_row.dart';
import 'full_diff_hunk_header.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax_contract.dart';
import 'full_source_hunk_map.dart';
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
    this.onAnchorProbeAttached,
    this.onAnchorProbeDetached,
    this.controller,
    super.key,
  });

  final BlameDocument document;
  final List<DiffHunk> hunks;
  final DiffAnchor? activeAnchor;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final Map<String, GlobalKey> anchorKeys;
  final FullDiffAnchorProbeCallback? onAnchorProbeAttached;
  final FullDiffAnchorProbeCallback? onAnchorProbeDetached;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final lineCount = document.file.lines.length;
    final sourceMap = FullSourceHunkMap(
      hunks: hunks,
      side: document.file.side,
      lineCount: lineCount,
      activeAnchor: activeAnchor,
    );
    final sourceLine = sourceMap.activeLine(activeAnchor);
    return FullDiffSelectionArea(
      child: ListView.builder(
        key: const Key('blame-list'),
        controller: controller,
        primary: controller == null,
        itemCount: sourceMap.itemCount,
        itemBuilder: (context, index) {
          final item = sourceMap.itemAt(index);
          if (item case FullSourceHunkHeaderItem(:final hunk)) {
            return _probe(
              hunk.anchor,
              KeyedSubtree(
                key: Key('blame-hunk-header-${hunk.anchor.id}'),
                child: KeyedSubtree(
                  key: _anchorKey(hunk.anchor),
                  child: FullDiffHunkHeader(
                    hunk: hunk,
                    path: document.file.path,
                    hunkCount: hunks.length,
                  ),
                ),
              ),
            );
          }
          final sourceItem = item as FullSourceLineItem;
          final lineNumber = sourceItem.lineNumber;
          final current = lineNumber == sourceLine;
          return _probe(
            nearestHunkAnchorForSourceLine(
              hunks: hunks,
              side: document.file.side,
              lineNumber: lineNumber,
            ),
            KeyedSubtree(
              key: Key('blame-line-$lineNumber'),
              child: KeyedSubtree(
                key: current ? Key('blame-current-line-$lineNumber') : null,
                child: BlameSourceRow(
                  blame: document.lines[lineNumber - 1],
                  source: document.file.lines[lineNumber - 1],
                  path: document.file.path,
                  side: document.file.side,
                  kind: sourceItem.kind,
                  wrapLines: wrapLines,
                  highlighter: document.file.disableRichRendering
                      ? const _NoopSyntaxHighlighter()
                      : highlighter,
                  current: current,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  GlobalKey _anchorKey(DiffAnchor anchor) =>
      anchorKeys[anchor.id] ??
      (throw StateError('Missing GlobalKey for ${anchor.id}'));

  Widget _probe(DiffAnchor? anchor, Widget child) => anchor == null
      ? child
      : FullDiffAnchorProbe(
          anchor: anchor,
          onAttached: onAnchorProbeAttached,
          onDetached: onAnchorProbeDetached,
          child: child,
        );
}

class BlameSourceRow extends StatelessWidget {
  const BlameSourceRow({
    required this.blame,
    required this.source,
    required this.path,
    required this.side,
    required this.kind,
    required this.wrapLines,
    required this.highlighter,
    required this.current,
    super.key,
  });

  final BlameLine blame;
  final String source;
  final String path;
  final FileDocumentSide side;
  final DiffLineKind kind;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final bool current;

  @override
  Widget build(BuildContext context) => FullDiffCodeRow(
    line: DiffLine(
      kind: kind,
      text: source,
      oldNumber: side == FileDocumentSide.old ? blame.lineNumber : null,
      newNumber: side == FileDocumentSide.result ? blame.lineNumber : null,
    ),
    path: path,
    wrapLines: wrapLines,
    highlighter: highlighter,
    current: current,
    compactGutter: true,
    leadingMetadata: SizedBox(
      key: Key('blame-metadata-${blame.lineNumber}'),
      width: 80,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
        child: Row(
          children: [
            SizedBox(
              width: 52,
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
            Expanded(
              child: Text(
                _authorInitials(blame.author),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _shortSha(String sha) => sha.length <= 7 ? sha : sha.substring(0, 7);

String _authorInitials(String author) {
  final words = author
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  return words
      .take(2)
      .map((word) => word.characters.first.toUpperCase())
      .join();
}

class _NoopSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const _NoopSyntaxHighlighter();

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) => const [];

  @override
  String? languageForPath(String path) => null;
}
