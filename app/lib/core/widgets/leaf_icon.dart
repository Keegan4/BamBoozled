import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// A bamboo leaf. Priority is shown as 1–4 leaves.
class LeafIcon extends StatelessWidget {
  const LeafIcon({super.key, this.size = 16, this.color});

  final double size;

  /// Defaults to the theme's bamboo green.
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _LeafPainter(color ?? context.panda.bamboo)),
  );
}

class _LeafPainter extends CustomPainter {
  _LeafPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16);
    canvas.drawPath(
      Path()
        ..moveTo(2, 14)
        ..cubicTo(2, 6.5, 6.5, 2, 14, 2)
        ..cubicTo(14, 9.5, 9.5, 14, 2, 14)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_LeafPainter old) => old.color != color;
}
