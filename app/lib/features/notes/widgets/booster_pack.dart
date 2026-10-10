import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/panda_mascot.dart';

/// A sealed booster pack. Sliding a finger or the mouse across the top strip tears it off; let go
/// past [ripAt] of the way across (or reach the end) and the pack opens, then [onOpened] runs.
/// Enter or Space opens it from the keyboard, and screen readers get an "Open pack" action.
class BoosterPack extends StatefulWidget {
  const BoosterPack({super.key, required this.width, required this.onOpened, this.title = 'Bamboo Booster'});

  final double width;
  final VoidCallback onOpened;
  final String title;

  static const aspect = 1.45;

  /// How far across (0–1) the slide has to get before letting go opens the pack.
  static const ripAt = 0.7;

  @override
  State<BoosterPack> createState() => _BoosterPackState();
}

class _BoosterPackState extends State<BoosterPack> with TickerProviderStateMixin {
  /// How far the tear has gone, 0–1.
  double _tear = 0;
  bool _opened = false;

  /// Springs the tear back, or finishes it.
  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(() => setState(() => _tear = _settleTween.evaluate(_settle)));
  Tween<double> _settleTween = Tween(begin: 0, end: 0);

  /// The torn strip flying away once the pack is open.
  late final AnimationController _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _settle.dispose();
    _fly.dispose();
    super.dispose();
  }

  bool get _still => MediaQuery.disableAnimationsOf(context);

  void _drag(DragUpdateDetails d) {
    if (_opened) return;
    _settle.stop();
    setState(() => _tear = (_tear + d.delta.dx / widget.width).clamp(0, 1));
    if (_tear >= 1) _open();
  }

  void _release(DragEndDetails d) {
    if (_opened) return;
    final fast = (d.primaryVelocity ?? 0) > 900 && _tear > 0.3;
    if (_tear >= BoosterPack.ripAt || fast) {
      _open();
    } else if (_still) {
      setState(() => _tear = 0);
    } else {
      _settleTween = Tween(begin: _tear, end: 0);
      _settle.forward(from: 0);
    }
  }

  Future<void> _open() async {
    if (_opened) return;
    _opened = true;
    _settle.stop();
    setState(() => _tear = 1);
    HapticFeedback.mediumImpact();
    if (!_still) await _fly.forward(from: 0);
    if (mounted) widget.onOpened();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = w * BoosterPack.aspect;
    final strip = h * 0.13;
    final fly = Curves.easeIn.transform(_fly.value);
    return Semantics(
      button: true,
      label: '${widget.title}, sealed. Slide across the top to open.',
      onTapHint: 'Open pack',
      onTap: _open,
      excludeSemantics: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _open,
          const SingleActivator(LogicalKeyboardKey.space): _open,
        },
        child: Focus(
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return GestureDetector(
                key: const ValueKey('booster-pack'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Focus.of(context).requestFocus(),
                onHorizontalDragUpdate: _drag,
                onHorizontalDragEnd: _release,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // The body of the pack, below the tear line.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: strip,
                        bottom: 0,
                        child: _PackBody(w: w, title: widget.title, focused: focused, part: _Part.body),
                      ),
                      // The strip above the tear line lifts as it's torn, then flies off.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: strip,
                        child: Transform.translate(
                          offset: Offset(fly * w * 0.9, -fly * h * 0.25 - _tear * strip * 0.25),
                          child: Transform.rotate(
                            alignment: Alignment.centerRight,
                            angle: -_tear * 0.06 + fly * 0.5,
                            child: Opacity(
                              opacity: 1 - fly,
                              child: _PackBody(w: w, title: widget.title, focused: focused, part: _Part.strip),
                            ),
                          ),
                        ),
                      ),
                      // The dotted tear line, with a bright cut where the tear has got to.
                      if (!_opened)
                        Positioned(
                          left: w * 0.04,
                          right: w * 0.04,
                          top: strip - 1.5,
                          height: 3,
                          child: CustomPaint(painter: _TearLinePainter(_tear)),
                        ),
                      if (!_opened)
                        Positioned(
                          left: w * 0.04 + (w * 0.92 - 28) * _tear,
                          top: strip - 30,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: _tear == 0 ? 0.85 : 1,
                              child: const Icon(Icons.arrow_forward_rounded, size: 28, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _Part { strip, body }

/// The foil pack. The strip and the body are drawn the same way and clipped, so they line up.
class _PackBody extends StatelessWidget {
  const _PackBody({required this.w, required this.title, required this.focused, required this.part});

  final double w;
  final String title;
  final bool focused;
  final _Part part;

  @override
  Widget build(BuildContext context) {
    final h = w * BoosterPack.aspect;
    final strip = h * 0.13;
    final radius = Radius.circular(w * 0.05);
    final full = SizedBox(
      width: w,
      height: h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(radius),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9CCB8E), Color(0xFF4F8A55), Color(0xFF2F5E3A), Color(0xFF5E9A5C)],
            stops: [0, 0.45, 0.8, 1],
          ),
          border: Border.all(color: focused ? Colors.white : const Color(0x55FFFFFF), width: focused ? 3 : 1.5),
        ),
        child: Stack(
          children: [
            // Crimped foil edges.
            Positioned(left: 0, right: 0, top: 0, height: strip * 0.42, child: const _Crimp()),
            Positioned(left: 0, right: 0, bottom: 0, height: strip * 0.42, child: const _Crimp()),
            // A soft shine across the foil.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(radius),
                  gradient: LinearGradient(
                    begin: const Alignment(-1, -0.4),
                    end: const Alignment(1, 0.4),
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0.3, 0.5, 0.7],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: h * 0.2,
              child: Column(
                children: [
                  PandaMascot(size: w * 0.42),
                  SizedBox(height: w * 0.06),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: w * 0.095,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: const [Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1))],
                    ),
                  ),
                  SizedBox(height: w * 0.02),
                  Text(
                    '7 CARDS · BAMBOO GROVE',
                    style: TextStyle(
                      fontSize: w * 0.045,
                      fontWeight: FontWeight.w800,
                      letterSpacing: w * 0.006,
                      color: const Color(0xFFE6F0E4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // Show only this part of the full pack.
    return ClipRect(
      child: OverflowBox(
        alignment: part == _Part.strip ? Alignment.topCenter : Alignment.bottomCenter,
        minHeight: h,
        maxHeight: h,
        child: full,
      ),
    );
  }
}

class _Crimp extends StatelessWidget {
  const _Crimp();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _CrimpPainter());
}

class _CrimpPainter extends CustomPainter {
  const _CrimpPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;
    for (var x = 4.0; x < size.width - 2; x += 5) {
      canvas.drawLine(Offset(x, size.height * 0.2), Offset(x, size.height * 0.8), paint);
    }
  }

  @override
  bool shouldRepaint(_CrimpPainter old) => false;
}

class _TearLinePainter extends CustomPainter {
  _TearLinePainter(this.tear);
  final double tear;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final dots = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var x = 0.0; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), dots);
    }
    if (tear > 0) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width * tear, y),
        Paint()
          ..color = const Color(0xFFFFF3C4)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2),
      );
    }
  }

  @override
  bool shouldRepaint(_TearLinePainter old) => old.tear != tear;
}
