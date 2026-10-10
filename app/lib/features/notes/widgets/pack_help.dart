import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../../data/cards/collection_store.dart';
import '../../../domain/models/cards.dart';
import '../../../domain/services/pack_roller.dart';
import 'collectible_card.dart';

/// What each finish looks like, for the help sheet.
const finishDescriptions = {
  Finish.none: 'The card as it was printed.',
  Finish.ink: 'Black-and-white, like a Chinese brush painting.',
  Finish.bamboo: 'A green-tinted photo in a bamboo-striped frame.',
  Finish.moonlight: 'A blue night tint with the moon out.',
  Finish.vintage: 'Sepia with darkened corners, like an old photograph.',
  Finish.fullArt: 'The photo fills the whole card.',
  Finish.signed: 'The photographer’s signature across the photo.',
  Finish.reverseHolo: 'A rainbow frame that shifts as the card tilts.',
  Finish.holo: 'A rainbow sheen over the photo.',
  Finish.gold: 'A gold frame and a golden photo.',
  Finish.cosmos: 'A starry night frame, with sparkles.',
  Finish.ghost: 'Pale, silvery and a little see-through.',
  Finish.rainbow: 'Soft rainbow colours over the whole card.',
  Finish.misprint: 'Shifted colours and a crooked banner, like a printing mistake.',
};

/// Opens a short guide to rarities and finishes. [sample] is drawn in each finish.
Future<void> showPackHelp(BuildContext context, {CardDef? sample}) => showDialog<void>(
  context: context,
  builder: (_) => PackHelp(sample: sample),
);

class PackHelp extends StatelessWidget {
  const PackHelp({super.key, this.sample});

  final CardDef? sample;

  static String _pct(double v) => v == v.roundToDouble() ? '${v.round()}%' : '$v%';

  @override
  Widget build(BuildContext context) {
    final p = context.panda;
    const pack = PackType.bamboo;
    final muted = PandaText.caption.copyWith(color: p.muted);
    // Commonest first, as they come out of a pack.
    final finishes = [
      Finish.none,
      ...Finish.values.where((f) => f != Finish.none).toList()..sort((a, b) => b.weight.compareTo(a.weight)),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
              child: Row(
                children: [
                  const Expanded(child: Text('About packs', style: PandaText.title)),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('pack-help'),
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'A new pack arrives every ${PackTimer.every.inHours} hours, and up to ${PackTimer.max} can '
                      'wait for you. Every pack has ${PackRoller.cardsPerPack} cards. Each card is rolled for a rarity, then '
                      'separately for a finish, so the same photo can be collected many ways.',
                      style: PandaText.body.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: 20),
                    const Text('Rarities', style: PandaText.heading),
                    const SizedBox(height: 8),
                    Table(
                      key: const ValueKey('rarity-table'),
                      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2)},
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          children: [
                            Text('Rarity', style: muted),
                            Text('Cards 1–5', style: muted, textAlign: TextAlign.end),
                            Text('Cards 6–7', style: muted, textAlign: TextAlign.end),
                          ],
                        ),
                        for (final r in Rarity.values)
                          TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Transform.rotate(
                                      angle: 0.785,
                                      child: Container(
                                        width: 11,
                                        height: 11,
                                        decoration: BoxDecoration(
                                          color: r.gem,
                                          border: Border.all(color: const Color(0xFF6B5F49)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(r.label, style: PandaText.bodyStrong),
                                  ],
                                ),
                              ),
                              Text(_pct(pack.early[r]!), textAlign: TextAlign.end, style: PandaText.body),
                              Text(_pct(pack.late[r]!), textAlign: TextAlign.end, style: PandaText.body),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The gem under a card’s name shows its rarity, and rarer cards glow when they come out. '
                      'If ${PackRoller.pityAfter - 1} packs in a row have no Legendary, the next one has one.',
                      style: muted,
                    ),
                    const SizedBox(height: 20),
                    const Text('Finishes', style: PandaText.heading),
                    const SizedBox(height: 4),
                    Text(
                      'About ${PackRoller.finishChance(pack.finishBoost).round()}% of cards get a finish, and '
                      'the last card in a pack is twice as likely to. Chances are per card.',
                      style: muted,
                    ),
                    const SizedBox(height: 8),
                    for (final f in finishes)
                      Padding(
                        key: ValueKey('help-${f.key}'),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            if (sample != null) ...[
                              CollectibleCard(card: sample!, finish: f, width: 44),
                              const SizedBox(width: 14),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f.label, style: PandaText.bodyStrong),
                                  Text(finishDescriptions[f]!, style: muted),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(_pct(f.weight), style: PandaText.captionStrong.copyWith(color: p.ink)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
