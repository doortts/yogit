import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'full_diff_syntax.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';
import 'typography.dart';

const fullDiffSourceRowHeight = 21.0;

const fullDiffSourceTextStyle = TextStyle(
  color: Colors.white,
  fontFamily: technicalFontFamily,
  fontFamilyFallback: technicalFontFallback,
  fontSize: 12,
  height: fullDiffSourceRowHeight / 12,
);

const _gutterStyle = TextStyle(
  color: fullDiffMuted,
  fontFamily: technicalFontFamily,
  fontFamilyFallback: technicalFontFallback,
  fontSize: 10,
  height: 21 / 10,
);

/// The sign standing where the code starts, on the row's own fill.
const _signStyle = TextStyle(
  color: fullDiffMuted,
  fontFamily: technicalFontFamily,
  fontFamilyFallback: technicalFontFallback,
  fontSize: 12,
  height: fullDiffSourceRowHeight / 12,
);

class FullDiffLazyBuildMetrics {
  int materializedItemCount = 0;
  int materializedPairCount = 0;
  int selectionTextBuildCount = 0;

  void recordItem({bool pair = false}) {
    materializedItemCount++;
    if (pair) materializedPairCount++;
  }

  void recordSelectionTextBuild() {
    selectionTextBuildCount++;
  }
}

class FullDiffSelectionArea extends StatefulWidget {
  const FullDiffSelectionArea({
    required this.child,
    this.allSourceText,
    this.allSourceTextBuilder,
    this.debugOnSelectionOrderResolved,
    super.key,
  }) : assert(allSourceText == null || allSourceTextBuilder == null);

  final Widget child;
  final String? allSourceText;
  final String Function()? allSourceTextBuilder;

  @visibleForTesting
  final VoidCallback? debugOnSelectionOrderResolved;

  @override
  State<FullDiffSelectionArea> createState() => _FullDiffSelectionAreaState();
}

class _FullDiffSelectionAreaState extends State<FullDiffSelectionArea> {
  final _selectionAreaKey = GlobalKey<SelectionAreaState>();
  final _sources = <_SourceSelectionContainerState>[];
  _SelectionSnapshot? _snapshot;
  bool _snapshotClearScheduled = false;
  bool _modelSelectAll = false;
  String? _selectedText;
  bool _disposed = false;

  void register(_SourceSelectionContainerState source) {
    if (_sources.contains(source)) return;
    _sources.add(source);
    invalidateSelectionSnapshot();
  }

  void unregister(_SourceSelectionContainerState source) {
    _sources.remove(source);
    invalidateSelectionSnapshot();
  }

  void invalidateSelectionSnapshot() {
    _snapshot = null;
  }

  String separatorAfter(_SourceSelectionContainerState source) {
    final existing = _snapshot;
    if (existing == null || identical(existing.first, source)) {
      _snapshot = _createSnapshot();
      _scheduleSnapshotClear();
    }
    return _snapshot?.separators[source] ?? '';
  }

  _SelectionSnapshot? _createSnapshot() {
    final registrationOrder = <_SourceSelectionContainerState, int>{
      for (final (index, source) in _sources.indexed) source: index,
    };
    final selected =
        <_SourceSelectionContainerState>[
          for (final source in _sources)
            if (source.rawSelectedContent != null) source,
        ]..sort((left, right) {
          final leftOrder = left.selectionOrder;
          final rightOrder = right.selectionOrder;
          if (leftOrder != null && rightOrder != null) {
            return leftOrder.compareTo(rightOrder);
          }
          final leftOrigin = _sourceOrigin(left);
          final rightOrigin = _sourceOrigin(right);
          if (leftOrigin == null || rightOrigin == null) {
            return registrationOrder[left]!.compareTo(
              registrationOrder[right]!,
            );
          }
          final verticalDelta = leftOrigin.dy - rightOrigin.dy;
          return verticalDelta.abs() > 0.5
              ? verticalDelta.sign.toInt()
              : leftOrigin.dx.compareTo(rightOrigin.dx);
        });
    if (selected.isEmpty) return null;

    widget.debugOnSelectionOrderResolved?.call();
    final separators = <_SourceSelectionContainerState, String>{};
    for (var index = 0; index < selected.length; index++) {
      if (index == selected.length - 1) {
        separators[selected[index]] = '';
        continue;
      }
      final currentOrder = selected[index].selectionOrder;
      final nextOrder = selected[index + 1].selectionOrder;
      if (currentOrder != null && nextOrder != null) {
        separators[selected[index]] = currentOrder.row == nextOrder.row
            ? '\t'
            : '\n';
        continue;
      }
      final currentOrigin = _sourceOrigin(selected[index]);
      final nextOrigin = _sourceOrigin(selected[index + 1]);
      separators[selected[index]] = currentOrigin == null || nextOrigin == null
          ? '\n'
          : nextOrigin.dy - currentOrigin.dy > 0.5
          ? '\n'
          : '\t';
    }
    return _SelectionSnapshot(first: selected.first, separators: separators);
  }

