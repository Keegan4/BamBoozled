import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/panda_mascot.dart';
import '../../data/daily_notes/daily_note_store.dart';
import '../../data/providers.dart';
import '../../domain/models/daily_note.dart';
import 'widgets/daily_card.dart';
import 'widgets/note_viewer.dart';

/// The Notes tab: one surprise card a day, plus the cards collected so far.
class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.panda;
    final phone = Breakpoints.isPhone(context);
    final now = ref.watch(clockProvider);
    final today = DateTime(now.year, now.month, now.day);
    final note = ref.watch(todaysNoteProvider);
    final state = ref.watch(dailyNoteStateProvider).value ?? const DailyNoteState();
    final library = ref.watch(dailyNotesProvider).value?.notes ?? const <DailyNote>[];
    final stage = state.stageOn(today);

    Future<void> tapToday(DailyNote n) => ref.read(dailyNoteStoreProvider).setStage(today, n.id, switch (stage) {
      CardStage.hidden => CardStage.revealed,
      CardStage.revealed => CardStage.back,
      CardStage.back => CardStage.revealed,
    });

    final notesById = {for (final n in library) n.id: n};
    final collected = [
      for (final (date, id) in state.history)
        if (notesById[id] case final n?) (date, n),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 40, phone ? 20 : 32, phone ? 16 : 40, 40),
      children: [
        Text('Today’s card', style: phone ? PandaText.title : PandaText.display),
        const SizedBox(height: 4),
        Text(
          note.value == null
              ? ''
              : stage == CardStage.hidden
              ? 'Tap the card to reveal today’s photo.'
              : 'A new card ${_untilMidnight(now)}.',
          key: const ValueKey('card-hint'),
          style: PandaText.body.copyWith(color: p.muted),
        ),
        const SizedBox(height: 20),
        switch (note) {
          AsyncData(value: final n?) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: DailyCard(
                key: const ValueKey('todays-card'),
                note: n,
                stage: stage,
                onTap: () => tapToday(n),
                footer: formatShortDate(today, now),
              ),
            ),
          ),
          AsyncData() || AsyncError() => const _NoCards(),
          _ => const SizedBox(height: 300, child: Center(child: CircularProgressIndicator())),
        },
        if (collected.isNotEmpty) ...[
          const SizedBox(height: 36),
          Text('Collected · ${collected.length}', style: PandaText.title),
          const SizedBox(height: 4),
          Text('Tap a card to look at it again.', style: PandaText.caption.copyWith(color: p.muted)),
          const SizedBox(height: 14),
          GridView(
            key: const ValueKey('collected'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Thumbnails stay small: 3 across on a phone, more on wider screens.
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
              childAspectRatio: 4 / 5.9,
            ),
            children: [
              for (final (date, n) in collected)
                _CollectedThumb(note: n, label: formatShortDate(date, now), today: date == today),
            ],
          ),
        ],
      ],
    );
  }

  static String _untilMidnight(DateTime now) {
    final left = DateTime(now.year, now.month, now.day + 1).difference(now);
    final h = left.inHours;
    final m = left.inMinutes % 60;
    if (h == 0) return m <= 1 ? 'in a minute' : 'in $m min';
    return m == 0 ? 'in $h h' : 'in $h h $m min';
  }
}

class _CollectedThumb extends StatelessWidget {
  const _CollectedThumb({required this.note, required this.label, required this.today});

  final DailyNote note;
  final String label;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    final caption = today ? 'Today' : label;
    return Semantics(
      button: true,
      label: '${note.title ?? 'Card'}, opened $caption. Open it.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: Material(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PandaSizes.tileRadius),
                side: BorderSide(color: p.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Ink.image(
                image: AssetImage(note.photo),
                fit: BoxFit.cover,
                child: InkWell(onTap: () => showNoteViewer(context, note, footer: caption)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PandaText.caption.copyWith(color: p.muted),
          ),
        ],
      ),
    );
  }
}

class _NoCards extends StatelessWidget {
  const _NoCards();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        const PandaMascot(size: 110, sleeping: true),
        const SizedBox(height: 16),
        const Text('No cards yet', style: PandaText.title, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Add photos and messages to assets/daily_notes to start getting a card a day.',
          style: PandaText.body.copyWith(color: context.panda.muted),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
