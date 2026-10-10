import 'package:flutter/material.dart';

import '../../../core/theme/panda_theme.dart';
import '../../../data/cards/collection_store.dart';
import '../../../domain/models/cards.dart';
import 'blurred_overlay.dart';
import 'collectible_card.dart';

/// Parchment colours, the same in light and dark mode like the cards.
const parchmentInk = Color(0xFF3B2F1E);
const parchmentFaded = Color(0xFF6E5B3E);
const parchment = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF3E9CF), Color(0xFFE4D3A8)],
  ),
  borderRadius: BorderRadius.all(Radius.circular(PandaSizes.tileRadius)),
  border: Border.fromBorderSide(BorderSide(color: Color(0x66806040))),
  boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))],
);

/// Opens a theme over the blurred app: its cards (the missing ones as gaps) and, once every card
/// is collected, its story.
Future<void> showThemeStory(BuildContext context, StoryTheme theme, List<CardDef> cards, CollectionState state) =>
    showBlurredOverlay<void>(
      context,
      builder: (_) => ThemeStory(theme: theme, cards: cards, state: state),
    );

class ThemeStory extends StatelessWidget {
  const ThemeStory({super.key, required this.theme, required this.cards, required this.state});

  final StoryTheme theme;
  final List<CardDef> cards;
  final CollectionState state;

  @override
  Widget build(BuildContext context) {
    final owned = state.ownedAmong(cards);
    final unlocked = state.ownsAll(cards);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 72, 16, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: DecoratedBox(
            key: const ValueKey('theme-story'),
            decoration: parchment,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'THEME · $owned OF ${cards.length} CARDS',
                    style: PandaText.captionStrong.copyWith(color: parchmentFaded, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 2),
                  Text(theme.name, style: PandaText.title.copyWith(color: parchmentInk)),
                  const SizedBox(height: 14),
                  ThemeCardsRow(cards: cards, state: state, width: 56),
                  const SizedBox(height: 18),
                  if (unlocked)
                    Text(
                      theme.story,
                      key: const ValueKey('story-text'),
                      style: PandaText.body.copyWith(color: parchmentInk, height: 1.6),
                    )
                  else
                    Row(
                      children: [
                        const Icon(Icons.lock_rounded, color: parchmentFaded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Collect all ${cards.length} cards to unlock the story. '
                            '${cards.length - owned} to go.',
                            key: const ValueKey('story-locked'),
                            style: PandaText.body.copyWith(color: parchmentInk),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A theme's cards in a row: the ones owned as small cards, the rest as numbered gaps.
class ThemeCardsRow extends StatelessWidget {
  const ThemeCardsRow({super.key, required this.cards, required this.state, required this.width});

  final List<CardDef> cards;
  final CollectionState state;
  final double width;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final c in cards)
        if (state.copiesOf(c.id) > 0)
          CollectibleCard(card: c, finish: state.finishesOf(c.id).first, width: width)
        else
          Container(
            width: width,
            height: width * CollectibleCard.aspect,
            decoration: BoxDecoration(
              color: const Color(0x22000000),
              borderRadius: BorderRadius.circular(width * 0.07),
              border: Border.all(color: const Color(0x33000000)),
            ),
            alignment: Alignment.center,
            child: Text(
              c.numberLabel,
              style: TextStyle(fontSize: width * 0.2, fontWeight: FontWeight.w800, color: const Color(0x99000000)),
            ),
          ),
    ],
  );
}
