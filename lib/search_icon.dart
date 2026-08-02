import 'package:flutter/material.dart';

/// A thinner magnifier than the Material glyph, so a search field's marker
/// sits at the same visual weight as the ref icons beside it. One widget for
/// every search field in the app, so they cannot drift apart.
class SearchIcon extends StatelessWidget {
  const SearchIcon({required this.color, this.size = 16, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _SearchIconPainter(color));
}

class _SearchIconPainter extends CustomPainter {
  const _SearchIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.072
      ..strokeCap = StrokeCap.round;
    final unit = size.width / 16;
    canvas.drawCircle(Offset(unit * 7.2, unit * 7.2), unit * 4.8, paint);
    canvas.drawLine(
      Offset(unit * 10.7, unit * 10.7),
      Offset(unit * 14.2, unit * 14.2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SearchIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