  Offset? _sourceOrigin(_SourceSelectionContainerState source) {
    final renderObject = source.context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    return renderObject.localToGlobal(Offset.zero);
  }

  void _scheduleSnapshotClear() {
    if (_snapshotClearScheduled) return;
    _snapshotClearScheduled = true;
    scheduleMicrotask(() {
      if (_disposed) return;
      _snapshot = null;
      _snapshotClearScheduled = false;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _snapshot = null;
    _sources.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasFullDocumentText =
        widget.allSourceText != null || widget.allSourceTextBuilder != null;
    final selectionArea = _FullDiffSelectionGroup(
      state: this,
      child: SelectionArea(
        key: _selectionAreaKey,
        onSelectionChanged: !hasFullDocumentText
            ? null
            : (content) {
                _modelSelectAll = false;
                _selectedText = content?.plainText;
              },
        child: widget.child,
      ),
    );
    if (!hasFullDocumentText) return selectionArea;
    return Actions(
      actions: <Type, Action<Intent>>{
        SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
          onInvoke: (intent) {
            _selectionAreaKey.currentState?.selectableRegion.selectAll(
              intent.cause,
            );
            _modelSelectAll = true;
            return null;
          },
        ),
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (intent) {
            if (_modelSelectAll) {
              final allSourceText =
                  widget.allSourceText ?? widget.allSourceTextBuilder!();
              unawaited(Clipboard.setData(ClipboardData(text: allSourceText)));
            } else if (_selectedText case final selectedText?) {
              unawaited(Clipboard.setData(ClipboardData(text: selectedText)));
            }
            return null;
          },
        ),
      },
      child: selectionArea,
    );
  }
}

class _SelectionSnapshot {
  const _SelectionSnapshot({required this.first, required this.separators});

