import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/cards.dart';
import '../../../domain/services/stable_random.dart';

/// Whether a card gets the [RarityFanfare] when it comes out of a pack.
bool hasFanfare(Rarity r) => r.index >= Rarity.epic.index;

/// Makes an Epic or Legendary card pop: it bounces in, sparkles twinkle round it, and "EPIC!" or
/// "LEGENDARY!" flashes above it. With reduced motion, the sparkles and banner just sit still.
class RarityFanfare extends StatefulWidget {
  const RarityFanfare({super.key, required this.rarity, required this.width, required this.child});

  final Rarity rarity;

  /// The card's width, which sizes the sparkles and banner.
  final double width;
  final Widget child;

  static String label(Rarity r) => '${r.label.toUpperCase()}!';

  @override
  State<RarityFanfare> createState() => _RarityFanfareState();
}

class _RarityFanfareState extends State<RarityFanfare> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _loop.value = 0.25;
    } else {
      _intro.forward();
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final legendary = widget.rarity == Rarity.legendary;
    final colors = legendary
        ? const [Color(0xFFFFF3B0), Color(0xFFF5A623), Color(0xFFFFE08A)]
        : const [Color(0xFFF1D9FF), Color(0xFFA45BE0), Color(0xFFE2B8FF)];
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _loop]),
      builder: (context, child) {
        final pop = Curves.elasticOut.transform(_intro.value.clamp(0, 1));
        final bannerIn = Curves.easeOutBack.transform(((_intro.value - 0.25) / 0.75).clamp(0, 1));
        // The banner flashes brighter and dimmer as it loops.
        final flash = 0.75 + 0.25 * math.sin(_loop.value * math.pi * 4);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.scale(scale: 0.85 + 0.15 * pop, child: child),
            Positioned.fill(
              left: -w * 0.18,
              right: -w * 0.18,
              top: -w * 0.18,
              bottom: -w * 0.18,
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('fanfare-sparkles'),
                  painter: _SparklePainter(
                    t: _loop.value,
                    seed: widget.rarity.name,
                    count: legendary ? 26 : 18,
                    size: w * 0.05,
                    colors: [Colors.white, colors[1], colors[0]],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -w * 0.2,
              child: IgnorePointer(
                child: Opacity(
                  opacity: bannerIn.clamp(0, 1),
                  child: Transform.scale(
                    scale: (0.4 + 0.6 * bannerIn) * (0.97 + 0.03 * flash),
                    child: Builder(
                      builder: (context) {
                        final size = w * (legendary ? 0.15 : 0.17);
                        final base = TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: size,
                          fontWeight: FontWeight.w900,
                          letterSpacing: w * 0.01,
                        );
                        final label = RarityFanfare.label(widget.rarity);
                        return Stack(
                          children: [
                            // A glow behind, then the letters in a gradient.
                            Text(
                              label,
                              style: base.copyWith(
                                color: colors[1],
                                shadows: [
                                  Shadow(
                                    color: colors[1].withValues(alpha: flash),
                                    blurRadius: w * 0.06,
                                  ),
                                  const Shadow(color: Color(0x99000000), blurRadius: 4, offset: Offset(0, 2)),
                                ],
                              ),
                            ),
                            Text(
                              label,
                              key: const ValueKey('fanfare-banner'),
                              style: base.copyWith(
                                foreground: Paint()
                                  ..shader = LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: colors,
                                  ).createShader(Rect.fromLTWH(0, size * 0.15, w, size * 1.1)),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// Four-pointed stars round the edge of the card, each twinkling at its own moment.
class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.t, required this.seed, required this.count, required this.size, required this.colors});

  final double t;
  final String seed;
  final int count;
  final double size;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size area) {
    final r = StableRandom('sparkles#$seed');
    for (var i = 0; i < count; i++) {
      // A point near the card's edge: pick a side, then a spot along it.
      final along = r.nextDouble();
      final depth = r.nextDouble() * 0.2;
      final o = switch (r.nextInt(4)) {
        0 => Offset(along * area.width, depth * area.height),
        1 => Offset(along * area.width, (1 - depth) * area.height),
        2 => Offset(depth * area.width, along * area.height),
        _ => Offset((1 - depth) * area.width, along * area.height),
      };
      final phase = r.nextDouble();
      final twinkle = math.pow(math.sin(((t + phase) % 1) * math.pi), 2).toDouble();
      if (twinkle < 0.05) continue;
      final s = size * (0.5 + r.nextDouble()) * twinkle;
      final paint = Paint()..color = colors[i % colors.length].withValues(alpha: 0.95 * twinkle);
      final star = Path()
        ..moveTo(o.dx, o.dy - s)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + s, o.dy)
        ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + s)
        ..quadraticBezierTo(o.dx, o.dy, o.dx - s, o.dy)
        ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - s)
        ..close();
      canvas.drawCircle(o, s * 0.9, Paint()..color = paint.color.withValues(alpha: 0.25 * twinkle));
      canvas.drawPath(star, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t || old.seed != seed || old.count != count || old.size != size;
}
