import 'package:flutter/widgets.dart';

/// Draws everything smaller on phones in the web app, where the full-size layout felt too big.
///
/// The whole app (pages, dialogs, menus and sheets) is laid out as if the screen were 1/[factor]
/// larger and then shrunk to fit, so text, buttons and spacing all keep their proportions. Taps
/// still land where they are drawn. Screens whose shortest side is [maxPhoneSide] or more, and
/// the installed apps, are left as they are.
class CompactScale extends StatelessWidget {
  const CompactScale({super.key, required this.enabled, required this.child});

  /// How big things are drawn compared with the full-size layout.
  static const factor = 0.85;

  /// Real (unscaled) shortest screen side up to which a screen counts as a phone. Kept below
  /// 600 × [factor] so a scaled phone still gets the phone layout.
  static const maxPhoneSide = 500.0;

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (!enabled || mq.size.shortestSide >= maxPhoneSide) return child;
    const s = factor;
    final size = mq.size / s;
    return MediaQuery(
      data: mq.copyWith(
        size: size,
        devicePixelRatio: mq.devicePixelRatio * s,
        padding: mq.padding / s,
        viewPadding: mq.viewPadding / s,
        viewInsets: mq.viewInsets / s,
        systemGestureInsets: mq.systemGestureInsets / s,
      ),
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: size.height,
        maxHeight: size.height,
        child: Transform.scale(scale: s, alignment: Alignment.topLeft, child: child),
      ),
    );
  }
}
