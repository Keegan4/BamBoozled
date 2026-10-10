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
import 'widgets/pack_help.dart';
import 'widgets/pack_opening.dart';

/// The Notes tab: free packs of 7 cards (a new one every 2 hours), opened by tearing off the top,
/// and the binder.
class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.panda;
    final phone = Breakpoints.isPhone(context);
    final now = ref.watch(clockProvider);
    final library = ref.watch(cardLibraryProvider);
    final collection = ref.watch(collectionProvider);
    final cards = library.value?.cards ?? const <CardDef>[];
    final state = collection.value ?? const CollectionState();
    final packs = state.packsAt(now);
    final next = state.nextPackAt(now);
    final lastPack = state.last != null && library.value != null ? state.last!.resolve(library.value!) : const <Pull>[];

    void seeBinder() => context.go('/notes/binder');
    void seeLast() => showPackOpening(context, lastPack, overview: true, onSeeBinder: seeBinder);

    Future<void> open() async {
      final lib = library.value;
      if (lib == null) return;
      final seed = await ref.read(packSeedProvider.future);
      final pulls = await ref.read(collectionStoreProvider).openPack(lib, seed, ref.read(clockProvider));
      if (pulls.isEmpty || !context.mounted) return;
      await showPackOpening(context, pulls, onSeeBinder: seeBinder);
    }

    final loading = !library.hasValue || !collection.hasValue;
    final owned = cards.where((c) => state.copiesOf(c.id) > 0).length;
    final packWidth = math.min(260.0, MediaQuery.sizeOf(context).width - 96);
    final wait = next == null ? '' : _until(next, now);

    return ListView(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 40, phone ? 20 : 32, phone ? 16 : 40, 40),
      children: [
        Row(
          children: [
            Flexible(child: Text('Card packs', style: phone ? PandaText.title : PandaText.display)),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'About packs',
              onPressed: () => showPackHelp(context, sample: cards.firstOrNull),
              icon: Icon(Icons.help_outline_rounded, color: p.muted),
            ),
          ],
        ),
        Text(
          loading || cards.isEmpty
              ? ''
              : switch ((packs, next)) {
                  (0, _) => 'No packs ready. The next one arrives $wait.',
                  (_, null) => '$packs packs ready. Slide across the top to tear one open.',
                  _ => '$packs pack ready, another $wait. Slide across the top to tear it open.',
                },
          key: const ValueKey('pack-hint'),
          style: PandaText.body.copyWith(color: p.muted),
        ),
        Text(
          'A new pack every ${PackTimer.every.inHours} hours. Up to ${PackTimer.max} wait for you.',
          style: PandaText.caption.copyWith(color: p.muted),
        ),
        const SizedBox(height: 24),
        if (loading)
          const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))
        else if (cards.isEmpty)
          const _NoCards()
        else if (packs > 0)
          Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // A second waiting pack peeks out behind.
                  if (packs > 1)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: Transform.translate(
                            offset: const Offset(18, 6),
                            child: Transform.rotate(
                              angle: 0.07,
                              child: Opacity(
                                key: const ValueKey('spare-pack'),
                                opacity: 0.85,
                                child: BoosterPack(width: packWidth, onOpened: () {}),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Keyed by number, so the next pack starts sealed.
                  BoosterPack(key: ValueKey('pack-${state.opened + 1}'), width: packWidth, onOpened: open),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '$packs of ${PackTimer.max} packs ready',
                key: const ValueKey('pack-count'),
                style: PandaText.captionStrong.copyWith(color: p.muted),
              ),
              if (lastPack.isNotEmpty) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: seeLast,
                  icon: const Icon(Icons.style_rounded),
                  label: const Text('See your last pack'),
                ),
              ],
            ],
          )
        else
          _LastPack(pulls: lastPack, onSee: seeLast),
        if (!loading && cards.isNotEmpty) ...[
          const SizedBox(height: 36),
          _BinderSummary(owned: owned, total: cards.length, onOpen: seeBinder),
        ],
      ],
    );
  }

  /// "in 1 h 45 min", "in 20 min", "in a minute".
  static String _until(DateTime at, DateTime now) {
    final left = at.difference(now);
    final h = left.inHours;
    final m = (left.inSeconds / 60).ceil() % 60;
    if (h == 0) return m <= 1 ? 'in a minute' : 'in $m min';
    return m == 0 ? 'in $h h' : 'in $h h $m min';
  }
}

/// The last pack's cards, fanned out small, with a button to look through them again.
class _LastPack extends StatelessWidget {
  const _LastPack({required this.pulls, required this.onSee});

  final List<Pull> pulls;
  final VoidCallback onSee;

  @override
  Widget build(BuildContext context) {
    const w = 84.0;
    final shown = pulls;
    // Two packs' worth fans out flatter.
    final spread = 7 / math.max(7, shown.length);
    final fanWidth = math.min(MediaQuery.sizeOf(context).width - 64, w + (shown.length - 1) * 36.0);
    final step = shown.length < 2 ? 0.0 : (fanWidth - w) / (shown.length - 1);
    return Column(
      children: [
        if (shown.isNotEmpty)
          Semantics(
            label: 'Your last pack: ${shown.map((x) => x.card.name).join(', ')}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onSee,
              child: SizedBox(
                key: const ValueKey('last-fan'),
                width: fanWidth,
                height: w * CollectibleCard.aspect + 16,
                child: Stack(
                  children: [
                    for (final (i, pull) in shown.indexed)
                      Positioned(
                        left: i * step,
                        top: 8 + ((i - (shown.length - 1) / 2).abs() * 2 * spread),
                        child: Transform.rotate(
                          angle: (i - (shown.length - 1) / 2) * 0.05 * spread,
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
            label: const Text('See your last pack'),
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
