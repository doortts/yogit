import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'full_diff_model.dart';
import 'full_diff_theme.dart';
import 'git.dart';

const _markerHeight = 3.0;
const _minimumViewportHeight = 18.0;

@immutable
class MinimapMarker {
  const MinimapMarker({
    required this.anchor,
    required this.top,
    required this.height,
    required this.color,
    required this.active,
  });

  final DiffAnchor anchor;
  final double top;
  final double height;
  final Color color;
  final bool active;

  double get center => top + height / 2;
}

@immutable
class MinimapViewport {
  const MinimapViewport({required this.top, required this.height});

  final double top;
  final double height;

  bool contains(double y) => y >= top && y <= top + height;
}

@immutable
class MinimapGeometry {
  const MinimapGeometry({required this.markers});

  factory MinimapGeometry.fromDocument({
    required DiffDocument document,
    required DiffAnchor? activeAnchor,
    required int sourceLineCount,
    required double height,
    required FileDocumentSide sourceSide,
  }) {
    return MinimapGeometry(
      markers: List<MinimapMarker>.unmodifiable(
        document.hunks.map((hunk) {
          final anchor = hunk.anchor;
          final line = sourceSide == FileDocumentSide.old
              ? anchor.oldLine ?? hunk.oldStart
              : anchor.newLine ?? hunk.newStart;
          final hasAddition = hunk.lines.any(
            (line) => line.kind == DiffLineKind.add,
          );
          final deletionOnly =
              !hasAddition &&
              hunk.lines.any((line) => line.kind == DiffLineKind.delete);
          return MinimapMarker(
            anchor: anchor,
            top: lineToTop(line, sourceLineCount, height),
            height: _markerHeight,
            color: deletionOnly ? fullDiffDeletedMark : fullDiffAccent,
            active: _sameAnchor(anchor, activeAnchor),
          );
        }),
      ),
    );
  }

  final List<MinimapMarker> markers;
}

int sourceLineCountForSide(DiffDocument document, FileDocumentSide sourceSide) {
  var maximum = 0;
  for (final hunk in document.hunks) {
    final start = sourceSide == FileDocumentSide.old
        ? hunk.oldStart
        : hunk.newStart;
    final count = sourceSide == FileDocumentSide.old
        ? hunk.oldCount
        : hunk.newCount;
    maximum = math.max(maximum, start + math.max(0, count - 1));
    for (final line in hunk.lines) {
      final number = sourceSide == FileDocumentSide.old
          ? line.oldNumber
          : line.newNumber;
      if (number != null) maximum = math.max(maximum, number);
    }
  }
  return maximum;
}

double lineToTop(int line, int lineCount, double height) {
  final availableHeight = math.max(0.0, height - _markerHeight);
  if (lineCount <= 1 || availableHeight == 0) return 0;
  return ((line - 1) / (lineCount - 1) * availableHeight)
      .clamp(0.0, availableHeight)
      .toDouble();
}

MinimapViewport scrollViewport({
  required double pixels,
  required double maxScrollExtent,
  required double viewportDimension,
  required double height,
}) {
  final trackHeight = math.max(0.0, height);
  final scrollExtent = math.max(0.0, maxScrollExtent);
  final visibleExtent = math.max(0.0, viewportDimension);
  final total = scrollExtent + visibleExtent;
  if (trackHeight == 0) {
    return const MinimapViewport(top: 0, height: 0);
  }
  if (total <= 0 || scrollExtent == 0) {
    return MinimapViewport(top: 0, height: trackHeight);
  }

  final viewportHeight = math.min(
    trackHeight,
    math.max(_minimumViewportHeight, visibleExtent / total * trackHeight),
  );
  final travel = trackHeight - viewportHeight;
  final scrollFraction = (pixels / scrollExtent).clamp(0.0, 1.0);
  return MinimapViewport(top: scrollFraction * travel, height: viewportHeight);
}

