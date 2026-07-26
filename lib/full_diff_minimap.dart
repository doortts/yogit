import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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
    required bool deletedFile,
  }) {
    return MinimapGeometry(
      markers: List<MinimapMarker>.unmodifiable(
        document.hunks.map((hunk) {
          final anchor = hunk.anchor;
          final line = deletedFile
              ? anchor.oldLine ?? anchor.newLine ?? 1
              : anchor.newLine ?? anchor.oldLine ?? 1;
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
    required this.deletedFile,
    required this.view,
    required this.scrollController,
    required this.onAnchorSelected,
    required this.onScrollFractionChanged,
    super.key,
  });

  final DiffDocument document;
  final DiffAnchor? activeAnchor;
  final int sourceLineCount;
  final bool deletedFile;
  final FullDiffView view;
  final ScrollController scrollController;
  final ValueChanged<DiffAnchor> onAnchorSelected;
  final ValueChanged<double> onScrollFractionChanged;

  @override
  State<FullDiffMinimap> createState() => _FullDiffMinimapState();
}

class _FullDiffMinimapState extends State<FullDiffMinimap> {
  bool _dragging = false;
  bool _draggingViewport = false;
  double _dragOffset = 0;
  int _programmaticScrollSerial = 0;
  DiffAnchor? _lastDragAnchor;
  bool _metricsRebuildScheduled = false;

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
    super.dispose();
  }

  void _handleExternalScroll() {
    if (!mounted) return;
    setState(() {});
    if (_dragging || _programmaticScrollSerial > 0) return;
  }

  MinimapViewport _viewport(double height) {
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

  void _scheduleMetricsRebuild() {
    if (_metricsRebuildScheduled) return;
    _metricsRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsRebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _selectAnchor(double y, double height, {required bool deduplicate}) {
    final geometry = MinimapGeometry.fromDocument(
      document: widget.document,
      activeAnchor: widget.activeAnchor,
      sourceLineCount: widget.sourceLineCount,
      height: height,
      deletedFile: widget.deletedFile,
    );
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
    _draggingViewport = _hasScrollableContent && viewport.contains(y);
    if (_draggingViewport) {
      _dragOffset = y - viewport.top;
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
          final geometry = MinimapGeometry.fromDocument(
            document: widget.document,
            activeAnchor: widget.activeAnchor,
            sourceLineCount: widget.sourceLineCount,
            height: height,
            deletedFile: widget.deletedFile,
          );
          final viewport = _viewport(height);
          return GestureDetector(
            key: const Key('full-diff-minimap'),
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
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
  final MinimapViewport viewport;

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
        ..color = fullDiffAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

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
        oldDelegate.viewport.top != viewport.top ||
        oldDelegate.viewport.height != viewport.height;
  }
}

bool _sameAnchor(DiffAnchor? left, DiffAnchor? right) {
  if (left == null || right == null) return left == right;
  return left.hunkIndex == right.hunkIndex &&
      left.oldLine == right.oldLine &&
      left.newLine == right.newLine;
}
