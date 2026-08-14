import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'full_diff_model.dart';
import 'git.dart';

/// The pane's one horizontal offset, per `docs/diff-horizontal-scroll-design.md`.
///
/// [FullDiffHorizontalScrollSurface] owns it, every source column in the pane
/// reads it, and side-by-side hands the same one to both sides so they move
/// together. Rows depend on the notifier's identity, not its value: the value
/// changes every frame of a drag and only the paint has to follow it.
class DiffHorizontalOffset extends InheritedWidget {
  const DiffHorizontalOffset({
    required this.offset,
    required super.child,
    super.key,
  });

  final ValueListenable<double> offset;

  static ValueListenable<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DiffHorizontalOffset>()
      ?.offset;

  @override
  bool updateShouldNotify(DiffHorizontalOffset oldWidget) =>
      !identical(offset, oldWidget.offset);
}

/// How far past the viewport the widest line reaches, given the pane's width.
typedef DiffHorizontalOverflow = double Function(double viewportWidth);

/// Gives the pane a single horizontal scroll and keeps everything but the
/// source columns standing still.
///
/// The list stays a child of the scroll view so a sideways trackpad gesture
/// over a row still reaches this scrollable — Flutter passes a pointer signal
/// on to the ancestor once the inner scrollable's own axis takes nothing from
/// it. The scroll view then only supplies the range: its child is pushed back
/// by the current offset so the gutters, the hunk headers and the split
/// divider hold their place, and each row moves its own text instead.
class FullDiffHorizontalScrollSurface extends StatefulWidget {
  const FullDiffHorizontalScrollSurface({
    required this.overflowForWidth,
    required this.child,
    this.resetKey,
    super.key,
  });

  final DiffHorizontalOverflow overflowForWidth;

  /// Sends the pane back to column 0 when it changes — a new file, a new
  /// layout. Vertical moves and hunk jumps leave the offset alone.
  final Object? resetKey;
  final Widget child;

  @override
  State<FullDiffHorizontalScrollSurface> createState() =>
      _FullDiffHorizontalScrollSurfaceState();
}

