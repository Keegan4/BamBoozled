import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';

/// Shows [builder]'s content over the rest of the app, which is blurred and dimmed. Tapping the
/// blurred background, the close button, Escape or Back closes it.
Future<T?> showBlurredOverlay<T>(BuildContext context, {required WidgetBuilder builder}) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: still ? Duration.zero : const Duration(milliseconds: 260),
    pageBuilder: (context, _, _) => BlurredOverlay(child: Builder(builder: builder)),
    transitionBuilder: (context, animation, _, child) {
      final t = Curves.easeOut.transform(animation.value);
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12 * t, sigmaY: 12 * t),
                child: ColoredBox(color: PandaColors.ink.withValues(alpha: 0.4 * t)),
              ),
            ),
          ),
          Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
          ),
        ],
      );
    },
  );
}

/// The frame of a blurred overlay: a tap-to-close background, the content, and a close button.
class BlurredOverlay extends StatelessWidget {
  const BlurredOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    void close() => Navigator.of(context).pop();
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('overlay-backdrop'),
                behavior: HitTestBehavior.opaque,
                onTap: close,
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Material(type: MaterialType.transparency, child: child),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: IconButton.filled(
                    tooltip: 'Close',
                    onPressed: close,
                    style: IconButton.styleFrom(
                      backgroundColor: p.surface,
                      foregroundColor: p.ink,
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
