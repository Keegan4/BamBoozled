import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../domain/models/daily_note.dart';
import 'daily_card.dart';

/// Opens a card on its own, over the rest of the app, which is blurred out. It starts at
/// [initialStage]: a collected card starts on the photo, today's card may still be hidden. A tap
/// on a hidden card reveals it; after that each tap flips it. Every change is reported to
/// [onStageChanged]. Tapping outside it, the close button, Escape or Back closes it.
Future<void> showNoteViewer(
  BuildContext context,
  DailyNote note, {
  String? footer,
  CardStage initialStage = CardStage.revealed,
  ValueChanged<CardStage>? onStageChanged,
}) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: still ? Duration.zero : const Duration(milliseconds: 260),
    pageBuilder: (context, _, _) =>
        NoteViewer(note: note, footer: footer, initialStage: initialStage, onStageChanged: onStageChanged),
    transitionBuilder: (context, animation, _, child) {
      final t = Curves.easeOut.transform(animation.value);
      return Stack(
        fit: StackFit.expand,
        children: [
          // Blurs and dims everything behind the card.
          Positioned.fill(
            child: IgnorePointer(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12 * t, sigmaY: 12 * t),
                child: ColoredBox(color: PandaColors.ink.withValues(alpha: 0.28 * t)),
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

class NoteViewer extends StatefulWidget {
  const NoteViewer({
    super.key,
    required this.note,
    this.footer,
    this.initialStage = CardStage.revealed,
    this.onStageChanged,
  });

  final DailyNote note;
  final String? footer;
  final CardStage initialStage;
  final ValueChanged<CardStage>? onStageChanged;

  @override
  State<NoteViewer> createState() => _NoteViewerState();
}

class _NoteViewerState extends State<NoteViewer> {
  late var _stage = widget.initialStage;

  void _tap() {
    setState(
      () => _stage = switch (_stage) {
        CardStage.hidden => CardStage.revealed,
        CardStage.revealed => CardStage.back,
        CardStage.back => CardStage.revealed,
      },
    );
    widget.onStageChanged?.call(_stage);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    final size = MediaQuery.sizeOf(context);
    // As big as fits, keeping the 4:5 card shape, with room for the close button.
    final width = [420.0, size.width - 32, (size.height - 140) * 4 / 5].reduce((a, b) => a < b ? a : b);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            // Taps on the blurred background close the viewer.
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('viewer-backdrop'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Center(
              child: SizedBox(
                key: const ValueKey('viewer-card'),
                width: width,
                child: DailyCard(note: widget.note, stage: _stage, onTap: _tap, footer: widget.footer),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: IconButton.filled(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
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
