import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../../domain/models/cards.dart';
import 'blurred_overlay.dart';
import 'collectible_card.dart';

/// Opens one card large over the blurred app, with its story beside it (below it on a phone).
/// [finishes] are the versions owned, showiest first; with more than one, chips switch between
/// them. [copies] counts copies of each finish, for the "×2" labels.
Future<void> showCardDetail(
  BuildContext context,
  CardDef card, {
  required List<Finish> finishes,
  Map<Finish, int> copies = const {},
}) => showBlurredOverlay<void>(
  context,
  builder: (_) => CardDetail(card: card, finishes: finishes, copies: copies),
);

class CardDetail extends StatefulWidget {
  const CardDetail({super.key, required this.card, required this.finishes, this.copies = const {}});

  final CardDef card;
  final List<Finish> finishes;
  final Map<Finish, int> copies;

  @override
  State<CardDetail> createState() => _CardDetailState();
}

class _CardDetailState extends State<CardDetail> {
  late Finish _finish = widget.finishes.isEmpty ? Finish.none : widget.finishes.first;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760;
    final cardW = wide
        ? [360.0, (size.height - 120) / CollectibleCard.aspect].reduce(math.min)
        : [320.0, size.width - 64].reduce(math.min);
    final card = CollectibleCard(
      key: const ValueKey('detail-card'),
      card: widget.card,
      finish: _finish,
      width: cardW,
      interactive: true,
    );
    final lore = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: wide ? 340 : cardW + 24),
      child: _Lore(
        card: widget.card,
        finish: _finish,
        finishes: widget.finishes,
        copies: widget.copies,
        onFinish: (f) => setState(() => _finish = f),
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

/// The parchment panel: number, rarity, flavour text, artist, and the finishes owned.
class _Lore extends StatelessWidget {
  const _Lore({
    required this.card,
    required this.finish,
    required this.finishes,
    required this.copies,
    required this.onFinish,
  });

  final CardDef card;
  final Finish finish;
  final List<Finish> finishes;
  final Map<Finish, int> copies;
  final ValueChanged<Finish> onFinish;

  // Parchment looks the same in light and dark mode, like the cards.
  static const _ink = Color(0xFF3B2F1E);
  static const _faded = Color(0xFF6E5B3E);

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('card-lore'),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF3E9CF), Color(0xFFE4D3A8)],
      ),
      borderRadius: BorderRadius.circular(PandaSizes.tileRadius),
      border: Border.all(color: const Color(0x66806040)),
      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${card.numberLabel} · ${card.set.toUpperCase()}',
            style: PandaText.captionStrong.copyWith(color: _faded, letterSpacing: 0.8),
          ),
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
          if (finishes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              finishes.length == 1 ? 'FINISH' : 'FINISHES OWNED',
              style: PandaText.captionStrong.copyWith(color: _faded, letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in finishes)
                  ChoiceChip(
                    key: ValueKey('finish-${f.key}'),
                    label: Text((copies[f] ?? 0) > 1 ? '${f.label} ×${copies[f]}' : f.label),
                    selected: f == finish,
                    onSelected: (_) => onFinish(f),
                    showCheckmark: false,
                    labelStyle: PandaText.captionStrong.copyWith(color: f == finish ? PandaColors.surface : _ink),
                    selectedColor: _ink,
                    backgroundColor: const Color(0xFFFAF3E0),
                    side: const BorderSide(color: Color(0x66806040)),
                    shape: const StadiumBorder(),
                  ),
              ],
            ),
            // BamBoozled's own finishes have nothing to credit.
            if (finish.inspiredBy case final from? when !from.startsWith('BamBoozled')) ...[
              const SizedBox(height: 8),
              Text('${finish.label} is inspired by $from.', style: PandaText.caption.copyWith(color: _faded)),
            ],
          ],
        ],
      ),
    ),
  );
}
