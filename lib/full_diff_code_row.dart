import 'package:flutter/material.dart';

import 'full_diff_syntax.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';
import 'typography.dart';

const _sourceStyle = TextStyle(
  color: Colors.white,
  fontFamily: technicalFontFamily,
  fontFamilyFallback: technicalFontFallback,
  fontSize: 14,
  height: 21 / 14,
);

const _gutterStyle = TextStyle(
  color: fullDiffMuted,
  fontFamily: technicalFontFamily,
  fontFamilyFallback: technicalFontFallback,
  fontSize: 12,
  height: 21 / 12,
);

class FullDiffCodeRow extends StatelessWidget {
  const FullDiffCodeRow({
    required this.line,
    required this.path,
    required this.wrapLines,
    required this.highlighter,
    this.current = false,
    this.wordRanges = const [],
    this.compactGutter = false,
    super.key,
  });

  final DiffLine line;
  final String path;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final bool current;
  final List<WordRange> wordRanges;
  final bool compactGutter;

  @override
  Widget build(BuildContext context) {
    final (sourceColor, gutterColor, marker) = switch (line.kind) {
      DiffLineKind.add => (fullDiffAddedSource, fullDiffAddedGutter, '+'),
      DiffLineKind.delete => (
        fullDiffDeletedSource,
        fullDiffDeletedGutter,
        '−',
      ),
      _ => (fullDiffCanvas, fullDiffCanvas, ' '),
    };
    final richText = _SourceText(
      wrapLines: wrapLines,
      text: TextSpan(
        style: _sourceStyle,
        children: _sourceSpans(
          line.text,
          highlighter.highlightLine(path, line.text),
          wordRanges,
        ),
      ),
    );
    final source = wrapLines
        ? richText
        : SingleChildScrollView(
            key: const Key('code-row-horizontal-scroll'),
            scrollDirection: Axis.horizontal,
            primary: false,
            child: richText,
          );

    return ColoredBox(
      color: sourceColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compactGutter)
            _GutterCell(
              number: line.newNumber ?? line.oldNumber,
              width: fullDiffLineNumberWidth - 18,
              color: gutterColor,
            )
          else ...[
            _GutterCell(
              number: line.oldNumber,
              width: (fullDiffLineNumberWidth - 18) / 2,
              color: gutterColor,
            ),
            _GutterCell(
              number: line.newNumber,
              width: (fullDiffLineNumberWidth - 18) / 2,
              color: gutterColor,
            ),
          ],
          Container(
            width: 18,
            constraints: const BoxConstraints(minHeight: 27),
            alignment: Alignment.topCenter,
            color: gutterColor,
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(marker, style: _gutterStyle),
          ),
          Expanded(
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 27),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
                    child: source,
                  ),
                ),
                if (current)
                  const Positioned(
                    key: Key('code-row-current-marker'),
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: fullDiffAccent,
                      child: SizedBox(width: 3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceText extends Text {
  const _SourceText({required InlineSpan text, required this.wrapLines})
    : super.rich(
        text,
        softWrap: wrapLines,
        maxLines: wrapLines ? null : 1,
        overflow: TextOverflow.visible,
      );

  final bool wrapLines;

  @override
  Widget build(BuildContext context) => RichText(
    key: const Key('code-row-source-text'),
    text: textSpan!,
    textDirection: Directionality.maybeOf(context),
    softWrap: wrapLines,
    overflow: TextOverflow.visible,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: wrapLines ? null : 1,
    locale: Localizations.maybeLocaleOf(context),
  );
}

class _GutterCell extends StatelessWidget {
  const _GutterCell({
    required this.number,
    required this.width,
    required this.color,
  });

  final int? number;
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 27),
    alignment: Alignment.topRight,
    color: color,
    padding: const EdgeInsets.fromLTRB(2, 3, 5, 3),
    child: Text(number?.toString() ?? '', style: _gutterStyle),
  );
}

List<TextSpan> _sourceSpans(
  String source,
  List<CodeTokenSpan> syntaxSpans,
  List<WordRange> wordRanges,
) {
  if (source.isEmpty) return const [TextSpan(text: '')];

  final boundaries = <int>{0, source.length};
  for (final span in syntaxSpans) {
    boundaries
      ..add(span.start.clamp(0, source.length))
      ..add(span.end.clamp(0, source.length));
  }
  for (final range in wordRanges) {
    boundaries
      ..add(range.start.clamp(0, source.length))
      ..add(range.end.clamp(0, source.length));
  }
  final offsets = boundaries.toList()..sort();

  return [
    for (var index = 0; index < offsets.length - 1; index++)
      if (offsets[index] < offsets[index + 1])
        _sourceSpan(
          source,
          offsets[index],
          offsets[index + 1],
          syntaxSpans,
          wordRanges,
        ),
  ];
}

TextSpan _sourceSpan(
  String source,
  int start,
  int end,
  List<CodeTokenSpan> syntaxSpans,
  List<WordRange> wordRanges,
) {
  final syntax = syntaxSpans.cast<CodeTokenSpan?>().firstWhere(
    (span) => span!.start <= start && span.end >= end,
    orElse: () => null,
  );
  final changed = wordRanges.any(
    (range) => range.start < end && range.end > start,
  );
  var style = _sourceStyle;
  if (syntax != null) style = style.merge(syntax.style);
  if (changed) {
    style = style.copyWith(
      backgroundColor: fullDiffWordChange,
      decoration: TextDecoration.underline,
      decorationColor: fullDiffAccent,
    );
  }
  return TextSpan(text: source.substring(start, end), style: style);
}
