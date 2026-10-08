import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/dates.dart';
import '../../data/providers.dart';
import '../../data/sync/sync_service.dart';

/// Small cloud icon showing whether tasks are synced. Tapping opens Settings.
/// Hidden when this build has no sync configured.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(supabaseClientProvider) == null) return const SizedBox.shrink();
    final user = ref.watch(currentUserProvider).value;
    final status = ref.watch(syncStatusProvider).value;
    final (icon, color, tip) = switch ((user, status?.phase)) {
      (null, _) => (Icons.cloud_off_rounded, PandaColors.muted, 'Not syncing — sign in to use on all your devices'),
      (_, SyncPhase.syncing) => (Icons.cloud_sync_rounded, PandaColors.bambooDark, 'Syncing…'),
      (_, SyncPhase.error) => (Icons.cloud_off_rounded, PandaColors.overdue, 'Couldn’t sync — will retry'),
      _ => (
        Icons.cloud_done_rounded,
        PandaColors.bambooDark,
        status?.lastSyncedAt == null ? 'Synced' : 'Synced at ${formatTime(status!.lastSyncedAt!)}',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        tooltip: tip,
        onPressed: () => context.go('/settings'),
        style: IconButton.styleFrom(
          backgroundColor: PandaColors.surface,
          side: const BorderSide(color: PandaColors.line, width: 1.5),
          minimumSize: const Size(48, 48),
        ),
        icon: Icon(icon, color: color),
      ),
    );
  }
}
