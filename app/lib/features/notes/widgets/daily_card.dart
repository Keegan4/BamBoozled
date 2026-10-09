import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../../domain/models/daily_note.dart';

/// A daily card: a photo on the front (blurred until revealed) and the message on the back.
/// Tapping it (or pressing Enter/Space) calls [onTap]; the parent decides the next [stage].
/// Animations are skipped when the device asks for reduced motion.
class DailyCard extends StatelessWidget {
  const DailyCard({
    super.key,
    required this.note,
    required this.stage,
    required this.onTap,
    this.footer,
    this.actionLabel,
  });

  final DailyNote note;
  final CardStage stage;
  final VoidCallback onTap;

  /// Small text at the bottom of the back, e.g. the date it was opened.
  final String? footer;

  /// Replaces the "Tap to reveal / flip" hints, e.g. "Tap to open" when the card is only a preview.
  final String? actionLabel;

  static const _blur = 22.0;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    final still = MediaQuery.disableAnimationsOf(context);
    Duration d(int ms) => still ? Duration.zero : Duration(milliseconds: ms);
    final label = switch (stage) {
      CardStage.hidden => 'Today’s card, hidden. ${actionLabel ?? 'Tap to reveal the photo'}.',
      CardStage.revealed =>
        'Card photo${note.title == null ? '' : ': ${note.title}'}. ${actionLabel ?? 'Tap to flip and read it'}.',
      CardStage.back =>
        '${note.title == null ? '' : '${note.title}. '}${note.text} ${actionLabel ?? 'Tap to flip back to the photo'}.',
    };
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: stage == CardStage.back ? math.pi : 0),
          duration: d(550),
          curve: Curves.easeInOutCubic,
          builder: (context, angle, _) {
            final showBack = angle > math.pi / 2;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(angle),
              child: Material(
                key: ValueKey(showBack ? 'card-back' : 'card-front'),
                color: showBack ? p.rice : p.surface,
                elevation: 6,
                shadowColor: p.ink.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(PandaSizes.cardRadius),
                  side: BorderSide(color: p.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: showBack
                      ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: _back(p))
                      : _front(p, d),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _front(PandaPalette p, Duration Function(int) d) => Stack(
    fit: StackFit.expand,
    children: [
      TweenAnimationBuilder<double>(
        tween: Tween(end: stage == CardStage.hidden ? _blur : 0),
        duration: d(650),
        curve: Curves.easeOut,
        builder: (context, sigma, child) => sigma < 0.05
            ? child!
            : ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
                child: child,
              ),
        child: Image.asset(note.photo, fit: BoxFit.cover, excludeFromSemantics: true),
      ),
      AnimatedSwitcher(
        duration: d(300),
        child: switch (stage) {
          CardStage.hidden => Container(
            key: const ValueKey('hidden-overlay'),
            color: p.rice.withValues(alpha: 0.35),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PandaMascot(size: 72, sleeping: true),
                const SizedBox(height: 12),
                _pill(p, Icons.touch_app_rounded, actionLabel ?? 'Tap to reveal'),
              ],
            ),
          ),
          _ => Align(
            key: const ValueKey('flip-hint'),
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _pill(
                p,
                actionLabel == null ? Icons.autorenew_rounded : Icons.open_in_full_rounded,
                actionLabel ?? 'Tap to flip',
              ),
            ),
          ),
        },
      ),
    ],
  );

  Widget _back(PandaPalette p) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.format_quote_rounded, color: p.bamboo, size: 32),
        const SizedBox(height: 8),
        if (note.title != null) ...[Text(note.title!, style: PandaText.title), const SizedBox(height: 12)],
        Expanded(
          child: SingleChildScrollView(
            child: Text(note.text, style: PandaText.body.copyWith(fontSize: 18, height: 28 / 18)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (footer != null) Text(footer!, style: PandaText.caption.copyWith(color: p.muted)),
            const Spacer(),
            Icon(Icons.autorenew_rounded, size: 18, color: p.muted),
            const SizedBox(width: 4),
            Text(actionLabel ?? 'Tap to flip back', style: PandaText.caption.copyWith(color: p.muted)),
          ],
        ),
      ],
    ),
  );

  static Widget _pill(PandaPalette p, IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: p.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(PandaSizes.pill),
      boxShadow: [BoxShadow(color: p.ink.withValues(alpha: 0.12), blurRadius: 8)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: p.bambooDark),
        const SizedBox(width: 6),
        Text(text, style: PandaText.captionStrong.copyWith(color: p.ink)),
      ],
    ),
  );
}
