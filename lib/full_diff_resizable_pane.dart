import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'full_diff_theme.dart';

class FullDiffResizablePane extends StatelessWidget {
  const FullDiffResizablePane({
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.label,
    required this.resizerKey,
    required this.dividerKey,
    required this.onChanged,
    required this.onChangeEnd,
    required this.child,
    super.key,
  });

  final double width;
  final double minWidth;
  final double maxWidth;
  final String label;
  final Key resizerKey;
  final Key dividerKey;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = width.clamp(minWidth, maxWidth).toDouble();

    return SizedBox(
      width: effectiveWidth,
      child: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            key: dividerKey,
            right: 0,
            top: 0,
            bottom: 0,
            width: 1,
            child: const ColoredBox(color: fullDiffDivider),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 8,
            child: _FullDiffResizeHandle(
              width: effectiveWidth,
              minWidth: minWidth,
              maxWidth: maxWidth,
              label: label,
              resizerKey: resizerKey,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullDiffResizeHandle extends StatefulWidget {
  const _FullDiffResizeHandle({
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.label,
    required this.resizerKey,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double width;
  final double minWidth;
  final double maxWidth;
  final String label;
  final Key resizerKey;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  State<_FullDiffResizeHandle> createState() => _FullDiffResizeHandleState();
}

class _FullDiffResizeHandleState extends State<_FullDiffResizeHandle> {
  double? _dragWidth;

  double _clamp(double width) =>
      width.clamp(widget.minWidth, widget.maxWidth).toDouble();

  void _endDrag() {
    _dragWidth = null;
    widget.onChangeEnd();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final delta = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => -8.0,
        LogicalKeyboardKey.arrowRight => 8.0,
        _ => null,
      };
      if (delta == null) return KeyEventResult.ignored;
      widget.onChanged(_clamp(widget.width + delta));
      widget.onChangeEnd();
      return KeyEventResult.handled;
    },
    child: Semantics(
      label: widget.label,
      value: '${widget.width.round()} px',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: widget.resizerKey,
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _dragWidth = widget.width,
          onHorizontalDragUpdate: (details) {
            final nextWidth = _clamp(
              (_dragWidth ?? widget.width) + details.delta.dx,
            );
            _dragWidth = nextWidth;
            widget.onChanged(nextWidth);
          },
          onHorizontalDragEnd: (_) => _endDrag(),
          onHorizontalDragCancel: _endDrag,
        ),
      ),
    ),
  );
}
