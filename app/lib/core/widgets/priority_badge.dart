import 'package:flutter/material.dart';

import '../../domain/models/priority.dart';
import '../theme/colors.dart';
import '../theme/panda_theme.dart';
import 'leaf_icon.dart';

/// Pill with 1–4 leaves plus the priority name (never colour alone).
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority, this.showLabel = true});

  final Priority priority;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final urgent = priority == Priority.urgent;
    final fg = urgent ? context.panda.overdue : context.panda.bambooDark;
    return Semantics(
      label: '${priority.label} priority',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: urgent ? context.panda.overdueTint : context.panda.bambooTint,
          borderRadius: BorderRadius.circular(PandaSizes.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < priority.weight; i++)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: LeafIcon(size: 14, color: fg),
              ),
            if (showLabel) ...[
              const SizedBox(width: 2),
              Text(priority.label, style: PandaText.captionStrong.copyWith(color: fg)),
            ],
          ],
        ),
      ),
    );
  }
}
