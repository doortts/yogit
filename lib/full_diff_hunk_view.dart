import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'full_diff_code_row.dart';
import 'full_diff_model.dart';
import 'full_diff_syntax.dart';
import 'full_diff_syntax_contract.dart';
import 'full_diff_theme.dart';
import 'git.dart';
import 'typography.dart';

class HunkPresentationView extends StatelessWidget {
  const HunkPresentationView({
    required this.document,
    required this.activeAnchor,
    required this.path,
    required this.wrapLines,
    required this.highlighter,
    super.key,
  });

  final DiffDocument document;
  final DiffAnchor? activeAnchor;
  final String path;
  final bool wrapLines;
  final FullDiffSyntaxHighlighter highlighter;

  @override
  Widget build(BuildContext context) {
    final hunkIndex = activeAnchor?.hunkIndex;
    if (hunkIndex == null ||
        hunkIndex < 0 ||
        hunkIndex >= document.hunks.length) {
      return const Center(
        child: Text(
          '현재 옵션으로 표시할 변경이 없습니다',
          style: TextStyle(color: fullDiffMuted, fontSize: 14),
        ),
      );
    }

    final hunk = document.hunks[hunkIndex];
    final wordRanges = _wordRangesByLine(hunk.lines);
    return SelectionArea(
      child: ListView(
        primary: true,
        children: [
          KeyedSubtree(
            key: GlobalObjectKey<State<StatefulWidget>>(hunk.anchor.id),
            child: _PresentationHunkHeader(
              hunk: hunk,
              path: path,
              hunkCount: document.hunks.length,
            ),
          ),
          for (final line in hunk.changedLines)
            FullDiffCodeRow(
              line: line,
              path: path,
              wrapLines: wrapLines,
              highlighter: highlighter,
              current: true,
              wordRanges: wordRanges[line] ?? const [],
            ),
        ],
      ),
    );
  }
}

class _PresentationHunkHeader extends StatelessWidget {
  const _PresentationHunkHeader({
    required this.hunk,
    required this.path,
    required this.hunkCount,
  });

  final DiffHunk hunk;
  final String path;
  final int hunkCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: const BoxDecoration(
      color: fullDiffHunkHeader,
      border: Border(
        top: BorderSide(color: fullDiffDivider),
        bottom: BorderSide(color: fullDiffDivider),
      ),
    ),
    child: Text(
      '${hunk.context.isEmpty ? path : hunk.context} · '
      'lines ${hunk.displayRange} · '
      'change ${hunk.index + 1} of $hunkCount',
      style: const TextStyle(
        fontFamily: technicalFontFamily,
        fontFamilyFallback: technicalFontFallback,
        fontSize: 14,
        height: 21 / 14,
        color: fullDiffMuted,
      ),
    ),
  );
}

Map<DiffLine, List<WordRange>> _wordRangesByLine(List<DiffLine> lines) {
  final ranges = <DiffLine, List<WordRange>>{};
  for (final pair in pairDiff(lines)) {
    final left = pair.left;
    final right = pair.right;
    if (left?.kind != DiffLineKind.delete || right?.kind != DiffLineKind.add) {
      continue;
    }
    final changes = changedWordRanges(left!.text, right!.text);
    ranges[left] = changes.oldRanges;
    ranges[right] = changes.newRanges;
  }
  return ranges;
}

// TODO(full-diff-workspace): Remove this compatibility surface after
// DiffScreen switches to HunkPresentationView.
const _background = Color(0xFF15171E);
const _surface = Color(0xFF1D2029);
const _raised = Color(0xFF252936);
const _border = Color(0xFF343946);
const _text = Color(0xFFE8EAF2);
const _muted = Color(0xFF8D94A8);
const _added = Color(0xFF9BE7B2);
const _addedFill = Color(0xFF8AD6A1);
const _deleted = Color(0xFFF29AB2);
const _activeBorder = Color(0xFF3A4657);
const _hunkRange = Color(0xFF7FB6FF);

const _gutterWidth = 104.0;
const _cardRadius = BorderRadius.all(Radius.circular(6));
const _codeStyle = TextStyle(
  color: _text,
  fontFamily: technicalFontFamily,
  fontFamilyFallback: technicalFontFallback,
  fontSize: 12,
);

@Deprecated('Use HunkPresentationView')
class HunkListView extends StatelessWidget {
  const HunkListView({
    required this.document,
    required this.activeHunkIndex,
    required this.wrapLines,
    required this.onHunkSelected,
    this.controller,
    this.anchorKeys,
    super.key,
  });

  final DiffDocument document;
  final int activeHunkIndex;
  final bool wrapLines;
  final ValueChanged<int> onHunkSelected;
  final ScrollController? controller;
  final Map<String, GlobalKey>? anchorKeys;