  final _SourceSelectionContainerState first;
  final Map<_SourceSelectionContainerState, String> separators;
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
    this.showGutter = true,
    this.leadingMetadata,
    this.horizontalScroll = true,
    this.richRenderingEnabled = true,
    this.compact = false,
    this.currentMarkerColor = fullDiffAccent,
    this.selectionOrder,
    super.key,
  });

  final DiffLine line;
  final String path;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;
  final bool current;
  final List<WordRange> wordRanges;
  final bool compactGutter;
  final bool showGutter;
  final Widget? leadingMetadata;
  final bool horizontalScroll;
  final bool richRenderingEnabled;
  final bool compact;
  final Color currentMarkerColor;
  final FullDiffSelectionOrder? selectionOrder;

  @override
  Widget build(BuildContext context) {
    final compactSourceRow = compact || leadingMetadata != null;
    // One switch decides everything the line's kind colors: its fill, its
    // gutter, its sign, and the emphasis a changed word carries on top.
    final (sourceColor, gutterColor, marker, wordColor) = switch (line.kind) {
      DiffLineKind.add => (
        fullDiffAddedSource,
        fullDiffAddedGutter,
        '+',
        fullDiffAddedWord,
      ),
      DiffLineKind.delete => (
        fullDiffDeletedSource,
        fullDiffDeletedGutter,
        '−',
        fullDiffDeletedWord,
      ),
      _ => (fullDiffCanvas, fullDiffCanvas, ' ', fullDiffAddedWord),
    };
    final richText = _SourceText(
      wrapLines: wrapLines,
      text: TextSpan(
        style: fullDiffSourceTextStyle,
        children: _sourceSpans(
          line.text,
          richRenderingEnabled
              ? highlighter.highlightLine(path, line.text)
              : const [],
          wordRanges,
          wordColor,
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
              if (showGutter) const SizedBox(width: fullDiffLineNumberWidth),
              if (leadingMetadata case final Widget metadata)
                SelectionContainer.disabled(child: metadata),
              Expanded(
                child: Stack(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: compactSourceRow
                            ? fullDiffSourceRowHeight
                            : 27,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compactGutter ? 10 : 6,
                          vertical: compactSourceRow ? 0 : 3,
                        ),
                        child: compactGutter
                            ? _SourceSelectionContainer(
                                selectionOrder: selectionOrder,
                                child: source,
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // The sign reads with the code but copies
                                  // with the gutter — that is, not at all.
                                  SelectionContainer.disabled(
                                    child: SizedBox(
                                      width: 14,
                                      child: Text(marker, style: _signStyle),
                                    ),
                                  ),
                                  Expanded(
                                    child: _SourceSelectionContainer(
                                      selectionOrder: selectionOrder,
                                      child: source,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    if (current)
                      Positioned(
                        key: const Key('code-row-current-marker'),
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: ColoredBox(
                          color: currentMarkerColor,
                          child: const SizedBox(width: 3),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (showGutter)
            Positioned(
              left: 0,
              top: 0,
              child: SelectionContainer.disabled(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (compactGutter) ...[
                      _GutterCell(
                        number: line.newNumber ?? line.oldNumber,
                        width: fullDiffLineNumberWidth - 18,
                        color: gutterColor,
                        compact: compactSourceRow,
                      ),
                      Container(
                        width: 18,
                        constraints: BoxConstraints(
                          minHeight: compactSourceRow
                              ? fullDiffSourceRowHeight
                              : 27,
                        ),
                        alignment: Alignment.topCenter,
                        color: gutterColor,
                        padding: EdgeInsets.symmetric(
                          vertical: compactSourceRow ? 0 : 3,
                        ),
                        child: Text(marker, style: _gutterStyle),
                      ),
                    ] else ...[
                      // Both numbers, the way git prints them; the sign moved
                      // over to the source so the two columns get the width.
                      _GutterCell(
                        number: line.oldNumber,
                        width: fullDiffLineNumberWidth / 2,
                        color: gutterColor,
                        compact: compactSourceRow,
                      ),
                      _GutterCell(
                        number: line.newNumber,
                        width: fullDiffLineNumberWidth / 2,
                        color: gutterColor,
                        compact: compactSourceRow,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

@immutable
class FullDiffSelectionOrder implements Comparable<FullDiffSelectionOrder> {
  const FullDiffSelectionOrder({required this.row, this.column = 0});

  final int row;
  final int column;

  @override
  int compareTo(FullDiffSelectionOrder other) {
    final rowComparison = row.compareTo(other.row);
    return rowComparison != 0 ? rowComparison : column.compareTo(other.column);
  }
}

class _SourceSelectionContainer extends StatefulWidget {
  const _SourceSelectionContainer({
    required this.child,
    required this.selectionOrder,
  });

  final Widget child;
  final FullDiffSelectionOrder? selectionOrder;

  @override
  State<_SourceSelectionContainer> createState() =>
      _SourceSelectionContainerState();
}

class _SourceSelectionContainerState extends State<_SourceSelectionContainer> {
  late final _delegate = _SourceSelectionContainerDelegate(this)
    ..addListener(_handleSelectionChanged);
  _FullDiffSelectionAreaState? _selectionGroup;

  SelectedContent? get rawSelectedContent => _delegate.rawSelectedContent;
  FullDiffSelectionOrder? get selectionOrder => widget.selectionOrder;

  void _handleSelectionChanged() {
    _selectionGroup?.invalidateSelectionSnapshot();
  }

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
  void didUpdateWidget(covariant _SourceSelectionContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionOrder != widget.selectionOrder) {
      _selectionGroup?.invalidateSelectionSnapshot();
    }
  }

  @override
  void dispose() {
    _selectionGroup?.unregister(this);
    _delegate.removeListener(_handleSelectionChanged);
    _delegate.dispose();
    super.dispose();
  }

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
    final separator = source._selectionGroup?.separatorAfter(source) ?? '';
    return SelectedContent(plainText: '${content.plainText}$separator');
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
    this.compact = false,
  });

  final int? number;
  final double width;
  final Color color;

  /// Follows the source row's own density — a tall cell beside a 21px row
  /// paints its fill past the line it belongs to.
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: BoxConstraints(
      minHeight: compact ? fullDiffSourceRowHeight : 27,
    ),
    alignment: Alignment.topRight,
    color: color,
    padding: EdgeInsets.fromLTRB(0, compact ? 0 : 3, 2, compact ? 0 : 3),
    child: Text(number?.toString() ?? '', style: _gutterStyle),
  );
}

List<TextSpan> _sourceSpans(
  String source,
  List<CodeTokenSpan> syntaxSpans,
  List<WordRange> wordRanges,
  Color wordColor,
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
          wordColor,
        ),
  ];
}

TextSpan _sourceSpan(
  String source,
  int start,
  int end,
  List<CodeTokenSpan> syntaxSpans,
  List<WordRange> wordRanges,
  Color wordColor,
) {
  final syntax = syntaxSpans.cast<CodeTokenSpan?>().firstWhere(
    (span) => span!.start <= start && span.end >= end,
    orElse: () => null,
  );
  final changed = wordRanges.any(
    (range) => range.start < end && range.end > start,
  );
  var style = fullDiffSourceTextStyle;
  if (syntax != null) style = style.merge(syntax.style);
  // The tint alone marks the changed words. An underline under them too broke
  // Hangul into per-syllable dashes and read as noise.
  if (changed) style = style.copyWith(backgroundColor: wordColor);
  return TextSpan(text: source.substring(start, end), style: style);
}
