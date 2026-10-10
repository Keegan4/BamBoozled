import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../core/widgets/panda_mascot.dart';
import '../../data/cards/collection_store.dart';
import '../../data/providers.dart';
import '../../domain/models/cards.dart';
import 'widgets/booster_pack.dart';
import 'widgets/collectible_card.dart';
import 'widgets/pack_opening.dart';

/// The Notes tab: a free pack of 7 cards a day, opened by tearing off the top, and the binder.
class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.panda;
    final phone = Breakpoints.isPhone(context);
    final now = ref.watch(clockProvider);
    final today = DateTime(now.year, now.month, now.day);
    final library = ref.watch(cardLibraryProvider);
    final collection = ref.watch(collectionProvider);
    final cards = library.value?.cards ?? const <CardDef>[];
    final state = collection.value ?? const CollectionState();
    final available = state.dailyAvailable(today);
    final todays = state.last != null && state.last!.date == dateKey(today) && library.value != null
        ? state.last!.resolve(library.value!)
        : const <Pull>[];

    void seeBinder() => context.go('/notes/binder');

    Future<void> open() async {
      final lib = library.value;
      if (lib == null) return;
      final seed = await ref.read(packSeedProvider.future);
      final pulls = await ref.read(collectionStoreProvider).openDaily(lib, seed, today);
      if (pulls.isEmpty || !context.mounted) return;
      await showPackOpening(context, pulls, onSeeBinder: seeBinder);
    }

    final loading = !library.hasValue || !collection.hasValue;
    final owned = cards.where((c) => state.copiesOf(c.id) > 0).length;
    final packWidth = math.min(260.0, MediaQuery.sizeOf(context).width - 96);

    return ListView(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 40, phone ? 20 : 32, phone ? 16 : 40, 40),
      children: [
        Text('Daily pack', style: phone ? PandaText.title : PandaText.display),
        const SizedBox(height: 4),
        Text(
          loading || cards.isEmpty
              ? ''
              : available
              ? 'Slide across the top of the pack to tear it open.'
              : 'Today’s pack is open. A new one ${_untilMidnight(now)}.',
          key: const ValueKey('pack-hint'),
          style: PandaText.body.copyWith(color: p.muted),
        ),
        const SizedBox(height: 24),
        if (loading)
          const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))
        else if (cards.isEmpty)
          const _NoCards()
        else if (available)
          Center(
            child: BoosterPack(key: const ValueKey('daily-pack'), width: packWidth, onOpened: open),
          )
        else
          _OpenedToday(
            pulls: todays,
            onSee: () => showPackOpening(context, todays, overview: true, onSeeBinder: seeBinder),
          ),
        if (!loading && cards.isNotEmpty) ...[
          const SizedBox(height: 36),
          _BinderSummary(owned: owned, total: cards.length, onOpen: seeBinder),
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

/// Today's cards, fanned out small, with a button to look through them again.
class _OpenedToday extends StatelessWidget {
  const _OpenedToday({required this.pulls, required this.onSee});

  final List<Pull> pulls;
  final VoidCallback onSee;

  @override
  Widget build(BuildContext context) {
    const w = 84.0;
    final shown = pulls.take(7).toList();
    final fanWidth = math.min(MediaQuery.sizeOf(context).width - 64, w + (shown.length - 1) * 36.0);
    final step = shown.length < 2 ? 0.0 : (fanWidth - w) / (shown.length - 1);
    return Column(
      children: [
        if (shown.isNotEmpty)
          Semantics(
            label: 'Today’s cards: ${shown.map((x) => x.card.name).join(', ')}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onSee,
              child: SizedBox(
                key: const ValueKey('todays-fan'),
                width: fanWidth,
                height: w * CollectibleCard.aspect + 16,
                child: Stack(
                  children: [
                    for (final (i, pull) in shown.indexed)
                      Positioned(
                        left: i * step,
                        top: 8 + ((i - (shown.length - 1) / 2).abs() * 2),
                        child: Transform.rotate(
                          angle: (i - (shown.length - 1) / 2) * 0.05,
                          child: CollectibleCard(card: pull.card, finish: pull.finish, width: w),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        if (shown.isNotEmpty)
          FilledButton.icon(
            onPressed: onSee,
            icon: const Icon(Icons.style_rounded),
            label: const Text('See today’s cards'),
          ),
      ],
    );
  }
}

class _BinderSummary extends StatelessWidget {
  const _BinderSummary({required this.owned, required this.total, required this.onOpen});

  final int owned;
  final int total;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PandaSizes.cardRadius),
        side: BorderSide(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('binder-summary'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.collections_bookmark_rounded, color: p.bambooDark, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Binder', style: PandaText.heading),
                    Text('$owned of $total cards collected', style: PandaText.caption.copyWith(color: p.muted)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(PandaSizes.pill),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : owned / total,
                        minHeight: 6,
                        color: p.bamboo,
                        backgroundColor: p.line,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ],
          ),
        ),
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
          'Add photos to assets/cards and list them in cards.yaml to start opening packs.',
          style: PandaText.body.copyWith(color: context.panda.muted),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
