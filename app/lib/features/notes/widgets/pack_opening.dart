import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/panda_theme.dart';
import '../../../domain/models/cards.dart';
import 'blurred_overlay.dart';
import 'card_detail.dart';
import 'collectible_card.dart';

/// Shows a freshly opened pack over the blurred app: the cards in a face-up stack, each tap or
/// swipe sliding the top one away, then an overview of all of them with the new ones marked.
/// With [overview], it goes straight to the overview (for looking at today's cards again).
Future<void> showPackOpening(
  BuildContext context,
  List<Pull> pulls, {
  bool overview = false,
  VoidCallback? onSeeBinder,
}) => showBlurredOverlay<void>(
  context,
  builder: (_) => PackOpening(pulls: pulls, startWithOverview: overview, onSeeBinder: onSeeBinder),
);

class PackOpening extends StatefulWidget {
  const PackOpening({super.key, required this.pulls, this.startWithOverview = false, this.onSeeBinder});

  final List<Pull> pulls;
  final bool startWithOverview;
  final VoidCallback? onSeeBinder;

  @override
  State<PackOpening> createState() => _PackOpeningState();
}

class _PackOpeningState extends State<PackOpening> with SingleTickerProviderStateMixin {
  /// Index of the card on top of the stack; past the end means the overview is showing.
  late int _top = widget.startWithOverview ? widget.pulls.length : 0;

  /// How far the top card has been dragged sideways.
  double _dx = 0;

  late final _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  Tween<double> _flyTween = Tween(begin: 0, end: 0);

  /// Takes the keyboard from the overlay, so arrow keys, Enter and Space move through the stack.
  final _focus = FocusNode(debugLabel: 'pack stack');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _fly.addListener(
      () => setState(() => _dx = _flyTween.evaluate(CurvedAnimation(parent: _fly, curve: Curves.easeIn))),
    );
  }

  @override
  void dispose() {
    _fly.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _done => _top >= widget.pulls.length;

  /// Slides the top card off to one side ([direction] -1 = left, 1 = right), then shows the next.
  Future<void> _next({int direction = 1}) async {
    if (_done || _fly.isAnimating) return;
    final width = MediaQuery.sizeOf(context).width;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _flyTween = Tween(begin: _dx, end: direction * width);
      await _fly.forward(from: 0);
    }
    if (!mounted) return;
    setState(() {
      _top++;
      _dx = 0;
    });
  }

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dx.abs() > 70 || v.abs() > 700) {
      _next(direction: (_dx.abs() > 70 ? _dx : v) < 0 ? -1 : 1);
    } else {
      setState(() => _dx = 0);
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: _done
        ? const {}
        : {
            const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _next(direction: -1),
            const SingleActivator(LogicalKeyboardKey.enter): _next,
            const SingleActivator(LogicalKeyboardKey.space): _next,
          },
    child: Focus(focusNode: _focus, child: _done ? _overview(context) : _stack(context)),
  );

  Widget _stack(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = [340.0, size.width - 48, (size.height - 190) / CollectibleCard.aspect].reduce(math.min);
    final h = w * CollectibleCard.aspect;
    final pull = widget.pulls[_top];
    final left = widget.pulls.length - _top;
    final rare = pull.card.rarity != Rarity.common;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: w + 24,
            height: h + 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The cards still waiting, peeking out underneath.
                for (var i = math.min(left - 1, 3); i >= 1; i--)
                  Transform.translate(
                    offset: Offset(0, i * 6.0),
                    child: Transform.rotate(
                      angle: (i.isEven ? 1 : -1) * i * 0.012,
                      child: CollectibleCard(
                        card: widget.pulls[_top + i].card,
                        finish: widget.pulls[_top + i].finish,
                        width: w,
                      ),
                    ),
                  ),
                GestureDetector(
                  key: const ValueKey('stack-top'),
                  onTap: _next,
                  onHorizontalDragUpdate: (d) => _fly.isAnimating ? null : setState(() => _dx += d.delta.dx),
                  onHorizontalDragEnd: _dragEnd,
                  child: Transform.translate(
                    offset: Offset(_dx, 0),
                    child: Transform.rotate(
                      angle: _dx / size.width * 0.35,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(w * 0.07),
                          boxShadow: [
                            if (rare)
                              BoxShadow(
                                color: pull.card.rarity.gem.withValues(alpha: 0.75),
                                blurRadius: 28,
                                spreadRadius: pull.card.rarity == Rarity.legendary ? 6 : 2,
                              ),
                          ],
                        ),
                        child: CollectibleCard(
                          key: ValueKey('pull-$_top'),
                          card: pull.card,
                          finish: pull.finish,
                          width: w,
                          interactive: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '${_top + 1} / ${widget.pulls.length}',
            key: const ValueKey('stack-count'),
            style: PandaText.heading.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            'Tap or swipe for the next card',
            style: PandaText.caption.copyWith(color: Colors.white.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _overview(BuildContext context) {
    final p = context.panda;
    final size = MediaQuery.sizeOf(context);
    final phone = size.width < 600;
    final cardW = phone ? (size.width - 32 - 24) / 3 : 150.0;
    final newCards = widget.pulls.where((x) => x.newCard).length;
    final newFinishes = widget.pulls.where((x) => x.newFinish).length;
    final summary = [
      if (newCards > 0) '$newCards new card${newCards == 1 ? '' : 's'}',
      if (newFinishes > 0) '$newFinishes new finish${newFinishes == 1 ? '' : 'es'}',
    ];
    return Center(
      child: SingleChildScrollView(
        key: const ValueKey('pack-overview'),
        padding: const EdgeInsets.fromLTRB(16, 72, 16, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Today’s pack', style: PandaText.display.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              Text(
                summary.isEmpty
                    ? 'All copies of cards you have. Tap one for a closer look.'
                    : '${summary.join(' · ')}. Tap one for a closer look.',
                textAlign: TextAlign.center,
                style: PandaText.body.copyWith(color: Colors.white.withValues(alpha: 0.85)),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final (i, pull) in widget.pulls.indexed)
                    _OverviewCard(key: ValueKey('overview-$i'), pull: pull, width: cardW),
                ],
              ),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (widget.onSeeBinder != null)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onSeeBinder!();
                      },
                      icon: const Icon(Icons.collections_bookmark_rounded),
                      label: const Text('See binder'),
                    ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(backgroundColor: p.surface, foregroundColor: p.ink),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({super.key, required this.pull, required this.width});

  final Pull pull;
  final double width;

  @override
  Widget build(BuildContext context) {
    final badge = pull.newCard
        ? ('New', PandaColors.bamboo)
        : pull.newFinish
        ? ('New finish', PandaColors.honey)
        : null;
    return Semantics(
      button: true,
      label: [
        pull.card.name,
        pull.card.rarity.label,
        if (pull.finish != Finish.none) pull.finish.label,
        if (badge != null) badge.$1,
      ].join(', '),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => showCardDetail(context, pull.card, finishes: [pull.finish]),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CollectibleCard(card: pull.card, finish: pull.finish, width: width),
              if (badge != null)
                Positioned(
                  top: -8,
                  right: -6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: badge.$2,
                      borderRadius: BorderRadius.circular(PandaSizes.pill),
                      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      child: Text(badge.$1, style: PandaText.captionStrong.copyWith(color: PandaColors.ink)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
