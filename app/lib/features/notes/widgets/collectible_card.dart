import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/cards.dart';
import '../../../domain/services/seeded_random.dart';

/// A collectible card: arched photo, name banner, rarity gem and text box, drawn in a [finish].
/// The card is always 5:7. With [interactive], a mouse or finger over it tilts the card and moves
/// the sheen of shiny finishes (skipped when the device asks for reduced motion).
class CollectibleCard extends StatefulWidget {
  const CollectibleCard({
    super.key,
    required this.card,
    this.finish = Finish.none,
    required this.width,
    this.interactive = false,
  });

  final CardDef card;
  final Finish finish;
  final double width;
  final bool interactive;

  static const aspect = 7 / 5;

  @override
  State<CollectibleCard> createState() => _CollectibleCardState();
}

class _CollectibleCardState extends State<CollectibleCard> {
  /// Pointer position over the card, -1..1 on each axis (0, 0 = centre).
  Offset _p = Offset.zero;

  void _track(Offset local) {
    final w = widget.width, h = widget.width * CollectibleCard.aspect;
    setState(() => _p = Offset((local.dx / w * 2 - 1).clamp(-1, 1), (local.dy / h * 2 - 1).clamp(-1, 1)));
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = w * CollectibleCard.aspect;
    final still = MediaQuery.disableAnimationsOf(context);
    final face = SizedBox(
      width: w,
      height: h,
      child: _CardFace(card: widget.card, finish: widget.finish, w: w, p: _p),
    );
    if (!widget.interactive) {
      return Semantics(
        label: _label,
        child: ExcludeSemantics(child: face),
      );
    }
    final tilted = still
        ? face
        : Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(-_p.dy * 0.14)
              ..rotateY(_p.dx * 0.14),
            child: face,
          );
    return Semantics(
      label: _label,
      child: ExcludeSemantics(
        child: MouseRegion(
          onHover: (e) => _track(e.localPosition),
          onExit: (_) => setState(() => _p = Offset.zero),
          child: Listener(
            onPointerMove: (e) => _track(e.localPosition),
            onPointerUp: (_) => setState(() => _p = Offset.zero),
            child: tilted,
          ),
        ),
      ),
    );
  }

  String get _label {
    final c = widget.card;
    final f = widget.finish == Finish.none ? '' : ', ${widget.finish.label}';
    return '${c.name}, ${c.rarity.label}$f. ${c.text}';
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.finish, required this.w, required this.p});

  final CardDef card;
  final Finish finish;
  final double w;
  final Offset p;

  static const _ink = Color(0xFF2C2418);

  @override
  Widget build(BuildContext context) {
    final h = w * CollectibleCard.aspect;
    final radius = BorderRadius.circular(w * 0.07);
    final fullArt = finish == Finish.fullArt;
    final misprint = finish == Finish.misprint;
    final legendary = card.rarity == Rarity.legendary;
    final paleText = finish == Finish.ghost;

    final art = _Art(card: card, finish: finish, w: w, p: p, arched: !fullArt);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: w * 0.06, offset: Offset(0, w * 0.025)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: _Frame(finish: finish, p: p, w: w, seed: card.id),
            ),
            if (fullArt)
              Positioned.fill(child: art)
            else
              Positioned(left: w * 0.07, right: w * 0.07, top: h * 0.06, height: h * 0.52, child: art),
            Positioned(
              left: w * 0.03,
              right: w * 0.03,
              top: h * 0.54,
              height: h * 0.11,
              child: Transform.rotate(
                angle: misprint ? -0.04 : 0,
                child: Transform.translate(
                  offset: Offset(misprint ? w * 0.03 : 0, 0),
                  child: _Plate(
                    w: w,
                    translucent: fullArt,
                    radius: w * 0.03,
                    child: Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: w * 0.075,
                        fontWeight: FontWeight.w800,
                        letterSpacing: w * 0.002,
                        color: paleText ? const Color(0xFF6E7480) : _ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: w / 2 - w * 0.045,
              top: h * 0.645,
              width: w * 0.09,
              height: w * 0.09,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: card.rarity.gem,
                    borderRadius: BorderRadius.circular(w * 0.012),
                    border: Border.all(color: const Color(0xFF6B5F49), width: w * 0.01),
                    boxShadow: [BoxShadow(color: card.rarity.gem.withValues(alpha: 0.8), blurRadius: w * 0.04)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: w * 0.1 + (misprint ? -w * 0.03 : 0),
              right: w * 0.1 + (misprint ? w * 0.03 : 0),
              top: h * 0.72,
              bottom: h * 0.07,
              child: _Plate(
                w: w,
                translucent: fullArt,
                radius: w * 0.04,
                bottomRadius: w * 0.08,
                padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.02),
                child: Text(
                  card.text,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: w * 0.058,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: paleText ? const Color(0xFF6E7480) : _ink,
                  ),
                ),
              ),
            ),
            Positioned(
              left: w * 0.07,
              bottom: h * 0.012,
              child: Text(
                card.numberLabel,
                style: TextStyle(
                  fontSize: w * 0.042,
                  fontWeight: FontWeight.w800,
                  color: _footColor.withValues(alpha: 0.7),
                ),
              ),
            ),
            if (finish != Finish.none)
              Positioned(
                right: w * 0.07,
                bottom: h * 0.012,
                child: Text(
                  finish.label,
                  style: TextStyle(
                    fontSize: w * 0.042,
                    fontWeight: FontWeight.w800,
                    color: _footColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            if (finish == Finish.signed && card.artist != null)
              Positioned(
                right: w * 0.1,
                top: h * 0.43,
                child: Transform.rotate(
                  angle: -0.14,
                  child: Text(
                    card.artist!,
                    style: TextStyle(
                      fontSize: w * 0.085,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: const [Shadow(color: Colors.black87, blurRadius: 3)],
                    ),
                  ),
                ),
              ),
            if (legendary)
              Positioned(
                left: w * 0.33,
                right: w * 0.33,
                top: 0,
                height: h * 0.05,
                child: const CustomPaint(painter: _CrownPainter()),
              ),
            if (finish == Finish.rainbow)
              Positioned.fill(
                child: _Sheen(p: p, strength: 0.5, blend: BlendMode.overlay),
              ),
            // A thin highlight round the edge, brighter on Legendary cards.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: legendary ? const Color(0xB3FFDC8C) : Colors.white.withValues(alpha: 0.35),
                      width: w * 0.01,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _footColor => finish == Finish.cosmos ? const Color(0xFFEDE8FF) : _ink;
}

/// The name banner and text box: parchment plates.
class _Plate extends StatelessWidget {
  const _Plate({
    required this.w,
    required this.child,
    required this.radius,
    this.bottomRadius,
    this.translucent = false,
    this.padding = EdgeInsets.zero,
  });

  final double w;
  final Widget child;
  final double radius;
  final double? bottomRadius;
  final bool translucent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: translucent
            ? [Colors.white.withValues(alpha: 0.78), Colors.white.withValues(alpha: 0.68)]
            : const [Color(0xFFEADFC2), Color(0xFFD5C59C)],
      ),
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(radius),
        bottom: Radius.circular(bottomRadius ?? radius),
      ),
      border: Border.all(color: const Color(0x59503C1E), width: w * 0.007),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: w * 0.02, offset: Offset(0, w * 0.01)),
      ],
    ),
    child: Padding(
      padding: padding,
      child: Center(child: child),
    ),
  );
}