class _FullDiffHorizontalScrollSurfaceState
    extends State<FullDiffHorizontalScrollSurface> {
  final _controller = ScrollController();
  final _offset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_readOffset);
  }

  @override
  void didUpdateWidget(covariant FullDiffHorizontalScrollSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetKey != oldWidget.resetKey) _reset();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_readOffset)
      ..dispose();
    _offset.dispose();
    super.dispose();
  }

  void _readOffset() {
    if (_controller.hasClients) _offset.value = _controller.offset;
  }

  void _reset() {
    _offset.value = 0;
    if (_controller.hasClients) _controller.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final measured = widget.overflowForWidth(constraints.maxWidth);
      // The scroll stays in the tree even with nothing to scroll to. Swapping
      // it in and out would re-parent the list below it, and a re-parented
      // list loses where the reader was standing.
      final overflow = measured.isFinite && measured > 0 ? measured : 0.0;
      final content = DiffHorizontalOffset(
        offset: _offset,
        child: widget.child,
      );
      if (overflow == 0 && _offset.value != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _reset();
        });
      }
      return Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          key: const Key('diff-horizontal-scroll'),
          scrollDirection: Axis.horizontal,
          controller: _controller,
          child: SizedBox(
            width: constraints.maxWidth + overflow,
            child: Align(
              alignment: Alignment.topLeft,
              child: AnimatedBuilder(
                animation: _offset,
                builder: (context, child) => Transform.translate(
                  offset: Offset(_offset.value, 0),
                  child: SizedBox(width: constraints.maxWidth, child: child),
                ),
                child: content,
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// One source column: its text laid out at full width, clipped to the column
/// and slid by the pane's offset.
class FullDiffHorizontalPan extends StatelessWidget {
  const FullDiffHorizontalPan({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final offset = DiffHorizontalOffset.maybeOf(context);
    return UnconstrainedBox(
      constrainedAxis: Axis.vertical,
      alignment: Alignment.topLeft,
      clipBehavior: Clip.hardEdge,
      child: offset == null
          ? child
          : AnimatedBuilder(
              animation: offset,
              builder: (context, child) => Transform.translate(
                offset: Offset(-offset.value, 0),
                child: child,
              ),
              child: child,
            ),
    );
  }
}

/// The widest line each side of a diff would draw, in logical pixels.
class DiffSourceWidths {
  const DiffSourceWidths({required this.oldSide, required this.newSide});

  final double oldSide;
  final double newSide;

  double get widest => math.max(oldSide, newSide);
}

/// Room left after the widest line, so its last character is not flush against
/// the pane's edge when the reader scrolls all the way over.
const diffHorizontalTailPadding = 12.0;

final _documentWidths = Expando<DiffSourceWidths>('diff source widths');
final _fileWidths = Expando<double>('diff file source width');

/// Widest line of a whole file, measured once per [document] — blame's side of
/// the same question `diffSourceWidths` answers for a patch.
double diffFileSourceWidth(
  Object document,
  Iterable<String> lines,
  TextStyle style,
) => _fileWidths[document] ??= diffLongestLineWidth(lines, style);

/// Widest line per side, measured once per document.
///
/// The scroll range has to hold still while the reader moves down the file, so
/// it comes from the whole document rather than the rows currently on screen.
DiffSourceWidths diffSourceWidths(DiffDocument document, TextStyle style) {
  final cached = _documentWidths[document];
  if (cached != null) return cached;
  final oldSide = _WidestLines();
  final newSide = _WidestLines();
  for (final hunk in document.hunks) {
    for (final line in hunk.lines) {
      switch (line.kind) {
        case DiffLineKind.add:
          newSide.offer(line.text);
        case DiffLineKind.delete:
          oldSide.offer(line.text);
        default:
          oldSide.offer(line.text);
          newSide.offer(line.text);
      }
    }
  }
  return _documentWidths[document] = DiffSourceWidths(
    oldSide: oldSide.measure(style),
    newSide: newSide.measure(style),
  );
}

/// Widest rendered line among [lines].
///
/// Laying out every line of a big file would cost more than the scroll is
/// worth, so this counts terminal cells first — cheap string maths — and only
/// measures the few widest candidates for real.
double diffLongestLineWidth(Iterable<String> lines, TextStyle style) {
  final widest = _WidestLines();
  for (final line in lines) {
    widest.offer(line);
  }
  return widest.measure(style);
}

class _WidestLines {
  // ponytail: five candidates, not one — cell counting is an approximation
  // (proportional fallback fonts, tabs), so the widest by cells is not always
  // the widest on screen. Raise it if a file ever scrolls short.
  static const _keep = 5;

  final _cells = <int>[];
  final _texts = <String>[];

  void offer(String text) {
    if (text.isEmpty) return;
    final cells = _cellCount(text);
    if (_cells.length == _keep && cells <= _cells.last) return;
    var index = 0;
    while (index < _cells.length && _cells[index] >= cells) {
      index++;
    }
    _cells.insert(index, cells);
    _texts.insert(index, text);
    if (_cells.length > _keep) {
      _cells.removeLast();
      _texts.removeLast();
    }
  }

  double measure(TextStyle style) {
    var width = 0.0;
    for (final text in _texts) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      width = math.max(width, painter.width);
      painter.dispose();
    }
    return width;
  }
}

/// Roughly what a terminal would call the line's width: Hangul, CJK and emoji
/// take two cells, everything else one.
int _cellCount(String text) {
  var cells = 0;
  for (final rune in text.runes) {
    cells += _wide(rune) ? 2 : 1;
  }
  return cells;
}

bool _wide(int rune) =>
    (rune >= 0x1100 && rune <= 0x115F) ||
    (rune >= 0x2E80 && rune <= 0xA4CF) ||
    (rune >= 0xAC00 && rune <= 0xD7A3) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0xFE30 && rune <= 0xFE6F) ||
    (rune >= 0xFF00 && rune <= 0xFF60) ||
    (rune >= 0xFFE0 && rune <= 0xFFE6) ||
    (rune >= 0x1F300 && rune <= 0x1FAFF) ||
    (rune >= 0x20000 && rune <= 0x3FFFD);
