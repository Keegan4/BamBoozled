import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../../data/cards/collection_store.dart';
import '../../../data/providers.dart';
import '../../../domain/models/cards.dart';
import 'blurred_overlay.dart';
import 'collectible_card.dart';
import 'theme_story.dart';

/// Opens one card large over the blurred app, with its story beside it (below it on a phone). It
/// starts in [finish], or the showiest finish owned. Every finish the card can come in is listed:
/// the owned ones switch the card, the rest are greyed out until collected.
Future<void> showCardDetail(BuildContext context, CardDef card, {Finish? finish}) => showBlurredOverlay<void>(
  context,
  builder: (_) => CardDetail(card: card, finish: finish),
);

class CardDetail extends ConsumerStatefulWidget {
  const CardDetail({super.key, required this.card, this.finish});

  final CardDef card;
  final Finish? finish;

  @override
  ConsumerState<CardDetail> createState() => _CardDetailState();
}

class _CardDetailState extends ConsumerState<CardDetail> {
  Finish? _picked;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectionProvider).value ?? const CollectionState();
    final library = ref.watch(cardLibraryProvider).value;
    final owned = state.finishesOf(widget.card.id);
    final finish = _picked ?? widget.finish ?? (owned.isEmpty ? Finish.none : owned.first);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760;
    final cardW = wide
        ? [360.0, (size.height - 120) / CollectibleCard.aspect].reduce(math.min)
        : [320.0, size.width - 64].reduce(math.min);
    final card = CollectibleCard(
      key: const ValueKey('detail-card'),
      card: widget.card,
      finish: finish,
      width: cardW,
      interactive: true,
    );
    final lore = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: wide ? 340 : cardW + 24),
      child: _Lore(
        card: widget.card,
        finish: finish,
        state: state,
        themes: [
          for (final id in widget.card.themes)
            if (library?.themeById(id) case final t?) (t, library!.cardsIn(id)),
        ],
        onFinish: (f) => setState(() => _picked = f),
      ),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 72, 16, 32),
        child: wide
            ? Row(mainAxisSize: MainAxisSize.min, children: [card, const SizedBox(width: 32), lore])
            : Column(mainAxisSize: MainAxisSize.min, children: [card, const SizedBox(height: 20), lore]),
      ),
    );
  }
}

/// The parchment panel: number, rarity, flavour text, artist, themes, and every finish.
class _Lore extends StatelessWidget {
  const _Lore({
    required this.card,
    required this.finish,
    required this.state,
    required this.themes,
    required this.onFinish,
  });

  final CardDef card;
  final Finish finish;
  final CollectionState state;
  final List<(StoryTheme, List<CardDef>)> themes;
  final ValueChanged<Finish> onFinish;

  static const _ink = parchmentInk;
  static const _faded = parchmentFaded;

  @override
  Widget build(BuildContext context) {
    final possible = card.possibleFinishes;
    final ownedCount = possible.where((f) => state.copiesIn(card.id, f) > 0).length;
    final label = PandaText.captionStrong.copyWith(color: _faded, letterSpacing: 0.8);
    return DecoratedBox(
      key: const ValueKey('card-lore'),
      decoration: parchment,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${card.numberLabel} · ${card.set.toUpperCase()}', style: label),
            const SizedBox(height: 2),
            Text(card.name, style: PandaText.title.copyWith(color: _ink)),
            const SizedBox(height: 6),
            Row(
              children: [
                Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: card.rarity.gem,
                      border: Border.all(color: const Color(0xFF6B5F49)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(card.rarity.label, style: PandaText.captionStrong.copyWith(color: _ink)),
              ],
            ),
            if (card.flavour != null) ...[
              const SizedBox(height: 14),
              Text(
                card.flavour!,
                style: PandaText.body.copyWith(color: _ink, fontStyle: FontStyle.italic),
              ),
            ],
            if (card.artist != null) ...[
              const SizedBox(height: 10),
              Text('Photo: ${card.artist}', style: PandaText.caption.copyWith(color: _faded)),
            ],
            for (final (theme, cards) in themes) ...[
              const SizedBox(height: 16),
              Text('THEME', style: label),
              const SizedBox(height: 6),
              InkWell(
                key: ValueKey('detail-theme-${theme.id}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => showThemeStory(context, theme, cards, state),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        state.ownsAll(cards) ? Icons.auto_stories_rounded : Icons.lock_rounded,
                        size: 18,
                        color: _faded,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${theme.name} · ${state.ownedAmong(cards)} of ${cards.length}',
                          style: PandaText.bodyStrong.copyWith(color: _ink),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: _faded),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('FINISHES · $ownedCount OF ${possible.length} COLLECTED', style: label),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final f in possible) _chip(f)]),
            // BamBoozled's own finishes have nothing to credit.
            if (finish.inspiredBy case final from? when !from.startsWith('BamBoozled')) ...[
              const SizedBox(height: 8),
              Text('${finish.label} is inspired by $from.', style: PandaText.caption.copyWith(color: _faded)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(Finish f) {
    final copies = state.copiesIn(card.id, f);
    if (copies == 0) {
      // Not collected yet: greyed out, like a missing card in the binder.
      return Semantics(
        label: '${f.label}, not collected yet',
        excludeSemantics: true,
        child: Container(
          key: ValueKey('finish-${f.key}'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0x14000000),
            borderRadius: BorderRadius.circular(PandaSizes.pill),
            border: Border.all(color: const Color(0x26000000)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 14, color: Color(0x73000000)),
              const SizedBox(width: 4),
              Text(f.label, style: PandaText.captionStrong.copyWith(color: const Color(0x73000000))),
            ],
          ),
        ),
      );
    }
    return ChoiceChip(
      key: ValueKey('finish-${f.key}'),
      label: Text(copies > 1 ? '${f.label} ×$copies' : f.label),
      selected: f == finish,
      onSelected: (_) => onFinish(f),
      showCheckmark: false,
      labelStyle: PandaText.captionStrong.copyWith(color: f == finish ? PandaColors.surface : _ink),
      selectedColor: _ink,
      backgroundColor: const Color(0xFFFAF3E0),
      side: const BorderSide(color: Color(0x66806040)),
      shape: const StadiumBorder(),
    );
  }
}