  @override
  Widget build(BuildContext context) {
    if (document.hunks.isEmpty) {
      return const ColoredBox(
        color: _background,
        child: Center(
          child: Text(
            'No changes',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ),
      );
    }

    return ColoredBox(
      color: _background,
      child: ListView.builder(
        key: const Key('hunk-list'),
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: document.hunks.length,
        itemBuilder: (context, index) {
          final hunk = document.hunks[index];
          return HunkCard(
            key: anchorKeys?[hunk.anchor.id] ?? ValueKey(hunk.anchor.id),
            hunk: hunk,
            selected: index == activeHunkIndex,
            positionLabel: '${index + 1} / ${document.hunks.length}',
            wrapLines: wrapLines,
            onSelected: () => onHunkSelected(index),
          );
        },
      ),
    );
  }
}

@Deprecated('Use HunkPresentationView')
class HunkCard extends StatelessWidget {
  const HunkCard({
    required this.hunk,
    required this.selected,
    required this.positionLabel,
    required this.wrapLines,
    required this.onSelected,
    super.key,
  });

  final DiffHunk hunk;
  final bool selected;
  final String positionLabel;
  final bool wrapLines;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    onTap: onSelected,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: DecoratedBox(
        key: Key('hunk-card-surface-${hunk.anchor.id}'),
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: selected ? _activeBorder : _border),
          borderRadius: _cardRadius,
        ),
        child: ClipRRect(
          borderRadius: _cardRadius,
          child: Material(
            color: _surface,
            child: SelectionArea(
              child: InkWell(
                excludeFromSemantics: true,
                onTap: onSelected,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HunkHeader(hunk: hunk, positionLabel: positionLabel),
                    _HunkLines(hunk: hunk, wrapLines: wrapLines),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _HunkHeader extends StatelessWidget {
  const _HunkHeader({required this.hunk, required this.positionLabel});

  final DiffHunk hunk;
  final String positionLabel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: const BoxDecoration(
      color: _raised,
      border: Border(bottom: BorderSide(color: _border)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          hunk.rangeLabel,
          style: const TextStyle(
            color: _hunkRange,
            fontFamily: technicalFontFamily,
            fontFamilyFallback: technicalFontFallback,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hunk.context.isNotEmpty) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hunk.context,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _text,
                fontFamily: technicalFontFamily,
                fontFamilyFallback: technicalFontFallback,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          positionLabel,
          style: const TextStyle(
            color: _muted,
            fontFamily: technicalFontFamily,
            fontFamilyFallback: technicalFontFallback,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

class _HunkLines extends StatelessWidget {
  const _HunkLines({required this.hunk, required this.wrapLines});

  final DiffHunk hunk;
  final bool wrapLines;

  @override
  Widget build(BuildContext context) {
    if (wrapLines) return _lineColumn();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _gutterWidth;
        final contentWidth = _widestSourceLine(context) + _gutterWidth + 16;
        final rowWidth = math.max(viewportWidth, contentWidth);
        return SingleChildScrollView(
          key: Key('hunk-horizontal-${hunk.anchor.id}'),
          scrollDirection: Axis.horizontal,
          primary: false,
          child: SizedBox(
            key: Key('hunk-lines-${hunk.anchor.id}'),
            width: rowWidth,
            child: _lineColumn(),
          ),
        );
      },
    );
  }

  Widget _lineColumn() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, line) in hunk.lines.indexed)
        _HunkLine(
          rowKey: Key('hunk-line-${hunk.anchor.id}-$index'),
          line: line,
          wrapLines: wrapLines,
        ),
    ],
  );

  double _widestSourceLine(BuildContext context) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var width = 0.0;
    for (final line in hunk.lines) {
      painter.text = TextSpan(text: line.text, style: _codeStyle);
      painter.layout();
      width = math.max(width, painter.width);
    }
    painter.dispose();
    return width;
  }
}

class _HunkLine extends StatelessWidget {
  const _HunkLine({
    required this.rowKey,
    required this.line,
    required this.wrapLines,
  });

  final Key rowKey;
  final DiffLine line;
  final bool wrapLines;

  @override
  Widget build(BuildContext context) {
    final color = _lineColor(line.kind);
    final marker = switch (line.kind) {
      DiffLineKind.add => '+',
      DiffLineKind.delete => '−',
      _ => '',
    };
    return ColoredBox(
      key: rowKey,
      color: _lineBackground(line.kind),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LineNumber(line.oldNumber),
          _LineNumber(line.newNumber),
          SizedBox(
            width: 20,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                marker,
                textAlign: TextAlign.center,
                style: _codeStyle.copyWith(color: color),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                line.text,
                softWrap: wrapLines,
                maxLines: wrapLines ? null : 1,
                style: _codeStyle.copyWith(color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineNumber extends StatelessWidget {
  const _LineNumber(this.number);

  final int? number;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    padding: const EdgeInsets.fromLTRB(2, 4, 6, 4),
    alignment: Alignment.centerRight,
    color: number == null ? Colors.transparent : _raised,
    child: Text(
      number?.toString() ?? '',
      style: const TextStyle(
        color: _muted,
        fontFamily: technicalFontFamily,
        fontFamilyFallback: technicalFontFallback,
        fontSize: 10,
      ),
    ),
  );
}

Color _lineColor(DiffLineKind kind) => switch (kind) {
  DiffLineKind.add => _added,
  DiffLineKind.delete => _deleted,
  DiffLineKind.context => _text,
  DiffLineKind.header || DiffLineKind.hunk => _muted,
};

Color _lineBackground(DiffLineKind kind) => switch (kind) {
  DiffLineKind.add => _addedFill.withValues(alpha: 0.15),
  DiffLineKind.delete => _deleted.withValues(alpha: 0.15),
  _ => Colors.transparent,
};