/// The card's border, which most finishes change.
class _Frame extends StatelessWidget {
  const _Frame({required this.finish, required this.p, required this.w, required this.seed});

  final Finish finish;
  final Offset p;
  final double w;
  final String seed;

  static const _rainbow = [
    Color(0xFFD8CFB8),
    Color(0xFFFFB3D9),
    Color(0xFFFFF2A8),
    Color(0xFFA8FFE0),
    Color(0xFFA8D8FF),
    Color(0xFFD9B3FF),
    Color(0xFFD8CFB8),
  ];

  @override
  Widget build(BuildContext context) {
    // Moving gradients slide with the pointer.
    final from = Alignment(-1.6 + p.dx * 0.8, -1.6 + p.dy * 0.8);
    final to = Alignment(1.6 + p.dx * 0.8, 1.6 + p.dy * 0.8);
    LinearGradient diagonal(List<Color> colors) =>
        LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors);
    final Decoration decoration = switch (finish) {
      Finish.ink => BoxDecoration(gradient: diagonal(const [Color(0xFFF4EFE2), Color(0xFFDCD5C3), Color(0xFFA9A190)])),
      Finish.bamboo => BoxDecoration(
        gradient: LinearGradient(
          colors: [
            for (var i = 0; i < 9; i++) ...[const Color(0xFF7DB078), const Color(0xFF6FA06A), const Color(0xFF5C8D58)],
          ],
          stops: [
            for (var i = 0; i < 9; i++) ...[i / 9, (i + 0.85) / 9, (i + 0.999) / 9],
          ],
        ),
      ),
      Finish.moonlight => BoxDecoration(
        gradient: diagonal(const [Color(0xFFA7B4D8), Color(0xFF6A779E), Color(0xFF3E4868)]),
      ),
      Finish.vintage => BoxDecoration(
        gradient: diagonal(const [Color(0xFFE0CDA8), Color(0xFFB99C6E), Color(0xFF7D6440)]),
      ),
      Finish.ghost => BoxDecoration(
        gradient: diagonal(const [Color(0xFFF7F8FA), Color(0xFFDADDE3), Color(0xFFB6BBC5)]),
      ),
      Finish.gold => BoxDecoration(
        gradient: LinearGradient(
          begin: from,
          end: to,
          colors: const [Color(0xFF8A6420), Color(0xFFF3D37A), Color(0xFFB88A2E), Color(0xFFFFF0B8), Color(0xFFA57A28)],
        ),
      ),
      Finish.cosmos => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.4, -0.6),
          radius: 1.3,
          colors: [Color(0xFF3B3F7A), Color(0xFF1E1F3F), Color(0xFF121229)],
        ),
      ),
      Finish.rainbow => BoxDecoration(
        gradient: diagonal(const [
          Color(0xFFFFC6D6),
          Color(0xFFFFE8A8),
          Color(0xFFC2F5D8),
          Color(0xFFBFE2FF),
          Color(0xFFE3CBFF),
        ]),
      ),
      Finish.reverseHolo => BoxDecoration(
        gradient: LinearGradient(begin: from, end: to, colors: _rainbow),
      ),
      _ => BoxDecoration(gradient: diagonal(const [Color(0xFFE4DCC8), Color(0xFFCFC6B0), Color(0xFF8E846D)])),
    };
    return DecoratedBox(
      decoration: decoration,
      child: finish == Finish.cosmos
          ? CustomPaint(
              painter: _StarsPainter(seed: '$seed-frame', count: 40, scale: w / 200),
            )
          : const SizedBox.expand(),
    );
  }
}