MinimapViewport? hunkViewport({
  required DiffHunk? hunk,
  required FileDocumentSide sourceSide,
  required int sourceLineCount,
  required double height,
}) {
  if (hunk == null) return null;
  final trackHeight = math.max(0.0, height);
  final lineCount = math.max(0, sourceLineCount);
  final start = sourceSide == FileDocumentSide.old
      ? hunk.oldStart
      : hunk.newStart;
  final count = sourceSide == FileDocumentSide.old
      ? hunk.oldCount
      : hunk.newCount;
  if (lineCount == 0) {
    if (count > 0) return null;
    return MinimapViewport(
      top: 0,
      height: math.min(_minimumViewportHeight, trackHeight),
    );
  }

  late final int boundaryStart;
  late final int boundaryEnd;
  if (count > 0) {
    boundaryStart = (start - 1).clamp(0, lineCount);
    boundaryEnd = (boundaryStart + count).clamp(boundaryStart, lineCount);
  } else {
    boundaryStart = start.clamp(0, lineCount);
    boundaryEnd = boundaryStart;
  }
  final rawTop = boundaryStart / lineCount * trackHeight;
  final rawBottom = boundaryEnd / lineCount * trackHeight;
  final viewportHeight = math.min(
    trackHeight,
    math.max(_minimumViewportHeight, rawBottom - rawTop),
  );
  final travel = math.max(0.0, trackHeight - viewportHeight);
  final center = (rawTop + rawBottom) / 2;
  return MinimapViewport(
    top: (center - viewportHeight / 2).clamp(0.0, travel).toDouble(),
    height: viewportHeight,
  );
}

DiffAnchor? nearestAnchorForY(
  double y,
  double height,
  List<MinimapMarker> markers,
) {
  if (markers.isEmpty) return null;
  final clampedY = y.clamp(0.0, math.max(0.0, height));
  return markers
      .reduce(
        (best, marker) =>
            (marker.center - clampedY).abs() < (best.center - clampedY).abs()
            ? marker
            : best,
      )
      .anchor;
}

class FullDiffMinimap extends StatefulWidget {
  const FullDiffMinimap({
    required this.document,
    required this.activeAnchor,
    required this.sourceLineCount,
    required this.sourceSide,
    required this.view,
    required this.presentation,
    required this.scrollController,
    required this.onAnchorSelected,
    required this.onScrollFractionChanged,
    super.key,
  });

  final DiffDocument document;
  final DiffAnchor? activeAnchor;
  final int sourceLineCount;
  final FileDocumentSide sourceSide;
  final FullDiffView view;
  final DiffPresentation presentation;
  final ScrollController scrollController;
  final ValueChanged<DiffAnchor> onAnchorSelected;
  final ValueChanged<double> onScrollFractionChanged;

  @override
  State<FullDiffMinimap> createState() => _FullDiffMinimapState();
}

