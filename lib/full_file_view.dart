import 'package:flutter/material.dart';

import 'full_diff_anchor_probe.dart';
import 'full_diff_code_row.dart';
import 'full_diff_hunk_header.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'full_source_hunk_map.dart';
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
    this.onAnchorProbeAttached,
    this.onAnchorProbeDetached,
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
  final FullDiffAnchorProbeCallback? onAnchorProbeAttached;
  final FullDiffAnchorProbeCallback? onAnchorProbeDetached;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final status = switch (document.kind) {
      FileContentKind.binary => 'Binary file',
      FileContentKind.unsupportedEncoding => 'Unsupported encoding',
      FileContentKind.tooLarge => 'File too large',
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

    final sourceMap = FullSourceHunkMap(
      hunks: hunks,
      side: document.side,
      lineCount: document.lines.length,
      activeAnchor: activeAnchor,
    );
    final sourceLine = sourceMap.activeLine(activeAnchor);
    final list = ListView.builder(
      key: const Key('file-list'),
      controller: controller,
      primary: controller == null,
      itemCount: sourceMap.itemCount + (document.lines.isEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == sourceMap.itemCount) {
          return const SizedBox(
            height: 180,
            child: Center(
              child: Text(
                'Empty file',
                style: TextStyle(color: fullDiffMuted, fontSize: 14),
              ),
            ),
          );
        }
        final item = sourceMap.itemAt(index);
        if (item case FullSourceHunkHeaderItem(:final hunk)) {
          return _probe(
            hunk.anchor,
            KeyedSubtree(
              key: Key('file-hunk-header-${hunk.anchor.id}'),
              child: KeyedSubtree(
                key: _anchorKey(hunk.anchor),
                child: FullDiffHunkHeader(
                  hunk: hunk,
                  path: path,
                  hunkCount: hunks.length,
                ),
              ),
            ),
          );
        }
        final sourceItem = item as FullSourceLineItem;
        final lineNumber = sourceItem.lineNumber;
        final current = lineNumber == sourceLine;
        final line = DiffLine(
          kind: sourceItem.kind,
          text: document.lines[lineNumber - 1],
          oldNumber: document.side == FileDocumentSide.old ? lineNumber : null,
          newNumber: document.side == FileDocumentSide.result
              ? lineNumber
              : null,
        );
        return _probe(
          nearestHunkAnchorForSourceLine(
            hunks: hunks,
            side: document.side,
            lineNumber: lineNumber,
          ),
          KeyedSubtree(
            key: Key('file-line-$lineNumber'),
            child: KeyedSubtree(
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
            ),
          ),
        );
      },
    );

    return _withDeletedBanner(FullDiffSelectionArea(child: list));
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

  Widget _probe(DiffAnchor? anchor, Widget child) => anchor == null
      ? child
      : FullDiffAnchorProbe(
          anchor: anchor,
          onAttached: onAnchorProbeAttached,
          onDetached: onAnchorProbeDetached,
          child: child,
        );
}

class _NoopSyntaxHighlighter implements FullDiffSyntaxHighlighter {
  const _NoopSyntaxHighlighter();

  @override
  List<CodeTokenSpan> highlightLine(String path, String source) => const [];

  @override
  String? languageForPath(String path) => null;
}
