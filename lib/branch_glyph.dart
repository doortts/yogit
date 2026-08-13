import 'package:flutter/widgets.dart';

/// The branch mark the ref rows wear: a trunk with one line leaving it for a
/// second node.
///
/// Material has no git branch — the nearest of its icons is a plain fork,
/// which reads as a road sign rather than as a ref. Ten lines of painter buys
/// the shape everyone already knows from git's own tools, and it stays crisp
/// at the 13px the sidebar draws it at.
class BranchGlyph extends StatelessWidget {
  const BranchGlyph({required this.color, this.size = 13, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _BranchGlyphPainter(color)),
  );
}

class _BranchGlyphPainter extends CustomPainter {
  const _BranchGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything is in fractions of the box, so one shape serves every size
    // the sidebar and the menus ask for.
    final stroke = size.width * 0.115;
    final radius = size.width * 0.155;
    final line = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final trunkX = size.width * 0.28;
    final branchX = size.width * 0.76;
    final topY = size.height * 0.2;
    final bottomY = size.height * 0.8;
    canvas.drawLine(
      Offset(trunkX, topY + radius),
      Offset(trunkX, bottomY - radius),
      line,
    );
    // The limb leaves the trunk halfway and turns up into the far node, so the
    // two dots sit at the same heights as a branch drawn on a graph.
    canvas.drawPath(
      Path()
        ..moveTo(trunkX, size.height * 0.62)
        ..cubicTo(
          trunkX,
          size.height * 0.42,
          branchX,
          size.height * 0.56,
          branchX,
          topY + radius,
        ),
      line,
    );
    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(trunkX, topY), radius, dot);
    canvas.drawCircle(Offset(trunkX, bottomY), radius, dot);
    canvas.drawCircle(Offset(branchX, topY), radius, dot);
  }

  @override
  bool shouldRepaint(_BranchGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