class _FullDiffMinimapState extends State<FullDiffMinimap> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Full diff minimap');
  bool _dragging = false;
  bool _draggingViewport = false;
  double _dragOffset = 0;
  int _programmaticScrollSerial = 0;
  DiffAnchor? _lastDragAnchor;
  bool _metricsRebuildScheduled = false;
  MinimapGeometry? _cachedGeometry;
  DiffDocument? _cachedDocument;
  DiffAnchor? _cachedActiveAnchor;
  int? _cachedSourceLineCount;
  double? _cachedHeight;
  FileDocumentSide? _cachedSourceSide;
  FullDiffView? _cachedView;
  DiffPresentation? _cachedPresentation;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleExternalScroll);
  }

  @override
  void didUpdateWidget(covariant FullDiffMinimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_handleExternalScroll);
      widget.scrollController.addListener(_handleExternalScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleExternalScroll);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleExternalScroll() {
    if (!mounted) return;
    setState(() {});
    if (_dragging || _programmaticScrollSerial > 0) return;
  }

  MinimapViewport? _viewport(double height) {
    if (_usesAnchorDrag) {
      final activeIndex = _activeHunkIndex;
      final activeHunk =
          activeIndex < 0 || activeIndex >= widget.document.hunks.length
          ? null
          : widget.document.hunks[activeIndex];
      return hunkViewport(
        hunk: activeHunk,
        sourceSide: widget.sourceSide,
        sourceLineCount: widget.sourceLineCount,
        height: height,
      );
    }
    final position = _position;
    if (position == null) {
      return MinimapViewport(top: 0, height: math.max(0, height));
    }
    if (!position.hasContentDimensions) {
      _scheduleMetricsRebuild();
      return MinimapViewport(top: 0, height: math.max(0, height));
    }
    return scrollViewport(
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
      viewportDimension: position.viewportDimension,
      height: height,
    );
  }

  ScrollPosition? get _position {
    final positions = widget.scrollController.positions;
    return positions.length == 1 ? positions.single : null;
  }

  bool get _hasScrollableContent {
    final position = _position;
    return position != null &&
        position.hasContentDimensions &&
        position.maxScrollExtent > 0;
  }

  bool get _usesAnchorDrag =>
      widget.view == FullDiffView.diff &&
      widget.presentation == DiffPresentation.hunk;

  void _scheduleMetricsRebuild() {
    if (_metricsRebuildScheduled) return;
    _metricsRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsRebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _selectAnchor(double y, double height, {required bool deduplicate}) {
    final geometry = _geometryFor(height);
    final anchor = nearestAnchorForY(y, height, geometry.markers);
    if (anchor == null) return;
    if (deduplicate && _sameAnchor(anchor, _lastDragAnchor)) return;
    _lastDragAnchor = anchor;
    widget.onAnchorSelected(anchor);
  }

  void _startDrag(DragStartDetails details, double height) {
    _dragging = true;
    _lastDragAnchor = null;
    final viewport = _viewport(height);
    final y = details.localPosition.dy;
    _draggingViewport =
        !_usesAnchorDrag &&
        _hasScrollableContent &&
        viewport != null &&
        viewport.contains(y);
    if (_draggingViewport) {
      _dragOffset = y - viewport!.top;
    } else {
      _selectAnchor(y, height, deduplicate: true);
    }
  }

  void _updateDrag(DragUpdateDetails details, double height) {
    if (!_dragging) return;
    if (!_draggingViewport) {
      _selectAnchor(details.localPosition.dy, height, deduplicate: true);
      return;
    }

    final viewport = _viewport(height);
    if (viewport == null) return;
    final travel = math.max(0.0, height - viewport.height);
    final fraction = travel == 0
        ? 0.0
        : ((details.localPosition.dy - _dragOffset) / travel)
              .clamp(0.0, 1.0)
              .toDouble();
    final serial = ++_programmaticScrollSerial;
    widget.onScrollFractionChanged(fraction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _programmaticScrollSerial == serial) {
        _programmaticScrollSerial = 0;
      }
    });
  }

  void _endDrag() {
    _dragging = false;
    _draggingViewport = false;
    _lastDragAnchor = null;
  }

  int get _activeHunkIndex => widget.document.hunks.indexWhere(
    (hunk) => _sameAnchor(hunk.anchor, widget.activeAnchor),
  );

  void _stepAnchor(int delta) {
    final current = _activeHunkIndex;
    final next = current + delta;
    if (next < 0 || next >= widget.document.hunks.length) return;
    widget.onAnchorSelected(widget.document.hunks[next].anchor);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _stepAnchor(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _stepAnchor(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  MinimapGeometry _geometryFor(double height) {
    final cached = _cachedGeometry;
    if (cached != null &&
        identical(_cachedDocument, widget.document) &&
        _sameAnchor(_cachedActiveAnchor, widget.activeAnchor) &&
        _cachedSourceLineCount == widget.sourceLineCount &&
        _cachedHeight == height &&
        _cachedSourceSide == widget.sourceSide &&
        _cachedView == widget.view &&
        _cachedPresentation == widget.presentation) {
      return cached;
    }

    final geometry = MinimapGeometry.fromDocument(
      document: widget.document,
      activeAnchor: widget.activeAnchor,
      sourceLineCount: widget.sourceLineCount,
      height: height,
      sourceSide: widget.sourceSide,
    );
    _cachedGeometry = geometry;
    _cachedDocument = widget.document;
    _cachedActiveAnchor = widget.activeAnchor;
    _cachedSourceLineCount = widget.sourceLineCount;
    _cachedHeight = height;
    _cachedSourceSide = widget.sourceSide;
    _cachedView = widget.view;
    _cachedPresentation = widget.presentation;
    return geometry;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.view == FullDiffView.history) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: fullDiffMinimapWidth,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight.isFinite
              ? math.max(0.0, constraints.maxHeight)
              : 0.0;
          final geometry = _geometryFor(height);
          final viewport = _viewport(height);
          final activeIndex = _activeHunkIndex;
          final hunkCount = widget.document.hunks.length;
          return Semantics(
            container: true,
            label: 'Diff minimap',
            value: hunkCount == 0
                ? 'No changes'
                : 'Change ${activeIndex + 1} of $hunkCount',
            focusable: true,
            increasedValue: activeIndex >= 0 && activeIndex < hunkCount - 1
                ? 'Change ${activeIndex + 2} of $hunkCount'
                : null,
            decreasedValue: activeIndex > 0
                ? 'Change $activeIndex of $hunkCount'
                : null,
            onIncrease: activeIndex >= 0 && activeIndex < hunkCount - 1
                ? () => _stepAnchor(1)
                : null,
            onDecrease: activeIndex > 0 ? () => _stepAnchor(-1) : null,
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _handleKeyEvent,
              child: GestureDetector(
                key: const Key('full-diff-minimap'),
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTapDown: (_) => _focusNode.requestFocus(),
                onTapUp: (details) => _selectAnchor(
                  details.localPosition.dy,
                  height,
                  deduplicate: false,
                ),
                onPanStart: (details) => _startDrag(details, height),
                onPanUpdate: (details) => _updateDrag(details, height),
                onPanEnd: (_) => _endDrag(),
                onPanCancel: _endDrag,
                child: CustomPaint(
                  painter: FullDiffMinimapPainter(
                    geometry: geometry,
                    viewport: viewport,
                  ),
                  size: Size(fullDiffMinimapWidth, height),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class FullDiffMinimapPainter extends CustomPainter {
  const FullDiffMinimapPainter({
    required this.geometry,
    required this.viewport,
  });

  final MinimapGeometry geometry;
  final MinimapViewport? viewport;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = fullDiffMinimapTrack);
    canvas.drawLine(
      Offset.zero,
      Offset(0, size.height),
      Paint()
        ..color = fullDiffDivider
        ..strokeWidth = 1,
    );

    if (viewport case final viewport?) {
      final viewportRect = Rect.fromLTWH(
        1,
        viewport.top.clamp(0.0, size.height),
        math.max(0, size.width - 1),
        viewport.height.clamp(0.0, size.height),
      );
      canvas.drawRect(viewportRect, Paint()..color = fullDiffMinimapViewport);
      canvas.drawRect(
        viewportRect,
        Paint()
          ..color = fullDiffMinimapRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    for (final marker in geometry.markers) {
      canvas.drawRect(
        Rect.fromLTWH(
          3,
          marker.top.clamp(0.0, size.height),
          math.max(0, size.width - 6),
          marker.height.clamp(0.0, size.height),
        ),
        Paint()..color = marker.color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FullDiffMinimapPainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        oldDelegate.viewport?.top != viewport?.top ||
        oldDelegate.viewport?.height != viewport?.height;
  }
}

bool _sameAnchor(DiffAnchor? left, DiffAnchor? right) {
  if (left == null || right == null) return left == right;
  return left.hunkIndex == right.hunkIndex &&
      left.oldLine == right.oldLine &&
      left.newLine == right.newLine;
}
