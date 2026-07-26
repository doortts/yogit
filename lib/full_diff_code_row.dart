import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

class FullDiffSelectionArea extends StatefulWidget {
  const FullDiffSelectionArea({required this.child, super.key});

  final Widget child;

  @override
  State<FullDiffSelectionArea> createState() => _FullDiffSelectionAreaState();
}

class _FullDiffSelectionAreaState extends State<FullDiffSelectionArea> {
  final _sources = <_SourceSelectionContainerState>[];

  void register(_SourceSelectionContainerState source) {
    if (!_sources.contains(source)) _sources.add(source);
  }

  void unregister(_SourceSelectionContainerState source) {
    _sources.remove(source);
  }

  bool needsLineBreakAfter(_SourceSelectionContainerState source) {
    final selected = [
      for (final candidate in _sources)
        if (candidate.rawSelectedContent != null) candidate,
    ]..sort(_compareSources);
    final index = selected.indexOf(source);
    if (index < 0 || index == selected.length - 1) return false;

    final currentOrigin = _sourceOrigin(selected[index]);
    final nextOrigin = _sourceOrigin(selected[index + 1]);
    if (currentOrigin == null || nextOrigin == null) return true;
    return nextOrigin.dy - currentOrigin.dy > 0.5;
  }

  int _compareSources(
    _SourceSelectionContainerState left,
    _SourceSelectionContainerState right,
  ) {
    final leftOrigin = _sourceOrigin(left);
    final rightOrigin = _sourceOrigin(right);
    if (leftOrigin == null || rightOrigin == null) {
      return _sources.indexOf(left).compareTo(_sources.indexOf(right));
    }
    final verticalDelta = leftOrigin.dy - rightOrigin.dy;
    return verticalDelta.abs() > 0.5
        ? verticalDelta.sign.toInt()
        : leftOrigin.dx.compareTo(rightOrigin.dx);
  }

  Offset? _sourceOrigin(_SourceSelectionContainerState source) {
    final renderObject = source.context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    return renderObject.localToGlobal(Offset.zero);
  }

  @override
  Widget build(BuildContext context) => _FullDiffSelectionGroup(
    state: this,
    child: SelectionArea(child: widget.child),
  );
}

class _FullDiffSelectionGroup extends InheritedWidget {
  const _FullDiffSelectionGroup({required this.state, required super.child});

  final _FullDiffSelectionAreaState state;

  static _FullDiffSelectionAreaState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_FullDiffSelectionGroup>()
      ?.state;

  @override
  bool updateShouldNotify(_FullDiffSelectionGroup oldWidget) =>
      !identical(state, oldWidget.state);
}

class FullDiffCodeRow extends StatelessWidget {
  const FullDiffCodeRow({
    required this.line,
    required this.path,
    required this.wrapLines,
    required this.highlighter,
    this.current = false,
    this.wordRanges = const [],
    this.compactGutter = false,
    this.horizontalScroll = true,
    super.key,
  });

  final DiffLine line;
  final String path;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final bool current;
  final List<WordRange> wordRanges;
  final bool compactGutter;
  final bool horizontalScroll;

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
    final source = wrapLines || !horizontalScroll
        ? richText
        : SingleChildScrollView(
            key: const Key('code-row-horizontal-scroll'),
            scrollDirection: Axis.horizontal,
            primary: false,
            child: richText,
          );

    return ColoredBox(
      color: sourceColor,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: fullDiffLineNumberWidth),
              Expanded(
                child: Stack(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 27),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
                        child: _SourceSelectionContainer(child: source),
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
          Positioned(
            left: 0,
            top: 0,
            child: SelectionContainer.disabled(
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceSelectionContainer extends StatefulWidget {
  const _SourceSelectionContainer({required this.child});

  final Widget child;

  @override
  State<_SourceSelectionContainer> createState() =>
      _SourceSelectionContainerState();
}

class _SourceSelectionContainerState extends State<_SourceSelectionContainer> {
  late final _delegate = _SourceSelectionContainerDelegate(this);
  _FullDiffSelectionAreaState? _selectionGroup;

  SelectedContent? get rawSelectedContent => _delegate.rawSelectedContent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextGroup = _FullDiffSelectionGroup.maybeOf(context);
    if (identical(_selectionGroup, nextGroup)) return;
    _selectionGroup?.unregister(this);
    _selectionGroup = nextGroup;
    _selectionGroup?.register(this);
  }

  @override
  void dispose() {
    _selectionGroup?.unregister(this);
    _delegate.dispose();
    super.dispose();
  }

  bool get needsLineBreak =>
      _selectionGroup?.needsLineBreakAfter(this) ?? false;

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}

class _SourceSelectionContainerDelegate
    extends StaticSelectionContainerDelegate {
  _SourceSelectionContainerDelegate(this.source);

  final _SourceSelectionContainerState source;

  SelectedContent? get rawSelectedContent => super.getSelectedContent();

  @override
  SelectedContent? getSelectedContent() {
    final content = rawSelectedContent;
    if (content == null) return null;
    return source.needsLineBreak
        ? SelectedContent(plainText: '${content.plainText}\n')
        : content;
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
    selectionRegistrar: SelectionContainer.maybeOf(context),
    selectionColor: DefaultSelectionStyle.of(context).selectionColor,
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
