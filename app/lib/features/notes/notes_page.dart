import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../core/widgets/panda_mascot.dart';

/// Placeholder until the notes milestone.
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PandaMascot(size: 120, sleeping: true),
          const SizedBox(height: 16),
          const Text('Notes are coming soon', style: PandaText.title, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'The panda is still sharpening its pencils.',
            style: PandaText.body.copyWith(color: PandaColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