/// The photo, with the finish's colour filter and overlays.
class _Art extends StatelessWidget {
  const _Art({required this.card, required this.finish, required this.w, required this.p, required this.arched});

  final CardDef card;
  final Finish finish;
  final double w;
  final Offset p;
  final bool arched;

  // Colour matrices (rows: red, green, blue, alpha; the 5th column adds 0–255).
  static const List<double> _ink = [
    0.28, 0.93, 0.09, 0, -40.0, //
    0.28, 0.93, 0.09, 0, -40, //
    0.28, 0.93, 0.09, 0, -40, //
    0, 0, 0, 1, 0,
  ];
  static const List<double> _sepia = [
    0.393, 0.769, 0.189, 0, 0.0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0,
  ];
  static const List<double> _moon = [
    0.15, 0.35, 0.05, 0, 0.0, //
    0.18, 0.42, 0.07, 0, 12, //
    0.25, 0.50, 0.15, 0, 48, //
    0, 0, 0, 1, 0,
  ];
  static const List<double> _bamboo = [
    0.70, 0.15, 0.05, 0, 0.0, //
    0.15, 0.85, 0.10, 0, 16, //
    0.05, 0.20, 0.55, 0, 0, //
    0, 0, 0, 1, 0,
  ];
  static const List<double> _ghost = [
    0.13, 0.43, 0.04, 0, 105.0, //
    0.13, 0.43, 0.04, 0, 108, //
    0.13, 0.43, 0.04, 0, 115, //
    0, 0, 0, 0.85, 0,
  ];
  static const List<double> _gold = [
    0.62, 0.50, 0.12, 0, 12.0, //
    0.38, 0.62, 0.10, 0, 4, //
    0.18, 0.30, 0.25, 0, 0, //
    0, 0, 0, 1, 0,
  ];
  static const List<double> _soft = [
    0.70, 0.25, 0.05, 0, 18.0, //
    0.10, 0.85, 0.05, 0, 18, //
    0.10, 0.25, 0.65, 0, 18, //
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final matrix = switch (finish) {
      Finish.ink => _ink,
      Finish.vintage => _sepia,
      Finish.moonlight => _moon,
      Finish.bamboo => _bamboo,
      Finish.ghost => _ghost,
      Finish.gold => _gold,
      Finish.rainbow => _soft,
      _ => null,
    };
    Widget photo = Image.asset(card.photo, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    if (finish == Finish.misprint) {
      photo = Stack(
        fit: StackFit.expand,
        children: [
          Transform.translate(
            offset: Offset(w * 0.025, 0),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Color(0x99FF0050), BlendMode.modulate),
              child: photo,
            ),
          ),
          Transform.translate(
            offset: Offset(-w * 0.025, 0),
            child: Opacity(
              opacity: 0.5,
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(Color(0xFF00C8FF), BlendMode.modulate),
                child: photo,
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(w * 0.04, -w * 0.02),
            child: Transform.scale(scale: 1.08, child: photo),
          ),
        ],
      );
    } else if (matrix != null) {
      photo = ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: photo);
    }

