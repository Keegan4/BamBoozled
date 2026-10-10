import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../data/cards/collection_store.dart';
import '../../data/providers.dart';
import '../../domain/models/cards.dart';
import 'widgets/card_detail.dart';
import 'widgets/collectible_card.dart';
import 'widgets/theme_story.dart';

enum BinderFilter {
  all('All'),
  collected('Collected'),
  missing('Missing');

  const BinderFilter(this.label);
  final String label;
}

final binderFilterProvider = NotifierProvider<BinderFilterNotifier, BinderFilter>(BinderFilterNotifier.new);

class BinderFilterNotifier extends Notifier<BinderFilter> {
  @override
  BinderFilter build() => BinderFilter.all;

  void set(BinderFilter f) => state = f;
}

/// Every card in the set, in number order: the ones collected in their showiest finish, the rest
/// as numbered gaps.
class BinderPage extends ConsumerWidget {
  const BinderPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.panda;
    final phone = Breakpoints.isPhone(context);
    final library = ref.watch(cardLibraryProvider).value;
    final cards = library?.cards ?? const <CardDef>[];
    final themes = library?.themes ?? const <StoryTheme>[];
    final state = ref.watch(collectionProvider).value ?? const CollectionState();
    final filter = ref.watch(binderFilterProvider);
    final owned = cards.where((c) => state.copiesOf(c.id) > 0).length;
    final finishes = state.copies.values.where((n) => n > 0).length;
    final shown = [
      for (final c in cards)
        if (switch (filter) {
          BinderFilter.all => true,
          BinderFilter.collected => state.copiesOf(c.id) > 0,
          BinderFilter.missing => state.copiesOf(c.id) == 0,
        })
          c,
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 40, phone ? 12 : 24, phone ? 16 : 40, 40),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/notes'),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Notes'),
          ),
        ),
        const SizedBox(height: 4),
        Text('Binder', style: phone ? PandaText.title : PandaText.display),
        const SizedBox(height: 4),
        Text(
          '$owned of ${cards.length} cards · $finishes finish${finishes == 1 ? '' : 'es'} collected',
          key: const ValueKey('binder-progress'),
          style: PandaText.body.copyWith(color: p.muted),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(PandaSizes.pill),
          child: LinearProgressIndicator(
            value: cards.isEmpty ? 0 : owned / cards.length,
            minHeight: 8,
            color: p.bamboo,
            backgroundColor: p.line,
          ),
        ),
        if (themes.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Themes', style: PandaText.heading),
          Text('Collect every card in a theme to unlock its story.', style: PandaText.caption.copyWith(color: p.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final t in themes) _ThemeTile(theme: t, cards: library!.cardsIn(t.id), state: state)],
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in BinderFilter.values)
              ChoiceChip(
                label: Text(f.label),
                selected: filter == f,
                onSelected: (_) => ref.read(binderFilterProvider.notifier).set(f),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              filter == BinderFilter.missing ? 'You have every card. Well done!' : 'No cards here yet. Open a pack!',
              textAlign: TextAlign.center,
              style: PandaText.body.copyWith(color: p.muted),
            ),
          )
        else
          GridView(
            key: const ValueKey('binder-grid'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 18,
              crossAxisSpacing: 14,
              childAspectRatio: 5 / 7.9,
            ),
            children: [for (final c in shown) _Slot(card: c, state: state)],
          ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.card, required this.state});

  final CardDef card;
  final CollectionState state;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    final count = state.copiesOf(card.id);
    final finishes = state.finishesOf(card.id);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        if (count == 0) {
          return Semantics(
            label: '${card.numberLabel}, not collected yet',
            excludeSemantics: true,
            child: Column(
              children: [
                Container(
                  key: ValueKey('missing-${card.id}'),
                  width: w,
                  height: w * CollectibleCard.aspect,
                  decoration: BoxDecoration(
                    color: p.line.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(w * 0.07),
                    border: Border.all(color: p.line, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.help_outline_rounded, color: p.muted, size: w * 0.22),
                      const SizedBox(height: 6),
                      Text(card.numberLabel, style: PandaText.captionStrong.copyWith(color: p.muted)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Semantics(
          button: true,
          label: '${card.name}, ${card.rarity.label}, $count cop${count == 1 ? 'y' : 'ies'}. Open it.',
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('slot-${card.id}'),
            onTap: () => showCardDetail(context, card),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CollectibleCard(card: card, finish: finishes.first, width: w),
                      if (count > 1)
                        Positioned(
                          top: -6,
                          right: -6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: p.ink,
                              borderRadius: BorderRadius.circular(PandaSizes.pill),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              child: Text('×$count', style: PandaText.captionStrong.copyWith(color: p.surface)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // One dot per finish owned.
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final f in finishes)
                        Tooltip(
                          message: f.label,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _dot(f),
                              border: Border.all(color: p.muted.withValues(alpha: 0.5), width: 0.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Color _dot(Finish f) => switch (f.kind) {
    FinishKind.none => PandaColors.stone,
    FinishKind.tint => PandaColors.sky,
    FinishKind.layout => PandaColors.honey,
    FinishKind.shiny => PandaColors.lavender,
  };
}

/// A theme in the binder: its name, how many of its cards are collected, and whether its story is
/// unlocked. Tapping it opens the theme.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.theme, required this.cards, required this.state});

  final StoryTheme theme;
  final List<CardDef> cards;
  final CollectionState state;

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    final owned = state.ownedAmong(cards);
    final done = state.ownsAll(cards);
    return SizedBox(
      width: 300,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PandaSizes.tileRadius),
          side: BorderSide(color: done ? PandaColors.honey : p.line, width: done ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('theme-${theme.id}'),
          onTap: () => showThemeStory(context, theme, cards, state),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(theme.name, style: PandaText.bodyStrong)),
                    Icon(
                      done ? Icons.auto_stories_rounded : Icons.lock_rounded,
                      size: 18,
                      color: done ? p.bambooDark : p.muted,
                    ),
                  ],
                ),
                Text(
                  done ? 'Story unlocked. Tap to read it.' : (theme.blurb ?? '$owned of ${cards.length} cards'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PandaText.caption.copyWith(color: p.muted),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(PandaSizes.pill),
                        child: LinearProgressIndicator(
                          value: cards.isEmpty ? 0 : owned / cards.length,
                          minHeight: 6,
                          color: done ? PandaColors.honey : p.bamboo,
                          backgroundColor: p.line,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$owned / ${cards.length}', style: PandaText.captionStrong.copyWith(color: p.muted)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
