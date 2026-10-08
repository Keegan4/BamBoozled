import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// The BamBoozled panda, drawn in code so it stays crisp at any size.
/// Matches the `PandaMascot` component in Figma.
class PandaMascot extends StatelessWidget {
  const PandaMascot({super.key, this.size = 64, this.sleeping = false});

  final double size;
  final bool sleeping;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PandaPainter(sleeping)),
    ),
  );
}

class _PandaPainter extends CustomPainter {
  _PandaPainter(this.sleeping);
  final bool sleeping;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    final ink = Paint()..color = PandaColors.ink;
    final white = Paint()..color = PandaColors.surface;

    // Ears and head.
    canvas.drawCircle(const Offset(14, 16), 9, ink);
    canvas.drawCircle(const Offset(50, 16), 9, ink);
    canvas.drawCircle(const Offset(32, 35), 24, white);
    canvas.drawCircle(
      const Offset(32, 35),
      24,
      Paint()
        ..color = PandaColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Eye patches.
    for (final (x, angle) in [(23.0, -25.0), (41.0, 25.0)]) {
      canvas
        ..save()
        ..translate(x, 33)
        ..rotate(angle * math.pi / 180)
        ..drawOval(Rect.fromCenter(center: Offset.zero, width: 12, height: 16), ink)
        ..restore();
    }

    // Eyes: open dots, or closed arcs when sleeping.
    if (sleeping) {
      final lid = Paint()
        ..color = PandaColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      for (final x in [20.5, 37.5]) {
        canvas.drawPath(
          Path()
            ..moveTo(x, 33)
            ..quadraticBezierTo(x + 3, 35.5, x + 6, 33),
          lid,
        );
      }
    } else {
      canvas.drawCircle(const Offset(24, 32), 2.4, white);
      canvas.drawCircle(const Offset(40, 32), 2.4, white);
    }

    // Nose, smile and cheeks.
    canvas.drawOval(Rect.fromCenter(center: const Offset(32, 43), width: 7, height: 5), ink);
    canvas.drawPath(
      Path()
        ..moveTo(28, 48)
        ..quadraticBezierTo(32, 51, 36, 48),
      Paint()
        ..color = PandaColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final cheek = Paint()..color = PandaColors.blush.withValues(alpha: 0.8);
    canvas.drawCircle(const Offset(18, 44), 3, cheek);
    canvas.drawCircle(const Offset(46, 44), 3, cheek);
  }

  @override
  bool shouldRepaint(_PandaPainter old) => old.sleeping != sleeping;
}