    final overlays = <Widget>[
      if (finish == Finish.vintage)
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(radius: 0.85, colors: [Colors.transparent, Color(0x995A3714)], stops: [0.55, 1]),
          ),
        ),
      if (finish == Finish.moonlight) CustomPaint(painter: _MoonPainter()),
      if (finish == Finish.cosmos)
        CustomPaint(
          painter: _StarsPainter(seed: card.id, count: 70, scale: w / 200),
        ),
      if (finish == Finish.holo || finish == Finish.cosmos) _Sheen(p: p, strength: 0.55),
      if (finish == Finish.ghost) _Sheen(p: p, strength: 0.35, silver: true),
      if (finish == Finish.gold) _Sheen(p: p, strength: 0.45, gold: true),
      if (finish == Finish.ink)
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(radius: 1.1, colors: [Color(0x00FAF6EC), Color(0x40FAF6EC)]),
          ),
        ),
    ];

    final child = Stack(
      fit: StackFit.expand,
      children: [
        photo,
        ...overlays.map((o) => IgnorePointer(child: o)),
      ],
    );
    if (!arched) return child;
    return ClipPath(
      clipper: _ArchClipper(),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black.withValues(alpha: 0.25), width: w * 0.012),
        ),
        child: child,
      ),
    );
  }
}

/// A rainbow (or gold / silver) band that slides with the pointer.
class _Sheen extends StatelessWidget {
  const _Sheen({required this.p, required this.strength, this.gold = false, this.silver = false, this.blend});

  final Offset p;
  final double strength;
  final bool gold;
  final bool silver;
  final BlendMode? blend;

  @override
  Widget build(BuildContext context) {
    final a = (strength * 255).round();
    final colors = gold
        ? [Colors.transparent, Color.fromARGB(a, 255, 230, 150), Colors.transparent]
        : silver
        ? [
            Colors.transparent,
            Color.fromARGB(a, 235, 240, 250),
            Color.fromARGB(a ~/ 2, 200, 210, 230),
            Colors.transparent,
          ]
        : [
            Colors.transparent,
            Color.fromARGB(a, 255, 0, 150),
            Color.fromARGB(a, 255, 230, 0),
            Color.fromARGB(a, 0, 255, 170),
            Color.fromARGB(a, 0, 170, 255),
            Color.fromARGB(a, 170, 0, 255),
            Colors.transparent,
          ];
    return DecoratedBox(
      decoration: BoxDecoration(
        backgroundBlendMode: blend ?? BlendMode.screen,
        gradient: LinearGradient(
          begin: Alignment(-2.2 + p.dx * 1.4, -2.2 + p.dy * 0.8),
          end: Alignment(2.2 + p.dx * 1.4, 2.2 + p.dy * 0.8),
          colors: colors,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ArchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) {
    final r = s.width * 0.06;
    return Path()
      ..moveTo(0, s.height * 0.22)
      ..quadraticBezierTo(0, 0, s.width * 0.5, 0)
      ..quadraticBezierTo(s.width, 0, s.width, s.height * 0.22)
      ..lineTo(s.width, s.height - r)
      ..quadraticBezierTo(s.width, s.height, s.width - r, s.height)
      ..lineTo(r, s.height)
      ..quadraticBezierTo(0, s.height, 0, s.height - r)
      ..close();
  }

  @override
  bool shouldReclip(_ArchClipper old) => false;
}

class _StarsPainter extends CustomPainter {
  _StarsPainter({required this.seed, required this.count, required this.scale});
  final String seed;
  final int count;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final r = SeededRandom(seed);
    final white = Paint()..color = Colors.white.withValues(alpha: 0.9);
    final warm = Paint()..color = const Color(0xFFFFF0B4).withValues(alpha: 0.9);
    for (var i = 0; i < count; i++) {
      final o = Offset(r.nextDouble() * size.width, r.nextDouble() * size.height);
      canvas.drawCircle(o, (0.6 + r.nextDouble() * 1.1) * scale, i.isEven ? white : warm);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.seed != seed || old.count != count || old.scale != scale;
}

class _MoonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.82, size.height * 0.16);
    final r = size.width * 0.08;
    canvas.drawCircle(c, r * 2.2, Paint()..color = const Color(0x33FFFADC));
    canvas.drawCircle(c, r, Paint()..color = const Color(0xF2FFFADC));
  }

  @override
  bool shouldRepaint(_MoonPainter old) => false;
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(0, s.height)
      ..lineTo(s.width * 0.08, s.height * 0.2)
      ..lineTo(s.width * 0.28, s.height * 0.7)
      ..lineTo(s.width * 0.5, 0)
      ..lineTo(s.width * 0.72, s.height * 0.7)
      ..lineTo(s.width * 0.92, s.height * 0.2)
      ..lineTo(s.width, s.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFFE8B83E), Color(0xFFFFE9A8), Color(0xFFE8B83E)])
            .createShader(Offset.zero & s),
    );
  }

  @override
  bool shouldRepaint(_CrownPainter old) => false;
}
